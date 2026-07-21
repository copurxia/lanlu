package lanlu_client_next.app

import cui.{State, Toaster, ToastKind, clearImageCache, clearPixelImages, onPixelImageEvicted, stagePixelImage}
import lanlu_client_next.img.*
import lanlu_client_next.net.*
import std.collection.{ArrayList, HashMap}
import std.convert.Parsable
import std.fs.{Directory, File, Path, exists}
import std.math.sqrt
import std.sync.Mutex

// 排序字段映射：与 ui 层 SORT_LABELS 按下标一一对应（改动须两边同步）。
public let SEARCH_SORT_FIELDS = ["title", "created_at", "updated_at", "lastread", "pagecount", "release_at"]

// 浏览模式：分类行上限（母计划 §7 防页面过长）与每行条目数（对齐 frontend getDiscover 默认 count=12）。
public let BROWSE_CATEGORY_ROW_LIMIT: Int64 = 8
public let BROWSE_ROW_SIZE: Int64 = 12

// 图片解码上限（最长边物理像素，0=不缩）：封面按最大展示位（详情 hero 200vp @2x）给 400，
// 阅读页按 2000 封顶。按 key 前缀分档、档位固定，故内存 staged/纹理 key 无需带尺寸；
// 磁盘缓存存原始字节，缩小只发生在解码期，各尺寸共用同一磁盘缓存条目。
private let ASSET_DECODE_MAX_DIM: Int32 = 400
private let PAGE_DECODE_MAX_DIM: Int32 = 2000

// key 前缀 → 解码尺寸档位（asset:=封面/资产，page:=阅读页）。
private func decodeMaxDimension(key: String): Int32 {
    if (key.startsWith("asset:")) { return ASSET_DECODE_MAX_DIM }
    if (key.startsWith("page:")) { return PAGE_DECODE_MAX_DIM }
    return 0
}

// 浏览模式的一行（随机推荐或某个分类）。元素内部字段可变；任何变更后须整体重赋值
// browseRows（或赋回原值）推进 State 代次，视图才会重绘。
public class BrowseRow {
    public var key: String = ""        // "random" 或 <catid>（worker 任务名 row:<key>）
    public var title: String = ""
    public var catid: String = ""      // 随机行为空串
    public var items = ArrayList<SearchItem>()
    public var requested = false       // 已提交过加载任务（分类到达后补建行不复用旧任务）
    public var loading = true
    public var failed = false
}

public class AppModel {
    public let page = State<Page>(Page.Login)
    public let toaster = Toaster()
    public var settings: AppSettings
    public var api: ?LanluApi = None
    public let worker = ApiWorker()

    // 书库
    public let searchText = State<String>("")
    public let items = State<ArrayList<SearchItem>>(ArrayList<SearchItem>())
    public let loading = State<Bool>(false)
    public let recordsTotal = State<Int64>(0)
    public let currentPage = State<Int64>(1)
    public var query = SearchQuery()
    public let categories = State<ArrayList<CategoryItem>>(ArrayList<CategoryItem>())
    public let categoryIndex = State<Int64>(0)
    public let sortIndex = State<Int64>(0)
    public let orderIndex = State<Int64>(0)
    public let favOnly = State<Bool>(false)
    public let newOnly = State<Bool>(false)
    public let untaggedOnly = State<Bool>(false)

    // 浏览模式行数据（随机推荐 + 分类行）与内容区宽度（SizeProbe 写入，驱动自适应列数）
    public let browseRows = State<ArrayList<BrowseRow>>(ArrayList<BrowseRow>())
    public let contentWidth = State<Float32>(0.0)
    // 工具条「合集聚合」开关（0=开 1=关）：T10 合集数据管线接入时消费，
    // 本任务仅保存选择状态（原型 home-tools 的第二个下拉）。
    public let tankGroupIndex = State<Int64>(0)

    // 详情/阅读
    public let meta = State<?ArchiveMeta>(None)
    public let pages = State<ArrayList<PageInfo>>(ArrayList<PageInfo>())
    public let readerIndex = State<Int64>(1)
    public var readerArcid: String = ""   // 当前阅读档案
    // 阅读器状态机（T12 拆出，纯逻辑可单测）。旧 reader_view 仍读本类的
    // pages/readerIndex（1 基）并经 gotoPage 等委托方法驱动；T13 重写后直接消费 reader。
    public let reader: ReaderModel
    // 媒体 lane 播放引擎（ffplay 子进程方案，纯逻辑可单测；与 reader 一样是普通类，
    // 状态变更经 readerVersion 广播视图重建）。
    public let playback = PlaybackModel()

    // 详情页（档案）：页面预览页表、三视图切换（0=缩略图 1=列表 2=树）、所属合集、相关推荐。
    // detailWidth 由详情主列 SizeProbe 写入，驱动预览缩略图网格列数。
    public let detailPages = State<ArrayList<PageInfo>>(ArrayList<PageInfo>())
    public let pageViewIndex = State<Int64>(0)
    public let parentTanks = State<ArrayList<TankoubonInfo>>(ArrayList<TankoubonInfo>())
    public let relatedItems = State<ArrayList<SearchItem>>(ArrayList<SearchItem>())
    public let detailWidth = State<Float32>(0.0)
    // 窗口逻辑宽（vp）：main.cj onTick 自 window.width 同步（变化才写），驱动详情标题字号等响应式布局。
    public let windowWidth = State<Int64>(0)

    // 详情页（合集）：元数据、成员档案（search?tankoubon_id）、网格/列表切换、即时筛选、相关合集。
    public let tank = State<?TankoubonInfo>(None)
    public let tankMembers = State<ArrayList<SearchItem>>(ArrayList<SearchItem>())
    public let tankMemberViewIndex = State<Int64>(0)
    public let tankFilter = State<String>("")
    public let tankRelated = State<ArrayList<TankoubonInfo>>(ArrayList<TankoubonInfo>())

    // 设置页
    public let serverInfo = State<?ServerInfo>(None)
    public let cacheInfo = State<String>("")
    // 当前登录用户是否管理员：控制设置页「服务器」分组入口显隐（LoginData.isAdmin）。
    public let isAdmin = State<Bool>(false)

    // ---- 设置区扩展：各板块数据（进场加载，随 State 重建自动刷新视图） ----
    public let userStats = State<?UserStats>(None)
    public let userTrend = State<ArrayList<TrendPoint>>(ArrayList<TrendPoint>())
    public let recentRead = State<ArrayList<SearchItem>>(ArrayList<SearchItem>())
    public let recentFav = State<ArrayList<SearchItem>>(ArrayList<SearchItem>())
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

