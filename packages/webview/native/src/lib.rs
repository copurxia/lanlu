//! webview_native C ABI 出口。
//!
//! 契约(与 packages/fontkit_ffi 同款风格):
//! - 句柄为不透明指针 *mut WvSession,lanlu_wv_create 返回,lanlu_wv_destroy 释放;
//! - 所有函数 catch_unwind 包裹 + null/无效入参防御,失败返回零值/null;
//! - 单线程约定:调用方必须在同一线程(UI 线程)使用同一句柄;
//! - 帧指针(lanlu_wv_frame_ptr)为会话内部缓冲借用,仅在下一次可能改帧的
//!   调用(lanlu_wv_render/load/resize/scroll/provide/set_theme)之前有效,
//!   调用方需同步拷贝(与 libvlc_ffi VideoFrame 借用语义一致)。

use std::ffi::{CStr, c_char};
use std::panic::{AssertUnwindSafe, catch_unwind};
use std::ptr;

mod session;
use session::WvSession;

/// 诊断日志（低频关键路径用；stderr 直写，崩溃前最后一行即断点）。
pub(crate) fn wvlog(args: std::fmt::Arguments) {
    use std::io::Write;
    let _ = writeln!(std::io::stderr(), "{}", args);
}

#[macro_export]
macro_rules! wvlog {
    ($($arg:tt)*) => { $crate::wvlog(format_args!($($arg)*)) }
}

/// 把 (ptr, len) 转成字节切片;null/长度异常时返回 None。
unsafe fn byte_slice<'a>(ptr: *const u8, len: usize) -> Option<&'a [u8]> {
    if ptr.is_null() || len == 0 {
        return None;
    }
    Some(unsafe { std::slice::from_raw_parts(ptr, len) })
}

unsafe fn as_session<'a>(s: *mut WvSession) -> Option<&'a mut WvSession> {
    if s.is_null() {
        return None;
    }
    Some(unsafe { &mut *s })
}

/// 创建离屏会话(width/height 为物理像素,scale 为 DPI 缩放)。失败返回 null。
#[unsafe(no_mangle)]
pub extern "C" fn lanlu_wv_create(width: u32, height: u32, scale: f32) -> *mut WvSession {
    wvlog!("[wv] lanlu_wv_create enter w={} h={} scale={}", width, height, scale);
    let p = catch_unwind(AssertUnwindSafe(|| Box::into_raw(Box::new(WvSession::new(width, height, scale)))))
        .unwrap_or(ptr::null_mut());
    wvlog!("[wv] lanlu_wv_create exit p={:p}", p);
    p
}

/// 释放会话;null 容忍。
#[unsafe(no_mangle)]
/// # Safety
/// `s` must be null or a live pointer returned by `lanlu_wv_create` that has not been destroyed.
pub unsafe extern "C" fn lanlu_wv_destroy(s: *mut WvSession) {
    if !s.is_null() {
        let _ = catch_unwind(AssertUnwindSafe(|| unsafe { drop(Box::from_raw(s)) }));
    }
}

/// 预热进程级共享字体上下文（幂等；应用启动早期调用一次）。
/// 把 fontique 系统字体扫描（FcConfigBuildFonts，最慢最深原生调用）提前到
/// GC 未活跃、主线程浅栈的启动阶段，避免 loadHtml 时出现长原生停留窗口。
/// 返回 0 表示成功（或已预热）；load_html 内部另有 get_or_init 兜底。
#[unsafe(no_mangle)]
pub extern "C" fn lanlu_wv_warmup() -> i32 {
    let rc = catch_unwind(AssertUnwindSafe(|| {
        let _ = session::ensure_font_ctx();
    }));
    if rc.is_ok() {
        wvlog!("[wv] lanlu_wv_warmup ok");
        0
    } else {
        wvlog!("[wv] lanlu_wv_warmup failed (panic)");
        -1
    }
}

