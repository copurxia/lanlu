package lanlu_client_next.net

import ignite.client.*
import std.collection.ArrayList
import std.fs.{File, FileInfo, OpenMode, Path}
import std.sync.{Mutex, SyncCounter}

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

// 看门狗共享状态箱：spawn 的 lambda 不能捕获可变局部变量，装箱后只捕获不可变引用。
private class WatchdogBox<T> {
    var result: ?T = None
    var failure: ?Exception = None
}

public class LanluApi {
    private let client: RestClient
    private let uploadClient: RestClient
    private let store = TokenStore()
    private let base: String
    // 连接硬超时（仅 info() 生效，见 info 注释）：None = 不设（默认行为不变）。
    private let connectTimeout: ?Duration

    public init(baseUrl: String, connectTimeout!: ?Duration = None) {
        var b = baseUrl.trimAscii()
        while (b.endsWith("/")) {
            b = b[0..b.size - 1]
        }
        base = b
        this.connectTimeout = connectTimeout
        let s = store
        client = RestClient(readTimeout: Duration.second * 30, writeTimeout: Duration.second * 30, poolSize: 8)
            .baseUrl(base)
            .onRequest(
                {
                    req =>
                        let t = s.get()
                        if (t.size > 0) {
                            req.header("Authorization", "Bearer ${t}")
                        }
                }
            )
        uploadClient = RestClient(readTimeout: Duration.second * 600, writeTimeout: Duration.second * 600, poolSize: 4)
            .baseUrl(base)
            .onRequest(
                {
                    req =>
                        let t = s.get()
                        if (t.size > 0) {
                            req.header("Authorization", "Bearer ${t}")
                        }
                }
            )
    }

    public func setToken(token: String): Unit {
        store.set(token)
    }
    public func close(): Unit {
        client.close()
        uploadClient.close()
    }

    private func checked(resp: ClientResponse): Envelope {
        if (resp.status == 401) {
            throw ApiException(401, "登录状态已失效，请重新登录")
        }
        if (!resp.isSuccess()) {
            throw ApiException(resp.status, resp.body())
        }
        parseEnvelope(resp.body())
    }

    private func checkedBytes(resp: ClientResponse): Array<UInt8> {
        if (resp.status == 401) {
            throw ApiException(401, "登录状态已失效，请重新登录")
        }
        if (!resp.isSuccess()) {
            // 页面/媒体接口的服务端错误体包含归档路径、条目读取等具体原因。保留它，
            // 否则播放层只能显示无诊断价值的 “HTTP 500”。
            let detail = resp.body().trimAscii()
            throw ApiException(resp.status, if (detail.size > 0) {
                "HTTP ${resp.status}: ${detail}"
            } else {
                "HTTP ${resp.status}"
            })
        }
        resp.bodyBytes()
    }

    // parseCategoryList/parseArchiveMeta 需要完整响应体而非已解包的 envelope。
    private func checkedBody(resp: ClientResponse): String {
        if (resp.status == 401) {
            throw ApiException(401, "登录状态已失效，请重新登录")
        }
        if (!resp.isSuccess()) {
            throw ApiException(resp.status, resp.body())
        }
        resp.body()
    }

    // ignite RestClient / stdx ClientBuilder 均无 connectTimeout 配置（connector 注入也无法
    // 穿过 RestClient），而 probe/登录前探测场景最怕的是 TCP connect 挂死（OS 默认重传可达
    // 分钟级）。这里用看门狗实现等效硬超时：构造时传入 connectTimeout 后，info() 在独立
    // 线程执行、调用方按超时等待；超时即抛 ApiException，残留的阻塞线程待其自行返回后回收
    //（次数受探测频率约束，无累积风险）。只包 info()：页面/媒体等大响应不承受总时长上限。
    public func info(): ServerInfo {
        match (connectTimeout) {
            case Some(t) => withHardTimeout(t, {=> fetchInfo()})
            case None => fetchInfo()
        }
    }

    private func fetchInfo(): ServerInfo {
        // /api/info 返回裸 JSON 对象（无包络），unwrapDataRaw 兼容两种形态。
        JsonCodec.decode<ServerInfo>(unwrapDataRaw(checkedBody(client.get("/api/info"))))
    }

