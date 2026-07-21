package lanlu_client_next.net

import ignite.client.*
import std.collection.ArrayList
import std.sync.Mutex

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
        synchronized(mutex) { token = t }
    }
    func get(): String {
        synchronized(mutex) { return token }
    }
}

public class LanluApi {
    private let client: RestClient
    private let store = TokenStore()
    private let base: String

    public init(baseUrl: String) {
        var b = baseUrl.trimAscii()
        while (b.endsWith("/")) { b = b[0..b.size - 1] }
        base = b
        let s = store
        client = RestClient(readTimeout: Duration.second * 30, writeTimeout: Duration.second * 30, poolSize: 8)
            .baseUrl(base)
            .onRequest({ req =>
                let t = s.get()
                if (t.size > 0) { req.header("Authorization", "Bearer ${t}") }
            })
    }

    public func setToken(token: String): Unit { store.set(token) }
    public func close(): Unit { client.close() }

    private func checked(resp: ClientResponse): Envelope {
        if (resp.status == 401) { throw ApiException(401, "登录状态已失效，请重新登录") }
        if (!resp.isSuccess()) { throw ApiException(resp.status, resp.body()) }
        parseEnvelope(resp.body())
    }

    private func checkedBytes(resp: ClientResponse): Array<UInt8> {
        if (resp.status == 401) { throw ApiException(401, "登录状态已失效，请重新登录") }
        if (!resp.isSuccess()) { throw ApiException(resp.status, "HTTP ${resp.status}") }
        resp.bodyBytes()
    }

    // parseCategoryList/parseArchiveMeta 需要完整响应体而非已解包的 envelope。
    private func checkedBody(resp: ClientResponse): String {
        if (resp.status == 401) { throw ApiException(401, "登录状态已失效，请重新登录") }
        if (!resp.isSuccess()) { throw ApiException(resp.status, resp.body()) }
        resp.body()
    }

    public func info(): ServerInfo {
        // /api/info 返回裸 JSON 对象（无包络），unwrapDataRaw 兼容两种形态。
        JsonCodec.decode<ServerInfo>(unwrapDataRaw(checkedBody(client.get("/api/info"))))
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
        if (resp.status == 401) { throw ApiException(401, "用户名或密码错误") }
        let env = checked(resp)
        let d = JsonCodec.decode<LoginData>(env.dataRaw)
        if (d.token.size == 0) { throw ApiException(0, "登录响应缺少 token") }
        setToken(d.token)
        return d
    }

    // TOTP 二次验证：POST /api/auth/login/totp/verify，响应形态与 login 一致（token+user）。
    // 401 = 验证码/恢复码错误（服务端 "invalid totp or recovery code"），不是会话失效，特判文案。
    public func verifyTotpLogin(challengeId: String, code: String, recoveryCode: String): LoginData {
        let body = "{\"challengeId\":${jsonQuote(challengeId)},\"code\":${jsonQuote(code)},\"recoveryCode\":${jsonQuote(recoveryCode)}}"
        let resp = client.postJson("/api/auth/login/totp/verify", body)
        if (resp.status == 401) { throw ApiException(401, "验证码或恢复码错误") }
        let env = checked(resp)
        let d = JsonCodec.decode<LoginData>(env.dataRaw)
        if (d.token.size == 0) { throw ApiException(0, "登录响应缺少 token") }
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
        if (resp.status == 401) { throw ApiException(401, "登录状态已失效，请重新登录") }
        if (!resp.isSuccess()) { throw ApiException(resp.status, resp.body()) }
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
        if (resp.status == 401) { throw ApiException(401, "登录状态已失效，请重新登录") }
        if (!resp.isSuccess()) { throw ApiException(resp.status, resp.body()) }
        parseSearchPage(resp.body())
    }

    public func categories(): ArrayList<CategoryItem> {
        parseCategoryList(checkedBody(client.get("/api/categories")))
    }

