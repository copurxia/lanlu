package lwindow

// L 层自有事件模型（不再依赖 SDL 的事件类型）。
//
// 事件来源：ArkTS 的 XComponent 输入 → 原生环形缓冲 → 本包 poll（见 lanlu_poll_input）。

import std.convert.*

public enum LWindowEventType {
    | PointerDown
    | PointerMove
    | PointerUp
    | Unknown
}

public struct LWindowEvent {
    public let kind: LWindowEventType
    public let x: Float32
    public let y: Float32
    public let key: Int32

    public init(kind: LWindowEventType, x: Float32, y: Float32, key: Int32) {
        this.kind = kind
        this.x = x
        this.y = y
        this.key = key
    }
}
