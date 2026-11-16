package lcodec

import std.sync.Mutex

/*
 * libblur 后端（lcodec 原生库 liblcodec_native，Rust）。
 *
 * 高斯模糊统一走这里：替代桌面的 vips_gaussblur 与 OHOS 上的仓颉三次盒式模糊
 * （盒式近似在大 sigma 下有明显的方块/十字伪影，且是单线程标量循环）。
 * libblur 是可分离高斯卷积（NEON/SSE 加速、多线程），预乘 alpha 处理半透明边缘。
 *
 * 装载方式与 vips 后端一致：运行时 dlopen，业务层/cui 不需要任何链接参数；
 * 库缺失时 available() = false，调用方回落到原有路径（行为不倒退）。
 * 库名：OHOS 随 HAP 打包 liblcodec_native.so；桌面放在可执行文件旁或 LD_LIBRARY_PATH。
 */

private type FnBlurRgba = CFunc<(CPointer<UInt8>, CPointer<UInt8>, UInt32, UInt32, Float64) -> Int32>
private type FnAbiVersion = CFunc<() -> UInt32>

private let LCODEC_NATIVE_ABI: UInt32 = 1
private let NATIVE_LIB_NAMES = ["liblcodec_native.so", "liblcodec_native.dylib", "lcodec_native.dll"]

private let nativeMutex = Mutex()
private var nativeState: Int8 = 0   // 0 未尝试 / 1 可用 / -1 不可用
private var nativeError = ""
private var fnBlurRgba: ?FnBlurRgba = None

private func loadNativeBlur(): Bool {
    synchronized(nativeMutex) {
        if (nativeState != 0) {
            return nativeState == 1
        }
        nativeState = -1
        for (name in NATIVE_LIB_NAMES) {
            let h = openLib(name)
            if (h.isNull()) {
                continue
            }
            let pAbi = symOf(h, "lcodec_native_abi_version")
            let pBlur = symOf(h, "lcodec_blur_rgba")
            if (pAbi.isNull() || pBlur.isNull()) {
                nativeError = "${name} 缺少符号"
                continue
            }
            let abi = unsafe { CFunc<() -> UInt32>(pAbi)() }
            if (abi != LCODEC_NATIVE_ABI) {
                nativeError = "${name} ABI 不匹配: ${abi} != ${LCODEC_NATIVE_ABI}"
                continue
            }
            fnBlurRgba = Some(CFunc<(CPointer<UInt8>, CPointer<UInt8>, UInt32, UInt32, Float64) -> Int32>(pBlur))
            nativeState = 1
            return true
        }
        if (nativeError.isEmpty()) {
            nativeError = "未找到 liblcodec_native"
        }
        false
    }
}

/// libblur 后端是否可用（首次调用时装载）。
public func nativeBlurAvailable(): Bool {
    loadNativeBlur()
}

/// 装载失败原因（诊断用）。
public func nativeBlurError(): String {
    nativeError
}

/// 用 libblur 对紧凑 RGBA8 原地/异地做高斯模糊。src、dst 长度都须 >= w*h*4（可相同）。
/// 返回 true 成功；后端不可用或失败返回 false（dst 内容不保证）。
public func nativeBlurInto(src: CPointer<UInt8>, dst: CPointer<UInt8>, w: Int32, h: Int32, sigma: Float64): Bool {
    if (src.isNull() || dst.isNull() || w <= 0 || h <= 0 || sigma <= 0.0) {
        return false
    }
    if (!loadNativeBlur()) {
        return false
    }
    match (fnBlurRgba) {
        case Some(f) => unsafe { f(src, dst, UInt32(w), UInt32(h), sigma) } == 0
        case None => false
    }
}
