//! 真实 GPU 离屏渲染测试：验证 TEX 管线的全局变换语义。
//!
//! 背景（P6 HiDPI 文字修复）：文字 quad 现在按物理像素定位，靠 `params.y = 1`
//! 让顶点着色器**绕过**全局变换（`world = p * xform_scale + xform_offset`）；
//! 几何/纹理图元仍走变换。本测试在真实的 wgpu（Vulkan，CI/本机无 GPU 时走
//! lavapipe 软件驱动）上建同款 TEX 管线，渲染两个 quad 到 64×64 离屏纹理并读回：
//!
//!   * 普通图元（params.y = 0）：dst 逻辑坐标 (8,8,4,4) @ scale 2 → 物理 (16..24)
//!   * 文字图元（params.y = 1）：dst 物理坐标 (10,40,4,4) → 保持 (10..14, 40..44)
//!
//! 断言像素位置即证明"文字不被拉伸、图元正常缩放"这条管线语义。
//! 无 Vulkan 适配器时打印 skip 并返回（CI 无 GPU 的机器不红）。

use lgpu_native::gpu::{TexInstance, TEX_SHADER};

const W: u32 = 64;
const H: u32 = 64;
const SCALE: f32 = 2.0;

#[repr(C)]
#[derive(Copy, Clone, bytemuck::Pod, bytemuck::Zeroable)]
struct Screen {
    size: [f32; 2],
    _pad0: [f32; 2],
    xform_scale: [f32; 2],
    _pad1: [f32; 2],
    xform_offset: [f32; 2],
    _pad2: [f32; 2],
}

fn tex_instance(dst: [f32; 4], params_y: f32) -> TexInstance {
    TexInstance {
        dst,
        uv: [0.0, 0.0, 1.0, 1.0],
        tint: [1.0, 1.0, 1.0, 1.0],
        clip: [0.0, 0.0, W as f32, H as f32],
        color2: [1.0, 1.0, 1.0, 1.0],
        // params.y = 1 → 顶点着色器绕过全局变换（文字路径）
        params: [0.0, params_y, 0.0, 0.0],
    }
}

