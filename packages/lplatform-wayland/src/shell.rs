//! Wayland 侧窗口壳：把 LWP 的 `window.*` / `surface.*` 请求翻译成 xdg-shell 调用，
//! 把 wl_seat 输入翻译成 `lw_input.*`。
//!
//! 计划 §9.3 的实现顺序：连接 → 全局绑定 → 收到 `window.create` 建 toplevel →
//! configure/ack → surface.available 交句柄 → 输入转发。
//!
//! **注意**：当前环境没有 compositor（没有 weston/sway），所以本模块的验证只做到
//! 「编译通过 + 没有 display 时优雅退出」。真正的行为验证需要一台有 Wayland 的机器。

use std::os::fd::AsRawFd;

use std::sync::{Arc, Mutex};

use wayland_client::protocol::{
    wl_buffer, wl_compositor, wl_data_device, wl_data_device_manager, wl_data_offer,
    wl_data_source, wl_keyboard, wl_output, wl_pointer, wl_seat, wl_shm, wl_shm_pool, wl_surface,
};
use wayland_client::globals::{registry_queue_init, GlobalListContents};
use wayland_client::protocol::wl_registry;
use wayland_client::{Connection, Dispatch, QueueHandle};
use wayland_protocols::wp::text_input::zv3::client::{
    zwp_text_input_manager_v3::ZwpTextInputManagerV3, zwp_text_input_v3::ZwpTextInputV3,
};
use xkbcommon_dl as xkb;
use wayland_protocols::xdg::shell::client::{xdg_surface, xdg_toplevel, xdg_wm_base};

use crate::lwp::{Channel, LWP_EVENT, LWP_REQUEST};
use crate::protocol::{self, iface, op};

/// 壳侧能力位（与 lplatform-ohos 对齐；Wayland 侧尚未实现的部分不置位）。
pub const CAP_SERVER_SIDE_DECORATIONS: u64 = 1 << 0;
pub const CAP_CURSOR_SHAPES: u64 = 1 << 1;
pub const CAP_IME_PREEDIT: u64 = 1 << 2;
pub const CAP_SOFT_KEYBOARD: u64 = 1 << 3;
pub const CAP_FILE_DIALOG_SAVE: u64 = 1 << 4;
pub const CAP_CLIPBOARD_READ_ASYNC: u64 = 1 << 5;

pub struct Shell {
    pub connection: Connection,
    pub compositor: wl_compositor::WlCompositor,
    pub shm: wl_shm::WlShm,
    /// 主显示器（有的话）；用来取 DPI 缩放
    pub output: Option<wl_output::WlOutput>,
    /// 所有显示器（多屏；索引与 `wl_surface.enter` 的对象 id 对应）
    pub outputs: Vec<wl_output::WlOutput>,
    /// 剪贴板：data device manager（有 seat 才有 data device）
    pub data_manager: Option<wl_data_device_manager::WlDataDeviceManager>,
    /// 文本输入管理器（text-input-v3）：合成器不支持时为 None（无输入法，按键自带文本仍可用）
    pub text_input_manager: Option<ZwpTextInputManagerV3>,
    pub seat: Option<wl_seat::WlSeat>,
    pub wm_base: xdg_wm_base::XdgWmBase,
}

impl Shell {
    /// 连接合成器并绑定最小全局集。没有 display 时返回 Err（调用方优雅退出）。
    pub fn connect() -> Result<(Self, wayland_client::EventQueue<State>), String> {
        let connection = Connection::connect_to_env()
            .map_err(|e| format!("连接 Wayland 失败（WAYLAND_DISPLAY 未设置或没有合成器）: {e}"))?;
        let (globals, event_queue) = registry_queue_init::<State>(&connection)
            .map_err(|e| format!("registry 初始化失败: {e}"))?;
        let qh = event_queue.handle();
        let compositor: wl_compositor::WlCompositor = globals
            .bind(&qh, 4..=6, ())
            .map_err(|_| "合成器不支持 wl_compositor v4+".to_string())?;
        let shm: wl_shm::WlShm = globals
            .bind(&qh, 1..=1, ())
            .map_err(|_| "合成器不支持 wl_shm v1".to_string())?;
        let wm_base: xdg_wm_base::XdgWmBase = globals
            .bind(&qh, 1..=5, ())
            .map_err(|_| "合成器不支持 xdg_wm_base".to_string())?;
        let seat = globals.bind::<wl_seat::WlSeat, _, _>(&qh, 1..=7, ()).ok();
        // 显示器：取 DPI 缩放；没有就退回 1（不影响建窗）
        // 多屏：把每个 wl_output 都绑上（缩放各不相同）
        let mut outputs: Vec<wl_output::WlOutput> = Vec::new();
        for g in globals.contents().clone_list() {
            if g.interface == "wl_output" {
                let o = globals.registry().bind::<wl_output::WlOutput, _, _>(
                    g.name, g.version.min(4), &qh, ());
                outputs.push(o);
            }
        }
        let output = outputs.first().cloned();
        let data_manager = globals
            .bind::<wl_data_device_manager::WlDataDeviceManager, _, _>(&qh, 1..=3, ())
            .ok();
        let text_input_manager = globals
            .bind::<ZwpTextInputManagerV3, _, _>(&qh, 1..=1, ())
            .ok();
        Ok((
            Shell { connection, compositor, shm, seat, wm_base, output, outputs, data_manager,
                text_input_manager },
            event_queue,
        ))
    }

    /// 建一个 xdg 窗口：`wl_surface` + `xdg_surface` + `xdg_toplevel`，并 commit 触发生效。
    /// 返回三个对象；调用方负责在每个 configure 后 ack 并回 LWP 的 `window.configure`。
    pub fn create_window(
        &self,
        qh: &wayland_client::QueueHandle<State>,
        title: &str,
        app_id: &str,
    ) -> (
        wl_surface::WlSurface,
        xdg_surface::XdgSurface,
        xdg_toplevel::XdgToplevel,
    ) {
        let surface = self.compositor.create_surface(qh, ());
        let xdg_surface = self.wm_base.get_xdg_surface(&surface, qh, ());
        let toplevel = xdg_surface.get_toplevel(qh, ());
        toplevel.set_title(title.to_string());
        toplevel.set_app_id(app_id.to_string());
        // 首次 commit：合成器才会下发 configure（Wayland 的既定流程）
        surface.commit();
        (surface, xdg_surface, toplevel)
    }

    /// 把引擎的共享缓冲（fd）挂到 wl_surface 上：`wl_shm` 池 + buffer + attach + damage + commit。
    ///
    /// 约定（计划 §7.3.1）：`lw_surface.attach.buffer` 是**进程内 fd**（壳与引擎同进程），
    /// 像素格式固定 ARGB8888/xRGB8888、stride = width*4。M3W 再考虑 dmabuf。
    pub fn attach_shm(
        &self,
        qh: &wayland_client::QueueHandle<State>,
        surface: &wl_surface::WlSurface,
        fd: i32,
        width: u32,
        height: u32,
    ) -> Result<wl_buffer::WlBuffer, String> {
        use std::os::fd::{AsFd, BorrowedFd};
        if fd < 0 || width == 0 || height == 0 {
            return Err(format!("attach 参数非法 fd={fd} {width}x{height}"));
        }
        let stride = width * 4;
        let size = stride * height;
        // dup 一份：缓冲的生命周期由壳管理，引擎那边继续用原 fd
        let owned = unsafe { BorrowedFd::borrow_raw(fd) }
            .try_clone_to_owned()
            .map_err(|e| format!("dup 缓冲 fd 失败: {e}"))?;
        let pool = self.shm.create_pool(owned.as_fd(), size as i32, qh, ());
        let buffer = pool.create_buffer(
            0,
            width as i32,
            height as i32,
            stride as i32,
            wl_shm::Format::Xrgb8888,
            qh,
            (),
        );
        surface.attach(Some(&buffer), 0, 0);
        surface.damage(0, 0, width as i32, height as i32);
        surface.commit();
        Ok(buffer)
    }

