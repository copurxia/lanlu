package qwest

// 异常层级：全部继承 HttpException，调用方可只 catch 基类。
// 状态码非 2xx 不抛异常（同 reqwest），由调用方按 resp.status 处理。
public open class HttpException <: Exception {
    public init(message: String) {
        super(message)
    }
}

// TCP 连接失败/连接超时。
public class ConnectException <: HttpException {
    public init(message: String) {
        super(message)
    }
}

// 读/写/TLS 握手超时。kind: "read" | "write" | "handshake"。
// 命名加 Http 前缀避免与 std.core.TimeoutException 歧义。
public class HttpTimeoutException <: HttpException {
    public let kind: String
    public init(kind: String, message: String) {
        super(message)
        this.kind = kind
    }
}

// TLS 握手/证书错误。
public class TlsException <: HttpException {
    public init(message: String) {
        super(message)
    }
}

// 状态行/响应头/chunked 编码解析失败，或 URL 非法。
public class ProtocolException <: HttpException {
    public init(message: String) {
        super(message)
    }
}

// 超过重定向跳数上限。
public class RedirectException <: HttpException {
    public init(message: String) {
        super(message)
    }
}

// bytes()/text() 缓冲读超出上限（防误用撑爆内存，流式场景请用 stream()）。
public class BodyTooLargeException <: HttpException {
    public init(message: String) {
        super(message)
    }
}
