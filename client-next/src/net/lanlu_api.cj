package lanlu_client_next.net

import qwest.*
import std.collection.{ArrayList, HashMap}
import std.fs.{Directory, File, FileInfo, OpenMode, Path, exists}
import std.io.OutputStream
import std.sync.{Mutex}

public class ApiException <: Exception {
    public let status: UInt16
    public init(status: UInt16, message: String) {
        super(message)
        this.status = status
    }
}

public class TotpRequired <: Exception {
    public let challengeId: String
    public init(challengeId: String) {
        super("该账号启用了二步验证，请输入验证码")
        this.challengeId = challengeId
    }
}

// Bearer token 的线程安全持有者，经 onRequest 钩子注入每个请求。
class TokenStore {
    private let mutex = Mutex()
    private var token: String = ""
    func set(t: String): Unit {
        synchronized(mutex) {
            token = t
        }
    }
    func get(): String {
        synchronized(mutex) {
            return token
        }
    }
}

public class LanluApi {
    private let client: Client
    private let uploadClient: Client
    private let store = TokenStore()
    private let base: String
    // TCP connect 超时（qwest 原生支持，不再需要看门狗）：None = 不设（默认行为不变）。
    private let connectTimeout: ?Duration
    // 离线缓存（读穿透回退 + 阅读进度队列）；None = 离线能力关闭（探测用实例不传）。
    private let offlineCache: ?OfflineCache
    private let serverHash: String
    // 离线回退命中时的一次性通知回调（model 用 toast 提示）。
    private let onOfflineFallback: ?(() -> Unit)

    public init(
        baseUrl: String,
        connectTimeout!: ?Duration = None,
        offlineCache!: ?OfflineCache = None,
        serverHash!: String = "",
        onOfflineFallback!: ?(() -> Unit) = None
    ) {
        this.offlineCache = offlineCache
        this.serverHash = serverHash
        this.onOfflineFallback = onOfflineFallback
        var b = baseUrl.trimAscii()
        while (b.endsWith("/")) {
            b = b[0..b.size - 1]
        }
        base = b
        this.connectTimeout = connectTimeout
        let s = store
        var cb = ClientBuilder()
            .baseUrl(base)
            .readTimeout(Duration.second * 30)
            .writeTimeout(Duration.second * 30)
            .poolMaxIdlePerHost(8)
            .interceptor(
                {
                    req =>
                        let t = s.get()
                        if (t.size > 0) {
                            req.header("Authorization", "Bearer ${t}")
                        }
                }
            )
        if (let Some(t) <- connectTimeout) {
            cb = cb.connectTimeout(t)
        }
        client = cb.build()
        var ub = ClientBuilder()
            .baseUrl(base)
            .readTimeout(Duration.second * 600)
            .writeTimeout(Duration.second * 600)
            .poolMaxIdlePerHost(4)
            .interceptor(
                {
                    req =>
                        let t = s.get()
                        if (t.size > 0) {
                            req.header("Authorization", "Bearer ${t}")
                        }
                }
            )
        if (let Some(t) <- connectTimeout) {
            ub = ub.connectTimeout(t)
        }
        uploadClient = ub.build()
    }

    public func setToken(token: String): Unit {
        store.set(token)
    }
    public func close(): Unit {
        client.close()
        uploadClient.close()
    }

    // 未读完响应体的异常分支必须 close（qwest 中未读尽的连接既不回池也不关闭），
    // 401 分支同样处理，避免连接悬挂。
    private func checked(resp: Response): Envelope {
        if (resp.status == 401) {
            resp.close()
            throw ApiException(401, "登录状态已失效，请重新登录")
        }
        if (!resp.isSuccess()) {
            throw ApiException(resp.status, resp.text())
        }
        parseEnvelope(resp.text())
    }

    private func checkedBytes(resp: Response): Array<UInt8> {
        if (resp.status == 401) {
            resp.close()
            throw ApiException(401, "登录状态已失效，请重新登录")
        }
        if (!resp.isSuccess()) {
            // 页面/媒体接口的服务端错误体包含归档路径、条目读取等具体原因。保留它，
            // 否则播放层只能显示无诊断价值的 “HTTP 500”。
            let detail = resp.text().trimAscii()
            throw ApiException(resp.status, if (detail.size > 0) {
                "HTTP ${resp.status}: ${detail}"
            } else {
                "HTTP ${resp.status}"
            })
        }
        resp.bytes()
    }

    // parseCategoryList/parseArchiveMeta 需要完整响应体而非已解包的 envelope。
    private func checkedBody(resp: Response): String {
        if (resp.status == 401) {
            resp.close()
            throw ApiException(401, "登录状态已失效，请重新登录")
        }
        if (!resp.isSuccess()) {
            throw ApiException(resp.status, resp.text())
        }
        resp.text()
    }

    // Tankoubon 等旧 mutation 端点返回裸 {success,error,...}，不能走 Envelope 解析。
    private func checkedMutation(resp: Response, valueField!: String = ""): ApiMutationResult {
        let status = resp.status
        let result = parseApiMutationResult(checkedBody(resp), valueField: valueField)
        if (!result.success) {
            throw ApiException(status, result.error)
        }
        result
    }

    // 离线读穿透（GET 白名单端点专用）：在线成功返回原始 body 并写响应快照；
    // 网络类异常（连接失败/超时等，非 ApiException）时回退缓存，命中返回缓存 body 并触发
    // 一次性通知；未命中/缓存未开启原样重抛。ApiException（401/非 2xx）不触发回退。
    private func checkedBodyCached(path: String): String {
        try {
            let resp = client.get(path).send()
            if (resp.status == 401) {
                resp.close()
                throw ApiException(401, "登录状态已失效，请重新登录")
            }
            if (!resp.isSuccess()) {
                throw ApiException(resp.status, resp.text())
            }
            let body = resp.text()
            try {
                match (offlineCache) {
                    case Some(c) => c.storeResponse(serverHash, path, body)
                    case None => ()
                }
            } catch (_: Exception) {}
            return body
        } catch (e: ApiException) {
            throw e
        } catch (_: Exception) {
            // 网络类异常：尝试回退离线缓存。
            try {
                match (offlineCache) {
                    case Some(c) => match (c.getResponse(serverHash, path)) {
                        case Some(body) =>
                            match (onOfflineFallback) {
                                case Some(f) => f()
                                case None => ()
                            }
                            return body
                        case None => ()
                    }
                    case None => ()
                }
            } catch (_: Exception) {}
            throw Exception("网络不可用且无离线缓存")
        }
    }

