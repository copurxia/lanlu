package lanlu_client_next.img

import std.sync.Mutex
import vips_ffi.*

// 块拷贝：替代逐字节 CPointer 读写循环，将 libvips 原生内存一次性拷进仓颉数组
// （同服务端 vips_convert_utils.cj 的 proven 用法）。
foreign func memcpy(dest: CPointer<UInt8>, src: CPointer<UInt8>, n: UIntNative): CPointer<Unit>

// vips_init 全进程只允许一次，用 Mutex + 三态标记守卫（沿用原 vips_transcode.cj 的守卫）。
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

// vips 解码产物：RGBA 像素（R,G,B,A 字节序，长度 == width*height*4）。
public class DecodedImage {
    public let width: Int32
    public let height: Int32
    public let pixels: Array<UInt8>

    public init(width: Int32, height: Int32, pixels: Array<UInt8>) {
        this.width = width
        this.height = height
        this.pixels = pixels
    }
}

// 任意格式图片文件 → RGBA 像素。失败抛异常（信息带 vips 错误串）。
// 管线：imageNewFromFile → （可选）vips_resize 缩小 → autorot（按 EXIF 方向转正）
// → colourspace(sRGB) → castUchar → bands 归一到 4 波段 → writeToMemory → 拷进 Array<UInt8>。
// maxDimension > 0 且原图最长边超出时按比例缩小到该上限（不放大）；磁盘缓存仍存
// 原始字节，缩小只发生在解码期，不同展示尺寸共用同一磁盘缓存条目。
// 仅在工作线程调用（vips 解码是 CPU 重活，UI 线程纪律见 model.startImageTask）。
public func decodeFileToRgba(path: String, maxDimension!: Int32 = 0): DecodedImage {
    ensureVips()
    var inImg: VipsImagePtr = CPointer<VipsImage>()
    var resizedImg: VipsImagePtr = CPointer<VipsImage>()
    var rotImg: VipsImagePtr = CPointer<VipsImage>()
    var srgbImg: VipsImagePtr = CPointer<VipsImage>()
    var u8Img: VipsImagePtr = CPointer<VipsImage>()
    var normImg: VipsImagePtr = CPointer<VipsImage>()
    var mem = CPointer<Unit>()
    try {
        let inC = unsafe { LibC.mallocCString(path) }
        inImg = VipsApi.imageNewFromFile(inC)
        unsafe { LibC.free(inC) }
        if (inImg.isNull()) { throw Exception("vips 解码失败: ${VipsApi.takeErrorString()}") }

        // 可选缩小解码：最长边超过 maxDimension 时按比例缩（封面/阅读页省内存与解码耗时）。
        var src = inImg
        if (maxDimension > 0) {
            let w0 = VipsApi.imageWidth(inImg)
            let h0 = VipsApi.imageHeight(inImg)
            let longest = max(Int64(w0), Int64(h0))
            if (w0 <= 0 || h0 <= 0) { throw Exception("vips 尺寸非法: ${w0}x${h0}") }
            if (longest > Int64(maxDimension)) {
                let scale = Float64(maxDimension) / Float64(longest)
                let resizeRc = VipsApi.resize(inImg, CPointer<VipsImagePtr>(inout resizedImg), scale)
                if (resizeRc != 0 || resizedImg.isNull()) {
                    throw Exception("vips resize 失败: ${VipsApi.takeErrorString()}")
                }
                src = resizedImg
            }
        }

        let rotRc = VipsApi.autorot(src, CPointer<VipsImagePtr>(inout rotImg))
        if (rotRc != 0 || rotImg.isNull()) { throw Exception("vips autorot 失败: ${VipsApi.takeErrorString()}") }

        let csRc = VipsApi.colourspaceSRgb(rotImg, CPointer<VipsImagePtr>(inout srgbImg))
        if (csRc != 0 || srgbImg.isNull()) { throw Exception("vips colourspace 失败: ${VipsApi.takeErrorString()}") }

        let castRc = VipsApi.castUChar(srgbImg, CPointer<VipsImagePtr>(inout u8Img))
        if (castRc != 0 || u8Img.isNull()) { throw Exception("vips cast_uchar 失败: ${VipsApi.takeErrorString()}") }

        // bands 归一到 RGBA 四波段。
        let bands = VipsApi.imageBands(u8Img)
        if (bands == 4) {
            normImg = u8Img
            u8Img = CPointer<VipsImage>()  // 所有权移交 normImg，finally 不得重复 unref
        } else if (bands == 3) {
            let rc = VipsApi.bandjoinConstAlpha255(u8Img, CPointer<VipsImagePtr>(inout normImg))
            if (rc != 0 || normImg.isNull()) { throw Exception("vips 补 alpha 失败: ${VipsApi.takeErrorString()}") }
        } else if (bands == 1) {
            normImg = greyToRgba(u8Img)
        } else if (bands == 2) {
            normImg = greyAlphaToRgba(u8Img)
        } else if (bands > 4) {
            normImg = takeFirst4Bands(u8Img)
        } else {
            throw Exception("vips 波段数非法: ${bands}")
        }

        let w = VipsApi.imageWidth(normImg)
        let h = VipsApi.imageHeight(normImg)
        if (w <= 0 || h <= 0) { throw Exception("vips 尺寸非法: ${w}x${h}") }

        var size: UIntNative = 0
        mem = VipsApi.writeToMemory(normImg, CPointer<UIntNative>(inout size))
        if (mem.isNull() || size == 0) { throw Exception("vips 写内存失败: ${VipsApi.takeErrorString()}") }
        let n = Int64(size)
        let expected = Int64(w) * Int64(h) * 4
        if (n != expected) { throw Exception("vips RGBA 字节数不符: ${n} != ${expected}") }

        let pixels = Array<UInt8>(n, repeat: 0u8)
        unsafe {
            let handle = acquireArrayRawData(pixels)
            memcpy(handle.pointer, CPointer<UInt8>(mem), size)
            releaseArrayRawData(handle)
        }
        return DecodedImage(w, h, pixels)
    } finally {
        // VipsApi.unref/free 内部自带空指针判断；未走到的步骤保持空指针，自然跳过。
        VipsApi.unref(inImg)
        VipsApi.unref(resizedImg)
        VipsApi.unref(rotImg)
        VipsApi.unref(srgbImg)
        VipsApi.unref(u8Img)
        VipsApi.unref(normImg)
        VipsApi.free(mem)
    }
}

