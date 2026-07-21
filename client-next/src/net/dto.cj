package lanlu_client_next.net

import std.collection.ArrayList
import std.io.ByteBuffer
import stdx.encoding.json.stream.*

public class Envelope {
    public var code: Int64 = 0
    public var message: String = ""
    public var dataRaw: String = ""
}

public func parseEnvelope(body: String): Envelope {
    let env = Envelope()
    var buf = ByteBuffer()
    unsafe { buf.write(body.rawData()) }
    let r = JsonReader(buf)
    while (let Some(tok) <- r.peek()) {
        match (tok) {
            case BeginObject =>
                r.startObject()
                while (r.peek() != EndObject) {
                    let n = r.readName()
                    match (n) {
                        case "code" => env.code = decodeRaw<Int64>(r.readValueBytes(), 0)
                        case "message" => env.message = decodeRaw<String>(r.readValueBytes(), "")
                        case "data" => env.dataRaw = rawText(r.readValueBytes())
                        case _ => r.skip()
                    }
                }
                r.endObject()
                break
            case _ => throw Exception("invalid json envelope")
        }
    }
    return env
}

// dataRaw 本身可能是对象/数组，不能按 String 解码 —— 用原始字节重新构造 reader 的辅助。
private func readerOf(s: String): JsonReader {
    var buf = ByteBuffer()
    unsafe { buf.write(s.rawData()) }
    JsonReader(buf)
}

public func parseStringArray(raw: String): ArrayList<String> {
    let list = ArrayList<String>()
    if (raw.size == 0) { return list }
    let r = readerOf(raw)
    while (let Some(tok) <- r.peek()) {
        match (tok) {
            case BeginArray =>
                r.startArray()
                while (r.peek() != EndArray) {
                    list.add(decodeRaw<String>(r.readValueBytes(), ""))
                }
                r.endArray()
                break
            case _ => break
        }
    }
    return list
}

// 部分端点（metadata、info 等）返回裸 JSON 对象，无 {code,message,data} 包络。
// 顶层存在 "data" 键时返回其原始 JSON 文本；否则原样返回整个 body（含空串）。
public func unwrapDataRaw(body: String): String {
    var raw = ""
    let r = readerOf(body)
    try {
        while (let Some(tok) <- r.peek()) {
            match (tok) {
                case BeginObject =>
                    r.startObject()
                    while (r.peek() != EndObject) {
                        match (r.readName()) {
                            case "data" => raw = rawText(r.readValueBytes())
                            case _ => r.skip()
                        }
                    }
                    r.endObject()
                    break
                case _ => break
            }
        }
    } catch (_: Exception) { return body }
    if (raw.size == 0) { return body }
    raw
}

public class ServerInfo <: JsonDeserializable<ServerInfo> {
    public var name: String = ""
    public var version: String = ""
    public var versionName: String = ""
    public var motd: String = ""
    public var totalArchives: Int64 = 0

    public static func fromJson(r: JsonReader): ServerInfo {
        let res = ServerInfo()
        while (let Some(tok) <- r.peek()) {
            match (tok) {
                case BeginObject =>
                    r.startObject()
                    while (r.peek() != EndObject) {
                        let n = r.readName()
                        match (n) {
                            case "name" => res.name = decodeRaw<String>(r.readValueBytes(), "")
                            case "version" => res.version = decodeRaw<String>(r.readValueBytes(), "")
                            case "version_name" => res.versionName = decodeRaw<String>(r.readValueBytes(), "")
                            case "motd" => res.motd = decodeRaw<String>(r.readValueBytes(), "")
                            case "total_archives" => res.totalArchives = decodeRaw<Int64>(r.readValueBytes(), 0)
                            case _ => r.skip()
                        }
                    }
                    r.endObject()
                    break
                case _ => throw Exception("invalid json")
            }
        }
        return res
    }
}

public class LoginData <: JsonDeserializable<LoginData> {
    public var token: String = ""
    public var username: String = ""
    public var isAdmin: Bool = false
    public var userId: Int64 = 0

    public static func fromJson(r: JsonReader): LoginData {
        let res = LoginData()
        while (let Some(tok) <- r.peek()) {
            match (tok) {
                case BeginObject =>
                    r.startObject()
                    while (r.peek() != EndObject) {
                        match (r.readName()) {
                            case "user" => res.readUser(r)
                            case "token" => res.readToken(r)
                            case _ => r.skip()
                        }
                    }
                    r.endObject()
                    break
                case _ => throw Exception("invalid json")
            }
        }
        return res
    }

    private func readUser(r: JsonReader): Unit {
        r.startObject()
        while (r.peek() != EndObject) {
            match (r.readName()) {
                case "id" => userId = decodeRaw<Int64>(r.readValueBytes(), 0)
                case "username" => username = decodeRaw<String>(r.readValueBytes(), "")
                case "isAdmin" => isAdmin = decodeRaw<Bool>(r.readValueBytes(), false)
                case _ => r.skip()
            }
        }
        r.endObject()
    }

    private func readToken(r: JsonReader): Unit {
        r.startObject()
        while (r.peek() != EndObject) {
            match (r.readName()) {
                case "token" => token = decodeRaw<String>(r.readValueBytes(), "")
                case _ => r.skip()
            }
        }
        r.endObject()
    }
}

// 登录 202 响应的 data：{"requiresTotp":true,"challengeId":"...","methods":[...]}，只取 challengeId。
public class LoginPendingTotp <: JsonDeserializable<LoginPendingTotp> {
    public var challengeId: String = ""

    public static func fromJson(r: JsonReader): LoginPendingTotp {
        let res = LoginPendingTotp()
        while (let Some(tok) <- r.peek()) {
            match (tok) {
                case BeginObject =>
                    r.startObject()
                    while (r.peek() != EndObject) {
                        match (r.readName()) {
                            case "challengeId" => res.challengeId = r.readValue<String>()
                            case _ => r.skip()
                        }
                    }
                    r.endObject()
                    break
                case _ => throw Exception("invalid pending totp json")
            }
        }
        return res
    }
}

public class SearchItem <: JsonDeserializable<SearchItem> {
    public var arcid: String = ""
    public var title: String = ""
    public var description: String = ""
    public var tagsCsv: String = ""
    public var archivetype: String = ""
    public var filename: String = ""
    public var coverAssetId: Int64 = 0
    public var pagecount: Int64 = 0
    public var progress: Int64 = 0
    public var size: Int64 = 0
    public var lastreadtime: Int64 = 0
    public var isnew: Bool = false
    public var isfavorite: Bool = false
    // 合集聚合（groupby_tanks=true）时合辑条目：type="tankoubon"、arcid 为空、
    // tankoubonId/archiveCount 有效（服务端 search_controller 聚合响应结构）。
    public var itemType: String = ""
    public var tankoubonId: String = ""
    public var archiveCount: Int64 = 0

    public static func fromJson(r: JsonReader): SearchItem {
        let res = SearchItem()
        while (let Some(tok) <- r.peek()) {
            match (tok) {
                case BeginObject =>
                    r.startObject()
                    while (r.peek() != EndObject) {
                        let n = r.readName()
                        match (n) {
                            case "arcid" => res.arcid = decodeRaw<String>(r.readValueBytes(), "")
                            case "type" => res.itemType = decodeRaw<String>(r.readValueBytes(), "")
                            case "tankoubon_id" => res.tankoubonId = decodeRaw<String>(r.readValueBytes(), "")
                            case "archive_count" => res.archiveCount = decodeRaw<Int64>(r.readValueBytes(), 0)
                            case "title" => res.title = decodeRaw<String>(r.readValueBytes(), "")
                            case "description" => res.description = decodeRaw<String>(r.readValueBytes(), "")
                            case "tags" => res.tagsCsv = decodeRaw<String>(r.readValueBytes(), "")
                            case "archivetype" => res.archivetype = decodeRaw<String>(r.readValueBytes(), "")
                            case "filename" => res.filename = decodeRaw<String>(r.readValueBytes(), "")
                            case "pagecount" => res.pagecount = decodeRaw<Int64>(r.readValueBytes(), 0)
                            case "progress" => res.progress = decodeRaw<Int64>(r.readValueBytes(), 0)
                            case "size" => res.size = decodeRaw<Int64>(r.readValueBytes(), 0)
                            case "lastreadtime" => res.lastreadtime = decodeRaw<Int64>(r.readValueBytes(), 0)
                            case "isnew" => res.isnew = decodeRaw<Bool>(r.readValueBytes(), false)
                            case "isfavorite" => res.isfavorite = decodeRaw<Bool>(r.readValueBytes(), false)
                            case "assets" => res.coverAssetId = parseCoverFromAssetsObject(r.readValueBytes())
                            case _ => r.skip()
                        }
                    }
                    r.endObject()
                    break
                case _ => throw Exception("invalid json")
            }
        }
        return res
    }
}

