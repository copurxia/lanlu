//! 文本：字形光栅化 + 图集打包。
//!
//! 分工：
//! - 字形**光栅化**用 ab_glyph（已在离线 registry 里），它给出抗锯齿覆盖率位图；
//! - **排版/整形**先用字符到字形的一一映射（拉丁/CJK 足够），复杂脚本
//!   （阿拉伯、天城体等）之后接 rustybuzz，接口保持不变；
//! - 覆盖度写进一张 R8 图集（实际用 RGBA8，RGB=255，A=覆盖率），绘制时按 tint 相乘。

use std::collections::HashMap;
use std::sync::atomic::{AtomicU32, Ordering};

use ab_glyph::{point, Font, FontVec, PxScale, ScaleFont};

/// 一张字体。句柄由 FFI 传出（不透明指针）。
pub struct FontHandle {
    pub id: u32,
    pub font: FontVec,
}

static NEXT_FONT_ID: AtomicU32 = AtomicU32::new(1);

impl FontHandle {
    pub fn load(bytes: Vec<u8>) -> Result<Self, String> {
        let font = FontVec::try_from_vec(bytes).map_err(|e| format!("parse font: {e}"))?;
        Ok(Self {
            id: NEXT_FONT_ID.fetch_add(1, Ordering::Relaxed),
            font,
        })
    }
}

/// 图集里一个已缓存字形的位置（像素）与排版的度量。
#[derive(Clone, Copy)]
pub struct GlyphSlot {
    pub x: u32,
    pub y: u32,
    pub w: u32,
    pub h: u32,
    /// 相对笔位的偏移（x 向右、y 向下为正）
    pub bearing_x: f32,
    pub bearing_y: f32,
    pub advance: f32,
}

/// 简单的货架式（shelf）打包图集。
pub struct Atlas {
    pub size: u32,
    pub shelf_y: u32,
    pub shelf_h: u32,
    pub cursor_x: u32,
    pub cache: HashMap<(u32, u16, u32), GlyphSlot>,
}

impl Atlas {
    pub fn new(size: u32) -> Self {
        Self {
            size,
            shelf_y: 0,
            shelf_h: 0,
            cursor_x: 0,
            cache: HashMap::new(),
        }
    }

    /// 为新字形分配位置；返回 None 表示图集已满（调用方应重建图集）。
    pub fn alloc(&mut self, w: u32, h: u32) -> Option<(u32, u32)> {
        let pad = 1;
        if self.cursor_x + w + pad > self.size {
            self.shelf_y += self.shelf_h + pad;
            self.shelf_h = 0;
            self.cursor_x = 0;
        }
        if self.shelf_y + h + pad > self.size {
            return None;
        }
        let pos = (self.cursor_x, self.shelf_y);
        self.cursor_x += w + pad;
        self.shelf_h = self.shelf_h.max(h);
        Some(pos)
    }
}

/// 光栅化结果：覆盖率位图（w*h，单通道）+ 度量。
pub struct RasterGlyph {
    pub w: u32,
    pub h: u32,
    pub coverage: Vec<u8>,
    pub bearing_x: f32,
    pub bearing_y: f32,
    pub advance: f32,
}

/// 把一个字符光栅化成覆盖率位图。复杂脚本整形接入前，这里是一字符一字形。
pub fn rasterize(font: &FontHandle, ch: char, px_size: f32) -> Option<RasterGlyph> {
    let scaled = font.font.as_scaled(PxScale::from(px_size));
    let glyph_id = font.font.glyph_id(ch);
    if glyph_id.0 == 0 {
        return None; // .notdef 或字体缺字
    }
    let advance = scaled.h_advance(glyph_id);
    let glyph = glyph_id.with_scale_and_position(PxScale::from(px_size), point(0.0, 0.0));
    let outlined = font.font.outline_glyph(glyph)?;
    let bounds = outlined.px_bounds();
    let w = bounds.width().ceil() as u32;
    let h = bounds.height().ceil() as u32;
    if w == 0 || h == 0 {
        return Some(RasterGlyph {
            w: 0,
            h: 0,
            coverage: Vec::new(),
            bearing_x: 0.0,
            bearing_y: 0.0,
            advance,
        });
    }
    let mut coverage = vec![0u8; (w * h) as usize];
    outlined.draw(|x, y, cov| {
        let (x, y) = (x as u32, y as u32);
        if x < w && y < h {
            coverage[(y * w + x) as usize] = (cov.clamp(0.0, 1.0) * 255.0) as u8;
        }
    });
    Some(RasterGlyph {
        w,
        h,
        coverage,
        bearing_x: bounds.min.x,
        bearing_y: bounds.min.y,
        advance,
    })
}

/// 字符串按像素宽度量测（不整形；用于布局）。
pub fn measure(font: &FontHandle, text: &str, px_size: f32) -> f32 {
    let scaled = font.font.as_scaled(PxScale::from(px_size));
    text.chars()
        .map(|c| scaled.h_advance(font.font.glyph_id(c)))
        .sum()
}

/// 字体度量（按 px_size 缩放）：(ascent, descent, line_gap, units_per_em)。
pub fn metrics(font: &FontHandle, px_size: f32) -> (f32, f32, f32, f32) {
    use ab_glyph::Font as _;
    let scale = PxScale::from(px_size);
    let scaled = font.font.as_scaled(scale);
    let ascent = scaled.ascent();
    let descent = scaled.descent();
    let gap = scaled.line_gap();
    let upem = font.font.units_per_em().unwrap_or(1000.0);
    (ascent, descent, gap, upem)
}
