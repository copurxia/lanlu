// 由 tools/lwp-gen.py 生成，勿手改。
// 源：packages/lwp/protocol/*.toml
package lwp

public let LWP_PROTOCOL_MAJOR: UInt16 = 1
public let LWP_PROTOCOL_MINOR: UInt16 = 0
public let LWP_DIR_REQUEST: UInt16 = 0
public let LWP_DIR_EVENT: UInt16 = 1

// error.code 取值；未列出的值一律按 Unknown 处理。
public let LWP_CORE_ERROR_NONE: UInt64 = 0
public let LWP_CORE_ERROR_BAD_MESSAGE: UInt64 = 1
public let LWP_CORE_ERROR_UNKNOWN_OPCODE: UInt64 = 2
public let LWP_CORE_ERROR_VERSION_MISMATCH: UInt64 = 3
public let LWP_CORE_ERROR_NOT_HANDSHAKED: UInt64 = 4
public let LWP_CORE_ERROR_DROPPED: UInt64 = 5

// hello.capabilities：壳宣告的能力位（计划 §5.3）。缺省全 0 = 什么都不支持。
public let LWP_CORE_CAPABILITIES_SERVER_SIDE_DECORATIONS: UInt64 = 1
public let LWP_CORE_CAPABILITIES_WINDOW_MOVE: UInt64 = 2
public let LWP_CORE_CAPABILITIES_WINDOW_RESIZE_EDGES: UInt64 = 4
public let LWP_CORE_CAPABILITIES_MIN_MAX_SIZE: UInt64 = 8
public let LWP_CORE_CAPABILITIES_CURSOR_SHAPES: UInt64 = 16
public let LWP_CORE_CAPABILITIES_CURSOR_LOCK: UInt64 = 32
public let LWP_CORE_CAPABILITIES_IME_PREEDIT: UInt64 = 64
public let LWP_CORE_CAPABILITIES_IME_SURROUNDING_TEXT: UInt64 = 128
public let LWP_CORE_CAPABILITIES_CLIPBOARD_READ_ASYNC: UInt64 = 256
public let LWP_CORE_CAPABILITIES_CLIPBOARD_MIME: UInt64 = 512
public let LWP_CORE_CAPABILITIES_DRAG_DROP: UInt64 = 1024
public let LWP_CORE_CAPABILITIES_FILE_DIALOG_SAVE: UInt64 = 2048
public let LWP_CORE_CAPABILITIES_FILE_DIALOG_FOLDER: UInt64 = 4096
public let LWP_CORE_CAPABILITIES_VSYNC: UInt64 = 8192
public let LWP_CORE_CAPABILITIES_FRACTIONAL_SCALE: UInt64 = 16384
public let LWP_CORE_CAPABILITIES_MULTI_WINDOW: UInt64 = 32768
public let LWP_CORE_CAPABILITIES_SOFT_KEYBOARD: UInt64 = 65536
public let LWP_CORE_CAPABILITIES_TITLE_BUTTONS: UInt64 = 131072

// lw_input.key 的 modifiers 字段。位定义对齐 SDL_KMOD_*（lgui.input.KeyModifiers 的输入格式）。
public let LWP_KEY_MODIFIERS_LSHIFT: UInt64 = 1
public let LWP_KEY_MODIFIERS_RSHIFT: UInt64 = 2
public let LWP_KEY_MODIFIERS_LEVEL5: UInt64 = 4
public let LWP_KEY_MODIFIERS_LCTRL: UInt64 = 64
public let LWP_KEY_MODIFIERS_RCTRL: UInt64 = 128
public let LWP_KEY_MODIFIERS_LALT: UInt64 = 256
public let LWP_KEY_MODIFIERS_RALT: UInt64 = 512
public let LWP_KEY_MODIFIERS_LGUI: UInt64 = 1024
public let LWP_KEY_MODIFIERS_RGUI: UInt64 = 2048
public let LWP_KEY_MODIFIERS_NUM: UInt64 = 4096
public let LWP_KEY_MODIFIERS_CAPS: UInt64 = 8192
public let LWP_KEY_MODIFIERS_MODE: UInt64 = 16384
public let LWP_KEY_MODIFIERS_SCROLL: UInt64 = 32768

// 输入框类型：壳据此选择输入法模式（文本/数字/密码/URL 等）。
public let LWP_IME_TEXT_INPUT_TYPE_TEXT: UInt64 = 0
public let LWP_IME_TEXT_INPUT_TYPE_NUMBER: UInt64 = 1
public let LWP_IME_TEXT_INPUT_TYPE_PHONE: UInt64 = 2
public let LWP_IME_TEXT_INPUT_TYPE_PASSWORD: UInt64 = 3
public let LWP_IME_TEXT_INPUT_TYPE_URL: UInt64 = 4
public let LWP_IME_TEXT_INPUT_TYPE_EMAIL: UInt64 = 5

// 回车键语义：壳据此决定软键盘右下角按键（完成/搜索/发送/换行）。
public let LWP_IME_ENTER_KEY_UNSPECIFIED: UInt64 = 0
public let LWP_IME_ENTER_KEY_NONE: UInt64 = 1
public let LWP_IME_ENTER_KEY_GO: UInt64 = 2
public let LWP_IME_ENTER_KEY_SEARCH: UInt64 = 3
public let LWP_IME_ENTER_KEY_SEND: UInt64 = 4
public let LWP_IME_ENTER_KEY_NEXT: UInt64 = 5
public let LWP_IME_ENTER_KEY_DONE: UInt64 = 6
public let LWP_IME_ENTER_KEY_PREVIOUS: UInt64 = 7
public let LWP_IME_ENTER_KEY_NEWLINE: UInt64 = 8

