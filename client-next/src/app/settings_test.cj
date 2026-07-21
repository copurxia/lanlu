package lanlu_client_next.app

import std.fs.{exists, remove, File, Directory, Path}

@Test
func settingsRoundTrip(): Unit {
    let dir = Directory.createTemp(Path("."))
    let p = "${dir}/sub/config.json"
    let s = AppSettings()
    let srv = s.upsertServer("", "alice 的服务器", "http://127.0.0.1:8082")
    srv.token = "tok-123"
    srv.username = "alice"
    s.activeServerId = srv.id
    saveSettingsTo(p, s)
    let back = loadSettingsFrom(p)
    @Expect(back.serverUrl, "http://127.0.0.1:8082")
    @Expect(back.token, "tok-123")
    @Expect(back.username, "alice")
    remove(dir, recursive: true)
}

@Test
func deletingLastServerDoesNotResurrect(): Unit {
    // 删除唯一服务器后保存：旧三字段必须清空，重载不得经迁移分支重建服务器。
    let dir = Directory.createTemp(Path("."))
    let p = "${dir}/config.json"
    let s = AppSettings()
    let srv = s.upsertServer("", "A", "http://a")
    srv.token = "tok"
    s.activeServerId = srv.id
    saveSettingsTo(p, s)
    let loaded = loadSettingsFrom(p)
    loaded.deleteServer(srv.id)
    saveSettingsTo(p, loaded)
    let back = loadSettingsFrom(p)
    @Expect(back.servers.size, 0)
    @Expect(back.serverUrl, "")
    @Expect(back.token, "")
    remove(dir, recursive: true)
}

@Test
func missingFileYieldsDefaults(): Unit {
    let s = loadSettingsFrom("/tmp/lanlu-cn-test-no-such-dir/config.json")
    @Expect(s.serverUrl, "")
    @Expect(s.token, "")
}

@Test
func corruptFileBackedUpAndReset(): Unit {
    let dir = Directory.createTemp(Path("."))
    let p = "${dir}/config.json"
    File.writeTo(Path(p), "{not json".toArray())
    let s = loadSettingsFrom(p)
    @Expect(s.serverUrl, "")
    @Expect(exists(Path("${p}.bak")), true)
    remove(dir, recursive: true)
}

@Test
func themeDefaultsDarkWhenFieldMissing(): Unit {
    // 旧版 config.json 无 theme 字段：向后兼容，按 "dark" 处理。
    let dir = Directory.createTemp(Path("."))
    let p = "${dir}/config.json"
    File.writeTo(Path(p), "{\"serverUrl\":\"http://x\",\"token\":\"t\",\"username\":\"u\"}".toArray())
    let s = loadSettingsFrom(p)
    @Expect(s.serverUrl, "http://x")
    @Expect(s.theme, "dark")
    remove(dir, recursive: true)
}

@Test
func themeRoundTrip(): Unit {
    let dir = Directory.createTemp(Path("."))
    let p = "${dir}/config.json"
    let s = AppSettings()
    s.theme = "light"
    saveSettingsTo(p, s)
    let back = loadSettingsFrom(p)
    @Expect(back.theme, "light")
    remove(dir, recursive: true)
}

@Test
func fnvHashIsStableHex(): Unit {
    @Expect(fnv1a64Hex("http://a"), fnv1a64Hex("http://a"))
    @Expect(fnv1a64Hex("http://a") != fnv1a64Hex("http://b"), true)
    @Expect(fnv1a64Hex("http://a").size, 16)
}

@Test
func serversRoundTrip(): Unit {
    let dir = Directory.createTemp(Path("."))
    let p = "${dir}/sub/config.json"
    let s = AppSettings()
    let srv = s.upsertServer("", "家里", "http://a:8082/")
    srv.token = "tok"
    s.activeServerId = srv.id
    saveSettingsTo(p, s)
    let back = loadSettingsFrom(p)
    @Expect(back.servers.size, 1)
    @Expect(back.servers[0].name, "家里")
    @Expect(back.servers[0].baseUrl, "http://a:8082") // 已归一化去尾斜杠
    @Expect(back.servers[0].token, "tok")
    @Expect(back.activeServerId, srv.id)
    // legacy 字段同步为 active profile（向后兼容）
    @Expect(back.serverUrl, "http://a:8082")
    @Expect(back.token, "tok")
    remove(dir, recursive: true)
}

