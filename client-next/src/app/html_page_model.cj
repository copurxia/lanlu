package lanlu_client_next.app

import std.collection.{ArrayList, HashSet}
import webview.{HtmlFrame, WebviewSession}

// html 页离屏渲染模型（对照 playback_model：纯逻辑可单测，网络出口全部注入）。
// 数据流：open 触发 fetchHtml → AppModel worker 拉页字节 → htmlLoaded 灌进
// WebviewSession（Blitz）；子资源经 pumpResources 发现 pending URL → 解析为
// 归档内路径 → fetchResource 异步取 → resourceLoaded 回填 provideResource。
// 会话单线程契约：本模型只在 UI 线程调用。

// 子资源 URL 的伪 scheme：loadHtml 以 lanlu://<arcid>/<pagePath> 作 baseUrl，
// 相对资源即解析为同 scheme 绝对 URL，再经 htmlResourcePath 还原归档内路径。
public let HTML_SCHEME = "lanlu"

// 十六进制位值；非法返回 -1。
private func hexVal(b: UInt8): Int64 {
    if (b >= 0x30u8 && b <= 0x39u8) {
        Int64(b - 0x30u8)
    } else if (b >= 0x41u8 && b <= 0x46u8) {
        Int64(b - 0x41u8) + 10
    } else if (b >= 0x61u8 && b <= 0x66u8) {
        Int64(b - 0x61u8) + 10
    } else {
        -1
    }
}

// URL 路径百分号解码（按字节；非法转义原样保留）。EPUB 路径偶含空格/非 ASCII，
// Blitz 的 url 解析会转义，回填后端前需还原为归档内原始路径。
public func percentDecodeBytes(src: Array<UInt8>): Array<UInt8> {
    let out = ArrayList<UInt8>()
    var i: Int64 = 0
    while (i < src.size) {
        if (src[i] == 0x25u8 && i + 2 < src.size) {
            let hi = hexVal(src[i + 1])
            let lo = hexVal(src[i + 2])
            if (hi >= 0 && lo >= 0) {
                out.add(UInt8(hi * 16 + lo))
                i += 3
                continue
            }
        }
        out.add(src[i])
        i++
    }
    out.toArray()
}

// String → UTF-8 字节（String 内部即 UTF-8；mallocCString 产出同内容 C 串，
// 经 getChars 一次 memcpy 拷出后归还。快照种子页/离线测试注入用）。
public func utf8BytesOf(s: String): Array<UInt8> {
    let cstr = unsafe { LibC.mallocCString(s) }
    let n = if (cstr.isNull()) { 0 } else { cstr.size() }
    let bytes = Array<UInt8>(n, repeat: 0u8)
    try {
        if (n > 0) {
            unsafe {
                let dst = acquireArrayRawData(bytes)
                let _ = memcpy(CPointer<Unit>(dst.pointer), CPointer<Unit>(cstr.getChars()), UIntNative(n))
                releaseArrayRawData(dst)
            }
        }
    } finally {
        unsafe { LibC.free(cstr) }
    }
    bytes
}

foreign func memcpy(destination: CPointer<Unit>, source: CPointer<Unit>, count: UIntNative): CPointer<Unit>

// UA 级主题 CSS（深/浅两份）：背景/前景/链接色/行距/页边距取值对齐 palette.cj
// 色板；阅读纸面用面板色而非页面底，长文不刺眼。注入后 Blitz 在每次
// load_html 后自动重新套用（Rust 侧 theme_css 跨文档驻留）。
// fontSize/margin 为阅读设置面板的字号档位与页边距档位（px，就近取档后传入）。
// 布局对齐 frontend：内容限宽居中（max-w-4xl≈896 语义：960 - 2×48 = 864 恰与
// frontend p-4 后的内容宽一致）；纸面/前景保留主题深浅（frontend 的 bg-white
// 是浏览器默认，桌面端深色纸面阅读更舒适，属有意差异）。
public func htmlThemeCss(light: Bool, fontSize!: Int64 = 16, margin!: Int64 = 48): String {
    // (纸面, 正文, 链接, 次文字, 代码底) 五组色取自 palette.cj 明/暗两档。
    let (bg, fg, link, dim, codeBg) = if (light) {
        ("#ffffff", "#1d1d21", "#c78a1e", "#6d6d76", "#f0f0f3")
    } else {
        ("#16161a", "#e8e8ea", "#e8b04b", "#9a9aa2", "#1e1e23")
    }
    let fs = max(12, min(24, fontSize))
    let mg = max(0, min(120, margin))
    "html, body { background: ${bg}; color: ${fg}; }\n" +
        "body { max-width: 960px; margin: 0 auto; padding: 0 ${mg}px; line-height: 1.75; font-size: ${fs}px; word-break: break-word; }\n" +
        "a { color: ${link}; text-decoration: none; }\n" +
        "img, video, svg, iframe { max-width: 100%; height: auto; }\n" +
        "p { margin: 0.6em 0; }\n" +
        "h1, h2, h3, h4, h5, h6 { line-height: 1.4; margin: 1.2em 0 0.6em; }\n" +
        "blockquote { margin: 0.8em 0; padding: 0 1em; color: ${dim}; }\n" +
        "code, pre { background: ${codeBg}; padding: 0.1em 0.3em; }"
}

