package qwest

import std.io.InputStream

// 响应体流的公共契约：read 到 0 即读尽；reusable 表示读尽后连接可回池。
// 截断/坏编码一律置 conn.broken 并抛 ProtocolException（连接不再回池）。
// knownRemaining：剩余字节数确切已知（Content-Length 分帧）时给出，
// bytes() 据此预分配精确大小直读，绕过 ByteBuffer 中转（实测慢 30 倍）。
interface HttpBody <: InputStream {
    prop reusable: Bool
    prop exhausted: Bool
    prop knownRemaining: ?Int64
}

// Content-Length 定长分帧：按剩余字节数计数（media_proxy UpstreamBody 同款模式）。
class FixedLenBody <: HttpBody {
    private let conn: Connection
    private var remaining: Int64

    init(conn: Connection, length: Int64) {
        this.conn = conn
        this.remaining = length
    }

    public func read(buf: Array<Byte>): Int64 {
        if (remaining <= 0 || buf.size == 0) {
            return 0
        }
        // 只借 min(buf, remaining) 的切片，绝不越过 body 末尾读走下个响应的字节。
        let want = if (buf.size < remaining) {
            buf.size
        } else {
            remaining
        }
        let n = conn.reader.read(buf[0..want])
        if (n <= 0) {
            conn.broken = true
            throw ProtocolException("响应体被截断（还差 ${remaining} 字节）")
        }
        remaining -= n
        n
    }

    public prop reusable: Bool {
        get() {
            remaining == 0
        }
    }

    public prop exhausted: Bool {
        get() {
            remaining == 0
        }
    }

    public prop knownRemaining: ?Int64 {
        get() {
            Some(remaining)
        }
    }
}

// chunked 分帧解码：size 行（hex[;扩展]）+ 数据 + CRLF，0 块后消费 trailer 到空行。
class ChunkedBody <: HttpBody {
    private let conn: Connection
    private var chunkRemaining: Int64 = 0
    private var done = false

    init(conn: Connection) {
        this.conn = conn
    }

    public func read(buf: Array<Byte>): Int64 {
        if (buf.size == 0) {
            return 0
        }
        while (true) {
            if (done) {
                return 0
            }
            if (chunkRemaining > 0) {
                let want = if (buf.size < chunkRemaining) {
                    buf.size
                } else {
                    chunkRemaining
                }
                let n = conn.reader.read(buf[0..want])
                if (n <= 0) {
                    conn.broken = true
                    throw ProtocolException("chunked 数据被截断")
                }
                chunkRemaining -= n
                if (chunkRemaining == 0) {
                    // 块末尾的 CRLF 立即消费，保持流位置对齐。
                    readChunkLine()
                }
                return n
            }
            // 读下一个 size 行。
            let line = readChunkLine()
            let size = parseChunkSize(line)
            if (size == 0) {
                // trailer 区：读到空行为止（内容忽略）。
                while (true) {
                    if (readChunkLine().size == 0) {
                        break
                    }
                }
                done = true
                return 0
            }
            chunkRemaining = size
        }
        throw ProtocolException("unreachable")
    }

    private func readChunkLine(): String {
        let sb = StringBuilder()
        var count = 0
        while (true) {
            let b = match (conn.reader.readByte()) {
                case Some(v) => v
                case None =>
                    conn.broken = true
                    throw ProtocolException("chunked 编码被截断")
            }
            if (b == 0x0Au8) { // '\n'
                break
            }
            if (b != 0x0Du8) { // 忽略 '\r'
                sb.append(Rune(UInt32(b)))
            }
            count++
            if (count > MAX_HEAD_LINE_BYTES) {
                conn.broken = true
                throw ProtocolException("chunked size/trailer 行超长")
            }
        }
        sb.toString()
    }

    private func parseChunkSize(line: String): Int64 {
        // size 后可跟 ";ext=..." 扩展，截掉。
        let text = match (line.indexOf(";")) {
            case Some(i) => line[0..i]
            case None => line
        }.trimAscii()
        if (text.size == 0 || text.size > 16) {
            conn.broken = true
            throw ProtocolException("非法 chunk size 行: ${line}")
        }
        var value: Int64 = 0
        for (b in text.toArray()) {
            let digit: Int64 = if (b >= 0x30u8 && b <= 0x39u8) {
                Int64(b - 0x30u8)
            } else if (b >= 0x61u8 && b <= 0x66u8) {
                Int64(b - 0x61u8) + 10
            } else if (b >= 0x41u8 && b <= 0x46u8) {
                Int64(b - 0x41u8) + 10
            } else {
                conn.broken = true
                throw ProtocolException("非法 chunk size 行: ${line}")
            }
            value = value * 16 + digit
        }
        value
    }

    public prop reusable: Bool {
        get() {
            done
        }
    }

    public prop exhausted: Bool {
        get() {
            done
        }
    }

    public prop knownRemaining: ?Int64 {
        get() {
            None
        }
    }
}

// 无长度信息（HTTP/1.0 或缺 Content-Length 且非 chunked）：读到 EOF，连接不可复用。
class EofBody <: HttpBody {
    private let conn: Connection
    private var done = false

    init(conn: Connection) {
        this.conn = conn
    }

    public func read(buf: Array<Byte>): Int64 {
        if (done || buf.size == 0) {
            return 0
        }
        let n = conn.reader.read(buf)
        if (n <= 0) {
            done = true
            return 0
        }
        n
    }

    public prop reusable: Bool {
        get() {
            false // EOF 分帧靠关连接界定 body，永不回池
        }
    }

    public prop exhausted: Bool {
        get() {
            done
        }
    }

    public prop knownRemaining: ?Int64 {
        get() {
            None
        }
    }
}