    /// 把 `wl_display` fd 暴露给 LWP 的等待逻辑（后续用 poll 合并两个事件源）。
    pub fn display_fd(&self) -> i32 {
        self.connection.backend().poll_fd().as_raw_fd()
    }
}

/// 每个 xdg 对象的 Dispatch 都只需要把事件记账；M1W 阶段先只打印/空实现。
#[derive(Default)]
pub struct State {
    /// 最近一次 configure 的尺寸（合成器决定）
    pub pending: Option<(u32, u32)>,
    pub closed: bool,
    /// LWP 通道：输入事件由这里的 Dispatch 直接投递（测试可注入一个自己的通道）
    pub channel: Option<Arc<Mutex<crate::lwp::Channel>>>,
    /// 已创建的 wl_surface（`surface.attach` 要用）
    pub surface: Option<wl_surface::WlSurface>,
    /// 已创建的 xdg_toplevel（窗口状态请求要用）
    pub toplevel: Option<xdg_toplevel::XdgToplevel>,
    /// 显示器 DPI 缩放（wl_output.scale；没有 output 时保持 1）
    pub output_scale: i32,
    /// 每个 wl_output 的缩放（按对象 id）
    pub output_scales: std::collections::HashMap<u32, i32>,
    /// wl_surface 当前所在的 output 对象 id（由 enter/leave 维护）
    pub surface_output: Option<u32>,
    /// 最近一次输入事件的 serial（Wayland 要求 set_selection 带它）
    pub last_input_serial: u32,
    /// 剪贴板：data device（有 seat 才建）
    pub data_device: Option<wl_data_device::WlDataDevice>,
    /// 我们自己拥有的选区数据源（引擎 clipboard.set 时创建）
    pub data_source: Option<wl_data_source::WlDataSource>,
    /// 当前选中的 offer（引擎 clipboard.get 时从它取数据）
    pub selection_offer: Option<wl_data_offer::WlDataOffer>,
    /// `data_offer` 事件交来的 offer（必须持有，否则代理被释放后会触发协议错误）
    pub offered: Option<wl_data_offer::WlDataOffer>,
    /// 选中 offer 支持的 mime 列表（按到达顺序）
    pub offer_mimes: Vec<String>,
    /// 待写出的文本（data_source.send 回调里用）
    pub pending_source_text: Option<String>,
    /// 待回给引擎的 get serial（异步读回后随 clipboard.text 一起发）
    pub pending_get_serial: Option<u32>,
    /// 拖放：当前 offer 与坐标
    pub dnd_offer: Option<wl_data_offer::WlDataOffer>,
    pub dnd_x: u32,
    pub dnd_y: u32,
    /// 拖放落下后正在读取 uris 的流
    pub dnd_read: Option<std::os::unix::net::UnixStream>,
    /// 正在从选区读数据的流（非阻塞；读完发 clipboard.text）
    pub pending_read: Option<(std::os::unix::net::UnixStream, String)>, // (流, mime)
    /// 待 ack 的 xdg_surface.configure serial（要等 toplevel 尺寸到齐一起处理）
    pub pending_configure_serial: Option<u32>,
    /// 已创建的 xdg_surface（ack_configure 要用）
    pub xdg_surface: Option<xdg_surface::XdgSurface>,
    /// 文本输入：管理器（registry 绑定时拿到）与会话（引擎 enable 时创建）
    pub text_input_manager: Option<ZwpTextInputManagerV3>,
    pub text_input: Option<ZwpTextInputV3>,
    /// wl_seat（text-input-v3 的 get_text_input 需要它；surface 由 enter 事件给出）
    pub seat: Option<wl_seat::WlSeat>,
    /// 引擎请求的输入类型（lw_text_input.enable 的 input_type；1 = 数字）
    pub pending_input_type: u32,
    /// 引擎是否要求"输入框聚焦"（v3 的 enable 要等 enter 事件之后才生效）
    pub text_input_wanted: bool,
    /// xkb 键盘布局：物理键 -> 文本（wl_keyboard.keymap 事件建立）
    pub xkb_ctx: Option<*mut xkb::xkb_context>,
    pub xkb_keymap: Option<*mut xkb::xkb_keymap>,
    pub xkb_state: Option<*mut xkb::xkb_state>,
    pub mods_depressed: u32,
    pub mods_latched: u32,
    pub mods_locked: u32,
    /// 已 attach 的缓冲（按 fd 缓存，复用 pool/buffer，避免每帧新建导致泄漏）
    pub shm_buffers: std::collections::HashMap<i32, (wl_buffer::WlBuffer, u32, u32)>,
}

impl State {
    /// 提交一帧：**按 fd 复用** pool/buffer，只在尺寸变化时重建。
    /// 每帧新建 pool 会累积 GPU/共享内存资源（第 66 轮遗留问题）。
    pub fn attach_shm(
        &mut self,
        shell: &Shell,
        qh: &wayland_client::QueueHandle<State>,
        fd: i32,
        width: u32,
        height: u32,
    ) -> Result<bool, String> {
        let surface = self.surface.clone().ok_or_else(|| "还没有 surface".to_string())?;
        if let Some((buf, bw, bh)) = self.shm_buffers.get(&fd) {
            if *bw == width && *bh == height {
                surface.attach(Some(buf), 0, 0);
                surface.damage(0, 0, width as i32, height as i32);
                surface.commit();
                return Ok(true); // 复用
            }
        }
        let buf = shell.attach_shm(qh, &surface, fd, width, height)?;
        self.shm_buffers.insert(fd, (buf, width, height));
        Ok(false)
    }

    /// 建一个带通道的 State（生产路径与测试都用这个）。
    pub fn with_channel(ch: crate::lwp::Channel) -> Self {
        State {
            pending: None,
            closed: false,
            channel: Some(Arc::new(Mutex::new(ch))),
            surface: None,
            toplevel: None,
            output_scale: 1,
            output_scales: std::collections::HashMap::new(),
            surface_output: None,
            last_input_serial: 0,
            data_device: None,
            data_source: None,
            selection_offer: None,
            offered: None,
            offer_mimes: Vec::new(),
            pending_source_text: None,
            pending_get_serial: None,
            pending_read: None,
            dnd_offer: None,
            dnd_x: 0,
            dnd_y: 0,
            dnd_read: None,
            pending_configure_serial: None,
            xdg_surface: None,
            shm_buffers: std::collections::HashMap::new(),
            text_input_manager: None,
            text_input: None,
            seat: None,
            pending_input_type: 0,
            text_input_wanted: false,
            xkb_ctx: None,
            xkb_keymap: None,
            xkb_state: None,
            mods_depressed: 0,
            mods_latched: 0,
            mods_locked: 0,
        }
    }

    /// 从 offer 的 mime 列表里挑一个我们认识的（优先 UTF-8 文本）。
    pub fn pick_mime(&self) -> Option<&str> {
        const PREF: [&str; 5] = [
            "text/plain;charset=utf-8",
            "text/plain;charset=UTF-8",
            "UTF8_STRING",
            "text/plain",
            "STRING",
        ];
        for want in PREF {
            if let Some(found) = self.offer_mimes.iter().find(|m| m.eq_ignore_ascii_case(want)) {
                return Some(found.as_str());
            }
        }
        None
    }

    /// 向选区发起一次读取：用 UnixStream pair 当管道（支持非阻塞读）。
    /// 写完的 fd 交给合成器/其他客户端，读端留在壳里轮询。
    pub fn start_clipboard_read(&mut self, mime: &str) -> Result<(), String> {
        let offer = self.selection_offer.clone().ok_or_else(|| "没有选区".to_string())?;
        let (mut ours, theirs) = std::os::unix::net::UnixStream::pair()
            .map_err(|e| format!("建管道失败: {e}"))?;
        ours.set_nonblocking(true).map_err(|e| format!("设置非阻塞失败: {e}"))?;
        use std::os::fd::{AsFd, OwnedFd};
        // 传出去的是「他们写」的一端；UnixStream -> OwnedFd 直接转
        let fd: OwnedFd = theirs.into();
        offer.receive(mime.to_string(), fd.as_fd());
        self.pending_read = Some((ours, mime.to_string()));
        Ok(())
    }

