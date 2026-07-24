package lanlu_client_next.app

import lanlu_client_next.net.PageInfo
import std.collection.ArrayList

// ---- 测试辅助 ----

class FakeClock {
    var now: Int64 = 0
}

// 仓颉限制「捕获可变局部变量的 lambda 必须直接调用」——计数走引用类型盒。
class IntBox {
    var v: Int64 = 0
}

// 按 pageType 序列造页表：id = "p<0基索引>"。
func mkReaderPages(types: Array<String>): ArrayList<PageInfo> {
    let list = ArrayList<PageInfo>()
    var i: Int64 = 0
    for (t in types) {
        let p = PageInfo()
        p.id = "p${i}"
        p.pageType = t
        list.add(p)
        i++
    }
    list
}

// n 页纯图片档案。
func mkImagePages(n: Int64): ArrayList<PageInfo> {
    let list = ArrayList<PageInfo>()
    for (i in 0..n) {
        let p = PageInfo()
        p.id = "p${i}"
        p.pageType = "image"
        list.add(p)
    }
    list
}

// img×4, video, img×2, audio 混合档案（8 页）。
func mkMixedPages(): ArrayList<PageInfo> {
    mkReaderPages(["image", "image", "image", "image", "video", "image", "image", "audio"])
}

func newReader(pages: ArrayList<PageInfo>): ReaderModel {
    let r = ReaderModel(AppSettings())
    r.open("arc1", 0)
    r.setPages(pages)
    r
}

func dirLabel(d: Option<Bool>): String {
    match (d) {
        case Some(true) => "next"
        case Some(false) => "prev"
        case None => "none"
    }
}

func spreadLabel(spread: Array<Int64>): String {
    let parts = ArrayList<String>()
    for (i in spread) {
        parts.add("${i}")
    }
    "[" + String.join(parts.toArray(), delimiter: ",") + "]"
}

func lanesLabel(lanes: Array<LaneId>): String {
    let parts = ArrayList<String>()
    for (l in lanes) {
        parts.add(l.toString())
    }
    "[" + String.join(parts.toArray(), delimiter: ",") + "]"
}

// ---- keyDirection：四模式方向键映射（对齐 frontend useReaderKeyboardNavigation）----

@Test
func keyDirectionSingleLtr(): Unit {
    let r = newReader(mkImagePages(10))
    r.setMode(SingleLtr)
    @Expect(dirLabel(r.keyDirection(KeyRight)), "next")
    @Expect(dirLabel(r.keyDirection(KeyLeft)), "prev")
    @Expect(dirLabel(r.keyDirection(KeyUp)), "none")
    @Expect(dirLabel(r.keyDirection(KeyDown)), "none")
}

@Test
func keyDirectionSingleRtl(): Unit {
    let r = newReader(mkImagePages(10))
    r.setMode(SingleRtl)
    // RTL 反转：左=下一页，右=上一页
    @Expect(dirLabel(r.keyDirection(KeyLeft)), "next")
    @Expect(dirLabel(r.keyDirection(KeyRight)), "prev")
    @Expect(dirLabel(r.keyDirection(KeyUp)), "none")
    @Expect(dirLabel(r.keyDirection(KeyDown)), "none")
}

@Test
func keyDirectionSingleTtb(): Unit {
    let r = newReader(mkImagePages(10))
    r.setMode(SingleTtb)
    @Expect(dirLabel(r.keyDirection(KeyDown)), "next")
    @Expect(dirLabel(r.keyDirection(KeyUp)), "prev")
    // 参考实现里 TTB 未排除左右键（非 webtoon 即响应）：左=prev 右=next
    @Expect(dirLabel(r.keyDirection(KeyLeft)), "prev")
    @Expect(dirLabel(r.keyDirection(KeyRight)), "next")
}

@Test
func keyDirectionWebtoonNone(): Unit {
    let r = newReader(mkImagePages(10))
    r.setMode(Webtoon)
    // 条漫由滚动驱动，四个方向键都不响应
    @Expect(dirLabel(r.keyDirection(KeyLeft)), "none")
    @Expect(dirLabel(r.keyDirection(KeyRight)), "none")
    @Expect(dirLabel(r.keyDirection(KeyUp)), "none")
    @Expect(dirLabel(r.keyDirection(KeyDown)), "none")
}

