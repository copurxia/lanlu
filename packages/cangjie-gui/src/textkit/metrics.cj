package cui.textkit

// P5：SDK 的 SDL_ttf 文本后端已移除。这里只保留 Renderer 需要的纯数据类型，
// 真正的文本测量/绘制由替代后端（lgpu）承担。

protected class NativeTextException <: Exception {
    public init(message: String) {
        super(message)
    }
}

protected struct NativeTextMetrics {
    public let width: Float32
    public let height: Float32

    public init(width: Float32, height: Float32) {
        this.width = width
        this.height = height
    }
}

protected struct NativeTextColor {
    public let red: UInt8
    public let green: UInt8
    public let blue: UInt8
    public let alpha: UInt8

    public init(red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8) {
        this.red = red
        this.green = green
        this.blue = blue
        this.alpha = alpha
    }
}

/// 无 SDL_ttf 的文本后端占位：文本由替代后端绘制，这里只提供度量缓存所需类型。
protected class NativeTextRenderer {
    public init(renderer: CPointer<Unit>, fontPath!: ?String = None) {
    }

    public func measure(text: String, pointSize: Float32): NativeTextMetrics {
        NativeTextMetrics(0.0, 0.0)
    }

    public func familyName(): String {
        ""
    }

    public func path(): String {
        ""
    }

    /// 无 SDL_ttf：文本绘制由替代后端承担，这里只保证接口存在。
    public func draw(text: String, x: Float32, y: Float32, pointSize: Float32, color: NativeTextColor): Unit {
    }

    public func shapeCount(): UInt64 {
        0
    }

    public func resetShapeCount(): Unit {
    }

    public func close(): Unit {
    }
}
