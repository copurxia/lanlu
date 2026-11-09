package lwindow

// L 层自有事件模型（不再依赖 SDL 的事件类型）。
//
// 事件来源：ArkTS 的 XComponent 输入 → 原生环形缓冲 → 本包 poll（见 lanlu_poll_input）。

import std.convert.*
import std.env.getVariable
import std.fs.{File, Path}
import std.collection.ArrayList

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

/// 读取并消费输入事件文件（原生侧追加写，这里读完后清空）。
/// 用文件而不是 FFI：引擎调用 libmain 的符号在真机上会崩（见 docs/l-layer.md）。
public func readInputEvents(): ArrayList<LWindowEvent> {
    let out = ArrayList<LWindowEvent>()
    let home = getVariable("HOME")
    match (home) {
        case None => return out
        case Some(base) =>
            let path = base + "/input_events.txt"
            let text = try {
                String.fromUtf8(File.readFrom(Path(path)))
            } catch (_) {
                return out
            }
            try {
                File.writeTo(Path(path), Array<UInt8>())
            } catch (_) {}
            for (line in text.split("\n")) {
                let parts = line.trimAscii().split(" ")
                if (parts.size < 4) {
                    continue
                }
                let action = try { Int64.parse(parts[0]) } catch (_) { 0 }
                let x = try { Float32.parse(parts[1]) } catch (_) { 0.0f32 }
                let y = try { Float32.parse(parts[2]) } catch (_) { 0.0f32 }
                let key = try { Int32.parse(parts[3]) } catch (_) { 0i32 }
                let kind = match (action) {
                    case 1 => LWindowEventType.PointerDown
                    case 11 => LWindowEventType.PointerDown
                    case 21 => LWindowEventType.PointerDown
                    case 2 => LWindowEventType.PointerMove
                    case 10 => LWindowEventType.PointerMove
                    case 20 => LWindowEventType.PointerMove
                    case 3 => LWindowEventType.PointerUp
                    case 12 => LWindowEventType.PointerUp
                    case 22 => LWindowEventType.PointerUp
                    case _ => LWindowEventType.Unknown
                }
                out.add(LWindowEvent(kind, x, y, key))
            }
    }
    return out
}