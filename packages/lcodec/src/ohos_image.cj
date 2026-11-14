package lcodec

import std.collection.ArrayList
import std.sync.Mutex

/*
 * 系统 ImageSource 直连后端（OHOS）。
 *
 * 定位：lcodec 不再经过 vips 形状的中间层，直接对接设备自带的图片解码框架
 * （libimage_source.so + libpixelmap.so）。这两个库随系统提供，不在 HAP 里，
 * 因此用 dlopen/dlsym 运行时装载：桌面构建自然装载失败（没有这两个 .so），
 * 解码自动回落到 libvips，不需要任何平台条件编译。
 *
 * 为什么直连：
 *   - 之前 OHOS 走的是 ABI 兼容 shim（packages/lplatform-ohos/deps/vips/vips_shim.c），
 *     多一层 C 代码、多一个随包 .so，但能力仍是系统解码器（AVIF/HEIC 走 ImageSource）。
 *     直连后 shim 可以整体删除，HAP 少一个动态库。
 *   - 系统解码失败的分支（例如 AVIF 4:4:4 profile）由 decode.cj 再尝试 libavif，
 *     见 avif_backend.cj。
 *
 * 坐标/契约：像素格式优先 RGBA_8888(3)，失败依次退 0(系统默认) 与 4(BGRA_8888)；
 * 读回的 stride 可能大于 width*4，这里统一规整成紧凑 RGBA（R,G,B,A 字节序）。
 */

// ---------- 符号签名 ----------
private type FnCreateFromUri = CFunc<(CString, UIntNative, CPointer<CPointer<Unit>>) -> Int32>
private type FnCreatePixelmap = CFunc<(CPointer<Unit>, CPointer<Unit>, CPointer<CPointer<Unit>>) -> Int32>
private type FnRelease1 = CFunc<(CPointer<Unit>) -> Unit>
private type FnCreate1 = CFunc<(CPointer<CPointer<Unit>>) -> Int32>
private type FnSetFmt = CFunc<(CPointer<Unit>, Int32) -> Int32>
private type FnGetU32 = CFunc<(CPointer<Unit>, CPointer<UInt32>) -> Int32>
private type FnGetI32 = CFunc<(CPointer<Unit>, CPointer<Int32>) -> Int32>
private type FnGetInfo = CFunc<(CPointer<Unit>, CPointer<Unit>) -> Int32>
private type FnReadPx = CFunc<(CPointer<Unit>, CPointer<UInt8>, CPointer<UIntNative>) -> Int32>

private let IMAGE_LIB_NAMES = ["libimage_source.so", "libimage_source.z.so"]
private let PIXELMAP_LIB_NAMES = ["libpixelmap.so", "libpixelmap.z.so"]

// 像素格式：3=RGBA_8888（首选），0=UNKNOWN（系统默认），4=BGRA_8888。
private let RGBA_8888: Int32 = 3
private let FMT_UNKNOWN: Int32 = 0
private let BGRA_8888: Int32 = 4
private let PIXEL_FMT_BGRA: Int32 = 4

// 装载状态：0 未尝试 / 1 成功 / -1 失败。
private var sysState: Int8 = 0
private var sysLoadError = ""
private let sysMutex = Mutex()

private var sysHandleImage = CPointer<Unit>()
private var sysHandlePixelmap = CPointer<Unit>()

private var fnCreateFromUri: ?FnCreateFromUri = None
private var fnCreatePixelmap: ?FnCreatePixelmap = None
private var fnSourceRelease: ?FnRelease1 = None
private var fnOptCreate: ?FnCreate1 = None
private var fnOptSetFmt: ?FnSetFmt = None
private var fnOptRelease: ?FnRelease1 = None
private var fnInfoCreate: ?FnCreate1 = None
private var fnInfoGetWidth: ?FnGetU32 = None
private var fnInfoGetHeight: ?FnGetU32 = None
private var fnInfoGetStride: ?FnGetU32 = None
private var fnInfoGetFmt: ?FnGetI32 = None
private var fnInfoRelease: ?FnRelease1 = None
private var fnPixelmapGetInfo: ?FnGetInfo = None
private var fnPixelmapReadPixels: ?FnReadPx = None
private var fnPixelmapRelease: ?FnRelease1 = None

