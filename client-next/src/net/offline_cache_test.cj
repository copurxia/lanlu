package lanlu_client_next.net

import std.collection.ArrayList
import std.fs.{Directory, Path}
import std.io.{ByteBuffer, readToEnd}
import std.time.DateTime
import stdx.encoding.json.stream.JsonWriter

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
    c.storeResponse("h1", "u1", "/api/search?q=a", "{\"data\":[1,2]}")
    let v = c.getResponse("h1", "u1", "/api/search?q=a")
    @Expect(v.isSome(), true)
    @Expect(v.getOrThrow(), "{\"data\":[1,2]}")
    @Expect(c.getResponse("h1", "u1", "/api/search?q=b").isNone(), true)
}

@Test
func responsePrefixIsolation(): Unit {
    let c = resetCache()
    c.storeResponse("h1", "u1", "/api/x", "body-1")
    c.storeResponse("h2", "u1", "/api/x", "body-2")
    @Expect(c.getResponse("h1", "u1", "/api/x").getOrThrow(), "body-1")
    @Expect(c.getResponse("h2", "u1", "/api/x").getOrThrow(), "body-2")
}

@Test
func responseAccountIsolation(): Unit {
    let c = resetCache()
    c.storeResponse("h1", "u1", "/api/x", "body-u1")
    c.storeResponse("h1", "u2", "/api/x", "body-u2")
    @Expect(c.getResponse("h1", "u1", "/api/x").getOrThrow(), "body-u1")
    @Expect(c.getResponse("h1", "u2", "/api/x").getOrThrow(), "body-u2")
    @Expect(c.getResponse("h1", "u3", "/api/x").isNone(), true)
}

@Test
func progressQueueRoundTrip(): Unit {
    let c = resetCache()
    c.enqueueProgress("h1", "u1", "arc-1", 5)
    c.enqueueProgress("h1", "u1", "arc-1", 9) // 同一档案后写覆盖
    c.enqueueProgress("h1", "u1", "arc-2", 3)
    c.enqueueProgress("h2", "u1", "arc-9", 42) // 另一服务器不受影响
    c.enqueueProgress("h1", "u2", "arc-9", 17) // 同服务器另一账号不受影响
    let list = c.listProgress("h1", "u1")
    @Expect(list.size, 2)
    @Expect(list[0][0], "arc-1")
    @Expect(list[0][1], 9)
    @Expect(list[1][0], "arc-2")
    @Expect(list[1][1], 3)
    c.deleteProgress("h1", "u1", "arc-1")
    @Expect(c.listProgress("h1", "u1").size, 1)
    @Expect(c.listProgress("h1", "u2").size, 1)
    @Expect(c.listProgress("h2", "u1").size, 1)
}

@Test
func progressListingIsBounded(): Unit {
    let c = resetCache()
    for (i in 0..70) {
        c.enqueueProgress("h1", "u1", "arc-${i}", i)
    }
    @Expect(c.listProgress("h1", "u1", limit: 7).size, 7)
    @Expect(c.listProgress("h1", "u1").size, 64)
}

@Test
func progressRetryStateSurvivesRequeueAndBackoff(): Unit {
    let c = resetCache()
    c.enqueueProgress("h1", "u1", "arc-1", 5)
    // 补报失败：retry count 递增、nextAttemptAt 推后、lastError 记录。
    c.markProgressFailed("h1", "u1", "arc-1", "connection refused")
    let entries = c.listProgressEntries("h1", "u1", limit: 64)
    @Expect(entries.size, 0) // 退避期内不返回
    let entriesAfter = c.listProgressEntries("h1", "u1", limit: 64, includeBackoff: true)
    @Expect(entriesAfter.size, 1)
    @Expect(entriesAfter[0].arcid, "arc-1")
    @Expect(entriesAfter[0].retryCount, 1)
    @Expect(entriesAfter[0].lastError, "connection refused")
    @Expect(entriesAfter[0].nextAttemptAt > 0, true)

    // 用户翻页只更新页码，retry 状态保留。
    c.enqueueProgress("h1", "u1", "arc-1", 9)
    let requeued = c.listProgressEntries("h1", "u1", limit: 64, includeBackoff: true)
    @Expect(requeued[0].page, 9)
    @Expect(requeued[0].retryCount, 1)
    @Expect(requeued[0].lastError, "connection refused")

    // 再次失败：retry count 继续递增（指数退避累进）。
    c.markProgressFailed("h1", "u1", "arc-1", "timeout")
    let twice = c.listProgressEntries("h1", "u1", limit: 64, includeBackoff: true)
    @Expect(twice[0].retryCount, 2)
    @Expect(twice[0].lastError, "timeout")
}

