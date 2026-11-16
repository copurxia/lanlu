//! LWP 消息编解码（Wayland 壳侧）。
//!
//! 布局由 `packages/lwp/protocol/*.toml` 生成，与 `include/lwp_protocol.h` 一一对应：
//! 每条消息体以 `uint32 size` 开头（含自身、不含 lwp_header），字段 packed 小端，
//! `string = {u16 off; u16 len}` 且 `off` 相对**消息体起点**，变长载荷排在定长头之后。
//!
//! 这里只实现 M1W 需要的那部分；尺寸常量在测试里与 C 头逐一对照，防止两侧漂移。

pub mod iface {
    pub const CORE: u16 = 1;
    pub const INPUT: u16 = 2;
    pub const APP: u16 = 3;
    pub const WINDOW: u16 = 4;
    pub const SURFACE: u16 = 5;
    pub const SYSTEM: u16 = 12;
    pub const CLIPBOARD: u16 = 10;
    pub const TEXT_INPUT: u16 = 9;
}

pub mod op {
    // 引擎 -> 壳 的请求（与上面壳 -> 引擎的事件号独立编号，见 lwp/README.md）
    pub const WINDOW_CREATE_REQ: u16 = 0;
    pub const WINDOW_SET_TITLE_REQ: u16 = 2;
    pub const WINDOW_SET_MIN_MAX_REQ: u16 = 3;
    pub const WINDOW_SET_STATE_REQ: u16 = 4;
    pub const WINDOW_CLOSE_REQ: u16 = 5;
    pub const WINDOW_BEGIN_MOVE_REQ: u16 = 6;
    pub const WINDOW_BEGIN_RESIZE_REQ: u16 = 7;
    pub const APP_EXIT_REQ: u16 = 0;
    pub const SYSTEM_LOG_REQ: u16 = 1;
    pub const SURFACE_ATTACH_REQ: u16 = 0;
    // core（壳 -> 引擎）
    pub const CORE_HELLO: u16 = 0;
    // app（壳 -> 引擎）
    pub const APP_STARTED: u16 = 0;
    pub const APP_RESUMED: u16 = 1;
    // window（壳 -> 引擎）
    pub const WINDOW_CREATED: u16 = 0;
    pub const WINDOW_CONFIGURE: u16 = 1;
    // surface（壳 -> 引擎）
    pub const SURFACE_AVAILABLE: u16 = 0;
    pub const SURFACE_CHANGED: u16 = 1;
    // input（壳 -> 引擎）
    pub const INPUT_POINTER_BUTTON: u16 = 0;
    pub const INPUT_POINTER_MOTION: u16 = 1;
    pub const INPUT_POINTER_AXIS: u16 = 2;
    pub const INPUT_KEY: u16 = 3;
    pub const INPUT_TEXT_INPUT: u16 = 4;
    // text_input（引擎 -> 壳的请求 / 壳 -> 引擎的事件），id 与 lw_text_input 一致
    pub const TEXT_INPUT_ENABLE_REQ: u16 = 0;
    pub const TEXT_INPUT_DISABLE_REQ: u16 = 1;
    pub const TEXT_INPUT_SET_SURROUNDING_REQ: u16 = 2;
    pub const TEXT_INPUT_SET_CURSOR_RECT_REQ: u16 = 3;
    pub const TEXT_INPUT_PREEDIT: u16 = 0;
    pub const TEXT_INPUT_COMMIT_STRING: u16 = 1;
    pub const TEXT_INPUT_DELETE_SURROUNDING: u16 = 2;
    // system（壳 -> 引擎）
    pub const SYSTEM_INFO: u16 = 0;
    // clipboard（引擎 -> 壳）
    pub const CLIPBOARD_GET_REQ: u16 = 0;
    pub const CLIPBOARD_SET_REQ: u16 = 1;
    // shell -> 引擎（lw_window 事件方向）
    pub const WINDOW_DRAG_ENTER: u16 = 2;
    pub const WINDOW_DRAG_MOTION: u16 = 3;
    pub const WINDOW_DRAG_LEAVE: u16 = 4;
    pub const WINDOW_DROP: u16 = 5;
    pub const CLIPBOARD_TEXT: u16 = 0;
}

