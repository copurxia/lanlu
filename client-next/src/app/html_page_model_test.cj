package lanlu_client_next.app

import std.collection.ArrayList

// HtmlPageModel 单测：URL→归档路径还原、字节工具、主题 CSS 以及
// 状态机（error/retry/close/迟到结果丢弃）。会话创建走真实 native（静态链接）。

// ---- URL → 归档内路径 ----

@Test
func htmlResourcePathBasic(): Unit {
    @Expect(htmlResourcePath("lanlu://arc1/css/style.css", "arc1"), "css/style.css")
}

@Test
func htmlResourcePathRejectsForeignArc(): Unit {
    // arcid 不匹配、非 lanlu scheme、裸 host 无路径：一律拒绝。
    @Expect(htmlResourcePath("lanlu://arc2/css/style.css", "arc1"), "")
    @Expect(htmlResourcePath("http://arc1/css/style.css", "arc1"), "")
    @Expect(htmlResourcePath("lanlu://arc1", "arc1"), "")
}

@Test
func htmlResourcePathNormalizesDotSegments(): Unit {
    // "."/".." 段规范化；越界 ".." 钳在根，不产生归档外路径。
    @Expect(htmlResourcePath("lanlu://arc1/text/../images/pic.png", "arc1"), "images/pic.png")
    @Expect(htmlResourcePath("lanlu://arc1/./text/./ch1.html", "arc1"), "text/ch1.html")
    @Expect(htmlResourcePath("lanlu://arc1/../../etc/passwd", "arc1"), "etc/passwd")
}

@Test
func htmlResourcePathPercentDecodes(): Unit {
    // 百分号转义按字节还原（空格与多字节 UTF-8 整体还原）。
    @Expect(htmlResourcePath("lanlu://arc1/OEBPS/ch%201.xhtml", "arc1"), "OEBPS/ch 1.xhtml")
    @Expect(htmlResourcePath("lanlu://arc1/%E4%B8%AD%E6%96%87.html", "arc1"), "中文.html")
}

// ---- 字节工具 ----

@Test
func utf8BytesRoundTrip(): Unit {
    let s = "héllo 中文 🚀"
    let bytes = utf8BytesOf(s)
    @Expect(String.fromUtf8(bytes), s)
    // String 内部即 UTF-8：字节数与 String.size（字节长度）一致
    @Expect(bytes.size, s.size)
    @Expect(utf8BytesOf("").size, 0)
}

// ---- M3.3 窗口尺寸变化后的滚动比例还原（纯函数）----

@Test
func htmlRestoredScrollKeepsRatio(): Unit {
    // 读在旧内容 50% 处（2000 高 → 1000），新内容高 3000：还原到 1500。
    @Expect(htmlRestoredScroll(1000.0, 2000.0, 3000.0, 800.0), 1500.0)
    // 内容变矮但新可滚范围仍充足（1800-800=1000 ≥ 900）：纯按比例回落。
    @Expect(htmlRestoredScroll(1000.0, 2000.0, 1800.0, 800.0), 900.0)
}

@Test
func htmlRestoredScrollClampsToNewRange(): Unit {
    // 新内容几乎不溢出：还原值被钳到可滚范围（1000-900=100）。
    @Expect(htmlRestoredScroll(800.0, 1000.0, 1000.0, 900.0), 100.0)
    // 新内容不溢出（内容高 ≤ 视口）：钳到 0（页首）。
    @Expect(htmlRestoredScroll(500.0, 2000.0, 900.0, 900.0), 0.0)
    // 负滚动/越界输入防御。
    @Expect(htmlRestoredScroll(-10.0, 2000.0, 3000.0, 800.0), 0.0)
}

@Test
func htmlRestoredScrollUnknownOldContent(): Unit {
    // 旧内容未知（首帧前）：回到 0，不产生无效比例。
    @Expect(htmlRestoredScroll(100.0, 0.0, 3000.0, 800.0), 0.0)
}

