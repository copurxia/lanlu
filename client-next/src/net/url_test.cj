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

// E3 随机推荐：服务端无 /api/search/random 路由，随机走 /api/search?sortby=RANDOM()
// （archive_dao 对字面量 "RANDOM()" 特判随机排序）；括号必须按 RFC3986 编码，
// 服务端 query 解码后还原为字面量 "RANDOM()"。
@Test
func randomSortbyIsPercentEncoded(): Unit {
    let q = SearchQuery()
    q.sortby = "RANDOM()"
    q.pageSize = 12
    // order 恒附加；服务端 sortby=="RANDOM()" 时忽略 order（archive_dao 分支不看方向）。
    @Expect(buildSearchQuery(q), "?page=1&pageSize=12&sortby=RANDOM%28%29&order=asc")
}

// T11 合集成员列表：search?tankoubon_id=X&sortby=tank_order（对齐 frontend fetchArchives）。
@Test
func tankoubonMemberQueryIsBuilt(): Unit {
    let q = SearchQuery()
    q.tankoubonId = "TANK 1"
    q.sortby = "tank_order"
    q.pageSize = 10000
    let s = buildSearchQuery(q)
    @Expect(s.contains("tankoubon_id=TANK%201"))
    @Expect(s.contains("sortby=tank_order"))
    @Expect(s.contains("pageSize=10000"))
}

// 合集聚合开关：groupbyTanks=true 时带 groupby_tanks=true，默认不带。
@Test
func groupbyTanksParamIsOptIn(): Unit {
    let q = SearchQuery()
    @Expect(!buildSearchQuery(q).contains("groupby_tanks"))
    q.groupbyTanks = true
    @Expect(buildSearchQuery(q).contains("groupby_tanks=true"))
}