    // connectTimeout 已由 qwest 原生支持（TcpSocket.connect(timeout)，见构造），
    // 看门狗（withHardTimeout）随迁移删除：TCP connect 挂死不再拖住调用线程。
    public func info(): ServerInfo {
        fetchInfo()
    }

    private func fetchInfo(): ServerInfo {
        // /api/info 返回裸 JSON 对象（无包络），unwrapDataRaw 兼容两种形态。
        JsonCodec.decode<ServerInfo>(unwrapDataRaw(checkedBody(client.get("/api/info").send())))
    }

    public func login(username: String, password: String): LoginData {
        let body = "{\"username\":${jsonQuote(username)},\"password\":${jsonQuote(password)},\"tokenName\":\"lanlu-desktop\"}"
        let resp = client.post("/api/auth/login").json(body).send()
        if (resp.status == 202) {
            let env = parseEnvelope(resp.text())
            throw TotpRequired(JsonCodec.decode<LoginPendingTotp>(env.dataRaw).challengeId)
        }
        // 服务端对用户名/密码错误也返回 401（{"code":401,"message":"invalid credentials"}），
        // 不能走 checked() 的“登录状态已失效”文案——那是会话过期专用，此处特判为凭据错误。
        if (resp.status == 401) {
            resp.close()
            throw ApiException(401, "用户名或密码错误")
        }
        let env = checked(resp)
        let d = JsonCodec.decode<LoginData>(env.dataRaw)
        if (d.token.size == 0) {
            throw ApiException(0, "登录响应缺少 token")
        }
        setToken(d.token)
        return d
    }

    // TOTP 二次验证：POST /api/auth/login/totp/verify，响应形态与 login 一致（token+user）。
    // 401 = 验证码/恢复码错误（服务端 "invalid totp or recovery code"），不是会话失效，特判文案。
    public func verifyTotpLogin(challengeId: String, code: String, recoveryCode: String): LoginData {
        let body = "{\"challengeId\":${jsonQuote(challengeId)},\"code\":${jsonQuote(code)},\"recoveryCode\":${jsonQuote(recoveryCode)}}"
        let resp = client.post("/api/auth/login/totp/verify").json(body).send()
        if (resp.status == 401) {
            resp.close()
            throw ApiException(401, "验证码或恢复码错误")
        }
        let env = checked(resp)
        let d = JsonCodec.decode<LoginData>(env.dataRaw)
        if (d.token.size == 0) {
            throw ApiException(0, "登录响应缺少 token")
        }
        setToken(d.token)
        return d
    }

    public func me(): LoginData {
        let env = parseEnvelope(checkedBodyCached("/api/auth/me"))
        // /api/auth/me 的 data 是 {"user": {...}}（UserDataView 序列化形态），
        // 直接解 LoginData 即可（token 缺省为空串）——不能再包一层 {"user": ...}，
        // 否则双重嵌套导致 username/isAdmin 全部解析落空。
        JsonCodec.decode<LoginData>(env.dataRaw)
    }

    public func search(q: SearchQuery): SearchPage {
        parseSearchPage(checkedBodyCached("/api/search${buildSearchQuery(q)}"))
    }

    // 随机推荐：服务端没有 /api/search/random 路由（routes/api/search.cj 只注册 GET /api/search），
    // 随机能力由 /api/search?sortby=RANDOM() 提供——archive_dao.cj 对 sortby=="RANDOM()"
    // 特判为 ORDER BY RANDOM() DESC（括号字面量经 query 解码后还原）。响应形态与
    // /api/search 完全一致，复用 SearchQuery 构造与 parseSearchPage 解析。
    public func randomSearch(count: Int64, lang!: String = "", groupbyTanks!: Bool = false): SearchPage {
        let q = SearchQuery()
        q.sortby = "RANDOM()"
        q.pageSize = count
        q.lang = lang
        q.groupbyTanks = groupbyTanks
        parseSearchPage(checkedBodyCached("/api/search${buildSearchQuery(q)}"))
    }

    public func categories(): ArrayList<CategoryItem> {
        parseCategoryList(checkedBodyCached("/api/categories"))
    }

    public func metadata(arcid: String, lang!: String = ""): ArchiveMeta {
        let suffix = if (lang.size > 0) {
            "?lang=${percentEncode(lang)}"
        } else {
            ""
        }
        parseArchiveMeta(checkedBodyCached("/api/archives/${arcid}/metadata${suffix}"))
    }

    public func updateArchiveMetadata(arcid: String, body: String): Unit {
        let _ = checked(client.put("/api/archives/${percentEncode(arcid)}/metadata").body(body).send())
    }

    public func files(arcid: String): ArrayList<PageInfo> {
        parsePages(checkedBodyCached("/api/archives/${arcid}/files"))
    }

    public func assetBytes(assetId: Int64): Array<UInt8> {
        checkedBytes(client.get("/api/assets/${assetId}").send())
    }

    // 流式下载资产原始字节到 output（固定缓冲逐块复制，不随响应大小增长），
    // 返回写入字节数。完整读完后连接可回池复用；错误语义同 checkedBytes，
    // 错误体只读上限 64KB 诊断文本后关闭响应（禁止无上限 body()）。
    public func downloadAssetTo(assetId: Int64, output: OutputStream): Int64 {
        downloadChecked(client.get("/api/assets/${assetId}").send(), output)
    }