@Test
func htmlReadingMaxOffsetUsesWholeSpreads(): Unit {
    @Expect(htmlReadingMaxOffset(900.0, 1000.0, false), 0.0)
    @Expect(htmlReadingMaxOffset(1500.0, 1000.0, false), 500.0)
    // 双页可容纳两屏：短章只有一个 spread；3.3 屏内容只有第二个 spread 起点 2000。
    @Expect(htmlReadingMaxOffset(1500.0, 1000.0, true), 0.0)
    @Expect(htmlReadingMaxOffset(3300.0, 1000.0, true), 2000.0)
    // 恰好两屏不应制造空白的下一 spread。
    @Expect(htmlReadingMaxOffset(2000.0, 1000.0, true), 0.0)
}

@Test
func htmlLiveViewportResizeRealignsSpread(): Unit {
    let m = HtmlPageModel()
    try {
        m.fetchHtml = {_, _, _ => ()}
        m.setDoublePage(true)
        m.open("arc1", "text/long.html", 2000, 972, 1.0)
        m.htmlLoaded("arc1:text/long.html",
            utf8BytesOf("<html><body><div style='height:5000px'>long chapter</div></body></html>"))
        m.ensureViewport(2000, 972, 1.0)
        let _ = m.takeHtmlFrame()
        @Expect(m.contentHeight > 4000.0, true)

        // 每张纸面末尾预留 12px 字形安全带：972 高对应实际页步 960。
        m.scrollTo(1944.0)
        @Expect(m.scrollY(), 1920.0)
        m.ensureViewport(2000, 1024, 1.0)
        @Expect(m.viewportHeight(), 1024)
        // 保持同一 spread 序号；新实际页步为 1012。
        @Expect(m.scrollY(), 2024.0)
    } finally {
        m.close()
    }
}

@Test
func htmlDoublePageLeavesLineSafeRemainder(): Unit {
    let m = HtmlPageModel()
    try {
        m.fetchHtml = {_, _, _ => ()}
        m.setDoublePage(true)
        m.open("arc1", "text/lines.html", 440, 120, 1.0)
        m.setThemeCss(htmlThemeCss(true, fontSize: 16, margin: 24, doublePage: true))
        m.htmlLoaded("arc1:text/lines.html", utf8BytesOf(
            "<html><body><p>one two three four five six seven eight nine ten eleven twelve thirteen fourteen " +
            "fifteen sixteen seventeen eighteen nineteen twenty twenty-one twenty-two twenty-three twenty-four " +
            "twenty-five twenty-six twenty-seven twenty-eight twenty-nine thirty thirty-one thirty-two</p></body></html>"))
        m.ensureViewport(440, 120, 1.0)
        let _ = m.takeHtmlFrame()
        // 纸面正文最多用到 viewport-12；下一纸面从完整行边界开始。
        @Expect(m.pageVisibleHeight(false) <= 108.0, true)
        @Expect(m.pageVisibleHeight(false) > 0.0, true)
        @Expect(m.pageVisibleHeight(true) <= 108.0, true)
    } finally {
        m.close()
    }
}

// ---- 主题 CSS ----

@Test
func htmlThemeCssPalettes(): Unit {
    let light = htmlThemeCss(true)
    let dark = htmlThemeCss(false)
    @Expect(light.contains("#ffffff"), true)
    @Expect(light.contains("#c78a1e"), true)
    @Expect(dark.contains("#16161a"), true)
    @Expect(dark.contains("#e8b04b"), true)
    // 深浅两套互不串色
    @Expect(light.contains("#16161a"), false)
    @Expect(dark.contains("#ffffff"), false)
    // 排版设置必须覆盖 EPUB 自带 body 样式；纵向安全区由每个 ReaderStage 纸面
    // 统一留出，body 只承载用户可调的横向页边距。
    @Expect(light.contains("padding: 0 48px !important"), true)
    @Expect(light.contains("max-width: 960px !important"), true)
    @Expect(htmlThemeCss(true, doublePage: true).contains("max-width: none !important"), true)
}

