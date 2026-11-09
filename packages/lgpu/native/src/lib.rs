//! L 层渲染器的原生实现（wgpu）。
//!
//! 设计约束（与项目内其它 Rust 库一致：webview_native / fontkit_native）：
//! - 导出 **C ABI**，只传不透明句柄与 POD 结构，绝不跨语言传 GC 指针。
//! - 所有入口都返回错误码，错误文本用线程局部保存，由 `lgpu_last_error()` 取回。
//!
//! P0 阶段只有版本/错误两个入口，用于验证构建与链接链路。

use std::cell::RefCell;
use std::ffi::{c_char, CString};

const VERSION: &str = concat!("lgpu ", env!("CARGO_PKG_VERSION"), " (wgpu pending)");

thread_local! {
    static LAST_ERROR: RefCell<Option<CString>> = const { RefCell::new(None) };
}

fn set_error(msg: impl Into<String>) {
    let s = msg.into();
    LAST_ERROR.with(|e| {
        *e.borrow_mut() = CString::new(s).ok();
    });
}

/// 版本字符串（UTF-8, NUL 结尾）。指针在进程生命周期内有效。
#[no_mangle]
pub extern "C" fn lgpu_version() -> *const c_char {
    thread_local! {
        static VERSION_C: CString = CString::new(VERSION).unwrap();
    }
    VERSION_C.with(|v| v.as_ptr())
}

/// 最近一次失败的原因；无错误时返回空串。指针在下一次调用前有效。
#[no_mangle]
pub extern "C" fn lgpu_last_error() -> *const c_char {
    thread_local! {
        static EMPTY: CString = CString::new("").unwrap();
    }
    LAST_ERROR.with(|e| match e.borrow().as_ref() {
        Some(c) => c.as_ptr(),
        None => EMPTY.with(|m| m.as_ptr()),
    })
}

/// 自检入口：返回 0 表示库可用。Cangjie 侧用它确认静态库真的链进来了。
#[no_mangle]
pub extern "C" fn lgpu_self_check() -> i32 {
    if VERSION.is_empty() {
        set_error("empty version");
        return -1;
    }
    0
}
