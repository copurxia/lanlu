package lwindow

// backend.headless：内存通道上的假壳。计划 §9.5、§16.3。
//
// 用途：不启动真壳，就能测「壳 -> 通道 -> 漏斗 -> LWindowEvent」全链路；
// 也是 lwtrace 回放（M1 后续）与 M0-6 输入回放基线的载体——回放就是把录制文件里
// 的壳侧消息重放进同一个通道。

import lwp.*

/// 假壳默认宣告的能力位（与真壳 lwp_client.cpp 一致）
public let HEADLESS_DEFAULT_CAPS: UInt64 =
    LWP_CORE_CAPABILITIES_SERVER_SIDE_DECORATIONS |
    LWP_CORE_CAPABILITIES_CURSOR_SHAPES |
    LWP_CORE_CAPABILITIES_IME_PREEDIT |
    LWP_CORE_CAPABILITIES_SOFT_KEYBOARD |
    LWP_CORE_CAPABILITIES_FILE_DIALOG_SAVE |
    LWP_CORE_CAPABILITIES_CLIPBOARD_READ_ASYNC

public class HeadlessShell {
    private let ch: LwpChannel
    private var seq: UInt32 = 0

    public init(name!: String = "headless", slots!: UInt32 = 64) {
        ch = LwpChannel.open(name, slots: slots)
    }

    /// 与真壳一致：先握手，再发业务事件。
    /// 默认宣告的能力位与 `lplatform-ohos` 的 `lwp_client.cpp` 保持一致；
    /// 测试要验证降级路径时传入更小的集合。
    public func handshake(capabilities!: UInt64 = HEADLESS_DEFAULT_CAPS): Unit {
        let _ = ch.send(LWP_EVENT, LWP_IFACE_LW_CORE, LWP_LW_CORE_HELLO_OPCODE,
            encodeHelloBody(capabilities))
    }

    public func pointerMotion(x: Float32, y: Float32): Unit {
        seq = seq + 1
        // 高频事件标 DROPPABLE（对齐真壳行为）
        let _ = ch.send(LWP_EVENT, LWP_IFACE_LW_INPUT, LWP_LW_INPUT_POINTER_MOTION_OPCODE,
            encodeLwInputPointerMotion(x, y), flags: LWP_FLAG_DROPPABLE)
    }

    public func pointerButton(x: Float32, y: Float32, button: UInt8, down: Bool): Unit {
        seq = seq + 1
        let _ = ch.send(LWP_EVENT, LWP_IFACE_LW_INPUT, LWP_LW_INPUT_POINTER_BUTTON_OPCODE,
            encodeLwInputPointerButton(x, y, button, down))
    }

    public func pointerAxis(dx: Float32, dy: Float32): Unit {
        seq = seq + 1
        let _ = ch.send(LWP_EVENT, LWP_IFACE_LW_INPUT, LWP_LW_INPUT_POINTER_AXIS_OPCODE,
            encodeLwInputPointerAxis(dx, dy))
    }

    public func key(keycode: UInt32, down: Bool): Unit {
        seq = seq + 1
        let _ = ch.send(LWP_EVENT, LWP_IFACE_LW_INPUT, LWP_LW_INPUT_KEY_OPCODE,
            encodeLwInputKey(keycode, down))
    }

    /// 键事件（since=2）：带该键产生的文本与修饰键位。
    public func keyText(keycode: UInt32, down: Bool, text: String, modifiers!: UInt16 = 0): Unit {
        seq = seq + 1
        let _ = ch.send(LWP_EVENT, LWP_IFACE_LW_INPUT, LWP_LW_INPUT_KEY_OPCODE,
            encodeLwInputKeyText(keycode, down, text, modifiers))
    }

    /// 输入法组合中文本（lw_text_input.preedit）。
    public func preedit(text: String, cursor: UInt32): Unit {
        seq = seq + 1
        let _ = ch.send(LWP_EVENT, LWP_IFACE_LW_TEXT_INPUT, LWP_LW_TEXT_INPUT_PREEDIT_OPCODE,
            encodeLwTextInputPreedit(text, cursor))
    }

    /// 输入法上屏文本（lw_text_input.commit_string）。
    public func commitString(text: String): Unit {
        seq = seq + 1
        let _ = ch.send(LWP_EVENT, LWP_IFACE_LW_TEXT_INPUT, LWP_LW_TEXT_INPUT_COMMIT_STRING_OPCODE,
            encodeLwTextInputCommitString(text))
    }

