package lcodec

import std.collection.ArrayList
import std.sync.Mutex

/*
 * libavif 直连回退（AVIF 系统解码器不支持的分支：4:4:4 profile、12-bit 等）。
 *
 * 系统 ImageSource 的 AvifDecoderImpl 只认 4:2:0 系列布局（真机日志
 * "IsSupportedPixelFormat unsupported layout : 3"），4:4:4 封面解不出来。
 * 这条路径用随包的 libavif（解码器 dav1d）补齐：libavif.so.16 + libdav1d.so.7
 * 打进 HAP，运行时 dlopen，链接期不依赖任何解码库。
 *
 * 结构体偏移来自 avif.h（libavif 1.1.1，LP64 下实测）：
 *   avifRGBImage(64B): width@0 height@4 depth@8 format@12 pixels@48 rowBytes@56
 *   avifImage:         width@0 height@4 depth@8
 * 只读这几个字段，其余字段交给 libavif 自己维护。
 */

private type FnDecoderCreate = CFunc<() -> CPointer<Unit>>
private type FnDecoderDestroy = CFunc<(CPointer<Unit>) -> Unit>
private type FnDecoderReadFile = CFunc<(CPointer<Unit>, CPointer<Unit>, CString) -> Int32>
private type FnResultToString = CFunc<(Int32) -> CString>
private type FnImageCreateEmpty = CFunc<() -> CPointer<Unit>>
private type FnImageDestroy = CFunc<(CPointer<Unit>) -> Unit>
private type FnRgbSetDefaults = CFunc<(CPointer<Unit>, CPointer<Unit>) -> Unit>
private type FnRgbAlloc = CFunc<(CPointer<Unit>) -> Int32>
private type FnRgbFree = CFunc<(CPointer<Unit>) -> Unit>
private type FnYuvToRgb = CFunc<(CPointer<Unit>, CPointer<Unit>) -> Int32>

// avif.h 的 LP64 布局常量（见文件头注释）。
private let RGB_SIZE: Int64 = 64
private let RGB_WIDTH: Int64 = 0
private let RGB_HEIGHT: Int64 = 4
private let RGB_FORMAT: Int64 = 12
private let RGB_PIXELS: Int64 = 48
private let RGB_ROW_BYTES: Int64 = 56
// AVIF_RGB_FORMAT_RGBA = 1（avifRGBFormat 枚举第 2 个）。
private let FMT_RGBA: Int32 = 1
private let AVIF_OK: Int32 = 0

private let AVIF_LIB_NAMES = ["libavif.so.16", "libavif.so"]

private var avifState: Int8 = 0
private var avifLoadError = ""
private let avifMutex = Mutex()

private var fnDecoderCreate: ?FnDecoderCreate = None
private var fnDecoderDestroy: ?FnDecoderDestroy = None
private var fnDecoderReadFile: ?FnDecoderReadFile = None
private var fnResultToString: ?FnResultToString = None
private var fnImageCreateEmpty: ?FnImageCreateEmpty = None
private var fnImageDestroy: ?FnImageDestroy = None
private var fnRgbSetDefaults: ?FnRgbSetDefaults = None
private var fnRgbAlloc: ?FnRgbAlloc = None
private var fnRgbFree: ?FnRgbFree = None
private var fnYuvToRgb: ?FnYuvToRgb = None

private func ensureAvifBackend(): Bool {
    synchronized(avifMutex) {
        if (avifState == 1) {
            return true
        }
        if (avifState == -1) {
            return false
        }
        avifState = -1
        var handle = CPointer<Unit>()
        for (n in AVIF_LIB_NAMES) {
            let h = openLib(n)
            if (!h.isNull()) {
                handle = h
                break
            }
        }
        if (handle.isNull()) {
            avifLoadError = "libavif 未随包提供（4:4:4/12-bit AVIF 暂不可解）"
            return false
        }
        var missing = ArrayList<String>()
        func need(n: String): CPointer<Unit> {
            let p = symOf(handle, n)
            if (p.isNull()) {
                missing.add(n)
            }
            p
        }
        let sCreate = need("avifDecoderCreate")
        let sDestroy = need("avifDecoderDestroy")
        let sReadFile = need("avifDecoderReadFile")
        let sStr = need("avifResultToString")
        let sImgCreate = need("avifImageCreateEmpty")
        let sImgDestroy = need("avifImageDestroy")
        let sSetDef = need("avifRGBImageSetDefaults")
        let sRgbAlloc = need("avifRGBImageAllocatePixels")
        let sRgbFree = need("avifRGBImageFreePixels")
        let sYuv2Rgb = need("avifImageYUVToRGB")
        if (!missing.isEmpty()) {
            avifLoadError = "libavif 缺少符号: ${missing}"
            return false
        }
        fnDecoderCreate = Some(CFunc<() -> CPointer<Unit>>(sCreate))
        fnDecoderDestroy = Some(CFunc<(CPointer<Unit>) -> Unit>(sDestroy))
        fnDecoderReadFile = Some(CFunc<(CPointer<Unit>, CPointer<Unit>, CString) -> Int32>(sReadFile))
        fnResultToString = Some(CFunc<(Int32) -> CString>(sStr))
        fnImageCreateEmpty = Some(CFunc<() -> CPointer<Unit>>(sImgCreate))
        fnImageDestroy = Some(CFunc<(CPointer<Unit>) -> Unit>(sImgDestroy))
        fnRgbSetDefaults = Some(CFunc<(CPointer<Unit>, CPointer<Unit>) -> Unit>(sSetDef))
        fnRgbAlloc = Some(CFunc<(CPointer<Unit>) -> Int32>(sRgbAlloc))
        fnRgbFree = Some(CFunc<(CPointer<Unit>) -> Unit>(sRgbFree))
        fnYuvToRgb = Some(CFunc<(CPointer<Unit>, CPointer<Unit>) -> Int32>(sYuv2Rgb))
        avifState = 1
        avifLoadError = ""
        return true
    }
}

