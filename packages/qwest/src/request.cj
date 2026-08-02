package qwest

import std.collection.ArrayList

// 请求构造器（reqwest 风格链式）。send() 前由拦截器补默认头（如 Authorization）。
public class RequestBuilder {
    private let client: Client
    let method: Method
    let urlOrPath: String
    let headers = Headers()
    let queryParams = ArrayList<(String, String)>()
    var bodyBytes: ?Array<UInt8> = None
    var timeoutOverride: ?Duration = None

    init(client: Client, method: Method, urlOrPath: String) {
        this.client = client
        this.method = method
        this.urlOrPath = urlOrPath
    }

    // 设置头（同名覆盖）。
    public func header(name: String, value: String): RequestBuilder {
        headers.set(name, value)
        this
    }

    // 追加 query 参数，send 时统一 percent-encode 拼到 URL。
    public func query(name: String, value: String): RequestBuilder {
        queryParams.add((name, value))
        this
    }

    public func body(bytes: Array<UInt8>): RequestBuilder {
        bodyBytes = bytes
        this
    }

    public func body(text: String): RequestBuilder {
        bodyBytes = text.toArray()
        this
    }

    // JSON 请求体：设 Content-Type 并携带序列化好的字符串（库不绑定序列化框架）。
    public func json(jsonText: String): RequestBuilder {
        headers.set("Content-Type", "application/json")
        bodyBytes = jsonText.toArray()
        this
    }

    // 单请求覆盖客户端级读写超时（长上传/下载场景）。
    public func timeout(d: Duration): RequestBuilder {
        timeoutOverride = d
        this
    }

    public func send(): Response {
        client.execute(this)
    }
}
