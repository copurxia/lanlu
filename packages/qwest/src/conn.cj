package qwest

import std.fs.{File, OpenMode}
import std.io.{BufferedInputStream, readToEnd}
import std.net.{TcpSocket, StreamingSocket, SocketTimeoutException}
import std.time.MonoTime
import stdx.crypto.common.Certificate
import stdx.crypto.x509.X509Certificate
import stdx.net.tls.{TlsSocket, TlsClientConfig}
import stdx.net.tls.common.CertificateVerifyMode
import stdx.net.tls.common.TlsException as StdxTlsException

// TLS 证书验证策略（透传给 stdx CertificateVerifyMode）。
public enum TlsVerify {
    | Default // 系统 CA（生产默认）
    | CustomCA(String) // PEM 证书文件路径（自签/私有 CA）
    | TrustAll // 跳过验证，仅限开发测试
}

// 一条到 (scheme, host, port) 的物理连接：TcpSocket 或其上的 TlsSocket，统一为
// StreamingSocket。读侧包 BufferedInputStream 做逐字节头解析；body 流必须继续从
// 同一个 reader 读（缓冲里可能已预读 body 前缀），reader 是连接唯一读取入口。
class Connection <: Resource {
    let key: String
    private let tcp: TcpSocket
    private let stream: StreamingSocket
    let reader: BufferedInputStream<StreamingSocket>
    // 回池时间戳，池按 idleTtl 淘汰。
    var idleSince: MonoTime = MonoTime.now()
    // 协议层发现流不同步（截断/坏 chunked）时置位，禁止回池。
    var broken = false
    private var closedFlag = false

    private init(key: String, tcp: TcpSocket, stream: StreamingSocket) {
        this.key = key
        this.tcp = tcp
        this.stream = stream
        this.reader = BufferedInputStream<StreamingSocket>(stream)
    }

    // 建连：TCP connect（原生超时）→ https 再做 TLS 握手（SNI/ALPN/验证模式）。
    // connectTimeout 只管 TCP 建连；handshakeTimeout 独立控制 TLS 握手（未配置即不设超时）。
    static func open(target: HttpTarget, connectTimeout: ?Duration, handshakeTimeout: ?Duration, verify: TlsVerify): Connection {
        let tcp = TcpSocket(target.host, target.port)
        try {
            match (connectTimeout) {
                case Some(t) => tcp.connect(timeout: t)
                case None => tcp.connect()
            }
        } catch (e: SocketTimeoutException) {
            closeQuietly(tcp)
            throw ConnectException("连接 ${target.host}:${target.port} 超时: ${e.message}")
        } catch (e: Exception) {
            closeQuietly(tcp)
            throw ConnectException("连接 ${target.host}:${target.port} 失败: ${e.message}")
        }
        if (target.scheme != "https") {
            return Connection(target.poolKey(), tcp, tcp)
        }
        var cfg = TlsClientConfig()
        // sts-1.1.3 字段名：serverName（SNI）/ supportedAlpnProtocols（与 skill 文档的 domain/alpnProtocolsList 不同）。
        cfg.serverName = Some(target.host)
        cfg.supportedAlpnProtocols = ["http/1.1"]
        match (verify) {
            case TlsVerify.Default => ()
            case TlsVerify.TrustAll => cfg.verifyMode = CertificateVerifyMode.TrustAll
            case TlsVerify.CustomCA(pemPath) =>
                let pem = try {
                    var text = ""
                    try (f = File(pemPath, OpenMode.Read)) {
                        text = String.fromUtf8(readToEnd(f))
                    }
                    text
                } catch (e: Exception) {
                    closeQuietly(tcp)
                    throw TlsException("读取 CA 证书失败 ${pemPath}: ${e.message}")
                }
                let x509 = X509Certificate.decodeFromPem(pem)
                // CustomCA 需要接口数组 Array<Certificate>，逐个上转型。
                cfg.verifyMode = CertificateVerifyMode.CustomCA(Array<Certificate>(x509.size, {i => x509[i]}))
        }
        try {
            let tls = TlsSocket.client(tcp, clientConfig: cfg)
            tls.handshake(timeout: handshakeTimeout)
            return Connection(target.poolKey(), tcp, tls)
        } catch (e: SocketTimeoutException) {
            closeQuietly(tcp)
            throw HttpTimeoutException("handshake", "TLS 握手超时: ${e.message}")
        } catch (e: StdxTlsException) {
            closeQuietly(tcp)
            throw TlsException("TLS 握手失败: ${e.message}")
        } catch (e: Exception) {
            closeQuietly(tcp)
            throw TlsException("TLS 握手失败: ${e.message}")
        }
    }

    // 每次借出前刷新超时（池里的连接会带着上个请求的配置）。
    func setTimeouts(read: ?Duration, write: ?Duration): Unit {
        stream.readTimeout = read
        stream.writeTimeout = write
    }

    func write(buf: Array<Byte>): Unit {
        stream.write(buf)
    }

    public func close(): Unit {
        if (closedFlag) {
            return
        }
        closedFlag = true
        // TLS 连接先关加密层再关底层 TCP；任一步失败不影响另一步。
        try {
            stream.close()
        } catch (_: Exception) {
            ()
        }
        closeQuietly(tcp)
    }

    public func isClosed(): Bool {
        closedFlag
    }

    private static func closeQuietly(s: TcpSocket): Unit {
        try {
            s.close()
        } catch (_: Exception) {
            ()
        }
    }
}
