package lanlu_client_next.app

import lanlu_client_next.net.PageInfo
import std.collection.ArrayList
import std.time.MonoTime

// 阅读器状态机（T12 从 model.cj 拆出；纯逻辑、无 UI 依赖，T13 的视图全部消费本文件接口）。
//
// 流索引语义（无缝续读，对齐 frontend build-reader-stream）：pageList 是扁平全量真实页
//（可经 appendArchive 追加下一档案），segments 记录每段档案的 (arcid, title, start, count)。
// 流 = 真实页 + 每个 segment 末尾的 virtual-end 项（末尾虚拟页恒存在；segment 间虚拟页
// 仅 seamlessNext 开时存在）。index 是 0 基流索引，且恒为「当前 spread 首页」——双页模式
// 下 gotoPage/turnPage 把落点吸附到所属 spread 首页（配页按 segment 内局部页码配对：
// splitCover 时每段封面 [0] 独占，其后 [1,2],[3,4]…；无 splitCover 时 [0,1],[2,3]…；
// 虚拟页恒为单页 spread，不参与配对）。进度上报只报真实页：(segment arcid, 段内 1 基页码)。

// 进度上报防抖窗口：窗口内连续翻页只记 pending，由 tick()（周期驱动）/flushProgress()
// （离开阅读器前）补发——ledger 记载旧实现「progress 去重丢尾」，停在最末页时最后一次
// 上报必须发出，故任何情况下 pending 都有出口。
public let READER_PROGRESS_DEBOUNCE_MS: Int64 = 900

// chrome（顶栏等阅读器镀铬）自动隐藏超时。计时闭环由 T13 UI 的 FrameHandler 完成
//（每帧比较 now - lastActivityMs），本模型只提供状态与该常量。
public let READER_CHROME_AUTOHIDE_MS: Int64 = 3000

// 阅读模式（对齐 frontend use-reader-settings 的 ReadingMode）。
public enum ReadingMode {
    | SingleLtr   // 单页从左到右
    | SingleRtl   // 单页从右到左（日漫）
    | SingleTtb   // 单页从上到下
    | Webtoon     // 条漫（滚动驱动，不响应按键翻页）

    // settings 持久化用词（与 frontend localStorage 值一致）。
    public func toSettingString(): String {
        match (this) {
            case SingleLtr => "single-ltr"
            case SingleRtl => "single-rtl"
            case SingleTtb => "single-ttb"
            case Webtoon => "webtoon"
        }
    }
}

// 自动播放间隔钳制（1..10 秒）；设置文件手改越界时回钳。
public func clampAutoPlayInterval(n: Int64): Int64 {
    max(1, min(10, n))
}

// 从 settings 词还原模式；非法/缺失值回退 SingleLtr（向后兼容）。
public func parseReadingMode(s: String): ReadingMode {
    match (s) {
        case "single-rtl" => SingleRtl
        case "single-ttb" => SingleTtb
        case "webtoon" => Webtoon
        case _ => SingleLtr
    }
}

// 阅读器方向键。独立定义而不复用 cui 的 Key：本模型不依赖 UI 框架，
// T13 事件层负责把 cui Key 映射到本枚举。
public enum KeyCode {
    | KeyLeft | KeyRight | KeyUp | KeyDown
}

// 当前 spread 的内容 lane：媒体页（视频/音频）各一条 + Book 兜底（恒在，对齐
// client ReaderScreen :1629-1669——即使整页都是媒体也保留「书」入口）。
// Int64 = 0 基页索引。
public enum LaneId <: ToString {
    | Book
    | Video(Int64)
    | Audio(Int64)

    public func toString(): String {
        match (this) {
            case Book => "Book"
            case Video(i) => "Video(${i})"
            case Audio(i) => "Audio(${i})"
        }
    }

    public func equals(other: LaneId): Bool {
        match ((this, other)) {
            case (Book, Book) => true
            case (Video(a), Video(b)) => a == b
            case (Audio(a), Audio(b)) => a == b
            case _ => false
        }
    }
}

