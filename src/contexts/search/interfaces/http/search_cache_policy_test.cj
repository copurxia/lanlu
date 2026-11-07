package lanlu.contexts.search.interfaces.http

/**
 * 搜索结果缓存策略回归测试（无需 DB）。
 * 覆盖 P0-3 引入的回归：随机排序绝不能缓存，否则客户端「换一批」
 * 在 30s TTL 内会拿到完全相同的 arcid 列表。
 */
@Test
func randomSortMustNotBeCachedTest() {
    @Assert(!SearchController.isSearchResultCacheable("RANDOM()", ""))
    @Assert(!SearchController.isSearchResultCacheable(" RANDOM() ", ""))
    @Assert(!SearchController.isSearchResultCacheable("RANDOM()", "category"))
}

@Test
func normalSortIsCacheableTest() {
    @Assert(SearchController.isSearchResultCacheable("title", ""))
    @Assert(SearchController.isSearchResultCacheable("created_at", ""))
    @Assert(SearchController.isSearchResultCacheable("id", ""))
}

@Test
func categoryAggregateMustNotBeCachedTest() {
    // 聚合分支返回结构不同且不写缓存，避免键不覆盖分类维度造成污染。
    // controller 已对 aggregate_by 做 toAsciiLower，此处传的是规范化后的值。
    @Assert(!SearchController.isSearchResultCacheable("title", "category"))
    @Assert(SearchController.isSearchResultCacheable("title", ""))
}