public let LWP_IFACE_LW_CORE: UInt16 = 1
public let LWP_IFACE_LW_CORE_VERSION: UInt16 = 1
public let LWP_IFACE_LW_INPUT: UInt16 = 2
public let LWP_IFACE_LW_INPUT_VERSION: UInt16 = 1
public let LWP_IFACE_LW_SEAT: UInt16 = 8
public let LWP_IFACE_LW_SEAT_VERSION: UInt16 = 1
public let LWP_IFACE_LW_TEXT_INPUT: UInt16 = 9
public let LWP_IFACE_LW_TEXT_INPUT_VERSION: UInt16 = 1
public let LWP_IFACE_LW_CLIPBOARD: UInt16 = 10
public let LWP_IFACE_LW_CLIPBOARD_VERSION: UInt16 = 1
public let LWP_IFACE_LW_DIALOG: UInt16 = 11
public let LWP_IFACE_LW_DIALOG_VERSION: UInt16 = 1
public let LWP_IFACE_LW_SYSTEM: UInt16 = 12
public let LWP_IFACE_LW_SYSTEM_VERSION: UInt16 = 1
public let LWP_IFACE_LW_TEST: UInt16 = 13
public let LWP_IFACE_LW_TEST_VERSION: UInt16 = 1
public let LWP_IFACE_LW_APP: UInt16 = 3
public let LWP_IFACE_LW_APP_VERSION: UInt16 = 1
public let LWP_IFACE_LW_WINDOW: UInt16 = 4
public let LWP_IFACE_LW_WINDOW_VERSION: UInt16 = 1
public let LWP_IFACE_LW_SURFACE: UInt16 = 5
public let LWP_IFACE_LW_SURFACE_VERSION: UInt16 = 1
public let LWP_IFACE_LW_FRAME: UInt16 = 6
public let LWP_IFACE_LW_FRAME_VERSION: UInt16 = 1
public let LWP_IFACE_LW_DISPLAY: UInt16 = 7
public let LWP_IFACE_LW_DISPLAY_VERSION: UInt16 = 1

public let LWP_LW_CORE_HELLO_ACK_OPCODE: UInt16 = 0
public let LWP_LW_CORE_HELLO_ACK_SIZE: Int64 = 16

public struct LwpLwCoreHelloAck {
    public let protocol_major: UInt16
    public let protocol_minor: UInt16
    public let engine_version: UInt32
    public let engine_name: String

    public init(protocol_major: UInt16, protocol_minor: UInt16, engine_version: UInt32, engine_name: String) {
        this.protocol_major = protocol_major
        this.protocol_minor = protocol_minor
        this.engine_version = engine_version
        this.engine_name = engine_name
    }
}

public func decodeLwpLwCoreHelloAck(body: Array<UInt8>): LwpLwCoreHelloAck {
    return LwpLwCoreHelloAck(
        lwpU16(body, 4),
        lwpU16(body, 6),
        lwpU32(body, 8),
        lwpString(body, 12),
    )
}

public let LWP_LW_CORE_PING_OPCODE: UInt16 = 1
public let LWP_LW_CORE_PING_SIZE: Int64 = 8

public struct LwpLwCorePing {
    public let seq: UInt32

    public init(seq: UInt32) {
        this.seq = seq
    }
}

public func decodeLwpLwCorePing(body: Array<UInt8>): LwpLwCorePing {
    return LwpLwCorePing(
        lwpU32(body, 4),
    )
}

public let LWP_LW_CORE_HELLO_OPCODE: UInt16 = 0
public let LWP_LW_CORE_HELLO_SIZE: Int64 = 28

public struct LwpLwCoreHello {
    public let protocol_major: UInt16
    public let protocol_minor: UInt16
    public let shell_name: String
    public let os_name: String
    public let os_api_level: UInt32
    public let capabilities: UInt64

    public init(protocol_major: UInt16, protocol_minor: UInt16, shell_name: String, os_name: String, os_api_level: UInt32, capabilities: UInt64) {
        this.protocol_major = protocol_major
        this.protocol_minor = protocol_minor
        this.shell_name = shell_name
        this.os_name = os_name
        this.os_api_level = os_api_level
        this.capabilities = capabilities
    }
}

public func decodeLwpLwCoreHello(body: Array<UInt8>): LwpLwCoreHello {
    return LwpLwCoreHello(
        lwpU16(body, 4),
        lwpU16(body, 6),
        lwpString(body, 8),
        lwpString(body, 12),
        lwpU32(body, 16),
        lwpU64(body, 20),
    )
}

public let LWP_LW_CORE_ERROR_OPCODE: UInt16 = 1
public let LWP_LW_CORE_ERROR_SIZE: Int64 = 12

public struct LwpLwCoreError {
    public let code: Int32
    public let message: String

    public init(code: Int32, message: String) {
        this.code = code
        this.message = message
    }
}

public func decodeLwpLwCoreError(body: Array<UInt8>): LwpLwCoreError {
    return LwpLwCoreError(
        lwpI32(body, 4),
        lwpString(body, 8),
    )
}

public let LWP_LW_CORE_LOG_OPCODE: UInt16 = 2
public let LWP_LW_CORE_LOG_SIZE: Int64 = 13

public struct LwpLwCoreLog {
    public let level: UInt8
    public let module: String
    public let text: String

    public init(level: UInt8, module: String, text: String) {
        this.level = level
        this.module = module
        this.text = text
    }
}

public func decodeLwpLwCoreLog(body: Array<UInt8>): LwpLwCoreLog {
    return LwpLwCoreLog(
        lwpU8(body, 4),
        lwpString(body, 5),
        lwpString(body, 9),
    )
}

public let LWP_LW_CORE_PONG_OPCODE: UInt16 = 3
public let LWP_LW_CORE_PONG_SIZE: Int64 = 8

public struct LwpLwCorePong {
    public let seq: UInt32

    public init(seq: UInt32) {
        this.seq = seq
    }
}

public func decodeLwpLwCorePong(body: Array<UInt8>): LwpLwCorePong {
    return LwpLwCorePong(
        lwpU32(body, 4),
    )
}

public let LWP_LW_INPUT_POINTER_MOTION_OPCODE: UInt16 = 0
public let LWP_LW_INPUT_POINTER_MOTION_SIZE: Int64 = 12

public struct LwpLwInputPointerMotion {
    public let x: Float32
    public let y: Float32

    public init(x: Float32, y: Float32) {
        this.x = x
        this.y = y
    }
}

public func decodeLwpLwInputPointerMotion(body: Array<UInt8>): LwpLwInputPointerMotion {
    return LwpLwInputPointerMotion(
        lwpF32(body, 4),
        lwpF32(body, 8),
    )
}