// 流中的一段档案：pageList 内的区间 [start, start+count)，title 用于结束页卡片
//（元数据到货后经 setSegmentTitle 回填，可能为空串）。
public class ReaderSegment {
    public let arcid: String
    public var title: String
    public let start: Int64
    public let count: Int64

    public init(arcid: String, title: String, start: Int64, count: Int64) {
        this.arcid = arcid
        this.title = title
        this.start = start
        this.count = count
    }
}

public class ReaderModel {
    private let settings: AppSettings

    // ---- 注入点（生产由 AppModel 接线；测试可替换/留空）----
    // 单调时钟（毫秒）；测试注入假时钟驱动防抖断言。
    public var clock: () -> Int64
    // 设置变更落盘（reader_* 一组键已写入 settings，由回调持久化）。
    public var onPersist: ?() -> Unit = None
    // 进度上报出口：(arcid, 1 基页码)。经防抖调度（maybeReport/tick/flushProgress）。
    public var onProgress: ?(String, Int64) -> Unit = None
    // 预取出口：(arcid, 0 基页索引数组)——当前页前后各 2 页、越界裁剪后的目标。
    public var onPrefetch: ?(String, Array<Int64>) -> Unit = None
    // 无缝续读出口：进入末尾虚拟页时触发（参数 = 尾 segment 的 arcid），
    // AppModel 解析候选并 appendArchive/appendNextFailed 回填（inFlight 防重在 AppModel）。
    public var onAppendNext: ?(String) -> Unit = None

    // ---- 档案状态（只读暴露，内部写）----
    private var _arcid: String = ""
    private var pageList = ArrayList<PageInfo>()
    private var _index: Int64 = 0
    // ---- 无缝续读：segment 流与拼接状态 ----
    private let segments = ArrayList<ReaderSegment>()
    private let _appendedArcids = ArrayList<String>()
    private var _appendError: String = ""   // ""=无失败；appendNextFailed 写入，appendArchive/翻页清除

    // ---- 阅读选项（reader_* 设置；只读暴露，经 setXxx 变更并持久化）----
    private var _mode: ReadingMode = SingleLtr
    private var _doublePage: Bool = false
    private var _splitCover: Bool = false
    private var _longPage: Bool = true
    private var _tapTurnPage: Bool = false
    private var _doubleTapZoom: Bool = false
    private var _autoHide: Bool = false
    private var _seamlessNext: Bool = false
    private var _autoPlay: Bool = false
    private var _autoPlayIntervalSec: Int64 = 3

    // ---- lane / chrome ----
    private var _activeLane: LaneId = Book
    private var _chromeVisible: Bool = true
    private var _lastActivityMs: Int64 = 0

    // ---- 进度防抖状态 ----
    private var lastReportAtMs: ?Int64 = None
    private var pendingReport = false

    public init(s: AppSettings) {
        settings = s
        let start = MonoTime.now()
        clock = { => (MonoTime.now() - start).toMilliseconds() }
        _mode = parseReadingMode(s.readerMode)
        _doublePage = s.readerDoublePage
        _splitCover = s.readerSplitCover
        _longPage = s.readerLongPage
        _tapTurnPage = s.readerTapTurnPage
        _doubleTapZoom = s.readerDoubleTapZoom
        _autoHide = s.readerAutoHide
        _seamlessNext = s.readerSeamlessNext
        _autoPlay = s.readerAutoPlay
        _autoPlayIntervalSec = clampAutoPlayInterval(s.readerAutoPlayInterval)
    }

    public prop arcid: String {
        get() {
            _arcid
        }
    }
    public prop index: Int64 {
        get() {
            _index
        }
    }
    public prop pageCount: Int64 {
        get() {
            pageList.size
        }
    }

    // ---- 流/segment 只读 API（视图层不直接摸流索引，经 display* 系列取值）----

