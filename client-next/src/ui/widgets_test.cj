package lanlu_client_next.ui

@Test
func pagePreviewViewportHeightShrinksAndCaps(): Unit {
    @Expect(pagePreviewViewportHeight(-1.0), 0.0)
    @Expect(pagePreviewViewportHeight(320.0), 320.0)
    @Expect(pagePreviewViewportHeight(500.0), 500.0)
    @Expect(pagePreviewViewportHeight(12000.0), 500.0)
}
