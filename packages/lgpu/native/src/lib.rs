//! L 层渲染器的原生实现（wgpu → Vulkan → VK_OHOS_surface）。
//!
//! 约束（与 webview_native / fontkit_native 一致）：
//! - 只导出 **C ABI**，句柄不透明，绝不跨语言传 GC 指针；
//! - 失败返回负错误码，错误文本用线程局部保存，`lgpu_last_error()` 取回。
//!
//! 本文件当前是 P2 的第一块：实例创建 + 适配器枚举 + surface 创建。
//! 管线/绘制在后续加入（见 docs/l-layer-plan）。

mod gpu;
mod text;

use std::cell::RefCell;
use std::ffi::{c_char, c_void, CStr, CString};
use std::ptr::NonNull;
use std::sync::{Mutex, OnceLock};

use raw_window_handle::{OhosDisplayHandle, OhosNdkWindowHandle, RawDisplayHandle, RawWindowHandle};

const VERSION: &str = concat!("lgpu ", env!("CARGO_PKG_VERSION"), " wgpu/vulkan");

// 错误码（负数），与 Cangjie 侧约定一致。
const E_NO_INSTANCE: i32 = -2;
const E_NO_ADAPTER: i32 = -3;
const E_NO_DEVICE: i32 = -4;
const E_BAD_ARG: i32 = -5;

thread_local! {
    static LAST_ERROR: RefCell<Option<CString>> = const { RefCell::new(None) };
}

/// 所有会改 SurfaceCtx 的 FFI 入口共用这把锁。
/// 为什么需要：Cangjie 侧可能在**另一个线程**（例如窗口就绪后的绘制线程）调进 lgpu，
/// 而 ArkTS 线程同时也在调（自检）；两份 &mut SurfaceCtx 并发就是数据竞争（真机上直接 SIGSEGV）。
static SURF_LOCK: Mutex<()> = Mutex::new(());

// ---- 帧统计（M0 度量：draw call / 实例 / 上传 / 测量）----------------------
// 全部用 Relaxed 原子计数：只做趋势观测，不参与同步。
use std::sync::atomic::{AtomicU64, Ordering};

pub struct FrameStats {
    /// 每帧渲染 pass 内的 draw call 次数（rect 组 + tex 组）
    pub draw_calls: AtomicU64,
    /// 每帧矩形实例数
    pub rect_instances: AtomicU64,
    /// 每帧纹理/字形实例数
    pub tex_instances: AtomicU64,
    /// 纹理实例合批后的 run 数（每 run 一次 bind group 切换）
    pub tex_runs: AtomicU64,
    /// write_texture 累计字节（RGBA）
    pub upload_bytes: AtomicU64,
    /// write_texture 调用次数
    pub uploads: AtomicU64,
    /// lgpu_text_measure 调用次数
    pub text_measures: AtomicU64,
    /// lgpu_texture_create 调用次数
    pub texture_creates: AtomicU64,
    /// lgpu_texture_destroy 调用次数
    pub texture_destroys: AtomicU64,
    /// 当前存活纹理数（create - destroy 的差值维护）
    pub textures_alive: AtomicU64,
    /// 累计渲染帧数
    pub frames: AtomicU64,
    /// R5.3：超过整页图集的单个字形被跳过的次数（仍前进半个字宽，不中断整段）
    pub glyph_overflow: AtomicU64,
    /// R5.3：图集页因超上限被淘汰的次数（FIFO）
    pub atlas_page_evict: AtomicU64,
}

static STATS: FrameStats = FrameStats {
    draw_calls: AtomicU64::new(0),
    rect_instances: AtomicU64::new(0),
    tex_instances: AtomicU64::new(0),
    tex_runs: AtomicU64::new(0),
    upload_bytes: AtomicU64::new(0),
    uploads: AtomicU64::new(0),
    text_measures: AtomicU64::new(0),
    texture_creates: AtomicU64::new(0),
    texture_destroys: AtomicU64::new(0),
    textures_alive: AtomicU64::new(0),
    frames: AtomicU64::new(0),
    glyph_overflow: AtomicU64::new(0),
    atlas_page_evict: AtomicU64::new(0),
};

fn stats_view() -> &'static FrameStats {
    &STATS
}

fn stats_reset() {
    for f in [
        &STATS.draw_calls,
        &STATS.rect_instances,
        &STATS.tex_instances,
        &STATS.tex_runs,
        &STATS.upload_bytes,
        &STATS.uploads,
        &STATS.text_measures,
        &STATS.texture_creates,
        &STATS.texture_destroys,
        &STATS.frames,
        &STATS.glyph_overflow,
        &STATS.atlas_page_evict,
    ] {
        f.store(0, Ordering::Relaxed);
    }
}

/// 把当前统计打包成 "k=v k=v ..." 的一行（Cangjie 侧解析打点）。
#[no_mangle]
pub extern "C" fn lgpu_stats_line(out: *mut c_char, out_len: usize) -> i32 {
    let s = stats_view();
    let line = format!(
        "draws={} rects={} texs={} runs={} uploads={} up_bytes={} measures={} tex_create={} tex_destroy={} tex_alive={} frames={} glyph_overflow={} atlas_evict={}",
        s.draw_calls.load(Ordering::Relaxed),
        s.rect_instances.load(Ordering::Relaxed),
        s.tex_instances.load(Ordering::Relaxed),
        s.tex_runs.load(Ordering::Relaxed),
        s.uploads.load(Ordering::Relaxed),
        s.upload_bytes.load(Ordering::Relaxed),
        s.text_measures.load(Ordering::Relaxed),
        s.texture_creates.load(Ordering::Relaxed),
        s.texture_destroys.load(Ordering::Relaxed),
        s.textures_alive.load(Ordering::Relaxed),
        s.frames.load(Ordering::Relaxed),
        s.glyph_overflow.load(Ordering::Relaxed),
        s.atlas_page_evict.load(Ordering::Relaxed),
    );
    write_c_str(out, out_len, &line);
    0
}

/// 清零全部计数（配合窗口采样：reset → 渲染 N 帧 → read）。
#[no_mangle]
pub extern "C" fn lgpu_stats_reset() {
    stats_reset()
}

// ---- 抓帧（Modal 模糊 / 页面转场快照）------------------------------------
// 渲染完一帧后把 surface 纹理拷进缓冲区，供 Cangjie 侧读取（CPU 模糊用）。
static CAPTURE_REQ: std::sync::atomic::AtomicBool = std::sync::atomic::AtomicBool::new(false);
static CAPTURE_DATA: Mutex<Option<(u32, u32, Vec<u8>)>> = Mutex::new(None);

/// 请求下一帧结束时抓帧（一次性）。
#[no_mangle]
pub extern "C" fn lgpu_capture_request() -> i32 {
    CAPTURE_REQ.store(true, std::sync::atomic::Ordering::SeqCst);
    0
}

/// 取最近一次抓帧的尺寸；没有则返回 0。
#[no_mangle]
pub extern "C" fn lgpu_capture_size(out_w: *mut u32, out_h: *mut u32) -> i32 {
    let guard = match CAPTURE_DATA.lock() { Ok(g) => g, Err(_) => return -1 };
    match guard.as_ref() {
        Some((w, h, _)) => {
            unsafe { if !out_w.is_null() { *out_w = *w; } if !out_h.is_null() { *out_h = *h; } }
            0
        }
        None => 1,
    }
}

/// 把最近一次抓帧写成原始 RGBA 文件（无头部）。返回 0 成功。
#[no_mangle]
pub extern "C" fn lgpu_capture_write(path: *const u8, path_len: usize) -> i32 {
    let path_s = match unsafe { std::str::from_utf8(std::slice::from_raw_parts(path, path_len)) } {
        Ok(v) => v,
        Err(_) => { set_error("capture path not utf8"); return -1; }
    };
    let guard = match CAPTURE_DATA.lock() { Ok(g) => g, Err(_) => return -1 };
    let Some((w, h, px)) = guard.as_ref() else { set_error("no capture data"); return -1 };
    match std::fs::write(path_s, px.as_slice()) {
        Ok(_) => 0,
        Err(e) => { set_error(format!("capture write: {e}")); -1 }
    }
}

fn lock_surface() -> std::sync::MutexGuard<'static, ()> {
    SURF_LOCK.lock().unwrap_or_else(|e| e.into_inner())
}

/// 第一条 wgpu 校验错误（诊断用；不被后续 set_error 覆盖）
static GPU_ERROR: Mutex<Option<String>> = Mutex::new(None);

fn set_gpu_error(msg: String) {
    if let Ok(mut g) = GPU_ERROR.lock() {
        if g.is_none() {
            *g = Some(msg);
        }
    }
}

fn gpu_error() -> String {
    GPU_ERROR.lock().ok().and_then(|g| g.clone()).unwrap_or_default()
}

fn set_error(msg: impl Into<String>) {
    let s = msg.into();
    LAST_ERROR.with(|e| *e.borrow_mut() = CString::new(s).ok());
}

/// 进程级实例：wgpu 的 Instance 不便宜，整个应用共用一个。
static INSTANCE: OnceLock<Mutex<Option<wgpu::Instance>>> = OnceLock::new();

fn instance_slot() -> &'static Mutex<Option<wgpu::Instance>> {
    INSTANCE.get_or_init(|| Mutex::new(None))
}

/// 版本字符串（NUL 结尾，进程生命周期内有效）。
#[no_mangle]
pub extern "C" fn lgpu_version() -> *const c_char {
    thread_local! { static V: CString = CString::new(VERSION).unwrap(); }
    V.with(|v| v.as_ptr())
}

/// 最近一次失败原因；无错误时为空串。
#[no_mangle]
pub extern "C" fn lgpu_last_error() -> *const c_char {
    thread_local! { static EMPTY: CString = CString::new("").unwrap(); }
    LAST_ERROR.with(|e| match e.borrow().as_ref() {
        Some(c) => c.as_ptr(),
        None => EMPTY.with(|m| m.as_ptr()),
    })
}

/// 创建 Vulkan 实例。0 = 成功。
#[no_mangle]
pub extern "C" fn lgpu_init() -> i32 {
    let mut slot = match instance_slot().lock() {
        Ok(g) => g,
        Err(_) => {
            set_error("instance lock poisoned");
            return E_NO_INSTANCE;
        }
    };
    if slot.is_some() {
        return 0;
    }
    let desc = wgpu::InstanceDescriptor {
        backends: wgpu::Backends::VULKAN,
        ..wgpu::InstanceDescriptor::new_without_display_handle()
    };
    *slot = Some(wgpu::Instance::new(desc));
    0
}

/// 枚举适配器，把 "name|backend|type" 每行一条写入 `out`（NUL 结尾）。
/// 返回写入的适配器数量（>=0）或负错误码。
#[no_mangle]
pub extern "C" fn lgpu_adapter_summary(out: *mut c_char, out_len: usize) -> i32 {
    if out.is_null() || out_len == 0 {
        set_error("bad argument: out buffer");
        return E_BAD_ARG;
    }
    if lgpu_init() != 0 {
        return E_NO_INSTANCE;
    }
    let guard = match instance_slot().lock() {
        Ok(g) => g,
        Err(_) => {
            set_error("instance lock poisoned");
            return E_NO_INSTANCE;
        }
    };
    let Some(instance) = guard.as_ref() else {
        set_error("instance missing");
        return E_NO_INSTANCE;
    };

    let adapters = pollster::block_on(instance.enumerate_adapters(wgpu::Backends::VULKAN));
    let mut text = String::new();
    for a in &adapters {
        let info = a.get_info();
        text.push_str(&format!(
            "{}|{:?}|{:?}\n",
            info.name, info.backend, info.device_type
        ));
    }
    if adapters.is_empty() {
        set_error("no vulkan adapter (VK_OHOS_surface unavailable?)");
    }
    write_c_str(out, out_len, &text);
    adapters.len() as i32
}

/// 一个 surface 的全部运行期状态：surface + 选中的 device/queue + 配置。
/// 离屏「截图目标」：所有 UI 先画进这张 **Rgba8Unorm** 纹理（gamma 空间混合），
/// 再用 blit 管线转换成线性写到 sRGB 交换链 —— 交换链的硬件编码把它还原成原值。
/// 这样半透明阴影/遮罩的混合结果与设计稿一致（horizon 用非 sRGB 交换链达成同一效果，
/// 但 OHOS 上配非 sRGB 会原生崩溃，见 docs/lgpu-color-pipeline.md）。
struct Offscreen {
    tex: wgpu::Texture,
    view: wgpu::TextureView,
    bind: wgpu::BindGroup,
}

pub struct SurfaceCtx {
    surface: wgpu::Surface<'static>,
    device: Option<wgpu::Device>,
    queue: Option<wgpu::Queue>,
    config: Option<wgpu::SurfaceConfiguration>,
    pipeline: Option<wgpu::RenderPipeline>,
    inst_buffer: Option<wgpu::Buffer>,
    inst_capacity: usize,
    screen_buffer: Option<wgpu::Buffer>,
    bind_group: Option<wgpu::BindGroup>,
    instances: Vec<gpu::RectInstance>,
    clear_color: [f32; 4],
    xform_scale: [f32; 2],
    xform_offset: [f32; 2],
    clip: [f32; 4],
    tex_pipeline: Option<wgpu::RenderPipeline>,
    tex_bgl: Option<wgpu::BindGroupLayout>,
    tex_sampler: Option<wgpu::Sampler>,
    tex_instances: Vec<(gpu::TexInstance, *mut c_void)>,
    tex_buffer: Option<wgpu::Buffer>,
    tex_capacity: usize,
    tex_order: Vec<*mut c_void>,
    /// 层断点：(rect 实例数, 纹理实例数)。帧内按断点分段，段内仍是"先矩形后纹理"，
    /// 段间严格按录制顺序——快照遮罩之上的描边/图标/Toast 不会再被纹理盖住。
    layer_marks: Vec<(usize, usize)>,
    /// 字形图集页（RGBA8，A 通道存覆盖率）。R5.3：满页自动新开一页，
    /// **绝不丢字**——之前单页 1024² 满了直接 break，CJK/多字号场景文字静默消失。
    atlas_pages: Vec<(*mut c_void, text::Atlas)>,
    /// 待销毁的纹理：帧内淘汰的图集页不能立刻 free（本帧已录制的图元还引用它），
    /// 统一在 frame_end 提交之后销毁。只放裸指针，数量很小。
    pending_destroy: Vec<*mut c_void>,
    /// 离屏 gamma 目标与上屏 blit 管线
    offscreen: Option<Offscreen>,
    blit_pipeline: Option<wgpu::RenderPipeline>,
    blit_bgl: Option<wgpu::BindGroupLayout>,
    blit_sampler: Option<wgpu::Sampler>,
}

/// 图集页上限：8 页 × 1024² × 4B = 32MB 显存。超过就淘汰最旧页（FIFO），
/// 其字形之后按需重新光栅化——比无界增长/静默丢字都好。
const MAX_ATLAS_PAGES: usize = 8;

/// 已持锁时的纹理销毁（避免第二次 lock_surface 死锁）。
fn destroy_texture_locked(tex: *mut c_void) {
    if tex.is_null() {
        return;
    }
    STATS.texture_destroys.fetch_add(1, Ordering::Relaxed);
    STATS.textures_alive.fetch_sub(1, Ordering::Relaxed);
    drop(unsafe { Box::from_raw(tex as *mut TexCtx) });
}

