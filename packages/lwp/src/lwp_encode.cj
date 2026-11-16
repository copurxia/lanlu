package lwp

// lw_input 接口的编码器（手写；与 gen/lwp_gen_protocol.cj 的解码一一对应）。
// 约定与 IDL 一致：消息体首字段 uint32 size；packed 小端；string = (u16 off, u16 len)，
// off 相对消息体起点（含 size 字段）。
//
// 发送方（壳）用这些函数组包；高频 motion 由调用方加 LWP_FLAG_DROPPABLE 并自行限流。

func u16le(v: UInt16, b: Array<UInt8>, off: Int64): Unit {
    b[off] = UInt8(v & 0xFF)
    b[off + 1] = UInt8((v >> 8) & 0xFF)
}

func u32le(v: UInt32, b: Array<UInt8>, off: Int64): Unit {
    b[off] = UInt8(v & 0xFF)
    b[off + 1] = UInt8((v >> 8) & 0xFF)
    b[off + 2] = UInt8((v >> 16) & 0xFF)
    b[off + 3] = UInt8((v >> 24) & 0xFF)
}

// f32 必须按 IEEE-754 位模式写入（UInt32(v) 是数值转换会截断且与 C 侧不一致）
func f32le(v: Float32, b: Array<UInt8>, off: Int64): Unit {
    unsafe {
        let h = acquireArrayRawData(b)
        CPointer<Float32>(CPointer<UInt8>(h.pointer) + off).write(v)
        releaseArrayRawData(h)
    }
}

/// pointer_motion：size(4) + x(4) + y(4) = 12
public func encodeLwInputPointerMotion(x: Float32, y: Float32): Array<UInt8> {
    var b = Array<UInt8>(LWP_LW_INPUT_POINTER_MOTION_SIZE, repeat: 0)
    u32le(UInt32(LWP_LW_INPUT_POINTER_MOTION_SIZE), b, 0)
    f32le(x, b, 4)
    f32le(y, b, 8)
    b
}

/// pointer_button：size(4) + x(4) + y(4) + button(1) + down(1) = 14
public func encodeLwInputPointerButton(x: Float32, y: Float32, button: UInt8, down: Bool): Array<UInt8> {
    var b = Array<UInt8>(LWP_LW_INPUT_POINTER_BUTTON_SIZE, repeat: 0)
    u32le(UInt32(LWP_LW_INPUT_POINTER_BUTTON_SIZE), b, 0)
    f32le(x, b, 4)
    f32le(y, b, 8)
    b[12] = button
    b[13] = if (down) { 1 } else { 0 }
    b
}

/// pointer_axis：size(4) + dx(4) + dy(4) = 12
public func encodeLwInputPointerAxis(dx: Float32, dy: Float32): Array<UInt8> {
    var b = Array<UInt8>(LWP_LW_INPUT_POINTER_AXIS_SIZE, repeat: 0)
    u32le(UInt32(LWP_LW_INPUT_POINTER_AXIS_SIZE), b, 0)
    f32le(dx, b, 4)
    f32le(dy, b, 8)
    b
}

/// key：size(4) + keycode(4) + down(1) = 9
public func encodeLwInputKey(keycode: UInt32, down: Bool): Array<UInt8> {
    var b = Array<UInt8>(LWP_LW_INPUT_KEY_SIZE, repeat: 0)
    u32le(UInt32(LWP_LW_INPUT_KEY_SIZE), b, 0)
    u32le(keycode, b, 4)
    b[8] = if (down) { 1 } else { 0 }
    b
}

/// text_input：size(4) + string(4) + utf8 = 8 + n；off 相对消息体起点 = 8
public func encodeLwInputTextInput(text: String): Array<UInt8> {
    let utf8 = text.toArray()
    let n = utf8.size
    var b = Array<UInt8>(LWP_LW_INPUT_TEXT_INPUT_SIZE + n, repeat: 0)
    u32le(UInt32(LWP_LW_INPUT_TEXT_INPUT_SIZE + n), b, 0)
    u16le(UInt16(LWP_LW_INPUT_TEXT_INPUT_SIZE), b, 4)
    u16le(UInt16(n), b, 6)
    for (i in 0..n) {
        b[LWP_LW_INPUT_TEXT_INPUT_SIZE + i] = utf8[i]
    }
    b
}

