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
        @Expect(request.contains("Range: bytes=7-33554438\r\n"))
        @Expect(request.contains("User-Agent: MediaProxyTest/1\r\n"))
    }
}