impl Drop for SurfaceCtx {
    fn drop(&mut self) {
        // SurfaceCtx 被 Box::from_raw 释放时，图集页与待销毁纹理的 TexCtx 也要释放，
        // 否则每页泄漏一张 wgpu 纹理（数组里存的是裸指针）。
        for (tex, _) in self.atlas_pages.drain(..) {
            drop(unsafe { Box::from_raw(tex as *mut TexCtx) });
        }
        for tex in self.pending_destroy.drain(..) {
            drop(unsafe { Box::from_raw(tex as *mut TexCtx) });
        }
    }
}

/// 离屏目标格式：Unorm —— 存的是 **gamma 空间**的值，混合也在该空间完成。
const SCREEN_FORMAT: wgpu::TextureFormat = wgpu::TextureFormat::Rgba8Unorm;

/// 上屏 blit：把离屏目标（gamma 值）转成线性写进 sRGB 交换链。
/// 硬件随后做 linear→sRGB 编码，输出即等于原始 sRGB 值，不产生二次编码。
const BLIT_SHADER: &str = r#"
struct VsOut {
    @builtin(position) pos: vec4<f32>,
    @location(0) uv: vec2<f32>,
};

@vertex
fn vs_main(@builtin(vertex_index) i: u32) -> VsOut {
    var pts = array<vec2<f32>, 3>(
        vec2<f32>(-1.0, -1.0),
        vec2<f32>(3.0, -1.0),
        vec2<f32>(-1.0, 3.0),
    );
    let xy = pts[i];
    var o: VsOut;
    o.pos = vec4<f32>(xy, 0.0, 1.0);
    o.uv = vec2<f32>((xy.x + 1.0) * 0.5, 1.0 - (xy.y + 1.0) * 0.5);
    return o;
}

@group(0) @binding(0) var src: texture_2d<f32>;
@group(0) @binding(1) var samp: sampler;

fn srgb_to_linear(c: vec3<f32>) -> vec3<f32> {
    let lo = c / 12.92;
    let hi = pow((c + vec3<f32>(0.055)) / 1.055, vec3<f32>(2.4));
    return select(hi, lo, c <= vec3<f32>(0.04045));
}

@fragment
fn fs_main(in: VsOut) -> @location(0) vec4<f32> {
    let c = textureSample(src, samp, in.uv);
    return vec4<f32>(srgb_to_linear(c.rgb), 1.0);
}
"#;

/// 惰性创建/更新离屏目标与 blit 管线（尺寸变化时重建纹理与 bind group）。
fn ensure_offscreen(ctx: &mut SurfaceCtx, device: &wgpu::Device, target_format: wgpu::TextureFormat) {
    let Some(cfg) = ctx.config.as_ref() else { return };
    let (w, h) = (cfg.width.max(1), cfg.height.max(1));
    let need_new_tex = match &ctx.offscreen {
        Some(o) => o.tex.width() != w || o.tex.height() != h,
        None => true,
    };

    if ctx.blit_bgl.is_none() {
        let shader = device.create_shader_module(wgpu::ShaderModuleDescriptor {
            label: Some("lgpu-blit"),
            source: wgpu::ShaderSource::Wgsl(BLIT_SHADER.into()),
        });
        let bgl = device.create_bind_group_layout(&wgpu::BindGroupLayoutDescriptor {
            label: Some("lgpu-blit-bgl"),
            entries: &[
                wgpu::BindGroupLayoutEntry {
                    binding: 0,
                    visibility: wgpu::ShaderStages::FRAGMENT,
                    ty: wgpu::BindingType::Texture {
                        sample_type: wgpu::TextureSampleType::Float { filterable: true },
                        view_dimension: wgpu::TextureViewDimension::D2,
                        multisampled: false,
                    },
                    count: None,
                },
                wgpu::BindGroupLayoutEntry {
                    binding: 1,
                    visibility: wgpu::ShaderStages::FRAGMENT,
                    ty: wgpu::BindingType::Sampler(wgpu::SamplerBindingType::Filtering),
                    count: None,
                },
            ],
        });
        let layout = device.create_pipeline_layout(&wgpu::PipelineLayoutDescriptor {
            label: Some("lgpu-blit-layout"),
            bind_group_layouts: &[Some(&bgl)],
            immediate_size: 0,
        });
        let pipeline = device.create_render_pipeline(&wgpu::RenderPipelineDescriptor {
            label: Some("lgpu-blit-pipeline"),
            layout: Some(&layout),
            vertex: wgpu::VertexState {
                module: &shader,
                entry_point: Some("vs_main"),
                compilation_options: Default::default(),
                buffers: &[],
            },
            fragment: Some(wgpu::FragmentState {
                module: &shader,
                entry_point: Some("fs_main"),
                compilation_options: Default::default(),
                targets: &[Some(wgpu::ColorTargetState {
                    format: target_format,
                    blend: None,
                    write_mask: wgpu::ColorWrites::ALL,
                })],
            }),
            primitive: wgpu::PrimitiveState::default(),
            depth_stencil: None,
            multisample: wgpu::MultisampleState::default(),
            multiview_mask: None,
            cache: None,
        });
        ctx.blit_pipeline = Some(pipeline);
        ctx.blit_bgl = Some(bgl);
        ctx.blit_sampler = Some(device.create_sampler(&wgpu::SamplerDescriptor {
            label: Some("lgpu-blit-sampler"),
            mag_filter: wgpu::FilterMode::Nearest,
            min_filter: wgpu::FilterMode::Nearest,
            ..Default::default()
        }));
    }

    if need_new_tex {
        let tex = device.create_texture(&wgpu::TextureDescriptor {
            label: Some("lgpu-offscreen"),
            size: wgpu::Extent3d { width: w, height: h, depth_or_array_layers: 1 },
            mip_level_count: 1,
            sample_count: 1,
            dimension: wgpu::TextureDimension::D2,
            format: SCREEN_FORMAT,
            usage: wgpu::TextureUsages::RENDER_ATTACHMENT | wgpu::TextureUsages::TEXTURE_BINDING,
            view_formats: &[],
        });
        let view = tex.create_view(&wgpu::TextureViewDescriptor::default());
        let bind = device.create_bind_group(&wgpu::BindGroupDescriptor {
            label: Some("lgpu-blit-bind"),
            layout: ctx.blit_bgl.as_ref().expect("blit bgl"),
            entries: &[
                wgpu::BindGroupEntry { binding: 0, resource: wgpu::BindingResource::TextureView(&view) },
                wgpu::BindGroupEntry {
                    binding: 1,
                    resource: wgpu::BindingResource::Sampler(ctx.blit_sampler.as_ref().expect("blit sampler")),
                },
            ],
        });
        ctx.offscreen = Some(Offscreen { tex, view, bind });
    }
}

/// 把离屏目标 blit 到交换链视图（一个 draw，全屏三角形）。
fn draw_blit(pass: &mut wgpu::RenderPass<'_>, ctx: &SurfaceCtx) {
    if let (Some(p), Some(off)) = (&ctx.blit_pipeline, &ctx.offscreen) {
        pass.set_pipeline(p);
        pass.set_bind_group(0, &off.bind, &[]);
        pass.draw(0..3, 0..1);
    }
}

/// 用 XComponent 的 OHNativeWindow* 建 wgpu surface。
/// 成功返回不透明句柄（!= null），失败返回 null 并可用 `lgpu_last_error()` 取原因。
#[no_mangle]
pub extern "C" fn lgpu_surface_create(native_window: *mut c_void) -> *mut c_void {
    if native_window.is_null() {
        set_error("null native window");
        return std::ptr::null_mut();
    }
    if lgpu_init() != 0 {
        return std::ptr::null_mut();
    }
    let guard = match instance_slot().lock() {
        Ok(g) => g,
        Err(_) => {
            set_error("instance lock poisoned");
            return std::ptr::null_mut();
        }
    };
    let Some(instance) = guard.as_ref() else {
        set_error("instance missing");
        return std::ptr::null_mut();
    };

    let raw_window = RawWindowHandle::OhosNdk(OhosNdkWindowHandle::new(
        NonNull::new(native_window).expect("checked non-null"),
    ));
    let raw_display = RawDisplayHandle::Ohos(OhosDisplayHandle::new());
    let target = wgpu::SurfaceTargetUnsafe::RawHandle {
        raw_display_handle: Some(raw_display),
        raw_window_handle: raw_window,
    };
    // SAFETY: 调用方保证 native_window 在 surface 生命周期内有效（XComponent 存活期）。
    match unsafe { instance.create_surface_unsafe(target) } {
        Ok(surface) => Box::into_raw(Box::new(SurfaceCtx {
            surface,
            device: None,
            queue: None,
            config: None,
            pipeline: None,
            inst_buffer: None,
            inst_capacity: 0,
            screen_buffer: None,
            bind_group: None,
            instances: Vec::new(),
            clear_color: [0.0, 0.0, 0.0, 1.0],
            xform_scale: [1.0, 1.0],
            xform_offset: [0.0, 0.0],
            clip: [0.0, 0.0, 0.0, 0.0],
            tex_pipeline: None,
            tex_bgl: None,
            tex_sampler: None,
            tex_instances: Vec::new(),
            tex_buffer: None,
            tex_capacity: 0,
            tex_order: Vec::new(),
            layer_marks: Vec::new(),
            atlas_pages: Vec::new(),
            pending_destroy: Vec::new(),
            offscreen: None,
            blit_pipeline: None,
            blit_bgl: None,
            blit_sampler: None,
        })) as *mut c_void,
        Err(e) => {
            set_error(format!("create_surface failed: {e}"));
            std::ptr::null_mut()
        }
    }
}

/// 释放 `lgpu_surface_create` 返回的句柄。
#[no_mangle]
pub extern "C" fn lgpu_surface_destroy(surface: *mut c_void) {
    if surface.is_null() {
        return;
    }
    // SAFETY: 指针来自 lgpu_surface_create 的 Box::into_raw，且只释放一次。
    drop(unsafe { Box::from_raw(surface as *mut SurfaceCtx) });
}

/// 自检：实例可用且能枚举适配器则返回 0。
#[no_mangle]
pub extern "C" fn lgpu_self_check() -> i32 {
    let mut buf = [0u8; 4096];
    // c_char 在本工具链上是 i8：u8 数组按位重解释（长度一致，无值变化）。
    let n = lgpu_adapter_summary(buf.as_mut_ptr() as *mut c_char, buf.len());
    if n < 0 { n } else { 0 }
}

/// 按 clip 连续分组绘制矩形实例（每组一个 scissor + 一次 draw）。
fn draw_rect_batches(
    pass: &mut wgpu::RenderPass<'_>,
    pipeline: &wgpu::RenderPipeline,
    bind_group: &wgpu::BindGroup,
    buffer: &wgpu::Buffer,
    instances: &[gpu::RectInstance],
    width: u32,
    height: u32,
) {
    let stride = std::mem::size_of::<gpu::RectInstance>() as u64;
    pass.set_pipeline(pipeline);
    pass.set_bind_group(0, bind_group, &[]);
    // 按 clip 连续分组：同组一次实例化 draw（一个 scissor 覆盖整组）。
    // 之前"多实例不出图"的真因是四边形第二个三角形退化（只画出半个），已修。
    let mut i = 0usize;
    while i < instances.len() {
        let clip = instances[i].clip;
        let mut j = i + 1;
        while j < instances.len() && instances[j].clip == clip {
            j += 1;
        }
        apply_scissor(pass, clip, width, height);
        let begin = i as u64 * stride;
        let end = j as u64 * stride;
        pass.set_vertex_buffer(0, buffer.slice(begin..end));
        pass.draw(0..6, 0..(j - i) as u32);
        i = j;
    }
}

/// 统计矩形实例按 clip 分组后的组数（与 draw_rect_batches 的分组一致，纯计数用）。
fn draw_rect_batch_count(instances: &[gpu::RectInstance]) -> u64 {
    let mut groups = 0u64;
    let mut i = 0usize;
    while i < instances.len() {
        let clip = instances[i].clip;
        let mut j = i + 1;
        while j < instances.len() && instances[j].clip == clip {
            j += 1;
        }
        groups += 1;
        i = j;
    }
    groups
}

/// 把纹理实例列表按「相邻且 (纹理指针, clip) 相同」划分为若干 run，返回每段的 [begin, end)。
/// R1 合批的唯一分组规则：frame_end 与 capture_offscreen 共用，保证抓帧与屏幕一致。
fn tex_run_bounds(instances: &[(gpu::TexInstance, *mut c_void)]) -> Vec<(usize, usize)> {
    let mut out: Vec<(usize, usize)> = Vec::new();
    let mut i = 0usize;
    while i < instances.len() {
        let (inst, tex_ptr) = &instances[i];
        let clip = inst.clip;
        let mut j = i + 1;
        while j < instances.len() {
            let (ninst, ntex) = &instances[j];
            if *ntex != *tex_ptr || ninst.clip != clip {
                break;
            }
            j += 1;
        }
        out.push((i, j));
        i = j;
    }
    out
}

/// 把 clip 矩形（像素，命中测试用 top-left 原点）转成 scissor（整数、裁到 surface 内）。
fn apply_scissor(pass: &mut wgpu::RenderPass<'_>, clip: [f32; 4], width: u32, height: u32) {
    if clip[2] <= 0.0 || clip[3] <= 0.0 {
        pass.set_scissor_rect(0, 0, width, height);
        return;
    }
    let x0 = clip[0].max(0.0).floor() as u32;
    let y0 = clip[1].max(0.0).floor() as u32;
    let x1 = (clip[0] + clip[2]).min(width as f32).ceil() as u32;
    let y1 = (clip[1] + clip[3]).min(height as f32).ceil() as u32;
    let w = x1.saturating_sub(x0);
    let h = y1.saturating_sub(y0);
    if w == 0 || h == 0 {
        pass.set_scissor_rect(0, 0, 0, 0);
    } else {
        pass.set_scissor_rect(x0, y0, w, h);
    }
}

fn write_c_str(out: *mut c_char, out_len: usize, text: &str) {
    let bytes = text.as_bytes();
    let cap = out_len.saturating_sub(1);
    let n = bytes.len().min(cap);
    // SAFETY: 调用方给出至少 out_len 字节的可写缓冲。
    unsafe {
        std::ptr::copy_nonoverlapping(bytes.as_ptr() as *const c_char, out, n);
        *out.add(n) = 0;
    }
}

/// 让 Cangjie 侧能把错误文本直接打印出来（调试期用）。
#[no_mangle]
pub extern "C" fn lgpu_debug_dump(out: *mut c_char, out_len: usize) -> i32 {
    let mut buf = [0u8; 4096];
    let n = lgpu_adapter_summary(buf.as_mut_ptr() as *mut c_char, buf.len());
    let adapters = unsafe { CStr::from_ptr(buf.as_ptr() as *const c_char) }.to_string_lossy().to_string();
    let text = format!(
        "{}\n-- adapters ({}) --\n{}\n-- last_error: {} --\n",
        VERSION,
        n,
        adapters,
        unsafe { CStr::from_ptr(lgpu_last_error()) }.to_string_lossy()
    );
    write_c_str(out, out_len, &text);
    0
}


