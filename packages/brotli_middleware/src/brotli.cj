package brotli_middleware

import ace_web.*
import std.collection.*

private const BROTLI_MODE_TEXT: Int32 = 1
private const BROTLI_FALSE: Int32 = 0

foreign func BrotliEncoderMaxCompressedSize(inputSize: UIntNative): UIntNative
foreign func BrotliEncoderCompress(
    quality: Int32,
    lgwin: Int32,
    mode: Int32,
    inputSize: UIntNative,
    inputBuffer: CPointer<UInt8>,
    encodedSize: CPointer<UIntNative>,
    encodedBuffer: CPointer<UInt8>
): Int32

private func neverSkip(_: String): Bool {
    false
}

public class BrotliConfig {
    public var minBytes: Int64 = 2048
    public var quality: Int32 = 5
    public var lgwin: Int32 = 22
    public var setVaryHeader: Bool = true
    public var skipIfNoGain: Bool = true

    public init(
        minBytes!: Int64 = 2048,
        quality!: Int32 = 5,
        lgwin!: Int32 = 22,
        setVaryHeader!: Bool = true,
        skipIfNoGain!: Bool = true
    ) {
        this.minBytes = minBytes
        this.quality = quality
        this.lgwin = lgwin
        this.setVaryHeader = setVaryHeader
        this.skipIfNoGain = skipIfNoGain
    }
}

/**
 * brotli 响应压缩中间件（后置）。仅当请求头 Accept-Encoding 含 br 且响应体是文本/二进制时压缩，
 * 压缩后替换响应体并设 Content-Encoding: br。流式(SSE)与空响应不压缩。
 * 照 ACE gzip.cj 模式：next() 后读 responseBody()，对 TextBody/BytesBody 压缩后 setBodyBytes。
 *
 * 用法：app.use(brotliMiddleware())  // 置于洋葱外层，包住业务，最后压缩。
 */
public func brotliMiddleware(
    config!: BrotliConfig = BrotliConfig(),
    shouldSkip!: (String) -> Bool = neverSkip
): Middleware {
    let minBytes = if (config.minBytes < 0) { 0 } else { config.minBytes }
    let quality = normalizeQuality(config.quality)
    let lgwin = normalizeLgwin(config.lgwin)

    return { ctx: Context, next: Next =>
        if (shouldSkip(ctx.path)) {
            next()
            return
        }
        next()

        if (ctx.method == "HEAD") { return }
        if (shouldSkipStatus(ctx.status)) { return }
        if ((ctx.header("range") ?? "").size > 0) { return }
        if (!clientAcceptsBrotli(ctx.header("accept-encoding") ?? "")) { return }

        match (ctx.responseBody()) {
            case TextBody(s) =>
                let rawBytes = s.toArray()
                if (Int64(rawBytes.size) < minBytes) {
                    return
                }
                tryCompress(ctx, rawBytes, config, quality, lgwin)
            case BytesBody(b) =>
                if (Int64(b.size) < minBytes) {
                    return
                }
                tryCompress(ctx, b, config, quality, lgwin)
            case _ => () // StreamBody / NoBody 不压缩
        }
    }
}

func tryCompress(
    ctx: Context,
    rawBytes: Array<UInt8>,
    config: BrotliConfig,
    quality: Int32,
    lgwin: Int32
): Unit {
    var compressedOpt: Option<Array<UInt8>> = None
    try {
        compressedOpt = compressToBrotli(rawBytes, quality: quality, lgwin: lgwin)
    } catch (_: Exception) {
        compressedOpt = None
    }
    if (let Some(compressed) <- compressedOpt) {
        if (config.skipIfNoGain && compressed.size >= rawBytes.size) {
            return
        }
        if (config.setVaryHeader) {
            ctx.setHeader("Vary", "Accept-Encoding")
        }
        ctx.setHeader("Content-Encoding", "br")
        ctx.setHeader("Content-Length", "${compressed.size}")
        ctx.setBodyBytes(compressed)
    }
}

