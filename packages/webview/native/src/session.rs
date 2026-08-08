//! WvSession: Blitz 离屏 HTML 渲染会话。
//!
//! 架构约定(与 todo.md M1 一致):
//! - 单线程访问(调用方 UI 线程),布局/光栅同步执行;
//! - framebuffer 恒等于视口物理像素,滚动经 viewport_scroll 实现,
//!   光栅只出视口窗口,长章节内存恒定;
//! - 网络资源不经本 crate:NetProvider 只把请求收进 pending 队列,
//!   由仓颉侧拉取字节后经 provide_resource 注入(NetHandler::bytes)。

use std::ffi::CString;
use std::sync::{Arc, Mutex, OnceLock};

use anyrender::{PaintScene as _, render_to_buffer};
use anyrender_vello_cpu::VelloCpuImageRenderer;
use blitz_dom::{DocumentConfig, Point, util::Color};
use blitz_html::HtmlDocument;
use blitz_paint::paint_scene;
use blitz_traits::net::{Bytes, NetHandler, NetProvider, Request};
use blitz_traits::shell::{ColorScheme, Viewport};
use parley::fontique::{Collection, CollectionOptions, SourceCache};
use parley::FontContext;
use peniko::Fill;
use peniko::kurbo::Rect;

/// 进程级共享字体上下文：系统字体发现（fontique → fontconfig）只在首次调用
/// 时执行一次（FcConfigBuildFonts 是全流程最慢、最深的原生调用，也是 GC 栈
/// 扫描崩溃的主要风险窗口）。单线程契约下初始化后只读 clone，无需锁。
/// 应用在启动早期经 lanlu_wv_warmup 预热；load_html 兜底 get_or_init。
static FONT_CTX: OnceLock<FontContext> = OnceLock::new();

/// 获取共享字体上下文（幂等；首次调用触发系统字体扫描）。
pub fn ensure_font_ctx() -> &'static FontContext {
    FONT_CTX.get_or_init(|| {
        crate::wvlog!("[wv:session] building shared FontContext (system font scan)");
        FontContext {
            source_cache: SourceCache::new_shared(),
            collection: Collection::new(CollectionOptions {
                shared: false,
                system_fonts: true,
            }),
        }
    })
}

/// 一次待外部供数的资源请求(url 用于匹配,handler 用于回填字节)。
struct PendingFetch {
    url: String,
    /// pending_url 返回的指针来源;与 url 同生命周期。
    c_url: CString,
    handler: Box<dyn NetHandler>,
}

/// 共享的待供数队列:NetProvider::fetch 在 resolve 期间写入,
/// C ABI 侧读取/消费。
#[derive(Default, Clone)]
pub struct PendingQueue(Arc<Mutex<Vec<PendingFetch>>>);

impl NetProvider for PendingQueue {
    fn fetch(&self, _doc_id: usize, request: Request, handler: Box<dyn NetHandler>) {
        let url = request.url.to_string();
        let mut queue = self.0.lock().expect("pending queue poisoned");
        // 同一 URL 只保留首个请求(重复 <img> 引用等);重复 handler 直接丢弃。
        if queue.iter().any(|pending| pending.url == url) {
            return;
        }
        let c_url = CString::new(url.replace('\0', "")).expect("NUL removed");
        queue.push(PendingFetch { url, c_url, handler });
    }
}

impl PendingQueue {
    pub fn len(&self) -> usize {
        self.0.lock().expect("pending queue poisoned").len()
    }

    pub fn url_ptr(&self, index: usize) -> *const i8 {
        let queue = self.0.lock().expect("pending queue poisoned");
        queue
            .get(index)
            .map_or(std::ptr::null(), |pending| pending.c_url.as_ptr())
    }

    /// 按 URL 取出 handler;未命中返回 false。
    pub fn take_handler(&self, url: &str) -> Option<Box<dyn NetHandler>> {
        let mut queue = self.0.lock().expect("pending queue poisoned");
        let pos = queue.iter().position(|pending| pending.url == url)?;
        Some(queue.remove(pos).handler)
    }
}

/// 离屏 HTML 渲染会话。所有方法假定单线程调用。
pub struct WvSession {
    doc: Option<HtmlDocument>,
    net: PendingQueue,
    width: u32,
    height: u32,
    scale: f32,
    generation: u64,
    dirty: bool,
    theme_css: Option<String>,
    framebuffer: Vec<u8>,
}

impl WvSession {
    pub fn new(width: u32, height: u32, scale: f32) -> Self {
        let (width, height) = (width.max(1), height.max(1));
        let scale = if scale > 0.0 { scale } else { 1.0 };
        Self {
            doc: None,
            net: PendingQueue::default(),
            width,
            height,
            scale,
            generation: 0,
            dirty: false,
            theme_css: None,
            framebuffer: vec![0u8; (width * height * 4) as usize],
        }
    }

    fn viewport(&self) -> Viewport {
        Viewport::new(self.width, self.height, self.scale, ColorScheme::Light)
    }

