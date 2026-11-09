//! 实例化 SDF 管线：一个 draw call 画完所有矩形/圆角矩形/描边。
//!
//! 为什么用 SDF：cui 的 Renderer 面里绝大多数图元是「矩形 / 圆角矩形 / 圆 / 描边」，
//! 用有符号距离场在片元里解析求交，既能拿到解析级抗锯齿，又不需要为每种图元生成
//! 三角网格——一个实例化 draw call 就够，CPU 侧只往缓冲里塞 12 个 float。

use bytemuck::{Pod, Zeroable};

/// 一个矩形实例。所有坐标都是**物理像素**，原点在左上角。
#[repr(C)]
#[derive(Clone, Copy, Pod, Zeroable)]
pub struct RectInstance {
    /// x, y, w, h（像素）
    pub rect: [f32; 4],
    /// r, g, b, a（线性 0..1）
    pub color: [f32; 4],
    /// x: 圆角半径（像素）；y: 描边宽度（0 = 填充）；z/w: 预留
    pub params: [f32; 4],
    /// 裁剪矩形 x, y, w, h（像素；w <= 0 表示不裁剪）
    pub clip: [f32; 4],
}

pub const SHADER: &str = r#"
struct Screen {
  size: vec2f,
  _pad0: vec2f,
  // 全局变换（cui 的 transform 栈在帧内是全局作用）：p' = p * xy_scale + xy_offset
  xform_scale: vec2f,
  _pad1: vec2f,
  xform_offset: vec2f,
  _pad2: vec2f,
};
@group(0) @binding(0) var<uniform> screen: Screen;

struct Inst {
  @location(0) rect: vec4f,
  @location(1) color: vec4f,
  @location(2) params: vec4f,
  @location(3) clip: vec4f,
};

struct VsOut {
  @builtin(position) pos: vec4f,
  @location(0) color: vec4f,
  @location(1) local: vec2f,
  @location(2) half_size: vec2f,
  @location(3) params: vec4f,
  @location(4) clip: vec4f,
  @location(5) world: vec2f,
};

@vertex
fn vs(@builtin(vertex_index) vi: u32, inst: Inst) -> VsOut {
  // 两个三角形拼成矩形（注意顺序：旧的写法让顶点 3/5 重合，第二个三角形退化，
  // 结果每个矩形只画出半个 —— 真机上表现为"高度只有一半"）。
  //   三角形 1: (-1,-1) (1,-1) (-1,1)
  //   三角形 2: (-1,1)  (1,-1) (1,1)
  var cx: f32 = select(-1.0, 1.0, vi == 1u || vi == 4u || vi == 5u);
  var cy: f32 = select(-1.0, 1.0, vi == 2u || vi == 3u || vi == 5u);

  let half_size = vec2f(inst.rect.z * 0.5, inst.rect.w * 0.5);
  let center = vec2f(inst.rect.x, inst.rect.y) + half_size;
  var p = center + vec2f(cx, cy) * half_size;
  // 像素坐标 -> NDC（y 向下）
  let ndc = vec2f(p.x / screen.size.x * 2.0 - 1.0, 1.0 - p.y / screen.size.y * 2.0);

  let world = p * screen.xform_scale + screen.xform_offset;
  let ndc2 = vec2f(world.x / screen.size.x * 2.0 - 1.0, 1.0 - world.y / screen.size.y * 2.0);

  var out: VsOut;
  out.pos = vec4f(ndc2, 0.0, 1.0);
  out.color = inst.color;
  out.local = vec2f(cx, cy) * half_size;
  out.half_size = half_size;
  out.params = inst.params;
  out.clip = inst.clip;
  out.world = world;
  return out;
}

// 圆角矩形的有符号距离：<0 在内部
fn sd_round_box(p: vec2f, b: vec2f, r: f32) -> f32 {
  let q = abs(p) - b + vec2f(r);
  return length(max(q, vec2f(0.0))) + min(max(q.x, q.y), 0.0) - r;
}

