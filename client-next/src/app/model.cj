package lanlu_client_next.app

import cui.{FileDialogRequest, FileDialogResult, PixelReleaser, State, Toaster, ToastKind, clearImageCache,
    clearPixelImages, onPixelImageEvicted, pixelUploadPerfReset, pixelUploadPerfStats, stageNativePixelImage}
import lanlu_client_next.i18n.*
import lanlu_client_next.img.*
import lanlu_client_next.net.*
import std.collection.{ArrayList, HashMap, HashSet}
import std.convert.Parsable
import std.fs.{Directory, File, FileInfo, Path, exists}
import std.io.OutputStream
import std.sync.Mutex
import std.time.MonoTime
import libavformat_ffi.{ExtractedSubtitleTrack, SubtitleCancelToken, SubtitleStreamInfo, probeSubtitleStreams}

// 排序字段映射：与 ui 层 SORT_LABELS 按下标一一对应（改动须两边同步）。
public let SEARCH_SORT_FIELDS = ["title", "created_at", "updated_at", "lastread", "pagecount", "release_at"]

// 浏览模式：分类行上限（母计划 §7 防页面过长）与每行条目数（对齐 frontend getDiscover 默认 count=12）。
public let BROWSE_CATEGORY_ROW_LIMIT: Int64 = 8
public let BROWSE_ROW_SIZE: Int64 = 12

// 图片解码上限（最长边物理像素，0=不缩）：封面按最大展示位（详情 hero 200vp @2x）给 400，
// 阅读页按 2000 封顶，侧栏/编辑器缩略图按 300。按 key 前缀分档、档位固定，故内存
// staged/纹理 key 无需带尺寸；磁盘缓存存原始字节，缩小只发生在解码期，各尺寸共用同一
// 磁盘缓存条目（thumb: 与 page: 经 rawKeyFor 映射为同一 page: 原始 key，磁盘只存
// 一份原始字节，解码档不同；athumb: 归并 asset:<id> 与封面共享原始缓存；
// backdrop 与普通封面共享 asset:<id> 原始缓存）。
private let ASSET_DECODE_MAX_DIM: Int32 = 400
private let PAGE_DECODE_MAX_DIM: Int32 = 2000
private let THUMB_DECODE_MAX_DIM: Int32 = 300

// 磁盘缓存 sweep：启动一次之外按周期/写入量补扫（#10）。阈值沿用既有 2GB。
private let SWEEP_MAX_BYTES: Int64 = 2 * 1024 * 1024 * 1024
private let SWEEP_INTERVAL_MS: Int64 = 3600000 // 每小时兜底一次
private let SWEEP_WRITE_TRIGGER_BYTES: Int64 = 512 * 1024 * 1024 // 累计新写入超 512MB 提前补扫

// key 前缀 → 解码尺寸档位（asset:=封面/资产，page:=阅读页，thumb:=缩略图，
// athumb:=资产缩略图，按 thumb 档解码——详情页页面预览的自定义缩略图用，显示位
// 远小于 asset 的 400 档）。
private func decodeMaxDimension(key: String): Int32 {
    if (key.startsWith("asset:")) {
        return ASSET_DECODE_MAX_DIM
    }
    if (key.startsWith("page:")) {
        return PAGE_DECODE_MAX_DIM
    }
    if (key.startsWith("thumb:")) {
        return THUMB_DECODE_MAX_DIM
    }
    if (key.startsWith("athumb:")) {
        return THUMB_DECODE_MAX_DIM
    }
    return 0
}

// 展示 key → 原始资源 key（网络去重与磁盘缓存的粒度）：thumb: 与 page: 共用同一
// 原始页面字节（仅解码档不同），映射为 page: 使磁盘只存一份；athumb: 归并回
// asset:<id>（与封面共享同一原始缓存，磁盘缓存键不变、不重复下载）；backdrop 展示 key
// 不在此映射（其下载方显式使用 asset:<id> 原始 key，见 requestBackdrop 系列）。
// asset:/page: 本身即原始 key，原样返回。
private func rawKeyFor(key: String): String {
    if (key.startsWith("thumb:")) {
        return "page:${key.removePrefix("thumb:")}"
    }
    if (key.startsWith("athumb:")) {
        return "asset:${key.removePrefix("athumb:")}"
    }
    key
}

// 浏览模式的一行（随机推荐或某个分类）。元素内部字段可变；任何变更后须整体重赋值
// browseRows（或赋回原值）推进 State 代次，视图才会重绘。
public class BrowseRow {
    public var key: String = "" // "random" 或 <catid>（worker 任务名 row:<key>）
    public var title: String = ""
    public var catid: String = "" // 随机行为空串
    public var items = SearchItemView.empty()
    public var requested = false // 已提交过加载任务（分类到达后补建行不复用旧任务）
    public var loading = true
    public var failed = false
}

// 上传抽屉的单文件状态。对象字段只在 UI 线程修改；工作线程通过 ApiWorker.post
// 投递不可变进度元组，pump 收件后再推进 uploadFiles 的 State 代次。
public class UploadFileItem {
    public var id: String = ""
    public var path: String = ""
    public var name: String = ""
    public var size: Int64 = 0
    public var categoryId: Int64 = 0
    public var progress: Int64 = 0
    public var status: String = "queued"
    public var message: String = ""
}

// 在线下载任务状态。与 UploadFileItem 同一线程约束：对象字段只在 UI 线程修改，
// 工作线程通过 ApiWorker.post 投递不可变进度元组，pump 收件后再推进 downloadTasks。
public class DownloadTaskItem {
    public var id: String = ""
    public var url: String = ""
    public var categoryId: Int64 = 0
    public var progress: Int64 = 0
    public var status: String = "queued"
    public var message: String = ""
}

private func metadataTagsJson(raw: String): String {
    let out = StringBuilder()
    out.append("[")
    var first = true
    for (part in raw.split(",")) {
        let tag = part.trimAscii()
        if (tag.size == 0) {
            continue
        }
        if (!first) {
            out.append(",")
        }
        out.append(jsonQuote(tag))
        first = false
    }
    out.append("]")
    out.toString()
}

private func metadataRootBody(title: String, description: String, tags: String, releaseAt: String): String {
    let dateField = if (releaseAt.trimAscii().size > 0) {
        ",\"release_at\":${jsonQuote(releaseAt.trimAscii())}"
    } else {
        ""
    }
    "{\"title\":${jsonQuote(title)},\"type\":0,\"description\":${jsonQuote(description)}," +
        "\"tags\":${metadataTagsJson(tags)}${dateField}}"
}

private func parsePositiveInt(raw: String, fallback: Int64): Int64 {
    try {
        let value = Int64.parse(raw.trimAscii())
        if (value > 0) {
            value
        } else {
            fallback
        }
    } catch (_: Exception) {
        fallback
    }
}

// 图片下载写入器：CacheWriter 接口实现，按展示 key 分派到 LanluApi 流式下载接口。
// 用接口而非函数闭包：仓颉 1.1.3 运行时缺陷——被函数参数传递的闭包在 spawn 线程
// 中调用时若写捕获字段会触发 GC WriteStaticRef 屏障 SIGSEGV；接口方法调用不触发
//（见 image_cache.cj CacheWriter 注释与探针验证）。
private class ImageWriter <: CacheWriter {
    let owner: AppModel
    let a: LanluApi
    let key: String
    init(owner: AppModel, a: LanluApi, key: String) {
        this.owner = owner
        this.a = a
        this.key = key
    }
    public func writeTo(output: OutputStream): Int64 {
        let n = if (key.startsWith("asset:")) {
            a.downloadAssetTo(Int64.parse(key.removePrefix("asset:")), output)
        } else if (key.startsWith("page:")) {
            // page:<arcid>:<pagePath>（pagePath 本身可能含冒号，只切第一个）
            let rest = key.removePrefix("page:")
            let sep = rest.indexOf(":") ?? 0
            a.downloadPageTo(rest[0..sep], rest[(sep + 1)..rest.size], output)
        } else if (key.startsWith("thumb:")) {
            // thumb:<arcid>:<pagePath>：与 page: 同一下载通道（原始字节），仅解码档不同。
            let rest = key.removePrefix("thumb:")
            let sep = rest.indexOf(":") ?? 0
            a.downloadPageTo(rest[0..sep], rest[(sep + 1)..rest.size], output)
        } else if (key.startsWith("athumb:")) {
            // athumb:<assetId>：资产缩略图展示 key，与 asset: 同一下载通道（原始字节），
            // 仅解码档不同（300 vs 400）。
            a.downloadAssetTo(Int64.parse(key.removePrefix("athumb:")), output)
        } else {
            throw Exception("未知图片 key: ${key}")
        }
        // 只在缓存未命中时执行，返回字节即本次新落盘量（#10 周期 sweep 的写入触发计数）。
        owner.noteCacheWrite(n)
        return n
    }
}

// NativeDecodedImage 的释放适配器：把 vips 原生像素的释放权交给 cui 的 staged 条目
//（接口而非闭包：规避仓颉 1.1.3 闭包作为参数跨线程写字段触发 GC 屏障 SIGSEGV）。
private class NativeImageReleaser <: PixelReleaser {
    let img: NativeDecodedImage
    init(img: NativeDecodedImage) {
        this.img = img
    }
    public func release(): Unit {
        img.close()
    }
}

// 详情页多级编辑草稿。根层编辑档案，子层逐页编辑；草稿只在 UI 线程修改。
public class AppModel {
    public let page = State<Page>(Page.Login)
    // 页面过渡（交叉淡化）：navigate() 不立即切页，先置 pending 标志让
    // PageTransition 在下一帧捕获旧页面（GPU 快照），捕获完成后
    // commitPendingPage() 才真正切页。直接赋 page.value（快照播种/测试）跳过动画。
    public var pageTransitionPending = false
    private var pendingPage: ?Page = None
    public let toaster = Toaster()
    public var settings: AppSettings
    private let localizer = Localizer()
    public let language: State<String>
    public var api: ?LanluApi = None
    // 离线缓存（响应快照 + 进度队列）：按 active 服务器地址懒加载；打开失败为 None（不阻断）。
    private var offlineCache: ?OfflineCache = None
    // 启动预热（仅正常启动由 main.cj 注入）：RocksDB open 与字体预热/设置加载并行，
    // 首次用缓存时 join——拿到的实例与同步打开完全相同，失败重试语义也不变。
    private var offlineCachePrewarm: ?Future<?OfflineCache> = None
    // 离线回退通知：worker 线程 mark（仅方法调用，规避 cjc 1.1.3 GC 屏障缺陷），UI pump 轮询 take。
    private let offlineNotice = OfflineNotice()
    private var offlineToastShown = false
    public let worker = ApiWorker()

    // 书库
    public let searchText = State<String>("")
    public let autocompleteSuggestions = State<ArrayList<TagSuggestion>>(ArrayList<TagSuggestion>())
    public let autocompleteQuery = State<String>("")
    public let autocompleteLoading = State<Bool>(false)
    public let autocompleteVisible = State<Bool>(false)
    private var autocompleteRequestId: Int64 = 0
    private var autocompleteTaskName: String = ""
    public let items = State<SearchItemView>(SearchItemView.empty())
    public let loading = State<Bool>(false)
    public let recordsTotal = State<Int64>(0)
    public let currentPage = State<Int64>(1)
    public var query = SearchQuery()
    public let categories = State<ArrayList<CategoryItem>>(ArrayList<CategoryItem>())
    public let categoryIndex = State<Int64>(0)
    // 工具条排序/方向默认：创建时间、降序（新档在前；frontend 首页默认亦按创建时间倒序）。
    // SEARCH_SORT_FIELDS[1]=created_at，orderIndex=1=desc。
    public let sortIndex = State<Int64>(1)
    public let orderIndex = State<Int64>(1)
    public let favOnly = State<Bool>(false)
    public let newOnly = State<Bool>(false)
    public let untaggedOnly = State<Bool>(false)
    public let dateFrom = State<String>("")
    public let dateTo = State<String>("")
    // 高级筛选弹窗由标题栏打开、书库页承载，因此可见性与草稿状态归模型统一持有。
    // 草稿仅在「应用」时写回查询状态；取消不会污染当前结果。
    public let advancedFilterOpen = State<Bool>(false)
    public let advancedSortIndex = State<Int64>(0)
    public let advancedOrderIndex = State<Int64>(0)
    public let advancedFavOnly = State<Bool>(false)
    public let advancedNewOnly = State<Bool>(false)
    public let advancedUntaggedOnly = State<Bool>(false)
    public let advancedTankGroupIndex = State<Int64>(0)
    public let advancedDateFrom = State<String>("")
    public let advancedDateTo = State<String>("")

    // ---- 多选（书库网格与合集成员列表共用一套状态）----
    // 条目 key 规则：档案用 arcid，tank 条目用其 tankoubon_id（与 SearchItem.itemType
    // == "tankoubon" 的区分逻辑配合，UI 层先判 isTank 再取对应 id）。
    public let selectionMode = State<Bool>(false)
    public let selectedIds = State<HashSet<String>>(HashSet<String>())

    // 右侧上传抽屉：分类使用 categories 的数组下标；系统文件对话框是异步请求，
    // 每次 onTick 由 pump 轮询，传输任务则走现有固定工作线程池。
    public let uploadDrawerOpen = State<Bool>(false)
    public let uploadCategoryIndex = State<Int64>(0)
    public let uploadFiles = State<ArrayList<UploadFileItem>>(ArrayList<UploadFileItem>())
    public let uploadFileDialog = State<?FileDialogRequest>(None<FileDialogRequest>)
    private var uploadSequence: Int64 = 0
    private var hasCompletedUploads = false

    // 在线下载：与上传共用分类选择（uploadCategoryIndex），任务同样走固定工作线程池。
    public let uploadTabIndex = State<Int64>(0)
    public let downloadUrlsText = State<String>("")
    public let downloadTasks = State<ArrayList<DownloadTaskItem>>(ArrayList<DownloadTaskItem>())
    private var downloadSequence: Int64 = 0
    private var hasCompletedDownloads = false

    // 浏览模式行数据（随机推荐 + 分类行）与内容区宽度（SizeProbe 写入，驱动自适应列数）
    public let browseRows = State<ArrayList<BrowseRow>>(ArrayList<BrowseRow>())
    public let contentWidth = State<Float32>(0.0)
    // 浏览行横向滚动位置外置存储（浏览页纵向虚拟化配套）：LazyColumn 只物化视口附近行，
    // 滚出视口的行其 LazyRow 局部状态被 StateStore 清除（lazy_column.cj 文档），横向 scroll
    // offset 随之归零。按 rowKey 惰性持有 State 并经 cardRow 的 scroll 参数外置传入，横滚
    // 位置与虚拟化前（行常驻）一致。仅 UI 线程读写（构建与事件处理），无需加锁。
    private let browseRowScrolls = HashMap<String, State<Float32>>()

    // 取（惰性创建）某浏览行的横向滚动位置 State。
    public func browseRowScroll(rowKey: String): State<Float32> {
        match (browseRowScrolls.get(rowKey)) {
            case Some(st) => st
            case None =>
                let st = State<Float32>(0.0)
                browseRowScrolls[rowKey] = st
                st
        }
    }
    // 工具条「合集聚合」开关（0=开 1=关）：T10 合集数据管线接入时消费，
    // 本任务仅保存选择状态（原型 home-tools 的第二个下拉）。
    public let tankGroupIndex = State<Int64>(0)

    // 书架（收藏 / 阅读历史）：两路数据独立加载，切换 Tab 时保留已到货内容。
    // 搜索词与首页全局搜索分离；标题栏会按当前页面绑定对应 State。
    public let shelfTab = State<Int64>(0) // 0=收藏 1=阅读历史
    public let shelfFilter = State<Int64>(0) // 0=全部 1=未读完 2=仅合集 3=新入库
    public let shelfSearchText = State<String>("")
    public let shelfFavoriteSortIndex = State<Int64>(0)
    public let shelfHistorySortIndex = State<Int64>(0)
    public let shelfFavorites = State<SearchItemView>(SearchItemView.empty())
    public let shelfHistory = State<SearchItemView>(SearchItemView.empty())
    public let shelfFavoritesLoading = State<Bool>(false)
    public let shelfHistoryLoading = State<Bool>(false)
    public let shelfFavoritesFailed = State<Bool>(false)
    public let shelfHistoryFailed = State<Bool>(false)
    public let shelfContentWidth = State<Float32>(0.0)
    private var shelfFavoritesLoaded = false
    private var shelfHistoryLoaded = false
    // 从书架打开详情/合集/阅读器时，详情顶栏返回书架而不是首页。
    private var detailReturnToShelf = false

    // 详情/阅读
    public let meta = State<?ArchiveMeta>(None)
    public let pages = State<ArchivePageView>(ArchivePageView.empty())
    public let readerIndex = State<Int64>(1)
    public var readerArcid: String = "" // 当前阅读档案

    // 阅读器状态机（T12 拆出，纯逻辑可单测）。旧 reader_view 仍读本类的
    // pages/readerIndex（1 基）并经 gotoPage 等委托方法驱动；T13 重写后直接消费 reader。
    public let reader: ReaderModel
    // 媒体 lane 播放引擎（libVLC 音视频统一方案，纯逻辑可单测；与 reader 一样是普通类，
    // 状态变更经 readerVersion 广播视图重建）。
    public let playback = PlaybackModel()
    // html 页离屏渲染引擎（Blitz：webview 包，纯逻辑类同 playback；
    // 状态变更经 readerVersion 广播视图重建）。
    public let htmlPage = HtmlPageModel()
    // 快照场景注入：种子 html 页正文（离线，不走网络）；非空时 html 页 open 直接灌入。
    public var htmlSeed: ?String = None
    private var mediaProxy: ?MediaProxy = None

    // 详情页（档案）：页面预览页表、三视图切换（0=缩略图 1=列表 2=树）、所属合集、相关推荐。
    // detailWidth 由详情主列 SizeProbe 写入，驱动预览缩略图网格列数。
    public let detailPages = State<ArchivePageView>(ArchivePageView.empty())
    public let pageViewIndex = State<Int64>(0)
    public let parentTanks = State<TankoubonView>(TankoubonView.empty())
    public let relatedItems = State<SearchItemView>(SearchItemView.empty())
    // 详情主数据与辅助区各自有显式状态，失败不再永久显示 loading，空结果也可区分。
    public let detailLoadState = State<String>("idle")
    public let detailLoadError = State<String>("")
    public let detailPagesState = State<String>("idle")
    public let detailPagesError = State<String>("")
    public let detailTagTranslations = State<TagTranslationView>(TagTranslationView.empty())
    private var recommendedArchiveOriginScene = ""
    private var recommendedArchiveOriginSeedType = ""
    private var recommendedArchiveOriginSeedId = ""
    private var recommendedArchiveOriginId = ""
    public let detailWidth = State<Float32>(0.0)
    // 窗口逻辑宽（vp）：main.cj onTick 自 window.width 同步（变化才写），驱动详情标题字号等响应式布局。
    public let windowWidth = State<Int64>(0)

    // 详情页（合集）：元数据、成员档案（search?tankoubon_id）、网格/列表切换、即时筛选、相关合集。
    public let tank = State<?TankoubonInfo>(None)
    public let tankMembers = State<SearchItemView>(SearchItemView.empty())
    public let tankMemberViewIndex = State<Int64>(0)
    public let tankFilter = State<String>("")
    public let tankRelated = State<TankoubonView>(TankoubonView.empty())
    public let tankLoadState = State<String>("idle")
    public let tankLoadError = State<String>("")
    public let tankMembersState = State<String>("idle")
    public let tankMembersError = State<String>("")

    // Archive 本地下载：系统保存/目录对话框异步完成后，由 pump 在 UI 线程合并状态，
    // 实际网络与文件 IO 交给 worker，避免阻塞渲染线程。
    public let archiveDownloadDialog = State<?FileDialogRequest>(None<FileDialogRequest>)
    private var pendingDownloadArcids = ArrayList<String>()
    private var pendingDownloadBatch = false

    // 多级元数据编辑器（0=合集、1=档案、2=页）。根编辑实体及下钻数据都留在
    // AppModel，避免声明式视图逐帧重建时丢失草稿；网络结果仍只在 UI 线程落 State。
    public let metadataEditorOpen = State<Bool>(false)
    public let metadataEditorLevel = State<Int64>(0)
    public let metadataEditorSaving = State<Bool>(false)
    public let metadataEditorDirty = State<Bool>(false)
    public let metadataPluginPreview = State<Bool>(false)
    public let metadataPluginRunning = State<Bool>(false)
    public let metadataTitle = State<String>("")
    public let metadataDescription = State<String>("")
    public let metadataTags = State<String>("")
    public let metadataReleaseAt = State<String>("")
    public let metadataOrderIndex = State<String>("")
    public let metadataVolumeNo = State<String>("")
    public let metadataHiddenInFiles = State<Bool>(false)
    public let metadataEditorArchiveMeta = State<?ArchiveMeta>(None)
    public let metadataEditorPages = State<ArchivePageView>(ArchivePageView.empty())
    public var metadataEditorTankId: String = ""
    public var metadataEditorTankTitle: String = ""
    public var metadataEditorArchiveId: String = ""
    public var metadataEditorArchiveTitle: String = ""
    public var metadataEditorPageIndex: Int64 = 0

    // 设置页
    public let serverInfo = State<?ServerInfo>(None)
    public let cacheInfo = State<String>("")
    // 当前登录用户是否管理员：控制设置页「服务器」分组入口显隐（LoginData.isAdmin）。
    public let isAdmin = State<Bool>(false)
    // 诊断：就绪像素纹理被预算淘汰后重新请求的次数（连续翻页抖动监控，见 pixelCacheDiagnostics）。
    public var pixelEvictRedecodeCount: Int64 = 0

    // ---- 设置区扩展：各板块数据（进场加载，随 State 重建自动刷新视图） ----
    public let userStats = State<?UserStats>(None)
    public let userTrend = State<ArrayList<TrendPoint>>(ArrayList<TrendPoint>())
    public let recentRead = State<SearchItemView>(SearchItemView.empty())
    public let recentFav = State<SearchItemView>(SearchItemView.empty())
    public let tagCloud = State<ArrayList<CloudTag>>(ArrayList<CloudTag>())
    public let adminUsers = State<ArrayList<AdminUserItem>>(ArrayList<AdminUserItem>())
    public let sysSettings = State<ArrayList<SysSetting>>(ArrayList<SysSetting>())
    public let adminCategories = State<ArrayList<AdminCategoryItem>>(ArrayList<AdminCategoryItem>())
    public let tagPage = State<?TagListPage>(None)
    public let tagNs = State<ArrayList<String>>(ArrayList<String>())
    public let smartFilters = State<ArrayList<SmartFilterItem>>(ArrayList<SmartFilterItem>())
    public let taskPage = State<?TaskListPage>(None)
    public let cronStatus = State<?CronStatus>(None)
    public let cronTasks = State<ArrayList<CronTask>>(ArrayList<CronTask>())
    public let plugins = State<ArrayList<PluginItem>>(ArrayList<PluginItem>())
    public let sessions = State<ArrayList<SessionItem>>(ArrayList<SessionItem>())
    public let apiTokens = State<ArrayList<TokenItem>>(ArrayList<TokenItem>())
    public let passkeys = State<ArrayList<PasskeyItem>>(ArrayList<PasskeyItem>())
    public let totpStatus = State<?TotpStatus>(None)

    // 图片：key → 状态（""=未开始/"loading"=在途/"error"=失败/"ready"=像素已就绪）
    public let imageStates = HashMap<String, State<String>>()
    private let imageMutex = Mutex()
    private let persistSettings: (AppSettings) -> Unit

    public init(s: AppSettings, persistSettings!: (AppSettings) -> Unit = {_ => ()},
        offlineCachePrewarm!: ?Future<?OfflineCache> = None) {
        settings = s
        this.offlineCachePrewarm = offlineCachePrewarm
        language = State<String>(resolveLanguage(s.languagePreference))
        this.persistSettings = persistSettings
        reader = ReaderModel(s)
        readerShowInfo = State<Bool>(s.readerShowInfo)
        autoPlayIntervalSlider.value = Float32(clampAutoPlayInterval(s.readerAutoPlayInterval))
        // 像素纹理缓存 LRU 逐出回调：把被逐出 key 的加载状态复位为 ""，仍在屏的
        // widget 下帧重建时经 requestImage 重新请求/显示占位，避免对着已逐出纹理绘制空白。
        // 回调在 UI 线程触发（stage/绘制路径），直接写 State 无并发问题。
        onPixelImageEvicted = {
            k => synchronized(imageMutex) {
                match (imageStates.get(k)) {
                    case Some(st) =>
                        if (st.value == "ready") {
                            st.value = ""
                            // 诊断：就绪纹理被预算淘汰 → 状态复位 → 重新可见时需重解码。
                            pixelEvictRedecodeCount++
                            // 条漫可见区请求缓存（reader_stage.cj）须随复位失效。
                            imageResetEpoch++
                        }
                    case None => ()
                }
            }
        }
        // ReaderModel 出口接线：设置落盘、进度上报（走 worker，失败静默同旧 reportProgress）、
        // 预取（复用图片管线，并发上限由 requestImage 保证）。
        reader.onPersist = {=> this.persistSettings(settings)}
        reader.onProgress = {
            arc, page1 => match (api) {
                case Some(a) => let _ = worker.submit(
                    "progress",
                    {
                        =>
                            a.setProgress(arc, page1);
                            return page1
                    }
                )
                case None => ()
            }
        }
        // 跨 segment 预取：页属哪个档案按 arcidOfReal 取（拼接后邻居页可能属下一档案）。
        // 只预取图片页：audio/video/html 页不经图片管线展示（reader_stage/webtoon/侧栏
        // 均按同款条件过滤），预取只会拿到 4xx/5xx 或不可解码字节，且 error 态会被
        // requestImage 重复入队形成重试风暴（音频档案每翻一页全部曲目重试）。
        reader.onPrefetch = {
            _, indices => for (i in indices) {
                match (reader.pageAt(i)) {
                    case Some(p) =>
                        if (p.pageType == "image" || p.pageType == "") {
                            let a2 = reader.arcidOfReal(i)
                            let pid = p.id
                            requestImage("page:${a2}:${pid}", "/api/archives/${a2}/page?path=${percentEncode(pid)}")
                        }
                    case None => ()
                }
            }
        }
        // 无缝续读出口：进入末尾虚拟页时解析候选（合集下一章 → 相关推荐），
        // seamless 开时继续取页表自动拼接；关时只解析候选供结束页卡片展示。
        reader.onAppendNext = {arcid => startAppendNext(arcid)}
        // 媒体下载出口：提交 worker 拉取页字节并落缓存目录（与图片缓存同根，
        // 按 arcid 分目录、percentEncode(pageId) 作文件名——"." 是 unreserved，
        // 扩展名得以保留）。任务名带 mediaKey 天然按媒体去重；完成经 pump 的
        // drain 分发回填 playback.onDownloaded/onFailed。
        playback.onDownload = {
            arc, pid => match (api) {
                case Some(a) =>
                    let key = playback.mediaKey // load() 先置 mediaKey 再调本回调
                    var lyricsAssetId: Int64 = 0
                    for (pageInfo in pages.value) {
                        if (pageInfo.id == pid || pageInfo.sourcePath == pid) {
                            lyricsAssetId = pageInfo.lyricsAssetId
                            break
                        }
                    }
                    let lyricAsset = lyricsAssetId
                    let dir = "${defaultCacheRoot(activeBaseUrl())}/media/${arc}"
                    let path = "${dir}/${percentEncode(pid)}"
                    let _ = worker.submit(
                        "playback:${key}",
                        {
                            =>
                                let bytes = a.pageBytes(arc, pid)
                                let dirPath = Path(dir)
                                if (!exists(dirPath)) {
                                    Directory.create(dirPath, recursive: true)
                                }
                                File.writeTo(Path(path), bytes)
                                let lyrics = if (lyricAsset > 0) {
                                    try {
                                        let lyricBytes = a.assetBytes(lyricAsset)
                                        if (lyricBytes.size <= 1048576) {
                                            String.fromUtf8(lyricBytes)
                                        } else {
                                            ""
                                        }
                                    } catch (_: Exception) {
                                        ""
                                    }
                                } else {
                                    ""
                                }
                                (key, path, lyrics)
                        }
                    )
                case None => ()
            }
        }
        // 流式音频只需单独获取体积很小的歌词资产；媒体本体不再整文件进内存。
        playback.onLyricsDownload = {
            key, assetId => match (api) {
                case Some(a) => let _ = worker.submit(
                    "lyrics:${key}",
                    {
                        =>
                            let bytes = a.assetBytes(assetId)
                            let lyrics = if (bytes.size <= 1048576) {
                                String.fromUtf8(bytes)
                            } else {
                                ""
                            }
                            (key, lyrics)
                    }
                )
                case None => ()
            }
        }
        // 外挂字幕文本：任务名带 assetId 天然多条去重；完成经 pump drain 回填
        // playback.onSubtitleDownloaded（文本体积限同歌词 1MiB）。
        playback.onSubtitleDownload = {
            key, assetId => match (api) {
                case Some(a) => let _ = worker.submit(
                    "subtitle:${key}:${assetId}",
                    {
                        =>
                            let bytes = a.assetBytes(assetId)
                            let text = if (bytes.size <= 1048576) {
                                String.fromUtf8(bytes)
                            } else {
                                ""
                            }
                            (key, assetId, text)
                    }
                )
                case None => ()
            }
        }
        playback.onSubtitleProbe = {
            key, generation, url, bearer =>
                SubtitlePerf.spanStart("subtitle_probe_e2e")
                let taskName = "subprobe:${generation}:${key}"
                match (registerSubtitleToken(taskName)) {
                    case Some(token) =>
                        let accepted = worker.submitSubtitle(taskName, {
                            => try {
                                SubtitlePerf.spanStart("subtitle_probe_ffi")
                                let streams = probeSubtitleStreams(url, bearer: bearer, cancel: token)
                                SubtitlePerf.spanEnd("subtitle_probe_ffi")
                                (key, generation, streams)
                            } finally {
                                releaseSubtitleToken(taskName, token)
                            }
                        })
                        if (!accepted) {
                            releaseSubtitleToken(taskName, token)
                        }
                    case None => ()
                }
        }
        playback.onSubtitleScan = {
            key, generation, url, bearer, stableKey =>
                SubtitlePerf.spanStart("subtitle_scan_e2e")
                let cache = subtitleCache()
                let taskName = "subscan:${generation}:${key}"
                match (registerSubtitleToken(taskName)) {
                    case Some(token) =>
                        let accepted = worker.submitSubtitle(taskName, {
                            => try {
                                (key, generation, cache.loadOrExtract(stableKey, url, bearer: bearer, cancel: token))
                            } finally {
                                releaseSubtitleToken(taskName, token)
                            }
                        })
                        if (!accepted) {
                            releaseSubtitleToken(taskName, token)
                        }
                    case None => ()
                }
        }
        playback.onSubtitleCancel = {
            key, generation => cancelSubtitleTokens(generation, key)
        }
        // html 离屏渲染出口：正文/子资源都由 worker 拉字节（Blitz 不碰网络），
        // 任务名带 pageKey 去重；完成经 pump 的 drain 分发回填 htmlPage。
        htmlPage.fetchHtml = {
            key, arc, path => match (htmlSeed) {
                case Some(seed) =>
                    // 快照/测试种子页：离线直灌，不走网络（api 可为 None）。
                    htmlPage.htmlLoaded(key, utf8BytesOf(seed))
                case None => match (api) {
                    case Some(a) => let _ = worker.submit("html:${key}", {=> (key, a.pageBytes(arc, path))})
                    case None => htmlPage.htmlFailed(key, "未连接服务器")
                }
            }
        }
        htmlPage.fetchResource = {
            key, arc, url, path => match (api) {
                case Some(a) => let _ = worker.submit("htmlres:${key}:${url}", {=> (key, url, a.pageBytes(arc, path))})
                case None =>
                    // 离线（快照种子）：即时判败，避免在途计数永不自减。
                    htmlPage.resourceFailed(key, url)
            }
        }
        // html 阅读主题随当前深浅色初始化（后续切换在 applyPendingTheme 同步）。
        applyHtmlThemeCss()
        // html 页滚到底视为读完：并入 ReaderModel 进度上报（防抖语义与翻页一致）。
        htmlPage.onHtmlRead = {
            => reader.markCurrentPageRead()
        }
        // 初始选中 active 服务器（回退首个）；api 不再在此构建——
        // 登录/恢复会话时按选中服务器的 baseUrl 现场创建。
        if (s.activeServerId.size > 0 && s.profileById(s.activeServerId).isSome()) {
            selectedServerId.value = s.activeServerId
        } else if (s.servers.size > 0) {
            selectedServerId.value = s.servers.at(0).id
        }
        probeServers()
    }

