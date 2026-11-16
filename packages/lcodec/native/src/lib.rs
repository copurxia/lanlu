//! lcodec 原生后端：libblur 高斯模糊的 C ABI。
//!
//! 约定（与 lcodec/src/blur_native.cj 一致）：
//!   - 输入为紧凑 RGBA8（stride = width * 4），按**预乘 alpha** 处理：
//!     直通 alpha 的透明像素颜色通常是 0（黑），直接卷积会让半透明边缘发黑一圈。
//!     这里先预乘、模糊、再反预乘（与 libvips 的 premultiply 流程同口径）。
//!   - 输出写入调用方提供的缓冲（与输入同尺寸），可以与输入相同（原地）。
//!   - 返回 0 成功；负值失败（参数非法 / libblur 报错 / panic 被截获）。

use libblur::{
    BlurImage, BlurImageMut, ConvolutionMode, EdgeMode, EdgeMode2D, FastBlurChannels,
    GaussianBlurParams, ThreadingPolicy, gaussian_blur,
};
use std::panic::{AssertUnwindSafe, catch_unwind};

const E_BAD_ARG: i32 = -1;
const E_BLUR: i32 = -2;
const E_PANIC: i32 = -3;

/// libblur 内核覆盖 ±3σ；超大 σ 在小图上没有意义，钳到图像短边量级避免巨大内核。
fn clamp_sigma(sigma: f64, w: u32, h: u32) -> f64 {
    let max_sigma = (w.min(h) as f64 / 2.0).max(0.8);
    sigma.clamp(0.8, max_sigma.max(0.8))
}

fn premultiply(px: &mut [u8]) {
    for p in px.chunks_exact_mut(4) {
        let a = p[3] as u32;
        if a == 255 {
            continue;
        }
        p[0] = ((p[0] as u32 * a + 127) / 255) as u8;
        p[1] = ((p[1] as u32 * a + 127) / 255) as u8;
        p[2] = ((p[2] as u32 * a + 127) / 255) as u8;
    }
}

fn unpremultiply(px: &mut [u8]) {
    for p in px.chunks_exact_mut(4) {
        let a = p[3] as u32;
        if a == 255 || a == 0 {
            if a == 0 {
                p[0] = 0;
                p[1] = 0;
                p[2] = 0;
            }
            continue;
        }
        p[0] = ((p[0] as u32 * 255 + a / 2) / a).min(255) as u8;
        p[1] = ((p[1] as u32 * 255 + a / 2) / a).min(255) as u8;
        p[2] = ((p[2] as u32 * 255 + a / 2) / a).min(255) as u8;
    }
}

fn blur_rgba(src: &[u8], dst: &mut [u8], w: u32, h: u32, sigma: f64) -> Result<(), i32> {
    let opaque = src.chunks_exact(4).all(|p| p[3] == 255);
    let mut work: Vec<u8> = src.to_vec();
    if !opaque {
        premultiply(&mut work);
    }
    let img = BlurImage::borrow(&work, w, h, FastBlurChannels::Channels4);
    let mut out = BlurImageMut::borrow(dst, w, h, FastBlurChannels::Channels4);
    let sigma = clamp_sigma(sigma, w, h);
    gaussian_blur(
        &img,
        &mut out,
        GaussianBlurParams::new_from_sigma(sigma),
        // Clamp：边缘像素外延——背景图边缘不会被"黑边"吃进去（vips_gaussblur 同口径）
        EdgeMode2D::new(EdgeMode::Clamp),
        ThreadingPolicy::Adaptive,
        ConvolutionMode::FixedPoint,
    )
    .map_err(|_| E_BLUR)?;
    if !opaque {
        unpremultiply(dst);
    }
    Ok(())
}

