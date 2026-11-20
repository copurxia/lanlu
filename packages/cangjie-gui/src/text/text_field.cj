package cui.text

import lbase.{Rect, Size}
import cui.base.{FontSizes, IconName, Key, MouseButton, UiEvent, drawIcon, textSurroundingSink}
import cui.input.{Clipboard, Keyboard}
import cui.core.{Bindable, CUI_CONTROL_H, CursorShape, State, UiContext, Widget, claimHoverIfInside, emit, localState,
    registerFocusable, resolveControlKey}

// SDL reports letter keys as their uppercase ASCII code, so the editing shortcuts read as
// the familiar Ctrl+letter table.
private let LETTER_A: UInt8 = 65
// 前缀图标占用的文本区左移量（图标 14 + 两侧间距）。
private let TEXT_FIELD_LEAD: Float32 = 26.0
private let LETTER_C: UInt8 = 67
private let LETTER_V: UInt8 = 86
private let LETTER_X: UInt8 = 88
private let LETTER_Y: UInt8 = 89
private let LETTER_Z: UInt8 = 90

public class TextField <: Widget {
    private let id: String
    private let text: Bindable<String>
    private var cursorStateValue: State<Int64>
    private var anchorStateValue: State<Int64>
    private let history: UndoHistory
    // Horizontal follow window: how many pixels the text is slid left so the caret stays
    // inside the field's inner width. Retained across rebuilds; recomputed each draw.
    private let xOffset: State<Float32>
    private var autofocusRequested = false
    private let autofocusDone: State<Bool>
    private let isEditable: Bool
    // 掩码模式（如密码框）：绘制时每个字素显示为掩码符，真实值不变。
    private let isMasked: Bool
    // 是否绘制自带底/边 chrome；外层自绘外壳（如顶栏搜索框）时置 false 避免双层框。
    private let hasChrome: Bool
    // 前缀图标（如登录框的用户/锁）：非 None 时文本区整体右移，图标画在左内边。
    private let leading: ?IconName
    // 后缀图标（如密码框的显示/隐藏眼睛）：非 None 时文本区右端让出同宽区域；
    // 点击该区域触发 onTrailingClick（不进焦、不移动光标）。
    private let trailing: ?IconName
    private let onTrailing: ?() -> Unit
    private let onSubmit: ?() -> Unit
    // 输入法组合串（preedit）：只影响显示，commit 时才写进真实值。
    private let preedit: State<String> = State<String>("")
    private let preeditCursor: State<Int64> = State<Int64>(0)
    private var frame = Rect.zero()

    public init(
        text: Bindable<String>,
        key!: ?String = None,
        cursor!: ?State<Int64> = None,
        anchor!: ?State<Int64> = None,
        editable!: Bool = true,
        masked!: Bool = false,
        chrome!: Bool = true,
        leadingIcon!: ?IconName = None,
        trailingIcon!: ?IconName = None,
        onTrailingClick!: ?() -> Unit = None,
        onSubmit!: ?() -> Unit = None
    ) {
        let ident = resolveControlKey(key, "TextField")
        this.id = ident
        this.text = text
        this.isEditable = editable
        this.isMasked = masked
        this.hasChrome = chrome
        this.leading = leadingIcon
        this.trailing = trailingIcon
        this.onTrailing = onTrailingClick
        this.onSubmit = onSubmit
        this.cursorStateValue = match (cursor) {
            case Some(value) => value
            case None => localState<Int64>("TextField:${ident}:cursor") {text.value.size}
        }
        // The anchor starts collapsed on the caret; defaulting it to the text end instead
        // would present a phantom selection whenever the caret begins elsewhere. A composing
        // widget (e.g. ComboBox) may own both caret and anchor so it can reset the selection.
        let caretStart = cursorStateValue.value
        this.anchorStateValue = match (anchor) {
            case Some(value) => value
            case None => localState<Int64>("TextField:${ident}:anchor") {caretStart}
        }
        this.history = localState<UndoHistory>("TextField:${ident}:history") {UndoHistory()}.value
        this.xOffset = localState<Float32>("TextField:${ident}:xoff") {0.0}
        this.autofocusDone = localState<Bool>("TextField:${ident}:autofocused") {false}
        // A read-only field is not an editing stop, so it stays out of Tab traversal (mirrors TextArea).
        if (editable) {
            registerFocusable(ident)
        }
        emit(this)
    }

