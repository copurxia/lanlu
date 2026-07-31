package lanlu_client_next.net

import std.collection.ArrayList
import std.io.InputStream
import std.net.TcpSocket
import std.sync.{Mutex, SyncCounter}
import std.convert.Parsable
import stdx.crypto.crypto.SecureRandom
import stdx.net.http.{HttpContext, HttpResponseBuilder, Server, ServerBuilder}

// libVLC 3 无法为普通 HTTP 媒体注入自定义 Authorization 请求头。这个回环代理只暴露
// 一个随机路径，把 VLC 的 Range/HEAD 请求转给当前兰鹿媒体 URL，并在出站请求上补 Bearer。
//
// 上游抓取不走 stdx Client：sts-1.1.3 的 client.send 会把整个响应体缓冲进托管堆才返回
// （实测 32 MiB 窗口在小堆上直接 Out of memory）。这里用裸 TcpSocket 手写 HTTP/1.1 GET，
// 响应体以 Content-Length 为界的 InputStream 交给 stdx server 分块写出，端到端 O(1) 内存。
private class UpstreamBody <: InputStream & Resource {
    private let socket: TcpSocket
    // remaining: 还需转发的字节数；-1 表示长度未知，读到 EOF 为止。
    private var remaining: Int64
    private var socketClosed = false

    init(socket: TcpSocket, remaining: Int64) {
        this.socket = socket
        this.remaining = remaining
    }

    public func read(buf: Array<Byte>): Int64 {
        if (socketClosed || remaining == 0) {
            return 0
        }
        try {
            // 请求带 Connection: close 且上游不多发字节，read 不会越过 body 末尾。
            let n = socket.read(buf)
            if (n <= 0) {
                close()
                return 0
            }
            if (remaining > 0) {
                remaining -= n
            }
            if (remaining == 0) {
                close()
            }
            n
        } catch (e: Exception) {
            close()
            throw e
        }
    }

    public func close(): Unit {
        if (!socketClosed) {
            socketClosed = true
            socket.close()
        }
    }

    public func isClosed(): Bool {
        socketClosed
    }
}

private class UpstreamUrl {
    let host: String
    let port: UInt16
    let pathQuery: String

    init(host: String, port: UInt16, pathQuery: String) {
        this.host = host
        this.port = port
        this.pathQuery = pathQuery
    }
}

public class MediaProxy <: Resource {
    private let mutex = Mutex()
    private let server: Server
    private let route: String
    private var upstream: String = ""
    private var token: String = ""
    private var closed = false