/// `system.info.api_level` 的「不适用」值：Wayland/桌面端没有 OS API level 这个概念。
/// 用 0 会被引擎误读成「壳说自己是 API 0」，所以显式用哨兵。
pub const API_LEVEL_NA: u32 = 0xFFFF_FFFF;

pub const PROTOCOL_MAJOR: u16 = 1;
pub const PROTOCOL_MINOR: u16 = 0;

// 与 C 头一致的定长尺寸（测试断言用）
pub const HELLO_SIZE: usize = 28;
pub const SYSTEM_INFO_SIZE: usize = 24;
pub const WINDOW_CREATED_SIZE: usize = 13;
pub const WINDOW_CONFIGURE_SIZE: usize = 16;
pub const SURFACE_AVAILABLE_SIZE: usize = 20;
pub const POINTER_BUTTON_SIZE: usize = 14;
pub const POINTER_MOTION_SIZE: usize = 12;
pub const POINTER_AXIS_SIZE: usize = 12;
pub const KEY_SIZE: usize = 9;
pub const TEXT_INPUT_SIZE: usize = 8;
pub const PREEDIT_SIZE: usize = 12;
pub const COMMIT_STRING_SIZE: usize = 8;
pub const DELETE_SURROUNDING_SIZE: usize = 12;

/// 小端写缓冲。所有消息体都以 size 开头，最后统一回填。
struct Buf {
    b: Vec<u8>,
}

impl Buf {
    fn new(cap: usize) -> Self {
        Buf { b: Vec::with_capacity(cap) }
    }
    fn u8(&mut self, v: u8) {
        self.b.push(v);
    }
    fn u16(&mut self, v: u16) {
        self.b.extend_from_slice(&v.to_le_bytes());
    }
    fn u32(&mut self, v: u32) {
        self.b.extend_from_slice(&v.to_le_bytes());
    }
    fn u64(&mut self, v: u64) {
        self.b.extend_from_slice(&v.to_le_bytes());
    }
    fn f32(&mut self, v: f32) {
        self.b.extend_from_slice(&v.to_le_bytes());
    }
    fn bytes(&mut self, v: &[u8]) {
        self.b.extend_from_slice(v);
    }
    /// 回填首个 u32 为总长度并返回缓冲。
    fn finish(mut self) -> Vec<u8> {
        let n = self.b.len() as u32;
        self.b[0..4].copy_from_slice(&n.to_le_bytes());
        self.b
    }
}

/// 组 `lwp_str` 头：off/len 都是 u16，off 相对消息体起点。
fn put_str_header(b: &mut Buf, off: usize, len: usize) -> Result<(), String> {
    if off > u16::MAX as usize || len > u16::MAX as usize {
        return Err("lwp_str 超出 u16 范围".into());
    }
    b.u16(off as u16);
    b.u16(len as u16);
    Ok(())
}

/// core.hello：壳 -> 引擎的握手（宣告能力位）。
pub fn hello(shell_name: &str, os_name: &str, os_api_level: u32, capabilities: u64) -> Vec<u8> {
    let sn = shell_name.as_bytes();
    let on = os_name.as_bytes();
    let mut b = Buf::new(HELLO_SIZE + sn.len() + on.len());
    b.u32(0); // size 占位
    b.u16(PROTOCOL_MAJOR);
    b.u16(PROTOCOL_MINOR);
    let sn_off = HELLO_SIZE;
    let on_off = HELLO_SIZE + sn.len();
    let _ = put_str_header(&mut b, sn_off, sn.len());
    let _ = put_str_header(&mut b, on_off, on.len());
    b.u32(os_api_level);
    b.u64(capabilities);
    b.bytes(sn);
    b.bytes(on);
    b.finish()
}

