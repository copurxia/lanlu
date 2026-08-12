package lanlu_client_next.net

import qwest.ClientBuilder
import std.collection.ArrayList
import std.net.{IPSocketAddress, TcpServerSocket, TcpSocket}
import std.sync.Mutex
import std.unittest.*
import std.unittest.testmacro.*

private class MediaProxyTestServer <: Resource {
    private let server: TcpServerSocket
    private let task: Future<Unit>
    let port: UInt16
    private var closed = false

    init(handler: (TcpSocket) -> Unit) {
        server = TcpServerSocket(bindAt: IPSocketAddress("127.0.0.1", 0u16))
        server.bind()
        port = match (server.localAddress as IPSocketAddress) {
            case Some(address) => address.port
            case None => throw Exception("media proxy test server has no port")
        }
        let listener = server
        task = spawn {
            let connection = try {
                listener.accept()
            } catch (_: Exception) {
                return
            }
            try {
                handler(connection)
            } finally {
                connection.close()
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
        server.close()
        task.get()
    }

    public func isClosed(): Bool {
        closed
    }
}

private class CapturedRequest {
    private let mutex = Mutex()
    private var value = ""

    func set(request: String): Unit {
        synchronized(mutex) {
            value = request
        }
    }

    func get(): String {
        synchronized(mutex) {
            value
        }
    }
}

private func readMediaProxyTestRequest(connection: TcpSocket): String {
    let bytes = ArrayList<UInt8>()
    let one = Array<UInt8>(1, repeat: 0u8)
    while (true) {
        let n = connection.read(one)
        if (n <= 0) {
            break
        }
        bytes.add(one[0])
        let size = bytes.size
        if (size >= 4 && bytes[size - 4] == 13u8 && bytes[size - 3] == 10u8 && bytes[size - 2] == 13u8 &&
            bytes[size - 1] == 10u8) {
            break
        }
    }
    String.fromUtf8(bytes.toArray())
}

@Test
func mediaProxyStreamsThroughQwestAndForwardsHeaders(): Unit {
    let captured = CapturedRequest()
    try (upstream = MediaProxyTestServer {
        connection =>
            let request = readMediaProxyTestRequest(connection)
            captured.set(request)
            connection.write(
                ("HTTP/1.1 206 Partial Content\r\n" + "Content-Type: video/test\r\n" + "Content-Length: 5\r\n" +
                    "Content-Range: bytes 7-11/12\r\n" + "Accept-Ranges: bytes\r\n\r\nhello").toArray())
    }, proxy = MediaProxy()) {
        let client = ClientBuilder().build()
        try (response = client
            .get(proxy.open(upstream.url("/media?q=%20"), "secret"))
            .header("Range", "bytes=7-")
            .header("User-Agent", "MediaProxyTest/1")
            .send()) {
            @Expect(response.status, 206u16)
            @Expect(response.header("Content-Type") ?? "", "video/test")
            @Expect(response.header("Content-Range") ?? "", "bytes 7-11/12")
            @Expect(response.text(), "hello")
        }
        client.close()

        let request = captured.get()
        @Expect(request.startsWith("GET /media?q=%20 HTTP/1.1\r\n"))
        @Expect(request.contains("Authorization: Bearer secret\r\n"))
        @Expect(request.contains("Range: bytes=7-\r\n"))
        @Expect(request.contains("User-Agent: MediaProxyTest/1\r\n"))
    }
}

@Test
func mediaProxyRoutesRemainBoundToTheirOriginalMedia(): Unit {
    try (first = MediaProxyTestServer {
        connection =>
            let _ = readMediaProxyTestRequest(connection)
            connection.write("HTTP/1.1 200 OK\r\nContent-Length: 5\r\n\r\nfirst".toArray())
    }, second = MediaProxyTestServer {
        connection =>
            let _ = readMediaProxyTestRequest(connection)
            connection.write("HTTP/1.1 200 OK\r\nContent-Length: 6\r\n\r\nsecond".toArray())
    }, proxy = MediaProxy()) {
        let firstRoute = proxy.open(first.url("/first"), "token-one")
        let secondRoute = proxy.open(second.url("/second"), "token-two")
        @Expect(firstRoute != secondRoute)
        let client = ClientBuilder().build()
        try (response = client.get(firstRoute).send()) {
            @Expect(response.text(), "first")
        }
        try (response = client.get(secondRoute).send()) {
            @Expect(response.text(), "second")
        }
        client.close()
    }
}

@Test
func mediaProxyStreamsPastFormerThirtyTwoMegabyteBoundary(): Unit {
    let totalSize: Int64 = 64 * 1024 * 1024 + 1
    try (upstream = MediaProxyTestServer {
        connection =>
            let request = readMediaProxyTestRequest(connection)
            @Expect(!request.contains("Range:"))
            connection.write(("HTTP/1.1 200 OK\r\nContent-Length: ${totalSize}\r\n\r\n").toArray())
            let chunk = Array<UInt8>(64 * 1024, {index => UInt8(index % 251)})
            var remaining = totalSize
            while (remaining > 0) {
                let size = if (remaining < chunk.size) {
                    remaining
                } else {
                    chunk.size
                }
                connection.write(chunk[..size])
                remaining -= size
            }
    }, proxy = MediaProxy()) {
        let client = ClientBuilder().build()
        try (response = client.get(proxy.open(upstream.url("/large"), "")).send()) {
            let stream = response.stream()
            let buffer = Array<UInt8>(128 * 1024, repeat: 0u8)
            var received: Int64 = 0
            while (true) {
                let count = stream.read(buffer)
                if (count <= 0) {
                    break
                }
                // Sample each transport chunk; per-byte @Expect is prohibitively slow under the
                // unittest macro and obscures the actual cross-boundary assertion.
                let stride = max(1, count / 16)
                var index: Int64 = 0
                while (index < count) {
                    @Expect(buffer[index], UInt8(((received + index) % (64 * 1024)) % 251))
                    index += stride
                }
                @Expect(buffer[count - 1], UInt8(((received + count - 1) % (64 * 1024)) % 251))
                received += count
            }
            @Expect(received, totalSize)
        }
        client.close()
    }
}
