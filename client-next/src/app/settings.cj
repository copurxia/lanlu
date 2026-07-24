package lanlu_client_next.app

import kv4cj.*
import std.collection.ArrayList
import std.env.getVariable
import std.fs.{exists, Directory, Path}
import std.overflow.*
import std.time.DateTime

// 一台已保存的 lanlu 服务器：列表管理 + 按服务器各存会话（token/username）。
public class ServerProfile {
    public var id: String = ""
    public var name: String = ""
    public var baseUrl: String = ""
    public var token: String = ""
    public var username: String = ""
    public var lastUsedAt: String = ""
}

// 服务器地址归一化：trim + 去尾部所有斜杠（对齐 client storage/servers.ts）。
public func normalizeServerUrl(input: String): String {
    var b = input.trimAscii()
    while (b.endsWith("/")) {
        b = b[0..b.size - 1]
    }
    b
}

// 服务器 id：地址哈希前缀 + 单调计数（同地址可重复添加，进程内唯一即可，落盘后不再生成）。
private var serverIdCounter: Int64 = 0

private func newServerId(baseUrl: String): String {
    serverIdCounter++
    "srv-${fnv1a64Hex(baseUrl)[0..8]}-${serverIdCounter}"
}

// 上次使用时间的展示格式。
public func nowLabel(): String {
    DateTime.now().format("yyyy-MM-dd HH:mm")
}

public class AppSettings {
    public var serverUrl: String = ""
    public var token: String = ""
    public var username: String = ""
    // 界面主题："dark"（默认）| "light"。
    public var theme: String = "dark"
    // 阅读器设置默认值对齐 frontend use-reader-settings；ReaderModel 读初值并写回。
    public var readerMode: String = "single-ltr" // single-ltr | single-rtl | single-ttb | webtoon
    public var readerDoublePage: Bool = false
    public var readerSplitCover: Bool = false
    public var readerLongPage: Bool = true
    public var readerTapTurnPage: Bool = false
    public var readerDoubleTapZoom: Bool = false
    public var readerAutoHide: Bool = false
    public var readerSeamlessNext: Bool = false // 无缝续读：仅设置占位（YAGNI，不实现拼接）
    public var readerShowInfo: Bool = false // 媒体信息浮层开关（文件名/时长/位置等）
    public var readerAutoPlay: Bool = false // 自动播放（按间隔自动翻页，到底自动停）
    public var readerAutoPlayInterval: Int64 = 3 // 自动播放间隔（秒，1-10）

    // 多服务器列表与当前选中；旧三字段（serverUrl/token/username）仅作迁移与向后兼容同步。
    public var servers = ArrayList<ServerProfile>()
    public var activeServerId: String = ""

    public func profileById(id: String): ?ServerProfile {
        for (p in servers) {
            if (p.id == id) {
                return p
            }
        }
        None
    }

    public func activeProfile(): ?ServerProfile {
        profileById(activeServerId)
    }

    // id 空=新增置顶；命中=更新 name/baseUrl（token/username/lastUsedAt 保留，改名换址不掉会话）。
    public func upsertServer(id: String, name: String, baseUrl: String): ServerProfile {
        let norm = normalizeServerUrl(baseUrl)
        if (id.size > 0) {
            for (p in servers) {
                if (p.id == id) {
                    p.name = name
                    p.baseUrl = norm
                    return p
                }
            }
        }
        let p = ServerProfile()
        p.id = newServerId(norm)
        p.name = name
        p.baseUrl = norm
        let next = ArrayList<ServerProfile>()
        next.add(p)
        next.add(all: servers)
        servers = next
        return p
    }

    public func deleteServer(id: String): Unit {
        var i: Int64 = 0
        while (i < servers.size) {
            if (servers[i].id == id) {
                servers.remove(at: i)
                break
            }
            i++
        }
        if (activeServerId == id) {
            activeServerId = ""
        }
    }

    // serverUrl/token/username 是运行期便捷镜像，不参与持久化；唯一真源是 active profile。
    public func syncActiveProfile(): Unit {
        match (activeProfile()) {
            case Some(p) =>
                serverUrl = p.baseUrl
                token = p.token
                username = p.username
            case None =>
                serverUrl = ""
                token = ""
                username = ""
        }
    }
}

public func defaultSettingsRoot(): String {
    let home = getVariable("HOME") ?? "."
    "${home}/.config/lanlu-client-next/mmkv"
}

private var settingsStore: ?MMKV = None

public func initializeSettingsStore(): Unit {
    initializeSettingsStore(defaultSettingsRoot())
}

public func initializeSettingsStore(root: String): Unit {
    if (!exists(Path(root))) {
        Directory.create(Path(root), recursive: true)
    }
    MMKV.initializeMMKV(root, MMKVLogWarning)
    settingsStore = MMKV.mmkvWithID("client-settings")
}

private func store(): MMKV {
    match (settingsStore) {
        case Some(kv) => kv
        case None => throw Exception("settings store is not initialized")
    }
}

private func serverKey(index: Int64, field: String): String {
    "servers.${index}.${field}"
}