    /// 输入法要求删字（lw_text_input.delete_surrounding）。
    public func deleteSurrounding(before: UInt32, after: UInt32): Unit {
        seq = seq + 1
        let _ = ch.send(LWP_EVENT, LWP_IFACE_LW_TEXT_INPUT, LWP_LW_TEXT_INPUT_DELETE_SURROUNDING_OPCODE,
            encodeLwTextInputDeleteSurrounding(before, after))
    }

    public func textInput(text: String): Unit {
        seq = seq + 1
        let _ = ch.send(LWP_EVENT, LWP_IFACE_LW_INPUT, LWP_LW_INPUT_TEXT_INPUT_OPCODE,
            encodeLwInputTextInput(text))
    }

    // ── 窗口生命周期（模拟壳侧行为，用于 M2 链路测试）────────────────────────
    // 小端写入（模拟壳组包；只写低字节会让解码拿到 64 而不是 1600 —— 测试抓到过）
    private func putU32(b: Array<UInt8>, off: Int64, v: UInt32): Unit {
        b[off] = UInt8(v & 0xFF)
        b[off + 1] = UInt8((v >> 8) & 0xFF)
        b[off + 2] = UInt8((v >> 16) & 0xFF)
        b[off + 3] = UInt8((v >> 24) & 0xFF)
    }

    private func putU64(b: Array<UInt8>, off: Int64, v: UInt64): Unit {
        putU32(b, off, UInt32(v & 0xFFFFFFFF))
        putU32(b, off + 4, UInt32((v >> 32) & 0xFFFFFFFF))
    }

    public func sendAppStarted(appId: UInt32): Unit {
        var b = Array<UInt8>(8, repeat: 0)
        b[0] = 8
        putU32(b, 4, appId)
        let _ = ch.send(LWP_EVENT, LWP_IFACE_LW_APP, LWP_LW_APP_STARTED_OPCODE, b)
    }

    public func sendWindowCreated(id: UInt32, scale: Float32, ssd: Bool): Unit {
        var b = Array<UInt8>(LWP_LW_WINDOW_CREATED_SIZE, repeat: 0)
        b[0] = UInt8(LWP_LW_WINDOW_CREATED_SIZE)
        putU32(b, 4, id)
        // scale 用位模式写入（与解码约定一致）
        unsafe {
            let h = acquireArrayRawData(b)
            CPointer<Float32>(CPointer<UInt8>(h.pointer) + 8).write(scale)
            releaseArrayRawData(h)
        }
        b[12] = if (ssd) { 1 } else { 0 }
        let _ = ch.send(LWP_EVENT, LWP_IFACE_LW_WINDOW, LWP_LW_WINDOW_CREATED_OPCODE, b)
    }

    public func sendConfigure(width: UInt32, height: UInt32, state: UInt32): Unit {
        var b = Array<UInt8>(LWP_LW_WINDOW_CONFIGURE_SIZE, repeat: 0)
        b[0] = UInt8(LWP_LW_WINDOW_CONFIGURE_SIZE)
        putU32(b, 4, width)
        putU32(b, 8, height)
        putU32(b, 12, state)
        let _ = ch.send(LWP_EVENT, LWP_IFACE_LW_WINDOW, LWP_LW_WINDOW_CONFIGURE_OPCODE, b)
    }

    public func sendFrameDone(serial: UInt32, timeNs: UInt64): Unit {
        var b = Array<UInt8>(LWP_LW_FRAME_DONE_SIZE, repeat: 0)
        b[0] = UInt8(LWP_LW_FRAME_DONE_SIZE)
        putU32(b, 4, serial)
        putU64(b, 8, timeNs)
        let _ = ch.send(LWP_EVENT, LWP_IFACE_LW_FRAME, LWP_LW_FRAME_DONE_OPCODE, b)
    }

    public func sendSurfaceAvailable(handle: UInt64, w: UInt32, h: UInt32): Unit {
        var b = Array<UInt8>(LWP_LW_SURFACE_AVAILABLE_SIZE, repeat: 0)
        putU32(b, 0, UInt32(LWP_LW_SURFACE_AVAILABLE_SIZE))
        putU64(b, 4, handle)
        putU32(b, 12, w)
        putU32(b, 16, h)
        let _ = ch.send(LWP_EVENT, LWP_IFACE_LW_SURFACE, LWP_LW_SURFACE_AVAILABLE_OPCODE, b)
    }