/// swapchain 格式：**非 sRGB** 目标。
///
/// 对齐 horizon（`crates/horizon-client/src/gfx.rs::surface_format`）的做法与理由：
/// horizon 的做法（`crates/horizon-client/src/gfx.rs::surface_format`）：选非 sRGB 目标，
/// 理由是其内容在 gamma 空间混合。**OHOS 上该方案不可用**：配非 sRGB 目标直接原生崩溃
/// （第 117 轮实测两次，Rgba8Unorm/Bgra8Unorm 皆崩），故退回 sRGB 目标，
/// 由 `canvas.cj` 的 sRGB→linear 预解码抵消硬件的 linear→sRGB 编码。
fn surface_format(formats: &[wgpu::TextureFormat], default: wgpu::TextureFormat) -> wgpu::TextureFormat {
    // 实测：OHOS 上非 sRGB swapchain 一 configure 就崩（Cpp Crash），
    // 只能保留 sRGB 目标，改由 CPU 侧把调色板预解码成线性来抵消硬件编码。
    formats
        .iter()
        .copied()
        .find(|f| f.is_srgb())
        .unwrap_or(default)
}

/// 在已有 surface 上初始化 device/queue 并按尺寸配置 swapchain。
/// 0 = 成功；负值 = 失败（原因见 `lgpu_last_error()`）。
#[no_mangle]
pub extern "C" fn lgpu_surface_init(surface: *mut c_void, width: u32, height: u32) -> i32 {
    if surface.is_null() || width == 0 || height == 0 {
        set_error("bad argument: surface/width/height");
        return E_BAD_ARG;
    }
    // SAFETY: 句柄来自 lgpu_surface_create，调用期间保持有效。
    let _guard = lock_surface();
    let ctx = unsafe { &mut *(surface as *mut SurfaceCtx) };
    if ctx.config.is_some() {
        return 0; // 已初始化
    }
    let guard = match instance_slot().lock() {
        Ok(g) => g,
        Err(_) => {
            set_error("instance lock poisoned");
            return E_NO_INSTANCE;
        }
    };
    let Some(instance) = guard.as_ref() else {
        set_error("instance missing");
        return E_NO_INSTANCE;
    };

    let adapter = match pollster::block_on(instance.request_adapter(&wgpu::RequestAdapterOptions {
        power_preference: wgpu::PowerPreference::HighPerformance,
        force_fallback_adapter: false,
        compatible_surface: Some(&ctx.surface),
        apply_limit_buckets: false,
    })) {
        Ok(a) => a,
        Err(e) => {
            set_error(format!("request_adapter failed: {e}"));
            return E_NO_ADAPTER;
        }
    };
    let (device, queue) = match pollster::block_on(adapter.request_device(&wgpu::DeviceDescriptor {
        label: Some("lgpu"),
        ..Default::default()
    })) {
        Ok(pair) => pair,
        Err(e) => {
            set_error(format!("request_device failed: {e}"));
            return E_NO_DEVICE;
        }
    };

    let caps = ctx.surface.get_capabilities(&adapter);
    let format = surface_format(&caps.formats, caps.formats[0]);

    let config = wgpu::SurfaceConfiguration {
        usage: wgpu::TextureUsages::RENDER_ATTACHMENT,
        format,
        width,
        height,
        present_mode: wgpu::PresentMode::AutoVsync,
        color_space: wgpu::SurfaceColorSpace::Auto,
        desired_maximum_frame_latency: 2,
        alpha_mode: caps.alpha_modes[0],
        view_formats: vec![],
    };
    // 把所有未捕获的 wgpu 校验错误/设备丢失记到 last_error，真机上才看得到原因
    device.on_uncaptured_error(std::sync::Arc::new(|err: wgpu::Error| {
        set_gpu_error(format!("{err}"));
    }));
    let adapter_name = adapter.get_info().name;
    device.set_device_lost_callback(move |reason, msg| {
        set_error(format!("device lost ({reason:?}) on {adapter_name}: {msg}"));
    });
    ctx.surface.configure(&device, &config);
    ctx.device = Some(device);
    ctx.queue = Some(queue);
    ctx.config = Some(config);
    0
}

/// 用给定颜色清一帧并 present（上屏自检）。
#[no_mangle]
pub extern "C" fn lgpu_present_clear(surface: *mut c_void, r: f32, g: f32, b: f32, a: f32) -> i32 {
    if surface.is_null() {
        set_error("null surface");
        return E_BAD_ARG;
    }
    // SAFETY: 同上，句柄有效且线程由调用方保证（L 层主线程）。
    let _guard = lock_surface();
    let ctx = unsafe { &mut *(surface as *mut SurfaceCtx) };
    let (Some(device), Some(queue), Some(config)) = (&ctx.device, &ctx.queue, &ctx.config) else {
        set_error("surface not initialised");
        return E_BAD_ARG;
    };

    let frame = match ctx.surface.get_current_texture() {
        wgpu::CurrentSurfaceTexture::Success(f) | wgpu::CurrentSurfaceTexture::Suboptimal(f) => f,
        other => {
            set_error(format!("get_current_texture: {other:?}"));
            return E_NO_DEVICE;
        }
    };
    let view = frame
        .texture
        .create_view(&wgpu::TextureViewDescriptor::default());
    let mut encoder = device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
        label: Some("lgpu-clear"),
    });
    {
        let _pass = encoder.begin_render_pass(&wgpu::RenderPassDescriptor {
            label: Some("lgpu-clear-pass"),
            color_attachments: &[Some(wgpu::RenderPassColorAttachment {
                view: &view,
                resolve_target: None,
                depth_slice: None,
                ops: wgpu::Operations {
                    load: wgpu::LoadOp::Clear(wgpu::Color {
                        r: r as f64,
                        g: g as f64,
                        b: b as f64,
                        a: a as f64,
                    }),
                    store: wgpu::StoreOp::Store,
                },
            })],
            depth_stencil_attachment: None,
            timestamp_writes: None,
            occlusion_query_set: None,
            multiview_mask: None,
        });
    }
    queue.submit(Some(encoder.finish()));
    // wgpu 30：present 挪到了 Queue 上（SurfaceTexture 不再自带 present）。

    let _ = config;
    0
}

/// 尺寸变化后重新配置 swapchain。
#[no_mangle]
pub extern "C" fn lgpu_surface_resize(surface: *mut c_void, width: u32, height: u32) -> i32 {
    if surface.is_null() || width == 0 || height == 0 {
        return E_BAD_ARG;
    }
    let _guard = lock_surface();
    let ctx = unsafe { &mut *(surface as *mut SurfaceCtx) };
    let (Some(device), Some(mut config)) = (&ctx.device, ctx.config.clone()) else {
        set_error("surface not initialised");
        return E_BAD_ARG;
    };
    config.width = width;
    config.height = height;
    ctx.surface.configure(device, &config);
    ctx.config = Some(config);
    0
}

/// 初始化 SDF 管线（surface 已 init 后调用一次）。
#[no_mangle]
pub extern "C" fn lgpu_pipeline_init(surface: *mut c_void) -> i32 {
    if surface.is_null() {
        set_error("null surface");
        return E_BAD_ARG;
    }
    let _guard = lock_surface();
    let ctx = unsafe { &mut *(surface as *mut SurfaceCtx) };
    let (Some(device), Some(config)) = (&ctx.device, ctx.config.clone()) else {
        set_error("surface not initialised");
        return E_BAD_ARG;
    };
    if ctx.pipeline.is_some() {
        return 0;
    }

    let shader = device.create_shader_module(wgpu::ShaderModuleDescriptor {
        label: Some("lgpu-sdf"),
        source: wgpu::ShaderSource::Wgsl(gpu::SHADER.into()),
    });

    let screen_buffer = device.create_buffer(&wgpu::BufferDescriptor {
        label: Some("lgpu-screen"),
        size: 48,
        usage: wgpu::BufferUsages::UNIFORM | wgpu::BufferUsages::COPY_DST,
        mapped_at_creation: false,
    });
    let bgl = device.create_bind_group_layout(&wgpu::BindGroupLayoutDescriptor {
        label: Some("lgpu-bgl"),
        entries: &[wgpu::BindGroupLayoutEntry {
            binding: 0,
            visibility: wgpu::ShaderStages::VERTEX,
            ty: wgpu::BindingType::Buffer {
                ty: wgpu::BufferBindingType::Uniform,
                has_dynamic_offset: false,
                min_binding_size: None,
            },
            count: None,
        }],
    });
    let bind_group = device.create_bind_group(&wgpu::BindGroupDescriptor {
        label: Some("lgpu-bg"),
        layout: &bgl,
        entries: &[wgpu::BindGroupEntry {
            binding: 0,
            resource: screen_buffer.as_entire_binding(),
        }],
    });
    let layout = device.create_pipeline_layout(&wgpu::PipelineLayoutDescriptor {
        label: Some("lgpu-layout"),
        bind_group_layouts: &[Some(&bgl)],
        immediate_size: 0,
    });

    let attrs = [
        wgpu::VertexAttribute {
            format: wgpu::VertexFormat::Float32x4,
            offset: 0,
            shader_location: 0,
        },
        wgpu::VertexAttribute {
            format: wgpu::VertexFormat::Float32x4,
            offset: 16,
            shader_location: 1,
        },
        wgpu::VertexAttribute {
            format: wgpu::VertexFormat::Float32x4,
            offset: 32,
            shader_location: 2,
        },
        wgpu::VertexAttribute {
            format: wgpu::VertexFormat::Float32x4,
            offset: 48,
            shader_location: 3,
        },
        wgpu::VertexAttribute {
            format: wgpu::VertexFormat::Float32x4,
            offset: 64,
            shader_location: 4,
        },
    ];
    let pipeline = device.create_render_pipeline(&wgpu::RenderPipelineDescriptor {
        label: Some("lgpu-pipeline"),
        layout: Some(&layout),
        vertex: wgpu::VertexState {
            module: &shader,
            entry_point: Some("vs"),
            compilation_options: Default::default(),
            buffers: &[Some(wgpu::VertexBufferLayout {
                array_stride: std::mem::size_of::<gpu::RectInstance>() as u64,
                step_mode: wgpu::VertexStepMode::Instance,
                attributes: &attrs,
            })],
        },
        fragment: Some(wgpu::FragmentState {
            module: &shader,
            entry_point: Some("fs"),
            compilation_options: Default::default(),
            targets: &[Some(wgpu::ColorTargetState {
                format: config.format,
                blend: Some(wgpu::BlendState::ALPHA_BLENDING),
                write_mask: wgpu::ColorWrites::ALL,
            })],
        }),
        primitive: wgpu::PrimitiveState::default(),
        depth_stencil: None,
        multisample: wgpu::MultisampleState::default(),
        multiview_mask: None,
        cache: None,
    });

    // ---- 纹理管线（group0 = screen，group1 = texture+sampler）----
    let tex_shader = device.create_shader_module(wgpu::ShaderModuleDescriptor {
        label: Some("lgpu-tex-shader"),
        source: wgpu::ShaderSource::Wgsl(gpu::TEX_SHADER.into()),
    });
    let tex_bgl = device.create_bind_group_layout(&wgpu::BindGroupLayoutDescriptor {
        label: Some("lgpu-tex-bgl"),
        entries: &[
            wgpu::BindGroupLayoutEntry {
                binding: 0,
                visibility: wgpu::ShaderStages::FRAGMENT,
                ty: wgpu::BindingType::Texture {
                    sample_type: wgpu::TextureSampleType::Float { filterable: true },
                    view_dimension: wgpu::TextureViewDimension::D2,
                    multisampled: false,
                },
                count: None,
            },
            wgpu::BindGroupLayoutEntry {
                binding: 1,
                visibility: wgpu::ShaderStages::FRAGMENT,
                ty: wgpu::BindingType::Sampler(wgpu::SamplerBindingType::Filtering),
                count: None,
            },
        ],
    });
    let tex_sampler = device.create_sampler(&wgpu::SamplerDescriptor {
        label: Some("lgpu-tex-sampler"),
        mag_filter: wgpu::FilterMode::Linear,
        min_filter: wgpu::FilterMode::Linear,
        ..Default::default()
    });
    let tex_layout = device.create_pipeline_layout(&wgpu::PipelineLayoutDescriptor {
        label: Some("lgpu-tex-layout"),
        bind_group_layouts: &[Some(&bgl), Some(&tex_bgl)],
        immediate_size: 0,
    });
    let tex_attrs = [
        wgpu::VertexAttribute { format: wgpu::VertexFormat::Float32x4, offset: 0, shader_location: 0 },
        wgpu::VertexAttribute { format: wgpu::VertexFormat::Float32x4, offset: 16, shader_location: 1 },
        wgpu::VertexAttribute { format: wgpu::VertexFormat::Float32x4, offset: 32, shader_location: 2 },
        wgpu::VertexAttribute { format: wgpu::VertexFormat::Float32x4, offset: 48, shader_location: 3 },
        wgpu::VertexAttribute { format: wgpu::VertexFormat::Float32x4, offset: 80, shader_location: 4 },
    ];
    let tex_pipeline = device.create_render_pipeline(&wgpu::RenderPipelineDescriptor {
        label: Some("lgpu-tex-pipeline"),
        layout: Some(&tex_layout),
        vertex: wgpu::VertexState {
            module: &tex_shader,
            entry_point: Some("vs"),
            compilation_options: Default::default(),
            buffers: &[Some(wgpu::VertexBufferLayout {
                array_stride: std::mem::size_of::<gpu::TexInstance>() as u64,
                step_mode: wgpu::VertexStepMode::Instance,
                attributes: &tex_attrs,
            })],
        },
        fragment: Some(wgpu::FragmentState {
            module: &tex_shader,
            entry_point: Some("fs"),
            compilation_options: Default::default(),
            targets: &[Some(wgpu::ColorTargetState {
                format: config.format,
                blend: Some(wgpu::BlendState::ALPHA_BLENDING),
                write_mask: wgpu::ColorWrites::ALL,
            })],
        }),
        primitive: wgpu::PrimitiveState::default(),
        depth_stencil: None,
        multisample: wgpu::MultisampleState::default(),
        multiview_mask: None,
        cache: None,
    });
    let tex_buffer = device.create_buffer(&wgpu::BufferDescriptor {
        label: Some("lgpu-tex-instance"),
        size: std::mem::size_of::<gpu::TexInstance>() as u64,
        usage: wgpu::BufferUsages::VERTEX | wgpu::BufferUsages::COPY_DST,
        mapped_at_creation: false,
    });
    ctx.tex_bgl = Some(tex_bgl);
    ctx.tex_sampler = Some(tex_sampler);
    ctx.tex_pipeline = Some(tex_pipeline);
    ctx.tex_buffer = Some(tex_buffer);

    ctx.screen_buffer = Some(screen_buffer);
    ctx.bind_group = Some(bind_group);
    ctx.pipeline = Some(pipeline);
    0
}

