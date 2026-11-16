package lwindow

// L 层自有事件模型（不再依赖 SDL 的事件类型）。
//
// 事件来源：ArkTS 的 XComponent 输入 → 原生环形缓冲 → 本包 poll（见 lanlu_poll_input）。

import std.convert.*
import std.collection.ArrayList

public enum LWindowEventType <: Equatable<LWindowEventType> {
    | PointerDown
    | PointerMove
    | PointerUp
    | PointerAxis   // 滚轮/触摸板（x=dx, y=dy，逻辑行数）
    | Key           // 键盘原始事件（key=键码，pressed=按下/释放，text=该键产生的文本）
    | TextInput     // 输入法上屏文本（text 字段）
    | Preedit       // 输入法组合中的文本（text 字段，key=组合串内光标字节偏移）
    | DeleteSurrounding // 输入法要求删字（key=前删字符数，x=后删字符数）
    | Unknown

    // 无载荷枚举也需显式实现 Equatable，@Expect 等宏断言才能比较（参照 qwest.Method）
    public func toString(): String {
        match (this) {
            case PointerDown => "pointer_down"
            case PointerMove => "pointer_move"
            case PointerUp => "pointer_up"
            case PointerAxis => "pointer_axis"
            case Key => "key"
            case TextInput => "text_input"
            case Preedit => "preedit"
            case DeleteSurrounding => "delete_surrounding"
            case Unknown => "unknown"
        }
    }

    public operator func ==(that: LWindowEventType): Bool {
        this.toString() == that.toString()
    }

    public operator func !=(that: LWindowEventType): Bool {
        !(this == that)
    }
}

public struct LWindowEvent {
    public let kind: LWindowEventType
    public let x: Float32
    public let y: Float32
    public let key: Int32
    public let pressed: Bool   // Key 事件：true=按下
    public let text: String    // Key：该键产生的文本（可为空）；TextInput/Preedit：文本
    /// Key 事件的修饰键位（LWP_KEY_MODIFIERS_*，与 lgui KeyModifiers 同值）。其余事件为 0。
    public let modifiers: UInt16

    public init(kind: LWindowEventType, x: Float32, y: Float32, key: Int32,
        pressed!: Bool = true, text!: String = "", modifiers!: UInt16 = 0) {
        this.kind = kind
        this.x = x
        this.y = y
        this.key = key
        this.pressed = pressed
        this.text = text
        this.modifiers = modifiers
    }

    public init(kind: LWindowEventType, x: Float32, y: Float32) {
        this(kind, x, y, 0)
    }
}