    // 流式下载阅读页原始字节到 output（同 downloadAssetTo 语义）。
    public func downloadPageTo(arcid: String, pagePath: String, output: OutputStream): Int64 {
        downloadChecked(client.get(pageUrl(arcid, pagePath)).send(), output)
    }

    public func archiveDownloadParts(arcid: String): ArrayList<ArchiveDownloadPart> {
        parseArchiveDownloadParts(
            checkedBody(client.get("/api/archives/${percentEncode(arcid)}/download/parts").send()))
    }

    // 单文件写入用户选定路径；分卷档案以服务端卷名写入所选文件的同级目录。
    public func downloadArchiveToPath(arcid: String, selectedPath: String): Int64 {
        let parts = archiveDownloadParts(arcid)
        if (parts.size == 0) {
            try (file = File(Path(selectedPath), OpenMode.Write)) {
                let _ = downloadChecked(client.get("/api/archives/${percentEncode(arcid)}/download").send(), file)
            }
            return 1
        }
        if (parts.size == 1) {
            try (file = File(Path(selectedPath), OpenMode.Write)) {
                let _ = downloadChecked(client.get("/api/archives/${percentEncode(arcid)}/download").send(), file)
            }
            return 1
        }
        let folder = Path(selectedPath).parent.toString()
        for (part in parts) {
            let name = safeDownloadName(part.name, "${arcid}.part${part.index + 1}")
            try (file = File(Path("${folder}/${name}"), OpenMode.Write)) {
                let _ = downloadChecked(
                    client.get("/api/archives/${percentEncode(arcid)}/download?part=${part.index}").send(), file)
            }
        }
        parts.size
    }

    // 批量下载落到用户选定目录；每个档案按服务端原始文件/分卷名保存。
    public func downloadArchiveToFolder(arcid: String, folder: String): Int64 {
        let archiveFolder = Path("${folder}/${safeDownloadName(arcid, "archive")}")
        if (!exists(archiveFolder)) {
            Directory.create(archiveFolder, recursive: true)
        }
        let targetFolder = archiveFolder.toString()
        let parts = archiveDownloadParts(arcid)
        if (parts.size == 0) {
            let fallback = safeDownloadName(arcid, "archive")
            try (file = File(Path("${targetFolder}/${fallback}"), OpenMode.Write)) {
                let _ = downloadChecked(client.get("/api/archives/${percentEncode(arcid)}/download").send(), file)
            }
            return 1
        }
        for (part in parts) {
            let name = safeDownloadName(part.name, if (parts.size > 1) {
                "${arcid}.part${part.index + 1}"
            } else {
                arcid
            })
            let suffix = if (parts.size > 1) {
                "?part=${part.index}"
            } else {
                ""
            }
            try (file = File(Path("${targetFolder}/${name}"), OpenMode.Write)) {
                let _ = downloadChecked(client.get("/api/archives/${percentEncode(arcid)}/download${suffix}").send(),
                    file)
            }
        }
        parts.size
    }

    public func downloadSourceArchive(namespace: String, remoteId: String, categoryId: Int64): Unit {
        let body = "{\"remote_id\":${jsonQuote(remoteId)},\"category_id\":${jsonQuote(categoryId.toString())}," +
            "\"kind\":\"archive\"}"
        let raw = checkedBody(
            client.post("/api/admin/source-plugins/${percentEncode(namespace)}/download").json(body).send())
        if (!raw.contains("\"success\":true") && !raw.contains("\"success\":1")) {
            throw Exception("创建 source 下载任务失败")
        }
    }

    public func tagTranslations(lang: String, arcid!: String = "", tankid!: String = ""): HashMap<String, String> {
        var path = "/api/tags/translations?lang=${percentEncode(lang)}"
        if (arcid.size > 0) {
            path = "${path}&arcid=${percentEncode(arcid)}"
        } else if (tankid.size > 0) {
            path = "${path}&tankoubon_id=${percentEncode(tankid)}"
        }
        parseTagTranslationMap(checkedBodyCached(path))
    }

    // 流式下载公共逻辑：401/状态码/错误体诊断语义与 checkedBytes 一致。
    private func downloadChecked(resp: Response, output: OutputStream): Int64 {
        if (resp.status == 401) {
            resp.close()
            throw ApiException(401, "登录状态已失效，请重新登录")
        }
        if (!resp.isSuccess()) {
            // 页面/媒体接口的服务端错误体包含归档路径、条目读取等具体原因。只读
            // 上限 64KB 诊断文本（一次 read 不超缓冲），随后关闭响应释放连接。
            let detail = try {
                let buf = Array<UInt8>(65536, repeat: 0u8)
                let n = resp.stream().read(buf)
                if (n > 0) {
                    String.fromUtf8(buf[0..n])
                } else {
                    ""
                }
            } catch (_: Exception) {
                ""
            }
            resp.close()
            let t = detail.trimAscii()
            throw ApiException(resp.status, if (t.size > 0) {
                "HTTP ${resp.status}: ${t}"
            } else {
                "HTTP ${resp.status}"
            })
        }
        resp.copyTo(output)
    }

    // 合集列表：GET /api/tankoubons 返回裸 {"filtered":N,"result":[...],"total":N}（无包络）。
    public func listTankoubons(lang!: String = ""): ArrayList<TankoubonInfo> {
        let path = if (lang.size > 0) {
            "/api/tankoubons?lang=${percentEncode(lang)}"
        } else {
            "/api/tankoubons"
        }
        parseTankoubonList(checkedBodyCached(path))
    }

    // 单个合集：GET /api/tankoubons/:id/metadata 返回裸对象（children 为 member 对象数组）。
    public func getTankoubon(id: String, lang!: String = ""): TankoubonInfo {
        let suffix = if (lang.size > 0) {
            "?lang=${percentEncode(lang)}"
        } else {
            ""
        }
        parseTankoubon(checkedBodyCached("/api/tankoubons/${id}/metadata${suffix}"))
    }