    public func showError(msg: String): Unit {
        toaster.show(msg, kind: ToastKind.Error, durationMs: 4200)
    }

    // 操作占位提示（T11：下载/加入合集/编辑/更多等按钮仅渲染，真实功能后续任务接入）。
    public func todoToast(feature: String): Unit {
        toaster.show("${feature}功能暂未实现", kind: ToastKind.Info)
    }

    // ---- 多级元数据编辑 ----

    public func openArchiveMetadataEditor(arcid: String): Unit {
        metadataEditorTankId = ""
        metadataEditorTankTitle = ""
        metadataEditorArchiveId = arcid
        metadataEditorPages.value = detailPages.value
        metadataEditorArchiveMeta.value = meta.value
        metadataEditorLevel.value = 1
        loadArchiveEditorDraft()
        metadataEditorOpen.value = true
        loadMetadataEditorPlugins()
    }

    public func openTankMetadataEditor(tankid: String): Unit {
        metadataEditorTankId = tankid
        metadataEditorArchiveId = ""
        metadataEditorArchiveMeta.value = None
        metadataEditorPages.value = ArchivePageView.empty()
        metadataEditorLevel.value = 0
        loadTankEditorDraft()
        metadataEditorOpen.value = true
        loadMetadataEditorPlugins()
    }

    public func editTankMember(item: SearchItem, volumeNo: Int64): Unit {
        metadataEditorArchiveId = item.arcid
        metadataEditorArchiveTitle = item.title
        // 从 SearchItem 投影出编辑草稿 meta（避免两份字段漂移）。
        metadataEditorArchiveMeta.value = Some(metaFromSearchItem(item))
        metadataEditorPages.value = ArchivePageView.empty(arcid: item.arcid)
        metadataEditorLevel.value = 1
        metadataTitle.value = item.title
        metadataDescription.value = item.description
        metadataTags.value = item.tagsCsv
        metadataReleaseAt.value = ""
        metadataVolumeNo.value = "${volumeNo}"
        metadataOrderIndex.value = ""
        metadataEditorDirty.value = false
        metadataPluginPreview.value = false
        let a = api ?? return
        let id = item.arcid
        let lang = language.value
        let _ = worker.submitTagged("editmeta:${id}", lang, {=> a.metadata(id, lang: lang)})
        let _ = worker.submit("editfiles:${id}", {=> a.files(id)})
    }

    public func editMetadataPage(index: Int64): Unit {
        let list = metadataEditorPages.value
        if (index < 0 || index >= list.size) {
            return
        }
        metadataEditorPageIndex = index
        metadataEditorLevel.value = 2
        let p = list[index]
        metadataTitle.value = if (p.title.size > 0 && !isPageFileFallbackTitle(p.title, p.sourcePath)) {
            p.title
        } else {
            "P.${index + 1}"
        }
        metadataDescription.value = p.description
        metadataReleaseAt.value = p.releaseAt
        metadataOrderIndex.value = "${if (p.orderIndex > 0) { p.orderIndex } else { index + 1 }}"
        metadataHiddenInFiles.value = p.hiddenInFiles
        metadataEditorDirty.value = false
        metadataPluginPreview.value = false
    }

    private func isPageFileFallbackTitle(title: String, sourcePath: String): Bool {
        let normalizedTitle = title.trimAscii()
        let normalizedPath = sourcePath.trimAscii()
        if (normalizedTitle.size == 0 || normalizedTitle == normalizedPath) {
            return true
        }
        let parts = normalizedPath.split("/")
        parts.size > 0 && normalizedTitle == parts[parts.size - 1]
    }

    public func metadataEditorBackTo(level: Int64): Unit {
        if (level <= 0 && metadataEditorTankId.size > 0) {
            metadataEditorLevel.value = 0
            loadTankEditorDraft()
        } else {
            metadataEditorLevel.value = 1
            loadArchiveEditorDraft()
        }
    }

    public func closeMetadataEditor(): Unit {
        if (metadataEditorSaving.value) {
            return
        }
        metadataEditorOpen.value = false
        metadataPluginPreview.value = false
    }

    private func loadMetadataEditorPlugins(): Unit {
        if (plugins.value.size > 0 || !isAdmin.value) {
            return
        }
        let a = api ?? return
        let _ = worker.submit("set.plugins", {=> a.plugins()})
    }

    public func runMetadataEditorPlugin(namespace: String, param: String): Unit {
        if (metadataPluginRunning.value) {
            return
        }
        let targetType = if (metadataEditorLevel.value == 0) {
            "tankoubon"
        } else {
            "archive"
        }
        let targetId = if (targetType == "tankoubon") {
            metadataEditorTankId
        } else {
            metadataEditorArchiveId
        }
        if (namespace.size == 0 || targetId.size == 0) {
            showError("请选择可用的元数据插件")
            return
        }
        let a = match (api) {
            case Some(x) => x
            case None => return
        }
        metadataPluginRunning.value = true
        let _ = worker.submit("metadata-plugin:${targetType}:${targetId}", {
            => a.runMetadataPlugin(targetType, targetId, namespace, param)
        })
    }

    public func saveMetadataEditor(): Unit {
        if (metadataEditorSaving.value) {
            return
        }
        let a = api ?? return
        let title = metadataTitle.value.trimAscii()
        if (title.size == 0) {
            toaster.show("标题不能为空", kind: ToastKind.Warning)
            return
        }
        let level = metadataEditorLevel.value
        let body: String
        let target: String
        let kind: String
        var pageIndex: Int64 = -1
        if (level == 0) {
            target = metadataEditorTankId
            kind = "tank"
            body = metadataRootBody(title, metadataDescription.value, metadataTags.value, metadataReleaseAt.value)
        } else if (level == 1) {
            target = metadataEditorArchiveId
            kind = "archive"
            body = metadataRootBody(title, metadataDescription.value, metadataTags.value, metadataReleaseAt.value)
        } else {
            target = metadataEditorArchiveId
            kind = "page"
            pageIndex = metadataEditorPageIndex
            let list = metadataEditorPages.value
            if (pageIndex < 0 || pageIndex >= list.size) {
                return
            }
            let p = list[pageIndex]
            let order = parsePositiveInt(metadataOrderIndex.value, pageIndex + 1)
            body = "{\"pages\":[{\"page_number\":${pageIndex + 1}," +
                "\"entry_path\":${jsonQuote(p.sourcePath)},\"title\":${jsonQuote(title)}," +
                "\"description\":${jsonQuote(metadataDescription.value)}," +
                "\"release_at\":${jsonQuote(metadataReleaseAt.value.trimAscii())},\"order_index\":${order}," +
                "\"hidden_in_files\":${metadataHiddenInFiles.value}}]}"
        }
        if (target.size == 0) {
            return
        }
        metadataEditorSaving.value = true
        let taskName = if (kind == "page") {
            "editsave:${kind}:${target}:${pageIndex}"
        } else {
            "editsave:${kind}:${target}"
        }
        let _ = worker.submit(
            taskName,
            {
                =>
                    if (kind == "tank") {
                        a.updateTankoubonMetadata(target, body)
                    } else {
                        a.updateArchiveMetadata(target, body)
                    }
                    return target
            }
        )
    }

    private func loadTankEditorDraft(): Unit {
        match (tank.value) {
            case Some(t) =>
                metadataEditorTankTitle = t.name
                metadataTitle.value = t.name
                metadataDescription.value = t.description
                metadataTags.value = joinTags(t.tags)
                metadataReleaseAt.value = ""
            case None => ()
        }
        metadataVolumeNo.value = ""
        metadataOrderIndex.value = ""
        metadataEditorDirty.value = false
        metadataPluginPreview.value = false
    }

    private func loadArchiveEditorDraft(): Unit {
        match (metadataEditorArchiveMeta.value) {
            case Some(m) =>
                metadataEditorArchiveTitle = m.title
                metadataTitle.value = m.title
                metadataDescription.value = m.description
                metadataTags.value = joinTags(m.tags)
                metadataReleaseAt.value = if (m.release_at > 0) {
                    formatTimestamp(m.release_at)
                } else {
                    ""
                }
            case None =>
                metadataTitle.value = metadataEditorArchiveTitle
                metadataDescription.value = ""
                metadataTags.value = ""
                metadataReleaseAt.value = ""
        }
        metadataOrderIndex.value = ""
        metadataEditorDirty.value = false
        metadataPluginPreview.value = false
    }

    // ---- 多服务器登录 ----
    public let selectedServerId = State<String>("")
    public let totpChallengeId = State<String>("") // 空串=无 TOTP 挑战
    public let testConnResult = State<String>("") // ""=无 "testing"=在途 "ok"=成功 其余=错误文案
    public let serverModalOpen = State<Bool>(false)
    public let deleteConfirmId = State<String>("") // 删除二次确认：首击置 id，再击执行
    public let serversVersion = State<Int64>(0) // settings.servers 变更计数，驱动列表重绘
    public var editingServerId: String = "" // 编辑弹窗目标；空串=新增
    public let loginError = State<String>("") // 登录/TOTP 内联错误条（空串=无），替代 toast

    // 在线状态探测：id → 状态（""=未知/在途 "online" "offline"），登录页卡片状态点用。
    // 无认证调 /api/info；任务名 probe:<id> 由 worker 在途去重，失败静默只落状态。
    public let probeStates = HashMap<String, State<String>>()
    private let probeMutex = Mutex()

    public func probeState(id: String): State<String> {
        synchronized(probeMutex) {
            match (probeStates.get(id)) {
                case Some(st) => return st
                case None =>
                    let st = State<String>("")
                    probeStates[id] = st
                    return st
            }
        }
    }

    // 探测全部服务器在线状态（登录页进场/列表变更后调用）。
    // 探测用 LanluApi 是即用即弃的短生命周期实例（各含一个连接池），用完必须 close，
    // 否则每次探测泄漏一个连接池（#31）。connect 超时用设置项
    // probeConnectTimeoutSec（任务E持久化，默认 5s 保守值，#21）：qwest 原生支持
    // TCP connect 超时，失效地址不再拖满 worker 池。
    public func probeServers(): Unit {
        for (p in settings.servers) {
            let id = p.id
            let _ = worker.submit(
                "probe:${id}",
                {
                    =>
                        let probeApi = LanluApi(p.baseUrl,
                            connectTimeout: Some(Duration.second * settings.probeConnectTimeoutSec))
                        try {
                            let _ = probeApi.info()
                            return id
                        } finally {
                            probeApi.close()
                        }
                }
            )
        }
    }

    // ---- 会话 ----

    public func selectedProfile(): ?ServerProfile {
        settings.profileById(selectedServerId.value)
    }

    // 切换选中服务器：复位 TOTP/删除确认态；有已存会话则静默恢复（成功直接进书库，
    // 失败由 handleError 的 "me" 分支清 token 落回表单）。
    public func selectServer(id: String): Unit {
        if (selectedServerId.value == id) {
            return
        }
        selectedServerId.value = id
        totpChallengeId.value = ""
        deleteConfirmId.value = ""
        loginError.value = ""
        match (settings.profileById(id)) {
            case Some(p) =>
                if (p.token.size > 0) {
                    resumeProfile(p)
                }
            case None => ()
        }
    }

    private func resumeProfile(p: ServerProfile): Unit {
        let a = LanluApi(p.baseUrl, connectTimeout: Some(Duration.second * settings.probeConnectTimeoutSec),
            offlineCache: offlineCacheFor(), serverHash: fnv1a64Hex(p.baseUrl),
            accountScope: offlineAccountScope(p.id, p.username, p.token), onOfflineFallback: {=> offlineNotice.mark()})
        a.setToken(p.token)
        api = a
        let _ = worker.submit("me", {
            =>
                // LANLU_PERF 打点：me RPC 实际执行耗时（区分"RPC 慢"与 API 池排队）。
                let rpcT0 = MonoTime.now()
                let d = a.me()
                if (SubtitlePerf.enabled()) {
                    SubtitlePerf.sampleUs("me_rpc_us", (MonoTime.now() - rpcT0).toMicroseconds())
                }
                d
        })
    }

    public func tryResumeSession(): Unit {
        match (settings.activeProfile()) {
            case Some(p) =>
                if (p.token.size > 0) {
                    resumeProfile(p)
                }
            case None => ()
        }
    }

    // 登录选中服务器。TotpRequired 不视为失败：任务内捕获后把 challengeId 放在元组第 4 位
    // 回传（worker 的 error 通道只有 String，带不了 challengeId），dispatch 据此切 TOTP 表单。
    private var pendingLoginUsername = ""

    public func loginSelected(user: String, pass: String): Unit {
        let p = match (selectedProfile()) {
            case Some(x) => x
            case None => return
        }
        let a = LanluApi(p.baseUrl, connectTimeout: Some(Duration.second * settings.probeConnectTimeoutSec),
            offlineCache: offlineCacheFor(), serverHash: fnv1a64Hex(p.baseUrl),
            accountScope: offlineAccountScope(p.id, user, ""), onOfflineFallback: {=> offlineNotice.mark()})
        pendingLoginUsername = user
        loading.value = true
        loginError.value = ""
        let sid = p.id
        let ok = worker.submit(
            "login",
            {
                =>
                // a 的所有权只随成功结果（含 TOTP 挑战）转交给 dispatch；
                // 任务抛错时 a 无人接管，必须就地 close，否则每次失败登录泄漏一个连接池（#31）。
                try {
                    let _ = a.info() // 先探测：非 lanlu 服务/地址错误会在这里抛错
                    try {
                        let d = a.login(user, pass)
                        a.setAccountScope(offlineAccountScope(sid, d.username, ""))
                        return (a, d, sid, "")
                    } catch (e: TotpRequired) {
                        return (a, LoginData(), sid, e.challengeId)
                    }
                } catch (e: Exception) {
                    a.close()
                    throw e
                }
            }
        )
        // 同名任务在途（快速重复登录）时 submit 去重返回 false：闭包不会执行，a 就地 close（#31）。
        if (!ok) {
            a.close()
        }
    }

    public func verifyTotp(code: String, recoveryCode: String): Unit {
        let p = match (selectedProfile()) {
            case Some(x) => x
            case None => return
        }
        let cid = totpChallengeId.value
        if (cid.size == 0) {
            return
        }
        let a = LanluApi(p.baseUrl, connectTimeout: Some(Duration.second * settings.probeConnectTimeoutSec),
            offlineCache: offlineCacheFor(), serverHash: fnv1a64Hex(p.baseUrl),
            accountScope: offlineAccountScope(p.id, pendingLoginUsername, p.token),
            onOfflineFallback: {=> offlineNotice.mark()})
        loading.value = true
        loginError.value = ""
        let sid = p.id
        let ok = worker.submit(
            "login-totp",
            {
                =>
                // 同 login：a 只随成功结果转交 dispatch，抛错路径就地 close（#31）。
                try {
                    let d = a.verifyTotpLogin(cid, code, recoveryCode)
                    a.setAccountScope(offlineAccountScope(sid, d.username, ""))
                    return (a, d, sid, "")
                } catch (e: Exception) {
                    a.close()
                    throw e
                }
            }
        )
        // 同名任务在途时 submit 去重返回 false：闭包不会执行，a 就地 close（#31）。
        if (!ok) {
            a.close()
        }
    }

    public func dismissTotp(): Unit {
        totpChallengeId.value = ""
        loginError.value = ""
        pendingLoginUsername = ""
    }

    public func openServerModal(editId: String): Unit {
        editingServerId = editId
        testConnResult.value = ""
        serverModalOpen.value = true
    }

    public func saveServer(name: String, url: String): Unit {
        let norm = normalizeServerUrl(url)
        if (norm.size == 0) {
            testConnResult.value = "请输入服务器地址"
            return
        }
        let p = settings.upsertServer(editingServerId, name, norm)
        persistSettings(settings)
        serversVersion.value = serversVersion.value + 1
        serverModalOpen.value = false
        selectedServerId.value = p.id
        probeServers()
    }

    // 删除二次确认：首击进入确认态（按钮变「确认删除」），再击执行；切服/选卡会复位确认态。
    public func requestDeleteServer(id: String): Unit {
        if (deleteConfirmId.value != id) {
            deleteConfirmId.value = id
            return
        }
        settings.deleteServer(id)
        persistSettings(settings)
        deleteConfirmId.value = ""
        serversVersion.value = serversVersion.value + 1
        if (selectedServerId.value == id) {
            selectedServerId.value = if (settings.servers.size > 0) {
                settings.servers.at(0).id
            } else {
                ""
            }
        }
    }

    public func testConnection(url: String): Unit {
        let norm = normalizeServerUrl(url)
        if (norm.size == 0) {
            testConnResult.value = "请输入服务器地址"
            return
        }
        testConnResult.value = "testing"
        // 即用即弃的测试实例（含连接池），try/finally 保证成败都 close（#31）。
        let _ = worker.submit(
            "testconn",
            {
                =>
                    let testApi = LanluApi(norm, connectTimeout: Some(Duration.second * settings.probeConnectTimeoutSec))
                    try {
                        return testApi.info()
                    } finally {
                        testApi.close()
                    }
            }
        )
    }

    // 登出：清 active profile 的 token（服务器条目保留）并复位图片/纹理缓存——
    // 换账号重新登录可能落到另一台服务器，旧服务器的 staged/纹理残留会导致串图
    //（与换服登录同款清理，顺序：先路径纹理、后像素纹理（纹理→staged），见 clearCache）。
    public func logout(): Unit {
        match (settings.activeProfile()) {
            case Some(p) => p.token = ""
            case None => ()
        }
        persistSettings(settings)
        clearImageCache() // cui 路径纹理缓存（按文件路径解码的 GPU 纹理）
        clearPixelImages() // cui 像素纹理缓存（含已建纹理与 staged 像素）
        synchronized(imageMutex) {
            imageStates.clear()
        }
        isAdmin.value = false
        navigate(Page.Login)
    }

    // ---- 书库查询（即时应用语义：状态变更即写 query 并查询，无「应用」按钮）----

    // 查询入口：把索引/开关状态同步进 query（query.filter 例外——它只由搜索按钮写入，
    // 本函数不同步 searchText，否则侧栏/排序的即时应用会把未提交的输入框文本一并提交）。
    public func submitSearch(page: Int64): Unit {
        let a = api ?? return query.page = page
        query.sortby = SEARCH_SORT_FIELDS[sortIndex.value]
        query.order = if (orderIndex.value == 0) {
            "asc"
        } else {
            "desc"
        }
        query.categoryId = selectedCategoryId()
        query.dateFrom = dateFrom.value
        query.dateTo = dateTo.value
        query.favoriteonly = favOnly.value
        query.newonly = newOnly.value
        query.untaggedonly = untaggedOnly.value
        query.groupbyTanks = tankGroupOn()
        query.lang = language.value
        loading.value = true
        let q = query
        let _ = worker.submitTagged("search", query.lang, {=> a.search(q)})
    }

    // ---- 书架（library-redesign.html）----

    // 页面过渡入口：不立即切页，先置 pending 标志，让 PageTransition 在下一帧
    // 捕获旧页面（GPU 快照）后调 commitPendingPage() 真正切页，产生 200ms 交叉
    // 淡化。同页（含参数相同）不播过渡；快照播种/测试直接赋 page.value 跳过动画。
    public func navigate(target: Page): Unit {
        if (pageEquals(page.value, target)) {
            return
        }
        pendingPage = Some(target)
        pageTransitionPending = true
    }

    // PageTransition 捕获旧帧后调用：提交挂起的页面切换。
    public func commitPendingPage(): Unit {
        match (pendingPage) {
            case Some(p) =>
                page.value = p
                pendingPage = None
            case None => ()
        }
    }

    public func openHome(): Unit {
        exitSelection()
        clearAutocomplete()
        navigate(Page.Library)
    }

    public func openShelf(): Unit {
        exitSelection()
        clearAutocomplete()
        navigate(Page.Shelf)
        if (shelfTab.value == 0) {
            if (!shelfFavoritesLoaded) {
                loadShelfFavorites()
            }
        } else if (!shelfHistoryLoaded) {
            loadShelfHistory()
        }
    }

    public func isShelfContext(): Bool {
        match (page.value) {
            case Page.Shelf => true
            case Page.Detail(_) | Page.Tank(_) | Page.Reader(_, _) => detailReturnToShelf
            case _ => false
        }
    }

    public func leaveDetailOrSettings(): Unit {
        exitSelection()
        match (page.value) {
            case Page.Detail(_) | Page.Tank(_) =>
                if (detailReturnToShelf) {
                    openShelf()
                } else {
                    openHome()
                }
            case _ => openHome()
        }
    }

    public func selectShelfTab(index: Int64): Unit {
        let next = if (index == 1) {
            1
        } else {
            0
        }
        if (shelfTab.value == next) {
            return
        }
        shelfTab.value = next
        if (next == 0) {
            if (!shelfFavoritesLoaded) {
                loadShelfFavorites()
            }
        } else if (!shelfHistoryLoaded) {
            loadShelfHistory()
        }
    }

    public func toggleShelfFilter(index: Int64): Unit {
        shelfFilter.value = if (shelfFilter.value == index) {
            0
        } else {
            index
        }
    }

    public func setShelfSort(index: Int64): Unit {
        if (shelfTab.value == 0) {
            if (shelfFavoriteSortIndex.value == index) {
                return
            }
            shelfFavoriteSortIndex.value = index
            loadShelfFavorites()
        } else {
            if (shelfHistorySortIndex.value == index) {
                return
            }
            shelfHistorySortIndex.value = index
            loadShelfHistory()
        }
    }

    public func refreshShelf(): Unit {
        if (shelfTab.value == 0) {
            loadShelfFavorites()
        } else {
            loadShelfHistory()
        }
    }

    private func loadShelfFavorites(): Unit {
        let a = api ?? return
        let q = SearchQuery()
        q.favoriteonly = true
        q.groupbyTanks = true
        q.pageSize = 1000
        q.lang = language.value
        match (shelfFavoriteSortIndex.value) {
            case 1 =>
                q.sortby = "title"
                q.order = "asc"
            case 2 =>
                q.sortby = "pagecount"
                q.order = "desc"
            case _ =>
                q.sortby = "created_at"
                q.order = "desc"
        }
        shelfFavoritesLoading.value = true
        shelfFavoritesFailed.value = false
        let _ = worker.submitTagged("shelf:favorites", q.lang, {=> a.search(q)})
    }

    private func loadShelfHistory(): Unit {
        let a = api ?? return
        let q = SearchQuery()
        q.pageSize = 1000
        q.lang = language.value
        match (shelfHistorySortIndex.value) {
            case 1 =>
                q.sortby = "title"
                q.order = "asc"
            case 2 =>
                q.sortby = "pagecount"
                q.order = "desc"
            case _ =>
                q.sortby = "lastread"
                q.order = "desc"
        }
        shelfHistoryLoading.value = true
        shelfHistoryFailed.value = false
        let _ = worker.submitTagged("shelf:history", q.lang, {=> a.search(q)})
    }

    // 浏览模式 ⟺ 无搜索词、无侧栏过滤（收藏/未读/无标签均关）、未选分类、未「查看更多」出站。
    // 模式是派生态而非独立状态：任何动作改完状态后经 applyFilters 收束。
    // browseExited 是唯一例外：横排行的「查看更多」（继续阅读/新到）不带任何过滤条件，
    // 派生规则表达不了"进站看网格"，故显式记录；侧栏点选/提交搜索词时复位（见下）。
    private var browseExited = false

    // 改名请求在途时暂存目标用户名：act.cred 成功后用它同步本地会话并落盘。
    private var pendingCredUsername = ""

    // 浏览行分批加载（启动风暴缓解）：先行行立即提交，分类行按批补发，
    // 每批最多 ROW_BATCH_SIZE 个在途，前一批落盘（成功/失败都算）后补下一批，
    // 避免启动瞬间 ~10 个 search 同时打服务器。
    private let ROW_BATCH_SIZE: Int64 = 3
    private var pendingRows = ArrayList<BrowseRow>()
    private var runningRowTasks: Int64 = 0

    public func isBrowseMode(): Bool {
        !browseExited && query.filter.size == 0 && !favOnly.value && !newOnly.value && !untaggedOnly.value &&
            dateFrom.value.size == 0 && dateTo.value.size == 0 && categoryIndex.value == 0
    }

