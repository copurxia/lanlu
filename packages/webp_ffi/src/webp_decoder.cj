package webp_ffi

/**
 * WebP decoder (high-level) returning RGBA8 pixels.
 */
public class WebpDecoder {
    public static func decodeRGBA(data: Array<UInt8>): ?(UInt32, UInt32, Array<UInt8>) {
        if (data.size < 12) {
            return None
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
}