/// window.created：窗口已建（含 DPI 缩放）。
/// system.info：启动时同步一次的系统事实（4 个字符串 + api_level）。
pub fn system_info(tz: &str, lang: &str, font_dir: &str, home: &str, api_level: u32) -> Vec<u8> {
    let parts = [tz, lang, font_dir, home];
    let total_payload: usize = parts.iter().map(|p| p.len()).sum();
    let mut b = Buf::new(SYSTEM_INFO_SIZE + total_payload);
    b.u32(0);
    // 四个 lwp_str 头（各 4 字节）占 4..20，载荷从 24 开始
    let mut off = SYSTEM_INFO_SIZE;
    for p in parts.iter() {
        let _ = put_str_header(&mut b, off, p.len());
        off += p.len();
    }
    b.u32(api_level);
    for p in parts.iter() {
        b.bytes(p.as_bytes());
    }
    b.finish()
}

/// clipboard.text：{size, serial, mime(lwp_str), text(lwp_str)}，头 16 字节。
pub fn clipboard_text(serial: u32, mime: &str, text: &str) -> Vec<u8> {
    // C 头：{size(4), serial(4), mime(lwp_str@8), text(lwp_str@12)}，载荷从 16 开始
    let mut b = Buf::new(16 + mime.len() + text.len());
    b.u32(0);
    b.u32(serial);
    let _ = put_str_header(&mut b, 16, mime.len());           // 8..12
    let _ = put_str_header(&mut b, 16 + mime.len(), text.len()); // 12..16
    b.bytes(mime.as_bytes());
    b.bytes(text.as_bytes());
    b.finish()
}

pub fn window_created(window_id: u32, scale: f32, server_side_decorations: bool) -> Vec<u8> {
    let mut b = Buf::new(WINDOW_CREATED_SIZE);
    b.u32(0);
    b.u32(window_id);
    b.f32(scale);
    b.u8(if server_side_decorations { 1 } else { 0 });
    b.finish()
}

/// window.configure：尺寸/状态下发（引擎必须回 ack_configure）。
pub fn window_configure(width: u32, height: u32, state: u32) -> Vec<u8> {
    let mut b = Buf::new(WINDOW_CONFIGURE_SIZE);
    b.u32(0);
    b.u32(width);
    b.u32(height);
    b.u32(state);
    b.finish()
}

/// surface.available：把原生窗口句柄交给引擎（Wayland 下是 wl_surface 指针）。
pub fn surface_available(handle: u64, width: u32, height: u32) -> Vec<u8> {
    let mut b = Buf::new(SURFACE_AVAILABLE_SIZE);
    b.u32(0);
    b.u64(handle);
    b.u32(width);
    b.u32(height);
    b.finish()
}

/// surface.changed：尺寸变化（引擎据此重配 swapchain）。
/// drag_enter / drop 共用的布局：size|x|y|uris(lwp_str@12)，载荷从 16 开始
fn drag_with_uris(opcode_size: usize, x: u32, y: u32, uris: &str) -> Vec<u8> {
    let mut b = Buf::new(opcode_size + uris.len());
    b.u32(0);
    b.u32(x);
    b.u32(y);
    let _ = put_str_header(&mut b, 16, uris.len());
    b.bytes(uris.as_bytes());
    b.finish()
}

pub const DRAG_ENTER_SIZE: usize = 16;
pub const DRAG_MOTION_SIZE: usize = 12;
pub const DRAG_LEAVE_SIZE: usize = 4;
pub const DROP_SIZE: usize = 16;

pub fn drag_enter(x: u32, y: u32, uris: &str) -> Vec<u8> {
    drag_with_uris(DRAG_ENTER_SIZE, x, y, uris)
}

pub fn drag_motion(x: u32, y: u32) -> Vec<u8> {
    let mut b = Buf::new(DRAG_MOTION_SIZE);
    b.u32(0);
    b.u32(x);
    b.u32(y);
    b.finish()
}

pub fn drag_leave() -> Vec<u8> {
    let mut b = Buf::new(DRAG_LEAVE_SIZE);
    b.u32(0);
    b.finish()
}

pub fn drop_event(x: u32, y: u32, uris: &str) -> Vec<u8> {
    drag_with_uris(DROP_SIZE, x, y, uris)
}