    // 标题栏筛选钮入口：每次打开都以当前已应用条件重建草稿，确保取消后再次打开不残留。
    public func openAdvancedFilter(): Unit {
        advancedSortIndex.value = sortIndex.value
        advancedOrderIndex.value = orderIndex.value
        advancedFavOnly.value = favOnly.value
        advancedNewOnly.value = newOnly.value
        advancedUntaggedOnly.value = untaggedOnly.value
        advancedTankGroupIndex.value = tankGroupIndex.value
        advancedDateFrom.value = dateFrom.value
        advancedDateTo.value = dateTo.value
        advancedFilterOpen.value = true
    }

    // 应用高级筛选后明确进入结果网格；即使只改变排序，也应与 frontend 的筛选动作一致地发起查询。
    public func applyAdvancedFilter(): Unit {
        sortIndex.value = advancedSortIndex.value
        orderIndex.value = advancedOrderIndex.value
        favOnly.value = advancedFavOnly.value
        newOnly.value = advancedNewOnly.value
        untaggedOnly.value = advancedUntaggedOnly.value
        tankGroupIndex.value = advancedTankGroupIndex.value
        dateFrom.value = advancedDateFrom.value.trimAscii()
        dateTo.value = advancedDateTo.value.trimAscii()
        query.dateFrom = dateFrom.value
        query.dateTo = dateTo.value
        browseExited = true
        advancedFilterOpen.value = false
        submitSearch(1)
    }

    // 重置只清高级筛选条件，保留搜索词与当前分类；无搜索/分类时回到书库浏览视图。
    // 排序/方向回默认（创建时间、降序）。
    public func resetAdvancedFilter(): Unit {
        let tankGroupingChanged = tankGroupIndex.value != 0
        sortIndex.value = 1
        orderIndex.value = 1
        favOnly.value = false
        newOnly.value = false
        untaggedOnly.value = false
        tankGroupIndex.value = 0
        dateFrom.value = ""
        dateTo.value = ""
        query.dateFrom = ""
        query.dateTo = ""
        advancedFilterOpen.value = false
        browseExited = false
        if (isBrowseMode()) {
            if (tankGroupingChanged) {
                for (r in browseRows.value) {
                    r.requested = false
                }
                loadBrowseRows()
            }
        } else {
            submitSearch(1)
        }
    }

    // 合集聚合开关：index 0 = 开（与 ui 的 TANK_GROUP_LABELS 同步）。
    public func tankGroupOn(): Bool {
        tankGroupIndex.value == 0
    }

    // 合集聚合开关变更：结果集规格变了——搜索/过滤模式立即重查；浏览模式各行按新规格
    // 重取（requested 复位后 loadBrowseRows 会对未请求行重新提交任务）。
    public func applyTankGroupChange(): Unit {
        if (isBrowseMode()) {
            for (r in browseRows.value) {
                r.requested = false
            }
            loadBrowseRows()
        } else {
            submitSearch(1)
        }
    }

    // 即时应用收束：浏览模式下排序/方向对分类行同样生效——复位所有行并按新规格重取
    // （resume 行仍按最近阅读倒序、random 行仍随机，见 submitRowTask）；搜索/过滤模式
    // 立即回第 1 页查询。
    public func applyFilters(): Unit {
        if (isBrowseMode()) {
            for (r in browseRows.value) {
                r.requested = false
            }
            loadBrowseRows()
            return
        }
        submitSearch(1)
    }

    // 侧栏「浏览」分组点击（互斥单选）：0=全部 1=仅收藏 2=仅未读 3=仅无标签。
    // 「全部」同时取消分类选择——它是回到浏览模式的总复位（搜索词需另行清空）。
    public func selectBrowseFilter(kind: Int64): Unit {
        browseExited = false
        favOnly.value = (kind == 1)
        newOnly.value = (kind == 2)
        untaggedOnly.value = (kind == 3)
        if (kind == 0) {
            categoryIndex.value = 0
            dateFrom.value = ""
            dateTo.value = ""
        }
        applyFilters()
    }

    // 工具条「搜索」：写入关键词并收束查询；清空词后搜索即回浏览模式（复位出站标记）。
    public func submitFilter(): Unit {
        clearAutocomplete()
        match (page.value) {
            // 书架搜索由 shelfSearchText 即时、本地过滤；Enter 只负责收起补全。
            case Page.Shelf => return
            case _ => ()
        }
        browseExited = false
        query.filter = searchText.value
        applyFilters()
    }

    // 顶栏只在 220ms UI 防抖到期后调本函数。任务带递增 id，先发后至的旧响应
    // 不会覆盖新输入的建议。
    public func requestAutocomplete(rawQuery: String): Unit {
        let queryText = rawQuery.trimAscii()
        let a = api ?? return clearAutocomplete()
        if (queryText.size == 0) {
            clearAutocomplete()
            return
        }
        autocompleteRequestId += 1
        let requestId = autocompleteRequestId
        let taskName = "autocomplete:${requestId}"
        autocompleteTaskName = taskName
        autocompleteQuery.value = queryText
        autocompleteSuggestions.value = ArrayList<TagSuggestion>()
        autocompleteLoading.value = true
        autocompleteVisible.value = true
        let lang = language.value
        let _ = worker.submitTagged(taskName, lang,
            {=> (requestId, queryText, a.tagAutocomplete(queryText, 10, lang: lang))})
    }

    public func dismissAutocomplete(): Unit {
        autocompleteVisible.value = false
    }

    public func clearAutocomplete(): Unit {
        autocompleteRequestId += 1
        autocompleteTaskName = ""
        autocompleteQuery.value = ""
        autocompleteSuggestions.value = ArrayList<TagSuggestion>()
        autocompleteLoading.value = false
        autocompleteVisible.value = false
    }

    // 横排行「查看更多」（继续阅读）：把行的排序规格搬进主查询并切到
    // 搜索/过滤模式网格。行不带过滤条件，只能靠 browseExited 显式出站。
    public func viewAllRow(key: String): Unit {
        if (key == "resume") {
            sortIndex.value = 3 // SEARCH_SORT_FIELDS 的 lastread（与 ui SORT_LABELS 同步）
            orderIndex.value = 1
        } else {
            return
        }
        browseExited = true
        submitSearch(1)
    }

    // 侧栏分类点击：0=全部分类；取消选择走「全部」（点击幂等，不做再次点击取消）。
    public func selectCategory(index: Int64): Unit {
        if (categoryIndex.value == index) {
            return
        }
        categoryIndex.value = index
        applyFilters()
    }

    // 浏览模式分类行「查看更多 ›」：选中该分类并切搜索/过滤模式。
    public func openCategory(catid: String): Unit {
        let cats = categories.value
        var i = 0
        while (i < cats.size) {
            if (cats[i].catid == catid) {
                selectCategory(i + 1)
                return
            }
            i++
        }
    }

    // 当前选中分类 id；0 或越界（换服后分类变短）按“全部分类”返回空串。
    public func selectedCategoryId(): String {
        let idx = categoryIndex.value
        if (idx <= 0 || idx > categories.value.size) {
            return ""
        }
        categories.value[idx - 1].catid
    }

    // 分类列表：登录/恢复会话成功后加载，供侧栏分类分组与浏览模式分类行使用。
    public func loadCategories(): Unit {
        let a = api ?? return
        let _ = worker.submit("categories", {=> a.categories()})
    }

    // ---- 上传抽屉 ----

    public func openUploadDrawer(): Unit {
        uploadDrawerOpen.value = true
        if (categories.value.size == 0) {
            loadCategories()
        }
    }

    // Drawer 自身先把 presented 置 false 再调用 onDismiss；有活动传输时立即写回 true，
    // 因而遮罩点击/Esc/关闭钮都遵守 frontend 的“传输中不可关闭”约束。
    public func closeUploadDrawer(): Unit {
        if (hasActiveUploads() || hasActiveDownloads()) {
            uploadDrawerOpen.value = true
            toaster.show("传输进行中，无法关闭", kind: ToastKind.Warning)
            return
        }
        uploadDrawerOpen.value = false
        uploadFileDialog.value = None<FileDialogRequest>
        uploadFiles.value = ArrayList<UploadFileItem>()
        uploadCategoryIndex.value = 0
        uploadTabIndex.value = 0
        downloadUrlsText.value = ""
        downloadTasks.value = ArrayList<DownloadTaskItem>()
        if (hasCompletedUploads || hasCompletedDownloads) {
            hasCompletedUploads = false
            hasCompletedDownloads = false
            loadCategories()
            refreshLibrary()
        }
    }

    public func beginUploadFileSelection(request: FileDialogRequest): Unit {
        match (uploadFileDialog.value) {
            case Some(current) =>
                if (!current.isDone()) {
                    toaster.show("文件选择器已打开", kind: ToastKind.Info)
                    return
                }
            case None => ()
        }
        uploadFileDialog.value = Some(request)
    }

    private func pollUploadFileDialog(): Unit {
        match (uploadFileDialog.value) {
            case Some(request) => match (request.result()) {
                case FileDialogResult.FileDialogPending => ()
                case FileDialogResult.FileDialogCanceled => uploadFileDialog.value = None<FileDialogRequest>
                case FileDialogResult.FileDialogFailed(message) =>
                    uploadFileDialog.value = None<FileDialogRequest>
                    showError(if (message.size > 0) {
                        "打开文件选择器失败：${message}"
                    } else {
                        "打开文件选择器失败"
                    })
                case FileDialogResult.FileDialogSelected(paths, _) =>
                    uploadFileDialog.value = None<FileDialogRequest>
                    addUploadPaths(paths)
            }
            case None => ()
        }
    }

    public func addUploadPath(path: String): Unit {
        addUploadPaths([path])
    }

    public func addUploadPaths(paths: Array<String>): Unit {
        let category = match (selectedUploadCategory()) {
            case Some(value) => value
            case None =>
                toaster.show("请先选择要上传到的分类", kind: ToastKind.Warning)
                return
        }
        for (rawPath in paths) {
            let path = rawPath.trimAscii()
            if (path.size == 0) {
                continue
            }
            if (!isSupportedArchiveUpload(path)) {
                toaster.show("不支持的档案格式：${Path(path).fileName}", kind: ToastKind.Warning)
                continue
            }
            var duplicate = false
            for (existing in uploadFiles.value) {
                if (existing.path == path && isUploadActive(existing.status)) {
                    duplicate = true
                    break
                }
            }
            if (duplicate) {
                toaster.show("该文件已在上传队列中", kind: ToastKind.Info)
                continue
            }
            try {
                let info = FileInfo(Path(path))
                let size = Int64(info.size)
                if (size <= 0) {
                    toaster.show("文件不能为空：${Path(path).fileName}", kind: ToastKind.Warning)
                    continue
                }
                uploadSequence += 1
                let item = UploadFileItem()
                item.id = "${uploadSequence}"
                item.path = path
                item.name = Path(path).fileName
                item.size = size
                item.categoryId = category.id
                uploadFiles.value.add(item)
                uploadFiles.value = uploadFiles.value
                startArchiveUpload(item, false)
            } catch (e: Exception) {
                showError("无法读取文件：${e.message}")
            }
        }
    }

    private func selectedUploadCategory(): ?CategoryItem {
        let index = uploadCategoryIndex.value
        if (index < 0 || index >= categories.value.size) {
            return None<CategoryItem>
        }
        let category = categories.value[index]
        if (category.id <= 0) {
            return None<CategoryItem>
        }
        Some(category)
    }

    private func startArchiveUpload(item: UploadFileItem, overwrite: Bool): Unit {
        let a = api ?? return item.status = "queued"
        item.progress = 0
        item.message = "排队中"
        uploadFiles.value = uploadFiles.value
        let id = item.id
        let path = item.path
        let categoryId = item.categoryId
        let mailbox = worker
        let submitted = worker.submit(
            "upload:${id}",
            {
                =>
                    let result = a.uploadArchive(path, categoryId, overwrite, {
                        stage, progress, message => mailbox.post("upload.progress", Some((id, stage, progress, message)))
                    })
                    return (id, result)
            }
        )
        if (!submitted) {
            item.status = "error"
            item.message = "上传任务已在运行"
            uploadFiles.value = uploadFiles.value
        }
    }

    public func retryUpload(id: String, overwrite!: Bool = false): Unit {
        match (findUpload(id)) {
            case Some(item) =>
                if (!isUploadActive(item.status)) {
                    startArchiveUpload(item, overwrite)
                }
            case None => ()
        }
    }

    public func removeUpload(id: String): Unit {
        let next = ArrayList<UploadFileItem>()
        for (item in uploadFiles.value) {
            if (item.id != id || isUploadActive(item.status)) {
                next.add(item)
            }
        }
        uploadFiles.value = next
    }

    public func clearCompletedUploads(): Unit {
        let next = ArrayList<UploadFileItem>()
        for (item in uploadFiles.value) {
            if (item.status != "success") {
                next.add(item)
            }
        }
        uploadFiles.value = next
    }

    public func clearUploads(): Unit {
        if (hasActiveUploads()) {
            toaster.show("传输进行中，无法清空", kind: ToastKind.Warning)
            return
        }
        uploadFiles.value = ArrayList<UploadFileItem>()
    }

    public func hasActiveUploads(): Bool {
        for (item in uploadFiles.value) {
            if (isUploadActive(item.status)) {
                return true
            }
        }
        false
    }

    private func isUploadActive(status: String): Bool {
        status == "queued" || status == "uploading" || status == "processing"
    }

    private func findUpload(id: String): ?UploadFileItem {
        for (item in uploadFiles.value) {
            if (item.id == id) {
                return Some(item)
            }
        }
        None<UploadFileItem>
    }

    // ---- 在线下载 ----

    // 每行一个 URL：空行跳过，非法链接提示后跳过，与活动任务重复的链接跳过。
    public func addDownloadTasks(): Unit {
        let category = match (selectedUploadCategory()) {
            case Some(value) => value
            case None =>
                showError("请先选择要下载到的分类")
                return
        }
        var added: Int64 = 0
        for (rawLine in downloadUrlsText.value.split("\n")) {
            let url = rawLine.trimAscii()
            if (url.size == 0) {
                continue
            }
            if (!url.startsWith("http://") && !url.startsWith("https://")) {
                toaster.show("下载链接无效：${url}", kind: ToastKind.Warning)
                continue
            }
            var duplicate = false
            for (existing in downloadTasks.value) {
                if (existing.url == url && isDownloadActive(existing.status)) {
                    duplicate = true
                    break
                }
            }
            if (duplicate) {
                toaster.show("该链接已在下载队列中", kind: ToastKind.Info)
                continue
            }
            downloadSequence += 1
            let item = DownloadTaskItem()
            item.id = "${downloadSequence}"
            item.url = url
            item.categoryId = category.id
            downloadTasks.value.add(item)
            downloadTasks.value = downloadTasks.value
            added += 1
            startUrlDownload(item)
        }
        if (added > 0) {
            downloadUrlsText.value = ""
        }
    }

    private func startUrlDownload(item: DownloadTaskItem): Unit {
        let a = api ?? return item.status = "queued"
        item.progress = 0
        item.message = "排队中"
        downloadTasks.value = downloadTasks.value
        let id = item.id
        let url = item.url
        let categoryId = item.categoryId
        let mailbox = worker
        let submitted = worker.submit(
            "download:${id}",
            {
                =>
                    let result = a.downloadFromUrl(url, categoryId, {
                        stage, progress, message => mailbox.post("download.progress", Some((id, stage, progress, message)))
                    })
                    return (id, result)
            }
        )
        if (!submitted) {
            item.status = "error"
            item.message = "下载任务已在运行"
            downloadTasks.value = downloadTasks.value
        }
    }

    public func removeDownloadTask(id: String): Unit {
        let next = ArrayList<DownloadTaskItem>()
        for (item in downloadTasks.value) {
            if (item.id != id || isDownloadActive(item.status)) {
                next.add(item)
            }
        }
        downloadTasks.value = next
    }

    public func clearCompletedDownloads(): Unit {
        let next = ArrayList<DownloadTaskItem>()
        for (item in downloadTasks.value) {
            if (item.status != "success") {
                next.add(item)
            }
        }
        downloadTasks.value = next
    }

    public func clearDownloads(): Unit {
        if (hasActiveDownloads()) {
            toaster.show("传输进行中，无法清空", kind: ToastKind.Warning)
            return
        }
        downloadTasks.value = ArrayList<DownloadTaskItem>()
    }

    public func hasActiveDownloads(): Bool {
        for (item in downloadTasks.value) {
            if (isDownloadActive(item.status)) {
                return true
            }
        }
        false
    }

    private func isDownloadActive(status: String): Bool {
        status == "queued" || status == "downloading" || status == "processing"
    }

    private func findDownload(id: String): ?DownloadTaskItem {
        for (item in downloadTasks.value) {
            if (item.id == id) {
                return Some(item)
            }
        }
        None<DownloadTaskItem>
    }

    // 总页数（至少 1 页）；pageSize 异常时按 40 防御。
    public func maxPage(): Int64 {
        let size = if (query.pageSize > 0) {
            query.pageSize
        } else {
            40
        }
        let total = recordsTotal.value
        if (total <= 0) {
            return 1
        }
        (total + size - 1) / size
    }

    // ---- 浏览模式行数据 ----

    // 建立/刷新行集合：继续阅读 + 随机推荐 + 分类前 BROWSE_CATEGORY_ROW_LIMIT 个
    // （新到档案行已按用户要求移除，随机推荐之下直接接分类行）。
    // 已存在的行原样保留（随机行不因分类列表到达而重洗）；仅对未请求过的行提交任务，
    // 任务名按行唯一（row:resume / row:random / row:<catid>），worker 对在途同名任务去重。
    public func loadBrowseRows(): Unit {
        if (api.isNone()) {
            return
        }
        let old = browseRows.value
        let rows = ArrayList<BrowseRow>()
        rows.add(findOrCreateRow(old, "resume", t("library.resume"), ""))
        rows.add(findOrCreateRow(old, "random", t("library.random"), ""))
        let cats = categories.value
        var n: Int64 = 0
        while (n < cats.size && n < BROWSE_CATEGORY_ROW_LIMIT) {
            let c = cats[n]
            rows.add(findOrCreateRow(old, c.catid, c.name, c.catid))
            n++
        }
        browseRows.value = rows
        // 分批提交：先行行（继续阅读/随机推荐）立即加载，分类行进待补队列按批补发。
        pendingRows = ArrayList<BrowseRow>()
        for (r in rows) {
            if (r.requested) {
                continue
            }
            if (r.key == "resume" || r.key == "random") {
                submitRowTask(r)
            } else {
                pendingRows.add(r)
            }
        }
        submitNextRowBatch()
    }

    // 补发下一批分类行：在途行任务不超 ROW_BATCH_SIZE 时从待补队列取（重入行防御跳过）。
    private func submitNextRowBatch(): Unit {
        while (runningRowTasks < ROW_BATCH_SIZE && pendingRows.size > 0) {
            let r = pendingRows.remove(at: 0)
            if (r.requested) {
                continue
            }
            runningRowTasks++
            submitRowTask(r)
        }
    }

    // 行任务落盘（dispatch 成功分支与 handleError 失败分支都调）：计数复位并补发下一批。
    private func onRowTaskFinished(): Unit {
        runningRowTasks--
        if (runningRowTasks < 0) {
            runningRowTasks = 0
        }
        submitNextRowBatch()
    }

    private func findOrCreateRow(old: ArrayList<BrowseRow>, key: String, title: String, catid: String): BrowseRow {
        for (r in old) {
            if (r.key == key) {
                return r
            }
        }
        let r = BrowseRow()
        r.key = key
        r.title = title
        r.catid = catid
        r
    }

    private func submitRowTask(r: BrowseRow): Unit {
        let a = api ?? return r.requested = true
        r.loading = true
        r.failed = false
        let lang = language.value
        if (r.key == "random") {
            let groupbyTanks = tankGroupOn()
            let _ = worker.submitTagged("row:random", lang,
                {
                    =>
                        // LANLU_PERF 打点：行搜索 RPC 实际执行耗时（区分 RPC 慢与 API 池排队）。
                        let rpcT0 = MonoTime.now()
                        let sp = a.randomSearch(BROWSE_ROW_SIZE, lang: lang, groupbyTanks: groupbyTanks)
                        if (SubtitlePerf.enabled()) {
                            SubtitlePerf.sampleUs("row_rpc_us", (MonoTime.now() - rpcT0).toMicroseconds())
                        }
                        sp
                })
        } else {
            // 继续阅读 = 最近阅读倒序（固定）；分类行跟随工具条排序/方向。
            // 浏览模式的所有行（包括上面的随机行）都跟随「合集聚合」开关。
            let q = SearchQuery()
            q.pageSize = BROWSE_ROW_SIZE
            q.groupbyTanks = tankGroupOn()
            q.lang = lang
            if (r.key == "resume") {
                q.sortby = "lastread"
                q.order = "desc"
            } else {
                q.categoryId = r.catid
                q.sortby = SEARCH_SORT_FIELDS[sortIndex.value]
                q.order = if (orderIndex.value == 0) {
                    "asc"
                } else {
                    "desc"
                }
            }
            let _ = worker.submitTagged("row:${r.key}", lang,
                {
                    =>
                        // LANLU_PERF 打点：行搜索 RPC 实际执行耗时（区分 RPC 慢与 API 池排队）。
                        let rpcT0 = MonoTime.now()
                        let sp = a.search(q)
                        if (SubtitlePerf.enabled()) {
                            SubtitlePerf.sampleUs("row_rpc_us", (MonoTime.now() - rpcT0).toMicroseconds())
                        }
                        sp
                })
        }
    }

    // 随机行「换一批」：重新随机（服务端 RANDOM() 每次新采样）。
    public func refreshRandomRow(): Unit {
        for (r in browseRows.value) {
            if (r.key == "random") {
                submitRowTask(r)
                browseRows.value = browseRows.value
                return
            }
        }
    }

    // 行加载失败后的点击重试。
    public func retryRow(key: String): Unit {
        for (r in browseRows.value) {
            if (r.key == key) {
                submitRowTask(r)
                browseRows.value = browseRows.value
                return
            }
        }
    }

    // 工具条「刷新」：按当前模式刷新——浏览模式重载全部行，搜索/过滤模式重查当前页。
    public func refreshLibrary(): Unit {
        if (isBrowseMode()) {
            for (r in browseRows.value) {
                submitRowTask(r)
            }
            browseRows.value = browseRows.value
        } else {
            submitSearch(currentPage.value)
        }
    }

    // ---- 图片 ----

    // key → 原始编码字节的磁盘缓存（按服务器地址分目录），首次使用时创建。
    private var imageCache: ?ImageCache = None
    private var subtitleDiskCache: ?SubtitleCache = None
    private let subtitleTokenMutex = Mutex()
    private let subtitleTokens = HashMap<String, SubtitleCancelToken>()

    // 缓存目录按当前 active 服务器地址派生；无 active 时退化为选中服务器/空串。
    private func activeBaseUrl(): String {
        match (settings.activeProfile()) {
            case Some(p) => return p.baseUrl
            case None => ()
        }
        match (selectedProfile()) {
            case Some(p) => p.baseUrl
            case None => ""
        }
    }

    private func cache(): ImageCache {
        match (imageCache) {
            case Some(c) => return c
            case None =>
                let c = ImageCache(defaultCacheRoot(activeBaseUrl()))
                imageCache = c
                // 启动时后台按 2GB 阈值做一次 LRU 清理（spec §5.3）；周期补扫见 maybeSweepCache。
                lastSweepAt = MonoTime.now()
                let _ = worker.submit(
                    "sweep",
                    {
                        =>
                            c.sweep(SWEEP_MAX_BYTES);
                            return true
                    }
                )
                return c
        }
    }

    private func subtitleCache(): SubtitleCache {
        match (subtitleDiskCache) {
            case Some(c) => return c
            case None =>
                let c = SubtitleCache(defaultCacheRoot(activeBaseUrl()))
                subtitleDiskCache = Some(c)
                return c
        }
    }

    // ---- 字幕缓存诊断/清理（性能基准用）----

    public func clearSubtitleCache(): Unit {
        subtitleCache().clear()
    }

    public func subtitleCacheBytes(): Int64 {
        subtitleCache().totalBytes()
    }

    public func subtitleCacheFileCount(): Int64 {
        subtitleCache().fileCount()
    }

    private func registerSubtitleToken(taskName: String): ?SubtitleCancelToken {
        synchronized(subtitleTokenMutex) {
            if (subtitleTokens.contains(taskName)) {
                return None
            }
            let token = SubtitleCancelToken()
            subtitleTokens[taskName] = token
            Some(token)
        }
    }

    private func releaseSubtitleToken(taskName: String, token: SubtitleCancelToken): Unit {
        synchronized(subtitleTokenMutex) {
            subtitleTokens.remove(taskName)
        }
        token.close()
    }

    private func cancelSubtitleTokens(generation: UInt64, key: String): Unit {
        let suffix = ":${generation}:${key}"
        synchronized(subtitleTokenMutex) {
            for ((name, token) in subtitleTokens) {
                if (name.endsWith(suffix)) {
                    token.cancel()
                }
            }
        }
    }

    // 离线缓存单例：懒打开（打开失败 None，离线能力缺失不阻断启动），多服务器靠前缀隔离。
    private func offlineCacheFor(): ?OfflineCache {
        match (offlineCache) {
            case Some(c) => return c
            case None => ()
        }
        let c = match (offlineCachePrewarm) {
            case Some(f) =>
                // 启动预热线程的 join：结果与同步 open 相同；消费后置 None，失败（None）
                // 时下次调用走同步重试，与无预热路径的重试语义一致。
                offlineCachePrewarm = None
                f.get()
            case None => OfflineCache.open(defaultOfflineCacheRoot())
        }
        offlineCache = c
        c
    }

    // 离线回退提示：pump 每帧轮询，worker 置位后 UI 线程 toast（每次会话一次）。
    private func pollOfflineNotice(): Unit {
        if (offlineNotice.take()) {
            if (!offlineToastShown) {
                offlineToastShown = true
                toaster.show("离线模式：显示缓存数据", kind: ToastKind.Info)
            }
        }
    }

    // 当前登录服务端恢复（探测 online/登录成功）后补报离线阅读进度；单条失败保留队列下次再试。
    // 提交任务前固定 profile 与 API，避免切服后异步任务把进度写到另一台服务器。
    private func flushOfflineProgress(profile: ServerProfile): Unit {
        if (settings.activeServerId != profile.id) {
            return
        }
        let targetApi = api ?? return
        let c = match (offlineCache) {
            case Some(x) => x
            case None => return
        }
        let hash = fnv1a64Hex(profile.baseUrl)
        let accountScope = offlineAccountScope(profile.id, profile.username, profile.token)
        let entries = c.listProgress(hash, accountScope, limit: 64)
        if (entries.size == 0) {
            return
        }
        let _ = worker.submit(
            "offline-flush",
            {
                =>
                    var anyOk = false
                    var batch = entries
                    while (batch.size > 0) {
                        let ok = ArrayList<String>()
                        for (e in batch) {
                            try {
                                targetApi.setProgress(e[0], e[1])
                                ok.add(e[0])
                            } catch (err: Exception) {
                                // 部分失败不串数据：只标记该条重试状态，其余照常 ack。
                                let _ = c.markProgressFailed(hash, accountScope, e[0], err.message)
                            }
                        }
                        if (ok.size > 0 && c.ackProgressBatch(hash, accountScope, ok)) {
                            anyOk = true
                        }
                        if (batch.size < 64) {
                            break
                        }
                        batch = c.listProgress(hash, accountScope, limit: 64)
                    }
                    return anyOk
            }
        )
    }

    // 磁盘缓存周期 sweep（#10）：启动一次之外，每小时兜底或累计新写入超阈值（512MB）时补扫。
    // 与在途读取的竞争沿用 ImageCache 既有惯例兜底：sweep 跳过 .bin 在途半成品、按 mtime
    // 最旧优先删（刚定稿、即将被解码的文件最后被考虑），解码侧打开失败经 decodeCachedOrEvict
    // 剔除坏条目并置 error 态自愈（重试重新拉取）；.bin→rename 原子定稿惯例不变。
    private var lastSweepAt: ?MonoTime = None
    private var sweepBytesSinceSweep: Int64 = 0
    private let sweepMutex = Mutex()