/**
 * 把待供数 URL 解析为归档内路径。
 * 仅接受 lanlu://<arcid>/<path> 形态且 arcid 匹配；规范化 "."/".." 段
 *（越界 ".." 钳在根，不产生归档外路径）。不匹配返回 ""。
 */
public func htmlResourcePath(url: String, arcid: String): String {
    let prefix = "${HTML_SCHEME}://"
    if (!url.startsWith(prefix)) {
        return ""
    }
    let rest = url[prefix.size..url.size]
    // host 段取到首个 "/"；无 "/" 的裸 host 没有路径可取。
    // （String 索引取字节，'/' = 0x2F）
    var hostEnd: Int64 = -1
    for (i in 0..rest.size) {
        if (rest[Int64(i)] == 0x2Fu8) {
            hostEnd = Int64(i)
            break
        }
    }
    if (hostEnd < 0 || rest[0..hostEnd] != arcid) {
        return ""
    }
    // 字节级分段 + 百分号解码（非 ASCII 路径段按 UTF-8 字节整体还原）。
    let bytes = utf8BytesOf(rest[hostEnd..rest.size])
    let segs = ArrayList<String>()
    var cur = ArrayList<UInt8>()
    var i: Int64 = 0
    while (i <= bytes.size) {
        let atEnd = i == bytes.size
        if (atEnd || bytes[i] == 0x2Fu8) {
            if (cur.size > 0) {
                let decoded = percentDecodeBytes(cur.toArray())
                let seg = String.fromUtf8(decoded)
                if (seg == "..") {
                    if (segs.size > 0) {
                        let _ = segs.remove(at: segs.size - 1)
                    }
                } else if (seg != ".") {
                    segs.add(seg)
                }
                cur = ArrayList<UInt8>()
            }
        } else {
            cur.add(bytes[i])
        }
        i++
    }
    if (segs.size == 0) {
        return ""
    }
    var path = ""
    for (seg in segs) {
        if (path.size == 0) {
            path = seg
        } else {
            path = "${path}/${seg}"
        }
    }
    path
}

/**
 * M3.3 窗口/scale 变化后的滚动位置按旧比例还原（纯函数，可单测）：
 * 比例基于旧内容高，结果 clamp 到新可滚范围 [0, newContent-newViewport]。
 * oldContent 未知（首帧前）返回 0。
 */
public func htmlRestoredScroll(oldScroll: Float32, oldContent: Float32, newContent: Float32, newViewport: Float32): Float32 {
    let ratio = if (oldContent > 0.0f32) {
        oldScroll / oldContent
    } else {
        0.0f32
    }
    let maxOff = max(0.0f32, newContent - newViewport)
    max(0.0f32, min(maxOff, ratio * newContent))
}

public class HtmlPageModel {
    // ---- 状态（只读暴露；AppModel 变更后 bump readerVersion 通知视图）----
    public var pageKey: String = ""      // "${arcid}:${pagePath}"，空串=无 html 页
    public var state: String = "idle"    // idle/loading/ready/error
    public var lastError: String = ""
    public var contentHeight: Float32 = 0.0
    // 已交付 UI 的帧代际（takeHtmlFrame 每取到新帧 +1）：舞台据此只在新帧续帧。
    public var htmlGeneration: UInt64 = 0
    // 在途子资源任务数：>0 时舞台 100ms 轮询兜底等回填。
    public var resourcesInFlight: Int64 = 0
    // 滚到页尾（含内容不溢出的短页）触发一次；AppModel 接 reader.markCurrentPageRead
    // 并入进度上报（M3.5：html 页不翻页也落进度）。
    public var onHtmlRead: ?() -> Unit = None

    // ---- 注入点（AppModel 接 worker；测试注入假出口）----
    // (key, arcid, pagePath) 触发正文拉取；结果经 htmlLoaded/htmlFailed 回填。
    public var fetchHtml: ?(String, String, String) -> Unit = None
    // (key, arcid, url, archivePath) 触发子资源拉取；结果经 resourceLoaded/resourceFailed 回填。
    public var fetchResource: ?(String, String, String, String) -> Unit = None