    /// 轮询待读取的剪贴板数据；读完就发 `clipboard.text`，返回是否已完成一次。
    pub fn poll_clipboard_read(&mut self) -> bool {
        use std::io::Read;
        let Some((stream, mime)) = self.pending_read.as_mut() else {
            return false;
        };
        let mut buf = Vec::new();
        let mut chunk = [0u8; 4096];
        loop {
            match stream.read(&mut chunk) {
                Ok(0) => break,                       // EOF：对方写完关了
                Ok(n) => buf.extend_from_slice(&chunk[..n]),
                Err(e) if e.kind() == std::io::ErrorKind::WouldBlock => {
                    // 还没写完：把这轮读到的先攒着，下轮继续
                    if buf.is_empty() {
                        return false;
                    }
                    break;
                }
                Err(_) => break,
            }
        }
        let mime = mime.clone();
        self.pending_read = None;
        let text = String::from_utf8_lossy(&buf).into_owned();
        if let (Some(serial), Some(ch)) = (self.pending_get_serial, &self.channel) {
            if let Ok(c) = ch.lock() {
                let _ = c.send(LWP_REQUEST, iface::CLIPBOARD, op::CLIPBOARD_TEXT, 0,
                    &protocol::clipboard_text(serial, &mime, &text));
            }
            self.pending_get_serial = None;
        }
        true
    }

    /// 轮询拖放读取；读完后发 `drop` 事件（uris 已把 file:// 转成本地路径）。
    pub fn poll_dnd_read(&mut self) -> bool {
        use std::io::Read;
        let Some(stream) = self.dnd_read.as_mut() else { return false; };
        let mut buf = Vec::new();
        let mut chunk = [0u8; 4096];
        loop {
            match stream.read(&mut chunk) {
                Ok(0) => break,
                Ok(n) => buf.extend_from_slice(&chunk[..n]),
                Err(e) if e.kind() == std::io::ErrorKind::WouldBlock => {
                    if buf.is_empty() { return false; }
                    break;
                }
                Err(_) => break,
            }
        }
        self.dnd_read = None;
        let raw = String::from_utf8_lossy(&buf).into_owned();
        let mut paths: Vec<String> = Vec::new();
        for line in raw.lines() {
            let line = line.trim();
            if line.is_empty() || line.starts_with('#') { continue; }
            paths.push(uri_to_path(line));
        }
        let uris = paths.join("\n");
        let (x, y) = (self.dnd_x, self.dnd_y);
        self.dnd_offer = None;
        self.send_request_event(iface::WINDOW, op::WINDOW_DROP,
            &protocol::drop_event(x, y, &uris));
        true
    }

    /// configure 齐了（serial + 尺寸）就通知引擎并 ack。
    /// 通知内容：`lw_surface.changed(width, height)` —— 引擎据此重配 swapchain。
    pub fn flush_configure(&mut self) {
        let (Some(serial), Some((w, h))) = (self.pending_configure_serial, self.pending) else {
            return;
        };
        if let Some(ch) = &self.channel {
            if let Ok(c) = ch.lock() {
                let _ = c.send(LWP_REQUEST, iface::SURFACE, op::SURFACE_CHANGED, 0,
                    &protocol::surface_changed(w, h));
            }
        }
        // DPI：告诉合成器这块缓冲按 scale 倍逻辑像素渲染
        if let Some(surf) = &self.surface {
            surf.set_buffer_scale(self.output_scale);
        }
        if let Some(xdg) = &self.xdg_surface {
            xdg.ack_configure(serial);
        }
        self.pending_configure_serial = None;
    }

    /// 壳 -> 引擎的界面事件（窗口拖放等）。
    fn send_request_event(&self, iface_id: u16, opcode: u16, body: &[u8]) {
        if let Some(ch) = &self.channel {
            if let Ok(c) = ch.lock() {
                let _ = c.send(LWP_REQUEST, iface_id, opcode, 0, body);
            }
        }
    }

    fn send_input(&self, opcode: u16, body: &[u8]) {
        if std::env::var("LANLU_LWP_DEBUG").is_ok() {
            eprintln!("[shell] send_input op={opcode} len={}", body.len());
        }
        if let Some(ch) = &self.channel {
            if let Ok(c) = ch.lock() {
                let _ = c.send(LWP_EVENT, iface::INPUT, opcode, 0, body);
            }
        }
    }
}

impl Dispatch<wl_pointer::WlPointer, ()> for State {
    fn event(
        state: &mut Self,
        _: &wl_pointer::WlPointer,
        event: <wl_pointer::WlPointer as wayland_client::Proxy>::Event,
        _: &(),
        _: &Connection,
        _: &QueueHandle<Self>,
    ) {
        use wl_pointer::Event as E;
        match event {
            E::Motion { surface_x, surface_y, .. } => {
                state.send_input(op::INPUT_POINTER_MOTION, &protocol::pointer_motion(
                    surface_x as f32, surface_y as f32));
            }
            E::Button { button, state: bs, serial, .. } => {
                state.last_input_serial = serial;
                // Wayland 的 button 是 evdev 编码（BTN_LEFT=0x110）；LWP 用 0/1/2
                let b = match button {
                    0x110 => 0u8,
                    0x111 => 1,
                    0x112 => 2,
                    _ => 0,
                };
                let down = matches!(bs, wayland_client::WEnum::Value(wl_pointer::ButtonState::Pressed));
                state.send_input(op::INPUT_POINTER_BUTTON,
                    &protocol::pointer_button(0.0, 0.0, b, down));
            }
            E::Axis { axis, value, .. } => {
                // Wayland 的 axis 是「一次一个方向」：VerticalScroll / HorizontalScroll
                let (dx, dy) = match axis {
                    wayland_client::WEnum::Value(wl_pointer::Axis::HorizontalScroll) => {
                        (value as f32, 0.0f32)
                    }
                    _ => (0.0f32, value as f32),
                };
                state.send_input(op::INPUT_POINTER_AXIS, &protocol::pointer_axis(dx, dy));
            }
            _ => {}
        }
    }
}

/// text-input-v3 的内容提示/用途（引擎只区分文本与数字两类）
fn wayland_client_hint_none() -> wayland_protocols::wp::text_input::zv3::client::zwp_text_input_v3::ContentHint {
    wayland_protocols::wp::text_input::zv3::client::zwp_text_input_v3::ContentHint::None
}
fn wayland_client_purpose_normal() -> wayland_protocols::wp::text_input::zv3::client::zwp_text_input_v3::ContentPurpose {
    wayland_protocols::wp::text_input::zv3::client::zwp_text_input_v3::ContentPurpose::Normal
}
fn wayland_client_purpose_number() -> wayland_protocols::wp::text_input::zv3::client::zwp_text_input_v3::ContentPurpose {
    wayland_protocols::wp::text_input::zv3::client::zwp_text_input_v3::ContentPurpose::Number
}

/// v3 的 commit_string 编码（与 text_input.commit_string 同格式）
fn wayland_protocols_preedit_commit(text: &str) -> Vec<u8> {
    protocol::commit_string(text)
}

/// 没有 libxkbcommon 时的 US 布局回落表（evdev -> 字符）。
fn us_layout_text(evdev: u32, shift: bool, caps: bool) -> String {
    let (lower, upper): (&str, &str) = match evdev {
        2..=11 => {
            const ROW: [&str; 10] = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"];
            const SHIFTED: [&str; 10] = ["!", "@", "#", "$", "%", "^", "&", "*", "(", ")"];
            let i = ((evdev - 2 + 9) % 10) as usize;
            return if shift { SHIFTED[i].to_string() } else { ROW[i].to_string() };
        }
        16..=25 => ("qwertyuiop", "QWERTYUIOP"),
        30..=38 => ("asdfghjkl", "ASDFGHJKL"),
        44..=50 => ("zxcvbnm", "ZXCVBNM"),
        57 => return " ".to_string(),
        _ => return String::new(),
    };
    let idx = match evdev {
        16..=25 => (evdev - 16) as usize,
        30..=38 => (evdev - 30) as usize,
        _ => (evdev - 44) as usize,
    };
    let letters: Vec<char> = if shift != caps { upper.chars().collect() } else { lower.chars().collect() };
    letters.get(idx).map(|c| c.to_string()).unwrap_or_default()
}

