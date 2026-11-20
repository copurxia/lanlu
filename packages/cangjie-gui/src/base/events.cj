package cui.base

import std.env.getVariable
import std.fs.{File, OpenMode}

public enum Key {
    | Escape
    | Backspace
    | Enter
    | Tab
    | Delete
    | Space
    | Home
    | End
    | PageUp
    | PageDown
    | Left
    | Right
    | Up
    | Down
    | Letter(UInt8)
    | Digit(UInt8)
    | RawScancode(Int32)
}

public enum MouseButton {
    | Left
    | Middle
    | Right
    | RawCode(UInt8)
}

public struct FrameInfo {
    public let elapsedMs: UInt64
    public let deltaMs: UInt64

    public init(elapsedMs: UInt64, deltaMs: UInt64) {
        this.elapsedMs = elapsedMs
        this.deltaMs = deltaMs
    }
}

public enum UiEvent {
    | Frame(FrameInfo)
    | Quit
    | WindowResized(Int32, Int32)
    | KeyDown(Key, Bool)
    | KeyUp(Key)
    | TextInput(String)
    /// 输入法组合中的文本（preedit）与组合串内光标字节偏移。不改变控件值，只影响显示。
    | TextEditing(String, Int64)
    /// 输入法要求删除光标前后文本（单位：字符）。壳侧 LWP delete_surrounding 的落点。
    | DeleteSurrounding(Int64, Int64)
    | MouseMove(Float32, Float32)
    | MouseDown(MouseButton, Float32, Float32)
    | MouseUp(MouseButton, Float32, Float32)
    | MouseWheel(Float32, Float32, Float32, Float32)
    | DropBegin
    | DropFile(String, Float32, Float32)
    | DropText(String, Float32, Float32)
    | DropPosition(Float32, Float32)
    | DropComplete
    | Unknown(UInt32)
}

// Decodes the SDL event union in place: the caller passes a pointer to the stack event it
// just polled (CPointer(inout raw), the same pattern as the vips call sites), so decoding
// costs no heap allocation per event — the previous malloc+copy existed only to obtain a
// reinterpretable address. The pointer is read synchronously and never escapes this call.
// 联调落盘（引擎 stdout 不进 hilog）：LANLU_INPUT_LOG=1 时把事件记录追加到 $HOME/input_log.txt
func appendInputLog(line: String): Unit {
    if (getVariable("LANLU_INPUT_LOG") != Some("1")) {
        return
    }
    let home = getVariable("HOME") ?? "."
    let body = (line + "\n").toArray()
    try {
        let f = File(home + "/input_log.txt", OpenMode.Append)
        f.write(body)
        f.close()
    } catch (_) {
        try {
            let f2 = File(home + "/input_log.txt", OpenMode.Write)
            f2.write(body)
            f2.close()
        } catch (_) {}
    }
}

// OHOS IME 桥用 SDL user event 提交文本时使用的 code
internal let LANLU_USER_TEXT_INPUT: Int32 = 1

