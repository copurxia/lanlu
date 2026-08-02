package qwest

import std.collection.ArrayList
import std.io.BufferedInputStream
import std.net.StreamingSocket

// 头区安全上限：单行 16KB、总量 64KB，超限按协议错误处理（防恶意/异常服务端撑爆内存）。
const MAX_HEAD_LINE_BYTES: Int64 = 16 * 1024
const MAX_HEAD_TOTAL_BYTES: Int64 = 64 * 1024

// 复用的空闲连接在写请求/读状态行之前就被对端关闭（EOF）——这是唯一可透明重试的
// 失败形态，用独立异常类型与真正的协议错误区分开。包内使用，不对外暴露。
class ConnectionClosedException <: Exception {
    init(message: String) {
        super(message)
    }
}

// 响应头产物：版本 + 状态码 + 头集合。
class ResponseHead {
    let version: String // "HTTP/1.1" / "HTTP/1.0"
    let status: UInt16
    let headers: Headers

    init(version: String, status: UInt16, headers: Headers) {
        this.version = version
        this.status = status
        this.headers = headers
    }

    // keep-alive 判定：HTTP/1.1 默认保持，除非 Connection: close；
    // HTTP/1.0 默认关闭，除非显式 Connection: keep-alive。
    func keepAlive(): Bool {
        let connValue = match (headers.get("Connection")) {
            case Some(v) => Headers.lowerAscii(v.trimAscii())
            case None => ""
        }
        if (version == "HTTP/1.0") {
            connValue == "keep-alive"
        } else {
            connValue != "close"
        }
    }
}

// 编码请求头区：请求行 + Host + 调用方头 + Content-Length。
// Host 放最前（RFC 7230 建议）；调用方显式设置过 Host 则不重复生成。
func encodeRequestHead(method: Method, target: HttpTarget, headers: Headers, contentLength: ?Int64): Array<UInt8> {
    let sb = StringBuilder()
    sb.append("${method} ${target.pathQuery} HTTP/1.1\r\n")
    if (!headers.contains("Host")) {
        sb.append("Host: ${target.hostHeader()}\r\n")
    }
    for ((k, v) in headers.toArray()) {
        sb.append("${k}: ${v}\r\n")
    }
    match (contentLength) {
        case Some(n) => sb.append("Content-Length: ${n}\r\n")
        case None => ()
    }
    sb.append("\r\n")
    sb.toString().toArray()
}

// 读一行（以 \n 结尾，剥掉 \r\n）。atStart 为 true 时首字节即 EOF 抛
// ConnectionClosedException（触发透明重试），否则视为响应被截断。
func readHeadLine(reader: BufferedInputStream<StreamingSocket>, atStart: Bool): String {
    let bytes = ArrayList<UInt8>()
    while (true) {
        let b = match (reader.readByte()) {
            case Some(v) => v
            case None =>
                if (atStart && bytes.size == 0) {
                    throw ConnectionClosedException("连接已被对端关闭")
                }
                throw ProtocolException("响应头被截断（对端提前关闭连接）")
        }
        if (b == 0x0Au8) { // '\n'
            break
        }
        if (b != 0x0Du8) { // 忽略 '\r'
            bytes.add(b)
        }
        if (bytes.size > MAX_HEAD_LINE_BYTES) {
            throw ProtocolException("响应头单行超过 ${MAX_HEAD_LINE_BYTES} 字节")
        }
    }
    String.fromUtf8(bytes.toArray())
}

// 读状态行 + 头，自动跳过 1xx 中间响应（100-continue 等）。
func readResponseHead(reader: BufferedInputStream<StreamingSocket>): ResponseHead {
    var firstRound = true
    while (true) {
        let statusLine = readHeadLine(reader, firstRound)
        firstRound = false
        // "HTTP/1.1 200 OK" — 原因短语可缺省/含空格，只取前两段。
        if (!statusLine.startsWith("HTTP/")) {
            throw ProtocolException("非法状态行: ${statusLine}")
        }
        let sp1 = match (statusLine.indexOf(" ")) {
            case Some(i) => i
            case None => throw ProtocolException("非法状态行: ${statusLine}")
        }
        let version = statusLine[0..sp1]
        let rest = statusLine[sp1 + 1..statusLine.size].trimAscii()
        let codeText = match (rest.indexOf(" ")) {
            case Some(i) => rest[0..i]
            case None => rest
        }
        let status = parseStatusCode(codeText, statusLine)

        let headers = Headers()
        var total = statusLine.size
        while (true) {
            let line = readHeadLine(reader, false)
            if (line.size == 0) {
                break
            }
            total += line.size
            if (total > MAX_HEAD_TOTAL_BYTES) {
                throw ProtocolException("响应头总量超过 ${MAX_HEAD_TOTAL_BYTES} 字节")
            }
            // "Name: value"，值两侧空白剥掉；无冒号的行按协议错误处理。
            match (line.indexOf(":")) {
                case Some(colon) =>
                    let name = line[0..colon].trimAscii()
                    let value = line[colon + 1..line.size].trimAscii()
                    if (name.size == 0) {
                        throw ProtocolException("非法响应头行: ${line}")
                    }
                    headers.add(name, value)
                case None => throw ProtocolException("非法响应头行: ${line}")
            }
        }
        // 101 是协议升级的最终响应（后续是原始协议数据），本库不支持 Upgrade，
        // 明确报错而不是把后续非 HTTP 数据当响应头解析。
        if (status == 101) {
            throw ProtocolException("不支持 101 Switching Protocols（Upgrade）")
        }
        // 其余 1xx 是中间响应（100-continue/103 等）：丢弃后继续读真正的响应头。
        if (status >= 100 && status < 200) {
            continue
        }
        return ResponseHead(version, status, headers)
    }
    throw ProtocolException("unreachable")
}

private func parseStatusCode(text: String, statusLine: String): UInt16 {
    if (text.size != 3) {
        throw ProtocolException("非法状态码: ${statusLine}")
    }
    var code: Int64 = 0
    for (b in text.toArray()) {
        if (b < 0x30u8 || b > 0x39u8) {
            throw ProtocolException("非法状态码: ${statusLine}")
        }
        code = code * 10 + Int64(b - 0x30u8)
    }
    UInt16(code)
}