/// 开始一帧：清屏 + 清空实例列表。
#[no_mangle]
pub extern "C" fn lgpu_frame_begin(surface: *mut c_void, r: f32, g: f32, b: f32, a: f32) -> i32 {
    if surface.is_null() {
        return E_BAD_ARG;
    }
    let _guard = lock_surface();
    let ctx = unsafe { &mut *(surface as *mut SurfaceCtx) };
    let (Some(queue), Some(config)) = (&ctx.queue, ctx.config.clone()) else {
        return E_BAD_ARG;
    };
    ctx.instances.clear();
    ctx.tex_instances.clear();
    ctx.layer_marks.clear();
    ctx.clear_color = [r, g, b, a];
    let screen: [f32; 12] = [
        config.width as f32,
        config.height as f32,
        0.0,
        0.0,
        ctx.xform_scale[0],
        ctx.xform_scale[1],
        0.0,
        0.0,
        ctx.xform_offset[0],
        ctx.xform_offset[1],
        0.0,
        0.0,
    ];
    if let Some(buf) = &ctx.screen_buffer {
        queue.write_buffer(buf, 0, bytemuck::cast_slice(&screen));
    }
    0
}

/// 设置当前帧的全局变换（p' = p * scale + offset）。传 (1,1,0,0) 复位。
#[no_mangle]
pub extern "C" fn lgpu_set_transform(surface: *mut c_void, sx: f32, sy: f32, ox: f32, oy: f32) -> i32 {
    if surface.is_null() {
        return E_BAD_ARG;
    }
    let _guard = lock_surface();
    let ctx = unsafe { &mut *(surface as *mut SurfaceCtx) };
    ctx.xform_scale = [sx, sy];
    ctx.xform_offset = [ox, oy];
    0
}

/// 设置当前裁剪矩形（像素）。w 或 h <= 0 表示不裁剪。
#[no_mangle]
pub extern "C" fn lgpu_set_clip(surface: *mut c_void, x: f32, y: f32, w: f32, h: f32) -> i32 {
    if surface.is_null() {
        return E_BAD_ARG;
    }
    let _guard = lock_surface();
    let ctx = unsafe { &mut *(surface as *mut SurfaceCtx) };
    ctx.clip = [x, y, w, h];
    0
}

/// 推一个矩形（radius>0 为圆角，stroke>0 为描边）。
#[no_mangle]
#[allow(clippy::too_many_arguments)]
pub extern "C" fn lgpu_draw_rect(
    surface: *mut c_void,
    x: f32,
    y: f32,
    w: f32,
    h: f32,
    radius: f32,
    stroke: f32,
    r: f32,
    g: f32,
    b: f32,
    a: f32,
) -> i32 {
    if surface.is_null() || w <= 0.0 || h <= 0.0 {
        return E_BAD_ARG;
    }
    let _guard = lock_surface();
    let ctx = unsafe { &mut *(surface as *mut SurfaceCtx) };
    ctx.instances.push(gpu::RectInstance {
        rect: [x, y, w, h],
        color: [r, g, b, a],
        params: [radius, stroke, 0.0, 0.0],
        clip: ctx.clip,
        color2: [r, g, b, a],
    });
    0
}

/// 画一条线段（用旋转矩形实现）：端点为线段两端，宽度为 width。
#[no_mangle]
#[allow(clippy::too_many_arguments)]
pub extern "C" fn lgpu_draw_line(
    surface: *mut c_void,
    x1: f32, y1: f32, x2: f32, y2: f32, width: f32,
    r: f32, g: f32, b: f32, a: f32,
) -> i32 {
    if surface.is_null() || width <= 0.0 {
        return E_BAD_ARG;
    }
    let _guard = lock_surface();
    let ctx = unsafe { &mut *(surface as *mut SurfaceCtx) };
    let dx = x2 - x1;
    let dy = y2 - y1;
    let len = (dx * dx + dy * dy).sqrt();
    if len <= f32::EPSILON {
        return 0;
    }
    let angle = dy.atan2(dx);
    let cx = (x1 + x2) * 0.5;
    let cy = (y1 + y2) * 0.5;
    ctx.instances.push(gpu::RectInstance {
        rect: [cx - len * 0.5, cy - width * 0.5, len, width],
        color: [r, g, b, a],
        params: [0.0, 0.0, 0.0, angle],
        clip: ctx.clip,
        color2: [r, g, b, a],
    });
    0
}

/// 推一个渐变矩形。mode: 0 纯色(=c1), 1 横向(c1→c2), 2 纵向(c1→c2)。
#[no_mangle]
#[allow(clippy::too_many_arguments)]
pub extern "C" fn lgpu_draw_rect_gradient(
    surface: *mut c_void,
    x: f32, y: f32, w: f32, h: f32,
    radius: f32, stroke: f32, mode: f32,
    r1: f32, g1: f32, b1: f32, a1: f32,
    r2: f32, g2: f32, b2: f32, a2: f32,
) -> i32 {
    if surface.is_null() || w <= 0.0 || h <= 0.0 {
        return E_BAD_ARG;
    }
    let _guard = lock_surface();
    let ctx = unsafe { &mut *(surface as *mut SurfaceCtx) };
    ctx.instances.push(gpu::RectInstance {
        rect: [x, y, w, h],
        color: [r1, g1, b1, a1],
        params: [radius, stroke, mode, 0.0],
        clip: ctx.clip,
        color2: [r2, g2, b2, a2],
    });
    0
}

/// 辉光环：环半径 ring_r 处 stroke 宽的实线，外侧 outer、内侧 inner 像素的二次衰减
/// 辉光（峰值 = a * glow）。单实例 SDF，替代多层同心 strokeCircle 模拟 box-shadow。
#[no_mangle]
#[allow(clippy::too_many_arguments)]
pub extern "C" fn lgpu_draw_glow_ring(
    surface: *mut c_void,
    cx: f32, cy: f32, ring_r: f32, stroke: f32, outer: f32, inner: f32, glow: f32,
    r: f32, g: f32, b: f32, a: f32,
) -> i32 {
    if surface.is_null() || ring_r <= 0.0 {
        return E_BAD_ARG;
    }
    let _guard = lock_surface();
    let ctx = unsafe { &mut *(surface as *mut SurfaceCtx) };
    let half = ring_r + outer.max(stroke) + 2.0;
    ctx.instances.push(gpu::RectInstance {
        rect: [cx - half, cy - half, half * 2.0, half * 2.0],
        color: [r, g, b, a],
        params: [ring_r, stroke, 3.0, 0.0],
 clip: ctx.clip,
        color2: [outer, inner, glow, 0.0],
    });
    0
}

/// 结束一帧：上传实例、绘制、present。
#[no_mangle]
pub extern "C" fn lgpu_frame_end(surface: *mut c_void) -> i32 {
    if surface.is_null() {
        return E_BAD_ARG;
    }
    let _guard = lock_surface();
    let ctx = unsafe { &mut *(surface as *mut SurfaceCtx) };
    let (device, queue, pipeline, bind_group, cfg) = match (
        ctx.device.clone(),
        ctx.queue.clone(),
        ctx.pipeline.clone(),
        ctx.bind_group.clone(),
        ctx.config.clone(),
    ) {
        (Some(d), Some(q), Some(p), Some(bg), Some(c)) => (d, q, p, bg, c),
        _ => {
            set_error("pipeline not initialised");
            return E_BAD_ARG;
        }
    };
    let (fw, fh) = (cfg.width, cfg.height);

    // 纹理实例缓冲：整帧一次性上传（见下方 pass 内的说明）。
    // M0：帧级计数在写入前采样（tex_instances 此时已定型）。
    STATS.rect_instances.fetch_add(ctx.instances.len() as u64, Ordering::Relaxed);
    STATS.tex_instances.fetch_add(ctx.tex_instances.len() as u64, Ordering::Relaxed);
    let tex_need = ctx.tex_instances.len();
    if tex_need > 0 {
        let tstride = std::mem::size_of::<gpu::TexInstance>();
        let need_bytes = tex_need * tstride;
        let cap_bytes = ctx.tex_capacity * tstride;
        if need_bytes > cap_bytes {
            let cap = tex_need.next_power_of_two();
            ctx.tex_buffer = Some(device.create_buffer(&wgpu::BufferDescriptor {
                label: Some("lgpu-tex-instances"),
                size: (cap * tstride) as u64,
                usage: wgpu::BufferUsages::VERTEX | wgpu::BufferUsages::COPY_DST,
                mapped_at_creation: false,
            }));
            ctx.tex_capacity = cap;
        }
        // 直接从 (TexInstance, ptr) 元组序列化 TexInstance，不再额外收集 Vec<TexInstance>。
        // bytemuck::Pod 保证 TexInstance 无 padding，逐个 cast_slice 后拼接等价于连续数组。
        if let Some(buf) = &ctx.tex_buffer {
            let mut staging: Vec<u8> = Vec::with_capacity(tex_need * tstride);
            for (inst, _) in &ctx.tex_instances {
                staging.extend_from_slice(bytemuck::bytes_of(inst));
            }
            queue.write_buffer(buf, 0, &staging);
        }
    }

    // 实例缓冲按需增长（容量翻倍，避免每帧重分配）。
    let need = ctx.instances.len();
    if need > ctx.inst_capacity {
        let cap = need.next_power_of_two();
        let size = (cap * std::mem::size_of::<gpu::RectInstance>()) as u64;
        ctx.inst_buffer = Some(device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("lgpu-instances"),
            size,
            usage: wgpu::BufferUsages::VERTEX | wgpu::BufferUsages::COPY_DST,
            mapped_at_creation: false,
        }));
        ctx.inst_capacity = cap;
    }
    if need > 0 {
        if let Some(buf) = &ctx.inst_buffer {
            queue.write_buffer(buf, 0, bytemuck::cast_slice(&ctx.instances));
        }
    }

    let frame = match ctx.surface.get_current_texture() {
        wgpu::CurrentSurfaceTexture::Success(f) | wgpu::CurrentSurfaceTexture::Suboptimal(f) => f,
        other => {
            set_error(format!("get_current_texture: {other:?}"));
            return E_NO_DEVICE;
        }
    };
    let view = frame.texture.create_view(&wgpu::TextureViewDescriptor::default());
    ensure_offscreen(ctx, &device, cfg.format);
    let Some(off_view) = ctx.offscreen.as_ref().map(|o| o.view.clone()) else {
        set_error("offscreen target missing");
        return E_NO_DEVICE;
    };
    let mut encoder = device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
        label: Some("lgpu-frame"),
    });
    {
        let mut pass = encoder.begin_render_pass(&wgpu::RenderPassDescriptor {
            label: Some("lgpu-pass"),
            color_attachments: &[Some(wgpu::RenderPassColorAttachment {
                view: &off_view,
                resolve_target: None,
                depth_slice: None,
                ops: wgpu::Operations {
                    load: wgpu::LoadOp::Clear(wgpu::Color {
                        r: ctx.clear_color[0] as f64,
                        g: ctx.clear_color[1] as f64,
                        b: ctx.clear_color[2] as f64,
                        a: ctx.clear_color[3] as f64,
                    }),
                    store: wgpu::StoreOp::Store,
                },
            })],
            depth_stencil_attachment: None,
            timestamp_writes: None,
            occlusion_query_set: None,
            multiview_mask: None,
        });
        // 绘制：走上屏同一条录制顺序路径（draw_recorded）。
        // R1：文本/图片实例按相邻 (纹理, clip) 合批 —— 之前是每张纹理一次 draw，
        // 文字页每个字形一次 draw call（真机一帧数千次）；合批后 draw 数 = run 数。
        // R2：layer_marks 断点让段与段之间严格保持录制顺序（模态/快照遮罩正确遮挡）。
        // **不要**在同一个 pass 内多次 write_buffer（写入在提交时生效，会让所有图元
        // 看到最后一次参数 —— 历史上踩过）。
        let calls = draw_recorded(
            &mut pass,
            &pipeline,
            ctx.tex_pipeline.as_ref(),
            &bind_group,
            ctx.inst_buffer.as_ref(),
            ctx.tex_buffer.as_ref(),
            &ctx.instances,
            &ctx.tex_instances,
            &ctx.layer_marks,
            fw,
            fh,
        );
        STATS.draw_calls.fetch_add(calls, Ordering::Relaxed);
    }
    {
        let mut pass = encoder.begin_render_pass(&wgpu::RenderPassDescriptor {
            label: Some("lgpu-blit-pass"),
            color_attachments: &[Some(wgpu::RenderPassColorAttachment {
                view: &view,
                resolve_target: None,
                depth_slice: None,
                ops: wgpu::Operations {
                    load: wgpu::LoadOp::Clear(wgpu::Color::BLACK),
                    store: wgpu::StoreOp::Store,
                },
            })],
            depth_stencil_attachment: None,
            timestamp_writes: None,
            occlusion_query_set: None,
            multiview_mask: None,
        });
        draw_blit(&mut pass, ctx);
    }
    queue.submit(Some(encoder.finish()));
    queue.present(frame);
    // R5.3：帧内淘汰的图集页在这里真正释放——本帧的绘制指令已经提交，
    // 之后不会再有图元引用这些纹理（延迟一帧销毁的代价是峰值多一页）。
    if !ctx.pending_destroy.is_empty() {
        let pending: Vec<*mut c_void> = ctx.pending_destroy.drain(..).collect();
        for tex in pending {
            destroy_texture_locked(tex);
        }
    }
    STATS.frames.fetch_add(1, Ordering::Relaxed);
    0
}


/// 按录制顺序绘制一帧（矩形 + 纹理），返回 draw call 数。
///
/// 管线约束：矩形和纹理是两条独立管线、各自一个实例缓冲，无法逐图元交错。折中是
/// 层断点（layer_marks，由 lgpu_layer_mark 推入）：每段内先矩形后纹理（与旧行为
/// 一致，保证普通 UI 的文字压在底色上），段与段之间严格按录制顺序。全屏快照遮罩之后
/// 打一个断点，其上的描边/图标/Toast 就不会再被快照纹理整片盖住。
#[allow(clippy::too_many_arguments)]
fn draw_recorded(
    pass: &mut wgpu::RenderPass<'_>,
    rect_pipeline: &wgpu::RenderPipeline,
    tex_pipeline: Option<&wgpu::RenderPipeline>,
    bind_group: &wgpu::BindGroup,
    rect_buf: Option<&wgpu::Buffer>,
    tex_buf: Option<&wgpu::Buffer>,
    rects: &[gpu::RectInstance],
    texs: &[(gpu::TexInstance, *mut c_void)],
    marks: &[(usize, usize)],
    width: u32,
    height: u32,
) -> u64 {
    let rstride = std::mem::size_of::<gpu::RectInstance>() as u64;
    let tstride = std::mem::size_of::<gpu::TexInstance>() as u64;
    let mut calls = 0u64;
    let (mut r0, mut t0) = (0usize, 0usize);
    let total = (rects.len(), texs.len());
    for &(mr, mt) in marks.iter().chain(std::iter::once(&total)) {
        let r1 = mr.clamp(r0, rects.len());
        let t1 = mt.clamp(t0, texs.len());
        if r1 > r0 {
            if let Some(buf) = rect_buf {
                pass.set_pipeline(rect_pipeline);
                pass.set_bind_group(0, bind_group, &[]);
                let mut i = r0;
                while i < r1 {
                    let clip = rects[i].clip;
                    let mut j = i + 1;
                    while j < r1 && rects[j].clip == clip {
                        j += 1;
                    }
                    apply_scissor(pass, clip, width, height);
                    pass.set_vertex_buffer(0, buf.slice(i as u64 * rstride..j as u64 * rstride));
                    pass.draw(0..6, 0..(j - i) as u32);
                    calls += 1;
                    i = j;
                }
            }
        }
        if t1 > t0 {
            if let (Some(tp), Some(buf)) = (tex_pipeline, tex_buf) {
                // 纹理实例合批（R1）：相邻且 (纹理指针, clip) 相同的实例合并为一次 draw。
                pass.set_pipeline(tp);
                pass.set_bind_group(0, bind_group, &[]);
                let mut i = t0;
                while i < t1 {
                    let (inst, tex_ptr) = &texs[i];
                    let clip = inst.clip;
                    let mut j = i + 1;
                    while j < t1 && texs[j].1 == *tex_ptr && texs[j].0.clip == clip {
                        j += 1;
                    }
                    let t = unsafe { &*(*tex_ptr as *const TexCtx) };
                    apply_scissor(pass, clip, width, height);
                    pass.set_bind_group(1, &t.bind_group, &[]);
                    pass.set_vertex_buffer(0, buf.slice(i as u64 * tstride..j as u64 * tstride));
                    pass.draw(0..6, 0..(j - i) as u32);
                    STATS.tex_runs.fetch_add(1, Ordering::Relaxed);
                    calls += 1;
                    i = j;
                }
            }
        }
        r0 = r1;
        t0 = t1;
    }
    calls
}