public let LWP_LW_INPUT_POINTER_BUTTON_OPCODE: UInt16 = 1
public let LWP_LW_INPUT_POINTER_BUTTON_SIZE: Int64 = 14

public struct LwpLwInputPointerButton {
    public let x: Float32
    public let y: Float32
    public let button: UInt8
    public let down: Bool

    public init(x: Float32, y: Float32, button: UInt8, down: Bool) {
        this.x = x
        this.y = y
        this.button = button
        this.down = down
    }
}

public func decodeLwpLwInputPointerButton(body: Array<UInt8>): LwpLwInputPointerButton {
    return LwpLwInputPointerButton(
        lwpF32(body, 4),
        lwpF32(body, 8),
        lwpU8(body, 12),
        lwpBool(body, 13),
    )
}

public let LWP_LW_INPUT_POINTER_AXIS_OPCODE: UInt16 = 2
public let LWP_LW_INPUT_POINTER_AXIS_SIZE: Int64 = 12

public struct LwpLwInputPointerAxis {
    public let dx: Float32
    public let dy: Float32

    public init(dx: Float32, dy: Float32) {
        this.dx = dx
        this.dy = dy
    }
}

public func decodeLwpLwInputPointerAxis(body: Array<UInt8>): LwpLwInputPointerAxis {
    return LwpLwInputPointerAxis(
        lwpF32(body, 4),
        lwpF32(body, 8),
    )
}

public let LWP_LW_INPUT_KEY_OPCODE: UInt16 = 3
public let LWP_LW_INPUT_KEY_SIZE: Int64 = 15

public struct LwpLwInputKey {
    public let keycode: UInt32
    public let down: Bool
    public let utf8: String
    public let modifiers: UInt16

    public init(keycode: UInt32, down: Bool, utf8: String, modifiers: UInt16) {
        this.keycode = keycode
        this.down = down
        this.utf8 = utf8
        this.modifiers = modifiers
    }
}

public func decodeLwpLwInputKey(body: Array<UInt8>): LwpLwInputKey {
    return LwpLwInputKey(
        lwpU32(body, 4),
        lwpBool(body, 8),
        lwpString(body, 9),
        lwpU16(body, 13),
    )
}

public let LWP_LW_INPUT_TEXT_INPUT_OPCODE: UInt16 = 4
public let LWP_LW_INPUT_TEXT_INPUT_SIZE: Int64 = 8

public struct LwpLwInputTextInput {
    public let text: String

    public init(text: String) {
        this.text = text
    }
}

public func decodeLwpLwInputTextInput(body: Array<UInt8>): LwpLwInputTextInput {
    return LwpLwInputTextInput(
        lwpString(body, 4),
    )
}

public let LWP_LW_SEAT_SET_CURSOR_OPCODE: UInt16 = 0
public let LWP_LW_SEAT_SET_CURSOR_SIZE: Int64 = 8

public struct LwpLwSeatSetCursor {
    public let shape: UInt32

    public init(shape: UInt32) {
        this.shape = shape
    }
}

public func decodeLwpLwSeatSetCursor(body: Array<UInt8>): LwpLwSeatSetCursor {
    return LwpLwSeatSetCursor(
        lwpU32(body, 4),
    )
}

public let LWP_LW_SEAT_LOCK_CURSOR_OPCODE: UInt16 = 1
public let LWP_LW_SEAT_LOCK_CURSOR_SIZE: Int64 = 5

public struct LwpLwSeatLockCursor {
    public let locked: Bool

    public init(locked: Bool) {
        this.locked = locked
    }
}

public func decodeLwpLwSeatLockCursor(body: Array<UInt8>): LwpLwSeatLockCursor {
    return LwpLwSeatLockCursor(
        lwpBool(body, 4),
    )
}

public let LWP_LW_SEAT_CAPABILITIES_OPCODE: UInt16 = 0
public let LWP_LW_SEAT_CAPABILITIES_SIZE: Int64 = 12

public struct LwpLwSeatCapabilities {
    public let bits: UInt64

    public init(bits: UInt64) {
        this.bits = bits
    }
}

public func decodeLwpLwSeatCapabilities(body: Array<UInt8>): LwpLwSeatCapabilities {
    return LwpLwSeatCapabilities(
        lwpU64(body, 4),
    )
}

public let LWP_LW_TEXT_INPUT_ENABLE_OPCODE: UInt16 = 0
public let LWP_LW_TEXT_INPUT_ENABLE_SIZE: Int64 = 12

public struct LwpLwTextInputEnable {
    public let input_type: UInt32
    public let enter_key: UInt32

    public init(input_type: UInt32, enter_key: UInt32) {
        this.input_type = input_type
        this.enter_key = enter_key
    }
}

public func decodeLwpLwTextInputEnable(body: Array<UInt8>): LwpLwTextInputEnable {
    return LwpLwTextInputEnable(
        lwpU32(body, 4),
        lwpU32(body, 8),
    )
}

public let LWP_LW_TEXT_INPUT_DISABLE_OPCODE: UInt16 = 1
public let LWP_LW_TEXT_INPUT_DISABLE_SIZE: Int64 = 4

public struct LwpLwTextInputDisable {
    public init() {
    }
}

public func decodeLwpLwTextInputDisable(body: Array<UInt8>): LwpLwTextInputDisable {
    return LwpLwTextInputDisable()
}

public let LWP_LW_TEXT_INPUT_SET_SURROUNDING_OPCODE: UInt16 = 2
public let LWP_LW_TEXT_INPUT_SET_SURROUNDING_SIZE: Int64 = 16

public struct LwpLwTextInputSetSurrounding {
    public let text: String
    public let cursor: UInt32
    public let anchor: UInt32

    public init(text: String, cursor: UInt32, anchor: UInt32) {
        this.text = text
        this.cursor = cursor
        this.anchor = anchor
    }
}

public func decodeLwpLwTextInputSetSurrounding(body: Array<UInt8>): LwpLwTextInputSetSurrounding {
    return LwpLwTextInputSetSurrounding(
        lwpString(body, 4),
        lwpU32(body, 8),
        lwpU32(body, 12),
    )
}

public let LWP_LW_TEXT_INPUT_SET_CURSOR_RECT_OPCODE: UInt16 = 3
public let LWP_LW_TEXT_INPUT_SET_CURSOR_RECT_SIZE: Int64 = 20