    /** Claims keyboard focus the first time the field appears (e.g. a search box or dialog). */
    public func autofocus(): TextField {
        autofocusRequested = true
        this
    }

    /** Reverts the last edit group; also bound to Ctrl+Z. */
    public func undo(): Unit {
        match (history.undo(snapshot())) {
            case Some(state) => applySnapshot(state)
            case None => ()
        }
    }

    /** Reapplies the last undone edit; also bound to Ctrl+Y / Ctrl+Shift+Z. */
    public func redo(): Unit {
        match (history.redo(snapshot())) {
            case Some(state) => applySnapshot(state)
            case None => ()
        }
    }

    public func measure(_: UiContext, available: Size): Size {
        Size(available.w, CUI_CONTROL_H)
    }

    public func layout(_: UiContext, rect: Rect): Unit {
        frame = rect
    }

    public func draw(ctx: UiContext): Unit {
        let edit = editState()
        edit.normalizeCursor()
        if (hasChrome) {
            drawTextBoxChrome(ctx, frame, id)
        }
        match (leading) {
            case Some(icon) =>
                drawIcon(ctx.renderer, icon, Rect(frame.x + 8.0, frame.centerY() - 7.0, 14.0, 14.0),
                    ctx.theme.mutedText)
            case None => ()
        }
        match (trailing) {
            case Some(icon) =>
                drawIcon(ctx.renderer, icon, Rect(frame.right() - 22.0, frame.centerY() - 7.0, 14.0, 14.0),
                    ctx.theme.mutedText)
            case None => ()
        }
        // 显示层文本：掩码模式下每个字素替换为掩码符，选区/光标偏移同步换算到显示串，
        // 因此高亮、光标与跟随滚动都按掩码后的宽度对齐，真实值不参与绘制。
        let view = displayView()
        let shown = view.display
        // Values longer than the field must not paint past its surface; selection, text and
        // caret are clipped together, and all three share the same follow shift.
        // 文本区（有前缀图标时右移）：文本/选区/光标/命中测试统一用 textFrame，
        // 各绘制助手都以 frame.x + TEXT_FIELD_PAD_X 为原点，传 textFrame 即可整体平移。
        let tf = textFrame()
        let shift = followCursorShift(ctx)
        ctx.renderer.pushClip(tf.inset(2.0))
        if (ctx.hasFocus(id)) {
            let caret = toDisplayOffset(cursorStateValue.value)
            drawTextFieldSelection(ctx, tf, shown,
                shiftForPreedit(toDisplayOffset(edit.selectionStart()), caret, view.length),
                shiftForPreedit(toDisplayOffset(edit.selectionEnd()), caret, view.length), xShift: shift)
        }
        drawTextFieldText(ctx, tf, shown, shift)
        if (view.length > 0) {
            // 组合态：给组合串画下划线（输入法组合中的标准视觉）
            let base = toDisplayOffset(cursorStateValue.value)
            drawPreeditUnderline(ctx, tf, shown, base, base + view.length, xShift: shift)
        }
        drawTextFieldCursor(ctx, tf, id, shown, view.cursor, xShift: shift)
        ctx.renderer.popClip()
    }

    // 文本区矩形：无前缀图标时即 frame 本身；有后缀图标时右端让出同宽区域。
    private func textFrame(): Rect {
        let left: Float32 = match (leading) {
            case Some(_) => TEXT_FIELD_LEAD
            case None => 0.0
        }
        let right: Float32 = match (trailing) {
            case Some(_) => TEXT_FIELD_LEAD
            case None => 0.0
        }
        Rect(frame.x + left, frame.y, frame.w - left - right, frame.h)
    }