// ---- spreadPages：配页规则（48 页）----

@Test
func spreadSinglePageMode(): Unit {
    let r = newReader(mkImagePages(48))
    r.gotoPage(5)
    @Expect(spreadLabel(r.spreadPages()), "[5]")
    @Expect(r.index, 5)
}

@Test
func spreadDoubleNoSplitCover(): Unit {
    let r = newReader(mkImagePages(48))
    r.setDoublePage(true)
    // [0,1],[2,3]…：gotoPage 落在对中页时 index 吸附到 spread 首页
    @Expect(spreadLabel(r.spreadPages()), "[0,1]")
    r.gotoPage(1)
    @Expect(r.index, 0)
    @Expect(spreadLabel(r.spreadPages()), "[0,1]")
    r.gotoPage(5)
    @Expect(r.index, 4)
    @Expect(spreadLabel(r.spreadPages()), "[4,5]")
    r.gotoPage(47)
    @Expect(r.index, 46)
    @Expect(spreadLabel(r.spreadPages()), "[46,47]")
}

@Test
func spreadDoubleSplitCover(): Unit {
    let r = newReader(mkImagePages(48))
    r.setDoublePage(true)
    r.setSplitCover(true)
    // 封面 [0] 独占，其后 [1,2],[3,4]…，末页 [47] 落单
    @Expect(spreadLabel(r.spreadPages()), "[0]")
    r.gotoPage(2)
    @Expect(r.index, 1)
    @Expect(spreadLabel(r.spreadPages()), "[1,2]")
    r.gotoPage(46)
    @Expect(r.index, 45)
    @Expect(spreadLabel(r.spreadPages()), "[45,46]")
    r.gotoPage(47)
    @Expect(spreadLabel(r.spreadPages()), "[47]")
}

@Test
func spreadRtlReversesPairOrder(): Unit {
    let r = newReader(mkImagePages(48))
    r.setMode(SingleRtl)
    r.setDoublePage(true)
    @Expect(spreadLabel(r.spreadPages()), "[1,0]")
    r.gotoPage(4)
    @Expect(spreadLabel(r.spreadPages()), "[5,4]")
    // splitCover 同样反转显示序
    r.setSplitCover(true)
    r.gotoPage(1)
    @Expect(spreadLabel(r.spreadPages()), "[2,1]")
    // LTR 双页不反转（对照）
    r.setMode(SingleLtr)
    @Expect(spreadLabel(r.spreadPages()), "[1,2]")
}

// ---- gotoPage 钳制 ----

@Test
func gotoPageClampsOutOfRange(): Unit {
    let r = newReader(mkImagePages(10))
    r.gotoPage(-5)
    @Expect(r.index, 0)
    // 流域钳制：末尾虚拟页恒存在，越界落在虚拟结束页（流索引 10）
    r.gotoPage(99)
    @Expect(r.index, 10)
    @Expect(r.onVirtualEnd, true)
    // 起始页（来自可能过期的 progress）越界：页表到货时钳制（同样落虚拟页）
    let r2 = ReaderModel(AppSettings())
    r2.open("arc2", 999)
    r2.setPages(mkImagePages(10))
    @Expect(r2.index, 10)
    @Expect(r2.onVirtualEnd, true)
    // 空页表：翻页空操作不炸
    let r3 = ReaderModel(AppSettings())
    r3.open("arc3", 0)
    r3.gotoPage(3)
    @Expect(r3.index, 0)
    @Expect(r3.pageCount, 0)
}

// ---- turnPage：步进与模式换算 ----

@Test
func turnPageStepsSingleMode(): Unit {
    let r = newReader(mkImagePages(10))
    r.turnPage(true)
    @Expect(r.index, 1)
    r.turnPage(true)
    @Expect(r.index, 2)
    r.turnPage(false)
    @Expect(r.index, 1)
    r.gotoPage(0)
    r.turnPage(false)  // 首页再往前：原地
    @Expect(r.index, 0)
    r.gotoPage(9)
    r.turnPage(true)   // 末真实页再往后：进虚拟结束页（流索引 10）
    @Expect(r.index, 10)
    @Expect(r.onVirtualEnd, true)
    r.turnPage(true)   // 虚拟页再往后：原地
    @Expect(r.index, 10)
    r.turnPage(false)  // 虚拟页「上一页」回本 segment 最后真实页
    @Expect(r.index, 9)
}

