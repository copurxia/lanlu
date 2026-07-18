package lanlu_client_next.app

import cui.{State, Toaster, ToastKind, clearImageCache, invalidateImage}
import lanlu_client_next.img.*
import lanlu_client_next.net.*
import std.collection.{ArrayList, HashMap}
import std.convert.Parsable
import std.sync.Mutex

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

    // 详情/阅读
    public let meta = State<?ArchiveMeta>(None)
    public let pages = State<ArrayList<PageInfo>>(ArrayList<PageInfo>())
    public let readerIndex = State<Int64>(1)
    public var readerArcid: String = ""   // 当前阅读档案

    // 设置页
    public let serverInfo = State<?ServerInfo>(None)
    public let cacheInfo = State<String>("")

    // 图片：key → 状态（""=未开始/"loading"=在途/"error"=失败/否则为 png 路径）
    public let imageStates = HashMap<String, State<String>>()
    private let imageMutex = Mutex()

    public init(s: AppSettings) {
        settings = s
        if (s.serverUrl.size > 0) {
            api = LanluApi(s.serverUrl)
            if (s.token.size > 0) {
                if (let Some(a) <- api) { a.setToken(s.token) }
            }
        }
    }

    public func showError(msg: String): Unit {
        toaster.show(msg, kind: ToastKind.Error, durationMs: 4200)
    }

    // ---- 会话 ----

    public func connectAndLogin(url: String, user: String, pass: String): Unit {
        let a = LanluApi(url)
        loading.value = true
        let _ = worker.submit("login", {=>
            let _ = a.info()              // 先探测：非 lanlu 服务/地址错误会在这里抛错
            let d = a.login(user, pass)   // 可能抛 TotpRequired / ApiException
            return (a, d, url)
        })
    }

    public func tryResumeSession(): Unit {
        if (settings.serverUrl.size == 0 || settings.token.size == 0) { return }
        let a = api ?? return
        let _ = worker.submit("me", {=> a.me() })
    }

    public func logout(): Unit {
        settings.token = ""
        saveSettingsTo(defaultSettingsPath(), settings)
        page.value = Page.Login
    }

    // ---- 书库查询（Task 8 的视图调用）----

    public func submitSearch(page: Int64): Unit {
        let a = api ?? return
        query.page = page
        query.favoriteonly = favOnly.value
        query.newonly = newOnly.value
        query.untaggedonly = untaggedOnly.value
        loading.value = true
        let q = query
        let _ = worker.submit("search", {=> a.search(q) })
    }

    // 分类列表：登录/恢复会话成功后加载，供书库工具条的分类下拉使用。
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

    // ---- 图片 ----

    // key → png 路径的磁盘缓存（按服务器地址分目录），首次使用时创建。
    private var imageCache: ?ImageCache = None

    private func cache(): ImageCache {
        match (imageCache) {
            case Some(c) => return c
            case None =>
                let c = ImageCache(defaultCacheRoot(settings.serverUrl))
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

    // 图片并发硬上限 4（spec §6）：超出进 FIFO 队列，完成一个补一个。
    // requestImage 与 pump 都在 UI 线程运行，计数无需加锁。
    private var activeImages: Int64 = 0
    private var imageQueue = ArrayList<(String, String)>()

    // 已在途或已完成的 key 直接跳过；否则置 loading 并提交 img:<key> 任务。
    // key 约定：asset:<assetId>（封面/资产）与 page:<arcid>:<pagePath>。
    public func requestImage(key: String, url: String): Unit {
        let st = imageState(key)
        if (st.value == "loading" || st.value.startsWith("/")) { return }
        st.value = "loading"
        if (activeImages >= 4) {
            imageQueue.add((key, url))
            return
        }
        startImageTask(key, url)
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
            c.ensurePng(key, fetch)
        })
        // 同名任务在途时 submit 去重返回 false：回滚并发计数，否则旧任务只减一次导致额度泄漏。
        // 状态保持 loading，由在途任务完成时经 dispatch/finishImageTask 正常设置，
        // 因此 retryImage 打到在途 key 也无害（无需额外短路）。
        if (!submitted) { activeImages-- }
    }

    // 图片任务结束（成功或失败都调）：计数复位并补发队首。
    private func finishImageTask(): Unit {
        activeImages--
        if (activeImages < 0) { activeImages = 0 }
        if (imageQueue.size > 0) {
            let (k, u) = imageQueue.remove(at: 0)
            startImageTask(k, u)
        }
    }

    public func retryImage(key: String, url: String): Unit {
        imageState(key).value = ""
        requestImage(key, url)
    }

    // ---- 详情/阅读（Task 9/10 的视图调用）----

    public func openDetail(arcid: String): Unit {
        meta.value = None
        page.value = Page.Detail(arcid)
        let a = api ?? return
        let _ = worker.submit("meta:${arcid}", {=> a.metadata(arcid) })
    }

    public func openReader(arcid: String, startPage: Int64): Unit {
        readerArcid = arcid
        pages.value = ArrayList<PageInfo>()
        readerIndex.value = startPage
        page.value = Page.Reader(arcid, startPage)
        let a = api ?? return
        let _ = worker.submit("files:${arcid}", {=> a.files(arcid) })
    }

    // 翻到第 n 页（1 基）：钳制到 [1, pages.size]，更新 readerIndex，上报进度并预取前后各 2 页。
    public func gotoPage(n: Int64): Unit {
        let total = pages.value.size
        if (total == 0) { return }
        var next = n
        if (next < 1) { next = 1 }
        if (next > total) { next = total }
        readerIndex.value = next
        reportProgress()
        prefetchAround()
    }

    // 进度回传：PUT /api/archives/:id/progress/:page，任务名 progress（失败静默，见 handleError）。
    public func reportProgress(): Unit {
        let a = api ?? return
        let arcid = readerArcid
        let page = readerIndex.value
        let _ = worker.submit("progress", {=> a.setProgress(arcid, page); return page })
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

    public func toggleIsNew(arcid: String, isNew: Bool): Unit {
        let a = api ?? return
        let _ = worker.submit("isnew:${arcid}", {=>
            a.setIsNew(arcid, isNew)
            return isNew
        })
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

    // 清图片缓存：磁盘目录 + cui 纹理缓存 + imageStates 三处一起复位。
    // 注意命名：cui 有全局 clearImageCache()（纹理缓存），model 方法起名 clearCache 避免遮蔽歧义。
    public func clearCache(): Unit {
        cache().clear()
        clearImageCache()   // cui 框架纹理缓存（已解码的 GPU 纹理）
        synchronized(imageMutex) { imageStates.clear() }
        refreshCacheInfo()
        toaster.show("缓存已清理", kind: ToastKind.Success)
    }

    // ---- 每帧泵：把工作线程结果写回 State（UI 线程）----

    public func pump(): Unit {
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
        if (name == "login") {
            loading.value = false
            match (r.payload) {
                case Some(p) =>
                    let (a, d, url) = (p as (LanluApi, LoginData, String)).getOrThrow()
                    api = a
                    settings.serverUrl = url
                    settings.token = d.token
                    settings.username = d.username
                    saveSettingsTo(defaultSettingsPath(), settings)
                    // 换服登录必须复位图片缓存：缓存目录按 serverUrl 派生，而 imageStates
                    // 的 key（asset:42 等）与服务器无关，不复位会把旧服务器的图误判为
                    // “已加载”，新下载也会落进旧目录。同服重登无害：磁盘文件仍在，
                    // ensurePng 直接命中，只是重新加载一遍。
                    imageCache = None
                    synchronized(imageMutex) { imageStates.clear() }
                    page.value = Page.Library
                    submitSearch(1)
                    loadCategories()
                case None => ()
            }
        } else if (name == "me") {
            page.value = Page.Library
            submitSearch(1)
            loadCategories()
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
        } else if (name == "categories") {
            match (r.payload) {
                case Some(p) => categories.value = (p as ArrayList<CategoryItem>).getOrThrow()
                case None => ()
            }
        } else if (name.startsWith("meta:")) {
            match (r.payload) {
                case Some(p) =>
                    // 迟到结果对号入座：详情页已从 A 切到 B 时，A 的元数据不得覆盖 B 的页面。
                    // arcid 取任务名（一定等于请求目标），不依赖响应体回传字段。
                    let arcid = name.removePrefix("meta:")
                    match (page.value) {
                        case Page.Detail(cur) => if (arcid == cur) {
                            meta.value = Some((p as ArchiveMeta).getOrThrow())
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
                                pages.value = (p as ArrayList<PageInfo>).getOrThrow()
                                // 起始页来自可能过期的 progress；页列表到货后钳制，防 readerIndex 越界取页。
                                let total = pages.value.size
                                if (total > 0) {
                                    if (readerIndex.value < 1) { readerIndex.value = 1 }
                                    if (readerIndex.value > total) { readerIndex.value = total }
                                }
                            }
                        case _ => ()
                    }
                case None => ()
            }
        } else if (name.startsWith("favorite:") || name.startsWith("isnew:")) {
            // 收藏/未读切换成功：仍在详情页则重取元数据刷新展示
            match (page.value) {
                case Page.Detail(arcid) => refreshMeta(arcid)
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
                    let path = (p as String).getOrThrow()
                    invalidateImage(path)   // cui 纹理缓存失效，覆盖旧图时必需
                    imageState(key).value = path
                case None => imageState(key).value = "error"
            }
        }
    }
}