    public func updateTankoubonMetadata(id: String, body: String): Unit {
        let _ = checked(client.put("/api/tankoubons/${percentEncode(id)}/metadata").body(body).send())
    }

    public func deleteArchive(arcid: String): Unit {
        let _ = checked(client.delete("/api/archives/${percentEncode(arcid)}").send())
    }

    public func deleteTankoubon(id: String): Unit {
        let _ = checked(client.delete("/api/tankoubons/${percentEncode(id)}").send())
    }

    // 新建合集：PUT /api/tankoubons?name=X（name 在 query），响应为裸 {success, tankoubon_id}。
    public func createTankoubon(name: String): String {
        let result = checkedMutation(client.put("/api/tankoubons?name=${percentEncode(name)}").body("").send(),
            valueField: "tankoubon_id")
        if (result.value.trimAscii().size == 0) {
            throw ApiException(200, "服务器未返回新合集 ID")
        }
        result.value
    }

    // 合集成员增删：PUT/DELETE /api/tankoubons/{tankId}/{arcid}。
    public func addTankMember(tankId: String, arcid: String): Unit {
        let _ = checkedMutation(
            client.put("/api/tankoubons/${percentEncode(tankId)}/${percentEncode(arcid)}").body("").send())
    }

    public func removeTankMember(tankId: String, arcid: String): Unit {
        let _ = checkedMutation(
            client.delete("/api/tankoubons/${percentEncode(tankId)}/${percentEncode(arcid)}").send())
    }

    // 档案所属合集：GET /api/archives/:id/tankoubons，响应形态同合集列表。
    public func listArchiveTankoubons(arcid: String, lang!: String = ""): ArrayList<TankoubonInfo> {
        let base = "/api/archives/${arcid}/tankoubons"
        let path = if (lang.size > 0) {
            "${base}?lang=${percentEncode(lang)}"
        } else {
            base
        }
        parseTankoubonList(checkedBodyCached(path))
    }

    // 相关推荐（档案详情）：GET /api/recommendations?scene=archive_related&archive_id=X
    // 返回裸 {"scene":...,"data":[...]}，data 数组元素与 search 条目同构，复用 parseSearchPage；
    // 混进的合集项没有 arcid，过滤丢弃（对齐 frontend getArchiveRelated 的 isArchiveItem 过滤）。
    public func relatedArchives(arcid: String, count: Int64, lang!: String = ""): ArrayList<SearchItem> {
        let languageQuery = if (lang.size > 0) {
            "&lang=${percentEncode(lang)}"
        } else {
            ""
        }
        let body = checkedBodyCached(
            "/api/recommendations?scene=archive_related&archive_id=${percentEncode(arcid)}&count=${count}${languageQuery}")
        let page = parseSearchPage(body)
        let list = ArrayList<SearchItem>()
        for (it in page.items) {
            if (it.arcid.size > 0) {
                list.add(it)
            }
        }
        list
    }

    // 相关推荐（合集详情）：scene=tankoubon_related，元素为合集对象（recommendations 形态，
    // assets 为对象），复用 parseTankoubonList；过滤掉无 id 的档案项。
    public func relatedTankoubons(tankid: String, count: Int64, lang!: String = ""): ArrayList<TankoubonInfo> {
        let languageQuery = if (lang.size > 0) {
            "&lang=${percentEncode(lang)}"
        } else {
            ""
        }
        let body = checkedBodyCached(
            "/api/recommendations?scene=tankoubon_related&tankoubon_id=${percentEncode(tankid)}&count=${count}${languageQuery}")
        let all = parseTankoubonList(body)
        let list = ArrayList<TankoubonInfo>()
        for (t in all) {
            if (t.id.size > 0) {
                list.add(t)
            }
        }
        list
    }

    public func recordRecommendationInteraction(scene: String, seedType: String, seedId: String, itemType: String,
        itemId: String, interaction: String): Unit {
        let body = "{\"scene\":${jsonQuote(scene)},\"seed_entity_type\":${jsonQuote(seedType)}," +
            "\"seed_entity_id\":${jsonQuote(seedId)},\"item_type\":${jsonQuote(itemType)}," +
            "\"item_id\":${jsonQuote(itemId)},\"interaction_type\":${jsonQuote(interaction)}}"
        let _ = checkedBody(client.post("/api/recommendations/interactions").json(body).send())
    }

    public func runMetadataPlugin(targetType: String, targetId: String, namespace: String, param: String): Int64 {
        let body = "{\"target_type\":${jsonQuote(targetType)},\"target_id\":${jsonQuote(targetId)}," +
            "\"namespace\":${jsonQuote(namespace)},\"param\":${jsonQuote(param)},\"write_back\":1}"
        let raw = checkedBody(client.post("/api/metadata_plugin").json(body).send())
        let job = uploadResultTaskId(raw, "job")
        if (job <= 0) {
            let reason = uploadResultText(raw, "error")
            throw Exception(if (reason.size > 0) {
                reason
            } else {
                "元数据插件未返回任务 ID"
            })
        }
        job
    }

    public func pageBytes(arcid: String, pagePath: String): Array<UInt8> {
        checkedBytes(client.get(pageUrl(arcid, pagePath)).send())
    }

    public func assetUrl(assetId: Int64): String {
        "/api/assets/${assetId}"
    }
    public func pageUrl(arcid: String, pagePath: String): String {
        "/api/archives/${arcid}/page?path=${percentEncode(pagePath)}"
    }

    public func setProgress(arcid: String, page: Int64): Unit {
        try {
            let _ = checked(client.put("/api/archives/${arcid}/progress/${page}").body("").send())
        } catch (e: ApiException) {
            throw e
        } catch (_: Exception) {
            // 网络类失败：进度入队待补报后原样重抛（worker 线程失败静默语义不变）。
            try {
                match (offlineCache) {
                    case Some(c) => c.enqueueProgress(serverHash, arcid, page)
                    case None => ()
                }
            } catch (_: Exception) {}
            throw Exception("网络不可用，阅读进度已离线暂存")
        }
    }

