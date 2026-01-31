package lanlu.utils

import std.sync.*
import vips_ffi.*

/**
 * libvips-based image -> AVIF conversion helpers.
 *
 * This replaces the "bind one decoder per format" approach for most inputs:
 * libvips handles decoding/resizing/cropping, and writes AVIF if the system
 * has an AVIF-capable saver (usually via libheif).
 */
public class VipsConvertUtils {
    private static let initMutex: Mutex = Mutex()
    private static var initDone: Bool = false
    private static var initOk: Bool = false
    private static var initErr: String = ""

    private static func ensureInit(): Bool {
        initMutex.lock()
        if (initDone) {
            initMutex.unlock()
            return initOk
        }

        var ok = false
        var err = ""
        try {
            let nameC = unsafe { LibC.mallocCString("lanlu") }
            let rc = VipsApi.initialize(nameC)
            unsafe { LibC.free(nameC) }
            if (rc == 0) {
                ok = true
            } else {
                err = VipsApi.takeErrorString()
                ok = false
            }
        } catch (e: Exception) {
            err = e.message
            ok = false
        }

        initOk = ok
        initErr = err
        initDone = true
        initMutex.unlock()
        return initOk
    }

    private static func takeVipsError(): String {
        return VipsApi.takeErrorString()
    }

    private static func unref(img: VipsImagePtr): Unit {
        VipsApi.unref(img)
    }

    /**
     * Convert an image file to an AVIF thumbnail:
     * - scale to `targetWidth`, preserving aspect ratio
     * - crop height to at most `maxHeight` (top-aligned)
     *
     * Returns None only when libvips is unavailable/uninitialized.
     * On decode/encode failure, returns Some(failed) so caller can decide whether to fallback.
     */
    public static func tryConvertToAvifThumbnail(inputPath: String, outputPath: String, targetWidth: Int64, maxHeight: Int64): ?ProcessResultData {
        if (!ensureInit()) {
            // Keep this a soft failure so caller can use ImageMagick/FFmpeg fallbacks.
            return Some(ProcessResultData(false, "", "libvips init failed: ${initErr}"))
        }

        // Basic sanity.
        if (targetWidth <= 0 || maxHeight <= 0) {
            return Some(ProcessResultData(false, "", "libvips invalid target size: ${targetWidth}x${maxHeight}"))
        }

        var inImg: VipsImagePtr = CPointer<VipsImage>()
        var rotImg: VipsImagePtr = CPointer<VipsImage>()
        var resizedImg: VipsImagePtr = CPointer<VipsImage>()
        var cropImg: VipsImagePtr = CPointer<VipsImage>()

        try {
            let inC = unsafe { LibC.mallocCString(inputPath) }
            inImg = VipsApi.imageNewFromFile(inC)
            unsafe { LibC.free(inC) }
            if (inImg.isNull()) {
                let err = takeVipsError()
                return Some(ProcessResultData(false, "", "libvips load failed: ${err}"))
            }

            // Autorotate based on metadata.
            let rotRc = VipsApi.autorot(inImg, CPointer<VipsImagePtr>(inout rotImg))
            if (rotRc != 0 || rotImg.isNull()) {
                let err = takeVipsError()
                return Some(ProcessResultData(false, "", "libvips autorot failed: ${err}"))
            }

            let w = VipsApi.imageWidth(rotImg)
            let h = VipsApi.imageHeight(rotImg)
            if (w <= 0 || h <= 0) {
                return Some(ProcessResultData(false, "", "libvips invalid input dimensions: ${w}x${h}"))
            }

            let scale = Float64(targetWidth) / Float64(w)
            let resizeRc = VipsApi.resize(rotImg, CPointer<VipsImagePtr>(inout resizedImg), scale)
            if (resizeRc != 0 || resizedImg.isNull()) {
                let err = takeVipsError()
                return Some(ProcessResultData(false, "", "libvips resize failed: ${err}"))
            }

            var rw = VipsApi.imageWidth(resizedImg)
            var rh = VipsApi.imageHeight(resizedImg)
            if (rw <= 0 || rh <= 0) {
                return Some(ProcessResultData(false, "", "libvips invalid resized dimensions: ${rw}x${rh}"))
            }

            // vips_resize rounds dimensions; keep output width stable for UI/layout expectations.
            if (rw != Int32(targetWidth)) {
                var resized2: VipsImagePtr = CPointer<VipsImage>()
                let scale2 = Float64(targetWidth) / Float64(rw)
                let resizeRc2 = VipsApi.resize(resizedImg, CPointer<VipsImagePtr>(inout resized2), scale2)
                if (resizeRc2 != 0 || resized2.isNull()) {
                    let err = takeVipsError()
                    return Some(ProcessResultData(false, "", "libvips resize(2) failed: ${err}"))
                }
                unref(resizedImg)
                resizedImg = resized2
                rw = VipsApi.imageWidth(resizedImg)
                rh = VipsApi.imageHeight(resizedImg)
            }

            let outW = if (rw > Int32(targetWidth)) { Int32(targetWidth) } else { rw }
            let outH = if (rh > Int32(maxHeight)) { Int32(maxHeight) } else { rh }
            if (outW <= 0 || outH <= 0) {
                return Some(ProcessResultData(false, "", "libvips invalid crop dimensions: ${outW}x${outH}"))
            }

            let finalImg = if (outW == rw && outH == rh) {
                resizedImg
            } else {
                let cropRc = VipsApi.extractArea(resizedImg, CPointer<VipsImagePtr>(inout cropImg), 0, 0, outW, outH)
                if (cropRc != 0 || cropImg.isNull()) {
                    let err = takeVipsError()
                    return Some(ProcessResultData(false, "", "libvips crop failed: ${err}"))
                }
                cropImg
            }

            let outC = unsafe { LibC.mallocCString(outputPath) }
            let writeRc = VipsApi.writeToFile(finalImg, outC)
            unsafe { LibC.free(outC) }
            if (writeRc != 0) {
                let err = takeVipsError()
                return Some(ProcessResultData(false, "", "libvips write failed: ${err}"))
            }

            return Some(ProcessResultData(true, outputPath, ""))
        } catch (e: Exception) {
            return Some(ProcessResultData(false, "", "libvips exception: ${e.message}"))
        } finally {
            // Cleanup in reverse-ish order. Note: finalImg references either resizedImg or cropImg.
            unref(cropImg)
            unref(resizedImg)
            unref(rotImg)
            unref(inImg)
        }
    }