// search 条目的 assets 是对象：{"cover": 42, ...}
private func parseCoverFromAssetsObject(b: Array<UInt8>): Int64 {
    var id: Int64 = 0
    let r = readerOf(rawText(b))
    try {
        r.startObject()
        while (r.peek() != EndObject) {
            match (r.readName()) {
                case "cover" => id = decodeRaw<Int64>(r.readValueBytes(), 0)
                case _ => r.skip()
            }
        }
        r.endObject()
    } catch (_: Exception) {}
    return id
}

public class SearchPage {
    public var items: ArrayList<SearchItem> = ArrayList<SearchItem>()
    public var page: Int64 = 1
    public var pageSize: Int64 = 0
    public var recordsFiltered: Int64 = 0
    public var recordsTotal: Int64 = 0
}

public func parseSearchPage(body: String): SearchPage {
    let res = SearchPage()
    let r = readerOf(body)
    while (let Some(tok) <- r.peek()) {
        match (tok) {
            case BeginObject =>
                r.startObject()
                while (r.peek() != EndObject) {
                    match (r.readName()) {
                        case "data" =>
                            r.startArray()
                            while (r.peek() != EndArray) {
                                res.items.add(SearchItem.fromJson(r))
                            }
                            r.endArray()
                        case "page" => res.page = decodeRaw<Int64>(r.readValueBytes(), 1)
                        case "pageSize" => res.pageSize = decodeRaw<Int64>(r.readValueBytes(), 0)
                        case "recordsFiltered" => res.recordsFiltered = decodeRaw<Int64>(r.readValueBytes(), 0)
                        case "recordsTotal" => res.recordsTotal = decodeRaw<Int64>(r.readValueBytes(), 0)
                        case _ => r.skip()
                    }
                }
                r.endObject()
                break
            case _ => throw Exception("invalid json")
        }
    }
    return res
}

public class CategoryItem {
    public var id: Int64 = 0
    public var catid: String = ""
    public var name: String = ""
    public var archiveCount: Int64 = 0
}

public func parseCategoryList(body: String): ArrayList<CategoryItem> {
    let list = ArrayList<CategoryItem>()
    let env = parseEnvelope(body)
    if (env.dataRaw.size == 0) { return list }
    // 容忍两种形态：data 直接是数组；或 data 是对象、内部再嵌套一层 "data" 键。
    var raw = env.dataRaw
    let probe = readerOf(raw)
    if (let Some(BeginObject) <- probe.peek()) {
        raw = extractNestedDataRaw(raw)
    }
    if (raw.size == 0) { return list }
    let r = readerOf(raw)
    while (let Some(tok) <- r.peek()) {
        match (tok) {
            case BeginArray =>
                r.startArray()
                while (r.peek() != EndArray) {
                    r.startObject()
                    let item = CategoryItem()
                    while (r.peek() != EndObject) {
                        match (r.readName()) {
                            case "id" => item.id = decodeRaw<Int64>(r.readValueBytes(), 0)
                            case "catid" => item.catid = decodeRaw<String>(r.readValueBytes(), "")
                            case "name" => item.name = decodeRaw<String>(r.readValueBytes(), "")
                            case "archive_count" => item.archiveCount = decodeRaw<Int64>(r.readValueBytes(), 0)
                            case _ => r.skip()
                        }
                    }
                    r.endObject()
                    list.add(item)
                }
                r.endArray()
                break
            case _ => break
        }
    }
    return list
}

// data 是对象时，取其内部 "data" 键的原始 JSON 文本（应为分类数组）。
private func extractNestedDataRaw(dataRaw: String): String {
    var raw = ""
    let r = readerOf(dataRaw)
    try {
        r.startObject()
        while (r.peek() != EndObject) {
            match (r.readName()) {
                case "data" => raw = rawText(r.readValueBytes())
                case _ => r.skip()
            }
        }
        r.endObject()
    } catch (_: Exception) {}
    return raw
}

public class ArchiveMeta <: JsonDeserializable<ArchiveMeta> {
    public var arcid: String = ""
    public var title: String = ""
    public var description: String = ""
    public var archivetype: String = ""
    public var filename: String = ""
    public var relativePath: String = ""
    public var thumbnailHash: String = ""
    public var tags: ArrayList<String> = ArrayList<String>()
    public var capabilities: ArrayList<String> = ArrayList<String>()
    public var coverAssetId: Int64 = 0
    public var pagecount: Int64 = 0
    public var progress: Int64 = 0
    public var size: Int64 = 0
    public var isnew: Bool = false
    public var isfavorite: Bool = false
    // 时间戳字段（Unix 秒，0 表示未知/未设置）
    public var release_at: Int64 = 0
    public var created_at: Int64 = 0
    public var updated_at: Int64 = 0
    public var lastreadtime: Int64 = 0

    public static func fromJson(r: JsonReader): ArchiveMeta {
        let res = ArchiveMeta()
        while (let Some(tok) <- r.peek()) {
            match (tok) {
                case BeginObject =>
                    r.startObject()
                    while (r.peek() != EndObject) {
                        let n = r.readName()
                        match (n) {
                            case "arcid" => res.arcid = decodeRaw<String>(r.readValueBytes(), "")
                            case "title" => res.title = decodeRaw<String>(r.readValueBytes(), "")
                            case "description" => res.description = decodeRaw<String>(r.readValueBytes(), "")
                            case "archivetype" => res.archivetype = decodeRaw<String>(r.readValueBytes(), "")
                            case "filename" => res.filename = decodeRaw<String>(r.readValueBytes(), "")
                            case "relative_path" => res.relativePath = decodeRaw<String>(r.readValueBytes(), "")
                            case "thumbnail_hash" => res.thumbnailHash = decodeRaw<String>(r.readValueBytes(), "")
                            case "tags" => res.tags = parseStringArray(rawText(r.readValueBytes()))
                            case "capabilities" => res.capabilities = parseStringArray(rawText(r.readValueBytes()))
                            case "pagecount" => res.pagecount = decodeRaw<Int64>(r.readValueBytes(), 0)
                            case "progress" => res.progress = decodeRaw<Int64>(r.readValueBytes(), 0)
                            case "file_size" => res.size = decodeRaw<Int64>(r.readValueBytes(), 0)
                            case "size" => res.size = decodeRaw<Int64>(r.readValueBytes(), 0)
                            case "isnew" => res.isnew = decodeRaw<Bool>(r.readValueBytes(), false)
                            case "isfavorite" => res.isfavorite = decodeRaw<Bool>(r.readValueBytes(), false)
                            case "assets" => res.coverAssetId = parseCoverFromAssetsArray(rawText(r.readValueBytes()))
                            case "release_at" => res.release_at = decodeRaw<Int64>(r.readValueBytes(), 0)
                            case "created_at" => res.created_at = decodeRaw<Int64>(r.readValueBytes(), 0)
                            case "updated_at" => res.updated_at = decodeRaw<Int64>(r.readValueBytes(), 0)
                            case "lastreadtime" => res.lastreadtime = decodeRaw<Int64>(r.readValueBytes(), 0)
                            case _ => r.skip()
                        }
                    }
                    r.endObject()
                    break
                case _ => throw Exception("invalid json")
            }
        }
        return res
    }
}