impl State {
    /// v3 的字节长度 -> 字符个数的保守换算（引擎按码点删；上限 8 个字符足够输入法场景）
    fn text_len_bytes_to_chars(&self, bytes: u32) -> u32 {
        ((bytes + 3) / 4).max(if bytes > 0 { 1 } else { 0 }).min(8)
    }

    /// 建立/替换键盘布局（wl_keyboard.keymap）。libxkbcommon 缺失时静默降级为 US 表。
    pub fn install_keymap(&mut self, format: wl_keyboard::KeymapFormat, fd: std::os::fd::OwnedFd, size: u32) {
        if !matches!(format, wl_keyboard::KeymapFormat::XkbV1) {
            eprintln!("[wayland] 不支持的 keymap 格式，回落 US 布局表");
            return;
        }
        let Some(lib) = xkb::xkbcommon_option() else {
            eprintln!("[wayland] libxkbcommon 不可用，回落 US 布局表");
            return;
        };
        let mut buf = vec![0u8; size as usize];
        {
            use std::io::Read;
            let mut f = std::fs::File::from(fd);
            if f.read_exact(&mut buf).is_err() {
                eprintln!("[wayland] 读 keymap 失败");
                return;
            }
        }
        if *buf.last().unwrap_or(&1) != 0 {
            buf.push(0);
        }
        unsafe {
            if self.xkb_ctx.is_none() {
                let ctx = (lib.xkb_context_new)(xkb::xkb_context_flags::XKB_CONTEXT_NO_FLAGS);
                if ctx.is_null() {
                    return;
                }
                self.xkb_ctx = Some(ctx);
            }
            let ctx = self.xkb_ctx.unwrap();
            let km = (lib.xkb_keymap_new_from_string)(
                ctx,
                buf.as_ptr() as *const std::os::raw::c_char,
                xkb::xkb_keymap_format::XKB_KEYMAP_FORMAT_TEXT_V1,
                xkb::xkb_keymap_compile_flags::XKB_KEYMAP_COMPILE_NO_FLAGS,
            );
            if km.is_null() {
                eprintln!("[wayland] keymap 编译失败，回落 US 布局表");
                return;
            }
            let st = (lib.xkb_state_new)(km);
            if st.is_null() {
                (lib.xkb_keymap_unref)(km);
                return;
            }
            if let Some(old) = self.xkb_state.take() {
                (lib.xkb_state_unref)(old);
            }
            if let Some(old) = self.xkb_keymap.replace(km) {
                (lib.xkb_keymap_unref)(old);
            }
            self.xkb_state = Some(st);
            self.refresh_xkb_state();
        }
        println!("[wayland] keymap 已装载（xkb）");
    }

    /// 把 Wayland 的修饰键掩码同步进 xkb state（决定 Shift/Caps 后的字符）。
    pub fn refresh_xkb_state(&mut self) {
        let (Some(lib), Some(st)) = (xkb::xkbcommon_option(), self.xkb_state) else {
            return;
        };
        unsafe {
            (lib.xkb_state_update_mask)(st, self.mods_depressed, self.mods_latched, self.mods_locked, 0, 0, 0);
        }
    }

    /// 该物理键在当前布局下产生的文本（空串 = 不产生文本）。
    pub fn key_text(&self, evdev: u32) -> String {
        let (Some(lib), Some(st)) = (xkb::xkbcommon_option(), self.xkb_state) else {
            return us_layout_text(evdev, self.shift_held(), self.caps_on());
        };
        // xkb 的 keycode = evdev + 8
        let mut out = [0i8; 32];
        let n = unsafe {
            (lib.xkb_state_key_get_utf8)(st, evdev + 8, out.as_mut_ptr() as *mut std::os::raw::c_char, out.len())
        };
        if n <= 0 {
            return String::new();
        }
        let bytes: Vec<u8> = out[..(n as usize).min(out.len() - 1)].iter().map(|&b| b as u8).collect();
        String::from_utf8_lossy(&bytes).into_owned()
    }

    fn shift_held(&self) -> bool {
        // xkb 的 Shift 掩码位是布局相关的，这里用 Wayland 的原始掩码近似：
        // 位 0 = Shift（xkb 默认布局），其余情况由 xkb 路径处理。
        (self.mods_depressed & 1) != 0
    }

    fn caps_on(&self) -> bool {
        (self.mods_locked & 2) != 0
    }

    /// 键事件的修饰键位（LWP_KEY_MODIFIERS_*，与 SDL_KMOD_* 同值）。
    pub fn key_modifier_mask(&self) -> u16 {
        let mut m: u16 = 0;
        if let (Some(lib), Some(st)) = (xkb::xkbcommon_option(), self.xkb_state) {
            let active = |name: &[u8]| unsafe {
                (lib.xkb_state_mod_name_is_active)(
                    st,
                    name.as_ptr() as *const std::os::raw::c_char,
                    xkb::xkb_state_component::XKB_STATE_MODS_EFFECTIVE,
                ) != 0
            };
            if active(xkb::XKB_MOD_NAME_SHIFT) { m |= 1; }
            if active(xkb::XKB_MOD_NAME_CTRL) { m |= 64; }
            if active(xkb::XKB_MOD_NAME_ALT) { m |= 256; }
            if active(xkb::XKB_MOD_NAME_LOGO) { m |= 1024; }
            if active(xkb::XKB_MOD_NAME_NUM) { m |= 4096; }
        } else if self.shift_held() {
            m |= 1;
        }
        m
    }

    /// 文本输入会话（引擎 lw_text_input.enable）：绑定到当前 surface。
    pub fn text_input_enable(&mut self, qh: &wayland_client::QueueHandle<State>) {
        if self.text_input.is_some() {
            return;
        }
        let (Some(mgr), Some(seat)) = (&self.text_input_manager, &self.seat) else {
            return;
        };
        // v3：get_text_input(seat)；绑定到哪个 surface 由 zwp_text_input_v3.enter 事件决定
        let ti = mgr.get_text_input(seat, qh, ());
        // 输入框语义：默认 TEXT + DONE（引擎的 input_type/enter_key 目前只有两类常用值）
        ti.set_content_type(
            wayland_protocols::wp::text_input::zv3::client::zwp_text_input_v3::ContentHint::None,
            wayland_protocols::wp::text_input::zv3::client::zwp_text_input_v3::ContentPurpose::Normal,
        );
        self.text_input = Some(ti);
        self.text_input_wanted = true;
        println!("[wayland] text_input enable");
    }

    pub fn text_input_disable(&mut self) {
        self.text_input_wanted = false;
        if let Some(ti) = self.text_input.take() {
            ti.disable();
            ti.commit();
            ti.destroy();
            println!("[wayland] text_input disable");
        }
    }
}

impl Dispatch<wl_keyboard::WlKeyboard, ()> for State {
    fn event(
        state: &mut Self,
        _: &wl_keyboard::WlKeyboard,
        event: <wl_keyboard::WlKeyboard as wayland_client::Proxy>::Event,
        _: &(),
        _: &Connection,
        _: &QueueHandle<Self>,
    ) {
        if let wl_keyboard::Event::Key { key, state: ks, .. } = event {
            // Wayland 的 key 是 evdev code（无需 +8 偏移）；LWP 直接用 evdev
            let down = matches!(ks, wayland_client::WEnum::Value(wl_keyboard::KeyState::Pressed));
            state.send_input(op::INPUT_KEY, &protocol::key(key, down));
        }
    }
}

impl Dispatch<ZwpTextInputManagerV3, ()> for State {
    fn event(
        _: &mut Self,
        _: &ZwpTextInputManagerV3,
        _: <ZwpTextInputManagerV3 as wayland_client::Proxy>::Event,
        _: &(),
        _: &Connection,
        _: &wayland_client::QueueHandle<Self>,
    ) {
    }
}

