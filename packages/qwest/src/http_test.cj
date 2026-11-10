package qwest

import std.collection.ArrayList
import std.convert.Parsable
import std.net.{IPSocketAddress, TcpServerSocket, TcpSocket}
import std.sync.{AtomicInt64, Mutex}

// ===== mock server 基座 =====

// 裸 TcpServerSocket 的 mock 服务端：绑 127.0.0.1 临时端口，后台线程 accept 最多
// maxConns 个连接，每个连接交给 handler 处理（handler 返回即关闭该连接）。
class MockServer <: Resource {
    private let server: TcpServerSocket
    let port: UInt16
    let acceptCount = AtomicInt64(0)
    private let fut: Future<Unit>
    private var closed = false

    init(maxConns: Int64, handler: (TcpSocket) -> Unit) {
        server = TcpServerSocket(bindAt: IPSocketAddress("127.0.0.1", 0u16))
        server.bind()
        port = match (server.localAddress as IPSocketAddress) {
            case Some(a) => a.port
            case None => throw Exception("mock server 未取到端口")
        }
        let s = server
        let cnt = acceptCount
        fut = spawn {
            var served = 0
            while (served < maxConns) {
                let conn = try {
                    s.accept()
                } catch (_: Exception) {
                    break // server.close() 触发，退出
                }
                cnt.fetchAdd(1)
                served++
                try {
                    handler(conn)
                } catch (_: Exception) {
                    ()
                }
                try {
                    conn.close()
                } catch (_: Exception) {
                    ()
                }
            }
        }
    }

    func url(path: String): String {
        "http://127.0.0.1:${port}${path}"
    }

    public func close(): Unit {
        if (closed) {
            return
        }
        closed = true
        try {
            server.close()
        } catch (_: Exception) {
            ()
        }
        fut.get()
    }

    public func isClosed(): Bool {
        closed
    }
}

// 从连接读一个完整请求（头区 + Content-Length 指明的 body），返回头区文本；
// 对端关闭/出错返回 None。逐字节找 \r\n\r\n，测试场景无所谓效率。
func readRequest(conn: TcpSocket): ?String {
    let one = Array<UInt8>(1, repeat: 0u8)
    let head = ArrayList<UInt8>()
    while (true) {
        let n = try {
            conn.read(one)
        } catch (_: Exception) {
            return None
        }
        if (n <= 0) {
            return None
        }
        head.add(one[0])
        let sz = head.size
        if (sz >= 4 && head[sz - 4] == 13u8 && head[sz - 3] == 10u8 && head[sz - 2] == 13u8 && head[sz - 1] == 10u8) {
            break
        }
    }
    let text = String.fromUtf8(head.toArray())
    // 按 Content-Length 消费 body，保持连接上的流位置对齐（keep-alive 多请求场景）。
    var bodyLen: Int64 = 0
    for (line in text.split("\r\n")) {
        if (Headers.lowerAscii(line).startsWith("content-length:")) {
            bodyLen = Int64.tryParse(line[15..line.size].trimAscii()) ?? 0
        }
    }
    var left = bodyLen
    let buf = Array<UInt8>(1024, repeat: 0u8)
    while (left > 0) {
        let want = if (left < buf.size) {
            left
        } else {
            buf.size
        }
        let n = try {
            conn.read(buf[0..want])
        } catch (_: Exception) {
            return None
        }
        if (n <= 0) {
            return None
        }
        left -= n
    }
    text
}

func writeText(conn: TcpSocket, text: String): Unit {
    conn.write(text.toArray())
}

// ===== 分帧 =====

// Content-Length 定长分帧 + 状态/头/contentLength 读取。
@Test
func contentLengthFraming(): Unit {
    try (server = MockServer(1) {
        conn => if (readRequest(conn).isSome()) {
            writeText(conn, "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: 5\r\n\r\nhello")
        }
    }) {
        let client = ClientBuilder().build()
        try (resp = client.get(server.url("/x")).send()) {
            @Expect(resp.status, 200u16)
            @Expect(resp.isSuccess())
            @Expect(resp.contentLength ?? -1, 5)
            @Expect(resp.header("content-type") ?? "", "text/plain")
            @Expect(resp.text(), "hello")
        }
        client.close()
    }
}

// chunked 解码：多块、带扩展、trailer 忽略。
@Test
func chunkedDecoding(): Unit {
    try (server = MockServer(1) {
        conn => if (readRequest(conn).isSome()) {
            writeText(
                conn,
                "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n" +
                    "5\r\nhello\r\n6;ext=x\r\n world\r\n0\r\nX-Trailer: v\r\n\r\n"
            )
        }
    }) {
        let client = ClientBuilder().build()
        try (resp = client.get(server.url("/c")).send()) {
            @Expect(resp.text(), "hello world")
        }
        client.close()
    }
}