/// 对 w*h 的紧凑 RGBA8 做高斯模糊（sigma 单位：像素）。
/// `dst` 可与 `src` 相同（原地）；两者长度都必须 >= w*h*4。
#[unsafe(no_mangle)]
pub unsafe extern "C" fn lcodec_blur_rgba(
    src: *const u8,
    dst: *mut u8,
    width: u32,
    height: u32,
    sigma: f64,
) -> i32 {
    if src.is_null() || dst.is_null() || width == 0 || height == 0 || !(sigma > 0.0) {
        return E_BAD_ARG;
    }
    let Some(len) = (width as usize)
        .checked_mul(height as usize)
        .and_then(|n| n.checked_mul(4))
    else {
        return E_BAD_ARG;
    };
    // 原地模式：先把源拷进 blur_rgba 内部的 work 缓冲（它本来就复制一份做预乘），
    // 所以 dst 与 src 指向同一内存也安全——这里只需避免同时持有 & 与 &mut 别名。
    let result = catch_unwind(AssertUnwindSafe(|| {
        let src_copy: Vec<u8> = unsafe { std::slice::from_raw_parts(src, len) }.to_vec();
        let dst_slice = unsafe { std::slice::from_raw_parts_mut(dst, len) };
        blur_rgba(&src_copy, dst_slice, width, height, sigma)
    }));
    match result {
        Ok(Ok(())) => 0,
        Ok(Err(e)) => e,
        Err(_) => E_PANIC,
    }
}

/// ABI 版本：lcodec 装载时校验，避免旧库与新绑定错配。
#[unsafe(no_mangle)]
pub extern "C" fn lcodec_native_abi_version() -> u32 {
    1
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn blur_spreads_a_single_white_pixel() {
        let (w, h) = (9u32, 9u32);
        let mut src = vec![0u8; (w * h * 4) as usize];
        for p in src.chunks_exact_mut(4) {
            p[3] = 255;
        }
        let c = ((4 * w + 4) * 4) as usize;
        src[c] = 255;
        src[c + 1] = 255;
        src[c + 2] = 255;
        let mut dst = vec![0u8; src.len()];
        let rc = unsafe { lcodec_blur_rgba(src.as_ptr(), dst.as_mut_ptr(), w, h, 1.5) };
        assert_eq!(rc, 0);
        // 中心变暗、邻居变亮：能量被摊开了
        assert!(dst[c] < 255 && dst[c] > 0);
        let n = ((4 * w + 5) * 4) as usize;
        assert!(dst[n] > 0);
        // 全不透明输入保持不透明
        assert!(dst.chunks_exact(4).all(|p| p[3] == 255));
    }

    #[test]
    fn transparent_edges_do_not_darken() {
        // 左半白不透明、右半全透明（颜色 0）：预乘后模糊不应在半透明区出现发黑
        let (w, h) = (16u32, 4u32);
        let mut src = vec![0u8; (w * h * 4) as usize];
        for y in 0..h {
            for x in 0..w / 2 {
                let i = ((y * w + x) * 4) as usize;
                src[i..i + 4].copy_from_slice(&[255, 255, 255, 255]);
            }
        }
        let mut dst = vec![0u8; src.len()];
        let rc = unsafe { lcodec_blur_rgba(src.as_ptr(), dst.as_mut_ptr(), w, h, 2.0) };
        assert_eq!(rc, 0);
        for p in dst.chunks_exact(4) {
            if p[3] > 8 {
                assert!(p[0] > 240, "半透明像素发黑: {:?}", p);
            }
        }
    }

    #[test]
    fn in_place_and_bad_args() {
        let mut buf = vec![128u8; 8 * 8 * 4];
        let p = buf.as_mut_ptr();
        assert_eq!(unsafe { lcodec_blur_rgba(p, p, 8, 8, 1.0) }, 0);
        assert_eq!(unsafe { lcodec_blur_rgba(p, p, 0, 8, 1.0) }, E_BAD_ARG);
        assert_eq!(unsafe { lcodec_blur_rgba(p, p, 8, 8, 0.0) }, E_BAD_ARG);
    }
}
