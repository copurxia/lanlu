package png_ffi

/**
 * PNG decoder (high-level) returning RGBA8 pixels.
 */
public class PngDecoder {
    public static func decodeRGBA(data: Array<UInt8>): ?(UInt32, UInt32, Array<UInt8>) {
        if (data.size < 8) {
            return None
        }

        unsafe {
            // png_image must be zero-initialized except version; using explicit zero VArray for message.
            var msg = VArray<UInt8, $64>(repeat: 0u8)
            var image = png_image(
                png_controlp(CPointer<png_control>()), // will be overwritten by libpng; must start as NULL
                PNG_IMAGE_VERSION,
                0u32,
                0u32,
                0u32,
                0u32,
                0u32,
                0u32,
                msg
            )

            let handle = acquireArrayRawData(data)
            try {
                let dataPtr = CPointer<Unit>(handle.pointer)
                let beginRes = png_image_begin_read_from_memory(CPointer<png_image>(inout image), dataPtr, UIntNative(data.size))
                if (beginRes == 0) {
                    return None
                }

                // Request RGBA output. (libpng requires `format` to be set before finish_read.)
                image = png_image(
                    image.opaque,
                    image.version,
                    image.width,
                    image.height,
                    PNG_FORMAT_RGBA,
                    image.flags,
                    image.colormap_entries,
                    image.warning_or_error,
                    image.message
                )

                let width = image.width
                let height = image.height
                if (width == 0u32 || height == 0u32) {
                    return None
                }

                let pixelCount = Int64(width) * Int64(height) * 4
                var pixels = Array<UInt8>(pixelCount, repeat: 0u8)
                let pixelHandle = acquireArrayRawData(pixels)
                try {
                    let rowStride = Int32(width * 4u32)
                    let finishRes = png_image_finish_read(
                        CPointer<png_image>(inout image),
                        png_const_colorp(CPointer<png_color>()), // NULL
                        CPointer<Unit>(pixelHandle.pointer),
                        rowStride,
                        CPointer<Unit>() // NULL
                    )
                    if (finishRes == 0) {
                        return None
                    }
                    return (width, height, pixels)
                } finally {
                    releaseArrayRawData(pixelHandle)
                }
            } finally {
                releaseArrayRawData(handle)
                // If begin_read succeeded and finish_read failed, this frees `opaque`.
                // If finish_read succeeded, freeing is a no-op.
                try { png_image_free(CPointer<png_image>(inout image)) } catch (_: Exception) {}
            }
        }
    }
}
