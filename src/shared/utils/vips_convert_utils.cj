package lanlu.shared.utils

import avif_ffi.*
import std.sync.*
import vips_ffi.*

/**
 * libvips-based image -> AVIF conversion helpers.
 *
 * This replaces the "bind one decoder per format" approach for most inputs:
 * libvips handles decoding/resizing/cropping, and libavif encodes the final
 * RGBA pixels to AVIF so alpha is preserved for transparent PNG inputs.
 */
public class RgbaPixelsData {
    public let pixels: Array<UInt8>
    public let width: Int32
    public let height: Int32

    public init(pixels: Array<UInt8>, width: Int32, height: Int32) {
        this.pixels = pixels
        this.width = width
        this.height = height
    }
}

public enum ImageConvertResult<T> {
    | Ok(T)
    | Err(String)
}

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

    private static func normalizeToRgbaU8(img: VipsImagePtr): ImageConvertResult<VipsImagePtr> {
        // Best-effort normalize for hashing:
        // - colourspace -> sRGB
        // - cast -> UCHAR (8-bit)
        // - ensure 4 bands (RGBA)
        var srgb: VipsImagePtr = CPointer<VipsImage>()
        var u8: VipsImagePtr = CPointer<VipsImage>()
        var rgb: VipsImagePtr = CPointer<VipsImage>()
        var rgba: VipsImagePtr = CPointer<VipsImage>()

        let csRc = VipsApi.colourspaceSRgb(img, CPointer<VipsImagePtr>(inout srgb))
        if (csRc != 0 || srgb.isNull()) {
            let err = takeVipsError()
            return ImageConvertResult<VipsImagePtr>.Err("libvips colourspace failed: ${err}")
        }

        let castRc = VipsApi.castUChar(srgb, CPointer<VipsImagePtr>(inout u8))
        if (castRc != 0 || u8.isNull()) {
            let err = takeVipsError()
            unref(srgb)
            return ImageConvertResult<VipsImagePtr>.Err("libvips cast_uchar failed: ${err}")
        }

        let bands = VipsApi.imageBands(u8)
        if (bands == 4) {
            // Caller takes ownership of u8; keep srgb alive until u8 created.
            unref(srgb)
            return ImageConvertResult<VipsImagePtr>.Ok(u8)
        }

        if (bands == 3) {
            let alphaRc = VipsApi.bandjoinConstAlpha255(u8, CPointer<VipsImagePtr>(inout rgba))
            unref(u8)
            unref(srgb)
            if (alphaRc != 0 || rgba.isNull()) {
                let err = takeVipsError()
                return ImageConvertResult<VipsImagePtr>.Err("libvips add alpha failed: ${err}")
            }
            return ImageConvertResult<VipsImagePtr>.Ok(rgba)
        }

        if (bands == 2) {
            // Expand GREY+A into RGBA while preserving the original alpha channel.
            var grey: VipsImagePtr = CPointer<VipsImage>()
            var alpha: VipsImagePtr = CPointer<VipsImage>()

            let greyRc = VipsApi.extractBand(u8, CPointer<VipsImagePtr>(inout grey), 0)
            if (greyRc != 0 || grey.isNull()) {
                let err = takeVipsError()
                unref(u8)
                unref(srgb)
                return ImageConvertResult<VipsImagePtr>.Err("libvips extract grey band failed: ${err}")
            }

            let alphaRc = VipsApi.extractBand(u8, CPointer<VipsImagePtr>(inout alpha), 1)
            if (alphaRc != 0 || alpha.isNull()) {
                let err = takeVipsError()
                unref(grey)
                unref(u8)
                unref(srgb)
                return ImageConvertResult<VipsImagePtr>.Err("libvips extract alpha band failed: ${err}")
            }

            let arr = unsafe { LibC.malloc<VipsImagePtr>(count: 4) }
            unsafe {
                (arr + 0).write(grey)
                (arr + 1).write(grey)
                (arr + 2).write(grey)
                (arr + 3).write(alpha)
            }
            let joinRc = VipsApi.bandjoin(arr, CPointer<VipsImagePtr>(inout rgba), 4)
            unsafe { LibC.free(arr) }
            unref(alpha)
            unref(grey)
            unref(u8)
            unref(srgb)
            if (joinRc != 0 || rgba.isNull()) {
                let err = takeVipsError()
                return ImageConvertResult<VipsImagePtr>.Err("libvips bandjoin grey+alpha->rgba failed: ${err}")
            }
            return ImageConvertResult<VipsImagePtr>.Ok(rgba)
        }

        if (bands == 1) {
            // Replicate grey channel into RGB.
            let arr = unsafe { LibC.malloc<VipsImagePtr>(count: 3) }
            unsafe {
                (arr + 0).write(u8)
                (arr + 1).write(u8)
                (arr + 2).write(u8)
            }
            let joinRc = VipsApi.bandjoin(arr, CPointer<VipsImagePtr>(inout rgb), 3)
            unsafe { LibC.free(arr) }
            unref(u8)
            unref(srgb)
            if (joinRc != 0 || rgb.isNull()) {
                let err = takeVipsError()
                return ImageConvertResult<VipsImagePtr>.Err("libvips bandjoin grey->rgb failed: ${err}")
            }
            let alphaRc = VipsApi.bandjoinConstAlpha255(rgb, CPointer<VipsImagePtr>(inout rgba))
            unref(rgb)
            if (alphaRc != 0 || rgba.isNull()) {
                let err = takeVipsError()
                return ImageConvertResult<VipsImagePtr>.Err("libvips add alpha failed: ${err}")
            }
            return ImageConvertResult<VipsImagePtr>.Ok(rgba)
        }

        // Unknown band count.
        unref(u8)
        unref(srgb)
        return ImageConvertResult<VipsImagePtr>.Err("libvips unsupported bands for rgba normalization: ${bands}")
    }

    private static func extractRgbaPixelsFromImage(img: VipsImagePtr): ImageConvertResult<RgbaPixelsData> {
        let rgbaImg = match (normalizeToRgbaU8(img)) {
            case ImageConvertResult<VipsImagePtr>.Ok(value) => value
            case ImageConvertResult<VipsImagePtr>.Err(err) => return ImageConvertResult<RgbaPixelsData>.Err(err)
        }
        if (rgbaImg.isNull()) {
            return ImageConvertResult<RgbaPixelsData>.Err("libvips rgba normalization returned null image")
        }

        let w = VipsApi.imageWidth(rgbaImg)
        let h = VipsApi.imageHeight(rgbaImg)
        if (w <= 0 || h <= 0) {
            unref(rgbaImg)
            return ImageConvertResult<RgbaPixelsData>.Err("libvips invalid rgba dimensions: ${w}x${h}")
        }

        var size: UIntNative = 0
        let mem = VipsApi.writeToMemory(rgbaImg, CPointer<UIntNative>(inout size))
        unref(rgbaImg)
        if (mem.isNull() || size == 0) {
            let err = takeVipsError()
            return ImageConvertResult<RgbaPixelsData>.Err("libvips write_to_memory failed: ${err}")
        }

        let n = Int64(size)
        let expected = Int64(w) * Int64(h) * 4
        if (n != expected) {
            VipsApi.free(mem)
            return ImageConvertResult<RgbaPixelsData>.Err("libvips rgba buffer size mismatch: ${n} != ${expected}")
        }
        let maxPixelBytes: Int64 = 64 * 1024 * 1024
        if (n > maxPixelBytes) {
            VipsApi.free(mem)
            return ImageConvertResult<RgbaPixelsData>.Err("libvips image too large: ${n} bytes exceeds ${maxPixelBytes} limit")
        }
        var pixels = Array<UInt8>(n, repeat: 0u8)
        try {
            unsafe {
                let handle = acquireArrayRawData(pixels)
                let src = CPointer<UInt8>(mem)
                let dst = handle.pointer
                for (i in 0..n) {
                    (dst + i).write(src.read(i))
                }
                releaseArrayRawData(handle)
            }
        } finally {
            VipsApi.free(mem)
        }

        return ImageConvertResult<RgbaPixelsData>.Ok(RgbaPixelsData(pixels, w, h))
    }

    private static func hashRgbaPixelsFromImage(img: VipsImagePtr): ImageConvertResult<String> {
        let rgba = match (extractRgbaPixelsFromImage(img)) {
            case ImageConvertResult<RgbaPixelsData>.Ok(value) => value
            case ImageConvertResult<RgbaPixelsData>.Err(err) => return ImageConvertResult<String>.Err(err)
        }

        let hash = ThumbHashUtils.calculateThumbHashFromRgbaPixels(rgba.pixels)
        return ImageConvertResult<String>.Ok(hash)
    }

    private static func encodeAvifFromImage(img: VipsImagePtr, outputPath: String): ImageConvertResult<Unit> {
        let rgba = match (extractRgbaPixelsFromImage(img)) {
            case ImageConvertResult<RgbaPixelsData>.Ok(value) => value
            case ImageConvertResult<RgbaPixelsData>.Err(err) => return ImageConvertResult<Unit>.Err(err)
        }

        if (!AvifEncoder.encodeRGBAFile(UInt32(rgba.width), UInt32(rgba.height), rgba.pixels, outputPath)) {
            return ImageConvertResult<Unit>.Err("libavif encode failed")
        }
        return ImageConvertResult<Unit>.Ok(())
    }

    /**
     * Decode an image into RGBA8 pixels, scaled/cropped to exactly `outW` x `outH` (center-crop cover).
     *
     * Returns None only when libvips is unavailable/uninitialized.
     * On decode failure, returns Some(empty array) so caller can fallback.
     */
    public static func tryDecodeRgbaCoverPixels(inputPath: String, outW: Int32, outH: Int32): ?Array<UInt8> {
        if (!ensureInit()) {
            return Some(Array<UInt8>())
        }
        if (outW <= 0 || outH <= 0) {
            return Some(Array<UInt8>())
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
                return Some(Array<UInt8>())
            }

            // Autorotate based on metadata.
            let rotRc = VipsApi.autorot(inImg, CPointer<VipsImagePtr>(inout rotImg))
            if (rotRc != 0 || rotImg.isNull()) {
                return Some(Array<UInt8>())
            }

            let w = VipsApi.imageWidth(rotImg)
            let h = VipsApi.imageHeight(rotImg)
            if (w <= 0 || h <= 0) {
                return Some(Array<UInt8>())
            }

            // Scale to cover.
            let sx = Float64(outW) / Float64(w)
            let sy = Float64(outH) / Float64(h)
            let scale = if (sx > sy) { sx } else { sy }

            let resizeRc = VipsApi.resize(rotImg, CPointer<VipsImagePtr>(inout resizedImg), scale)
            if (resizeRc != 0 || resizedImg.isNull()) {
                return Some(Array<UInt8>())
            }

            let rw = VipsApi.imageWidth(resizedImg)
            let rh = VipsApi.imageHeight(resizedImg)
            if (rw <= 0 || rh <= 0) {
                return Some(Array<UInt8>())
            }

            // Center-crop to exact size.
            let left = if (rw > outW) { (rw - outW) / 2 } else { 0i32 }
            let top = if (rh > outH) { (rh - outH) / 2 } else { 0i32 }
            let cropRc = VipsApi.extractArea(resizedImg, CPointer<VipsImagePtr>(inout cropImg), left, top, outW, outH)
            if (cropRc != 0 || cropImg.isNull()) {
                return Some(Array<UInt8>())
            }

            match (extractRgbaPixelsFromImage(cropImg)) {
                case ImageConvertResult<RgbaPixelsData>.Ok(data) => return Some(data.pixels)
                case ImageConvertResult<RgbaPixelsData>.Err(_) => return Some(Array<UInt8>())
            }
        } catch (_: Exception) {
            return Some(Array<UInt8>())
        } finally {
            unref(cropImg)
            unref(resizedImg)
            unref(rotImg)
            unref(inImg)
        }
    }

    /**
     * Render text to an RGBA8 pixel buffer using libvips/pango.
     *
     * Returns None only when libvips is unavailable/uninitialized.
     * On render failure, returns Some((empty, 0, 0)).
     */
    public static func tryRenderTextRgbaPixels(
        text: String,
        font: String,
        maxWidth: Int32,
        maxHeight: Int32,
        wrapChar: Bool,
        lineSpacing: Int32
    ): ?(Array<UInt8>, Int32, Int32) {
        if (!ensureInit()) {
            return None
        }

        let t = text.trimAscii()
        if (t.size == 0 || maxWidth <= 0 || maxHeight <= 0) {
            return Some((Array<UInt8>(), 0i32, 0i32))
        }

        var outImg: VipsImagePtr = CPointer<VipsImage>()
        try {
            let tC = unsafe { LibC.mallocCString(t) }
            let fontC = unsafe { LibC.mallocCString(font) }
            try {
                let rc = VipsApi.text(CPointer<VipsImagePtr>(inout outImg), tC, fontC, maxWidth, maxHeight, true, wrapChar, lineSpacing)
                if (rc != 0 || outImg.isNull()) {
                    return Some((Array<UInt8>(), 0i32, 0i32))
                }
            } finally {
                unsafe {
                    LibC.free(fontC)
                    LibC.free(tC)
                }
            }

            let pixelsData = match (extractRgbaPixelsFromImage(outImg)) {
                case ImageConvertResult<RgbaPixelsData>.Ok(data) => data
                case ImageConvertResult<RgbaPixelsData>.Err(_) =>
                    unref(outImg)
                    return Some((Array<UInt8>(), 0i32, 0i32))
            }
            unref(outImg)
            return Some((pixelsData.pixels, pixelsData.width, pixelsData.height))
        } catch (_: Exception) {
            unref(outImg)
            return Some((Array<UInt8>(), 0i32, 0i32))
        }
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

            match (encodeAvifFromImage(finalImg, outputPath)) {
                case ImageConvertResult<Unit>.Ok(_) => ()
                case ImageConvertResult<Unit>.Err(err) => return Some(ProcessResultData(false, "", err))
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
     * Like tryConvertToAvifThumbnail(), but also returns a thumbhash computed from the
     * scaled/cropped RGBA pixels (without re-decoding the written AVIF).
     */
    public static func tryConvertToAvifThumbnailWithThumbHash(inputPath: String, outputPath: String, targetWidth: Int64, maxHeight: Int64): ?(ProcessResultData, String) {
        if (!ensureInit()) {
            return Some((ProcessResultData(false, "", "libvips init failed: ${initErr}"), ""))
        }

        if (targetWidth <= 0 || maxHeight <= 0) {
            return Some((ProcessResultData(false, "", "libvips invalid target size: ${targetWidth}x${maxHeight}"), ""))
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
                return Some((ProcessResultData(false, "", "libvips load failed: ${err}"), ""))
            }

            let rotRc = VipsApi.autorot(inImg, CPointer<VipsImagePtr>(inout rotImg))
            if (rotRc != 0 || rotImg.isNull()) {
                let err = takeVipsError()
                return Some((ProcessResultData(false, "", "libvips autorot failed: ${err}"), ""))
            }

            let w = VipsApi.imageWidth(rotImg)
            let h = VipsApi.imageHeight(rotImg)
            if (w <= 0 || h <= 0) {
                return Some((ProcessResultData(false, "", "libvips invalid input dimensions: ${w}x${h}"), ""))
            }

            let scale = Float64(targetWidth) / Float64(w)
            let resizeRc = VipsApi.resize(rotImg, CPointer<VipsImagePtr>(inout resizedImg), scale)
            if (resizeRc != 0 || resizedImg.isNull()) {
                let err = takeVipsError()
                return Some((ProcessResultData(false, "", "libvips resize failed: ${err}"), ""))
            }

            var rw = VipsApi.imageWidth(resizedImg)
            var rh = VipsApi.imageHeight(resizedImg)
            if (rw <= 0 || rh <= 0) {
                return Some((ProcessResultData(false, "", "libvips invalid resized dimensions: ${rw}x${rh}"), ""))
            }

            if (rw != Int32(targetWidth)) {
                var resized2: VipsImagePtr = CPointer<VipsImage>()
                let scale2 = Float64(targetWidth) / Float64(rw)
                let resizeRc2 = VipsApi.resize(resizedImg, CPointer<VipsImagePtr>(inout resized2), scale2)
                if (resizeRc2 != 0 || resized2.isNull()) {
                    let err = takeVipsError()
                    return Some((ProcessResultData(false, "", "libvips resize(2) failed: ${err}"), ""))
                }
                unref(resizedImg)
                resizedImg = resized2
                rw = VipsApi.imageWidth(resizedImg)
                rh = VipsApi.imageHeight(resizedImg)
            }

            let outW = if (rw > Int32(targetWidth)) { Int32(targetWidth) } else { rw }
            let outH = if (rh > Int32(maxHeight)) { Int32(maxHeight) } else { rh }
            if (outW <= 0 || outH <= 0) {
                return Some((ProcessResultData(false, "", "libvips invalid crop dimensions: ${outW}x${outH}"), ""))
            }

            let finalImg = if (outW == rw && outH == rh) {
                resizedImg
            } else {
                let cropRc = VipsApi.extractArea(resizedImg, CPointer<VipsImagePtr>(inout cropImg), 0, 0, outW, outH)
                if (cropRc != 0 || cropImg.isNull()) {
                    let err = takeVipsError()
                    return Some((ProcessResultData(false, "", "libvips crop failed: ${err}"), ""))
                }
                cropImg
            }

            // Compute thumbhash before writing, from the final pixels.
            var thumbHash = ""
            var hashErr = ""
            match (hashRgbaPixelsFromImage(finalImg)) {
                case ImageConvertResult<String>.Ok(value) => thumbHash = value
                case ImageConvertResult<String>.Err(err) => hashErr = err
            }
            if (thumbHash.size == 0) {
                match (encodeAvifFromImage(finalImg, outputPath)) {
                    case ImageConvertResult<Unit>.Ok(_) => ()
                    case ImageConvertResult<Unit>.Err(err) => return Some((ProcessResultData(false, "", err), ""))
                }
                return Some((ProcessResultData(true, outputPath, "thumbhash compute failed: ${hashErr}"), ""))
            }

            match (encodeAvifFromImage(finalImg, outputPath)) {
                case ImageConvertResult<Unit>.Ok(_) => ()
                case ImageConvertResult<Unit>.Err(err) => return Some((ProcessResultData(false, "", err), ""))
            }

            return Some((ProcessResultData(true, outputPath, ""), thumbHash))
        } catch (e: Exception) {
            return Some((ProcessResultData(false, "", "libvips exception: ${e.message}"), ""))
        } finally {
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

            match (encodeAvifFromImage(cropImg, outputPath)) {
                case ImageConvertResult<Unit>.Ok(_) => ()
                case ImageConvertResult<Unit>.Err(err) => return Some(ProcessResultData(false, "", err))
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

    public static func tryConvertAvatarToAvifWithThumbHash(inputPath: String, outputPath: String, size: Int64): ?(ProcessResultData, String) {
        if (!ensureInit()) {
            return Some((ProcessResultData(false, "", "libvips init failed: ${initErr}"), ""))
        }
        if (size <= 0) {
            return Some((ProcessResultData(false, "", "libvips invalid avatar size: ${size}"), ""))
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
                return Some((ProcessResultData(false, "", "libvips load failed: ${err}"), ""))
            }

            let rotRc = VipsApi.autorot(inImg, CPointer<VipsImagePtr>(inout rotImg))
            if (rotRc != 0 || rotImg.isNull()) {
                let err = takeVipsError()
                return Some((ProcessResultData(false, "", "libvips autorot failed: ${err}"), ""))
            }

            let w = VipsApi.imageWidth(rotImg)
            let h = VipsApi.imageHeight(rotImg)
            if (w <= 0 || h <= 0) {
                return Some((ProcessResultData(false, "", "libvips invalid input dimensions: ${w}x${h}"), ""))
            }

            let s = Int32(size)
            let scaleW = Float64(s) / Float64(w)
            let scaleH = Float64(s) / Float64(h)
            let scale = if (scaleW > scaleH) { scaleW } else { scaleH }

            let resizeRc = VipsApi.resize(rotImg, CPointer<VipsImagePtr>(inout resizedImg), scale)
            if (resizeRc != 0 || resizedImg.isNull()) {
                let err = takeVipsError()
                return Some((ProcessResultData(false, "", "libvips resize failed: ${err}"), ""))
            }

            let rw = VipsApi.imageWidth(resizedImg)
            let rh = VipsApi.imageHeight(resizedImg)
            if (rw < s || rh < s) {
                return Some((ProcessResultData(false, "", "libvips resized too small: ${rw}x${rh} (need >= ${s}x${s})"), ""))
            }

            let left = (rw - s) / 2
            let top = (rh - s) / 2
            let cropRc = VipsApi.extractArea(resizedImg, CPointer<VipsImagePtr>(inout cropImg), left, top, s, s)
            if (cropRc != 0 || cropImg.isNull()) {
                let err = takeVipsError()
                return Some((ProcessResultData(false, "", "libvips crop failed: ${err}"), ""))
            }

            var thumbHash = ""
            var hashErr = ""
            match (hashRgbaPixelsFromImage(cropImg)) {
                case ImageConvertResult<String>.Ok(value) => thumbHash = value
                case ImageConvertResult<String>.Err(err) => hashErr = err
            }
            match (encodeAvifFromImage(cropImg, outputPath)) {
                case ImageConvertResult<Unit>.Ok(_) => ()
                case ImageConvertResult<Unit>.Err(err) => return Some((ProcessResultData(false, "", err), ""))
            }
            if (thumbHash.size == 0) {
                return Some((ProcessResultData(true, outputPath, "thumbhash compute failed: ${hashErr}"), ""))
            }
            return Some((ProcessResultData(true, outputPath, ""), thumbHash))
        } catch (e: Exception) {
            return Some((ProcessResultData(false, "", "libvips exception: ${e.message}"), ""))
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

    public static func tryConvertTagBackgroundToAvifWithThumbHash(inputPath: String, outputPath: String, targetWidth: Int64, maxHeight: Int64): ?(ProcessResultData, String) {
        return tryConvertToAvifThumbnailWithThumbHash(inputPath, outputPath, targetWidth, maxHeight)
    }
}