    public func setFavorite(arcid: String, fav: Bool): Unit {
        if (fav) {
            let _ = checked(client.put("/api/archives/${arcid}/favorite").body("").send())
        } else {
            let _ = checked(client.delete("/api/archives/${arcid}/favorite").send())
        }
    }

    public func setTankFavorite(tankid: String, fav: Bool): Unit {
        if (fav) {
            let _ = checked(client.put("/api/tankoubons/${tankid}/favorite").body("").send())
        } else {
            let _ = checked(client.delete("/api/tankoubons/${tankid}/favorite").send())
        }
    }

    public func setIsNew(arcid: String, isNew: Bool): Unit {
        if (isNew) {
            let _ = checked(client.put("/api/archives/${arcid}/isnew").body("").send())
        } else {
            let _ = checked(client.delete("/api/archives/${arcid}/isnew").send())
        }
    }

    // 档案上传协议与 frontend ChunkedUploadService 保持一致：创建 asset_upload 任务，
    // 等待调度为 running，按 10 MiB 顺序 PUT 分片，再等待 process/consume 任务链完成。
    public func uploadArchive(
        path: String,
        categoryId: Int64,
        overwrite: Bool,
        onUpdate: (String, Int64, String) -> Unit
    ): ArchiveUploadResult {
        let filePath = Path(path)
        let info = FileInfo(filePath)
        let fileSize = Int64(info.size)
        let filename = filePath.fileName
        if (fileSize <= 0) {
            throw IllegalArgumentException("文件不能为空")
        }
        if (categoryId <= 0) {
            throw IllegalArgumentException("请选择要上传到的分类")
        }

        let totalChunks = (fileSize + ARCHIVE_UPLOAD_CHUNK_SIZE - 1) / ARCHIVE_UPLOAD_CHUNK_SIZE
        let body = "{\"filename\":${jsonQuote(filename)},\"file_checksum\":\"\"," +
            "\"filesize\":${fileSize},\"chunk_size\":${ARCHIVE_UPLOAD_CHUNK_SIZE}," +
            "\"total_chunks\":${totalChunks},\"title\":${jsonQuote(filePath.fileNameWithoutExtension)}," +
            "\"tags\":\"\",\"summary\":\"\",\"category_id\":${categoryId}," +
            "\"overwrite\":${if (overwrite) { "true" } else { "false" }}," +
            "\"target_type\":\"archive\",\"target_id\":\"\",\"content_type\":\"\"}"
        let initResponse = uploadClient.post("/api/assets/upload/init").json(body).send()
        if (initResponse.status == 409) {
            let result = ArchiveUploadResult()
            result.fileExists = true
            let envelope = parseEnvelope(initResponse.text())
            result.error = if (envelope.message.size > 0) {
                envelope.message
            } else {
                "文件已存在"
            }
            return result
        }
        let initEnvelope = checked(initResponse)
        let taskId = uploadResultTaskId(initEnvelope.dataRaw, "taskId")
        if (taskId <= 0) {
            throw ApiException(0, "服务器未返回上传任务 ID")
        }

        onUpdate("queued", 0, "等待上传任务调度")
        waitForUploadReady(taskId, onUpdate)
        onUpdate("uploading", 0, "正在上传")
        try (file = File(filePath, OpenMode.Read)) {
            var chunkIndex: Int64 = 0
            while (chunkIndex < totalChunks) {
                let offset = chunkIndex * ARCHIVE_UPLOAD_CHUNK_SIZE
                let expectedSize = min(ARCHIVE_UPLOAD_CHUNK_SIZE, fileSize - offset)
                let chunk = Array<UInt8>(expectedSize, repeat: 0)
                let bytesRead = file.read(chunk)
                if (bytesRead != expectedSize) {
                    throw Exception("读取分片失败：期望 ${expectedSize} 字节，实际 ${bytesRead} 字节")
                }
                uploadArchiveChunk(taskId, chunkIndex, totalChunks, chunk)
                chunkIndex += 1
                onUpdate("uploading", min(100, chunkIndex * 100 / totalChunks),
                    "已上传 ${chunkIndex}/${totalChunks} 个分片")
            }
        }

        onUpdate("processing", 100, "服务器正在处理档案")
        let uploadTask = waitForTerminalTask(taskId, onUpdate)
        ensureUploadTaskCompleted(uploadTask)

        let processTaskId = uploadResultTaskId(uploadTask.result, "process_task_id")
        var processTask = uploadTask
        if (processTaskId > 0) {
            processTask = waitForTerminalTask(processTaskId, onUpdate)
            ensureUploadTaskCompleted(processTask)
        }
        let consumeTaskId = uploadResultTaskId(processTask.result, "consume_task_id")
        if (consumeTaskId > 0) {
            ensureUploadTaskCompleted(waitForTerminalTask(consumeTaskId, onUpdate))
        }

        let result = ArchiveUploadResult()
        result.success = true
        result.taskId = taskId
        result
    }

    // 在线下载协议与 frontend downloadFromUrl 一致：POST /api/download_url 入队即返回，
    // 下载与入库全在服务端 TaskPool 内完成，客户端只轮询任务至终态。
    // 注意该接口响应是裸 JSON（{"job":id,"success":1,...}）而非统一 envelope，故用
    // checkedBody + uploadResultTaskId 解析，不能走 checked/parseEnvelope。
    public func downloadFromUrl(
        url: String,
        categoryId: Int64,
        onUpdate: (String, Int64, String) -> Unit
    ): ArchiveUploadResult {
        let trimmed = url.trimAscii()
        if (!trimmed.startsWith("http://") && !trimmed.startsWith("https://")) {
            throw IllegalArgumentException("下载链接无效")
        }
        if (categoryId <= 0) {
            throw IllegalArgumentException("请选择要下载到的分类")
        }

        let body = "{\"url\":${jsonQuote(trimmed)},\"category_id\":${categoryId}}"
        let raw = checkedBody(client.post("/api/download_url").json(body).send())
        let taskId = uploadResultTaskId(raw, "job")
        if (taskId <= 0) {
            let detail = uploadResultText(raw, "error")
            throw ApiException(0, if (detail.size > 0) {
                detail
            } else {
                "服务器未返回下载任务 ID"
            })
        }

        onUpdate("downloading", 0, "等待下载任务调度")
        // 服务端在同一个任务里先下载后入库：进度未满视为下载中，满 100 后视为处理中。
        let task = waitForTerminalTask(taskId, {
            stage, progress, message => onUpdate(if (stage == "processing" && progress < 100) {
                "downloading"
            } else {
                stage
            }, progress, message)
        }, what: "下载任务")
        ensureUploadTaskCompleted(task)

        let result = ArchiveUploadResult()
        result.success = true
        result.taskId = taskId
        result
    }