/// 加载 HTML 字节(base_url 用于相对路径解析)。0 成功,-1 失败。
#[unsafe(no_mangle)]
/// # Safety
/// `s` must be a live session; `html` must point to `html_len` valid bytes.
pub unsafe extern "C" fn lanlu_wv_load_html(
    s: *mut WvSession,
    html: *const u8,
    html_len: usize,
    base_url: *const c_char,
) -> i32 {
    wvlog!("[wv] lanlu_wv_load_html enter s={:p} len={} base={:?}", s, html_len, {
        if base_url.is_null() { "".to_string() } else { unsafe { CStr::from_ptr(base_url) }.to_string_lossy().into_owned() }
    });
    let run = || -> Option<i32> {
        let session = unsafe { as_session(s) }?;
        let bytes = unsafe { byte_slice(html, html_len) }?;
        let html_str = std::str::from_utf8(bytes).ok()?;
        let base = if base_url.is_null() {
            ""
        } else {
            unsafe { CStr::from_ptr(base_url) }.to_str().unwrap_or("")
        };
        Some(if session.load_html(html_str, base) { 0 } else { -1 })
    };
    let rc = catch_unwind(AssertUnwindSafe(run)).ok().flatten().unwrap_or(-1);
    wvlog!("[wv] lanlu_wv_load_html exit rc={}", rc);
    rc
}

/// 调整视口(物理像素)与 DPI scale;尺寸未变时 no-op。
#[unsafe(no_mangle)]
/// # Safety
/// `s` must be a live session.
pub unsafe extern "C" fn lanlu_wv_resize(s: *mut WvSession, width: u32, height: u32, scale: f32) {
    let _ = catch_unwind(AssertUnwindSafe(|| {
        if let Some(session) = unsafe { as_session(s) } {
            session.resize(width, height, scale);
        }
    }));
}

/// 向下滚动 dy 像素(正数向下)。返回 1 发生滚动,0 到边界或未加载。
#[unsafe(no_mangle)]
/// # Safety
/// `s` must be a live session.
pub unsafe extern "C" fn lanlu_wv_scroll_by(s: *mut WvSession, dy: f32) -> i32 {
    let run = || -> Option<i32> {
        let session = unsafe { as_session(s) }?;
        Some(if session.scroll_by(dy) { 1 } else { 0 })
    };
    catch_unwind(AssertUnwindSafe(run)).ok().flatten().unwrap_or(0)
}

/// 绝对滚动到 y(内部 clamp 到 [0, content_height - viewport])。
#[unsafe(no_mangle)]
/// # Safety
/// `s` must be a live session.
pub unsafe extern "C" fn lanlu_wv_scroll_to(s: *mut WvSession, y: f32) {
    let _ = catch_unwind(AssertUnwindSafe(|| {
        if let Some(session) = unsafe { as_session(s) } {
            session.scroll_to(y);
        }
    }));
}

/// 分页副视口绝对定位到 y，不钳制内容底部；仅供双页右纸面渲染末页空白。
#[unsafe(no_mangle)]
/// # Safety
/// `s` must be a live session.
pub unsafe extern "C" fn lanlu_wv_scroll_to_page(s: *mut WvSession, y: f32) {
    let _ = catch_unwind(AssertUnwindSafe(|| {
        if let Some(session) = unsafe { as_session(s) } {
            session.scroll_to_page(y);
        }
    }));
}

/// 当前滚动偏移(逻辑像素)。未加载返回 0。
#[unsafe(no_mangle)]
/// # Safety
/// `s` must be null or a live session.
pub unsafe extern "C" fn lanlu_wv_scroll_y(s: *mut WvSession) -> f32 {
    let run = || -> Option<f32> { unsafe { as_session(s) }.map(|session| session.scroll_y()) };
    catch_unwind(AssertUnwindSafe(run)).ok().flatten().unwrap_or(0.0)
}

/// 内容总高(逻辑像素)。未加载返回 0。
#[unsafe(no_mangle)]
/// # Safety
/// `s` must be null or a live session.
pub unsafe extern "C" fn lanlu_wv_content_height(s: *mut WvSession) -> f32 {
    let run = || -> Option<f32> { unsafe { as_session(s) }.map(|session| session.content_height()) };
    catch_unwind(AssertUnwindSafe(run)).ok().flatten().unwrap_or(0.0)
}

/// 把目标分页位置回退到完整文本行/图片之前，避免下一纸面从半行开始。
#[unsafe(no_mangle)]
/// # Safety
/// `s` must be null or a live session.
pub unsafe extern "C" fn lanlu_wv_page_break_before(s: *mut WvSession, target_y: f32) -> f32 {
    let run = || -> Option<f32> {
        unsafe { as_session(s) }.map(|session| session.page_break_before(target_y))
    };
    catch_unwind(AssertUnwindSafe(run)).ok().flatten().unwrap_or(target_y.max(0.0))
}