    /// 加载 HTML(替换已有文档)。base_url 用于相对路径解析。
    pub fn load_html(&mut self, html: &str, base_url: &str) -> bool {
        crate::wvlog!("[wv:session] load_html enter len={} base={}", html.len(), base_url);
        // 旧文档的待供数请求随旧文档作废,先清空队列(新文档共享同一队列)。
        self.net.0.lock().expect("pending queue poisoned").clear();
        // 复用进程级共享字体上下文：避免 from_html 内部重建 SystemFonts
        //（FcConfigBuildFonts 慢初始化集中到启动预热，不再出现长原生窗口）。
        let font_ctx = ensure_font_ctx().clone();
        let config = DocumentConfig {
            base_url: if base_url.is_empty() { None } else { Some(base_url.to_string()) },
            net_provider: Some(Arc::new(self.net.clone()) as _),
            viewport: Some(self.viewport()),
            font_ctx: Some(font_ctx),
            ..Default::default()
        };
        // 主题样式需要在文档创建后注入,先把旧主题记着。
        let theme = self.theme_css.take();
        crate::wvlog!("[wv:session] load_html before from_html");
        let mut doc = HtmlDocument::from_html(html, config);
        crate::wvlog!("[wv:session] load_html after from_html");
        if let Some(css) = theme {
            doc.as_mut().add_user_agent_stylesheet(&css);
            self.theme_css = Some(css);
        }
        crate::wvlog!("[wv:session] load_html before resolve");
        doc.as_mut().resolve(0.0);
        crate::wvlog!("[wv:session] load_html after resolve");
        self.doc = Some(doc);
        self.dirty = true;
        true
    }

    pub fn resize(&mut self, width: u32, height: u32, scale: f32) {
        let width = width.max(1);
        let height = height.max(1);
        let scale = if scale > 0.0 { scale } else { 1.0 };
        if width == self.width && height == self.height && (scale - self.scale).abs() < f32::EPSILON {
            return;
        }
        self.width = width;
        self.height = height;
        self.scale = scale;
        self.framebuffer = vec![0u8; (width * height * 4) as usize];
        let vp = self.viewport();
        if let Some(doc) = &mut self.doc {
            doc.as_mut().set_viewport(vp);
            doc.as_mut().resolve(0.0);
        }
        self.dirty = true;
    }

    /// 向下为正。返回是否发生滚动(到边界时返回 false,供调用方外溢翻页)。
    pub fn scroll_by(&mut self, dy: f32) -> bool {
        let Some(doc) = &mut self.doc else { return false };
        // blitz 内部 new_scroll = scroll - y,向下滚动(增大 scroll.y)需传负值。
        let changed = doc.as_mut().scroll_viewport_by_has_changed(0.0, -(dy as f64));
        if changed {
            self.dirty = true;
        }
        changed
    }

    pub fn scroll_to(&mut self, y: f32) {
        let delta = y - self.scroll_y();
        if delta.abs() > f32::EPSILON {
            self.scroll_by(delta);
        }
    }

    /// 分页副视口定位：允许页首超过普通滚动上界，使末页不足一屏时余部为空白，
    /// 而不是被 clamp 后与左页重复。仅供只读的双页右纸面使用。
    pub fn scroll_to_page(&mut self, y: f32) {
        let Some(doc) = &mut self.doc else { return };
        let current = doc.as_ref().viewport_scroll();
        let next = Point { x: current.x, y: y.max(0.0) as f64 };
        if next != current {
            doc.as_mut().set_viewport_scroll(next);
            self.dirty = true;
        }
    }

    pub fn scroll_y(&self) -> f32 {
        self.doc
            .as_ref()
            .map_or(0.0, |doc| doc.as_ref().viewport_scroll().y as f32)
    }

    /// 内容总高(含溢出),与 blitz 内部 clamp 上界口径一致。
    pub fn content_height(&self) -> f32 {
        let Some(doc) = &self.doc else { return 0.0 };
        let layout = &doc.as_ref().root_element().final_layout;
        layout.size.height.max(layout.content_size.height)
    }

    /// 注入 UA 级主题 CSS(深浅色);替换式:先移除旧的再添加。
    pub fn set_theme_css(&mut self, css: &str) {
        if let Some(doc) = &mut self.doc {
            if let Some(old) = &self.theme_css {
                doc.as_mut().remove_user_agent_stylesheet(old);
            }
            doc.as_mut().add_user_agent_stylesheet(css);
            doc.as_mut().resolve(0.0);
            self.dirty = true;
        }
        self.theme_css = Some(css.to_string());
    }

    /// 回填子资源字节;URL 不在 pending 队列时忽略(幂等)。
    pub fn provide_resource(&mut self, url: &str, bytes: &[u8]) -> bool {
        let Some(handler) = self.net.take_handler(url) else { return false };
        handler.bytes(url.to_string(), Bytes::copy_from_slice(bytes));
        self.dirty = true;
        true
    }

    pub fn pending_count(&self) -> usize {
        self.net.len()
    }

    pub fn pending_url_ptr(&self, index: usize) -> *const i8 {
        self.net.url_ptr(index)
    }

    /// dirty 才重排/重光栅;返回帧代际。
    pub fn render(&mut self) -> u64 {
        if !self.dirty {
            return self.generation;
        }
        if let Some(doc) = &mut self.doc {
            doc.as_mut().resolve(0.0);
            let buffer = render_to_buffer::<VelloCpuImageRenderer, _>(
                |scene| {
                    scene.fill(
                        Fill::NonZero,
                        Default::default(),
                        Color::WHITE,
                        Default::default(),
                        &Rect::new(0.0, 0.0, self.width as f64, self.height as f64),
                    );
                    paint_scene(scene, doc.as_mut(), self.scale as f64, self.width, self.height, 0, 0);
                },
                self.width,
                self.height,
            );
            self.framebuffer = buffer;
            self.generation += 1;
            self.dirty = false;
        }
        self.generation
    }

    pub fn frame_ptr(&self) -> *const u8 {
        // 未出过任何帧(未加载/未渲染)时返回 null,避免调用方误读零缓冲。
        if self.generation == 0 {
            return std::ptr::null();
        }
        self.framebuffer.as_ptr()
    }

    pub fn frame_width(&self) -> u32 {
        self.width
    }

    pub fn frame_height(&self) -> u32 {
        self.height
    }
}
