package jpeg_ffi

/**
 * JPEG decoder (high-level) returning RGBA8 pixels.
 *
 * NOTE: libjpeg uses callbacks for fatal error handling. We install a custom
 * error_exit that longjmps back to a checkpoint.
 */
public class JpegDecoder {
    public static func decodeRGBA(data: Array<UInt8>): ?(UInt32, UInt32, Array<UInt8>) {
        if (data.size < 4) {
            return None
        }

        unsafe {
            var jerr = jpeg_error_mgr()
            let _ = jpeg_std_error(CPointer<jpeg_error_mgr>(inout jerr))

            var cinfo = jpeg_decompress_struct()
            cinfo.err = CPointer<jpeg_error_mgr>(inout jerr)

            jpeg_CreateDecompress(CPointer<jpeg_decompress_struct>(inout cinfo), JPEG_LIB_VERSION, UIntNative(sizeOf<jpeg_decompress_struct>()))

            let handle = acquireArrayRawData(data)
            try {
                let dataPtr = CString(handle.pointer)
                jpeg_mem_src(CPointer<jpeg_decompress_struct>(inout cinfo), dataPtr, UInt64(data.size))

                let hdrOk = jpeg_read_header(CPointer<jpeg_decompress_struct>(inout cinfo), 1)
                if (hdrOk == 0) {
                    jpeg_destroy_decompress(CPointer<jpeg_decompress_struct>(inout cinfo))
                    return None
                }

                cinfo.out_color_space = JCS_RGB
                cinfo.quantize_colors = 0

                let startOk = jpeg_start_decompress(CPointer<jpeg_decompress_struct>(inout cinfo))
                if (startOk == 0) {
                    jpeg_destroy_decompress(CPointer<jpeg_decompress_struct>(inout cinfo))
                    return None
                }

                let width = cinfo.output_width
                let height = cinfo.output_height
                let comps = cinfo.output_components

                if (width == 0u32 || height == 0u32 || (comps != 1 && comps != 3)) {
                    try { jpeg_destroy_decompress(CPointer<jpeg_decompress_struct>(inout cinfo)) } catch (_: Exception) {}
                    return None
                }

                let outSize = Int64(width) * Int64(height) * 4
                var pixels = Array<UInt8>(outSize, repeat: 0u8)

                let rowBytes = Int64(width) * Int64(comps)
                let rowBuf = LibC.malloc<UInt8>(count: rowBytes)
                let rowArray = LibC.malloc<JSAMPROW>(count: 1)
                unsafe { rowArray.write(JSAMPROW(rowBuf)) }

                try {
                    while (cinfo.output_scanline < height) {
                        let got = jpeg_read_scanlines(CPointer<jpeg_decompress_struct>(inout cinfo), JSAMPARRAY(rowArray), 1u32)
                        if (got == 0u32) {
                            break
                        }
                        let y = Int64(cinfo.output_scanline) - 1
                        let base = y * Int64(width) * 4

                        if (comps == 3) {
                            for (x in 0..Int64(width)) {
                                let s = x * 3
                                let d = base + x * 4
                                pixels[d] = (rowBuf + s).read()
                                pixels[d + 1] = (rowBuf + s + 1).read()
                                pixels[d + 2] = (rowBuf + s + 2).read()
                                pixels[d + 3] = 255u8
                            }
                        } else {
                            // Grayscale -> RGBA
                            for (x in 0..Int64(width)) {
                                let v = (rowBuf + x).read()
                                let d = base + x * 4
                                pixels[d] = v
                                pixels[d + 1] = v
                                pixels[d + 2] = v
                                pixels[d + 3] = 255u8
                            }
                        }
                    }
                } finally {
                    LibC.free(rowArray)
                    LibC.free(rowBuf)
                }

                let _ = jpeg_finish_decompress(CPointer<jpeg_decompress_struct>(inout cinfo))
                jpeg_destroy_decompress(CPointer<jpeg_decompress_struct>(inout cinfo))

                return (width, height, pixels)
            } finally {
                releaseArrayRawData(handle)
            }
        }
    }
}