// metadata 的 assets 是 [{key,value}] 数组
private func parseCoverFromAssetsArray(raw: String): Int64 {
    var id: Int64 = 0
    if (raw.size == 0) { return id }
    let r = readerOf(raw)
    try {
        r.startArray()
        while (r.peek() != EndArray) {
            r.startObject()
            var key = ""
            var value: Int64 = 0
            while (r.peek() != EndObject) {
                match (r.readName()) {
                    case "key" => key = decodeRaw<String>(r.readValueBytes(), "")
                    case "value" => value = decodeRaw<Int64>(r.readValueBytes(), 0)
                    case _ => r.skip()
                }
            }
            r.endObject()
            if (key == "cover") { id = value }
        }
        r.endArray()
    } catch (_: Exception) {}
    return id
}

public func parseArchiveMeta(body: String): ArchiveMeta {
    // 服务端 metadata 端点返回裸对象（无包络），先经 unwrapDataRaw 兼容两种形态。
    let raw = unwrapDataRaw(body)
    if (raw.size == 0) { throw Exception("empty metadata") }
    JsonCodec.decode<ArchiveMeta>(raw)
}

// 复合在线源 arcid（"source:<ns>:<id>"）→ 插件命名空间；本地档案（非复合 id）返回空串。
public func sourceNamespace(arcid: String): String {
    if (!arcid.startsWith("source:")) { return "" }
    let rest = arcid[7..arcid.size]
    match (rest.indexOf(":")) {
        case Some(i) => rest[0..i]
        case None => ""
    }
}

// Unix 时间戳（秒）→ "YYYY-MM-DD"；0 表示未知，返回 "未知"。
public func formatTimestamp(ts: Int64): String {
    if (ts <= 0) { return "未知" }
    // 从 1970-01-01 起逐 year 减天数，再逐 month 减天数。
    var remaining = ts / 86400
    var year: Int64 = 1970
    while (true) {
        let yd = if (isLeapYear(year)) { 366 } else { 365 }
        if (remaining < yd) { break }
        remaining -= yd
        year++
    }
    let leap = isLeapYear(year)
    let monthDays = if (leap) { [31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31] }
                    else { [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31] }
    var month: Int64 = 1
    for (md in monthDays) {
        if (remaining < md) { break }
        remaining -= md
        month++
    }
    let day = remaining + 1
    let mStr = if (month < 10) { "0${month}" } else { "${month}" }
    let dStr = if (day < 10) { "0${day}" } else { "${day}" }
    "${year}-${mStr}-${dStr}"
}

private func isLeapYear(y: Int64): Bool {
    (y % 4 == 0 && y % 100 != 0) || (y % 400 == 0)
}

public class PageInfo {
    public var id: String = ""
    public var pageType: String = ""
    public var title: String = ""
}

public func parsePages(body: String): ArrayList<PageInfo> {
    // 容忍两种形态：顶层 {"pages":[...]}，或 envelope 的 data.pages。
    var raw = ""
    let top = readerOf(body)
    while (let Some(tok) <- top.peek()) {
        match (tok) {
            case BeginObject =>
                top.startObject()
                while (top.peek() != EndObject) {
                    match (top.readName()) {
                        case "pages" => raw = rawText(top.readValueBytes())
                        case "data" =>
                            let dataRaw = rawText(top.readValueBytes())
                            if (raw.size == 0) { raw = extractPagesRaw(dataRaw) }
                        case _ => top.skip()
                    }
                }
                top.endObject()
                break
            case _ => break
        }
    }
    return parsePageArray(raw)
}

private func extractPagesRaw(dataRaw: String): String {
    var raw = ""
    if (dataRaw.size == 0) { return raw }
    let r = readerOf(dataRaw)
    try {
        r.startObject()
        while (r.peek() != EndObject) {
            match (r.readName()) {
                case "pages" => raw = rawText(r.readValueBytes())
                case _ => r.skip()
            }
        }
        r.endObject()
    } catch (_: Exception) {}
    return raw
}

private func parsePageArray(raw: String): ArrayList<PageInfo> {
    let list = ArrayList<PageInfo>()
    if (raw.size == 0) { return list }
    let r = readerOf(raw)
    try {
        r.startArray()
        while (r.peek() != EndArray) {
            r.startObject()
            let p = PageInfo()
            while (r.peek() != EndObject) {
                match (r.readName()) {
                    case "id" => p.id = decodeRaw<String>(r.readValueBytes(), "")
                    case "type" => p.pageType = decodeRaw<String>(r.readValueBytes(), "")
                    case "title" => p.title = decodeRaw<String>(r.readValueBytes(), "")
                    case _ => r.skip()
                }
            }
            r.endObject()
            list.add(p)
        }
        r.endArray()
    } catch (_: Exception) {}
    return list
}

// ===== 合集（tankoubon）=====
// 端点（src/routes/api/tankoubons.cj、archives.cj 核实）：
//   GET /api/tankoubons                 → 裸 {"filtered":N,"result":[...],"total":N}
//   GET /api/archives/:id/tankoubons    → 同上形态
//   GET /api/tankoubons/:id/metadata    → 单个裸对象
// 均无 {code,message,data} 包络；result 通常是数组，frontend normalizeResult 兼容单对象。
// 列表形态 children 为字符串数组；metadata 形态 children 为 member 对象（entity_id）。
public class TankoubonInfo <: JsonDeserializable<TankoubonInfo> {
    public var id: String = ""
    public var name: String = ""
    public var description: String = ""
    public var tags: ArrayList<String> = ArrayList<String>()
    public var archiveCount: Int64 = 0
    public var totalPages: Int64 = 0
    // 服务端 progress 为各成员档案平均进度（页码，AVG(uas.progress)）。
    public var progress: Float32 = 0.0
    // 封面档案 id = 首个成员档案（children[0]），对齐 frontend TankoubonCard firstArchiveId。
    public var coverArcid: String = ""
    // 封面资产 id：列表形态 assets 为 {"cover":N} 对象，metadata 形态为 [{key,value}] 数组。
    public var coverAssetId: Int64 = 0
    public var createdAt: String = ""
    public var updatedAt: String = ""

    public static func fromJson(r: JsonReader): TankoubonInfo {
        let res = TankoubonInfo()
        while (let Some(tok) <- r.peek()) {
            match (tok) {
                case BeginObject =>
                    r.startObject()
                    while (r.peek() != EndObject) {
                        let n = r.readName()
                        match (n) {
                            case "tankoubon_id" => res.id = decodeRaw<String>(r.readValueBytes(), "")
                            case "title" => res.name = decodeRaw<String>(r.readValueBytes(), "")
                            case "description" => res.description = decodeRaw<String>(r.readValueBytes(), "")
                            case "tags" => res.tags = parseTankTags(r.readValueBytes())
                            case "archive_count" => res.archiveCount = decodeRaw<Int64>(r.readValueBytes(), 0)
                            case "pagecount" => res.totalPages = decodeRaw<Int64>(r.readValueBytes(), 0)
                            case "progress" => res.progress = Float32(decodeRaw<Float64>(r.readValueBytes(), 0.0))
                            case "children" => res.coverArcid = firstChildArcid(r.readValueBytes())
                            case "assets" => res.coverAssetId = parseTankCoverAssets(r.readValueBytes())
                            case "created_at" => res.createdAt = decodeRaw<String>(r.readValueBytes(), "")
                            case "updated_at" => res.updatedAt = decodeRaw<String>(r.readValueBytes(), "")
                            case _ => r.skip()
                        }
                    }
                    r.endObject()
                    break
                case _ => throw Exception("invalid json")
            }
        }
        return res
    }
}

// 合集 tags 两形态：metadata 端点是字符串数组，列表端点是 CSV 字符串。
private func parseTankTags(b: Array<UInt8>): ArrayList<String> {
    let list = ArrayList<String>()
    let raw = rawText(b)
    if (raw.size == 0) { return list }
    let probe = readerOf(raw)
    match (probe.peek()) {
        case Some(BeginArray) => return parseStringArray(raw)
        case _ => ()
    }
    let csv = decodeRaw<String>(b, "")
    for (t in csv.split(",")) {
        let trimmed = t.trimAscii()
        if (trimmed.size > 0) { list.add(trimmed) }
    }
    list
}

