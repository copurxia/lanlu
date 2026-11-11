//! liblwp_native.so 的最小 Rust 绑定（计划 §5.2）。
//!
//! 边界原则与仓颉绑定一致：**只传标量与字节缓冲**，不跨 FFI 传结构体。
//! 这里是壳侧（Wayland 桌面端）用的那一半。

use std::ffi::{c_char, c_int, c_void, CString};
use std::sync::OnceLock;

pub const LWP_REQUEST: c_int = 0;
pub const LWP_EVENT: c_int = 1;

pub const LWP_OK: c_int = 0;
pub const LWP_EAGAIN: c_int = -11;
pub const LWP_EMSGSIZE: c_int = -90;

pub const LWP_F_BLOB: u32 = 1;
pub const LWP_F_DROPPABLE: u32 = 2;
pub const LWP_INLINE_MAX: usize = 320;

/// 与 `packages/lwp/include/lwp.h` 保持一致的公开 ABI。
#[allow(dead_code)]
mod ffi {
    use super::*;
    extern "C" {
        pub fn lwp_open(name: *const c_char, slots: u32, out: *mut *mut c_void) -> c_int;
        pub fn lwp_close(ch: *mut c_void);
        pub fn lwp_send_parts(
            ch: *mut c_void,
            dir: c_int,
            iface: u16,
            opcode: u16,
            flags: u32,
            body: *const u8,
            len: u32,
        ) -> c_int;
        pub fn lwp_recv_parts(
            ch: *mut c_void,
            dir: c_int,
            iface: *mut u16,
            opcode: *mut u16,
            flags: *mut u32,
            time_ns: *mut u64,
            body: *mut u8,
            cap: u32,
            out_len: *mut u32,
        ) -> c_int;
        pub fn lwp_wait(ch: *mut c_void, dir: c_int, timeout_ms: c_int) -> c_int;
        pub fn lwp_wake(ch: *mut c_void, dir: c_int) -> c_int;
        pub fn lwp_checker_enable(ch: *mut c_void, strict: c_int) -> c_int;
        pub fn lwp_trace_open(ch: *mut c_void, path: *const c_char) -> c_int;
        pub fn lwp_trace_close(ch: *mut c_void);
        pub fn lwp_now_ns() -> u64;
        pub fn lwp_stats_summary(ch: *mut c_void, out: *mut c_char, cap: u32) -> c_int;
    }
}

/// 一条收到的协议消息。
#[derive(Debug, Clone)]
pub struct Message {
    pub iface: u16,
    pub opcode: u16,
    pub flags: u32,
    pub time_ns: u64,
    pub body: Vec<u8>,
}

/// 通道句柄（进程内单例，名字相同则复用）。
pub struct Channel {
    raw: *mut c_void,
}

// 通道本身是线程安全的（C 侧用原子量 + eventfd），但裸指针默认不是 Send。
unsafe impl Send for Channel {}

impl Channel {
    pub fn open(name: &str, slots: u32) -> Result<Self, String> {
        let cname = CString::new(name).map_err(|e| format!("name: {e}"))?;
        let mut raw: *mut c_void = std::ptr::null_mut();
        let rc = unsafe { ffi::lwp_open(cname.as_ptr(), slots, &mut raw) };
        if rc != LWP_OK || raw.is_null() {
            return Err(format!("lwp_open({name}) rc={rc}"));
        }
        Ok(Self { raw })
    }

    pub fn send(&self, dir: c_int, iface: u16, opcode: u16, flags: u32, body: &[u8]) -> c_int {
        let (ptr, len) = if body.is_empty() {
            (std::ptr::null(), 0)
        } else {
            (body.as_ptr(), body.len() as u32)
        };
        unsafe { ffi::lwp_send_parts(self.raw, dir, iface, opcode, flags, ptr, len) }
    }

    /// 非阻塞收一条；队列空返回 None。
    pub fn recv(&self, dir: c_int) -> Option<Message> {
        let mut buf = vec![0u8; LWP_INLINE_MAX];
        let (mut iface, mut opcode, mut flags, mut time_ns) = (0u16, 0u16, 0u32, 0u64);
        let mut out_len = 0u32;
        let rc = unsafe {
            ffi::lwp_recv_parts(
                self.raw,
                dir,
                &mut iface,
                &mut opcode,
                &mut flags,
                &mut time_ns,
                buf.as_mut_ptr(),
                LWP_INLINE_MAX as u32,
                &mut out_len,
            )
        };
        if rc != LWP_OK {
            return None;
        }
        buf.truncate(out_len as usize);
        Some(Message { iface, opcode, flags, time_ns, body: buf })
    }

    /// 睡眠等待（毫秒）。返回 true 表示可能有数据。
    pub fn wait(&self, dir: c_int, timeout_ms: c_int) -> bool {
        (unsafe { ffi::lwp_wait(self.raw, dir, timeout_ms) }) == LWP_OK
    }

    pub fn wake(&self, dir: c_int) {
        unsafe {
            ffi::lwp_wake(self.raw, dir);
        }
    }

    pub fn enable_checker(&self, strict: bool) {
        unsafe {
            ffi::lwp_checker_enable(self.raw, if strict { 1 } else { 0 });
        }
    }

    pub fn trace_open(&self, path: &str) -> bool {
        match CString::new(path) {
            Ok(p) => unsafe { ffi::lwp_trace_open(self.raw, p.as_ptr()) == LWP_OK },
            Err(_) => false,
        }
    }

    pub fn trace_close(&self) {
        unsafe { ffi::lwp_trace_close(self.raw) }
    }

    pub fn stats(&self) -> String {
        let mut buf = vec![0i8; 256];
        let n = unsafe { ffi::lwp_stats_summary(self.raw, buf.as_mut_ptr(), buf.len() as u32) };
        if n <= 0 {
            return String::new();
        }
        let bytes: Vec<u8> = buf[..n as usize].iter().map(|&c| c as u8).collect();
        String::from_utf8_lossy(&bytes).into_owned()
    }
}

impl Drop for Channel {
    fn drop(&mut self) {
        unsafe { ffi::lwp_close(self.raw) }
    }
}

pub fn now_ns() -> u64 {
    unsafe { ffi::lwp_now_ns() }
}

/// 记录一次进程级「协议是否可用」（与 C 侧 `lanlu_lwp_ready()` 语义一致）。
static READY: OnceLock<bool> = OnceLock::new();

pub fn mark_ready(v: bool) {
    let _ = READY.set(v);
}

pub fn is_ready() -> bool {
    *READY.get().unwrap_or(&false)
}
