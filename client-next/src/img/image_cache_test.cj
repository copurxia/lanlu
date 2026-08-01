package lanlu_client_next.img

import std.fs.{exists, remove, Directory, File, Path}
import std.io.OutputStream
import std.sync.SyncCounter
import stdx.encoding.base64.fromBase64String

// 1x1 PNG（标准测试图；新管线缓存的是原始编码字节，原样落盘不再转码）
private let PNG_1PX_B64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="

private func testPngBytes(): Array<UInt8> {
    fromBase64String(PNG_1PX_B64) ?? Array<UInt8>(0, repeat: 0)
}

// 适配流式落盘：把整块字节写入 output 并返回字节数（模拟一次完整下载）。
private func writeAll(output: OutputStream, bytes: Array<UInt8>): Int64 {
    output.write(bytes)
    Int64(bytes.size)
}

// 测试用 CacheWriter 实现。用类而非闭包：仓颉 1.1.3 运行时缺陷——被函数参数传递的
// 闭包在 spawn 线程中调用时若写捕获字段会触发 GC WriteStaticRef 屏障 SIGSEGV，
// 接口方法调用不触发（见 image_cache.cj CacheWriter 注释）。
private class TestWriter <: CacheWriter {
    let counter: FetchCounter
    let bytes: Array<UInt8>
    let delayMs: Int64
    let failMsg: String
    init(counter: FetchCounter, bytes: Array<UInt8>, delayMs!: Int64 = 0, failMsg!: String = "") {
        this.counter = counter
        this.bytes = bytes
        this.delayMs = delayMs
        this.failMsg = failMsg
    }
    public func writeTo(output: OutputStream): Int64 {
        if (delayMs > 0) {
            sleep(Duration.millisecond * delayMs)
        }
        counter.n++
        if (failMsg.size > 0) {
            throw Exception(failMsg)
        }
        writeAll(output, bytes)
    }
}

// 仓颉不允许捕获可变变量的 lambda 作为值传递，用类实例计数。
private class FetchCounter {
    var n: Int64 = 0
}

// spawn 的 lambda 不能捕获可变局部变量：并发测试用类装箱收集结果/异常。
private class PathBox {
    var p1: String = ""
    var p2: String = ""
}

private class FailureBox {
    var e1: String = ""
    var e2: String = ""
}

// 同一原始 key 并发未命中：single-flight 保证只有一个下载者，其余等待定稿结果。
@Test
func singleFlightDeduplicatesConcurrentMiss(): Unit {
    let dir = Directory.createTemp(Path("."))
    let cache = ImageCache("${dir}/cache")
    let counter = FetchCounter()
    // 模拟慢下载：拉大并发窗口，确保两个调用者都在 leader 完成前到达门闩。
    let writer = TestWriter(counter, testPngBytes(), delayMs: 80)
    let done = SyncCounter(2)
    let paths = PathBox()
    let _ = spawn {
        paths.p1 = cache.ensureCached("asset:sf", writer)
        done.dec()
    }
    let _ = spawn {
        paths.p2 = cache.ensureCached("asset:sf", writer)
        done.dec()
    }
    done.waitUntilZero(timeout: Duration.second * 10)
    @Expect(counter.n, 1)          // 只下载一次
    @Expect(paths.p1.size > 0, true)
    @Expect(paths.p1, paths.p2)    // 等待者与 leader 拿到同一份定稿文件
    @Expect(exists(Path(paths.p1)), true)
    remove(dir, recursive: true)
}

// writer 返回 0（空响应）：不生成正式缓存文件，抛“图片内容为空”，临时文件已清理。
@Test
func emptyWriterDoesNotPublishCache(): Unit {
    let dir = Directory.createTemp(Path("."))
    let cache = ImageCache("${dir}/cache")
    let writer = TestWriter(FetchCounter(), Array<UInt8>(0, repeat: 0))
    var threw = false
    try {
        let _ = cache.ensureCached("asset:empty", writer)
    } catch (_: Exception) {
        threw = true
    }
    @Expect(threw, true)
    @Expect(exists(Path("${dir}/cache/asset_empty.img")), false)  // 空响应不落盘
    @Expect(exists(Path("${dir}/cache/asset_empty.bin")), false)  // 临时文件已清理
    remove(dir, recursive: true)
}