// 解码缓存定稿文件（图片管线用）：解码失败说明 .img 字节损坏（如截断的下载），
// 先剔除该 key 的缓存条目再原样抛出——坏字节留在缓存里会让每次重试都命中同一份坏数据。
// 剔除本身的 I/O 失败静默吞掉，保证抛出的始终是原始解码错误。
// maxDimension 透传 decodeFileToRgba（缩小解码，见上）；evict 的 key 是磁盘缓存
// 条目 key（原始字节），与尺寸档位无关。
public func decodeCachedOrEvict(cache: ImageCache, key: String, path: String,
    maxDimension!: Int32 = 0): DecodedImage {
    try {
        return decodeFileToRgba(path, maxDimension: maxDimension)
    } catch (e: Exception) {
        try { cache.evict(key) } catch (_: Exception) { () }
        throw e
    }
}

// backdrop 解码：加载文件 → vips_resize 缩到 targetWidth 像素宽（保持比例）→ vips_gaussblur
// 真高斯模糊 → 后续管线同 decodeFileToRgba。仅在工作线程调用。用于详情页 backdrop 模糊背景：
// 旧实现只缩到 ~48px 宽靠 SDL Linear 放大得到"模糊"，高对比内容（漫画线稿）会糊成脏块；
// 改为中间尺寸（~256px）+ sigma 高斯模糊，质感对齐原型 filter: blur(36px)。
// blurSigma 为高斯核 sigma（中间图像素单位），0 表示不模糊（回退旧行为的逃生口）。
public func decodeBackdrop(path: String, targetWidth: Int32, blurSigma!: Float64 = 8.0): DecodedImage {
    ensureVips()
    var inImg: VipsImagePtr = CPointer<VipsImage>()
    var resizedImg: VipsImagePtr = CPointer<VipsImage>()
    var blurImg: VipsImagePtr = CPointer<VipsImage>()
    var rotImg: VipsImagePtr = CPointer<VipsImage>()
    var srgbImg: VipsImagePtr = CPointer<VipsImage>()
    var u8Img: VipsImagePtr = CPointer<VipsImage>()
    var normImg: VipsImagePtr = CPointer<VipsImage>()
    var mem = CPointer<Unit>()
    try {
        // 1. 加载原始文件
        let inC = unsafe { LibC.mallocCString(path) }
        inImg = VipsApi.imageNewFromFile(inC)
        unsafe { LibC.free(inC) }
        if (inImg.isNull()) { throw Exception("vips 解码失败: ${VipsApi.takeErrorString()}") }

        // 2. 缩放到 targetWidth 宽（scale = target / originalWidth，保比例）
        let w = VipsApi.imageWidth(inImg)
        if (w <= 0) { throw Exception("vips 尺寸非法: ${w}") }
        let scale = Float64(targetWidth) / Float64(w)
        let resizeRc = VipsApi.resize(inImg, CPointer<VipsImagePtr>(inout resizedImg), scale)
        if (resizeRc != 0 || resizedImg.isNull()) {
            throw Exception("vips resize 失败: ${VipsApi.takeErrorString()}")
        }

        // 3. 真高斯模糊（sigma > 0 时）：在中间尺寸上模糊，放大后保持柔和
        var src = resizedImg
        if (blurSigma > 0.0) {
            let blurRc = VipsApi.gaussblur(resizedImg, CPointer<VipsImagePtr>(inout blurImg), blurSigma)
            if (blurRc != 0 || blurImg.isNull()) {
                throw Exception("vips gaussblur 失败: ${VipsApi.takeErrorString()}")
            }
            src = blurImg
        }

        // 4. autorot → colourspace → cast → normalize bands（同 decodeFileToRgba 管线）
        let rotRc = VipsApi.autorot(src, CPointer<VipsImagePtr>(inout rotImg))
        if (rotRc != 0 || rotImg.isNull()) { throw Exception("vips autorot 失败: ${VipsApi.takeErrorString()}") }

        let csRc = VipsApi.colourspaceSRgb(rotImg, CPointer<VipsImagePtr>(inout srgbImg))
        if (csRc != 0 || srgbImg.isNull()) { throw Exception("vips colourspace 失败: ${VipsApi.takeErrorString()}") }

        let castRc = VipsApi.castUChar(srgbImg, CPointer<VipsImagePtr>(inout u8Img))
        if (castRc != 0 || u8Img.isNull()) { throw Exception("vips cast_uchar 失败: ${VipsApi.takeErrorString()}") }

        let bands = VipsApi.imageBands(u8Img)
        if (bands == 4) {
            normImg = u8Img
            u8Img = CPointer<VipsImage>()
        } else if (bands == 3) {
            let rc = VipsApi.bandjoinConstAlpha255(u8Img, CPointer<VipsImagePtr>(inout normImg))
            if (rc != 0 || normImg.isNull()) { throw Exception("vips 补 alpha 失败: ${VipsApi.takeErrorString()}") }
        } else if (bands == 1) {
            normImg = greyToRgba(u8Img)
        } else if (bands == 2) {
            normImg = greyAlphaToRgba(u8Img)
        } else if (bands > 4) {
            normImg = takeFirst4Bands(u8Img)
        } else {
            throw Exception("vips 波段数非法: ${bands}")
        }

        let bw = VipsApi.imageWidth(normImg)
        let bh = VipsApi.imageHeight(normImg)
        if (bw <= 0 || bh <= 0) { throw Exception("vips 尺寸非法: ${bw}x${bh}") }

        var size: UIntNative = 0
        mem = VipsApi.writeToMemory(normImg, CPointer<UIntNative>(inout size))
        if (mem.isNull() || size == 0) { throw Exception("vips 写内存失败: ${VipsApi.takeErrorString()}") }
        let n = Int64(size)
        let expected = Int64(bw) * Int64(bh) * 4
        if (n != expected) { throw Exception("vips RGBA 字节数不符: ${n} != ${expected}") }

        let pixels = Array<UInt8>(n, repeat: 0u8)
        unsafe {
            let handle = acquireArrayRawData(pixels)
            memcpy(handle.pointer, CPointer<UInt8>(mem), size)
            releaseArrayRawData(handle)
        }
        return DecodedImage(bw, bh, pixels)
    } finally {
        VipsApi.unref(inImg)
        VipsApi.unref(resizedImg)
        VipsApi.unref(blurImg)
        VipsApi.unref(rotImg)
        VipsApi.unref(srgbImg)
        VipsApi.unref(u8Img)
        VipsApi.unref(normImg)
        VipsApi.free(mem)
    }
}

