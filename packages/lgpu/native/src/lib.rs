//! L 层渲染器的原生实现（wgpu → Vulkan → VK_OHOS_surface）。
//!
//! 约束（与 webview_native / fontkit_native 一致）：
//! - 只导出 **C ABI**，句柄不透明，绝不跨语言传 GC 指针；
//! - 失败返回负错误码，错误文本用线程局部保存，`lgpu_last_error()` 取回。
//!
//! 本文件当前是 P2 的第一块：实例创建 + 适配器枚举 + surface 创建。
//! 管线/绘制在后续加入（见 docs/l-layer-plan）。

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
        Ok(surface) => Box::into_raw(Box::new(surface)) as *mut c_void,
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
    drop(unsafe { Box::from_raw(surface as *mut wgpu::Surface<'static>) });
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