public struct LwpLwTextInputSetCursorRect {
    public let x: Int32
    public let y: Int32
    public let w: Int32
    public let h: Int32

    public init(x: Int32, y: Int32, w: Int32, h: Int32) {
        this.x = x
        this.y = y
        this.w = w
        this.h = h
    }
}

public func decodeLwpLwTextInputSetCursorRect(body: Array<UInt8>): LwpLwTextInputSetCursorRect {
    return LwpLwTextInputSetCursorRect(
        lwpI32(body, 4),
        lwpI32(body, 8),
        lwpI32(body, 12),
        lwpI32(body, 16),
    )
}

public let LWP_LW_TEXT_INPUT_PREEDIT_OPCODE: UInt16 = 0
public let LWP_LW_TEXT_INPUT_PREEDIT_SIZE: Int64 = 12

public struct LwpLwTextInputPreedit {
    public let text: String
    public let cursor: UInt32

    public init(text: String, cursor: UInt32) {
        this.text = text
        this.cursor = cursor
    }
}

public func decodeLwpLwTextInputPreedit(body: Array<UInt8>): LwpLwTextInputPreedit {
    return LwpLwTextInputPreedit(
        lwpString(body, 4),
        lwpU32(body, 8),
    )
}

public let LWP_LW_TEXT_INPUT_COMMIT_STRING_OPCODE: UInt16 = 1
public let LWP_LW_TEXT_INPUT_COMMIT_STRING_SIZE: Int64 = 8

public struct LwpLwTextInputCommitString {
    public let text: String

    public init(text: String) {
        this.text = text
    }
}

public func decodeLwpLwTextInputCommitString(body: Array<UInt8>): LwpLwTextInputCommitString {
    return LwpLwTextInputCommitString(
        lwpString(body, 4),
    )
}

public let LWP_LW_TEXT_INPUT_DELETE_SURROUNDING_OPCODE: UInt16 = 2
public let LWP_LW_TEXT_INPUT_DELETE_SURROUNDING_SIZE: Int64 = 12

public struct LwpLwTextInputDeleteSurrounding {
    public let before: UInt32
    public let after: UInt32

    public init(before: UInt32, after: UInt32) {
        this.before = before
        this.after = after
    }
}

public func decodeLwpLwTextInputDeleteSurrounding(body: Array<UInt8>): LwpLwTextInputDeleteSurrounding {
    return LwpLwTextInputDeleteSurrounding(
        lwpU32(body, 4),
        lwpU32(body, 8),
    )
}

public let LWP_LW_CLIPBOARD_GET_OPCODE: UInt16 = 0
public let LWP_LW_CLIPBOARD_GET_SIZE: Int64 = 8

public struct LwpLwClipboardGet {
    public let serial: UInt32

    public init(serial: UInt32) {
        this.serial = serial
    }
}

public func decodeLwpLwClipboardGet(body: Array<UInt8>): LwpLwClipboardGet {
    return LwpLwClipboardGet(
        lwpU32(body, 4),
    )
}

public let LWP_LW_CLIPBOARD_SET_OPCODE: UInt16 = 1
public let LWP_LW_CLIPBOARD_SET_SIZE: Int64 = 12

public struct LwpLwClipboardSet {
    public let mime: String
    public let text: String

    public init(mime: String, text: String) {
        this.mime = mime
        this.text = text
    }
}

public func decodeLwpLwClipboardSet(body: Array<UInt8>): LwpLwClipboardSet {
    return LwpLwClipboardSet(
        lwpString(body, 4),
        lwpString(body, 8),
    )
}

public let LWP_LW_CLIPBOARD_TEXT_OPCODE: UInt16 = 0
public let LWP_LW_CLIPBOARD_TEXT_SIZE: Int64 = 16

public struct LwpLwClipboardText {
    public let serial: UInt32
    public let mime: String
    public let text: String

    public init(serial: UInt32, mime: String, text: String) {
        this.serial = serial
        this.mime = mime
        this.text = text
    }
}

public func decodeLwpLwClipboardText(body: Array<UInt8>): LwpLwClipboardText {
    return LwpLwClipboardText(
        lwpU32(body, 4),
        lwpString(body, 8),
        lwpString(body, 12),
    )
}

public let LWP_LW_DIALOG_OPEN_FILE_OPCODE: UInt16 = 0
public let LWP_LW_DIALOG_OPEN_FILE_SIZE: Int64 = 12

public struct LwpLwDialogOpenFile {
    public let serial: UInt32
    public let filters: String

    public init(serial: UInt32, filters: String) {
        this.serial = serial
        this.filters = filters
    }
}

public func decodeLwpLwDialogOpenFile(body: Array<UInt8>): LwpLwDialogOpenFile {
    return LwpLwDialogOpenFile(
        lwpU32(body, 4),
        lwpString(body, 8),
    )
}

public let LWP_LW_DIALOG_SAVE_FILE_OPCODE: UInt16 = 1
public let LWP_LW_DIALOG_SAVE_FILE_SIZE: Int64 = 12

public struct LwpLwDialogSaveFile {
    public let serial: UInt32
    public let suggested: String

    public init(serial: UInt32, suggested: String) {
        this.serial = serial
        this.suggested = suggested
    }
}

public func decodeLwpLwDialogSaveFile(body: Array<UInt8>): LwpLwDialogSaveFile {
    return LwpLwDialogSaveFile(
        lwpU32(body, 4),
        lwpString(body, 8),
    )
}

public let LWP_LW_DIALOG_RESULT_OPCODE: UInt16 = 0
public let LWP_LW_DIALOG_RESULT_SIZE: Int64 = 12

public struct LwpLwDialogResult {
    public let serial: UInt32
    public let path: String

    public init(serial: UInt32, path: String) {
        this.serial = serial
        this.path = path
    }
}

public func decodeLwpLwDialogResult(body: Array<UInt8>): LwpLwDialogResult {
    return LwpLwDialogResult(
        lwpU32(body, 4),
        lwpString(body, 8),
    )
}

public let LWP_LW_SYSTEM_LOG_OPCODE: UInt16 = 0
public let LWP_LW_SYSTEM_LOG_SIZE: Int64 = 9