    // 全部 segment（侧边栏分组用；返回快照数组）。
    public prop segmentList: Array<ReaderSegment> {
        get() {
            segments.toArray()
        }
    }
    // 已拼接过的 arcid 集（含首档案；AppModel 候选解析去重用，提交 worker 前取快照）。
    public prop appendedArcids: Array<String> {
        get() {
            _appendedArcids.toArray()
        }
    }
    // 拼接失败原因（""=无；结束页卡片显示「没有下一档案」态）。
    public prop appendError: String {
        get() {
            _appendError
        }
    }
    // 当前流项所属 segment 下标。
    public func activeSegmentIndex(): Int64 {
        segmentOfStream(_index)
    }
    // 当前 spread 是否为虚拟结束页。
    public prop onVirtualEnd: Bool {
        get() {
            realOfStream(_index).isNone() && pageList.size > 0
        }
    }
    // 当前 spread 首页的真实页 pageList 索引（虚拟页/空表为 None）。
    public prop currentReal: ?Int64 {
        get() {
            realOfStream(_index)
        }
    }
    // 显示总页数：seamless 开 = 当前 segment 页数；关 = 全量真实页（frontend
    // sliderTotalPages 语义）。
    public prop displayTotal: Int64 {
        get() {
            if (pageList.size == 0) {
                return 0
            }
            if (_seamlessNext) {
                return segments[segmentOfStream(_index)].count
            }
            pageList.size
        }
    }
    // 显示页码（1 基；虚拟页 = displayTotal，滑条满格、胶囊由 UI 显示「完」）。
    public prop displayPage: Int64 {
        get() {
            match (realOfStream(_index)) {
                case Some(p) => displayPageOfReal(p)
                case None => displayTotal
            }
        }
    }
    // 真实页 pageList 索引 → 1 基显示页码（seamless 开 = 段内页码，关 = 全局页码）。
    public func displayPageOfReal(p: Int64): Int64 {
        if (_seamlessNext) {
            return p - segments[segmentOfReal(p)].start + 1
        }
        p + 1
    }
    // 当前 segment 标题（结束页卡片「已读完《X》」；元数据未回填时为空串，UI 回退元数据）。
    public prop activeSegmentTitle: String {
        get() {
            if (segments.size == 0) {
                return ""
            }
            segments[segmentOfStream(_index)].title
        }
    }
    // 当前虚拟页的下一 segment 标题（中间虚拟页才有；末尾虚拟页/非虚拟页为空串）。
    public prop nextSegmentTitle: String {
        get() {
            let i = segmentOfStream(_index)
            if (realOfStream(_index).isSome() || i + 1 >= segments.size) {
                return ""
            }
            segments[i + 1].title
        }
    }
    public prop mode: ReadingMode {
        get() {
            _mode
        }
    }
    public prop doublePage: Bool {
        get() {
            _doublePage
        }
    }
    public prop splitCover: Bool {
        get() {
            _splitCover
        }
    }
    public prop longPage: Bool {
        get() {
            _longPage
        }
    }
    public prop tapTurnPage: Bool {
        get() {
            _tapTurnPage
        }
    }
    public prop doubleTapZoom: Bool {
        get() {
            _doubleTapZoom
        }
    }
    public prop autoHide: Bool {
        get() {
            _autoHide
        }
    }
    public prop seamlessNext: Bool {
        get() {
            _seamlessNext
        }
    }
    public prop autoPlay: Bool {
        get() {
            _autoPlay
        }
    }
    public prop autoPlayIntervalSec: Int64 {
        get() {
            _autoPlayIntervalSec
        }
    }
    public prop activeLane: LaneId {
        get() {
            _activeLane
        }
    }
    public prop chromeVisible: Bool {
        get() {
            _chromeVisible
        }
    }
    // 最近一次活动（noteActivity/toggleChrome/open）的时钟读数，供 T13 每帧算 elapsed。
    public prop lastActivityMs: Int64 {
        get() {
            _lastActivityMs
        }
    }

    // 页信息只读访问（T13 渲染取 id/pageType 用）；越界返回 None。
    public func pageAt(i: Int64): ?PageInfo {
        if (i < 0 || i >= pageList.size) {
            return None
        }
        pageList[i]
    }

    // 真实页所属档案 arcid（无缝续读拼接后，不同 segment 的页属不同档案：
    // 图片 key/url、媒体下载都必须按页取 arcid，不能再用档案级 _arcid）。
    public func arcidOfReal(p: Int64): String {
        if (segments.size == 0) {
            return _arcid
        }
        segments[segmentOfReal(p)].arcid
    }