    public init(s: AppSettings) {
        settings = s
        reader = ReaderModel(s)
        readerShowInfo = State<Bool>(s.readerShowInfo)
        autoPlayIntervalSlider.value = Float32(clampAutoPlayInterval(s.readerAutoPlayInterval))
        // 像素纹理缓存 LRU 逐出回调：把被逐出 key 的加载状态复位为 ""，仍在屏的
        // widget 下帧重建时经 requestImage 重新请求/显示占位，避免对着已逐出纹理绘制空白。
        // 回调在 UI 线程触发（stage/绘制路径），直接写 State 无并发问题。
        onPixelImageEvicted = { k =>
            synchronized(imageMutex) {
                match (imageStates.get(k)) {
                    case Some(st) => if (st.value == "ready") { st.value = "" }
                    case None => ()
                }
            }
        }
        // ReaderModel 出口接线：设置落盘、进度上报（走 worker，失败静默同旧 reportProgress）、
        // 预取（复用图片管线，并发上限由 requestImage 保证）。
        reader.onPersist = { => saveSettingsTo(defaultSettingsPath(), settings) }
        reader.onProgress = { arc, page1 =>
            match (api) {
                case Some(a) =>
                    let _ = worker.submit("progress", {=> a.setProgress(arc, page1); return page1 })
                case None => ()
            }
        }
        // 跨 segment 预取：页属哪个档案按 arcidOfReal 取（拼接后邻居页可能属下一档案）。
        reader.onPrefetch = { _, indices =>
            for (i in indices) {
                match (reader.pageAt(i)) {
                    case Some(p) =>
                        let a2 = reader.arcidOfReal(i)
                        let pid = p.id
                        requestImage("page:${a2}:${pid}",
                            "/api/archives/${a2}/page?path=${percentEncode(pid)}")
                    case None => ()
                }
            }
        }
        // 无缝续读出口：进入末尾虚拟页时解析候选（合集下一章 → 相关推荐），
        // seamless 开时继续取页表自动拼接；关时只解析候选供结束页卡片展示。
        reader.onAppendNext = { arcid => startAppendNext(arcid) }
        // 媒体下载出口：提交 worker 拉取页字节并落缓存目录（与图片缓存同根，
        // 按 arcid 分目录、percentEncode(pageId) 作文件名——"." 是 unreserved，
        // 扩展名得以保留）。任务名带 mediaKey 天然按媒体去重；完成经 pump 的
        // drain 分发回填 playback.onDownloaded/onFailed。
        playback.onDownload = { arc, pid =>
            match (api) {
                case Some(a) =>
                    let key = playback.mediaKey // load() 先置 mediaKey 再调本回调
                    let dir = "${defaultCacheRoot(activeBaseUrl())}/media/${arc}"
                    let path = "${dir}/${percentEncode(pid)}"
                    let _ = worker.submit("playback:${key}", {=>
                        let bytes = a.pageBytes(arc, pid)
                        let dirPath = Path(dir)
                        if (!exists(dirPath)) { Directory.create(dirPath, recursive: true) }
                        File.writeTo(Path(path), bytes)
                        // 时长探测：ffplay 不回报总时长，进度条/seek 上限都需要它。
                        // 在 worker 线程跑 ffprobe（UI 线程不能阻塞），失败/缺失保持 0（未知）。
                        (key, path, probeMediaDuration(path))
                    })
                case None => ()
            }
        }
        // 初始选中 active 服务器（回退首个）；api 不再在此构建——
        // 登录/恢复会话时按选中服务器的 baseUrl 现场创建。
        if (s.activeServerId.size > 0 && s.profileById(s.activeServerId).isSome()) {
            selectedServerId.value = s.activeServerId
        } else if (s.servers.size > 0) {
            selectedServerId.value = s.servers[0].id
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

    // ---- 多服务器登录 ----
    public let selectedServerId = State<String>("")
    public let totpChallengeId = State<String>("") // 空串=无 TOTP 挑战
    public let testConnResult = State<String>("")  // ""=无 "testing"=在途 "ok"=成功 其余=错误文案
    public let serverModalOpen = State<Bool>(false)
    public let deleteConfirmId = State<String>("") // 删除二次确认：首击置 id，再击执行
    public let serversVersion = State<Int64>(0)    // settings.servers 变更计数，驱动列表重绘
    public var editingServerId: String = ""        // 编辑弹窗目标；空串=新增
    public let loginError = State<String>("")      // 登录/TOTP 内联错误条（空串=无），替代 toast

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
    public func probeServers(): Unit {
        for (p in settings.servers) {
            let id = p.id
            let _ = worker.submit("probe:${id}", {=>
                let _ = LanluApi(p.baseUrl).info()
                return id
            })
        }
    }

    // ---- 会话 ----

    public func selectedProfile(): ?ServerProfile {
        settings.profileById(selectedServerId.value)
    }

    // 切换选中服务器：复位 TOTP/删除确认态；有已存会话则静默恢复（成功直接进书库，
    // 失败由 handleError 的 "me" 分支清 token 落回表单）。
    public func selectServer(id: String): Unit {
        if (selectedServerId.value == id) { return }
        selectedServerId.value = id
        totpChallengeId.value = ""
        deleteConfirmId.value = ""
        loginError.value = ""
        match (settings.profileById(id)) {
            case Some(p) => if (p.token.size > 0) { resumeProfile(p) }
            case None => ()
        }
    }

    private func resumeProfile(p: ServerProfile): Unit {
        let a = LanluApi(p.baseUrl)
        a.setToken(p.token)
        api = a
        let _ = worker.submit("me", {=> a.me() })
    }

    public func tryResumeSession(): Unit {
        match (settings.activeProfile()) {
            case Some(p) => if (p.token.size > 0) { resumeProfile(p) }
            case None => ()
        }
    }

    // 登录选中服务器。TotpRequired 不视为失败：任务内捕获后把 challengeId 放在元组第 4 位
    // 回传（worker 的 error 通道只有 String，带不了 challengeId），dispatch 据此切 TOTP 表单。
    public func loginSelected(user: String, pass: String): Unit {
        let p = match (selectedProfile()) {
            case Some(x) => x
            case None => return
        }
        let a = LanluApi(p.baseUrl)
        loading.value = true
        loginError.value = ""
        let sid = p.id
        let _ = worker.submit("login", {=>
            let _ = a.info()              // 先探测：非 lanlu 服务/地址错误会在这里抛错
            try {
                let d = a.login(user, pass)
                return (a, d, sid, "")
            } catch (e: TotpRequired) {
                return (a, LoginData(), sid, e.challengeId)
            }
        })
    }

    public func verifyTotp(code: String, recoveryCode: String): Unit {
        let p = match (selectedProfile()) {
            case Some(x) => x
            case None => return
        }
        let cid = totpChallengeId.value
        if (cid.size == 0) { return }
        let a = LanluApi(p.baseUrl)
        loading.value = true
        loginError.value = ""
        let sid = p.id
        let _ = worker.submit("login-totp", {=>
            let d = a.verifyTotpLogin(cid, code, recoveryCode)
            return (a, d, sid, "")
        })
    }

    public func dismissTotp(): Unit {
        totpChallengeId.value = ""
        loginError.value = ""
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
        saveSettingsTo(defaultSettingsPath(), settings)
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
        saveSettingsTo(defaultSettingsPath(), settings)
        deleteConfirmId.value = ""
        serversVersion.value = serversVersion.value + 1
        if (selectedServerId.value == id) {
            selectedServerId.value = if (settings.servers.size > 0) { settings.servers[0].id } else { "" }
        }
    }

    public func testConnection(url: String): Unit {
        let norm = normalizeServerUrl(url)
        if (norm.size == 0) {
            testConnResult.value = "请输入服务器地址"
            return
        }
        testConnResult.value = "testing"
        let _ = worker.submit("testconn", {=> LanluApi(norm).info() })
    }

    // 登出只清 active profile 的 token（服务器条目保留）；旧三字段由 saveSettingsTo 同步。
    public func logout(): Unit {
        match (settings.activeProfile()) {
            case Some(p) => p.token = ""
            case None => ()
        }
        saveSettingsTo(defaultSettingsPath(), settings)
        isAdmin.value = false
        page.value = Page.Login
    }

    // ---- 书库查询（即时应用语义：状态变更即写 query 并查询，无「应用」按钮）----

    // 查询入口：把索引/开关状态同步进 query（query.filter 例外——它只由搜索按钮写入，
    // 本函数不同步 searchText，否则侧栏/排序的即时应用会把未提交的输入框文本一并提交）。
    public func submitSearch(page: Int64): Unit {
        let a = api ?? return
        query.page = page
        query.sortby = SEARCH_SORT_FIELDS[sortIndex.value]
        query.order = if (orderIndex.value == 0) { "asc" } else { "desc" }
        query.categoryId = selectedCategoryId()
        query.favoriteonly = favOnly.value
        query.newonly = newOnly.value
        query.untaggedonly = untaggedOnly.value
        query.groupbyTanks = tankGroupOn()
        loading.value = true
        let q = query
        let _ = worker.submit("search", {=> a.search(q) })
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
        !browseExited && query.filter.size == 0 && !favOnly.value && !newOnly.value &&
            !untaggedOnly.value && categoryIndex.value == 0
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

    // 即时应用收束：浏览模式下网格不可见、无需查询（行数据各自加载，且再次进入搜索
    // 模式时 submitSearch 会同步全部状态）；搜索/过滤模式立即回第 1 页查询。
    public func applyFilters(): Unit {
        if (isBrowseMode()) { return }
        submitSearch(1)
    }

    // 侧栏「浏览」分组点击（互斥单选）：0=全部 1=仅收藏 2=仅未读 3=仅无标签。
    // 「全部」同时取消分类选择——它是回到浏览模式的总复位（搜索词需另行清空）。
    public func selectBrowseFilter(kind: Int64): Unit {
        browseExited = false
        favOnly.value = (kind == 1)
        newOnly.value = (kind == 2)
        untaggedOnly.value = (kind == 3)
        if (kind == 0) { categoryIndex.value = 0 }
        applyFilters()
    }

    // 工具条「搜索」：写入关键词并收束查询；清空词后搜索即回浏览模式（复位出站标记）。
    public func submitFilter(): Unit {
        browseExited = false
        query.filter = searchText.value
        applyFilters()
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
        if (categoryIndex.value == index) { return }
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
        if (idx <= 0 || idx > categories.value.size) { return "" }
        categories.value[idx - 1].catid
    }

    // 分类列表：登录/恢复会话成功后加载，供侧栏分类分组与浏览模式分类行使用。
    public func loadCategories(): Unit {
        let a = api ?? return
        let _ = worker.submit("categories", {=> a.categories() })
    }

    // 总页数（至少 1 页）；pageSize 异常时按 40 防御。
    public func maxPage(): Int64 {
        let size = if (query.pageSize > 0) { query.pageSize } else { 40 }
        let total = recordsTotal.value
        if (total <= 0) { return 1 }
        (total + size - 1) / size
    }

    // ---- 浏览模式行数据 ----

    // 建立/刷新行集合：继续阅读 + 随机推荐 + 分类前 BROWSE_CATEGORY_ROW_LIMIT 个
    // （新到档案行已按用户要求移除，随机推荐之下直接接分类行）。
    // 已存在的行原样保留（随机行不因分类列表到达而重洗）；仅对未请求过的行提交任务，
    // 任务名按行唯一（row:resume / row:random / row:<catid>），worker 对在途同名任务去重。
    public func loadBrowseRows(): Unit {
        if (api.isNone()) { return }
        let old = browseRows.value
        let rows = ArrayList<BrowseRow>()
        rows.add(findOrCreateRow(old, "resume", "继续阅读", ""))
        rows.add(findOrCreateRow(old, "random", "随机推荐", ""))
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
            if (r.requested) { continue }
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
            if (r.requested) { continue }
            runningRowTasks++
            submitRowTask(r)
        }
    }

    // 行任务落盘（dispatch 成功分支与 handleError 失败分支都调）：计数复位并补发下一批。
    private func onRowTaskFinished(): Unit {
        runningRowTasks--
        if (runningRowTasks < 0) { runningRowTasks = 0 }
        submitNextRowBatch()
    }

    private func findOrCreateRow(old: ArrayList<BrowseRow>, key: String, title: String, catid: String): BrowseRow {
        for (r in old) {
            if (r.key == key) { return r }
        }
        let r = BrowseRow()
        r.key = key
        r.title = title
        r.catid = catid
        r
    }

    private func submitRowTask(r: BrowseRow): Unit {
        let a = api ?? return
        r.requested = true
        r.loading = true
        r.failed = false
        if (r.key == "random") {
            let _ = worker.submit("row:random", {=> a.randomSearch(BROWSE_ROW_SIZE) })
        } else {
            // 继续阅读 = 最近阅读倒序；分类行 = 该分类默认序。两者都随「合集聚合」开关
            // 带 groupby_tanks（随机行走 randomSearch 独立接口，不参与聚合）。
            let q = SearchQuery()
            q.pageSize = BROWSE_ROW_SIZE
            q.groupbyTanks = tankGroupOn()
            if (r.key == "resume") {
                q.sortby = "lastread"
                q.order = "desc"
            } else {
                q.categoryId = r.catid
            }
            let _ = worker.submit("row:${r.key}", {=> a.search(q) })
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
            for (r in browseRows.value) { submitRowTask(r) }
            browseRows.value = browseRows.value
        } else {
            submitSearch(currentPage.value)
        }
    }

    // ---- 图片 ----

    // key → 原始编码字节的磁盘缓存（按服务器地址分目录），首次使用时创建。
    private var imageCache: ?ImageCache = None

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
                // 启动时后台按 2GB 阈值做一次 LRU 清理（spec §5.3）
                let _ = worker.submit("sweep", {=> c.sweep(2 * 1024 * 1024 * 1024); return true })
                return c
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

    // 图片并发硬上限 4（spec §6）：超出进队列，完成一个补一个。
    // 队列条目带优先级：高优先级（阅读当前页等）插到低优先级（封面/预取）排队条目之前，
    // 同优先级保持 FIFO。requestImage 与 pump 都在 UI 线程运行，计数无需加锁。
    private var activeImages: Int64 = 0
    private var imageQueue = ArrayList<(String, String, Bool)>() // (key, url, 高优先级?)

    // 已在途/已排队/已完成的 key 直接跳过（状态机去重，队列不会进重）；否则置 loading
    // 并提交 img:<key> 任务。key 约定：asset:<assetId>（封面/资产）与 page:<arcid>:<pagePath>。
    // highPriority：当前可见的关键图（阅读当前页）置 true，滚屏封面/预取用默认 false。
    public func requestImage(key: String, url: String, highPriority!: Bool = false): Unit {
        let st = imageState(key)
        if (st.value == "loading" || st.value == "ready") { return }
        st.value = "loading"
        if (activeImages >= 4) {
            if (highPriority) {
                // 插到最后一个高优先级条目之后（越过所有低优先级排队项）。
                var i: Int64 = 0
                while (i < imageQueue.size && imageQueue[i][2]) { i++ }
                let next = ArrayList<(String, String, Bool)>()
                for (j in 0..i) { next.add(imageQueue[j]) }
                next.add((key, url, true))
                for (j in i..imageQueue.size) { next.add(imageQueue[j]) }
                imageQueue = next
            } else {
                imageQueue.add((key, url, false))
            }
            return
        }
        startImageTask(key, url)
    }

    // 取消未开始的排队请求（滚出屏幕的封面等）：从队列移除并复位状态，
    // 之后重新可见时 requestImage 可再次入队。已开始/在途任务不干预——
    // 其完成结果落磁盘/staged 缓存无害。仅 UI 线程调用（同 requestImage/pump 纪律）。
    public func cancelImage(key: String): Unit {
        var i: Int64 = 0
        while (i < imageQueue.size) {
            if (imageQueue[i][0] == key) {
                let _ = imageQueue.remove(at: i)
                imageState(key).value = ""
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
        // 防御：page: 畸形 key（pagePath 缺分隔符）直接置 error 返回，
        // 避免切出空 arcid 发出必然 404 的请求（key 由内部生成，正常不会触发）。
        if (key.startsWith("page:") && key.removePrefix("page:").indexOf(":").isNone()) {
            imageState(key).value = "error"
            return
        }
        activeImages++
        let c = cache()
        let submitted = worker.submit("img:${key}", {=>
            let fetch = {=>
                if (key.startsWith("asset:")) {
                    return a.assetBytes(Int64.parse(key.removePrefix("asset:")))
                }
                if (key.startsWith("page:")) {
                    // page:<arcid>:<pagePath>（pagePath 本身可能含冒号，只切第一个）
                    let rest = key.removePrefix("page:")
                    let sep = rest.indexOf(":") ?? 0
                    return a.pageBytes(rest[0..sep], rest[(sep + 1)..rest.size])
                }
                throw Exception("未知图片 key: ${key}")
            }
            // 缓存原始字节 → 工作线程上 vips 按 key 档位缩小解码 RGBA；纹理创建留给
            // UI 线程首帧惰性完成。解码失败时 decodeCachedOrEvict 会先剔除坏缓存再抛出，
            // 重试可重新拉取。
            let path = c.ensureCached(key, fetch)
            let d = decodeCachedOrEvict(c, key, path, maxDimension: decodeMaxDimension(key))
            return (key, d)
        })
        // 同名任务在途时 submit 去重返回 false：回滚并发计数，否则旧任务只减一次导致额度泄漏。
        // 状态保持 loading，由在途任务完成时经 dispatch/finishImageTask 正常设置，
        // 因此 retryImage 打到在途 key 也无害（无需额外短路）。
        if (!submitted) { activeImages-- }
    }

    // 图片任务结束（成功或失败都调）：计数复位并补发队首（高优先级已在入队时排前）。
    private func finishImageTask(): Unit {
        activeImages--
        if (activeImages < 0) { activeImages = 0 }
        if (imageQueue.size > 0) {
            let (k, u, _) = imageQueue.remove(at: 0)
            startImageTask(k, u)
        }
    }

    public func retryImage(key: String, url: String): Unit {
        imageState(key).value = ""
        requestImage(key, url)
    }

    // ---- 详情/阅读（Task 9/10 的视图调用）----

    public func openDetail(arcid: String): Unit {
        // 离开阅读器（典型路径就是 Esc/← 详情）前把进度尾巴发掉（去重丢尾教训）；
        // 无 pending 时为空操作。
        reader.flushProgress()
        playback.stop()      // 离开阅读器停播（音频不带到详情页）
        lastLane = Book
        meta.value = None
        detailPages.value = ArrayList<PageInfo>()
        parentTanks.value = ArrayList<TankoubonInfo>()
        relatedItems.value = ArrayList<SearchItem>()
        page.value = Page.Detail(arcid)
        let a = api ?? return
        let _ = worker.submit("meta:${arcid}", {=> a.metadata(arcid) })
        // 辅助卡片数据（页面预览/所属合集/相关推荐）：失败静默，卡片无数据即隐藏。
        let _ = worker.submit("dfiles:${arcid}", {=> a.files(arcid) })
        let _ = worker.submit("ptanks:${arcid}", {=> a.listArchiveTankoubons(arcid) })
        let _ = worker.submit("related:${arcid}", {=> a.relatedArchives(arcid, 12) })
    }

    // 打开合集详情：元数据 + 成员档案 + 相关合集三路并发。
    public func openTank(tankid: String): Unit {
        tank.value = None
        tankMembers.value = ArrayList<SearchItem>()
        tankRelated.value = ArrayList<TankoubonInfo>()
        tankFilter.value = ""
        page.value = Page.Tank(tankid)
        let a = api ?? return
        let _ = worker.submit("tankmeta:${tankid}", {=> a.getTankoubon(tankid) })
        // 成员档案走 search?tankoubon_id=X&sortby=tank_order（对齐 frontend
        // tankoubon/page.tsx fetchArchives：合集内序、大 pageSize 一次取全）。
        let q = SearchQuery()
        q.tankoubonId = tankid
        q.sortby = "tank_order"
        q.order = "asc"
        q.pageSize = 10000
        let _ = worker.submit("tankmembers:${tankid}", {=> a.search(q) })
        let _ = worker.submit("tankrelated:${tankid}", {=> a.relatedTankoubons(tankid, 12) })
    }

    // 合集主操作：从首个成员档案开始阅读（按钮在无成员时禁用，不会空调用）。
    public func startTankReading(): Unit {
        let members = tankMembers.value
        if (members.size == 0) { return }
        openReader(members[0].arcid, 1)
    }

    // backdrop 模糊背景：元数据到货后，若有封面则提交 worker 任务，将封面缩到 ~256px 宽
    // 并经 vips 高斯模糊后解码为 RGBA 像素，供 detail_view 以 PixelImageView 放大为背景。
    // 失败静默（不 toast，不阻塞页面），backdrop 区域回退为纯色渐变。
    private func requestBackdrop(arcid: String, assetId: Int64): Unit {
        let a = api ?? return
        let imgKey = "backdrop:${arcid}"
        let c = cache()
        let _ = worker.submit(imgKey, {=>
            let fetch = {=> a.assetBytes(assetId) }
            let path = c.ensureCached(imgKey, fetch)
            let d = decodeBackdrop(path, 256)
            return (imgKey, d)
        })
    }

    public func openReader(arcid: String, startPage: Int64): Unit {
        playback.stop()      // 换档案/重进阅读器：停掉上一媒体（旧进程不得泄漏）
        lastLane = Book      // 与 reader.open 的 activeLane=Book 复位对齐
        readerArcid = arcid
        pages.value = ArrayList<PageInfo>()
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
        page.value = Page.Reader(arcid, startPage)
        let a = api ?? return
        let _ = worker.submit("files:${arcid}", {=> a.files(arcid) })
        // 顶栏标题与收藏态（reader-redesign #topbar）：复用元数据通道。
        let _ = worker.submit("meta:${arcid}", {=> a.metadata(arcid) })
    }

    // 翻到显示页码 n（1 基）：seamlessNext 开 = 当前 segment 内页码，关 = 全局页码
    //（对齐 frontend slider 语义）；流索引换算在 ReaderModel.gotoDisplayPage 内。
    public func gotoPage(n: Int64): Unit {
        reader.gotoDisplayPage(n - 1)
        readerIndex.value = reader.displayPage
        readerPageSlider.value = Float32(reader.displayPage)
    }

    // dock Book lane 的 ‹ ›：按阅读顺序步进一个 spread（方向换算不需要——dock 按钮
    // 语义就是「上一页/下一页」逻辑方向）。镜像同步与版本广播同 readerKeyTurn。
    public func readerTurnPage(forward: Bool): Unit {
        reader.turnPage(forward)
        readerIndex.value = reader.displayPage
        readerPageSlider.value = Float32(reader.displayPage)
        readerVersion.value += 1
    }

    // 方向键翻页（T2 阅读舞台接线）：cui Key 已在视图层映射为 KeyCode，方向换算
    //（RTL 反转/TTB 上下/webtoon 不响应）全部在 ReaderModel.keyDirection 内；
    // None（webtoon/无效键）自然不翻页。命中后同步 1 基镜像并 bump readerVersion——
    // 舞台的自绘翻页动画靠 readerVersion 触发的重建检测 index 变化。
    public func readerKeyTurn(key: KeyCode): Unit {
        match (reader.keyDirection(key)) {
            case Some(forward) =>
                reader.turnPage(forward)
                readerIndex.value = reader.displayPage
                readerPageSlider.value = Float32(reader.displayPage)
                readerVersion.value += 1
            case None => ()
        }
    }

    // 进度回传：PUT /api/archives/:id/progress/:page，任务名 progress（失败静默，见 handleError）。
    // 兼容委托：翻页上报已由 ReaderModel 防抖管线接管，这里把 pending 尾巴立即发出即可。
    public func reportProgress(): Unit {
        reader.flushProgress()
    }

    // 预取当前页前后各 2 页（经图片管线，并发上限由 requestImage 保证）。
    public func prefetchAround(): Unit {
        let total = pages.value.size
        let cur = readerIndex.value
        for (d in [-2, -1, 1, 2]) {
            let idx = cur + d
            if (idx >= 1 && idx <= total) {
                let pid = pages.value[idx - 1].id
                requestImage("page:${readerArcid}:${pid}", "/api/archives/${readerArcid}/page?path=${percentEncode(pid)}")
            }
        }
    }

    // ---- 阅读器顶栏（T13：reader-redesign #topbar）----
    // ReaderModel 是纯逻辑类（属性非 State），影响 UI 的变更经 readerVersion 通知视图重建：
    // 顶栏/阅读页先读 readerVersion.value 订阅，再读 reader.* 普通属性。
    public let readerVersion = State<Int64>(0)
    // chrome 可见性镜像（pump 比对同步；autoHide 超时/open 复位等非视图路径的兜底出口）。
    private var lastChromeSync: Bool = true
    // lane 镜像（pump 比对同步）：ReaderModel.refreshLaneForSpread 自动激活媒体 lane
    // 时不经过 syncReaderLane，靠它在下一帧补上播放联动。
    private var lastLane: LaneId = Book
    // 自动播放计时：上次自动翻页（或开关/间隔变更）的时钟读数（reader.clock 基准）。
    private var lastAutoPlayTurnMs: Int64 = 0
    // ---- 无缝续读：下一档案解析/拼接状态 ----
    private var appendInFlight = false        // 解析/拼接在途（防重；openReader 复位）
    private var appendResolvedFrom = ""       // 已完成解析链的源 arcid（成败都记，避免重复打）
    private var readerNextId = ""             // 候选档案 id（""=未解析到）
    public var readerNextCoverKey = ""        // 候选封面 asset key（""=无；结束页卡片用）
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
        if (reader.chromeVisible != before) { readerVersion.value += 1 }
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
        if (readerSettingsOpen.value) { readerSidebarOpen.value = false }
    }

    public func toggleReaderSidebar(): Unit {
        readerSidebarOpen.value = !readerSidebarOpen.value
        if (readerSidebarOpen.value) { readerSettingsOpen.value = false }
    }

    public func closeReaderPanels(): Unit {
        readerSettingsOpen.value = false
        readerSidebarOpen.value = false
    }

    // 信息浮层开关：写 settings 并落盘（与 reader.onPersist 同款 saveSettingsTo）。
    public func toggleReaderShowInfo(): Unit {
        readerShowInfo.value = !readerShowInfo.value
        settings.readerShowInfo = readerShowInfo.value
        saveSettingsTo(defaultSettingsPath(), settings)
    }

    // ---- 阅读选项的 UI 入口：委托 ReaderModel 持久化，bump readerVersion 通知视图 ----

    public func setReadingMode(m: ReadingMode): Unit {
        reader.setMode(m)
        readerVersion.value += 1
    }
    public func toggleReaderDoublePage(): Unit {
        reader.setDoublePage(!reader.doublePage)
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

    // ---- lane ⇄ 播放同步 ----

    // UI 手动切 lane：状态机校验 + 播放联动（pump 的 lastLane 镜像同步更新，
    // 避免下一帧被当成「自动激活」再同步一次）。
    public func syncReaderLane(l: LaneId): Unit {
        reader.setActiveLane(l)
        lastLane = l
        syncPlaybackToLane(l)
        readerVersion.value += 1
    }

    // ---- 无缝续读：下一档案解析与拼接 ----

    // 候选是否已解析到（结束页「打开下一档案」按钮使能判定）。
    public func hasNextCandidate(): Bool {
        readerNextId.size > 0
    }

    // 结束页「打开下一档案」：候选已解析时整档打开（openReader 会复位拼接状态）。
    public func openReaderNext(): Unit {
        if (readerNextId.size == 0) { return }
        openReader(readerNextId, 1)
    }

    // 进入末尾虚拟页触发（ReaderModel.onAppendNext 出口）：
    // 解析候选（档案在合集 → 合集内下一章；否则 relatedArchives 第一个未拼过的），
    // seamlessNext 开时继续取页表自动拼接，关时只展示候选。worker 线程跑，drain 回填。
    private func startAppendNext(arcid: String): Unit {
        if (appendInFlight || appendResolvedFrom == arcid) { return }
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
        let _ = worker.submit("next.resolve", {=>
            var candidate: ?(String, String, Int64) = None
            let tanks = a.listArchiveTankoubons(arcid)
            if (tanks.size > 0) {
                // 合集内按 tank_order 找当前档案的下一章（跳过已拼接的）。
                let q = SearchQuery()
                q.tankoubonId = tanks[0].id
                q.sortby = "tank_order"
                q.order = "asc"
                q.pageSize = 10000
                let members = a.search(q).items
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
                for (r in a.relatedArchives(arcid, 10)) {
                    if (!appended.contains(r.arcid)) {
                        candidate = Some((r.arcid, r.title, r.coverAssetId))
                        break
                    }
                }
            }
            (arcid, seamless, candidate)
        })
    }

    // lane → 播放联动：Audio lane 加载对应媒体页（下载+ffplay 在 PlaybackModel 内）；
    // Book lane 停播。Video lane 本阶段不触发播放——视频播放后续接入（UI 侧另行处理）。
    private func syncPlaybackToLane(l: LaneId): Unit {
        match (l) {
            case Audio(i) =>
                match (reader.pageAt(i)) {
                    case Some(p) => playback.load(reader.arcidOfReal(i), i, p.id)
                    case None => ()
                }
            case Book => playback.stop()
            case Video(_) => () // 视频播放先不做（范围调整），留待后续任务
        }
    }

    // 顶栏 ♥：切换当前档案收藏；元数据未到货（arcid 不匹配）时忽略，完成后由 dispatch 刷新 meta。
    public func toggleReaderFavorite(): Unit {
        match (meta.value) {
            case Some(m) => if (m.arcid == readerArcid) { toggleFavorite(readerArcid, !m.isfavorite) }
            case None => ()
        }
    }

    // 重取详情元数据（收藏/未读切换成功后由 dispatch 触发刷新）。
    public func refreshMeta(arcid: String): Unit {
        let a = api ?? return
        let _ = worker.submit("meta:${arcid}", {=> a.metadata(arcid) })
    }

    public func toggleFavorite(arcid: String, fav: Bool): Unit {
        let a = api ?? return
        let _ = worker.submit("favorite:${arcid}", {=>
            a.setFavorite(arcid, fav)
            return fav
        })
    }

    // 首页卡片收藏 chip（Task 9）：乐观翻转 items/browseRows 里所有同 arcid 条目并立即重绘；
    // 失败由 handleError 统一 toast（不回滚，下次行/网格数据到货自愈）。
    public func toggleFavoriteOnCard(arcid: String): Unit {
        var target = false
        var found = false
        for (it in items.value) {
            if (it.arcid == arcid) { found = true; target = !it.isfavorite; it.isfavorite = target }
        }
        for (row in browseRows.value) {
            for (it in row.items) {
                if (it.arcid == arcid) { found = true; target = !it.isfavorite; it.isfavorite = target }
            }
        }
        if (!found) { return }
        items.value = items.value
        browseRows.value = browseRows.value
        toggleFavorite(arcid, target)
    }

    public func toggleIsNew(arcid: String, isNew: Bool): Unit {
        let a = api ?? return
        let _ = worker.submit("isnew:${arcid}", {=>
            a.setIsNew(arcid, isNew)
            return isNew
        })
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

    // 切换主题：更新设置、落盘，再经注入回调应用到运行中的 DesktopApp（即切即生效）。
    public func setTheme(mode: String): Unit {
        if (mode != "dark" && mode != "light") { return }
        settings.theme = mode
        saveSettingsTo(defaultSettingsPath(), settings)
        if (let Some(h) <- themeChangeHandler) { h(mode) }
    }

    // ---- 设置页 ----

    // 拉取服务器信息（结果经 dispatch 的 "info" 分支写入 serverInfo）。
    public func loadServerInfo(): Unit {
        let a = api ?? return
        let _ = worker.submit("info", {=> a.info() })
    }

    // 同步读磁盘缓存总量刷新展示（设置页进场与清理后调用）。
    public func refreshCacheInfo(): Unit {
        let bytes = cache().totalBytes()
        cacheInfo.value = "图片缓存 ${bytes / 1048576} MB"
    }

    // 清图片缓存：磁盘目录 + cui 纹理缓存（路径纹理 + 像素纹理）+ imageStates 三处一起复位。
    // 注意命名：cui 有全局 clearImageCache()（路径纹理缓存），model 方法起名 clearCache 避免遮蔽歧义。
    public func clearCache(): Unit {
        cache().clear()
        clearImageCache()    // cui 路径纹理缓存（按文件路径解码的 GPU 纹理）
        clearPixelImages()   // cui 像素纹理缓存（含已建纹理与 staged 像素）
        synchronized(imageMutex) { imageStates.clear() }
        refreshCacheInfo()
        toaster.show("缓存已清理", kind: ToastKind.Success)
    }

    // 封面圆角（asset: key 专用）：框架渲染器只有矩形裁剪，纹理无法在绘制期切圆角；
    // 在登记像素前把四角（半径≈7.2% 短边——首页 168vp 封面 ≈12vp、详情 hero 200vp ≈14vp，
    // 对齐原型 .card .cover/.cover-big 的 12/14px，1px 羽化）以外的像素 alpha 清零——
    // 纹理混合模式下透明角露出页面底，得到真圆角封面。阅读页（page: key）不处理。
    private func roundCoverCorners(d: DecodedImage): Unit {
        let w = Int64(d.width)
        let h = Int64(d.height)
        let r = Float64(min(w, h)) * 0.072
        if (r < 2.0) { return }
        let ri = Int64(r) + 1
        for (cy in 0..ri) {
            for (cx in 0..ri) {
                // 角弧圆心在各角内侧 (r, r) 处；dist > r 的像素在圆角之外。
                let dist = sqrt((r - Float64(cx)) * (r - Float64(cx)) +
                    (r - Float64(cy)) * (r - Float64(cy)))
                if (dist > r + 0.5) {
                    setCornerAlpha(d, cx, cy, w, h, 0u8)
                } else if (dist > r - 0.5) {
                    // 1px 羽化带：按覆盖率衰减 alpha，边缘无锯齿。
                    let coverage = r + 0.5 - dist
                    setCornerAlphaScaled(d, cx, cy, w, h, coverage)
                }
            }
        }
    }

    // 四角镜像像素的 alpha 置为给定值。
    private func setCornerAlpha(d: DecodedImage, cx: Int64, cy: Int64, w: Int64, h: Int64, a: UInt8): Unit {
        let xs = [cx, w - 1 - cx]
        let ys = [cy, h - 1 - cy]
        for (y in ys) {
            for (x in xs) {
                d.pixels[(y * w + x) * 4 + 3] = a
            }
        }
    }

    // 四角镜像像素的 alpha 按覆盖率缩放（羽化）。
    private func setCornerAlphaScaled(d: DecodedImage, cx: Int64, cy: Int64, w: Int64, h: Int64,
        coverage: Float64): Unit {
        let xs = [cx, w - 1 - cx]
        let ys = [cy, h - 1 - cy]
        for (y in ys) {
            for (x in xs) {
                let i = (y * w + x) * 4 + 3
                d.pixels[i] = UInt8(Float64(d.pixels[i]) * coverage)
            }
        }
    }

    // ---- 每帧泵：把工作线程结果写回 State（UI 线程）----

    public func pump(): Unit {
        reader.tick() // 进度防抖周期驱动：窗口到点补发 pending 尾巴
        // chrome 自动隐藏计时（T13）：autoHide 开且 READER_CHROME_AUTOHIDE_MS 无活动则隐藏
        // 顶栏，仅在阅读页生效（离开阅读器后 reader 状态闲置，不应静默翻转）。
        match (page.value) {
            case Page.Reader(_, _) =>
                if (reader.autoHide && reader.chromeVisible &&
                    reader.clock() - reader.lastActivityMs >= READER_CHROME_AUTOHIDE_MS) {
                    reader.toggleChrome()
                }
            case _ => ()
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
        // lane 镜像：翻 spread 时 ReaderModel.refreshLaneForSpread 会自动激活媒体 lane
        //（不经过 syncReaderLane），这里比对出变化后补同一套播放联动。
        if (!reader.activeLane.equals(lastLane)) {
            lastLane = reader.activeLane
            syncPlaybackToLane(lastLane)
            readerVersion.value += 1
        }
        let results = worker.drain()
        for (r in results) {
            if (r.error.size > 0) { handleError(r); continue }
            dispatch(r)
        }
    }

    private func handleError(r: ApiResult): Unit {
        // 图片任务失败不 toast，只置 error 态并补发队列。
        if (r.name.startsWith("img:")) {
            finishImageTask()
            imageState(r.name.removePrefix("img:")).value = "error"
            return
        }
        if (r.name == "sweep" || r.name == "progress") {
            return  // 后台维护类任务失败不打扰用户
        }
        // backdrop 解码失败静默（不 toast，不阻塞页面），backdrop 区域回退为纯色渐变。
        if (r.name.startsWith("backdrop:")) {
            return
        }
        // 续读解析/拼接失败：结束页落「没有下一档案」态（不 toast，阅读器内联展示）。
        if (r.name == "next.resolve" || r.name.startsWith("next.files")) {
            appendInFlight = false
            reader.appendNextFailed("没有下一档案了")
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
            onRowTaskFinished()  // 失败也算落盘：补发下一批分类行
            return
        }
        // 详情辅助卡片（页面预览/所属合集/相关推荐）失败静默：卡片无数据即隐藏；
        // 401/会话失效仍走全局 logout + 提示（同 row: 分支惯例）。
        if (r.name.startsWith("dfiles:") || r.name.startsWith("ptanks:") ||
            r.name.startsWith("related:") || r.name.startsWith("tankrelated:")) {
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
            saveSettingsTo(defaultSettingsPath(), settings)
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
        if (r.name == "login") { loading.value = false }
        if (r.name == "search") { loading.value = false }
        // 登录任务的 401 是“用户名或密码错误”而非会话失效，不做 logout（本就未登录）。
        if (r.name != "login" && (r.error.contains("失效") || r.error.contains("401"))) {
            logout()
        }
        showError(r.error)
    }

    private func dispatch(r: ApiResult): Unit {
        let name = r.name
        if (name == "login" || name == "login-totp") {
            loading.value = false
            match (r.payload) {
                case Some(p) =>
                    let (a, d, sid, cid) = (p as (LanluApi, LoginData, String, String)).getOrThrow()
                    if (cid.size > 0) {
                        // 202 挑战：切 TOTP 表单，等待 verifyTotp 提交。
                        totpChallengeId.value = cid
                    } else {
                        totpChallengeId.value = ""
                        api = a
                        match (settings.profileById(sid)) {
                            case Some(prof) =>
                                prof.token = d.token
                                prof.username = d.username
                                prof.lastUsedAt = nowLabel()
                                settings.activeServerId = sid
                            case None => ()
                        }
                        saveSettingsTo(defaultSettingsPath(), settings)
                        // 换服登录必须复位图片缓存：缓存目录按 serverUrl 派生，而 imageStates
                        // 的 key（asset:42 等）与服务器无关，不复位会把旧服务器的图误判为
                        // “已加载”，新下载也会落进旧目录。
                        imageCache = None
                        synchronized(imageMutex) { imageStates.clear() }
                        isAdmin.value = d.isAdmin
                        page.value = Page.Library
                        loadCategories()
                        loadBrowseRows()
                    }
                case None => ()
            }
        } else if (name == "testconn") {
            testConnResult.value = "ok"
        } else if (name.startsWith("probe:")) {
            // 探测成功：任务载荷即服务器 id（见 probeServers）。
            match (r.payload) {
                case Some(p) => probeState((p as String).getOrThrow()).value = "online"
                case None => ()
            }
        } else if (name == "me") {
            // 静默恢复成功同样视为一次使用：刷新 lastUsedAt 并置 active，
            // 否则"最后使用的服务器"与实际不符（按服务器各存会话语义）。
            match (selectedProfile()) {
                case Some(prof) =>
                    prof.lastUsedAt = nowLabel()
                    settings.activeServerId = prof.id
                    saveSettingsTo(defaultSettingsPath(), settings)
                case None => ()
            }
            // me() 返回同 LoginData 结构：同步管理员标记（控制设置页「服务器」分组显隐）。
            match (r.payload) {
                case Some(p) => isAdmin.value = (p as LoginData).getOrThrow().isAdmin
                case None => ()
            }
            page.value = Page.Library
            loadCategories()
            loadBrowseRows()
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
        } else if (name == "set.overview") {
            match (r.payload) {
                case Some(p) =>
                    let (stats, trend, read, fav) = (p as (UserStats, ArrayList<TrendPoint>, ArrayList<SearchItem>, ArrayList<SearchItem>)).getOrThrow()
                    userStats.value = stats
                    userTrend.value = trend
                    recentRead.value = read
                    recentFav.value = fav
                case None => ()
            }
        } else if (name == "set.cloud") {
            match (r.payload) { case Some(p) => tagCloud.value = (p as ArrayList<CloudTag>).getOrThrow(); case None => () }
        } else if (name == "set.users") {
            match (r.payload) { case Some(p) => adminUsers.value = (p as ArrayList<AdminUserItem>).getOrThrow(); case None => () }
        } else if (name == "set.sys") {
            match (r.payload) { case Some(p) => sysSettings.value = (p as ArrayList<SysSetting>).getOrThrow(); case None => () }
        } else if (name == "set.cats") {
            match (r.payload) { case Some(p) => adminCategories.value = (p as ArrayList<AdminCategoryItem>).getOrThrow(); case None => () }
        } else if (name.startsWith("set.tags")) {
            match (r.payload) { case Some(p) => tagPage.value = (p as TagListPage).getOrThrow(); case None => () }
        } else if (name == "set.tagns") {
            match (r.payload) { case Some(p) => tagNs.value = (p as ArrayList<String>).getOrThrow(); case None => () }
        } else if (name == "set.filters") {
            match (r.payload) { case Some(p) => smartFilters.value = (p as ArrayList<SmartFilterItem>).getOrThrow(); case None => () }
        } else if (name.startsWith("set.tasks")) {
            match (r.payload) { case Some(p) => taskPage.value = (p as TaskListPage).getOrThrow(); case None => () }
        } else if (name == "set.cron") {
            match (r.payload) {
                case Some(p) =>
                    let (st, tasks) = (p as (CronStatus, ArrayList<CronTask>)).getOrThrow()
                    cronStatus.value = st
                    cronTasks.value = tasks
                case None => ()
            }
        } else if (name == "set.plugins") {
            match (r.payload) { case Some(p) => plugins.value = (p as ArrayList<PluginItem>).getOrThrow(); case None => () }
        } else if (name == "set.security") {
            match (r.payload) {
                case Some(p) =>
                    let (se, tk, pk, tp) = (p as (ArrayList<SessionItem>, ArrayList<TokenItem>, ArrayList<PasskeyItem>, TotpStatus)).getOrThrow()
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
            if (name.startsWith("act.user")) { loadAdminUsers() }
            else if (name.startsWith("act.sys")) { loadSysSettings() }
            else if (name.startsWith("act.cat")) { loadAdminCategories() }
            // act.tag 只 toast，不在此 reload（避免清空筛选条件），由视图侧确认回调触发按当前筛选重拉。
            else if (name.startsWith("act.filter")) { loadSmartFilters() }
            else if (name.startsWith("act.task")) { loadTasks("all") }
            else if (name.startsWith("act.cron")) { loadCron() }
            else if (name.startsWith("act.plugin")) { loadPlugins() }
            else if (name.startsWith("act.cred") || name.startsWith("act.totp") ||
                     name.startsWith("act.session") || name.startsWith("act.token") ||
                     name.startsWith("act.passkey")) {
                // 改名成功：同步本地会话用户名并落盘，避免顶栏/会话仍是旧名。
                if (name == "act.cred" && pendingCredUsername.size > 0) {
                    settings.username = pendingCredUsername
                    match (settings.activeProfile()) {
                        case Some(p) => p.username = pendingCredUsername
                        case None => ()
                    }
                    saveSettingsTo(defaultSettingsPath(), settings)
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
            onRowTaskFinished()  // 本批落盘：补发下一批分类行
        } else if (name.startsWith("meta:")) {
            match (r.payload) {
                case Some(p) =>
                    // 迟到结果对号入座：详情页已从 A 切到 B 时，A 的元数据不得覆盖 B 的页面。
                    // arcid 取任务名（一定等于请求目标），不依赖响应体回传字段。
                    let arcid = name.removePrefix("meta:")
                    match (page.value) {
                        case Page.Detail(cur) => if (arcid == cur) {
                            let m = (p as ArchiveMeta).getOrThrow()
                            meta.value = Some(m)
                            // 元数据到货后，若有封面则提交 backdrop 解码任务（模糊背景用）。
                            if (m.coverAssetId > 0) {
                                requestBackdrop(arcid, m.coverAssetId)
                            }
                        }
                        // 阅读器顶栏只要标题/收藏态，不请求 backdrop；
                        // 顺手回填 segment 标题（结束页卡片「已读完《X》」用）。
                        case Page.Reader(cur, _) => if (arcid == cur) {
                            let m = (p as ArchiveMeta).getOrThrow()
                            meta.value = Some(m)
                            reader.setSegmentTitle(arcid, m.title)
                        }
                        case _ => ()
                    }
                case None => ()
            }
        } else if (name.startsWith("dfiles:")) {
            match (r.payload) {
                case Some(p) =>
                    // 迟到结果对号入座（同 meta: 分支）：仅当前详情页匹配时才写页面预览页表。
                    let arcid = name.removePrefix("dfiles:")
                    match (page.value) {
                        case Page.Detail(cur) => if (arcid == cur) {
                            detailPages.value = (p as ArrayList<PageInfo>).getOrThrow()
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
                        case Page.Detail(cur) => if (arcid == cur) {
                            parentTanks.value = (p as ArrayList<TankoubonInfo>).getOrThrow()
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
                        case Page.Detail(cur) => if (arcid == cur) {
                            relatedItems.value = (p as ArrayList<SearchItem>).getOrThrow()
                        }
                        case _ => ()
                    }
                case None => ()
            }
        } else if (name.startsWith("tankmeta:")) {
            match (r.payload) {
                case Some(p) =>
                    let tankid = name.removePrefix("tankmeta:")
                    match (page.value) {
                        case Page.Tank(cur) => if (tankid == cur) {
                            let t = (p as TankoubonInfo).getOrThrow()
                            tank.value = Some(t)
                            // 合集 backdrop：复用封面资产解码（key 前缀 tank: 避免与档案冲突）。
                            if (t.coverAssetId > 0) {
                                requestBackdrop("tank:${tankid}", t.coverAssetId)
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
                        case Page.Tank(cur) => if (tankid == cur) {
                            tankMembers.value = (p as SearchPage).getOrThrow().items
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
                        case Page.Tank(cur) => if (tankid == cur) {
                            tankRelated.value = (p as ArrayList<TankoubonInfo>).getOrThrow()
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
                                let list = (p as ArrayList<PageInfo>).getOrThrow()
                                pages.value = list
                                // 起始页来自可能过期的 progress；页表到货钳制+spread 吸附
                                // 在 ReaderModel 内完成，readerIndex 同步回 1 基。
                                reader.setPages(list)
                                readerIndex.value = reader.displayPage
                                readerPageSlider.value = Float32(reader.displayPage)
                            }
                        case _ => ()
                    }
                case None => ()
            }
        } else if (name.startsWith("favorite:") || name.startsWith("isnew:")) {
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
        } else if (name.startsWith("img:")) {
            finishImageTask()
            let key = name.removePrefix("img:")
            match (r.payload) {
                case Some(p) =>
                    // 像素已在工作线程解好；这里只登记 staged 像素（UI 线程），
                    // 纹理由 PixelImageView 首帧绘制时惰性创建。
                    let (k, d) = (p as (String, DecodedImage)).getOrThrow()
                    if (k.startsWith("asset:")) { roundCoverCorners(d) }
                    stagePixelImage(k, d.width, d.height, d.pixels)
                    imageState(k).value = "ready"
                case None => imageState(key).value = "error"
            }
        } else if (name.startsWith("backdrop:")) {
            // backdrop 解码到货：直接 stage 像素（不经过 img 管线，不需圆角），失败静默。
            match (r.payload) {
                case Some(p) =>
                    let (k, d) = (p as (String, DecodedImage)).getOrThrow()
                    stagePixelImage(k, d.width, d.height, d.pixels)
                case None => ()
            }
        } else if (name.startsWith("playback:")) {
            // 媒体下载到货：回填 PlaybackModel（key 对号入座，迟到结果由模型内丢弃）。
            match (r.payload) {
                case Some(p) =>
                    // 载荷 (key, path, durationSec)：时长由 worker 内 ffprobe 探得（0=未知）。
                    let (key, path, dur) = (p as (String, String, Float64)).getOrThrow()
                    playback.onDownloaded(key, path)
                    playback.durationSec = dur
                    readerVersion.value += 1
                case None => ()
            }
        } else if (name == "next.resolve") {
            // 候选解析到货：无候选 → 失败态；有候选 → 记录（卡片展示）；
            // seamlessNext 开时继续取页表自动拼接。
            appendInFlight = false
            match (r.payload) {
                case Some(p) =>
                    let (fromArc, seamless, candidate) =
                        (p as (String, Bool, ?(String, String, Int64))).getOrThrow()
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
                                        let _ = worker.submit("next.files:${id}", {=>
                                            (id, title, a.files(id))
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
                    let (id, title, list) = (p as (String, String, ArrayList<PageInfo>)).getOrThrow()
                    if (list.size == 0) {
                        reader.appendNextFailed("没有下一档案了")
                    } else {
                        reader.appendArchive(id, title, list)
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
        let _ = worker.submit("set.overview", {=>
            let stats = a.userStats()
            let trend = a.userTrend(30)
            let qr = SearchQuery()
            qr.sortby = "lastread"
            qr.order = "desc"
            qr.pageSize = 3
            let read = a.search(qr).items
            let qf = SearchQuery()
            qf.sortby = "lastread"
            qf.order = "desc"
            qf.favoriteonly = true
            qf.pageSize = 3
            let fav = a.search(qf).items
            (stats, trend, read, fav)
        })
    }

    public func loadTagCloud(): Unit {
        let a = api ?? return
        let _ = worker.submit("set.cloud", {=> a.tagCloud(200) })
    }

    public func loadAdminUsers(): Unit {
        let a = api ?? return
        let _ = worker.submit("set.users", {=> a.adminUsers() })
    }

    public func loadSysSettings(): Unit {
        let a = api ?? return
        let _ = worker.submit("set.sys", {=> a.systemSettings() })
    }

    public func loadAdminCategories(): Unit {
        let a = api ?? return
        let _ = worker.submit("set.cats", {=> a.adminCategories() })
    }

    public func loadTagPage(q: String, ns: String, offset: Int64): Unit {
        let a = api ?? return
        // 任务名带筛选参数，避免快速切换筛选时后一次请求被同名去重静默丢弃。
        let _ = worker.submit("set.tags:${q}:${ns}:${offset}", {=> a.adminTagPage(q, ns, offset, 20) })
    }

    public func loadTagNamespaces(): Unit {
        let a = api ?? return
        let _ = worker.submit("set.tagns", {=> a.adminTagNamespaces() })
    }

    public func loadSmartFilters(): Unit {
        let a = api ?? return
        let _ = worker.submit("set.filters", {=> a.smartFilters() })
    }

    public func loadTasks(status: String): Unit {
        let a = api ?? return
        let _ = worker.submit("set.tasks:${status}", {=> a.taskListSnapshot(status, 1, 10) })
    }

    public func loadCron(): Unit {
        let a = api ?? return
        let _ = worker.submit("set.cron", {=> (a.cronStatus(), a.cronTasks()) })
    }

    public func loadPlugins(): Unit {
        let a = api ?? return
        let _ = worker.submit("set.plugins", {=> a.plugins() })
    }

    // 账户安全四路数据打包一路返回（dispatch 解包写四个 State）。
    public func loadAuthSecurity(): Unit {
        let a = api ?? return
        let _ = worker.submit("set.security", {=>
            (a.listSessions(), a.listTokens(), a.listPasskeys(), a.totpStatus())
        })
    }

    // ==================== 设置区扩展：写操作 ====================
    // 统一模式：worker 执行 → 成功 toast + 按任务名 reload 对应板块（见 dispatch 的 act.* 分支）；
    // 失败走 handleError。submitAct 不传闭包，reload 由 dispatch 按任务名前缀触发。

    private func submitAct(name: String, okToast: String, job: () -> Any): Unit {
        let _ = worker.submit(name, {=>
            job()
            okToast
        })
    }

    // ---- 用户管理 ----
    public func actCreateUser(username: String, admin: Bool): Unit {
        let a = api ?? return
        let _ = worker.submit("act.user.create", {=> "用户创建成功 \"${username}\"，生成密码: ${a.adminCreateUser(username, admin)}" })
    }
    public func actDeleteUser(id: Int64): Unit {
        let a = api ?? return
        let _ = submitAct("act.user.del", "用户已删除", {=> a.adminDeleteUser(id); "" })
    }
    public func actSetUserRole(id: Int64, admin: Bool): Unit {
        let a = api ?? return
        let _ = submitAct("act.user.role", "角色已更新", {=> a.adminSetUserRole(id, admin); "" })
    }
    public func actResetUserPassword(id: Int64, pw: String): Unit {
        let a = api ?? return
        let _ = submitAct("act.user.resetpw", "密码已重置", {=> a.adminResetUserPassword(id, pw); "" })
    }

    // ---- 系统设置 ----
    public func actSaveSysSettings(entries: ArrayList<(String, String)>): Unit {
        let a = api ?? return
        let _ = submitAct("act.sys.save", "设置已保存", {=> a.saveSystemSettings(entries); "" })
    }

    // ---- 分类管理 ----
    public func actToggleCategory(catid: String, enabled: Bool): Unit {
        let a = api ?? return
        let _ = submitAct("act.cat.toggle", "分类已更新", {=>
            a.updateCategory(catid, "{\"enabled\":${enabled}}")
            ""
        })
    }
    public func actDeleteCategory(catid: String): Unit {
        let a = api ?? return
        let _ = submitAct("act.cat.del", "分类已删除", {=> a.deleteCategory(catid); "" })
    }
    public func actScanCategory(catid: String): Unit {
        let a = api ?? return
        let _ = submitAct("act.cat.scan", "已提交分类扫描任务", {=> a.scanCategory(catid); "" })
    }
    public func actScanAllCategories(): Unit {
        let a = api ?? return
        let _ = submitAct("act.cat.scanall", "已提交全库扫描任务", {=> a.scanAllCategories(); "" })
    }
    public func actSaveCategory(catid: String, jsonBody: String): Unit {
        if (catid.size == 0) {
            let a = api ?? return
            let _ = submitAct("act.cat.save", "分类已创建", {=> a.createCategory(jsonBody); "" })
        } else {
            let a = api ?? return
            let _ = submitAct("act.cat.save", "分类已保存", {=> a.updateCategory(catid, jsonBody); "" })
        }
    }

    // ---- 标签管理 ----
    public func actSaveTag(id: Int64, jsonBody: String): Unit {
        if (id == 0) {
            let a = api ?? return
            let _ = submitAct("act.tag.save", "标签已创建", {=> a.createTag(jsonBody); "" })
        } else {
            let a = api ?? return
            let _ = submitAct("act.tag.save", "标签已保存", {=> a.updateTag(id, jsonBody); "" })
        }
    }
    public func actDeleteTag(id: Int64): Unit {
        let a = api ?? return
        let _ = submitAct("act.tag.del", "标签已删除", {=> a.deleteTag(id); "" })
    }

    // ---- 智能分类 ----
    public func actToggleFilter(id: Int64): Unit {
        let a = api ?? return
        let _ = submitAct("act.filter.toggle", "已更新", {=> a.toggleSmartFilter(id); "" })
    }
    public func actDeleteFilter(id: Int64): Unit {
        let a = api ?? return
        let _ = submitAct("act.filter.del", "删除成功", {=> a.deleteSmartFilter(id); "" })
    }
    public func actSaveFilter(id: Int64, jsonBody: String): Unit {
        if (id == 0) {
            let a = api ?? return
            let _ = submitAct("act.filter.save", "智能分类已创建", {=> a.createSmartFilter(jsonBody); "" })
        } else {
            let a = api ?? return
            let _ = submitAct("act.filter.save", "智能分类已保存", {=> a.updateSmartFilter(id, jsonBody); "" })
        }
    }
    // 上移/下移：先在本地 State 换序（立即反馈），再提交全量顺序。
    public func actMoveFilter(id: Int64, up: Bool): Unit {
        let a = api ?? return
        let list = smartFilters.value
        var idx = -1
        for (i in 0..list.size) { if (list[i].id == id) { idx = i; break } }
        let target = if (up) { idx - 1 } else { idx + 1 }
        if (idx < 0 || target < 0 || target >= list.size) { return }
        let tmp = list[idx]
        list[idx] = list[target]
        list[target] = tmp
        smartFilters.value = list   // 整体重赋值推进 State 代次
        let ids = ArrayList<Int64>()
        for (f in list) { ids.add(f.id) }
        let _ = submitAct("act.filter.reorder", "顺序已保存", {=> a.reorderSmartFilters(ids); "" })
    }

    // ---- 任务记录 ----
    public func actCancelTask(id: Int64): Unit {
        let a = api ?? return
        let _ = submitAct("act.task.cancel", "任务已取消", {=> a.cancelTask(id); "" })
    }
    public func actRetryTask(id: Int64): Unit {
        let a = api ?? return
        let _ = submitAct("act.task.retry", "已重新加入任务队列", {=> a.retryTask(id); "" })
    }

    // ---- 定时任务 ----
    public func actCronServiceToggle(): Unit {
        let a = api ?? return
        let running = match (cronStatus.value) { case Some(s) => s.running; case None => false }
        if (running) {
            let _ = submitAct("act.cron.svc", "定时任务服务已停止", {=> a.cronStop(); "" })
        } else {
            let _ = submitAct("act.cron.svc", "定时任务服务已启动", {=> a.cronStart(); "" })
        }
    }
    public func actCronToggle(id: Int64, enabled: Bool): Unit {
        let a = api ?? return
        let _ = submitAct("act.cron.toggle", "已更新", {=> a.cronSetEnabled(id, enabled); "" })
    }
    public func actCronTrigger(id: Int64): Unit {
        let a = api ?? return
        let _ = submitAct("act.cron.trigger", "已手动触发任务", {=> a.cronTrigger(id); "" })
    }
    public func actCronDelete(id: Int64): Unit {
        let a = api ?? return
        let _ = submitAct("act.cron.del", "定时任务已删除", {=> a.cronDeleteTask(id); "" })
    }
    public func actCronSave(id: Int64, jsonBody: String): Unit {
        if (id == 0) {
            let a = api ?? return
            let _ = submitAct("act.cron.save", "定时任务已创建", {=> a.cronCreateTask(jsonBody); "" })
        } else {
            let a = api ?? return
            let _ = submitAct("act.cron.save", "定时任务已保存", {=> a.cronUpdateTask(id, jsonBody); "" })
        }
    }
    // 启动任务设置（复用系统设置批量接口，单项保存）。
    public func actSaveStartup(key: String, value: Bool): Unit {
        let a = api ?? return
        let entries = ArrayList<(String, String)>()
        entries.add((key, "${value}"))
        let _ = submitAct("act.sys.save", "启动任务设置已保存", {=> a.saveSystemSettings(entries); "" })
    }

    // ---- 插件管理 ----
    public func actPluginEnabled(ns: String, enabled: Bool): Unit {
        let a = api ?? return
        let _ = submitAct("act.plugin.toggle", "已更新", {=> a.setPluginEnabled(ns, enabled); "" })
    }
    public func actPluginDelete(ns: String): Unit {
        let a = api ?? return
        let _ = submitAct("act.plugin.del", "插件已删除", {=> a.deletePlugin(ns); "" })
    }
    public func actPluginSaveConfig(ns: String, jsonBody: String): Unit {
        let a = api ?? return
        let _ = submitAct("act.plugin.cfg", "插件配置已保存", {=> a.savePluginConfig(ns, jsonBody); "" })
    }

    // ---- 账户安全 ----
    public func actChangeCredentials(username: String, password: String): Unit {
        let a = api ?? return
        if (username.size > 0 && username != settings.username) {
            pendingCredUsername = username
        }
        let _ = submitAct("act.cred", "凭据已保存", {=>
            if (username.size > 0 && username != settings.username) { a.changeUsername(username) }
            if (password.size > 0) { a.changePassword(password) }
            ""
        })
    }
    public func actTotpDisable(): Unit {
        let a = api ?? return
        let _ = submitAct("act.totp.off", "双重验证已关闭", {=> a.totpDisable(); "" })
    }
    public func actTotpRegenerate(): Unit {
        let a = api ?? return
        let _ = submitAct("act.totp.regen", "新的恢复码已生成", {=> a.totpRegenerate(); "" })
    }
    public func actRevokeSession(id: Int64): Unit {
        let a = api ?? return
        let _ = submitAct("act.session.revoke", "登录会话已撤销", {=> a.revokeSession(id); "" })
    }
    public func actRevokeOtherSessions(): Unit {
        let a = api ?? return
        let _ = submitAct("act.session.revokeothers", "其他设备已全部退出", {=> a.revokeOtherSessions(); "" })
    }
    public func actCreateToken(name: String): Unit {
        let a = api ?? return
        let _ = worker.submit("act.token.create", {=>
            let t = a.createToken(name)
            "Token已创建: ${t.token}（仅显示一次）"
        })
    }
    public func actRevokeToken(id: Int64): Unit {
        let a = api ?? return
        let _ = submitAct("act.token.revoke", "Token 已撤销", {=> a.revokeToken(id); "" })
    }
    public func actRevokePasskey(id: Int64): Unit {
        let a = api ?? return
        let _ = submitAct("act.passkey.revoke", "Passkey 已删除", {=> a.revokePasskey(id); "" })
    }

    // 统计信息词云点击：携标签回书库搜索（对齐 frontend 词云跳 /?q= 的行为）。
    // 沿用详情页标签 chip 的既有链路：写 searchText → submitFilter 收束查询 → 切回书库页。
    public func searchFromSettings(tag: String): Unit {
        searchText.value = tag
        submitFilter()
        page.value = Page.Library
    }
}
