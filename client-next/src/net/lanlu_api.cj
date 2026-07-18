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
    public init() {
        super("该账号启用了二步验证（TOTP），桌面客户端暂不支持")
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
        let env = parseEnvelope(checkedBody(client.get("/api/info")))
        JsonCodec.decode<ServerInfo>(env.dataRaw)
    }

    public func login(username: String, password: String): LoginData {
        let body = "{\"username\":${jsonQuote(username)},\"password\":${jsonQuote(password)},\"tokenName\":\"lanlu-desktop\"}"
        let resp = client.postJson("/api/auth/login", body)
        if (resp.status == 202) { throw TotpRequired() }
        // 服务端对用户名/密码错误也返回 401（{"code":401,"message":"invalid credentials"}），
        // 不能走 checked() 的“登录状态已失效”文案——那是会话过期专用，此处特判为凭据错误。
        if (resp.status == 401) { throw ApiException(401, "用户名或密码错误") }
        let env = checked(resp)
        let d = JsonCodec.decode<LoginData>(env.dataRaw)
        if (d.token.size == 0) { throw ApiException(0, "登录响应缺少 token") }
        setToken(d.token)
        return d
    }

    public func me(): LoginData {
        let env = checked(client.get("/api/auth/me"))
        // /api/auth/me 的 data 是 user 对象；包装成 LoginData（token 为空）。
        let d = JsonCodec.decode<LoginData>("{\"user\":${env.dataRaw},\"token\":{\"token\":\"\"}}")
        return d
    }

    public func search(q: SearchQuery): SearchPage {
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
}