@Test
func legacyConfigMigratesToServerList(): Unit {
    // 旧版 config.json（无 servers 字段）加载时迁移为一条 ServerProfile 并置 active。
    let dir = Directory.createTemp(Path("."))
    let p = "${dir}/config.json"
    File.writeTo(Path(p), "{\"serverUrl\":\"http://x\",\"token\":\"t\",\"username\":\"u\"}".toArray())
    let s = loadSettingsFrom(p)
    @Expect(s.servers.size, 1)
    @Expect(s.servers[0].baseUrl, "http://x")
    @Expect(s.servers[0].token, "t")
    @Expect(s.activeServerId, s.servers[0].id)
    remove(dir, recursive: true)
}

@Test
func upsertInsertThenUpdatePreservesSession(): Unit {
    let s = AppSettings()
    let a = s.upsertServer("", "A", "http://a")
    let b = s.upsertServer("", "B", "http://b")
    @Expect(s.servers.size, 2)
    @Expect(s.servers[0].id, b.id) // 新增置顶
    a.token = "tok-a"
    let a2 = s.upsertServer(a.id, "A2", "http://a2")
    @Expect(s.servers.size, 2)
    @Expect(a2.name, "A2")
    @Expect(a2.baseUrl, "http://a2")
    @Expect(a2.token, "tok-a") // 更新名称/地址不清会话
}

@Test
func deleteActiveServerClearsActiveId(): Unit {
    let s = AppSettings()
    let a = s.upsertServer("", "A", "http://a")
    s.activeServerId = a.id
    s.deleteServer(a.id)
    @Expect(s.servers.size, 0)
    @Expect(s.activeServerId, "")
}

@Test
func normalizeServerUrlCases(): Unit {
    @Expect(normalizeServerUrl(" http://a/ "), "http://a")
    @Expect(normalizeServerUrl("http://a//"), "http://a")
    @Expect(normalizeServerUrl("http://a"), "http://a")
}

@Test
func readerSettingsDefaultsWhenMissing(): Unit {
    // 旧版 config.json 无 reader_* 字段：向后兼容，按默认值处理
    //（对齐 frontend use-reader-settings：mode=single-ltr，longPage=true，其余 false）。
    let dir = Directory.createTemp(Path("."))
    let p = "${dir}/config.json"
    File.writeTo(Path(p), "{\"serverUrl\":\"http://x\",\"token\":\"t\",\"username\":\"u\"}".toArray())
    let s = loadSettingsFrom(p)
    @Expect(s.readerMode, "single-ltr")
    @Expect(s.readerDoublePage, false)
    @Expect(s.readerSplitCover, false)
    @Expect(s.readerLongPage, true)
    @Expect(s.readerTapTurnPage, false)
    @Expect(s.readerDoubleTapZoom, false)
    @Expect(s.readerAutoHide, false)
    @Expect(s.readerSeamlessNext, false)
    @Expect(s.readerShowInfo, false)
    @Expect(s.readerAutoPlay, false)
    @Expect(s.readerAutoPlayInterval, 3)
    remove(dir, recursive: true)
}

@Test
func readerSettingsRoundTrip(): Unit {
    let dir = Directory.createTemp(Path("."))
    let p = "${dir}/sub/config.json"
    let s = AppSettings()
    s.readerMode = "single-rtl"
    s.readerDoublePage = true
    s.readerSplitCover = true
    s.readerLongPage = false
    s.readerTapTurnPage = true
    s.readerDoubleTapZoom = true
    s.readerAutoHide = true
    s.readerSeamlessNext = true
    s.readerShowInfo = true
    s.readerAutoPlay = true
    s.readerAutoPlayInterval = 7
    saveSettingsTo(p, s)
    let back = loadSettingsFrom(p)
    @Expect(back.readerMode, "single-rtl")
    @Expect(back.readerDoublePage, true)
    @Expect(back.readerSplitCover, true)
    @Expect(back.readerLongPage, false)
    @Expect(back.readerTapTurnPage, true)
    @Expect(back.readerDoubleTapZoom, true)
    @Expect(back.readerAutoHide, true)
    @Expect(back.readerSeamlessNext, true)
    @Expect(back.readerShowInfo, true)
    @Expect(back.readerAutoPlay, true)
    @Expect(back.readerAutoPlayInterval, 7)
    remove(dir, recursive: true)
}

@Test
func themeIndexMapping(): Unit {
    @Expect(themeToIndex("dark"), 0)
    @Expect(themeToIndex("light"), 1)
    // 非法值回落暗色，与 lanluThemeFor 的语义一致（"light" 之外一律暗色）。
    @Expect(themeToIndex("system"), 0)
    @Expect(indexToTheme(0), "dark")
    @Expect(indexToTheme(1), "light")
    @Expect(indexToTheme(2), "dark")
}