@Test
func turnPageStepsDoubleSpread(): Unit {
    let r = newReader(mkImagePages(48))
    r.setDoublePage(true)
    r.turnPage(true)   // [0,1] → [2,3]
    @Expect(r.index, 2)
    r.turnPage(true)   // → [4,5]
    @Expect(r.index, 4)
    r.turnPage(false)  // → 回到 [2,3]
    @Expect(r.index, 2)
    // splitCover：封面独占，步进按 spread 尺寸换算
    r.setSplitCover(true)
    r.gotoPage(0)
    @Expect(spreadLabel(r.spreadPages()), "[0]")
    r.turnPage(true)   // [0] → [1,2]
    @Expect(r.index, 1)
    r.turnPage(true)   // [1,2] → [3,4]
    @Expect(r.index, 3)
    r.turnPage(false)  // [3,4] → [1,2]
    @Expect(r.index, 1)
    r.turnPage(false)  // [1,2] → [0]
    @Expect(r.index, 0)
    // 末 spread 落单 [47]：往后进虚拟结束页（流索引 48），再往后原地
    r.gotoPage(47)
    r.turnPage(true)
    @Expect(r.index, 48)
    @Expect(r.onVirtualEnd, true)
    r.turnPage(true)
    @Expect(r.index, 48)
    // 虚拟页「上一页」：splitCover 下 47 落单，回本 segment 最后真实页（吸附后仍是 47）
    r.turnPage(false)
    @Expect(r.index, 47)
}

@Test
func turnPageWebtoonNoOp(): Unit {
    let r = newReader(mkImagePages(10))
    r.setMode(Webtoon)
    r.gotoPage(3)
    r.turnPage(true)
    @Expect(r.index, 3)
    r.turnPage(false)
    @Expect(r.index, 3)
}

// ---- laneSpecs：混合档案媒体 lane ----

@Test
func laneSpecsMixedArchive(): Unit {
    let r = newReader(mkMixedPages())
    r.gotoPage(4)
    @Expect(lanesLabel(r.laneSpecs()), "[Video(4),Book]")
    r.gotoPage(5)
    @Expect(lanesLabel(r.laneSpecs()), "[Book]")
    r.gotoPage(7)
    @Expect(lanesLabel(r.laneSpecs()), "[Audio(7),Book]")
    r.gotoPage(0)
    @Expect(lanesLabel(r.laneSpecs()), "[Book]")
}

@Test
func laneAutoActivateOnSpreadChange(): Unit {
    let r = newReader(mkMixedPages())
    r.gotoPage(4)
    // 换到含媒体的 spread：自动激活第一个媒体 lane
    @Expect(r.activeLane.toString(), "Video(4)")
    // 手动切回 Book：不翻页
    r.setActiveLane(Book)
    @Expect(r.activeLane.toString(), "Book")
    @Expect(r.index, 4)
    // 同 spread 内 gotoPage（未换 spread）：lane 选择保持
    r.gotoPage(4)
    @Expect(r.activeLane.toString(), "Book")
    // 换到纯图片 spread：Book 兜底
    r.gotoPage(5)
    @Expect(r.activeLane.toString(), "Book")
    // 再换到含音频的 spread：重新自动激活媒体 lane
    r.gotoPage(7)
    @Expect(r.activeLane.toString(), "Audio(7)")
    // 不在当前 lanes 里的 setActiveLane 被忽略
    r.setActiveLane(Video(4))
    @Expect(r.activeLane.toString(), "Audio(7)")
}

@Test
func laneExpansionDoesNotChangeSpreadMedia(): Unit {
    let r = newReader(mkMixedPages())
    r.gotoPage(4)
    @Expect(r.spreadMediaLane().toString(), "Video(4)")
    r.setActiveLane(Book)
    // activeLane 只是 dock 展开项；内容仍然是当前 spread 的视频。
    @Expect(r.activeLane.toString(), "Book")
    @Expect(r.spreadMediaLane().toString(), "Video(4)")
}