func compressToBrotli(
    input: Array<UInt8>,
    quality!: Int32 = 5,
    lgwin!: Int32 = 22
): Option<Array<UInt8>> {
    if (input.size == 0) {
        return None
    }
    unsafe {
        let maxSize = BrotliEncoderMaxCompressedSize(UIntNative(input.size))
        if (maxSize == UIntNative(0)) {
            return None
        }
        var output = Array<UInt8>(Int64(maxSize), repeat: 0u8)
        var encodedSize = maxSize
        let inputHandle = acquireArrayRawData(input)
        let outputHandle = acquireArrayRawData(output)
        try {
            let ok = BrotliEncoderCompress(
                quality,
                lgwin,
                BROTLI_MODE_TEXT,
                UIntNative(input.size),
                CPointer<UInt8>(inputHandle.pointer),
                CPointer<UIntNative>(inout encodedSize),
                CPointer<UInt8>(outputHandle.pointer)
            )
            if (ok == BROTLI_FALSE || encodedSize == UIntNative(0)) {
                return None
            }
            let actualSize = Int64(encodedSize)
            return output[..actualSize]
        } finally {
            releaseArrayRawData(outputHandle)
            releaseArrayRawData(inputHandle)
        }
    }
}

func shouldSkipStatus(status: UInt16): Bool {
    status < 200 || status == 204 || status == 304
}

func normalizeQuality(raw: Int32): Int32 {
    if (raw < 0) { return 0 }
    if (raw > 11) { return 11 }
    raw
}

func normalizeLgwin(raw: Int32): Int32 {
    if (raw < 10) { return 10 }
    if (raw > 24) { return 24 }
    raw
}

func clientAcceptsBrotli(acceptEncodingRaw: String): Bool {
    let acceptEncoding = acceptEncodingRaw.trimAscii().toAsciiLower()
    if (acceptEncoding.size == 0) {
        return false
    }
    var qBrotli: Int64 = -1
    var qWildcard: Int64 = -1
    for (part in acceptEncoding.split(",")) {
        let item = part.trimAscii()
        if (item.size == 0) { continue }
        let tokens = item.split(";")
        let name = tokens[0].trimAscii()
        var quality: Int64 = 1000
        if (tokens.size > 1) {
            var idx: Int64 = 1
            while (idx < tokens.size) {
                let kv = tokens[idx].trimAscii().split("=", 2)
                if (kv.size == 2 && kv[0].trimAscii() == "q") {
                    quality = parseQValue(kv[1])
                }
                idx += 1
            }
        }
        if (quality < 0) { continue }
        if (name == "br") {
            qBrotli = quality
        } else if (name == "*") {
            qWildcard = quality
        }
    }
    if (qBrotli < 0) { qBrotli = qWildcard }
    qBrotli > 0
}

func parseQValue(raw: String): Int64 {
    let s = raw.trimAscii()
    if (s.size == 0) { return -1 }
    let parts = s.split(".", 2)
    if (parts.size == 0) { return -1 }
    let whole = parseDigits(parts[0])
    if (whole < 0 || whole > 1) { return -1 }
    var fracScaled: Int64 = 0
    if (parts.size == 2) {
        let frac = parts[1]
        if (frac.size == 0) { return -1 }
        var scale: Int64 = 100
        var count: Int64 = 0
        for (ch in frac.toRuneArray()) {
            if (count >= 3) { break }
            if (ch < r'0' || ch > r'9') { return -1 }
            fracScaled += (Int64(UInt32(ch)) - Int64(UInt32(r'0'))) * scale
            scale /= 10
            count += 1
        }
        for (ch in frac.toRuneArray()) {
            if (ch < r'0' || ch > r'9') { return -1 }
        }
    }
    whole * 1000 + fracScaled
}

func parseDigits(raw: String): Int64 {
    if (raw.size == 0) { return -1 }
    var value: Int64 = 0
    for (ch in raw.toRuneArray()) {
        if (ch < r'0' || ch > r'9') { return -1 }
        value = value * 10 + (Int64(UInt32(ch)) - Int64(UInt32(r'0')))
    }
    value
}