    // ---- 内部 ----
    private var session: ?WebviewSession = None
    private var arcid: String = ""
    private var pagePath: String = ""
    // 正文章节字节在会话尚未按帧尺寸创建时暂存，ensureViewport 补灌。
    private var pendingHtmlBytes = Array<UInt8>(0, repeat: 0u8)
    // 每 URL 只试一次：失败/不可解析记入跳过集，不阻塞正文渲染。
    private let triedUrls = HashSet<String>()
    // 当前主题 CSS（主题切换时经 setThemeCss 替换；新会话创建时补套）。
    private var themeCss: String = ""
    private var viewW: Int32 = 0
    private var viewH: Int32 = 0
    private var viewScale: Float32 = 0.0
    // 本页是否已触发过 onHtmlRead（每页一次；open 重置）。
    private var bottomReported = false

    // 进入 html 页：同 key 且 loading/ready 幂等返回；否则重置并触发正文拉取。
    // w/h/scale 是首帧前的标称视口，舞台首次绘制会经 ensureViewport 校正。
    public func open(arcid: String, pagePath: String, wPx: Int32, hPx: Int32, scale: Float32): Unit {
        let key = "${arcid}:${pagePath}"
        if (key == pageKey && (state == "loading" || state == "ready")) {
            return
        }
        closeSession()
        this.arcid = arcid
        this.pagePath = pagePath
        pageKey = key
        state = "loading"
        lastError = ""
        contentHeight = 0.0
        htmlGeneration = 0
        resourcesInFlight = 0
        bottomReported = false
        triedUrls.clear()
        pendingHtmlBytes = Array<UInt8>(0, repeat: 0u8)
        session = Some(WebviewSession(wPx, hPx, scale))
        viewW = wPx
        viewH = hPx
        viewScale = scale
        match (session) {
            case Some(s) =>
                if (themeCss.size > 0) {
                    s.setThemeCss(themeCss)
                }
            case None => ()
        }
        match (fetchHtml) {
            case Some(cb) => cb(key, arcid, pagePath)
            case None => ()
        }
    }

    // 正文到货：迟到结果按 key 对号入座，切页后静默丢弃（对照 playback.onDownloaded）。
    public func htmlLoaded(key: String, bytes: Array<UInt8>): Unit {
        if (key != pageKey || state != "loading") {
            return
        }
        match (session) {
            case Some(_) =>
                loadIntoSession(bytes)
            case None =>
                // 会话还没按真实帧尺寸创建：暂存，ensureViewport 时补灌。
                pendingHtmlBytes = bytes
        }
    }

    public func htmlFailed(key: String, err: String): Unit {
        if (key != pageKey) {
            return
        }
        state = "error"
        lastError = err
    }

    // 失败重试：仅 error 态有效，回到 loading 并重新触发拉取。
    public func retry(): Unit {
        if (state != "error" || pageKey.size == 0) {
            return
        }
        state = "loading"
        lastError = ""
        match (fetchHtml) {
            case Some(cb) => cb(pageKey, arcid, pagePath)
            case None => ()
        }
    }

    private func loadIntoSession(bytes: Array<UInt8>): Unit {
        match (session) {
            case Some(s) =>
                try {
                    s.loadHtml(bytes, "${HTML_SCHEME}://${arcid}/${pagePath}")
                    state = "ready"
                    pumpResources()
                } catch (e: Exception) {
                    state = "error"
                    lastError = "webview loadHtml failed"
                }
            case None => ()
        }
    }

    // 舞台每帧调用：视口跟随物理像素（变则 resize）；正文早于会话到货时补灌。
    // M3.3：resize 后内容重排，滚动位置按 (scrollY/oldContentHeight) 比例还原，
    // 窗口拉伸不会把阅读位置甩回页首。
    public func ensureViewport(wPx: Int32, hPx: Int32, scale: Float32): Unit {
        if (wPx <= 0 || hPx <= 0 || pageKey.size == 0) {
            return
        }
        match (session) {
            case Some(s) =>
                if (wPx != viewW || hPx != viewH || scale != viewScale) {
                    let oldScroll = s.scrollY()
                    let oldContent = s.contentHeight()
                    s.resize(wPx, hPx, scale)
                    viewW = wPx
                    viewH = hPx
                    viewScale = scale
                    let newContent = s.contentHeight()
                    if (oldContent > 0.0 && newContent > 0.0 && oldContent != newContent) {
                        s.scrollTo(htmlRestoredScroll(oldScroll, oldContent, newContent, Float32(hPx)))
                    }
                }
            case None =>
                session = Some(WebviewSession(wPx, hPx, scale))
                viewW = wPx
                viewH = hPx
                viewScale = scale
                if (pendingHtmlBytes.size > 0) {
                    let bytes = pendingHtmlBytes
                    pendingHtmlBytes = Array<UInt8>(0, repeat: 0u8)
                    loadIntoSession(bytes)
                }
        }
    }

