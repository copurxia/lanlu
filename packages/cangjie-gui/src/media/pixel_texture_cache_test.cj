package cui.media

import std.collection.ArrayList
import std.env.{getVariable, setVariable}
import cui.base.{Renderer, SdlWindow, WindowSpec}

/*
 * pixel_texture_cache 的字节预算 LRU 与 streaming 复用测试。
 * 缓存是进程级单例：每个测试开头结尾都复位（clearPixelImages + 预算/回调还原），
 * 窗口类测试在 window.close() 之前先 clearPixelImages——SDL 销毁渲染器时会连带销毁
 * 纹理，之后再由缓存 close 会访问已释放句柄。
 */

private func resetPixelCache(): Unit {
    clearPixelImages()
    pixelCacheMaxBytes = 512 * 1024 * 1024
    onPixelImageEvicted = None
}

private func testPixels(width: Int32, height: Int32): Array<UInt8> {
    Array<UInt8>(Int64(width) * Int64(height) * 4, repeat: 255u8)
}

// Headless CI 无显示；与 cui.desktop 的 idle_wait_test 同一做法：offscreen 驱动可建窗。
private func ensureVideoDriver(): Unit {
    if (getVariable("SDL_VIDEODRIVER").isNone() && getVariable("WAYLAND_DISPLAY").isNone() &&
        getVariable("DISPLAY").isNone()) {
        setVariable("SDL_VIDEODRIVER", "offscreen")
    }
}

@Test
func byteBudgetEvictsLeastRecentlyUsed(): Unit {
    resetPixelCache()
    try {
        let evicted = ArrayList<String>()
        onPixelImageEvicted = {k => evicted.add(k)}
        // 8x8 RGBA = 256 字节/张；预算 768 = 整 3 张。
        pixelCacheMaxBytes = 768
        stagePixelImage("a", 8, 8, testPixels(8, 8))
        stagePixelImage("b", 8, 8, testPixels(8, 8))
        stagePixelImage("c", 8, 8, testPixels(8, 8))
        @Expect(evicted.size, 0)
        @Expect(pixelCacheTrackedBytes()[0], Int64(768))
        // 第 4 张超预算：逐出最久未用的 a（不逐出刚登记的 d 自己）。
        stagePixelImage("d", 8, 8, testPixels(8, 8))
        @Expect(evicted.size, 1)
        @Expect(evicted[0], "a")
        @Expect(pixelCacheTrackedBytes()[0], Int64(768))
        // 再超：逐出 b。
        stagePixelImage("e", 8, 8, testPixels(8, 8))
        @Expect(evicted.size, 2)
        @Expect(evicted[1], "b")
        @Expect(pixelCacheTrackedBytes()[0], Int64(768))
    } finally {
        resetPixelCache()
    }
}

@Test
func stagedReplacementReaccountsBytes(): Unit {
    resetPixelCache()
    try {
        stagePixelImage("k", 8, 8, testPixels(8, 8))
        @Expect(pixelCacheTrackedBytes()[0], Int64(256))
        // 同 key 重复登记以最后一次为准：旧占用立即释放，不是累加。
        stagePixelImage("k", 16, 16, testPixels(16, 16))
        @Expect(pixelCacheTrackedBytes()[0], Int64(1024))
    } finally {
        resetPixelCache()
    }
}

@Test
func oversizedNewestEntrySurvivesEviction(): Unit {
    resetPixelCache()
    try {
        let evicted = ArrayList<String>()
        onPixelImageEvicted = {k => evicted.add(k)}
        pixelCacheMaxBytes = 100
        // 单张就超预算：LRU 只此一张时保留（逐出自己会导致每帧重上传的抖动）。
        stagePixelImage("huge", 16, 16, testPixels(16, 16))
        @Expect(evicted.size, 0)
        @Expect(pixelCacheTrackedBytes()[0], Int64(1024))
        // 再来一张：huge 成为最久未用被逐出；small 作为最新一张保留。
        stagePixelImage("small", 8, 8, testPixels(8, 8))
        @Expect(evicted.size, 1)
        @Expect(evicted[0], "huge")
        @Expect(pixelCacheTrackedBytes()[0], Int64(256))
    } finally {
        resetPixelCache()
    }
}

