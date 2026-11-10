package qwest

// HTTP 方法。enum 而非字符串：send 路径按模式匹配决定是否携带 body/Content-Length。
public enum Method <: ToString & Equatable<Method> {
    | GET
    | POST
    | PUT
    | DELETE
    | HEAD
    | PATCH
    | OPTIONS

    public func toString(): String {
        match (this) {
            case GET => "GET"
            case POST => "POST"
            case PUT => "PUT"
            case DELETE => "DELETE"
            case HEAD => "HEAD"
            case PATCH => "PATCH"
            case OPTIONS => "OPTIONS"
        }
    }

    public operator func ==(that: Method): Bool {
        this.toString() == that.toString()
    }

    public operator func !=(that: Method): Bool {
        !(this == that)
    }

    // POST/PUT/PATCH 语义上带请求体：即使 body 为空也发 Content-Length: 0，
    // 避免部分服务端对无长度头的“有体方法”响应 411。
    public func expectsBody(): Bool {
        match (this) {
            case POST | PUT | PATCH => true
            case _ => false
        }
    }
}