@Test
func progressBatchAckDeletesOnlyAckedAndKeepsFailed(): Unit {
    let c = resetCache()
    c.enqueueProgress("h1", "u1", "arc-1", 1)
    c.enqueueProgress("h1", "u1", "arc-2", 2)
    c.enqueueProgress("h1", "u1", "arc-3", 3)
    c.enqueueProgress("h1", "u2", "arc-9", 9) // 另一账号不受影响
    c.markProgressFailed("h1", "u1", "arc-2", "boom") // 退避中
    let ok = ArrayList<String>()
    ok.add("arc-1")
    ok.add("arc-2") // 补报成功则 ack（即使退避中）
    @Expect(c.ackProgressBatch("h1", "u1", ok), true)
    @Expect(c.listProgress("h1", "u1").size, 1) // arc-3 仍待补报
    @Expect(c.listProgress("h1", "u1")[0][0], "arc-3")
    @Expect(c.listProgress("h1", "u2").size, 1)
}

@Test
func progressPartialFailureDoesNotCrossAccountsOrServers(): Unit {
    let c = resetCache()
    // 同服务器两个账号 + 另一服务器：flush 失败只标记本账号本条。
    c.enqueueProgress("h1", "u1", "arc-1", 1)
    c.enqueueProgress("h1", "u2", "arc-1", 2)
    c.enqueueProgress("h2", "u1", "arc-1", 3)
    c.markProgressFailed("h1", "u1", "arc-1", "network")
    // u1 的 arc-1 退避中，u2 与 h2 的记录不受影响、可正常列出。
    @Expect(c.listProgress("h1", "u1").size, 0)
    @Expect(c.listProgress("h1", "u2").size, 1)
    @Expect(c.listProgress("h1", "u2")[0][1], 2)
    @Expect(c.listProgress("h2", "u1").size, 1)
    @Expect(c.listProgress("h2", "u1")[0][1], 3)
    // 部分失败后 ack 其余：u1 失败条保留，u2 正常 ack。
    let ok = ArrayList<String>()
    ok.add("arc-1")
    @Expect(c.ackProgressBatch("h1", "u2", ok), true)
    @Expect(c.listProgress("h1", "u2").size, 0)
}

