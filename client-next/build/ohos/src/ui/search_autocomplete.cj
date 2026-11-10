package lanlu_client_next.ui

import cui.*
import lanlu_client_next.app.AppModel
import lanlu_client_next.net.TagSuggestion
import std.collection.ArrayList

private let AUTOCOMPLETE_DEBOUNCE_MS: UInt64 = 220
private let AUTOCOMPLETE_ROW_H: Float32 = 36.0
private let AUTOCOMPLETE_PAD: Float32 = 4.0
private let AUTOCOMPLETE_GAP: Float32 = 4.0
private let AUTOCOMPLETE_OWNER = "titlebar:autocomplete"

private func autocompleteWords(raw: String): ArrayList<String> {
    let words = ArrayList<String>()
    let normalized = raw.replace("\t", " ").replace("\n", " ").replace("\r", " ")
    for (part in normalized.trimAscii().split(" ", removeEmpty: true)) {
        let word = part.trimAscii()
        if (word.size > 0) {
            words.add(word)
        }
    }
    words
}

func lastAutocompleteToken(raw: String): String {
    let words = autocompleteWords(raw)
    if (words.size == 0) {
        return ""
    }
    words[words.size - 1]
}

func replaceAutocompleteToken(raw: String, value: String): String {
    let words = autocompleteWords(raw)
    if (words.size == 0) {
        return value
    }
    words[words.size - 1] = value
    String.join(words.toArray(), delimiter: " ")
}

// TextField 仍负责文本编辑；本件只观察输入做防抖请求，并把建议列表注册为
// 全局交互浮层，确保它能绘制在书库内容之上且优先接收鼠标/键盘事件。
class SearchAutocomplete <: Widget {
    private let model: AppModel
    private let fieldId: String
    private let observedText: State<String>
    private let dueAt: State<UInt64>
    private let wasFocused: State<Bool>
    private let selectedIndex: State<Int64>
    private var frame = Rect.zero()

    public init(model: AppModel, fieldId: String) {
        this.model = model
        this.fieldId = fieldId
        this.observedText = rememberState<String>("titlebar:autocomplete:text", {=> ""})
        this.dueAt = rememberState<UInt64>("titlebar:autocomplete:due", {=> UInt64(0)})
        this.wasFocused = rememberState<Bool>("titlebar:autocomplete:focused", {=> false})
        this.selectedIndex = rememberState<Int64>("titlebar:autocomplete:selected", {=> -1})
        emit(this)
    }

    public func measure(_: UiContext, _: Size): Size {
        Size(0.0, 0.0)
    }

    public func layout(_: UiContext, rect: Rect): Unit {
        frame = rect
    }

    public func draw(ctx: UiContext): Unit {
        driveDebounce(ctx)
        let token = lastAutocompleteToken(model.searchText.value)
        let shouldShow = ctx.hasFocus(fieldId) && model.autocompleteVisible.value && model.autocompleteQuery.value ==
            token && (model.autocompleteLoading.value || model.autocompleteSuggestions.value.size > 0)
        if (shouldShow) {
            let popup = popupRect()
            ctx.setOverlay(
                Overlay(owner: AUTOCOMPLETE_OWNER, handleEvent: {c, event => handleOverlay(c, event, popup)},
                    render: {c => drawPopup(c, popup)}))
        }
    }

    private func driveDebounce(ctx: UiContext): Unit {
        let focused = ctx.hasFocus(fieldId)
        let text = model.searchText.value
        if (text != observedText.value) {
            observedText.value = text
            selectedIndex.value = -1
            if (model.autocompleteVisible.value) {
                model.dismissAutocomplete()
            }
            schedule(ctx, focused)
        }
        if (focused != wasFocused.value) {
            wasFocused.value = focused
            if (focused) {
                schedule(ctx, true)
            } else {
                dueAt.value = UInt64(0)
                if (model.autocompleteVisible.value) {
                    model.dismissAutocomplete()
                }
            }
        }
        if (focused && dueAt.value > UInt64(0)) {
            if (ctx.frame.elapsedMs >= dueAt.value) {
                dueAt.value = UInt64(0)
                model.requestAutocomplete(lastAutocompleteToken(text))
            } else {
                ctx.requestFrame()
            }
        }
    }

    private func schedule(ctx: UiContext, focused: Bool): Unit {
        let token = lastAutocompleteToken(model.searchText.value)
        if (!focused || token.size == 0) {
            dueAt.value = UInt64(0)
            if (token.size == 0 && model.autocompleteQuery.value.size > 0) {
                model.clearAutocomplete()
            }
            return
        }
        dueAt.value = ctx.frame.elapsedMs + AUTOCOMPLETE_DEBOUNCE_MS
        ctx.requestFrame()
    }

    private func popupRect(): Rect {
        let rows = if (model.autocompleteSuggestions.value.size > 0) {
            model.autocompleteSuggestions.value.size
        } else {
            1
        }
        Rect(frame.x, frame.bottom() + AUTOCOMPLETE_GAP, frame.w,
            Float32(rows) * AUTOCOMPLETE_ROW_H + AUTOCOMPLETE_PAD * 2.0)
    }

