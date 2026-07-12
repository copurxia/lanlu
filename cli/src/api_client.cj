package cli

import stdx.net.http.*
import std.io.StringReader
import std.collection.HashMap

/**
 * Lanlu HTTP API 客户端
 */
public class LanluApiClient {
    public let host: String
    public let token: String
    private var client: Client

    public init(host!: String, token!: String, noProxy!: Bool) {
        this.host = host
        this.token = token
        var builder = ClientBuilder()
        if (noProxy) {
            builder = builder.noProxy()
        }
        this.client = builder.build()
    }

    public func get(path: String, query: HashMap<String, String>): HttpResponse {
        let url = buildUrl(path, query)
        let req = HttpRequestBuilder()
            .get()
            .url(url)
            .header("Authorization", bearerHeader())
            .header("Accept", "application/json")
            .build()
        return client.send(req)
    }

    public func post(path: String, body: String): HttpResponse {
        let url = buildUrl(path, HashMap<String, String>())
        let req = HttpRequestBuilder()
            .post()
            .url(url)
            .header("Authorization", bearerHeader())
            .header("Content-Type", "application/json")
            .header("Accept", "application/json")
            .body(body)
            .build()
        return client.send(req)
    }

    public func putBytes(path: String, query: HashMap<String, String>, body: Array<UInt8>): HttpResponse {
        let url = buildUrl(path, query)
        let req = HttpRequestBuilder()
            .put()
            .url(url)
            .header("Authorization", bearerHeader())
            .header("Content-Type", "application/octet-stream")
            .header("Accept", "application/json")
            .body(body)
            .build()
        return client.send(req)
    }

    /**
     * 读取响应体为字符串并关闭响应；非 2xx 状态抛出异常
     */
    public func readBody(resp: HttpResponse): String {
        let body = StringReader(resp.body).readToEnd()
        resp.close()
        if (resp.status < 200 || resp.status >= 300) {
            throw IllegalStateException("HTTP ${resp.status}: ${body}")
        }
        return body
    }

    public func close(): Unit {
        client.close()
    }

    private func bearerHeader(): String {
        return "Bearer ${token}"
    }

    private func buildUrl(path: String, query: HashMap<String, String>): String {
        let url = joinHostPath(host, path)
        let q = buildQuery(query)
        if (q.size > 0) {
            return "${url}?${q}"
        }
        return url
    }

    private func joinHostPath(host: String, path: String): String {
        var h = host.trimAscii()
        let p = path.trimAscii()
        if (h.size == 0) {
            return p
        }
        if (p.size == 0) {
            return h
        }
        let hBytes = h.toArray()
        if (hBytes.size > 0 && hBytes[hBytes.size - 1] == 47) {
            h = String.fromUtf8(hBytes.slice(0, hBytes.size - 1))
        }
        let p2 = if (p.startsWith("/")) { p } else { "/${p}" }
        return "${h}${p2}"
    }
}