// leader 下载失败：等待者不重复下载，并抛同一异常（上层任务置 error，重试可重新拉取）。
@Test
func singleFlightPropagatesLeaderFailure(): Unit {
    let dir = Directory.createTemp(Path("."))
    let cache = ImageCache("${dir}/cache")
    let counter = FetchCounter()
    let writer = TestWriter(counter, Array<UInt8>(0, repeat: 0), failMsg: "网络中断")
    let done = SyncCounter(2)
    let failures = FailureBox()
    let _ = spawn {
        try {
            let _ = cache.ensureCached("asset:fail", writer)
        } catch (e: Exception) {
            failures.e1 = e.message
        }
        done.dec()
    }
    let _ = spawn {
        try {
            let _ = cache.ensureCached("asset:fail", writer)
        } catch (e: Exception) {
            failures.e2 = e.message
        }
        done.dec()
    }
    done.waitUntilZero(timeout: Duration.second * 10)
    @Expect(counter.n, 1)          // leader 只执行一次 writer
    @Expect(failures.e1.size > 0, true)
    @Expect(failures.e1, failures.e2)
    @Expect(exists(Path("${dir}/cache/asset_fail.img")), false)  // 失败不落盘
    remove(dir, recursive: true)
}

@Test
func cacheStoresRawBytesAndHits(): Unit {
    let dir = Directory.createTemp(Path("."))
    let cache = ImageCache("${dir}/cache")
    let counter = FetchCounter()
    let writer = TestWriter(counter, testPngBytes())
    let p1 = cache.ensureCached("asset:1", writer)
    @Expect(p1.endsWith("asset_1.img"), true)
    // 命中不再调用 writer，且两次返回同一路径
    let p2 = cache.ensureCached("asset:1", writer)
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
    let writer = TestWriter(FetchCounter(), testPngBytes())
    let _ = cache.ensureCached("asset:1", writer)
    let _ = cache.ensureCached("asset:2", writer)
    cache.sweep(1)  // 阈值 1 字节 → 清到阈值以下
    @Expect(cache.totalBytes() <= 1, true)
    remove(dir, recursive: true)
}

@Test
func sweepSkipsInFlightBin(): Unit {
    let dir = Directory.createTemp(Path("."))
    let cache = ImageCache("${dir}/cache")
    let writer = TestWriter(FetchCounter(), testPngBytes())
    let img = cache.ensureCached("asset:1", writer)
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
    let writer = TestWriter(counter, bad)
    let path = cache.ensureCached("asset:bad", writer)
    var threw = false
    try {
        let _ = decodeCachedOrEvict(cache, "asset:bad", path)
    } catch (_: Exception) {
        threw = true
    }
    @Expect(threw, true)
    // 解码失败后坏 .img 已被剔除：再次 ensureCached 会重新走完整下载而不是永远命中坏缓存。
    @Expect(exists(Path(path)), false)
    let _ = cache.ensureCached("asset:bad", writer)
    @Expect(counter.n, 2)
    // 剔除不存在的 key 不抛异常（重试路径的兜底前提）。
    cache.evict("asset:nonexistent")
    remove(dir, recursive: true)
}

// E4: backdrop 解码缩放到目标宽度后仍能正确输出 RGBA 像素。
@Test
func decodeBackdropResizesToTargetWidth(): Unit {
    let dir = Directory.createTemp(Path("."))
    let cache = ImageCache("${dir}/cache")
    let path = cache.ensureCached("asset:backdrop_test", TestWriter(FetchCounter(), testPngBytes()))
    // 1x1 PNG 缩放到 48px 宽：scale = 48.0 / 1.0 = 48.0，输出 48×48
    let d = decodeBackdrop(path, 48)
    @Expect(d.width, 48)
    @Expect(d.height, 48)
    @Expect(d.size, 48 * 48 * 4)
    d.close()
    remove(dir, recursive: true)
}
