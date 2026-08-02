package qwest

import std.collection.ArrayList
import std.convert.Parsable
import std.net.{SocketException, SocketTimeoutException}

// 客户端构造器。命名与 reqwest 对齐：一个 Client 全局复用（内含连接池），
// 单请求差异用 RequestBuilder.timeout() 覆盖，不必为不同超时建多个客户端。
public class ClientBuilder {
    private var baseUrlValue: String = ""
    private var connectTimeoutValue: ?Duration = None
    private var readTimeoutValue: ?Duration = None
    private var writeTimeoutValue: ?Duration = None
    private var tlsHandshakeTimeoutValue: ?Duration = None
    private var poolMaxIdlePerHostValue: Int64 = 8
    private var poolIdleTtlValue: Duration = Duration.second * 90
    private let defaultHeadersValue = Headers()
    private let interceptorsValue = ArrayList<(RequestBuilder) -> Unit>()
    private var tlsVerifyValue: TlsVerify = TlsVerify.Default
    private var maxRedirectsValue: Int64 = 10
    private var bodyLimitValue: Int64 = 64 * 1024 * 1024

    public init() {}

    // 基地址：请求传相对路径时拼接（尾部 / 自动去除）。
    public func baseUrl(u: String): ClientBuilder {
        baseUrlValue = u.trimAscii()
        this
    }

    public func connectTimeout(d: Duration): ClientBuilder {
        connectTimeoutValue = d
        this
    }

    public func readTimeout(d: Duration): ClientBuilder {
        readTimeoutValue = d
        this
    }

    public func writeTimeout(d: Duration): ClientBuilder {
        writeTimeoutValue = d
        this
    }

    // TLS 握手超时；未设置时复用 connectTimeout（慢证书链/OCSP 场景可单独放宽）。
    public func tlsHandshakeTimeout(d: Duration): ClientBuilder {
        tlsHandshakeTimeoutValue = d
        this
    }

    // 每主机最大空闲连接数（在途连接不受限）。
    public func poolMaxIdlePerHost(n: Int64): ClientBuilder {
        poolMaxIdlePerHostValue = n
        this
    }

    public func poolIdleTtl(d: Duration): ClientBuilder {
        poolIdleTtlValue = d
        this
    }

    // 默认请求头（每个请求都带，同名可被 RequestBuilder.header 覆盖）。
    public func defaultHeader(name: String, value: String): ClientBuilder {
        defaultHeadersValue.set(name, value)
        this
    }

    // 请求拦截器：send 前依次调用（注入 Authorization 等，对应 RestClient onRequest）。
    public func interceptor(f: (RequestBuilder) -> Unit): ClientBuilder {
        interceptorsValue.add(f)
        this
    }

    public func tlsVerify(v: TlsVerify): ClientBuilder {
        tlsVerifyValue = v
        this
    }

    // 最大重定向跳数；0 = 不跟随（3xx 原样返回）。
    public func redirect(max: Int64): ClientBuilder {
        maxRedirectsValue = max
        this
    }

    // bytes()/text() 缓冲上限。
    public func bodyLimit(n: Int64): ClientBuilder {
        bodyLimitValue = n
        this
    }

    public func build(): Client {
        Client(
            baseUrlValue,
            connectTimeoutValue,
            readTimeoutValue,
            writeTimeoutValue,
            tlsHandshakeTimeoutValue,
            poolMaxIdlePerHostValue,
            poolIdleTtlValue,
            defaultHeadersValue,
            interceptorsValue,
            tlsVerifyValue,
            maxRedirectsValue,
            bodyLimitValue
        )
    }
}

// HTTP 客户端：线程安全，内含 keep-alive 连接池，应全局复用。
public class Client {
    private let baseUrl: String
    private let connectTimeout: ?Duration
    private let readTimeout: ?Duration
    private let writeTimeout: ?Duration
    private let tlsHandshakeTimeout: ?Duration
    private let defaultHeaders: Headers
    private let interceptors: ArrayList<(RequestBuilder) -> Unit>
    private let tlsVerify: TlsVerify
    private let maxRedirects: Int64
    private let bodyLimit: Int64
    private let pool: ConnectionPool