public struct LwpLwSystemLog {
    public let level: UInt8
    public let text: String

    public init(level: UInt8, text: String) {
        this.level = level
        this.text = text
    }
}

public func decodeLwpLwSystemLog(body: Array<UInt8>): LwpLwSystemLog {
    return LwpLwSystemLog(
        lwpU8(body, 4),
        lwpString(body, 5),
    )
}

public let LWP_LW_SYSTEM_INFO_OPCODE: UInt16 = 0
public let LWP_LW_SYSTEM_INFO_SIZE: Int64 = 24

public struct LwpLwSystemInfo {
    public let timezone: String
    public let language: String
    public let font_dir: String
    public let home_dir: String
    public let api_level: UInt32

    public init(timezone: String, language: String, font_dir: String, home_dir: String, api_level: UInt32) {
        this.timezone = timezone
        this.language = language
        this.font_dir = font_dir
        this.home_dir = home_dir
        this.api_level = api_level
    }
}

public func decodeLwpLwSystemInfo(body: Array<UInt8>): LwpLwSystemInfo {
    return LwpLwSystemInfo(
        lwpString(body, 4),
        lwpString(body, 8),
        lwpString(body, 12),
        lwpString(body, 16),
        lwpU32(body, 20),
    )
}

public let LWP_LW_TEST_READY_OPCODE: UInt16 = 0
public let LWP_LW_TEST_READY_SIZE: Int64 = 8

public struct LwpLwTestReady {
    public let engine_version: UInt32

    public init(engine_version: UInt32) {
        this.engine_version = engine_version
    }
}

public func decodeLwpLwTestReady(body: Array<UInt8>): LwpLwTestReady {
    return LwpLwTestReady(
        lwpU32(body, 4),
    )
}

public let LWP_LW_TEST_REQUEST_CAPTURE_OPCODE: UInt16 = 1
public let LWP_LW_TEST_REQUEST_CAPTURE_SIZE: Int64 = 8

public struct LwpLwTestRequestCapture {
    public let path: String

    public init(path: String) {
        this.path = path
    }
}

public func decodeLwpLwTestRequestCapture(body: Array<UInt8>): LwpLwTestRequestCapture {
    return LwpLwTestRequestCapture(
        lwpString(body, 4),
    )
}

public let LWP_LW_TEST_INJECT_OPCODE: UInt16 = 0
public let LWP_LW_TEST_INJECT_SIZE: Int64 = 16

public struct LwpLwTestInject {
    public let kind: UInt32
    public let a: Int32
    public let b: Int32

    public init(kind: UInt32, a: Int32, b: Int32) {
        this.kind = kind
        this.a = a
        this.b = b
    }
}

public func decodeLwpLwTestInject(body: Array<UInt8>): LwpLwTestInject {
    return LwpLwTestInject(
        lwpU32(body, 4),
        lwpI32(body, 8),
        lwpI32(body, 12),
    )
}

public let LWP_LW_TEST_REPLAY_OPCODE: UInt16 = 1
public let LWP_LW_TEST_REPLAY_SIZE: Int64 = 8

public struct LwpLwTestReplay {
    public let path: String

    public init(path: String) {
        this.path = path
    }
}

public func decodeLwpLwTestReplay(body: Array<UInt8>): LwpLwTestReplay {
    return LwpLwTestReplay(
        lwpString(body, 4),
    )
}

public let LWP_LW_TEST_CAPTURE_OPCODE: UInt16 = 2
public let LWP_LW_TEST_CAPTURE_SIZE: Int64 = 8

public struct LwpLwTestCapture {
    public let path: String

    public init(path: String) {
        this.path = path
    }
}

public func decodeLwpLwTestCapture(body: Array<UInt8>): LwpLwTestCapture {
    return LwpLwTestCapture(
        lwpString(body, 4),
    )
}

public let LWP_LW_APP_QUIT_OPCODE: UInt16 = 0
public let LWP_LW_APP_QUIT_SIZE: Int64 = 8

public struct LwpLwAppQuit {
    public let code: Int32

    public init(code: Int32) {
        this.code = code
    }
}

public func decodeLwpLwAppQuit(body: Array<UInt8>): LwpLwAppQuit {
    return LwpLwAppQuit(
        lwpI32(body, 4),
    )
}

public let LWP_LW_APP_EXIT_OPCODE: UInt16 = 1
public let LWP_LW_APP_EXIT_SIZE: Int64 = 8

public struct LwpLwAppExit {
    public let code: Int32

    public init(code: Int32) {
        this.code = code
    }
}

public func decodeLwpLwAppExit(body: Array<UInt8>): LwpLwAppExit {
    return LwpLwAppExit(
        lwpI32(body, 4),
    )
}

public let LWP_LW_APP_STARTED_OPCODE: UInt16 = 0
public let LWP_LW_APP_STARTED_SIZE: Int64 = 8

public struct LwpLwAppStarted {
    public let app_id: UInt32

    public init(app_id: UInt32) {
        this.app_id = app_id
    }
}

public func decodeLwpLwAppStarted(body: Array<UInt8>): LwpLwAppStarted {
    return LwpLwAppStarted(
        lwpU32(body, 4),
    )
}

public let LWP_LW_APP_RESUMED_OPCODE: UInt16 = 1
public let LWP_LW_APP_RESUMED_SIZE: Int64 = 4

public struct LwpLwAppResumed {
    public init() {
    }
}

public func decodeLwpLwAppResumed(body: Array<UInt8>): LwpLwAppResumed {
    return LwpLwAppResumed()
}

public let LWP_LW_APP_PAUSED_OPCODE: UInt16 = 2
public let LWP_LW_APP_PAUSED_SIZE: Int64 = 4

public struct LwpLwAppPaused {
    public init() {
    }
}

public func decodeLwpLwAppPaused(body: Array<UInt8>): LwpLwAppPaused {
    return LwpLwAppPaused()
}

public let LWP_LW_WINDOW_CREATE_OPCODE: UInt16 = 0
public let LWP_LW_WINDOW_CREATE_SIZE: Int64 = 20

public struct LwpLwWindowCreate {
    public let title: String
    public let width: UInt32
    public let height: UInt32
    public let flags: UInt32