/// 层断点：此后录制的图元整体画在此前所有图元（含纹理）之上。见 draw_recorded。
#[no_mangle]
pub extern "C" fn lgpu_layer_mark(surface: *mut c_void) -> i32 {
    if surface.is_null() {
        return E_BAD_ARG;
    }
    let _guard = lock_surface();
    let ctx = unsafe { &mut *(surface as *mut SurfaceCtx) };
    let mark = (ctx.instances.len(), ctx.tex_instances.len());
    if ctx.layer_marks.last() != Some(&mark) {
        ctx.layer_marks.push(mark);
    }
    0
}

/// 丢弃本帧到目前为止录制的全部图元。全屏不透明遮罩（主题涟漪）已完全覆盖下层时
/// 调用，省掉被盖住那部分的 GPU 填充。
#[no_mangle]
pub extern "C" fn lgpu_discard_recorded(surface: *mut c_void) -> i32 {
    if surface.is_null() {
        return E_BAD_ARG;
    }
    let _guard = lock_surface();
    let ctx = unsafe { &mut *(surface as *mut SurfaceCtx) };
    ctx.instances.clear();
    ctx.tex_instances.clear();
    ctx.layer_marks.clear();
    0
}

/// GPU 快照：把本帧到目前为止录制的图元渲染进一张可采样纹理，直接返回纹理句柄。
///
/// 与 lgpu_capture_offscreen 的区别：全程不离开 GPU——不建 readback 缓冲、不
/// map/poll 等待、不写文件、不再上传。只 submit 一次就返回（不阻塞），之后的绘制在
/// 同一队列上按提交顺序执行，天然在快照完成之后采样。纹理物理像素尺寸 = surface
/// 尺寸，格式 = surface 格式（非 sRGB，与 gamma 直传链路一致）。失败返回 null。
#[no_mangle]
pub extern "C" fn lgpu_snapshot_texture(
    surface: *mut c_void,
    out_w: *mut u32,
    out_h: *mut u32,
) -> *mut c_void {
    if surface.is_null() {
        set_error("snapshot: null surface");
        return std::ptr::null_mut();
    }
    let _guard = lock_surface();
    let ctx = unsafe { &mut *(surface as *mut SurfaceCtx) };
    let (
        Some(device),
        Some(queue),
        Some(pipeline),
        Some(bind_group),
        Some(config),
        Some(sampler),
        Some(bgl),
    ) = (
        &ctx.device,
        &ctx.queue,
        &ctx.pipeline,
        &ctx.bind_group,
        ctx.config.clone(),
        &ctx.tex_sampler,
        &ctx.tex_bgl,
    )
    else {
        set_error("snapshot: pipeline not initialised");
        return std::ptr::null_mut();
    };
    let (w, h) = (config.width.max(1), config.height.max(1));
    let texture = device.create_texture(&wgpu::TextureDescriptor {
        label: Some("lgpu-snapshot"),
        size: wgpu::Extent3d {
            width: w,
            height: h,
            depth_or_array_layers: 1,
        },
        mip_level_count: 1,
        sample_count: 1,
        dimension: wgpu::TextureDimension::D2,
        format: config.format,
        usage: wgpu::TextureUsages::RENDER_ATTACHMENT | wgpu::TextureUsages::TEXTURE_BINDING,
        view_formats: &[],
    });
    let view = texture.create_view(&wgpu::TextureViewDescriptor::default());

    // 本帧实例用临时缓冲（ctx.inst_buffer/tex_buffer 要到 frame_end 才写入本帧数据）。
    let make_buf = |label: &'static str, bytes: &[u8]| -> Option<wgpu::Buffer> {
        if bytes.is_empty() {
            return None;
        }
        let buf = device.create_buffer(&wgpu::BufferDescriptor {
            label: Some(label),
            size: bytes.len() as u64,
            usage: wgpu::BufferUsages::VERTEX | wgpu::BufferUsages::COPY_DST,
            mapped_at_creation: false,
        });
        queue.write_buffer(&buf, 0, bytes);
        Some(buf)
    };
    let rect_buf = make_buf("lgpu-snapshot-rects", bytemuck::cast_slice(&ctx.instances));
    let mut tex_bytes: Vec<u8> =
        Vec::with_capacity(ctx.tex_instances.len() * std::mem::size_of::<gpu::TexInstance>());
    for (inst, _) in &ctx.tex_instances {
        tex_bytes.extend_from_slice(bytemuck::bytes_of(inst));
    }
    let tex_buf = make_buf("lgpu-snapshot-texs", &tex_bytes);

    let mut encoder = device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
        label: Some("lgpu-snapshot-enc"),
    });
    {
        let clear = ctx.clear_color;
        let mut pass = encoder.begin_render_pass(&wgpu::RenderPassDescriptor {
            label: Some("lgpu-snapshot-pass"),
            color_attachments: &[Some(wgpu::RenderPassColorAttachment {
                view: &view,
                resolve_target: None,
                depth_slice: None,
                ops: wgpu::Operations {
                    load: wgpu::LoadOp::Clear(wgpu::Color {
                        r: clear[0] as f64,
                        g: clear[1] as f64,
                        b: clear[2] as f64,
                        a: clear[3] as f64,
                    }),
                    store: wgpu::StoreOp::Store,
                },
            })],
            depth_stencil_attachment: None,
            timestamp_writes: None,
            occlusion_query_set: None,
            multiview_mask: None,
        });
        draw_recorded(
            &mut pass,
            pipeline,
            ctx.tex_pipeline.as_ref(),
            bind_group,
            rect_buf.as_ref(),
            tex_buf.as_ref(),
            &ctx.instances,
            &ctx.tex_instances,
            &ctx.layer_marks,
            w,
            h,
        );
    }
    queue.submit(Some(encoder.finish()));

    let tex_bind_group = device.create_bind_group(&wgpu::BindGroupDescriptor {
        label: Some("lgpu-snapshot-bg"),
        layout: bgl,
        entries: &[
            wgpu::BindGroupEntry {
                binding: 0,
                resource: wgpu::BindingResource::TextureView(&view),
            },
            wgpu::BindGroupEntry {
                binding: 1,
                resource: wgpu::BindingResource::Sampler(sampler),
            },
        ],
    });
    if !out_w.is_null() {
        unsafe { *out_w = w };
    }
    if !out_h.is_null() {
        unsafe { *out_h = h };
    }
    let tex = Box::into_raw(Box::new(TexCtx {
        texture,
        view,
        bind_group: tex_bind_group,
        width: w,
        height: h,
    })) as *mut c_void;
    texture_created_hook();
    tex
}

#[allow(dead_code)]
fn cap_log(home: &str, msg: &str) {
    use std::io::Write;
    let p = format!("{home}/cap_step.txt");
    if let Ok(mut f) = std::fs::OpenOptions::new().create(true).append(true).open(&p) {
        let _ = writeln!(f, "{msg}");
    }
}

/// 离屏抓帧：把**当前已录制的这一帧**（矩形 + 纹理图元）重绘到一张离屏纹理，
/// 读回原始 RGBA 写入文件。不触碰 surface/present 路径，因此不会影响正常渲染。
/// 用途：替代 SDL 的截图/模糊底图（Modal 模糊、页面转场快照）。
#[no_mangle]
pub extern "C" fn lgpu_capture_offscreen(surface: *mut c_void, path: *const u8, path_len: usize) -> i32 {
    if surface.is_null() {
        return E_BAD_ARG;
    }
    let path_s = match unsafe { std::str::from_utf8(std::slice::from_raw_parts(path, path_len)) } {
        Ok(v) => v.to_string(),
        Err(_) => {
            set_error("capture: path not utf8");
            return E_BAD_ARG;
        }
    };
    let _guard = lock_surface();
    let ctx = unsafe { &mut *(surface as *mut SurfaceCtx) };
    let (Some(device), Some(queue)) = (&ctx.device, &ctx.queue) else {
        set_error("capture: no device");
        return E_NO_DEVICE;
    };
    let Some(config) = ctx.config.clone() else {
        set_error("capture: no config");
        return E_NO_DEVICE;
    };
    let (w, h) = (config.width.max(1), config.height.max(1));

    let target = device.create_texture(&wgpu::TextureDescriptor {
        label: Some("lgpu-capture-offscreen"),
        size: wgpu::Extent3d { width: w, height: h, depth_or_array_layers: 1 },
        mip_level_count: 1,
        sample_count: 1,
        dimension: wgpu::TextureDimension::D2,
        format: SCREEN_FORMAT,
        usage: wgpu::TextureUsages::RENDER_ATTACHMENT | wgpu::TextureUsages::COPY_SRC,
        view_formats: &[],
    });
    let view = target.create_view(&wgpu::TextureViewDescriptor::default());
    let bpr = ((w * 4 + 255) / 256) * 256;
    let readback = device.create_buffer(&wgpu::BufferDescriptor {
        label: Some("lgpu-capture-readback"),
        size: (bpr as u64) * (h as u64),
        usage: wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::MAP_READ,
        mapped_at_creation: false,
    });

    // 纹理实例必须用**本帧**数据自建缓冲：ctx.tex_buffer 是上一帧 frame_end 才写入的，
    // 直接按本帧 tex_instances 去 slice 会越界 panic（R66 实测崩在这里）。
    let cap_tex_buf = if ctx.tex_instances.is_empty() {
        None
    } else {
        let insts: Vec<gpu::TexInstance> = ctx.tex_instances.iter().map(|(i, _)| *i).collect();
        let bytes: &[u8] = bytemuck::cast_slice(&insts);
        let buf = device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("lgpu-capture-texinst"),
            size: bytes.len().max(1) as u64,
            usage: wgpu::BufferUsages::VERTEX | wgpu::BufferUsages::COPY_DST,
            mapped_at_creation: false,
        });
        queue.write_buffer(&buf, 0, bytes);
        Some(buf)
    };

    let mut encoder = device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
        label: Some("lgpu-capture-enc"),
    });
    {
        let clear = ctx.clear_color;
        let mut pass = encoder.begin_render_pass(&wgpu::RenderPassDescriptor {
            label: Some("lgpu-capture-pass"),
            color_attachments: &[Some(wgpu::RenderPassColorAttachment {
                view: &view,
                resolve_target: None,
                depth_slice: None,
                ops: wgpu::Operations {
                    load: wgpu::LoadOp::Clear(wgpu::Color {
                        r: clear[0] as f64,
                        g: clear[1] as f64,
                        b: clear[2] as f64,
                        a: clear[3] as f64,
                    }),
                    store: wgpu::StoreOp::Store,
                },
            })],
            depth_stencil_attachment: None,
            timestamp_writes: None,
            occlusion_query_set: None,
            multiview_mask: None,
        });
        // 与 frame_end 同一套按层断点分段的绘制，保证抓帧内容与屏幕一致。
        if let (Some(p), Some(bg)) = (&ctx.pipeline, &ctx.bind_group) {
            let cap_rect_buf = if ctx.instances.is_empty() {
                None
            } else {
                let bytes: &[u8] = bytemuck::cast_slice(&ctx.instances);
                let buf = device.create_buffer(&wgpu::BufferDescriptor {
                    label: Some("lgpu-capture-rectinst"),
                    size: bytes.len() as u64,
                    usage: wgpu::BufferUsages::VERTEX | wgpu::BufferUsages::COPY_DST,
                    mapped_at_creation: false,
                });
                queue.write_buffer(&buf, 0, bytes);
                Some(buf)
            };
            draw_recorded(
                &mut pass,
                p,
                ctx.tex_pipeline.as_ref(),
                bg,
                cap_rect_buf.as_ref(),
                cap_tex_buf.as_ref(),
                &ctx.instances,
                &ctx.tex_instances,
                &ctx.layer_marks,
                w,
                h,
            );
        }
    }
    encoder.copy_texture_to_buffer(
        wgpu::TexelCopyTextureInfo {
            texture: &target,
            mip_level: 0,
            origin: wgpu::Origin3d::ZERO,
            aspect: wgpu::TextureAspect::All,
        },
        wgpu::TexelCopyBufferInfo {
            buffer: &readback,
            layout: wgpu::TexelCopyBufferLayout {
                offset: 0,
                bytes_per_row: Some(bpr),
                rows_per_image: Some(h),
            },
        },
        wgpu::Extent3d { width: w, height: h, depth_or_array_layers: 1 },
    );
    let sub = queue.submit(Some(encoder.finish()));
    let slice = readback.slice(..);
    if !map_and_wait(device, &slice, sub) {
        set_error("capture: map timeout");
        return E_NO_DEVICE;
    }
    let data = match slice.get_mapped_range() {
        Ok(v) => v,
        Err(_) => {
            set_error("capture: map range failed");
            return E_NO_DEVICE;
        }
    };
    let mut out: Vec<u8> = Vec::with_capacity((w * h * 4) as usize);
    for row in 0..h {
        let start = (row * bpr) as usize;
        out.extend_from_slice(&data[start..start + (w * 4) as usize]);
    }
    drop(data);
    readback.unmap();
    match std::fs::write(&path_s, &out) {
        Ok(_) => (w as i32) * 1_000_000 + (h as i32),
        Err(e) => {
            set_error(format!("capture write: {e}"));
            -1
        }
    }
}

// ---- 纹理路径（图片 / 视频帧共用）------------------------------------------

/// 一张 GPU 纹理 + 它的 bind group。句柄对 Cangjie 不透明。
pub struct TexCtx {
    texture: wgpu::Texture,
    view: wgpu::TextureView,
    bind_group: wgpu::BindGroup,
    width: u32,
    height: u32,
}

/// 创建一张 RGBA8 纹理。返回不透明句柄，失败返回 null。
#[no_mangle]
pub extern "C" fn lgpu_texture_create(
    surface: *mut c_void,
    width: u32,
    height: u32,
) -> *mut c_void {
    if surface.is_null() || width == 0 || height == 0 {
        set_error("bad argument: surface/width/height");
        return std::ptr::null_mut();
    }
    let _guard = lock_surface();
    let ctx = unsafe { &mut *(surface as *mut SurfaceCtx) };
    texture_create_locked(ctx, width, height)
}