impl Dispatch<ZwpTextInputV3, ()> for State {
    fn event(
        state: &mut Self,
        _: &ZwpTextInputV3,
        event: <ZwpTextInputV3 as wayland_client::Proxy>::Event,
        _: &(),
        _: &Connection,
        _: &wayland_client::QueueHandle<Self>,
    ) {
        use wayland_protocols::wp::text_input::zv3::client::zwp_text_input_v3::Event;
        match event {
            // 上屏文本：引擎把它插入当前光标处并清空组合态
            Event::CommitString { text } => {
                if let Some(t) = text.filter(|t| !t.is_empty()) {
                    state.send_input(op::TEXT_INPUT_COMMIT_STRING,
                        &wayland_protocols_preedit_commit(&t));
                }
            }
            // 组合中文本：cursor_begin/cursor_end 是**字节**偏移（v3 定义）
            Event::PreeditString { text, cursor_begin, cursor_end } => {
                let t = text.unwrap_or_default();
                let cursor = if cursor_end >= 0 { cursor_end.max(0) as u32 } else { t.len() as u32 };
                let _ = cursor_begin;
                state.send_input(op::TEXT_INPUT_PREEDIT, &protocol::preedit(&t, cursor));
            }
            Event::DeleteSurroundingText { before_length, after_length } => {
                // v3 的 before/after 是**字节**长度；引擎按字符删，这里按 UTF-8 码点换算成保守值
                let before = state.text_len_bytes_to_chars(before_length.max(0) as u32);
                let after = state.text_len_bytes_to_chars(after_length.max(0) as u32);
                state.send_input(op::TEXT_INPUT_DELETE_SURROUNDING,
                    &protocol::delete_surrounding(before, after));
            }
            // v3 的 done：一批变更结束。引擎按到达顺序逐条应用，这里不需要额外事件。
            Event::Done { .. } => {}
            // 会话绑定到哪个 surface 由 enter 决定；enable 必须在那之后才生效，
            // 所以进入时才真正 enable+commit（之前调用只是登记意图）。
            Event::Enter { .. } => {
                if let Some(ti) = &state.text_input {
                    let (hint, purpose) = if state.pending_input_type == 1 {
                        (wayland_client_hint_none(), wayland_client_purpose_number())
                    } else {
                        (wayland_client_hint_none(), wayland_client_purpose_normal())
                    };
                    ti.set_content_type(hint, purpose);
                    if state.text_input_wanted {
                        ti.enable();
                    }
                    ti.commit();
                }
            }
            Event::Leave { .. } => {}
            _ => {}
        }
    }
}

impl Dispatch<wl_compositor::WlCompositor, ()> for State {
    fn event(
        _: &mut Self,
        _: &wl_compositor::WlCompositor,
        _: <wl_compositor::WlCompositor as wayland_client::Proxy>::Event,
        _: &(),
        _: &Connection,
        _: &QueueHandle<Self>,
    ) {
    }
}

impl Dispatch<wl_shm::WlShm, ()> for State {
    fn event(
        _: &mut Self,
        _: &wl_shm::WlShm,
        _: <wl_shm::WlShm as wayland_client::Proxy>::Event,
        _: &(),
        _: &Connection,
        _: &QueueHandle<Self>,
    ) {
    }
}

impl Dispatch<wl_shm_pool::WlShmPool, ()> for State {
    fn event(
        _: &mut Self,
        _: &wl_shm_pool::WlShmPool,
        _: <wl_shm_pool::WlShmPool as wayland_client::Proxy>::Event,
        _: &(),
        _: &Connection,
        _: &QueueHandle<Self>,
    ) {
    }
}

impl Dispatch<wl_buffer::WlBuffer, ()> for State {
    fn event(
        _: &mut Self,
        _: &wl_buffer::WlBuffer,
        _: <wl_buffer::WlBuffer as wayland_client::Proxy>::Event,
        _: &(),
        _: &Connection,
        _: &QueueHandle<Self>,
    ) {
    }
}

impl Dispatch<wl_surface::WlSurface, ()> for State {
    fn event(
        state: &mut Self,
        _: &wl_surface::WlSurface,
        event: <wl_surface::WlSurface as wayland_client::Proxy>::Event,
        _: &(),
        _: &Connection,
        _: &QueueHandle<Self>,
    ) {
        use wayland_client::protocol::wl_surface::Event as E;
        use wayland_client::Proxy;
        match event {
            // 表面进入/离开某个显示器：切到那个显示器的缩放（多屏 DPI 正确性）
            E::Enter { output } => {
                let id = output.id().protocol_id();
                state.surface_output = Some(id);
                if let Some(sc) = state.output_scales.get(&id).copied() {
                    state.output_scale = sc;
                }
                state.flush_configure();
            }
            E::Leave { output } => {
                let id = output.id().protocol_id();
                if state.surface_output == Some(id) {
                    state.surface_output = None;
                }
            }
            _ => {}
        }
    }
}

// ── 剪贴板（wl_data_device 系列）──────────────────────────────────────────
impl Dispatch<wl_data_device_manager::WlDataDeviceManager, ()> for State {
    fn event(
        _: &mut Self,
        _: &wl_data_device_manager::WlDataDeviceManager,
        _: <wl_data_device_manager::WlDataDeviceManager as wayland_client::Proxy>::Event,
        _: &(),
        _: &Connection,
        _: &QueueHandle<Self>,
    ) {
    }
}

impl Dispatch<wl_data_device::WlDataDevice, ()> for State {
    /// `data_offer` 事件会**新建一个对象**（wl_data_offer）；不实现这个钩子，
    /// wayland-client 直接 panic："Missing event_created_child specialization"。
    fn event_created_child(
        opcode: u16,
        qhandle: &QueueHandle<Self>,
    ) -> std::sync::Arc<dyn wayland_client::backend::ObjectData> {
        match opcode {
            0 => qhandle.make_data::<wl_data_offer::WlDataOffer, ()>(()),
            _ => panic!("wl_data_device 未知的 new_id 事件：{opcode}"),
        }
    }

    fn event(
        state: &mut Self,
        _: &wl_data_device::WlDataDevice,
        event: <wl_data_device::WlDataDevice as wayland_client::Proxy>::Event,
        _: &(),
        _: &Connection,
        _: &QueueHandle<Self>,
    ) {
        use wayland_client::protocol::wl_data_device::Event as E;
        match event {
            // 合成器新建了一个 offer：**必须持有**，否则代理被 drop 后对象销毁，
            // 紧接着的 selection(offer) 就成了非法引用（会直接协议错误）。
            E::DataOffer { id } => {
                state.offered = Some(id);
                state.offer_mimes.clear();
            }
            // 选区变了：记下最新的 offer（旧的由客户端 released 事件释放）。
            // 注意：mime 列表在 `data_offer` 时清空；`selection` 紧跟其后到达时**不能**再清，
            // 否则刚收到的 offer(mime) 会被抹掉（第 99 轮踩过）。
            E::Selection { id } => {
                use wayland_client::Proxy;
                let same = match (&id, &state.offered) {
                    (Some(a), Some(b)) => a.id().protocol_id() == b.id().protocol_id(),
                    _ => false,
                };
                if !same {
                    state.offer_mimes.clear();
                }
                state.selection_offer = id;
            }
            // 拖放：进入/移动/离开/落下
            E::Enter { x, y, id, .. } => {
                state.dnd_offer = id;
                state.dnd_x = x as u32;
                state.dnd_y = y as u32;
                state.send_request_event(iface::WINDOW, op::WINDOW_DRAG_ENTER,
                    &protocol::drag_enter(x as u32, y as u32, ""));
            }
            E::Motion { x, y, .. } => {
                state.dnd_x = x as u32;
                state.dnd_y = y as u32;
                state.send_request_event(iface::WINDOW, op::WINDOW_DRAG_MOTION,
                    &protocol::drag_motion(x as u32, y as u32));
            }
            E::Leave => {
                state.dnd_offer = None;
                state.send_request_event(iface::WINDOW, op::WINDOW_DRAG_LEAVE,
                    &protocol::drag_leave());
            }
            E::Drop => {
                // 向 offer 要 uri-list；读完在 poll 里发 drop 事件
                if let Some(offer) = state.dnd_offer.clone() {
                    if let Ok((ours, theirs)) = std::os::unix::net::UnixStream::pair() {
                        let _ = ours.set_nonblocking(true);
                        use std::os::fd::AsFd;
                        offer.receive("text/uri-list".to_string(), theirs.as_fd());
                        state.dnd_read = Some(ours);
                    }
                } else {
                    state.send_request_event(iface::WINDOW, op::WINDOW_DROP,
                        &protocol::drop_event(state.dnd_x, state.dnd_y, ""));
                }
            }
            _ => {}
        }
    }
}

