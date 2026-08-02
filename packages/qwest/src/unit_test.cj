package qwest

// HttpTarget 解析：默认端口补全、显式端口、path/query 保留、Host 头省略默认端口。
@Test
func urlParseBasics(): Unit {
    let t = HttpTarget.parse("https://example.com/api/info?x=1&y=%20")
    @Expect(t.scheme, "https")
    @Expect(t.host, "example.com")
    @Expect(t.port, 443u16)
    @Expect(t.pathQuery, "/api/info?x=1&y=%20")
    @Expect(t.hostHeader(), "example.com")

    let t2 = HttpTarget.parse("http://127.0.0.1:8080")
    @Expect(t2.scheme, "http")
    @Expect(t2.port, 8080u16)
    @Expect(t2.pathQuery, "/") // 空路径补 "/"
    @Expect(t2.hostHeader(), "127.0.0.1:8080")
    @Expect(t2.poolKey(), "http://127.0.0.1:8080")

    // http 显式 443 非默认端口，Host 头保留端口
    let t3 = HttpTarget.parse("http://a.example:443/p")
    @Expect(t3.hostHeader(), "a.example:443")
}

@Test
func urlParseRejects(): Unit {
    @ExpectThrows[ProtocolException](HttpTarget.parse("ftp://example.com/x"))
    @ExpectThrows[ProtocolException](HttpTarget.parse("http://"))
}

// Headers：大小写不敏感 get/set/remove，同名多值 getAll。
@Test
func headersCaseInsensitive(): Unit {
    let h = Headers()
    h.add("Content-Type", "text/plain")
    @Expect(h.get("content-type") ?? "", "text/plain")
    @Expect(h.contains("CONTENT-TYPE"))

    h.set("CONTENT-type", "application/json") // set 覆盖同名
    @Expect(h.size, 1)
    @Expect(h.get("Content-Type") ?? "", "application/json")

    h.add("Set-Cookie", "a=1")
    h.add("set-cookie", "b=2")
    @Expect(h.getAll("SET-COOKIE").size, 2)

    h.remove("set-COOKIE")
    @Expect(h.size, 1)
    @Expect(h.get("Set-Cookie").isNone())
}

// percentEncode：unreserved 原样，空格/符号 %XX，非 ASCII 按 UTF-8 字节编码。
@Test
func percentEncodeCases(): Unit {
    @Expect(percentEncode("AZaz09-._~"), "AZaz09-._~")
    @Expect(percentEncode("a b&c=d/e?"), "a%20b%26c%3Dd%2Fe%3F")
    @Expect(percentEncode("中"), "%E4%B8%AD")
    @Expect(percentEncode(""), "")
}

@Test
func urlHelpers(): Unit {
    @Expect(isAbsoluteUrl("HTTP://x"))
    @Expect(isAbsoluteUrl("https://x"))
    @Expect(!isAbsoluteUrl("/path"))
    @Expect(joinUrl("http://a/", "/b"), "http://a/b")
    @Expect(joinUrl("http://a", "b"), "http://a/b")
    @Expect(joinUrl("http://a//", ""), "http://a")
}

// keep-alive 判定：1.1 默认保持除非 close；1.0 默认关闭除非 keep-alive。
@Test
func keepAliveJudgement(): Unit {
    @Expect(ResponseHead("HTTP/1.1", 200, Headers()).keepAlive())

    let h2 = Headers()
    h2.add("Connection", "Close")
    @Expect(!ResponseHead("HTTP/1.1", 200, h2).keepAlive())

    @Expect(!ResponseHead("HTTP/1.0", 200, Headers()).keepAlive())

    let h4 = Headers()
    h4.add("Connection", "Keep-Alive")
    @Expect(ResponseHead("HTTP/1.0", 200, h4).keepAlive())
}

// 请求头区编码：请求行、自动 Host、显式 Host 不重复、Content-Length 追加。
@Test
func encodeRequestHeadFormat(): Unit {
    let target = HttpTarget.parse("http://example.com/a?b=1")
    let head = String.fromUtf8(encodeRequestHead(Method.POST, target, Headers(), Some(3)))
    @Expect(head.startsWith("POST /a?b=1 HTTP/1.1\r\n"))
    @Expect(head.contains("\r\nHost: example.com\r\n") || head.startsWith("POST /a?b=1 HTTP/1.1\r\nHost: example.com\r\n"))
    @Expect(head.contains("\r\nContent-Length: 3\r\n"))
    @Expect(head.endsWith("\r\n\r\n"))

    let custom = Headers()
    custom.set("Host", "override.example")
    let head2 = String.fromUtf8(encodeRequestHead(Method.GET, target, custom, None))
    @Expect(!head2.contains("Host: example.com"))
    @Expect(head2.contains("Host: override.example\r\n"))
    @Expect(!head2.contains("Content-Length"))
}