@Test
func clearServerIsolation(): Unit {
    let c = resetCache()
    c.storeResponse("h1", "u1", "/api/x", "a")
    c.storeResponse("h2", "u1", "/api/x", "b")
    c.enqueueProgress("h1", "u1", "arc-1", 1)
    c.clearServer("h1")
    @Expect(c.getResponse("h1", "u1", "/api/x").isNone(), true)
    @Expect(c.getResponse("h2", "u1", "/api/x").getOrThrow(), "b")
    @Expect(c.listProgress("h1", "u1").size, 0)
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

@Test
func responseTtlExpiresOnlineHitButAllowsStale(): Unit {
    let c = resetCache()
    let now = DateTime.now().toUnixTimeStamp().toMilliseconds()
    // TTL=1ms：在线命中窗口很快过期。
    c.storeResponseTtl("h1", "u1", "/api/search?q=a", "{\"data\":[1]}", 1)
    c.storeResponseTtl("h1", "u1", "/api/search?q=b", "{\"data\":[2]}", 1)
    // 用未来时间模拟越过 TTL：/api/search 策略 allowStale=true，过期仍可回退。
    @Expect(c.getResponseStale("h1", "u1", "/api/search?q=a", true, nowMs: now + 10).getOrThrow(),
        "{\"data\":[1]}")
    // 显式 allowStale=false：过期视为未命中。
    @Expect(c.getResponseStale("h1", "u1", "/api/search?q=b", false, nowMs: now + 10).isNone(), true)
    // 当前时间未过期：正常命中。
    @Expect(c.getResponseStale("h1", "u1", "/api/search?q=a", false, nowMs: now).getOrThrow(),
        "{\"data\":[1]}")
    // 未过期记录正常命中。
    c.storeResponseTtl("h1", "u1", "/api/tankoubons?lang=zh", "[]", 60000)
    @Expect(c.getResponse("h1", "u1", "/api/tankoubons?lang=zh").getOrThrow(), "[]")
}

@Test
func responseLegacyKeyMigratesToObjectEnvelope(): Unit {
    let c = resetCache()
    // 直接写旧格式 resp:{server}:{account}:{path} JSON key，验证读取时迁移。
    let out = ByteBuffer()
    let w = JsonWriter(out)
    w.startObject()
    w.writeName("saved_at").writeValue("2026-08-15 00:00:00")
    w.writeName("body").writeValue("{\"legacy\":true}")
    w.endObject()
    w.flush()
    let _ = c.putRawBytesForTest("resp:h1:u1:/api/search?q=legacy".toArray(), readToEnd(out))
    let body = c.getResponse("h1", "u1", "/api/search?q=legacy")
    @Expect(body.isSome(), true)
    @Expect(body.getOrThrow(), "{\"legacy\":true}")
    // 旧 key 已被删除（迁移后不再双写），新格式可读。
    @Expect(c.hasRawKeyForTest("resp:h1:u1:/api/search?q=legacy".toArray()), false)
    @Expect(c.getResponse("h1", "u1", "/api/search?q=legacy").getOrThrow(), "{\"legacy\":true}")
}

@Test
func responsePrefixInvalidationMatchesPolicyRegistry(): Unit {
    let c = resetCache()
    c.storeResponse("h1", "u1", "/api/archives/arc-9/metadata", "m")
    c.storeResponse("h1", "u1", "/api/archives/arc-9/files", "f")
    c.storeResponse("h1", "u1", "/api/search?q=x", "s")
    c.storeResponse("h1", "u1", "/api/archives/arc-8/metadata", "other")
    c.storeResponse("h1", "u2", "/api/archives/arc-9/metadata", "u2")

    // 收藏 mutation 的失效前缀：arc 元数据、搜索、推荐与所属合集（页表 files 与收藏无关，保留）。
    for (prefix in invalidatedResponsePrefixes("archive-favorite", "arc-9")) {
        c.deleteResponsePrefix("h1", "u1", prefix)
    }
    @Expect(c.getResponse("h1", "u1", "/api/archives/arc-9/metadata").isNone(), true)
    @Expect(c.getResponse("h1", "u1", "/api/archives/arc-9/files").getOrThrow(), "f")
    @Expect(c.getResponse("h1", "u1", "/api/search?q=x").isNone(), true)
    // 无关实体与账号不受影响。
    @Expect(c.getResponse("h1", "u1", "/api/archives/arc-8/metadata").getOrThrow(), "other")
    @Expect(c.getResponse("h1", "u2", "/api/archives/arc-9/metadata").getOrThrow(), "u2")
}

@Test
func responsePolicyTableSelectsLongestPrefix(): Unit {
    // /api/archives/ 命中档案策略（中 TTL、允许 stale）；/api/archives 自身无匹配走默认。
    let archivePolicy = responsePolicyFor("/api/archives/arc-1/metadata")
    @Expect(archivePolicy.allowStaleOffline, true)
    let searchPolicy = responsePolicyFor("/api/search?sortby=RANDOM()")
    @Expect(searchPolicy.allowStaleOffline, true)
    let mePolicy = responsePolicyFor("/api/auth/me")
    @Expect(mePolicy.allowStaleOffline, false)
    let fallback = responsePolicyFor("/api/unknown-endpoint")
    @Expect(fallback.allowStaleOffline, false)
    // P5 统计与管理端点：短 TTL、不允许 stale（仅在线 session cache）。
    let statsPolicy = responsePolicyFor("/api/user/stats")
    @Expect(statsPolicy.allowStaleOffline, false)
    let adminPolicy = responsePolicyFor("/api/admin/smart_filters")
    @Expect(adminPolicy.allowStaleOffline, false)
    let usersPolicy = responsePolicyFor("/api/auth/admin/users")
    @Expect(usersPolicy.allowStaleOffline, false)
}

@Test
func securityPageDataNeverEntersCacheDb(): Unit {
    let c = resetCache()
    // 安全页端点即使误调 storeResponse 也拒绝落库。
    c.storeResponse("h1", "u1", "/api/auth/sessions", "{\"data\":[{\"id\":1}]}")
    c.storeResponse("h1", "u1", "/api/auth/tokens", "{\"data\":[{\"token\":\"secret\"}]}")
    c.storeResponse("h1", "u1", "/api/auth/webauthn/credentials", "{\"data\":[]}")
    c.storeResponse("h1", "u1", "/api/auth/totp/status", "{\"enabled\":true}")
    c.storeResponse("h1", "u1", "/api/auth/username", "{}")
    c.storeResponse("h1", "u1", "/api/auth/password", "{}")
    @Expect(c.getResponse("h1", "u1", "/api/auth/sessions").isNone(), true)
    @Expect(c.getResponse("h1", "u1", "/api/auth/tokens").isNone(), true)
    @Expect(c.getResponse("h1", "u1", "/api/auth/webauthn/credentials").isNone(), true)
    @Expect(c.getResponse("h1", "u1", "/api/auth/totp/status").isNone(), true)
    @Expect(c.getResponse("h1", "u1", "/api/auth/username").isNone(), true)
    @Expect(c.getResponse("h1", "u1", "/api/auth/password").isNone(), true)
    // 可缓存端点不受影响。
    c.storeResponse("h1", "u1", "/api/user/stats", "{\"data\":{}}")
    @Expect(c.getResponse("h1", "u1", "/api/user/stats").getOrThrow().size > 0, true)
    // 直接写盘测试：raw key 不存在。
    @Expect(c.hasRawKeyForTest("/api/auth/tokens".toArray()), false)
}

@Test
func adminMutationInvalidationCoversStatsAndAdminEndpoints(): Unit {
    let c = resetCache()
    c.storeResponse("h1", "u1", "/api/user/stats", "{\"favoriteCount\":1}")
    c.storeResponse("h1", "u1", "/api/user/trend?days=30", "[{}]")
    c.storeResponse("h1", "u1", "/api/tags/cloud?limit=200&lang=zh", "[]")
    c.storeResponse("h1", "u1", "/api/admin/smart_filters", "[]")
    c.storeResponse("h1", "u1", "/api/admin/cron/tasks", "[]")
    c.storeResponse("h1", "u1", "/api/admin/system/settings", "[]")
    c.storeResponse("h1", "u1", "/api/admin/categories", "[]")
    c.storeResponse("h1", "u1", "/api/auth/admin/users", "[]")
    c.storeResponse("h1", "u2", "/api/admin/smart_filters", "other-account")

    // 管理 mutation 精确失效相关端点，其余不受影响。
    for (prefix in invalidatedResponsePrefixes("admin-category", "cat:1")) {
        c.deleteResponsePrefix("h1", "u1", prefix)
    }
    @Expect(c.getResponse("h1", "u1", "/api/admin/categories").isNone(), true)
    @Expect(c.getResponse("h1", "u1", "/api/admin/smart_filters").getOrThrow(), "[]")
    @Expect(c.getResponse("h1", "u2", "/api/admin/smart_filters").getOrThrow(), "other-account")

    for (prefix in invalidatedResponsePrefixes("smart-filter", "5")) {
        c.deleteResponsePrefix("h1", "u1", prefix)
    }
    @Expect(c.getResponse("h1", "u1", "/api/admin/smart_filters").isNone(), true)
    @Expect(c.getResponse("h1", "u1", "/api/user/stats").getOrThrow().size > 0, true)

    // cron 失效覆盖 cron 前缀。
    for (prefix in invalidatedResponsePrefixes("cron", "")) {
        c.deleteResponsePrefix("h1", "u1", prefix)
    }
    @Expect(c.getResponse("h1", "u1", "/api/admin/cron/tasks").isNone(), true)
    @Expect(c.getResponse("h1", "u1", "/api/admin/system/settings").getOrThrow(), "[]")

    // 用户统计失效覆盖 user-stats 三端点。
    for (prefix in invalidatedResponsePrefixes("user-stats", "")) {
        c.deleteResponsePrefix("h1", "u1", prefix)
    }
    @Expect(c.getResponse("h1", "u1", "/api/user/stats").isNone(), true)
    @Expect(c.getResponse("h1", "u1", "/api/user/trend?days=30").isNone(), true)
    @Expect(c.getResponse("h1", "u1", "/api/tags/cloud?limit=200&lang=zh").isNone(), true)
}