    public func metadata(arcid: String): ArchiveMeta {
        parseArchiveMeta(checkedBody(client.get("/api/archives/${arcid}/metadata")))
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

    // 档案所属合集：GET /api/archives/:id/tankoubons，响应形态同合集列表。
    public func listArchiveTankoubons(arcid: String): ArrayList<TankoubonInfo> {
        parseTankoubonList(checkedBody(client.get("/api/archives/${arcid}/tankoubons")))
    }

    // 相关推荐（档案详情）：GET /api/recommendations?scene=archive_related&archive_id=X
    // 返回裸 {"scene":...,"data":[...]}，data 数组元素与 search 条目同构，复用 parseSearchPage；
    // 混进的合集项没有 arcid，过滤丢弃（对齐 frontend getArchiveRelated 的 isArchiveItem 过滤）。
    public func relatedArchives(arcid: String, count: Int64): ArrayList<SearchItem> {
        let body = checkedBody(client.get(
            "/api/recommendations?scene=archive_related&archive_id=${percentEncode(arcid)}&count=${count}"))
        let page = parseSearchPage(body)
        let list = ArrayList<SearchItem>()
        for (it in page.items) {
            if (it.arcid.size > 0) { list.add(it) }
        }
        list
    }

    // 相关推荐（合集详情）：scene=tankoubon_related，元素为合集对象（recommendations 形态，
    // assets 为对象），复用 parseTankoubonList；过滤掉无 id 的档案项。
    public func relatedTankoubons(tankid: String, count: Int64): ArrayList<TankoubonInfo> {
        let body = checkedBody(client.get(
            "/api/recommendations?scene=tankoubon_related&tankoubon_id=${percentEncode(tankid)}&count=${count}"))
        let all = parseTankoubonList(body)
        let list = ArrayList<TankoubonInfo>()
        for (t in all) {
            if (t.id.size > 0) { list.add(t) }
        }
        list
    }

    public func pageBytes(arcid: String, pagePath: String): Array<UInt8> {
        checkedBytes(client.get(pageUrl(arcid, pagePath)))
    }

    public func assetUrl(assetId: Int64): String { "/api/assets/${assetId}" }
    public func pageUrl(arcid: String, pagePath: String): String {
        "/api/archives/${arcid}/page?path=${percentEncode(pagePath)}"
    }

    public func setProgress(arcid: String, page: Int64): Unit {
        let _ = checked(client.put("/api/archives/${arcid}/progress/${page}", ""))
    }

    public func setFavorite(arcid: String, fav: Bool): Unit {
        if (fav) { let _ = checked(client.put("/api/archives/${arcid}/favorite", "")) }
        else { let _ = checked(client.delete("/api/archives/${arcid}/favorite")) }
    }

    public func setIsNew(arcid: String, isNew: Bool): Unit {
        if (isNew) { let _ = checked(client.put("/api/archives/${arcid}/isnew", "")) }
        else { let _ = checked(client.delete("/api/archives/${arcid}/isnew")) }
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
        let _ = checked(client.postJson("/api/auth/admin/users/${id}/reset-password",
            "{\"password\":${jsonQuote(newPassword)}}"))
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
            if (i > 0) { inner += "," }
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
        if (q.size > 0) { url += "&q=${percentEncode(q)}" }
        if (ns.size > 0) { url += "&namespace=${percentEncode(ns)}" }
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
            if (i > 0) { arr += "," }
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
        parseCronValidate(checkedBody(client.postJson("/api/admin/cron/validate",
            "{\"expression\":${jsonQuote(expr)}}")))
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
        let action = if (enabled) { "enable" } else { "disable" }
        let _ = checked(client.postJson("/api/admin/cron/tasks/${id}/${action}", "{}"))
    }

    public func cancelTask(id: Int64): Unit {
        let _ = checked(client.postJson("/api/admin/taskpool/${id}/cancel", "{}"))
    }

    public func retryTask(id: Int64): Unit {
        let _ = checked(client.postJson("/api/admin/taskpool/${id}/retry", "{}"))
    }

    // ==================== 设置区扩展：任务记录（SSE 首帧快照） ====================

    // /api/admin/taskpool/tasks 只有 SSE 形态（首帧 snapshot 即全量分页），
    // 用 bodyStream 增量读到首个完整 data 帧即停；SSE 响应永不结束，
    // 必须显式关闭流释放底层连接（try/finally 覆盖解析异常路径）。
    public func taskListSnapshot(status: String, page: Int64, pageSize: Int64): TaskListPage {
        var url = "/api/admin/taskpool/tasks?page=${page}&pageSize=${pageSize}"
        if (status != "all" && status.size > 0) { url += "&status=${status}" }
        let resp = client.request().method("GET").url(url)
            .header("Accept", "text/event-stream").send()
        if (resp.status == 401) { throw ApiException(401, "登录状态已失效，请重新登录") }
        if (!resp.isSuccess()) { throw ApiException(resp.status, "HTTP ${resp.status}") }
        let stream = resp.bodyStream()
        try {
            let text = readSseSnapshot(stream)
            match (sseFirstData(text)) {
                case Some(data) => parseTaskListPage(data)
                case None => throw ApiException(0, "任务列表快照读取失败（未收到完整 SSE 帧）")
            }
        } finally {
            // InputStream 接口未静态暴露 close，底层实现均为 Resource，转型后关闭。
            match (stream as Resource) {
                case Some(r) => r.close()
                case None => ()
            }
        }
    }
}