    public init(title: String, width: UInt32, height: UInt32, flags: UInt32) {
        this.title = title
        this.width = width
        this.height = height
        this.flags = flags
    }
}

public func decodeLwpLwWindowCreate(body: Array<UInt8>): LwpLwWindowCreate {
    return LwpLwWindowCreate(
        lwpString(body, 4),
        lwpU32(body, 8),
        lwpU32(body, 12),
        lwpU32(body, 16),
    )
}

public let LWP_LW_WINDOW_ACK_CONFIGURE_OPCODE: UInt16 = 1
public let LWP_LW_WINDOW_ACK_CONFIGURE_SIZE: Int64 = 8

public struct LwpLwWindowAckConfigure {
    public let serial: UInt32

    public init(serial: UInt32) {
        this.serial = serial
    }
}

public func decodeLwpLwWindowAckConfigure(body: Array<UInt8>): LwpLwWindowAckConfigure {
    return LwpLwWindowAckConfigure(
        lwpU32(body, 4),
    )
}

public let LWP_LW_WINDOW_SET_TITLE_OPCODE: UInt16 = 2
public let LWP_LW_WINDOW_SET_TITLE_SIZE: Int64 = 8

public struct LwpLwWindowSetTitle {
    public let title: String

    public init(title: String) {
        this.title = title
    }
}

public func decodeLwpLwWindowSetTitle(body: Array<UInt8>): LwpLwWindowSetTitle {
    return LwpLwWindowSetTitle(
        lwpString(body, 4),
    )
}

public let LWP_LW_WINDOW_SET_MIN_MAX_OPCODE: UInt16 = 3
public let LWP_LW_WINDOW_SET_MIN_MAX_SIZE: Int64 = 20

public struct LwpLwWindowSetMinMax {
    public let min_w: UInt32
    public let min_h: UInt32
    public let max_w: UInt32
    public let max_h: UInt32

    public init(min_w: UInt32, min_h: UInt32, max_w: UInt32, max_h: UInt32) {
        this.min_w = min_w
        this.min_h = min_h
        this.max_w = max_w
        this.max_h = max_h
    }
}

public func decodeLwpLwWindowSetMinMax(body: Array<UInt8>): LwpLwWindowSetMinMax {
    return LwpLwWindowSetMinMax(
        lwpU32(body, 4),
        lwpU32(body, 8),
        lwpU32(body, 12),
        lwpU32(body, 16),
    )
}

public let LWP_LW_WINDOW_SET_STATE_OPCODE: UInt16 = 4
public let LWP_LW_WINDOW_SET_STATE_SIZE: Int64 = 8

public struct LwpLwWindowSetState {
    public let state: UInt32

    public init(state: UInt32) {
        this.state = state
    }
}

public func decodeLwpLwWindowSetState(body: Array<UInt8>): LwpLwWindowSetState {
    return LwpLwWindowSetState(
        lwpU32(body, 4),
    )
}

public let LWP_LW_WINDOW_CLOSE_OPCODE: UInt16 = 5
public let LWP_LW_WINDOW_CLOSE_SIZE: Int64 = 4

public struct LwpLwWindowClose {
    public init() {
    }
}

public func decodeLwpLwWindowClose(body: Array<UInt8>): LwpLwWindowClose {
    return LwpLwWindowClose()
}

public let LWP_LW_WINDOW_BEGIN_MOVE_OPCODE: UInt16 = 6
public let LWP_LW_WINDOW_BEGIN_MOVE_SIZE: Int64 = 4

public struct LwpLwWindowBeginMove {
    public init() {
    }
}

public func decodeLwpLwWindowBeginMove(body: Array<UInt8>): LwpLwWindowBeginMove {
    return LwpLwWindowBeginMove()
}

public let LWP_LW_WINDOW_BEGIN_RESIZE_OPCODE: UInt16 = 7
public let LWP_LW_WINDOW_BEGIN_RESIZE_SIZE: Int64 = 8

public struct LwpLwWindowBeginResize {
    public let edges: UInt32

    public init(edges: UInt32) {
        this.edges = edges
    }
}

public func decodeLwpLwWindowBeginResize(body: Array<UInt8>): LwpLwWindowBeginResize {
    return LwpLwWindowBeginResize(
        lwpU32(body, 4),
    )
}

public let LWP_LW_WINDOW_SET_TITLE_BUTTONS_OPCODE: UInt16 = 8
public let LWP_LW_WINDOW_SET_TITLE_BUTTONS_SIZE: Int64 = 28

public struct LwpLwWindowSetTitleButtons {
    public let visible: UInt32
    public let side: UInt32
    public let close_margin: UInt32
    public let spacing: UInt32
    public let button_size: UInt32
    public let color_mode: UInt32

    public init(visible: UInt32, side: UInt32, close_margin: UInt32, spacing: UInt32, button_size: UInt32, color_mode: UInt32) {
        this.visible = visible
        this.side = side
        this.close_margin = close_margin
        this.spacing = spacing
        this.button_size = button_size
        this.color_mode = color_mode
    }
}

public func decodeLwpLwWindowSetTitleButtons(body: Array<UInt8>): LwpLwWindowSetTitleButtons {
    return LwpLwWindowSetTitleButtons(
        lwpU32(body, 4),
        lwpU32(body, 8),
        lwpU32(body, 12),
        lwpU32(body, 16),
        lwpU32(body, 20),
        lwpU32(body, 24),
    )
}

public let LWP_LW_WINDOW_CREATED_OPCODE: UInt16 = 0
public let LWP_LW_WINDOW_CREATED_SIZE: Int64 = 13

public struct LwpLwWindowCreated {
    public let window_id: UInt32
    public let scale: Float32
    public let server_side_decorations: Bool

    public init(window_id: UInt32, scale: Float32, server_side_decorations: Bool) {
        this.window_id = window_id
        this.scale = scale
        this.server_side_decorations = server_side_decorations
    }
}

public func decodeLwpLwWindowCreated(body: Array<UInt8>): LwpLwWindowCreated {
    return LwpLwWindowCreated(
        lwpU32(body, 4),
        lwpF32(body, 8),
        lwpBool(body, 12),
    )
}