    init(
        baseUrl: String,
        connectTimeout: ?Duration,
        readTimeout: ?Duration,
        writeTimeout: ?Duration,
        tlsHandshakeTimeout: ?Duration,
        poolMaxIdlePerHost: Int64,
        poolIdleTtl: Duration,
        defaultHeaders: Headers,
        interceptors: ArrayList<(RequestBuilder) -> Unit>,
        tlsVerify: TlsVerify,
        maxRedirects: Int64,
        bodyLimit: Int64
    ) {
        var b = baseUrl
        while (b.endsWith("/")) {
            b = b[0..b.size - 1]
        }
        this.baseUrl = b
        this.connectTimeout = connectTimeout
        this.readTimeout = readTimeout
        this.writeTimeout = writeTimeout
        this.tlsHandshakeTimeout = tlsHandshakeTimeout
        this.defaultHeaders = defaultHeaders
        this.interceptors = interceptors
        this.tlsVerify = tlsVerify
        this.maxRedirects = maxRedirects
        this.bodyLimit = bodyLimit
        this.pool = ConnectionPool(poolMaxIdlePerHost, poolIdleTtl)
    }

    public func request(method: Method, url: String): RequestBuilder {
        RequestBuilder(this, method, url)
    }

    public func get(url: String): RequestBuilder {
        request(Method.GET, url)
    }

    public func post(url: String): RequestBuilder {
        request(Method.POST, url)
    }

    public func put(url: String): RequestBuilder {
        request(Method.PUT, url)
    }

    public func delete(url: String): RequestBuilder {
        request(Method.DELETE, url)
    }

    public func head(url: String): RequestBuilder {
        request(Method.HEAD, url)
    }

    public func patch(url: String): RequestBuilder {
        request(Method.PATCH, url)
    }

    public func options(url: String): RequestBuilder {
        request(Method.OPTIONS, url)
    }

    // 关闭全部空闲连接。在途请求不受影响（其连接结算时会因池已关闭而直接释放）。
    public func close(): Unit {
        pool.closeAll()
    }

    // 发送入口：拦截器 → URL 解析 → 重定向循环。
    func execute(rb: RequestBuilder): Response {
        for (ic in interceptors) {
            ic(rb)
        }
        var absolute = if (isAbsoluteUrl(rb.urlOrPath)) {
            rb.urlOrPath
        } else {
            if (baseUrl.size == 0) {
                throw ProtocolException("相对路径 ${rb.urlOrPath} 需要先配置 baseUrl")
            }
            joinUrl(baseUrl, rb.urlOrPath)
        }
        if (rb.queryParams.size > 0) {
            let sb = StringBuilder()
            var first = true
            for ((k, v) in rb.queryParams) {
                if (!first) {
                    sb.append("&")
                }
                first = false
                sb.append("${percentEncode(k)}=${percentEncode(v)}")
            }
            absolute = if (absolute.contains("?")) {
                "${absolute}&${sb.toString()}"
            } else {
                "${absolute}?${sb.toString()}"
            }
        }
        // 合并默认头 + 请求头（请求头同名覆盖默认头）。
        let headers = Headers()
        for ((k, v) in defaultHeaders.toArray()) {
            headers.add(k, v)
        }
        for ((k, v) in rb.headers.toArray()) {
            headers.set(k, v)
        }

        var target = HttpTarget.parse(absolute)
        var method = rb.method
        var body = rb.bodyBytes
        var redirectsLeft = maxRedirects
        while (true) {
            let resp = doRequest(method, target, headers, body, rb.timeoutOverride)
            if (!isRedirectStatus(resp.status) || maxRedirects == 0) {
                return resp
            }
            let loc = match (resp.headers.get("Location")) {
                case Some(l) => l
                case None => return resp // 无 Location 的 3xx 原样返回
            }
            if (redirectsLeft == 0) {
                resp.close()
                throw RedirectException("超过最大重定向次数 ${maxRedirects}")
            }
            redirectsLeft--
            resp.drain() // 读掉旧响应体，尽量让连接可复用
            let next = HttpTarget.parse(resolveLocation(target, loc))
            // 跨源（host/port/scheme 任一变化）丢弃 Authorization，防凭据泄漏（同 reqwest）。
            if (next.host != target.host || next.port != target.port || next.scheme != target.scheme) {
                headers.remove("Authorization")
            }
            // 303 一律转 GET；301/302 对 POST 转 GET（浏览器/reqwest 惯例）。
            if (resp.status == 303 || ((resp.status == 301 || resp.status == 302) && method == Method.POST)) {
                method = Method.GET
                body = None
                headers.remove("Content-Type")
            }
            target = next
        }
        throw HttpException("unreachable")
    }