// 合集 assets 两形态：对象 {"cover":N}（列表/recommendations）或 [{key,value}] 数组（metadata）。
private func parseTankCoverAssets(b: Array<UInt8>): Int64 {
    let raw = rawText(b)
    if (raw.size == 0) { return 0 }
    let probe = readerOf(raw)
    match (probe.peek()) {
        case Some(BeginArray) => return parseCoverFromAssetsArray(raw)
        case _ => ()
    }
    parseCoverFromAssetsObject(b)
}

// children 首元素：列表形态是字符串，metadata 形态是 {"entity_id":...} 对象。
private func firstChildArcid(b: Array<UInt8>): String {
    var id = ""
    let r = readerOf(rawText(b))
    try {
        r.startArray()
        match (r.peek()) {
            case Some(BeginObject) =>
                r.startObject()
                while (r.peek() != EndObject) {
                    match (r.readName()) {
                        case "entity_id" => id = decodeRaw<String>(r.readValueBytes(), "")
                        case _ => r.skip()
                    }
                }
                r.endObject()
            case Some(EndArray) => ()
            case _ => id = decodeRaw<String>(r.readValueBytes(), "")
        }
    } catch (_: Exception) {}
    return id
}

// 列表响应：{"filtered":N,"result":[...] 或 {...},"total":N}；unwrapDataRaw 兜底包络形态。
public func parseTankoubonList(body: String): ArrayList<TankoubonInfo> {
    let list = ArrayList<TankoubonInfo>()
    let raw = unwrapDataRaw(body)
    if (raw.size == 0) { return list }
    let r = readerOf(raw)
    while (let Some(tok) <- r.peek()) {
        match (tok) {
            case BeginObject =>
                r.startObject()
                while (r.peek() != EndObject) {
                    match (r.readName()) {
                        case "result" =>
                            match (r.peek()) {
                                case Some(BeginArray) =>
                                    r.startArray()
                                    while (r.peek() != EndArray) {
                                        list.add(TankoubonInfo.fromJson(r))
                                    }
                                    r.endArray()
                                case Some(BeginObject) => list.add(TankoubonInfo.fromJson(r))
                                case _ => r.skip()
                            }
                        case _ => r.skip()
                    }
                }
                r.endObject()
                break
            case BeginArray =>
                r.startArray()
                while (r.peek() != EndArray) {
                    list.add(TankoubonInfo.fromJson(r))
                }
                r.endArray()
                break
            case _ => break
        }
    }
    return list
}

// 单个合集：metadata 端点返回裸对象，unwrapDataRaw 兼容包络形态。
public func parseTankoubon(body: String): TankoubonInfo {
    let raw = unwrapDataRaw(body)
    if (raw.size == 0) { throw Exception("empty tankoubon") }
    JsonCodec.decode<TankoubonInfo>(raw)
}

// 混合页统计：按 pageType 字符串计数（"image"/"video"/"audio"/"html"），未知类型忽略。
public class PageTypeStat {
    public var image: Int64 = 0
    public var video: Int64 = 0
    public var audio: Int64 = 0
    public var html: Int64 = 0
}

public func statPages(pages: Array<PageInfo>): PageTypeStat {
    let s = PageTypeStat()
    for (p in pages) {
        match (p.pageType) {
            case "image" => s.image += 1
            case "video" => s.video += 1
            case "audio" => s.audio += 1
            case "html" => s.html += 1
            case _ => ()
        }
    }
    return s
}

// 首页混合列表项：档案或合集。去重 key 对齐 frontend HomePageClient :290-309
// （"tankoubon:{tankoubon_id}" / "archive:{arcid}"）。
// 注：简报中的 Arc(ArchiveInfo) 对应本包档案摘要 DTO SearchItem（无单独 ArchiveInfo 类型）。
public enum HomeItem {
    | Arc(SearchItem)
    | Tank(TankoubonInfo)

    public func key(): String {
        match (this) {
            case Arc(a) => "archive:${a.arcid}"
            case Tank(t) => "tankoubon:${t.id}"
        }
    }
}

// ==================== 设置区扩展 DTO（管理/统计端点） ====================
// 响应形态已对照 src/routes/api/** 与 frontend/src/lib/services/** 核实。

public class UserStats {
    public var favoriteCount: Int64 = 0
    public var readCount: Int64 = 0
    public var totalPagesRead: Int64 = 0
    public var totalArchives: Int64 = 0
}

public func parseUserStats(body: String): UserStats {
    let s = UserStats()
    let env = parseEnvelope(body)
    var raw = env.dataRaw
    if (raw.size == 0) { raw = unwrapDataRaw(body) }
    if (raw.size == 0) { return s }
    let r = readerOf(raw)
    while (let Some(tok) <- r.peek()) {
        match (tok) {
            case BeginObject =>
                r.startObject()
                while (r.peek() != EndObject) {
                    match (r.readName()) {
                        case "favoriteCount" => s.favoriteCount = decodeRaw<Int64>(r.readValueBytes(), 0)
                        case "readCount" => s.readCount = decodeRaw<Int64>(r.readValueBytes(), 0)
                        case "totalPagesRead" => s.totalPagesRead = decodeRaw<Int64>(r.readValueBytes(), 0)
                        case "totalArchives" => s.totalArchives = decodeRaw<Int64>(r.readValueBytes(), 0)
                        case _ => r.skip()
                    }
                }
                r.endObject()
                break
            case _ => break
        }
    }
    return s
}

public class TrendPoint {
    public var date: String = ""
    public var count: Int64 = 0
}

public class CloudTag {
    public var tag: String = ""
    public var display: String = ""
    public var count: Int64 = 0
}

// 对象数组解析的内部通用件：数组可能直接是 data，也可能包在对象 key 内。
// 保持包内可见（不加 private），Task 2 的第二批 DTO 会复用。
func dataArrayRaw(body: String, objectKey: String): String {
    // 部分端点直接返回裸 JSON 数组（如 /api/admin/plugins 的 getAllPlugins），
    // 无 {code,message,data} 包络——原样返回，不能走 parseEnvelope（会抛 invalid json envelope）。
    let trimmed = body.trimAscii()
    if (trimmed.size > 0 && trimmed[0..1] == "[") { return trimmed }
    let env = parseEnvelope(body)
    var raw = env.dataRaw
    if (raw.size == 0) { raw = unwrapDataRaw(body) }
    if (raw.size == 0) { return "" }
    // data 是对象：取指定键（users/sessions/tokens/credentials/items…）；是数组则原样。
    let probe = readerOf(raw)
    if (let Some(BeginObject) <- probe.peek()) {
        let r = readerOf(raw)
        while (let Some(tok) <- r.peek()) {
            match (tok) {
                case BeginObject =>
                    r.startObject()
                    while (r.peek() != EndObject) {
                        if (r.readName() == objectKey) {
                            return rawText(r.readValueBytes())
                        } else {
                            r.skip()
                        }
                    }
                    r.endObject()
                    return ""
                case _ => return ""
            }
        }
        return ""
    }
    return raw
}

public func parseTrendList(body: String): ArrayList<TrendPoint> {
    let list = ArrayList<TrendPoint>()
    let raw = dataArrayRaw(body, "trend")
    if (raw.size == 0) { return list }
    let r = readerOf(raw)
    while (let Some(tok) <- r.peek()) {
        match (tok) {
            case BeginArray =>
                r.startArray()
                while (r.peek() != EndArray) {
                    r.startObject()
                    let p = TrendPoint()
                    while (r.peek() != EndObject) {
                        match (r.readName()) {
                            case "date" => p.date = decodeRaw<String>(r.readValueBytes(), "")
                            case "count" => p.count = decodeRaw<Int64>(r.readValueBytes(), 0)
                            case _ => r.skip()
                        }
                    }
                    r.endObject()
                    list.add(p)
                }
                r.endArray()
                break
            case _ => break
        }
    }
    return list
}