    // 工作线程回调（图片任务下载写入器内）：累计新落盘的缓存字节。下载写入器只在缓存
    // 未命中时执行，其返回字节数即本次新写入量；计数只读写在锁内，UI 线程判定见
    // maybeSweepCache。public 供 ImageWriter（CacheWriter 实现）调用。
    public func noteCacheWrite(bytes: Int64): Unit {
        synchronized(sweepMutex) {
            sweepBytesSinceSweep += bytes
        }
    }

    // 周期 sweep 判定（pump 每迭代调用，UI 线程）：到点或写入超阈值才提交；worker 同名
    // 去重——已在途的 sweep 不会叠加（提交被拒时保留计数与时刻，下轮迭代再试）。
    private func maybeSweepCache(): Unit {
        let c = match (imageCache) {
            case Some(x) => x
            case None => return
        }
        let due = match (lastSweepAt) {
            case Some(at) => (MonoTime.now() - at).toMilliseconds() >= SWEEP_INTERVAL_MS
            case None => true
        }
        var written: Int64 = 0
        synchronized(sweepMutex) {
            written = sweepBytesSinceSweep
        }
        if (!due && written < SWEEP_WRITE_TRIGGER_BYTES) {
            return
        }
        let submitted = worker.submit(
            "sweep",
            {
                =>
                    c.sweep(SWEEP_MAX_BYTES)
                    return true
            }
        )
        if (submitted) {
            lastSweepAt = MonoTime.now()
            synchronized(sweepMutex) {
                sweepBytesSinceSweep = 0
            }
        }
    }

    public func imageState(key: String): State<String> {
        synchronized(imageMutex) {
            match (imageStates.get(key)) {
                case Some(st) => return st
                case None =>
                    let st = State<String>("")
                    imageStates[key] = st
                    return st
            }
        }
    }

    // 图片仍被需要（工作线程协作式取消判定，P2.7）：状态为 loading 才算在途需要；
    // 已被 cancelImage 复位（""）或完成（"ready"）的不再需要（ready 的结果已有纹理）。
    private func isImageWanted(key: String): Bool {
        synchronized(imageMutex) {
            match (imageStates.get(key)) {
                case Some(st) => st.value == "loading"
                case None => false
            }
        }
    }

    // 图片并发硬上限 8（2026-08 LANLU_PERF 实测由 4 上调：书库滚动时图片 e2e 的 ~85%
    // 耗在等槽位，而下载/解码本身 p50 仅 ~20ms；8 与下载池 6/解码池 4 配套，8 核内不
    // 造成过度订阅）：超出进队列，完成一个补一个。
    // 队列拆成高优先级 FIFO 与普通优先级 FIFO（P2.8）：高优先级插队不再重建整个
    // ArrayList，只往高优先级队列尾部追加；同优先级保持 FIFO。requestImage 与 pump
    // 都在 UI 线程运行，计数无需加锁。
    private var activeImages: Int64 = 0
    private var imageQueueHi = ArrayList<(String, String)>() // (key, url) 高优先级
    private var imageQueueLo = ArrayList<(String, String)>() // (key, url) 普通优先级

    // ── LANLU_PERF=1 打点（性能评估，默认关闭零开销）──
    // imgPerfT0：key 首次 requestImage 的时刻（UI 线程独占，无需锁），dispatch 到货时
    // 算出用户感知 e2e；imgPerfStage：worker 线程写入的 (下载us, 解码us) 分阶段耗时，
    // dispatch 读取后移除（跨线程，加锁）。readerTurn*：翻页时刻与当前 spread 未到位
    // 图片集合，全部到达时 emit reader_turn_ms（0ms = 预取全命中）。
    private let imgPerfT0 = HashMap<String, MonoTime>()
    private let imgPerfStageMutex = Mutex()
    private let imgPerfStage = HashMap<String, (Int64, Int64)>()
    private var readerTurnT0: ?MonoTime = None
    private let readerTurnPending = HashSet<String>()
    private var lastPerfFlush = MonoTime.now()
    private var firstRowsEmitted = false

    // LANLU_PERF 打点：worker 线程记录 key 的分阶段耗时（stage: 0=下载 1=解码）。
    private func perfStageMark(key: String, stage: Int64, us: Int64): Unit {
        synchronized(imgPerfStageMutex) {
            match (imgPerfStage.get(key)) {
                case Some(prev) =>
                    if (stage == 0) {
                        imgPerfStage[key] = (us, prev[1])
                    } else {
                        imgPerfStage[key] = (prev[0], us)
                    }
                case None =>
                    if (stage == 0) {
                        imgPerfStage[key] = (us, 0)
                    } else {
                        imgPerfStage[key] = (0, us)
                    }
            }
        }
    }

    // LANLU_PERF 打点：翻页后记录当前 spread 尚未 ready 的图片 key；全部到达由
    // dispatch("img:") emit reader_turn_ms，本就全部命中则这里直接 emit 0ms。
    private func perfReaderTurnMark(): Unit {
        if (!SubtitlePerf.enabled()) {
            return
        }
        readerTurnPending.clear()
        for (i in reader.spreadPages()) {
            match (reader.pageAt(i)) {
                case Some(p) =>
                    if (p.pageType == "image" || p.pageType == "") {
                        let key = "page:${reader.arcidOfReal(i)}:${p.id}"
                        if (imageState(key).value != "ready") {
                            readerTurnPending.add(key)
                        }
                    }
                case None => ()
            }
        }
        if (readerTurnPending.isEmpty()) {
            readerTurnT0 = None
            SubtitlePerf.emit("reader_turn_ms", 0, "ms")
        } else {
            readerTurnT0 = Some(MonoTime.now())
        }
    }

    // LANLU_PERF=1：每 5s 滚动输出样本分位数（flushSamples 输出后清空，即上一窗口的
    // 分布），并拉取 cui 纹理上传计数（UI 线程惰性上传，帧成本热点）。
    private func perfFlushTick(): Unit {
        if (!SubtitlePerf.enabled()) {
            return
        }
        let now = MonoTime.now()
        if ((now - lastPerfFlush).toMilliseconds() < 5000) {
            return
        }
        lastPerfFlush = now
        SubtitlePerf.flushSamples("img_queuewait_us")
        SubtitlePerf.flushSamples("img_download_us")
        SubtitlePerf.flushSamples("img_decode_us")
        SubtitlePerf.flushSamples("img_e2e_us")
        SubtitlePerf.flushSamples("pump_dispatch_us")
        SubtitlePerf.flushSamples("pump_img_us")
        SubtitlePerf.flushSamples("pump_files_us")
        SubtitlePerf.flushSamples("pump_row_us")
        SubtitlePerf.flushSamples("pump_categories_us")
        SubtitlePerf.flushSamples("pump_me_us")
        SubtitlePerf.flushSamples("pump_meta_us")
        SubtitlePerf.flushSamples("pump_other_us")
        SubtitlePerf.flushSamples("me_rpc_us")
        SubtitlePerf.flushSamples("row_rpc_us")
        let (n, totalUs, maxUs) = pixelUploadPerfStats()
        if (n > 0) {
            println("[perf] tex_upload count=${n} avg=${totalUs / n / 1000}ms max=${maxUs / 1000}ms")
            pixelUploadPerfReset()
        }
    }

    // 已在途/已排队/已完成的 key 直接跳过（状态机去重，队列不会进重）；否则置 loading
    // 并提交 img:<key> 任务。key 约定：asset:<assetId>（封面/资产）、athumb:<assetId>
    // （资产缩略图，300px 档）、page:<arcid>:<pagePath>（阅读页）与
    // thumb:<arcid>:<pagePath>（300px 缩略图档）。
    // highPriority：当前可见的关键图（阅读当前页）置 true，滚屏封面/预取用默认 false。
    public func requestImage(key: String, url: String, highPriority!: Bool = false): Unit {
        let st = imageState(key)
        if (st.value == "loading" || st.value == "ready") {
            return
        }
        st.value = "loading"
        // LANLU_PERF 打点：记录首次请求时刻（e2e 起点；重试不覆盖，保留用户最早等待点）。
        if (SubtitlePerf.enabled() && !imgPerfT0.contains(key)) {
            imgPerfT0[key] = MonoTime.now()
        }
        if (activeImages >= 8) {
            // 按优先级进各自 FIFO：高优先级始终先于低优先级补位（P2.8，无整队列复制）。
            if (highPriority) {
                imageQueueHi.add((key, url))
            } else {
                imageQueueLo.add((key, url))
            }
            return
        }
        startImageTask(key, url)
    }

    // 取消未开始的排队请求（滚出屏幕的封面等）：从两个优先级队列移除并复位状态，
    // 之后重新可见时 requestImage 可再次入队。已开始/在途任务不干预——
    // 其完成结果落磁盘/staged 缓存无害（P2.7 的协作式取消点会跳过解码）。
    // 仅 UI 线程调用（同 requestImage/pump 纪律）。
    // 图片状态复位代际：任何把已请求 key 复位为 "" 的路径（cancelImage 队列取消、
    // 像素纹理 LRU 逐出回调）都 +1。条漫可见区请求去重缓存（reader_stage.cj）以此为
    // 输入之一——不复位的复位路径会让缓存漏掉重新请求。retryImage 同步复位并重入队，
    // 无中间窗口，不参与。
    public var imageResetEpoch: Int64 = 0

    public func cancelImage(key: String): Unit {
        // LANLU_PERF 打点：滚出屏幕取消排队时清掉 e2e 起点，重新可见后再请求从 0 计。
        if (SubtitlePerf.enabled()) {
            imgPerfT0.remove(key)
        }
        var i: Int64 = 0
        while (i < imageQueueHi.size) {
            if (imageQueueHi[i][0] == key) {
                let _ = imageQueueHi.remove(at: i)
                imageState(key).value = ""
                imageResetEpoch++
                return
            }
            i++
        }
        i = 0
        while (i < imageQueueLo.size) {
            if (imageQueueLo[i][0] == key) {
                let _ = imageQueueLo.remove(at: i)
                imageState(key).value = ""
                imageResetEpoch++
                return
            }
            i++
        }
    }

    // url 目前不参与下载（地址由 key 约定推导，经 LanluApi 带 Bearer）；
    // 保留参数是为与队列条目/requestImage 签名对齐，便于将来按 url 直取。
    private func startImageTask(key: String, url: String): Unit {
        let _ = url
        let a = match (api) {
            case Some(x) => x
            case None =>
                imageState(key).value = "error"
                return
        }
        // 防御：page:/thumb: 畸形 key（pagePath 缺分隔符）直接置 error 返回，
        // 避免切出空 arcid 发出必然 404 的请求（key 由内部生成，正常不会触发）。
        if ((key.startsWith("page:") && key.removePrefix("page:").indexOf(":").isNone()) || (key.startsWith("thumb:") &&
            key.removePrefix("thumb:").indexOf(":").isNone())) {
            imageState(key).value = "error"
            return
        }
        activeImages++
        // LANLU_PERF 打点：requestImage → 实际开跑的排队等待（并发上限 8 的排队成本）。
        if (SubtitlePerf.enabled()) {
            match (imgPerfT0.get(key)) {
                case Some(t0) => SubtitlePerf.sampleUs("img_queuewait_us", (MonoTime.now() - t0).toMicroseconds())
                case None => ()
            }
        }
        let c = cache()
        // 图片任务走三级流水线（P1.6）：下载阶段在独立下载池（6 线程），完成后在下载
        // 线程内把解码阶段提交到独立解码池（4 线程、有界队列 32 背压）；两阶段都不再
        // 占用交互 API 池（#22）。activeImages 并发硬上限 8 与优先级插队语义不变
        //（见 requestImage/pump）。
        // 下载阶段使用独立命名空间 "imgdl:" 避免与解码阶段 "img:" 的 inflight 冲突
        //（workLoop 在 job 返回后才释放 inflight，job 内部 submitDecode 时下载条目仍在）；
        // 解码阶段使用 "img:" 使 UI dispatch 正常处理结果。single-flight 已在 ImageCache
        // 层保证磁盘只下载一次。
        let submitted = worker.submitDownload(
            "imgdl:${key}",
            {
                =>
                    // 下载写入器：流式把原始字节写入缓存临时文件（固定缓冲，不随
                    // 图片大小增长）；返回本次落盘字节数（#10 周期 sweep 的写入触发计数）。
                    let writer = ImageWriter(this, a, key)
                    // 缓存原始字节（工作线程上流式落盘，按原始资源 key 去重/共用：thumb
                    // 与 page 共享同一份原始页面文件）
                    let rawKey = rawKeyFor(key)
                    let dlT0 = MonoTime.now()
                    let path = c.ensureCached(rawKey, writer)
                    // LANLU_PERF 打点：下载+落盘（命中磁盘缓存时≈0）。
                    if (SubtitlePerf.enabled()) {
                        let dlUs = (MonoTime.now() - dlT0).toMicroseconds()
                        SubtitlePerf.sampleUs("img_download_us", dlUs)
                        perfStageMark(key, 0, dlUs)
                    }
                    // 下载完成 → 提交解码阶段（解码池；队列满则阻塞下载线程产生背压）。
                    // 解码阶段使用 "img:" 命名空间（与下载阶段 "imgdl:" 分开），inflight
                    // 不冲突；UI dispatch 按 "img:" 正常处理解码结果。
                    let ok = worker.submitDecode(
                        "img:${key}",
                        {
                            =>
                                // 协作式取消点：下载完成但图片已不可见（状态被复位/取消）时
                                // 保留磁盘缓存并跳过解码（省 CPU；重新可见时再解码）。
                                if (!isImageWanted(key)) {
                                    return (key, Option<NativeDecodedImage>.None)
                                }
                                // vips 按展示 key 档位缩小解码原生 RGBA；纹理创建留给 UI 线程
                                // 首帧惰性完成。解码失败时 decodeCachedOrEvict 会先剔除坏缓存
                                //（原始 key 条目）再抛出，重试可重新拉取。解码期间标记引用，
                                // sweep 不得删除正在被 vips 打开的文件（P2.9）。
                                c.markReferenced(rawKey)
                                let decT0 = MonoTime.now()
                                let d = try {
                                    decodeCachedOrEvict(c, rawKey, path, maxDimension: decodeMaxDimension(key))
                                } finally {
                                    c.clearReferenced(rawKey)
                                }
                                // LANLU_PERF 打点：vips 解码（含 shrink-on-load/resize/圆角前）。
                                if (SubtitlePerf.enabled()) {
                                    let decUs = (MonoTime.now() - decT0).toMicroseconds()
                                    SubtitlePerf.sampleUs("img_decode_us", decUs)
                                    perfStageMark(key, 1, decUs)
                                }
                                // 封面圆角在工作线程内完成（原生内存直改 alpha，避免 UI dispatch
                                // 遍历整张封面像素）；阅读页（page:/thumb:）不处理。
                                if (key.startsWith("asset:")) {
                                    roundCoverAlphaNative(d)
                                }
                                return (key, Some(d))
                        }
                    )
                    if (!ok) {
                        throw Exception("解码任务提交失败: ${key}")
                    }
                    return true
            }
        )
        // 同名任务在途时 submit 去重返回 false：回滚并发计数，否则旧任务只减一次导致额度泄漏。
        // 状态保持 loading，由在途任务完成时经 dispatch/finishImageTask 正常设置，
        // 因此 retryImage 打到在途 key 也无害（无需额外短路）。
        if (!submitted) {
            activeImages--
        }
    }

    // 图片任务结束（成功或失败都调）：计数复位并补发队首（高优先级队列先于普通队列）。
    private func finishImageTask(): Unit {
        activeImages--
        if (activeImages < 0) {
            activeImages = 0
        }
        if (imageQueueHi.size > 0) {
            let (k, u) = imageQueueHi.remove(at: 0)
            startImageTask(k, u)
        } else if (imageQueueLo.size > 0) {
            let (k, u) = imageQueueLo.remove(at: 0)
            startImageTask(k, u)
        }
    }

    public func retryImage(key: String, url: String): Unit {
        imageState(key).value = ""
        requestImage(key, url)
    }

    // ---- 详情/阅读（Task 9/10 的视图调用）----

    public func openDetail(arcid: String): Unit {
        recommendedArchiveOriginScene = ""
        recommendedArchiveOriginSeedType = ""
        recommendedArchiveOriginSeedId = ""
        recommendedArchiveOriginId = ""
        match (page.value) {
            case Page.Shelf => detailReturnToShelf = true
            // 详情层级内继续跳转或阅读器返回时保留最初来源。
            case Page.Detail(_) | Page.Tank(_) | Page.Reader(_, _) => ()
            case _ => detailReturnToShelf = false
        }
        // 离开阅读器（典型路径就是 Esc/← 详情）前把进度尾巴发掉（去重丢尾教训）；
        // 无 pending 时为空操作。
        reader.flushProgress()
        playback.stop() // 离开阅读器停播（音频不带到详情页）
        lastLane = Book
        meta.value = None
        detailPages.value = ArchivePageView.empty(arcid: arcid)
        parentTanks.value = TankoubonView.empty(queryKey: "parent-tanks:${arcid}", language: language.value)
        relatedItems.value = SearchItemView.empty(queryKey: "related-archives:${arcid}", language: language.value)
        detailTagTranslations.value = TagTranslationView.empty(queryKey: "tag-translations:archive:${arcid}",
            language: language.value)
        detailLoadState.value = "loading"
        detailLoadError.value = ""
        detailPagesState.value = "loading"
        detailPagesError.value = ""
        navigate(Page.Detail(arcid))
        let a = api ?? return
        let lang = language.value
        let _ = worker.submitTagged("meta:${arcid}", lang, {=> a.metadata(arcid, lang: lang)})
        // 辅助卡片数据（页面预览/所属合集/相关推荐）：失败静默，卡片无数据即隐藏。
        let _ = worker.submit("dfiles:${arcid}", {=> a.files(arcid)})
        let _ = worker.submitTagged("ptanks:${arcid}", lang, {=> a.listArchiveTankoubons(arcid, lang: lang)})
        let _ = worker.submitTagged("related:${arcid}", lang, {=> a.relatedArchives(arcid, 12, lang: lang)})
        let _ = worker.submitTagged("tagtranslations:archive:${arcid}", lang, {
            => a.tagTranslations(lang, arcid: arcid)
        })
    }

    public func retryDetail(arcid: String): Unit {
        openDetail(arcid)
    }

    // 打开合集详情：元数据 + 成员档案 + 相关合集三路并发。
    public func openTank(tankid: String): Unit {
        match (page.value) {
            case Page.Shelf => detailReturnToShelf = true
            case Page.Detail(_) | Page.Tank(_) | Page.Reader(_, _) => ()
            case _ => detailReturnToShelf = false
        }
        tank.value = None
        tankMembers.value = SearchItemView.empty(queryKey: "tank-members:${tankid}", language: language.value)
        tankRelated.value = TankoubonView.empty(queryKey: "tank-related:${tankid}", language: language.value)
        tankFilter.value = ""
        detailTagTranslations.value = TagTranslationView.empty(queryKey: "tag-translations:tank:${tankid}",
            language: language.value)
        tankLoadState.value = "loading"
        tankLoadError.value = ""
        tankMembersState.value = "loading"
        tankMembersError.value = ""
        navigate(Page.Tank(tankid))
        let a = api ?? return
        let lang = language.value
        let _ = worker.submitTagged("tankmeta:${tankid}", lang, {=> a.getTankoubon(tankid, lang: lang)})
        // 成员档案按 256 项分批拉取并逐页写入 RocksDB membership，避免万级响应一次物化。
        let q = SearchQuery()
        q.tankoubonId = tankid
        q.sortby = "tank_order"
        q.order = "asc"
        q.pageSize = 256
        q.lang = lang
        let _ = worker.submitTagged("tankmembers:${tankid}", lang, {=> a.searchAll(q)})
        let _ = worker.submitTagged("tankrelated:${tankid}", lang, {
            => a.relatedTankoubons(tankid, 12, lang: lang)
        })
        let _ = worker.submitTagged("tagtranslations:tank:${tankid}", lang, {
            => a.tagTranslations(lang, tankid: tankid)
        })
    }

    public func retryTank(tankid: String): Unit {
        openTank(tankid)
    }

    // 重取合集详情（成员增删/收藏切换成功后刷新）：与 openTank 同三路并发，
    // 但不清空现有 State、不切页（避免已渲染内容闪空）。同名任务在途去重兜底。
    private func refreshTankDetail(tankid: String): Unit {
        let a = api ?? return
        let lang = language.value
        let _ = worker.submitTagged("tankmeta:${tankid}", lang, {=> a.getTankoubon(tankid, lang: lang)})
        let q = SearchQuery()
        q.tankoubonId = tankid
        q.sortby = "tank_order"
        q.order = "asc"
        q.pageSize = 256
        q.lang = lang
        let _ = worker.submitTagged("tankmembers:${tankid}", lang, {=> a.searchAll(q)})
        let _ = worker.submitTagged("tankrelated:${tankid}", lang, {
            => a.relatedTankoubons(tankid, 12, lang: lang)
        })
    }

    // 合集主操作：从首个成员档案开始阅读（按钮在无成员时禁用，不会空调用）。
    public func startTankReading(): Unit {
        let members = tankMembers.value
        if (members.size == 0) {
            return
        }
        openReader(members[0].arcid, 1)
    }

    // backdrop 模糊背景：元数据到货后，若有封面则提交 worker 任务，将封面缩到 ~256px 宽
    // 并经 vips 高斯模糊后解码为 RGBA 像素，供 detail_view 以 PixelImageView 放大为背景。
    // 失败静默（不 toast，不阻塞页面），backdrop 区域回退为纯色渐变。
    private func requestBackdrop(arcid: String, assetId: Int64): Unit {
        let a = api ?? return
        let imgKey = "backdrop:${arcid}"
        let c = cache()
        let _ = worker.submit(
            imgKey,
            {
                =>
                    // 与普通封面共享 asset:<id> 原始缓存文件（只分别执行普通解码或高斯
                    // 模糊解码），避免同一封面产生两份磁盘缓存。
                    let writer = ImageWriter(this, a, "asset:${assetId}")
                    let rawKey = "asset:${assetId}"
                    let path = c.ensureCached(rawKey, writer)
                    let d = decodeBackdrop(path, 256)
                    return (imgKey, d)
            }
        )
    }

    // 阅读器音频封面背景：与详情页相同，在图片工作线程完成缩放和真高斯模糊。
    public func requestAudioBackdrop(assetId: Int64): String {
        let imgKey = "backdrop:audio:${assetId}"
        let state = imageState(imgKey)
        if (state.value == "loading" || state.value == "ready") {
            return imgKey
        }
        state.value = "loading"
        let a = api ?? return imgKey
        let c = cache()
        let _ = worker.submit(
            imgKey,
            {
                =>
                    // 与普通封面共享 asset:<id> 原始缓存文件，只解码档/模糊参数不同。
                    let writer = ImageWriter(this, a, "asset:${assetId}")
                    let rawKey = "asset:${assetId}"
                    let path = c.ensureCached(rawKey, writer)
                    let d = decodeBackdrop(path, 320, blurSigma: 14.0)
                    return (imgKey, d)
            }
        )
        imgKey
    }

    public func openReader(arcid: String, startPage: Int64): Unit {
        if (recommendedArchiveOriginScene.size > 0 && recommendedArchiveOriginId == arcid) {
            trackRecommendation(recommendedArchiveOriginScene, recommendedArchiveOriginSeedType,
                recommendedArchiveOriginSeedId, "archive", arcid, "open_reader")
            recommendedArchiveOriginScene = ""
            recommendedArchiveOriginSeedType = ""
            recommendedArchiveOriginSeedId = ""
            recommendedArchiveOriginId = ""
        }
        match (page.value) {
            case Page.Shelf => detailReturnToShelf = true
            case _ => ()
        }
        playback.stop() // 换档案/重进阅读器：停掉上一媒体（旧进程不得泄漏）
        lastLane = Book // 与 reader.open 的 activeLane=Book 复位对齐
        readerArcid = arcid
        pages.value = ArchivePageView.empty(arcid: arcid)
        // 顶栏标题/收藏态随档案切换：清掉上一档案的元数据，避免迟到结果显示错档案。
        meta.value = None
        // 无缝续读状态复位：候选/在途标记/解析缓存不跨档案（reader.open 内重置流）。
        appendInFlight = false
        appendResolvedFrom = ""
        readerNextId = ""
        readerNextCoverKey = ""
        readerNextTitle.value = ""
        // 状态机 0 基流索引；Page.Reader 路由与 readerIndex State 维持 1 基显示页码。
        reader.open(arcid, startPage - 1)
        readerIndex.value = reader.displayPage
        readerPageSlider.value = Float32(reader.displayPage)
        // 自动播放计时重置：每次进入阅读器都从此刻开始计时，避免继承旧的
        // lastAutoPlayTurnMs（来自上一本书或 AppModel 初始值 0）导致立即触发翻页并误判末页。
        // 必须在 api ?? return 之前，否则离线模式会跳过重置。
        lastAutoPlayTurnMs = reader.clock()
        navigate(Page.Reader(arcid, startPage))
        let a = api ?? return
        let _ = worker.submit("files:${arcid}", {=> a.files(arcid)})
        // 顶栏标题与收藏态（reader-redesign #topbar）：复用元数据通道。
        let lang = language.value
        let _ = worker.submitTagged("meta:${arcid}", lang, {=> a.metadata(arcid, lang: lang)})
    }

    // 翻到显示页码 n（1 基）：seamlessNext 开 = 当前 segment 内页码，关 = 全局页码
    //（对齐 frontend slider 语义）；流索引换算在 ReaderModel.gotoDisplayPage 内。
    public func gotoPage(n: Int64): Unit {
        reader.gotoDisplayPage(n - 1)
        readerIndex.value = reader.displayPage
        readerPageSlider.value = Float32(reader.displayPage)
    }

    // 条漫滚动位置 -> 0 基流索引。这里不能走 gotoPage（其入参是当前 segment 的
    // 1 基显示页码），否则无缝续读跨 segment 后会跳回错误页。滚动只在实际跨页时
    // 广播，避免每个滚轮事件都重建整棵阅读器视图。
    public func syncWebtoonScrollPage(streamIndex: Int64): Unit {
        if (streamIndex == reader.index) {
            return
        }
        reader.gotoPage(streamIndex)
        readerIndex.value = reader.displayPage
        readerPageSlider.value = Float32(reader.displayPage)
        readerVersion.value += 1
    }

    // dock Book lane 的 ‹ ›：按阅读顺序步进一个 spread（方向换算不需要——dock 按钮
    // 语义就是「上一页/下一页」逻辑方向）。镜像同步与版本广播同 readerKeyTurn。
    public func readerTurnPage(forward: Bool): Unit {
        reader.turnPage(forward)
        readerIndex.value = reader.displayPage
        readerPageSlider.value = Float32(reader.displayPage)
        readerVersion.value += 1
        perfReaderTurnMark()
    }

    // html 页 PgUp/PgDn/空格：先页内按视口高翻滚（重叠 24px）；到底/到顶后
    // 外溢现有翻页语义。返回是否消费（非 html 页/未就绪返回 false 由调用方放行）。
    public func readerHtmlPageTurn(down!: Bool): Bool {
        if (htmlPage.state != "ready") {
            return false
        }
        let vh = Float32(htmlPage.viewportHeight())
        if (vh <= 0.0) {
            return false
        }
        let delta = max(24.0, vh - 24.0)
        let moved = htmlPage.scrollBy(if (down) {
            delta
        } else {
            -delta
        })
        if (!moved) {
            reader.turnPage(down)
            readerIndex.value = reader.displayPage
            readerPageSlider.value = Float32(reader.displayPage)
        }
        readerVersion.value += 1
        true
    }

    // 方向键翻页（T2 阅读舞台接线）：cui Key 已在视图层映射为 KeyCode，方向换算
    //（RTL 反转/TTB 上下/webtoon 不响应）全部在 ReaderModel.keyDirection 内；
    // None（webtoon/无效键）自然不翻页。命中后同步 1 基镜像并 bump readerVersion——
    // 舞台的自绘翻页动画靠 readerVersion 触发的重建检测 index 变化。
    public func readerKeyTurn(key: KeyCode): Unit {
        match (reader.keyDirection(key)) {
            case Some(forward) =>
                // HTML 双页先在当前章节内翻 spread；到章节边界才进入前/后一档案页。
                // 单页 HTML 同样保留“先滚正文、再翻档案页”的既有语义。
                if (htmlPage.state == "ready" && readerHtmlPageTurn(down: forward)) {
                    return
                }
                reader.turnPage(forward)
                readerIndex.value = reader.displayPage
                readerPageSlider.value = Float32(reader.displayPage)
                readerVersion.value += 1
                perfReaderTurnMark()
            case None => ()
        }
    }