// 一次装载：任一符号缺失即整体失败（宁可明确报错，不要半可用状态）。
private func ensureSystemBackend(): Bool {
    synchronized(sysMutex) {
        if (sysState == 1) {
            return true
        }
        if (sysState == -1) {
            return false
        }
        sysState = -1
        for (n in IMAGE_LIB_NAMES) {
            let h = openLib(n)
            if (!h.isNull()) {
                sysHandleImage = h
                break
            }
        }
        for (n in PIXELMAP_LIB_NAMES) {
            let h = openLib(n)
            if (!h.isNull()) {
                sysHandlePixelmap = h
                break
            }
        }
        if (sysHandleImage.isNull() || sysHandlePixelmap.isNull()) {
            sysLoadError = "系统 ImageSource 不可用（libimage_source/libpixelmap 均未找到）"
            return false
        }
        var missing = ArrayList<String>()
        func need(h: CPointer<Unit>, n: String): CPointer<Unit> {
            let p = symOf(h, n)
            if (p.isNull()) {
                missing.add(n)
            }
            p
        }
        let sUri = need(sysHandleImage, "OH_ImageSourceNative_CreateFromUri")
        let sPm = need(sysHandleImage, "OH_ImageSourceNative_CreatePixelmap")
        let sIsRel = need(sysHandleImage, "OH_ImageSourceNative_Release")
        let sOptCreate = need(sysHandleImage, "OH_DecodingOptions_Create")
        let sOptSetFmt = need(sysHandleImage, "OH_DecodingOptions_SetPixelFormat")
        let sOptRel = need(sysHandleImage, "OH_DecodingOptions_Release")
        let sInfoCreate = need(sysHandlePixelmap, "OH_PixelmapImageInfo_Create")
        let sInfoW = need(sysHandlePixelmap, "OH_PixelmapImageInfo_GetWidth")
        let sInfoH = need(sysHandlePixelmap, "OH_PixelmapImageInfo_GetHeight")
        let sInfoS = need(sysHandlePixelmap, "OH_PixelmapImageInfo_GetRowStride")
        let sInfoFmt = need(sysHandlePixelmap, "OH_PixelmapImageInfo_GetPixelFormat")
        let sInfoRel = need(sysHandlePixelmap, "OH_PixelmapImageInfo_Release")
        let sGetInfo = need(sysHandlePixelmap, "OH_PixelmapNative_GetImageInfo")
        let sReadPx = need(sysHandlePixelmap, "OH_PixelmapNative_ReadPixels")
        let sPmRel = need(sysHandlePixelmap, "OH_PixelmapNative_Release")
        if (!missing.isEmpty()) {
            sysLoadError = "系统 ImageSource 缺少符号: ${missing}"
            return false
        }
        fnCreateFromUri = Some(CFunc<(CString, UIntNative, CPointer<CPointer<Unit>>) -> Int32>(sUri))
        fnCreatePixelmap = Some(CFunc<(CPointer<Unit>, CPointer<Unit>, CPointer<CPointer<Unit>>) -> Int32>(sPm))
        fnSourceRelease = Some(CFunc<(CPointer<Unit>) -> Unit>(sIsRel))
        fnOptCreate = Some(CFunc<(CPointer<CPointer<Unit>>) -> Int32>(sOptCreate))
        fnOptSetFmt = Some(CFunc<(CPointer<Unit>, Int32) -> Int32>(sOptSetFmt))
        fnOptRelease = Some(CFunc<(CPointer<Unit>) -> Unit>(sOptRel))
        fnInfoCreate = Some(CFunc<(CPointer<CPointer<Unit>>) -> Int32>(sInfoCreate))
        fnInfoGetWidth = Some(CFunc<(CPointer<Unit>, CPointer<UInt32>) -> Int32>(sInfoW))
        fnInfoGetHeight = Some(CFunc<(CPointer<Unit>, CPointer<UInt32>) -> Int32>(sInfoH))
        fnInfoGetStride = Some(CFunc<(CPointer<Unit>, CPointer<UInt32>) -> Int32>(sInfoS))
        fnInfoGetFmt = Some(CFunc<(CPointer<Unit>, CPointer<Int32>) -> Int32>(sInfoFmt))
        fnInfoRelease = Some(CFunc<(CPointer<Unit>) -> Unit>(sInfoRel))
        fnPixelmapGetInfo = Some(CFunc<(CPointer<Unit>, CPointer<Unit>) -> Int32>(sGetInfo))
        fnPixelmapReadPixels = Some(CFunc<(CPointer<Unit>, CPointer<UInt8>, CPointer<UIntNative>) -> Int32>(sReadPx))
        fnPixelmapRelease = Some(CFunc<(CPointer<Unit>) -> Unit>(sPmRel))
        sysState = 1
        sysLoadError = ""
        return true
    }
}