    // ---- 生命周期 ----

    // 打开档案：startIndex 为 0 基页索引（可能来自过期 progress，页表到货时再钳制）。
    // 换档案前把上一档案的 pending 尾巴发掉（去重丢尾教训）。
    public func open(arcid: String, startIndex: Int64): Unit {
        if (pendingReport) {
            fireProgress()
        }
        _arcid = arcid
        pageList = ArrayList<PageInfo>()
        segments.clear()
        segments.add(ReaderSegment(arcid, "", 0, 0))
        _appendedArcids.clear()
        _appendedArcids.add(arcid)
        _appendError = ""
        _index = if (startIndex < 0) {
            0
        } else {
            startIndex
        }
        _activeLane = Book
        _chromeVisible = true
        pendingReport = false
        lastReportAtMs = None
        _lastActivityMs = clock()
    }

    // 页表到货（首 segment；拼接走 appendArchive）：钳制起始页并吸附 spread 首页，重算 lane。
    public func setPages(list: ArrayList<PageInfo>): Unit {
        pageList = list
        segments[0] = ReaderSegment(segments[0].arcid, segments[0].title, 0, list.size)
        let total = pageList.size
        if (total == 0) {
            _index = 0
            _activeLane = Book
            return
        }
        if (_index > streamLength() - 1) {
            _index = streamLength() - 1
        }
        _index = snapToSpreadStart(_index)
        refreshLaneForSpread()
        firePrefetch() // 页表到货补一次预取（open 时没有 moveTo，邻居页全靠这次）
    }

    // ---- 翻页 ----

    // 翻到 0 基流索引 n：钳制（含末尾虚拟页）→ 吸附 spread 首页 → 换 spread 则重算
    // lane → 上报（防抖）→ 预取 → 末尾虚拟页触发续读解析。
    public func gotoPage(n: Int64): Unit {
        let total = streamLength()
        if (total == 0) {
            return
        }
        var next = n
        if (next < 0) {
            next = 0
        }
        if (next > total - 1) {
            next = total - 1
        }
        moveTo(next)
    }

    // 按 0 基显示页码翻页（UI/AppModel 入口；流索引由模型内部换算）：
    // seamless 开 = 当前 segment 内页码（0 基），关 = 全局真实页码（0 基）。
    public func gotoDisplayPage(d0: Int64): Unit {
        if (pageList.size == 0) {
            return
        }
        if (_seamlessNext) {
            let i = segmentOfStream(_index)
            var local = d0
            if (local < 0) {
                local = 0
            }
            if (local > segments[i].count - 1) {
                local = segments[i].count - 1
            }
            gotoPage(streamStartOf(i) + local)
            return
        }
        var p = d0
        if (p < 0) {
            p = 0
        }
        if (p > pageList.size - 1) {
            p = pageList.size - 1
        }
        gotoPage(streamOfReal(p))
    }

    // 按阅读顺序步进一个 spread。forward 是逻辑方向（下一页/上一页），与物理按键的
    // 换算（RTL 反转等）全部在 keyDirection 完成，二者组合不会二次反转。
    // webtoon 由滚动驱动，不响应按键翻页。虚拟页上「上一页」回本 segment 最后真实页
    //（moveTo 内按双页/拆分封面规则吸附，对齐 frontend computeCollectionEndReturnRealPage）。
    public func turnPage(forward: Bool): Unit {
        if (isWebtoon()) {
            return
        }
        let total = streamLength()
        if (total == 0) {
            return
        }
        if (forward) {
            let c = _index + spreadSizeAt(_index)
            if (c > total - 1) {
                return
            } // 已在末流项（末尾虚拟页）
            moveTo(c)
        } else {
            if (_index <= 0) {
                return
            } // 已在首 spread
            match (realOfStream(_index)) {
                case Some(_) => moveTo(_index - 1)
                case None =>
                    // 虚拟页 → 本 segment 最后真实页；空 segment（无真实页）退到上一流项。
                    let i = segmentOfStream(_index)
                    if (segments[i].count == 0) {
                        moveTo(_index - 1)
                    } else {
                        moveTo(streamStartOf(i) + segments[i].count - 1)
                    }
            }
        }
    }

