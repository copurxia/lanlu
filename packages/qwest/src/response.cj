package qwest

import std.convert.Parsable
import std.io.{ByteBuffer, InputStream, OutputStream}

// HTTP 响应。Resource：读尽自动归还连接，未读尽 close() 丢弃连接（不回池）。
public class Response <: Resource {
    public let status: UInt16
    public let version: String
    public let headers: Headers
    private let conn: Connection
    private let pool: ConnectionPool
    private let body: HttpBody
    // 响应头允许 keep-alive（Connection/版本判定）；与 body.reusable 同时成立才回池。
    private let keepAliveAllowed: Bool
    private var finished = false
    // bytes()/text() 缓冲上限（客户端配置，防误用；流式场景请用 stream()）。
    private let bodyLimit: Int64

    init(head: ResponseHead, conn: Connection, pool: ConnectionPool, body: HttpBody, bodyLimit: Int64) {
        this.status = head.status
        this.version = head.version
        this.headers = head.headers
        this.conn = conn
        this.pool = pool
        this.body = body
        this.keepAliveAllowed = head.keepAlive()
        this.bodyLimit = bodyLimit
        // 空 body（HEAD/204/304/Content-Length: 0）当场结算，连接立即可复用。
        if (body.exhausted) {
            finish()
        }
    }

    public func isSuccess(): Bool {
        status >= 200 && status < 300
    }

    // 第一个同名响应头。
    public func header(name: String): ?String {
        headers.get(name)
    }

    public prop contentLength: ?Int64 {
        get() {
            match (headers.get("Content-Length")) {
                case Some(v) => Int64.tryParse(v.trimAscii())
                case None => None
            }
        }
    }

    // 流式响应体（chunked 已解码）。SSE/大文件下载走这里，O(1) 内存。
    // 读到 0 表示读尽（此刻连接已自动归还）；中途不读完则须 close() 释放连接。
    public func stream(): InputStream {
        GuardedBody(this)
    }

    // 缓冲读整个 body（读尽自动归还连接）。超过 limit 抛 BodyTooLargeException。
    public func bytes(): Array<UInt8> {
        bytes(limit: bodyLimit)
    }

    public func bytes(limit!: Int64): Array<UInt8> {
        // 容器选 ByteBuffer 而非预分配 Array：Array(size, repeat:) 要零填充
        //（19MB 实测 240ms），ByteBuffer(cap) 构造 0ms，且 bytes() 返回内部
        // 数组的等长视图不拷贝（局部缓冲用完即弃，共享无副作用）。
        // Content-Length 已知时用作精确容量，免增长重分配；并提前拒绝超限。
        let cap = match (body.knownRemaining) {
            case Some(n) =>
                if (n > limit) {
                    close()
                    throw BodyTooLargeException("响应体超过 ${limit} 字节上限，请改用 stream()")
                }
                if (n > 0) {
                    n
                } else {
                    64
                }
            case None => 64 * 1024
        }
        let out = ByteBuffer(cap)
        let buf = Array<UInt8>(64 * 1024, repeat: 0u8)
        var total: Int64 = 0
        while (true) {
            let n = readBody(buf)
            if (n <= 0) {
                break
            }
            total += n
            if (total > limit) {
                close()
                throw BodyTooLargeException("响应体超过 ${limit} 字节上限，请改用 stream()")
            }
            out.write(buf[0..n])
        }
        out.bytes()
    }

    public func text(): String {
        String.fromUtf8(bytes())
    }

    // 流式拷贝 body 到 output，返回写入字节数（对应 RestClient downloadTo）。
    public func copyTo(output: OutputStream): Int64 {
        let buf = Array<UInt8>(64 * 1024, repeat: 0u8)
        var total: Int64 = 0
        while (true) {
            let n = readBody(buf)
            if (n <= 0) {
                break
            }
            output.write(buf[0..n])
            total += n
        }
        output.flush()
        total
    }

    // 重定向等场景：读掉剩余 body 让连接可复用；太大（>256KB）就不值得，直接丢弃连接。
    func drain(): Unit {
        if (finished) {
            return
        }
        try {
            let buf = Array<UInt8>(16 * 1024, repeat: 0u8)
            var total: Int64 = 0
            while (true) {
                let n = readBody(buf)
                if (n <= 0) {
                    return
                }
                total += n
                if (total > 256 * 1024) {
                    close()
                    return
                }
            }
        } catch (_: Exception) {
            close()
        }
    }

    // body 读取的唯一入口：读尽自动结算；异常标记连接损坏并丢弃。
    // 消费掉最后一字节即结算（不等下次读返回 0）：bytes() 的精确预分配直读
    // 路径读满即止、不会多读一次，若只在 n<=0 时结算则连接永不回池；
    // chunked 需消费完 trailer 才 exhausted，仍走 n<=0 分支。
    func readBody(buf: Array<Byte>): Int64 {
        if (finished) {
            return 0
        }
        let n = try {
            body.read(buf)
        } catch (e: Exception) {
            conn.broken = true
            finish()
            throw e
        }
        if (n <= 0) {
            finish()
            return 0
        }
        if (body.exhausted) {
            finish()
        }
        n
    }

    // 结算连接归属：读尽且允许 keep-alive → 回池；否则关闭。
    private func finish(): Unit {
        if (finished) {
            return
        }
        finished = true
        if (keepAliveAllowed && body.reusable && !conn.broken) {
            pool.give(conn)
        } else {
            conn.close()
        }
    }

    // 未读尽时调用：丢弃连接（半途 body 无法回池）。幂等。
    public func close(): Unit {
        if (finished) {
            return
        }
        finished = true
        conn.close()
    }

    public func isClosed(): Bool {
        finished
    }
}

// stream() 返回的守卫流：把读转发给 Response.readBody，保证读尽/异常时的连接结算逻辑
// 只有一份（无论调用方拿 stream 还是走 bytes/copyTo）。注意 InputStream 接口没有
// close 成员，连接收尾（读尽自动结算 / 未读完丢弃）统一走 Response.close()。
private class GuardedBody <: InputStream {
    private let resp: Response

    init(resp: Response) {
        this.resp = resp
    }

    public func read(buf: Array<Byte>): Int64 {
        resp.readBody(buf)
    }
}