    // 单次收发（带池化连接透明重试）：复用的空闲连接可能已被对端关闭，写请求/读状态行
    // 阶段的连接级失败重试一次新连接；v1 请求体全在内存，重发安全。
    private func doRequest(
        method: Method,
        target: HttpTarget,
        headers: Headers,
        body: ?Array<UInt8>,
        timeoutOverride: ?Duration
    ): Response {
        let readT = pickTimeout(timeoutOverride, readTimeout)
        let writeT = pickTimeout(timeoutOverride, writeTimeout)
        var attempt = 0
        while (true) {
            var reused = true
            let conn = match (pool.take(target.poolKey())) {
                case Some(c) => c
                case None =>
                    reused = false
                    Connection.open(target, connectTimeout, tlsHandshakeTimeout, tlsVerify)
            }
            conn.setTimeouts(readT, writeT)
            try {
                let contentLength: ?Int64 = match (body) {
                    case Some(b) => Some(b.size)
                    case None => if (method.expectsBody()) {
                        Some(0)
                    } else {
                        None
                    }
                }
                // 写阶段单独捕超时，区分 kind=write（外层 SocketTimeoutException 归为 read）。
                try {
                    conn.write(encodeRequestHead(method, target, headers, contentLength))
                    match (body) {
                        case Some(b) => if (b.size > 0) {
                            conn.write(b)
                        }
                        case None => ()
                    }
                } catch (e: SocketTimeoutException) {
                    throw HttpTimeoutException("write", "写请求超时: ${e.message}")
                }
                let head = readResponseHead(conn.reader)
                return buildResponse(method, head, conn)
            } catch (e: ConnectionClosedException) {
                conn.close()
                if (reused && attempt == 0) {
                    attempt++
                    continue
                }
                throw HttpException("连接已被对端关闭")
            } catch (e: SocketTimeoutException) {
                conn.close()
                throw HttpTimeoutException("read", "等待响应超时: ${e.message}")
            } catch (e: SocketException) {
                conn.close()
                if (reused && attempt == 0) {
                    attempt++
                    continue
                }
                throw HttpException("网络错误: ${e.message}")
            } catch (e: Exception) {
                conn.close()
                throw e
            }
        }
        throw HttpException("unreachable")
    }

    // 按响应头选定 body 分帧，组装 Response。
    private func buildResponse(method: Method, head: ResponseHead, conn: Connection): Response {
        let body: HttpBody = if (method == Method.HEAD || head.status == 204 || head.status == 304) {
            // 语义上无 body（即使带 Content-Length 也不允许读）。
            FixedLenBody(conn, 0)
        } else if (isChunked(head.headers)) {
            ChunkedBody(conn)
        } else {
            match (head.headers.get("Content-Length")) {
                case Some(v) =>
                    let len = match (Int64.tryParse(v.trimAscii())) {
                        case Some(n) => n
                        case None => throw ProtocolException("非法 Content-Length: ${v}")
                    }
                    if (len < 0) {
                        throw ProtocolException("非法 Content-Length: ${v}")
                    }
                    FixedLenBody(conn, len)
                case None => EofBody(conn)
            }
        }
        Response(head, conn, pool, body, bodyLimit)
    }

    private static func pickTimeout(overrideValue: ?Duration, base: ?Duration): ?Duration {
        match (overrideValue) {
            case Some(t) => Some(t)
            case None => base
        }
    }

    private static func isRedirectStatus(status: UInt16): Bool {
        status == 301 || status == 302 || status == 303 || status == 307 || status == 308
    }

    private static func isChunked(headers: Headers): Bool {
        match (headers.get("Transfer-Encoding")) {
            case Some(v) => Headers.lowerAscii(v).contains("chunked")
            case None => false
        }
    }

    // Location 解析：绝对 URL / 协议相对（//host/..）/ 根相对（/path）/ 路径相对。
    private static func resolveLocation(current: HttpTarget, loc: String): String {
        if (isAbsoluteUrl(loc)) {
            return loc
        }
        if (loc.startsWith("//")) {
            return "${current.scheme}:${loc}"
        }
        let origin = "${current.scheme}://${current.host}:${current.port}"
        if (loc.startsWith("/")) {
            return "${origin}${loc}"
        }
        // 路径相对：去掉当前 path 的 query 与最后一段，再拼接。
        var path = current.pathQuery
        match (path.indexOf("?")) {
            case Some(i) => path = path[0..i]
            case None => ()
        }
        let dir = match (path.lastIndexOf("/")) {
            case Some(i) => path[0..i + 1]
            case None => "/"
        }
        "${origin}${dir}${loc}"
    }
}
