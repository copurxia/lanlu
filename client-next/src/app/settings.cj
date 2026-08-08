package lanlu_client_next.app

import lanlu_client_next.i18n.{LANGUAGE_EN, LANGUAGE_SYSTEM, LANGUAGE_ZH, normalizeLanguagePreference}
import lanlu_client_next.net.decodeRaw
import rocksdb_ffi.{RocksDb, RocksDbOperationResult}
import std.collection.ArrayList
import std.env.getVariable
import std.fs.{exists, Directory, Path}
import std.io.{ByteBuffer, readToEnd}
import std.overflow.*
import std.sync.Mutex
import std.time.{DateTime, MonoTime}
import stdx.encoding.json.stream.*

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

// html 阅读字号档位（px）：13/16/19/22，就近取档（默认 16）。
public func clampHtmlFontSize(v: Int64): Int64 {
    if (v <= 14) {
        13
    } else if (v <= 17) {
        16
    } else if (v <= 20) {
        19
    } else {
        22
    }
}

// html 阅读页边距档位（px）：24/48/72，就近取档（默认 48）。
public func clampHtmlMargin(v: Int64): Int64 {
    if (v <= 36) {
        24
    } else if (v <= 60) {
        48
    } else {
        72
    }
}

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
    // 界面字体：TTF/TTC/OTF 文件路径。空串 = 使用系统默认字体。需重启生效。
    public var fontPath: String = ""
    // 显示语言偏好：system（跟随系统）| zh | en。
    public var languagePreference: String = LANGUAGE_SYSTEM
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
    // html 阅读排版（Blitz 离屏页）：字号档位 px（13/16/19/22，默认 16）、
    // 页边距档位 px（24/48/72，默认 48），经 htmlThemeCss 的 UA CSS 生效。
    public var readerHtmlFontSize: Int64 = 16
    public var readerHtmlMargin: Int64 = 48

    // 服务器在线探测（probe）连接硬超时（秒）：不可达服务器的 TCP connect 走 OS 默认重传
    // 可达分钟级，探测必须短超时快速判离线。LanluApi(connectTimeout:) 的消费方。
    public var probeConnectTimeoutSec: Int64 = 5

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
    "${home}/.config/lanlu-client-next/kv"
}

private var settingsStore: ?RocksDb = None

public func initializeSettingsStore(): Unit {
    initializeSettingsStore(defaultSettingsRoot())
}

// RocksDB 是目录型 DB，root 直接作为 DB 路径；打开失败抛异常（与旧 store 未初始化即抛一致）。
public func initializeSettingsStore(root: String): Unit {
    if (!exists(Path(root))) {
        Directory.create(Path(root), recursive: true)
    }
    match (RocksDb.openLowMemory(root)) {
        case (true, Some(db), _) => settingsStore = db
        case (_, _, err) => throw Exception("rocksdb settings store open failed: ${err}")
    }
}

// 包内可见（测试注入坏数据用）；public 仅供本包调用方使用。
func store(): RocksDb {
    match (settingsStore) {
        case Some(db) => db
        case None => throw Exception("settings store is not initialized")
    }
}

public func loadSettings(): AppSettings {
    let kv = store()
    match (kv.getResult("settings")) {
        case RocksDbOperationResult<String>.Ok(body) => parseSettingsJson(body)
        // 键缺失或读失败一律回落全默认（坏数据自愈，不再有逐键回退）。
        case _ => AppSettings()
    }
}

// ---- 单键 JSON 整表快照（schema_version=2）----
// 整个 AppSettings 序列化为一个 JSON 文档存 "settings" 键，单次 put 天然原子（WAL 持久化），
// 不再有 servers.count/索引键与旧键清理。解析失败回落全默认 AppSettings()。
private func parseSettingsJson(body: String): AppSettings {
    let s = AppSettings()
    var buf = ByteBuffer()
    unsafe { buf.write(body.rawData()) }
    let r = JsonReader(buf)
    try {
        while (let Some(tok) <- r.peek()) {
            match (tok) {
                case BeginObject =>
                    r.startObject()
                    while (r.peek() != EndObject) {
                        let n = r.readName()
                        match (n) {
                            case "appearance" => readAppearance(r, s)
                            case "reader" => readReader(r, s)
                            case "network" => readNetwork(r, s)
                            case "servers" => readServers(r, s)
                            case _ => r.skip()
                        }
                    }
                    r.endObject()
                    break
                case _ => return AppSettings()
            }
        }
    } catch (_: Exception) {
        return AppSettings()
    }
    normalizeLoadedSettings(s)
    s
}