public let LWP_LW_WINDOW_CONFIGURE_OPCODE: UInt16 = 1
public let LWP_LW_WINDOW_CONFIGURE_SIZE: Int64 = 16

public struct LwpLwWindowConfigure {
    public let width: UInt32
    public let height: UInt32
    public let state: UInt32

    public init(width: UInt32, height: UInt32, state: UInt32) {
        this.width = width
        this.height = height
        this.state = state
    }
}

public func decodeLwpLwWindowConfigure(body: Array<UInt8>): LwpLwWindowConfigure {
    return LwpLwWindowConfigure(
        lwpU32(body, 4),
        lwpU32(body, 8),
        lwpU32(body, 12),
    )
}

public let LWP_LW_WINDOW_CLOSE_REQUEST_OPCODE: UInt16 = 2
public let LWP_LW_WINDOW_CLOSE_REQUEST_SIZE: Int64 = 4

public struct LwpLwWindowCloseRequest {
    public init() {
    }
}

public func decodeLwpLwWindowCloseRequest(body: Array<UInt8>): LwpLwWindowCloseRequest {
    return LwpLwWindowCloseRequest()
}

public let LWP_LW_WINDOW_FOCUS_OPCODE: UInt16 = 3
public let LWP_LW_WINDOW_FOCUS_SIZE: Int64 = 5

public struct LwpLwWindowFocus {
    public let focused: Bool

    public init(focused: Bool) {
        this.focused = focused
    }
}

public func decodeLwpLwWindowFocus(body: Array<UInt8>): LwpLwWindowFocus {
    return LwpLwWindowFocus(
        lwpBool(body, 4),
    )
}

public let LWP_LW_WINDOW_DRAG_ENTER_OPCODE: UInt16 = 4
public let LWP_LW_WINDOW_DRAG_ENTER_SIZE: Int64 = 16

public struct LwpLwWindowDragEnter {
    public let x: UInt32
    public let y: UInt32
    public let uris: String

    public init(x: UInt32, y: UInt32, uris: String) {
        this.x = x
        this.y = y
        this.uris = uris
    }
}

public func decodeLwpLwWindowDragEnter(body: Array<UInt8>): LwpLwWindowDragEnter {
    return LwpLwWindowDragEnter(
        lwpU32(body, 4),
        lwpU32(body, 8),
        lwpString(body, 12),
    )
}

public let LWP_LW_WINDOW_DRAG_MOTION_OPCODE: UInt16 = 5
public let LWP_LW_WINDOW_DRAG_MOTION_SIZE: Int64 = 12

public struct LwpLwWindowDragMotion {
    public let x: UInt32
    public let y: UInt32

    public init(x: UInt32, y: UInt32) {
        this.x = x
        this.y = y
    }
}

public func decodeLwpLwWindowDragMotion(body: Array<UInt8>): LwpLwWindowDragMotion {
    return LwpLwWindowDragMotion(
        lwpU32(body, 4),
        lwpU32(body, 8),
    )
}

public let LWP_LW_WINDOW_DRAG_LEAVE_OPCODE: UInt16 = 6
public let LWP_LW_WINDOW_DRAG_LEAVE_SIZE: Int64 = 4

public struct LwpLwWindowDragLeave {
    public init() {
    }
}

public func decodeLwpLwWindowDragLeave(body: Array<UInt8>): LwpLwWindowDragLeave {
    return LwpLwWindowDragLeave()
}

public let LWP_LW_WINDOW_DROP_OPCODE: UInt16 = 7
public let LWP_LW_WINDOW_DROP_SIZE: Int64 = 16

public struct LwpLwWindowDrop {
    public let x: UInt32
    public let y: UInt32
    public let uris: String

    public init(x: UInt32, y: UInt32, uris: String) {
        this.x = x
        this.y = y
        this.uris = uris
    }
}

public func decodeLwpLwWindowDrop(body: Array<UInt8>): LwpLwWindowDrop {
    return LwpLwWindowDrop(
        lwpU32(body, 4),
        lwpU32(body, 8),
        lwpString(body, 12),
    )
}

public let LWP_LW_WINDOW_TITLE_BUTTONS_RECT_OPCODE: UInt16 = 8
public let LWP_LW_WINDOW_TITLE_BUTTONS_RECT_SIZE: Int64 = 21

public struct LwpLwWindowTitleButtonsRect {
    public let right: Int32
    public let top: Int32
    public let width: UInt32
    public let height: UInt32
    public let visible: Bool

    public init(right: Int32, top: Int32, width: UInt32, height: UInt32, visible: Bool) {
        this.right = right
        this.top = top
        this.width = width
        this.height = height
        this.visible = visible
    }
}

public func decodeLwpLwWindowTitleButtonsRect(body: Array<UInt8>): LwpLwWindowTitleButtonsRect {
    return LwpLwWindowTitleButtonsRect(
        lwpI32(body, 4),
        lwpI32(body, 8),
        lwpU32(body, 12),
        lwpU32(body, 16),
        lwpBool(body, 20),
    )
}

public let LWP_LW_SURFACE_ATTACH_OPCODE: UInt16 = 0
public let LWP_LW_SURFACE_ATTACH_SIZE: Int64 = 24

public struct LwpLwSurfaceAttach {
    public let buffer: UInt64
    public let width: UInt32
    public let height: UInt32
    public let serial: UInt32

    public init(buffer: UInt64, width: UInt32, height: UInt32, serial: UInt32) {
        this.buffer = buffer
        this.width = width
        this.height = height
        this.serial = serial
    }
}

public func decodeLwpLwSurfaceAttach(body: Array<UInt8>): LwpLwSurfaceAttach {
    return LwpLwSurfaceAttach(
        lwpU64(body, 4),
        lwpU32(body, 12),
        lwpU32(body, 16),
        lwpU32(body, 20),
    )
}

public let LWP_LW_SURFACE_FRAME_DONE_OPCODE: UInt16 = 0
public let LWP_LW_SURFACE_FRAME_DONE_SIZE: Int64 = 16

public struct LwpLwSurfaceFrameDone {
    public let serial: UInt32
    public let time_ns: UInt64

    public init(serial: UInt32, time_ns: UInt64) {
        this.serial = serial
        this.time_ns = time_ns
    }
}

