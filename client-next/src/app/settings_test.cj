package lanlu_client_next.app

import std.fs.{exists, remove, File, Directory, Path}

@Test
func settingsRoundTrip(): Unit {
    let dir = Directory.createTemp(Path("."))
    let p = "${dir}/sub/config.json"
    let s = AppSettings()
    s.serverUrl = "http://127.0.0.1:8082"
    s.token = "tok-123"
    s.username = "alice"
    saveSettingsTo(p, s)
    let back = loadSettingsFrom(p)
    @Expect(back.serverUrl, "http://127.0.0.1:8082")
    @Expect(back.token, "tok-123")
    @Expect(back.username, "alice")
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
func fnvHashIsStableHex(): Unit {
    @Expect(fnv1a64Hex("http://a"), fnv1a64Hex("http://a"))
    @Expect(fnv1a64Hex("http://a") != fnv1a64Hex("http://b"), true)
    @Expect(fnv1a64Hex("http://a").size, 16)
}