    private func uploadTask(taskId: Int64): UploadTaskSnapshot {
        parseUploadTaskSnapshot(checkedBody(client.get("/api/admin/taskpool/${taskId}").send()))
    }

    private func waitForUploadReady(taskId: Int64, onUpdate: (String, Int64, String) -> Unit): Unit {
        var attempts: Int64 = 0
        while (attempts < 1800) {
            let task = uploadTask(taskId)
            match (task.status) {
                case "running" => return
                case "pending" | "waiting" => onUpdate("queued", 0, if (task.message.size > 0) {
                    task.message
                } else {
                    "等待上传任务调度"
                })
                case "failed" | "stopped" | "cancelled" | "canceled" => throw ApiException(0, uploadTaskError(task))
                case "completed" => throw ApiException(0, "上传任务未进入运行态便已结束")
                case _ => ()
            }
            attempts += 1
            sleep(Duration.second)
        }
        throw ApiException(0, "等待上传任务调度超时")
    }

    private func uploadArchiveChunk(taskId: Int64, chunkIndex: Int64, totalChunks: Int64, chunk: Array<UInt8>): Unit {
        var attempt: Int64 = 0
        while (true) {
            let response = uploadClient
                .request(Method.PUT,
                    "/api/assets/upload/chunk?taskId=${taskId}&chunkIndex=${chunkIndex}&totalChunks=${totalChunks}")
                .header("Content-Type", "application/octet-stream")
                .body(chunk)
                .send()
            if (response.isSuccess()) {
                let _ = checked(response)
                return
            }
            let status = response.status
            let detail = response.text()
            if (status == 400 || status == 404 || attempt >= 3) {
                throw ApiException(status, if (detail.size > 0) {
                    detail
                } else {
                    "分片 ${chunkIndex} 上传失败"
                })
            }
            attempt += 1
            sleep(Duration.second * attempt)
        }
    }

    private func waitForTerminalTask(taskId: Int64, onUpdate: (String, Int64, String) -> Unit,
        what!: String = "上传档案"): UploadTaskSnapshot {
        var attempts: Int64 = 0
        while (attempts < 3600) {
            let task = uploadTask(taskId)
            onUpdate("processing", min(100, max(0, task.progress)), task.message)
            match (task.status) {
                case "completed" | "failed" | "stopped" | "cancelled" | "canceled" => return task
                case _ => ()
            }
            attempts += 1
            sleep(Duration.second)
        }
        throw ApiException(0, "等待服务器处理${what}超时")
    }

    private func ensureUploadTaskCompleted(task: UploadTaskSnapshot): Unit {
        if (task.status != "completed") {
            throw ApiException(0, uploadTaskError(task))
        }
    }

    private func uploadTaskError(task: UploadTaskSnapshot): String {
        if (task.message.size > 0) {
            task.message
        } else {
            "任务 ${task.id} 状态为 ${task.status}"
        }
    }

    // ==================== 设置区扩展：统计 / 账户安全 ====================

    public func userStats(): UserStats {
        parseUserStats(checkedBody(client.get("/api/user/stats").send()))
    }

    public func userTrend(days: Int64): ArrayList<TrendPoint> {
        parseTrendList(checkedBody(client.get("/api/user/trend?days=${days}").send()))
    }

    public func tagCloud(limit: Int64, lang!: String = ""): ArrayList<CloudTag> {
        let langPart = if (lang.size > 0) {
            "&lang=${percentEncode(lang)}"
        } else {
            ""
        }
        parseCloudTags(checkedBody(client.get("/api/tags/cloud?limit=${limit}${langPart}").send()))
    }

    public func tagAutocomplete(query: String, limit: Int64, lang!: String = ""): ArrayList<TagSuggestion> {
        let effectiveLang = if (lang.size > 0) {
            lang
        } else {
            "zh"
        }
        let url = "/api/tags/autocomplete?q=${percentEncode(query.trimAscii())}" +
            "&lang=${percentEncode(effectiveLang)}&limit=${limit}" + "&require_bound=1"
        parseTagSuggestions(checkedBody(client.get(url).send()))
    }

    public func totpStatus(): TotpStatus {
        parseTotpStatus(checkedBody(client.get("/api/auth/totp/status").send()))
    }

    public func totpDisable(): Unit {
        let _ = checked(client.delete("/api/auth/totp").send())
    }

    public func totpRegenerate(): ArrayList<String> {
        parseStringArray(checked(client.post("/api/auth/totp/recovery-codes/regenerate").json("{}").send()).dataRaw)
    }

    public func listSessions(): ArrayList<SessionItem> {
        parseSessionList(checkedBody(client.get("/api/auth/sessions").send()))
    }

    public func revokeSession(id: Int64): Unit {
        let _ = checked(client.delete("/api/auth/sessions/${id}").send())
    }

    public func revokeOtherSessions(): Unit {
        let _ = checked(client.post("/api/auth/sessions/revoke-others").json("{}").send())
    }

    public func listTokens(): ArrayList<TokenItem> {
        parseTokenList(checkedBody(client.get("/api/auth/tokens").send()))
    }

