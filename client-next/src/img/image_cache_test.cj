package lanlu_client_next.img

import std.fs.{exists, remove, Directory, File, Path}
import stdx.encoding.base64.fromBase64String

// 1x1 PNG（标准测试图；新管线缓存的是原始编码字节，原样落盘不再转码）
private let PNG_1PX_B64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="

private func testPngBytes(): Array<UInt8> {
    fromBase64String(PNG_1PX_B64) ?? Array<UInt8>(0, repeat: 0)
}

// 仓颉不允许捕获可变变量的 lambda 作为值传递，用类实例计数。
private class FetchCounter {
    var n: Int64 = 0
}

@Test
func cacheStoresRawBytesAndHits(): Unit {
    let dir = Directory.createTemp(Path("."))
    let cache = ImageCache("${dir}/cache")
    let counter = FetchCounter()
    let fetch = {=>
        counter.n++
        testPngBytes()
    }
    let p1 = cache.ensureCached("asset:1", fetch)
    @Expect(p1.endsWith("asset_1.img"), true)
    // 命中不再 fetch，且两次返回同一路径
    let p2 = cache.ensureCached("asset:1", fetch)
    @Expect(p1, p2)
    @Expect(counter.n, 1)
    // 落盘内容与 fetch 字节完全一致（原始字节原样保留，无转码）：全量逐字节比对。
    let want = testPngBytes()
    let onDisk = File.readFrom(Path(p2))
    @Expect(onDisk.size, want.size)
    for (i in 0..want.size) {
        @Expect(onDisk[i], want[i])
    }
    @Expect(cache.totalBytes() > 0, true)
    remove(dir, recursive: true)
}

@Test
func sanitizeKeepsSafeChars(): Unit {
    @Expect(sanitizeKey("asset:42"), "asset_42")
    @Expect(sanitizeKey("a/b c.jpg"), "a_b_c.jpg")
}

@Test
func sweepRemovesOldest(): Unit {
    let dir = Directory.createTemp(Path("."))
    let cache = ImageCache("${dir}/cache")
    let fetch = {=> testPngBytes() }
    let _ = cache.ensureCached("asset:1", fetch)
    let _ = cache.ensureCached("asset:2", fetch)
    cache.sweep(1)  // 阈值 1 字节 → 清到阈值以下
    @Expect(cache.totalBytes() <= 1, true)
    remove(dir, recursive: true)
}

@Test
func sweepSkipsInFlightBin(): Unit {
    let dir = Directory.createTemp(Path("."))
    let cache = ImageCache("${dir}/cache")
    let fetch = {=> testPngBytes() }
    let img = cache.ensureCached("asset:1", fetch)
    // 模拟在途半成品：<key>.bin，sweep 不得将其纳入清理候选。
    let bin = "${dir}/cache/asset_9.bin"
    File.writeTo(Path(bin), testPngBytes())
    cache.sweep(1)
    @Expect(exists(Path(bin)), true)   // 在途文件保留
    @Expect(exists(Path(img)), false)  // 成品已按阈值清掉
    remove(dir, recursive: true)
}

@Test
func sweepCollectsLegacyPng(): Unit {
    // 新口径：目录内除 .bin 外所有文件都是清理候选，旧管线遗留的 .png 也能被清。
    let dir = Directory.createTemp(Path("."))
    let cache = ImageCache("${dir}/cache")
    let legacy = "${dir}/cache/asset_1.png"
    File.writeTo(Path(legacy), testPngBytes())
    cache.sweep(1)
    @Expect(exists(Path(legacy)), false)
    remove(dir, recursive: true)
}

@Test
func decodeFailureEvictsCache(): Unit {
    let dir = Directory.createTemp(Path("."))
    let cache = ImageCache("${dir}/cache")
    let counter = FetchCounter()
    // 截断的 PNG（只有 magic 没有 IHDR）：能定稿落盘，但任何解码器都处理不了。
    let bad = [0x89u8, 0x50u8, 0x4Eu8, 0x47u8, 0x0Du8, 0x0Au8, 0x1Au8, 0x0Au8]
    let fetch = {=>
        counter.n++
        bad
    }
    let path = cache.ensureCached("asset:bad", fetch)
    var threw = false
    try {
        let _ = decodeCachedOrEvict(cache, "asset:bad", path)
    } catch (_: Exception) {
        threw = true
    }
    @Expect(threw, true)
    // 解码失败后坏 .img 已被剔除：再次 ensureCached 会重新 fetch 而不是永远命中坏缓存。
    @Expect(exists(Path(path)), false)
    let _ = cache.ensureCached("asset:bad", fetch)
    @Expect(counter.n, 2)
    // 剔除不存在的 key 不抛异常（重试路径的兜底前提）。
    cache.evict("asset:nonexistent")
    remove(dir, recursive: true)
}