@Test
func invalidateAndClearReleaseBytes(): Unit {
    resetPixelCache()
    try {
        stagePixelImage("a", 8, 8, testPixels(8, 8))
        stagePixelImage("b", 16, 16, testPixels(16, 16))
        @Expect(pixelCacheTrackedBytes()[0], Int64(1280))
        invalidatePixelImage("a")
        @Expect(pixelCacheTrackedBytes()[0], Int64(1024))
        // invalidate 不触发逐出回调（语义与逐出通知区分）。
        clearPixelImages()
        let (staged, tex) = pixelCacheTrackedBytes()
        @Expect(staged, Int64(0))
        @Expect(tex, Int64(0))
    } finally {
        resetPixelCache()
    }
}

@Test
func registerFailureOnHeadlessCachesNone(): Unit {
    resetPixelCache()
    try {
        // headless（ptr 空）上传必败：register 缓存 None 而不是抛出，重复 register 不炸。
        let renderer = Renderer.headless()
        registerPixelImage(renderer, "bad", 4, 4, testPixels(4, 4))
        @Expect(pixelTexture(renderer, "bad").isNone())
        registerPixelImage(renderer, "bad", 4, 4, testPixels(4, 4))
        @Expect(pixelTexture(renderer, "bad").isNone())
        let (_, tex) = pixelCacheTrackedBytes()
        @Expect(tex, Int64(0))
    } finally {
        resetPixelCache()
    }
}

@Test
func byteBudgetAccountsStagedAndTexturesTogether(): Unit {
    ensureVideoDriver()
    let window = SdlWindow(WindowSpec("pixel cache budget test", 64, 64))
    try {
        resetPixelCache()
        let evicted = ArrayList<String>()
        onPixelImageEvicted = {k => evicted.add(k)}
        let renderer = window.renderer
        // register 直接上传纹理：纹理侧记账 256。
        registerPixelImage(renderer, "v", 8, 8, testPixels(8, 8))
        @Expect(pixelCacheTrackedBytes()[0], Int64(0))
        @Expect(pixelCacheTrackedBytes()[1], Int64(256))
        // staged 与纹理统一纳入同一预算。
        stagePixelImage("s", 8, 8, testPixels(8, 8))
        @Expect(pixelCacheTrackedBytes()[0], Int64(256))
        @Expect(pixelCacheTrackedBytes()[1], Int64(256))
        // 合计 512 > 300：逐出最久未用的 v（纹理），staged 的 s 留下。
        pixelCacheMaxBytes = 300
        stagePixelImage("t", 1, 1, testPixels(1, 1)) // 触发一次预算检查
        @Expect(evicted.size, 1)
        @Expect(evicted[0], "v")
        @Expect(pixelCacheTrackedBytes()[0], Int64(260))
        @Expect(pixelCacheTrackedBytes()[1], Int64(0))
    } finally {
        resetPixelCache()
        window.close()
    }
}

@Test
func streamingRegisterReusesSameTextureInstance(): Unit {
    ensureVideoDriver()
    let window = SdlWindow(WindowSpec("pixel cache streaming test", 64, 64))
    try {
        resetPixelCache()
        let renderer = window.renderer
        registerPixelImage(renderer, "video", 4, 4, testPixels(4, 4))
        let first = pixelTexture(renderer, "video").getOrThrow()
        // 同 key 同尺寸重复 register：SDL_UpdateTexture 原地更新，纹理实例不变——
        // 视频每帧 register 的场景不再 close+重建。
        registerPixelImage(renderer, "video", 4, 4, testPixels(4, 4))
        let second = pixelTexture(renderer, "video").getOrThrow()
        @Expect(refEq(first, second))
        @Expect(pixelCacheTrackedBytes()[1], Int64(64))
        // 尺寸变化：重建纹理，实例更换，记账跟随新尺寸。
        registerPixelImage(renderer, "video", 8, 8, testPixels(8, 8))
        let third = pixelTexture(renderer, "video").getOrThrow()
        @Expect(!refEq(first, third))
        @Expect(Int32(third.width), Int32(8))
        @Expect(pixelCacheTrackedBytes()[1], Int64(256))
    } finally {
        resetPixelCache()
        window.close()
    }
}