    // 进度回传：PUT /api/archives/:id/progress/:page，任务名 progress（失败静默，见 handleError）。
    // 兼容委托：翻页上报已由 ReaderModel 防抖管线接管，这里把 pending 尾巴立即发出即可。
    public func reportProgress(): Unit {
        reader.flushProgress()
    }

    // 预取目标快照：上一次预取集合与本次的差集 = 已离开预取区的页，取消其未开始任务
    //（P2.7 可见性驱动取消；已开始的让其完成，结果落磁盘/staged 无害）。
    private var lastPrefetchKeys = HashSet<String>()

    // 预取当前页前后各 2 页（经图片管线，并发上限由 requestImage 保证）。
    // 只预取图片页（同 reader.onPrefetch 接线处的守卫）：audio/video/html 页
    // 不经图片管线展示，预取必然 4xx/5xx 或解码失败，且 error 态不挡 requestImage
    // 重复入队——音频档案里这会让每页翻页都重试全部曲目（重试风暴）。
    public func prefetchAround(): Unit {
        let total = pages.value.size
        let cur = readerIndex.value
        let next = HashSet<String>()
        for (d in [-2, -1, 1, 2]) {
            let idx = cur + d
            if (idx >= 1 && idx <= total) {
                let p = pages.value[idx - 1]
                if (p.pageType == "image" || p.pageType == "") {
                    let pid = p.id
                    let key = "page:${readerArcid}:${pid}"
                    next.add(key)
                    requestImage(key, "/api/archives/${readerArcid}/page?path=${percentEncode(pid)}")
                }
            }
        }
        // 离开预取区且尚未开始的任务取消（排队中移除；在途/已完成的跳过）。
        for (old in lastPrefetchKeys) {
            if (!next.contains(old)) {
                cancelImage(old)
            }
        }
        lastPrefetchKeys = next
    }

    // ---- 阅读器顶栏（T13：reader-redesign #topbar）----
    // ReaderModel 是纯逻辑类（属性非 State），影响 UI 的变更经 readerVersion 通知视图重建：
    // 顶栏/阅读页先读 readerVersion.value 订阅，再读 reader.* 普通属性。
    public let readerVersion = State<Int64>(0)
    // chrome 可见性镜像（pump 比对同步；autoHide 超时/open 复位等非视图路径的兜底出口）。
    private var lastChromeSync: Bool = true
    // 当前 spread 的媒体镜像。媒体加载只随内容 spread 变化，绝不能随 dock 展开项变化。
    private var lastLane: LaneId = Book
    // 当前 spread 的 html 页镜像（-1=无）：html 会话生命周期只跟 spread 走。
    private var lastHtmlPageIdx: Int64 = -1
    // 自动播放计时：上次自动翻页（或开关/间隔变更）的时钟读数（reader.clock 基准）。
    private var lastAutoPlayTurnMs: Int64 = 0
    // ---- 无缝续读：下一档案解析/拼接状态 ----
    private var appendInFlight = false // 解析/拼接在途（防重；openReader 复位）
    private var appendResolvedFrom = "" // 已完成解析链的源 arcid（成败都记，避免重复打）
    private var readerNextId = "" // 候选档案 id（""=未解析到）
    public var readerNextCoverKey = "" // 候选封面 asset key（""=无；结束页卡片用）

    // 候选档案标题（结束页卡片「下一档案：X」；seamless 关时也预解析）。
    public let readerNextTitle = State<String>("")

    // 顶栏 ⇄ 钮：循环切换阅读模式（ltr→rtl→ttb→webtoon→ltr），持久化在 ReaderModel 内完成。
    public func cycleReadingMode(): Unit {
        let next = match (reader.mode) {
            case ReadingMode.SingleLtr => ReadingMode.SingleRtl
            case ReadingMode.SingleRtl => ReadingMode.SingleTtb
            case ReadingMode.SingleTtb => ReadingMode.Webtoon
            case ReadingMode.Webtoon => ReadingMode.SingleLtr
        }
        reader.setMode(next)
        readerVersion.value += 1
    }

    // 舞台中央点击：显隐 chrome（顶栏）。
    public func toggleReaderChrome(): Unit {
        reader.toggleChrome()
        readerVersion.value += 1
    }

    // 鼠标/键盘活动：刷新自动隐藏计时；chrome 因此重新亮出时立即同步视图
    //（隐藏→亮出方向由 pump 的镜像比对兜底，二者都是 setIfChanged 语义，空转零成本）。
    public func noteReaderActivity(): Unit {
        let before = reader.chromeVisible
        reader.noteActivity()
        if (reader.chromeVisible != before) {
            readerVersion.value += 1
        }
    }

    // ---- 阅读器面板/浮层（State，视图直接订阅）----

    // 设置面板与页面导航侧栏互斥：开一个关另一个（屏幕右侧只有一块抽屉空间）。
    public let readerSettingsOpen = State<Bool>(false)
    public let readerSidebarOpen = State<Bool>(false)
    // 媒体信息浮层开关：初值取 settings（持久化键 readerShowInfo）。
    public let readerShowInfo: State<Bool>
    // dock 页码 Slider 绑定：State 已实现 Bindable<Float32>，直接绑它即可；
    // 本镜像只随 gotoPage/openReader/页表到货同步（Slider 拖动提交仍走 gotoPage）。
    public let readerPageSlider = State<Float32>(1.0)
    // 自动播放间隔 Slider 镜像（reader_panels 设置抽屉）：模型侧写入时同步镜像，
    // 镜像与模型值不一致即为用户拖动，视图构建期提交 setReaderAutoPlayInterval。
    public let autoPlayIntervalSlider = State<Float32>(3.0)

    public func toggleReaderSettings(): Unit {
        readerSettingsOpen.value = !readerSettingsOpen.value
        if (readerSettingsOpen.value) {
            readerSidebarOpen.value = false
        }
    }

    public func toggleReaderSidebar(): Unit {
        readerSidebarOpen.value = !readerSidebarOpen.value
        if (readerSidebarOpen.value) {
            readerSettingsOpen.value = false
        }
    }

    public func closeReaderPanels(): Unit {
        readerSettingsOpen.value = false
        readerSidebarOpen.value = false
    }

    // 信息浮层开关：写 settings 并落盘（与 reader.onPersist 同款 saveSettings）。
    public func toggleReaderShowInfo(): Unit {
        readerShowInfo.value = !readerShowInfo.value
        settings.readerShowInfo = readerShowInfo.value
        persistSettings(settings)
    }

    // ---- 阅读选项的 UI 入口：委托 ReaderModel 持久化，bump readerVersion 通知视图 ----

    public func setReadingMode(m: ReadingMode): Unit {
        reader.setMode(m)
        readerVersion.value += 1
    }
    public func toggleReaderDoublePage(): Unit {
        reader.setDoublePage(!reader.doublePage)
        htmlPage.setDoublePage(reader.doublePage)
        applyHtmlThemeCss()
        readerVersion.value += 1
    }
    public func toggleReaderSplitCover(): Unit {
        reader.setSplitCover(!reader.splitCover)
        readerVersion.value += 1
    }
    public func toggleReaderLongPage(): Unit {
        reader.setLongPage(!reader.longPage)
        readerVersion.value += 1
    }
    public func toggleReaderTapTurnPage(): Unit {
        reader.setTapTurnPage(!reader.tapTurnPage)
        readerVersion.value += 1
    }
    public func toggleReaderDoubleTapZoom(): Unit {
        reader.setDoubleTapZoom(!reader.doubleTapZoom)
        readerVersion.value += 1
    }
    public func toggleReaderAutoHide(): Unit {
        reader.setAutoHide(!reader.autoHide)
        readerVersion.value += 1
    }
    public func toggleReaderSeamlessNext(): Unit {
        reader.setSeamlessNext(!reader.seamlessNext)
        readerVersion.value += 1
    }
    public func toggleReaderAutoPlay(): Unit {
        reader.setAutoPlay(!reader.autoPlay)
        // 开关变化即重置计时起点：开 → 从现在起一个间隔后首翻；关 → 残留计时不得翻页。
        lastAutoPlayTurnMs = reader.clock()
        readerVersion.value += 1
    }
    // 间隔变更即生效：重置计时起点，下一次翻页按新间隔起算；镜像同步回 Slider。
    public func setReaderAutoPlayInterval(n: Int64): Unit {
        reader.setAutoPlayIntervalSec(n)
        autoPlayIntervalSlider.value = Float32(reader.autoPlayIntervalSec)
        lastAutoPlayTurnMs = reader.clock()
        readerVersion.value += 1
    }

    // ---- html 阅读排版（M4.3）：字号/页边距档位，持久化 + 立即重建 UA CSS ----

    public func setReaderHtmlFontSize(n: Int64): Unit {
        reader.setHtmlFontSize(n)
        applyHtmlThemeCss()
        readerVersion.value += 1
    }

    public func setReaderHtmlMargin(n: Int64): Unit {
        reader.setHtmlMargin(n)
        applyHtmlThemeCss()
        readerVersion.value += 1
    }

    // 深浅色与排版档位统一的 UA CSS 应用出口（init / 主题切换 / 档位变更共用）。
    private func applyHtmlThemeCss(): Unit {
        htmlPage.setDoublePage(reader.doublePage)
        htmlPage.setThemeCss(
            htmlThemeCss(isLight(), fontSize: reader.htmlFontSize, margin: reader.htmlMargin,
                doublePage: reader.doublePage))
    }

    // ---- lane ⇄ 播放同步 ----

    // UI 手动切 lane：只改变 dock 展开的控制组。frontend 的 lane 不是内容源选择器，
    // 因此这里不得加载、停止或替换当前 spread 的媒体。
    public func syncReaderLane(l: LaneId): Unit {
        reader.setActiveLane(l)
        readerVersion.value += 1
    }

    // ---- 无缝续读：下一档案解析与拼接 ----

    // 候选是否已解析到（结束页「打开下一档案」按钮使能判定）。
    public func hasNextCandidate(): Bool {
        readerNextId.size > 0
    }

    // 结束页「打开下一档案」：候选已解析时整档打开（openReader 会复位拼接状态）。
    public func openReaderNext(): Unit {
        if (readerNextId.size == 0) {
            return
        }
        openReader(readerNextId, 1)
    }

    // 进入末尾虚拟页触发（ReaderModel.onAppendNext 出口）：
    // 解析候选（档案在合集 → 合集内下一章；否则 relatedArchives 第一个未拼过的），
    // seamlessNext 开时继续取页表自动拼接，关时只展示候选。worker 线程跑，drain 回填。
    private func startAppendNext(arcid: String): Unit {
        if (appendInFlight || appendResolvedFrom == arcid) {
            return
        }
        let a = match (api) {
            case Some(x) => x
            case None =>
                // 离线（快照装置）：直接落失败态，结束页显示「没有下一档案」。
                reader.appendNextFailed("没有下一档案了")
                readerVersion.value += 1
                return
        }
        appendInFlight = true
        let appended = reader.appendedArcids
        let seamless = reader.seamlessNext
        let lang = language.value
        let _ = worker.submitTagged(
            "next.resolve",
            lang,
            {
                =>
                    var candidate: ?(String, String, Int64) = None
                    let tanks = a.listArchiveTankoubons(arcid, lang: lang)
                    if (tanks.size > 0) {
                        // 合集内按 tank_order 找当前档案的下一章（跳过已拼接的）。
                        let q = SearchQuery()
                        q.tankoubonId = tanks[0].id
                        q.sortby = "tank_order"
                        q.order = "asc"
                        q.pageSize = 256
                        q.lang = lang
                        let members = a.searchAll(q).items
                        var i: Int64 = 0
                        while (i < members.size) {
                            if (members[Int64(i)].arcid == arcid) {
                                var j = i + 1
                                while (j < members.size) {
                                    let m = members[Int64(j)]
                                    if (!appended.contains(m.arcid)) {
                                        candidate = Some((m.arcid, m.title, m.coverAssetId))
                                        break
                                    }
                                    j++
                                }
                                break
                            }
                            i++
                        }
                    }
                    if (candidate.isNone()) {
                        for (r in a.relatedArchives(arcid, 10, lang: lang)) {
                            if (!appended.contains(r.arcid)) {
                                candidate = Some((r.arcid, r.title, r.coverAssetId))
                                break
                            }
                        }
                    }
                    (arcid, seamless, candidate)
            }
        )
    }

    // spread 内容 → 播放联动：音视频统一走 libVLC，视频额外读取内存帧；
    // 无媒体的 spread 才停播。调用方只传 reader.spreadMediaLane()。
    private func syncPlaybackToLane(l: LaneId): Unit {
        match (l) {
            case Audio(i) => match (reader.pageAt(i)) {
                case Some(p) =>
                    let arc = reader.arcidOfReal(i)
                    let url = "${activeBaseUrl()}/api/archives/${arc}/page?path=${percentEncode(p.sourcePath)}"
                    let token = match (settings.activeProfile()) {
                        case Some(profile) => profile.token
                        case None => match (selectedProfile()) {
                            case Some(profile) => profile.token
                            case None => ""
                        }
                    }
                    let proxy = match (mediaProxy) {
                        case Some(existing) => existing
                        case None =>
                            let created = MediaProxy()
                            mediaProxy = Some(created)
                            created
                    }
                    playback.loadRemote(arc, i, proxy.open(url, token), "", video: false)
                    playback.loadLyrics(p.lyricsAssetId)
                    // 进入音频页自动播放：已加载且未在播放时启动
                    if (playback.loaded && !playback.playing) {
                        playback.play()
                    }
                case None => ()
            }
            case Book => playback.stop()
            case Html(_) => playback.stop() // html 页无媒体；Blitz 离屏渲染不在此驱动
            case Video(i) => match (reader.pageAt(i)) {
                case Some(p) =>
                    let arc = reader.arcidOfReal(i)
                    let path = p.sourcePath
                    let url = "${activeBaseUrl()}/api/archives/${arc}/page?path=${percentEncode(path)}"
                    let token = match (settings.activeProfile()) {
                        case Some(profile) => profile.token
                        case None => match (selectedProfile()) {
                            case Some(profile) => profile.token
                            case None => ""
                        }
                    }
                    let proxy = match (mediaProxy) {
                        case Some(existing) => existing
                        case None =>
                            let created = MediaProxy()
                            mediaProxy = Some(created)
                            created
                    }
                    playback.loadRemote(arc, i, proxy.open(url, token), "", stableCacheKey: "${arc}:${p.sourcePath}",
                        subtitleUrl: url, subtitleBearer: token)
                    playback.loadSubtitles(p.subtitleAttachments)
                    // 进入视频页自动播放：已加载且未在播放时启动
                    if (playback.loaded && !playback.playing) {
                        playback.play()
                    }
                case None => ()
            }
        }
    }

    public func close(): Unit {
        stopTaskStream()
        playback.stop()
        htmlPage.close()
        match (mediaProxy) {
            case Some(proxy) => proxy.close()
            case None => ()
        }
        match (api) {
            case Some(a) => a.close()
            case None => ()
        }
        match (offlineCache) {
            case Some(c) => c.close()
            case None => ()
        }
    }

    // 顶栏 ♥：切换当前档案收藏；元数据未到货（arcid 不匹配）时忽略，完成后由 dispatch 刷新 meta。
    public func toggleReaderFavorite(): Unit {
        match (meta.value) {
            case Some(m) =>
                if (m.arcid == readerArcid) {
                    toggleFavorite(readerArcid, !m.isfavorite)
                }
            case None => ()
        }
    }

    // 重取详情元数据（收藏/未读切换成功后由 dispatch 触发刷新）。
    public func refreshMeta(arcid: String): Unit {
        let a = api ?? return
        let lang = language.value
        let _ = worker.submitTagged("meta:${arcid}", lang, {=> a.metadata(arcid, lang: lang)})
    }

    // 元数据刷新/保存后把规范 SearchItem 投影写回共享对象：搜索/浏览行/书架/合集成员等
    // 视图按 rank 重读同一实体，标题、简介、标签等重叠字段不再各持一份拷贝。
    private func syncSearchItemFromMeta(meta: ArchiveMeta): Unit {
        if (meta.arcid.size == 0) {
            return
        }
        let synced = searchItemFromMeta(meta)
        // 空视图直接跳过：persisted 视图每次 itemAt 都是 UI 线程上的 RocksDB 点查，
        // 对 size==0 的视图整个扫描必然无产出。
        for (view in [items.value, relatedItems.value, tankMembers.value, shelfFavorites.value,
            shelfHistory.value, recentRead.value, recentFav.value]) {
            if (view.size == 0) {
                continue
            }
            for (i in 0..view.size) {
                match (view.itemAt(i)) {
                    case Some(it) =>
                        if (it.arcid == meta.arcid) {
                            copySearchProjection(it, synced)
                            let _ = view.persist(it)
                            break
                        }
                    case None => ()
                }
            }
        }
        for (row in browseRows.value) {
            if (row.items.size == 0) {
                continue
            }
            for (i in 0..row.items.size) {
                match (row.items.itemAt(i)) {
                    case Some(it) =>
                        if (it.arcid == meta.arcid) {
                            copySearchProjection(it, synced)
                            let _ = row.items.persist(it)
                            break
                        }
                    case None => ()
                }
            }
        }
    }

    private func refreshDetailLocalized(arcid: String): Unit {
        let a = api ?? return
        let lang = language.value
        refreshMeta(arcid)
        let _ = worker.submitTagged("ptanks:${arcid}", lang, {=> a.listArchiveTankoubons(arcid, lang: lang)})
        let _ = worker.submitTagged("related:${arcid}", lang, {
            => a.relatedArchives(arcid, 12, lang: lang)
        })
    }

    public func toggleFavorite(arcid: String, fav: Bool): Unit {
        let a = api ?? return
        let _ = worker.submit(
            "favorite:${arcid}",
            {
                =>
                    a.setFavorite(arcid, fav)
                    return fav
            }
        )
    }

    // 档案卡收藏：乐观翻转首页/搜索/合集成员中的同一档案并立即重绘；
    // 失败由 handleError 统一 toast（不回滚，下次行/网格数据到货自愈）。
    // persisted 视图按 rank 线性扫描是 UI 线程上的 RocksDB 点查，空视图先短路。
    public func toggleFavoriteOnCard(arcid: String): Unit {
        var target = false
        var found = false
        if (items.value.size > 0) {
            for (it in items.value) {
                if (it.arcid == arcid) {
                    if (!found) {
                        target = !it.isfavorite
                        found = true
                    }
                    it.isfavorite = target
                    let _ = items.value.persist(it)
                    break
                }
            }
        }
        for (row in browseRows.value) {
            if (row.items.size == 0) {
                continue
            }
            for (it in row.items) {
                if (it.arcid == arcid) {
                    if (!found) {
                        target = !it.isfavorite
                        found = true
                    }
                    it.isfavorite = target
                    let _ = row.items.persist(it)
                    break
                }
            }
        }
        if (tankMembers.value.size > 0) {
            for (it in tankMembers.value) {
                if (it.arcid == arcid) {
                    if (!found) {
                        target = !it.isfavorite
                        found = true
                    }
                    it.isfavorite = target
                    let _ = tankMembers.value.persist(it)
                    break
                }
            }
        }
        if (shelfFavorites.value.size > 0) {
            for (it in shelfFavorites.value) {
                if (it.arcid == arcid) {
                    if (!found) {
                        target = !it.isfavorite
                        found = true
                    }
                    it.isfavorite = target
                    let _ = shelfFavorites.value.persist(it)
                    break
                }
            }
        }
        if (shelfHistory.value.size > 0) {
            for (it in shelfHistory.value) {
                if (it.arcid == arcid) {
                    if (!found) {
                        target = !it.isfavorite
                        found = true
                    }
                    it.isfavorite = target
                    let _ = shelfHistory.value.persist(it)
                    break
                }
            }
        }
        if (!found) {
            return
        }
        items.value = items.value
        browseRows.value = browseRows.value
        tankMembers.value = tankMembers.value
        shelfFavorites.value = shelfFavorites.value
        shelfHistory.value = shelfHistory.value
        toggleFavorite(arcid, target)
    }

    // 合集卡收藏：endpoint 与 frontend FavoriteService 的 tankoubon 分支一致。
    public func toggleTankFavoriteOnCard(tankid: String): Unit {
        var target = false
        var found = false
        for (it in items.value) {
            if (it.itemType == "tankoubon" && it.tankoubonId == tankid) {
                if (!found) {
                    target = !it.isfavorite
                    found = true
                }
                it.isfavorite = target
                let _ = items.value.persist(it)
                break
            }
        }
        for (row in browseRows.value) {
            for (it in row.items) {
                if (it.itemType == "tankoubon" && it.tankoubonId == tankid) {
                    if (!found) {
                        target = !it.isfavorite
                        found = true
                    }
                    it.isfavorite = target
                    let _ = row.items.persist(it)
                    break
                }
            }
        }
        for (i in 0..parentTanks.value.size) {
            match (parentTanks.value.itemAt(i)) {
                case Some(it) =>
                    if (it.id == tankid) {
                        if (!found) {
                            target = !it.isfavorite
                            found = true
                        }
                        it.isfavorite = target
                        let _ = parentTanks.value.persist(it)
                        break
                    }
                case None => ()
            }
        }
        for (i in 0..tankRelated.value.size) {
            match (tankRelated.value.itemAt(i)) {
                case Some(it) =>
                    if (it.id == tankid) {
                        if (!found) {
                            target = !it.isfavorite
                            found = true
                        }
                        it.isfavorite = target
                        let _ = tankRelated.value.persist(it)
                        break
                    }
                case None => ()
            }
        }
        for (it in shelfFavorites.value) {
            if (it.itemType == "tankoubon" && it.tankoubonId == tankid) {
                if (!found) {
                    target = !it.isfavorite
                    found = true
                }
                it.isfavorite = target
                let _ = shelfFavorites.value.persist(it)
                break
            }
        }
        match (tank.value) {
            case Some(it) =>
                if (it.id == tankid) {
                    if (!found) {
                        target = !it.isfavorite
                        found = true
                    }
                    it.isfavorite = target
                    tank.value = Some(it)
                }
            case None => ()
        }
        if (!found) {
            return
        }
        items.value = items.value
        browseRows.value = browseRows.value
        parentTanks.value = parentTanks.value
        tankRelated.value = tankRelated.value
        shelfFavorites.value = shelfFavorites.value
        let a = api ?? return
        let nextFavorite = target
        let _ = worker.submit(
            "tank-favorite:${tankid}",
            {
                =>
                    a.setTankFavorite(tankid, nextFavorite)
                    return nextFavorite
            }
        )
    }

    public func toggleIsNew(arcid: String, isNew: Bool): Unit {
        let a = api ?? return
        let _ = worker.submit(
            "isnew:${arcid}",
            {
                =>
                    a.setIsNew(arcid, isNew)
                    return isNew
            }
        )
    }

    public func beginArchiveDownloadSelection(request: FileDialogRequest, arcid: String): Unit {
        pendingDownloadArcids = ArrayList<String>()
        pendingDownloadArcids.add(arcid)
        pendingDownloadBatch = false
        archiveDownloadDialog.value = Some(request)
    }

    public func beginBatchArchiveDownloadSelection(request: FileDialogRequest, arcids: ArrayList<String>): Unit {
        pendingDownloadArcids = ArrayList<String>()
        for (id in arcids) {
            pendingDownloadArcids.add(id)
        }
        pendingDownloadBatch = true
        archiveDownloadDialog.value = Some(request)
    }

    public func startSourceArchiveDownload(arcid: String): Unit {
        if (!isAdmin.value) {
            showError("source 下载需要管理员权限")
            return
        }
        let ns = sourceNamespace(arcid)
        let remoteId = sourceRemoteId(arcid)
        if (ns.size == 0 || remoteId.size == 0) {
            showError("无效的 source 档案 ID")
            return
        }
        let category = match (selectedUploadCategory()) {
            case Some(value) => value
            case None =>
                openUploadDrawer()
                uploadTabIndex.value = 1
                toaster.show("请先在下载抽屉选择入库分类，再重试 source 下载", kind: ToastKind.Info)
                return
        }
        let _ = worker.submit(
            "source-download:${arcid}",
            {
                =>
                    let a = api ?? throw Exception("尚未连接服务器")
                    a.downloadSourceArchive(ns, remoteId, category.id)
                    return arcid
            }
        )
    }

    private func pollArchiveDownloadDialog(): Unit {
        match (archiveDownloadDialog.value) {
            case Some(request) => match (request.result()) {
                case FileDialogResult.FileDialogPending => ()
                case FileDialogResult.FileDialogCanceled =>
                    archiveDownloadDialog.value = None<FileDialogRequest>
                    pendingDownloadArcids = ArrayList<String>()
                case FileDialogResult.FileDialogFailed(message) =>
                    archiveDownloadDialog.value = None<FileDialogRequest>
                    pendingDownloadArcids = ArrayList<String>()
                    showError(if (message.size > 0) {
                        "打开保存位置失败：${message}"
                    } else {
                        "打开保存位置失败"
                    })
                case FileDialogResult.FileDialogSelected(paths, _) =>
                    archiveDownloadDialog.value = None<FileDialogRequest>
                    if (paths.size == 0 || pendingDownloadArcids.size == 0) {
                        pendingDownloadArcids = ArrayList<String>()
                        return
                    }
                    let target = paths[0]
                    let ids = pendingDownloadArcids
                    let batch = pendingDownloadBatch
                    pendingDownloadArcids = ArrayList<String>()
                    let _ = worker.submitDownload(
                        if (batch) {
                            "archive-download:batch"
                        } else {
                            "archive-download:${ids[0]}"
                        },
                        {
                            =>
                                let a = api ?? throw Exception("尚未连接服务器")
                                var ok: Int64 = 0
                                for (id in ids) {
                                    try {
                                        if (batch) {
                                            let _ = a.downloadArchiveToFolder(id, target)
                                        } else {
                                            let _ = a.downloadArchiveToPath(id, target)
                                        }
                                        ok += 1
                                    } catch (_: Exception) {}
                                }
                                if (ok == 0) {
                                    throw Exception("下载失败")
                                }
                                return (ok, ids.size, target)
                        }
                    )
            }
            case None => ()
        }
    }

    public func batchSetIsNew(arcids: ArrayList<String>, isNew: Bool): Unit {
        let a = api ?? return
        let _ = worker.submit(
            "batch.isnew",
            {
                =>
                    var ok: Int64 = 0
                    for (id in arcids) {
                        try {
                            a.setIsNew(id, isNew);
                            ok += 1
                        } catch (_: Exception) {}
                    }
                    return (isNew, ok, arcids.size)
            }
        )
    }

    public func batchEditTankMembers(arcids: ArrayList<String>, addTagsRaw: String, removeTagsRaw: String,
        summaryAppend: String): Unit {
        let a = api ?? return
        let members = tankMembers.value
        let addTags = splitTags(addTagsRaw)
        let removeTags = splitTags(removeTagsRaw)
        let summary = summaryAppend.trimAscii()
        let _ = worker.submit(
            "batch.edit",
            {
                =>
                    var ok: Int64 = 0
                    for (id in arcids) {
                        for (item in members) {
                            if (item.arcid != id) {
                                continue
                            }
                            let tags = ArrayList<String>()
                            for (existing in splitTags(item.tagsCsv)) {
                                if (!removeTags.contains(existing)) {
                                    tags.add(existing)
                                }
                            }
                            for (added in addTags) {
                                if (!tags.contains(added)) {
                                    tags.add(added)
                                }
                            }
                            let desc = if (summary.size == 0) {
                                item.description
                            } else if (item.description.trimAscii().size == 0) {
                                summary
                            } else {
                                "${item.description}\n${summary}"
                            }
                            try {
                                a.updateArchiveMetadata(id,
                                    metadataRootBody(item.title, desc, String.join(tags.toArray(), delimiter: ","), ""))
                                ok += 1
                            } catch (_: Exception) {}
                        }
                    }
                    return (ok, arcids.size)
            }
        )
    }

    public func searchExactTag(displayTag: String): Unit {
        let display = displayTag.trimAscii()
        if (display.size == 0) {
            return
        }
        var canonical = display
        let translations = detailTagTranslations.value
        for (i in 0..translations.size) {
            match (translations.entryAt(i)) {
                case Some((raw, translated)) =>
                    let expected = match (raw.indexOf(":")) {
                        case Some(j) => "${raw[0..j]}:${translated}"
                        case None => translated
                    }
                    if (expected == display) {
                        canonical = raw
                        break
                    }
                case None => ()
            }
        }
        searchText.value = if (canonical.endsWith("$")) {
            canonical
        } else {
            "${canonical}$"
        }
        submitFilter()
        navigate(Page.Library)
    }

