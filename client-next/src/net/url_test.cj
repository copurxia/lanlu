package lanlu_client_next.net

@Test
func percentEncodeKeepsUnreservedAndEscapesUtf8(): Unit {
    @Expect(percentEncode("abcXYZ019-._~"), "abcXYZ019-._~")
    @Expect(percentEncode("a b/c"), "a%20b%2Fc")
    @Expect(percentEncode("目录/1.jpg").contains("%"), true)
    @Expect(percentEncode("a&b=c"), "a%26b%3Dc")
}

@Test
func searchQueryOmitsEmptyParamsAndEncodesFilter(): Unit {
    let q = SearchQuery()
    @Expect(buildSearchQuery(q), "?page=1&pageSize=40&sortby=title&order=asc")
    let q2 = SearchQuery()
    q2.filter = "foo bar"
    q2.categoryId = "CAT_1"
    q2.sortby = "lastread"
    q2.order = "desc"
    q2.page = 3
    q2.favoriteonly = true
    let s = buildSearchQuery(q2)
    @Expect(s.contains("filter=foo%20bar"))
    @Expect(s.contains("category_id=CAT_1"))
    @Expect(s.contains("sortby=lastread"))
    @Expect(s.contains("order=desc"))
    @Expect(s.contains("page=3"))
    @Expect(s.contains("favoriteonly=1"))
    @Expect(!s.contains("newonly"))
}

// Task 2 评审 Minor 补测：jsonQuote 要正确转义引号与反斜杠。
@Test
func jsonQuoteEscapesQuotesAndBackslash(): Unit {
    @Expect(jsonQuote("a\"b\\c"), "\"a\\\"b\\\\c\"")
    @Expect(jsonQuote(""), "\"\"")
}