public func parseCloudTags(body: String): ArrayList<CloudTag> {
    let list = ArrayList<CloudTag>()
    let raw = dataArrayRaw(body, "items")
    if (raw.size == 0) { return list }
    let r = readerOf(raw)
    while (let Some(tok) <- r.peek()) {
        match (tok) {
            case BeginArray =>
                r.startArray()
                while (r.peek() != EndArray) {
                    r.startObject()
                    let t = CloudTag()
                    while (r.peek() != EndObject) {
                        match (r.readName()) {
                            case "tag" => t.tag = decodeRaw<String>(r.readValueBytes(), "")
                            case "display" => t.display = decodeRaw<String>(r.readValueBytes(), "")
                            case "count" => t.count = decodeRaw<Int64>(r.readValueBytes(), 0)
                            case _ => r.skip()
                        }
                    }
                    r.endObject()
                    // 服务端 display 可缺省，前端列表直接展示，回落 tag。
                    if (t.display.size == 0) { t.display = t.tag }
                    list.add(t)
                }
                r.endArray()
                break
            case _ => break
        }
    }
    return list
}

public class TotpStatus {
    public var enabled: Bool = false
    public var credentialName: String = ""
    public var createdAt: String = ""
    public var recoveryCodesRemaining: Int64 = 0
}

public func parseTotpStatus(body: String): TotpStatus {
    let s = TotpStatus()
    let env = parseEnvelope(body)
    var raw = env.dataRaw
    if (raw.size == 0) { raw = unwrapDataRaw(body) }
    if (raw.size == 0) { return s }
    let r = readerOf(raw)
    while (let Some(tok) <- r.peek()) {
        match (tok) {
            case BeginObject =>
                r.startObject()
                while (r.peek() != EndObject) {
                    match (r.readName()) {
                        case "enabled" => s.enabled = decodeRaw<Bool>(r.readValueBytes(), false)
                        case "credentialName" => s.credentialName = decodeRaw<String>(r.readValueBytes(), "")
                        case "createdAt" => s.createdAt = decodeRaw<String>(r.readValueBytes(), "")
                        case "recoveryCodesRemaining" => s.recoveryCodesRemaining = decodeRaw<Int64>(r.readValueBytes(), 0)
                        case _ => r.skip()
                    }
                }
                r.endObject()
                break
            case _ => break
        }
    }
    return s
}

public class SessionItem {
    public var id: Int64 = 0
    public var name: String = ""
    public var prefix: String = ""
    public var createdAt: String = ""
    public var lastUsedAt: String = ""
    public var lastUsedIp: String = ""
    public var current: Bool = false
}

public func parseSessionList(body: String): ArrayList<SessionItem> {
    let list = ArrayList<SessionItem>()
    let raw = dataArrayRaw(body, "sessions")
    if (raw.size == 0) { return list }
    let r = readerOf(raw)
    while (let Some(tok) <- r.peek()) {
        match (tok) {
            case BeginArray =>
                r.startArray()
                while (r.peek() != EndArray) {
                    r.startObject()
                    let it = SessionItem()
                    while (r.peek() != EndObject) {
                        match (r.readName()) {
                            case "id" => it.id = decodeRaw<Int64>(r.readValueBytes(), 0)
                            case "name" => it.name = decodeRaw<String>(r.readValueBytes(), "")
                            case "prefix" => it.prefix = decodeRaw<String>(r.readValueBytes(), "")
                            case "createdAt" => it.createdAt = decodeRaw<String>(r.readValueBytes(), "")
                            case "lastUsedAt" => it.lastUsedAt = decodeRaw<String>(r.readValueBytes(), "")
                            case "lastUsedIp" => it.lastUsedIp = decodeRaw<String>(r.readValueBytes(), "")
                            case "current" => it.current = decodeRaw<Bool>(r.readValueBytes(), false)
                            case _ => r.skip()
                        }
                    }
                    r.endObject()
                    list.add(it)
                }
                r.endArray()
                break
            case _ => break
        }
    }
    return list
}

public class TokenItem {
    public var id: Int64 = 0
    public var name: String = ""
    public var prefix: String = ""
    public var token: String = ""
}

public func parseTokenList(body: String): ArrayList<TokenItem> {
    let list = ArrayList<TokenItem>()
    let raw = dataArrayRaw(body, "tokens")
    if (raw.size == 0) { return list }
    let r = readerOf(raw)
    while (let Some(tok) <- r.peek()) {
        match (tok) {
            case BeginArray =>
                r.startArray()
                while (r.peek() != EndArray) {
                    r.startObject()
                    let it = TokenItem()
                    while (r.peek() != EndObject) {
                        match (r.readName()) {
                            case "id" => it.id = decodeRaw<Int64>(r.readValueBytes(), 0)
                            case "name" => it.name = decodeRaw<String>(r.readValueBytes(), "")
                            case "prefix" => it.prefix = decodeRaw<String>(r.readValueBytes(), "")
                            // token 明文仅创建响应返回一次，列表里没有。
                            case "token" => it.token = decodeRaw<String>(r.readValueBytes(), "")
                            case _ => r.skip()
                        }
                    }
                    r.endObject()
                    list.add(it)
                }
                r.endArray()
                break
            case _ => break
        }
    }
    return list
}

public class PasskeyItem {
    public var id: Int64 = 0
    public var name: String = ""
    public var credentialId: String = ""
    public var algorithm: String = ""
    public var userVerified: Bool = false
    public var lastUsedAt: String = ""
}

public func parsePasskeyList(body: String): ArrayList<PasskeyItem> {
    let list = ArrayList<PasskeyItem>()
    let raw = dataArrayRaw(body, "credentials")
    if (raw.size == 0) { return list }
    let r = readerOf(raw)
    while (let Some(tok) <- r.peek()) {
        match (tok) {
            case BeginArray =>
                r.startArray()
                while (r.peek() != EndArray) {
                    r.startObject()
                    let it = PasskeyItem()
                    while (r.peek() != EndObject) {
                        match (r.readName()) {
                            case "id" => it.id = decodeRaw<Int64>(r.readValueBytes(), 0)
                            case "name" => it.name = decodeRaw<String>(r.readValueBytes(), "")
                            case "credentialId" => it.credentialId = decodeRaw<String>(r.readValueBytes(), "")
                            case "algorithm" => it.algorithm = decodeRaw<String>(r.readValueBytes(), "")
                            case "userVerified" => it.userVerified = decodeRaw<Bool>(r.readValueBytes(), false)
                            case "lastUsedAt" => it.lastUsedAt = decodeRaw<String>(r.readValueBytes(), "")
                            case _ => r.skip()
                        }
                    }
                    r.endObject()
                    list.add(it)
                }
                r.endArray()
                break
            case _ => break
        }
    }
    return list
}

public class AdminUserItem {
    public var id: Int64 = 0
    public var username: String = ""
    public var isAdmin: Bool = false
    public var createdAt: String = ""
}

public func parseAdminUserList(body: String): ArrayList<AdminUserItem> {
    let list = ArrayList<AdminUserItem>()
    let raw = dataArrayRaw(body, "users")
    if (raw.size == 0) { return list }
    let r = readerOf(raw)
    while (let Some(tok) <- r.peek()) {
        match (tok) {
            case BeginArray =>
                r.startArray()
                while (r.peek() != EndArray) {
                    r.startObject()
                    let it = AdminUserItem()
                    while (r.peek() != EndObject) {
                        match (r.readName()) {
                            case "id" => it.id = decodeRaw<Int64>(r.readValueBytes(), 0)
                            case "username" => it.username = decodeRaw<String>(r.readValueBytes(), "")
                            case "isAdmin" => it.isAdmin = decodeRaw<Bool>(r.readValueBytes(), false)
                            case "createdAt" => it.createdAt = decodeRaw<String>(r.readValueBytes(), "")
                            case _ => r.skip()
                        }
                    }
                    r.endObject()
                    list.add(it)
                }
                r.endArray()
                break
            case _ => break
        }
    }
    return list
}

public class SysSetting {
    public var key: String = ""
    public var value: String = ""
    public var valueType: String = ""
    public var category: String = ""
    public var descriptionZh: String = ""
}

