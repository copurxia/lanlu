package lanlu_client_next.ui

import lanlu_client_next.net.PageInfo

@Test
func pagePreviewViewportHeightShrinksAndCaps(): Unit {
    @Expect(pagePreviewViewportHeight(-1.0), 0.0)
    @Expect(pagePreviewViewportHeight(320.0), 320.0)
    @Expect(pagePreviewViewportHeight(500.0), 500.0)
    @Expect(pagePreviewViewportHeight(12000.0), 500.0)
}

@Test
func pagePreviewThumbUsesCustomAssetWhenPresent(): Unit {
    let page = PageInfo()
    page.id = "folder/page 1.jpg"
    page.pageType = "image"
    page.thumbAssetId = 42
    @Expect(pagePreviewThumbKey("arc-1", page), "athumb:42")
    @Expect(pagePreviewThumbUrl("arc-1", page), "/api/assets/42")
}

@Test
func pagePreviewThumbUsesSharedRawPageCacheForImages(): Unit {
    let page = PageInfo()
    page.id = "folder/page 1.jpg"
    page.pageType = "image"
    @Expect(pagePreviewThumbKey("arc-1", page), "thumb:arc-1:folder/page 1.jpg")
    @Expect(pagePreviewThumbUrl("arc-1", page), "/api/archives/arc-1/page?path=folder%2Fpage%201.jpg")
}

@Test
func pagePreviewThumbKeepsMediaPlaceholderWithoutCustomAsset(): Unit {
    for (pageType in ["video", "audio", "html"]) {
        let page = PageInfo()
        page.id = "media/file.bin"
        page.pageType = pageType
        @Expect(pagePreviewThumbKey("arc-1", page), "")
        @Expect(pagePreviewThumbUrl("arc-1", page), "")
    }
}