    // 显示层文本：掩码模式把真实值的每个字素替换为掩码符；编辑逻辑仍操作真实值。
    private func shownText(): String {
        if (isMasked) {
            maskedDisplayText(text.value)
        } else {
            text.value
        }
    }

    /// 显示层最终字符串 = 上屏文本 + 插入在光标处的组合串。
    private func displayView(): PreeditView {
        preeditView(shownText(), toDisplayOffset(cursorStateValue.value), composingText(), preeditCursor.value)
    }

    // 组合串只在聚焦的可编辑、非掩码控件上显示（密码框不显示组合内容）。
    private func composingText(): String {
        if (isMasked || !isEditable) {
            return ""
        }
        preedit.value
    }

    // 真实值字节偏移 → 显示串字节偏移（非掩码模式为恒等映射）。
    private func toDisplayOffset(offset: Int64): Int64 {
        if (isMasked) {
            maskedDisplayOffset(text.value, offset)
        } else {
            offset
        }
    }

    // 显示串字节偏移 → 真实值字节偏移（命中测试换算回编辑层）。
    private func toSourceOffset(displayOffset: Int64): Int64 {
        if (isMasked) {
            maskedSourceOffset(text.value, displayOffset)
        } else {
            displayOffset
        }
    }

    /*
     * Horizontal caret follow. Values wider than the field slide left so the caret stays
     * visible: the window moves only when the caret leaves it (the usual desktop feel) and
     * is clamped so the text's tail never detaches from the right edge. Runs in draw, so
     * every way the caret moves — keys, clicks, undo, an external state write — is followed.
     */
    private func followCursorShift(ctx: UiContext): Float32 {
        let innerW = max(1.0, textFrame().w - 16.0)
        // 掩码模式按显示串测宽，光标跟随窗口同样基于掩码后的宽度滑动。
        let view = displayView()
        let shown = view.display
        let position = normalizedTextCursor(shown, view.cursor)
        let caretX = ctx.renderer.textWidth(shown[0..position], pointSize: FontSizes.BODY)
        let textW = ctx.renderer.textWidth(shown, pointSize: FontSizes.BODY)
        var shift = min(xOffset.value, max(0.0, textW - innerW))
        if (caretX < shift) {
            shift = caretX
        } else if (caretX > shift + innerW) {
            shift = caretX - innerW
        }
        if (shift != xOffset.value) {
            xOffset.value = shift
        }
        shift
    }