/// 注入/替换 UA 级主题 CSS(深浅色)。
#[unsafe(no_mangle)]
/// # Safety
/// `s` must be a live session; `css` must point to `css_len` valid UTF-8 bytes.
pub unsafe extern "C" fn lanlu_wv_set_theme_css(s: *mut WvSession, css: *const u8, css_len: usize) {
    let _ = catch_unwind(AssertUnwindSafe(|| {
        let Some(session) = (unsafe { as_session(s) }) else { return };
        let Some(bytes) = (unsafe { byte_slice(css, css_len) }) else { return };
        let Some(css_str) = std::str::from_utf8(bytes).ok() else { return };
        session.set_theme_css(css_str);
    }));
}

/// 回填子资源字节;URL 不在 pending 队列时忽略。返回 1 命中,0 未命中。
#[unsafe(no_mangle)]
/// # Safety
/// `s` must be a live session; `url` must be a valid C string;
/// `bytes` must point to `bytes_len` valid bytes.
pub unsafe extern "C" fn lanlu_wv_provide_resource(
    s: *mut WvSession,
    url: *const c_char,
    bytes: *const u8,
    bytes_len: usize,
) -> i32 {
    let run = || -> Option<i32> {
        let session = unsafe { as_session(s) }?;
        if url.is_null() {
            return Some(0);
        }
        let url_str = unsafe { CStr::from_ptr(url) }.to_str().ok()?;
        let data = unsafe { byte_slice(bytes, bytes_len) }?;
        Some(if session.provide_resource(url_str, data) { 1 } else { 0 })
    };
    catch_unwind(AssertUnwindSafe(run)).ok().flatten().unwrap_or(0)
}

/// 待供数子资源数量(外部需逐个拉取后经 provide_resource 回填)。
#[unsafe(no_mangle)]
/// # Safety
/// `s` must be null or a live session.
pub unsafe extern "C" fn lanlu_wv_pending_count(s: *mut WvSession) -> usize {
    let run = || -> Option<usize> { unsafe { as_session(s) }.map(|session| session.pending_count()) };
    catch_unwind(AssertUnwindSafe(run)).ok().flatten().unwrap_or(0)
}

/// 第 index 个待供数资源的 URL(C 字符串)。
/// 指针有效期:到该资源被 provide_resource 消费或下一次 load_html 为止。
#[unsafe(no_mangle)]
/// # Safety
/// `s` must be null or a live session.
pub unsafe extern "C" fn lanlu_wv_pending_url(s: *mut WvSession, index: usize) -> *const c_char {
    let run = || -> *const c_char {
        unsafe { as_session(s) }.map_or(ptr::null(), |session| session.pending_url_ptr(index))
    };
    catch_unwind(AssertUnwindSafe(run)).unwrap_or(ptr::null())
}

/// 渲染一帧。dirty 才重排/重光栅;返回帧代际(未加载返回 0)。
#[unsafe(no_mangle)]
/// # Safety
/// `s` must be null or a live session.
pub unsafe extern "C" fn lanlu_wv_render(s: *mut WvSession) -> u64 {
    let run = || -> Option<u64> { unsafe { as_session(s) }.map(|session| session.render()) };
    catch_unwind(AssertUnwindSafe(run)).ok().flatten().unwrap_or(0)
}

/// 借用帧 RGBA 缓冲(尺寸 = 视口物理像素)。未渲染/未加载返回 null。
#[unsafe(no_mangle)]
/// # Safety
/// `s` must be null or a live session.
pub unsafe extern "C" fn lanlu_wv_frame_ptr(s: *mut WvSession) -> *const u8 {
    let run = || -> *const u8 {
        unsafe { as_session(s) }.map_or(ptr::null(), |session| {
            if session.frame_width() == 0 { ptr::null() } else { session.frame_ptr() }
        })
    };
    catch_unwind(AssertUnwindSafe(run)).unwrap_or(ptr::null())
}

/// 帧宽(物理像素)。
#[unsafe(no_mangle)]
/// # Safety
/// `s` must be null or a live session.
pub unsafe extern "C" fn lanlu_wv_frame_width(s: *mut WvSession) -> u32 {
    let run = || -> Option<u32> { unsafe { as_session(s) }.map(|session| session.frame_width()) };
    catch_unwind(AssertUnwindSafe(run)).ok().flatten().unwrap_or(0)
}

/// 帧高(物理像素)。
#[unsafe(no_mangle)]
/// # Safety
/// `s` must be null or a live session.
pub unsafe extern "C" fn lanlu_wv_frame_height(s: *mut WvSession) -> u32 {
    let run = || -> Option<u32> { unsafe { as_session(s) }.map(|session| session.frame_height()) };
    catch_unwind(AssertUnwindSafe(run)).ok().flatten().unwrap_or(0)
}

#[cfg(test)]
mod tests;