public func parseSysSettings(body: String): ArrayList<SysSetting> {
    let list = ArrayList<SysSetting>()
    let raw = dataArrayRaw(body, "settings")
    if (raw.size == 0) { return list }
    let r = readerOf(raw)
    while (let Some(tok) <- r.peek()) {
        match (tok) {
            case BeginArray =>
                r.startArray()
                while (r.peek() != EndArray) {
                    r.startObject()
                    let it = SysSetting()
                    while (r.peek() != EndObject) {
                        match (r.readName()) {
                            case "key" => it.key = decodeRaw<String>(r.readValueBytes(), "")
                            case "value" => it.value = decodeRaw<String>(r.readValueBytes(), "")
                            // 服务端序列化键未在仓库内固定写死，驼峰/下划线两种都收。
                            case "valueType" => it.valueType = decodeRaw<String>(r.readValueBytes(), "")
                            case "value_type" => it.valueType = decodeRaw<String>(r.readValueBytes(), "")
                            case "category" => it.category = decodeRaw<String>(r.readValueBytes(), "")
                            case "description" => it.descriptionZh = parseDescriptionZh(rawText(r.readValueBytes()))
                            case _ => r.skip()
                        }
                    }
                    r.endObject()
                    list.add(it)
                }
                r.endArray()
                break
            case _ => break
        }
    }
    return list
}

// description 是多语言对象 {"zh":"…","en":"…"}，设置页只取中文。
private func parseDescriptionZh(raw: String): String {
    if (raw.size == 0) { return "" }
    let r = readerOf(raw)
    while (let Some(tok) <- r.peek()) {
        match (tok) {
            case BeginObject =>
                r.startObject()
                while (r.peek() != EndObject) {
                    if (r.readName() == "zh") {
                        return decodeRaw<String>(r.readValueBytes(), "")
                    } else {
                        r.skip()
                    }
                }
                r.endObject()
                return ""
            case _ => return ""
        }
    }
    return ""
}

// 创建用户响应 data 内含服务端生成的初始密码（auth.admin.user.create）。
public func parseGeneratedPassword(body: String): String {
    let env = parseEnvelope(body)
    var raw = env.dataRaw
    if (raw.size == 0) { raw = unwrapDataRaw(body) }
    if (raw.size == 0) { return "" }
    let r = readerOf(raw)
    while (let Some(tok) <- r.peek()) {
        match (tok) {
            case BeginObject =>
                r.startObject()
                while (r.peek() != EndObject) {
                    if (r.readName() == "password") {
                        return decodeRaw<String>(r.readValueBytes(), "")
                    } else {
                        r.skip()
                    }
                }
                r.endObject()
                return ""
            case _ => return ""
        }
    }
    return ""
}


// ==================== 设置区扩展 DTO 第二批（内容/任务/插件） ====================

public class AdminCategoryItem {
    public var id: Int64 = 0
    public var catid: String = ""
    public var name: String = ""
    public var scanPath: String = ""
    public var description: String = ""
    public var sortOrder: Int64 = 0
    public var enabled: Bool = false
    public var plugins = ArrayList<String>()
    public var coverAssetId: Int64 = 0
    public var archiveCount: Int64 = 0
}

public func parseAdminCategoryList(body: String): ArrayList<AdminCategoryItem> {
    let list = ArrayList<AdminCategoryItem>()
    let raw = dataArrayRaw(body, "categories")
    if (raw.size == 0) { return list }
    let r = readerOf(raw)
    while (let Some(tok) <- r.peek()) {
        match (tok) {
            case BeginArray =>
                r.startArray()
                while (r.peek() != EndArray) {
                    r.startObject()
                    let it = AdminCategoryItem()
                    while (r.peek() != EndObject) {
                        match (r.readName()) {
                            case "id" => it.id = decodeRaw<Int64>(r.readValueBytes(), 0)
                            case "catid" => it.catid = decodeRaw<String>(r.readValueBytes(), "")
                            case "name" => it.name = decodeRaw<String>(r.readValueBytes(), "")
                            case "scan_path" => it.scanPath = decodeRaw<String>(r.readValueBytes(), "")
                            case "description" => it.description = decodeRaw<String>(r.readValueBytes(), "")
                            case "sort_order" => it.sortOrder = decodeRaw<Int64>(r.readValueBytes(), 0)
                            case "enabled" => it.enabled = decodeRaw<Bool>(r.readValueBytes(), false)
                            case "plugins" => it.plugins = parseStringArray(rawText(r.readValueBytes()))
                            case "cover_asset_id" => it.coverAssetId = decodeRaw<Int64>(r.readValueBytes(), 0)
                            case "archive_count" => it.archiveCount = decodeRaw<Int64>(r.readValueBytes(), 0)
                            case _ => r.skip()
                        }
                    }
                    r.endObject()
                    list.add(it)
                }
                r.endArray()
                break
            case _ => break
        }
    }
    return list
}

public class AdminTagItem {
    public var id: Int64 = 0
    public var namespace: String = ""
    public var name: String = ""
    public var zhText: String = ""
    public var enText: String = ""
    public var links: String = ""
}

public class TagListPage {
    public var items = ArrayList<AdminTagItem>()
    public var total: Int64 = 0
}

// translations 是 {"zh":{"text":"…"},"en":{"text":"…"}}，展平到 zhText/enText。
private func parseTranslationText(raw: String, lang: String): String {
    if (raw.size == 0) { return "" }
    let r = readerOf(raw)
    while (let Some(tok) <- r.peek()) {
        match (tok) {
            case BeginObject =>
                r.startObject()
                while (r.peek() != EndObject) {
                    if (r.readName() == lang) {
                        let inner = readerOf(rawText(r.readValueBytes()))
                        while (let Some(t2) <- inner.peek()) {
                            match (t2) {
                                case BeginObject =>
                                    inner.startObject()
                                    while (inner.peek() != EndObject) {
                                        if (inner.readName() == "text") {
                                            return decodeRaw<String>(inner.readValueBytes(), "")
                                        } else {
                                            inner.skip()
                                        }
                                    }
                                    inner.endObject()
                                    return ""
                                case _ => return ""
                            }
                        }
                        return ""
                    } else {
                        r.skip()
                    }
                }
                r.endObject()
                return ""
            case _ => return ""
        }
    }
    return ""
}

public func parseTagListPage(body: String): TagListPage {
    let page = TagListPage()
    let env = parseEnvelope(body)
    var raw = env.dataRaw
    if (raw.size == 0) { raw = unwrapDataRaw(body) }
    if (raw.size == 0) { return page }
    var itemsRaw = ""
    let r = readerOf(raw)
    while (let Some(tok) <- r.peek()) {
        match (tok) {
            case BeginObject =>
                r.startObject()
                while (r.peek() != EndObject) {
                    match (r.readName()) {
                        case "total" => page.total = decodeRaw<Int64>(r.readValueBytes(), 0)
                        case "items" => itemsRaw = rawText(r.readValueBytes())
                        case _ => r.skip()
                    }
                }
                r.endObject()
                break
            case _ => break
        }
    }
    if (itemsRaw.size == 0) { return page }
    let ir = readerOf(itemsRaw)
    while (let Some(tok) <- ir.peek()) {
        match (tok) {
            case BeginArray =>
                ir.startArray()
                while (ir.peek() != EndArray) {
                    ir.startObject()
                    let it = AdminTagItem()
                    while (ir.peek() != EndObject) {
                        match (ir.readName()) {
                            case "id" => it.id = decodeRaw<Int64>(ir.readValueBytes(), 0)
                            case "namespace" => it.namespace = decodeRaw<String>(ir.readValueBytes(), "")
                            case "name" => it.name = decodeRaw<String>(ir.readValueBytes(), "")
                            case "links" => it.links = decodeRaw<String>(ir.readValueBytes(), "")
                            case "translations" =>
                                let tr = rawText(ir.readValueBytes())
                                it.zhText = parseTranslationText(tr, "zh")
                                it.enText = parseTranslationText(tr, "en")
                            case _ => ir.skip()
                        }
                    }
                    ir.endObject()
                    page.items.add(it)
                }
                ir.endArray()
                break
            case _ => break
        }
    }
    return page
}

public class SmartFilterItem {
    public var id: Int64 = 0
    public var name: String = ""
    public var icon: String = ""
    public var query: String = ""
    public var sortBy: String = ""
    public var sortOrder: String = "desc"
    public var dateFrom: String = ""
    public var dateTo: String = ""
    public var newonly: Bool = false
    public var untaggedonly: Bool = false
    public var sortOrderNum: Int64 = 0
    public var enabled: Bool = false
}