    // 创建成功时响应 data 为单个 TokenView 对象，含一次性明文 token（仅此一次可见）。
    public func createToken(name: String): TokenItem {
        let body = "{\"name\":${jsonQuote(name)}}"
        let env = checked(client.post("/api/auth/tokens").json(body).send())
        parseCreatedToken("{\"data\":${env.dataRaw}}")
    }

    public func revokeToken(id: Int64): Unit {
        let _ = checked(client.delete("/api/auth/tokens/${id}").send())
    }

    public func listPasskeys(): ArrayList<PasskeyItem> {
        parsePasskeyList(checkedBody(client.get("/api/auth/webauthn/credentials").send()))
    }

    public func revokePasskey(id: Int64): Unit {
        let _ = checked(client.delete("/api/auth/webauthn/credentials/${id}").send())
    }

    public func changeUsername(username: String): Unit {
        let _ = checked(client.post("/api/auth/username").json("{\"username\":${jsonQuote(username)}}").send())
    }

    public func changePassword(newPassword: String): Unit {
        let _ = checked(client.post("/api/auth/password").json("{\"password\":${jsonQuote(newPassword)}}").send())
    }

    // ==================== 设置区扩展：用户管理（admin） ====================

    public func adminUsers(): ArrayList<AdminUserItem> {
        parseAdminUserList(checkedBody(client.get("/api/auth/admin/users").send()))
    }

    public func adminCreateUser(username: String, isAdmin: Bool): String {
        let body = "{\"username\":${jsonQuote(username)},\"isAdmin\":${isAdmin}}"
        let env = checked(client.post("/api/auth/admin/users").json(body).send())
        parseGeneratedPassword("{\"data\":${env.dataRaw}}")
    }

    public func adminSetUserRole(id: Int64, isAdmin: Bool): Unit {
        let _ = checked(client.put("/api/auth/admin/users/${id}/role").body("{\"isAdmin\":${isAdmin}}").send())
    }

    public func adminDeleteUser(id: Int64): Unit {
        let _ = checked(client.delete("/api/auth/admin/users/${id}").send())
    }

    public func adminResetUserPassword(id: Int64, newPassword: String): Unit {
        let _ = checked(
            client
                .post("/api/auth/admin/users/${id}/reset-password")
                .json("{\"password\":${jsonQuote(newPassword)}}")
                .send())
    }

    // ==================== 设置区扩展：系统设置 ====================

    public func systemSettings(): ArrayList<SysSetting> {
        parseSysSettings(checkedBody(client.get("/api/admin/system/settings").send()))
    }

    // 批量保存：body {"settings":{"KEY":"value",...}}（system_settings_controller batchUpdate）。
    public func saveSystemSettings(entries: ArrayList<(String, String)>): Unit {
        var inner = ""
        for (i in 0..entries.size) {
            let (k, v) = entries[i]
            if (i > 0) {
                inner += ","
            }
            inner += "${jsonQuote(k)}:${jsonQuote(v)}"
        }
        let _ = checked(client.put("/api/admin/system/settings/batch").body("{\"settings\":{${inner}}}").send())
    }

    // ==================== 设置区扩展：分类管理（admin） ====================

    public func adminCategories(): ArrayList<AdminCategoryItem> {
        parseAdminCategoryList(checkedBody(client.get("/api/admin/categories").send()))
    }

    public func createCategory(jsonBody: String): Unit {
        let _ = checked(client.post("/api/categories").json(jsonBody).send())
    }

    public func updateCategory(catid: String, jsonBody: String): Unit {
        let _ = checked(client.put("/api/categories/${catid}").body(jsonBody).send())
    }

    public func deleteCategory(catid: String): Unit {
        let _ = checked(client.delete("/api/categories/${catid}").send())
    }

    public func scanCategory(catid: String): Unit {
        let _ = checked(client.post("/api/categories/${catid}/scan").json("{}").send())
    }

    public func scanAllCategories(): Unit {
        let _ = checked(client.post("/api/categories/scan").json("{}").send())
    }

    // ==================== 设置区扩展：标签管理（admin） ====================

    // 标签列表用公开组 /api/tags（分页/筛选），写操作走 /api/admin/tags。
    public func adminTagPage(q: String, ns: String, offset: Int64, limit: Int64): TagListPage {
        var url = "/api/tags?offset=${offset}&limit=${limit}"
        if (q.size > 0) {
            url += "&q=${percentEncode(q)}"
        }
        if (ns.size > 0) {
            url += "&namespace=${percentEncode(ns)}"
        }
        parseTagListPage(checkedBody(client.get(url).send()))
    }

    public func adminTagNamespaces(): ArrayList<String> {
        // 响应 data 形态是 {"namespaces": [...]}（tag_controller.listNamespaces 经 successJson 包裹）。
        parseStringArray(dataArrayRaw(checkedBody(client.get("/api/tags/namespaces").send()), "namespaces"))
    }

    public func createTag(jsonBody: String): Unit {
        let _ = checked(client.post("/api/admin/tags").json(jsonBody).send())
    }

    public func updateTag(id: Int64, jsonBody: String): Unit {
        let _ = checked(client.put("/api/admin/tags/${id}").body(jsonBody).send())
    }

    public func deleteTag(id: Int64): Unit {
        let _ = checked(client.delete("/api/admin/tags/${id}").send())
    }

    // ==================== 设置区扩展：智能分类 ====================

    public func smartFilters(): ArrayList<SmartFilterItem> {
        parseSmartFilterList(checkedBody(client.get("/api/admin/smart_filters").send()))
    }

    public func createSmartFilter(jsonBody: String): Unit {
        let _ = checked(client.post("/api/admin/smart_filters").json(jsonBody).send())
    }

    public func updateSmartFilter(id: Int64, jsonBody: String): Unit {
        let _ = checked(client.put("/api/admin/smart_filters/${id}").body(jsonBody).send())
    }