// ── 窗口/应用/表面/帧 ───────────────────────────────────────────────────────
// 大端小端同前：packed 小端；string = (u16 off, u16 len) 相对消息体起点。

func strField(b: Array<UInt8>, off: Int64, text: String): Int64 {
    // 在 off 处写 string 头，返回追加后的总长度（off + 4 + len）
    let utf8 = text.toArray()
    u16le(UInt16(off + 4), b, off)      // off 指向文本本体
    u16le(UInt16(utf8.size), b, off + 2)
    for (i in 0..utf8.size) {
        b[off + 4 + i] = utf8[i]
    }
    off + 4 + Int64(utf8.size)
}

/// window.create：size(4) + title(str) + w(4) + h(4) + flags(4)
public func encodeLwWindowCreate(title: String, width: UInt32, height: UInt32, flags: UInt32): Array<UInt8> {
    let t = title.toArray()
    let total = LWP_LW_WINDOW_CREATE_SIZE + Int64(t.size)
    var b = Array<UInt8>(total, repeat: 0)
    u32le(UInt32(total), b, 0)
    // title 头在 4，文本从 8 开始 => off=8
    u16le(8, b, 4)
    u16le(UInt16(t.size), b, 6)
    for (i in 0..t.size) { b[8 + i] = t[i] }
    let base = 8 + Int64(t.size)
    u32le(width, b, base)
    u32le(height, b, base + 4)
    u32le(flags, b, base + 8)
    b
}

/// window.ack_configure：size(4) + serial(4) = 8
public func encodeLwWindowAckConfigure(serial: UInt32): Array<UInt8> {
    var b = Array<UInt8>(8, repeat: 0)
    u32le(8, b, 0)
    u32le(serial, b, 4)
    b
}

/// window.set_title：size(4) + title(str)
public func encodeLwWindowSetTitle(title: String): Array<UInt8> {
    let t = title.toArray()
    let total = 8 + Int64(t.size)
    var b = Array<UInt8>(total, repeat: 0)
    u32le(UInt32(total), b, 0)
    u16le(8, b, 4)
    u16le(UInt16(t.size), b, 6)
    for (i in 0..t.size) { b[8 + i] = t[i] }
    b
}

/// window.set_min_max：size(4) + 4×u32 = 20
public func encodeLwWindowSetMinMax(minW: UInt32, minH: UInt32, maxW: UInt32, maxH: UInt32): Array<UInt8> {
    var b = Array<UInt8>(20, repeat: 0)
    u32le(20, b, 0)
    u32le(minW, b, 4)
    u32le(minH, b, 8)
    u32le(maxW, b, 12)
    u32le(maxH, b, 16)
    b
}

/// frame.request：size(4) + serial(4) = 8
public func encodeLwFrameRequest(serial: UInt32): Array<UInt8> {
    var b = Array<UInt8>(8, repeat: 0)
    u32le(8, b, 0)
    u32le(serial, b, 4)
    b
}

/// surface.attach：size(4) + buffer(8) + w(4) + h(4) + serial(4) = 24
public func encodeLwSurfaceAttach(buffer: UInt64, width: UInt32, height: UInt32, serial: UInt32): Array<UInt8> {
    var b = Array<UInt8>(LWP_LW_SURFACE_ATTACH_SIZE, repeat: 0)
    u32le(UInt32(LWP_LW_SURFACE_ATTACH_SIZE), b, 0)
    u32le(UInt32(buffer & 0xFFFFFFFF), b, 4)
    u32le(UInt32((buffer >> 32) & 0xFFFFFFFF), b, 8)
    u32le(width, b, 12)
    u32le(height, b, 16)
    u32le(serial, b, 20)
    b
}