// 1 波段（灰度）→ RGBA：灰度通道三复制成 RGB，再补常数 alpha 255。
private func greyToRgba(img: VipsImagePtr): VipsImagePtr {
    var rgb: VipsImagePtr = CPointer<VipsImage>()
    var rgba: VipsImagePtr = CPointer<VipsImage>()
    let arr = unsafe { LibC.malloc<VipsImagePtr>(count: 3) }
    unsafe {
        (arr + 0).write(img)
        (arr + 1).write(img)
        (arr + 2).write(img)
    }
    let joinRc = VipsApi.bandjoin(arr, CPointer<VipsImagePtr>(inout rgb), 3)
    unsafe { LibC.free(arr) }
    if (joinRc != 0 || rgb.isNull()) { throw Exception("vips 灰度转 RGB 失败: ${VipsApi.takeErrorString()}") }
    let alphaRc = VipsApi.bandjoinConstAlpha255(rgb, CPointer<VipsImagePtr>(inout rgba))
    VipsApi.unref(rgb)
    if (alphaRc != 0 || rgba.isNull()) { throw Exception("vips 补 alpha 失败: ${VipsApi.takeErrorString()}") }
    return rgba
}

// 2 波段（灰度+alpha）→ RGBA：灰度三复制 + 保留原 alpha（同服务端 normalizeToRgbaU8）。
private func greyAlphaToRgba(img: VipsImagePtr): VipsImagePtr {
    var grey: VipsImagePtr = CPointer<VipsImage>()
    var alpha: VipsImagePtr = CPointer<VipsImage>()
    var rgba: VipsImagePtr = CPointer<VipsImage>()
    try {
        let greyRc = VipsApi.extractBand(img, CPointer<VipsImagePtr>(inout grey), 0)
        if (greyRc != 0 || grey.isNull()) { throw Exception("vips 抽灰度波段失败: ${VipsApi.takeErrorString()}") }
        let alphaRc = VipsApi.extractBand(img, CPointer<VipsImagePtr>(inout alpha), 1)
        if (alphaRc != 0 || alpha.isNull()) { throw Exception("vips 抽 alpha 波段失败: ${VipsApi.takeErrorString()}") }
        let arr = unsafe { LibC.malloc<VipsImagePtr>(count: 4) }
        unsafe {
            (arr + 0).write(grey)
            (arr + 1).write(grey)
            (arr + 2).write(grey)
            (arr + 3).write(alpha)
        }
        let joinRc = VipsApi.bandjoin(arr, CPointer<VipsImagePtr>(inout rgba), 4)
        unsafe { LibC.free(arr) }
        if (joinRc != 0 || rgba.isNull()) { throw Exception("vips 灰度+alpha 转 RGBA 失败: ${VipsApi.takeErrorString()}") }
        return rgba
    } finally {
        VipsApi.unref(grey)
        VipsApi.unref(alpha)
    }
}

