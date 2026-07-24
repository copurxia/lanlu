package lanlu_client_next.app

import std.fs.{Directory, Path}

private var testStoreReady = false

private func resetTestStore(): Unit {
    if (!testStoreReady) {
        let dir = Directory.createTemp(Path("/tmp"))
        initializeSettingsStore(dir.toString())
        testStoreReady = true
    }
    clearSettings()
}

@Test
func settingsDefaultsComeFromMmkv(): Unit {
    resetTestStore()
    let s = loadSettings()
    @Expect(s.theme, "dark")
    @Expect(s.readerMode, "single-ltr")
    @Expect(s.readerLongPage, true)
    @Expect(s.readerAutoPlayInterval, 3)
    @Expect(s.servers.size, 0)
    @Expect(s.serverUrl, "")
}

@Test
func settingsRoundTripThroughMmkv(): Unit {
    resetTestStore()
    let s = AppSettings()
    s.theme = "light"
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
    let srv = s.upsertServer("", "家里", "http://a:8082/")
    srv.token = "tok"
    srv.username = "alice"
    srv.lastUsedAt = "2026-07-24 12:00"
    s.activeServerId = srv.id
    saveSettings(s)

    let back = loadSettings()
    @Expect(back.theme, "light")
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
    @Expect(back.servers.size, 1)
    @Expect(back.servers[0].baseUrl, "http://a:8082")
    @Expect(back.serverUrl, "http://a:8082")
    @Expect(back.token, "tok")
    @Expect(back.username, "alice")
}

@Test
func deletingLastServerRemovesMmkvEntries(): Unit {
    resetTestStore()
    let s = AppSettings()
    let srv = s.upsertServer("", "A", "http://a")
    srv.token = "tok"
    s.activeServerId = srv.id
    saveSettings(s)
    s.deleteServer(srv.id)
    saveSettings(s)

    let back = loadSettings()
    @Expect(back.servers.size, 0)
    @Expect(back.activeServerId, "")
    @Expect(back.serverUrl, "")
    @Expect(back.token, "")
}

@Test
func serverEditingPreservesSession(): Unit {
    let s = AppSettings()
    let a = s.upsertServer("", "A", "http://a")
    a.token = "tok-a"
    let a2 = s.upsertServer(a.id, "A2", "http://a2")
    @Expect(s.servers.size, 1)
    @Expect(a2.name, "A2")
    @Expect(a2.baseUrl, "http://a2")
    @Expect(a2.token, "tok-a")
}

@Test
func settingsHelpersAreStable(): Unit {
    @Expect(normalizeServerUrl(" http://a// "), "http://a")
    @Expect(fnv1a64Hex("http://a").size, 16)
    @Expect(fnv1a64Hex("http://a") != fnv1a64Hex("http://b"), true)
    @Expect(themeToIndex("dark"), 0)
    @Expect(themeToIndex("light"), 1)
    @Expect(indexToTheme(1), "light")
    @Expect(indexToTheme(2), "dark")
}