// 把 libavif 的 avifResult 转成可读文本（诊断用）。
private func avifResultText(rc: Int32): String {
    match (fnResultToString) {
        case Some(f) =>
            let s = unsafe { f(rc) }
            if (s.isNull()) {
                return "rc=${rc}"
            }
            return unsafe { s.toString() } + " (${rc})"
        case None => return "rc=${rc}"
    }
}

/// libavif 直连回退。
public class AvifBackend {
    public static func available(): Bool {
        ensureAvifBackend()
    }

    public static func unavailableReason(): String {
        if (ensureAvifBackend()) {
            return ""
        }
        return avifLoadError
    }

    /// 解码 AVIF → 紧凑 RGBA（malloc 分配，调用方 freeRgba）。失败返回 None。
    public static func decodeRgba(path: String): ?SystemDecoded {
        if (!ensureAvifBackend()) {
            return None
        }
        let decoder = match (fnDecoderCreate) {
            case Some(f) => unsafe { f() }
            case None => CPointer<Unit>()
        }
        if (decoder.isNull()) {
            lastError = "avifDecoderCreate 失败"
            return None
        }
        var image = CPointer<Unit>()
        var rgb = CPointer<UInt8>()
        var result: ?SystemDecoded = None
        try {
            let createImg = match (fnImageCreateEmpty) {
                case Some(f) => unsafe { f() }
                case None => CPointer<Unit>()
            }
            if (createImg.isNull()) {
                lastError = "avifImageCreateEmpty 失败"
                return None
            }
            image = createImg
            let pathC = unsafe { LibC.mallocCString(path) }
            var readRc = Int32(-1)
            try {
                let f = fnDecoderReadFile.getOrThrow()
                readRc = unsafe { f(decoder, image, pathC) }
            } finally {
                unsafe { LibC.free(pathC) }
            }
            if (readRc != AVIF_OK) {
                lastError = "avifDecoderReadFile 失败: ${avifResultText(readRc)}"
                return None
            }
            let w = unsafe { CPointer<UInt32>(image + RGB_WIDTH).read() }
            let h = unsafe { CPointer<UInt32>(image + RGB_HEIGHT).read() }
            if (w == 0 || h == 0) {
                lastError = "libavif 尺寸非法 ${w}x${h}"
                return None
            }
            // avifRGBImage 是栈结构：malloc 一块零初始化的 64 字节，交给 libavif 填。
            rgb = unsafe { LibC.malloc<UInt8>(count: RGB_SIZE) }
            if (rgb.isNull()) {
                lastError = "avifRGBImage 分配失败"
                return None
            }
            unsafe {
                for (i in 0..RGB_SIZE) {
                    (rgb + i).write(0u8)
                }
            }
            let setDefaults = fnRgbSetDefaults.getOrThrow()
            unsafe { setDefaults(CPointer<Unit>(rgb), image) }
            // 目标格式固定 RGBA（服务端封面都是不透明 8-bit，够用且零转换分支）。
            unsafe { CPointer<Int32>(rgb + RGB_FORMAT).write(FMT_RGBA) }
            let allocRc = fnRgbAlloc.getOrThrow()
            let aRc = unsafe { allocRc(CPointer<Unit>(rgb)) }
            if (aRc != AVIF_OK) {
                lastError = "avifRGBImageAllocatePixels 失败: ${avifResultText(aRc)}"
                return None
            }
            let yuv2rgb = fnYuvToRgb.getOrThrow()
            let cRc = unsafe { yuv2rgb(image, CPointer<Unit>(rgb)) }
            if (cRc != AVIF_OK) {
                lastError = "avifImageYUVToRGB 失败: ${avifResultText(cRc)}"
                return None
            }
            let rw = unsafe { CPointer<UInt32>(rgb + RGB_WIDTH).read() }
            let rh = unsafe { CPointer<UInt32>(rgb + RGB_HEIGHT).read() }
            let rowBytes = unsafe { CPointer<UInt32>(rgb + RGB_ROW_BYTES).read() }
            let srcPixels = unsafe { CPointer<CPointer<UInt8>>(rgb + RGB_PIXELS).read() }
            if (srcPixels.isNull() || rw == 0 || rh == 0) {
                lastError = "libavif 像素缓冲为空"
                return None
            }
            let iw = Int32(rw)
            let ih = Int32(rh)
            let stride = if (rowBytes > 0) { Int64(rowBytes) } else { Int64(iw) * 4 }
            let tight = Int64(iw) * Int64(ih) * 4
            let out = unsafe { LibC.malloc<UInt8>(count: tight) }
            if (out.isNull()) {
                lastError = "输出缓冲分配失败"
                return None
            }
            unsafe {
                for (y in 0..Int64(ih)) {
                    memcpy(out + y * Int64(iw) * 4, srcPixels + y * stride, UIntNative(Int64(iw) * 4))
                }
            }
            result = Some(SystemDecoded(iw, ih, out, tight))
            return result
        } finally {
            if (!rgb.isNull()) {
                match (fnRgbFree) {
                    case Some(f) => unsafe { f(CPointer<Unit>(rgb)) }
                    case None => ()
                }
                freeRgba(rgb)
            }
            if (!image.isNull()) {
                match (fnImageDestroy) {
                    case Some(f) => unsafe { f(image) }
                    case None => ()
                }
            }
            match (fnDecoderDestroy) {
                case Some(f) => unsafe { f(decoder) }
                case None => ()
            }
        }
    }

    /// 最近一次失败原因（诊断用）。
    public static var lastError: String = ""
}