    public func handle(ctx: UiContext, event: UiEvent): Bool {
        // A read-only field is not an editing target, so it does not request the text cursor.
        if (isEditable) {
            claimHoverIfInside(ctx, event, frame, id, CursorShape.Text)
        }
        let edit = editState()
        match (event) {
            case UiEvent.MouseDown(MouseButton.Left, x, y) => return pressAt(ctx, edit, x, y)
            case UiEvent.MouseMove(x, _) =>
                if (ctx.isDragging(id) && ctx.leftMouseDown) {
                    edit.extendTo(hitTestOffset(ctx, x))
                    return true
                }
            case UiEvent.TextInput(value) =>
                if (!ctx.hasFocus(id) || !isEditable) {
                    return false
                }
                preedit.value = ""
                preeditCursor.value = 0
                return recordedEdit(ctx, {=> edit.insert(value)})
            case UiEvent.TextEditing(value, caretBytes) =>
                // 组合态不进撤销栈、不改值：只记录显示（输入法的私有状态）。
                if (!ctx.hasFocus(id) || !isEditable) {
                    return false
                }
                preedit.value = value
                preeditCursor.value = caretBytes
                ctx.requestFrame()
                return true
            case UiEvent.DeleteSurrounding(before, after) =>
                if (!ctx.hasFocus(id) || !isEditable) {
                    return false
                }
                preedit.value = ""
                preeditCursor.value = 0
                return recordedEdit(ctx, {=> edit.deleteSurrounding(before, after)})
            case UiEvent.KeyDown(Key.Backspace, _) => return recordedEdit(ctx, {=> edit.backspace()})
            case UiEvent.KeyDown(Key.Delete, _) => return recordedEdit(ctx, {=> edit.deleteForward()})
            case UiEvent.KeyDown(Key.Left, _) => return navigate(ctx, {=> edit.moveLeft()}, {=> edit.extendLeft()})
            case UiEvent.KeyDown(Key.Right, _) => return navigate(ctx, {=> edit.moveRight()}, {=> edit.extendRight()})
            case UiEvent.KeyDown(Key.Home, _) => return navigate(ctx, {=> edit.moveToStart()}, {=> edit.extendToStart()})
            case UiEvent.KeyDown(Key.End, _) => return navigate(ctx, {=> edit.moveToEnd()}, {=> edit.extendToEnd()})
            case UiEvent.KeyDown(Key.Enter, _) =>
                if (ctx.hasFocus(id) && isEditable) {
                    match (onSubmit) {
                        case Some(submit) =>
                            submit()
                            return true
                        case None => ()
                    }
                }
            case UiEvent.KeyDown(Key.Letter(code), _) => return shortcut(ctx, edit, code)
            case UiEvent.Frame(_) =>
                // 聚焦时把光标周围文本交给输入法（联想/删除上下文）；无变化时会话层去抖。
                if (ctx.hasFocus(id)) {
                    reportSurrounding()
                } else if (!preedit.value.isEmpty()) {
                    // 失焦：组合态作废（输入法可能在失焦时不发 finish_preview）
                    preedit.value = ""
                    preeditCursor.value = 0
                }
                // One-time initial focus, applied after the frame's pointer events so a stray
                // startup click cannot cancel it; later frames leave focus to the user.
                if (autofocusRequested && !autofocusDone.value) {
                    ctx.focus(id, viaKeyboard: true) // autofocus expects typing, so show the ring
                    autofocusDone.value = true
                }
            case _ => ()
        }
        false
    }

    // 光标周围文本（上限 512 字节，前端 256/后端 256）：输入法做联想与"删除上下文"用。
    private func reportSurrounding(): Unit {
        match (textSurroundingSink) {
            case Some(sink) =>
                let value = text.value
                let caret = max(0, min(cursorStateValue.value, value.size))
                let anchor = max(0, min(anchorStateValue.value, value.size))
                if (value.size <= 512) {
                    sink(value, caret, anchor)
                } else {
                    let from = max(0, caret - 256)
                    let to = min(value.size, from + 512)
                    sink(value[from..to], caret - from, anchor - from)
                }
            case None => ()
        }
    }

    public func focusableId(): ?String {
        Some(id)
    }

    // 点击/拖选的命中测试：在显示串上定位（掩码模式按掩码符宽度），再换算回真实值字节偏移。
    private func hitTestOffset(ctx: UiContext, x: Float32): Int64 {
        let displayOffset = textFieldCursorForPoint(ctx, textFrame(), shownText(), x, xShift: xOffset.value)
        toSourceOffset(displayOffset)
    }

    private func editState(): TextEditState {
        TextEditState(text, cursor: Some(cursorStateValue), anchor: Some(anchorStateValue))
    }

    private func pressAt(ctx: UiContext, edit: TextEditState, x: Float32, y: Float32): Bool {
        if (frame.contains(x, y)) {
            // 后缀图标区域：触发回调（如密码显示/隐藏切换），不进焦、不移动光标。
            if (trailing.isSome() && x >= frame.right() - TEXT_FIELD_LEAD) {
                match (onTrailing) {
                    case Some(cb) => cb()
                    case None => ()
                }
                return true
            }
            // 指针焦点同样显示描边：输入框是编辑目标，与 Tab/autofocus 行为一致
            // （此前只有 viaKeyboard 才画环，真机表现为"Tab 有描边、鼠标没有"）。
            ctx.focus(id, viaKeyboard: true)
            let offset = hitTestOffset(ctx, x)
            if (ctx.clickCount == 2) {
                edit.selectWordAt(offset)
            } else if (ctx.clickCount >= 3) {
                edit.selectLineAt(offset)
            } else {
                edit.moveTo(offset)
                ctx.beginDrag(id) // a press-drag extends the selection (see MouseMove)
            }
            history.breakGroup() // edits before and after a caret jump undo separately
            return true
        }
        false
    }