/// test.ready：size(4) + engine_version(4) = 8
public func encodeLwTestReady(engineVersion: UInt32): Array<UInt8> {
    var b = Array<UInt8>(8, repeat: 0)
    u32le(8, b, 0)
    u32le(engineVersion, b, 4)
    b
}

// ── 剪贴板 / 对话框（计划 §8）───────────────────────────────────────────────

/// clipboard.set：size(4) + mime(str) + text(str)
public func encodeLwClipboardSet(mime: String, text: String): Array<UInt8> {
    let m = mime.toArray()
    let t = text.toArray()
    let total = 4 + 4 + 4 + m.size + t.size
    var b = Array<UInt8>(total, repeat: 0)
    u32le(UInt32(total), b, 0)
    // 头：mime @4、text @8；载荷从 12 开始（off 相对消息体起点）
    u16le(12, b, 4)
    u16le(UInt16(m.size), b, 6)
    u16le(UInt16(12 + m.size), b, 8)
    u16le(UInt16(t.size), b, 10)
    for (i in 0..m.size) { b[12 + i] = m[i] }
    for (i in 0..t.size) { b[12 + m.size + i] = t[i] }
    b
}

/// clipboard.get：size(4) + serial(4) = 8
public func encodeLwClipboardGet(serial: UInt32): Array<UInt8> {
    var b = Array<UInt8>(8, repeat: 0)
    u32le(8, b, 0)
    u32le(serial, b, 4)
    b
}

/// dialog.open_file：size(4) + serial(4) + filters(str)
public func encodeLwDialogOpenFile(serial: UInt32, filters: String): Array<UInt8> {
    let f = filters.toArray()
    let total = 8 + 4 + f.size
    var b = Array<UInt8>(total, repeat: 0)
    u32le(UInt32(total), b, 0)
    u32le(serial, b, 4)
    u16le(UInt16(total - f.size), b, 8)
    u16le(UInt16(f.size), b, 10)
    for (i in 0..f.size) { b[total - f.size + i] = f[i] }
    b
}

/// dialog.save_file：size(4) + serial(4) + suggested(str)
public func encodeLwDialogSaveFile(serial: UInt32, suggested: String): Array<UInt8> {
    let s = suggested.toArray()
    let total = 8 + 4 + s.size
    var b = Array<UInt8>(total, repeat: 0)
    u32le(UInt32(total), b, 0)
    u32le(serial, b, 4)
    u16le(UInt16(total - s.size), b, 8)
    u16le(UInt16(s.size), b, 10)
    for (i in 0..s.size) { b[total - s.size + i] = s[i] }
    b
}

// ── 日志 ────────────────────────────────────────────────────────────────────

/// system.log：size(4) + level(1) + text(str) = 9 + n
public func encodeLwSystemLog(level: UInt8, text: String): Array<UInt8> {
    let t = text.toArray()
    let total = 9 + t.size
    var b = Array<UInt8>(total, repeat: 0)
    u32le(UInt32(total), b, 0)
    b[4] = level
    // text 头 @5（未对齐也没关系：字段是 packed 的）
    u16le(9, b, 5)
    u16le(UInt16(t.size), b, 7)
    for (i in 0..t.size) { b[9 + i] = t[i] }
    b
}

// ── 窗口状态请求（计划 §7.4）───────────────────────────────────────────────

/// window.set_state：size(4) + state(4) = 8
public func encodeLwWindowSetState(state: UInt32): Array<UInt8> {
    var b = Array<UInt8>(LWP_LW_WINDOW_SET_STATE_SIZE, repeat: 0)
    u32le(UInt32(LWP_LW_WINDOW_SET_STATE_SIZE), b, 0)
    u32le(state, b, 4)
    b
}

/// window.close：size(4)
public func encodeLwWindowClose(): Array<UInt8> {
    var b = Array<UInt8>(4, repeat: 0)
    u32le(4, b, 0)
    b
}