// 坏 chunk size（非 hex）按协议错误处理。
@Test
func chunkedBadHex(): Unit {
    try (server = MockServer(1) {
        conn => if (readRequest(conn).isSome()) {
            writeText(conn, "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\nZZ\r\nxxxx\r\n0\r\n\r\n")
        }
    }) {
        let client = ClientBuilder().build()
        let resp = client.get(server.url("/bad")).send()
        @ExpectThrows[ProtocolException](resp.bytes())
        resp.close()
        client.close()
    }
}

// Connection: close 且无长度信息：读到 EOF 分帧。
@Test
func eofFraming(): Unit {
    try (server = MockServer(1) {
        conn => if (readRequest(conn).isSome()) {
            writeText(conn, "HTTP/1.1 200 OK\r\nConnection: close\r\n\r\nbye!")
        }
    }) {
        let client = ClientBuilder().build()
        try (resp = client.get(server.url("/e")).send()) {
            @Expect(resp.text(), "bye!")
        }
        client.close()
    }
}

// ===== 连接复用与重试 =====

// keep-alive：两次请求走同一条连接（server accept 次数 = 1）；顺带验证 baseUrl 拼接。
@Test
func keepAliveReuse(): Unit {
    try (server = MockServer(1) {
        conn => while (readRequest(conn).isSome()) {
            writeText(conn, "HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\nok")
        }
    }) {
        let client = ClientBuilder().baseUrl("http://127.0.0.1:${server.port}").build()
        try (r1 = client.get("/a").send()) {
            @Expect(r1.text(), "ok")
        }
        try (r2 = client.get("b").send()) {
            @Expect(r2.text(), "ok")
        }
        client.close()
        @Expect(server.acceptCount.load(), 1)
    }
}

// 闲置连接被服务端关闭后透明重试：第二次请求拿到死连接，应自动换新连接成功。
@Test
func retryOnClosedIdleConnection(): Unit {
    try (server = MockServer(2) {
        conn => if (readRequest(conn).isSome()) {
            // 只服务一个请求，handler 返回即关连接（模拟服务端 keep-alive 超时）
            writeText(conn, "HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\nok")
        }
    }) {
        let client = ClientBuilder().build()
        try (r1 = client.get(server.url("/1")).send()) {
            @Expect(r1.text(), "ok")
        }
        sleep(Duration.millisecond * 150) // 等服务端 close 传播，确保池中连接已死
        try (r2 = client.get(server.url("/2")).send()) {
            @Expect(r2.text(), "ok")
        }
        client.close()
        @Expect(server.acceptCount.load(), 2)
    }
}

// 脏连接透明重试：上游在响应体之后多写了 chunked 终止块，连接带残留字节回池；
// 下一个请求在这条连接上把 "0" 读成状态行，应丢连接换新连接重试成功而非报错。
@Test
func retryOnDirtyPooledConnection(): Unit {
    let connIndex = AtomicInt64(0)
    try (server = MockServer(2) {
        conn =>
            let idx = connIndex.fetchAdd(1)
            while (readRequest(conn).isSome()) {
                if (idx == 0) {
                    // 响应本身完整（Content-Length 对齐），但线上多写 "0\r\n\r\n"。
                    writeText(conn, "HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\nok0\r\n\r\n")
                } else {
                    writeText(conn, "HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\nok")
                }
            }
    }) {
        let client = ClientBuilder().build()
        try (r1 = client.get(server.url("/1")).send()) {
            @Expect(r1.text(), "ok") // 残留字节不影响本次，但连接带脏回池
        }
        try (r2 = client.get(server.url("/2")).send()) {
            @Expect(r2.text(), "ok")
        }
        client.close()
        @Expect(server.acceptCount.load(), 2)
    }
}

// HEAD 用后即关不回池：后续 GET 必须新建连接（accept 次数 = 2），
// 防上游对 HEAD 误写残留字节污染连接池。
@Test
func headConnectionNotPooled(): Unit {
    try (server = MockServer(2) {
        conn => while (true) {
            let req = match (readRequest(conn)) {
                case Some(r) => r
                case None => break
            }
            if (req.startsWith("HEAD")) {
                writeText(conn, "HTTP/1.1 200 OK\r\nContent-Length: 5\r\n\r\n")
            } else {
                writeText(conn, "HTTP/1.1 200 OK\r\nContent-Length: 5\r\n\r\nhello")
            }
        }
    }) {
        let client = ClientBuilder().build()
        try (r1 = client.head(server.url("/h")).send()) {
            @Expect(r1.status, 200u16)
            @Expect(r1.contentLength ?? -1, 5)
            @Expect(r1.bytes().size, 0) // HEAD 不读 body
        }
        try (r2 = client.get(server.url("/g")).send()) {
            @Expect(r2.text(), "hello")
        }
        client.close()
        @Expect(server.acceptCount.load(), 2)
    }
}