internal func decodeEvent(eventPtr: CPointer<SdlEvent>): UiEvent {
    var decoded = UiEvent.Unknown(UInt32(0))
    let common = unsafe { CPointer<SdlCommonEvent>(eventPtr).read() }
    let eventType = common.eventType
    if (getVariable("LANLU_INPUT_LOG") == Some("1")) {
        appendInputLog("poll type=" + eventType.toString())
    }

    // Only SDL_EVENT_QUIT ends the app. For a single-window desktop app SDL raises
    // it when the last window's close button is pressed. SDL_EVENT_WINDOW_CLOSE_REQUESTED
    // is intentionally NOT treated as quit: Windows can emit a spurious close request
    // during window creation, which would otherwise flash the window shut on startup.
    // 平台层（OHOS IME 桥）用 SDL user event 携带文本：SDL 拒绝直接推 TEXT_INPUT，
    // 而 USER 事件通道可用（唤醒事件即走这条路）。code=1 表示"提交文本"。
    if (eventType == SDL_EVENT_USER) {
        let u = unsafe { CPointer<SdlUserEvent>(eventPtr).read() }
        if (u.code == LANLU_USER_TEXT_INPUT) {
            let txt = if (u.data1.isNull()) { "" } else { CString(u.data1).toString() }
            if (!u.data1.isNull()) {
                unsafe { LibC.free(CPointer<UInt8>(u.data1)) }
            }
            appendInputLog("[input] TEXT_INPUT text=\"" + txt + "\" (user event)")
            return UiEvent.TextInput(txt)
        }
    }
    if (eventType == SDL_EVENT_QUIT) {
        decoded = UiEvent.Quit
    } else if (eventType == SDL_EVENT_WINDOW_RESIZED) {
        let window = unsafe { CPointer<SdlWindowEvent>(eventPtr).read() }
        decoded = UiEvent.WindowResized(window.data1, window.data2)
    } else if (eventType == SDL_EVENT_KEY_DOWN || eventType == SDL_EVENT_KEY_UP) {
        let keyEvent = unsafe { CPointer<SdlKeyboardEvent>(eventPtr).read() }
        if (eventType == SDL_EVENT_KEY_DOWN) {
            decoded = UiEvent.KeyDown(keyFromScancode(keyEvent.scancode), keyEvent.repeat)
        } else {
            decoded = UiEvent.KeyUp(keyFromScancode(keyEvent.scancode))
        }
    } else if (eventType == SDL_EVENT_TEXT_INPUT) {
        // 联调：LANLU_INPUT_LOG=1 时打印收到的文本输入（验证 IME 桥 -> 引擎链路）
        if (getVariable("LANLU_INPUT_LOG") == Some("1")) {
            // 写文件而非 stdout（引擎 stdout 不进 hilog），便于 hdc 取回核对
            let t = unsafe { CPointer<SdlTextInputEvent>(eventPtr).read() }
            let txt = if (t.text.isNull()) { "" } else { CString(t.text).toString() }
            // Append 模式要求文件已存在：失败时退回 Write（每次覆盖，测试够用）
            let home = getVariable("HOME") ?? "."
            let body = ("[input] TEXT_INPUT text=\"" + txt + "\"\n").toArray()
            try {
                let f = File(home + "/input_log.txt", OpenMode.Append)
                f.write(body)
                f.close()
            } catch (_) {
                try {
                    let f2 = File(home + "/input_log.txt", OpenMode.Write)
                    f2.write(body)
                    f2.close()
                } catch (_) {}
            }
        }
        let text = unsafe { CPointer<SdlTextInputEvent>(eventPtr).read() }
        if (text.text.isNull()) {
            decoded = UiEvent.TextInput("")
        } else {
            decoded = UiEvent.TextInput(CString(text.text).toString())
        }
    } else if (eventType == SDL_EVENT_MOUSE_MOTION) {
        let motion = unsafe { CPointer<SdlMouseMotionEvent>(eventPtr).read() }
        decoded = UiEvent.MouseMove(motion.x, motion.y)
    } else if (eventType == SDL_EVENT_MOUSE_BUTTON_DOWN || eventType == SDL_EVENT_MOUSE_BUTTON_UP) {
        let button = unsafe { CPointer<SdlMouseButtonEvent>(eventPtr).read() }
        if (eventType == SDL_EVENT_MOUSE_BUTTON_DOWN) {
            decoded = UiEvent.MouseDown(buttonFromCode(button.button), button.x, button.y)
        } else {
            decoded = UiEvent.MouseUp(buttonFromCode(button.button), button.x, button.y)
        }
    } else if (eventType == SDL_EVENT_MOUSE_WHEEL) {
        let wheel = unsafe { CPointer<SdlMouseWheelEvent>(eventPtr).read() }
        decoded = UiEvent.MouseWheel(wheel.x, wheel.y, wheel.mouseX, wheel.mouseY)
    } else if (isDropEvent(eventType)) {
        let drop = unsafe { CPointer<SdlDropEvent>(eventPtr).read() }
        decoded = decodeDropEvent(eventType, drop)
    } else {
        decoded = UiEvent.Unknown(eventType)
    }
    decoded
}