    public func trackRecommendation(scene: String, seedType: String, seedId: String, itemType: String, itemId: String,
        interaction: String): Unit {
        let a = api ?? return
        let task = "recommendation:${scene}:${interaction}:${itemType}:${itemId}"
        let _ = worker.submit(
            task,
            {
                =>
                    a.recordRecommendationInteraction(scene, seedType, seedId, itemType, itemId, interaction)
                    return itemId
            }
        )
    }

    public func openRecommendedArchive(scene: String, seedType: String, seedId: String, arcid: String): Unit {
        trackRecommendation(scene, seedType, seedId, "archive", arcid, "click")
        openDetail(arcid)
        recommendedArchiveOriginScene = scene
        recommendedArchiveOriginSeedType = seedType
        recommendedArchiveOriginSeedId = seedId
        recommendedArchiveOriginId = arcid
    }

    public func openRecommendedTank(scene: String, seedType: String, seedId: String, tankid: String): Unit {
        trackRecommendation(scene, seedType, seedId, "tankoubon", tankid, "click")
        openTank(tankid)
    }

    // ---- 多选操作 ----

    // 长按/右键首项进入选择模式并选中该项。
    public func enterSelection(id: String): Unit {
        selectionMode.value = true
        selectedIds.value.add(id)
        selectedIds.value = selectedIds.value
    }

    // 选择模式下点选：切换选中态（空选不自动退出，退出由 exitSelection 显式控制）。
    public func toggleSelected(id: String): Unit {
        if (selectedIds.value.contains(id)) {
            selectedIds.value.remove(id)
        } else {
            selectedIds.value.add(id)
        }
        selectedIds.value = selectedIds.value
    }

    public func clearSelection(): Unit {
        selectedIds.value.clear()
        selectedIds.value = selectedIds.value
    }

    public func exitSelection(): Unit {
        clearSelection()
        selectionMode.value = false
    }

    public func isSelected(id: String): Bool {
        selectedIds.value.contains(id)
    }

    public func selectedCount(): Int64 {
        selectedIds.value.size
    }

    // ---- 详情页/批量动作 ----

    // 删除档案：成功后 toast、若仍在该档案详情页则退回书库，并刷新列表（dispatch 处理）。
    public func deleteArchive(arcid: String): Unit {
        let a = api ?? return
        let _ = worker.submit(
            "deletearchive:${arcid}",
            {
                =>
                    a.deleteArchive(arcid)
                    return arcid
            }
        )
    }

    // 删除合集：成功后 toast、若仍在该合集详情页则退回书库，并刷新列表（dispatch 处理）。
    public func deleteCurrentTank(id: String): Unit {
        let a = api ?? return
        let _ = worker.submit(
            "deletetank:${id}",
            {
                =>
                    a.deleteTankoubon(id)
                    return id
            }
        )
    }

    // 合集详情页收藏切换：复用 setTankFavorite，乐观更新详情页数据的 isfavorite
    // （卡片场景见 toggleTankFavoriteOnCard；失败由 handleError 统一 toast）。
    public func setTankFavoriteOnDetail(id: String, fav: Bool): Unit {
        match (tank.value) {
            case Some(t) =>
                if (t.id == id) {
                    t.isfavorite = fav
                    tank.value = Some(t)
                }
            case None => ()
        }
        let a = api ?? return
        let _ = worker.submit(
            "tank-favorite:${id}",
            {
                =>
                    a.setTankFavorite(id, fav)
                    return fav
            }
        )
    }

    // 批量加入合集：逐个 addTankMember，单条失败不打断批量，
    // 完成后 toast 成功/总数并刷新合集详情成员列表与书库（dispatch 处理）。
    public func addArchivesToTank(tankId: String, arcids: ArrayList<String>): Unit {
        let a = api ?? return
        let _ = worker.submit(
            "tankadd:${tankId}",
            {
                =>
                    var ok: Int64 = 0
                    for (arcid in arcids) {
                        try {
                            a.addTankMember(tankId, arcid)
                            ok += 1
                        } catch (_: Exception) {
                            // 单条失败跳过，结果按 成功/总数 汇报
                        }
                    }
                    return (ok, arcids.size)
            }
        )
    }

    // 新建合集并批量加入：createTankoubon 后逐个 addTankMember。
    public func createTankAndAdd(name: String, arcids: ArrayList<String>): Unit {
        let a = api ?? return
        let _ = worker.submit(
            "tankcreate:${name}",
            {
                =>
                    let tankId = a.createTankoubon(name)
                    var ok: Int64 = 0
                    for (arcid in arcids) {
                        try {
                            a.addTankMember(tankId, arcid)
                            ok += 1
                        } catch (_: Exception) {
                            // 单条失败跳过，结果按 成功/总数 汇报
                        }
                    }
                    return (ok, arcids.size)
            }
        )
    }

    // 批量移出合集：逐个 removeTankMember，完成后刷新合集详情（dispatch 处理）。
    public func removeTankMembers(tankId: String, arcids: ArrayList<String>): Unit {
        let a = api ?? return
        let _ = worker.submit(
            "tankremove:${tankId}",
            {
                =>
                    var ok: Int64 = 0
                    for (arcid in arcids) {
                        try {
                            a.removeTankMember(tankId, arcid)
                            ok += 1
                        } catch (_: Exception) {
                            // 单条失败跳过，结果按 成功/总数 汇报
                        }
                    }
                    return (ok, arcids.size)
            }
        )
    }

    // 批量删除：档案与合集按 id 分两列传入（UI 层按 isTankItem 拆分 selectedIds），
    // 逐个删除；完成后 toast 成功/总数、刷新书库并退出选择模式（dispatch 处理）。
    public func batchDelete(arcids: ArrayList<String>, tankIds: ArrayList<String>): Unit {
        let a = api ?? return
        let _ = worker.submit(
            "batch.delete",
            {
                =>
                    var ok: Int64 = 0
                    for (arcid in arcids) {
                        try {
                            a.deleteArchive(arcid)
                            ok += 1
                        } catch (_: Exception) {
                        }
                    }
                    for (tankId in tankIds) {
                        try {
                            a.deleteTankoubon(tankId)
                            ok += 1
                        } catch (_: Exception) {
                        }
                    }
                    return (ok, arcids.size + tankIds.size)
            }
        )
    }

    // 批量收藏/取消收藏：档案走 setFavorite、合集走 setTankFavorite；完成后 toast + 刷新。
    public func batchFavorite(arcids: ArrayList<String>, tankIds: ArrayList<String>, fav: Bool): Unit {
        let a = api ?? return
        let _ = worker.submit(
            "batch.favorite",
            {
                =>
                    var ok: Int64 = 0
                    for (arcid in arcids) {
                        try {
                            a.setFavorite(arcid, fav)
                            ok += 1
                        } catch (_: Exception) {
                        }
                    }
                    for (tankId in tankIds) {
                        try {
                            a.setTankFavorite(tankId, fav)
                            ok += 1
                        } catch (_: Exception) {
                        }
                    }
                    return (fav, ok, arcids.size + tankIds.size)
            }
        )
    }

    // ---- 主题 ----

    // 构建期主题判定：视图构建时拿不到 ctx.theme（绘制期上下文），需要铺底/描边色时
    // 用本判定在 palette.cj 的明/暗常量间二选一（settings.theme 由 setTheme 即时更新并触发重绘）。
    public func isLight(): Bool {
        settings.theme == "light"
    }

    // 主题应用回调由 main.cj 注入：lanluThemeDark/Light 与 DesktopApp 都在 root 包，
    // app 包直接引用会成环，故以 (String) -> Unit 回调桥接（参数 "dark"|"light"）。
    public var themeChangeHandler: ?(String) -> Unit = None

    // ── 主题涟漪动画状态 ──
    // 点击切换主题时不立即应用，而是经 ThemeRipple 组件播放扩展圆动画，
    // 动画覆盖全窗口后再执行实际切换（网页 Material 涟漪式明暗切换）。
    public var themeRipplePending: Bool = false
    public var themeRippleTarget: String = ""
    // 触发点使用窗口逻辑坐标；负值表示没有指针来源（例如设置页分段切换），
    // ThemeRipple 会回落到窗口中心。
    public var themeRippleX: Float32 = -1.0
    public var themeRippleY: Float32 = -1.0
    public var themeToggleX: Float32 = -1.0
    public var themeToggleY: Float32 = -1.0

    // 切换主题：不再即切即生效，改为设置待处理标记，由 ThemeRipple 组件
    // 播放涟漪动画并在完成时回调 applyPendingTheme 落盘并应用新主题。
    public func setTheme(mode: String): Unit {
        setThemeAt(mode, -1.0, -1.0)
    }

    // 标题栏主题按钮把实际点击点传进来，使扩散圆与参考页一样从按钮处揭开。
    public func setThemeAt(mode: String, x: Float32, y: Float32): Unit {
        requestTheme(mode, x, y, -1.0, -1.0)
    }

    // 主题按钮同时提供实际点击点（涟漪圆心）与按钮中心（图标形变中心）。
    public func setThemeFromToggle(mode: String, x: Float32, y: Float32, toggleX: Float32, toggleY: Float32): Unit {
        requestTheme(mode, x, y, toggleX, toggleY)
    }

    private func requestTheme(mode: String, x: Float32, y: Float32, toggleX: Float32, toggleY: Float32): Unit {
        if (mode != "dark" && mode != "light") {
            return
        }
        // 动画期间拒绝第二次切换，避免待处理目标和正在绘制的目标互相覆盖。
        if (mode == settings.theme || themeRipplePending || themeRippleTarget.size > 0) {
            return
        }
        themeRippleTarget = mode
        themeRippleX = x
        themeRippleY = y
        themeToggleX = toggleX
        themeToggleY = toggleY
        themeRipplePending = true
    }

    // 涟漪动画完成后调用：更新内存设置、落盘、经注入回调应用到 DesktopApp。
    public func applyPendingTheme(): Unit {
        if (themeRippleTarget.size == 0) {
            return
        }
        settings.theme = themeRippleTarget
        persistSettings(settings)
        // html 阅读纸面同步新主题（活动会话立即重渲染，下一帧取新帧）。
        htmlPage.setThemeCss(
            htmlThemeCss(themeRippleTarget == "light", fontSize: reader.htmlFontSize, margin: reader.htmlMargin,
                doublePage: reader.doublePage))
        if (let Some(h) <- themeChangeHandler) {
            h(themeRippleTarget)
        }
        themeRippleTarget = ""
        themeRippleX = -1.0
        themeRippleY = -1.0
        themeToggleX = -1.0
        themeToggleY = -1.0
    }

    // 设置界面字体（需重启生效）。
    public func setFontPath(path: String): Unit {
        settings.fontPath = path
        persistSettings(settings)
        toaster.show(t("appearance.fontRestart"), kind: ToastKind.Info)
    }

    /** Translates one application message using the current effective language. */
    public func t(key: String, params!: Array<(String, String)> = []): String {
        localizer.text(language.value, key, params: params)
    }

    public func effectiveLanguageName(): String {
        t("language.name.${language.value}")
    }

    /** Applies and persists a display-language preference without restarting the application. */
    public func setLanguagePreference(preference: String): Unit {
        let normalized = normalizeLanguagePreference(preference)
        let next = resolveLanguage(normalized)
        if (settings.languagePreference == normalized && language.value == next) {
            return
        }
        settings.languagePreference = normalized
        language.value = next
        persistSettings(settings)
        autocompleteSuggestions.value = ArrayList<TagSuggestion>()
        autocompleteVisible.value = false
        autocompleteRequestId++
        for (row in browseRows.value) {
            if (row.key == "resume") {
                row.title = t("library.resume")
            } else if (row.key == "random") {
                row.title = t("library.random")
            }
        }
        browseRows.value = browseRows.value
        refreshLocalizedData()
        toaster.show(t("language.changed", params: [("language", effectiveLanguageName())]), kind: ToastKind.Success)
    }

    private func refreshLocalizedData(): Unit {
        match (page.value) {
            case Page.Library => refreshLibrary()
            case Page.Shelf => refreshShelf()
            case Page.Detail(arcid) => refreshDetailLocalized(arcid)
            case Page.Tank(tankid) => refreshTankDetail(tankid)
            case Page.Reader(arcid, _) => refreshMeta(arcid)
            case _ => ()
        }
    }

    // ---- 设置页 ----

    // 拉取服务器信息（结果经 dispatch 的 "info" 分支写入 serverInfo）。
    public func loadServerInfo(): Unit {
        let a = api ?? return
        let _ = worker.submit("info", {=> a.info()})
    }

    // 同步读磁盘缓存总量刷新展示（设置页进场与清理后调用）。
    public func refreshCacheInfo(): Unit {
        let bytes = cache().totalBytes()
        cacheInfo.value = t("cache.size", params: [("size", "${bytes / 1048576}")])
    }

    // 清图片缓存：磁盘目录 + cui 纹理缓存（路径纹理 + 像素纹理）+ imageStates 三处一起复位。
    // 注意命名：cui 有全局 clearImageCache()（路径纹理缓存），model 方法起名 clearCache 避免遮蔽歧义。
    public func clearCache(): Unit {
        cache().clear()
        subtitleCache().clear()
        clearImageCache() // cui 路径纹理缓存（按文件路径解码的 GPU 纹理）
        clearPixelImages() // cui 像素纹理缓存（含已建纹理与 staged 像素）
        synchronized(imageMutex) {
            imageStates.clear()
        }
        // 联动清理离线响应/进度缓存（当前服务器前缀；跨服务器互不影响）。
        match (offlineCache) {
            case Some(c) => c.clearServer(fnv1a64Hex(activeBaseUrl()))
            case None => ()
        }
        refreshCacheInfo()
        toaster.show(t("cache.cleared"), kind: ToastKind.Success)
    }

    // 封面圆角说明（asset: key 专用）：实现已移至 img 包 roundCoverAlphaNative，在解码
    // 工作线程内直接修改原生 RGBA 内存，不再经 UI dispatch 遍历像素（见 startImageTask）。

    // ---- 每帧泵：把工作线程结果写回 State（UI 线程）----

    /*
     * pump 自带的周期定时器（chrome 自动隐藏 / 自动翻页 / 进度防抖尾巴）中最近一个的
     * 剩余毫秒，供主循环注册定时帧请求（DesktopApp.requestFrameAfter）：循环空转等待时
     * 在最近到期时刻被唤醒，醒后那次迭代正常 pump 触发对应逻辑。时钟基准与 pump 内部
     * 一致（reader.clock），返回的是相对剩余量（已钳制 ≥0），与调用方时基无关。
     * 无活动定时器时返回 None，主循环可无限期等待（输入/worker 唤醒兜底）。
     */
    public func nextPumpTimerMs(): ?Int64 {
        var best: ?Int64 = None
        let onReaderPage = match (page.value) {
            case Page.Reader(_, _) => true
            case _ => false
        }
        if (onReaderPage) {
            if (reader.autoHide && reader.chromeVisible) {
                best = earliestTimer(best, reader.lastActivityMs + READER_CHROME_AUTOHIDE_MS - reader.clock())
            }
            if (reader.autoPlay && reader.pageCount > 0) {
                best = earliestTimer(best, lastAutoPlayTurnMs + reader.autoPlayIntervalSec * 1000 - reader.clock())
            }
            best = earliestTimer(best, reader.nextProgressFlushMs())
        }
        best
    }

    private func earliestTimer(current: ?Int64, candidate: ?Int64): ?Int64 {
        match (candidate) {
            case None => current
            case Some(ms) =>
                let clamped = max(Int64(0), ms)
                match (current) {
                    case Some(existing) => Some(min(existing, clamped))
                    case None => Some(clamped)
                }
        }
    }

    public func pump(): Unit {
        reader.tick() // 进度防抖周期驱动：窗口到点补发 pending 尾巴
        pollUploadFileDialog()
        pollArchiveDownloadDialog()
        maybeSweepCache() // 磁盘缓存周期 sweep 判定（#10，判定本身零 I/O）

        // chrome 自动隐藏计时（T13）：autoHide 开且 READER_CHROME_AUTOHIDE_MS 无活动则隐藏
        // 顶栏，仅在阅读页生效（离开阅读器后 reader 状态闲置，不应静默翻转）。
        match (page.value) {
            case Page.Reader(_, _) =>
                if (reader.autoHide && reader.chromeVisible && reader.clock() - reader.lastActivityMs >=
                    READER_CHROME_AUTOHIDE_MS) {
                    reader.toggleChrome()
                }
            case _ => ()
        }
        // 任务记录 SSE 生命周期：离开设置页即停（板块内进入/切筛选由视图侧负责）。
        match (page.value) {
            case Page.Settings => ()
            case _ => stopTaskStream()
        }
        // 自动播放驱动（对齐 frontend useReaderAutoPlay）：每 intervalSec 秒前进一个
        // spread；翻到末 spread 无法前进时自动停（到底自动停）并提示。计时基准
        // reader.clock（与进度防抖 tick 同惯例）；webtoon 本实现是分页的，同样步进。
        // 仅在阅读页生效（离开阅读器后 reader 状态闲置，与 chrome 自动隐藏同约束）。
        let onReaderPage = match (page.value) {
            case Page.Reader(_, _) => true
            case _ => false
        }
        if (onReaderPage && reader.autoPlay && reader.pageCount > 0) {
            if (reader.clock() - lastAutoPlayTurnMs >= reader.autoPlayIntervalSec * 1000) {
                let before = reader.index
                readerTurnPage(true)
                lastAutoPlayTurnMs = reader.clock()
                if (reader.index == before) {
                    reader.setAutoPlay(false)
                    readerVersion.value += 1
                    toaster.show("已自动翻页到末页", kind: ToastKind.Info)
                }
            }
        }
        // chrome 可见性镜像：超时隐藏/open 复位等非视图路径的变更经 readerVersion 广播。
        if (reader.chromeVisible != lastChromeSync) {
            lastChromeSync = reader.chromeVisible
            readerVersion.value += 1
        }
        // 媒体生命周期只跟当前 spread 走；点击 dock lane 不进入这条链。
        let spreadLane = reader.spreadMediaLane()
        if (!spreadLane.equals(lastLane)) {
            lastLane = spreadLane
            syncPlaybackToLane(lastLane)
            readerVersion.value += 1
        }
        // html 页生命周期同媒体：翻离/离开阅读器即关会话（framebuffer 归还）；
        // 进入 html 页 open 标称视口，舞台首帧经 ensureViewport 校正为真实物理像素。
        let htmlIdx: Int64 = if (onReaderPage) {
            match (reader.spreadHtmlPage()) {
                case Some(i) => i
                case None => -1
            }
        } else {
            -1
        }
        if (htmlIdx != lastHtmlPageIdx) {
            lastHtmlPageIdx = htmlIdx
            if (htmlIdx < 0) {
                htmlPage.close()
            } else {
                match (reader.pageAt(htmlIdx)) {
                    case Some(p) =>
                        let arc = reader.arcidOfReal(htmlIdx)
                        let path = if (p.sourcePath.size > 0) {
                            p.sourcePath
                        } else {
                            p.id
                        }
                        htmlPage.open(arc, path, 1280, 800, 1.0)
                    case None => ()
                }
            }
            readerVersion.value += 1
        }
        // 离线回退通知轮询：worker 置位后在此（UI 线程）toast。
        pollOfflineNotice()
        let pumpT0 = MonoTime.now()
        let results = worker.drain()
        for (r in results) {
            if (r.tag.size > 0 && r.tag != language.value) {
                if (r.name.startsWith("row:")) {
                    onRowTaskFinished()
                }
                continue
            }
            if (r.error.size > 0) {
                handleError(r);
                continue
            }
            let dispatchT0 = MonoTime.now()
            dispatch(r)
            // LANLU_PERF 打点：按结果名前缀分桶的 dispatch 成本（定位 pump p99 尖刺归属：
            // 图片类 img:/imgdl:、章节文件 files:、行/分类/会话/元数据各自独立桶，其余归 other）。
            if (SubtitlePerf.enabled()) {
                SubtitlePerf.sampleUs(pumpDispatchBucket(r.name), (MonoTime.now() - dispatchT0).toMicroseconds())
            }
        }
        // LANLU_PERF 打点：有结果时的 drain+dispatch UI 线程成本；并驱动 5s 滚动汇总。
        if (SubtitlePerf.enabled()) {
            if (results.size > 0) {
                SubtitlePerf.sampleUs("pump_dispatch_us", (MonoTime.now() - pumpT0).toMicroseconds())
            }
            perfFlushTick()
        }
    }

    // pump 分桶：img:/imgdl: 归图片，files: 归章节文件；other 再细分——静态分析表明
    // row:/categories 的 dispatch 只是字段/State 赋值（无观察者、无 I/O），me 多一次
    // leading 落盘（saveSettings 即时写契约），meta: 含 syncSearchItemFromMeta 的 UI 线程
    // RocksDB 点查；细分后实测可直接归因 pump_other 尖刺，剩余杂项仍归 pump_other_us。
    private func pumpDispatchBucket(name: String): String {
        if (name.startsWith("img:") || name.startsWith("imgdl:")) {
            return "pump_img_us"
        }
        if (name.startsWith("files:")) {
            return "pump_files_us"
        }
        if (name.startsWith("row:")) {
            return "pump_row_us"
        }
        if (name == "categories") {
            return "pump_categories_us"
        }
        if (name == "me") {
            return "pump_me_us"
        }
        if (name.startsWith("meta:")) {
            return "pump_meta_us"
        }
        "pump_other_us"
    }

    private func handleError(r: ApiResult): Unit {
        // 书架两路错误在页面内联呈现；普通网络失败不再叠一层 toast。
        if (r.name == "shelf:favorites" || r.name == "shelf:history") {
            if (r.name == "shelf:favorites") {
                shelfFavoritesLoading.value = false
                shelfFavoritesFailed.value = true
            } else {
                shelfHistoryLoading.value = false
                shelfHistoryFailed.value = true
            }
            if (r.error.contains("失效") || r.error.contains("401")) {
                logout()
                showError(r.error)
            }
            return
        }
        if (r.name.startsWith("upload:")) {
            let id = r.name.removePrefix("upload:")
            match (findUpload(id)) {
                case Some(item) =>
                    item.status = "error"
                    item.message = if (r.error.size > 0) {
                        r.error
                    } else {
                        "上传失败"
                    }
                    uploadFiles.value = uploadFiles.value
                case None => ()
            }
            if (r.error.contains("失效") || r.error.contains("401")) {
                logout()
            }
            showError(r.error)
            return
        }
        if (r.name.startsWith("download:")) {
            let id = r.name.removePrefix("download:")
            match (findDownload(id)) {
                case Some(item) =>
                    item.status = "error"
                    item.message = if (r.error.size > 0) {
                        r.error
                    } else {
                        "下载失败"
                    }
                    downloadTasks.value = downloadTasks.value
                case None => ()
            }
            if (r.error.contains("失效") || r.error.contains("401")) {
                logout()
            }
            showError(r.error)
            return
        }
        // 自动补全是辅助能力：普通网络失败静默收起，会话失效仍走全局登出。
        if (r.name.startsWith("autocomplete:")) {
            if (r.name == autocompleteTaskName) {
                autocompleteLoading.value = false
                autocompleteSuggestions.value = ArrayList<TagSuggestion>()
                autocompleteVisible.value = false
            }
            if (r.error.contains("失效") || r.error.contains("401")) {
                logout()
                showError(r.error)
            }
            return
        }
        // 图片下载阶段失败：置 error 态并补发队列（与 img: 解码失败同款处理）。
        // 下载阶段成功的中间结果在 dispatch 中静默忽略。
        if (r.name.startsWith("imgdl:")) {
            finishImageTask()
            // 不 toast 但留 stderr 痕迹：Windows 上批量封面失败类故障（如缺解码器）
            // 全靠这条日志定位（与 [boot]/[win] 诊断风格一致）。
            eprintln("[img] download failed ${r.name}: ${r.error}")
            imageState(r.name.removePrefix("imgdl:")).value = "error"
            return
        }
        // 图片任务失败不 toast，只置 error 态并补发队列。
        if (r.name.startsWith("img:")) {
            finishImageTask()
            eprintln("[img] decode failed ${r.name}: ${r.error}")
            imageState(r.name.removePrefix("img:")).value = "error"
            return
        }
        if (r.name == "sweep" || r.name == "progress") {
            return // 后台维护类任务失败不打扰用户
        }
        // backdrop 解码失败静默（不 toast，不阻塞页面），backdrop 区域回退为纯色渐变。
        if (r.name.startsWith("backdrop:")) {
            if (r.name.startsWith("backdrop:audio:")) {
                imageState(r.name).value = "error"
            }
            return
        }
        // 续读解析/拼接失败：结束页落「没有下一档案」态（不 toast，阅读器内联展示）。
        if (r.name == "next.resolve" || r.name.startsWith("next.files")) {
            appendInFlight = false
            reader.appendNextFailed("没有下一档案了")
            readerVersion.value += 1
            return
        }
        // html 取字节失败：阅读器内联错误态（可点击重试），不 toast；
        // 与图片管线同惯例，401 不做全局 logout。htmlres 须先于 html 匹配。
        if (r.name.startsWith("htmlres:")) {
            htmlPage.resourceFailed(r.name.removePrefix("htmlres:"), "")
            return
        }
        if (r.name.startsWith("html:")) {
            htmlPage.htmlFailed(r.name.removePrefix("html:"), r.error)
            readerVersion.value += 1
            return
        }
        // 媒体下载失败：回填 PlaybackModel error 态（阅读器内联展示），不 toast；
        // 401 不做全局 logout——阅读器内图片管线同样不因此踢出会话，保持一致。
        if (r.name.startsWith("playback:")) {
            playback.onFailed(r.name.removePrefix("playback:"), r.error)
            readerVersion.value += 1
            return
        }
        if (r.name.startsWith("lyrics:")) {
            return
        }
        if (r.name.startsWith("editsave:")) {
            metadataEditorSaving.value = false
            showError(r.error)
            return
        }
        if (r.name.startsWith("metadata-plugin:")) {
            metadataPluginRunning.value = false
            showError(r.error)
            return
        }
        if (r.name.startsWith("meta:")) {
            detailLoadState.value = "error"
            detailLoadError.value = r.error
            if (r.error.contains("失效") || r.error.contains("401")) {
                logout()
            }
            return
        }
        if (r.name.startsWith("tankmeta:")) {
            tankLoadState.value = "error"
            tankLoadError.value = r.error
            if (r.error.contains("失效") || r.error.contains("401")) {
                logout()
            }
            return
        }
        if (r.name.startsWith("dfiles:")) {
            detailPagesState.value = "error"
            detailPagesError.value = r.error
            if (r.error.contains("失效") || r.error.contains("401")) {
                logout()
            }
            return
        }
        if (r.name.startsWith("tankmembers:")) {
            tankMembersState.value = "error"
            tankMembersError.value = r.error
            if (r.error.contains("失效") || r.error.contains("401")) {
                logout()
            }
            return
        }
        if (r.name.startsWith("tagtranslations:")) {
            if (r.error.contains("失效") || r.error.contains("401")) {
                logout()
            }
            return
        }
        if (r.name.startsWith("recommendation:")) {
            return // 推荐反馈不影响主交互，失败静默并允许下次继续上报
        }
        if (r.name.startsWith("archive-download:")) {
            showError(r.error)
            return
        }
        if (r.name.startsWith("source-download:")) {
            showError(r.error)
            return
        }
        // 嵌套档案的辅助元数据加载失败不关闭编辑器：保留搜索条目提供的基础草稿，
        // 页侧栏显示为空即可，避免一次非关键请求失败中断整个编辑流程。
        if (r.name.startsWith("editmeta:") || r.name.startsWith("editfiles:")) {
            if (r.error.contains("失效") || r.error.contains("401")) {
                logout()
                showError(r.error)
            }
            return
        }
        // 浏览模式行任务失败：不 toast（9 行并发失败会刷屏），行内呈现可点击重试；
        // 401/会话失效仍走全局 logout + 提示。
        if (r.name.startsWith("row:")) {
            if (r.error.contains("失效") || r.error.contains("401")) {
                logout()
                showError(r.error)
                return
            }
            let key = r.name.removePrefix("row:")
            for (row in browseRows.value) {
                if (row.key == key) {
                    row.loading = false
                    row.failed = true
                }
            }
            browseRows.value = browseRows.value
            onRowTaskFinished() // 失败也算落盘：补发下一批分类行
            return
        }
        // 详情辅助卡片（页面预览/所属合集/相关推荐）失败静默：卡片无数据即隐藏；
        // 401/会话失效仍走全局 logout + 提示（同 row: 分支惯例）。
        if (r.name.startsWith("ptanks:") || r.name.startsWith("related:") || r.name.startsWith("tankrelated:")) {
            if (r.error.contains("失效") || r.error.contains("401")) {
                logout()
                showError(r.error)
            }
            return
        }
        if (r.name == "testconn") {
            testConnResult.value = r.error
            return
        }
        // 在线探测失败：只落 offline 状态，不 toast 不打扰。
        if (r.name.startsWith("probe:")) {
            probeState(r.name.removePrefix("probe:")).value = "offline"
            return
        }
        // 静默恢复会话失败（含 401）：清掉已存 token 停留登录页，不 toast 不打扰。
        if (r.name == "me") {
            match (selectedProfile()) {
                case Some(p) => p.token = ""
                case None => ()
            }
            match (settings.activeProfile()) {
                case Some(p) => p.token = ""
                case None => ()
            }
            persistSettings(settings)
            return
        }
        // TOTP 验证失败（401=验证码错误）：不 logout（本就未登录），内联错误条展示。
        if (r.name == "login-totp") {
            loading.value = false
            loginError.value = r.error
            return
        }
        // 登录失败（凭据错误/无法连接等）：内联错误条展示，不 toast。
        if (r.name == "login") {
            loading.value = false
            loginError.value = r.error
            return
        }
        if (r.name == "login") {
            loading.value = false
        }
        if (r.name == "search") {
            loading.value = false
        }
        // 登录任务的 401 是“用户名或密码错误”而非会话失效，不做 logout（本就未登录）。
        if (r.name != "login" && (r.error.contains("失效") || r.error.contains("401"))) {
            logout()
        }
        showError(r.error)
    }