// ---- HtmlPageModel 状态机 ----

// 记录 fetchHtml 触发的 (key, arcid, pagePath)。
class HtmlFetchLog {
    let calls = ArrayList<String>()
    var count: Int64 = 0
}

@Test
func htmlOpenIdempotentWhileLoading(): Unit {
    let m = HtmlPageModel()
    let log = HtmlFetchLog()
    m.fetchHtml = {
        key, arc, p =>
        log.calls.add("${key}|${arc}|${p}");
        log.count++
    }
    m.open("arc1", "text/ch1.html", 1280, 800, 1.0)
    @Expect(m.state, "loading")
    @Expect(m.pageKey, "arc1:text/ch1.html")
    // loading 中重复 open 同 key：幂等，不重复拉取
    m.open("arc1", "text/ch1.html", 1280, 800, 1.0)
    @Expect(log.count, 1)
    m.close()
}

@Test
func htmlFailedAndRetry(): Unit {
    let m = HtmlPageModel()
    let log = HtmlFetchLog()
    m.fetchHtml = {key, arc, p => log.count++}
    m.open("arc1", "text/ch1.html", 1280, 800, 1.0)
    @Expect(log.count, 1)
    m.htmlFailed("arc1:text/ch1.html", "网络中断")
    @Expect(m.state, "error")
    @Expect(m.lastError, "网络中断")
    // 非 error 态之外的重试无效；error 态 retry 重新触发拉取
    m.retry()
    @Expect(m.state, "loading")
    @Expect(m.lastError, "")
    @Expect(log.count, 2)
    m.close()
}

@Test
func htmlLateResultsIgnoredAfterClose(): Unit {
    let m = HtmlPageModel()
    m.fetchHtml = {_, _, _ => ()}
    m.open("arc1", "text/ch1.html", 1280, 800, 1.0)
    m.close()
    @Expect(m.state, "idle")
    @Expect(m.pageKey, "")
    // 迟到回填：key 不匹配静默丢弃，不改变 idle 态
    m.htmlFailed("arc1:text/ch1.html", "late")
    @Expect(m.state, "idle")
    m.htmlLoaded("arc1:text/ch1.html", Array<UInt8>(0, repeat: 0u8))
    @Expect(m.state, "idle")
    // close 后 retry 无效（pageKey 已清空）
    m.retry()
    @Expect(m.state, "idle")
}

@Test
func htmlRetryOnlyInErrorState(): Unit {
    let m = HtmlPageModel()
    let log = HtmlFetchLog()
    m.fetchHtml = {_, _, _ => log.count++}
    m.open("arc1", "text/ch1.html", 1280, 800, 1.0)
    @Expect(log.count, 1)
    // loading 态 retry 不触发新拉取
    m.retry()
    @Expect(log.count, 1)
    @Expect(m.state, "loading")
    m.close()
}

@Test
func htmlResourceFailedAccounting(): Unit {
    let m = HtmlPageModel()
    m.fetchHtml = {_, _, _ => ()}
    m.open("arc1", "text/ch1.html", 1280, 800, 1.0)
    // 手工记账场景：在途数不降到负
    m.resourceFailed("arc1:text/ch1.html", "lanlu://arc1/missing.png")
    @Expect(m.resourcesInFlight, 0)
    // 迟到（key 不匹配）不影响计数
    m.resourceFailed("arc9:other", "lanlu://arc9/x.png")
    @Expect(m.resourcesInFlight, 0)
    m.close()
}

@Test
func htmlIsOpenSemantics(): Unit {
    let m = HtmlPageModel()
    m.fetchHtml = {_, _, _ => ()}
    @Expect(m.isOpen("arc1:text/ch1.html"), false)
    m.open("arc1", "text/ch1.html", 1280, 800, 1.0)
    @Expect(m.isOpen("arc1:text/ch1.html"), true)
    @Expect(m.isOpen("arc1:text/ch2.html"), false)
    m.close()
    @Expect(m.isOpen("arc1:text/ch1.html"), false)
}