    /// 平台三键矩形事件（壳 -> 引擎；docs/lwindow-title-buttons-plan.md）。
    public func sendTitleButtonsRect(right: Int32, top: Int32, width: UInt32, height: UInt32,
        visible: Bool): Unit {
        var b = Array<UInt8>(LWP_LW_WINDOW_TITLE_BUTTONS_RECT_SIZE, repeat: 0)
        putU32(b, 0, UInt32(LWP_LW_WINDOW_TITLE_BUTTONS_RECT_SIZE))
        putU32(b, 4, UInt32(right))
        putU32(b, 8, UInt32(top))
        putU32(b, 12, width)
        putU32(b, 16, height)
        b[20] = if (visible) { 1 } else { 0 }
        let _ = ch.send(LWP_EVENT, LWP_IFACE_LW_WINDOW, LWP_LW_WINDOW_TITLE_BUTTONS_RECT_OPCODE, b)
    }

    public func sendSurfaceChanged(w: UInt32, h: UInt32): Unit {
        var b = Array<UInt8>(LWP_LW_SURFACE_CHANGED_SIZE, repeat: 0)
        putU32(b, 0, UInt32(LWP_LW_SURFACE_CHANGED_SIZE))
        putU32(b, 4, w)
        putU32(b, 8, h)
        let _ = ch.send(LWP_EVENT, LWP_IFACE_LW_SURFACE, LWP_LW_SURFACE_CHANGED_OPCODE, b)
    }

    public func sendSurfaceWillDestroy(): Unit {
        var b = Array<UInt8>(4, repeat: 0)
        putU32(b, 0, 4)
        let _ = ch.send(LWP_EVENT, LWP_IFACE_LW_SURFACE, LWP_LW_SURFACE_WILL_DESTROY_OPCODE, b)
    }

    /// system.info：5 个字段（4 个字符串 + api 级别）
    public func sendSystemInfo(tz: String, lang: String, fontDir: String, homeDir: String, api: UInt32): Unit {
        let a = tz.toArray()
        let bb = lang.toArray()
        let c = fontDir.toArray()
        let d = homeDir.toArray()
        let total = 24 + a.size + bb.size + c.size + d.size
        var buf = Array<UInt8>(total, repeat: 0)
        putU32(buf, 0, UInt32(total))
        // 字符串本体从 24 开始依次排列
        var off: Int64 = 24
        let strs = [a, bb, c, d]
        var hdr: Int64 = 4
        for (sArr in strs) {
            buf[hdr] = UInt8(off & 0xFF)
            buf[hdr + 1] = UInt8((off >> 8) & 0xFF)
            buf[hdr + 2] = UInt8(sArr.size)
            buf[hdr + 3] = 0
            for (i in 0..sArr.size) { buf[off + i] = sArr[i] }
            off = off + Int64(sArr.size)
            hdr = hdr + 4
        }
        putU32(buf, 20, api)
        let _ = ch.send(LWP_EVENT, LWP_IFACE_LW_SYSTEM, LWP_LW_SYSTEM_INFO_OPCODE, buf)
    }

    /// 壳侧收引擎请求（REQUEST 方向）。返回 (iface, opcode, body)。
    public func recvRequest(): (UInt16, UInt16, Array<UInt8>) {
        match (ch.recv(LWP_REQUEST)) {
            case Some(m) => (m.iface, m.opcode, m.body)
            case None => (0, 0, Array<UInt8>(0, repeat: 0))
        }
    }

    public func channel(): LwpChannel {
        ch
    }

    /// core.hello 消息体（size=28 + "headless" + "linux"）
    private func encodeHelloBody(caps: UInt64): Array<UInt8> {
        let shell = "headless".toArray()
        let os = "linux".toArray()
        let so: Int64 = 28
        let oo: Int64 = so + shell.size
        var b = Array<UInt8>(oo + os.size, repeat: 0)
        b[0] = 28
        b[4] = 1  // protocol_major
        b[6] = 0  // protocol_minor
        b[8] = UInt8(so)
        b[10] = UInt8(shell.size)
        b[12] = UInt8(oo)
        b[14] = UInt8(os.size)
        b[16] = 0  // os_api_level（headless 无意义）
        for (i in 0..8) {
            b[20 + i] = UInt8((caps >> (8 * i)) & 0xFF)
        }
        for (i in 0..shell.size) { b[so + i] = shell[i] }
        for (i in 0..os.size) { b[oo + i] = os[i] }
        b
    }
}
