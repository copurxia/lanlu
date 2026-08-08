package lanlu_client_next.net

import std.fs.{Directory, Path}

// 每个用例独立临时目录：RocksDB 单进程内同一目录只能开一个实例。
private var testCache: ?OfflineCache = None

private func resetCache(): OfflineCache {
    let dir = Directory.createTemp(Path("/tmp"))
    let c = OfflineCache.open(dir.toString()).getOrThrow()
    testCache = c
    c
}

@Test
func responseRoundTrip(): Unit {
    let c = resetCache()
    c.storeResponse("h1", "/api/search?q=a", "{\"data\":[1,2]}")
    let v = c.getResponse("h1", "/api/search?q=a")
    @Expect(v.isSome(), true)
    @Expect(v.getOrThrow(), "{\"data\":[1,2]}")
    @Expect(c.getResponse("h1", "/api/search?q=b").isNone(), true)
}

@Test
func responsePrefixIsolation(): Unit {
    let c = resetCache()
    c.storeResponse("h1", "/api/x", "body-1")
    c.storeResponse("h2", "/api/x", "body-2")
    @Expect(c.getResponse("h1", "/api/x").getOrThrow(), "body-1")
    @Expect(c.getResponse("h2", "/api/x").getOrThrow(), "body-2")
}

@Test
func progressQueueRoundTrip(): Unit {
    let c = resetCache()
    c.enqueueProgress("h1", "arc-1", 5)
    c.enqueueProgress("h1", "arc-1", 9) // 同一档案后写覆盖
    c.enqueueProgress("h1", "arc-2", 3)
    c.enqueueProgress("h2", "arc-9", 42) // 另一服务器不受影响
    let list = c.listProgress("h1")
    @Expect(list.size, 2)
    @Expect(list[0][0], "arc-1")
    @Expect(list[0][1], 9)
    @Expect(list[1][0], "arc-2")
    @Expect(list[1][1], 3)
    c.deleteProgress("h1", "arc-1")
    @Expect(c.listProgress("h1").size, 1)
    @Expect(c.listProgress("h2").size, 1)
}

@Test
func clearServerIsolation(): Unit {
    let c = resetCache()
    c.storeResponse("h1", "/api/x", "a")
    c.storeResponse("h2", "/api/x", "b")
    c.enqueueProgress("h1", "arc-1", 1)
    c.clearServer("h1")
    @Expect(c.getResponse("h1", "/api/x").isNone(), true)
    @Expect(c.getResponse("h2", "/api/x").getOrThrow(), "b")
    @Expect(c.listProgress("h1").size, 0)
}

@Test
func openFailureDegradesToNoop(): Unit {
    // 不可写路径：open 返回 None 且不抛（离线能力缺失不阻断启动）。
    let c = OfflineCache.open("/proc/lanlu-offline-cache-should-not-exist/xx")
    @Expect(c.isNone(), true)
}

@Test
func offlineNoticeFlag(): Unit {
    let n = OfflineNotice()
    @Expect(n.take(), false)
    n.mark()
    @Expect(n.take(), true)
    @Expect(n.take(), false) // 取走即清除
    n.mark()
    n.mark() // 重复置位幂等
    @Expect(n.take(), true)
}