public func parseSmartFilterList(body: String): ArrayList<SmartFilterItem> {
    let list = ArrayList<SmartFilterItem>()
    let raw = dataArrayRaw(body, "items")
    if (raw.size == 0) { return list }
    let r = readerOf(raw)
    while (let Some(tok) <- r.peek()) {
        match (tok) {
            case BeginArray =>
                r.startArray()
                while (r.peek() != EndArray) {
                    r.startObject()
                    let it = SmartFilterItem()
                    while (r.peek() != EndObject) {
                        match (r.readName()) {
                            case "id" => it.id = decodeRaw<Int64>(r.readValueBytes(), 0)
                            case "name" => it.name = decodeRaw<String>(r.readValueBytes(), "")
                            case "icon" => it.icon = decodeRaw<String>(r.readValueBytes(), "")
                            case "query" => it.query = decodeRaw<String>(r.readValueBytes(), "")
                            case "sort_by" => it.sortBy = decodeRaw<String>(r.readValueBytes(), "")
                            case "sort_order" => it.sortOrder = decodeRaw<String>(r.readValueBytes(), "desc")
                            case "date_from" => it.dateFrom = decodeRaw<String>(r.readValueBytes(), "")
                            case "date_to" => it.dateTo = decodeRaw<String>(r.readValueBytes(), "")
                            case "newonly" => it.newonly = decodeRaw<Bool>(r.readValueBytes(), false)
                            case "untaggedonly" => it.untaggedonly = decodeRaw<Bool>(r.readValueBytes(), false)
                            case "sort_order_num" => it.sortOrderNum = decodeRaw<Int64>(r.readValueBytes(), 0)
                            case "enabled" => it.enabled = decodeRaw<Bool>(r.readValueBytes(), false)
                            case _ => r.skip()
                        }
                    }
                    r.endObject()
                    list.add(it)
                }
                r.endArray()
                break
            case _ => break
        }
    }
    return list
}

public class TaskRecord {
    public var id: Int64 = 0
    public var name: String = ""
    public var status: String = ""
    public var phase: String = ""
    public var message: String = ""
    public var taskType: String = ""
    public var pluginNamespace: String = ""
    public var result: String = ""
    public var waitingReason: String = ""
    public var triggerSource: String = ""
    public var progress: Int64 = 0
    public var priority: Int64 = 0
    public var createdAt: String = ""
    public var startedAt: String = ""
    public var completedAt: String = ""
}

public class TaskListPage {
    public var tasks = ArrayList<TaskRecord>()
    public var total: Int64 = 0
}

// 入参是 SSE data 帧原文（裸 JSON {"tasks":[...],"total":N}，无 envelope）——
// taskpool_controller.getTasks 是 SSE 端点，不走 parseEnvelope。
public func parseTaskListPage(data: String): TaskListPage {
    let page = TaskListPage()
    if (data.size == 0) { return page }
    // SSE 快照负载形态：{"v":2,"event_type":"snapshot","data":{"tasks":[...],"total":N}}——
    // tasks/total 在嵌套的 data 对象里（taskpool_controller.buildTaskListStreamData）。
    var payload = data
    let probe = readerOf(data)
    if (let Some(BeginObject) <- probe.peek()) {
        let pr = readerOf(data)
        while (let Some(tok) <- pr.peek()) {
            match (tok) {
                case BeginObject =>
                    pr.startObject()
                    while (pr.peek() != EndObject) {
                        if (pr.readName() == "data") {
                            payload = rawText(pr.readValueBytes())
                            break
                        } else {
                            pr.skip()
                        }
                    }
                    pr.endObject()
                    break
                case _ => break
            }
        }
    }
    var tasksRaw = ""
    let r = readerOf(payload)
    while (let Some(tok) <- r.peek()) {
        match (tok) {
            case BeginObject =>
                r.startObject()
                while (r.peek() != EndObject) {
                    match (r.readName()) {
                        case "total" => page.total = decodeRaw<Int64>(r.readValueBytes(), 0)
                        case "tasks" => tasksRaw = rawText(r.readValueBytes())
                        case _ => r.skip()
                    }
                }
                r.endObject()
                break
            case _ => break
        }
    }
    if (tasksRaw.size == 0) { return page }
    let tr = readerOf(tasksRaw)
    while (let Some(tok) <- tr.peek()) {
        match (tok) {
            case BeginArray =>
                tr.startArray()
                while (tr.peek() != EndArray) {
                    tr.startObject()
                    let it = TaskRecord()
                    while (tr.peek() != EndObject) {
                        match (tr.readName()) {
                            case "id" => it.id = decodeRaw<Int64>(tr.readValueBytes(), 0)
                            case "name" => it.name = decodeRaw<String>(tr.readValueBytes(), "")
                            case "status" => it.status = decodeRaw<String>(tr.readValueBytes(), "")
                            case "phase" => it.phase = decodeRaw<String>(tr.readValueBytes(), "")
                            case "message" => it.message = decodeRaw<String>(tr.readValueBytes(), "")
                            case "task_type" => it.taskType = decodeRaw<String>(tr.readValueBytes(), "")
                            case "plugin_namespace" => it.pluginNamespace = decodeRaw<String>(tr.readValueBytes(), "")
                            case "result" => it.result = rawText(tr.readValueBytes())
                            case "waiting_reason" => it.waitingReason = decodeRaw<String>(tr.readValueBytes(), "")
                            case "trigger_source" => it.triggerSource = decodeRaw<String>(tr.readValueBytes(), "")
                            case "progress" => it.progress = decodeRaw<Int64>(tr.readValueBytes(), 0)
                            case "priority" => it.priority = decodeRaw<Int64>(tr.readValueBytes(), 0)
                            case "created_at" => it.createdAt = decodeRaw<String>(tr.readValueBytes(), "")
                            case "started_at" => it.startedAt = decodeRaw<String>(tr.readValueBytes(), "")
                            case "completed_at" => it.completedAt = decodeRaw<String>(tr.readValueBytes(), "")
                            case _ => tr.skip()
                        }
                    }
                    tr.endObject()
                    page.tasks.add(it)
                }
                tr.endArray()
                break
            case _ => break
        }
    }
    return page
}

public class CronTask {
    public var id: Int64 = 0
    public var name: String = ""
    public var cronExpression: String = ""
    public var taskType: String = ""
    public var enabled: Bool = false
    public var priority: Int64 = 0
    public var timeoutSeconds: Int64 = 0
    public var runCount: Int64 = 0
    public var lastRunAt: String = ""
    public var nextRunAt: String = ""
    public var lastRunSuccess: Bool = false
    public var hasLastRun: Bool = false
}

public class CronStatus {
    public var running: Bool = false
    public var totalTasks: Int64 = 0
    public var enabledTasks: Int64 = 0
}

public class CronTaskType {
    public var value: String = ""
    public var label: String = ""
    public var description: String = ""
}

public class CronValidateResult {
    public var valid: Bool = false
    public var error: String = ""
    public var nextRuns = ArrayList<String>()
}

// cron 状态/校验共用：取 envelope 的 data 原文并返回 reader。
private func cronDataReader(body: String): ?JsonReader {
    let env = parseEnvelope(body)
    var raw = env.dataRaw
    if (raw.size == 0) { raw = unwrapDataRaw(body) }
    if (raw.size == 0) { return None }
    return readerOf(raw)
}

public func parseCronStatus(body: String): CronStatus {
    let s = CronStatus()
    let r = match (cronDataReader(body)) { case Some(x) => x; case None => return s }
    while (let Some(tok) <- r.peek()) {
        match (tok) {
            case BeginObject =>
                r.startObject()
                while (r.peek() != EndObject) {
                    match (r.readName()) {
                        case "running" => s.running = decodeRaw<Bool>(r.readValueBytes(), false)
                        case "totalTasks" => s.totalTasks = decodeRaw<Int64>(r.readValueBytes(), 0)
                        case "enabledTasks" => s.enabledTasks = decodeRaw<Int64>(r.readValueBytes(), 0)
                        case _ => r.skip()
                    }
                }
                r.endObject()
                break
            case _ => break
        }
    }
    return s
}