    // 方向键 → 逻辑翻页方向（true=阅读顺序下一页）。对齐 frontend
    // useReaderKeyboardNavigation：LTR 右=next；RTL 反转；TTB 下=next（参考实现未排除
    // 左右键，故 TTB 左=prev 右=next）；webtoon 一律 None。
    public func keyDirection(key: KeyCode): Option<Bool> {
        match (_mode) {
            case Webtoon => None
            case SingleRtl => match (key) {
                    case KeyLeft => Some(true)
                    case KeyRight => Some(false)
                    case _ => None
                }
            case SingleTtb => match (key) {
                    case KeyDown => Some(true)
                    case KeyUp => Some(false)
                    case KeyLeft => Some(false)
                    case KeyRight => Some(true)
                }
            case SingleLtr => match (key) {
                    case KeyRight => Some(true)
                    case KeyLeft => Some(false)
                    case _ => None
                }
        }
    }

    // ---- spread / lane ----

    // 当前 spread 的真实页 pageList 索引（显示序）：单页 [i]；双页按 splitCover 在
    // segment 内配页（splitCover：封面 [0] 独占，其后 [1,2],[3,4]…；无 splitCover：
    // [0,1],[2,3]…），RTL 双页顺序反转（对齐 frontend ReaderPageContainer :2520-2565
    // 校正规则）。虚拟结束页不参配，返回空数组（UI 经 onVirtualEnd 走结束卡片）。
    public func spreadPages(): Array<Int64> {
        if (pageList.size == 0) {
            return Array<Int64>(0, repeat: 0)
        }
        let s = snapToSpreadStart(_index)
        match (realOfStream(s)) {
            case None => Array<Int64>(0, repeat: 0)
            case Some(p) =>
                if (spreadSizeAt(s) == 1) {
                    return [p]
                }
                if (isRtl()) {
                    return [p + 1, p]
                }
                [p, p + 1]
        }
    }

    // 当前 spread 的内容 lane：spread 内每个 video/audio 页一条（页索引升序）+ Book 兜底
    //（对齐 client ReaderScreen :1629-1669）。虚拟页只有 Book。
    public func laneSpecs(): Array<LaneId> {
        let lanes = ArrayList<LaneId>()
        if (pageList.size > 0) {
            let s = snapToSpreadStart(_index)
            match (realOfStream(s)) {
                case None => ()
                case Some(p) =>
                    let end = p + spreadSizeAt(s)
                    var i = p
                    while (i < end) {
                        let t = pageList[i].pageType
                        if (t == "video") {
                            lanes.add(Video(i))
                        } else if (t == "audio") {
                            lanes.add(Audio(i))
                        }
                        i++
                    }
            }
        }
        lanes.add(Book)
        lanes.toArray()
    }

    // 当前 spread 自身承载的媒体内容。它只由页表/布局决定，与 dock 当前展开哪条
    // lane 无关；AppModel 用它管理媒体生命周期，ReaderStage 用它选择内容舞台。
    public func spreadMediaLane(): LaneId {
        for (lane in laneSpecs()) {
            match (lane) {
                case Book => ()
                case _ => return lane
            }
        }
        Book
    }

    // 手动切 lane：不翻页；不在当前 lanes 里的 lane 忽略（参考实现 activeLane 落回 lanes[0]，
    // 这里选择静默忽略以保持状态机简单）。
    public func setActiveLane(l: LaneId): Unit {
        for (x in laneSpecs()) {
            if (x.equals(l)) {
                _activeLane = l
                return
            }
        }
    }

    // ---- chrome ----

    public func toggleChrome(): Unit {
        _chromeVisible = !_chromeVisible
        _lastActivityMs = clock()
    }

    // 有用户活动（鼠标移动/按键等）时调用：刷新活动时间；autoHide 开启时重新亮出 chrome。
    public func noteActivity(): Unit {
        _lastActivityMs = clock()
        if (_autoHide) {
            _chromeVisible = true
        }
    }

    // ---- 进度 ----