/// 已持有 SURF_LOCK 时的纹理创建（图集新页路径使用；避免二次加锁死锁）。
fn texture_create_locked(
    ctx: &mut SurfaceCtx,
    width: u32,
    height: u32,
) -> *mut c_void {
    let (Some(device), Some(sampler), Some(bgl)) =
        (&ctx.device, &ctx.tex_sampler, &ctx.tex_bgl)
    else {
        set_error("texture pipeline not initialised (call lgpu_pipeline_init first)");
        return std::ptr::null_mut();
    };

    let texture = device.create_texture(&wgpu::TextureDescriptor {
        label: Some("lgpu-tex"),
        size: wgpu::Extent3d {
            width,
            height,
            depth_or_array_layers: 1,
        },
        mip_level_count: 1,
        sample_count: 1,
        dimension: wgpu::TextureDimension::D2,
        format: wgpu::TextureFormat::Rgba8Unorm,
        usage: wgpu::TextureUsages::TEXTURE_BINDING | wgpu::TextureUsages::COPY_DST,
        view_formats: &[],
    });
    let view = texture.create_view(&wgpu::TextureViewDescriptor::default());
    let bind_group = device.create_bind_group(&wgpu::BindGroupDescriptor {
        label: Some("lgpu-tex-bg"),
        layout: bgl,
        entries: &[
            wgpu::BindGroupEntry {
                binding: 0,
                resource: wgpu::BindingResource::TextureView(&view),
            },
            wgpu::BindGroupEntry {
                binding: 1,
                resource: wgpu::BindingResource::Sampler(sampler),
            },
        ],
    });

    let tex = Box::into_raw(Box::new(TexCtx {
        texture,
        view,
        bind_group,
        width,
        height,
    })) as *mut c_void;
    texture_created_hook();
    tex
}

/// 纹理存活/创建计数（create 成功路径统一走这里，含 PNG 直载）。
fn texture_created_hook() {
    STATS.texture_creates.fetch_add(1, Ordering::Relaxed);
    STATS.textures_alive.fetch_add(1, Ordering::Relaxed);
}

/// 上传一块 RGBA8 像素到纹理的 (x, y) 处。stride 是每行字节数。
#[no_mangle]
pub extern "C" fn lgpu_texture_upload(
    surface: *mut c_void,
    tex: *mut c_void,
    x: u32,
    y: u32,
    width: u32,
    height: u32,
    pixels: *const u8,
    stride: u32,
) -> i32 {
    if surface.is_null() || tex.is_null() || pixels.is_null() {
        set_error("bad argument: surface/tex/pixels");
        return E_BAD_ARG;
    }
    let _guard = lock_surface();
    let ctx = unsafe { &mut *(surface as *mut SurfaceCtx) };
    let t = unsafe { &*(tex as *const TexCtx) };
    let Some(queue) = &ctx.queue else {
        set_error("no queue");
        return E_BAD_ARG;
    };
    if width == 0 || height == 0 || stride < width * 4 {
        set_error("bad upload size");
        return E_BAD_ARG;
    }
    let bytes = unsafe { std::slice::from_raw_parts(pixels, (stride * height) as usize) };
    STATS.uploads.fetch_add(1, Ordering::Relaxed);
    STATS.upload_bytes.fetch_add((width * height * 4) as u64, Ordering::Relaxed);
    queue.write_texture(
        wgpu::TexelCopyTextureInfo {
            texture: &t.texture,
            mip_level: 0,
            origin: wgpu::Origin3d { x, y, z: 0 },
            aspect: wgpu::TextureAspect::All,
        },
        bytes,
        wgpu::TexelCopyBufferLayout {
            offset: 0,
            bytes_per_row: Some(stride),
            rows_per_image: Some(height),
        },
        wgpu::Extent3d {
            width,
            height,
            depth_or_array_layers: 1,
        },
    );
    0
}

/// 把一个纹理实例推入当前帧。
#[no_mangle]
#[allow(clippy::too_many_arguments)]
pub extern "C" fn lgpu_draw_texture(
    surface: *mut c_void,
    tex: *mut c_void,
    dx: f32,
    dy: f32,
    dw: f32,
    dh: f32,
    u0: f32,
    v0: f32,
    u1: f32,
    v1: f32,
    r: f32,
    g: f32,
    b: f32,
    a: f32,
) -> i32 {
    if surface.is_null() || tex.is_null() || dw <= 0.0 || dh <= 0.0 {
        return E_BAD_ARG;
    }
    let _guard = lock_surface();
    let ctx = unsafe { &mut *(surface as *mut SurfaceCtx) };
    ctx.tex_instances.push((gpu::TexInstance {
        dst: [dx, dy, dw, dh],
        uv: [u0, v0, u1, v1],
        tint: [r, g, b, a],
        clip: ctx.clip,
        color2: [r, g, b, a],
        params: [0.0, 0.0, 0.0, 0.0],
    }, tex));
    0
}

/// 绘制带圆角裁剪的纹理：radius 为圆角半径（像素），0 等价于普通绘制。
#[no_mangle]
#[allow(clippy::too_many_arguments)]
pub extern "C" fn lgpu_draw_texture_rounded(
    surface: *mut c_void,
    tex: *mut c_void,
    dx: f32,
    dy: f32,
    dw: f32,
    dh: f32,
    u0: f32,
    v0: f32,
    u1: f32,
    v1: f32,
    radius: f32,
    a: f32,
) -> i32 {
    if surface.is_null() || tex.is_null() || dw <= 0.0 || dh <= 0.0 {
        return E_BAD_ARG;
    }
    let _guard = lock_surface();
    let ctx = unsafe { &mut *(surface as *mut SurfaceCtx) };
    ctx.tex_instances.push((gpu::TexInstance {
        dst: [dx, dy, dw, dh],
        uv: [u0, v0, u1, v1],
        tint: [1.0, 1.0, 1.0, a],
        clip: ctx.clip,
        color2: [1.0, 1.0, 1.0, a],
        params: [radius, 0.0, 0.0, 0.0],
    }, tex));
    0
}

/// 释放纹理。
#[no_mangle]
pub extern "C" fn lgpu_texture_destroy(tex: *mut c_void) {
    if tex.is_null() {
        return;
    }
    destroy_texture_locked(tex);
}

// ---- 离屏渲染 + 读回自检 ---------------------------------------------------
//
// 为什么需要：截图做像素判定太脆弱（测试窗口和 UI 重叠、坐标随布局漂移）。
// 这里把同一套管线渲染到离屏纹理，copy_texture_to_buffer 读回后**在库内断言**，
// 结果是确定性的，后续任何渲染改动都能用它做回归。

#[allow(clippy::too_many_arguments)]
fn render_to_texture(
    device: &wgpu::Device,
    queue: &wgpu::Queue,
    pipeline: &wgpu::RenderPipeline,
    bind_group: &wgpu::BindGroup,
    screen_buffer: &wgpu::Buffer,
    xform_scale: [f32; 2],
    xform_offset: [f32; 2],
    width: u32,
    height: u32,
    target_format: wgpu::TextureFormat,
    instances: &[gpu::RectInstance],
) -> Option<Vec<u8>> {

    let target = device.create_texture(&wgpu::TextureDescriptor {
        label: Some("lgpu-offscreen"),
        size: wgpu::Extent3d { width, height, depth_or_array_layers: 1 },
        mip_level_count: 1,
        sample_count: 1,
        dimension: wgpu::TextureDimension::D2,
        // 必须与管线 color target 的格式一致（= surface 格式），否则整个 pass 会被丢弃
        format: target_format,
        usage: wgpu::TextureUsages::RENDER_ATTACHMENT | wgpu::TextureUsages::COPY_SRC,
        view_formats: &[],
    });
    let view = target.create_view(&wgpu::TextureViewDescriptor::default());

    let inst_buf = device.create_buffer(&wgpu::BufferDescriptor {
        label: Some("lgpu-offscreen-inst"),
        size: (instances.len().max(1) * std::mem::size_of::<gpu::RectInstance>()) as u64,
        usage: wgpu::BufferUsages::VERTEX | wgpu::BufferUsages::COPY_DST,
        mapped_at_creation: false,
    });
    let screen: [f32; 12] = [
        width as f32, height as f32, 0.0, 0.0,
        xform_scale[0], xform_scale[1], 0.0, 0.0,
        xform_offset[0], xform_offset[1], 0.0, 0.0,
    ];
    queue.write_buffer(screen_buffer, 0, bytemuck::cast_slice(&screen));
    if !instances.is_empty() {
        queue.write_buffer(&inst_buf, 0, bytemuck::cast_slice(instances));
    }

    let bytes_per_row = ((width * 4 + 255) / 256) * 256;
    let readback = device.create_buffer(&wgpu::BufferDescriptor {
        label: Some("lgpu-readback"),
        size: (bytes_per_row * height) as u64,
        usage: wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::MAP_READ,
        mapped_at_creation: false,
    });

    let mut encoder = device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
        label: Some("lgpu-offscreen"),
    });
    {
        let mut pass = encoder.begin_render_pass(&wgpu::RenderPassDescriptor {
            label: Some("lgpu-offscreen-pass"),
            color_attachments: &[Some(wgpu::RenderPassColorAttachment {
                view: &view,
                resolve_target: None,
                depth_slice: None,
                ops: wgpu::Operations {
                    load: wgpu::LoadOp::Clear(wgpu::Color { r: 0.0, g: 0.0, b: 0.0, a: 1.0 }),
                    store: wgpu::StoreOp::Store,
                },
            })],
            depth_stencil_attachment: None,
            timestamp_writes: None,
            occlusion_query_set: None,
            multiview_mask: None,
        });
        if !instances.is_empty() {
            draw_rect_batches(&mut pass, pipeline, bind_group, &inst_buf, instances, width, height);
        }
    }
    encoder.copy_texture_to_buffer(
        wgpu::TexelCopyTextureInfo {
            texture: &target,
            mip_level: 0,
            origin: wgpu::Origin3d::ZERO,
            aspect: wgpu::TextureAspect::All,
        },
        wgpu::TexelCopyBufferInfo {
            buffer: &readback,
            layout: wgpu::TexelCopyBufferLayout {
                offset: 0,
                bytes_per_row: Some(bytes_per_row),
                rows_per_image: Some(height),
            },
        },
        wgpu::Extent3d { width, height, depth_or_array_layers: 1 },
    );
    let submission = queue.submit(Some(encoder.finish()));

    let slice = readback.slice(..);
    if !map_and_wait(device, &slice, submission) {
        set_error("readback: buffer never mapped");
        return None;
    }
    let data = match slice.get_mapped_range() {
        Ok(d) => d,
        Err(e) => {
            set_error(format!("map readback failed: {e:?}"));
            return None;
        }
    };
    let mut out = Vec::with_capacity((width * height * 4) as usize);
    for row in 0..height {
        let start = (row * bytes_per_row) as usize;
        out.extend_from_slice(&data[start..start + (width * 4) as usize]);
    }
    drop(data);
    readback.unmap();
    Some(out)
}


/// 等待缓冲区映射完成。map_async 的回调不保证在第一次 poll 后触发，
/// 必须循环 poll 直到真正可读（否则真机上会偶发 "Buffer is not mapped"）。
fn map_and_wait(
    device: &wgpu::Device,
    slice: &wgpu::BufferSlice<'_>,
    submission: wgpu::SubmissionIndex,
) -> bool {
    slice.map_async(wgpu::MapMode::Read, |_| {});
    let _ = device.poll(wgpu::PollType::Wait {
        submission_index: Some(submission),
        timeout: None,
    });
    for _ in 0..32 {
        if slice.get_mapped_range().is_ok() {
            return true;
        }
        let _ = device.poll(wgpu::PollType::Wait {
            submission_index: None,
            timeout: None,
        });
    }
    false
}

/// 取像素（RGBA8）。
fn px(buf: &[u8], width: u32, x: u32, y: u32) -> [u8; 4] {
    let i = ((y * width + x) * 4) as usize;
    [buf[i], buf[i + 1], buf[i + 2], buf[i + 3]]
}

/// 离屏渲染自检：验证裁剪与变换。
/// 返回值：低 2 位 flags（bit0 裁剪语义不符，bit1 变换不符，bit2 读回失败），
/// 其余位打包三个探测像素的红色分量，便于真机定位：
///   r1 = 全量裁剪矩形内像素（应为白）
///   r2 = 半裁剪矩形内的左半像素（应为白）
///   r3 = 半裁剪矩形外的右半像素（应为黑）
#[no_mangle]
pub extern "C" fn lgpu_selftest(surface: *mut c_void) -> i32 {
    if surface.is_null() {
        return 1 << 2;
    }
    let ctx = unsafe { &*(surface as *const SurfaceCtx) };
    let w = 200u32;
    let h = 120u32;
    let fmt = ctx
        .config
        .as_ref()
        .map(|c| c.format)
        .unwrap_or(wgpu::TextureFormat::Bgra8Unorm);

    let (Some(device), Some(queue), Some(pipeline), Some(bind_group), Some(screen_buffer)) = (
        ctx.device.as_ref(),
        ctx.queue.as_ref(),
        ctx.pipeline.as_ref(),
        ctx.bind_group.as_ref(),
        ctx.screen_buffer.as_ref(),
    ) else {
        return 1 << 2;
    };

    // 单探针：一个 100x20 的白条，裁剪到左侧 60px。
    // 期望可见包围盒 = (20, 40) - (79, 59)；右半边必须不可见。
    let inst = gpu::RectInstance {
        rect: [20.0, 40.0, 100.0, 20.0],
        color: [1.0, 1.0, 1.0, 1.0],
        params: [0.0, 0.0, 0.0, 0.0],
        clip: [20.0, 40.0, 60.0, 100.0],
        color2: [1.0, 1.0, 1.0, 1.0],
    };

    // 第二个实例：横向渐变（黑→白），验证渐变与同组合批
    let inst2 = gpu::RectInstance {
        rect: [20.0, 80.0, 160.0, 20.0],
        color: [0.0, 0.0, 0.0, 1.0],
        params: [0.0, 0.0, 1.0, 0.0],   // mode=1 横向渐变
        clip: [0.0, 0.0, 0.0, 0.0],
        color2: [1.0, 1.0, 1.0, 1.0],
    };
    let Some(buf) = render_to_texture(
        device, queue, pipeline, bind_group, screen_buffer,
        [1.0, 1.0], [0.0, 0.0], w, h, fmt, &[inst, inst2],
    ) else {
        return 1 << 2;
    };

    let (mut x0, mut y0, mut x1, mut y1) = (u32::MAX, u32::MAX, 0u32, 0u32);
    for y in 0..h {
        for x in 0..w {
            if px(&buf, w, x, y)[0] > 60 {
                x0 = x0.min(x);
                y0 = y0.min(y);
                x1 = x1.max(x);
                y1 = y1.max(y);
            }
        }
    }
    if x0 == u32::MAX {
        set_error(format!("selftest: nothing rendered (fmt={fmt:?})"));
        return 1;
    }
    // 允许 2px 抗锯齿误差
    // 渐变探针：左端应接近黑、右端应接近白
    let grad_left = px(&buf, w, 24, 90)[0];
    let grad_right = px(&buf, w, 176, 90)[0];
    // 只判定裁剪条所在行段（y 40..60）的右边界；整体 bbox 含下方渐变条
    let mut bar_right = 0u32;
    for y in 40..60u32 {
        for x in 0..w {
            if px(&buf, w, x, y)[0] > 60 {
                bar_right = bar_right.max(x);
            }
        }
    }
    let ok = x0 <= 22 && bar_right >= 77 && bar_right <= 82 && grad_left < 80 && grad_right > 180;
    // 期望：x 被裁到 20..79，y 完整 40..59
    let fail = if ok { 0 } else { 1 };
    set_error(format!(
        "selftest: bbox=({x0},{y0})-({x1},{y1}) bar_right={bar_right} grad_left={grad_left} grad_right={grad_right} ok={}",
        ok
    ));
    fail
}