    private func dispatch(r: ApiResult): Unit {
        let name = r.name
        if (name == "upload.progress") {
            match (r.payload) {
                case Some(payload) =>
                    let (id, stage, progress, message) = (payload as (String, String, Int64, String)).getOrThrow()
                    match (findUpload(id)) {
                        case Some(item) =>
                            item.status = stage
                            item.progress = if (stage == "queued") {
                                0
                            } else {
                                max(item.progress, progress)
                            }
                            if (message.size > 0) {
                                item.message = message
                            }
                            uploadFiles.value = uploadFiles.value
                        case None => ()
                    }
                case None => ()
            }
        } else if (name.startsWith("upload:")) {
            match (r.payload) {
                case Some(payload) =>
                    let (id, result) = (payload as (String, ArchiveUploadResult)).getOrThrow()
                    match (findUpload(id)) {
                        case Some(item) =>
                            if (result.success) {
                                item.status = "success"
                                item.progress = 100
                                item.message = "上传完成"
                                hasCompletedUploads = true
                            } else if (result.fileExists) {
                                item.status = "fileExists"
                                item.message = if (result.error.size > 0) {
                                    result.error
                                } else {
                                    "文件已存在"
                                }
                            } else {
                                item.status = "error"
                                item.message = if (result.error.size > 0) {
                                    result.error
                                } else {
                                    "上传失败"
                                }
                            }
                            uploadFiles.value = uploadFiles.value
                        case None => ()
                    }
                case None => ()
            }
        } else if (name == "download.progress") {
            match (r.payload) {
                case Some(payload) =>
                    let (id, stage, progress, message) = (payload as (String, String, Int64, String)).getOrThrow()
                    match (findDownload(id)) {
                        case Some(item) =>
                            item.status = stage
                            item.progress = if (stage == "queued") {
                                0
                            } else {
                                max(item.progress, progress)
                            }
                            if (message.size > 0) {
                                item.message = message
                            }
                            downloadTasks.value = downloadTasks.value
                        case None => ()
                    }
                case None => ()
            }
        } else if (name.startsWith("download:")) {
            match (r.payload) {
                case Some(payload) =>
                    let (id, result) = (payload as (String, ArchiveUploadResult)).getOrThrow()
                    match (findDownload(id)) {
                        case Some(item) =>
                            if (result.success) {
                                item.status = "success"
                                item.progress = 100
                                item.message = "下载完成，已入库"
                                hasCompletedDownloads = true
                            } else {
                                item.status = "error"
                                item.message = if (result.error.size > 0) {
                                    result.error
                                } else {
                                    "下载失败"
                                }
                            }
                            downloadTasks.value = downloadTasks.value
                        case None => ()
                    }
                case None => ()
            }
        } else if (name == "login" || name == "login-totp") {
            loading.value = false
            match (r.payload) {
                case Some(p) =>
                    let (a, d, sid, cid) = (p as (LanluApi, LoginData, String, String)).getOrThrow()
                    if (cid.size > 0) {
                        // 202 挑战：切 TOTP 表单，等待 verifyTotp 提交。
                        // a 不转交（verifyTotp 另建实例），不 close 会泄漏一个连接池（#31）。
                        a.close()
                        totpChallengeId.value = cid
                    } else {
                        totpChallengeId.value = ""
                        pendingLoginUsername = ""
                        api = a
                        match (settings.profileById(sid)) {
                            case Some(prof) =>
                                prof.token = d.token
                                prof.username = d.username
                                prof.lastUsedAt = nowLabel()
                                settings.activeServerId = sid
                            case None => ()
                        }
                        persistSettings(settings)
                        // 换服登录必须复位图片缓存：缓存目录按 serverUrl 派生，而 imageStates
                        // 的 key（asset:42 等）与服务器无关，不复位会把旧服务器的图误判为
                        // “已加载”，新下载也会落进旧目录；CUI 的路径/像素纹理（含 staged）
                        // 也按同一 key 键控，必须一并释放，否则同 asset id 显示上一台服务器
                        // 的旧图（顺序：先路径纹理、后像素纹理（纹理→staged），见 clearCache）。
                        imageCache = None
                        clearImageCache()
                        clearPixelImages()
                        synchronized(imageMutex) {
                            imageStates.clear()
                        }
                        isAdmin.value = d.isAdmin
                        navigate(Page.Library)
                        loadCategories()
                        loadBrowseRows()
                        // 登录成功：服务端已恢复，补报该服务器的离线阅读进度。
                        match (settings.profileById(sid)) {
                            case Some(prof) => flushOfflineProgress(prof)
                            case None => ()
                        }
                    }
                case None => ()
            }
        } else if (name == "testconn") {
            testConnResult.value = "ok"
        } else if (name.startsWith("probe:")) {
            // 探测成功：任务载荷即服务器 id（见 probeServers）。
            match (r.payload) {
                case Some(p) =>
                    let pid = (p as String).getOrThrow()
                    probeState(pid).value = "online"
                    // 服务端已恢复：补报该服务器的离线阅读进度。
                    match (settings.profileById(pid)) {
                        case Some(prof) => flushOfflineProgress(prof)
                        case None => ()
                    }
                case None => ()
            }
        } else if (name == "me") {
            // 静默恢复成功同样视为一次使用：刷新 lastUsedAt 并置 active，
            // 否则"最后使用的服务器"与实际不符（按服务器各存会话语义）。
            match (selectedProfile()) {
                case Some(prof) =>
                    prof.lastUsedAt = nowLabel()
                    settings.activeServerId = prof.id
                    persistSettings(settings)
                case None => ()
            }
            // me() 返回同 LoginData 结构：同步管理员标记（控制设置页「服务器」分组显隐）。
            match (r.payload) {
                case Some(p) => isAdmin.value = (p as LoginData).getOrThrow().isAdmin
                case None => ()
            }
            navigate(Page.Library)
            loadCategories()
            loadBrowseRows()
            // LANLU_PERF 打点：会话恢复端到端（tryResumeSession→me 到货）。
            if (SubtitlePerf.enabled()) {
                SubtitlePerf.spanEnd("session_resume")
                SubtitlePerf.emit("session_resume_ms", SubtitlePerf.getGauge("session_resume"), "ms")
                // 首批浏览行抓取区间起点（与 session_resume 首尾相接，终点在首个 row: dispatch）。
                SubtitlePerf.spanStart("rows_fetch")
            }
        } else if (name.startsWith("autocomplete:")) {
            match (r.payload) {
                case Some(p) =>
                    let (requestId, queryText, suggestions) = (p as (Int64, String, ArrayList<TagSuggestion>))
                        .getOrThrow()
                    if (requestId == autocompleteRequestId) {
                        autocompleteQuery.value = queryText
                        autocompleteSuggestions.value = suggestions
                        autocompleteLoading.value = false
                        autocompleteVisible.value = suggestions.size > 0
                    }
                case None => ()
            }
        } else if (name == "search") {
            loading.value = false
            match (r.payload) {
                case Some(p) =>
                    let sp = (p as SearchPage).getOrThrow()
                    items.value = sp.items
                    recordsTotal.value = sp.recordsTotal
                    currentPage.value = sp.page
                case None => ()
            }
        } else if (name == "shelf:favorites") {
            shelfFavoritesLoading.value = false
            match (r.payload) {
                case Some(p) =>
                    shelfFavorites.value = (p as SearchPage).getOrThrow().items
                    shelfFavoritesLoaded = true
                    shelfFavoritesFailed.value = false
                case None => ()
            }
        } else if (name == "shelf:history") {
            shelfHistoryLoading.value = false
            match (r.payload) {
                case Some(p) =>
                    shelfHistory.value = (p as SearchPage).getOrThrow().items
                    shelfHistoryLoaded = true
                    shelfHistoryFailed.value = false
                case None => ()
            }
        } else if (name == "set.overview") {
            match (r.payload) {
                case Some(p) =>
                    let (stats, trend, read, fav) = (p as (UserStats, ArrayList<TrendPoint>, SearchItemView,
                        SearchItemView)).getOrThrow()
                    userStats.value = stats
                    userTrend.value = trend
                    recentRead.value = read
                    recentFav.value = fav
                case None => ()
            }
        } else if (name == "set.cloud") {
            match (r.payload) {
                case Some(p) => tagCloud.value = (p as ArrayList<CloudTag>).getOrThrow()
                case None => ()
            }
        } else if (name == "set.users") {
            match (r.payload) {
                case Some(p) => adminUsers.value = (p as ArrayList<AdminUserItem>).getOrThrow()
                case None => ()
            }
        } else if (name == "set.sys") {
            match (r.payload) {
                case Some(p) => sysSettings.value = (p as ArrayList<SysSetting>).getOrThrow()
                case None => ()
            }
        } else if (name == "set.cats") {
            match (r.payload) {
                case Some(p) => adminCategories.value = (p as ArrayList<AdminCategoryItem>).getOrThrow()
                case None => ()
            }
        } else if (name.startsWith("set.tags")) {
            match (r.payload) {
                case Some(p) => tagPage.value = (p as TagListPage).getOrThrow()
                case None => ()
            }
        } else if (name == "set.tagns") {
            match (r.payload) {
                case Some(p) => tagNs.value = (p as ArrayList<String>).getOrThrow()
                case None => ()
            }
        } else if (name == "set.filters") {
            match (r.payload) {
                case Some(p) => smartFilters.value = (p as ArrayList<SmartFilterItem>).getOrThrow()
                case None => ()
            }
        } else if (name.startsWith("set.tasks.stream:")) {
            // 流式整页推送：仅当结果筛选与当前订阅一致才应用
            //（旧流尾帧/切板块后的残留一律丢弃）。
            let st = name.removePrefix("set.tasks.stream:")
            match (r.payload) {
                case Some(p) =>
                    if (st == taskStreamStatus) {
                        taskPage.value = (p as TaskListPage).getOrThrow()
                    }
                case None => ()
            }
        } else if (name == "set.cron") {
            match (r.payload) {
                case Some(p) =>
                    let (st, tasks) = (p as (CronStatus, ArrayList<CronTask>)).getOrThrow()
                    cronStatus.value = st
                    cronTasks.value = tasks
                case None => ()
            }
        } else if (name == "set.plugins") {
            match (r.payload) {
                case Some(p) => plugins.value = (p as ArrayList<PluginItem>).getOrThrow()
                case None => ()
            }
        } else if (name == "set.security") {
            match (r.payload) {
                case Some(p) =>
                    let (se, tk, pk, tp) = (p as (ArrayList<SessionItem>, ArrayList<TokenItem>, ArrayList<PasskeyItem>, 
                        TotpStatus)).getOrThrow()
                    sessions.value = se
                    apiTokens.value = tk
                    passkeys.value = pk
                    totpStatus.value = tp
                case None => ()
            }
        } else if (name.startsWith("act.")) {
            // 动作成功：payload 是 toast 文案；按任务名 reload 对应板块。
            match (r.payload) {
                case Some(p) => toaster.show((p as String).getOrThrow(), kind: ToastKind.Success)
                case None => ()
            }
            if (name.startsWith("act.user")) {
                loadAdminUsers()
            } else if (name.startsWith("act.sys")) {
                loadSysSettings()
            } else if (name.startsWith("act.cat")) {
                loadAdminCategories()
            }
                // act.tag 只 toast，不在此 reload（避免清空筛选条件），由视图侧确认回调触发按当前筛选重拉。
                else if (name.startsWith("act.filter")) {
                loadSmartFilters()
            } else if (name.startsWith("act.cron")) {
                loadCron()
            } else if (name.startsWith("act.plugin")) {
                loadPlugins()
            } else if (name.startsWith("act.cred") || name.startsWith("act.totp") || name.startsWith("act.session") ||
                name.startsWith("act.token") || name.startsWith("act.passkey")) {
                // 改名成功：同步本地会话用户名并落盘，避免顶栏/会话仍是旧名。
                if (name == "act.cred" && pendingCredUsername.size > 0) {
                    settings.username = pendingCredUsername
                    match (settings.activeProfile()) {
                        case Some(p) => p.username = pendingCredUsername
                        case None => ()
                    }
                    persistSettings(settings)
                    pendingCredUsername = ""
                }
                loadAuthSecurity()
            }
        } else if (name == "categories") {
            match (r.payload) {
                case Some(p) =>
                    categories.value = (p as ArrayList<CategoryItem>).getOrThrow()
                    // 分类到达后补齐浏览模式分类行（随机行已先行，已加载行原样保留）。
                    loadBrowseRows()
                case None => ()
            }
        } else if (name.startsWith("row:")) {
            // 浏览模式行到货：对号入座写回（行内字段可变，整体重赋值推进代次触发重绘）。
            let key = name.removePrefix("row:")
            for (row in browseRows.value) {
                if (row.key == key) {
                    match (r.payload) {
                        case Some(p) => row.items = (p as SearchPage).getOrThrow().items
                        case None => ()
                    }
                    row.loading = false
                    row.failed = false
                }
            }
            browseRows.value = browseRows.value
            onRowTaskFinished() // 本批落盘：补发下一批分类行
            // LANLU_PERF 打点：首批浏览行到货（首屏内容可用的近似点，只报一次）。
            if (SubtitlePerf.enabled() && !firstRowsEmitted) {
                firstRowsEmitted = true
                SubtitlePerf.spanEnd("first_rows")
                SubtitlePerf.emit("first_rows_ms", SubtitlePerf.getGauge("first_rows"), "ms")
                // 首批浏览行抓取区间终点（起点在 me dispatch 的 loadBrowseRows 之后）。
                SubtitlePerf.spanEnd("rows_fetch")
                SubtitlePerf.emit("rows_fetch_ms", SubtitlePerf.getGauge("rows_fetch"), "ms")
            }
        } else if (name.startsWith("meta:")) {
            match (r.payload) {
                case Some(p) =>
                    // 迟到结果对号入座：详情页已从 A 切到 B 时，A 的元数据不得覆盖 B 的页面。
                    // arcid 取任务名（一定等于请求目标），不依赖响应体回传字段。
                    let arcid = name.removePrefix("meta:")
                    match (page.value) {
                        case Page.Detail(cur) =>
                            if (arcid == cur) {
                                let m = (p as ArchiveMeta).getOrThrow()
                                meta.value = Some(m)
                                detailLoadState.value = "ready"
                                detailLoadError.value = ""
                                // 把规范字段投影写回共享 SearchItem 视图，避免两份字段漂移。
                                syncSearchItemFromMeta(m)
                                // 优先真实 backdrop，缺省才退回封面模糊背景。
                                let backdropAsset = if (m.backdropAssetId > 0) {
                                    m.backdropAssetId
                                } else {
                                    m.coverAssetId
                                }
                                if (backdropAsset > 0) {
                                    requestBackdrop(arcid, backdropAsset)
                                }
                            }
                        // 阅读器顶栏只要标题/收藏态，不请求 backdrop；
                        // 顺手回填 segment 标题（结束页卡片「已读完《X》」用）。
                        case Page.Reader(cur, _) =>
                            if (arcid == cur) {
                                let m = (p as ArchiveMeta).getOrThrow()
                                meta.value = Some(m)
                                syncSearchItemFromMeta(m)
                                reader.setSegmentTitle(arcid, m.title)
                            }
                        case _ => ()
                    }
                case None => ()
            }
        } else if (name.startsWith("editmeta:")) {
            match (r.payload) {
                case Some(p) =>
                    let arcid = name.removePrefix("editmeta:")
                    if (metadataEditorOpen.value && arcid == metadataEditorArchiveId) {
                        let m = (p as ArchiveMeta).getOrThrow()
                        metadataEditorArchiveMeta.value = Some(m)
                        loadArchiveEditorDraft()
                    }
                case None => ()
            }
        } else if (name.startsWith("editfiles:")) {
            match (r.payload) {
                case Some(p) =>
                    let arcid = name.removePrefix("editfiles:")
                    if (metadataEditorOpen.value && arcid == metadataEditorArchiveId) {
                        metadataEditorPages.value = (p as ArchivePageView).getOrThrow()
                    }
                case None => ()
            }
        } else if (name.startsWith("editsave:")) {
            metadataEditorSaving.value = false
            metadataEditorDirty.value = false
            metadataEditorOpen.value = false
            toaster.show("元数据已保存", kind: ToastKind.Success)
            // 页级编辑成功后只更新单页主记录并让热点窗口失效，不重新整本拉取页表。
            if (name.startsWith("editsave:page:")) {
                let remainder = name.removePrefix("editsave:page:")
                let sep = remainder.lastIndexOf(":")
                if (let Some(i) <- sep) {
                    let arcid = remainder[0..i]
                    let rank = try {
                        Int64.parse(remainder[i + 1..remainder.size])
                    } catch (_: Exception) {
                        -1
                    }
                    if (rank >= 0 && detailPages.value.arcid == arcid) {
                        match (detailPages.value.itemAt(rank)) {
                            case Some(edited) =>
                                let view = detailPages.value
                                view.invalidateRank(rank)
                                match (offlineCacheFor()) {
                                    case Some(c) =>
                                        match (settings.activeProfile()) {
                                            case Some(p) =>
                                                let _ = c.updatePage(fnv1a64Hex(p.baseUrl),
                                                    offlineAccountScope(p.id, p.username, p.token), arcid, rank,
                                                    edited)
                                            case None => ()
                                        }
                                    case None => ()
                                }
                            case None => ()
                        }
                    }
                }
            }
            match (page.value) {
                case Page.Detail(arcid) =>
                    refreshMeta(arcid)
                    let a = api ?? return
                    let _ = worker.submit("dfiles:${arcid}", {=> a.files(arcid)})
                case Page.Tank(tankid) => openTank(tankid)
                case _ => ()
            }
        } else if (name.startsWith("metadata-plugin:")) {
            metadataPluginRunning.value = false
            metadataPluginPreview.value = true
            toaster.show("元数据插件任务已创建，将在服务端写回", kind: ToastKind.Success)
        } else if (name.startsWith("dfiles:")) {
            match (r.payload) {
                case Some(p) =>
                    // 迟到结果对号入座（同 meta: 分支）：仅当前详情页匹配时才写页面预览页表。
                    let arcid = name.removePrefix("dfiles:")
                    match (page.value) {
                        case Page.Detail(cur) =>
                            if (arcid == cur) {
                                detailPages.value = (p as ArchivePageView).getOrThrow()
                                detailPagesState.value = "ready"
                                detailPagesError.value = ""
                            }
                        case _ => ()
                    }
                case None => ()
            }
        } else if (name.startsWith("ptanks:")) {
            match (r.payload) {
                case Some(p) =>
                    let arcid = name.removePrefix("ptanks:")
                    match (page.value) {
                        case Page.Detail(cur) =>
                            if (arcid == cur) {
                                parentTanks.value = (p as TankoubonView).getOrThrow()
                            }
                        case _ => ()
                    }
                case None => ()
            }
        } else if (name.startsWith("related:")) {
            match (r.payload) {
                case Some(p) =>
                    let arcid = name.removePrefix("related:")
                    match (page.value) {
                        case Page.Detail(cur) =>
                            if (arcid == cur) {
                                relatedItems.value = (p as SearchItemView).getOrThrow()
                            }
                        case _ => ()
                    }
                case None => ()
            }
        } else if (name.startsWith("tagtranslations:")) {
            match (r.payload) {
                case Some(p) => detailTagTranslations.value = (p as TagTranslationView).getOrThrow()
                case None => ()
            }
        } else if (name.startsWith("tankmeta:")) {
            match (r.payload) {
                case Some(p) =>
                    let tankid = name.removePrefix("tankmeta:")
                    match (page.value) {
                        case Page.Tank(cur) =>
                            if (tankid == cur) {
                                let t = (p as TankoubonInfo).getOrThrow()
                                tank.value = Some(t)
                                tankLoadState.value = "ready"
                                tankLoadError.value = ""
                                let backdropAsset = if (t.backdropAssetId > 0) {
                                    t.backdropAssetId
                                } else {
                                    t.coverAssetId
                                }
                                if (backdropAsset > 0) {
                                    requestBackdrop("tank:${tankid}", backdropAsset)
                                }
                            }
                        case _ => ()
                    }
                case None => ()
            }
        } else if (name.startsWith("tankmembers:")) {
            match (r.payload) {
                case Some(p) =>
                    let tankid = name.removePrefix("tankmembers:")
                    match (page.value) {
                        case Page.Tank(cur) =>
                            if (tankid == cur) {
                                tankMembers.value = (p as SearchPage).getOrThrow().items
                                tankMembersState.value = "ready"
                                tankMembersError.value = ""
                            }
                        case _ => ()
                    }
                case None => ()
            }
        } else if (name.startsWith("tankrelated:")) {
            match (r.payload) {
                case Some(p) =>
                    let tankid = name.removePrefix("tankrelated:")
                    match (page.value) {
                        case Page.Tank(cur) =>
                            if (tankid == cur) {
                                tankRelated.value = (p as TankoubonView).getOrThrow()
                            }
                        case _ => ()
                    }
                case None => ()
            }
        } else if (name.startsWith("files:")) {
            match (r.payload) {
                case Some(p) =>
                    // 迟到结果对号入座：files:A 晚于 files:B 到达时不得覆盖 B 的页表，
                    // 否则 readerArcid 是 B 而 pages 是 A 的，阅读器每页 404。
                    let arcid = name.removePrefix("files:")
                    match (page.value) {
                        case Page.Reader(cur, _) =>
                            if (arcid == cur) {
                                let view = (p as ArchivePageView).getOrThrow()
                                pages.value = view
                                // 起始页来自可能过期的 progress；页表到货钳制+spread 吸附
                                // 在 ReaderModel 内完成，readerIndex 同步回 1 基。
                                reader.setPages(view)
                                readerIndex.value = reader.displayPage
                                readerPageSlider.value = Float32(reader.displayPage)
                            }
                        case _ => ()
                    }
                case None => ()
            }
        } else if (name.startsWith("deletearchive:")) {
            // 删除档案成功：toast、仍在该详情页则退回书库、刷新列表。
            toaster.show("档案已删除", kind: ToastKind.Success)
            let arcid = name.removePrefix("deletearchive:")
            match (page.value) {
                case Page.Detail(cur) =>
                    if (arcid == cur) {
                        navigate(Page.Library)
                    }
                case _ => ()
            }
            refreshLibrary()
        } else if (name.startsWith("deletetank:")) {
            // 删除合集成功：toast、仍在该合集详情页则退回书库、刷新列表。
            toaster.show("合集已删除", kind: ToastKind.Success)
            let tankid = name.removePrefix("deletetank:")
            match (page.value) {
                case Page.Tank(cur) =>
                    if (tankid == cur) {
                        navigate(Page.Library)
                    }
                case _ => ()
            }
            refreshLibrary()
        } else if (name.startsWith("tankadd:")) {
            // 批量加入合集完成：toast 成功/总数，刷新合集详情成员列表与书库。
            match (r.payload) {
                case Some(p) =>
                    let (ok, total) = (p as (Int64, Int64)).getOrThrow()
                    let kind = if (ok == total) {
                        ToastKind.Success
                    } else if (ok == 0) {
                        ToastKind.Error
                    } else {
                        ToastKind.Warning
                    }
                    toaster.show("已加入合集 ${ok}/${total}", kind: kind)
                case None => ()
            }
            let tankid = name.removePrefix("tankadd:")
            match (page.value) {
                case Page.Tank(cur) =>
                    if (tankid == cur) {
                        refreshTankDetail(tankid)
                    }
                case _ => ()
            }
            refreshLibrary()
        } else if (name.startsWith("tankremove:")) {
            // 批量移出合集完成：toast 成功/总数，刷新合集详情成员列表。
            match (r.payload) {
                case Some(p) =>
                    let (ok, total) = (p as (Int64, Int64)).getOrThrow()
                    toaster.show("已移出合集 ${ok}/${total}", kind: ToastKind.Success)
                case None => ()
            }
            let tankid = name.removePrefix("tankremove:")
            match (page.value) {
                case Page.Tank(cur) =>
                    if (tankid == cur) {
                        refreshTankDetail(tankid)
                    }
                case _ => ()
            }
        } else if (name.startsWith("tankcreate:")) {
            // 新建合集并加入完成：toast 成功/总数，刷新书库（新合集卡片入场）。
            match (r.payload) {
                case Some(p) =>
                    let (ok, total) = (p as (Int64, Int64)).getOrThrow()
                    let kind = if (ok == total) {
                        ToastKind.Success
                    } else {
                        ToastKind.Warning
                    }
                    toaster.show("合集已创建（加入 ${ok}/${total}）", kind: kind)
                case None => ()
            }
            refreshLibrary()
        } else if (name == "batch.delete") {
            // 批量删除完成：toast 成功/总数、刷新书库并退出选择模式。
            match (r.payload) {
                case Some(p) =>
                    let (ok, total) = (p as (Int64, Int64)).getOrThrow()
                    toaster.show("已删除 ${ok}/${total}", kind: ToastKind.Success)
                case None => ()
            }
            refreshLibrary()
            exitSelection()
        } else if (name == "batch.favorite") {
            // 批量收藏完成：toast 成功/总数并刷新书库（保留选择模式，便于连续操作）。
            match (r.payload) {
                case Some(p) =>
                    let (fav, ok, total) = (p as (Bool, Int64, Int64)).getOrThrow()
                    let verb = if (fav) {
                        "已收藏"
                    } else {
                        "已取消收藏"
                    }
                    toaster.show("${verb} ${ok}/${total}", kind: ToastKind.Success)
                case None => ()
            }
            refreshLibrary()
        } else if (name == "batch.isnew") {
            match (r.payload) {
                case Some(p) =>
                    let (isNew, ok, total) = (p as (Bool, Int64, Int64)).getOrThrow()
                    toaster.show(if (isNew) {
                        "已标为未读 ${ok}/${total}"
                    } else {
                        "已标为已读 ${ok}/${total}"
                    }, kind: ToastKind.Success)
                case None => ()
            }
            match (page.value) {
                case Page.Tank(id) => refreshTankDetail(id)
                case _ => refreshLibrary()
            }
        } else if (name == "batch.edit") {
            match (r.payload) {
                case Some(p) =>
                    let (ok, total) = (p as (Int64, Int64)).getOrThrow()
                    toaster.show("已更新元数据 ${ok}/${total}", kind: ToastKind.Success)
                case None => ()
            }
            match (page.value) {
                case Page.Tank(id) => refreshTankDetail(id)
                case _ => refreshLibrary()
            }
        } else if (name.startsWith("archive-download:")) {
            match (r.payload) {
                case Some(p) =>
                    let (ok, total, path) = (p as (Int64, Int64, String)).getOrThrow()
                    toaster.show("已下载 ${ok}/${total} 到 ${path}", kind: ToastKind.Success)
                case None => ()
            }
        } else if (name.startsWith("source-download:")) {
            toaster.show("source 下载任务已创建", kind: ToastKind.Success)
        } else if (name.startsWith("tank-favorite:")) {
            // 取消收藏后条目应从书架即时消失；重取同时校正乐观更新。
            if (shelfFavoritesLoaded) {
                loadShelfFavorites()
            }
            match (page.value) {
                case Page.Tank(tankid) => refreshTankDetail(tankid)
                case _ => ()
            }
        } else if (name.startsWith("favorite:") || name.startsWith("isnew:")) {
            if (name.startsWith("favorite:") && shelfFavoritesLoaded) {
                loadShelfFavorites()
            }
            // 收藏/未读切换成功：仍在详情页/阅读页则重取元数据刷新展示
            match (page.value) {
                case Page.Detail(arcid) => refreshMeta(arcid)
                case Page.Reader(arcid, _) => refreshMeta(arcid)
                case _ => ()
            }
        } else if (name == "info") {
            match (r.payload) {
                case Some(p) => serverInfo.value = Some((p as ServerInfo).getOrThrow())
                case None => ()
            }
        } else if (name.startsWith("imgdl:")) {
        // 下载阶段成功是中间结果（解码由下载线程内提交到解码池），静默忽略。
        } else if (name.startsWith("img:")) {
            finishImageTask()
            let key = name.removePrefix("img:")
            match (r.payload) {
                case Some(p) =>
                    // 载荷 (String, ?NativeDecodedImage)：None = 下载完成但已不可见，跳过解码
                    // 的结果（静默，状态保持当前值，重新可见时会再次入队）。
                    let (k, d) = (p as (String, ?NativeDecodedImage)).getOrThrow()
                    match (d) {
                        case Some(img) =>
                            // 像素已在工作线程解好（圆角也已就地完成）；这里只登记 staged
                            // 原生像素（UI 线程，所有权交 cui 释放），纹理由 PixelImageView
                            // 首帧绘制时惰性创建。
                            stageNativePixelImage(k, img.width, img.height, img.pointer(), NativeImageReleaser(img))
                            imageState(k).value = "ready"
                            // LANLU_PERF 打点：e2e（requestImage→上屏前）+ 分阶段明细；
                            // 若该图属于翻页待达集合，集齐时 emit reader_turn_ms。
                            if (SubtitlePerf.enabled()) {
                                var dlUs: Int64 = 0
                                var decUs: Int64 = 0
                                synchronized(imgPerfStageMutex) {
                                    match (imgPerfStage.get(k)) {
                                        case Some(v) =>
                                            dlUs = v[0]
                                            decUs = v[1]
                                            imgPerfStage.remove(k)
                                        case None => ()
                                    }
                                }
                                var e2eUs: Int64 = 0
                                match (imgPerfT0.get(k)) {
                                    case Some(t0) =>
                                        e2eUs = (MonoTime.now() - t0).toMicroseconds()
                                        imgPerfT0.remove(k)
                                    case None => ()
                                }
                                SubtitlePerf.sampleUs("img_e2e_us", e2eUs)
                                // 逐图明细仅在 LANLU_PERF_VERBOSE=1 时输出：洪泛期 UI 线程
                                // 同步 println 本身是 pump 尖刺来源；聚合采样不受影响。
                                if (SubtitlePerf.verbose()) {
                                    println("[perf] img ${k} ${img.width}x${img.height} e2e=${e2eUs / 1000}ms dl=${dlUs / 1000}ms dec=${decUs / 1000}ms")
                                }
                                if (readerTurnPending.contains(k)) {
                                    readerTurnPending.remove(k)
                                    if (readerTurnPending.isEmpty()) {
                                        match (readerTurnT0) {
                                            case Some(t0) =>
                                                readerTurnT0 = None
                                                SubtitlePerf.emit("reader_turn_ms",
                                                    (MonoTime.now() - t0).toMilliseconds(), "ms")
                                            case None => ()
                                        }
                                    }
                                }
                            }
                        case None => ()
                    }
                case None =>
                    imageState(key).value = "error"
                    // LANLU_PERF 打点：失败也要清起点，避免残留影响后续重试的 e2e。
                    if (SubtitlePerf.enabled()) {
                        imgPerfT0.remove(key)
                        synchronized(imgPerfStageMutex) {
                            imgPerfStage.remove(key)
                        }
                    }
            }
        } else if (name.startsWith("backdrop:")) {
            // backdrop 解码到货：直接登记 staged 原生像素（不经过 img 管线，不需圆角），
            // 失败静默。
            match (r.payload) {
                case Some(p) =>
                    let (k, d) = (p as (String, NativeDecodedImage)).getOrThrow()
                    stageNativePixelImage(k, d.width, d.height, d.pointer(), NativeImageReleaser(d))
                    if (k.startsWith("backdrop:audio:")) {
                        imageState(k).value = "ready"
                    }
                case None => ()
            }
        } else if (name.startsWith("htmlres:")) {
            // 子资源到货：回填 WebviewSession（key 对号入座，迟到结果由模型内丢弃）。
            match (r.payload) {
                case Some(p) =>
                    let (key, url, bytes) = (p as (String, String, Array<UInt8>)).getOrThrow()
                    htmlPage.resourceLoaded(key, url, bytes)
                    readerVersion.value += 1
                case None => ()
            }
        } else if (name.startsWith("html:")) {
            // 正文到货：灌入 Blitz 会话，首帧由舞台 takeHtmlFrame 取走。
            match (r.payload) {
                case Some(p) =>
                    let (key, bytes) = (p as (String, Array<UInt8>)).getOrThrow()
                    htmlPage.htmlLoaded(key, bytes)
                    readerVersion.value += 1
                case None => ()
            }
        } else if (name.startsWith("playback:")) {
            // 媒体下载到货：回填 PlaybackModel（key 对号入座，迟到结果由模型内丢弃）。
            match (r.payload) {
                case Some(p) =>
                    // 载荷包含音频缓存路径及可选 LRC 歌词文本；时长开播后由 libVLC 回填。
                    let (key, path, lyrics) = (p as (String, String, String)).getOrThrow()
                    playback.onDownloaded(key, path, lyrics: lyrics)
                    readerVersion.value += 1
                case None => ()
            }
        } else if (name.startsWith("lyrics:")) {
            match (r.payload) {
                case Some(p) =>
                    let (key, lyrics) = (p as (String, String)).getOrThrow()
                    playback.onLyricsDownloaded(key, lyrics)
                    readerVersion.value += 1
                case None => ()
            }
        } else if (name.startsWith("subtitle:")) {
            // 外挂字幕文本到货：回填 PlaybackModel（key 对号入座，迟到结果由模型内丢弃）。
            match (r.payload) {
                case Some(p) =>
                    let (key, assetId, text) = (p as (String, Int64, String)).getOrThrow()
                    playback.onSubtitleDownloaded(key, assetId, text)
                    readerVersion.value += 1
                case None => ()
            }
        } else if (name.startsWith("subprobe:")) {
            match (r.payload) {
                case Some(p) =>
                    SubtitlePerf.spanEnd("subtitle_probe_e2e")
                    let (key, generation, streams) = (p as (String, UInt64, ArrayList<SubtitleStreamInfo>)).getOrThrow()
                    playback.onEmbeddedSubtitleProbed(key, generation, streams)
                    readerVersion.value += 1
                case None =>
                    SubtitlePerf.spanEnd("subtitle_probe_e2e")
                    if (name == "subprobe:${playback.mediaGeneration}:${playback.mediaKey}") {
                        playback.onEmbeddedSubtitleFailed(playback.mediaKey, playback.mediaGeneration, r.error)
                    }
            }
        } else if (name.startsWith("subscan:")) {
            match (r.payload) {
                case Some(p) =>
                    SubtitlePerf.spanEnd("subtitle_scan_e2e")
                    let (key, generation, tracks) = (p as (String, UInt64, ArrayList<ExtractedSubtitleTrack>))
                        .getOrThrow()
                    playback.onEmbeddedSubtitleScanned(key, generation, tracks)
                    readerVersion.value += 1
                case None =>
                    SubtitlePerf.spanEnd("subtitle_scan_e2e")
                    if (name == "subscan:${playback.mediaGeneration}:${playback.mediaKey}") {
                        playback.onEmbeddedSubtitleFailed(playback.mediaKey, playback.mediaGeneration, r.error)
                    }
            }
        } else if (name == "next.resolve") {
            // 候选解析到货：无候选 → 失败态；有候选 → 记录（卡片展示）；
            // seamlessNext 开时继续取页表自动拼接。
            appendInFlight = false
            match (r.payload) {
                case Some(p) =>
                    let (fromArc, seamless, candidate) = (p as (String, Bool, ?(String, String, Int64))).getOrThrow()
                    appendResolvedFrom = fromArc
                    match (candidate) {
                        case Some((id, title, coverId)) =>
                            readerNextId = id
                            readerNextTitle.value = title
                            // 结束页卡片封面（asset 管线低优先级；失败静默占位）。
                            if (coverId > 0) {
                                readerNextCoverKey = "asset:${coverId}"
                                requestImage(readerNextCoverKey, "/api/assets/${coverId}")
                            }
                            if (seamless) {
                                match (api) {
                                    case Some(a) =>
                                        appendInFlight = true
                                        let _ = worker.submit("next.files:${id}", {
                                            => (id, title, a.files(id))
                                        })
                                    case None => ()
                                }
                            }
                        case None =>
                            reader.appendNextFailed("没有下一档案了")
                            readerVersion.value += 1
                    }
                case None => ()
            }
        } else if (name.startsWith("next.files")) {
            // 候选页表到货：追加 segment 重建流（当前位置不变，末尾虚拟页顺延）。
            appendInFlight = false
            match (r.payload) {
                case Some(p) =>
                    let (id, title, view) = (p as (String, String, ArchivePageView)).getOrThrow()
                    if (view.size == 0) {
                        reader.appendNextFailed("没有下一档案了")
                    } else {
                        reader.appendArchive(id, title, view)
                    }
                    readerVersion.value += 1
                case None => ()
            }
        }
    }