    public init() {
        let random = SecureRandom()
        route = "/media/${random.nextInt64()}-${random.nextInt64()}"
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
        let (target, bearer) = synchronized(mutex) { (upstream, token) }
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

    // 裸 socket HTTP/1.1 GET：直连上游（不经 HTTP_PROXY，媒体服务器通常在内网，
    // stdx 也不认 no_proxy 的 CIDR 写法，绕行代理纯属浪费），跟随有限次重定向。
    private func fetchUpstream(method: String, url0: String, bearer: String, range: String, ua: ?String)
        : (UInt16, ArrayList<(String, String)>, ?UpstreamBody) {
        var target = url0
        var redirects = 0
        while (true) {
            let url = parseUpstream(target)
            let socket = TcpSocket(url.host, url.port)
            socket.connect(timeout: Duration.second * 10)
            var request = "${method} ${url.pathQuery} HTTP/1.1\r\nHost: ${url.host}\r\n"
            if (bearer.size > 0) {
                request += "Authorization: Bearer ${bearer}\r\n"
            }
            request += "Range: ${range}\r\n"
            match (ua) {
                case Some(value) => request += "User-Agent: ${value}\r\n"
                case None => ()
            }
            request += "Accept: */*\r\nConnection: close\r\n\r\n"
            socket.write(request.toArray())

            let statusLine = readHeaderLine(socket)
            let status = parseStatus(statusLine)
            let headers = readHeaders(socket)
            if (status / 100 == 3) {
                socket.close()
                match (headerValue(headers, "location")) {
                    case Some(location) =>
                        redirects++
                        if (redirects > 5) {
                            throw Exception("MediaProxy: too many redirects")
                        }
                        target = location
                        continue
                    case None => throw Exception("MediaProxy: upstream ${status} without Location")
                }
            }
            if (method == "HEAD") {
                socket.close()
                return (status, headers, None)
            }
            match (headerValue(headers, "transfer-encoding")) {
                case Some(_) =>
                    // 兰鹿对文件/Range 响应始终给 Content-Length；不实现 dechunk。
                    socket.close()
                    throw Exception("MediaProxy: chunked upstream response not supported")
                case None => ()
            }
            let length = match (headerValue(headers, "content-length")) {
                case Some(value) => try {
                    Int64.parse(value)
                } catch (_: Exception) {
                    -1
                }
                case None => -1
            }
            return (status, headers, Some(UpstreamBody(socket, length)))
        }
        throw Exception("unreachable")
    }

    // 解析 http://host[:port]/path?query（上游 URL 已 percent-encode，原样转发，
    // 不走 URL 库以免 path 被解码）。不支持 IPv6/userinfo，兰鹿服务器地址用不到。
    private func parseUpstream(url: String): UpstreamUrl {
        if (!url.startsWith("http://")) {
            throw Exception("MediaProxy: only http upstream supported: ${url}")
        }
        let rest = url[7..]
        let slash = rest.indexOf("/")
        let authority = match (slash) {
            case Some(i) => rest[0..i]
            case None => rest
        }
        let pathQuery = match (slash) {
            case Some(i) => rest[i..]
            case None => "/"
        }
        var host = authority
        var port = 80u16
        match (authority.indexOf(":")) {
            case Some(i) =>
                host = authority[0..i]
                port = UInt16.parse(authority[i + 1..])
            case None => ()
        }
        UpstreamUrl(host, port, pathQuery)
    }

    private func readHeaderLine(socket: TcpSocket): String {
        let line = ArrayList<Byte>()
        let one = Array<Byte>(1, repeat: 0)
        while (true) {
            let n = socket.read(one)
            if (n <= 0 || one[0] == 0x0Au8) {
                break
            }
            if (one[0] != 0x0Du8) {
                line.add(one[0])
            }
        }
        String.fromUtf8(line.toArray())
    }

    private func parseStatus(statusLine: String): UInt16 {
        let parts = statusLine.split(" ")
        if (parts.size < 2) {
            throw Exception("MediaProxy: bad status line: ${statusLine}")
        }
        UInt16.parse(parts[1])
    }

    private func readHeaders(socket: TcpSocket): ArrayList<(String, String)> {
        let headers = ArrayList<(String, String)>()
        while (true) {
            let line = readHeaderLine(socket)
            if (line.size == 0) {
                break
            }
            match (line.indexOf(":")) {
                case Some(i) => headers.add((line[0..i].trimAscii().toAsciiLower(), line[i + 1..].trimAscii()))
                case None => ()
            }
        }
        headers
    }

    private func headerValue(headers: ArrayList<(String, String)>, name: String): ?String {
        for ((n, v) in headers) {
            if (n == name) {
                return v
            }
        }
        None
    }

    private func copyHeader(headers: ArrayList<(String, String)>, out: HttpResponseBuilder, name: String): Unit {
        match (headerValue(headers, name)) {
            case Some(value) => let _ = out.header(name, value)
            case None => ()
        }
    }

    private func boundedRange(value: String): String {
        if (!value.startsWith("bytes=") || !value.endsWith("-")) { return value }
        let rawStart = value[6..value.size - 1]
        try {
            let start = Int64.parse(rawStart)
            if (start < 0) { return "bytes=0-33554431" }
            return "bytes=${start}-${start + 33554431}"
        } catch (_: Exception) {
            "bytes=0-33554431"
        }
    }

    public func close(): Unit {
        if (closed) { return }
        closed = true
        server.close()
    }

    public func isClosed(): Bool { closed }
}
