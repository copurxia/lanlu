//! L 层渲染器的原生实现（wgpu → Vulkan → VK_OHOS_surface）。
//!
//! 约束（与 webview_native / fontkit_native 一致）：
//! - 只导出 **C ABI**，句柄不透明，绝不跨语言传 GC 指针；
//! - 失败返回负错误码，错误文本用线程局部保存，`lgpu_last_error()` 取回。
//!
//! 本文件当前是 P2 的第一块：实例创建 + 适配器枚举 + surface 创建。
//! 管线/绘制在后续加入（见 docs/l-layer-plan）。

mod gpu;

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
    let n = lgpu_adapter_summary(buf.as_mut_ptr(), buf.len());
    if n < 0 { n } else { 0 }
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
    let n = lgpu_adapter_summary(buf.as_mut_ptr(), buf.len());
    let adapters = unsafe { CStr::from_ptr(buf.as_ptr()) }.to_string_lossy().to_string();
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

/// 在已有 surface 上初始化 device/queue 并按尺寸配置 swapchain。
/// 0 = 成功；负值 = 失败（原因见 `lgpu_last_error()`）。
#[no_mangle]
pub extern "C" fn lgpu_surface_init(surface: *mut c_void, width: u32, height: u32) -> i32 {
    if surface.is_null() || width == 0 || height == 0 {
        set_error("bad argument: surface/width/height");
        return E_BAD_ARG;
    }
    // SAFETY: 句柄来自 lgpu_surface_create，调用期间保持有效。
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
    let format = caps
        .formats
        .iter()
        .copied()
        .find(|f| f.is_srgb())
        .unwrap_or_else(|| caps.formats[0]);

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
    queue.present(frame);
    let _ = config;
    0
}

/// 尺寸变化后重新配置 swapchain。
#[no_mangle]
pub extern "C" fn lgpu_surface_resize(surface: *mut c_void, width: u32, height: u32) -> i32 {
    if surface.is_null() || width == 0 || height == 0 {
        return E_BAD_ARG;
    }
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
        size: 16,
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
    let ctx = unsafe { &mut *(surface as *mut SurfaceCtx) };
    let (Some(queue), Some(config)) = (&ctx.queue, ctx.config.clone()) else {
        return E_BAD_ARG;
    };
    ctx.instances.clear();
    ctx.clear_color = [r, g, b, a];
    let screen = [config.width as f32, config.height as f32, 0.0, 0.0];
    if let Some(buf) = &ctx.screen_buffer {
        queue.write_buffer(buf, 0, bytemuck::cast_slice(&screen));
    }
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
    let ctx = unsafe { &mut *(surface as *mut SurfaceCtx) };
    ctx.instances.push(gpu::RectInstance {
        rect: [x, y, w, h],
        color: [r, g, b, a],
        params: [radius, stroke, 0.0, 0.0],
    });
    0
}

/// 结束一帧：上传实例、绘制、present。
#[no_mangle]
pub extern "C" fn lgpu_frame_end(surface: *mut c_void) -> i32 {
    if surface.is_null() {
        return E_BAD_ARG;
    }
    let ctx = unsafe { &mut *(surface as *mut SurfaceCtx) };
    let (Some(device), Some(queue), Some(pipeline), Some(bind_group)) =
        (&ctx.device, &ctx.queue, &ctx.pipeline, &ctx.bind_group)
    else {
        set_error("pipeline not initialised");
        return E_BAD_ARG;
    };

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
    let mut encoder = device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
        label: Some("lgpu-frame"),
    });
    {
        let mut pass = encoder.begin_render_pass(&wgpu::RenderPassDescriptor {
            label: Some("lgpu-pass"),
            color_attachments: &[Some(wgpu::RenderPassColorAttachment {
                view: &view,
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
        if need > 0 {
            if let Some(buf) = &ctx.inst_buffer {
                pass.set_pipeline(pipeline);
                pass.set_bind_group(0, bind_group, &[]);
                pass.set_vertex_buffer(0, buf.slice(..));
                pass.draw(0..6, 0..need as u32);
            }
        }
    }
    queue.submit(Some(encoder.finish()));
    queue.present(frame);
    0
}