    // ==================== 设置区扩展：数据加载 ====================
    // 惯例：worker.submit 同名在途去重；失败统一走 handleError（401 → logout + toast）。

    // 概览 dashboard：统计 + 30 天趋势 + 最近阅读/收藏（最近活动用 search 聚合，对齐 frontend）。
    public func loadOverviewExtras(): Unit {
        let a = api ?? return
        let lang = language.value
        let _ = worker.submitTagged(
            "set.overview",
            lang,
            {
                =>
                    let stats = a.userStats()
                    let trend = a.userTrend(30)
                    let qr = SearchQuery()
                    qr.sortby = "lastread"
                    qr.order = "desc"
                    qr.pageSize = 3
                    qr.lang = lang
                    let read = a.search(qr).items
                    let qf = SearchQuery()
                    qf.sortby = "lastread"
                    qf.order = "desc"
                    qf.favoriteonly = true
                    qf.pageSize = 3
                    qf.lang = lang
                    let fav = a.search(qf).items
                    (stats, trend, read, fav)
            }
        )
    }

    public func loadTagCloud(): Unit {
        let a = api ?? return
        let lang = language.value
        let _ = worker.submitTagged("set.cloud", lang, {=> a.tagCloud(200, lang: lang)})
    }

    public func loadAdminUsers(): Unit {
        let a = api ?? return
        let _ = worker.submit("set.users", {=> a.adminUsers()})
    }

    public func loadSysSettings(): Unit {
        let a = api ?? return
        let _ = worker.submit("set.sys", {=> a.systemSettings()})
    }

    public func loadAdminCategories(): Unit {
        let a = api ?? return
        let _ = worker.submit("set.cats", {=> a.adminCategories()})
    }

    public func loadTagPage(q: String, ns: String, offset: Int64): Unit {
        let a = api ?? return
        // 任务名带筛选参数，避免快速切换筛选时后一次请求被同名去重静默丢弃。
        let _ = worker.submit("set.tags:${q}:${ns}:${offset}", {=> a.adminTagPage(q, ns, offset, 20)})
    }

    public func loadTagNamespaces(): Unit {
        let a = api ?? return
        let _ = worker.submit("set.tagns", {=> a.adminTagNamespaces()})
    }

    public func loadSmartFilters(): Unit {
        let a = api ?? return
        let _ = worker.submit("set.filters", {=> a.smartFilters()})
    }

    // ---- 任务记录 SSE 实时订阅（对齐 web 前端 EventSource：进入页即长连，帧到即刷新）----
    // 生命周期：tasksPage 组合时 ensureTaskStream(status)；切筛选→按新 status 重连；
    // 切走板块（settings_view）/离开设置页（pump）→ stopTaskStream。
    // 取消仅置标志位不跨线程关流：服务端 15s ping 会唤醒 read，旧线程最迟一个 ping 周期
    // 内自行退出，其间尾帧由 dispatch 的 status 一致性校验丢弃（代次 gen 兜底）。
    private let taskStreamMutex = Mutex()
    private var taskStreamGen: Int64 = 0
    private var taskStreamRunning = false
    private var taskStreamCancel = false
    private var taskStreamStatus = ""

    public func ensureTaskStream(status: String): Unit {
        let a = match (api) {
            case Some(x) => x
            case None => return
        }
        var resetPage = false
        let gen = synchronized(taskStreamMutex) {
            if (taskStreamRunning && taskStreamStatus == status) {
                return
            }
            taskStreamCancel = true // 停旧流（靠 gen 代次判停，见块头注释）
            resetPage = taskStreamStatus != status
            taskStreamStatus = status
            taskStreamCancel = false
            taskStreamRunning = true
            taskStreamGen += 1
            taskStreamGen
        }
        // 筛选变化：清掉旧筛选的页面数据，避免新快照到货前展示错筛选列表。
        if (resetPage) {
            taskPage.value = None
        }
        let _ = spawn {
            taskStreamLoop(a, status, gen)
        }
    }

    public func restartTaskStream(status: String): Unit {
        stopTaskStream()
        ensureTaskStream(status)
    }

    public func stopTaskStream(): Unit {
        synchronized(taskStreamMutex) {
            taskStreamCancel = true
            taskStreamRunning = false
            taskStreamStatus = ""
            taskStreamGen += 1
        }
    }

    private func isTaskStreamCancelled(gen: Int64): Bool {
        synchronized(taskStreamMutex) {
            taskStreamCancel || taskStreamGen != gen
        }
    }

    // 断线/服务端关流 2s 后重连（对齐 EventSource retry）；401 投错误结果走全局登出后退出。
    private func taskStreamLoop(a: LanluApi, status: String, gen: Int64): Unit {
        while (!isTaskStreamCancelled(gen)) {
            try {
                a.streamTaskList(status, 10, {page => postTaskStreamPage(status, gen, page)})
                // 流正常结束（服务端关闭）：取消则退出，否则走统一退避重连。
                if (isTaskStreamCancelled(gen)) {
                    return
                }
                sleep(Duration.second * 2)
            } catch (e: Exception) {
                if (isTaskStreamCancelled(gen)) {
                    return
                }
                match (e as ApiException) {
                    case Some(ae) =>
                        if (ae.status == 401) {
                            worker.post("set.tasks.stream:${status}", None, error: ae.message)
                            return
                        }
                    case None => ()
                }
                sleep(Duration.second * 2)
            }
        }
    }

    private func postTaskStreamPage(status: String, gen: Int64, page: TaskListPage): Bool {
        if (isTaskStreamCancelled(gen)) {
            return false
        }
        worker.post("set.tasks.stream:${status}", Some(page))
        return true
    }

    public func loadCron(): Unit {
        let a = api ?? return
        let _ = worker.submit("set.cron", {=> (a.cronStatus(), a.cronTasks())})
    }

    public func loadPlugins(): Unit {
        let a = api ?? return
        let _ = worker.submit("set.plugins", {=> a.plugins()})
    }

    // 账户安全四路数据打包一路返回（dispatch 解包写四个 State）。
    public func loadAuthSecurity(): Unit {
        let a = api ?? return
        let _ = worker.submit("set.security", {
            => (a.listSessions(), a.listTokens(), a.listPasskeys(), a.totpStatus())
        })
    }

    // ==================== 设置区扩展：写操作 ====================
    // 统一模式：worker 执行 → 成功 toast + 按任务名 reload 对应板块（见 dispatch 的 act.* 分支）；
    // 失败走 handleError。submitAct 不传闭包，reload 由 dispatch 按任务名前缀触发。

    private func submitAct(name: String, okToast: String, job: () -> Any): Unit {
        let _ = worker.submit(
            name,
            {
                =>
                    job()
                    okToast
            }
        )
    }

    // ---- 用户管理 ----
    public func actCreateUser(username: String, admin: Bool): Unit {
        let a = api ?? return
        let _ = worker.submit("act.user.create",
            {=> "用户创建成功 \"${username}\"，生成密码: ${a.adminCreateUser(username, admin)}"})
    }
    public func actDeleteUser(id: Int64): Unit {
        let a = api ?? return
        let _ = submitAct(
            "act.user.del",
            "用户已删除",
            {
                =>
                    a.adminDeleteUser(id);
                    ""
            }
        )
    }
    public func actSetUserRole(id: Int64, admin: Bool): Unit {
        let a = api ?? return
        let _ = submitAct(
            "act.user.role",
            "角色已更新",
            {
                =>
                    a.adminSetUserRole(id, admin);
                    ""
            }
        )
    }
    public func actResetUserPassword(id: Int64, pw: String): Unit {
        let a = api ?? return
        let _ = submitAct(
            "act.user.resetpw",
            "密码已重置",
            {
                =>
                    a.adminResetUserPassword(id, pw);
                    ""
            }
        )
    }

    // ---- 系统设置 ----
    public func actSaveSysSettings(entries: ArrayList<(String, String)>): Unit {
        let a = api ?? return
        let _ = submitAct(
            "act.sys.save",
            "设置已保存",
            {
                =>
                    a.saveSystemSettings(entries);
                    ""
            }
        )
    }

    // ---- 分类管理 ----
    public func actToggleCategory(catid: String, enabled: Bool): Unit {
        let a = api ?? return
        let _ = submitAct(
            "act.cat.toggle",
            "分类已更新",
            {
                =>
                    a.updateCategory(catid, "{\"enabled\":${enabled}}")
                    ""
            }
        )
    }
    public func actDeleteCategory(catid: String): Unit {
        let a = api ?? return
        let _ = submitAct(
            "act.cat.del",
            "分类已删除",
            {
                =>
                    a.deleteCategory(catid);
                    ""
            }
        )
    }
    public func actScanCategory(catid: String): Unit {
        let a = api ?? return
        let _ = submitAct(
            "act.cat.scan",
            "已提交分类扫描任务",
            {
                =>
                    a.scanCategory(catid);
                    ""
            }
        )
    }
    public func actScanAllCategories(): Unit {
        let a = api ?? return
        let _ = submitAct(
            "act.cat.scanall",
            "已提交全库扫描任务",
            {
                =>
                    a.scanAllCategories();
                    ""
            }
        )
    }
    public func actSaveCategory(catid: String, jsonBody: String): Unit {
        if (catid.size == 0) {
            let a = api ?? return
            let _ = submitAct(
                "act.cat.save",
                "分类已创建",
                {
                    =>
                        a.createCategory(jsonBody);
                        ""
                }
            )
        } else {
            let a = api ?? return
            let _ = submitAct(
                "act.cat.save",
                "分类已保存",
                {
                    =>
                        a.updateCategory(catid, jsonBody);
                        ""
                }
            )
        }
    }

    // ---- 标签管理 ----
    public func actSaveTag(id: Int64, jsonBody: String): Unit {
        if (id == 0) {
            let a = api ?? return
            let _ = submitAct(
                "act.tag.save",
                "标签已创建",
                {
                    =>
                        a.createTag(jsonBody);
                        ""
                }
            )
        } else {
            let a = api ?? return
            let _ = submitAct(
                "act.tag.save",
                "标签已保存",
                {
                    =>
                        a.updateTag(id, jsonBody);
                        ""
                }
            )
        }
    }
    public func actDeleteTag(id: Int64): Unit {
        let a = api ?? return
        let _ = submitAct(
            "act.tag.del",
            "标签已删除",
            {
                =>
                    a.deleteTag(id);
                    ""
            }
        )
    }

    // ---- 智能分类 ----
    public func actToggleFilter(id: Int64): Unit {
        let a = api ?? return
        let _ = submitAct(
            "act.filter.toggle",
            "已更新",
            {
                =>
                    a.toggleSmartFilter(id);
                    ""
            }
        )
    }
    public func actDeleteFilter(id: Int64): Unit {
        let a = api ?? return
        let _ = submitAct(
            "act.filter.del",
            "删除成功",
            {
                =>
                    a.deleteSmartFilter(id);
                    ""
            }
        )
    }
    public func actSaveFilter(id: Int64, jsonBody: String): Unit {
        if (id == 0) {
            let a = api ?? return
            let _ = submitAct(
                "act.filter.save",
                "智能分类已创建",
                {
                    =>
                        a.createSmartFilter(jsonBody);
                        ""
                }
            )
        } else {
            let a = api ?? return
            let _ = submitAct(
                "act.filter.save",
                "智能分类已保存",
                {
                    =>
                        a.updateSmartFilter(id, jsonBody);
                        ""
                }
            )
        }
    }
    // 上移/下移：先在本地 State 换序（立即反馈），再提交全量顺序。
    public func actMoveFilter(id: Int64, up: Bool): Unit {
        let a = api ?? return
        let list = smartFilters.value
        var idx = -1
        for (i in 0..list.size) {
            if (list[i].id == id) {
                idx = i
                break
            }
        }
        let target = if (up) {
            idx - 1
        } else {
            idx + 1
        }
        if (idx < 0 || target < 0 || target >= list.size) {
            return
        }
        let tmp = list[idx]
        list[idx] = list[target]
        list[target] = tmp
        smartFilters.value = list // 整体重赋值推进 State 代次
        let ids = ArrayList<Int64>()
        for (f in list) {
            ids.add(f.id)
        }
        let _ = submitAct(
            "act.filter.reorder",
            "顺序已保存",
            {
                =>
                    a.reorderSmartFilters(ids);
                    ""
            }
        )
    }

    // ---- 任务记录 ----
    public func actCancelTask(id: Int64): Unit {
        let a = api ?? return
        let _ = submitAct(
            "act.task.cancel",
            "任务已取消",
            {
                =>
                    a.cancelTask(id);
                    ""
            }
        )
    }
    public func actRetryTask(id: Int64): Unit {
        let a = api ?? return
        let _ = submitAct(
            "act.task.retry",
            "已重新加入任务队列",
            {
                =>
                    a.retryTask(id);
                    ""
            }
        )
    }

    // ---- 定时任务 ----
    public func actCronServiceToggle(): Unit {
        let a = api ?? return
        let running = match (cronStatus.value) {
            case Some(s) => s.running;
            case None => false
        }
        if (running) {
            let _ = submitAct(
                "act.cron.svc",
                "定时任务服务已停止",
                {
                    =>
                        a.cronStop();
                        ""
                }
            )
        } else {
            let _ = submitAct(
                "act.cron.svc",
                "定时任务服务已启动",
                {
                    =>
                        a.cronStart();
                        ""
                }
            )
        }
    }
    public func actCronToggle(id: Int64, enabled: Bool): Unit {
        let a = api ?? return
        let _ = submitAct(
            "act.cron.toggle",
            "已更新",
            {
                =>
                    a.cronSetEnabled(id, enabled);
                    ""
            }
        )
    }
    public func actCronTrigger(id: Int64): Unit {
        let a = api ?? return
        let _ = submitAct(
            "act.cron.trigger",
            "已手动触发任务",
            {
                =>
                    a.cronTrigger(id);
                    ""
            }
        )
    }
    public func actCronDelete(id: Int64): Unit {
        let a = api ?? return
        let _ = submitAct(
            "act.cron.del",
            "定时任务已删除",
            {
                =>
                    a.cronDeleteTask(id);
                    ""
            }
        )
    }
    public func actCronSave(id: Int64, jsonBody: String): Unit {
        if (id == 0) {
            let a = api ?? return
            let _ = submitAct(
                "act.cron.save",
                "定时任务已创建",
                {
                    =>
                        a.cronCreateTask(jsonBody);
                        ""
                }
            )
        } else {
            let a = api ?? return
            let _ = submitAct(
                "act.cron.save",
                "定时任务已保存",
                {
                    =>
                        a.cronUpdateTask(id, jsonBody);
                        ""
                }
            )
        }
    }
    // 启动任务设置（复用系统设置批量接口，单项保存）。
    public func actSaveStartup(key: String, value: Bool): Unit {
        let a = api ?? return
        let entries = ArrayList<(String, String)>()
        entries.add((key, "${value}"))
        let _ = submitAct(
            "act.sys.save",
            "启动任务设置已保存",
            {
                =>
                    a.saveSystemSettings(entries);
                    ""
            }
        )
    }

    // ---- 插件管理 ----
    public func actPluginEnabled(ns: String, enabled: Bool): Unit {
        let a = api ?? return
        let _ = submitAct(
            "act.plugin.toggle",
            "已更新",
            {
                =>
                    a.setPluginEnabled(ns, enabled);
                    ""
            }
        )
    }
    public func actPluginDelete(ns: String): Unit {
        let a = api ?? return
        let _ = submitAct(
            "act.plugin.del",
            "插件已删除",
            {
                =>
                    a.deletePlugin(ns);
                    ""
            }
        )
    }
    public func actPluginSaveConfig(ns: String, jsonBody: String): Unit {
        let a = api ?? return
        let _ = submitAct(
            "act.plugin.cfg",
            "插件配置已保存",
            {
                =>
                    a.savePluginConfig(ns, jsonBody);
                    ""
            }
        )
    }

    // ---- 账户安全 ----
    public func actChangeCredentials(username: String, password: String): Unit {
        let a = api ?? return if (username.size > 0 && username != settings.username) {
            pendingCredUsername = username
        }
        let _ = submitAct(
            "act.cred",
            "凭据已保存",
            {
                =>
                    if (username.size > 0 && username != settings.username) {
                        a.changeUsername(username)
                    }
                    if (password.size > 0) {
                        a.changePassword(password)
                    }
                    ""
            }
        )
    }
    public func actTotpDisable(): Unit {
        let a = api ?? return
        let _ = submitAct(
            "act.totp.off",
            "双重验证已关闭",
            {
                =>
                    a.totpDisable();
                    ""
            }
        )
    }
    public func actTotpRegenerate(): Unit {
        let a = api ?? return
        let _ = submitAct(
            "act.totp.regen",
            "新的恢复码已生成",
            {
                =>
                    a.totpRegenerate();
                    ""
            }
        )
    }
    public func actRevokeSession(id: Int64): Unit {
        let a = api ?? return
        let _ = submitAct(
            "act.session.revoke",
            "登录会话已撤销",
            {
                =>
                    a.revokeSession(id);
                    ""
            }
        )
    }
    public func actRevokeOtherSessions(): Unit {
        let a = api ?? return
        let _ = submitAct(
            "act.session.revokeothers",
            "其他设备已全部退出",
            {
                =>
                    a.revokeOtherSessions();
                    ""
            }
        )
    }
    public func actCreateToken(name: String): Unit {
        let a = api ?? return
        let _ = worker.submit(
            "act.token.create",
            {
                =>
                    let t = a.createToken(name)
                    "Token已创建: ${t.token}（仅显示一次）"
            }
        )
    }
    public func actRevokeToken(id: Int64): Unit {
        let a = api ?? return
        let _ = submitAct(
            "act.token.revoke",
            "Token 已撤销",
            {
                =>
                    a.revokeToken(id);
                    ""
            }
        )
    }
    public func actRevokePasskey(id: Int64): Unit {
        let a = api ?? return
        let _ = submitAct(
            "act.passkey.revoke",
            "Passkey 已删除",
            {
                =>
                    a.revokePasskey(id);
                    ""
            }
        )
    }

    // 统计信息词云点击：携标签回书库搜索（对齐 frontend 词云跳 /?q= 的行为）。
    // 沿用详情页标签 chip 的既有链路：写 searchText → submitFilter 收束查询 → 切回书库页。
    public func searchFromSettings(tag: String): Unit {
        searchText.value = tag
        submitFilter()
        navigate(Page.Library)
    }
}