private func readAppearance(r: JsonReader, s: AppSettings): Unit {
    r.startObject()
    while (r.peek() != EndObject) {
        let n = r.readName()
        match (n) {
            case "theme" => s.theme = decodeRaw<String>(r.readValueBytes(), "dark")
            case "font_path" => s.fontPath = decodeRaw<String>(r.readValueBytes(), "")
            case "language" => s.languagePreference = decodeRaw<String>(r.readValueBytes(), LANGUAGE_SYSTEM)
            case _ => r.skip()
        }
    }
    r.endObject()
}

private func readReader(r: JsonReader, s: AppSettings): Unit {
    r.startObject()
    while (r.peek() != EndObject) {
        let n = r.readName()
        match (n) {
            case "mode" => s.readerMode = decodeRaw<String>(r.readValueBytes(), "single-ltr")
            case "double_page" => s.readerDoublePage = decodeRaw<Bool>(r.readValueBytes(), false)
            case "split_cover" => s.readerSplitCover = decodeRaw<Bool>(r.readValueBytes(), false)
            case "long_page" => s.readerLongPage = decodeRaw<Bool>(r.readValueBytes(), true)
            case "tap_turn_page" => s.readerTapTurnPage = decodeRaw<Bool>(r.readValueBytes(), false)
            case "double_tap_zoom" => s.readerDoubleTapZoom = decodeRaw<Bool>(r.readValueBytes(), false)
            case "auto_hide" => s.readerAutoHide = decodeRaw<Bool>(r.readValueBytes(), false)
            case "seamless_next" => s.readerSeamlessNext = decodeRaw<Bool>(r.readValueBytes(), false)
            case "show_info" => s.readerShowInfo = decodeRaw<Bool>(r.readValueBytes(), false)
            case "auto_play" => s.readerAutoPlay = decodeRaw<Bool>(r.readValueBytes(), false)
            case "auto_play_interval" => s.readerAutoPlayInterval = decodeRaw<Int64>(r.readValueBytes(), 3)
            case "html_font_size" => s.readerHtmlFontSize = decodeRaw<Int64>(r.readValueBytes(), 16)
            case "html_margin" => s.readerHtmlMargin = decodeRaw<Int64>(r.readValueBytes(), 48)
            case _ => r.skip()
        }
    }
    r.endObject()
}

private func readNetwork(r: JsonReader, s: AppSettings): Unit {
    r.startObject()
    while (r.peek() != EndObject) {
        let n = r.readName()
        match (n) {
            case "probe_connect_timeout_sec" => s.probeConnectTimeoutSec = decodeRaw<Int64>(r.readValueBytes(), 5)
            case _ => r.skip()
        }
    }
    r.endObject()
}

private func readServers(r: JsonReader, s: AppSettings): Unit {
    r.startObject()
    while (r.peek() != EndObject) {
        let n = r.readName()
        match (n) {
            case "active_id" => s.activeServerId = decodeRaw<String>(r.readValueBytes(), "")
            case "list" =>
                r.startArray()
                while (r.peek() != EndArray) {
                    s.servers.add(readServerProfile(r))
                }
                r.endArray()
            case _ => r.skip()
        }
    }
    r.endObject()
}

private func readServerProfile(r: JsonReader): ServerProfile {
    let p = ServerProfile()
    r.startObject()
    while (r.peek() != EndObject) {
        let n = r.readName()
        match (n) {
            case "id" => p.id = decodeRaw<String>(r.readValueBytes(), "")
            case "name" => p.name = decodeRaw<String>(r.readValueBytes(), "")
            case "base_url" => p.baseUrl = normalizeServerUrl(decodeRaw<String>(r.readValueBytes(), ""))
            case "token" => p.token = decodeRaw<String>(r.readValueBytes(), "")
            case "username" => p.username = decodeRaw<String>(r.readValueBytes(), "")
            case "last_used_at" => p.lastUsedAt = decodeRaw<String>(r.readValueBytes(), "")
            case _ => r.skip()
        }
    }
    r.endObject()
    p
}