    public func deleteSmartFilter(id: Int64): Unit {
        let _ = checked(client.delete("/api/admin/smart_filters/${id}").send())
    }

    public func toggleSmartFilter(id: Int64): Unit {
        let _ = checked(client.post("/api/admin/smart_filters/${id}/toggle").json("{}").send())
    }

    public func reorderSmartFilters(ids: ArrayList<Int64>): Unit {
        var arr = ""
        for (i in 0..ids.size) {
            if (i > 0) {
                arr += ","
            }
            arr += "${ids[i]}"
        }
        let _ = checked(client.post("/api/admin/smart_filters/reorder").json("{\"ids\":[${arr}]}").send())
    }

    // ==================== 设置区扩展：插件管理 ====================

    public func plugins(): ArrayList<PluginItem> {
        parsePluginList(checkedBody(client.get("/api/admin/plugins").send()))
    }

    public func pluginParams(ns: String): ArrayList<PluginParam> {
        parsePluginParams(checkedBody(client.get("/api/admin/plugins/${percentEncode(ns)}/config").send()))
    }

    public func savePluginConfig(ns: String, jsonBody: String): Unit {
        let _ = checked(client.put("/api/admin/plugins/${percentEncode(ns)}/config").body(jsonBody).send())
    }

    public func setPluginEnabled(ns: String, enabled: Bool): Unit {
        let _ = checked(
            client.put("/api/admin/plugins/${percentEncode(ns)}/enabled").body("{\"enabled\":${enabled}}").send())
    }

    public func deletePlugin(ns: String): Unit {
        let _ = checked(client.delete("/api/admin/plugins/${percentEncode(ns)}").send())
    }

    // ==================== 设置区扩展：定时任务（cron） ====================

    public func cronStatus(): CronStatus {
        parseCronStatus(checkedBody(client.get("/api/admin/cron/status").send()))
    }

    public func cronStart(): Unit {
        let _ = checked(client.post("/api/admin/cron/start").json("{}").send())
    }

    public func cronStop(): Unit {
        let _ = checked(client.post("/api/admin/cron/stop").json("{}").send())
    }

    public func cronTasks(): ArrayList<CronTask> {
        parseCronTaskList(checkedBody(client.get("/api/admin/cron/tasks").send()))
    }

    public func cronTaskTypes(): ArrayList<CronTaskType> {
        parseCronTaskTypes(checkedBody(client.get("/api/admin/cron/task-types").send()))
    }

    public func cronValidate(expr: String): CronValidateResult {
        parseCronValidate(
            checkedBody(client.post("/api/admin/cron/validate").json("{\"expression\":${jsonQuote(expr)}}").send()))
    }

    public func cronCreateTask(jsonBody: String): Unit {
        let _ = checked(client.post("/api/admin/cron/tasks").json(jsonBody).send())
    }

    public func cronUpdateTask(id: Int64, jsonBody: String): Unit {
        let _ = checked(client.put("/api/admin/cron/tasks/${id}").body(jsonBody).send())
    }

    public func cronDeleteTask(id: Int64): Unit {
        let _ = checked(client.delete("/api/admin/cron/tasks/${id}").send())
    }

    public func cronTrigger(id: Int64): Unit {
        let _ = checked(client.post("/api/admin/cron/tasks/${id}/trigger").json("{}").send())
    }

    public func cronSetEnabled(id: Int64, enabled: Bool): Unit {
        let action = if (enabled) {
            "enable"
        } else {
            "disable"
        }
        let _ = checked(client.post("/api/admin/cron/tasks/${id}/${action}").json("{}").send())
    }

    public func cancelTask(id: Int64): Unit {
        let _ = checked(client.post("/api/admin/taskpool/${id}/cancel").json("{}").send())
    }

    public func retryTask(id: Int64): Unit {
        let _ = checked(client.post("/api/admin/taskpool/${id}/retry").json("{}").send())
    }

    // ==================== 设置区扩展：任务记录（SSE 实时订阅） ====================

    // 持续订阅 /api/admin/taskpool/tasks（SSE）：服务端首帧 snapshot 即全量分页，此后
    // 每次列表变化推一整页 tasks 帧；ping 心跳帧跳过。onPage 返回 false 表示调用方取消，
    // 函数随即关闭流并正常返回；连接中断/读取异常抛异常，由调用方决定重连
    // （对齐 web 前端 EventSource 断线自动重连）。
    public func streamTaskList(status: String, pageSize: Int64, onPage: (TaskListPage) -> Bool): Unit {
        var url = "/api/admin/taskpool/tasks?page=1&pageSize=${pageSize}"
        if (status != "all" && status.size > 0) {
            url += "&status=${status}"
        }
        let resp = client.request(Method.GET, url).header("Accept", "text/event-stream").send()
        if (resp.status == 401) {
            resp.close()
            throw ApiException(401, "登录状态已失效，请重新登录")
        }
        if (!resp.isSuccess()) {
            resp.close()
            throw ApiException(resp.status, "HTTP ${resp.status}")
        }
        let stream = resp.stream()
        try {
            readSseStream(stream, {
                event, data => if (event == "ping") {
                    true
                } else {
                    onPage(parseTaskListPage(data))
                }
            })
        } finally {
            // SSE 流不读完，关闭响应即丢弃连接（不回池）；resp.close() 幂等。
            resp.close()
        }
    }
}

private func safeDownloadName(raw: String, fallback: String): String {
    let source = if (raw.trimAscii().size > 0) {
        raw.trimAscii()
    } else {
        fallback
    }
    let out = StringBuilder()
    for (r in source.runes()) {
        if (r == r'/' || r == r'\\' || r == r'\0' || r == r':' || r == r'*' || r == r'?' || r == r'"' || r == r'<' ||
            r == r'>' || r == r'|') {
            out.append(r'_')
        } else {
            out.append(r)
        }
    }
    let value = out.toString().trimAscii()
    if (value.size > 0 && value != "." && value != "..") {
        value
    } else {
        "archive"
    }
}