// >4 波段（如带附加通道的 TIFF）→ 取前 4 个波段拼成 RGBA。
private func takeFirst4Bands(img: VipsImagePtr): VipsImagePtr {
    let extracted = Array<VipsImagePtr>(4, repeat: CPointer<VipsImage>())
    var rgba: VipsImagePtr = CPointer<VipsImage>()
    try {
        for (i in 0..4) {
            var b: VipsImagePtr = CPointer<VipsImage>()
            let rc = VipsApi.extractBand(img, CPointer<VipsImagePtr>(inout b), Int32(i))
            if (rc != 0 || b.isNull()) { throw Exception("vips 抽第 ${i} 波段失败: ${VipsApi.takeErrorString()}") }
            extracted[i] = b
        }
        let arr = unsafe { LibC.malloc<VipsImagePtr>(count: 4) }
        unsafe {
            for (i in 0..4) {
                (arr + i).write(extracted[i])
            }
        }
        let joinRc = VipsApi.bandjoin(arr, CPointer<VipsImagePtr>(inout rgba), 4)
        unsafe { LibC.free(arr) }
        if (joinRc != 0 || rgba.isNull()) { throw Exception("vips 前 4 波段拼接失败: ${VipsApi.takeErrorString()}") }
        return rgba
    } finally {
        for (b in extracted) {
            VipsApi.unref(b)
        }
    }
}
