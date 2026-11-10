package qwest

import std.convert.Parsable
import stdx.encoding.url.URL

// 请求目标：从绝对 URL 解析出的连接与请求行要素。
// 解析交给 stdx.encoding.url.URL（rawPath/rawQuery 保留原始编码，避免二次转义）。
public class HttpTarget {
    public let scheme: String // "http" | "https"
    public let host: String // 主机名（不含端口）
    public let port: UInt16
    public let pathQuery: String // 请求行里的 path[?query]，永不为空（至少 "/"）

    init(scheme: String, host: String, port: UInt16, pathQuery: String) {
        this.scheme = scheme
        this.host = host
        this.port = port
        this.pathQuery = pathQuery
    }

    // Host 头：默认端口省略端口号（服务端/CDN 对带默认端口的 Host 兼容性参差）。
    public func hostHeader(): String {
        let defaultPort: UInt16 = if (scheme == "https") {
            443
        } else {
            80
        }
        if (port == defaultPort) {
            host
        } else {
            "${host}:${port}"
        }
    }

    // 连接池键：同 (scheme, host, port) 才能复用连接。
    public func poolKey(): String {
        "${scheme}://${host}:${port}"
    }

    public static func parse(absoluteUrl: String): HttpTarget {
        let u = try {
            URL.parse(absoluteUrl)
        } catch (e: Exception) {
            throw ProtocolException("URL 非法: ${absoluteUrl} (${e.message})")
        }
        let scheme = Headers.lowerAscii(u.scheme)
        if (scheme != "http" && scheme != "https") {
            throw ProtocolException("不支持的协议: ${u.scheme}")
        }
        let host = u.hostName
        if (host.size == 0) {
            throw ProtocolException("URL 缺少主机名: ${absoluteUrl}")
        }
        // sts-1.1.3 的 URL.port 是 String（缺省空串），自行解析 + 按 scheme 补默认端口。
        let parsedPort: Int64 = match (Int64.tryParse(u.port)) {
            case Some(p) => p
            case None => 0
        }
        let port: UInt16 = if (parsedPort > 0 && parsedPort <= 65535) {
            UInt16(parsedPort)
        } else if (scheme == "https") {
            443
        } else {
            80
        }
        var pq = u.rawPath
        if (pq.size == 0) {
            pq = "/"
        }
        match (u.rawQuery) {
            case Some(q) => pq = "${pq}?${q}"
            case None => ()
        }
        HttpTarget(scheme, host, port, pq)
    }
}

// RFC3986 unreserved：A-Z a-z 0-9 - . _ ~，其余一律按 UTF-8 字节 %XX。
public func percentEncode(s: String): String {
    let sb = StringBuilder()
    for (b in s.toArray()) {
        let c = b
        let unreserved = (c >= 0x41u8 && c <= 0x5Au8) || (c >= 0x61u8 && c <= 0x7Au8) ||
            (c >= 0x30u8 && c <= 0x39u8) || c == 0x2Du8 || c == 0x2Eu8 || c == 0x5Fu8 || c == 0x7Eu8
        if (unreserved) {
            sb.append(Rune(UInt32(c))) // 单字节 ASCII 直接追加
        } else {
            sb.append('%')
            sb.append(hexUpper(c >> 4))
            sb.append(hexUpper(c & 0x0Fu8))
        }
    }
    sb.toString()
}

private func hexUpper(n: UInt8): Rune {
    if (n < 10u8) {
        return Rune(UInt32(0x30u8 + n)) // '0'
    }
    Rune(UInt32(0x41u8 + (n - 10u8))) // 'A'
}

// 是否为绝对 URL（大小写不敏感前缀判断）。
func isAbsoluteUrl(s: String): Bool {
    let lower = Headers.lowerAscii(s)
    lower.startsWith("http://") || lower.startsWith("https://")
}

// baseUrl + 相对路径拼接：base 去尾部 /，path 补头部 /。
func joinUrl(base: String, path: String): String {
    var b = base
    while (b.endsWith("/")) {
        b = b[0..b.size - 1]
    }
    if (path.size == 0) {
        return b
    }
    if (path.startsWith("/")) {
        "${b}${path}"
    } else {
        "${b}/${path}"
    }
}
