package webview

// WebviewSession 离屏渲染单测：offscreen 无窗依赖，直接 load 固定 html →
// takeFrame 断言尺寸与 generation 前进。native 静态链接，可进 CI
//（Rust 侧 tests.rs 覆盖 C ABI 层，这里验证仓颉封装与钉扎/复用路径）。

foreign func memcpy(destination: CPointer<Unit>, source: CPointer<Unit>, count: UIntNative): CPointer<Unit>

// String → UTF-8 字节（与 client-next html_page_model.utf8BytesOf 同款：
// mallocCString 产出同内容 C 串，getChars 一次 memcpy 拷出后归还）。
private func utf8Bytes(s: String): Array<UInt8> {
    let cstr = unsafe { LibC.mallocCString(s) }
    let n = if (cstr.isNull()) { 0 } else { cstr.size() }
    let bytes = Array<UInt8>(n, repeat: 0u8)
    try {
        if (n > 0) {
            unsafe {
                let dst = acquireArrayRawData(bytes)
                let _ = memcpy(CPointer<Unit>(dst.pointer), CPointer<Unit>(cstr.getChars()), UIntNative(n))
                releaseArrayRawData(dst)
            }
        }
    } finally {
        unsafe { LibC.free(cstr) }
    }
    bytes
}

const TEST_HTML: String = "<html><body style=\"background:#123456\"><p>hello</p></body></html>"

@Test
func webviewRendersFrameWithExpectedSize(): Unit {
    let s = WebviewSession(320, 240, 1.0)
    try {
        s.loadHtml(utf8Bytes(TEST_HTML), "lanlu://arc1/text/ch1.html")
        // 首帧：generation 前进，帧尺寸 = 视口物理像素。
        let frame1 = s.takeFrame()
        @Expect(frame1.isSome(), true)
        match (frame1) {
            case Some(f) =>
                @Expect(f.width, 320)
                @Expect(f.height, 240)
                @Expect(f.rgba.size, 320 * 240 * 4)
                // 背景色已渲染（四角非透明黑）。
                let corner = f.rgba[0]
                @Expect(corner != 0u8, true)
            case None => ()
        }
        // 未变化再取：无新帧返回 None（代际未前进）。
        @Expect(s.takeFrame().isNone(), true)
    } finally {
        s.close()
    }
    @Expect(s.isClosed(), true)
}

@Test
func webviewScrollChangesGeneration(): Unit {
    let s = WebviewSession(320, 480, 1.0)
    try {
        s.loadHtml(utf8Bytes(TEST_HTML), "lanlu://arc1/text/ch1.html")
        let _ = s.takeFrame()
        let moved = s.scrollBy(60.0)
        // 内容未溢出（短页）→ 滚动到边界返回 false，且不产生新帧。
        @Expect(moved, false)
        @Expect(s.takeFrame().isNone(), true)
    } finally {
        s.close()
    }
}

@Test
func webviewLoadHtmlThrowsOnNullNativeFailure(): Unit {
    // 防御：loadHtml 失败（Rust 侧返回 -1）在仓颉层抛异常。
    let s = WebviewSession(320, 240, 1.0)
    try {
        var threw = false
        try {
            s.loadHtml(Array<UInt8>(0, repeat: 0u8), "")
        } catch (e: Exception) {
            threw = true
        }
        @Expect(threw, true)
    } finally {
        s.close()
    }
}
