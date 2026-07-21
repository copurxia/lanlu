package lanlu_client_next.app

import lanlu_client_next.net.JsonCodec
import std.collection.ArrayList
import std.env.getVariable
import std.fs.{exists, rename, File, Directory, Path}
import std.io.{ByteBuffer, readToEnd}
import std.overflow.*
import std.time.DateTime
import stdx.encoding.json.stream.*

// 一台已保存的 lanlu 服务器：列表管理 + 按服务器各存会话（token/username）。
public class ServerProfile <: JsonSerializable & JsonDeserializable<ServerProfile> {
    public var id: String = ""
    public var name: String = ""
    public var baseUrl: String = ""
    public var token: String = ""
    public var username: String = ""
    public var lastUsedAt: String = ""

    public func toJson(w: JsonWriter): Unit {
        w.startObject()
        w.writeName("id").writeValue(id)
        w.writeName("name").writeValue(name)
        w.writeName("baseUrl").writeValue(baseUrl)
        w.writeName("token").writeValue(token)
        w.writeName("username").writeValue(username)
        w.writeName("lastUsedAt").writeValue(lastUsedAt)
        w.endObject()
    }

    public static func fromJson(r: JsonReader): ServerProfile {
        let res = ServerProfile()
        while (let Some(tok) <- r.peek()) {
            match (tok) {
                case BeginObject =>
                    r.startObject()
                    while (r.peek() != EndObject) {
                        match (r.readName()) {
                            case "id" => res.id = r.readValue<String>()
                            case "name" => res.name = r.readValue<String>()
                            case "baseUrl" => res.baseUrl = r.readValue<String>()
                            case "token" => res.token = r.readValue<String>()
                            case "username" => res.username = r.readValue<String>()
                            case "lastUsedAt" => res.lastUsedAt = r.readValue<String>()
                            case _ => r.skip()
                        }
                    }
                    r.endObject()
                    break
                case _ => throw Exception("invalid server profile json")
            }
        }
        return res
    }
}

