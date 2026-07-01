package lanlu.shared.http_ext

import ace_web.*
import std.io.InputStream

/**
 * ACE Context 的 HTTP 扩展（自由函数）。
 * ACE dispatch 预读 body 到 ctx.rawBodyBytes()，本模块提供从预读 bytes 构造 InputStream 的能力。
 * SSE 用 ACE 原生 sse(ctx, producer)；locals 用 ctx.state 直接访问。
 */

/**
 * 从 Array<UInt8> 构造的 InputStream。
 * ACE dispatch 预读 body 到 rawBodyBytes，原始 req.body 已耗尽；
 * 本类让业务侧能从预读的 bytes 流式读取。
 */
public class ByteArrayInputStream <: InputStream {
    private let data: Array<UInt8>
    private var pos: Int64 = 0
    private var closed: Bool = false

    public init(data: Array<UInt8>) {
        this.data = data
    }

    public func read(buffer: Array<Byte>): Int64 {
        if (closed) { return 0 }
        if (pos >= Int64(data.size)) { return 0 }
        let available = Int64(data.size) - pos
        let toRead = if (available < Int64(buffer.size)) { available } else { Int64(buffer.size) }
        for (i in 0..toRead) {
            buffer[i] = data[pos + i]
        }
        pos += toRead
        return toRead
    }

    public func close(): Unit {
        closed = true
    }
}

/**
 * 原始请求体 InputStream。
 * ACE dispatch 预读了 body 到 ctx.rawBodyBytes()，这里从 bytes 构造 InputStream 返回。
 */
public func requestBodyOf(ctx: Context): InputStream {
    match (ctx.rawBodyBytes()) {
        case Some(bytes) => ByteArrayInputStream(bytes)
        case None => ByteArrayInputStream(Array<UInt8>(0, { _ => 0u8 }))
    }
}

/** 读取 state 中的字符串值（ctx.state.get 返回 ?Any，这里做 String 类型转换）。 */
public func getLocalStr(ctx: Context, key: String): ?String {
    match (ctx.state.get(key)) {
        case Some(v) => match (v) {
            case s: String => Some(s)
            case _ => None
        }
        case None => None
    }
}

/** 写入字符串到 state。 */
public func setLocalStr(ctx: Context, key: String, value: String): Unit {
    ctx.state.add(key, value)
}