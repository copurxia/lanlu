package lcodec

import std.math.{pow, sqrt}

/*
 * 纯仓颉 RGBA 像素运算：缩放 + 高斯模糊。
 *
 * 背景：lcodec 在 OHOS 上直连系统 ImageSource 之后不再有 vips（也就没有
 * vips_resize / vips_gaussblur）。这两步本来就不需要通用图像库：
 *   - 缩放：双线性，目标尺寸由调用方给出（封面档位 / backdrop 宽度）；
 *   - 模糊：三次盒式模糊近似高斯（半径由 sigma 推导），分离式横竖两遍，
 *     复杂度 O(w*h)，在 1/4 缩略图上做（模态遮罩 blur 背景）耗时可忽略。
 * 桌面仍走真 libvips 的同名路径，行为不变。
 */

/// 双线性缩放：源为紧凑 RGBA（w*h*4），返回 malloc 分配的新缓冲（调用方 freeRgba）。
public func resizeRgbaBilinear(src: CPointer<UInt8>, sw: Int32, sh: Int32, dw: Int32, dh: Int32): CPointer<UInt8> {
    if (sw <= 0 || sh <= 0 || dw <= 0 || dh <= 0 || src.isNull()) {
        return CPointer<UInt8>()
    }
    let outSize = Int64(dw) * Int64(dh) * 4
    let out = unsafe { LibC.malloc<UInt8>(count: outSize) }
    if (out.isNull()) {
        return CPointer<UInt8>()
    }
    let xRatio = Float64(sw) / Float64(dw)
    let yRatio = Float64(sh) / Float64(dh)
    unsafe {
        for (y in 0..Int64(dh)) {
            let sy = (Float64(y) + 0.5) * yRatio - 0.5
            var y0 = Int64(sy)
            if (y0 < 0) {
                y0 = 0
            }
            if (y0 > Int64(sh) - 1) {
                y0 = Int64(sh) - 1
            }
            var y1 = y0 + 1
            if (y1 > Int64(sh) - 1) {
                y1 = Int64(sh) - 1
            }
            let fy = sy - Float64(y0)
            let row0 = src + y0 * Int64(sw) * 4
            let row1 = src + y1 * Int64(sw) * 4
            let drow = out + y * Int64(dw) * 4
            for (x in 0..Int64(dw)) {
                let sx = (Float64(x) + 0.5) * xRatio - 0.5
                var x0 = Int64(sx)
                if (x0 < 0) {
                    x0 = 0
                }
                if (x0 > Int64(sw) - 1) {
                    x0 = Int64(sw) - 1
                }
                var x1 = x0 + 1
                if (x1 > Int64(sw) - 1) {
                    x1 = Int64(sw) - 1
                }
                let fx = Float64(sx - Float64(x0))
                let i00 = x0 * 4
                let i01 = x1 * 4
                let o = x * 4
                for (c in 0..4) {
                    let p00 = Float64((row0 + i00 + c).read())
                    let p01 = Float64((row0 + i01 + c).read())
                    let p10 = Float64((row1 + i00 + c).read())
                    let p11 = Float64((row1 + i01 + c).read())
                    let top = p00 + (p01 - p00) * fx
                    let bottom = p10 + (p11 - p10) * fx
                    let v = top + (bottom - top) * fy
                    (drow + o + c).write(UInt8(if (v < 0.0) { 0 } else if (v > 255.0) { 255 } else { Int64(v + 0.5) }))
                }
            }
        }
    }
    out
}

// 横向盒式模糊一遍（滑窗求和，O(w*h)）。
private func boxBlurH(src: CPointer<UInt8>, dst: CPointer<UInt8>, w: Int64, h: Int64, r: Int64): Unit {
    if (r <= 0) {
        unsafe { memcpy(dst, src, UIntNative(w * h * 4)) }
        return
    }
    let win = r * 2 + 1
    unsafe {
        for (y in 0..h) {
            let row = y * w * 4
            var sr = Int64(0)
            var sg = Int64(0)
            var sb = Int64(0)
            var sa = Int64(0)
            // 初始化窗口（左边界按端点复制）
            for (k in -r..=r) {
                var xx = k
                if (xx < 0) {
                    xx = 0
                }
                if (xx > w - 1) {
                    xx = w - 1
                }
                let p = src + row + xx * 4
                sr += Int64(p.read())
                sg += Int64((p + 1).read())
                sb += Int64((p + 2).read())
                sa += Int64((p + 3).read())
            }
            for (x in 0..w) {
                let d = dst + row + x * 4
                (d).write(UInt8(sr / win))
                (d + 1).write(UInt8(sg / win))
                (d + 2).write(UInt8(sb / win))
                (d + 3).write(UInt8(sa / win))
                // 滑动：移出 x-r，移入 x+r+1
                var xo = x - r
                if (xo < 0) {
                    xo = 0
                }
                var xi = x + r + 1
                if (xi > w - 1) {
                    xi = w - 1
                }
                let po = src + row + xo * 4
                let pi = src + row + xi * 4
                sr += Int64(pi.read()) - Int64(po.read())
                sg += Int64((pi + 1).read()) - Int64((po + 1).read())
                sb += Int64((pi + 2).read()) - Int64((po + 2).read())
                sa += Int64((pi + 3).read()) - Int64((po + 3).read())
            }
        }
    }
}