/// window.set_title_buttons：size(4) + visible(4) + side(4) + close_margin(4)
///                         + spacing(4) + button_size(4) + color_mode(4) = 28
/// 三键平台化（docs/lwindow-title-buttons-plan.md）：引擎只表达"想要什么"，
/// 壳按平台能力 clamp / 忽略；实际生效矩形以 title_buttons_rect 事件为准。
public func encodeLwWindowSetTitleButtons(visible: UInt32, side: UInt32, closeMargin: UInt32,
    spacing: UInt32, buttonSize: UInt32, colorMode: UInt32): Array<UInt8> {
    var b = Array<UInt8>(LWP_LW_WINDOW_SET_TITLE_BUTTONS_SIZE, repeat: 0)
    u32le(UInt32(LWP_LW_WINDOW_SET_TITLE_BUTTONS_SIZE), b, 0)
    u32le(visible, b, 4)
    u32le(side, b, 8)
    u32le(closeMargin, b, 12)
    u32le(spacing, b, 16)
    u32le(buttonSize, b, 20)
    u32le(colorMode, b, 24)
    b
}

/// app.exit：size(4) + code(4) = 8
public func encodeLwAppExit(code: Int32): Array<UInt8> {
    var b = Array<UInt8>(LWP_LW_APP_EXIT_SIZE, repeat: 0)
    u32le(UInt32(LWP_LW_APP_EXIT_SIZE), b, 0)
    u32le(UInt32(code), b, 4)
    b
}

/// test.request_capture：size(4) + path(str) = 8 + n（引擎 -> 壳 请求壳抓帧）
/// 注意与 event 方向的 `capture`（壳 -> 引擎）区分：opcode 各自独立编号。
public func encodeLwTestCapture(path: String): Array<UInt8> {
    let t = path.toArray()
    let total = 8 + t.size
    var b = Array<UInt8>(total, repeat: 0)
    u32le(UInt32(total), b, 0)
    u16le(8, b, 4)
    u16le(UInt16(t.size), b, 6)
    for (i in 0..t.size) { b[8 + i] = t[i] }
    b
}

// ── IME（lw_text_input，text-input-v3 的子集；计划 §6.4）─────────────────────

/// text_input.enable / disable：只有 size
public func encodeLwTextInputToggle(): Array<UInt8> {
    var b = Array<UInt8>(4, repeat: 0)
    u32le(4, b, 0)
    b
}

/// text_input.enable（since=2）：size(4) + input_type(4) + enter_key(4) = 12
public func encodeLwTextInputEnable(inputType: UInt32, enterKey: UInt32): Array<UInt8> {
    var b = Array<UInt8>(LWP_LW_TEXT_INPUT_ENABLE_SIZE, repeat: 0)
    u32le(UInt32(LWP_LW_TEXT_INPUT_ENABLE_SIZE), b, 0)
    u32le(inputType, b, 4)
    u32le(enterKey, b, 8)
    b
}

/// text_input.set_surrounding：size(4) + text(str) + cursor(4) + anchor(4)
public func encodeLwTextInputSetSurrounding(text: String, cursor: UInt32, anchor: UInt32): Array<UInt8> {
    let t = text.toArray()
    let total = 16 + t.size
    var b = Array<UInt8>(total, repeat: 0)
    u32le(UInt32(total), b, 0)
    u16le(16, b, 4)                 // text 载荷从 16 开始（16 = size+text头+cursor+anchor）
    u16le(UInt16(t.size), b, 6)
    for (i in 0..t.size) { b[16 + i] = t[i] }
    // 定长头之后才是文本载荷：cursor@8、anchor@12，文本从 16 开始
    u32le(cursor, b, 8)
    u32le(anchor, b, 12)
    b
}

/// text_input.set_cursor_rect：size(4) + x,y,w,h (i32×4) = 20
public func encodeLwTextInputCursorRect(x: Int32, y: Int32, w: Int32, h: Int32): Array<UInt8> {
    var b = Array<UInt8>(20, repeat: 0)
    u32le(20, b, 0)
    u32le(UInt32(x), b, 4)
    u32le(UInt32(y), b, 8)
    u32le(UInt32(w), b, 12)
    u32le(UInt32(h), b, 16)
    b
}