// ---- 文本 -----------------------------------------------------------------

/// 从文件加载字体，返回不透明句柄；失败返回 null。
#[no_mangle]
pub extern "C" fn lgpu_font_load_path(path: *const u8, path_len: usize) -> *mut c_void {
    if path.is_null() || path_len == 0 {
        set_error("null font path");
        return std::ptr::null_mut();
    }
    let path_str = String::from_utf8_lossy(unsafe { std::slice::from_raw_parts(path, path_len) }).to_string();
    let bytes = match std::fs::read(&path_str) {
        Ok(b) => b,
        Err(e) => {
            set_error(format!("read font {path_str}: {e}"));
            return std::ptr::null_mut();
        }
    };
    match text::FontHandle::load(bytes) {
        Ok(f) => Box::into_raw(Box::new(f)) as *mut c_void,
        Err(e) => {
            set_error(e);
            std::ptr::null_mut()
        }
    }
}

/// 释放字体句柄。
#[no_mangle]
pub extern "C" fn lgpu_font_destroy(font: *mut c_void) {
    if font.is_null() {
        return;
    }
    drop(unsafe { Box::from_raw(font as *mut text::FontHandle) });
}

/// 量测字符串宽度（像素）。
#[no_mangle]
pub extern "C" fn lgpu_text_measure(font: *mut c_void, utf8: *const u8, len: usize, px_size: f32) -> f32 {
    if font.is_null() || utf8.is_null() || len == 0 {
        return 0.0;
    }
    STATS.text_measures.fetch_add(1, Ordering::Relaxed);
    let f = unsafe { &*(font as *const text::FontHandle) };
    let s = String::from_utf8_lossy(unsafe { std::slice::from_raw_parts(utf8, len) }).to_string();
    text::measure(f, &s, px_size)
}

const ATLAS_SIZE: u32 = 1024;

/// 绘制一段文本到当前帧。返回文字前进宽度（像素）。
/// 字形按需光栅化进图集（同一字形按 (字体, 字号) 缓存）。
#[no_mangle]
#[allow(clippy::too_many_arguments)]
pub extern "C" fn lgpu_text_draw(
    surface: *mut c_void,
    font: *mut c_void,
    utf8: *const u8,
    len: usize,
    x: f32,
    y: f32,
    px_size: f32,
    r: f32,
    g: f32,
    b: f32,
    a: f32,
) -> f32 {
    // 空字符串是合法调用（UI 里大量存在空标签）：直接当 no-op，不设错误。
    // 之前把 len==0 当坏参数，既污染 lgpu_last_error，又让"首个错误"变成噪声。
    if len == 0 {
        return 0.0;
    }
    if surface.is_null() || font.is_null() || utf8.is_null() || px_size <= 0.0 {
        set_error(format!(
            "bad argument: text_draw surface_null={} font_null={} utf8_null={} len={} px={:.3} x={:.1} y={:.1}",
            surface.is_null(), font.is_null(), utf8.is_null(), len, px_size, x, y
        ));
        return 0.0;
    }
    let fh = unsafe { &*(font as *const text::FontHandle) };
    let s = String::from_utf8_lossy(unsafe { std::slice::from_raw_parts(utf8, len) }).to_string();

    // 阶段 0：确保至少有一页图集。注意**不要**在持有 &mut SurfaceCtx 时再调同名 FFI——
    // 那会造出第二个 &mut（别名 UB），真机上表现为图集内容错乱/不显示。
    // R5.3：wgpu 新纹理默认零初始化，无需上传 4MB 空白缓冲（省一次全页上传）。
    let pages_empty = unsafe { &*(surface as *const SurfaceCtx) }.atlas_pages.is_empty();
    if pages_empty {
        let atlas_tex = lgpu_texture_create(surface, ATLAS_SIZE, ATLAS_SIZE);
        if atlas_tex.is_null() {
            set_error("create text atlas failed");
            return 0.0;
        }
        let _guard = lock_surface();
        let ctx = unsafe { &mut *(surface as *mut SurfaceCtx) };
        ctx.atlas_pages.push((atlas_tex, text::Atlas::new(ATLAS_SIZE)));
    }

    // 阶段 1：按需光栅化 + 上传（上传期间不持有 ctx 借用）。
    // 多页查找/分配：先在现有页里找缓存槽或能放下的空位；全都放不下就新开一页。
    let size_key = (px_size * 4.0) as u32;
    let mut pen_x = x;
    // 基线用字体真实 ascent（之前硬编码 0.8*size，跟字体实际度量有偏差）
    let baseline = y + text::metrics(fh, px_size).0;
    let mut quads: Vec<(f32, f32, f32, f32, f32, f32, f32, f32, *mut c_void)> = Vec::new();

    for ch in s.chars() {
        let glyph_id = {
            use ab_glyph::Font as _;
            fh.font.glyph_id(ch).0
        };
        let key = (fh.id, glyph_id, size_key);

        // (a) 已缓存：直接用（跨页查找，页号随槽一起返回）。
        let cached: Option<(text::GlyphSlot, *mut c_void)> = {
            let ro = unsafe { &*(surface as *const SurfaceCtx) };
            let mut found = None;
            for (tex, packer) in ro.atlas_pages.iter() {
                if let Some(slot) = packer.cache.get(&key).copied() {
                    found = Some((slot, *tex));
                    break;
                }
            }
            found
        };

        let (slot, page_tex) = match cached {
            Some(v) => v,
            None => {
                let Some(rg) = text::rasterize(fh, ch, px_size) else {
                    pen_x += px_size * 0.5;
                    continue;
                };
                if rg.w == 0 || rg.h == 0 {
                    pen_x += rg.advance;
                    continue;
                }
                // (b) 逐页找空位；都满了新开一页（R5.3：不再丢字）。
                let mut alloc: Option<(*mut c_void, u32, u32)> = None;
                {
                    let _guard = lock_surface();
                    let ctx = unsafe { &mut *(surface as *mut SurfaceCtx) };
                    // 从最后一页开始尝试（新字形大概率落在活跃页）。
                    for (tex, packer) in ctx.atlas_pages.iter_mut().rev() {
                        if let Some((ax, ay)) = packer.alloc(rg.w, rg.h) {
                            alloc = Some((*tex, ax, ay));
                            break;
                        }
                    }
                    if alloc.is_none() {
                        // 所有页都放不下：先用一个**全新** packer 试分配，成功才建纹理。
                        // 关键：槽位必须来自与纹理配对的那个 packer，否则 (x,y) 会
                        // 落到别的页上 —— 表现为字形错位/串位（写这段时踩过）。
                        let mut fresh = text::Atlas::new(ATLAS_SIZE);
                        if let Some((ax, ay)) = fresh.alloc(rg.w, rg.h) {
                            // 页数到上限：淘汰最旧页（FIFO）。**不立即 free**：
                            // 本帧已录制的图元还引用它，推迟到 frame_end 之后销毁。
                            if ctx.atlas_pages.len() >= MAX_ATLAS_PAGES {
                                let (old_tex, _) = ctx.atlas_pages.remove(0);
                                ctx.pending_destroy.push(old_tex);
                                STATS.atlas_page_evict.fetch_add(1, Ordering::Relaxed);
                            }
                            let atlas_tex = texture_create_locked(ctx, ATLAS_SIZE, ATLAS_SIZE);
                            if !atlas_tex.is_null() {
                                alloc = Some((atlas_tex, ax, ay));
                                ctx.atlas_pages.push((atlas_tex, fresh));
                            }
                        }
                    }
                }
                let Some((page_tex, ax, ay)) = alloc else {
                    // 单个字形比整页还大：跳过该字符（仍前进半个字宽），不再中断整段。
                    STATS.glyph_overflow.fetch_add(1, Ordering::Relaxed);
                    pen_x += px_size * 0.5;
                    continue;
                };
                let mut rgba = vec![0u8; (rg.w * rg.h * 4) as usize];
                for i in 0..(rg.w * rg.h) as usize {
                    rgba[i * 4] = 255;
                    rgba[i * 4 + 1] = 255;
                    rgba[i * 4 + 2] = 255;
                    rgba[i * 4 + 3] = rg.coverage[i];
                }
                lgpu_texture_upload(surface, page_tex, ax, ay, rg.w, rg.h, rgba.as_ptr(), rg.w * 4);
                let slot = text::GlyphSlot {
                    x: ax,
                    y: ay,
                    w: rg.w,
                    h: rg.h,
                    bearing_x: rg.bearing_x,
                    bearing_y: rg.bearing_y,
                    advance: rg.advance,
                };
                let _guard = lock_surface();
                let ctx = unsafe { &mut *(surface as *mut SurfaceCtx) };
                // 槽位登记到刚分配的页（按纹理指针找到它）
                for (tex, packer) in ctx.atlas_pages.iter_mut() {
                    if *tex == page_tex {
                        packer.cache.insert(key, slot);
                        break;
                    }
                }
                (slot, page_tex)
            }
        };

        if slot.w > 0 && slot.h > 0 {
            let page_size = ATLAS_SIZE as f32;
            let dx = pen_x + slot.bearing_x;
            let dy = baseline + slot.bearing_y;
            quads.push((
                dx,
                dy,
                slot.w as f32,
                slot.h as f32,
                slot.x as f32 / page_size,
                slot.y as f32 / page_size,
                (slot.x + slot.w) as f32 / page_size,
                (slot.y + slot.h) as f32 / page_size,
                page_tex,
            ));
        }
        pen_x += slot.advance;
    }

    // 阶段 2：把四边形推入当前帧（quad 自带所在页的纹理指针）
    let _guard = lock_surface();
    let ctx = unsafe { &mut *(surface as *mut SurfaceCtx) };
    for (dx, dy, dw, dh, u0, v0, u1, v1, page_tex) in quads {
        ctx.tex_instances.push((
            gpu::TexInstance {
                dst: [dx, dy, dw, dh],
                uv: [u0, v0, u1, v1],
                tint: [r, g, b, a],
                clip: ctx.clip,
                color2: [r, g, b, a],
                params: [0.0, 0.0, 0.0, 0.0],
            },
            page_tex,
        ));
    }

    pen_x - x
}

/// 文本自检：用给定字体渲染 "AA" 到离屏目标，返回可见包围盒高度<<8 | 宽度高 8 位。
/// 0 = 什么都没画出来（失败）。
#[no_mangle]
pub extern "C" fn lgpu_selftest_text(surface: *mut c_void, font_path: *const u8, path_len: usize) -> i32 {
    if surface.is_null() || font_path.is_null() {
        return 0;
    }
    let font = lgpu_font_load_path(font_path, path_len);
    if font.is_null() {
        return 0;
    }
    let (w, h, fmt) = {
        let ctx = unsafe { &*(surface as *const SurfaceCtx) };
        let fmt = ctx
            .config
            .as_ref()
            .map(|c| c.format)
            .unwrap_or(wgpu::TextureFormat::Bgra8Unorm);
        (200u32, 120u32, fmt)
    };

    // 清空当前帧的实例列表（短借用）
    {
        let _guard = lock_surface();
    let ctx = unsafe { &mut *(surface as *mut SurfaceCtx) };
        ctx.instances.clear();
        ctx.tex_instances.clear();
    }

    let size = 48.0f32;
    let sample: &[u8] = b"AA";
    let advance = lgpu_text_draw(
        surface, font, sample.as_ptr(), sample.len(), 10.0, 10.0, size, 1.0, 1.0, 1.0, 1.0,
    );

    // 取渲染需要的东西（克隆句柄），随后**不再**持有 ctx 借用
    let (device, queue, tex_pipeline, bind_group, screen_buffer, tex_items, quad_count) = {
        let ctx = unsafe { &*(surface as *const SurfaceCtx) };
        match (
            ctx.device.clone(),
            ctx.queue.clone(),
            ctx.tex_pipeline.clone(),
            ctx.bind_group.clone(),
            ctx.screen_buffer.clone(),
        ) {
            (Some(d), Some(q), Some(p), Some(b), Some(sb)) => {
                let items = ctx.tex_instances.clone();
                let n = items.len();
                (d, q, p, b, sb, items, n)
            }
            _ => {
                lgpu_font_destroy(font);
                return 0;
            }
        }
    };

    // 对照探针：一张已知的纯白纹理，画在 (120,10)-(160,50)。
    // 若它可见而字形不可见，说明纹理管线正常、问题在图集内容。
    let white_items: Vec<(gpu::TexInstance, *mut c_void)> = {
        let tex = lgpu_texture_create(surface, 8, 8);
        if tex.is_null() {
            Vec::new()
        } else {
            let px8 = vec![255u8; 8 * 8 * 4];
            lgpu_texture_upload(surface, tex, 0, 0, 8, 8, px8.as_ptr(), 8 * 4);
            let mut v = tex_items.clone();
            v.push((
                gpu::TexInstance {
                    dst: [120.0, 10.0, 40.0, 40.0],
                    uv: [0.0, 0.0, 1.0, 1.0],
                    tint: [1.0, 1.0, 1.0, 1.0],
                    clip: [0.0, 0.0, 0.0, 0.0],
                    color2: [1.0, 1.0, 1.0, 1.0],
                    params: [0.0, 0.0, 0.0, 0.0],
                },
                tex,
            ));
            v
        }
    };

    let Some(buf) = render_tex_to_texture(
        &device, &queue, &tex_pipeline, &bind_group, &screen_buffer, w, h, fmt, &white_items,
    ) else {
        lgpu_font_destroy(font);
        return 0;
    };

    let (mut x0, mut y0, mut x1, mut y1) = (u32::MAX, u32::MAX, 0u32, 0u32);
    for y in 0..h {
        for x in 0..w {
            if px(&buf, w, x, y)[0] > 60 {
                x0 = x0.min(x);
                y0 = y0.min(y);
                x1 = x1.max(x);
                y1 = y1.max(y);
            }
        }
    }
    lgpu_font_destroy(font);
    if x0 == u32::MAX {
        set_error(format!(
            "selftest_text: nothing rendered (advance={advance:.1} quads={quad_count} known_white={} gpu_err={})",
            px(&buf, w, 140, 30)[0],
            gpu_error()
        ));
        return 0;
    }
    let bw = (x1 - x0 + 1).min(255);
    let bh = (y1 - y0 + 1).min(255);
    set_error(format!(
        "selftest_text: bbox=({x0},{y0})-({x1},{y1}) size=48 advance={advance:.1} glyph_h={bh} quads={quad_count} known_white={} gpu_err={}",
        px(&buf, w, 140, 30)[0],
        gpu_error()
    ));
    ((bh as i32) << 8) | bw as i32
}

