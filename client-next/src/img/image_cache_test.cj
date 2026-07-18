package lanlu_client_next.img

import std.fs.{exists, remove, Directory, File, Path}
import stdx.encoding.base64.fromBase64String

// 1x1 PNG（标准测试图）
private let PNG_1PX_B64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="

private func writeTestPng(path: String): Unit {
    let bytes = fromBase64String(PNG_1PX_B64) ?? Array<UInt8>(0, repeat: 0)
    File.writeTo(Path(path), bytes)
}

@Test
func transcodeProducesValidPng(): Unit {
    let dir = Directory.createTemp(Path("."))
    let src = "${dir}/in.png"
    let dst = "${dir}/out.png"
    writeTestPng(src)
    transcodeFileToPng(src, dst)
    @Expect(exists(Path(dst)), true)
    let head = File.readFrom(Path(dst))
    @Expect(head.size > 8, true)
    @Expect(head[0], 0x89u8)  // PNG magic
    @Expect(head[1], 0x50u8)  // 'P'
    remove(dir, recursive: true)
}

// 仓颉不允许捕获可变变量的 lambda 作为值传递，用类实例计数。
private class FetchCounter {
    var n: Int64 = 0
}

@Test
func cacheHitSkipsFetch(): Unit {
    let dir = Directory.createTemp(Path("."))
    let cache = ImageCache("${dir}/cache")
    let counter = FetchCounter()
    let fetch = {=>
        counter.n++
        let tmp = "${dir}/src.png"
        writeTestPng(tmp)
        File.readFrom(Path(tmp))
    }
    let p1 = cache.ensurePng("asset:1", fetch)
    let p2 = cache.ensurePng("asset:1", fetch)
    @Expect(p1, p2)
    @Expect(counter.n, 1)
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
    let fetch = {=>
        let tmp = "${dir}/src.png"
        writeTestPng(tmp)
        File.readFrom(Path(tmp))
    }
    let _ = cache.ensurePng("asset:1", fetch)
    let _ = cache.ensurePng("asset:2", fetch)
    cache.sweep(1)  // 阈值 1 字节 → 清到阈值以下
    @Expect(cache.totalBytes() <= 1, true)
    remove(dir, recursive: true)
}

@Test
func sweepSkipsTmpFiles(): Unit {
    let dir = Directory.createTemp(Path("."))
    let cache = ImageCache("${dir}/cache")
    let fetch = {=>
        let tmp = "${dir}/src.png"
        writeTestPng(tmp)
        File.readFrom(Path(tmp))
    }
    let _ = cache.ensurePng("asset:1", fetch)
    // 模拟在途半成品：<key>.png.tmp.png，sweep 不得将其纳入清理候选。
    let tmp = "${dir}/cache/asset_9.png.tmp.png"
    writeTestPng(tmp)
    cache.sweep(1)  // 删完成品已在阈值内；若半成品入候选会被一并删掉
    @Expect(exists(Path(tmp)), true)
    remove(dir, recursive: true)
}