// ===== 重定向 =====

// 重定向链 POST /submit → 303 → GET /step2 → 302 → GET /final；303 转 GET。
@Test
func redirectChainAnd303ToGet(): Unit {
    let mu = Mutex()
    let lines = ArrayList<String>()
    try (server = MockServer(1) {
        conn => while (true) {
            let req = match (readRequest(conn)) {
                case Some(r) => r
                case None => break
            }
            let firstLine = req.split("\r\n")[0]
            synchronized(mu) {
                lines.add(firstLine)
            }
            if (firstLine.startsWith("POST /submit")) {
                writeText(conn, "HTTP/1.1 303 See Other\r\nLocation: /step2\r\nContent-Length: 0\r\n\r\n")
            } else if (firstLine.startsWith("GET /step2")) {
                writeText(conn, "HTTP/1.1 302 Found\r\nLocation: /final\r\nContent-Length: 0\r\n\r\n")
            } else {
                writeText(conn, "HTTP/1.1 200 OK\r\nContent-Length: 4\r\n\r\ndone")
            }
        }
    }) {
        let client = ClientBuilder().build()
        try (resp = client.post(server.url("/submit")).body("payload").send()) {
            @Expect(resp.status, 200u16)
            @Expect(resp.text(), "done")
        }
        client.close()
        let recorded = synchronized(mu) {
            lines.toArray()
        }
        @Expect(recorded.size, 3)
        @Expect(recorded[0].startsWith("POST /submit"))
        @Expect(recorded[1].startsWith("GET /step2")) // 303 转 GET 且不带 body
        @Expect(recorded[2].startsWith("GET /final"))
    }
}

// 超过跳数上限抛 RedirectException；redirect(0) 关闭跟随，3xx 原样返回。
@Test
func redirectLimitAndDisable(): Unit {
    try (server = MockServer(2) {
        conn => while (readRequest(conn).isSome()) {
            writeText(conn, "HTTP/1.1 302 Found\r\nLocation: /loop\r\nContent-Length: 0\r\n\r\n")
        }
    }) {
        let limited = ClientBuilder().redirect(2).build()
        @ExpectThrows[RedirectException](limited.get(server.url("/loop")).send())
        limited.close()

        let noFollow = ClientBuilder().redirect(0).build()
        try (resp = noFollow.get(server.url("/loop")).send()) {
            @Expect(resp.status, 302u16)
            @Expect(resp.header("Location") ?? "", "/loop")
        }
        noFollow.close()
    }
}

// ===== query 编码上线 =====

// query() 参数在请求行上按 RFC3986 percent-encode。
@Test
func queryEncodedOnWire(): Unit {
    let mu = Mutex()
    let lines = ArrayList<String>()
    try (server = MockServer(1) {
        conn => if (let Some(req) <- readRequest(conn)) {
            synchronized(mu) {
                lines.add(req.split("\r\n")[0])
            }
            writeText(conn, "HTTP/1.1 200 OK\r\nContent-Length: 0\r\n\r\n")
        }
    }) {
        let client = ClientBuilder().build()
        try (resp = client.get(server.url("/search")).query("q", "a b&c").query("页", "1").send()) {
            @Expect(resp.status, 200u16)
        }
        client.close()
        let recorded = synchronized(mu) {
            lines.toArray()
        }
        @Expect(recorded.size, 1)
        @Expect(recorded[0].startsWith("GET /search?q=a%20b%26c&%E9%A1%B5=1 "))
    }
}

// ===== 超时 =====

// connectTimeout：TEST-NET-3 保留段不可路由，超时/拒绝均归一为 ConnectException。
@Test
func connectTimeoutFires(): Unit {
    let client = ClientBuilder().connectTimeout(Duration.millisecond * 300).build()
    @ExpectThrows[ConnectException](client.get("http://203.0.113.1:81/").send())
    client.close()
}

// readTimeout：服务端收到请求后不回应，客户端应在超时后抛 HttpTimeoutException。
@Test
func readTimeoutFires(): Unit {
    try (server = MockServer(1) {
        conn =>
        let _ = readRequest(conn) // 读走请求但不回应
        sleep(Duration.second * 1) // 拖住连接直到客户端超时
    }) {
        let client = ClientBuilder().readTimeout(Duration.millisecond * 200).build()
        @ExpectThrows[HttpTimeoutException](client.get(server.url("/slow")).send())
        client.close()
    }
}