impl Dispatch<wl_data_source::WlDataSource, ()> for State {
    fn event(
        state: &mut Self,
        _: &wl_data_source::WlDataSource,
        event: <wl_data_source::WlDataSource as wayland_client::Proxy>::Event,
        _: &(),
        _: &Connection,
        _: &QueueHandle<Self>,
    ) {
        use wayland_client::protocol::wl_data_source::Event as E;
        match event {
            // 别的客户端来取数据：把文本写进它给的 fd
            E::Send { mime_type: _, fd } => {
                // fd 是 OwnedFd：写不写都会在作用域结束时关闭，不会泄漏
                use std::io::Write;
                if let Some(text) = &state.pending_source_text {
                    let mut f = std::fs::File::from(fd);
                    let _ = f.write_all(text.as_bytes());
                }
            }
            E::Cancelled => {
                state.data_source = None;
                state.pending_source_text = None;
            }
            _ => {}
        }
    }
}

impl Dispatch<wl_data_offer::WlDataOffer, ()> for State {
    fn event(
        state: &mut Self,
        _: &wl_data_offer::WlDataOffer,
        event: <wl_data_offer::WlDataOffer as wayland_client::Proxy>::Event,
        _: &(),
        _: &Connection,
        _: &QueueHandle<Self>,
    ) {
        use wayland_client::protocol::wl_data_offer::Event as E;
        if let E::Offer { mime_type } = event {
            state.offer_mimes.push(mime_type);
        }
    }
}

impl Dispatch<wl_output::WlOutput, ()> for State {
    fn event(
        state: &mut Self,
        output: &wl_output::WlOutput,
        event: <wl_output::WlOutput as wayland_client::Proxy>::Event,
        _: &(),
        _: &Connection,
        _: &QueueHandle<Self>,
    ) {
        use wayland_client::Proxy;
        if let wl_output::Event::Scale { factor } = event {
            if factor > 0 {
                let id = output.id().protocol_id();
                state.output_scales.insert(id, factor);
                // 表面还没进过任何 output 时，退回第一个 output 的缩放
                if state.surface_output.is_none() {
                    state.output_scale = factor;
                }
                // 表面就在这个 output 上：立刻更新
                if state.surface_output == Some(id) {
                    state.output_scale = factor;
                    state.flush_configure();
                }
            }
        }
    }
}

impl Dispatch<wl_seat::WlSeat, ()> for State {
    fn event(
        _: &mut Self,
        seat: &wl_seat::WlSeat,
        event: <wl_seat::WlSeat as wayland_client::Proxy>::Event,
        _: &(),
        _: &Connection,
        qh: &QueueHandle<Self>,
    ) {
        if let wl_seat::Event::Capabilities { capabilities } = event {
            // 能力位只是记账：M1W 阶段按键/指针转发由后续的 pointer/keyboard 对象完成
            let has_ptr = matches!(capabilities.into_result(), Ok(c)
                if c.contains(wl_seat::Capability::Pointer));
            let has_kbd = matches!(capabilities.into_result(), Ok(c)
                if c.contains(wl_seat::Capability::Keyboard));
            // 拿到能力位才创建对应对象；事件由各自的 Dispatch 转发成 lw_input.*
            if has_ptr {
                let _ = seat.get_pointer(qh, ());
            }
            if has_kbd {
                let _ = seat.get_keyboard(qh, ());
            }
        }
    }
}

impl Dispatch<xdg_wm_base::XdgWmBase, ()> for State {
    fn event(
        _: &mut Self,
        wm_base: &xdg_wm_base::XdgWmBase,
        event: <xdg_wm_base::XdgWmBase as wayland_client::Proxy>::Event,
        _: &(),
        _: &Connection,
        _: &QueueHandle<Self>,
    ) {
        // 合成器 ping，必须回 pong，否则会被判定无响应并断开
        if let xdg_wm_base::Event::Ping { serial } = event {
            wm_base.pong(serial);
        }
    }
}

impl Dispatch<xdg_surface::XdgSurface, ()> for State {
    fn event(
        state: &mut Self,
        _xdg_surface: &xdg_surface::XdgSurface,
        event: <xdg_surface::XdgSurface as wayland_client::Proxy>::Event,
        _: &(),
        _: &Connection,
        _: &QueueHandle<Self>,
    ) {
        if let xdg_surface::Event::Configure { serial } = event {
            state.pending_configure_serial = Some(serial);
            state.flush_configure();
        }
    }
}

impl Dispatch<xdg_toplevel::XdgToplevel, ()> for State {
    fn event(
        state: &mut Self,
        _: &xdg_toplevel::XdgToplevel,
        event: <xdg_toplevel::XdgToplevel as wayland_client::Proxy>::Event,
        _: &(),
        _: &Connection,
        _: &QueueHandle<Self>,
    ) {
        match event {
            xdg_toplevel::Event::Configure { width, height, .. } => {
                if width > 0 && height > 0 {
                    state.pending = Some((width as u32, height as u32));
                    // 尺寸变了通知引擎（它会重配 swapchain，不重建 device）
                    state.flush_configure();
                }
            }
            xdg_toplevel::Event::Close => {
                println!("[wayland] toplevel close");
            }
            _ => {}
        }
    }
}

impl Dispatch<wl_registry::WlRegistry, GlobalListContents> for State {
    fn event(
        _: &mut Self,
        _: &wl_registry::WlRegistry,
        _: <wl_registry::WlRegistry as wayland_client::Proxy>::Event,
        _: &GlobalListContents,
        _: &Connection,
        _: &QueueHandle<Self>,
    ) {
        // registry_queue_init 会自己跟踪全局列表，这里无需额外处理
    }
}

/// 供测试用：把 LWP edges 位转成 xdg ResizeEdge。
pub fn test_edges(bits: u32) -> xdg_toplevel::ResizeEdge {
    to_xdg_edges(bits)
}

/// 供测试：uri -> 路径。
pub fn test_uri_to_path(uri: &str) -> String {
    uri_to_path(uri)
}

/// `file:///path` -> `/path`（简单百分号解码）；不是 file URI 就原样返回。
fn uri_to_path(uri: &str) -> String {
    let rest = match uri.strip_prefix("file://") {
        Some(r) => r,
        None => return uri.to_string(),
    };
    let bytes = rest.as_bytes();
    let mut out = Vec::with_capacity(bytes.len());
    let mut i = 0;
    while i < bytes.len() {
        if bytes[i] == b'%' && i + 2 < bytes.len() {
            let hex = &rest[i + 1..i + 3];
            if let Ok(v) = u8::from_str_radix(hex, 16) {
                out.push(v);
                i += 3;
                continue;
            }
        }
        out.push(bytes[i]);
        i += 1;
    }
    String::from_utf8_lossy(&out).into_owned()
}

/// LWP 的 edges 位与 xdg-shell 一致（1=上 2=下 4=左 8=右），直接转。
fn to_xdg_edges(bits: u32) -> xdg_toplevel::ResizeEdge {
    use xdg_toplevel::ResizeEdge as E;
    // 组合边在 xdg-shell 里是单独的枚举值
    match bits & 0xF {
        // xdg-shell 没有「上+下」「左+右」这种组合边（语义上无意义），按 None 处理
        3 | 12 => E::None,
        5 => E::TopLeft,       // 1|4
        6 => E::TopRight,      // 2|4
        9 => E::BottomLeft,    // 1|8
        10 => E::BottomRight,  // 2|8
        1 => E::Top,
        2 => E::Bottom,
        4 => E::Left,
        8 => E::Right,
        _ => E::None,
    }
}