@Test
func appLaneSwitchDoesNotReloadOrStopPlayback(): Unit {
    let m = AppModel(AppSettings())
    m.reader.open("arc1", 0)
    m.reader.setPages(mkMixedPages())
    m.reader.gotoPage(4)
    m.playback.loadRemote("arc1", 4, "http://media/video", "", video: true)
    let key = m.playback.mediaKey
    m.syncReaderLane(Book)
    @Expect(m.reader.activeLane.toString(), "Book")
    @Expect(m.playback.mediaKey, key)
    @Expect(m.playback.loaded, true)
    @Expect(m.playback.isVideo, true)
}

// ---- 进度上报：900ms 防抖，尾巴不丢 ----

@Test
func progressDebounceKeepsTail(): Unit {
    let fake = FakeClock()
    let r = ReaderModel(AppSettings())
    r.clock = { => fake.now }
    let reports = ArrayList<Int64>()
    r.onProgress = { _arcid, page => reports.add(page) }
    r.open("arc1", 0)
    r.setPages(mkImagePages(48))
    // 首次翻页立即上报（1 基页码）
    r.gotoPage(0)
    @Expect(reports.size, 1)
    @Expect(reports[0], 1)
    // 窗口内连续翻页被防抖压住
    fake.now = 100
    r.gotoPage(1)
    fake.now = 200
    r.gotoPage(2)
    @Expect(reports.size, 1)
    // 窗口未满 tick 不发
    fake.now = 899
    r.tick()
    @Expect(reports.size, 1)
    // 窗口到点 tick 补发最后一页（尾巴不丢）
    fake.now = 901
    r.tick()
    @Expect(reports.size, 2)
    @Expect(reports[1], 3)
    // 停在最末页：窗口内 flush 必须发出最后一次上报
    fake.now = 1000
    r.gotoPage(47)
    @Expect(reports.size, 2)
    r.flushProgress()
    @Expect(reports.size, 3)
    @Expect(reports[2], 48)
    // 无 pending 时 flush/tick 都是空操作
    r.flushProgress()
    r.tick()
    @Expect(reports.size, 3)
}

@Test
func progressForReportPages(): Unit {
    let r = newReader(mkImagePages(48))
    r.gotoPage(5)
    let (page, total) = r.progressForReport()
    @Expect(page, 6) // 1 基
    @Expect(total, 48)
}

// ---- 预取目标：当前页前后各 2 页（0 基，越界裁剪）----

@Test
func prefetchTargetsClampToRange(): Unit {
    let r = newReader(mkImagePages(10))
    let captured = ArrayList<Array<Int64>>()
    r.onPrefetch = { _arcid, indices => captured.add(indices) }
    r.gotoPage(5)
    @Expect(spreadLabel(captured[0]), "[3,4,6,7]")
    r.gotoPage(0)
    @Expect(spreadLabel(captured[1]), "[1,2]")
    r.gotoPage(9)
    @Expect(spreadLabel(captured[2]), "[7,8]")
}

// ---- chrome 显隐（autoHide 计时闭环由 T13 FrameHandler 完成，此处只验状态与常量）----

@Test
func chromeToggleAndActivity(): Unit {
    @Expect(READER_CHROME_AUTOHIDE_MS, 3000)
    let fake = FakeClock()
    let r = ReaderModel(AppSettings())
    r.clock = { => fake.now }
    r.open("arc1", 0)
    @Expect(r.chromeVisible, true)
    r.toggleChrome()
    @Expect(r.chromeVisible, false)
    r.toggleChrome()
    @Expect(r.chromeVisible, true)
    // autoHide 开启时活动会重新亮出 chrome 并刷新活动时间
    r.setAutoHide(true)
    r.toggleChrome()
    @Expect(r.chromeVisible, false)
    fake.now = 5000
    r.noteActivity()
    @Expect(r.chromeVisible, true)
    @Expect(r.lastActivityMs, 5000)
}

// ---- 设置持久化：reader_* 字段即时写入 AppSettings 并触发 onPersist ----

