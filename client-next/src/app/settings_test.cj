package lanlu_client_next.app

import lanlu_client_next.i18n.{LANGUAGE_EN, LANGUAGE_SYSTEM}
import std.fs.{Directory, Path}

private var testStoreReady = false

private func resetTestStore(): Unit {
    if (!testStoreReady) {
        let dir = Directory.createTemp(Path("/tmp"))
        initializeSettingsStore(dir.toString())
        testStoreReady = true
    }
    // 防抖状态复位：补写上一用例的快照并拉回 leading 即刻写语义，避免用例间串扰。
    flushPendingSave()
    lastSaveAtMs = -86400000
    saveFlushScheduled = false
    saveDebounceMs = 300
    clearSettings()
}

@Test
func settingsDefaultsComeFromMmkv(): Unit {
    resetTestStore()
    let s = loadSettings()
    @Expect(s.theme, "dark")
    @Expect(s.languagePreference, LANGUAGE_SYSTEM)
    @Expect(s.readerMode, "single-ltr")
    @Expect(s.readerLongPage, true)
    @Expect(s.readerAutoPlayInterval, 3)
    @Expect(s.probeConnectTimeoutSec, 5)
    @Expect(s.servers.size, 0)
    @Expect(s.serverUrl, "")
}

@Test
func settingsRoundTripThroughMmkv(): Unit {
    resetTestStore()
    let s = AppSettings()
    s.theme = "light"
    s.languagePreference = LANGUAGE_EN
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
    @Expect(back.languagePreference, LANGUAGE_EN)
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
    flushPendingSave() // 第二次调用落在防抖窗口内（trailing），强制补写后再校验

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
    @Expect(languagePreferenceToIndex(LANGUAGE_SYSTEM), 0)
    @Expect(languagePreferenceToIndex("zh"), 1)
    @Expect(languagePreferenceToIndex(LANGUAGE_EN), 2)
    @Expect(languagePreferenceToIndex("unsupported"), 0)
    @Expect(indexToLanguagePreference(0), LANGUAGE_SYSTEM)
    @Expect(indexToLanguagePreference(1), "zh")
    @Expect(indexToLanguagePreference(2), LANGUAGE_EN)
    @Expect(indexToLanguagePreference(9), LANGUAGE_SYSTEM)
}

@Test
func probeConnectTimeoutRoundTrip(): Unit {
    resetTestStore()
    let s = AppSettings()
    s.probeConnectTimeoutSec = 9
    saveSettings(s)
    let back = loadSettings()
    @Expect(back.probeConnectTimeoutSec, 9)
}

@Test
func saveSettingsLeadingWriteIsImmediate(): Unit {
    resetTestStore()
    let s = AppSettings()
    s.theme = "light"
    saveSettings(s) // 距上次落盘远超窗口：leading 立即写
    @Expect(loadSettings().theme, "light")
}

@Test
func saveSettingsCoalescesBurstIntoTrailingFlush(): Unit {
    resetTestStore()
    saveDebounceMs = 150
    let s = AppSettings()
    s.theme = "light"
    saveSettings(s) // leading：立即写 light
    s.theme = "dark"
    saveSettings(s) // 窗口内：只记快照，不落盘
    @Expect(loadSettings().theme, "light") // 磁盘仍是 leading 值
    var tries = 0
    while (loadSettings().theme != "dark" && tries < 50) {
        sleep(Duration.millisecond * 50)
        tries++
    }
    @Expect(loadSettings().theme, "dark") // trailing flush 合并写入最终值
}
