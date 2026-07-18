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
func unwrapDataRaw(body: String): String {
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
    public var thumbnailHash: String = ""
    public var tags: ArrayList<String> = ArrayList<String>()
    public var capabilities: ArrayList<String> = ArrayList<String>()
    public var coverAssetId: Int64 = 0
    public var pagecount: Int64 = 0
    public var progress: Int64 = 0
    public var size: Int64 = 0
    public var isnew: Bool = false
    public var isfavorite: Bool = false

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