// 服务器地址归一化：trim + 去尾部所有斜杠（对齐 client storage/servers.ts）。
public func normalizeServerUrl(input: String): String {
    var b = input.trimAscii()
    while (b.endsWith("/")) { b = b[0..b.size - 1] }
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

public class AppSettings <: JsonSerializable & JsonDeserializable<AppSettings> {
    public var serverUrl: String = ""
    public var token: String = ""
    public var username: String = ""
    // 界面主题："dark"（默认）| "light"；旧 config.json 无此字段时保持默认，向后兼容。
    public var theme: String = "dark"
    // 阅读器设置一组 reader_* 键（默认值对齐 frontend use-reader-settings；
    // 旧 config.json 无这些字段时保持默认，向后兼容）。ReaderModel 读初值并写回。
    public var readerMode: String = "single-ltr"   // single-ltr | single-rtl | single-ttb | webtoon
    public var readerDoublePage: Bool = false
    public var readerSplitCover: Bool = false
    public var readerLongPage: Bool = true
    public var readerTapTurnPage: Bool = false
    public var readerDoubleTapZoom: Bool = false
    public var readerAutoHide: Bool = false
    public var readerSeamlessNext: Bool = false     // 无缝续读：仅设置占位（YAGNI，不实现拼接）
    public var readerShowInfo: Bool = false         // 媒体信息浮层开关（文件名/时长/位置等）
    public var readerAutoPlay: Bool = false         // 自动播放（按间隔自动翻页，到底自动停）
    public var readerAutoPlayInterval: Int64 = 3    // 自动播放间隔（秒，1-10）
    // 多服务器列表与当前选中；旧三字段（serverUrl/token/username）仅作迁移与向后兼容同步。
    public var servers = ArrayList<ServerProfile>()
    public var activeServerId: String = ""

    public func toJson(w: JsonWriter): Unit {
        w.startObject()
        w.writeName("serverUrl").writeValue(serverUrl)
        w.writeName("token").writeValue(token)
        w.writeName("username").writeValue(username)
        w.writeName("theme").writeValue(theme)
        w.writeName("readerMode").writeValue(readerMode)
        w.writeName("readerDoublePage").writeValue(readerDoublePage)
        w.writeName("readerSplitCover").writeValue(readerSplitCover)
        w.writeName("readerLongPage").writeValue(readerLongPage)
        w.writeName("readerTapTurnPage").writeValue(readerTapTurnPage)
        w.writeName("readerDoubleTapZoom").writeValue(readerDoubleTapZoom)
        w.writeName("readerAutoHide").writeValue(readerAutoHide)
        w.writeName("readerSeamlessNext").writeValue(readerSeamlessNext)
        w.writeName("readerShowInfo").writeValue(readerShowInfo)
        w.writeName("readerAutoPlay").writeValue(readerAutoPlay)
        w.writeName("readerAutoPlayInterval").writeValue(readerAutoPlayInterval)
        w.writeName("servers")
        w.startArray()
        for (p in servers) { w.writeValue(p) }
        w.endArray()
        w.writeName("activeServerId").writeValue(activeServerId)
        w.endObject()
    }

    public static func fromJson(r: JsonReader): AppSettings {
        let res = AppSettings()
        while (let Some(tok) <- r.peek()) {
            match (tok) {
                case BeginObject =>
                    r.startObject()
                    while (r.peek() != EndObject) {
                        match (r.readName()) {
                            case "serverUrl" => res.serverUrl = r.readValue<String>()
                            case "token" => res.token = r.readValue<String>()
                            case "username" => res.username = r.readValue<String>()
                            case "theme" => res.theme = r.readValue<String>()
                            case "readerMode" => res.readerMode = r.readValue<String>()
                            case "readerDoublePage" => res.readerDoublePage = r.readValue<Bool>()
                            case "readerSplitCover" => res.readerSplitCover = r.readValue<Bool>()
                            case "readerLongPage" => res.readerLongPage = r.readValue<Bool>()
                            case "readerTapTurnPage" => res.readerTapTurnPage = r.readValue<Bool>()
                            case "readerDoubleTapZoom" => res.readerDoubleTapZoom = r.readValue<Bool>()
                            case "readerAutoHide" => res.readerAutoHide = r.readValue<Bool>()
                            case "readerSeamlessNext" => res.readerSeamlessNext = r.readValue<Bool>()
                            case "readerShowInfo" => res.readerShowInfo = r.readValue<Bool>()
                            case "readerAutoPlay" => res.readerAutoPlay = r.readValue<Bool>()
                            case "readerAutoPlayInterval" => res.readerAutoPlayInterval = r.readValue<Int64>()
                            case "servers" =>
                                r.startArray()
                                while (r.peek() != EndArray) {
                                    res.servers.add(ServerProfile.fromJson(r))
                                }
                                r.endArray()
                            case "activeServerId" => res.activeServerId = r.readValue<String>()
                            case _ => r.skip()
                        }
                    }
                    r.endObject()
                    break
                case _ => throw Exception("invalid settings json")
            }
        }
        // 旧版单服务器配置迁移：servers 为空且旧 serverUrl 非空 → 迁移为一条 profile 并置 active。
        if (res.servers.size == 0 && res.serverUrl.size > 0) {
            let p = ServerProfile()
            p.id = "srv-${fnv1a64Hex(res.serverUrl)[0..8]}"
            p.baseUrl = normalizeServerUrl(res.serverUrl)
            p.token = res.token
            p.username = res.username
            res.servers.add(p)
            res.activeServerId = p.id
        }
        return res
    }

    public func profileById(id: String): ?ServerProfile {
        for (p in servers) {
            if (p.id == id) { return p }
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
        if (activeServerId == id) { activeServerId = "" }
    }

    // 保存前把 active profile 同步进旧三字段：未升级的旧视图仍读它们。
    // 无 active profile 时必须清空旧字段，否则删除最后一台服务器后残留的 serverUrl/token
    // 会在下次 loadSettingsFrom 的迁移分支把被删服务器带 token 重建并自动恢复会话。
    public func syncLegacy(): Unit {
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

public func defaultSettingsPath(): String {
    let home = getVariable("HOME") ?? "."
    "${home}/.config/lanlu-client-next/config.json"
}

public func loadSettingsFrom(path: String): AppSettings {
    if (!exists(Path(path))) { return AppSettings() }
    try {
        JsonCodec.decode<AppSettings>(String.fromUtf8(File.readFrom(Path(path))))
    } catch (_: Exception) {
        try { rename(Path(path), to: Path("${path}.bak"), overwrite: true) } catch (_: Exception) {}
        AppSettings()
    }
}

public func saveSettingsTo(path: String, s: AppSettings): Unit {
    s.syncLegacy()
    let p = Path(path)
    // cjc 1.1.3 的 Directory.create 对空路径和已存在目录都会抛异常，先做两道判断。
    let parent = p.parent
    if (!parent.toString().isEmpty() && !exists(parent)) {
        Directory.create(parent, recursive: true)
    }
    let out = ByteBuffer()
    let w = JsonWriter(out)
    w.writeValue(s)
    w.flush()
    File.writeTo(p, readToEnd(out))
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
    if (mode == "light") { 1 } else { 0 }
}

public func indexToTheme(i: Int64): String {
    if (i == 1) { "light" } else { "dark" }
}