public func loadSettings(): AppSettings {
    let kv = store()
    let s = AppSettings()
    s.theme = kv.getString("appearance.theme", defaultValue: "dark")
    if (s.theme != "light") {
        s.theme = "dark"
    }
    s.readerMode = kv.getString("reader.mode", defaultValue: "single-ltr")
    if (s.readerMode != "single-ltr" && s.readerMode != "single-rtl" && s.readerMode != "single-ttb" && s.readerMode !=
        "webtoon") {
        s.readerMode = "single-ltr"
    }
    s.readerDoublePage = kv.getBool("reader.double_page")
    s.readerSplitCover = kv.getBool("reader.split_cover")
    s.readerLongPage = kv.getBool("reader.long_page", defaultValue: true)
    s.readerTapTurnPage = kv.getBool("reader.tap_turn_page")
    s.readerDoubleTapZoom = kv.getBool("reader.double_tap_zoom")
    s.readerAutoHide = kv.getBool("reader.auto_hide")
    s.readerSeamlessNext = kv.getBool("reader.seamless_next")
    s.readerShowInfo = kv.getBool("reader.show_info")
    s.readerAutoPlay = kv.getBool("reader.auto_play")
    s.readerAutoPlayInterval = kv.getInt64("reader.auto_play_interval", defaultValue: 3)
    if (s.readerAutoPlayInterval < 1 || s.readerAutoPlayInterval > 10) {
        s.readerAutoPlayInterval = 3
    }
    s.activeServerId = kv.getString("servers.active_id")
    let count = kv.getInt64("servers.count")
    for (i in 0..count) {
        let p = ServerProfile()
        p.id = kv.getString(serverKey(i, "id"))
        p.name = kv.getString(serverKey(i, "name"))
        p.baseUrl = normalizeServerUrl(kv.getString(serverKey(i, "base_url")))
        p.token = kv.getString(serverKey(i, "token"))
        p.username = kv.getString(serverKey(i, "username"))
        p.lastUsedAt = kv.getString(serverKey(i, "last_used_at"))
        if (p.id.size > 0 && p.baseUrl.size > 0) {
            s.servers.add(p)
        }
    }
    if (s.profileById(s.activeServerId).isNone()) {
        s.activeServerId = ""
    }
    s.syncActiveProfile()
    s
}

public func saveSettings(s: AppSettings): Unit {
    let kv = store()
    s.syncActiveProfile()
    let oldCount = kv.getInt64("servers.count")
    let _ = kv.set("schema.version", Int64(1))
    let _ = kv.set("appearance.theme", s.theme)
    let _ = kv.set("reader.mode", s.readerMode)
    let _ = kv.set("reader.double_page", s.readerDoublePage)
    let _ = kv.set("reader.split_cover", s.readerSplitCover)
    let _ = kv.set("reader.long_page", s.readerLongPage)
    let _ = kv.set("reader.tap_turn_page", s.readerTapTurnPage)
    let _ = kv.set("reader.double_tap_zoom", s.readerDoubleTapZoom)
    let _ = kv.set("reader.auto_hide", s.readerAutoHide)
    let _ = kv.set("reader.seamless_next", s.readerSeamlessNext)
    let _ = kv.set("reader.show_info", s.readerShowInfo)
    let _ = kv.set("reader.auto_play", s.readerAutoPlay)
    let _ = kv.set("reader.auto_play_interval", s.readerAutoPlayInterval)
    let _ = kv.set("servers.active_id", s.activeServerId)
    let _ = kv.set("servers.count", s.servers.size)
    for (i in 0..s.servers.size) {
        let p = s.servers[i]
        let _ = kv.set(serverKey(i, "id"), p.id)
        let _ = kv.set(serverKey(i, "name"), p.name)
        let _ = kv.set(serverKey(i, "base_url"), p.baseUrl)
        let _ = kv.set(serverKey(i, "token"), p.token)
        let _ = kv.set(serverKey(i, "username"), p.username)
        let _ = kv.set(serverKey(i, "last_used_at"), p.lastUsedAt)
    }
    for (i in s.servers.size..oldCount) {
        kv.removeValuesForKeys(
            [serverKey(i, "id"), serverKey(i, "name"), serverKey(i, "base_url"), serverKey(i, "token"),
                serverKey(i, "username"), serverKey(i, "last_used_at")])
    }
    kv.sync()
}

public func closeSettingsStore(): Unit {
    match (settingsStore) {
        case Some(kv) => kv.sync()
        case None => ()
    }
    MMKV.onExit()
    settingsStore = None
}

// 清空客户端设置并保留已打开的 store，供“恢复默认设置”和测试隔离复用。
public func clearSettings(): Unit {
    store().clearAll()
    store().sync()
}

// 服务器地址 → 稳定的短目录名（区分多服务器缓存）。
// FNV-1a 需要环绕乘法：仓颉整数运算默认溢出抛异常，且 cjc 1.1.3 没有 `*!` 运算符，
// 用 std.overflow 的 wrappingMul（截断高位，等同 C 无符号溢出行为）。
public func fnv1a64Hex(s: String): String {
    var hash: UInt64 = 0xcbf29ce484222325
    for (b in s.toArray()) {
        hash = hash ^ UInt64(b)
        hash = hash.wrappingMul(0x100000001b3)
    }
    let digits = "0123456789abcdef".toArray()
    let out = Array<UInt8>(16, repeat: 0)
    var v = hash
    for (i in 0..16) {
        out[15 - i] = digits[Int64(v & 0xF)]
        v = v >> 4
    }
    String.fromUtf8(out)
}

public func defaultCacheRoot(serverUrl: String): String {
    let home = getVariable("HOME") ?? "."
    "${home}/.cache/lanlu-client-next/${fnv1a64Hex(serverUrl)}"
}

// 主题设置值 ↔ 外观页 SegmentedControl 分段索引（0=暗色 1=亮色）。
// 非法值一律回落暗色，与 theme.cj lanluThemeFor 的 "light" 之外按暗色处理对齐。
public func themeToIndex(mode: String): Int64 {
    if (mode == "light") {
        1
    } else {
        0
    }
}

public func indexToTheme(i: Int64): String {
    if (i == 1) {
        "light"
    } else {
        "dark"
    }
}
