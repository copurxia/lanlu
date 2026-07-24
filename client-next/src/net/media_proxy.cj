package lanlu_client_next.net

import std.sync.{Mutex, SyncCounter}
import std.convert.Parsable
import stdx.crypto.crypto.SecureRandom
import stdx.net.http.{Client, ClientBuilder, HttpContext, HttpRequestBuilder, HttpResponse,
    HttpResponseBuilder, Server, ServerBuilder}

// libVLC 3 无法为普通 HTTP 媒体注入自定义 Authorization 请求头。这个回环代理只暴露
// 一个随机路径，把 VLC 的 Range/HEAD 请求转给当前兰鹿媒体 URL，并在出站请求上补 Bearer。
// 响应 body 保持 InputStream，不在客户端内存中聚合整个视频。
public class MediaProxy <: Resource {
    private let mutex = Mutex()
    private let client: Client
    private let server: Server
    private let route: String
    private var upstream: String = ""
    private var token: String = ""
    private var closed = false

    public init() {
        let random = SecureRandom()
        route = "/media/${random.nextInt64()}-${random.nextInt64()}"
        client = ClientBuilder().autoRedirect(true).build()
        server = ServerBuilder().addr("127.0.0.1").port(0u16).build()
        server.distributor.register(route, { ctx => forward(ctx) })
        let ready = SyncCounter(1)
        server.afterBind({ => ready.dec() })
        spawn { server.serve() }
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
        let target = synchronized(mutex) { upstream }
        let bearer = synchronized(mutex) { token }
        if (target.size == 0 || (ctx.request.method != "GET" && ctx.request.method != "HEAD")) {
            ctx.responseBuilder.status(404u16).body("Not found")
            return
        }
        var builder = HttpRequestBuilder().method(ctx.request.method).url(target)
        if (bearer.size > 0) {
            builder = builder.header("Authorization", "Bearer ${bearer}")
        }
        // VLC 常用 bytes=N- 的开放区间。兰鹿会据此声明从 N 到文件末尾的巨大
        // Content-Length；stdx server 转交超大响应时会造成不必要的内存压力。
        // 把开放区间切成 8 MiB 窗口，VLC 会依据 Content-Range 继续请求下一段。
        let range = match (ctx.request.headers.getFirst("Range")) {
            case Some(value) => boundedRange(value)
            case None => "bytes=0-8388607"
        }
        builder = builder.header("Range", range)
        match (ctx.request.headers.getFirst("User-Agent")) {
            case Some(value) => builder = builder.header("User-Agent", value)
            case None => ()
        }
        let response = client.send(builder.build())
        let out = ctx.responseBuilder.status(response.status)
        copyHeader(response, out, "Content-Type")
        copyHeader(response, out, "Content-Length")
        copyHeader(response, out, "Content-Range")
        copyHeader(response, out, "Accept-Ranges")
        copyHeader(response, out, "ETag")
        copyHeader(response, out, "Last-Modified")
        if (ctx.request.method != "HEAD") {
            out.body(response.body)
        }
    }

    private func copyHeader(response: HttpResponse, builder: HttpResponseBuilder, name: String): Unit {
        match (response.headers.getFirst(name)) {
            case Some(value) => let _ = builder.header(name, value)
            case None => ()
        }
    }

    private func boundedRange(value: String): String {
        if (!value.startsWith("bytes=") || !value.endsWith("-")) { return value }
        let rawStart = value[6..value.size - 1]
        try {
            let start = Int64.parse(rawStart)
            if (start < 0) { return "bytes=0-8388607" }
            return "bytes=${start}-${start + 8388607}"
        } catch (_: Exception) {
            "bytes=0-8388607"
        }
    }

    public func close(): Unit {
        if (closed) { return }
        closed = true
        server.close()
        client.close()
    }

    public func isClosed(): Bool { closed }
}
