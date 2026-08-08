//! webview_native 单元测试(对照 todo.md 1.5)。

use super::*;
use std::ffi::CString;

const XHTML: &str = r#"<html><head><style>
body { background: #336699; margin: 0; padding: 20px; font-family: sans-serif; }
h1 { color: #ffffff; font-size: 24px; }
p { font-size: 14px; line-height: 1.8; }
.tall { height: 500px; background: #993333; margin-top: 300px; }
</style></head><body>
<h1>测试章节</h1>
<p>兰鹿阅读器 html 渲染内核测试文本。The quick brown fox.</p>
<div class="tall"></div>
<p>tail</p>
</body></html>"#;

/// 1x1 PNG(经典最小 PNG 字节序列)。
const TINY_PNG: &[u8] = &[
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
    0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x08, 0x02, 0x00, 0x00, 0x00, 0x90, 0x77, 0x53,
    0xDE, 0x00, 0x00, 0x00, 0x0C, 0x49, 0x44, 0x41, 0x54, 0x08, 0xD7, 0x63, 0xF8, 0xCF, 0xC0, 0x00,
    0x00, 0x00, 0x03, 0x00, 0x01, 0x5B, 0x9E, 0x2E, 0x48, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E,
    0x44, 0xAE, 0x42, 0x60, 0x82,
];

fn rgba_at(buf: &[u8], width: usize, x: usize, y: usize) -> [u8; 4] {
    let i = (y * width + x) * 4;
    [buf[i], buf[i + 1], buf[i + 2], buf[i + 3]]
}

#[test]
fn c_abi_handles_null_and_invalid_inputs() {
    unsafe {
        lanlu_wv_destroy(ptr::null_mut());
        assert_eq!(lanlu_wv_render(ptr::null_mut()), 0);
        assert_eq!(lanlu_wv_pending_count(ptr::null_mut()), 0);
        assert!(lanlu_wv_pending_url(ptr::null_mut(), 0).is_null());
        assert!(lanlu_wv_frame_ptr(ptr::null_mut()).is_null());
        assert_eq!(lanlu_wv_frame_width(ptr::null_mut()), 0);
        assert_eq!(lanlu_wv_scroll_y(ptr::null_mut()), 0.0);
        assert_eq!(lanlu_wv_content_height(ptr::null_mut()), 0.0);
        assert_eq!(lanlu_wv_scroll_by(ptr::null_mut(), 10.0), 0);

        let s = lanlu_wv_create(64, 64, 1.0);
        assert!(!s.is_null());
        // 未加载时各操作安全返回零值
        assert_eq!(lanlu_wv_render(s), 0);
        assert!(lanlu_wv_frame_ptr(s).is_null());
        assert_eq!(lanlu_wv_load_html(s, ptr::null(), 0, ptr::null()), -1);
        lanlu_wv_destroy(s);
        // 双 destroy(null)不应崩溃;悬垂指针双 destroy 属调用方 UB,不在防御范围。
        lanlu_wv_destroy(ptr::null_mut());
    }
}

#[test]
fn renders_colored_background_and_text() {
    unsafe {
        let s = lanlu_wv_create(400, 300, 1.0);
        let html = CString::new(XHTML).unwrap();
        let base = CString::new("https://example.com/book/ch1.xhtml").unwrap();
        assert_eq!(
            lanlu_wv_load_html(s, html.as_ptr() as *const u8, html.as_bytes().len(), base.as_ptr()),
            0
        );
        let g = lanlu_wv_render(s);
        assert!(g > 0, "首帧代际应前进");
        assert_eq!(lanlu_wv_frame_width(s), 400);
        assert_eq!(lanlu_wv_frame_height(s), 300);
        let frame = std::slice::from_raw_parts(lanlu_wv_frame_ptr(s), 400 * 300 * 4);
        // body 背景 #336699:四角应接近该色
        let corner = rgba_at(frame, 400, 5, 5);
        assert_eq!(corner, [0x33, 0x66, 0x99, 0xFF], "左上角应为 body 背景色");
        // 未 dirty 时 render 不前进
        assert_eq!(lanlu_wv_render(s), g);
        lanlu_wv_destroy(s);
    }
}

#[test]
fn content_height_and_scroll_with_clamp() {
    unsafe {
        let s = lanlu_wv_create(400, 300, 1.0);
        let html = CString::new(XHTML).unwrap();
        assert_eq!(lanlu_wv_load_html(s, html.as_ptr() as *const u8, html.as_bytes().len(), ptr::null()), 0);
        let _ = lanlu_wv_render(s);

        let content_h = lanlu_wv_content_height(s);
        assert!(content_h > 300.0, "内容高度应超过视口: {content_h}");

        let g0 = lanlu_wv_render(s);
        assert_eq!(lanlu_wv_scroll_by(s, 100.0), 1, "中段滚动应生效");
        assert!((lanlu_wv_scroll_y(s) - 100.0).abs() < 1.0);
        let g1 = lanlu_wv_render(s);
        assert!(g1 > g0, "滚动后帧代际应前进");

        // 滚到底:再滚 99999 应被 clamp,随后返回 0(到边界)
        assert_eq!(lanlu_wv_scroll_by(s, 99999.0), 1);
        let max_scroll = content_h - 300.0;
        assert!((lanlu_wv_scroll_y(s) - max_scroll).abs() < 1.0, "应 clamp 到内容底部");
        assert_eq!(lanlu_wv_scroll_by(s, 10.0), 0, "到底后应返回 0 供外溢翻页");
        // 分页右纸面允许页首越过普通上界，短末页剩余区域应保持空白而非回退重复。
        lanlu_wv_scroll_to_page(s, content_h + 100.0);
        assert!((lanlu_wv_scroll_y(s) - content_h - 100.0).abs() < 1.0);
        // 向上到顶同理
        assert_eq!(lanlu_wv_scroll_by(s, -99999.0), 1);
        assert_eq!(lanlu_wv_scroll_by(s, -10.0), 0, "到顶后应返回 0");
        assert!(lanlu_wv_scroll_y(s).abs() < 1.0);
        lanlu_wv_destroy(s);
    }
}

#[test]
fn resize_reallocates_framebuffer() {
    unsafe {
        let s = lanlu_wv_create(200, 150, 1.0);
        let html = CString::new(XHTML).unwrap();
        assert_eq!(lanlu_wv_load_html(s, html.as_ptr() as *const u8, html.as_bytes().len(), ptr::null()), 0);
        let _ = lanlu_wv_render(s);
        lanlu_wv_resize(s, 320, 240, 2.0);
        assert_eq!(lanlu_wv_frame_width(s), 320);
        assert_eq!(lanlu_wv_frame_height(s), 240);
        let g = lanlu_wv_render(s);
        assert!(g > 0);
        let frame = std::slice::from_raw_parts(lanlu_wv_frame_ptr(s), 320 * 240 * 4);
        assert_eq!(frame.len(), 320 * 240 * 4);
        lanlu_wv_destroy(s);
    }
}

#[test]
fn pending_resource_roundtrip() {
    unsafe {
        let html_str = r#"<html><body><img src="logo.png" width="64" height="64"/></body></html>"#;
        let s = lanlu_wv_create(200, 200, 1.0);
        let html = CString::new(html_str).unwrap();
        let base = CString::new("https://example.com/book/ch1.xhtml").unwrap();
        assert_eq!(lanlu_wv_load_html(s, html.as_ptr() as *const u8, html.as_bytes().len(), base.as_ptr()), 0);
        let _ = lanlu_wv_render(s);

        assert_eq!(lanlu_wv_pending_count(s), 1, "img 应产生一个待供数请求");
        let url = CStr::from_ptr(lanlu_wv_pending_url(s, 0)).to_str().unwrap().to_string();
        assert_eq!(url, "https://example.com/book/logo.png", "相对路径应基于 base_url 解析");

        let c_url = CString::new(url.clone()).unwrap();
        assert_eq!(lanlu_wv_provide_resource(s, c_url.as_ptr(), TINY_PNG.as_ptr(), TINY_PNG.len()), 1);
        assert_eq!(lanlu_wv_pending_count(s), 0, "消费后队列应清空");
        // 重复/未知 URL 幂等忽略
        assert_eq!(lanlu_wv_provide_resource(s, c_url.as_ptr(), TINY_PNG.as_ptr(), TINY_PNG.len()), 0);
        let g = lanlu_wv_render(s);
        assert!(g > 0, "供数后应可重渲染");
        lanlu_wv_destroy(s);
    }
}

#[test]
fn theme_css_takes_effect() {
    unsafe {
        let s = lanlu_wv_create(100, 100, 1.0);
        let html = CString::new("<html><body>themed</body></html>").unwrap();
        assert_eq!(lanlu_wv_load_html(s, html.as_ptr() as *const u8, html.as_bytes().len(), ptr::null()), 0);
        let css = CString::new("body { background: #ff0000; }").unwrap();
        lanlu_wv_set_theme_css(s, css.as_ptr() as *const u8, css.as_bytes().len());
        let g = lanlu_wv_render(s);
        assert!(g > 0);
        let frame = std::slice::from_raw_parts(lanlu_wv_frame_ptr(s), 100 * 100 * 4);
        let corner = rgba_at(frame, 100, 2, 2);
        assert_eq!(corner[0], 0xFF, "主题 CSS 应把背景变红");
        assert_eq!(corner[1], 0x00);
        lanlu_wv_destroy(s);
    }
}

#[test]
fn theme_css_set_before_load_takes_effect() {
    unsafe {
        let s = lanlu_wv_create(600, 300, 1.0);
        let css = CString::new("body { background: #ff0000 !important; }").unwrap();
        lanlu_wv_set_theme_css(s, css.as_ptr() as *const u8, css.as_bytes().len());
        let html = CString::new(XHTML).unwrap();
        assert_eq!(lanlu_wv_load_html(s, html.as_ptr() as *const u8, html.as_bytes().len(), ptr::null()), 0);
        let _ = lanlu_wv_render(s);

        let frame = std::slice::from_raw_parts(lanlu_wv_frame_ptr(s), 600 * 300 * 4);
        let corner = rgba_at(frame, 600, 2, 2);
        assert_eq!(corner[0], 0xFF, "加载前设置的主题 CSS 应保留到文档创建后");
        assert_eq!(corner[1], 0x00);
        lanlu_wv_destroy(s);
    }
}