/// lw_seat.set_cursor：8 字节（size + shape）。
public func encodeLwSeatSetCursor(shape: UInt32): Array<UInt8> {
    var b = Array<UInt8>(LWP_LW_SEAT_SET_CURSOR_SIZE, repeat: 0)
    u32le(UInt32(LWP_LW_SEAT_SET_CURSOR_SIZE), b, 0)
    u32le(shape, b, 4)
    b
}

/// window.begin_move：size(4)
public func encodeLwWindowBeginMove(): Array<UInt8> {
    var b = Array<UInt8>(LWP_LW_WINDOW_BEGIN_MOVE_SIZE, repeat: 0)
    u32le(UInt32(LWP_LW_WINDOW_BEGIN_MOVE_SIZE), b, 0)
    b
}

/// window.begin_resize：size(4) + edges(4)
public func encodeLwWindowBeginResize(edges: UInt32): Array<UInt8> {
    var b = Array<UInt8>(LWP_LW_WINDOW_BEGIN_RESIZE_SIZE, repeat: 0)
    u32le(UInt32(LWP_LW_WINDOW_BEGIN_RESIZE_SIZE), b, 0)
    u32le(edges, b, 4)
    b
}

/// key（since=2）：size(4)+keycode(4)+down(1)+utf8(string)+modifiers(u16)
public func encodeLwInputKeyText(keycode: UInt32, down: Bool, text: String, modifiers: UInt16): Array<UInt8> {
    let t = text.toArray()
    let total = LWP_LW_INPUT_KEY_SIZE + t.size
    var b = Array<UInt8>(total, repeat: 0)
    u32le(UInt32(total), b, 0)
    u32le(keycode, b, 4)
    b[8] = if (down) { 1 } else { 0 }
    u16le(UInt16(LWP_LW_INPUT_KEY_SIZE), b, 9)
    u16le(UInt16(t.size), b, 11)
    u16le(modifiers, b, 13)
    for (i in 0..t.size) { b[LWP_LW_INPUT_KEY_SIZE + i] = t[i] }
    b
}

/// text_input.preedit（壳 -> 引擎，since=1）：size(4)+text(string)+cursor(u32)
public func encodeLwTextInputPreedit(text: String, cursor: UInt32): Array<UInt8> {
    let t = text.toArray()
    let total = LWP_LW_TEXT_INPUT_PREEDIT_SIZE + t.size
    var b = Array<UInt8>(total, repeat: 0)
    u32le(UInt32(total), b, 0)
    u16le(UInt16(LWP_LW_TEXT_INPUT_PREEDIT_SIZE), b, 4)
    u16le(UInt16(t.size), b, 6)
    u32le(cursor, b, 8)
    for (i in 0..t.size) { b[LWP_LW_TEXT_INPUT_PREEDIT_SIZE + i] = t[i] }
    b
}

/// text_input.commit_string（壳 -> 引擎，since=2）：size(4)+text(string)
public func encodeLwTextInputCommitString(text: String): Array<UInt8> {
    let t = text.toArray()
    let total = LWP_LW_TEXT_INPUT_COMMIT_STRING_SIZE + t.size
    var b = Array<UInt8>(total, repeat: 0)
    u32le(UInt32(total), b, 0)
    u16le(UInt16(LWP_LW_TEXT_INPUT_COMMIT_STRING_SIZE), b, 4)
    u16le(UInt16(t.size), b, 6)
    for (i in 0..t.size) { b[LWP_LW_TEXT_INPUT_COMMIT_STRING_SIZE + i] = t[i] }
    b
}

/// text_input.delete_surrounding（壳 -> 引擎，since=2）：size(4)+before(4)+after(4)
public func encodeLwTextInputDeleteSurrounding(before: UInt32, after: UInt32): Array<UInt8> {
    var b = Array<UInt8>(LWP_LW_TEXT_INPUT_DELETE_SURROUNDING_SIZE, repeat: 0)
    u32le(UInt32(LWP_LW_TEXT_INPUT_DELETE_SURROUNDING_SIZE), b, 0)
    u32le(before, b, 4)
    u32le(after, b, 8)
    b
}