public func parseCronTaskList(body: String): ArrayList<CronTask> {
    let list = ArrayList<CronTask>()
    let raw = dataArrayRaw(body, "tasks")
    if (raw.size == 0) { return list }
    let r = readerOf(raw)
    while (let Some(tok) <- r.peek()) {
        match (tok) {
            case BeginArray =>
                r.startArray()
                while (r.peek() != EndArray) {
                    r.startObject()
                    let it = CronTask()
                    while (r.peek() != EndObject) {
                        match (r.readName()) {
                            case "id" => it.id = decodeRaw<Int64>(r.readValueBytes(), 0)
                            case "name" => it.name = decodeRaw<String>(r.readValueBytes(), "")
                            case "cronExpression" => it.cronExpression = decodeRaw<String>(r.readValueBytes(), "")
                            case "taskType" => it.taskType = decodeRaw<String>(r.readValueBytes(), "")
                            case "enabled" => it.enabled = decodeRaw<Bool>(r.readValueBytes(), false)
                            case "priority" => it.priority = decodeRaw<Int64>(r.readValueBytes(), 0)
                            case "timeoutSeconds" => it.timeoutSeconds = decodeRaw<Int64>(r.readValueBytes(), 0)
                            case "runCount" => it.runCount = decodeRaw<Int64>(r.readValueBytes(), 0)
                            case "nextRunAt" => it.nextRunAt = decodeRaw<String>(r.readValueBytes(), "")
                            case "lastRunSuccess" => it.lastRunSuccess = decodeRaw<Bool>(r.readValueBytes(), false)
                            case "lastRunAt" =>
                                it.lastRunAt = decodeRaw<String>(r.readValueBytes(), "")
                                it.hasLastRun = it.lastRunAt.size > 0
                            case _ => r.skip()
                        }
                    }
                    r.endObject()
                    list.add(it)
                }
                r.endArray()
                break
            case _ => break
        }
    }
    return list
}

public func parseCronTaskTypes(body: String): ArrayList<CronTaskType> {
    let list = ArrayList<CronTaskType>()
    let raw = dataArrayRaw(body, "types")
    if (raw.size == 0) { return list }
    let r = readerOf(raw)
    while (let Some(tok) <- r.peek()) {
        match (tok) {
            case BeginArray =>
                r.startArray()
                while (r.peek() != EndArray) {
                    r.startObject()
                    let it = CronTaskType()
                    while (r.peek() != EndObject) {
                        match (r.readName()) {
                            case "value" => it.value = decodeRaw<String>(r.readValueBytes(), "")
                            case "label" => it.label = decodeRaw<String>(r.readValueBytes(), "")
                            case "description" => it.description = decodeRaw<String>(r.readValueBytes(), "")
                            case _ => r.skip()
                        }
                    }
                    r.endObject()
                    // label 缺省时回落 value，供下拉直接展示。
                    if (it.label.size == 0) { it.label = it.value }
                    list.add(it)
                }
                r.endArray()
                break
            case _ => break
        }
    }
    return list
}

public func parseCronValidate(body: String): CronValidateResult {
    let s = CronValidateResult()
    let r = match (cronDataReader(body)) { case Some(x) => x; case None => return s }
    while (let Some(tok) <- r.peek()) {
        match (tok) {
            case BeginObject =>
                r.startObject()
                while (r.peek() != EndObject) {
                    match (r.readName()) {
                        case "valid" => s.valid = decodeRaw<Bool>(r.readValueBytes(), false)
                        case "error" => s.error = decodeRaw<String>(r.readValueBytes(), "")
                        case "nextRuns" => s.nextRuns = parseStringArray(rawText(r.readValueBytes()))
                        case _ => r.skip()
                    }
                }
                r.endObject()
                break
            case _ => break
        }
    }
    return s
}

public class PluginItem {
    public var name: String = ""
    public var namespace: String = ""
    public var version: String = ""
    public var pluginType: String = ""
    public var author: String = ""
    public var description: String = ""
    public var updateUrl: String = ""
    public var enabled: Bool = false
    public var installed: Bool = false
    public var hasSchema: Bool = false
}

public func parsePluginList(body: String): ArrayList<PluginItem> {
    let list = ArrayList<PluginItem>()
    let raw = dataArrayRaw(body, "plugins")
    if (raw.size == 0) { return list }
    let r = readerOf(raw)
    while (let Some(tok) <- r.peek()) {
        match (tok) {
            case BeginArray =>
                r.startArray()
                while (r.peek() != EndArray) {
                    r.startObject()
                    let it = PluginItem()
                    while (r.peek() != EndObject) {
                        match (r.readName()) {
                            case "name" => it.name = decodeRaw<String>(r.readValueBytes(), "")
                            case "namespace" => it.namespace = decodeRaw<String>(r.readValueBytes(), "")
                            case "version" => it.version = decodeRaw<String>(r.readValueBytes(), "")
                            case "plugin_type" => it.pluginType = decodeRaw<String>(r.readValueBytes(), "").toAsciiLower()
                            case "pluginType" => it.pluginType = decodeRaw<String>(r.readValueBytes(), "").toAsciiLower()
                            case "author" => it.author = decodeRaw<String>(r.readValueBytes(), "")
                            case "description" => it.description = decodeRaw<String>(r.readValueBytes(), "")
                            case "update_url" => it.updateUrl = decodeRaw<String>(r.readValueBytes(), "")
                            case "enabled" => it.enabled = decodeRaw<Bool>(r.readValueBytes(), false)
                            case "installed" => it.installed = decodeRaw<Bool>(r.readValueBytes(), false)
                            case "has_schema" => it.hasSchema = decodeRaw<Bool>(r.readValueBytes(), false)
                            case _ => r.skip()
                        }
                    }
                    r.endObject()
                    list.add(it)
                }
                r.endArray()
                break
            case _ => break
        }
    }
    return list
}

public class PluginParam {
    public var name: String = ""
    public var `type`: String = ""
    public var desc: String = ""
    public var defaultValue: String = ""
    public var value: String = ""
}

public func parsePluginParams(body: String): ArrayList<PluginParam> {
    let list = ArrayList<PluginParam>()
    let raw = dataArrayRaw(body, "parameters")
    if (raw.size == 0) { return list }
    let r = readerOf(raw)
    while (let Some(tok) <- r.peek()) {
        match (tok) {
            case BeginArray =>
                r.startArray()
                while (r.peek() != EndArray) {
                    r.startObject()
                    let it = PluginParam()
                    while (r.peek() != EndObject) {
                        match (r.readName()) {
                            case "name" => it.name = decodeRaw<String>(r.readValueBytes(), "")
                            case "type" => it.`type` = decodeRaw<String>(r.readValueBytes(), "")
                            case "desc" => it.desc = decodeRaw<String>(r.readValueBytes(), "")
                            case "default_value" => it.defaultValue = decodeRaw<String>(r.readValueBytes(), "")
                            case "value" => it.value = decodeRaw<String>(r.readValueBytes(), "")
                            case _ => r.skip()
                        }
                    }
                    r.endObject()
                    list.add(it)
                }
                r.endArray()
                break
            case _ => break
        }
    }
    return list
}

// 创建 Token 响应：data 为单个 TokenView 对象（含一次性明文 token，仅此一次可见）。
public func parseCreatedToken(body: String): TokenItem {
    let t = TokenItem()
    let env = parseEnvelope(body)
    var raw = env.dataRaw
    if (raw.size == 0) { raw = unwrapDataRaw(body) }
    if (raw.size == 0) { return t }
    let r = readerOf(raw)
    while (let Some(tok) <- r.peek()) {
        match (tok) {
            case BeginObject =>
                r.startObject()
                while (r.peek() != EndObject) {
                    match (r.readName()) {
                        case "id" => t.id = decodeRaw<Int64>(r.readValueBytes(), 0)
                        case "name" => t.name = decodeRaw<String>(r.readValueBytes(), "")
                        case "prefix" => t.prefix = decodeRaw<String>(r.readValueBytes(), "")
                        case "token" => t.token = decodeRaw<String>(r.readValueBytes(), "")
                        case _ => r.skip()
                    }
                }
                r.endObject()
                break
            case _ => break
        }
    }
    return t
}