    // 待上报进度：(segment 内 1 基页码, segment 页数)——服务端 progress 语义为 1 基，
    // arcid 在 fireProgress 取当前 segment（对齐 frontend activeLocalPage）。
    // 虚拟页不上报，返回 (0, 0)。
    public func progressForReport(): (Int64, Int64) {
        match (realOfStream(_index)) {
            case Some(p) =>
                let seg = segments[segmentOfReal(p)]
                (p - seg.start + 1, seg.count)
            case None => (0, 0)
        }
    }

    // 周期驱动（T13 FrameHandler / AppModel.pump 每帧调用）：防抖窗口到后补发 pending 尾巴。
    public func tick(): Unit {
        if (!pendingReport) {
            return
        }
        match (lastReportAtMs) {
            case Some(t) =>
                if (clock() - t >= READER_PROGRESS_DEBOUNCE_MS) {
                    fireProgress()
                }
            case None => fireProgress()
        }
    }

    // 离开阅读器/换档案前调用：pending 立即发，不等防抖窗口（尾巴不丢）。
    public func flushProgress(): Unit {
        if (pendingReport) {
            fireProgress()
        }
    }

    // ---- 阅读选项变更（写 settings + 落盘）----

    public func setMode(m: ReadingMode): Unit {
        _mode = m
        settings.readerMode = m.toSettingString()
        persist()
        afterLayoutChange()
    }

    public func setDoublePage(v: Bool): Unit {
        _doublePage = v
        settings.readerDoublePage = v
        persist()
        afterLayoutChange()
    }

    public func setSplitCover(v: Bool): Unit {
        _splitCover = v
        settings.readerSplitCover = v
        persist()
        afterLayoutChange()
    }

    public func setLongPage(v: Bool): Unit {
        _longPage = v
        settings.readerLongPage = v
        persist()
    }

    public func setTapTurnPage(v: Bool): Unit {
        _tapTurnPage = v
        settings.readerTapTurnPage = v
        persist()
    }

    public func setDoubleTapZoom(v: Bool): Unit {
        _doubleTapZoom = v
        settings.readerDoubleTapZoom = v
        persist()
    }

    public func setAutoHide(v: Bool): Unit {
        _autoHide = v
        settings.readerAutoHide = v
        persist()
    }

    // 无缝续读开关：持久化 + 流映射重建（segment 间虚拟页随开关出现/消失），
    // 尽量保持当前位置不跳（真实页按 pageList 索引换算回新流索引；虚拟页留原 segment）。
    public func setSeamlessNext(v: Bool): Unit {
        if (v == _seamlessNext) {
            return
        }
        let real = realOfStream(_index)
        let seg = segmentOfStream(_index)
        _seamlessNext = v
        settings.readerSeamlessNext = v
        persist()
        if (pageList.size == 0) {
            _index = 0
            return
        }
        match (real) {
            case Some(p) => _index = snapToSpreadStart(streamOfReal(p))
            case None => _index = virtualStreamIndexOf(seg)
        }
    }

    // 自动播放开关。翻页驱动在 AppModel.pump（每帧计时调 readerTurnPage），
    // 模型只持久化选项（对齐 frontend useReaderAutoPlay：到底自动停由驱动侧负责）。
    public func setAutoPlay(v: Bool): Unit {
        _autoPlay = v
        settings.readerAutoPlay = v
        persist()
    }

    // 自动播放间隔（秒）：钳 1..10（frontend ReaderSettingsSheet 的滑条范围）。
    public func setAutoPlayIntervalSec(n: Int64): Unit {
        _autoPlayIntervalSec = clampAutoPlayInterval(n)
        settings.readerAutoPlayInterval = _autoPlayIntervalSec
        persist()
    }

    // ---- 内部 ----

    private func moveTo(n: Int64): Unit {
        let next = snapToSpreadStart(n)
        let spreadChanged = next != _index
        _index = next
        if (spreadChanged) {
            refreshLaneForSpread()
        }
        if (spreadChanged) {
            _appendError = ""
        } // 离开失败现场：结束页回到解析/加载态
        maybeReport()
        firePrefetch()
        maybeFireAppendNext()
    }