@Test
func optionsPersistToSettings(): Unit {
    let s = AppSettings()
    let r = ReaderModel(s)
    let persistCount = IntBox()
    r.onPersist = { => persistCount.v++ }
    @Expect(r.mode.toSettingString(), "single-ltr") // 默认
    r.setMode(Webtoon)
    @Expect(s.readerMode, "webtoon")
    r.setDoublePage(true)
    @Expect(s.readerDoublePage, true)
    r.setSplitCover(true)
    @Expect(s.readerSplitCover, true)
    r.setTapTurnPage(true)
    @Expect(s.readerTapTurnPage, true)
    r.setDoubleTapZoom(true)
    @Expect(s.readerDoubleTapZoom, true)
    r.setSeamlessNext(true)
    @Expect(s.readerSeamlessNext, true)
    // longPage 默认 true（对齐 frontend），关一次
    @Expect(r.longPage, true)
    r.setLongPage(false)
    @Expect(s.readerLongPage, false)
    @Expect(persistCount.v, 7)
    // 从 settings 重建：模式/开关读回
    let r2 = ReaderModel(s)
    @Expect(r2.mode.toSettingString(), "webtoon")
    @Expect(r2.doublePage, true)
    @Expect(r2.splitCover, true)
    @Expect(r2.longPage, false)
}

@Test
func autoPlayOptionsPersistAndClamp(): Unit {
    let s = AppSettings()
    let r = ReaderModel(s)
    let persistCount = IntBox()
    r.onPersist = { => persistCount.v++ }
    // 默认：关、3 秒（对齐 frontend useReaderAutoPlay）。
    @Expect(r.autoPlay, false)
    @Expect(r.autoPlayIntervalSec, 3)
    r.setAutoPlay(true)
    @Expect(r.autoPlay, true)
    @Expect(s.readerAutoPlay, true)
    r.setAutoPlayIntervalSec(7)
    @Expect(r.autoPlayIntervalSec, 7)
    @Expect(s.readerAutoPlayInterval, 7)
    // 间隔钳 1..10（含设置文件手改越界的回钳）。
    r.setAutoPlayIntervalSec(0)
    @Expect(r.autoPlayIntervalSec, 1)
    r.setAutoPlayIntervalSec(99)
    @Expect(r.autoPlayIntervalSec, 10)
    @Expect(persistCount.v, 4)
    // 从 settings 重建读回。
    let r2 = ReaderModel(s)
    @Expect(r2.autoPlay, true)
    @Expect(r2.autoPlayIntervalSec, 10)
    let s3 = AppSettings()
    s3.readerAutoPlayInterval = -5
    @Expect(ReaderModel(s3).autoPlayIntervalSec, 1)
}

@Test
func autoPlayPumpDrivesTurnAndStopsAtEnd(): Unit {
    // AppModel.pump 驱动：注入假时钟（reader.clock 是注入点），3 页档案间隔 2s。
    let m = AppModel(AppSettings())
    let fake = FakeClock()
    m.reader.clock = { => fake.now }
    m.reader.open("arc1", 0)
    m.reader.setPages(mkImagePages(3))
    m.page.value = Page.Reader("arc1", 1)
    m.setReaderAutoPlayInterval(2)
    m.toggleReaderAutoPlay() // 开：计时从 now=0 起
    fake.now = 1999
    m.pump()
    @Expect(m.reader.index, 0)
    fake.now = 2000
    m.pump()
    @Expect(m.reader.index, 1)
    fake.now = 4000
    m.pump()
    @Expect(m.reader.index, 2)
    // 末真实页之后是虚拟结束页（流索引 3）：先翻到虚拟页，再无法前进才自动停
    //（frontend「到底自动停」）。
    fake.now = 6000
    m.pump()
    @Expect(m.reader.index, 3)
    @Expect(m.reader.onVirtualEnd, true)
    @Expect(m.reader.autoPlay, true)
    fake.now = 8000
    m.pump()
    @Expect(m.reader.index, 3)
    @Expect(m.reader.autoPlay, false)
}

@Test
func autoPlayPumpOffDoesNothing(): Unit {
    let m = AppModel(AppSettings())
    let fake = FakeClock()
    m.reader.clock = { => fake.now }
    m.reader.open("arc1", 0)
    m.reader.setPages(mkImagePages(3))
    m.page.value = Page.Reader("arc1", 1)
    // 未开 autoPlay：时间推进不翻页。
    fake.now = 60000
    m.pump()
    @Expect(m.reader.index, 0)
    // 不在阅读页：开了也不翻（阅读器离场状态闲置）。
    m.toggleReaderAutoPlay()
    m.page.value = Page.Library
    fake.now = 66000
    m.pump()
    @Expect(m.reader.index, 0)
    m.toggleReaderAutoPlay() // 复位，避免影响其他用例（本用例独立实例，防御性）
}

