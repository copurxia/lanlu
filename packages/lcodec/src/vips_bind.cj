package lcodec

import std.collection.ArrayList
import std.sync.Mutex

/*
 * libvips 运行时装载（lcodec 私有后端）。
 *
 * 为什么不用 vips_ffi 的 link-time 绑定：
 *   - 业务层（client-next）不应为解码器声明链接参数；cjpm 的静态依赖 link-option
 *     不向上传递（见 tools/…/lwindow 注释与实测），若 lcodec 直接 link vips，
 *     client-next 仍得自己写 -lvips —— 解码依赖就漏回业务层。
 *   - 改为运行时 dlopen：桌面加载系统 libvips；OHOS 加载随 HAP 打包的同名 shim。
 *     引擎二进制不再有 libvips 的 NEEDED，缺库时给明确错误而不是链接失败。
 *
 * varargs 处理：libvips 的可选参数以 NULL 结尾。CFunc 类型不能声明变长参数，
 * 这里给每个 varargs 函数多声明一个尾随 CPointer<Unit> 形参并固定传 NULL——
 * 在 x86_64 SysV 与 aarch64 AAPCS 上，这等价于只传一个 NULL 终止符。
 */

@C
public struct VipsImage {
    init() {
        throw Exception("type should not be inited")
    }
}

public type VipsImagePtr = CPointer<VipsImage>

public const VIPS_FORMAT_UCHAR: Int32 = 0
public const VIPS_INTERPRETATION_sRGB: Int32 = 22

// ---------- 平台动态库 API ----------

@When[os == "Windows"]
foreign func LoadLibraryA(name: CString): CPointer<Unit>

@When[os == "Windows"]
foreign func GetProcAddress(h: CPointer<Unit>, name: CString): CPointer<Unit>

@When[os != "Windows"]
foreign func dlopen(filename: CString, flag: Int32): CPointer<Unit>

@When[os != "Windows"]
foreign func dlsym(handle: CPointer<Unit>, symbol: CString): CPointer<Unit>

@When[os == "Windows"]
private func openLib(name: String): CPointer<Unit> {
    let c = unsafe { LibC.mallocCString(name) }
    let h = unsafe { LoadLibraryA(c) }
    unsafe { LibC.free(c) }
    h
}

@When[os == "Windows"]
private func symOf(handle: CPointer<Unit>, name: String): CPointer<Unit> {
    let c = unsafe { LibC.mallocCString(name) }
    let p = unsafe { GetProcAddress(handle, c) }
    unsafe { LibC.free(c) }
    p
}

@When[os != "Windows"]
private func openLib(name: String): CPointer<Unit> {
    let c = unsafe { LibC.mallocCString(name) }
    let h = unsafe { dlopen(c, 2) } // RTLD_NOW
    unsafe { LibC.free(c) }
    h
}

@When[os != "Windows"]
private func symOf(handle: CPointer<Unit>, name: String): CPointer<Unit> {
    let c = unsafe { LibC.mallocCString(name) }
    let p = unsafe { dlsym(handle, c) }
    unsafe { LibC.free(c) }
    p
}

// ---------- 函数指针类型（尾随形参 = varargs NULL 终止符） ----------

private type FnInit = CFunc<(CString) -> Int32>
private type FnVoid = CFunc<() -> Unit>
private type FnErrBuf = CFunc<() -> CString>
private type FnSetConcurrency = CFunc<(Int32) -> Unit>
private type FnNewFromFile = CFunc<(CString, CPointer<Unit>) -> CPointer<Unit>>
private type FnNewFromMemCopy = CFunc<(CPointer<Unit>, UIntNative, Int32, Int32, Int32, Int32) -> CPointer<Unit>>
private type FnGetInt = CFunc<(CPointer<Unit>) -> Int32>
private type FnOutOnly = CFunc<(CPointer<Unit>, CPointer<CPointer<Unit>>, CPointer<Unit>) -> Int32>
private type FnResize = CFunc<(CPointer<Unit>, CPointer<CPointer<Unit>>, Float64, CPointer<Unit>) -> Int32>
private type FnExtractBand = CFunc<(CPointer<Unit>, CPointer<CPointer<Unit>>, Int32, CPointer<Unit>) -> Int32>
private type FnColourspace = CFunc<(CPointer<Unit>, CPointer<CPointer<Unit>>, Int32, CPointer<Unit>) -> Int32>
private type FnBandjoinConst = CFunc<(CPointer<Unit>, CPointer<CPointer<Unit>>, Float64, CPointer<Unit>) -> Int32>
private type FnBandjoin = CFunc<(CPointer<CPointer<Unit>>, CPointer<CPointer<Unit>>, Int32, CPointer<Unit>) -> Int32>
private type FnExtractArea = CFunc<(CPointer<Unit>, CPointer<CPointer<Unit>>, Int32, Int32, Int32, Int32, CPointer<Unit>) -> Int32>
private type FnWriteFile = CFunc<(CPointer<Unit>, CString, CPointer<Unit>) -> Int32>
private type FnWriteMem = CFunc<(CPointer<Unit>, CPointer<UIntNative>) -> CPointer<Unit>>
private type FnFree = CFunc<(CPointer<Unit>) -> Unit>