// 读路径归一化（对齐旧 loadSettings）：非法枚举回落、档位钳制、超时范围、activeId 校验。
private func normalizeLoadedSettings(s: AppSettings): Unit {
    if (s.theme != "light") {
        s.theme = "dark"
    }
    s.languagePreference = normalizeLanguagePreference(s.languagePreference)
    if (s.readerMode != "single-ltr" && s.readerMode != "single-rtl" && s.readerMode != "single-ttb" && s.readerMode !=
        "webtoon") {
        s.readerMode = "single-ltr"
    }
    if (s.readerAutoPlayInterval < 1 || s.readerAutoPlayInterval > 10) {
        s.readerAutoPlayInterval = 3
    }
    s.readerHtmlFontSize = clampHtmlFontSize(s.readerHtmlFontSize)
    s.readerHtmlMargin = clampHtmlMargin(s.readerHtmlMargin)
    if (s.probeConnectTimeoutSec < 1 || s.probeConnectTimeoutSec > 60) {
        s.probeConnectTimeoutSec = 5
    }
    if (s.profileById(s.activeServerId).isNone()) {
        s.activeServerId = ""
    }
    s.syncActiveProfile()
}

// ---- 落盘防抖（leading 即时 + trailing 合并）----
// 滑条类高频调用（自动播放间隔拖动、窗口期连续设置变更）会逐次触发整表重写。
// 这里给 saveSettings 加 300ms 合并：距上次落盘超窗 → 立即写（leading，开关类即时性不变）；
// 窗口内的连续调用只记最新快照，由后台线程到点做一次 trailing flush（合并后只写最终值）。
// 以下变量不 private 以便同包测试注入窗口/复位状态；saveClock 默认单调时钟毫秒。
private let saveClockEpoch = MonoTime.now()
var saveDebounceMs: Int64 = 300
var saveClock: () -> Int64 = {=> (MonoTime.now() - saveClockEpoch).toMilliseconds()}
private let saveStateMutex = Mutex()
private let saveWriteMutex = Mutex()
var lastSaveAtMs: Int64 = -86400000
var pendingSave: ?AppSettings = None
var saveFlushScheduled = false

public func saveSettings(s: AppSettings): Unit {
    var flushNow = false
    var waitMs: Int64 = 0
    synchronized(saveStateMutex) {
        let now = saveClock()
        if (now - lastSaveAtMs >= saveDebounceMs) {
            lastSaveAtMs = now
            flushNow = true
        } else {
            pendingSave = s
            if (!saveFlushScheduled) {
                saveFlushScheduled = true
                waitMs = saveDebounceMs - (now - lastSaveAtMs)
            }
        }
    }
    if (flushNow) {
        writeSettings(s)
        return
    }
    if (waitMs > 0) {
        // spawn 的 lambda 不能捕获可变局部变量：先固化为不可变副本。
        let w = waitMs
        let _ = spawn {
            saveFlushLoop(w)
        }
    }
}

// trailing flush 线程：窗口起点固定在 leading 落盘时刻（不随窗口内调用顺延），
// 到点后写最后一次快照。提前唤醒（时钟抖动）时按剩余时长续睡。
private func saveFlushLoop(initialWaitMs: Int64): Unit {
    var waitMs = initialWaitMs
    while (true) {
        sleep(Duration.millisecond * waitMs)
        var target: ?AppSettings = None
        var expired = false
        synchronized(saveStateMutex) {
            let now = saveClock()
            let remain = saveDebounceMs - (now - lastSaveAtMs)
            if (remain > 0) {
                waitMs = remain
            } else {
                saveFlushScheduled = false
                lastSaveAtMs = now
                target = pendingSave
                pendingSave = None
                expired = true
            }
        }
        match (target) {
            case Some(s) => writeSettings(s)
            case None => ()
        }
        // 窗口到期即退出：快照被 flushPendingSave 抢先取走（target=None）时也直接返回，
        // 否则线程带着陈旧 waitMs 永远空转（再无 pendingSave 可写）。
        if (expired) {
            return
        }
    }
}

// 退出前把窗口内未 flush 的快照补写（否则最后一次变更可能丢）。
// 包内可见：测试用它强制落盘，绕开防抖窗口。
func flushPendingSave(): Unit {
    var target: ?AppSettings = None
    synchronized(saveStateMutex) {
        target = pendingSave
        pendingSave = None
    }
    match (target) {
        case Some(s) => writeSettings(s)
        case None => ()
    }
}