    /**
     * Convert an image file to a square AVIF avatar:
     * - scale to cover `size`x`size`
     * - center-crop to `size`x`size`
     */
    public static func tryConvertAvatarToAvif(inputPath: String, outputPath: String, size: Int64): ?ProcessResultData {
        if (!ensureInit()) {
            return Some(ProcessResultData(false, "", "libvips init failed: ${initErr}"))
        }
        if (size <= 0) {
            return Some(ProcessResultData(false, "", "libvips invalid avatar size: ${size}"))
        }

        var inImg: VipsImagePtr = CPointer<VipsImage>()
        var rotImg: VipsImagePtr = CPointer<VipsImage>()
        var resizedImg: VipsImagePtr = CPointer<VipsImage>()
        var cropImg: VipsImagePtr = CPointer<VipsImage>()

        try {
            let inC = unsafe { LibC.mallocCString(inputPath) }
            inImg = VipsApi.imageNewFromFile(inC)
            unsafe { LibC.free(inC) }
            if (inImg.isNull()) {
                let err = takeVipsError()
                return Some(ProcessResultData(false, "", "libvips load failed: ${err}"))
            }

            let rotRc = VipsApi.autorot(inImg, CPointer<VipsImagePtr>(inout rotImg))
            if (rotRc != 0 || rotImg.isNull()) {
                let err = takeVipsError()
                return Some(ProcessResultData(false, "", "libvips autorot failed: ${err}"))
            }

            let w = VipsApi.imageWidth(rotImg)
            let h = VipsApi.imageHeight(rotImg)
            if (w <= 0 || h <= 0) {
                return Some(ProcessResultData(false, "", "libvips invalid input dimensions: ${w}x${h}"))
            }

            let s = Int32(size)
            let scaleW = Float64(s) / Float64(w)
            let scaleH = Float64(s) / Float64(h)
            let scale = if (scaleW > scaleH) { scaleW } else { scaleH }

            let resizeRc = VipsApi.resize(rotImg, CPointer<VipsImagePtr>(inout resizedImg), scale)
            if (resizeRc != 0 || resizedImg.isNull()) {
                let err = takeVipsError()
                return Some(ProcessResultData(false, "", "libvips resize failed: ${err}"))
            }

            let rw = VipsApi.imageWidth(resizedImg)
            let rh = VipsApi.imageHeight(resizedImg)
            if (rw < s || rh < s) {
                return Some(ProcessResultData(false, "", "libvips resized too small: ${rw}x${rh} (need >= ${s}x${s})"))
            }

            let left = (rw - s) / 2
            let top = (rh - s) / 2
            let cropRc = VipsApi.extractArea(resizedImg, CPointer<VipsImagePtr>(inout cropImg), left, top, s, s)
            if (cropRc != 0 || cropImg.isNull()) {
                let err = takeVipsError()
                return Some(ProcessResultData(false, "", "libvips crop failed: ${err}"))
            }

            let outC = unsafe { LibC.mallocCString(outputPath) }
            let writeRc = VipsApi.writeToFile(cropImg, outC)
            unsafe { LibC.free(outC) }
            if (writeRc != 0) {
                let err = takeVipsError()
                return Some(ProcessResultData(false, "", "libvips write failed: ${err}"))
            }

            return Some(ProcessResultData(true, outputPath, ""))
        } catch (e: Exception) {
            return Some(ProcessResultData(false, "", "libvips exception: ${e.message}"))
        } finally {
            unref(cropImg)
            unref(resizedImg)
            unref(rotImg)
            unref(inImg)
        }
    }

    /**
     * Convert an image file to a tag background AVIF:
     * - scale to width=`targetWidth`, preserving aspect ratio
     * - crop height to at most `maxHeight` (top-aligned)
     */
    public static func tryConvertTagBackgroundToAvif(inputPath: String, outputPath: String, targetWidth: Int64, maxHeight: Int64): ?ProcessResultData {
        // Same policy as thumbnail, but kept separate for clarity (different dimensions).
        return tryConvertToAvifThumbnail(inputPath, outputPath, targetWidth, maxHeight)
    }
}