/// 读 `lwp_str`（u16 off / u16 len，相对 body 起点）。
fn lwp_str(body: &[u8], at: usize) -> String {
    if at + 4 > body.len() {
        return String::new();
    }
    let off = u16::from_le_bytes([body[at], body[at + 1]]) as usize;
    let len = u16::from_le_bytes([body[at + 2], body[at + 3]]) as usize;
    if off + len > body.len() {
        return String::new();
    }
    String::from_utf8_lossy(&body[off..off + len]).into_owned()
}

fn lwp_str_len(body: &[u8], at: usize) -> usize {
    if at + 4 > body.len() {
        return 0;
    }
    u16::from_le_bytes([body[at + 2], body[at + 3]]) as usize
}

/// 把系统事实（时区/语言/字体目录/home/api level）同步一次给引擎。
/// 抽成独立函数便于测试：`run()` 里调用，测试里也能直接调用。
pub fn announce_system_info(ch: &Channel) {
    let tz = std::env::var("TZ").unwrap_or_else(|_| "UTC".to_string());
    let lang = std::env::var("LANG").unwrap_or_else(|_| "C".to_string());
    let home = std::env::var("HOME").unwrap_or_else(|_| "/".to_string());
    let font_dir = std::env::var("LANLU_FONT_DIR")
        .unwrap_or_else(|_| "/usr/share/fonts".to_string());
    let _ = ch.send(LWP_REQUEST, iface::SYSTEM, op::SYSTEM_INFO, 0,
        &protocol::system_info(&tz, &lang, &font_dir, &home, protocol::API_LEVEL_NA));
}