/// 系统解码结果：紧凑 RGBA（malloc 分配，调用方用 freeRgba 释放）。
public struct SystemDecoded {
    public let width: Int32
    public let height: Int32
    public let pixels: CPointer<UInt8>
    public let size: Int64

    public init(width: Int32, height: Int32, pixels: CPointer<UInt8>, size: Int64) {
        this.width = width
        this.height = height
        this.pixels = pixels
        this.size = size
    }
}

/// 释放 SystemDecoded 的像素缓冲（幂等：空指针直接忽略）。
public func freeRgba(p: CPointer<UInt8>): Unit {
    if (!p.isNull()) {
        unsafe { LibC.free(p) }
    }
}

/// 系统图片解码后端（OHOS 系统库；桌面自然不可用，调用方回落 vips）。
public class SystemImageDecoder {
    /// 后端是否可用（dlopen 成功且符号齐全）。首次调用做一次装载，之后命中缓存。
    public static func available(): Bool {
        ensureSystemBackend()
    }

    public static func unavailableReason(): String {
        if (ensureSystemBackend()) {
            return ""
        }
        return sysLoadError
    }

    /// 解码任意系统支持的图片文件（PNG/JPEG/WebP/AVIF/HEIC/GIF/BMP）为紧凑 RGBA。
    /// 失败返回 None（原因写进 lastError）。
    public static func decodeRgba(path: String): ?SystemDecoded {
        if (!ensureSystemBackend()) {
            return None
        }
        let src = unsafe { LibC.mallocCString(path) }
        var source = CPointer<Unit>()
        var rc = Int32(-1)
        try {
            let f = fnCreateFromUri.getOrThrow()
            rc = unsafe { f(src, UIntNative(path.size), CPointer<CPointer<Unit>>(inout source)) }
        } finally {
            unsafe { LibC.free(src) }
        }
        if (rc != 0 || source.isNull()) {
            lastError = "CreateFromUri rc=${rc}"
            return None
        }
        var pixelmap = CPointer<Unit>()
        var usedFmt = Int32(-1)
        try {
            // 像素格式回退：AVIF/HEIC 的 10-bit/HDR 流在部分设备上不支持强制 RGBA_8888。
            for (fmt in [RGBA_8888, FMT_UNKNOWN, BGRA_8888]) {
                var opt = CPointer<Unit>()
                let fc = fnOptCreate.getOrThrow()
                unsafe { fc(CPointer<CPointer<Unit>>(inout opt)) }
                if (!opt.isNull()) {
                    let fs = fnOptSetFmt.getOrThrow()
                    unsafe { fs(opt, fmt) }
                }
                let cp = fnCreatePixelmap.getOrThrow()
                let e = unsafe { cp(source, opt, CPointer<CPointer<Unit>>(inout pixelmap)) }
                if (!opt.isNull()) {
                    let fr = fnOptRelease.getOrThrow()
                    unsafe { fr(opt) }
                }
                if (e == 0 && !pixelmap.isNull()) {
                    usedFmt = fmt
                    break
                }
                pixelmap = CPointer<Unit>()
                lastError = "CreatePixelmap rc=${e} fmt=${fmt}"
            }
        } finally {
            let fr = fnSourceRelease.getOrThrow()
            unsafe { fr(source) }
        }
        if (pixelmap.isNull()) {
            return None
        }

        var info = CPointer<Unit>()
        var w: UInt32 = 0
        var h: UInt32 = 0
        var stride: UInt32 = 0
        var fmtOut: Int32 = 0
        try {
            let fgi = fnPixelmapGetInfo.getOrThrow()
            let fic = fnInfoCreate.getOrThrow()
            unsafe { fic(CPointer<CPointer<Unit>>(inout info)) }
            let gi = unsafe { fgi(pixelmap, info) }
            if (gi != 0 || info.isNull()) {
                lastError = "GetImageInfo rc=${gi}"
                return None
            }
            let fw = fnInfoGetWidth.getOrThrow()
            let fh = fnInfoGetHeight.getOrThrow()
            let fs = fnInfoGetStride.getOrThrow()
            let ff = fnInfoGetFmt.getOrThrow()
            unsafe {
                fw(info, CPointer<UInt32>(inout w))
                fh(info, CPointer<UInt32>(inout h))
                fs(info, CPointer<UInt32>(inout stride))
                ff(info, CPointer<Int32>(inout fmtOut))
            }
        } finally {
            if (!info.isNull()) {
                let fir = fnInfoRelease.getOrThrow()
                unsafe { fir(info) }
            }
        }
        let iw = Int32(w)
        let ih = Int32(h)
        if (iw <= 0 || ih <= 0) {
            lastError = "尺寸非法 ${iw}x${ih}"
            let pr = fnPixelmapRelease.getOrThrow()
            unsafe { pr(pixelmap) }
            return None
        }
        let rowBytes = Int64(if (stride > 0) { stride } else { w * 4 })
        let bufSize = rowBytes * Int64(ih)
        let raw = unsafe { LibC.malloc<UInt8>(count: bufSize) }
        if (raw.isNull()) {
            let pr = fnPixelmapRelease.getOrThrow()
            unsafe { pr(pixelmap) }
            lastError = "像素缓冲分配失败"
            return None
        }
        var readSize = UIntNative(bufSize)
        var readRc = Int32(-1)
        try {
            let fr = fnPixelmapReadPixels.getOrThrow()
            readRc = unsafe { fr(pixelmap, raw, CPointer<UIntNative>(inout readSize)) }
        } finally {
            let pr = fnPixelmapRelease.getOrThrow()
            unsafe { pr(pixelmap) }
        }
        if (readRc != 0) {
            freeRgba(raw)
            lastError = "ReadPixels rc=${readRc}"
            return None
        }

        // 规整成紧凑 RGBA：去 stride 填充；BGRA 交换 R/B。
        let tight = Int64(iw) * Int64(ih) * 4
        let out = unsafe { LibC.malloc<UInt8>(count: tight) }
        if (out.isNull()) {
            freeRgba(raw)
            lastError = "输出缓冲分配失败"
            return None
        }
        let swapRb = fmtOut == PIXEL_FMT_BGRA || (fmtOut <= 0 && usedFmt == BGRA_8888)
        unsafe {
            for (y in 0..Int64(ih)) {
                let s = raw + y * rowBytes
                let d = out + y * Int64(iw) * 4
                if (swapRb) {
                    for (x in 0..Int64(iw)) {
                        let so = x * 4
                        let b = (s + so + 2).read()
                        let g = (s + so + 1).read()
                        let r = (s + so).read()
                        let a = (s + so + 3).read()
                        (d + so).write(r)
                        (d + so + 1).write(g)
                        (d + so + 2).write(b)
                        (d + so + 3).write(a)
                    }
                } else {
                    memcpy(d, s, UIntNative(Int64(iw) * 4))
                }
            }
        }
        freeRgba(raw)
        SystemDecoded(iw, ih, out, tight)
    }

    /// 最近一次失败原因（诊断用）。
    public static var lastError: String = ""
}
