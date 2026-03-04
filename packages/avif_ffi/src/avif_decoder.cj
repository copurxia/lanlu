package avif_ffi

/**
 * AVIF 图片解码器高级 API
 */
public class AvifDecoder {

    /**
     * 从内存数据解码 AVIF 图片为 RGBA 像素
     * @param data AVIF 图片数据
     * @return (width, height, pixels) 或 None
     */
    public static func decodeRGBA(data: Array<UInt8>): ?(UInt32, UInt32, Array<UInt8>) {
        unsafe {
            let decoder = avifDecoderCreate()
            if (decoder.isNull()) {
                return None
            }

            let handle = acquireArrayRawData(data)
            let dataPtr = CString(handle.pointer)

            let res = avifDecoderSetIOMemory(decoder, dataPtr, UIntNative(data.size))
            if (res != avifResult_AVIF_RESULT_OK) {
                releaseArrayRawData(handle)
                avifDecoderDestroy(decoder)
                return None
            }

            let parseRes = avifDecoderParse(decoder)
            if (parseRes != avifResult_AVIF_RESULT_OK) {
                releaseArrayRawData(handle)
                avifDecoderDestroy(decoder)
                return None
            }

            let nextRes = avifDecoderNextImage(decoder)
            if (nextRes != avifResult_AVIF_RESULT_OK) {
                releaseArrayRawData(handle)
                avifDecoderDestroy(decoder)
                return None
            }

            let decoderVal = decoder.read()
            let image = decoderVal.image
            let imageVal = image.read()
            let width = imageVal.width
            let height = imageVal.height

            // 分配像素缓冲区
            let pixelCount = Int64(width) * Int64(height) * 4
            var pixels = Array<UInt8>(pixelCount, repeat: 0)
            let pixelHandle = acquireArrayRawData(pixels)

            // 创建 RGB 图像结构并设置默认值
            var rgb = avifRGBImage(
                width, height, 8,
                avifRGBFormat_AVIF_RGB_FORMAT_RGBA,
                avifChromaUpsampling_AVIF_CHROMA_UPSAMPLING_AUTOMATIC,
                avifChromaDownsampling_AVIF_CHROMA_DOWNSAMPLING_AUTOMATIC,
                0, 0, 0, 0, 0,
                CString(pixelHandle.pointer),
                width * 4
            )

            // 使用 avifRGBImageSetDefaults 设置默认值，然后手动设置 pixels
            avifRGBImageSetDefaults(CPointer<avifRGBImage>(inout rgb), image)

            // 重新设置 pixels 和 rowBytes（因为 SetDefaults 会清空它们）
            rgb = avifRGBImage(
                rgb.width, rgb.height, 8,
                rgb.format,
                rgb.chromaUpsampling,
                rgb.chromaDownsampling,
                rgb.avoidLibYUV,
                rgb.ignoreAlpha,
                rgb.alphaPremultiplied,
                rgb.isFloat,
                rgb.maxThreads,
                CString(pixelHandle.pointer),
                width * 4
            )

            let yuvRes = avifImageYUVToRGB(image, CPointer<avifRGBImage>(inout rgb))

            releaseArrayRawData(pixelHandle)
            releaseArrayRawData(handle)
            avifDecoderDestroy(decoder)

            if (yuvRes != avifResult_AVIF_RESULT_OK) {
                return None
            }

            return (width, height, pixels)
        }
    }

    /**
     * 获取 libavif 版本
     */
    public static func version(): String {
        unsafe {
            return avifVersion().toString()
        }
    }
}