// ---- 无缝续读：流映射 / 虚拟页 / 拼接 ----

@Test
func streamSingleSegmentMapping(): Unit {
    // 单 segment（10 页）：流 = 10 真实 + 末尾 1 虚拟；映射双向一致。
    let r = newReader(mkImagePages(10))
    @Expect(r.pageCount, 10)
    @Expect(r.onVirtualEnd, false)
    @Expect(r.displayTotal, 10) // seamless 关：全局页数
    r.gotoPage(4)
    @Expect(r.displayPage, 5)
    @Expect(r.currentReal.isSome(), true)
    r.gotoPage(10) // 虚拟页
    @Expect(r.onVirtualEnd, true)
    @Expect(r.currentReal.isNone(), true)
    @Expect(r.displayPage, 10) // 虚拟页显示页码 = 总页数（滑条满格）
}

@Test
func appendArchiveRebuildsStream(): Unit {
    let s = AppSettings()
    s.readerSeamlessNext = true
    let r = ReaderModel(s)
    r.open("arc1", 0)
    r.setPages(mkImagePages(4))
    // seamless 开：segment 间虚拟页存在，流 = 4 + 1(虚拟) = 5
    r.gotoPage(4)
    @Expect(r.onVirtualEnd, true)
    // 拼接第二档案（3 页）：流 = 4 + 1 + 3 + 1 = 9；当前位置不变，末尾虚拟顺延
    r.appendArchive("arc2", "第二话", mkImagePages(3))
    @Expect(r.pageCount, 7)
    @Expect(r.index, 4) // 中间虚拟页位置不变
    @Expect(r.onVirtualEnd, true)
    // 末尾虚拟页移到 8
    r.gotoPage(99)
    @Expect(r.index, 8)
    @Expect(r.onVirtualEnd, true)
    // 中间虚拟页「上一页」回 seg0 最后真实页；「下一页」进 seg1 首页
    r.gotoPage(4)
    r.turnPage(true)
    @Expect(r.currentReal.isSome(), true)
    @Expect(r.displayPage, 1) // seamless 开：segment 内页码
    @Expect(r.displayTotal, 3)
    // 去重：同 arcid 重复拼接忽略
    r.appendArchive("arc2", "第二话", mkImagePages(3))
    @Expect(r.pageCount, 7)
}

@Test
func appendNextFailedAndProgressPerSegment(): Unit {
    let s = AppSettings()
    s.readerSeamlessNext = true
    let r = ReaderModel(s)
    r.open("arc1", 0)
    r.setPages(mkImagePages(4))
    r.appendNextFailed("没有下一档案了")
    @Expect(r.appendError, "没有下一档案了")
    r.appendArchive("arc2", "第二话", mkImagePages(3))
    @Expect(r.appendError, "") // 拼接成功清失败态
    // 进度上报：seg2 内页码（arcid 按 segment）
    let reports = ArrayList<String>()
    r.onProgress = { arc, page1 => reports.add("${arc}:${page1}") }
    r.gotoPage(5) // seg1 第 0 页（流 5 = 4 + 1虚拟 + 0）
    @Expect(reports.size, 1)
    @Expect(reports[0], "arc2:1")
    r.gotoPage(7) // seg1 第 2 页（防抖窗口内，flush 补发）
    r.flushProgress()
    @Expect(reports.size, 2)
    @Expect(reports[1], "arc2:3")
    // 虚拟页不上报（也不记 pending）
    r.gotoPage(8)
    r.flushProgress()
    @Expect(reports.size, 2)
    @Expect(r.progressForReport()[0], 0)
}

@Test
func appendTriggerFiresOnEndVirtual(): Unit {
    let s = AppSettings()
    s.readerSeamlessNext = true
    let r = ReaderModel(s)
    r.open("arc1", 0)
    r.setPages(mkImagePages(3))
    let fired = ArrayList<String>()
    r.onAppendNext = { arc => fired.add(arc) }
    r.gotoPage(1) // 普通翻页不触发
    @Expect(fired.size, 0)
    r.gotoPage(3) // 末尾虚拟页 → 触发
    @Expect(fired.size, 1)
    @Expect(fired[0], "arc1")
    // 拼接后中间虚拟页不触发，末尾虚拟页以新尾 segment arcid 触发
    r.appendArchive("arc2", "t2", mkImagePages(2))
    r.gotoPage(3) // 中间虚拟页
    @Expect(fired.size, 1)
    r.gotoPage(6) // 新末尾虚拟页
    @Expect(fired.size, 2)
    @Expect(fired[1], "arc2")
}

