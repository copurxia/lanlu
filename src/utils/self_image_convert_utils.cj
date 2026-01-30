package lanlu.utils

import std.fs.*
import png_ffi.*
import avif_ffi.*

/**
 * Self-implemented image->AVIF conversion pipeline.
 *
 * Design goal: keep this extensible for adding more decoders in the future
 * (e.g. jpeg_ffi/webp_ffi), while providing a fast/robust first-choice path
 * for formats we can decode ourselves.
 */
public class SelfImageConvertUtils {
    /**
     * Convert an image file to an AVIF thumbnail:
     * - scale to `targetWidth`, preserving aspect ratio
     * - crop height to at most `maxHeight` (top-aligned)
     *
     * Returns Some(ProcessResultData) if a self-backend handled the input;
     * returns None if no self-backend supports the input (caller should fallback).
     */
    public static func tryConvertToAvifThumbnail(inputPath: String, outputPath: String, targetWidth: Int64, maxHeight: Int64): ?ProcessResultData {
        let ext = ArchiveUtils.getFileExtension(inputPath)

        // Currently only PNG is supported by self path.
        if (ext != "png") {
            return None
        }

        try {
            let bytes = readAllBytes(inputPath)
            if (let Some((w, h, rgba)) <- PngDecoder.decodeRGBA(bytes)) {
                let (tw, th, tpix) = resizeToWidthNearest(w, h, rgba, UInt32(targetWidth))
                let (cw, ch, cpix) = cropTop(tw, th, tpix, UInt32(maxHeight))

                let ok = AvifEncoder.encodeRGBAFile(cw, ch, cpix, outputPath)
                if (ok) {
                    return Some(ProcessResultData(true, outputPath, ""))
                }
                return Some(ProcessResultData(false, "", "Self PNG->AVIF (libpng+libavif) encode failed"))
            }
            return Some(ProcessResultData(false, "", "Self PNG->AVIF decode failed"))
        } catch (e: Exception) {
            return Some(ProcessResultData(false, "", "Self PNG->AVIF exception: ${e.message}"))
        }
    }

    private static func readAllBytes(pathStr: String): Array<UInt8> {
        let p = Path(pathStr)
        let f = File(p, Read)
        let size = Int64(f.info.size)
        let buf = Array<UInt8>(size, repeat: 0u8)
        let n = f.read(buf)
        f.close()
        if (n <= 0) {
            return []
        }
        return buf[0..n]
    }

    private static func resizeToWidthNearest(srcW: UInt32, srcH: UInt32, rgba: Array<UInt8>, targetW: UInt32): (UInt32, UInt32, Array<UInt8>) {
        if (srcW == 0u32 || srcH == 0u32 || targetW == 0u32) {
            return (srcW, srcH, rgba)
        }
        if (srcW == targetW) {
            return (srcW, srcH, rgba)
        }

        let outW = targetW
        let outH = UInt32((Int64(srcH) * Int64(outW)) / Int64(srcW))
        if (outH == 0u32) {
            return (outW, 1u32, Array<UInt8>(Int64(outW) * 4, repeat: 0u8))
        }

        var out = Array<UInt8>(Int64(outW) * Int64(outH) * 4, repeat: 0u8)

        let srcW64 = Int64(srcW)
        let srcH64 = Int64(srcH)
        let outW64 = Int64(outW)
        let outH64 = Int64(outH)

        for (y in 0..outH64) {
            let sy = (y * srcH64) / outH64
            for (x in 0..outW64) {
                let sx = (x * srcW64) / outW64
                let srcIdx = (sy * srcW64 + sx) * 4
                let dstIdx = (y * outW64 + x) * 4
                out[dstIdx] = rgba[srcIdx]
                out[dstIdx + 1] = rgba[srcIdx + 1]
                out[dstIdx + 2] = rgba[srcIdx + 2]
                out[dstIdx + 3] = rgba[srcIdx + 3]
            }
        }

        return (outW, outH, out)
    }

    private static func cropTop(w: UInt32, h: UInt32, rgba: Array<UInt8>, maxH: UInt32): (UInt32, UInt32, Array<UInt8>) {
        if (maxH == 0u32 || h <= maxH) {
            return (w, h, rgba)
        }

        let outH = maxH
        var out = Array<UInt8>(Int64(w) * Int64(outH) * 4, repeat: 0u8)
        let rowBytes = Int64(w) * 4

        for (y in 0..Int64(outH)) {
            let srcOff = y * rowBytes
            let dstOff = y * rowBytes
            for (i in 0..rowBytes) {
                out[dstOff + i] = rgba[srcOff + i]
            }
        }

        return (w, outH, out)
    }
}