internal func scaleEventCoordinates(event: UiEvent, scale: Float32): UiEvent {
    if (scale == 1.0) {
        return event
    }
    match (event) {
        case UiEvent.MouseMove(x, y) => UiEvent.MouseMove(x / scale, y / scale)
        case UiEvent.MouseDown(button, x, y) => UiEvent.MouseDown(button, x / scale, y / scale)
        case UiEvent.MouseUp(button, x, y) => UiEvent.MouseUp(button, x / scale, y / scale)
        case UiEvent.MouseWheel(dx, dy, x, y) => UiEvent.MouseWheel(dx, dy, x / scale, y / scale)
        case UiEvent.DropFile(path, x, y) => UiEvent.DropFile(path, x / scale, y / scale)
        case UiEvent.DropText(text, x, y) => UiEvent.DropText(text, x / scale, y / scale)
        case UiEvent.DropPosition(x, y) => UiEvent.DropPosition(x / scale, y / scale)
        case _ => event
    }
}

internal func isDropEvent(eventType: UInt32): Bool {
    eventType == SDL_EVENT_DROP_FILE || eventType == SDL_EVENT_DROP_TEXT || eventType == SDL_EVENT_DROP_BEGIN ||
        eventType == SDL_EVENT_DROP_COMPLETE || eventType == SDL_EVENT_DROP_POSITION
}

internal func decodeDropEvent(eventType: UInt32, drop: SdlDropEvent): UiEvent {
    if (eventType == SDL_EVENT_DROP_FILE) {
        UiEvent.DropFile(dropData(drop), drop.x, drop.y)
    } else if (eventType == SDL_EVENT_DROP_TEXT) {
        UiEvent.DropText(dropData(drop), drop.x, drop.y)
    } else if (eventType == SDL_EVENT_DROP_POSITION) {
        UiEvent.DropPosition(drop.x, drop.y)
    } else if (eventType == SDL_EVENT_DROP_BEGIN) {
        UiEvent.DropBegin
    } else {
        UiEvent.DropComplete
    }
}

private func dropData(drop: SdlDropEvent): String {
    if (drop.data.isNull()) {
        ""
    } else {
        CString(drop.data).toString()
    }
}

internal func keyFromScancode(scancode: Int32): Key {
    if (scancode >= SDL_SCANCODE_A && scancode <= SDL_SCANCODE_Z) {
        Key.Letter(UInt8(scancode - SDL_SCANCODE_A + 65))
    } else if (scancode >= SDL_SCANCODE_1 && scancode <= SDL_SCANCODE_0) {
        if (scancode == SDL_SCANCODE_0) {
            Key.Digit(UInt8(48))
        } else {
            Key.Digit(UInt8(scancode - SDL_SCANCODE_1 + 49))
        }
    } else if (scancode == SDL_SCANCODE_ESCAPE) {
        Key.Escape
    } else if (scancode == SDL_SCANCODE_BACKSPACE) {
        Key.Backspace
    } else if (scancode == SDL_SCANCODE_RETURN) {
        Key.Enter
    } else if (scancode == SDL_SCANCODE_TAB) {
        Key.Tab
    } else if (scancode == SDL_SCANCODE_DELETE) {
        Key.Delete
    } else if (scancode == SDL_SCANCODE_SPACE) {
        Key.Space
    } else if (scancode == SDL_SCANCODE_HOME) {
        Key.Home
    } else if (scancode == SDL_SCANCODE_END) {
        Key.End
    } else if (scancode == SDL_SCANCODE_PAGEUP) {
        Key.PageUp
    } else if (scancode == SDL_SCANCODE_PAGEDOWN) {
        Key.PageDown
    } else if (scancode == SDL_SCANCODE_RIGHT) {
        Key.Right
    } else if (scancode == SDL_SCANCODE_LEFT) {
        Key.Left
    } else if (scancode == SDL_SCANCODE_DOWN) {
        Key.Down
    } else if (scancode == SDL_SCANCODE_UP) {
        Key.Up
    } else {
        Key.RawScancode(scancode)
    }
}

internal func buttonFromCode(button: UInt8): MouseButton {
    if (button == SDL_BUTTON_LEFT) {
        MouseButton.Left
    } else if (button == SDL_BUTTON_MIDDLE) {
        MouseButton.Middle
    } else if (button == SDL_BUTTON_RIGHT) {
        MouseButton.Right
    } else {
        MouseButton.RawCode(button)
    }
}
