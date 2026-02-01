package avif_ffi

import std.fs.*

/**
 * Minimal AVIF encoder for RGBA8 pixels using libavif.
 *
 * This is intentionally small: it supports the needs of thumbnail generation.
 * We can extend it later (quality/speed tuning, alpha policy, metadata, etc).
 */
@C
private struct RWDataView {
    public let data: CPointer<UInt8>
    public let size: UIntNative

    public init(data: CPointer<UInt8>, size: UIntNative) {
        this.data = data
        this.size = size
    }
}

public class AvifEncoder {
    private static func parentDir(path: String): String {
        let parts = path.split("/")
        if (parts.size > 1) {
            var result = ""
            for (i in 0..parts.size - 1) {
                if (i == 0 && parts[i].size == 0) {
                    result += "/"
                } else {
                    if (result.size > 0 && result != "/") {
                        result += "/"
                    }
                    result += parts[i]
                }
            }
            return result
        } else if (parts.size == 1) {
            if (parts[0].size == 0) { return "/" }
        }
        return ""
    }

    public static func encodeRGBAFile(width: UInt32, height: UInt32, pixels: Array<UInt8>, outputPath: String): Bool {
        if (width == 0u32 || height == 0u32) {
            return false
        }
        if (Int64(pixels.size) != Int64(width) * Int64(height) * 4) {
            return false
        }

        unsafe {
            let image = avifImageCreate(width, height, 8u32, avifPixelFormat_AVIF_PIXEL_FORMAT_YUV420)
            if (image.isNull()) {
                return false
            }

            let encoder = avifEncoderCreate()
            if (encoder.isNull()) {
                avifImageDestroy(image)
                return false
            }
            // Tune for "thumbnail-like" speed. Defaults can be extremely slow depending on codec.
            // We keep quality reasonable and prioritize runtime determinism for server-side tasks.
            try {
                let e0 = encoder.read()
                let tuned = avifEncoder(
                    e0.codecChoice,
                    1,          // maxThreads
                    8,          // speed (0=slowest, 10=fastest)
                    e0.keyframeInterval,
                    e0.timescale,
                    e0.repetitionCount,
                    e0.extraLayerCount,
                    60,         // quality
                    60,         // qualityAlpha
                    e0.minQuantizer,
                    e0.maxQuantizer,
                    e0.minQuantizerAlpha,
                    e0.maxQuantizerAlpha,
                    e0.tileRowsLog2,
                    e0.tileColsLog2,
                    e0.autoTiling,
                    e0.scalingMode,
                    e0.ioStats,
                    e0.diag,
                    e0.data,
                    e0.csOptions
                )
                encoder.write(tuned)
            } catch (_: Exception) {
                // Best-effort: if this fails, fall back to libavif defaults.
            }

            let pixelHandle = acquireArrayRawData(pixels)
            var rgb = avifRGBImage(
                width, height, 8u32,
                avifRGBFormat_AVIF_RGB_FORMAT_RGBA,
                avifChromaUpsampling_AVIF_CHROMA_UPSAMPLING_AUTOMATIC,
                avifChromaDownsampling_AVIF_CHROMA_DOWNSAMPLING_AUTOMATIC,
                0, 0, 0, 0, 1,
                CString(pixelHandle.pointer),
                width * 4u32
            )

            // Let libavif fill defaults based on the avifImage, then restore pixels/rowBytes.
            avifRGBImageSetDefaults(CPointer<avifRGBImage>(inout rgb), image)
            rgb = avifRGBImage(
                rgb.width, rgb.height, 8u32,
                rgb.format,
                rgb.chromaUpsampling,
                rgb.chromaDownsampling,
                rgb.avoidLibYUV,
                rgb.ignoreAlpha,
                rgb.alphaPremultiplied,
                rgb.isFloat,
                1,
                CString(pixelHandle.pointer),
                width * 4u32
            )

            let yuvRes = avifImageRGBToYUV(image, CPointer<avifRGBImage>(inout rgb))
            releaseArrayRawData(pixelHandle)
            if (yuvRes != avifResult_AVIF_RESULT_OK) {
                avifEncoderDestroy(encoder)
                avifImageDestroy(image)
                return false
            }

            // Encode to memory.
            var out = avifRWData(CString(CPointer<UInt8>()), 0)
            let encRes = avifEncoderWrite(encoder, image, CPointer<avifRWData>(inout out))

            avifEncoderDestroy(encoder)
            avifImageDestroy(image)

            if (encRes != avifResult_AVIF_RESULT_OK) {
                try { avifRWDataFree(CPointer<avifRWData>(inout out)) } catch (_: Exception) {}
                return false
            }

            // Write output bytes to file.
            let viewPtr = CPointer<RWDataView>(CPointer<avifRWData>(inout out))
            let view = viewPtr.read()
            let outSize = Int64(view.size)
            if (outSize <= 0) {
                avifRWDataFree(CPointer<avifRWData>(inout out))
                return false
            }

            var bytes = Array<UInt8>(outSize, repeat: 0u8)
            let base = view.data
            for (i in 0..outSize) {
                bytes[i] = (base + i).read()
            }

            avifRWDataFree(CPointer<avifRWData>(inout out))

            // Ensure parent directory exists.
            try {
                let dir = parentDir(outputPath)
                if (dir.size > 0 && !exists(Path(dir))) {
                    Directory.create(Path(dir), recursive: true)
                }
            } catch (_: Exception) {}

            try {
                let f = File(Path(outputPath), Write)
                f.write(bytes)
                f.close()
                return true
            } catch (_: Exception) {
                return false
            }
        }
    }
}
