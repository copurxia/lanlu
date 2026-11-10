package lanlu_client_next.net

import std.io.InputStream
import std.sync.SyncCounter
import stdx.crypto.crypto.SecureRandom
import stdx.net.http.{HttpContext, HttpResponseBuilder, Server, ServerBuilder}
import qwest.{Client, ClientBuilder, Headers, RequestBuilder, Response}

// libVLC 3 无法为普通 HTTP 媒体注入自定义 Authorization 请求头。这个回环代理只暴露
// 每次 open 创建一个不可变随机路径，把 Range/HEAD 请求转给对应媒体并补 Bearer。
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
    private let server: Server
    private let client: Client
    private var closed = false

    public init() {
        client = ClientBuilder()
            .connectTimeout(Duration.second * 10)
            .tlsHandshakeTimeout(Duration.second * 10)
            .redirect(5)
            .build()
        server = ServerBuilder().addr("127.0.0.1").port(0u16).build()
        let ready = SyncCounter(1)
        server.afterBind({=> ready.dec()})
        spawn {server.serve()}
        ready.waitUntilZero()
    }

    public func open(url: String, bearerToken: String): String {
        if (closed || url.size == 0) {
            throw Exception("media proxy is closed or URL is empty")
        }
        let random = SecureRandom()
        let route = "/media/${random.nextInt64()}-${random.nextInt64()}"
        let target = url
        let bearer = bearerToken
        server.distributor.register(route, {ctx => forward(ctx, target, bearer)})
        "http://127.0.0.1:${server.port}${route}"
    }

    private func forward(ctx: HttpContext, target: String, bearer: String): Unit {
        try {
            doForward(ctx, target, bearer)
        } catch (_: Exception) {
            // qwest 错误文本可能包含完整上游 URL；这里只记录分类，避免泄漏 query/token。
            println("[MediaProxy] upstream request failed")
            respondBadGateway(ctx)
        } catch (_: Error) {
            // OutOfMemoryError 等 Error 也不能放出去，否则会杀死引擎线程、拖死连接池。
            println("[MediaProxy] upstream request failed with fatal error")
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

    private func doForward(ctx: HttpContext, target: String, bearer: String): Unit {
        if (target.size == 0 || (ctx.request.method != "GET" && ctx.request.method != "HEAD")) {
            ctx.responseBuilder.status(404u16).body("Not found")
            return
        }
        let range = ctx.request.headers.getFirst("Range")
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
        range: ?String,
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
        match (range) {
            case Some(value) => request.header("Range", value)
            case None => ()
        }
        request.header("Accept", "*/*")
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
