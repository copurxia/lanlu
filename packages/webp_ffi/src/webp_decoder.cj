package webp_ffi

/**
 * WebP decoder (high-level) returning RGBA8 pixels.
 */
public class WebpDecoder {
    public static func decodeRGBA(data: Array<UInt8>): ?(UInt32, UInt32, Array<UInt8>) {
        if (data.size < 12) {
            return None
        }

        // Animated WebP can require proper frame composition. `WebPDecodeRGBA` is a
        // still-image decoder and is not reliable for animated WebP.
        if (isAnimatedWebp(data)) {
            match (decodeAnimatedFirstFrameRGBA(data)) {
                case Some(v) => return Some(v)
                case None => ()
            }
            // If animation decoding isn't available, fall back to still decode.
        }

        unsafe {
            var w: Int32 = 0
            var h: Int32 = 0

            let handle = acquireArrayRawData(data)
            try {
                let dataPtr = CString(handle.pointer)
                let ok = WebPGetInfo(dataPtr, UIntNative(data.size), CPointer<Int32>(inout w), CPointer<Int32>(inout h))
                if (ok == 0 || w <= 0 || h <= 0) {
                    return None
                }

                var dw: Int32 = 0
                var dh: Int32 = 0
                let decoded = WebPDecodeRGBA(dataPtr, UIntNative(data.size), CPointer<Int32>(inout dw), CPointer<Int32>(inout dh))
                if (decoded.isNull() || dw <= 0 || dh <= 0) {
                    return None
                }

                let width = UInt32(dw)
                let height = UInt32(dh)
                let outSize = Int64(width) * Int64(height) * 4
                var pixels = Array<UInt8>(outSize, repeat: 0u8)

                let src = decoded
                for (i in 0..outSize) {
                    pixels[i] = (src + i).read()
                }

                WebPFree(CPointer<Unit>(decoded))
                return (width, height, pixels)
            } finally {
                releaseArrayRawData(handle)
            }
        }
    }

    // Best-effort detection of animated WebP using container chunk parsing.
    // WebP animation flag is in VP8X chunk flags (bit 0x10).
    private static func isAnimatedWebp(data: Array<UInt8>): Bool {
        if (data.size < 16) {
            return false
        }

        // RIFF....WEBP
        if (!(data[0] == 0x52u8 && data[1] == 0x49u8 && data[2] == 0x46u8 && data[3] == 0x46u8 &&
              data[8] == 0x57u8 && data[9] == 0x45u8 && data[10] == 0x42u8 && data[11] == 0x50u8)) {
            return false
        }

        // Chunk iteration: after RIFF header (12 bytes): FourCC + size(le32) + payload + padding-to-even.
        var off: Int64 = 12
        while (off + 8 <= Int64(data.size)) {
            let tag0 = data[off]
            let tag1 = data[off + 1]
            let tag2 = data[off + 2]
            let tag3 = data[off + 3]
            let size = readLeU32(data, off + 4)
            let payloadOff = off + 8
            if (payloadOff + Int64(size) > Int64(data.size)) {
                return false
            }

            // VP8X chunk: first byte in payload is flags.
            if (tag0 == 0x56u8 && tag1 == 0x50u8 && tag2 == 0x38u8 && tag3 == 0x58u8) { // "VP8X"
                if (size >= 1u32) {
                    let flags = data[payloadOff]
                    return (flags & 0x10u8) != 0u8
                }
                return false
            }

            var advance = 8i64 + Int64(size)
            if ((advance & 1i64) == 1i64) {
                advance += 1
            }
            off += advance
        }

        return false
    }

    private static func readLeU32(data: Array<UInt8>, off: Int64): UInt32 {
        if (off + 4 > Int64(data.size)) {
            return 0u32
        }
        let b0 = UInt32(data[off])
        let b1 = UInt32(data[off + 1]) << 8
        let b2 = UInt32(data[off + 2]) << 16
        let b3 = UInt32(data[off + 3]) << 24
        return b0 | b1 | b2 | b3
    }

    private static func decodeAnimatedFirstFrameRGBA(data: Array<UInt8>): ?(UInt32, UInt32, Array<UInt8>) {
        unsafe {
            let handle = acquireArrayRawData(data)
            try {
                let bytesPtr = CPointer<UInt8>(handle.pointer)
                var webpData = WebPData(bytesPtr, UIntNative(data.size))

                let dec = WebPAnimDecoderNewInternal(
                    CPointer<WebPData>(inout webpData),
                    CPointer<Unit>(), // NULL options (defaults to MODE_RGBA)
                    WEBP_DEMUX_ABI_VERSION
                )
                if (dec.isNull()) {
                    return None
                }
                try {
                    // If libwebpdemux cannot parse, bail.
                    var pad = VArray<UInt32, $4>(repeat: 0u32)
                    var info = WebPAnimInfo(0u32, 0u32, 0u32, 0u32, 0u32, pad)
                    let okInfo = WebPAnimDecoderGetInfo(dec, CPointer<WebPAnimInfo>(inout info))
                    if (okInfo == 0 || info.canvas_width == 0u32 || info.canvas_height == 0u32) {
                        return None
                    }

                    var buf: CPointer<UInt8> = CPointer<UInt8>()
                    var ts: Int32 = 0
                    let okNext = WebPAnimDecoderGetNext(dec, CPointer<CPointer<UInt8>>(inout buf), CPointer<Int32>(inout ts))
                    if (okNext == 0 || buf.isNull()) {
                        return None
                    }

                    let width = info.canvas_width
                    let height = info.canvas_height
                    let outSize = Int64(width) * Int64(height) * 4
                    var pixels = Array<UInt8>(outSize, repeat: 0u8)
                    for (i in 0..outSize) {
                        pixels[i] = (buf + i).read()
                    }
                    return (width, height, pixels)
                } finally {
                    WebPAnimDecoderDelete(dec)
                }
            } finally {
                releaseArrayRawData(handle)
            }
        }
    }
}