@Test
func seamlessTogglePreservesPosition(): Unit {
    let s = AppSettings()
    s.readerSeamlessNext = true
    let r = ReaderModel(s)
    r.open("arc1", 0)
    r.setPages(mkImagePages(4))
    r.appendArchive("arc2", "t2", mkImagePages(3))
    // 站在 seg1 第 1 页（流 6 = 4 + 1 + 1）：关 seamless 后中间虚拟消失，
    // 位置保持同一真实页（流 5），显示语义回全局页码
    r.gotoPage(6)
    @Expect(r.displayPage, 2)
    r.setSeamlessNext(false)
    @Expect(r.currentReal.isSome(), true)
    match (r.currentReal) {
        case Some(p) => @Expect(p, 5)
        case None => @Expect(true, false)
    }
    @Expect(r.displayPage, 6) // 全局页码
    @Expect(r.displayTotal, 7)
    // 再开回 seamless：仍同页，段内页码恢复
    r.setSeamlessNext(true)
    @Expect(r.displayPage, 2)
    @Expect(r.displayTotal, 3)
}

@Test
func gotoDisplayPageBothModes(): Unit {
    let s = AppSettings()
    s.readerSeamlessNext = true
    let r = ReaderModel(s)
    r.open("arc1", 0)
    r.setPages(mkImagePages(4))
    r.appendArchive("arc2", "t2", mkImagePages(3))
    // seamless 开：段内 0 基；当前在 seg0
    r.gotoDisplayPage(2)
    @Expect(r.displayPage, 3)
    // 切到 seg1 后段内导航
    r.gotoPage(5)
    r.gotoDisplayPage(1)
    @Expect(r.displayPage, 2)
    @Expect(r.displayTotal, 3)
    // seamless 关：全局 0 基
    r.setSeamlessNext(false)
    r.gotoDisplayPage(6)
    @Expect(r.displayPage, 7)
}

@Test
func prefetchCrossesSegmentBoundary(): Unit {
    let s = AppSettings()
    s.readerSeamlessNext = true
    let r = ReaderModel(s)
    r.open("arc1", 0)
    r.setPages(mkImagePages(4))
    r.appendArchive("arc2", "t2", mkImagePages(4))
    // seg0 最后真实页（pageList 3）：预取跨边界到 seg1
    r.gotoPage(3)
    @Expect(spreadLabel(r.prefetchTargets()), "[1,2,4,5]")
    // 虚拟页：以最后真实页为基准
    r.gotoPage(9)
    @Expect(r.onVirtualEnd, true)
    @Expect(spreadLabel(r.prefetchTargets()), "[5,6]")
}

@Test
func doublePagePairsWithinSegment(): Unit {
    // 双页配页按 segment 内局部页码：seg1 局部 0 起重新配对（奇数 count 不串段）
    let s = AppSettings()
    s.readerSeamlessNext = true
    s.readerDoublePage = true
    let r = ReaderModel(s)
    r.open("arc1", 0)
    r.setPages(mkImagePages(3)) // seg0: [0,1] [2]
    r.appendArchive("arc2", "t2", mkImagePages(4)) // seg1 局部: [0,1] [2,3]
    r.gotoPage(0)
    @Expect(spreadLabel(r.spreadPages()), "[0,1]")
    // seg1 第一 spread：pageList [3,4]（局部 [0,1]）
    r.gotoPage(5) // 流 5 = seg1 局部 0
    @Expect(spreadLabel(r.spreadPages()), "[3,4]")
    r.turnPage(true)
    @Expect(spreadLabel(r.spreadPages()), "[5,6]")
    // 虚拟页恒单页 spread：turnPage 从 [5,6] 进末尾虚拟页
    r.turnPage(true)
    @Expect(r.onVirtualEnd, true)
    // 虚拟页「上一页」回 seg1 最后真实页并吸附其 spread 首页（局部 2 → [2,3] 首页）
    r.turnPage(false)
    @Expect(spreadLabel(r.spreadPages()), "[5,6]")
}
