package lanlu_client_next.img

import std.sync.Mutex
import vips_ffi.*

// vips_init 全进程只允许一次，用 Mutex + 三态标记守卫（参照服务端 vips_convert_utils.cj 的 proven 用法）。
private let vipsMutex = Mutex()
private var vipsReady: ?Bool = None

private func ensureVips(): Unit {
    synchronized(vipsMutex) {
        match (vipsReady) {
            case Some(true) => return
            case Some(false) => throw Exception("libvips 初始化失败")
            case None =>
                let nameC = unsafe { LibC.mallocCString("lanlu-client-next") }
                let rc = VipsApi.initialize(nameC)
                unsafe { LibC.free(nameC) }
                if (rc != 0) {
                    vipsReady = Some(false)
                    throw Exception("libvips 初始化失败: ${VipsApi.takeErrorString()}")
                }
                vipsReady = Some(true)
        }
    }
}

// 任意格式图片文件 → PNG 文件。失败抛异常（信息带 vips 错误串）。
// 管线：imageNewFromFile → autorot（按 EXIF 方向转正）→ writeToFile（vips 按 .png 扩展名选编码器）。
public func transcodeFileToPng(inputPath: String, outputPath: String): Unit {
    ensureVips()
    var inImg: VipsImagePtr = CPointer<VipsImage>()
    var rotImg: VipsImagePtr = CPointer<VipsImage>()
    try {
        let inC = unsafe { LibC.mallocCString(inputPath) }
        inImg = VipsApi.imageNewFromFile(inC)
        unsafe { LibC.free(inC) }
        if (inImg.isNull()) { throw Exception("vips 解码失败: ${VipsApi.takeErrorString()}") }

        let rotRc = VipsApi.autorot(inImg, CPointer<VipsImagePtr>(inout rotImg))
        if (rotRc != 0 || rotImg.isNull()) { throw Exception("vips autorot 失败: ${VipsApi.takeErrorString()}") }

        let outC = unsafe { LibC.mallocCString(outputPath) }
        let wRc = VipsApi.writeToFile(rotImg, outC)
        unsafe { LibC.free(outC) }
        if (wRc != 0) { throw Exception("vips 写 PNG 失败: ${VipsApi.takeErrorString()}") }
    } finally {
        if (!rotImg.isNull()) { VipsApi.unref(rotImg) }
        if (!inImg.isNull()) { VipsApi.unref(inImg) }
    }
}