// 纵向盒式模糊一遍（按列滑窗；为缓存友好按行累加列和）。
private func boxBlurV(src: CPointer<UInt8>, dst: CPointer<UInt8>, w: Int64, h: Int64, r: Int64): Unit {
    if (r <= 0) {
        unsafe { memcpy(dst, src, UIntNative(w * h * 4)) }
        return
    }
    let win = r * 2 + 1
    // 列和缓冲：4 个通道分别累加
    let sums = unsafe { LibC.malloc<Int64>(count: w * 4) }
    if (sums.isNull()) {
        unsafe { memcpy(dst, src, UIntNative(w * h * 4)) }
        return
    }
    unsafe {
        for (i in 0..(w * 4)) {
            (sums + i).write(0)
        }
        // 初始化窗口（上边界端点复制）
        for (k in -r..=r) {
            var yy = k
            if (yy < 0) {
                yy = 0
            }
            if (yy > h - 1) {
                yy = h - 1
            }
            let row = src + yy * w * 4
            for (i in 0..(w * 4)) {
                (sums + i).write((sums + i).read() + Int64((row + i).read()))
            }
        }
        for (y in 0..h) {
            let drow = dst + y * w * 4
            for (i in 0..(w * 4)) {
                (drow + i).write(UInt8((sums + i).read() / win))
            }
            var yo = y - r
            if (yo < 0) {
                yo = 0
            }
            var yi = y + r + 1
            if (yi > h - 1) {
                yi = h - 1
            }
            let pro = src + yo * w * 4
            let pri = src + yi * w * 4
            for (i in 0..(w * 4)) {
                (sums + i).write((sums + i).read() + Int64((pri + i).read()) - Int64((pro + i).read()))
            }
        }
    }
    unsafe { LibC.free(sums) }
}

/// 高斯模糊（sigma 单位=像素）。返回 malloc 分配的新缓冲（调用方 freeRgba）。
/// 优先 libblur（真高斯、SIMD+多线程、预乘 alpha）；后端不可用时回落三次盒式近似。
public func blurRgbaNative(src: CPointer<UInt8>, w: Int32, h: Int32, sigma: Float64): CPointer<UInt8> {
    if (w <= 0 || h <= 0 || src.isNull()) {
        return CPointer<UInt8>()
    }
    let iw = Int64(w)
    let ih = Int64(h)
    let total = iw * ih * 4
    if (nativeBlurAvailable()) {
        let dst = unsafe { LibC.malloc<UInt8>(count: total) }
        if (!dst.isNull()) {
            if (nativeBlurInto(src, dst, w, h, sigma)) {
                return dst
            }
            unsafe { LibC.free(dst) }
        }
    }
    return boxBlurRgba(src, w, h, sigma)
}

/// 三次盒式模糊近似高斯（libblur 不可用时的回落）。返回 malloc 分配的新缓冲。
func boxBlurRgba(src: CPointer<UInt8>, w: Int32, h: Int32, sigma: Float64): CPointer<UInt8> {
    let iw = Int64(w)
    let ih = Int64(h)
    let total = iw * ih * 4
    let a = unsafe { LibC.malloc<UInt8>(count: total) }
    let b = unsafe { LibC.malloc<UInt8>(count: total) }
    let out = unsafe { LibC.malloc<UInt8>(count: total) }
    if (a.isNull() || b.isNull() || out.isNull()) {
        if (!a.isNull()) {
            unsafe { LibC.free(a) }
        }
        if (!b.isNull()) {
            unsafe { LibC.free(b) }
        }
        if (!out.isNull()) {
            unsafe { LibC.free(out) }
        }
        return CPointer<UInt8>()
    }
    // 三次盒式模糊的等效半径：由高斯 sigma 反解（经典近似 r = sqrt(12σ²/3+1)/2 - 0.5）。
    var r = Int64(sqrt(12.0 * sigma * sigma / 3.0 + 1.0) / 2.0 - 0.5 + 0.5)
    if (r < 1) {
        r = 1
    }
    if (r > 64) {
        r = 64
    }
    // 三次盒式模糊：横竖交替，缓冲在两块临时区之间轮转，最后一轮直接落到 out。
    // 第 i 轮：H(cur -> a)，V(a -> dst)，dst = b / b / out。
    var cur = src
    for (i in 0..3) {
        let dst = if (i == 2) { out } else { b }
        boxBlurH(cur, a, iw, ih, r)
        boxBlurV(a, dst, iw, ih, r)
        cur = dst
    }
    unsafe {
        LibC.free(a)
        LibC.free(b)
    }
    out
}