    // ---- 流索引 ⇔ 真实页映射（segment 增删/开关切换时经这些函数换算，无缓存表）----

    // 流总长：真实页 + 虚拟页（末尾恒 1；segment 间仅 seamlessNext 开时计入）。
    private func streamLength(): Int64 {
        pageList.size + if (_seamlessNext) {
            segments.size
        } else {
            min(segments.size, 1)
        }
    }

    // segment i 之前流内的虚拟页数。
    private func virtualsBeforeSegment(i: Int64): Int64 {
        if (_seamlessNext) {
            return i
        }
        0
    }

    // segment i 第一个真实页的流索引。
    private func streamStartOf(i: Int64): Int64 {
        segments[i].start + virtualsBeforeSegment(i)
    }

    // segment i 的 virtual-end 项流索引。
    private func virtualStreamIndexOf(i: Int64): Int64 {
        streamStartOf(i) + segments[i].count
    }

    // 真实页 pageList 索引 → 所属 segment 下标。
    private func segmentOfReal(p: Int64): Int64 {
        var i = segments.size - 1
        while (i > 0 && segments[i].start > p) {
            i--
        }
        i
    }

    // 真实页 pageList 索引 → 流索引。
    private func streamOfReal(p: Int64): Int64 {
        let i = segmentOfReal(p)
        streamStartOf(i) + (p - segments[i].start)
    }

    // 流索引 → 所属 segment 下标（虚拟页归本 segment）。
    private func segmentOfStream(s: Int64): Int64 {
        var i = segments.size - 1
        while (i > 0 && streamStartOf(i) > s) {
            i--
        }
        i
    }

    // 流索引 → 真实页 pageList 索引；虚拟页/越界返回 None。
    private func realOfStream(s: Int64): ?Int64 {
        if (s < 0 || segments.size == 0) {
            return None
        }
        let i = segmentOfStream(s)
        let local = s - streamStartOf(i)
        if (local < 0 || local >= segments[i].count) {
            return None
        }
        segments[i].start + local
    }

    // 进入末尾虚拟页 → 触发续读解析（中间虚拟页的下一档案已在流内，不触发）。
    private func maybeFireAppendNext(): Unit {
        if (segments.size == 0) {
            return
        }
        if (realOfStream(_index).isSome()) {
            return
        }
        if (segmentOfStream(_index) != segments.size - 1) {
            return
        }
        match (onAppendNext) {
            case Some(cb) => cb(segments[segments.size - 1].arcid)
            case None => ()
        }
    }

    private func isWebtoon(): Bool {
        match (_mode) {
            case Webtoon => true
            case _ => false
        }
    }

    private func isRtl(): Bool {
        match (_mode) {
            case SingleRtl => true
            case _ => false
        }
    }

    // 双页生效条件：双页开关开且非条漫（条漫滚动驱动，不做 spread 配页；
    // 不破坏 doublePage 设置本身——切回单页模式即恢复）。
    private func doublePageEffective(): Bool {
        _doublePage && !isWebtoon()
    }

    // 流索引 s 所属 spread 的首项流索引（虚拟页恒单页；真实页按 segment 内局部页码配对）。
    private func snapToSpreadStart(s: Int64): Int64 {
        match (realOfStream(s)) {
            case None => s
            case Some(p) =>
                let i = segmentOfReal(p)
                let local = p - segments[i].start
                streamStartOf(i) + snapLocalToSpreadStart(segments[i], local)
        }
    }

    // segment 内局部页码 → 所属 spread 的首页局部页码。
    private func snapLocalToSpreadStart(seg: ReaderSegment, local: Int64): Int64 {
        if (!doublePageEffective()) {
            return local
        }
        if (_splitCover) {
            if (local == 0) {
                return 0
            }
            return if (local % 2 == 1) {
                local
            } else {
                local - 1
            }
        }
        if (local % 2 == 0) {
            local
        } else {
            local - 1
        }
    }

