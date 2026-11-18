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
 *   - 之前 OHOS 走的是 ABI 兼容 shim（同符号 libvips.so，stb_image 实现），多一层 C 代码、
 *     多一个随包 .so，能力仍受限于 stb_image。直连后 shim 已整体删除，HAP 少一个动态库
 *     （2026-11-17 清理，见 docs/lcodec.md「历史坑」）。
 *   - 系统解码失败的分支（例如 AVIF 4:4:4 profile）由 decode.cj 再尝试 libavif，
 *     见 avif_backend.cj。
 *
 * 坐标/契约：像素格式优先 RGBA_8888(3)，失败依次退 0(系统默认) 与 4(BGRA_8888)；
 * 读回的 stride 可能大于 width*4，这里统一规整成紧凑 RGBA（R,G,B,A 字节序）。
 */

// ---------- 符号签名 ----------
private type FnCreateFromUri = CFunc<(CString, UIntNative, CPointer<CPointer<Unit>>) -> Int32>
// OH_ImageSourceNative_CreateFromData(void *data, size_t dataSize, OH_ImageSourceNative **res)
// API 12+；老系统缺该符号时字节解码回退到 vips shim（stb_image）。
private type FnCreateFromData = CFunc<(CPointer<Unit>, UIntNative, CPointer<CPointer<Unit>>) -> Int32>
private type FnCreatePixelmap = CFunc<(CPointer<Unit>, CPointer<Unit>, CPointer<CPointer<Unit>>) -> Int32>
private type FnRelease1 = CFunc<(CPointer<Unit>) -> Unit>
private type FnCreate1 = CFunc<(CPointer<CPointer<Unit>>) -> Int32>
private type FnSetFmt = CFunc<(CPointer<Unit>, Int32) -> Int32>
private type FnGetU32 = CFunc<(CPointer<Unit>, CPointer<UInt32>) -> Int32>
private type FnGetI32 = CFunc<(CPointer<Unit>, CPointer<Int32>) -> Int32>
private type FnGetInfo = CFunc<(CPointer<Unit>, CPointer<Unit>) -> Int32>
private type FnReadPx = CFunc<(CPointer<Unit>, CPointer<UInt8>, CPointer<UIntNative>) -> Int32>
// G8：OH_DecodingOptions_SetDesiredSize(options, Image_Size*)——Image_Size = {uint32 w; uint32 h}
// 用 2×UInt32 的裸缓冲承载（aarch64 LP64 下与结构体布局一致，无填充）。
private type FnSetDesiredSize = CFunc<(CPointer<Unit>, CPointer<UInt32>) -> Int32>
// OH_ImageSourceNative_GetImageInfo(source, index, OH_ImageSource_Info*)
private type FnGetSourceInfo = CFunc<(CPointer<Unit>, Int32, CPointer<Unit>) -> Int32>

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
private var fnCreateFromData: ?FnCreateFromData = None
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
// G8 可选能力（API12+，缺失时后端仍可用，只是退回全尺寸解码）：
private var fnOptSetDesiredSize: ?FnSetDesiredSize = None
private var fnSourceInfoCreate: ?FnCreate1 = None
private var fnSourceInfoGetWidth: ?FnGetU32 = None
private var fnSourceInfoGetHeight: ?FnGetU32 = None
private var fnSourceInfoRelease: ?FnRelease1 = None
private var fnSourceGetImageInfo: ?FnGetSourceInfo = None

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
        // 可选：内存字节解码入口（API 12+）。缺符号只影响"从内存字节解码"，
        // 文件路径解码与其它能力必须继续可用。
        let oFromData = symOf(sysHandleImage, "OH_ImageSourceNative_CreateFromData")
        if (!oFromData.isNull()) {
            fnCreateFromData = Some(CFunc<(CPointer<Unit>, UIntNative, CPointer<CPointer<Unit>>) -> Int32>(oFromData))
        }
        // G8 可选符号：desiredSize 与源尺寸查询是"加速能力"，不是后端前置条件。
        // 老设备/老 API 缺这些符号时整体后端必须仍可用（否则会从"慢"退化成"不能解码"），
        // 因此这里不用上面的严格 need()，缺任何一个都只是跳过对应优化（行为=现状全尺寸解码）。
        let oDesired = symOf(sysHandleImage, "OH_DecodingOptions_SetDesiredSize")
        if (!oDesired.isNull()) {
            fnOptSetDesiredSize = Some(CFunc<(CPointer<Unit>, CPointer<UInt32>) -> Int32>(oDesired))
        }
        let oSiCreate = symOf(sysHandleImage, "OH_ImageSourceInfo_Create")
        let oSiW = symOf(sysHandleImage, "OH_ImageSourceInfo_GetWidth")
        let oSiH = symOf(sysHandleImage, "OH_ImageSourceInfo_GetHeight")
        let oSiRel = symOf(sysHandleImage, "OH_ImageSourceInfo_Release")
        let oGetInfo = symOf(sysHandleImage, "OH_ImageSourceNative_GetImageInfo")
        if (!oSiCreate.isNull() && !oSiW.isNull() && !oSiH.isNull() && !oSiRel.isNull() && !oGetInfo.isNull()) {
            fnSourceInfoCreate = Some(CFunc<(CPointer<CPointer<Unit>>) -> Int32>(oSiCreate))
            fnSourceInfoGetWidth = Some(CFunc<(CPointer<Unit>, CPointer<UInt32>) -> Int32>(oSiW))
            fnSourceInfoGetHeight = Some(CFunc<(CPointer<Unit>, CPointer<UInt32>) -> Int32>(oSiH))
            fnSourceInfoRelease = Some(CFunc<(CPointer<Unit>) -> Unit>(oSiRel))
            fnSourceGetImageInfo = Some(CFunc<(CPointer<Unit>, Int32, CPointer<Unit>) -> Int32>(oGetInfo))
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
    ///
    /// G8：`maxDimension > 0` 且系统支持 `OH_DecodingOptions_SetDesiredSize` 时，按源图
    /// 原始尺寸等比算出目标尺寸传给解码器（"全尺寸解码 + 仓颉双线性缩放"→"解码期缩放"）。
    /// 源尺寸取不到 / 老 API 缺符号时自动退回全尺寸（调用方的 resize 分支仍是兜底）。
    public static func decodeRgba(path: String, maxDimension!: Int32 = 0): ?SystemDecoded {
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
        decodeFromSource(source, maxDimension)
    }

    /// 从**内存字节**解码（内嵌资源、网络直收的字节）。入口是
    /// `OH_ImageSourceNative_CreateFromData`（API 12+）；缺该符号时返回 None，
    /// 调用方（decodeBytesToRgba）回退到 vips shim 的 stb_image 路径。
    ///
    /// 缓冲区在整个 `ImageSource` 生命周期内保持钉住（pin）：系统可能在
    /// `CreatePixelmap` 时才真正读取，提前放手就是 use-after-free。
    public static func decodeRgbaBytes(bytes: Array<UInt8>, maxDimension!: Int32 = 0): ?SystemDecoded {
        if (!ensureSystemBackend()) {
            return None
        }
        if (bytes.size == 0) {
            lastError = "空字节缓冲"
            return None
        }
        let create = match (fnCreateFromData) {
            case Some(f) => f
            case None =>
                lastError = "OH_ImageSourceNative_CreateFromData 不可用（API<12）"
                return None
        }
        let handle = unsafe { acquireArrayRawData(bytes) }
        try {
            var source = CPointer<Unit>()
            let rc = unsafe {
                create(CPointer<Unit>(handle.pointer), UIntNative(bytes.size), CPointer<CPointer<Unit>>(inout source))
            }
            if (rc != 0 || source.isNull()) {
                lastError = "CreateFromData rc=${rc}"
                return None
            }
            decodeFromSource(source, maxDimension)
        } finally {
            unsafe { releaseArrayRawData(handle) }
        }
    }

    /// URI / 内存字节两个入口共用的解码尾段：创建 Pixelmap → 读像素 → 规整成紧凑 RGBA。
    /// `source` 的所有权在尾部释放（本函数内完成，调用方不得再释放）。
    private static func decodeFromSource(source: CPointer<Unit>, maxDimension: Int32): ?SystemDecoded {
        var pixelmap = CPointer<Unit>()
        var usedFmt = Int32(-1)
        // G8：解码前按源尺寸算等比目标（file-space 像素；系统对 EXIF 的处理与全尺寸
        // 路径同源，因此不会改变现有方向语义）。取不到尺寸则 desiredW/H 保持 0（全尺寸）。
        var desiredW = Int32(0)
        var desiredH = Int32(0)
        if (maxDimension > 0 && fnOptSetDesiredSize.isSome()) {
            let (sw, sh) = sourceDimensions(source)
            let (dw, dh) = desiredSizeFor(sw, sh, maxDimension)
            if (dw > 0 && dh > 0) {
                desiredW = dw
                desiredH = dh
            }
        }
        lastDesiredSize = if (desiredW > 0) {
            "${desiredW}x${desiredH}(max=${maxDimension})"
        } else {
            "full"
        }
        try {
            // 像素格式回退：AVIF/HEIC 的 10-bit/HDR 流在部分设备上不支持强制 RGBA_8888。
            for (fmt in [RGBA_8888, FMT_UNKNOWN, BGRA_8888]) {
                var opt = CPointer<Unit>()
                let fc = fnOptCreate.getOrThrow()
                unsafe { fc(CPointer<CPointer<Unit>>(inout opt)) }
                if (!opt.isNull()) {
                    let fs = fnOptSetFmt.getOrThrow()
                    unsafe { fs(opt, fmt) }
                    // G8：同一 options 上追加 desiredSize（Image_Size{uint32 w, h}）。
                    if (desiredW > 0 && desiredH > 0) {
                        match (fnOptSetDesiredSize) {
                            case Some(fds) =>
                                let szBuf = unsafe { LibC.malloc<UInt32>(count: 2) }
                                if (!szBuf.isNull()) {
                                    unsafe {
                                        szBuf.write(0, UInt32(desiredW))
                                        (szBuf + 1).write(UInt32(desiredH))
                                    }
                                    let _ = unsafe { fds(opt, szBuf) }
                                    unsafe { LibC.free(szBuf) }
                                }
                            case None => ()
                        }
                    }
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

    /// 设备是否具备"内存字节"入口（`OH_ImageSourceNative_CreateFromData`，API 12+）。
    /// 为 false 时 `decodeBytesToRgba` 走临时文件回退（等价文件入口）。
    public static func bytesSupported(): Bool {
        if (!ensureSystemBackend()) {
            return false
        }
        fnCreateFromData.isSome()
    }

    /// 最近一次失败原因（诊断用）。
    public static var lastError: String = ""

    /// G8 诊断：最近一次解码的 desiredSize 决策（"WxH(max=N)" 或 "full"），供真机确认生效。
    public static var lastDesiredSize: String = ""

    // 读源图原始尺寸（file-space 像素）。任一可选符号缺失/调用失败返回 (0,0)。
    private static func sourceDimensions(source: CPointer<Unit>): (Int32, Int32) {
        if (fnSourceGetImageInfo.isNone() || fnSourceInfoCreate.isNone() ||
            fnSourceInfoGetWidth.isNone() || fnSourceInfoGetHeight.isNone() || fnSourceInfoRelease.isNone()) {
            return (0, 0)
        }
        let gi = fnSourceGetImageInfo.getOrThrow()
        let ic = fnSourceInfoCreate.getOrThrow()
        let gw = fnSourceInfoGetWidth.getOrThrow()
        let gh = fnSourceInfoGetHeight.getOrThrow()
        let rel = fnSourceInfoRelease.getOrThrow()
        var info = CPointer<Unit>()
        if (unsafe { ic(CPointer<CPointer<Unit>>(inout info)) } != 0 || info.isNull()) {
            return (0, 0)
        }
        var w: UInt32 = 0
        var h: UInt32 = 0
        let rc = unsafe { gi(source, 0, info) }
        if (rc == 0) {
            unsafe {
                gw(info, CPointer<UInt32>(inout w))
                gh(info, CPointer<UInt32>(inout h))
            }
        }
        unsafe { rel(info) }
        if (rc == 0 && w > 0 && h > 0) {
            (Int32(w), Int32(h))
        } else {
            (0, 0)
        }
    }
}

/// G8：按"最长边不超过 maxDimension、等比、不放大"计算目标尺寸。返回 (0,0) 表示无需缩放。
/// 纯函数（无 FFI），供解码路径与单测/对拍共用；四舍五入与桌面 vips_resize 的取整一致
/// （对拍实测：300x200@max100，vips 得 100x67，本函数同样 100x67）。
public func desiredSizeFor(srcW: Int32, srcH: Int32, maxDimension: Int32): (Int32, Int32) {
    if (maxDimension <= 0 || srcW <= 0 || srcH <= 0) {
        return (0, 0)
    }
    let longest = max(Int64(srcW), Int64(srcH))
    if (longest <= Int64(maxDimension)) {
        return (0, 0)
    }
    let scale = Float64(maxDimension) / Float64(longest)
    let dw = max(Int64(1), Int64(Float64(srcW) * scale + 0.5))
    let dh = max(Int64(1), Int64(Float64(srcH) * scale + 0.5))
    (Int32(dw), Int32(dh))
}
