package lanlu_client_next.net

import std.io.InputStream
import std.sync.{Mutex, SyncCounter}
import std.convert.Parsable
import stdx.crypto.crypto.SecureRandom
import stdx.net.http.{HttpContext, HttpResponseBuilder, Server, ServerBuilder}
import qwest.{Client, ClientBuilder, Headers, RequestBuilder, Response}

// libVLC 3 无法为普通 HTTP 媒体注入自定义 Authorization 请求头。这个回环代理只暴露
// 一个随机路径，把 VLC 的 Range/HEAD 请求转给当前兰鹿媒体 URL，并在出站请求上补 Bearer。
//
// 上游抓取走 qwest 的流式响应（stdx Client 会先把整个响应体缓冲进托管堆）。Response
// 持有 HTTP/HTTPS 连接，响应体作为 InputStream 交给 stdx server 分块写出，端到端 O(1) 内存。
private class UpstreamBody <: InputStream & Resource {
    private let response: Response
    private let stream: InputStream
    private var closed = false

    init(response: Response) {
        this.response = response
        this.stream = response.stream()
    }

    public func read(buf: Array<Byte>): Int64 {
        if (closed) {
            return 0
        }
        try {
            let n = stream.read(buf)
            if (n <= 0) {
                close()
            }
            n
        } catch (e: Exception) {
            close()
            throw e
        }
    }

    public func close(): Unit {
        if (!closed) {
            closed = true
            response.close()
        }
    }

    public func isClosed(): Bool {
        closed || response.isClosed()
    }
}

public class MediaProxy <: Resource {
    private let mutex = Mutex()
    private let server: Server
    private let client: Client
    private let route: String
    private var upstream: String = ""
    private var token: String = ""
    private var closed = false

    public init() {
        let random = SecureRandom()
        route = "/media/${random.nextInt64()}-${random.nextInt64()}"
        client = ClientBuilder()
            .connectTimeout(Duration.second * 10)
            .tlsHandshakeTimeout(Duration.second * 10)
            .redirect(5)
            .build()
        server = ServerBuilder().addr("127.0.0.1").port(0u16).build()
        server.distributor.register(route, {ctx => forward(ctx)})
        let ready = SyncCounter(1)
        server.afterBind({=> ready.dec()})
        spawn {server.serve()}
        ready.waitUntilZero()
    }

    public func open(url: String, bearerToken: String): String {
        synchronized(mutex) {
            upstream = url
            token = bearerToken
        }
        "http://127.0.0.1:${server.port}${route}"
    }

    private func forward(ctx: HttpContext): Unit {
        try {
            doForward(ctx)
        } catch (e: Exception) {
            println("[MediaProxy] forward failed: ${e}")
            respondBadGateway(ctx)
        } catch (e: Error) {
            // OutOfMemoryError 等 Error 也不能放出去，否则会杀死引擎线程、拖死连接池。
            println("[MediaProxy] forward failed with error: ${e}")
            respondBadGateway(ctx)
        }
    }

    // 响应可能已部分写出，此时重建响应会抛异常，吞掉由引擎收尾即可。
    private func respondBadGateway(ctx: HttpContext): Unit {
        try {
            ctx.responseBuilder.status(502u16).body("Bad Gateway")
        } catch (_: Exception) {
            ()
        }
    }

    private func doForward(ctx: HttpContext): Unit {
        let (target, bearer) = synchronized(mutex) {
            (upstream, token)
        }
        if (target.size == 0 || (ctx.request.method != "GET" && ctx.request.method != "HEAD")) {
            ctx.responseBuilder.status(404u16).body("Not found")
            return
        }
        // VLC 常用 bytes=N- 的开放区间。兰鹿会据此声明从 N 到文件末尾的巨大
        // Content-Length；把开放区间切成 32 MiB 窗口，VLC 会依据 Content-Range
        // 继续请求下一段。流式转发下窗口大小不再占用堆内存。
        let range = match (ctx.request.headers.getFirst("Range")) {
            case Some(value) => boundedRange(value)
            case None => "bytes=0-33554431"
        }
        let ua = ctx.request.headers.getFirst("User-Agent")
        let (status, headers, body) = fetchUpstream(ctx.request.method, target, bearer, range, ua)
        let out = ctx.responseBuilder.status(status)
        copyHeader(headers, out, "content-type")
        copyHeader(headers, out, "content-length")
        copyHeader(headers, out, "content-range")
        copyHeader(headers, out, "accept-ranges")
        copyHeader(headers, out, "etag")
        copyHeader(headers, out, "last-modified")
        match (body) {
            case Some(b) => let _ = out.body(b)
            case None => ()
        }
    }

    // qwest 直连上游并流式返回响应体；同时负责 HTTPS/TLS、分块解码和有限次重定向。
    private func fetchUpstream(
        method: String,
        url0: String,
        bearer: String,
        range: String,
        ua: ?String
    ): (UInt16, Headers, ?UpstreamBody) {
        let request: RequestBuilder = if (method == "HEAD") {
            client.head(url0)
        } else {
            client.get(url0)
        }
        if (bearer.size > 0) {
            request.header("Authorization", "Bearer ${bearer}")
        }
        request.header("Range", range).header("Accept", "*/*")
        match (ua) {
            case Some(value) => request.header("User-Agent", value)
            case None => ()
        }
        let response = request.send()
        let body: ?UpstreamBody = if (method == "HEAD") {
            None
        } else {
            Some(UpstreamBody(response))
        }
        (response.status, response.headers, body)
    }

    private func copyHeader(headers: Headers, out: HttpResponseBuilder, name: String): Unit {
        match (headers.get(name)) {
            case Some(value) => let _ = out.header(name, value)
            case None => ()
        }
    }

    private func boundedRange(value: String): String {
        if (!value.startsWith("bytes=") || !value.endsWith("-")) {
            return value
        }
        let rawStart = value[6..value.size - 1]
        try {
            let start = Int64.parse(rawStart)
            if (start < 0) {
                return "bytes=0-33554431"
            }
            return "bytes=${start}-${start + 33554431}"
        } catch (_: Exception) {
            "bytes=0-33554431"
        }
    }

    public func close(): Unit {
        if (closed) {
            return
        }
        closed = true
        server.close()
        client.close()
    }

    public func isClosed(): Bool {
        closed
    }
}