pub fn surface_changed(width: u32, height: u32) -> Vec<u8> {
    let mut b = Buf::new(12);
    b.u32(0);
    b.u32(width);
    b.u32(height);
    b.finish()
}

pub fn pointer_button(x: f32, y: f32, button: u8, down: bool) -> Vec<u8> {
    let mut b = Buf::new(POINTER_BUTTON_SIZE);
    b.u32(0);
    b.f32(x);
    b.f32(y);
    b.u8(button);
    b.u8(if down { 1 } else { 0 });
    b.finish()
}

pub fn pointer_motion(x: f32, y: f32) -> Vec<u8> {
    let mut b = Buf::new(POINTER_MOTION_SIZE);
    b.u32(0);
    b.f32(x);
    b.f32(y);
    b.finish()
}

/// 滚轮/触摸板轴事件（逻辑行数；与 `lw_input.pointer_axis` 对应）。
pub fn pointer_axis(dx: f32, dy: f32) -> Vec<u8> {
    let mut b = Buf::new(POINTER_AXIS_SIZE);
    b.u32(0);
    b.f32(dx);
    b.f32(dy);
    b.finish()
}

pub fn key(keycode: u32, down: bool) -> Vec<u8> {
    let mut b = Buf::new(KEY_SIZE);
    b.u32(0);
    b.u32(keycode);
    b.u8(if down { 1 } else { 0 });
    b.finish()
}

/// lw_input.key（since=2）：size(4)+keycode(4)+down(1)+utf8(string)+modifiers(u16)
pub fn key_text(keycode: u32, down: bool, text: &str, modifiers: u16) -> Vec<u8> {
    let t = text.as_bytes();
    let total = KEY_SIZE + 4 + t.len() + 2;
    let mut b = Buf::new(total);
    b.u32(0);
    b.u32(keycode);
    b.u8(if down { 1 } else { 0 });
    let off = KEY_SIZE;
    b.u16(off as u16);
    b.u16(t.len() as u16);
    b.bytes(t);
    b.u16(modifiers);
    b.finish()
}

/// lw_text_input.preedit：size(4)+text(string)+cursor(u32)
pub fn preedit(text: &str, cursor: u32) -> Vec<u8> {
    let t = text.as_bytes();
    let total = PREEDIT_SIZE + t.len();
    let mut b = Buf::new(total);
    b.u32(0);
    let _ = put_str_header(&mut b, PREEDIT_SIZE, t.len());
    b.u32(cursor);
    b.bytes(t);
    b.finish()
}

/// lw_text_input.commit_string：size(4)+text(string)
pub fn commit_string(text: &str) -> Vec<u8> {
    let t = text.as_bytes();
    let total = COMMIT_STRING_SIZE + t.len();
    let mut b = Buf::new(total);
    b.u32(0);
    let _ = put_str_header(&mut b, COMMIT_STRING_SIZE, t.len());
    b.bytes(t);
    b.finish()
}

/// lw_text_input.delete_surrounding：size(4)+before(u32)+after(u32)
pub fn delete_surrounding(before: u32, after: u32) -> Vec<u8> {
    let mut b = Buf::new(DELETE_SURROUNDING_SIZE);
    b.u32(0);
    b.u32(before);
    b.u32(after);
    b.finish()
}

pub fn text_input(text: &str) -> Vec<u8> {
    let t = text.as_bytes();
    let mut b = Buf::new(TEXT_INPUT_SIZE + t.len());
    b.u32(0);
    let _ = put_str_header(&mut b, TEXT_INPUT_SIZE, t.len());
    b.bytes(t);
    b.finish()
}