/// 把纹理实例渲染到离屏目标（文本自检用）。
#[allow(clippy::too_many_arguments)]
fn render_tex_to_texture(
    device: &wgpu::Device,
    queue: &wgpu::Queue,
    pipeline: &wgpu::RenderPipeline,
    bind_group: &wgpu::BindGroup,
    screen_buffer: &wgpu::Buffer,
    width: u32,
    height: u32,
    target_format: wgpu::TextureFormat,
    items: &[(gpu::TexInstance, *mut c_void)],
) -> Option<Vec<u8>> {
    let target = device.create_texture(&wgpu::TextureDescriptor {
        label: Some("lgpu-offscreen-tex"),
        size: wgpu::Extent3d { width, height, depth_or_array_layers: 1 },
        mip_level_count: 1,
        sample_count: 1,
        dimension: wgpu::TextureDimension::D2,
        format: target_format,
        usage: wgpu::TextureUsages::RENDER_ATTACHMENT | wgpu::TextureUsages::COPY_SRC,
        view_formats: &[],
    });
    let view = target.create_view(&wgpu::TextureViewDescriptor::default());
    let screen: [f32; 12] = [
        width as f32, height as f32, 0.0, 0.0,
        1.0, 1.0, 0.0, 0.0,
        0.0, 0.0, 0.0, 0.0,
    ];
    queue.write_buffer(screen_buffer, 0, bytemuck::cast_slice(&screen));

    let inst_buf = device.create_buffer(&wgpu::BufferDescriptor {
        label: Some("lgpu-offscreen-tex-inst"),
        size: (items.len().max(1) * std::mem::size_of::<gpu::TexInstance>()) as u64,
        usage: wgpu::BufferUsages::VERTEX | wgpu::BufferUsages::COPY_DST,
        mapped_at_creation: false,
    });
    if !items.is_empty() {
        let flat: Vec<gpu::TexInstance> = items.iter().map(|(i, _)| *i).collect();
        queue.write_buffer(&inst_buf, 0, bytemuck::cast_slice(&flat));
    }

    let bytes_per_row = ((width * 4 + 255) / 256) * 256;
    let readback = device.create_buffer(&wgpu::BufferDescriptor {
        label: Some("lgpu-readback-tex"),
        size: (bytes_per_row * height) as u64,
        usage: wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::MAP_READ,
        mapped_at_creation: false,
    });

    let mut encoder = device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
        label: Some("lgpu-offscreen-tex"),
    });
    {
        let mut pass = encoder.begin_render_pass(&wgpu::RenderPassDescriptor {
            label: Some("lgpu-offscreen-tex-pass"),
            color_attachments: &[Some(wgpu::RenderPassColorAttachment {
                view: &view,
                resolve_target: None,
                depth_slice: None,
                ops: wgpu::Operations {
                    load: wgpu::LoadOp::Clear(wgpu::Color { r: 0.0, g: 0.0, b: 0.0, a: 1.0 }),
                    store: wgpu::StoreOp::Store,
                },
            })],
            depth_stencil_attachment: None,
            timestamp_writes: None,
            occlusion_query_set: None,
            multiview_mask: None,
        });
        if !items.is_empty() {
            pass.set_pipeline(pipeline);
            pass.set_bind_group(0, bind_group, &[]);
            let tstride = std::mem::size_of::<gpu::TexInstance>() as u64;
            for (i, (_inst, tex_ptr)) in items.iter().enumerate() {
                let t = unsafe { &*(*tex_ptr as *const TexCtx) };
                pass.set_bind_group(1, &t.bind_group, &[]);
                let begin = i as u64 * tstride;
                pass.set_vertex_buffer(0, inst_buf.slice(begin..begin + tstride));
                pass.draw(0..6, 0..1);
            }
        }
    }
    encoder.copy_texture_to_buffer(
        wgpu::TexelCopyTextureInfo {
            texture: &target,
            mip_level: 0,
            origin: wgpu::Origin3d::ZERO,
            aspect: wgpu::TextureAspect::All,
        },
        wgpu::TexelCopyBufferInfo {
            buffer: &readback,
            layout: wgpu::TexelCopyBufferLayout {
                offset: 0,
                bytes_per_row: Some(bytes_per_row),
                rows_per_image: Some(height),
            },
        },
        wgpu::Extent3d { width, height, depth_or_array_layers: 1 },
    );
    let submission = queue.submit(Some(encoder.finish()));
    let slice = readback.slice(..);
    if !map_and_wait(device, &slice, submission) {
        set_error("readback: buffer never mapped");
        return None;
    }
    let data = match slice.get_mapped_range() {
        Ok(d) => d,
        Err(e) => {
            set_error(format!("text readback map failed: {e:?}"));
            return None;
        }
    };
    let mut out = Vec::with_capacity((width * height * 4) as usize);
    for row in 0..height {
        let start = (row * bytes_per_row) as usize;
        out.extend_from_slice(&data[start..start + (width * 4) as usize]);
    }
    drop(data);
    readback.unmap();
    Some(out)
}

// ---- 窗口：由 surfaceId 创建原生窗口（lwindow 用）---------------------------

/// OHOS 的 NDK 接口：从 XComponent 的 surfaceId 拿到 OHNativeWindow*。
/// 返回的窗口由系统持有，调用方只借用；surface 存活期间必须保持有效。
extern "C" {
    fn OH_NativeWindow_CreateNativeWindowFromSurfaceId(
        surface_id: u64,
        window: *mut *mut c_void,
    ) -> i32;
    // 设置缓冲几何/格式：XComponent 的 surface 在 attach 之前几何量可能是 0，
    // 不设置的话 Vulkan swapchain 会建在 0x0 上、present 出去看不到东西。
    fn OH_NativeWindow_NativeWindowHandleOpt(window: *mut c_void, code: i32, ...) -> i32;
}

// OH_NativeWindow_NativeWindowHandleOpt 的命令码（native_window/external_window.h）
const NATIVE_WINDOW_SET_BUFFER_GEOMETRY: i32 = 0;
const NATIVE_WINDOW_SET_FORMAT: i32 = 3;

/// 由 surfaceId 创建 OHNativeWindow*（失败返回 null）。
/// lwindow 在**自己的线程**里用它建窗口，再把窗口交给 lgpu_surface_create，
/// 全程不跨边界传指针（真机验证过：跨线程传窗口指针会 SIGSEGV）。
#[no_mangle]
pub extern "C" fn lgpu_native_window_from_surface_id(surface_id: u64) -> *mut c_void {
    let mut window: *mut c_void = std::ptr::null_mut();
    let rc = unsafe { OH_NativeWindow_CreateNativeWindowFromSurfaceId(surface_id, &mut window) };
    if rc != 0 || window.is_null() {
        set_error(format!(
            "OH_NativeWindow_CreateNativeWindowFromSurfaceId failed: rc={rc} id={surface_id}"
        ));
        return std::ptr::null_mut();
    }
    window
}

/// 给 surfaceId 对应的 native window 显式设置缓冲几何与格式（RGBA_8888）。
#[no_mangle]
pub extern "C" fn lgpu_native_window_set_geometry(
    surface_id: u64,
    width: u32,
    height: u32,
) -> i32 {
    let window = lgpu_native_window_from_surface_id(surface_id);
    if window.is_null() {
        return -1;
    }
    let rc_geo = unsafe {
        OH_NativeWindow_NativeWindowHandleOpt(
            window,
            NATIVE_WINDOW_SET_BUFFER_GEOMETRY,
            width as i32,
            height as i32,
        )
    };
    // RGBA_8888 = 0x1 (OHOS PixelFormat); 失败不致命
    let _rc_fmt = unsafe {
        OH_NativeWindow_NativeWindowHandleOpt(window, NATIVE_WINDOW_SET_FORMAT, 0x1i32)
    };
    if rc_geo != 0 {
        set_error(format!("set buffer geometry failed: rc={rc_geo} {width}x{height}"));
    }
    rc_geo
}

/// 一步到位：surfaceId → wgpu surface 句柄。
#[no_mangle]
pub extern "C" fn lgpu_surface_create_from_id(surface_id: u64) -> *mut c_void {
    let window = lgpu_native_window_from_surface_id(surface_id);
    if window.is_null() {
        return std::ptr::null_mut();
    }
    lgpu_surface_create(window)
}

/// 字体度量：out[0]=ascent, out[1]=descent, out[2]=line_gap, out[3]=units_per_em（均按 px_size 缩放）。
/// 供 cui 的文本排版使用（行高、基线定位）。
#[no_mangle]
pub extern "C" fn lgpu_font_metrics(font: *mut c_void, px_size: f32, out: *mut f32) -> i32 {
    if font.is_null() || out.is_null() || px_size <= 0.0 {
        return E_BAD_ARG;
    }
    let fh = unsafe { &*(font as *const text::FontHandle) };
    let m = text::metrics(fh, px_size);
    unsafe {
        *out.add(0) = m.0;
        *out.add(1) = m.1;
        *out.add(2) = m.2;
        *out.add(3) = m.3;
    }
    0
}

// ---- PNG 纹理（图片路径）----------------------------------------------------

/// 直接从 PNG 字节创建纹理（解码在 Rust 侧，避免把像素跨语言搬运）。
/// out_w/out_h 可空；成功返回纹理句柄，失败 null。
#[no_mangle]
pub extern "C" fn lgpu_texture_create_from_png(
    surface: *mut c_void,
    bytes: *const u8,
    len: usize,
    out_w: *mut u32,
    out_h: *mut u32,
) -> *mut c_void {
    if surface.is_null() || bytes.is_null() || len == 0 {
        set_error("bad argument: png");
        return std::ptr::null_mut();
    }
    let data = unsafe { std::slice::from_raw_parts(bytes, len) };
    // png 0.17: Decoder::new 直接返回 Decoder（错误在 read_info/next_frame 才报）
    let mut decoder = png::Decoder::new(data);
    // 统一转成 RGBA8
    decoder.set_transformations(png::Transformations::EXPAND | png::Transformations::STRIP_16);
    let mut reader = match decoder.read_info() {
        Ok(r) => r,
        Err(e) => {
            set_error(format!("png read_info: {e}"));
            return std::ptr::null_mut();
        }
    };
    let mut buf = vec![0u8; reader.output_buffer_size()];
    let info = match reader.next_frame(&mut buf) {
        Ok(i) => i,
        Err(e) => {
            set_error(format!("png decode: {e}"));
            return std::ptr::null_mut();
        }
    };
    let (w, h) = (info.width, info.height);
    // 按实际颜色类型补齐为 RGBA
    let mut rgba = vec![0u8; (w * h * 4) as usize];
    match info.color_type {
        png::ColorType::Rgba => rgba.copy_from_slice(&buf[..(w * h * 4) as usize]),
        png::ColorType::Rgb => {
            for i in 0..(w * h) as usize {
                rgba[i * 4] = buf[i * 3];
                rgba[i * 4 + 1] = buf[i * 3 + 1];
                rgba[i * 4 + 2] = buf[i * 3 + 2];
                rgba[i * 4 + 3] = 255;
            }
        }
        png::ColorType::Grayscale => {
            for i in 0..(w * h) as usize {
                let v = buf[i];
                rgba[i * 4] = v;
                rgba[i * 4 + 1] = v;
                rgba[i * 4 + 2] = v;
                rgba[i * 4 + 3] = 255;
            }
        }
        other => {
            set_error(format!("png unsupported color type: {other:?}"));
            return std::ptr::null_mut();
        }
    }

    let tex = lgpu_texture_create(surface, w, h);
    if tex.is_null() {
        return std::ptr::null_mut();
    }
    let rc = lgpu_texture_upload(surface, tex, 0, 0, w, h, rgba.as_ptr(), w * 4);
    if rc != 0 {
        lgpu_texture_destroy(tex);
        return std::ptr::null_mut();
    }
    if !out_w.is_null() {
        unsafe { *out_w = w };
    }
    if !out_h.is_null() {
        unsafe { *out_h = h };
    }
    tex
}

// ---- 单元测试：实例合批分组（R1 回归保护）----------------------------------
#[cfg(test)]
mod tests {
    use super::*;

    fn inst(clip: [f32; 4]) -> gpu::TexInstance {
        gpu::TexInstance {
            dst: [0.0, 0.0, 1.0, 1.0],
            uv: [0.0, 0.0, 1.0, 1.0],
            tint: [1.0, 1.0, 1.0, 1.0],
            clip,
            color2: [1.0, 1.0, 1.0, 1.0],
            params: [0.0, 0.0, 0.0, 0.0],
        }
    }

    fn tex(n: u8) -> *mut c_void {
        n as usize as *mut c_void
    }

    /// run 划分：相邻且 (纹理, clip) 相同的实例必须合并，边界处必须断开。
    #[test]
    fn tex_runs_merge_adjacent_same_texture_and_clip() {
        let a = tex(1);
        let b = tex(2);
        let c0 = [0.0, 0.0, 0.0, 0.0];
        let c1 = [0.0, 0.0, 100.0, 50.0];
        let list = vec![
            (inst(c0), a),
            (inst(c0), a),
            (inst(c0), a), // run [0,3) tex a clip c0
            (inst(c0), b), // 纹理变 -> 断开
            (inst(c0), b), // run [3,5) tex b clip c0
            (inst(c1), b), // clip 变 -> 断开
            (inst(c1), b), // run [5,7) tex b clip c1
            (inst(c0), a), // run [7,8)
        ];
        let bounds = tex_run_bounds(&list);
        assert_eq!(bounds, vec![(0, 3), (3, 5), (5, 7), (7, 8)]);
    }

    #[test]
    fn tex_runs_single_texture_glyphs_collapse_to_one_draw() {
        // 一页文字：上千个字形共享同一图集与同一 clip，必须合成 1 个 run。
        let a = tex(9);
        let c0 = [0.0, 0.0, 0.0, 0.0];
        let list: Vec<(gpu::TexInstance, *mut c_void)> = (0..1000).map(|_| (inst(c0), a)).collect();
        let bounds = tex_run_bounds(&list);
        assert_eq!(bounds.len(), 1);
        assert_eq!(bounds[0], (0, 1000));
    }

    #[test]
    fn tex_runs_empty() {
        let list: Vec<(gpu::TexInstance, *mut c_void)> = Vec::new();
        assert!(tex_run_bounds(&list).is_empty());
    }

    #[test]
    fn rect_batch_count_matches_clip_groups() {
        let c0 = [0.0, 0.0, 0.0, 0.0];
        let c1 = [0.0, 0.0, 10.0, 10.0];
        let mk = |clip: [f32; 4]| gpu::RectInstance {
            rect: [0.0, 0.0, 1.0, 1.0],
            color: [1.0, 1.0, 1.0, 1.0],
            params: [0.0, 0.0, 0.0, 0.0],
            clip,
            color2: [1.0, 1.0, 1.0, 1.0],
        };
        let v = vec![mk(c0), mk(c0), mk(c1), mk(c0)];
        assert_eq!(draw_rect_batch_count(&v), 3);
        assert_eq!(draw_rect_batch_count(&[]), 0);
    }
}