#[test]
fn tex_shader_applies_transform_only_when_not_bypassed() {
    let instance = wgpu::Instance::new(wgpu::InstanceDescriptor {
        backends: wgpu::Backends::VULKAN,
        ..wgpu::InstanceDescriptor::new_without_display_handle()
    });
    let adapter = match pollster::block_on(instance.request_adapter(&wgpu::RequestAdapterOptions::default()))
    {
        Ok(a) => a,
        Err(e) => {
            eprintln!("[skip] 无 Vulkan 适配器（{e:?}），跳过真实渲染测试");
            return;
        }
    };
    eprintln!("[info] 适配器: {:?}", adapter.get_info());
    let (device, queue) = pollster::block_on(adapter.request_device(&wgpu::DeviceDescriptor::default()))
        .expect("request_device");

    // ---- 目标纹理（离屏渲染 + 读回）----
    let target = device.create_texture(&wgpu::TextureDescriptor {
        label: Some("test-target"),
        size: wgpu::Extent3d { width: W, height: H, depth_or_array_layers: 1 },
        mip_level_count: 1,
        sample_count: 1,
        dimension: wgpu::TextureDimension::D2,
        format: wgpu::TextureFormat::Rgba8Unorm,
        usage: wgpu::TextureUsages::RENDER_ATTACHMENT | wgpu::TextureUsages::COPY_SRC,
        view_formats: &[],
    });
    let target_view = target.create_view(&wgpu::TextureViewDescriptor::default());

    // ---- 白块图集纹理（4×4，全白不透明）----
    let atlas = device.create_texture(&wgpu::TextureDescriptor {
        label: Some("test-atlas"),
        size: wgpu::Extent3d { width: 4, height: 4, depth_or_array_layers: 1 },
        mip_level_count: 1,
        sample_count: 1,
        dimension: wgpu::TextureDimension::D2,
        format: wgpu::TextureFormat::Rgba8UnormSrgb,
        usage: wgpu::TextureUsages::TEXTURE_BINDING | wgpu::TextureUsages::COPY_DST,
        view_formats: &[],
    });
    queue.write_texture(
        wgpu::TexelCopyTextureInfo {
            texture: &atlas,
            mip_level: 0,
            origin: wgpu::Origin3d::ZERO,
            aspect: wgpu::TextureAspect::All,
        },
        &[255u8; 4 * 4 * 4],
        wgpu::TexelCopyBufferLayout { offset: 0, bytes_per_row: Some(4 * 4), rows_per_image: Some(4) },
        wgpu::Extent3d { width: 4, height: 4, depth_or_array_layers: 1 },
    );

    // ---- Screen uniform（与 gpu.rs 的 TEX_SHADER 布局逐字段一致）----
    let screen_buffer = device.create_buffer(&wgpu::BufferDescriptor {
        label: Some("test-screen"),
        size: 48,
        usage: wgpu::BufferUsages::UNIFORM | wgpu::BufferUsages::COPY_DST,
        mapped_at_creation: false,
    });
    let screen = Screen {
        size: [W as f32, H as f32],
        _pad0: [0.0; 2],
        xform_scale: [SCALE, SCALE],
        _pad1: [0.0; 2],
        xform_offset: [0.0, 0.0],
        _pad2: [0.0; 2],
    };
    queue.write_buffer(&screen_buffer, 0, bytemuck::cast_slice(&[screen]));

    // ---- 管线（逐字段复刻 lib.rs 的 tex 管线）----
    let shader = device.create_shader_module(wgpu::ShaderModuleDescriptor {
        label: Some("test-tex-shader"),
        source: wgpu::ShaderSource::Wgsl(TEX_SHADER.into()),
    });
    let screen_bgl = device.create_bind_group_layout(&wgpu::BindGroupLayoutDescriptor {
        label: Some("test-screen-bgl"),
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
    let screen_bg = device.create_bind_group(&wgpu::BindGroupDescriptor {
        label: Some("test-screen-bg"),
        layout: &screen_bgl,
        entries: &[wgpu::BindGroupEntry { binding: 0, resource: screen_buffer.as_entire_binding() }],
    });
    let tex_bgl = device.create_bind_group_layout(&wgpu::BindGroupLayoutDescriptor {
        label: Some("test-tex-bgl"),
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
    let sampler = device.create_sampler(&wgpu::SamplerDescriptor {
        mag_filter: wgpu::FilterMode::Linear,
        min_filter: wgpu::FilterMode::Linear,
        ..Default::default()
    });
    let atlas_view = atlas.create_view(&wgpu::TextureViewDescriptor::default());
    let tex_bg = device.create_bind_group(&wgpu::BindGroupDescriptor {
        label: Some("test-tex-bg"),
        layout: &tex_bgl,
        entries: &[
            wgpu::BindGroupEntry { binding: 0, resource: wgpu::BindingResource::TextureView(&atlas_view) },
            wgpu::BindGroupEntry { binding: 1, resource: wgpu::BindingResource::Sampler(&sampler) },
        ],
    });
    let layout = device.create_pipeline_layout(&wgpu::PipelineLayoutDescriptor {
        label: Some("test-layout"),
        bind_group_layouts: &[Some(&screen_bgl), Some(&tex_bgl)],
        immediate_size: 0,
    });
    let attrs = [
        wgpu::VertexAttribute { format: wgpu::VertexFormat::Float32x4, offset: 0, shader_location: 0 },
        wgpu::VertexAttribute { format: wgpu::VertexFormat::Float32x4, offset: 16, shader_location: 1 },
        wgpu::VertexAttribute { format: wgpu::VertexFormat::Float32x4, offset: 32, shader_location: 2 },
        wgpu::VertexAttribute { format: wgpu::VertexFormat::Float32x4, offset: 48, shader_location: 3 },
        wgpu::VertexAttribute { format: wgpu::VertexFormat::Float32x4, offset: 80, shader_location: 4 },
    ];
    let pipeline = device.create_render_pipeline(&wgpu::RenderPipelineDescriptor {
        label: Some("test-tex-pipeline"),
        layout: Some(&layout),
        vertex: wgpu::VertexState {
            module: &shader,
            entry_point: Some("vs"),
            compilation_options: Default::default(),
            buffers: &[Some(wgpu::VertexBufferLayout {
                array_stride: std::mem::size_of::<TexInstance>() as u64,
                step_mode: wgpu::VertexStepMode::Instance,
                attributes: &attrs,
            })],
        },
        fragment: Some(wgpu::FragmentState {
            module: &shader,
            entry_point: Some("fs"),
            compilation_options: Default::default(),
            targets: &[Some(wgpu::ColorTargetState {
                format: wgpu::TextureFormat::Rgba8Unorm,
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

    // ---- 两个实例：A 普通（走变换）、B 文字（旁路）----
    let instances = [
        tex_instance([8.0, 8.0, 4.0, 4.0], 0.0),
        tex_instance([10.0, 40.0, 4.0, 4.0], 1.0),
    ];
    let vb = device.create_buffer(&wgpu::BufferDescriptor {
        label: Some("test-vb"),
        size: (std::mem::size_of::<TexInstance>() * instances.len()) as u64,
        usage: wgpu::BufferUsages::VERTEX | wgpu::BufferUsages::COPY_DST,
        mapped_at_creation: false,
    });
    queue.write_buffer(&vb, 0, bytemuck::cast_slice(&instances));

    let mut encoder = device.create_command_encoder(&wgpu::CommandEncoderDescriptor { label: Some("test-enc") });
    {
        let mut pass = encoder.begin_render_pass(&wgpu::RenderPassDescriptor {
            label: Some("test-pass"),
            color_attachments: &[Some(wgpu::RenderPassColorAttachment {
                view: &target_view,
                depth_slice: None,
                resolve_target: None,
                ops: wgpu::Operations {
                    load: wgpu::LoadOp::Clear(wgpu::Color::TRANSPARENT),
                    store: wgpu::StoreOp::Store,
                },
            })],
            depth_stencil_attachment: None,
            timestamp_writes: None,
            occlusion_query_set: None,
            multiview_mask: None,
        });
        pass.set_pipeline(&pipeline);
        pass.set_bind_group(0, &screen_bg, &[]);
        pass.set_bind_group(1, &tex_bg, &[]);
        pass.set_vertex_buffer(0, vb.slice(..));
        pass.draw(0..6, 0..instances.len() as u32);
    }

    // ---- 读回（64×4 = 256 字节/行，天然 256 对齐）----
    let readback = device.create_buffer(&wgpu::BufferDescriptor {
        label: Some("test-readback"),
        size: (W * H * 4) as u64,
        usage: wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::MAP_READ,
        mapped_at_creation: false,
    });
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
                bytes_per_row: Some(W * 4),
                rows_per_image: Some(H),
            },
        },
        wgpu::Extent3d { width: W, height: H, depth_or_array_layers: 1 },
    );
    queue.submit([encoder.finish()]);

    let slice = readback.slice(..);
    let (tx, rx) = std::sync::mpsc::channel();
    slice.map_async(wgpu::MapMode::Read, move |r| {
        let _ = tx.send(r);
    });
    device.poll(wgpu::PollType::Wait { submission_index: None, timeout: None }).expect("poll");
    rx.recv().expect("map_async 回调").expect("map 成功");
    let data = slice.get_mapped_range().expect("mapped range").to_vec();
    drop(slice);
    readback.unmap();

    let px = |x: u32, y: u32| -> [u8; 4] {
        let i = ((y * W + x) * 4) as usize;
        [data[i], data[i + 1], data[i + 2], data[i + 3]]
    };
    let lit = |x: u32, y: u32| px(x, y)[0] > 200 && px(x, y)[3] > 200;

    // A 普通图元 dst=(8,8,4,4) @ scale 2 → 物理 (16..24, 16..24)
    assert!(lit(18, 18), "普通图元应被放大到 (18,18)：实际 {:?}", px(18, 18));
    assert!(lit(23, 23), "普通图元右/下边界 (23,23) 应覆盖：实际 {:?}", px(23, 23));
    assert!(!lit(10, 10), "普通图元不应出现在未缩放位置 (10,10)：实际 {:?}", px(10, 10));
    assert!(!lit(24, 24), "普通图元不应超出 dst 右/下边界 (24,24)：实际 {:?}", px(24, 24));

    // B 文字图元 dst=(10,40,4,4)，params.y=1 → 保持物理位置 (10..14, 40..44)
    assert!(lit(11, 41), "文字图元应原样落在 (11,41)：实际 {:?}", px(11, 41));
    assert!(lit(13, 43), "文字图元应覆盖 (13,43)：实际 {:?}", px(13, 43));
    assert!(!lit(22, 42), "文字图元不应被 x 变换放大到 (22,42)：实际 {:?}", px(22, 42));
    // 若被错误地按 scale 放大，y 会到 80..88（画布外）；x 会被拉到 20..28——上一断言已覆盖。

    eprintln!("[pass] TEX 管线变换语义：图元缩放 ✓ / 文字旁路 ✓（lavapipe 真实渲染 + 读回）");
}

// ─────────────────────────────────────────────────────────────────────────
// 第二个测试：SDF（RECT）管线 —— 渐变着色是详情页 scrim / 渐变底色的底层原语，
// 圆角 + 半透明是"胶囊卡片"（玻璃操作卡）的渲染基础。
// ─────────────────────────────────────────────────────────────────────────

use lgpu_native::gpu::{RectInstance, SHADER as RECT_SHADER};

#[test]
fn rect_shader_renders_gradient_rounded_and_alpha() {
    let instance = wgpu::Instance::new(wgpu::InstanceDescriptor {
        backends: wgpu::Backends::VULKAN,
        ..wgpu::InstanceDescriptor::new_without_display_handle()
    });
    let adapter = match pollster::block_on(instance.request_adapter(&wgpu::RequestAdapterOptions::default()))
    {
        Ok(a) => a,
        Err(e) => {
            eprintln!("[skip] 无 Vulkan 适配器（{e:?}），跳过真实渲染测试");
            return;
        }
    };
    let (device, queue) = pollster::block_on(adapter.request_device(&wgpu::DeviceDescriptor::default()))
        .expect("request_device");

    let target = device.create_texture(&wgpu::TextureDescriptor {
        label: Some("sdf-target"),
        size: wgpu::Extent3d { width: W, height: H, depth_or_array_layers: 1 },
        mip_level_count: 1,
        sample_count: 1,
        dimension: wgpu::TextureDimension::D2,
        format: wgpu::TextureFormat::Rgba8Unorm,
        usage: wgpu::TextureUsages::RENDER_ATTACHMENT | wgpu::TextureUsages::COPY_SRC,
        view_formats: &[],
    });
    let target_view = target.create_view(&wgpu::TextureViewDescriptor::default());

    let screen_buffer = device.create_buffer(&wgpu::BufferDescriptor {
        label: Some("sdf-screen"),
        size: 48,
        usage: wgpu::BufferUsages::UNIFORM | wgpu::BufferUsages::COPY_DST,
        mapped_at_creation: false,
    });
    let screen = Screen {
        size: [W as f32, H as f32],
        _pad0: [0.0; 2],
        xform_scale: [1.0, 1.0], // 本测试只验 SDF 着色，变换已在测试 1 覆盖
        _pad1: [0.0; 2],
        xform_offset: [0.0, 0.0],
        _pad2: [0.0; 2],
    };
    queue.write_buffer(&screen_buffer, 0, bytemuck::cast_slice(&[screen]));

    let shader = device.create_shader_module(wgpu::ShaderModuleDescriptor {
        label: Some("sdf-shader"),
        source: wgpu::ShaderSource::Wgsl(RECT_SHADER.into()),
    });
    let bgl = device.create_bind_group_layout(&wgpu::BindGroupLayoutDescriptor {
        label: Some("sdf-bgl"),
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
    let bg = device.create_bind_group(&wgpu::BindGroupDescriptor {
        label: Some("sdf-bg"),
        layout: &bgl,
        entries: &[wgpu::BindGroupEntry { binding: 0, resource: screen_buffer.as_entire_binding() }],
    });
    let layout = device.create_pipeline_layout(&wgpu::PipelineLayoutDescriptor {
        label: Some("sdf-layout"),
        bind_group_layouts: &[Some(&bgl)],
        immediate_size: 0,
    });
    let attrs = [
        wgpu::VertexAttribute { format: wgpu::VertexFormat::Float32x4, offset: 0, shader_location: 0 },
        wgpu::VertexAttribute { format: wgpu::VertexFormat::Float32x4, offset: 16, shader_location: 1 },
        wgpu::VertexAttribute { format: wgpu::VertexFormat::Float32x4, offset: 32, shader_location: 2 },
        wgpu::VertexAttribute { format: wgpu::VertexFormat::Float32x4, offset: 48, shader_location: 3 },
        wgpu::VertexAttribute { format: wgpu::VertexFormat::Float32x4, offset: 64, shader_location: 4 },
    ];
    let pipeline = device.create_render_pipeline(&wgpu::RenderPipelineDescriptor {
        label: Some("sdf-pipeline"),
        layout: Some(&layout),
        vertex: wgpu::VertexState {
            module: &shader,
            entry_point: Some("vs"),
            compilation_options: Default::default(),
            buffers: &[Some(wgpu::VertexBufferLayout {
                array_stride: std::mem::size_of::<RectInstance>() as u64,
                step_mode: wgpu::VertexStepMode::Instance,
                attributes: &attrs,
            })],
        },
        fragment: Some(wgpu::FragmentState {
            module: &shader,
            entry_point: Some("fs"),
            compilation_options: Default::default(),
            targets: &[Some(wgpu::ColorTargetState {
                format: wgpu::TextureFormat::Rgba8Unorm,
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

    let clip = [0.0f32, 0.0, W as f32, H as f32];
    let instances = [
        // ① 横向渐变（params.z=1）：红 → 蓝，rect (4,4,48,16)
        RectInstance {
            rect: [4.0, 4.0, 48.0, 16.0],
            color: [1.0, 0.0, 0.0, 1.0],
            params: [0.0, 0.0, 1.0, 0.0],
            clip,
            color2: [0.0, 0.0, 1.0, 1.0],
        },
        // ② 圆角 + 半透明白（胶囊卡底层语义）：rect (4,40,20,20) r=6 alpha=0.5
        RectInstance {
            rect: [4.0, 40.0, 20.0, 20.0],
            color: [1.0, 1.0, 1.0, 0.5],
            params: [6.0, 0.0, 0.0, 0.0],
            clip,
            color2: [1.0, 1.0, 1.0, 0.5],
        },
    ];
    let vb = device.create_buffer(&wgpu::BufferDescriptor {
        label: Some("sdf-vb"),
        size: (std::mem::size_of::<RectInstance>() * instances.len()) as u64,
        usage: wgpu::BufferUsages::VERTEX | wgpu::BufferUsages::COPY_DST,
        mapped_at_creation: false,
    });
    queue.write_buffer(&vb, 0, bytemuck::cast_slice(&instances));

    let mut encoder = device.create_command_encoder(&wgpu::CommandEncoderDescriptor { label: Some("sdf-enc") });
    {
        let mut pass = encoder.begin_render_pass(&wgpu::RenderPassDescriptor {
            label: Some("sdf-pass"),
            color_attachments: &[Some(wgpu::RenderPassColorAttachment {
                view: &target_view,
                depth_slice: None,
                resolve_target: None,
                ops: wgpu::Operations {
                    load: wgpu::LoadOp::Clear(wgpu::Color::TRANSPARENT),
                    store: wgpu::StoreOp::Store,
                },
            })],
            depth_stencil_attachment: None,
            timestamp_writes: None,
            occlusion_query_set: None,
            multiview_mask: None,
        });
        pass.set_pipeline(&pipeline);
        pass.set_bind_group(0, &bg, &[]);
        pass.set_vertex_buffer(0, vb.slice(..));
        pass.draw(0..6, 0..instances.len() as u32);
    }
    let readback = device.create_buffer(&wgpu::BufferDescriptor {
        label: Some("sdf-readback"),
        size: (W * H * 4) as u64,
        usage: wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::MAP_READ,
        mapped_at_creation: false,
    });
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
                bytes_per_row: Some(W * 4),
                rows_per_image: Some(H),
            },
        },
        wgpu::Extent3d { width: W, height: H, depth_or_array_layers: 1 },
    );
    queue.submit([encoder.finish()]);

    let slice = readback.slice(..);
    let (tx, rx) = std::sync::mpsc::channel();
    slice.map_async(wgpu::MapMode::Read, move |r| {
        let _ = tx.send(r);
    });
    device.poll(wgpu::PollType::Wait { submission_index: None, timeout: None }).expect("poll");
    rx.recv().expect("map 回调").expect("map 成功");
    let data = slice.get_mapped_range().expect("mapped range").to_vec();
    drop(slice);
    readback.unmap();

    let px = |x: u32, y: u32| -> [u8; 4] {
        let i = ((y * W + x) * 4) as usize;
        [data[i], data[i + 1], data[i + 2], data[i + 3]]
    };

    // 渐变：左端红、右端蓝、中间混合
    let left = px(6, 12);
    let right = px(50, 12);
    let mid = px(27, 12);
    assert!(left[0] > 200 && left[2] < 60, "渐变左端应 ≈ 红：实际 {:?}", left);
    assert!(right[2] > 200 && right[0] < 60, "渐变右端应 ≈ 蓝：实际 {:?}", right);
    assert!(
        mid[0] > 60 && mid[0] < 200 && mid[2] > 60 && mid[2] < 200,
        "渐变中点应红蓝混合：实际 {:?}",
        mid
    );

    // 圆角 + 半透明：中心 alpha ≈ 128；圆角的几何尖角（像素 (4,40)）应被 SDF 裁掉。
    // 注意 (5,41) 落在 AA 过渡带（实测 alpha≈41），不能当"裁掉"的判据。
    let center = px(14, 50);
    let corner = px(4, 40);
    assert!(
        center[3] > 100 && center[3] < 160,
        "半透明白中心 alpha 应 ≈128：实际 {:?}",
        center
    );
    assert!(corner[3] < 20, "圆角几何尖角应被裁掉：实际 {:?}", corner);

    eprintln!("[pass] SDF 管线：横向渐变 ✓ / 圆角 SDF ✓ / 半透明混合 ✓（真实渲染 + 读回）");
}