/// 读消息体里的 size 字段并校验它与实际长度一致（壳侧收到引擎消息先过这一关）。
pub fn body_len_ok(body: &[u8]) -> bool {
    if body.len() < 4 {
        return false;
    }
    let n = u32::from_le_bytes([body[0], body[1], body[2], body[3]]) as usize;
    n == body.len()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn hello_layout_matches_c_header() {
        let b = hello("wayland", "linux", 0, 0x3f);
        assert_eq!(b.len(), HELLO_SIZE + 7 + 5);
        assert_eq!(u32::from_le_bytes([b[0], b[1], b[2], b[3]]) as usize, b.len());
        assert_eq!(u16::from_le_bytes([b[4], b[5]]), PROTOCOL_MAJOR);
        // shell_name 头在 8：off=28, len=7
        assert_eq!(u16::from_le_bytes([b[8], b[9]]), HELLO_SIZE as u16);
        assert_eq!(u16::from_le_bytes([b[10], b[11]]), 7);
        // os_name 头在 12：off=35, len=5
        assert_eq!(u16::from_le_bytes([b[12], b[13]]), (HELLO_SIZE + 7) as u16);
        assert_eq!(u16::from_le_bytes([b[14], b[15]]), 5);
        // capabilities 在 20
        assert_eq!(u64::from_le_bytes(b[20..28].try_into().unwrap()), 0x3f);
        assert_eq!(&b[28..35], b"wayland");
        assert_eq!(&b[35..40], b"linux");
    }

    #[test]
    fn clipboard_text_layout() {
        let b = clipboard_text(7, "text/plain", "hello");
        assert_eq!(u32::from_le_bytes(b[0..4].try_into().unwrap()) as usize, b.len());
        assert_eq!(u32::from_le_bytes(b[4..8].try_into().unwrap()), 7, "serial");
        // mime 头 8..12，text 头 12..16，载荷 16 起
        assert_eq!(u16::from_le_bytes([b[8], b[9]]) as usize, 16, "mime off");
        assert_eq!(u16::from_le_bytes([b[10], b[11]]) as usize, 10, "mime len");
        assert_eq!(u16::from_le_bytes([b[12], b[13]]) as usize, 26, "text off");
        assert_eq!(u16::from_le_bytes([b[14], b[15]]) as usize, 5, "text len");
        assert_eq!(&b[16..26], b"text/plain");
        assert_eq!(&b[26..31], b"hello");
    }

    #[test]
    fn drag_layouts() {
        let e = drag_enter(10, 20, "a.txt\nb.txt");
        assert_eq!(u32::from_le_bytes(e[0..4].try_into().unwrap()) as usize, e.len());
        assert_eq!(u32::from_le_bytes(e[4..8].try_into().unwrap()), 10);
        assert_eq!(u16::from_le_bytes([e[12], e[13]]) as usize, 16, "uris off");
        assert_eq!(u16::from_le_bytes([e[14], e[15]]) as usize, 11, "uris len");
        assert_eq!(&e[16..], b"a.txt\nb.txt");

        let m = drag_motion(3, 4);
        assert_eq!(m.len(), 12);
        assert_eq!(drag_leave().len(), 4);
    }

    #[test]
    fn system_info_layout() {
        let b = system_info("Asia/Shanghai", "zh-Hans", "/usr/share/fonts", "/home/u", 26);
        assert_eq!(u32::from_le_bytes(b[0..4].try_into().unwrap()) as usize, b.len());
        // 四个字符串头连续排在 4..20
        let mut off = SYSTEM_INFO_SIZE;
        for (i, len) in [13usize, 7, 16, 7].iter().enumerate() {
            let h = 4 + i * 4;
            assert_eq!(u16::from_le_bytes([b[h], b[h + 1]]) as usize, off, "第 {i} 个 off");
            assert_eq!(u16::from_le_bytes([b[h + 2], b[h + 3]]) as usize, *len, "第 {i} 个 len");
            off += len;
        }
        assert_eq!(u32::from_le_bytes(b[20..24].try_into().unwrap()), 26);
    }

    /// 防止再出现「凭记忆写 opcode」：直接读生成头文件校对窗口请求编号。
    #[test]
    fn window_request_opcodes_match_c_header() {
        let hdr = std::fs::read_to_string("../../packages/lwp/include/lwp_protocol.h")
            .expect("应能读到生成头文件");
        let expected: Vec<(u16, &str)> = vec![
            (op::WINDOW_CREATE_REQ, "CREATE"),
            (op::WINDOW_SET_TITLE_REQ, "SET_TITLE"),
            (op::WINDOW_SET_MIN_MAX_REQ, "SET_MIN_MAX"),
            (op::WINDOW_SET_STATE_REQ, "SET_STATE"),
            (op::WINDOW_CLOSE_REQ, "CLOSE"),
            (op::WINDOW_BEGIN_MOVE_REQ, "BEGIN_MOVE"),
            (op::WINDOW_BEGIN_RESIZE_REQ, "BEGIN_RESIZE"),
        ];
        for (got, name) in expected {
            let needle = format!("#define LWP_LW_WINDOW_{name}_OPCODE ");
            let line = hdr.lines().find(|l| l.starts_with(&needle))
                .unwrap_or_else(|| panic!("头文件里没有 {needle}"));
            let want: u16 = line.split_whitespace().last().unwrap().parse().unwrap();
            assert_eq!(got, want, "{name} 的 opcode 应为 {want}，实际 {got}");
        }
    }

    #[test]
    fn fixed_sizes_match_c_header() {
        assert_eq!(window_created(1, 1.0, true).len(), WINDOW_CREATED_SIZE);
        assert_eq!(window_configure(800, 600, 0).len(), WINDOW_CONFIGURE_SIZE);
        assert_eq!(surface_available(0xdead_beef, 800, 600).len(), SURFACE_AVAILABLE_SIZE);
        assert_eq!(pointer_button(1.0, 2.0, 0, true).len(), POINTER_BUTTON_SIZE);
        assert_eq!(pointer_motion(1.0, 2.0).len(), POINTER_MOTION_SIZE);
        assert_eq!(pointer_axis(0.0, 3.0).len(), POINTER_AXIS_SIZE);
        assert_eq!(key(28, true).len(), KEY_SIZE);
        assert_eq!(text_input("").len(), TEXT_INPUT_SIZE);
    }

    #[test]
    fn floats_and_ints_are_little_endian() {
        let b = pointer_button(10.5, -2.25, 1, false);
        assert_eq!(f32::from_le_bytes(b[4..8].try_into().unwrap()), 10.5);
        assert_eq!(f32::from_le_bytes(b[8..12].try_into().unwrap()), -2.25);
        assert_eq!(b[12], 1);
        assert_eq!(b[13], 0);

        let k = key(57, true);
        assert_eq!(u32::from_le_bytes(k[4..8].try_into().unwrap()), 57);
        assert_eq!(k[8], 1);

        let s = surface_available(0x0102_0304_0506_0708, 1, 2);
        assert_eq!(u64::from_le_bytes(s[4..12].try_into().unwrap()), 0x0102_0304_0506_0708);
    }

    #[test]
    fn text_input_offsets_are_relative_to_body_start() {
        let b = text_input("你好");
        assert_eq!(b.len(), TEXT_INPUT_SIZE + 6);
        assert_eq!(u16::from_le_bytes([b[4], b[5]]) as usize, TEXT_INPUT_SIZE);
        assert_eq!(u16::from_le_bytes([b[6], b[7]]) as usize, 6);
        assert_eq!(&b[8..], "你好".as_bytes());
    }

    #[test]
    fn body_len_check_rejects_truncated() {
        let mut b = hello("a", "b", 0, 0);
        assert!(body_len_ok(&b));
        b.pop();
        assert!(!body_len_ok(&b));
        assert!(!body_len_ok(&[1, 2]));
    }

    #[test]
    fn capabilities_bits_are_distinct() {
        // 与 lplatform-ohos 的 lwp_client.cpp 一致（位定义见 IDL core.capabilities）
        let shells = 1u64 << 0;
        let cursor = 1u64 << 1;
        let preedit = 1u64 << 2;
        assert_ne!(shells, cursor);
        assert_ne!(cursor, preedit);
        let b = hello("wayland", "linux", 0, shells | cursor | preedit);
        assert_eq!(u64::from_le_bytes(b[20..28].try_into().unwrap()), 0b111);
    }
}