@fragment
fn fs(in: VsOut) -> @location(0) vec4f {
  // 裁剪由 render pass 的 scissor 负责（见 lib.rs 的批次分组），这里不再逐像素判断。
  let radius = clamp(in.params.x, 0.0, min(in.half_size.x, in.half_size.y));
  let stroke = in.params.y;
  let d = sd_round_box(in.local, in.half_size, radius);

  if (stroke > 0.0) {
    // 描边：只保留 |d| 落在 [0, stroke] 的部分
    let aa = fwidth(d);
    let outer = 1.0 - smoothstep(0.0, aa, d);
    let inner = 1.0 - smoothstep(-stroke, -stroke + aa, d);
    let cover = clamp(outer - inner, 0.0, 1.0);
    if (cover <= 0.001) { discard; }
    return vec4f(in.color.rgb, in.color.a * cover);
  }
  let aa = fwidth(d);
  let cover = 1.0 - smoothstep(-aa, aa, d);
  if (cover <= 0.001) { discard; }
  return vec4f(in.color.rgb, in.color.a * cover);
}
"#;

/// 一个纹理实例：目标矩形 + UV 子区 + 染色（tint 用来做淡入淡出/图片蒙层）。
#[repr(C)]
#[derive(Clone, Copy, Pod, Zeroable)]
pub struct TexInstance {
    /// 目标矩形 x, y, w, h（像素）
    pub dst: [f32; 4],
    /// UV 子区 u0, v0, u1, v1（0..1）
    pub uv: [f32; 4],
    /// 染色 r, g, b, a（与原色相乘）
    pub tint: [f32; 4],
    /// 裁剪矩形 x, y, w, h（像素；w <= 0 表示不裁剪）
    pub clip: [f32; 4],
}

pub const TEX_SHADER: &str = r#"
struct Screen {
  size: vec2f,
  _pad0: vec2f,
  xform_scale: vec2f,
  _pad1: vec2f,
  xform_offset: vec2f,
  _pad2: vec2f,
};
@group(0) @binding(0) var<uniform> screen: Screen;
@group(1) @binding(0) var tex: texture_2d<f32>;
@group(1) @binding(1) var samp: sampler;

struct Inst {
  @location(0) dst: vec4f,
  @location(1) uv: vec4f,
  @location(2) tint: vec4f,
  @location(3) clip: vec4f,
};

struct VsOut {
  @builtin(position) pos: vec4f,
  @location(0) uv: vec2f,
  @location(1) tint: vec4f,
  @location(2) clip: vec4f,
  @location(3) world: vec2f,
};

@vertex
fn vs(@builtin(vertex_index) vi: u32, inst: Inst) -> VsOut {
  // 两个三角形拼成矩形（注意顺序：旧的写法让顶点 3/5 重合，第二个三角形退化，
  // 结果每个矩形只画出半个 —— 真机上表现为"高度只有一半"）。
  //   三角形 1: (-1,-1) (1,-1) (-1,1)
  //   三角形 2: (-1,1)  (1,-1) (1,1)
  var cx: f32 = select(-1.0, 1.0, vi == 1u || vi == 4u || vi == 5u);
  var cy: f32 = select(-1.0, 1.0, vi == 2u || vi == 3u || vi == 5u);

  let p = vec2f(inst.dst.x + (cx * 0.5 + 0.5) * inst.dst.z,
                inst.dst.y + (cy * 0.5 + 0.5) * inst.dst.w);
  let world = p * screen.xform_scale + screen.xform_offset;
  let ndc = vec2f(world.x / screen.size.x * 2.0 - 1.0, 1.0 - world.y / screen.size.y * 2.0);

  var out: VsOut;
  out.pos = vec4f(ndc, 0.0, 1.0);
  out.uv = mix(inst.uv.xy, inst.uv.zw, vec2f(cx * 0.5 + 0.5, cy * 0.5 + 0.5));
  out.tint = inst.tint;
  out.clip = inst.clip;
  out.world = world;
  return out;
}

@fragment
fn fs(in: VsOut) -> @location(0) vec4f {
  let c = textureSample(tex, samp, in.uv);
  return c * in.tint;
}
"#;
