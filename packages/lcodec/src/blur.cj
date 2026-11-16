package lcodec

import std.sync.Mutex

/*
 * RGBA 高斯模糊（Modal 背景 / backdrop 用）。
 *
 * 后端优先级：libblur（liblcodec_native，见 blur_native.cj）> libvips > 纯仓颉盒式近似。
 *
 * 这是原先散落在 cui（packages/cangjie-gui/lgui/src/texture.cj）里的 vips 直接调用；
 * 解码统合后由 lcodec 提供，UI 框架不再 import vips_ffi。
 */

private let blurMutex = Mutex()
private var blurReady: ?Bool = None

private func ensureVipsForBlur(): Bool {
    synchronized(blurMutex) {
        match (blurReady) {
            case Some(v) => return v
            case None => ()
        }
        let argv0 = unsafe { LibC.mallocCString("lcodec-blur") }
        let rc = try {
            VipsApi.initialize(argv0)
        } finally {
            unsafe { LibC.free(argv0) }
        }
        blurReady = Some(rc == 0)
        rc == 0
    }
}

// 对 width*height*4 的 RGBA 像素做高斯模糊（sigma 单位=像素）。
// 返回新数组（长度不变）；后端不可用或尺寸不符时返回 None。
public func blurRgba(pixels: Array<UInt8>, width: Int32, height: Int32,
    sigma!: Float64 = 8.0): ?Array<UInt8> {
    if (width <= 0 || height <= 0 || sigma <= 0.0) {
        return None
    }
    let expected = Int64(width) * Int64(height) * 4
    if (Int64(pixels.size) != expected) {
        return None
    }
    // 1) libblur（所有平台优先）：真高斯 + 预乘 alpha，不需要 libvips。
    if (nativeBlurAvailable()) {
        let result = Array<UInt8>(expected, repeat: 0u8)
        let src = unsafe { acquireArrayRawData(pixels) }
        let dst = unsafe { acquireArrayRawData(result) }
        let ok = nativeBlurInto(CPointer<UInt8>(src.pointer), CPointer<UInt8>(dst.pointer), width, height, sigma)
        unsafe {
            releaseArrayRawData(dst)
            releaseArrayRawData(src)
        }
        if (ok) {
            return Some(result)
        }
    }
    // 2) libvips（桌面），3) 盒式近似（OHOS 无 vips 时）
    if (!ensureVipsForBlur()) {
        // OHOS 没有 vips：走纯仓颉三次盒式模糊（等价能力，无外部库依赖）。
        let handle = unsafe { acquireArrayRawData(pixels) }
        let blurredPtr = blurRgbaNative(CPointer<UInt8>(handle.pointer), width, height, sigma)
        unsafe { releaseArrayRawData(handle) }
        if (blurredPtr.isNull()) {
            return None
        }
        let result = Array<UInt8>(expected, repeat: 0u8)
        unsafe {
            let out = acquireArrayRawData(result)
            memcpy(out.pointer, blurredPtr, UIntNative(expected))
            releaseArrayRawData(out)
        }
        freeRgba(blurredPtr)
        return Some(result)
    }
    var source: VipsImagePtr = CPointer<VipsImage>()
    var blurred: VipsImagePtr = CPointer<VipsImage>()
    var mem = CPointer<Unit>()
    try {
        // libvips 会拷贝输入像素，钉扎只需覆盖构造调用。
        let handle = unsafe { acquireArrayRawData(pixels) }
        try {
            source = VipsApi.imageNewFromRgbaMemory(CPointer<Unit>(handle.pointer), UIntNative(pixels.size), width,
                height)
        } finally {
            unsafe { releaseArrayRawData(handle) }
        }
        if (source.isNull()) {
            return None
        }
        let rc = VipsApi.gaussblur(source, CPointer<VipsImagePtr>(inout blurred), sigma)
        if (rc != 0 || blurred.isNull()) {
            return None
        }
        var size: UIntNative = 0
        mem = VipsApi.writeToMemory(blurred, CPointer<UIntNative>(inout size))
        if (mem.isNull() || Int64(size) != expected) {
            return None
        }
        let result = Array<UInt8>(expected, repeat: 0u8)
        unsafe {
            let out = acquireArrayRawData(result)
            memcpy(out.pointer, CPointer<UInt8>(mem), size)
            releaseArrayRawData(out)
        }
        Some(result)
    } finally {
        VipsApi.free(mem)
        VipsApi.unref(blurred)
        VipsApi.unref(source)
    }
}