// 实际落盘。trailing flush 在后台线程执行：此时读到的是 AppSettings 的合并最新值——
// 正是防抖想要的语义；字段级撕裂（两个代次混读）对设置项无害。写路径本身串行化。
private func writeSettings(s: AppSettings): Unit {
    synchronized(saveWriteMutex) {
        writeSettingsLocked(s)
    }
}

private func writeSettingsLocked(s: AppSettings): Unit {
    let kv = store()
    s.syncActiveProfile()
    // 整表序列化为单个 JSON 文档，一次 put 原子落盘（RocksDB WAL 保证持久，替代原 kv.sync()）。
    let _ = kv.putResult("settings", settingsToJson(s))
}

private func settingsToJson(s: AppSettings): String {
    let out = ByteBuffer()
    let w = JsonWriter(out)
    w.startObject()
    w.writeName("schema_version").writeValue(2)
    w.writeName("appearance")
    w.startObject()
    w.writeName("theme").writeValue(s.theme)
    w.writeName("font_path").writeValue(s.fontPath)
    w.writeName("language").writeValue(normalizeLanguagePreference(s.languagePreference))
    w.endObject()
    w.writeName("reader")
    w.startObject()
    w.writeName("mode").writeValue(s.readerMode)
    w.writeName("double_page").writeValue(s.readerDoublePage)
    w.writeName("split_cover").writeValue(s.readerSplitCover)
    w.writeName("long_page").writeValue(s.readerLongPage)
    w.writeName("tap_turn_page").writeValue(s.readerTapTurnPage)
    w.writeName("double_tap_zoom").writeValue(s.readerDoubleTapZoom)
    w.writeName("auto_hide").writeValue(s.readerAutoHide)
    w.writeName("seamless_next").writeValue(s.readerSeamlessNext)
    w.writeName("show_info").writeValue(s.readerShowInfo)
    w.writeName("auto_play").writeValue(s.readerAutoPlay)
    w.writeName("auto_play_interval").writeValue(s.readerAutoPlayInterval)
    w.writeName("html_font_size").writeValue(clampHtmlFontSize(s.readerHtmlFontSize))
    w.writeName("html_margin").writeValue(clampHtmlMargin(s.readerHtmlMargin))
    w.endObject()
    w.writeName("network")
    w.startObject()
    w.writeName("probe_connect_timeout_sec").writeValue(s.probeConnectTimeoutSec)
    w.endObject()
    w.writeName("servers")
    w.startObject()
    w.writeName("active_id").writeValue(s.activeServerId)
    w.writeName("list")
    w.startArray()
    for (p in s.servers) {
        w.startObject()
        w.writeName("id").writeValue(p.id)
        w.writeName("name").writeValue(p.name)
        w.writeName("base_url").writeValue(p.baseUrl)
        w.writeName("token").writeValue(p.token)
        w.writeName("username").writeValue(p.username)
        w.writeName("last_used_at").writeValue(p.lastUsedAt)
        w.endObject()
    }
    w.endArray()
    w.endObject()
    w.endObject()
    w.flush()
    String.fromUtf8(readToEnd(out))
}

public func closeSettingsStore(): Unit {
    flushPendingSave()
    match (settingsStore) {
        case Some(db) => db.close()
        case None => ()
    }
    settingsStore = None
}

// 清空客户端设置并保留已打开的 store，供“恢复默认设置”和测试隔离复用。
public func clearSettings(): Unit {
    let _ = store().deleteResult("settings")
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

// 语言偏好值 ↔ 语言页 Dropdown 索引（0=跟随系统 1=简体中文 2=English）。
// 非法设置值和越界索引都回落到跟随系统，与设置加载时的归一化规则一致。
public func languagePreferenceToIndex(preference: String): Int64 {
    let normalized = normalizeLanguagePreference(preference)
    if (normalized == LANGUAGE_ZH) {
        1
    } else if (normalized == LANGUAGE_EN) {
        2
    } else {
        0
    }
}

public func indexToLanguagePreference(index: Int64): String {
    match (index) {
        case 1 => LANGUAGE_ZH
        case 2 => LANGUAGE_EN
        case _ => LANGUAGE_SYSTEM
    }
}