/// M1W 的第一步：连上合成器、绑定全局、发 hello，然后进主循环。
/// 没有合成器时返回 Err 说明原因（这是本环境的预期路径）。
pub fn run(channel: Channel) -> Result<(), String> {
    let (shell, mut queue) = Shell::connect()?;
    println!(
        "[wayland] 已连接合成器，display fd={}，seat={}",
        shell.display_fd(),
        shell.seat.is_some()
    );

    // 录制（§16.3）：LANLU_LWP_TRACE=<path> 时把整个会话录下来，便于事后 diff/回放
    if let Ok(path) = std::env::var("LANLU_LWP_TRACE") {
        if !path.is_empty() {
            let ok = channel.trace_open(&path);
            println!("[wayland] trace {path} -> {ok}");
        }
    }

    // 握手：hello 必须最先发（协议检查器要求，见计划 §5.3）
    // 现在支持 mime 协商（从 offer 列表里挑），所以 CLIPBOARD_MIME 也宣告出去
    let caps = CAP_SERVER_SIDE_DECORATIONS
        | CAP_CURSOR_SHAPES
        | CAP_CLIPBOARD_READ_ASYNC
        | (1 << 9) /* CAP_CLIPBOARD_MIME */;
    let _ = channel.send(
        LWP_EVENT,
        iface::CORE,
        op::CORE_HELLO,
        0,
        &protocol::hello("wayland", "linux", 0, caps),
    );

    let mut state = State::with_channel(channel);
    state.text_input_manager = shell.text_input_manager.clone();
    state.seat = shell.seat.clone();
    // 剪贴板：有 seat + manager 才建 data device
    {
        let qh = queue.handle();
        if let (Some(dm), Some(seat)) = (&shell.data_manager, &shell.seat) {
            state.data_device = Some(dm.get_data_device(seat, &qh, ()));
        }
    }
    // 第一轮：先把 registry 事件处理掉（拿到全部全局）
    queue
        .roundtrip(&mut state)
        .map_err(|e| format!("roundtrip 失败: {e}"))?;
    let shared = state.channel.clone().expect("刚构造的 State 一定有通道");

    if let Ok(c) = shared.lock() {
        announce_system_info(&c);
    }
    // 默认窗口尺寸（合成器 configure 前先用它；拿到 configure 后以合成器为准）
    let iface_w: u32 = std::env::var("LANLU_WAYLAND_W").ok()
        .and_then(|v| v.parse().ok()).unwrap_or(1280);
    let iface_h: u32 = std::env::var("LANLU_WAYLAND_H").ok()
        .and_then(|v| v.parse().ok()).unwrap_or(800);

    // 主循环：一把抓 wayland 事件 + 看 LWP 有没有 request。
    loop {
        // 非阻塞取出所有待处理的 LWP 请求（window.create 等）
        // 剪贴板：把上一轮发起、这一轮已就绪的数据读回来
        state.poll_clipboard_read();
        // 拖放：落下后读取 uri-list（读完发 drop 事件）
        state.poll_dnd_read();

        let mut pending = Vec::new();
        if let Ok(c) = shared.lock() {
            while let Some(m) = c.recv(crate::lwp::LWP_REQUEST) {
                pending.push((m.iface, m.opcode, m.body));
            }
        }
        for (iface_id, opcode, body) in pending {
            let len = body.len();
            match (iface_id, opcode) {
                // window.create：建 xdg 窗口，回 created + configure（计划 §7）
                (iface::WINDOW, op::WINDOW_CREATE_REQ) => {
                    let qh = queue.handle();
                    let (surf, xdg, tl) = shell.create_window(&qh, "lanlu", "com.lanlu");
                    state.surface = Some(surf);
                    state.xdg_surface = Some(xdg);
                    state.toplevel = Some(tl);
                    if let Ok(c) = shared.lock() {
                        let scale = state.output_scale as f32;
                        let _ = c.send(LWP_REQUEST, iface::WINDOW, op::WINDOW_CREATED, 0,
                            &protocol::window_created(1, scale, false));
                        let _ = c.send(LWP_REQUEST, iface::WINDOW, op::WINDOW_CONFIGURE, 0,
                            &protocol::window_configure(iface_w, iface_h, 0));
                    }
                    println!("[wayland] window.create -> xdg toplevel {iface_w}x{iface_h}");
                }
                // surface.attach：引擎提交一帧。buffer = 进程内 fd（同进程），见 §7.3.1
                (iface::SURFACE, op::SURFACE_ATTACH_REQ) if body.len() >= 24 => {
                    let fd_raw = u64::from_le_bytes(body[4..12].try_into().unwrap());
                    let w = u32::from_le_bytes(body[12..16].try_into().unwrap());
                    let h = u32::from_le_bytes(body[16..20].try_into().unwrap());
                    let serial = u32::from_le_bytes(body[20..24].try_into().unwrap());
                    let fd = fd_raw as i64;
                    if fd >= 0 && fd <= i32::MAX as i64 {
                        let qh = queue.handle();
                        match state.attach_shm(&shell, &qh, fd as i32, w, h) {
                            Ok(reused) => println!(
                                "[wayland] attach serial={serial} {w}x{h} reused={reused}"),
                            Err(e) => println!("[wayland] attach 失败: {e}"),
                        }
                    } else {
                        println!("[wayland] attach 的 fd 非法: {fd}");
                    }
                }
                // text_input.enable：输入框获焦，绑定 text-input-v3 会话（引擎的 input_type/enter_key
                // 只有文本/数字两类常用值，v3 的 content_purpose 只需区分 Normal/Number）
                (iface::TEXT_INPUT, op::TEXT_INPUT_ENABLE_REQ) => {
                    let qh = queue.handle();
                    if body.len() >= 12 {
                        let itype = u32::from_le_bytes(body[4..8].try_into().unwrap());
                        state.pending_input_type = itype;
                    }
                    state.text_input_enable(&qh);
                }
                (iface::TEXT_INPUT, op::TEXT_INPUT_DISABLE_REQ) => {
                    state.text_input_disable();
                }
                // text_input.set_cursor_rect：候选框跟着光标（窗口局部 px -> surface 坐标）
                (iface::TEXT_INPUT, op::TEXT_INPUT_SET_CURSOR_RECT_REQ) if body.len() >= 20 => {
                    let x = i32::from_le_bytes(body[4..8].try_into().unwrap());
                    let y = i32::from_le_bytes(body[8..12].try_into().unwrap());
                    let w = i32::from_le_bytes(body[12..16].try_into().unwrap());
                    let h = i32::from_le_bytes(body[16..20].try_into().unwrap());
                    if let Some(ti) = &state.text_input {
                        ti.set_cursor_rectangle(x, y, w, h);
                        ti.commit();
                    }
                }
                // text_input.set_surrounding：光标周围文本（联想/删除上下文）
                (iface::TEXT_INPUT, op::TEXT_INPUT_SET_SURROUNDING_REQ) if body.len() >= 16 => {
                    let text = lwp_str(&body, 4);
                    let text_len = lwp_str_len(&body, 4);
                    let cursor = u32::from_le_bytes(body[8 + text_len..12 + text_len].try_into().unwrap());
                    let anchor = u32::from_le_bytes(body[12 + text_len..16 + text_len].try_into().unwrap());
                    if let Some(ti) = &state.text_input {
                        ti.set_surrounding_text(text, cursor as i32, anchor as i32);
                        ti.commit();
                    }
                }
                // clipboard.set：成为选区拥有者（别的客户端来取时由 data_source.send 写回）
                (iface::CLIPBOARD, op::CLIPBOARD_SET_REQ) if body.len() >= 12 => {
                    let mime = lwp_str(&body, 4);
                    let mime_len = lwp_str_len(&body, 4);
                    let text = lwp_str(&body, 8 + mime_len);
                    match (&shell.data_manager, &state.data_device) {
                        (Some(dm), Some(dd)) => {
                            let qh = queue.handle();
                            let src = dm.create_data_source(&qh, ());
                            src.offer("text/plain;charset=utf-8".to_string());
                            src.offer("text/plain".to_string());
                            src.offer("UTF8_STRING".to_string());
                            dd.set_selection(Some(&src), state.last_input_serial);
                            state.pending_source_text = Some(text);
                            state.data_source = Some(src);
                            println!("[wayland] clipboard.set {mime} {}B -> 选区", body.len());
                        }
                        _ => println!("[wayland] clipboard.set：没有 data device（无 seat？）"),
                    }
                }
                // clipboard.get：有选区就先记下 serial，取回数据后回 clipboard.text
                (iface::CLIPBOARD, op::CLIPBOARD_GET_REQ) if body.len() >= 8 => {
                    let serial = u32::from_le_bytes(body[4..8].try_into().unwrap());
                    state.pending_get_serial = Some(serial);
                    let has_offer = state.selection_offer.is_some();
                    println!("[wayland] clipboard.get serial={serial} offer={has_offer}");
                    if has_offer {
                        // 先按 offer 的 mime 列表协商，挑不到就退回 utf8（合成器多半接受）
                        let mime = state.pick_mime().unwrap_or("text/plain;charset=utf-8").to_string();
                        if let Err(e) = state.start_clipboard_read(&mime) {
                            println!("[wayland] clipboard.get 发起失败: {e}");
                            if let Ok(c) = shared.lock() {
                                let _ = c.send(LWP_REQUEST, iface::CLIPBOARD, op::CLIPBOARD_TEXT, 0,
                                    &protocol::clipboard_text(serial, "text/plain", ""));
                            }
                            state.pending_get_serial = None;
                        }
                    } else {
                        // 没有选区：立刻回空文本，避免引擎一直等
                        if let Ok(c) = shared.lock() {
                            let _ = c.send(LWP_REQUEST, iface::CLIPBOARD, op::CLIPBOARD_TEXT, 0,
                                &protocol::clipboard_text(serial, "text/plain", ""));
                        }
                        state.pending_get_serial = None;
                    }
                }
                // system.log：引擎日志 -> 壳的 stderr/hilog
                (iface::SYSTEM, op::SYSTEM_LOG_REQ) if body.len() >= 9 => {
                    let level = body[4];
                    let off = u16::from_le_bytes([body[5], body[6]]) as usize;
                    let l = u16::from_le_bytes([body[7], body[8]]) as usize;
                    if off + l <= body.len() {
                        let text = String::from_utf8_lossy(&body[off..off + l]);
                        println!("[lanlu-engine L{level}] {text}");
                    }
                }
                // window.set_state：1=普通 2=最大化 4=全屏（与 configure 的 state 位一致）
                (iface::WINDOW, op::WINDOW_SET_STATE_REQ) if body.len() >= 8 => {
                    let st = u32::from_le_bytes(body[4..8].try_into().unwrap());
                    match &state.toplevel {
                        Some(tl) => {
                            // xdg_toplevel 请求：set_maximized(11) / unset_maximized(12)
                            //                  set_fullscreen(13) / unset_fullscreen(14)
                            if st & 2 != 0 {
                                tl.set_maximized();
                            } else if st & 4 != 0 {
                                tl.set_fullscreen(None);
                            } else {
                                tl.unset_maximized();
                                tl.unset_fullscreen();
                            }
                            println!("[wayland] window.set_state {st} -> xdg_toplevel");
                        }
                        None => println!("[wayland] window.set_state {st}：还没有 toplevel"),
                    }
                }
                // 运行期改标题 / 最小最大尺寸（计划 §7.4，过去只声明未实现）
                (iface::WINDOW, op::WINDOW_SET_TITLE_REQ) => {
                    let title = lwp_str(&body, 4);
                    if let Some(tl) = &state.toplevel {
                        tl.set_title(title.clone());
                    }
                    println!("[wayland] window.set_title {title}");
                }
                (iface::WINDOW, op::WINDOW_SET_MIN_MAX_REQ) if body.len() >= 20 => {
                    let min_w = u32::from_le_bytes(body[4..8].try_into().unwrap());
                    let min_h = u32::from_le_bytes(body[8..12].try_into().unwrap());
                    let max_w = u32::from_le_bytes(body[12..16].try_into().unwrap());
                    let max_h = u32::from_le_bytes(body[16..20].try_into().unwrap());
                    if let Some(tl) = &state.toplevel {
                        tl.set_min_size(min_w as i32, min_h as i32);
                        tl.set_max_size(max_w as i32, max_h as i32);
                    }
                    println!("[wayland] window.set_min_max min={min_w}x{min_h} max={max_w}x{max_h}");
                }
                // 交互式移动/缩放：xdg_toplevel.move/resize 需要 seat + 最近一次输入 serial
                (iface::WINDOW, op::WINDOW_BEGIN_MOVE_REQ) => {
                    match (&state.toplevel, &shell.seat) {
                        (Some(tl), Some(seat)) => {
                            tl._move(seat, state.last_input_serial);
                            println!("[wayland] begin_move serial={}", state.last_input_serial);
                        }
                        _ => println!("[wayland] begin_move：缺 toplevel 或 seat"),
                    }
                }
                (iface::WINDOW, op::WINDOW_BEGIN_RESIZE_REQ) if body.len() >= 8 => {
                    let edges = u32::from_le_bytes(body[4..8].try_into().unwrap());
                    match (&state.toplevel, &shell.seat) {
                        (Some(tl), Some(seat)) => {
                            tl.resize(seat, state.last_input_serial, to_xdg_edges(edges));
                            println!("[wayland] begin_resize edges={edges}");
                        }
                        _ => println!("[wayland] begin_resize：缺 toplevel 或 seat"),
                    }
                }
                (iface::WINDOW, op::WINDOW_CLOSE_REQ) => {
                    if let Some(tl) = &state.toplevel {
                        tl.destroy();
                    }
                    println!("[wayland] window.close -> toplevel.destroy");
                    return Ok(());
                }
                (iface::APP, op::APP_EXIT_REQ) if body.len() >= 8 => {
                    let code = i32::from_le_bytes(body[4..8].try_into().unwrap());
                    println!("[wayland] app.exit({code}) -> 退出主循环");
                    return Ok(());
                }
                _ => println!("[wayland] recv iface={iface_id} opcode={opcode} len={len}"),
            }
        }
        queue
            .blocking_dispatch(&mut state)
            .map_err(|e| format!("dispatch 失败: {e}"))?;
    }
}