    // Runs a mutating action while focused and records it for undo. The before/after text
    // comparison means a no-op edit (e.g. Backspace at position 0) adds no undo step.
    private func recordedEdit(ctx: UiContext, action: () -> Unit): Bool {
        if (!ctx.hasFocus(id) || !isEditable) {
            return false
        }
        let before = snapshot()
        action()
        if (text.value != before.text) {
            history.commit(before, ctx.frame.elapsedMs)
        }
        true
    }

    private func snapshot(): TextSnapshot {
        TextSnapshot(text.value, cursorStateValue.value, anchorStateValue.value)
    }

    private func applySnapshot(state: TextSnapshot): Unit {
        text.value = state.text
        cursorStateValue.value = state.cursor
        anchorStateValue.value = state.anchor
    }

    // Held Shift extends the selection; a plain arrow collapses it.
    private func navigate(ctx: UiContext, moveCaret: () -> Unit, growSelection: () -> Unit): Bool {
        if (!ctx.hasFocus(id)) {
            return false
        }
        if (Keyboard.modifiers().shift) {
            growSelection()
        } else {
            moveCaret()
        }
        history.breakGroup() // edits before and after a caret jump undo separately
        true
    }

    private func shortcut(ctx: UiContext, edit: TextEditState, code: UInt8): Bool {
        if (!ctx.hasFocus(id) || !Keyboard.modifiers().command) {
            return false
        }
        if (code == LETTER_A) {
            edit.selectAll()
            return true
        } else if (code == LETTER_C) {
            copySelection(edit)
            return true
        } else if (code == LETTER_X) {
            return recordedEdit(ctx, {=> if (copySelection(edit)) {
                let _ = edit.deleteSelection()
            }})
        } else if (code == LETTER_V) {
            return recordedEdit(ctx, {=> pasteClipboard(edit)})
        } else if (code == LETTER_Z) {
            if (Keyboard.modifiers().shift) {
                redo()
            } else {
                undo()
            }
            return true
        } else if (code == LETTER_Y) {
            redo()
            return true
        }
        false
    }

    // Clipboard access can fail where there is no desktop session; treat it as best-effort
    // so a copy or paste never crashes the field.
    private func copySelection(edit: TextEditState): Bool {
        if (!edit.hasSelection()) {
            return false
        }
        try {
            Clipboard.setText(edit.selectedText())
            true
        } catch (_: Exception) {
            false
        }
    }

    private func pasteClipboard(edit: TextEditState): Unit {
        try {
            let clip = Clipboard.getText()
            if (clip.size > 0) {
                edit.insert(flattenLines(clip)) // a single-line field keeps its value on one row
            }
        } catch (_: Exception) {
            ()
        }
    }
}

// Collapses any line breaks so pasted multi-line text stays on the field's single row:
// newlines become spaces and stray carriage returns are dropped.
private func flattenLines(value: String): String {
    let builder = StringBuilder()
    var firstLine = true
    for (line in value.split("\n")) {
        if (!firstLine) {
            builder.append(" ")
        }
        firstLine = false
        for (chunk in line.split("\r")) {
            builder.append(chunk)
        }
    }
    builder.toString()
}

private func drawTextFieldText(ctx: UiContext, frame: Rect, text: String, xShift: Float32): Unit {
    let textY = frame.centerY() - ctx.renderer.textHeight(pointSize: FontSizes.BODY) * 0.3519
    ctx.renderer.text(text, frame.x + 8.0 - xShift, textY, ctx.theme.text, pointSize: FontSizes.BODY)
}