    // 首项为流索引 s 的 spread 的页数（1 或 2；虚拟页/末页落单/splitCover 封面为 1）。
    private func spreadSizeAt(s: Int64): Int64 {
        match (realOfStream(s)) {
            case None => 1
            case Some(p) =>
                let seg = segments[segmentOfReal(p)]
                let local = p - seg.start
                if (!doublePageEffective()) {
                    return 1
                }
                if (local == 0 && _splitCover) {
                    return 1
                }
                if (local + 1 > seg.count - 1) {
                    return 1
                }
                2
        }
    }

    // 换 spread 后：若存在媒体 lane 自动激活第一个，否则 Book 兜底
    //（对齐 client ReaderScreen :1651-1669 的 preferredLane 逻辑）。
    private func refreshLaneForSpread(): Unit {
        for (l in laneSpecs()) {
            match (l) {
                case Book => ()
                case _ =>
                    _activeLane = l
                    return
            }
        }
        _activeLane = Book
    }

    // 布局相关选项（模式/双页/splitCover）变更后：当前页重新吸附 spread 首页，
    // spread 变了就重算 lane（对齐 frontend 容器切换 splitCover 时的页码校正）。
    private func afterLayoutChange(): Unit {
        if (pageList.size == 0) {
            return
        }
        let next = snapToSpreadStart(_index)
        if (next != _index) {
            _index = next
            refreshLaneForSpread()
        }
    }

    private func maybeReport(): Unit {
        if (realOfStream(_index).isNone()) {
            return
        } // 虚拟页不上报（也不记 pending）
        match (lastReportAtMs) {
            case Some(t) =>
                if (clock() - t >= READER_PROGRESS_DEBOUNCE_MS) {
                    fireProgress()
                } else {
                    pendingReport = true
                }
            case None => fireProgress()
        }
    }

    private func fireProgress(): Unit {
        pendingReport = false
        lastReportAtMs = Some(clock())
        match (realOfStream(_index)) {
            case Some(p) =>
                let seg = segments[segmentOfReal(p)]
                match (onProgress) {
                    case Some(cb) => cb(seg.arcid, p - seg.start + 1)
                    case None => ()
                }
            case None => ()
        }
    }

    private func firePrefetch(): Unit {
        match (onPrefetch) {
            case Some(cb) => cb(_arcid, prefetchTargets())
            case None => ()
        }
    }

    // 预取目标：当前真实页前后各 2 页（pageList 0 基，跨 segment 边界照常），越界裁剪。
    // 虚拟页上以本 segment 最后真实页为基准。
    public func prefetchTargets(): Array<Int64> {
        let total = pageList.size
        let out = ArrayList<Int64>()
        if (total == 0) {
            return out.toArray()
        }
        let base = match (realOfStream(_index)) {
            case Some(p) => p
            case None => total - 1
        }
        for (d in [-2, -1, 1, 2]) {
            let i = base + d
            if (i >= 0 && i < total) {
                out.add(i)
            }
        }
        out.toArray()
    }

    // ---- 无缝续读：拼接回填（AppModel worker drain 调用，UI 线程）----

    // 追加下一档案：segment 追加到流尾并重建映射（当前位置不变，末尾虚拟页顺延）。
    // appendedArcids 去重——同一档案重复回调静默忽略。
    public func appendArchive(arcid: String, title: String, pages: ArrayList<PageInfo>): Unit {
        if (arcid.size == 0 || _appendedArcids.contains(arcid)) {
            return
        }
        _appendedArcids.add(arcid)
        let start = pageList.size
        for (p in pages) {
            pageList.add(p)
        }
        segments.add(ReaderSegment(arcid, title, start, pages.size))
        _appendError = ""
    }

    // 拼接失败/无候选回填（结束页卡片「没有下一档案」态）。
    public func appendNextFailed(reason: String): Unit {
        _appendError = reason
    }

    // 元数据到货回填 segment 标题（结束页卡片「已读完《X》」）。
    public func setSegmentTitle(arcid: String, title: String): Unit {
        for (i in 0..segments.size) {
            if (segments[Int64(i)].arcid == arcid) {
                segments[Int64(i)].title = title
                return
            }
        }
    }

    private func persist(): Unit {
        match (onPersist) {
            case Some(cb) => cb()
            case None => ()
        }
    }
}