public func decodeLwpLwSurfaceFrameDone(body: Array<UInt8>): LwpLwSurfaceFrameDone {
    return LwpLwSurfaceFrameDone(
        lwpU32(body, 4),
        lwpU64(body, 8),
    )
}

public let LWP_LW_SURFACE_AVAILABLE_OPCODE: UInt16 = 1
public let LWP_LW_SURFACE_AVAILABLE_SIZE: Int64 = 20

public struct LwpLwSurfaceAvailable {
    public let handle: UInt64
    public let width: UInt32
    public let height: UInt32

    public init(handle: UInt64, width: UInt32, height: UInt32) {
        this.handle = handle
        this.width = width
        this.height = height
    }
}

public func decodeLwpLwSurfaceAvailable(body: Array<UInt8>): LwpLwSurfaceAvailable {
    return LwpLwSurfaceAvailable(
        lwpU64(body, 4),
        lwpU32(body, 12),
        lwpU32(body, 16),
    )
}

public let LWP_LW_SURFACE_CHANGED_OPCODE: UInt16 = 2
public let LWP_LW_SURFACE_CHANGED_SIZE: Int64 = 12

public struct LwpLwSurfaceChanged {
    public let width: UInt32
    public let height: UInt32

    public init(width: UInt32, height: UInt32) {
        this.width = width
        this.height = height
    }
}

public func decodeLwpLwSurfaceChanged(body: Array<UInt8>): LwpLwSurfaceChanged {
    return LwpLwSurfaceChanged(
        lwpU32(body, 4),
        lwpU32(body, 8),
    )
}

public let LWP_LW_SURFACE_WILL_DESTROY_OPCODE: UInt16 = 3
public let LWP_LW_SURFACE_WILL_DESTROY_SIZE: Int64 = 4

public struct LwpLwSurfaceWillDestroy {
    public init() {
    }
}

public func decodeLwpLwSurfaceWillDestroy(body: Array<UInt8>): LwpLwSurfaceWillDestroy {
    return LwpLwSurfaceWillDestroy()
}

public let LWP_LW_SURFACE_HIDDEN_OPCODE: UInt16 = 4
public let LWP_LW_SURFACE_HIDDEN_SIZE: Int64 = 4

public struct LwpLwSurfaceHidden {
    public init() {
    }
}

public func decodeLwpLwSurfaceHidden(body: Array<UInt8>): LwpLwSurfaceHidden {
    return LwpLwSurfaceHidden()
}

public let LWP_LW_FRAME_REQUEST_OPCODE: UInt16 = 0
public let LWP_LW_FRAME_REQUEST_SIZE: Int64 = 8

public struct LwpLwFrameRequest {
    public let serial: UInt32

    public init(serial: UInt32) {
        this.serial = serial
    }
}

public func decodeLwpLwFrameRequest(body: Array<UInt8>): LwpLwFrameRequest {
    return LwpLwFrameRequest(
        lwpU32(body, 4),
    )
}

public let LWP_LW_FRAME_DONE_OPCODE: UInt16 = 0
public let LWP_LW_FRAME_DONE_SIZE: Int64 = 16

public struct LwpLwFrameDone {
    public let serial: UInt32
    public let time_ns: UInt64

    public init(serial: UInt32, time_ns: UInt64) {
        this.serial = serial
        this.time_ns = time_ns
    }
}

public func decodeLwpLwFrameDone(body: Array<UInt8>): LwpLwFrameDone {
    return LwpLwFrameDone(
        lwpU32(body, 4),
        lwpU64(body, 8),
    )
}

public let LWP_LW_DISPLAY_INFO_OPCODE: UInt16 = 0
public let LWP_LW_DISPLAY_INFO_SIZE: Int64 = 28

public struct LwpLwDisplayInfo {
    public let width: UInt32
    public let height: UInt32
    public let scale: Float32
    public let refresh_mhz: UInt32
    public let inset_top: UInt32
    public let inset_bottom: UInt32

    public init(width: UInt32, height: UInt32, scale: Float32, refresh_mhz: UInt32, inset_top: UInt32, inset_bottom: UInt32) {
        this.width = width
        this.height = height
        this.scale = scale
        this.refresh_mhz = refresh_mhz
        this.inset_top = inset_top
        this.inset_bottom = inset_bottom
    }
}

public func decodeLwpLwDisplayInfo(body: Array<UInt8>): LwpLwDisplayInfo {
    return LwpLwDisplayInfo(
        lwpU32(body, 4),
        lwpU32(body, 8),
        lwpF32(body, 12),
        lwpU32(body, 16),
        lwpU32(body, 20),
        lwpU32(body, 24),
    )
}

// ── 字节读取（小端）──────────────────────────────────────────────────────────
func lwpU8(body: Array<UInt8>, off: Int64): UInt8 { body[off] }
func lwpU16(body: Array<UInt8>, off: Int64): UInt16 {
    UInt16(body[off]) | (UInt16(body[off + 1]) << 8)
}
func lwpU32(body: Array<UInt8>, off: Int64): UInt32 {
    UInt32(body[off]) | (UInt32(body[off + 1]) << 8) | (UInt32(body[off + 2]) << 16) | (UInt32(body[off + 3]) << 24)
}
func lwpU64(body: Array<UInt8>, off: Int64): UInt64 {
    UInt64(lwpU32(body, off)) | (UInt64(lwpU32(body, off + 4)) << 32)
}
func lwpI32(body: Array<UInt8>, off: Int64): Int32 { Int32(lwpU32(body, off)) }
func lwpF32(body: Array<UInt8>, off: Int64): Float32 { Float32(lwpU32(body, off)) }
func lwpBool(body: Array<UInt8>, off: Int64): Bool { body[off] != 0 }
// string：u16 off + u16 len，off 相对消息体起点
// 越界或非法 UTF-8 一律返回空串——坏消息不能把解码方打崩（协议检查器约定）。
func lwpString(body: Array<UInt8>, off: Int64): String {
    let so = Int64(lwpU16(body, off))
    let sl = Int64(lwpU16(body, off + 2))
    if (sl <= 0 || so + sl > body.size) { return "" }
    try {
        String.fromUtf8(body[so..so + sl])
    } catch (_) {
        ""
    }
}