// 候选库名：桌面发行版 soname 不一（Debian 12 是 .so.42，部分发行版 .so.43/.so.44）；
// OHOS 随 HAP 的 shim 固定 libvips.so。
private let LIB_NAMES = ["libvips.so", "libvips.so.42", "libvips.so.43", "libvips.so.44",
    "libvips.dylib", "libvips-42.dll", "libvips.dll"]

// 装载结果：0 未尝试 / 1 成功 / -1 失败（失败原因留在 loadError）。
private var backendState: Int8 = 0
private var loadError = ""
private let backendMutex = Mutex()

private var fnInit: ?FnInit = None
private var fnShutdown: ?FnVoid = None
private var fnErrorBuffer: ?FnErrBuf = None
private var fnErrorClear: ?FnVoid = None
private var fnConcurrency: ?FnSetConcurrency = None
private var fnNewFromFile: ?FnNewFromFile = None
private var fnNewFromMemCopy: ?FnNewFromMemCopy = None
private var fnGetWidth: ?FnGetInt = None
private var fnGetHeight: ?FnGetInt = None
private var fnGetBands: ?FnGetInt = None
private var fnAutorot: ?FnOutOnly = None
private var fnResize: ?FnResize = None
private var fnGaussblur: ?FnResize = None
private var fnExtractArea: ?FnExtractArea = None
private var fnExtractBand: ?FnExtractBand = None
private var fnColourspace: ?FnColourspace = None
private var fnCastUchar: ?FnOutOnly = None
private var fnBandjoinConst: ?FnBandjoinConst = None
private var fnBandjoin: ?FnBandjoin = None
private var fnWriteFile: ?FnWriteFile = None
private var fnWriteMem: ?FnWriteMem = None
private var fnUnref: ?FnFree = None
private var fnFree: ?FnFree = None

