package lwindow

// backend.lwp：LWP 消息 -> LWindowEvent 的**唯一事件漏斗**（计划 §6、§16.3）。
//
// 规则：
//   * 引擎不得自己从通道里挑事件；所有壳侧事件都经 decodeLwpEvent 变成 LWindowEvent，
//     未识别的消息在此计数并忽略（协议检查器已在 liblwp 层拦过一次）；
//   * 事件模型扩展（PointerAxis/Key/TextInput）向后兼容：旧调用方按 `case _` 处理不受影响。

import lwp.*
import std.collection.ArrayList

public func decodeLwpEvent(m: LwpMessage): ?LWindowEvent {
    if (m.iface != LWP_IFACE_LW_INPUT) {
        return None
    }
    let b = m.body
    // 注意：Cangjie 的 match 分支里 `case LET_CONST =>` 是**绑定模式**（匹配一切），
    // 不是常量比较；协议 opcode 必须用 if/else 判等，否则所有消息都会落到第一个分支。
    // 壳传来的指针坐标是**物理像素**（窗口局部），而 UI 用**逻辑坐标**布局
    // （逻辑 = 物理 / UI 缩放）。这里统一换算，下游（UI 命中、光标形状、边缘热区）
    // 全部拿逻辑坐标 —— 否则 PC 模式 190%/200% 缩放下鼠标整体偏移（第 117 轮真机症状）。
    let pxScale = lwpReportedScale()
    let uiDiv: Float32 = if (pxScale > 0.0) { pxScale } else { 1.0f32 }
    if (m.opcode == LWP_LW_INPUT_POINTER_MOTION_OPCODE) {
        if (b.size < 12) { return None }
        let px = f32at(b, 4) / uiDiv
        let py = f32at(b, 8) / uiDiv
        lwpNotePointer(px, py)   // 供 frame tick 决定光标形状
        return Some(LWindowEvent(LWindowEventType.PointerMove, px, py))
    }
    if (m.opcode == LWP_LW_INPUT_POINTER_BUTTON_OPCODE) {
        if (b.size < 14) { return None }
        let down = b[13] != 0
        let kind = if (down) { LWindowEventType.PointerDown } else { LWindowEventType.PointerUp }
        return Some(LWindowEvent(kind, f32at(b, 4) / uiDiv, f32at(b, 8) / uiDiv,
            Int32(b[12]), pressed: down))
    }
    if (m.opcode == LWP_LW_INPUT_POINTER_AXIS_OPCODE) {
        if (b.size < 12) { return None }
        return Some(LWindowEvent(LWindowEventType.PointerAxis, f32at(b, 4), f32at(b, 8)))
    }
    if (m.opcode == LWP_LW_INPUT_KEY_OPCODE) {
        if (b.size < 9) { return None }
        return Some(LWindowEvent(LWindowEventType.Key, 0.0f32, 0.0f32,
            Int32(u32at(b, 4)), pressed: b[8] != 0))
    }
    if (m.opcode == LWP_LW_INPUT_TEXT_INPUT_OPCODE) {
        if (b.size < 8) { return None }
        let so = Int64(u16at(b, 4))
        let sl = Int64(u16at(b, 6))
        var text = ""
        if (sl > 0 && so + sl <= b.size) {
            text = String.fromUtf8(b[so..so + sl])
        }
        return Some(LWindowEvent(LWindowEventType.TextInput, 0.0f32, 0.0f32, 0, text: text))
    }
    None
}

/// 被 `LwpWindowClient.poll()` 误取到的**输入事件**暂存区。
/// `poll()` 只关心生命周期事件，但它和输入共用一条 EVENT 队列；
/// 早先它把不认识的消息直接丢掉 —— 于是每帧 tick 都可能吞掉指针移动
/// （第 90 轮实测：25 条 motion 全部没进 UI）。
private let g_backlogMsgs = ArrayList<LwpMessage>()

/// 把轮询时误取到的输入消息放回暂存区，供 `nextLwpEvent()` 后续取出。
public func pushBackLwpMessage(m: LwpMessage): Unit {
    g_backlogMsgs.add(m)
}

/// 从暂存区取一条（没有则 None）。
public func takeBacklogLwpMessage(): ?LwpMessage {
    if (g_backlogMsgs.size == 0) { return None }
    g_backlogMsgs.remove(at: 0)
}

/// 排空通道的 EVENT 队列，解码为事件列表（引擎主循环的输入入口）。
public func pollLwpEvents(ch: LwpChannel): ArrayList<LWindowEvent> {
    let out = ArrayList<LWindowEvent>()
    while (true) {
        let m = ch.recv(LWP_EVENT)
        match (m) {
            case Some(msg) =>
                match (decodeLwpEvent(msg)) {
                    case Some(ev) => out.add(ev)
                    case None => ()   // 未识别：丢弃（stats 由 liblwp 记）
                }
            case None => break
        }
    }
    out
}

// ── 小端读取（与 lwp 包的解码约定一致）───────────────────────────────────────
func u16at(b: Array<UInt8>, off: Int64): UInt16 {
    UInt16(b[off]) | (UInt16(b[off + 1]) << 8)
}

func u32at(b: Array<UInt8>, off: Int64): UInt32 {
    UInt32(b[off]) | (UInt32(b[off + 1]) << 8) | (UInt32(b[off + 2]) << 16) | (UInt32(b[off + 3]) << 24)
}

// f32 按 IEEE-754 位模式读取（Float32(u32) 是数值转换，会把位模式当整数解释）
func f32at(b: Array<UInt8>, off: Int64): Float32 {
    unsafe {
        let h = acquireArrayRawData(b)
        let v = CPointer<Float32>(CPointer<UInt8>(h.pointer) + off).read()
        releaseArrayRawData(h)
        v
    }
}