    private func handleOverlay(ctx: UiContext, event: UiEvent, popup: Rect): Bool {
        match (event) {
            case UiEvent.MouseDown(MouseButton.Left, x, y) =>
                if (!popup.contains(x, y)) {
                    model.dismissAutocomplete()
                    ctx.removeOverlay(AUTOCOMPLETE_OWNER)
                    return false
                }
                let index = rowAt(popup, y)
                if (validIndex(index)) {
                    choose(ctx, index)
                }
                true
            case UiEvent.MouseMove(x, y) =>
                if (popup.contains(x, y)) {
                    ctx.claimHover(AUTOCOMPLETE_OWNER, CursorShape.Interactive)
                    let index = rowAt(popup, y)
                    if (validIndex(index) && selectedIndex.value != index) {
                        selectedIndex.value = index
                    }
                }
                false
            case UiEvent.KeyDown(Key.Down, _) => moveSelection(1)
            case UiEvent.KeyDown(Key.Up, _) => moveSelection(-1)
            case UiEvent.KeyDown(Key.Enter, _) =>
                if (validIndex(selectedIndex.value)) {
                    choose(ctx, selectedIndex.value)
                    true
                } else {
                    false
                }
            case UiEvent.KeyDown(Key.Escape, _) =>
                model.dismissAutocomplete()
                selectedIndex.value = -1
                ctx.removeOverlay(AUTOCOMPLETE_OWNER)
                true
            case _ => false
        }
    }

    private func moveSelection(delta: Int64): Bool {
        let count = model.autocompleteSuggestions.value.size
        if (count == 0) {
            return false
        }
        if (delta > 0) {
            selectedIndex.value = if (selectedIndex.value + 1 < count) {
                selectedIndex.value + 1
            } else {
                0
            }
        } else {
            selectedIndex.value = if (selectedIndex.value > 0) {
                selectedIndex.value - 1
            } else {
                count - 1
            }
        }
        true
    }

    private func choose(ctx: UiContext, index: Int64): Unit {
        let suggestion = model.autocompleteSuggestions.value[index]
        let nextText = replaceAutocompleteToken(model.searchText.value, suggestion.value)
        // 选择是一次已完成的补全，先同步观察值，避免下一帧把结果又当成新输入发起请求。
        observedText.value = nextText
        dueAt.value = UInt64(0)
        model.searchText.value = nextText
        model.clearAutocomplete()
        selectedIndex.value = -1
        ctx.removeOverlay(AUTOCOMPLETE_OWNER)
        ctx.focus(fieldId)
    }

    private func rowAt(popup: Rect, y: Float32): Int64 {
        if (y < popup.y + AUTOCOMPLETE_PAD || y >= popup.bottom() - AUTOCOMPLETE_PAD) {
            return -1
        }
        Int64((y - popup.y - AUTOCOMPLETE_PAD) / AUTOCOMPLETE_ROW_H)
    }

    private func validIndex(index: Int64): Bool {
        index >= 0 && index < model.autocompleteSuggestions.value.size
    }

    private func drawPopup(ctx: UiContext, popup: Rect): Unit {
        let surface = if (model.isLight()) { ctx.theme.panel } else { ctx.theme.panelRaised }
        ctx.renderer.fillRoundedRect(popup, 9.0, surface)
        ctx.renderer.strokeRoundedRect(popup.inset(0.5), 8.5, Pen(width: 1.0, color: ctx.theme.panelEdge))
        let suggestions = model.autocompleteSuggestions.value
        if (suggestions.size == 0) {
            drawLoading(ctx, popup)
            return
        }
        for (i in 0..suggestions.size) {
            drawSuggestion(ctx, popup, i, suggestions[i])
        }
    }

    private func drawLoading(ctx: UiContext, popup: Rect): Unit {
        let text = "正在查找标签…"
        let textH = ctx.renderer.textHeight(pointSize: 12.0)
        ctx.renderer.text(text, popup.x + 12.0, popup.centerY() - textH / 2.0, ctx.theme.mutedText, pointSize: 12.0)
    }

    private func drawSuggestion(ctx: UiContext, popup: Rect, index: Int64, suggestion: TagSuggestion): Unit {
        let row = Rect(popup.x + AUTOCOMPLETE_PAD, popup.y + AUTOCOMPLETE_PAD + Float32(index) * AUTOCOMPLETE_ROW_H,
            popup.w - AUTOCOMPLETE_PAD * 2.0, AUTOCOMPLETE_ROW_H)
        let selected = index == selectedIndex.value || row.contains(ctx.mouseX, ctx.mouseY)
        if (selected) {
            ctx.renderer.fillRoundedRect(row, 6.0, ctx.theme.accentSoft)
        }
        let textColor = if (selected) {
            ctx.theme.accent
        } else {
            ctx.theme.text
        }
        let textY = row.centerY() - ctx.renderer.textHeight(pointSize: 12.5) / 2.0
        ctx.renderer.pushClip(Rect(row.x + 10.0, row.y, max(0.0, row.w - 20.0), row.h))
        ctx.renderer.text(suggestion.label, row.x + 10.0, textY, textColor, pointSize: 12.5)
        if (suggestion.label != suggestion.value) {
            let labelW = ctx.renderer.textWidth(suggestion.label, pointSize: 12.5)
            ctx
                .renderer
                .text("(${suggestion.value})", row.x + 18.0 + labelW, textY + 1.0, ctx.theme.mutedText, pointSize: 11.0)
        }
        ctx.renderer.popClip()
    }

    public func handle(_: UiContext, _: UiEvent): Bool {
        false
    }
}