// 一次装载：任一符号缺失即整体失败（宁可明确报错，不要半可用状态）。
private func ensureBackend(): Bool {
    synchronized(backendMutex) {
        if (backendState == 1) {
            return true
        }
        if (backendState == -1) {
            return false
        }
        backendState = -1
        var handle = CPointer<Unit>()
        var usedName = ""
        for (n in LIB_NAMES) {
            let h = openLib(n)
            if (!h.isNull()) {
                handle = h
                usedName = n
                break
            }
        }
        if (handle.isNull()) {
            loadError = "libvips 不可用（尝试过 ${LIB_NAMES}）"
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
        let sInit = need("vips_init")
        let sShutdown = need("vips_shutdown")
        let sErrBuf = need("vips_error_buffer")
        let sErrClear = need("vips_error_clear")
        let sConc = need("vips_concurrency_set")
        let sNewFile = need("vips_image_new_from_file")
        let sNewMem = need("vips_image_new_from_memory_copy")
        let sW = need("vips_image_get_width")
        let sH = need("vips_image_get_height")
        let sB = need("vips_image_get_bands")
        let sAutorot = need("vips_autorot")
        let sResize = need("vips_resize")
        let sBlur = need("vips_gaussblur")
        let sArea = need("vips_extract_area")
        let sBand = need("vips_extract_band")
        let sCs = need("vips_colourspace")
        let sCast = need("vips_cast_uchar")
        let sJoinConst = need("vips_bandjoin_const1")
        let sJoin = need("vips_bandjoin")
        let sWriteFile = need("vips_image_write_to_file")
        let sWriteMem = need("vips_image_write_to_memory")
        let sUnref = need("g_object_unref")
        let sFree = need("g_free")
        if (!missing.isEmpty()) {
            loadError = "${usedName} 缺少符号: ${missing}"
            return false
        }
        fnInit = Some(CFunc<(CString) -> Int32>(sInit))
        fnShutdown = Some(CFunc<() -> Unit>(sShutdown))
        fnErrorBuffer = Some(CFunc<() -> CString>(sErrBuf))
        fnErrorClear = Some(CFunc<() -> Unit>(sErrClear))
        fnConcurrency = Some(CFunc<(Int32) -> Unit>(sConc))
        fnNewFromFile = Some(CFunc<(CString, CPointer<Unit>) -> CPointer<Unit>>(sNewFile))
        fnNewFromMemCopy = Some(CFunc<(CPointer<Unit>, UIntNative, Int32, Int32, Int32, Int32) -> CPointer<Unit>>(sNewMem))
        fnGetWidth = Some(CFunc<(CPointer<Unit>) -> Int32>(sW))
        fnGetHeight = Some(CFunc<(CPointer<Unit>) -> Int32>(sH))
        fnGetBands = Some(CFunc<(CPointer<Unit>) -> Int32>(sB))
        fnAutorot = Some(CFunc<(CPointer<Unit>, CPointer<CPointer<Unit>>, CPointer<Unit>) -> Int32>(sAutorot))
        fnResize = Some(CFunc<(CPointer<Unit>, CPointer<CPointer<Unit>>, Float64, CPointer<Unit>) -> Int32>(sResize))
        fnGaussblur = Some(CFunc<(CPointer<Unit>, CPointer<CPointer<Unit>>, Float64, CPointer<Unit>) -> Int32>(sBlur))
        fnExtractArea = Some(CFunc<(CPointer<Unit>, CPointer<CPointer<Unit>>, Int32, Int32, Int32, Int32, CPointer<Unit>) -> Int32>(sArea))
        fnExtractBand = Some(CFunc<(CPointer<Unit>, CPointer<CPointer<Unit>>, Int32, CPointer<Unit>) -> Int32>(sBand))
        fnColourspace = Some(CFunc<(CPointer<Unit>, CPointer<CPointer<Unit>>, Int32, CPointer<Unit>) -> Int32>(sCs))
        fnCastUchar = Some(CFunc<(CPointer<Unit>, CPointer<CPointer<Unit>>, CPointer<Unit>) -> Int32>(sCast))
        fnBandjoinConst = Some(CFunc<(CPointer<Unit>, CPointer<CPointer<Unit>>, Float64, CPointer<Unit>) -> Int32>(sJoinConst))
        fnBandjoin = Some(CFunc<(CPointer<CPointer<Unit>>, CPointer<CPointer<Unit>>, Int32, CPointer<Unit>) -> Int32>(sJoin))
        fnWriteFile = Some(CFunc<(CPointer<Unit>, CString, CPointer<Unit>) -> Int32>(sWriteFile))
        fnWriteMem = Some(CFunc<(CPointer<Unit>, CPointer<UIntNative>) -> CPointer<Unit>>(sWriteMem))
        fnUnref = Some(CFunc<(CPointer<Unit>) -> Unit>(sUnref))
        fnFree = Some(CFunc<(CPointer<Unit>) -> Unit>(sFree))
        backendState = 1
        loadError = ""
        return true
    }
}

public class VipsApi {
    public static func available(): Bool {
        ensureBackend()
    }

    public static func unavailableReason(): String {
        if (ensureBackend()) {
            return ""
        }
        return loadError
    }

    public static func initialize(argv0: CString): Int32 {
        if (!ensureBackend()) {
            return -1
        }
        match (fnInit) {
            case Some(f) => unsafe { f(argv0) }
            case None => -1
        }
    }

    public static func setConcurrency(n: Int32): Unit {
        if (!ensureBackend()) {
            return
        }
        match (fnConcurrency) {
            case Some(f) => unsafe { f(n) }
            case None => ()
        }
    }

    public static func shutdown(): Unit {
        if (!ensureBackend()) {
            return
        }
        match (fnShutdown) {
            case Some(f) => unsafe { f() }
            case None => ()
        }
    }

    public static func takeErrorString(): String {
        if (!ensureBackend()) {
            return loadError
        }
        match (fnErrorBuffer) {
            case Some(f) =>
                var s = ""
                try {
                    let p = unsafe { f() }
                    if (!p.isNull()) {
                        s = unsafe { p.toString() }
                    }
                    match (fnErrorClear) {
                        case Some(c) => unsafe { c() }
                        case None => ()
                    }
                } catch (_: Exception) {}
                s
            case None => ""
        }
    }

    public static func imageNewFromFile(filename: CString): VipsImagePtr {
        if (!ensureBackend()) {
            return CPointer<VipsImage>()
        }
        match (fnNewFromFile) {
            case Some(f) => CPointer<VipsImage>(unsafe { f(filename, CPointer<Unit>()) })
            case None => CPointer<VipsImage>()
        }
    }

    public static func imageNewFromRgbaMemory(data: CPointer<Unit>, size: UIntNative, width: Int32,
        height: Int32): VipsImagePtr {
        if (!ensureBackend()) {
            return CPointer<VipsImage>()
        }
        match (fnNewFromMemCopy) {
            case Some(f) => CPointer<VipsImage>(unsafe { f(data, size, width, height, 4, VIPS_FORMAT_UCHAR) })
            case None => CPointer<VipsImage>()
        }
    }

    public static func imageWidth(image: VipsImagePtr): Int32 {
        match (fnGetWidth) {
            case Some(f) => unsafe { f(CPointer<Unit>(image)) }
            case None => 0
        }
    }

    public static func imageHeight(image: VipsImagePtr): Int32 {
        match (fnGetHeight) {
            case Some(f) => unsafe { f(CPointer<Unit>(image)) }
            case None => 0
        }
    }

    public static func imageBands(image: VipsImagePtr): Int32 {
        match (fnGetBands) {
            case Some(f) => unsafe { f(CPointer<Unit>(image)) }
            case None => 0
        }
    }

    public static func autorot(_in: VipsImagePtr, out: CPointer<VipsImagePtr>): Int32 {
        match (fnAutorot) {
            case Some(f) => unsafe { f(CPointer<Unit>(_in), CPointer<CPointer<Unit>>(out), CPointer<Unit>()) }
            case None => -1
        }
    }

    public static func resize(_in: VipsImagePtr, out: CPointer<VipsImagePtr>, scale: Float64): Int32 {
        match (fnResize) {
            case Some(f) => unsafe { f(CPointer<Unit>(_in), CPointer<CPointer<Unit>>(out), scale, CPointer<Unit>()) }
            case None => -1
        }
    }

    public static func gaussblur(_in: VipsImagePtr, out: CPointer<VipsImagePtr>, sigma: Float64): Int32 {
        match (fnGaussblur) {
            case Some(f) => unsafe { f(CPointer<Unit>(_in), CPointer<CPointer<Unit>>(out), sigma, CPointer<Unit>()) }
            case None => -1
        }
    }

    public static func extractArea(_in: VipsImagePtr, out: CPointer<VipsImagePtr>, left: Int32, top: Int32,
        width: Int32, height: Int32): Int32 {
        match (fnExtractArea) {
            case Some(f) => unsafe {
                f(CPointer<Unit>(_in), CPointer<CPointer<Unit>>(out), left, top, width, height, CPointer<Unit>())
            }
            case None => -1
        }
    }

    public static func extractBand(_in: VipsImagePtr, out: CPointer<VipsImagePtr>, band: Int32): Int32 {
        match (fnExtractBand) {
            case Some(f) => unsafe { f(CPointer<Unit>(_in), CPointer<CPointer<Unit>>(out), band, CPointer<Unit>()) }
            case None => -1
        }
    }

    public static func colourspaceSRgb(_in: VipsImagePtr, out: CPointer<VipsImagePtr>): Int32 {
        match (fnColourspace) {
            case Some(f) => unsafe {
                f(CPointer<Unit>(_in), CPointer<CPointer<Unit>>(out), VIPS_INTERPRETATION_sRGB, CPointer<Unit>())
            }
            case None => -1
        }
    }

    public static func castUChar(_in: VipsImagePtr, out: CPointer<VipsImagePtr>): Int32 {
        match (fnCastUchar) {
            case Some(f) => unsafe { f(CPointer<Unit>(_in), CPointer<CPointer<Unit>>(out), CPointer<Unit>()) }
            case None => -1
        }
    }

    public static func bandjoinConstAlpha255(_in: VipsImagePtr, out: CPointer<VipsImagePtr>): Int32 {
        match (fnBandjoinConst) {
            case Some(f) => unsafe { f(CPointer<Unit>(_in), CPointer<CPointer<Unit>>(out), 255.0, CPointer<Unit>()) }
            case None => -1
        }
    }

    public static func bandjoin(images: CPointer<VipsImagePtr>, out: CPointer<VipsImagePtr>, n: Int32): Int32 {
        match (fnBandjoin) {
            case Some(f) => unsafe { f(CPointer<CPointer<Unit>>(images), CPointer<CPointer<Unit>>(out), n, CPointer<Unit>()) }
            case None => -1
        }
    }

    public static func writeToFile(image: VipsImagePtr, filename: CString): Int32 {
        match (fnWriteFile) {
            case Some(f) => unsafe { f(CPointer<Unit>(image), filename, CPointer<Unit>()) }
            case None => -1
        }
    }

    public static func writeToMemory(image: VipsImagePtr, outSize: CPointer<UIntNative>): CPointer<Unit> {
        match (fnWriteMem) {
            case Some(f) => unsafe { f(CPointer<Unit>(image), outSize) }
            case None => CPointer<Unit>()
        }
    }

    public static func free(mem: CPointer<Unit>): Unit {
        if (mem.isNull()) {
            return
        }
        match (fnFree) {
            case Some(f) => unsafe { f(mem) }
            case None => ()
        }
    }

    public static func unref(image: VipsImagePtr): Unit {
        if (image.isNull()) {
            return
        }
        match (fnUnref) {
            case Some(f) => unsafe { f(CPointer<Unit>(image)) }
            case None => ()
        }
    }
}