    private func withHardTimeout<T>(t: Duration, f: () -> T): T {
        let done = SyncCounter(1)
        // 仓颉限制：捕获可变局部变量的 lambda 只能直接调用（不能 spawn），
        // 故共享状态装箱，spawn 只捕获不可变的箱引用。
        let box = WatchdogBox<T>()
        let _ = spawn {
            try {
                box.result = Some(f())
            } catch (e: Exception) {
                box.failure = Some(e)
            }
            done.dec()
        }
        done.waitUntilZero(timeout: t)
        if (done.count > 0) {
            throw ApiException(0, "连接超时（${t.toMilliseconds()}ms 内未建立连接）")
        }
        match (box.failure) {
            case Some(e) => throw e
            case None => ()
        }
        match (box.result) {
            case Some(v) => v
            case None => throw ApiException(0, "连接失败")
        }
    }

    public func login(username: String, password: String): LoginData {
        let body = "{\"username\":${jsonQuote(username)},\"password\":${jsonQuote(password)},\"tokenName\":\"lanlu-desktop\"}"
        let resp = client.postJson("/api/auth/login", body)
        if (resp.status == 202) {
            let env = parseEnvelope(resp.body())
            throw TotpRequired(JsonCodec.decode<LoginPendingTotp>(env.dataRaw).challengeId)
        }
        // 服务端对用户名/密码错误也返回 401（{"code":401,"message":"invalid credentials"}），
        // 不能走 checked() 的“登录状态已失效”文案——那是会话过期专用，此处特判为凭据错误。
        if (resp.status == 401) {
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
        let resp = client.postJson("/api/auth/login/totp/verify", body)
        if (resp.status == 401) {
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
        let env = checked(client.get("/api/auth/me"))
        // /api/auth/me 的 data 是 {"user": {...}}（UserDataView 序列化形态），
        // 直接解 LoginData 即可（token 缺省为空串）——不能再包一层 {"user": ...}，
        // 否则双重嵌套导致 username/isAdmin 全部解析落空。
        JsonCodec.decode<LoginData>(env.dataRaw)
    }

    public func search(q: SearchQuery): SearchPage {
        let resp = client.get("/api/search${buildSearchQuery(q)}")
        if (resp.status == 401) {
            throw ApiException(401, "登录状态已失效，请重新登录")
        }
        if (!resp.isSuccess()) {
            throw ApiException(resp.status, resp.body())
        }
        parseSearchPage(resp.body())
    }

    // 随机推荐：服务端没有 /api/search/random 路由（routes/api/search.cj 只注册 GET /api/search），
    // 随机能力由 /api/search?sortby=RANDOM() 提供——archive_dao.cj 对 sortby=="RANDOM()"
    // 特判为 ORDER BY RANDOM() DESC（括号字面量经 query 解码后还原）。响应形态与
    // /api/search 完全一致，复用 SearchQuery 构造与 parseSearchPage 解析。
    public func randomSearch(count: Int64): SearchPage {
        let q = SearchQuery()
        q.sortby = "RANDOM()"
        q.pageSize = count
        let resp = client.get("/api/search${buildSearchQuery(q)}")
        if (resp.status == 401) {
            throw ApiException(401, "登录状态已失效，请重新登录")
        }
        if (!resp.isSuccess()) {
            throw ApiException(resp.status, resp.body())
        }
        parseSearchPage(resp.body())
    }

    public func categories(): ArrayList<CategoryItem> {
        parseCategoryList(checkedBody(client.get("/api/categories")))
    }

    public func metadata(arcid: String): ArchiveMeta {
        parseArchiveMeta(checkedBody(client.get("/api/archives/${arcid}/metadata")))
    }

    public func updateArchiveMetadata(arcid: String, body: String): Unit {
        let _ = checked(client.put("/api/archives/${percentEncode(arcid)}/metadata", body))
    }

    public func files(arcid: String): ArrayList<PageInfo> {
        parsePages(checkedBody(client.get("/api/archives/${arcid}/files")))
    }

    public func assetBytes(assetId: Int64): Array<UInt8> {
        checkedBytes(client.get("/api/assets/${assetId}"))
    }

    // 合集列表：GET /api/tankoubons 返回裸 {"filtered":N,"result":[...],"total":N}（无包络）。
    public func listTankoubons(): ArrayList<TankoubonInfo> {
        parseTankoubonList(checkedBody(client.get("/api/tankoubons")))
    }

    // 单个合集：GET /api/tankoubons/:id/metadata 返回裸对象（children 为 member 对象数组）。
    public func getTankoubon(id: String): TankoubonInfo {
        parseTankoubon(checkedBody(client.get("/api/tankoubons/${id}/metadata")))
    }

    public func updateTankoubonMetadata(id: String, body: String): Unit {
        let _ = checked(client.put("/api/tankoubons/${percentEncode(id)}/metadata", body))
    }

    public func deleteArchive(arcid: String): Unit {
        let _ = checked(client.delete("/api/archives/${percentEncode(arcid)}"))
    }

    public func deleteTankoubon(id: String): Unit {
        let _ = checked(client.delete("/api/tankoubons/${percentEncode(id)}"))
    }

    // 新建合集：PUT /api/tankoubons?name=X（name 在 query），响应 data 为 {success, tankoubon_id}。
    public func createTankoubon(name: String): String {
        let env = checked(client.put("/api/tankoubons?name=${percentEncode(name)}", ""))
        uploadResultText(env.dataRaw, "tankoubon_id")
    }

    // 合集成员增删：PUT/DELETE /api/tankoubons/{tankId}/{arcid}。
    public func addTankMember(tankId: String, arcid: String): Unit {
        let _ = checked(client.put("/api/tankoubons/${percentEncode(tankId)}/${percentEncode(arcid)}", ""))
    }

    public func removeTankMember(tankId: String, arcid: String): Unit {
        let _ = checked(client.delete("/api/tankoubons/${percentEncode(tankId)}/${percentEncode(arcid)}"))
    }

    // 档案所属合集：GET /api/archives/:id/tankoubons，响应形态同合集列表。
    public func listArchiveTankoubons(arcid: String): ArrayList<TankoubonInfo> {
        parseTankoubonList(checkedBody(client.get("/api/archives/${arcid}/tankoubons")))
    }

    // 相关推荐（档案详情）：GET /api/recommendations?scene=archive_related&archive_id=X
    // 返回裸 {"scene":...,"data":[...]}，data 数组元素与 search 条目同构，复用 parseSearchPage；
    // 混进的合集项没有 arcid，过滤丢弃（对齐 frontend getArchiveRelated 的 isArchiveItem 过滤）。
    public func relatedArchives(arcid: String, count: Int64): ArrayList<SearchItem> {
        let body = checkedBody(
            client.get("/api/recommendations?scene=archive_related&archive_id=${percentEncode(arcid)}&count=${count}"))
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
    public func relatedTankoubons(tankid: String, count: Int64): ArrayList<TankoubonInfo> {
        let body = checkedBody(
            client.get(
                "/api/recommendations?scene=tankoubon_related&tankoubon_id=${percentEncode(tankid)}&count=${count}"))
        let all = parseTankoubonList(body)
        let list = ArrayList<TankoubonInfo>()
        for (t in all) {
            if (t.id.size > 0) {
                list.add(t)
            }
        }
        list
    }

    public func pageBytes(arcid: String, pagePath: String): Array<UInt8> {
        checkedBytes(client.get(pageUrl(arcid, pagePath)))
    }

    public func assetUrl(assetId: Int64): String {
        "/api/assets/${assetId}"
    }
    public func pageUrl(arcid: String, pagePath: String): String {
        "/api/archives/${arcid}/page?path=${percentEncode(pagePath)}"
    }

    public func setProgress(arcid: String, page: Int64): Unit {
        let _ = checked(client.put("/api/archives/${arcid}/progress/${page}", ""))
    }

    public func setFavorite(arcid: String, fav: Bool): Unit {
        if (fav) {
            let _ = checked(client.put("/api/archives/${arcid}/favorite", ""))
        } else {
            let _ = checked(client.delete("/api/archives/${arcid}/favorite"))
        }
    }

    public func setTankFavorite(tankid: String, fav: Bool): Unit {
        if (fav) {
            let _ = checked(client.put("/api/tankoubons/${tankid}/favorite", ""))
        } else {
            let _ = checked(client.delete("/api/tankoubons/${tankid}/favorite"))
        }
    }

    public func setIsNew(arcid: String, isNew: Bool): Unit {
        if (isNew) {
            let _ = checked(client.put("/api/archives/${arcid}/isnew", ""))
        } else {
            let _ = checked(client.delete("/api/archives/${arcid}/isnew"))
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
        let initResponse = uploadClient.postJson("/api/assets/upload/init", body)
        if (initResponse.status == 409) {
            let result = ArchiveUploadResult()
            result.fileExists = true
            let envelope = parseEnvelope(initResponse.body())
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
        let raw = checkedBody(client.postJson("/api/download_url", body))
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
        parseUploadTaskSnapshot(checkedBody(client.get("/api/admin/taskpool/${taskId}")))
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
                .request()
                .method("PUT")
                .url("/api/assets/upload/chunk?taskId=${taskId}&chunkIndex=${chunkIndex}&totalChunks=${totalChunks}")
                .header("Content-Type", "application/octet-stream")
                .bodyBytes(chunk)
                .send()
            if (response.isSuccess()) {
                let _ = checked(response)
                return
            }
            let status = response.status
            let detail = response.body()
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
        parseUserStats(checkedBody(client.get("/api/user/stats")))
    }

    public func userTrend(days: Int64): ArrayList<TrendPoint> {
        parseTrendList(checkedBody(client.get("/api/user/trend?days=${days}")))
    }

    public func tagCloud(limit: Int64): ArrayList<CloudTag> {
        parseCloudTags(checkedBody(client.get("/api/tags/cloud?limit=${limit}")))
    }

    public func tagAutocomplete(query: String, limit: Int64): ArrayList<TagSuggestion> {
        let url = "/api/tags/autocomplete?q=${percentEncode(query.trimAscii())}&lang=zh&limit=${limit}" +
            "&require_bound=1"
        parseTagSuggestions(checkedBody(client.get(url)))
    }

    public func totpStatus(): TotpStatus {
        parseTotpStatus(checkedBody(client.get("/api/auth/totp/status")))
    }

    public func totpDisable(): Unit {
        let _ = checked(client.delete("/api/auth/totp"))
    }

    public func totpRegenerate(): ArrayList<String> {
        parseStringArray(checked(client.postJson("/api/auth/totp/recovery-codes/regenerate", "{}")).dataRaw)
    }

    public func listSessions(): ArrayList<SessionItem> {
        parseSessionList(checkedBody(client.get("/api/auth/sessions")))
    }

    public func revokeSession(id: Int64): Unit {
        let _ = checked(client.delete("/api/auth/sessions/${id}"))
    }

    public func revokeOtherSessions(): Unit {
        let _ = checked(client.postJson("/api/auth/sessions/revoke-others", "{}"))
    }

    public func listTokens(): ArrayList<TokenItem> {
        parseTokenList(checkedBody(client.get("/api/auth/tokens")))
    }

    // 创建成功时响应 data 为单个 TokenView 对象，含一次性明文 token（仅此一次可见）。
    public func createToken(name: String): TokenItem {
        let body = "{\"name\":${jsonQuote(name)}}"
        let env = checked(client.postJson("/api/auth/tokens", body))
        parseCreatedToken("{\"data\":${env.dataRaw}}")
    }

    public func revokeToken(id: Int64): Unit {
        let _ = checked(client.delete("/api/auth/tokens/${id}"))
    }

    public func listPasskeys(): ArrayList<PasskeyItem> {
        parsePasskeyList(checkedBody(client.get("/api/auth/webauthn/credentials")))
    }

    public func revokePasskey(id: Int64): Unit {
        let _ = checked(client.delete("/api/auth/webauthn/credentials/${id}"))
    }

    public func changeUsername(username: String): Unit {
        let _ = checked(client.postJson("/api/auth/username", "{\"username\":${jsonQuote(username)}}"))
    }

    public func changePassword(newPassword: String): Unit {
        let _ = checked(client.postJson("/api/auth/password", "{\"password\":${jsonQuote(newPassword)}}"))
    }

    // ==================== 设置区扩展：用户管理（admin） ====================

    public func adminUsers(): ArrayList<AdminUserItem> {
        parseAdminUserList(checkedBody(client.get("/api/auth/admin/users")))
    }

    public func adminCreateUser(username: String, isAdmin: Bool): String {
        let body = "{\"username\":${jsonQuote(username)},\"isAdmin\":${isAdmin}}"
        let env = checked(client.postJson("/api/auth/admin/users", body))
        parseGeneratedPassword("{\"data\":${env.dataRaw}}")
    }

    public func adminSetUserRole(id: Int64, isAdmin: Bool): Unit {
        let _ = checked(client.put("/api/auth/admin/users/${id}/role", "{\"isAdmin\":${isAdmin}}"))
    }

    public func adminDeleteUser(id: Int64): Unit {
        let _ = checked(client.delete("/api/auth/admin/users/${id}"))
    }

    public func adminResetUserPassword(id: Int64, newPassword: String): Unit {
        let _ = checked(
            client.postJson("/api/auth/admin/users/${id}/reset-password", "{\"password\":${jsonQuote(newPassword)}}"))
    }

    // ==================== 设置区扩展：系统设置 ====================

    public func systemSettings(): ArrayList<SysSetting> {
        parseSysSettings(checkedBody(client.get("/api/admin/system/settings")))
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
        let _ = checked(client.put("/api/admin/system/settings/batch", "{\"settings\":{${inner}}}"))
    }

    // ==================== 设置区扩展：分类管理（admin） ====================

    public func adminCategories(): ArrayList<AdminCategoryItem> {
        parseAdminCategoryList(checkedBody(client.get("/api/admin/categories")))
    }

    public func createCategory(jsonBody: String): Unit {
        let _ = checked(client.postJson("/api/categories", jsonBody))
    }

    public func updateCategory(catid: String, jsonBody: String): Unit {
        let _ = checked(client.put("/api/categories/${catid}", jsonBody))
    }

    public func deleteCategory(catid: String): Unit {
        let _ = checked(client.delete("/api/categories/${catid}"))
    }

    public func scanCategory(catid: String): Unit {
        let _ = checked(client.postJson("/api/categories/${catid}/scan", "{}"))
    }

    public func scanAllCategories(): Unit {
        let _ = checked(client.postJson("/api/categories/scan", "{}"))
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
        parseTagListPage(checkedBody(client.get(url)))
    }

    public func adminTagNamespaces(): ArrayList<String> {
        // 响应 data 形态是 {"namespaces": [...]}（tag_controller.listNamespaces 经 successJson 包裹）。
        parseStringArray(dataArrayRaw(checkedBody(client.get("/api/tags/namespaces")), "namespaces"))
    }

    public func createTag(jsonBody: String): Unit {
        let _ = checked(client.postJson("/api/admin/tags", jsonBody))
    }

    public func updateTag(id: Int64, jsonBody: String): Unit {
        let _ = checked(client.put("/api/admin/tags/${id}", jsonBody))
    }

    public func deleteTag(id: Int64): Unit {
        let _ = checked(client.delete("/api/admin/tags/${id}"))
    }

    // ==================== 设置区扩展：智能分类 ====================

    public func smartFilters(): ArrayList<SmartFilterItem> {
        parseSmartFilterList(checkedBody(client.get("/api/admin/smart_filters")))
    }

    public func createSmartFilter(jsonBody: String): Unit {
        let _ = checked(client.postJson("/api/admin/smart_filters", jsonBody))
    }

    public func updateSmartFilter(id: Int64, jsonBody: String): Unit {
        let _ = checked(client.put("/api/admin/smart_filters/${id}", jsonBody))
    }

    public func deleteSmartFilter(id: Int64): Unit {
        let _ = checked(client.delete("/api/admin/smart_filters/${id}"))
    }

    public func toggleSmartFilter(id: Int64): Unit {
        let _ = checked(client.postJson("/api/admin/smart_filters/${id}/toggle", "{}"))
    }

    public func reorderSmartFilters(ids: ArrayList<Int64>): Unit {
        var arr = ""
        for (i in 0..ids.size) {
            if (i > 0) {
                arr += ","
            }
            arr += "${ids[i]}"
        }
        let _ = checked(client.postJson("/api/admin/smart_filters/reorder", "{\"ids\":[${arr}]}"))
    }

    // ==================== 设置区扩展：插件管理 ====================

    public func plugins(): ArrayList<PluginItem> {
        parsePluginList(checkedBody(client.get("/api/admin/plugins")))
    }

    public func pluginParams(ns: String): ArrayList<PluginParam> {
        parsePluginParams(checkedBody(client.get("/api/admin/plugins/${percentEncode(ns)}/config")))
    }

    public func savePluginConfig(ns: String, jsonBody: String): Unit {
        let _ = checked(client.put("/api/admin/plugins/${percentEncode(ns)}/config", jsonBody))
    }

    public func setPluginEnabled(ns: String, enabled: Bool): Unit {
        let _ = checked(client.put("/api/admin/plugins/${percentEncode(ns)}/enabled", "{\"enabled\":${enabled}}"))
    }

    public func deletePlugin(ns: String): Unit {
        let _ = checked(client.delete("/api/admin/plugins/${percentEncode(ns)}"))
    }

    // ==================== 设置区扩展：定时任务（cron） ====================

    public func cronStatus(): CronStatus {
        parseCronStatus(checkedBody(client.get("/api/admin/cron/status")))
    }

    public func cronStart(): Unit {
        let _ = checked(client.postJson("/api/admin/cron/start", "{}"))
    }

    public func cronStop(): Unit {
        let _ = checked(client.postJson("/api/admin/cron/stop", "{}"))
    }

    public func cronTasks(): ArrayList<CronTask> {
        parseCronTaskList(checkedBody(client.get("/api/admin/cron/tasks")))
    }

    public func cronTaskTypes(): ArrayList<CronTaskType> {
        parseCronTaskTypes(checkedBody(client.get("/api/admin/cron/task-types")))
    }

    public func cronValidate(expr: String): CronValidateResult {
        parseCronValidate(
            checkedBody(client.postJson("/api/admin/cron/validate", "{\"expression\":${jsonQuote(expr)}}")))
    }

    public func cronCreateTask(jsonBody: String): Unit {
        let _ = checked(client.postJson("/api/admin/cron/tasks", jsonBody))
    }

    public func cronUpdateTask(id: Int64, jsonBody: String): Unit {
        let _ = checked(client.put("/api/admin/cron/tasks/${id}", jsonBody))
    }

    public func cronDeleteTask(id: Int64): Unit {
        let _ = checked(client.delete("/api/admin/cron/tasks/${id}"))
    }

    public func cronTrigger(id: Int64): Unit {
        let _ = checked(client.postJson("/api/admin/cron/tasks/${id}/trigger", "{}"))
    }

    public func cronSetEnabled(id: Int64, enabled: Bool): Unit {
        let action = if (enabled) {
            "enable"
        } else {
            "disable"
        }
        let _ = checked(client.postJson("/api/admin/cron/tasks/${id}/${action}", "{}"))
    }

    public func cancelTask(id: Int64): Unit {
        let _ = checked(client.postJson("/api/admin/taskpool/${id}/cancel", "{}"))
    }

    public func retryTask(id: Int64): Unit {
        let _ = checked(client.postJson("/api/admin/taskpool/${id}/retry", "{}"))
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
        let resp = client.request().method("GET").url(url).header("Accept", "text/event-stream").send()
        if (resp.status == 401) {
            throw ApiException(401, "登录状态已失效，请重新登录")
        }
        if (!resp.isSuccess()) {
            throw ApiException(resp.status, "HTTP ${resp.status}")
        }
        let stream = resp.bodyStream()
        try {
            readSseStream(stream, {
                event, data => if (event == "ping") {
                    true
                } else {
                    onPage(parseTaskListPage(data))
                }
            })
        } finally {
            // InputStream 接口未静态暴露 close，底层实现均为 Resource，转型后关闭。
            match (stream as Resource) {
                case Some(r) => r.close()
                case None => ()
            }
        }
    }
}