    public func viewportHeight(): Int32 {
        viewH
    }

    // 子资源泵：pending URL → 归档内路径 → 经注入出口异步拉取。
    // 每 URL 只试一次；加载新文档时 triedUrls 已清空。
    public func pumpResources(): Unit {
        if (state != "ready") {
            return
        }
        match (session) {
            case Some(s) =>
                for (url in s.pendingResources()) {
                    if (triedUrls.contains(url)) {
                        continue
                    }
                    let path = htmlResourcePath(url, arcid)
                    if (path.size == 0) {
                        triedUrls.add(url)
                        continue
                    }
                    triedUrls.add(url)
                    resourcesInFlight++
                    match (fetchResource) {
                        case Some(cb) => cb(pageKey, arcid, url, path)
                        case None => resourcesInFlight--
                    }
                }
            case None => ()
        }
    }

    public func resourceLoaded(key: String, url: String, bytes: Array<UInt8>): Unit {
        if (key != pageKey) {
            return
        }
        if (resourcesInFlight > 0) {
            resourcesInFlight--
        }
        match (session) {
            case Some(s) =>
                let _ = s.provideResource(url, bytes)
                // 资源注入可能触发样式重算并暴露新的 pending（css 内 @import/url()）。
                pumpResources()
            case None => ()
        }
    }

    public func resourceFailed(key: String, url: String): Unit {
        if (key != pageKey) {
            return
        }
        if (resourcesInFlight > 0) {
            resourcesInFlight--
        }
        triedUrls.add(url)
    }

    // 取新帧（转发 session）；顺带刷新 contentHeight 与对外帧代际。
    // 滚动每次都会产出新帧，故每帧的读尾判定都以此为驱动：滚到可滚范围底部
    //（或内容根本不溢出）即视为读完，触发一次 onHtmlRead。
    public func takeHtmlFrame(): ?HtmlFrame {
        match (session) {
            case Some(s) =>
                let frame = s.takeFrame()
                match (frame) {
                    case Some(f) =>
                        contentHeight = s.contentHeight()
                        htmlGeneration += 1
                        if (state == "ready" && !bottomReported && viewH > 0 && contentHeight > 0.0) {
                            let maxScroll = max(0.0f32, contentHeight - Float32(viewH))
                            if (maxScroll <= 1.0 || s.scrollY() >= maxScroll - 1.0) {
                                bottomReported = true
                                match (onHtmlRead) {
                                    case Some(cb) => cb()
                                    case None => ()
                                }
                            }
                        }
                    case None => ()
                }
                frame
            case None => None
        }
    }

    /** 页内进度 0..1 = scrollY/(contentHeight-viewportH)；内容不溢出视为 1.0。 */
    public func htmlPageProgress01(): Float32 {
        if (state != "ready" || contentHeight <= 0.0 || viewH <= 0) {
            return 0.0f32
        }
        let maxScroll = max(0.0f32, contentHeight - Float32(viewH))
        if (maxScroll <= 1.0) {
            return 1.0f32
        }
        max(0.0f32, min(1.0f32, scrollY() / maxScroll))
    }

    /** 向下滚动 dy 像素；返回 false 表示已到边界（调用方可外溢给翻页）。 */
    public func scrollBy(dy: Float32): Bool {
        match (session) {
            case Some(s) => s.scrollBy(dy)
            case None => false
        }
    }

    public func scrollTo(y: Float32): Unit {
        match (session) {
            case Some(s) => s.scrollTo(y)
            case None => ()
        }
    }

    public func scrollY(): Float32 {
        match (session) {
            case Some(s) => s.scrollY()
            case None => 0.0
        }
    }

    public func setThemeCss(css: String): Unit {
        themeCss = css
        match (session) {
            case Some(s) => s.setThemeCss(css)
            case None => ()
        }
    }

    public func isOpen(key: String): Bool {
        key == pageKey && state != "idle"
    }

    // 翻离 html 页/退出阅读器：释放会话（framebuffer 随之归还）。
    public func close(): Unit {
        closeSession()
        pageKey = ""
        state = "idle"
        lastError = ""
        contentHeight = 0.0
        htmlGeneration = 0
        resourcesInFlight = 0
        bottomReported = false
    }

    private func closeSession(): Unit {
        match (session) {
            case Some(s) => s.close()
            case None => ()
        }
        session = None
        pendingHtmlBytes = Array<UInt8>(0, repeat: 0u8)
        triedUrls.clear()
        arcid = ""
        pagePath = ""
    }
}
