package cui.input

import lbase.CuiException

import cui.base.{ensureSdl, lastSdlError}

public enum SystemCursor {
    | Default
    | Text
    | Wait
    | Crosshair
    | Progress
    | NwseResize
    | NeswResize
    | EwResize
    | NsResize
    | Move
    | NotAllowed
    | Pointer
    | NwResize
    | NResize
    | NeResize
    | EResize
    | SeResize
    | SResize
    | SwResize
    | WResize
}

/// 平台层注册的光标出口：lgui 只决定「要什么形状」，怎么设由 L 层负责
/// （OHOS 走 multimodalInput.pointer，Wayland 走 wl_pointer.set_cursor）。
public var cursorSink: Option<(SystemCursor) -> Unit> = None

// P5：无 SDL 窗口时鼠标样式设置交给 L 层（OHOS 有自己的光标 API）。
// 关闭后 system() 返回空光标对象、setActive() 为空操作，避免未初始化 SDL 报错。
public var cursorsEnabled: Bool = true

public class Cursor <: Resource {
    private let ptr: CPointer<Unit>
    private var closed = false

    private init(ptr: CPointer<Unit>) {
        this.ptr = ptr
    }

    /**
     * Throws `CuiException` when SDL cannot create the requested native system cursor.
     */

    public static func system(kind: SystemCursor): Cursor {
        // P5：无 SDL 光标对象；形状请求交给平台层
        match (cursorSink) {
            case Some(sink) => sink(kind)
            case None => ()
        }
        Cursor(CPointer<Unit>())
    }

    /**
     * Throws `CuiException` when a closed cursor is reused or SDL cannot activate it.
     */

    public func setActive() {
        // P5：无 SDL 光标
        ()
    }

    public func isClosed(): Bool {
        closed
    }


    public func close() {
        this.closed = true
    }

    /**
     * Throws `CuiException` when SDL cannot show the OS cursor.
     */

    public static func show() {
        // P5：光标显隐由系统控制
        ()
    }

    /**
     * Throws `CuiException` when SDL cannot hide the OS cursor.
     */

    public static func hide() {
        ()
    }


    public static func isVisible(): Bool {
        true
    }

    /**
     * Throws `CuiException` when a closed cursor is reused.
     */
    private func ensureOpen(): Unit {
        if (closed) {
            throw CuiException("Cursor is already closed.")
        }
    }
}

internal func systemCursorCode(kind: SystemCursor): Int32 {
    match (kind) {
        case SystemCursor.Default => 0
        case SystemCursor.Text => 1
        case SystemCursor.Wait => 2
        case SystemCursor.Crosshair => 3
        case SystemCursor.Progress => 4
        case SystemCursor.NwseResize => 5
        case SystemCursor.NeswResize => 6
        case SystemCursor.EwResize => 7
        case SystemCursor.NsResize => 8
        case SystemCursor.Move => 9
        case SystemCursor.NotAllowed => 10
        case SystemCursor.Pointer => 11
        case SystemCursor.NwResize => 12
        case SystemCursor.NResize => 13
        case SystemCursor.NeResize => 14
        case SystemCursor.EResize => 15
        case SystemCursor.SeResize => 16
        case SystemCursor.SResize => 17
        case SystemCursor.SwResize => 18
        case SystemCursor.WResize => 19
    }
}
