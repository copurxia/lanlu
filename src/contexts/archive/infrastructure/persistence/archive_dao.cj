package lanlu.contexts.archive.infrastructure.persistence

import csorm.*
import postgresql_driver.*
import lanlu.shared.config.*
import lanlu.shared.utils.*
import lanlu.shared.utils.SearchFilter
import lanlu.infrastructure.kv.*
import lanlu.contexts.tag.infrastructure.persistence.*
import lanlu.contexts.metadata.infrastructure.persistence.*
import std.collection.*
import std.convert.*
import stdx.log.*

/**
 * 归档数据结构
 * 为了避免循环依赖，这个数据结构独立于 Archive 模型类
 * 注意：isNew 字段已移除，现在使用用户级别的已读状态（user_archive_status 表）
 */
public class ArchiveData {
    public var id: String = ""  // arcid
    public var internalId: Int64 = 0  // 数据库内部ID，用于关联查询
    public var title: String = ""
    public var filename: String = ""
    public var summary: String = ""
    public var thumbhash: String = ""
    public var cover_asset_id: Int64 = 0
    public var release_at: String = ""
    public var created_at: String = ""
    public var updated_at: String = ""
    public var relative_path: String = ""
    public var file_size: Int64 = 0
    public var pagecount: Int32 = 0
    public var archive_type: String = "archive"  // 归档类型：archive=压缩包，folder=文件夹，pdf=PDF
    public var category_id: Int64 = 0  // 分类ID
    public var tags: String = ""
    // last_read_time 和 progress 不再存储在 archives 表中，而是从 user_archive_status 表获取
    // 这些字段仅用于 API 响应，由 UserArchiveStatusDao 填充
    public var last_read_time: String = ""
    public var progress: Int32 = 0
    // favorite_time 存储用户收藏该档案的时间，从 user_favorites 表获取
    public var favorite_time: String = ""

    // When groupby_tanks=true, DAO can return one row per group with these fields populated.
    // group_item_type: "archive" | "tankoubon"
    // group_item_id: arcid (for archive) or tankoubon_id (for tankoubon)
    public var group_item_type: String = ""
    public var group_item_id: String = ""

    /**
     * 获取文件扩展名
     */
    public func getExtension(): String {
        if (filename.size > 0) {
            let parts = filename.split(".")
            if (parts.size > 1) {
                return parts[parts.size - 1]
            }
        }
        return ""
    }

    /**
     * 获取文件大小（别名，与API文档一致）
     */
    public func size(): Int64 {
        return file_size
    }
}

/**
 * Maintenance helper row: archive + category scan path + cover info.
 */
public class ArchiveCoverRegenerationRow {
    public var archiveInternalId: Int64 = 0  // archives.id
    public var archiveId: String = ""       // arcid
    public var filename: String = ""
    public var relativePath: String = ""
    public var archiveType: String = "archive"
    public var categoryId: Int64 = 0
    public var categoryScanPath: String = ""
    public var coverAssetId: Int64 = 0
    public var thumbhash: String = ""
}

/**
 * Maintenance helper row: archive + category plugins config (JSON array string).
 */
public class ArchiveMetadataBackfillRow {
    public var archiveInternalId: Int64 = 0  // archives.id
    public var archiveId: String = ""   // arcid
    public var categoryId: Int64 = 0
    public var categoryPlugins: String = "[]"
}

/**
 * 归档数据访问对象 (DAO)
 * 负责处理所有与归档相关的数据库操作
 */
public class ArchiveDao {
    private static let logger = getLogger("archive_dao")
    private static let archiveAssetsRawCacheTtlSeconds: Int64 = 7 * 24 * 60 * 60

    private static func normalizeUniqueIds(ids: Array<String>): Array<String> {
        return DerivedCacheUtils.normalizeUniqueIds(ids)
    }

    private static func buildArchiveAssetsRawCacheKey(version: Int64, archiveId: String): String {
        return "v${version.toString()}:a${archiveId}"
    }

    private static func readArchiveAssetsRawCache(cacheKey: String): Option<String> {
        let cacheNamespace = DerivedCacheUtils.getArchiveAssetsRawPayloadNamespace()
        match (PersistentCacheService.get(cacheNamespace, cacheKey)) {
            case Some(payload) =>
                let normalized = payload.trimAscii()
                return Some(if (normalized.size > 0) { normalized } else { "{}" })
            case None => return None
        }
    }

    private static func writeArchiveAssetsRawCache(cacheKey: String, raw: String): Unit {
        let cacheNamespace = DerivedCacheUtils.getArchiveAssetsRawPayloadNamespace()
        let payload = raw.trimAscii()
        let _ = PersistentCacheService.set(
            cacheNamespace,
            cacheKey,
            if (payload.size > 0) { payload } else { "{}" },
            archiveAssetsRawCacheTtlSeconds
        )
    }

    private static func invalidateTankoubonAggregatedContent(reason: String): Unit {
        let _ = DerivedCacheUtils.bumpTankoubonAggregatedContentVersion(reason)
    }

    private static func invalidateTankoubonChildren(reason: String): Unit {
        let _ = DerivedCacheUtils.bumpTankoubonChildrenVersion(reason)
    }

    private static func invalidateArchiveAssetsRaw(reason: String): Unit {
        let _ = DerivedCacheUtils.bumpArchiveAssetsRawVersion(reason)
    }

    private static func invalidateArchiveBasePath(reason: String): Unit {
        let _ = DerivedCacheUtils.bumpArchiveBasePathVersion(reason)
    }

    private static func extensionInstalled(db: Database, extensionName: String): Bool {
        try {
            return db.rawOne<Int64>(
                "SELECT 1 FROM pg_extension WHERE extname = $1 LIMIT 1",
                [vtext(extensionName)],
                { row => row.getInt64(0) }
            ).isSome()
        } catch (_: Exception) {
            return false
        }
    }

    private static func functionExists(db: Database, functionName: String): Bool {
        try {
            return db.rawOne<Int64>(
                "SELECT 1 FROM pg_proc WHERE proname = $1 LIMIT 1",
                [vtext(functionName)],
                { row => row.getInt64(0) }
            ).isSome()
        } catch (_: Exception) {
            return false
        }
    }

    private static func getUnaccentFunction(db: Database): String {
        if (functionExists(db, "lanlu_immutable_unaccent")) {
            return "lanlu_immutable_unaccent"
        }
        if (extensionInstalled(db, "unaccent")) {
            return "unaccent"
        }
        return ""
    }

    private static func wrapSearchExpr(expr: String, unaccentFunction: String): String {
        if (unaccentFunction.size > 0) {
            return "${unaccentFunction}(COALESCE(${expr}, ''))"
        }
        return "COALESCE(${expr}, '')"
    }

    private static func buildArchiveTextMatchCondition(
        pattern: String,
        params: ArrayList<String>,
        tableAlias: String,
        unaccentFunction: String
    ): String {
        params.add(pattern)
        params.add(pattern)
        params.add(pattern)
        let titleExpr = wrapSearchExpr("${tableAlias}.title", unaccentFunction)
        let filenameExpr = wrapSearchExpr("${tableAlias}.filename", unaccentFunction)
        let summaryExpr = wrapSearchExpr("${tableAlias}.summary", unaccentFunction)
        let patternExpr = if (unaccentFunction.size > 0) { "${unaccentFunction}(?)" } else { "?" }
        return "(${titleExpr} LIKE ${patternExpr} ESCAPE '\\' OR ${filenameExpr} LIKE ${patternExpr} ESCAPE '\\' OR ${summaryExpr} LIKE ${patternExpr} ESCAPE '\\' OR " +
            buildTagLikeCondition(pattern, params, tableAlias, unaccentFunction)
    }

    private static func buildMetadataTagLikeCondition(
        pattern: String,
        params: ArrayList<String>,
        entityType: String,
        entityIdExpr: String,
        unaccentFunction: String
    ): String {
        params.add(pattern)
        params.add(pattern)
        let nameExpr = if (unaccentFunction.size > 0) {
            "${unaccentFunction}(substring(mt.tag FROM position(':' IN mt.tag) + 1))"
        } else {
            "substring(mt.tag FROM position(':' IN mt.tag) + 1)"
        }
        let tagExpr = if (unaccentFunction.size > 0) { "${unaccentFunction}(mt.tag)" } else { "mt.tag" }
        let patternExpr = if (unaccentFunction.size > 0) { "${unaccentFunction}(?)" } else { "?" }
        return "EXISTS (SELECT 1 FROM metadata_objects mo JOIN metadata_tags mt ON mt.metadata_id = mo.id WHERE mo.entity_type = '${entityType}' AND mo.entity_id = ${entityIdExpr} AND ((position(':' IN mt.tag) > 0 AND ${nameExpr} LIKE ${patternExpr} ESCAPE '\\') OR ${tagExpr} LIKE ${patternExpr} ESCAPE '\\'))"
    }

    private static func buildTankoubonTextMatchCondition(
        pattern: String,
        params: ArrayList<String>,
        unaccentFunction: String
    ): String {
        params.add(pattern)
        params.add(pattern)
        params.add(pattern)
        let titleExpr = wrapSearchExpr("tankoubon_metadata.title", unaccentFunction)
        let summaryExpr = wrapSearchExpr("tankoubon_metadata.description", unaccentFunction)
        let idExpr = wrapSearchExpr("tb.tankoubon_id", unaccentFunction)
        let patternExpr = if (unaccentFunction.size > 0) { "${unaccentFunction}(?)" } else { "?" }
        return "(${titleExpr} LIKE ${patternExpr} ESCAPE '\\' OR ${summaryExpr} LIKE ${patternExpr} ESCAPE '\\' OR ${idExpr} LIKE ${patternExpr} ESCAPE '\\' OR " +
            buildMetadataTagLikeCondition(pattern, params, "tankoubon", "tb.tankoubon_id", unaccentFunction) + ")"
    }

    /**
     * 从搜索 token 中剥离 `$` 精确匹配后缀。
     * 约定：`xxx$` 表示对标签进行完全匹配（tag token 精确匹配）。
     */
    private static func stripExactSuffix(token: String): (String, Bool) {
        let t = token.trimAscii()
        if (t.size > 1 && t.endsWith("$")) {
            return (t[0..t.size - 1], true)
        }
        return (t, false)
    }

    private static func normalizeSearchTimeField(field: String): String {
        let normalized = field.trimAscii()
        if (normalized == "date_added" || normalized == "created_at") {
            return "created_at"
        }
        if (normalized == "release_at") {
            return "release_at"
        }
        if (normalized == "updated_at") {
            return "updated_at"
        }
        return "created_at"
    }

    private static func parseCategoryFilterValues(category: String): ArrayList<String> {
        var values = ArrayList<String>()
        var seen = HashMap<String, Bool>()
        for (rawValue in category.split(",")) {
            let normalized = rawValue.trimAscii()
            if (normalized.size == 0) {
                continue
            }
            let parsed = try { Int64.parse(normalized) } catch (_: Exception) { 0i64 }
            if (parsed <= 0i64) {
                continue
            }
            let key = parsed.toString()
            if (seen.contains(key)) {
                continue
            }
            seen[key] = true
            values.add(key)
        }
        return values
    }

    private static func appendCategoryFilter(whereConditions: ArrayList<String>, filterParams: ArrayList<String>, category: String) {
        let categoryValues = parseCategoryFilterValues(category)
        if (categoryValues.size > 0) {
            if (categoryValues.size == 1) {
                whereConditions.add("archive_metadata_search.category_id = ?")
                filterParams.add(categoryValues[0])
                return
            }

            var placeholders = ""
            for (i in 0..categoryValues.size) {
                if (i > 0) {
                    placeholders += ", "
                }
                placeholders += "?"
                filterParams.add(categoryValues[i])
            }
            whereConditions.add("archive_metadata_search.category_id IN (${placeholders})")
            return
        }

        // 当没有指定分类时，只搜索启用的分类
        whereConditions.add("EXISTS (SELECT 1 FROM categories c WHERE c.id = archive_metadata_search.category_id AND c.enabled = true)")
    }

    /**
     * 为 tags 构建“完全匹配单个 tag token”的条件（结构化查询）。
     * - token 含 namespace: 仅匹配该 namespace/name
     * - token 不含 namespace: 仅匹配 namespace 为空的 tag
     */
    private static func buildExactTagMatchCondition(tagToken: String, params: ArrayList<String>, tableAlias: String): String {
        let t = tagToken.trimAscii()
        if (t.contains(":")) {
            let idxOpt = t.indexOf(":")
            match (idxOpt) {
                case Some(idx) =>
                    let ns = if (idx > 0) { t[0..idx] } else { "" }
                    let name = if (idx + 1 < t.size) { t[idx + 1..t.size] } else { "" }
                    let namespaced = if (ns.size > 0) { "${ns}:${name}" } else { name }
                    params.add(namespaced)
                    return "EXISTS (SELECT 1 FROM metadata_objects mo JOIN metadata_tags mt ON mt.metadata_id = mo.id WHERE mo.entity_type = 'archive' AND mo.entity_id = ${tableAlias}.arcid AND mt.tag = ?)"
                case None => ()
            }
        }
        params.add(t)
        return "EXISTS (SELECT 1 FROM metadata_objects mo JOIN metadata_tags mt ON mt.metadata_id = mo.id WHERE mo.entity_type = 'archive' AND mo.entity_id = ${tableAlias}.arcid AND mt.tag = ?)"
    }

    private static func buildExactTagMatchConditionWithCandidates(
        tagToken: String,
        translatedTags: ArrayList<String>,
        params: ArrayList<String>,
        tableAlias: String
    ): String {
        var candidates: ArrayList<String> = ArrayList<String>()
        var seen: HashMap<String, Bool> = HashMap<String, Bool>()

        // 原 token
        if (tagToken.size > 0) {
            candidates.add(tagToken)
            seen[tagToken] = true
        }

        // 翻译命中标签（去重）
        for (t in translatedTags) {
            match (seen.get(t)) {
                case Some(_) => ()
                case None =>
                    candidates.add(t)
                    seen[t] = true
            }
        }

        var condition = "("
        for (i in 0..candidates.size) {
            if (i > 0) {
                condition += " OR "
            }
            condition += buildExactTagMatchCondition(candidates[i], params, tableAlias)
        }
        condition += ")"
        return condition
    }

    private static func collectTranslationLookupTerms(searchResult: SearchFilterResult): Array<String> {
        let collected = ArrayList<String>()
        let seen = HashMap<String, Bool>()

        func addToken(token: String): Unit {
            let (value, _) = stripExactSuffix(token)
            let normalized = value.trimAscii()
            if (normalized.size == 0 || seen.contains(normalized)) {
                return
            }
            seen[normalized] = true
            collected.add(normalized)
        }

        for (term in searchResult.terms) {
            addToken(term)
        }
        for (term in searchResult.exactTerms) {
            addToken(term)
        }
        for (term in searchResult.excludeTerms) {
            addToken(term)
        }

        return collected.toArray()
    }

    private static func preloadTranslatedTags(db: Database, searchResult: SearchFilterResult): HashMap<String, ArrayList<String>> {
        let terms = collectTranslationLookupTerms(searchResult)
        if (terms.size == 0) {
            return HashMap<String, ArrayList<String>>()
        }
        return TagDao.batchFindTagsByTranslationWithConn(db, terms)
    }

    private static func getPreloadedTranslatedTags(
        lookup: HashMap<String, ArrayList<String>>,
        termValue: String
    ): ArrayList<String> {
        let normalized = termValue.trimAscii()
        if (normalized.size == 0) {
            return ArrayList<String>()
        }
        match (lookup.get(normalized)) {
            case Some(found) => return found
            case None => return ArrayList<String>()
        }
    }

    /**
     * 构建 tags 模糊匹配条件（结构化查询）。
     * 同时匹配 name 与 namespace:name 两种形式。
     */
    private static func buildTagLikeCondition(pattern: String, params: ArrayList<String>, tableAlias: String, unaccentFunction: String): String {
        return buildMetadataTagLikeCondition(pattern, params, "archive", "${tableAlias}.arcid", unaccentFunction)
    }

    private static func ensureArchiveMetadataRoot(archiveId: String): Bool {
        let normalized = archiveId.trimAscii()
        if (normalized.size == 0) { return false }
        match (MetadataDao.getMetadataObject("archive", normalized)) {
            case Some(_) => return true
            case None => return MetadataDao.upsertRootMetadataObject("archive", normalized, "", "")
        }
    }

    /**
     * 将包含 `?` 与 `@@UID@@` 占位符的 SQL 转换为 csorm 的 `$1..$n` 形式，
     * 并按出现顺序消费 stringParams（每个 `?` 对应一个 vtext 参数），
     * `@@UID@@` 占位符则绑定 vint(userId)。
     * 返回 (替换后的 SQL, 参数数组)。
     */
    private static func substitutePlaceholders(sql: String, stringParams: ArrayList<String>, userId: Int64): (String, Array<Value>) {
        // 逐字节重写 SQL 流，必须用 ArrayList<UInt8> + String.fromUtf8：
        // StringBuilder.append(UInt8) 会把字节当整数追加其十进制文本（S → "83"），导致 SQL 数字化。
        let out = ArrayList<UInt8>()
        // 把 String 的字节批量追加进 out（占位符 $n 等已解码文本片段走这里）。
        func appendStr(s: String): Unit {
            for (b in s.toArray()) {
                out.add(b)
            }
        }
        var params = ArrayList<Value>()
        var strIdx = 0
        var n = 0
        var i = 0
        let bytes = sql.toArray()
        while (i < bytes.size) {
            let c = bytes[i]
            if (c == 63u8) {  // '?'
                n += 1
                appendStr("${'$'}${n.toString()}")
                if (strIdx < stringParams.size) {
                    params.add(vtext(stringParams[strIdx]))
                    strIdx += 1
                } else {
                    params.add(vnull())
                }
                i += 1
                continue
            }
            // 检测 `@@UID@@`
            if (c == 64u8 && i + 7 < bytes.size &&  // '@'
                bytes[i + 1] == 64u8 && bytes[i + 2] == 85u8 && bytes[i + 3] == 73u8 &&  // @UI
                bytes[i + 4] == 68u8 && bytes[i + 5] == 64u8 && bytes[i + 6] == 64u8) {  // D@@
                n += 1
                appendStr("${'$'}${n.toString()}")
                params.add(vint(userId))
                i += 7
                continue
            }
            out.add(c)
            i += 1
        }
        return (String.fromUtf8(out.toArray()), params.toArray())
    }

    /**
     * 获取所有归档
     */
    public static func getAllArchives(): Array<ArchiveData> {
        match (DatabaseConfig.getDatabase()) {
            case Some(db) =>
                try {
                    let sql = "SELECT arcid, title, filename, summary, thumbhash, cover_asset_id, created_at, updated_at, release_at, relative_path, file_size, pagecount, archive_type, category_id FROM archive_metadata_search ORDER BY id"
                    return db.raw<ArchiveData>(sql, Array<Value>(), { row =>
                        let archive = ArchiveData()
                        archive.id = row.getOrNullText(0) ?? ""
                        archive.title = row.getOrNullText(1) ?? ""
                        archive.filename = row.getOrNullText(2) ?? ""
                        archive.summary = row.getOrNullText(3) ?? ""
                        archive.thumbhash = row.getOrNullText(4) ?? ""
                        archive.cover_asset_id = row.getOrNullInt64(5) ?? 0
                        archive.created_at = row.getOrNullText(6) ?? ""
                        archive.updated_at = row.getOrNullText(7) ?? ""
                        archive.release_at = row.getOrNullText(8) ?? ""
                        archive.relative_path = row.getOrNullText(9) ?? ""
                        archive.file_size = row.getOrNullInt64(10) ?? 0
                        archive.pagecount = row.getOrNullInt32(11) ?? 0
                        archive.archive_type = row.getOrNullText(12) ?? "archive"
                        archive.category_id = row.getOrNullInt64(13) ?? 0
                        archive
                    })
                } catch (e: Exception) {
                    getLogger("archive_dao").error("查询归档失败", ("error", e.message))
                    return Array<ArchiveData>()
                }
            case None =>
                getLogger("archive_dao").error("无法连接到数据库")
                return Array<ArchiveData>()
        }
    }

    /**
     * 根据 ID 获取归档
     */
    public static func getArchiveById(id: String): ArchiveData {
        match (DatabaseConfig.getDatabase()) {
            case Some(db) =>
                try {
                    let sql = "SELECT arcid, title, filename, summary, thumbhash, cover_asset_id, created_at, updated_at, release_at, relative_path, file_size, pagecount, archive_type, category_id FROM archive_metadata_search WHERE arcid = $1"
                    let result = db.rawOne<ArchiveData>(sql, [vtext(id)], { row =>
                        let archive = ArchiveData()
                        archive.id = row.getOrNullText(0) ?? ""
                        archive.title = row.getOrNullText(1) ?? ""
                        archive.filename = row.getOrNullText(2) ?? ""
                        archive.summary = row.getOrNullText(3) ?? ""
                        archive.thumbhash = row.getOrNullText(4) ?? ""
                        archive.cover_asset_id = row.getOrNullInt64(5) ?? 0
                        archive.created_at = row.getOrNullText(6) ?? ""
                        archive.updated_at = row.getOrNullText(7) ?? ""
                        archive.release_at = row.getOrNullText(8) ?? ""
                        archive.relative_path = row.getOrNullText(9) ?? ""
                        archive.file_size = row.getOrNullInt64(10) ?? 0
                        archive.pagecount = row.getOrNullInt32(11) ?? 0
                        archive.archive_type = row.getOrNullText(12) ?? "archive"
                        archive.category_id = row.getOrNullInt64(13) ?? 0
                        archive
                    })
                    match (result) {
                        case Some(a) => return a
                        case None => return ArchiveData()
                    }
                } catch (e: Exception) {
                    getLogger("archive_dao").error("查询归档失败", ("error", e.message))
                    return ArchiveData()
                }
            case None =>
                getLogger("archive_dao").error("无法连接到数据库")
                return ArchiveData()
        }
    }

    /**
     * 批量根据 arcid 获取归档数据
     */
    public static func getBatchArchivesById(archiveIds: Array<String>): HashMap<String, ArchiveData> {
        let result = HashMap<String, ArchiveData>()
        if (archiveIds.size == 0) { return result }

        let deduped = ArrayList<String>()
        let seen = HashMap<String, Bool>()
        for (archiveId in archiveIds) {
            let id = archiveId.trimAscii()
            if (id.size == 0) { continue }
            match (seen.get(id)) {
                case Some(_) => ()
                case None =>
                    seen[id] = true
                    deduped.add(id)
            }
        }
        if (deduped.size == 0) { return result }

        match (DatabaseConfig.getDatabase()) {
            case Some(db) =>
                try {
                    var placeholders = ""
                    var params = ArrayList<Value>()
                    for (i in 0..deduped.size) {
                        if (i > 0) { placeholders += "," }
                        placeholders += "${'$'}${(i + 1).toString()}"
                        params.add(vtext(deduped[i]))
                    }
                    let sql = "SELECT arcid, id, title, filename, summary, thumbhash, cover_asset_id, created_at, updated_at, release_at, relative_path, file_size, pagecount, archive_type, category_id, tags FROM archive_metadata_search WHERE arcid IN (${placeholders})"
                    let rows = db.raw<ArchiveData>(sql, params.toArray(), { row =>
                        let archive = ArchiveData()
                        archive.id = row.getOrNullText(0) ?? ""
                        archive.internalId = row.getOrNullInt64(1) ?? 0
                        archive.title = row.getOrNullText(2) ?? ""
                        archive.filename = row.getOrNullText(3) ?? ""
                        archive.summary = row.getOrNullText(4) ?? ""
                        archive.thumbhash = row.getOrNullText(5) ?? ""
                        archive.cover_asset_id = row.getOrNullInt64(6) ?? 0
                        archive.created_at = row.getOrNullText(7) ?? ""
                        archive.updated_at = row.getOrNullText(8) ?? ""
                        archive.release_at = row.getOrNullText(9) ?? ""
                        archive.relative_path = row.getOrNullText(10) ?? ""
                        archive.file_size = row.getOrNullInt64(11) ?? 0
                        archive.pagecount = row.getOrNullInt32(12) ?? 0
                        archive.archive_type = row.getOrNullText(13) ?? "archive"
                        archive.category_id = row.getOrNullInt64(14) ?? 0
                        archive.tags = row.getOrNullText(15) ?? ""
                        if (archive.id.trimAscii().size > 0) {
                            result[archive.id] = archive
                        }
                        archive
                    })
                    // result 已在回调中填充
                    let _ = rows
                } catch (e: Exception) {
                    getLogger("archive_dao").error("批量查询归档失败", ("error", e.message))
                    return result
                }
            case None =>
                getLogger("archive_dao").error("无法连接到数据库")
        }

        return result
    }

    /**
     * 根据 arcid 获取 archives 表的内部 ID（INTEGER）
     */
    public static func getArchiveInternalId(arcid: String): Int64 {
        match (DatabaseConfig.getDatabase()) {
            case Some(db) =>
                try {
                    return db.rawOne<Int64>("SELECT id FROM archives WHERE arcid = $1", [vtext(arcid)], { row => row.getInt64(0) }) ?? 0
                } catch (e: Exception) {
                    getLogger("archive_dao").error("查询归档内部ID失败", ("error", e.message))
                    return 0
                }
            case None =>
                getLogger("archive_dao").error("无法连接到数据库")
                return 0
        }
    }

    /**
     * 搜索归档
     */
    public static func searchArchives(filter: String, category: String, start: Int32, count: Int32, sortby: String, order: String): (Array<ArchiveData>, Int64) {
        return searchArchives(filter, category, start, count, sortby, order, false, false, false, "", "", 0)
    }

    public static func searchArchives(filter: String, category: String, start: Int32, count: Int32, sortby: String, order: String, newOnly: Bool, untaggedOnly: Bool): (Array<ArchiveData>, Int64) {
        // 调用带 userId 的版本，userId=0 表示不进行用户级别的 newOnly 过滤
        return searchArchives(filter, category, start, count, sortby, order, newOnly, untaggedOnly, false, "", "", 0)
    }

    public static func searchArchives(filter: String, category: String, start: Int32, count: Int32, sortby: String, order: String, newOnly: Bool, untaggedOnly: Bool, userId: Int64): (Array<ArchiveData>, Int64) {
        return searchArchives(filter, category, start, count, sortby, order, newOnly, untaggedOnly, false, "", "", userId)
    }

    /**
     * 构建相关度评分 SQL 表达式
     * 只对普通搜索词计算相关度
     * 精确短语、精确标签、排除词等是硬性过滤条件，不参与相关度计算
     * @param filter 搜索词
     * @return 相关度评分表达式字符串
     */
    private static func buildRelevanceExpr(filter: String, tablePrefix: String, unaccentFunction: String): String {
        // 使用 SearchFilter 解析搜索语法
        let searchResult = SearchFilter.parse(filter)

        // 只有普通搜索词参与相关度计算
        var relevanceTerms: ArrayList<String> = ArrayList<String>()
        for (term in searchResult.terms) {
            let (_, isExactTag) = stripExactSuffix(term)
            if (!isExactTag) {
                relevanceTerms.add(term)
            }
        }

        if (relevanceTerms.size == 0) {
            return "1"  // 无普通搜索词时返回常量
        }

        // 构建 ILIKE 条件用于评分
        var ilikeScoreExpr = "0"
        for (term in relevanceTerms) {
            let escapedTerm = term.replace("'", "''")
            let pattern = "'%" + escapedTerm + "%'"
            let patternExpr = if (unaccentFunction.size > 0) { "${unaccentFunction}(${pattern})" } else { pattern }
            ilikeScoreExpr = ilikeScoreExpr + " + CASE WHEN " + wrapSearchExpr(tablePrefix + "title", unaccentFunction) + " ILIKE " + patternExpr + " THEN 0.15 ELSE 0 END"
            ilikeScoreExpr = ilikeScoreExpr + " + CASE WHEN " + wrapSearchExpr(tablePrefix + "filename", unaccentFunction) + " ILIKE " + patternExpr + " THEN 0.1 ELSE 0 END"
            ilikeScoreExpr = ilikeScoreExpr + " + CASE WHEN " + wrapSearchExpr(tablePrefix + "tags", unaccentFunction) + " ILIKE " + patternExpr + " THEN 0.05 ELSE 0 END"
        }

        // 构建用于全文搜索的查询字符串
        var tsQueryTerms: ArrayList<String> = ArrayList<String>()
        for (term in relevanceTerms) {
            tsQueryTerms.add(term.replace("'", "''"))
        }
        let tsQueryStr = String.join(tsQueryTerms.toArray(), delimiter: " ")

        // 构建完整的评分表达式（全文搜索 + ILIKE 匹配）
        let relevanceExpr = "COALESCE(ts_rank(" + tablePrefix + "search_tsv, websearch_to_tsquery('simple', '" + tsQueryStr + "')) * 2, 0) + (" + ilikeScoreExpr + ")"

        return relevanceExpr
    }

    private static func buildTankoubonRelevanceExpr(filter: String, unaccentFunction: String): String {
        let searchResult = SearchFilter.parse(filter)
        var relevanceTerms: ArrayList<String> = ArrayList<String>()
        for (term in searchResult.terms) {
            let (_, isExactTag) = stripExactSuffix(term)
            if (!isExactTag) {
                relevanceTerms.add(term)
            }
        }

        if (relevanceTerms.size == 0) {
            return "0"
        }

        var expr = "0"
        for (term in relevanceTerms) {
            let escapedTerm = term.replace("'", "''")
            let pattern = "'%" + escapedTerm + "%'"
            let patternExpr = if (unaccentFunction.size > 0) { "${unaccentFunction}(${pattern})" } else { pattern }
            expr = expr + " + CASE WHEN " + wrapSearchExpr("tankoubon_metadata.title", unaccentFunction) + " ILIKE " + patternExpr + " THEN 0.35 ELSE 0 END"
            expr = expr + " + CASE WHEN " + wrapSearchExpr("tankoubon_metadata.description", unaccentFunction) + " ILIKE " + patternExpr + " THEN 0.12 ELSE 0 END"
            expr = expr + " + CASE WHEN " + wrapSearchExpr("tb.tankoubon_id", unaccentFunction) + " ILIKE " + patternExpr + " THEN 0.08 ELSE 0 END"
            expr = expr + " + CASE WHEN EXISTS (SELECT 1 FROM metadata_objects mo JOIN metadata_tags mt ON mt.metadata_id = mo.id WHERE mo.entity_type = 'tankoubon' AND mo.entity_id = tb.tankoubon_id AND " + wrapSearchExpr("mt.tag", unaccentFunction) + " ILIKE " + patternExpr + ") THEN 0.08 ELSE 0 END"
        }
        return expr
    }

    public static func searchArchives(filter: String, category: String, start: Int32, count: Int32, sortby: String, order: String, newOnly: Bool, untaggedOnly: Bool, favoriteOnly: Bool, dateFrom: String, dateTo: String, userId: Int64): (Array<ArchiveData>, Int64) {
        return searchArchives(filter, category, start, count, sortby, order, newOnly, untaggedOnly, favoriteOnly, dateFrom, dateTo, userId, "")
    }

    public static func searchArchives(filter: String, category: String, start: Int32, count: Int32, sortby: String, order: String, newOnly: Bool, untaggedOnly: Bool, favoriteOnly: Bool, dateFrom: String, dateTo: String, userId: Int64, tankoubonId: String): (Array<ArchiveData>, Int64) {
        match (DatabaseConfig.getDatabase()) {
            case Some(db) =>
                var archives: ArrayList<ArchiveData> = ArrayList<ArchiveData>()
                try {
                    getLogger("archive_dao").debug("开始搜索归档",
                                           ("filter", filter),
                                           ("category", category),
                                           ("start", start.toString()),
                                           ("count", count.toString()),
                                           ("sortby", sortby),
                                           ("order", order),
                                           ("newOnly", newOnly.toString()),
                                           ("untaggedOnly", untaggedOnly.toString()))

                    let resolvedDateField = normalizeSearchTimeField(sortby)

                    // 首先获取总记录数
                    var countSql = "SELECT COUNT(*) FROM archive_metadata_search"
                    var whereConditions: ArrayList<String> = ArrayList<String>()

                    // 解析搜索过滤器
                    let searchResult = SearchFilter.parse(filter)
                    var filterParams: ArrayList<String> = ArrayList<String>()

                    getLogger("archive_dao").info("搜索过滤器解析结果",
                        ("filter", filter),
                        ("terms", searchResult.terms.size.toString()))
                    let unaccentFunction = getUnaccentFunction(db)
                    let translatedTagsLookup = preloadTranslatedTags(db, searchResult)

                    // 处理普通搜索词（支持通配符和翻译搜索）
                    if (searchResult.terms.size > 0) {
                        var termConditions: ArrayList<String> = ArrayList<String>()
                        for (term in searchResult.terms) {
                            let (termValue, isExactTag) = stripExactSuffix(term)
                            if (termValue.size == 0) {
                                continue
                            }

                            // `$`：标签完全匹配（硬性过滤条件，不参与 OR 相关度）
                            if (isExactTag) {
                                whereConditions.add(buildExactTagMatchConditionWithCandidates(
                                    termValue,
                                    getPreloadedTranslatedTags(translatedTagsLookup, termValue),
                                    filterParams,
                                    "archive_metadata_search"
                                ))
                                continue
                            }

                            let pattern = SearchFilter.toLikePattern(termValue)
                            var fieldCondition = buildArchiveTextMatchCondition(pattern, filterParams, "archive_metadata_search", unaccentFunction)

                            // 查询翻译匹配的标签，添加 OR 条件
                            let translatedTags = getPreloadedTranslatedTags(translatedTagsLookup, termValue)
                            for (tagName in translatedTags) {
                                fieldCondition += " OR " + buildTagLikeCondition("%" + tagName + "%", filterParams, "archive_metadata_search", unaccentFunction)
                            }

                            fieldCondition += ")"
                            termConditions.add(fieldCondition)
                        }
                        if (termConditions.size > 0) {
                            var combined = ""
                            for (i in 0..termConditions.size) {
                                if (i > 0) {
                                    combined += " OR "
                                }
                                combined += termConditions[i]
                            }
                            whereConditions.add("(" + combined + ")")
                        }
                    }

                    // 处理精确短语（引号内的内容，支持翻译搜索）
                    if (searchResult.exactTerms.size > 0) {
                        for (phrase in searchResult.exactTerms) {
                            let (phraseValue, isExactTag) = stripExactSuffix(phrase)
                            if (phraseValue.size == 0) {
                                continue
                            }

                            // `"xxx$"` 且不包含空格时，按标签完全匹配处理
                            if (isExactTag && !phraseValue.contains(" ")) {
                                whereConditions.add(buildExactTagMatchConditionWithCandidates(
                                    phraseValue,
                                    getPreloadedTranslatedTags(translatedTagsLookup, phraseValue),
                                    filterParams,
                                    "archive_metadata_search"
                                ))
                                continue
                            }

                            let pattern = SearchFilter.toLikePattern(phraseValue)
                            var fieldCondition = buildArchiveTextMatchCondition(pattern, filterParams, "archive_metadata_search", unaccentFunction)

                            // 查询翻译匹配的标签
                            let translatedTags = getPreloadedTranslatedTags(translatedTagsLookup, phraseValue)
                            for (tagName in translatedTags) {
                                fieldCondition += " OR " + buildTagLikeCondition("%" + tagName + "%", filterParams, "archive_metadata_search", unaccentFunction)
                            }

                            fieldCondition += ")"
                            whereConditions.add(fieldCondition)
                        }
                    }

                    // 处理排除词（支持翻译搜索）
                    if (searchResult.excludeTerms.size > 0) {
                        for (excludeTerm in searchResult.excludeTerms) {
                            let (excludeValue, isExactTag) = stripExactSuffix(excludeTerm)
                            if (excludeValue.size == 0) {
                                continue
                            }

                            // `-xxx$`：排除包含该精确标签的归档
                            if (isExactTag) {
                                whereConditions.add("NOT " + buildExactTagMatchConditionWithCandidates(
                                    excludeValue,
                                    getPreloadedTranslatedTags(translatedTagsLookup, excludeValue),
                                    filterParams,
                                    "archive_metadata_search"
                                ))
                                continue
                            }

                            let pattern = SearchFilter.toLikePattern(excludeValue)
                            var fieldCondition = buildArchiveTextMatchCondition(pattern, filterParams, "archive_metadata_search", unaccentFunction)

                            // 查询翻译匹配的标签
                            let translatedTags = getPreloadedTranslatedTags(translatedTagsLookup, excludeValue)
                            for (tagName in translatedTags) {
                                fieldCondition += " OR " + buildTagLikeCondition("%" + tagName + "%", filterParams, "archive_metadata_search", unaccentFunction)
                            }

                            fieldCondition += ")"
                            whereConditions.add("NOT " + fieldCondition)
                        }
                    }

                    // newOnly 过滤 - 使用用户级别的已读状态
                    // 当 newOnly=true 且 userId > 0 时，排除用户已读的归档
                    if (newOnly && userId > 0) {
                        // 排除用户已读的归档（is_new = false 的记录）
                        // 使用子查询：排除在 user_archive_status 表中 is_new = false 的归档
                        whereConditions.add("NOT EXISTS (SELECT 1 FROM user_archive_status uas JOIN archives a ON a.id = uas.archive_id WHERE a.arcid = archive_metadata_search.arcid AND uas.user_id = @@UID@@ AND uas.is_new = false)")
                    }

                    // 按 lastread 排序时，移除从未阅读的记录
                    // 根据 API 文档："If you sort by lastread, IDs that have never been read will be removed from the search."
                    // 使用 user_archive_status 表判断用户是否阅读过（is_new = false 表示已读）
                    // 注意：未登录用户会被重定向到登录页，所以这里只处理已登录用户
                    if ((sortby == "lastread" || sortby == "lastreadtime") && userId > 0) {
                        // 只显示用户已读的档案（在 user_archive_status 表中有记录且 is_new = false）
                        whereConditions.add("EXISTS (SELECT 1 FROM user_archive_status uas JOIN archives a ON a.id = uas.archive_id WHERE a.arcid = archive_metadata_search.arcid AND uas.user_id = @@UID@@ AND uas.is_new = false)")
                    }

                    // 添加无标签过滤条件
                    if (untaggedOnly) {
                        whereConditions.add("NOT EXISTS (SELECT 1 FROM metadata_objects mo JOIN metadata_tags mt ON mt.metadata_id = mo.id WHERE mo.entity_type = 'archive' AND mo.entity_id = archive_metadata_search.arcid)")
                    }

                    // favoriteOnly 过滤 - 只显示用户收藏的档案
                    // 当 favoriteOnly=true 且 userId > 0 时，只返回用户收藏的归档
                    if (favoriteOnly && userId > 0) {
                        whereConditions.add("EXISTS (SELECT 1 FROM user_favorites uf JOIN archives a ON a.id = uf.archive_id WHERE a.arcid = archive_metadata_search.arcid AND uf.user_id = @@UID@@)")
                    }

                    // 分类过滤
                    appendCategoryFilter(whereConditions, filterParams, category)

                    // tankoubon_id 过滤 - 只返回某个合集中的归档
                    if (tankoubonId.size > 0) {
                        whereConditions.add("EXISTS (SELECT 1 FROM tankoubons t JOIN tankoubon_archives ta ON ta.tankoubon_id = t.id WHERE t.tankoubon_id = ? AND ta.archive_id = archive_metadata_search.id)")
                        filterParams.add(tankoubonId)
                    }

                    // 日期范围过滤
                    if (dateFrom.size > 0) {
                        whereConditions.add("${resolvedDateField} >= ?")
                        filterParams.add(dateFrom)
                    }
                    if (dateTo.size > 0) {
                        whereConditions.add("${resolvedDateField} <= ?")
                        filterParams.add(dateTo + " 23:59:59")
                    }

                    // 构建相关度评分表达式。
                    // 优化：当存在 relevance 时，在 SQL 内部用 CTE 计算一次 relevance_score，
                    // 然后复用于阈值过滤/排序，避免重复拼接/重复计算表达式。
                    let relevanceExpr = buildRelevanceExpr(filter, "", unaccentFunction)
                    let hasRelevance = filter.size > 0 && relevanceExpr != "1"
                    let minRelevanceThreshold = 0.05  // 最低相关度阈值

                    // 组合基础 WHERE（不包含相关度阈值）
                    var baseWhereClause = ""
                    for (i in 0..whereConditions.size) {
                        if (i > 0) {
                            baseWhereClause += " AND "
                        }
                        baseWhereClause += whereConditions[i]
                    }

                    // 构建计数 SQL
                    if (!hasRelevance) {
                        if (baseWhereClause.size > 0) {
                            countSql += " WHERE " + baseWhereClause
                        }
                    } else {
                        // relevance_score 只在本语句内计算一次
                        countSql = "WITH base AS (SELECT (" + relevanceExpr + ") AS relevance_score FROM archive_metadata_search"
                        if (baseWhereClause.size > 0) {
                            countSql += " WHERE " + baseWhereClause
                        }
                        countSql += ") SELECT COUNT(*) FROM base WHERE relevance_score >= " + minRelevanceThreshold.toString()
                    }

                    getLogger("archive_dao").debug("执行计数SQL", ("sql", countSql))
                    let (boundCountSql, countParams) = substitutePlaceholders(countSql, filterParams, userId)
                    var totalCount: Int64 = 0
                    match (db.rawOne<Int64>(boundCountSql, countParams, { row => row.getInt64(0) })) {
                        case Some(c) =>
                            totalCount = c
                            getLogger("archive_dao").debug("获取到总记录数", ("count", totalCount.toString()))
                        case None =>
                            getLogger("archive_dao").error("无法获取总记录数")
                    }

                    // 然后查询分页数据
                    var sql = ""
                    var orderJoinPrefix: ArrayList<String> = ArrayList<String>()
                    if (!hasRelevance) {
                        // 无 relevance：保持原查询形态
                        sql = "SELECT archive_metadata_search.id, archive_metadata_search.arcid, archive_metadata_search.filename, archive_metadata_search.title, archive_metadata_search.summary, archive_metadata_search.thumbhash, archive_metadata_search.cover_asset_id, archive_metadata_search.created_at, archive_metadata_search.updated_at, archive_metadata_search.release_at, archive_metadata_search.relative_path, archive_metadata_search.file_size, archive_metadata_search.pagecount, archive_metadata_search.archive_type, archive_metadata_search.tags FROM archive_metadata_search"
                        if (sortby == "tank_order" && tankoubonId.size > 0) {
                            sql += " LEFT JOIN tankoubons t_order ON t_order.tankoubon_id = ?"
                            sql += " LEFT JOIN tankoubon_archives ta_order ON ta_order.tankoubon_id = t_order.id AND ta_order.archive_id = archive_metadata_search.id"
                            orderJoinPrefix.add(tankoubonId)
                        }
                        if (baseWhereClause.size > 0) {
                            sql += " WHERE " + baseWhereClause
                        }
                    } else {
                        // 有 relevance：在 base CTE 里计算 relevance_score，并在外层应用阈值过滤
                        sql = "WITH base AS (SELECT archive_metadata_search.id, archive_metadata_search.arcid, archive_metadata_search.filename, archive_metadata_search.title, archive_metadata_search.summary, archive_metadata_search.thumbhash, archive_metadata_search.cover_asset_id, archive_metadata_search.created_at, archive_metadata_search.updated_at, archive_metadata_search.release_at, archive_metadata_search.relative_path, archive_metadata_search.file_size, archive_metadata_search.pagecount, archive_metadata_search.archive_type, archive_metadata_search.tags, (" + relevanceExpr + ") AS relevance_score"
                        if (sortby == "tank_order" && tankoubonId.size > 0) {
                            sql += ", ta_order.sort_order AS tank_sort_order"
                        }
                        sql += " FROM archive_metadata_search"
                        if (sortby == "tank_order" && tankoubonId.size > 0) {
                            sql += " LEFT JOIN tankoubons t_order ON t_order.tankoubon_id = ?"
                            sql += " LEFT JOIN tankoubon_archives ta_order ON ta_order.tankoubon_id = t_order.id AND ta_order.archive_id = archive_metadata_search.id"
                            orderJoinPrefix.add(tankoubonId)
                        }
                        if (baseWhereClause.size > 0) {
                            sql += " WHERE " + baseWhereClause
                        }
                        sql += ") SELECT id, arcid, filename, title, summary, thumbhash, cover_asset_id, created_at, updated_at, release_at, relative_path, file_size, pagecount, archive_type, tags FROM base WHERE relevance_score >= " + minRelevanceThreshold.toString()
                    }

                    // 处理排序参数
                    if (sortby == "RANDOM()") {
                        // 对于随机排序，使用 RANDOM() 函数
                        // 为了确保每次查询都有不同的随机结果，使用 ORDER BY RANDOM() DESC
                        // 这样可以避免某些数据库版本中 RANDOM() 的缓存问题
                        sql += " ORDER BY RANDOM() DESC"  // 使用 DESC 以获得更好的随机分布
                    } else if (sortby == "title") {
                        let orderDirection = if (order == "desc") { "DESC" } else { "ASC" }
                        sql += " ORDER BY title ${orderDirection}"
                    } else if ((sortby == "lastread" || sortby == "lastreadtime") && userId > 0) {
                        // 按用户最后阅读时间排序，使用 user_archive_status.updated_at
                        let orderDirection = if (order == "desc") { "DESC" } else { "ASC" }
                        sql += " ORDER BY (SELECT MAX(uas.updated_at) FROM user_archive_status uas JOIN (SELECT id, arcid AS archive_arcid FROM archives) a ON a.id = uas.archive_id WHERE a.archive_arcid = arcid AND uas.user_id = @@UID@@) ${orderDirection}"
                    } else if (sortby == "date_added" || sortby == "created_at") {
                        let orderDirection = if (order == "desc") { "DESC" } else { "ASC" }
                        sql += " ORDER BY created_at ${orderDirection}"
                    } else if (sortby == "release_at") {
                        let orderDirection = if (order == "desc") { "DESC" } else { "ASC" }
                        sql += " ORDER BY release_at ${orderDirection}"
                    } else if (sortby == "updated_at") {
                        let orderDirection = if (order == "desc") { "DESC" } else { "ASC" }
                        sql += " ORDER BY updated_at ${orderDirection}"
                    } else if (sortby == "pagecount") {
                        let orderDirection = if (order == "desc") { "DESC" } else { "ASC" }
                        sql += " ORDER BY pagecount ${orderDirection}"
                    } else if (sortby == "tank_order" && tankoubonId.size > 0) {
                        let orderDirection = if (order == "desc") { "DESC" } else { "ASC" }
                        let orderExpr = if (hasRelevance) { "tank_sort_order" } else { "ta_order.sort_order" }
                        sql += " ORDER BY ${orderExpr} ${orderDirection} NULLS LAST, created_at DESC"
                    } else if (sortby == "size") {
                        let orderDirection = if (order == "desc") { "DESC" } else { "ASC" }
                        sql += " ORDER BY file_size ${orderDirection}"
                    } else if (sortby == "relevance" && filter.size > 0 && relevanceExpr != "1") {
                        // 相关度排序：使用 CTE 内计算的 relevance_score（避免重复计算表达式）
                        if (hasRelevance) {
                            sql += " ORDER BY relevance_score DESC, created_at DESC"
                        } else {
                            sql += " ORDER BY created_at DESC"
                        }
                    } else {
                        // 默认按标题排序
                        let orderDirection = if (order == "desc") { "DESC" } else { "ASC" }
                        sql += " ORDER BY title ${orderDirection}"
                    }

                    // start=-1 时不添加 LIMIT/OFFSET，返回全部数据
                    if (start >= 0) {
                        sql += " LIMIT ${count} OFFSET ${start}"
                    }

                    // 打印SQL语句用于调试
                    getLogger("archive_dao").debug("执行数据SQL", ("sql", sql))
                    getLogger("archive_dao").debug("SQL参数", ("filter", filter), ("start", start.toString()), ("count", count.toString()))

                    // 合并 orderJoinPrefix（出现在 SQL 文本最前面）与 filterParams
                    var allStringParams = ArrayList<String>()
                    for (i in 0..orderJoinPrefix.size) {
                        allStringParams.add(orderJoinPrefix[i])
                    }
                    for (i in 0..filterParams.size) {
                        allStringParams.add(filterParams[i])
                    }
                    let (boundSql, dataParams) = substitutePlaceholders(sql, allStringParams, userId)

                    let rows = db.raw<ArchiveData>(boundSql, dataParams, { row =>
                        let archive = ArchiveData()
                        archive.internalId = row.getOrNullInt64(0) ?? 0
                        archive.id = row.getOrNullText(1) ?? ""
                        archive.filename = row.getOrNullText(2) ?? ""
                        archive.title = row.getOrNullText(3) ?? ""
                        archive.summary = row.getOrNullText(4) ?? ""
                        archive.thumbhash = row.getOrNullText(5) ?? ""
                        archive.cover_asset_id = row.getOrNullInt64(6) ?? 0
                        archive.created_at = row.getOrNullText(7) ?? ""
                        archive.updated_at = row.getOrNullText(8) ?? ""
                        archive.release_at = row.getOrNullText(9) ?? ""
                        archive.relative_path = row.getOrNullText(10) ?? ""
                        archive.file_size = row.getOrNullInt64(11) ?? 0
                        archive.pagecount = row.getOrNullInt32(12) ?? 0
                        archive.archive_type = row.getOrNullText(13) ?? "archive"
                        archive.tags = row.getOrNullText(14) ?? ""
                        archive
                    })
                    for (a in rows) {
                        archives.add(a)
                    }

                    let resultArray = archives.toArray()
                    getLogger("archive_dao").info("查询完成", ("records", resultArray.size.toString()), ("total_count", totalCount.toString()))
                    return (resultArray, totalCount)
                } catch (e: Exception) {
                    getLogger("archive_dao").error("搜索归档失败", ("error", e.message))
                    return (Array<ArchiveData>(), 0)
                }
            case None =>
                getLogger("archive_dao").error("无法连接到数据库")
                return (Array<ArchiveData>(), 0)
        }
    }

    /**
     * Search archives but return a grouped list when groupby_tanks=true:
     * - For each tankoubon, only the best (by current sort) representative archive is used for ordering.
     * - Returned rows include `group_item_type` and `group_item_id` so the caller can emit either
     *   a tankoubon item or an archive item without scanning all results in memory.
     *
     * This avoids the old behavior in SearchController that used start=-1 (no LIMIT/OFFSET) +
     * getArchiveTankoubonMapping(IN huge list), which becomes very slow on large datasets.
     */
    public static func searchArchivesGrouped(
        filter: String,
        category: String,
        start: Int32,
        count: Int32,
        sortby: String,
        order: String,
        newOnly: Bool,
        untaggedOnly: Bool,
        favoriteOnly: Bool,
        dateFrom: String,
        dateTo: String,
        userId: Int64,
        tankoubonId: String
    ): (Array<ArchiveData>, Int64) {
        match (DatabaseConfig.getDatabase()) {
            case Some(db) =>
                var archives: ArrayList<ArchiveData> = ArrayList<ArchiveData>()
                try {
                    getLogger("archive_dao").debug("开始分组搜索归档(groupby_tanks)",
                        ("filter", filter),
                        ("category", category),
                        ("start", start.toString()),
                        ("count", count.toString()),
                        ("sortby", sortby),
                        ("order", order),
                        ("newOnly", newOnly.toString()),
                        ("untaggedOnly", untaggedOnly.toString()))

                    let resolvedDateField = normalizeSearchTimeField(sortby)

                    // Build WHERE conditions (mostly copied from searchArchives to keep semantics identical).
                    var whereConditions: ArrayList<String> = ArrayList<String>()
                    let searchResult = SearchFilter.parse(filter)
                    var filterParams: ArrayList<String> = ArrayList<String>()
                    let unaccentFunction = getUnaccentFunction(db)
                    let translatedTagsLookup = preloadTranslatedTags(db, searchResult)

                    // 处理普通搜索词（支持通配符和翻译搜索）
                    if (searchResult.terms.size > 0) {
                        var termConditions: ArrayList<String> = ArrayList<String>()
                        for (term in searchResult.terms) {
                            let (termValue, isExactTag) = stripExactSuffix(term)
                            if (termValue.size == 0) { continue }

                            // `$`：标签完全匹配（硬性过滤条件，不参与 OR 相关度）
                            if (isExactTag) {
                                whereConditions.add(buildExactTagMatchConditionWithCandidates(
                                    termValue,
                                    getPreloadedTranslatedTags(translatedTagsLookup, termValue),
                                    filterParams,
                                    "archive_metadata_search"
                                ))
                                continue
                            }

                            let pattern = SearchFilter.toLikePattern(termValue)
                            var fieldCondition = buildArchiveTextMatchCondition(pattern, filterParams, "archive_metadata_search", unaccentFunction)

                            let translatedTags = getPreloadedTranslatedTags(translatedTagsLookup, termValue)
                            for (tagName in translatedTags) {
                                fieldCondition += " OR " + buildTagLikeCondition("%" + tagName + "%", filterParams, "archive_metadata_search", unaccentFunction)
                            }

                            fieldCondition += ")"
                            let tankCondition = buildTankoubonTextMatchCondition(pattern, filterParams, unaccentFunction)
                            termConditions.add("(" + fieldCondition + " OR " + tankCondition + ")")
                        }
                        if (termConditions.size > 0) {
                            var combined = ""
                            for (i in 0..termConditions.size) {
                                if (i > 0) { combined += " OR " }
                                combined += termConditions[i]
                            }
                            whereConditions.add("(" + combined + ")")
                        }
                    }

                    // 处理精确短语（引号内的内容，支持翻译搜索）
                    if (searchResult.exactTerms.size > 0) {
                        for (phrase in searchResult.exactTerms) {
                            let (phraseValue, isExactTag) = stripExactSuffix(phrase)
                            if (phraseValue.size == 0) { continue }

                            // `"xxx$"` 且不包含空格时，按标签完全匹配处理
                            if (isExactTag && !phraseValue.contains(" ")) {
                                whereConditions.add(buildExactTagMatchConditionWithCandidates(
                                    phraseValue,
                                    getPreloadedTranslatedTags(translatedTagsLookup, phraseValue),
                                    filterParams,
                                    "archive_metadata_search"
                                ))
                                continue
                            }

                            let pattern = SearchFilter.toLikePattern(phraseValue)
                            var fieldCondition = buildArchiveTextMatchCondition(pattern, filterParams, "archive_metadata_search", unaccentFunction)

                            let translatedTags = getPreloadedTranslatedTags(translatedTagsLookup, phraseValue)
                            for (tagName in translatedTags) {
                                fieldCondition += " OR " + buildTagLikeCondition("%" + tagName + "%", filterParams, "archive_metadata_search", unaccentFunction)
                            }

                            fieldCondition += ")"
                            let tankCondition = buildTankoubonTextMatchCondition(pattern, filterParams, unaccentFunction)
                            whereConditions.add("(" + fieldCondition + " OR " + tankCondition + ")")
                        }
                    }

                    // 处理排除词（支持翻译搜索）
                    if (searchResult.excludeTerms.size > 0) {
                        for (excludeTerm in searchResult.excludeTerms) {
                            let (excludeValue, isExactTag) = stripExactSuffix(excludeTerm)
                            if (excludeValue.size == 0) { continue }

                            // `-xxx$`：排除包含该精确标签的归档
                            if (isExactTag) {
                                whereConditions.add("NOT " + buildExactTagMatchConditionWithCandidates(
                                    excludeValue,
                                    getPreloadedTranslatedTags(translatedTagsLookup, excludeValue),
                                    filterParams,
                                    "archive_metadata_search"
                                ))
                                continue
                            }

                            let pattern = SearchFilter.toLikePattern(excludeValue)
                            var fieldCondition = buildArchiveTextMatchCondition(pattern, filterParams, "archive_metadata_search", unaccentFunction)

                            let translatedTags = getPreloadedTranslatedTags(translatedTagsLookup, excludeValue)
                            for (tagName in translatedTags) {
                                fieldCondition += " OR " + buildTagLikeCondition("%" + tagName + "%", filterParams, "archive_metadata_search", unaccentFunction)
                            }

                            fieldCondition += ")"
                            let tankCondition = buildTankoubonTextMatchCondition(pattern, filterParams, unaccentFunction)
                            whereConditions.add("NOT (" + fieldCondition + " OR " + tankCondition + ")")
                        }
                    }

                    // newOnly 过滤 - 使用用户级别的已读状态
                    if (newOnly && userId > 0) {
                        whereConditions.add("NOT EXISTS (SELECT 1 FROM user_archive_status uas JOIN archives a ON a.id = uas.archive_id WHERE a.arcid = archive_metadata_search.arcid AND uas.user_id = @@UID@@ AND uas.is_new = false)")
                    }

                    // 按 lastread 排序时，移除从未阅读的记录
                    if ((sortby == "lastread" || sortby == "lastreadtime") && userId > 0) {
                        whereConditions.add("EXISTS (SELECT 1 FROM user_archive_status uas JOIN archives a ON a.id = uas.archive_id WHERE a.arcid = archive_metadata_search.arcid AND uas.user_id = @@UID@@ AND uas.is_new = false)")
                    }

                    if (untaggedOnly) {
                        whereConditions.add("NOT EXISTS (SELECT 1 FROM metadata_objects mo JOIN metadata_tags mt ON mt.metadata_id = mo.id WHERE mo.entity_type = 'archive' AND mo.entity_id = archive_metadata_search.arcid)")
                    }

                    if (favoriteOnly && userId > 0) {
                        whereConditions.add("EXISTS (SELECT 1 FROM user_favorites uf JOIN archives a ON a.id = uf.archive_id WHERE a.arcid = archive_metadata_search.arcid AND uf.user_id = @@UID@@)")
                    }

                    appendCategoryFilter(whereConditions, filterParams, category)

                    if (tankoubonId.size > 0) {
                        whereConditions.add("EXISTS (SELECT 1 FROM tankoubons t JOIN tankoubon_archives ta ON ta.tankoubon_id = t.id WHERE t.tankoubon_id = ? AND ta.archive_id = archive_metadata_search.id)")
                        filterParams.add(tankoubonId)
                    }

                    if (dateFrom.size > 0) {
                        whereConditions.add("archive_metadata_search.${resolvedDateField} >= ?")
                        filterParams.add(dateFrom)
                    }
                    if (dateTo.size > 0) {
                        whereConditions.add("archive_metadata_search.${resolvedDateField} <= ?")
                        filterParams.add(dateTo + " 23:59:59")
                    }

                    let archiveRelevanceExpr = buildRelevanceExpr(filter, "archive_metadata_search.", unaccentFunction)
                    let tankRelevanceExpr = buildTankoubonRelevanceExpr(filter, unaccentFunction)
                    let relevanceExpr = if (archiveRelevanceExpr == "1") {
                        "1"
                    } else {
                        "(" + archiveRelevanceExpr + ") + (" + tankRelevanceExpr + ")"
                    }
                    let minRelevanceThreshold = 0.05

                    var whereClause = ""
                    if (whereConditions.size > 0 || filter.size > 0) {
                        for (i in 0..whereConditions.size) {
                            if (i > 0) { whereClause += " AND " }
                            whereClause += whereConditions[i]
                        }
                        if (filter.size > 0 && relevanceExpr != "1") {
                            if (whereClause.size > 0) { whereClause += " AND " }
                            whereClause += "(" + relevanceExpr + ") >= " + minRelevanceThreshold.toString()
                        }
                    }

                    // Count distinct groups (tankoubon_id or arcid).
                    var countSql = """
                        SELECT COUNT(DISTINCT COALESCE(tb.tankoubon_id, archive_metadata_search.arcid))
                        FROM archive_metadata_search
                        LEFT JOIN tankoubon_archives tba ON tba.archive_id = archive_metadata_search.id
                        LEFT JOIN tankoubons tb ON tb.id = tba.tankoubon_id
                        LEFT JOIN metadata_objects tankoubon_metadata
                               ON tankoubon_metadata.entity_type = 'tankoubon'
                              AND tankoubon_metadata.entity_id = tb.tankoubon_id
                    """
                    if (whereClause.size > 0) {
                        countSql += " WHERE " + whereClause
                    }

                    getLogger("archive_dao").debug("执行分组计数SQL", ("sql", countSql))
                    let (boundCountSql, countParams) = substitutePlaceholders(countSql, filterParams, userId)
                    var totalGroups: Int64 = 0
                    match (db.rawOne<Int64>(boundCountSql, countParams, { row => row.getInt64(0) })) {
                        case Some(c) => totalGroups = c
                        case None => ()
                    }

                    // Build ORDER BY for representative row selection (must match ungrouped search ordering).
                    var windowOrderBy = ""
                    var finalOrderBy = ""
                    var orderJoinPrefix: ArrayList<String> = ArrayList<String>()
                    if (sortby == "RANDOM()") {
                        windowOrderBy = "RANDOM() DESC"
                        finalOrderBy = "RANDOM() DESC"
                    } else if (sortby == "title") {
                        let dir = if (order == "desc") { "DESC" } else { "ASC" }
                        windowOrderBy = "title ${dir}"
                        finalOrderBy = "title ${dir}"
                    } else if ((sortby == "lastread" || sortby == "lastreadtime") && userId > 0) {
                        let dir = if (order == "desc") { "DESC" } else { "ASC" }
                        let windowExpr = "(SELECT MAX(uas.updated_at) FROM user_archive_status uas JOIN (SELECT id, arcid AS archive_arcid FROM archives) a ON a.id = uas.archive_id WHERE a.archive_arcid = base.arcid AND uas.user_id = @@UID@@)"
                        let finalExpr = "(SELECT MAX(uas.updated_at) FROM user_archive_status uas JOIN (SELECT id, arcid AS archive_arcid FROM archives) a ON a.id = uas.archive_id WHERE a.archive_arcid = arcid AND uas.user_id = @@UID@@)"
                        windowOrderBy = "${windowExpr} ${dir}"
                        finalOrderBy = "${finalExpr} ${dir}"
                    } else if (sortby == "date_added" || sortby == "created_at") {
                        let dir = if (order == "desc") { "DESC" } else { "ASC" }
                        windowOrderBy = "created_at ${dir}"
                        finalOrderBy = "created_at ${dir}"
                    } else if (sortby == "release_at") {
                        let dir = if (order == "desc") { "DESC" } else { "ASC" }
                        windowOrderBy = "release_at ${dir}"
                        finalOrderBy = "release_at ${dir}"
                    } else if (sortby == "updated_at") {
                        let dir = if (order == "desc") { "DESC" } else { "ASC" }
                        windowOrderBy = "updated_at ${dir}"
                        finalOrderBy = "updated_at ${dir}"
                    } else if (sortby == "pagecount") {
                        let dir = if (order == "desc") { "DESC" } else { "ASC" }
                        windowOrderBy = "pagecount ${dir}"
                        finalOrderBy = "pagecount ${dir}"
                    } else if (sortby == "tank_order" && tankoubonId.size > 0) {
                        let dir = if (order == "desc") { "DESC" } else { "ASC" }
                        windowOrderBy = "tank_sort_order ${dir} NULLS LAST, created_at DESC"
                        finalOrderBy = "tank_sort_order ${dir} NULLS LAST, created_at DESC"
                        // JOIN tank id param comes before WHERE params in SQL
                        orderJoinPrefix.add(tankoubonId)
                    } else if (sortby == "size") {
                        let dir = if (order == "desc") { "DESC" } else { "ASC" }
                        windowOrderBy = "file_size ${dir}"
                        finalOrderBy = "file_size ${dir}"
                    } else if (sortby == "relevance" && filter.size > 0 && relevanceExpr != "1") {
                        // base CTE computes relevance_score so we don't need to repeat the heavy expression.
                        windowOrderBy = "relevance_score DESC, created_at DESC"
                        finalOrderBy = "relevance_score DESC, created_at DESC"
                    } else {
                        let dir = if (order == "desc") { "DESC" } else { "ASC" }
                        windowOrderBy = "title ${dir}"
                        finalOrderBy = "title ${dir}"
                    }

                    // Data query: rank within each group and take the first representative row.
                    // Note: We compute relevance_score in base so ranking/ordering can reuse it.
                    var dataSql = """
                        WITH base AS (
                            SELECT
                                archive_metadata_search.id,
                                archive_metadata_search.arcid,
                                archive_metadata_search.filename,
                                archive_metadata_search.title,
                                archive_metadata_search.summary,
                                archive_metadata_search.thumbhash,
                                archive_metadata_search.cover_asset_id,
                                archive_metadata_search.created_at,
                                archive_metadata_search.updated_at,
                                archive_metadata_search.release_at,
                                archive_metadata_search.relative_path,
                                archive_metadata_search.file_size,
                                archive_metadata_search.pagecount,
                                archive_metadata_search.archive_type,
                                archive_metadata_search.tags,
                                CASE WHEN tb.tankoubon_id IS NOT NULL AND tb.tankoubon_id != '' THEN 'tankoubon' ELSE 'archive' END AS group_item_type,
                                COALESCE(tb.tankoubon_id, archive_metadata_search.arcid) AS group_item_id,
                                COALESCE((${relevanceExpr}), 0) AS relevance_score
                    """
                    if (sortby == "tank_order" && tankoubonId.size > 0) {
                        dataSql += ", ta_order.sort_order AS tank_sort_order"
                    }
                    dataSql += """
                            FROM archive_metadata_search
                            LEFT JOIN tankoubon_archives tba ON tba.archive_id = archive_metadata_search.id
                            LEFT JOIN tankoubons tb ON tb.id = tba.tankoubon_id
                            LEFT JOIN metadata_objects tankoubon_metadata
                                   ON tankoubon_metadata.entity_type = 'tankoubon'
                                  AND tankoubon_metadata.entity_id = tb.tankoubon_id
                    """
                    if (sortby == "tank_order" && tankoubonId.size > 0) {
                        dataSql += " LEFT JOIN tankoubons t_order ON t_order.tankoubon_id = ?"
                        dataSql += " LEFT JOIN tankoubon_archives ta_order ON ta_order.tankoubon_id = t_order.id AND ta_order.archive_id = archive_metadata_search.id"
                    }
                    if (whereClause.size > 0) {
                        dataSql += " WHERE " + whereClause
                    }

                    dataSql += """
                        ),
                        ranked AS (
                            SELECT base.*,
                                   ROW_NUMBER() OVER (PARTITION BY base.group_item_id ORDER BY ${windowOrderBy}) AS rn
                            FROM base
                        )
                        SELECT
                            id, arcid, filename, title, summary, thumbhash, cover_asset_id, created_at, updated_at, release_at,
                            relative_path, file_size, pagecount, archive_type, tags, group_item_type, group_item_id
                        FROM ranked
                        WHERE rn = 1
                        ORDER BY ${finalOrderBy}
                        LIMIT ${count} OFFSET ${start}
                    """

                    getLogger("archive_dao").debug("执行分组数据SQL", ("sql", dataSql))

                    // 合并 orderJoinPrefix（出现在 SQL 文本最前面）与 filterParams
                    var allStringParams = ArrayList<String>()
                    for (i in 0..orderJoinPrefix.size) {
                        allStringParams.add(orderJoinPrefix[i])
                    }
                    for (i in 0..filterParams.size) {
                        allStringParams.add(filterParams[i])
                    }
                    let (boundSql, dataParams) = substitutePlaceholders(dataSql, allStringParams, userId)

                    let rows = db.raw<ArchiveData>(boundSql, dataParams, { row =>
                        let archive = ArchiveData()
                        archive.internalId = row.getOrNullInt64(0) ?? 0
                        archive.id = row.getOrNullText(1) ?? ""
                        archive.filename = row.getOrNullText(2) ?? ""
                        archive.title = row.getOrNullText(3) ?? ""
                        archive.summary = row.getOrNullText(4) ?? ""
                        archive.thumbhash = row.getOrNullText(5) ?? ""
                        archive.cover_asset_id = row.getOrNullInt64(6) ?? 0
                        archive.created_at = row.getOrNullText(7) ?? ""
                        archive.updated_at = row.getOrNullText(8) ?? ""
                        archive.release_at = row.getOrNullText(9) ?? ""
                        archive.relative_path = row.getOrNullText(10) ?? ""
                        archive.file_size = row.getOrNullInt64(11) ?? 0
                        archive.pagecount = row.getOrNullInt32(12) ?? 0
                        archive.archive_type = row.getOrNullText(13) ?? "archive"
                        archive.tags = row.getOrNullText(14) ?? ""
                        archive.group_item_type = row.getOrNullText(15) ?? ""
                        archive.group_item_id = row.getOrNullText(16) ?? ""
                        archive
                    })
                    for (a in rows) {
                        archives.add(a)
                    }

                    return (archives.toArray(), totalGroups)
                } catch (e: Exception) {
                    getLogger("archive_dao").error("分组搜索归档失败", ("error", e.message))
                    return (Array<ArchiveData>(), 0)
                }
            case None =>
                getLogger("archive_dao").error("无法连接到数据库")
                return (Array<ArchiveData>(), 0)
        }
    }

    /**
     * 获取归档所属的Tankoubon映射
     * 返回 HashMap<arcid, tankoubon_id>
     */
    public static func getArchiveTankoubonMapping(arcids: Array<String>): HashMap<String, String> {
        var mapping: HashMap<String, String> = HashMap<String, String>()
        if (arcids.size == 0) {
            return mapping
        }

        match (DatabaseConfig.getDatabase()) {
            case Some(db) =>
                try {
                    // 构建 IN 子句的占位符
                    var placeholders = ""
                    var params = ArrayList<Value>()
                    for (i in 0..arcids.size) {
                        if (i > 0) {
                            placeholders += ","
                        }
                        placeholders += "${'$'}${(i + 1).toString()}"
                        params.add(vtext(arcids[i]))
                    }

                    let sql = """
                        SELECT a.arcid, t.tankoubon_id
                        FROM tankoubon_archives ta
                        JOIN tankoubons t ON t.id = ta.tankoubon_id
                        JOIN archives a ON a.id = ta.archive_id
                        WHERE a.arcid IN (${placeholders})
                    """

                    let rows = db.raw<(String, String)>(sql, params.toArray(), { row =>
                        (row.getOrNullText(0) ?? "", row.getOrNullText(1) ?? "")
                    })
                    for ((arcid, tankoubonId) in rows) {
                        if (arcid != "" && tankoubonId != "") {
                            mapping[arcid] = tankoubonId
                        }
                    }
                } catch (e: Exception) {
                    logger.error("获取归档Tankoubon映射失败", ("error", e.message))
                }
            case None =>
                logger.error("无法连接到数据库")
        }

        return mapping
    }

    /**
     * 创建归档记录
     */
    public static func create(archive: ArchiveData): Bool {
        match (DatabaseConfig.getDatabase()) {
            case Some(db) =>
                try {
                    let sql = "INSERT INTO archives (arcid, filename, thumbhash, relative_path, file_size, pagecount, archive_type, category_id) VALUES ($1, $2, $3, $4, $5, $6, $7, $8)"
                    db.execRaw(sql, [
                        vtext(archive.id),
                        vtext(archive.filename),
                        vtext(archive.thumbhash),
                        vtext(archive.relative_path),
                        vint(archive.file_size),
                        vint(Int64(archive.pagecount)),
                        vtext(archive.archive_type),
                        vint(archive.category_id)
                    ])
                    let ok = MetadataDao.upsertRootMetadataObject(
                        "archive",
                        archive.id,
                        archive.title,
                        archive.summary,
                        releaseAt: archive.release_at,
                        sourceNamespace: "",
                        createdAt: archive.created_at,
                        updatedAt: archive.updated_at
                    )
                    if (ok) {
                        invalidateTankoubonAggregatedContent("archiveCreate:${archive.id}")
                        invalidateArchiveBasePath("archiveCreate:${archive.id}")
                    }
                    return ok
                } catch (e: Exception) {
                    logger.error("创建归档失败", ("error", e.message))
                    return false
                }
            case None =>
                logger.error("无法连接到数据库")
                return false
        }
    }

    /**
     * 插入归档记录 - 专门为 ShinobuService 提供的方法
     */
    public static func insertArchive(
        archiveId: String,
        title: String,
        fileName: String,
        fileSize: Int64,
        relativePath: String,
        archiveType: String,
        categoryId: Int64,
        pageCount: Int32
    ): Bool {
        match (DatabaseConfig.getDatabase()) {
            case Some(db) =>
                try {
                    // 使用数据库的默认值来处理时间戳，避免格式问题
                    let sql = "INSERT INTO archives (arcid, filename, thumbhash, relative_path, file_size, pagecount, archive_type, category_id) VALUES ($1, $2, $3, $4, $5, $6, $7, $8)"
                    db.execRaw(sql, [
                        vtext(archiveId),
                        vtext(fileName),
                        vtext(""),
                        vtext(relativePath),
                        vint(fileSize),
                        vint(Int64(pageCount)),
                        vtext(archiveType),
                        vint(categoryId)
                    ])
                    if (!MetadataDao.upsertRootMetadataObject("archive", archiveId, title, "")) {
                        logger.error("归档 metadata root 写入失败", ("archive_id", archiveId))
                        return false
                    }
                    invalidateTankoubonAggregatedContent("archiveInsert:${archiveId}")
                    invalidateArchiveBasePath("archiveInsert:${archiveId}")
                    logger.info("归档记录插入成功", ("archive_id", archiveId))
                    return true
                } catch (e: Exception) {
                    logger.error("插入语句执行失败", ("error", e.message))
                    return false
                }
            case None =>
                logger.error("Failed to connect to database")
                return false
        }
    }

    /**
     * 更新归档记录
     */
    public static func update(archive: ArchiveData): Bool {
        match (DatabaseConfig.getDatabase()) {
            case Some(db) =>
                try {
                    let sql = "UPDATE archives SET filename = $1, thumbhash = $2, relative_path = $3, file_size = $4, pagecount = $5, archive_type = $6, category_id = $7 WHERE arcid = $8"
                    db.execRaw(sql, [
                        vtext(archive.filename),
                        vtext(archive.thumbhash),
                        vtext(archive.relative_path),
                        vint(archive.file_size),
                        vint(Int64(archive.pagecount)),
                        vtext(archive.archive_type),
                        vint(archive.category_id),
                        vtext(archive.id)
                    ])
                    let ok = MetadataDao.upsertRootMetadataObject(
                        "archive",
                        archive.id,
                        archive.title,
                        archive.summary,
                        releaseAt: archive.release_at,
                        sourceNamespace: "",
                        createdAt: archive.created_at,
                        updatedAt: archive.updated_at
                    )
                    if (ok) {
                        invalidateTankoubonAggregatedContent("archiveUpdate:${archive.id}")
                        invalidateArchiveBasePath("archiveUpdate:${archive.id}")
                    }
                    return ok
                } catch (e: Exception) {
                    logger.error("更新归档失败", ("error", e.message))
                    return false
                }
            case None =>
                logger.error("无法连接到数据库")
                return false
        }
    }

    /**
     * 删除归档记录
     */
    public static func delete(id: String): Bool {
        match (DatabaseConfig.getDatabase()) {
            case Some(db) =>
                try {
                    let affected = db.execRaw("DELETE FROM archives WHERE arcid = $1", [vtext(id)])
                    if (affected > 0) {
                        invalidateTankoubonAggregatedContent("archiveDelete:${id}")
                        invalidateTankoubonChildren("archiveDelete:${id}")
                        invalidateArchiveBasePath("archiveDelete:${id}")
                        return true
                    }
                    logger.warn("删除归档未命中记录", ("arcid", id))
                    return false
                } catch (e: Exception) {
                    logger.error("删除归档失败", ("error", e.message))
                    return false
                }
            case None =>
                logger.error("无法连接到数据库")
                return false
        }
    }

    /**
     * 更新归档的页数
     */
    public static func updatePageCount(archiveId: String, pageCount: Int32): Bool {
        match (DatabaseConfig.getDatabase()) {
            case Some(db) =>
                try {
                    db.execRaw("UPDATE archives SET pagecount = $1 WHERE arcid = $2", [vint(Int64(pageCount)), vtext(archiveId)])
                    invalidateTankoubonAggregatedContent("updatePageCount:${archiveId}")
                    return true
                } catch (e: Exception) {
                    logger.error("更新归档页数失败", ("error", e.message))
                    return false
                }
            case None =>
                logger.error("无法连接到数据库")
                return false
        }
    }

    /**
     * 更新归档的缩略图hash
     */
    public static func updateThumbHash(archiveId: String, thumbHash: String): Bool {
        match (DatabaseConfig.getDatabase()) {
            case Some(db) =>
                try {
                    db.execRaw("UPDATE archives SET thumbhash = $1 WHERE arcid = $2", [vtext(thumbHash), vtext(archiveId)])
                    return true
                } catch (e: Exception) {
                    logger.error("更新归档缩略图hash失败", ("error", e.message))
                    return false
                }
            case None =>
                logger.error("无法连接到数据库")
                return false
        }
    }

    /**
     * 同时更新归档的页数和缩略图hash
     */
    public static func updateArchiveDetails(archiveId: String, pageCount: Int32, thumbHash: String): Bool {
        match (DatabaseConfig.getDatabase()) {
            case Some(db) =>
                try {
                    db.execRaw("UPDATE archives SET pagecount = $1, thumbhash = $2 WHERE arcid = $3", [vint(Int64(pageCount)), vtext(thumbHash), vtext(archiveId)])
                    invalidateTankoubonAggregatedContent("updateArchiveDetails:${archiveId}")
                    return true
                } catch (e: Exception) {
                    logger.error("更新归档详情失败", ("error", e.message))
                    return false
                }
            case None =>
                logger.error("无法连接到数据库")
                return false
        }
    }

    /**
     * 更新归档的相对路径
     */
    public static func updateArchiveRelativePath(archiveId: String, relativePath: String): Bool {
        match (DatabaseConfig.getDatabase()) {
            case Some(db) =>
                try {
                    db.execRaw("UPDATE archives SET relative_path = $1 WHERE arcid = $2", [vtext(relativePath), vtext(archiveId)])
                    return true
                } catch (e: Exception) {
                    getLogger("archive_dao").error("更新归档相对路径失败", ("error", e.message))
                    return false
                }
            case None =>
                getLogger("archive_dao").error("无法连接到数据库")
                return false
        }
    }

    /**
     * 获取所有没有缩略图的归档
     */
    public static func getArchivesWithoutThumbnails(): Array<ArchiveData> {
        match (DatabaseConfig.getDatabase()) {
            case Some(db) =>
                try {
                    let sql = "SELECT arcid, title, filename, summary, thumbhash, cover_asset_id, created_at, updated_at, release_at, relative_path, file_size, pagecount, category_id FROM archive_metadata_search WHERE thumbhash = '' OR thumbhash IS NULL ORDER BY id"
                    return db.raw<ArchiveData>(sql, Array<Value>(), { row =>
                        let archive = ArchiveData()
                        archive.id = row.getOrNullText(0) ?? ""
                        archive.title = row.getOrNullText(1) ?? ""
                        archive.filename = row.getOrNullText(2) ?? ""
                        archive.summary = row.getOrNullText(3) ?? ""
                        archive.thumbhash = row.getOrNullText(4) ?? ""
                        archive.cover_asset_id = row.getOrNullInt64(5) ?? 0
                        archive.created_at = row.getOrNullText(6) ?? ""
                        archive.updated_at = row.getOrNullText(7) ?? ""
                        archive.release_at = row.getOrNullText(8) ?? ""
                        archive.relative_path = row.getOrNullText(9) ?? ""
                        archive.file_size = row.getOrNullInt64(10) ?? 0
                        archive.pagecount = row.getOrNullInt32(11) ?? 0
                        archive.category_id = row.getOrNullInt64(12) ?? 0
                        archive
                    })
                } catch (e: Exception) {
                    getLogger("archive_dao").error("获取无缩略图归档失败", ("error", e.message))
                    return Array<ArchiveData>()
                }
            case None =>
                getLogger("archive_dao").error("无法连接到数据库")
                return Array<ArchiveData>()
        }
    }

    /**
     * 检查归档是否存在
     */
    public static func exists(id: String): Bool {
        match (DatabaseConfig.getDatabase()) {
            case Some(db) =>
                try {
                    let count = db.rawOne<Int64>("SELECT COUNT(*) FROM archives WHERE arcid = $1", [vtext(id)], { row => row.getInt64(0) }) ?? 0
                    return count > 0
                } catch (e: Exception) {
                    getLogger("archive_dao").error("检查归档存在性失败", ("error", e.message))
                    return false
                }
            case None =>
                getLogger("archive_dao").error("无法连接到数据库")
                return false
        }
    }

    /**
     * 根据文件路径获取归档信息
     */
    public static func getByPath(filePath: String): Option<ArchiveData> {
        match (DatabaseConfig.getDatabase()) {
            case Some(db) =>
                try {
                    let sql = "SELECT arcid, title, filename, summary, thumbhash, cover_asset_id, created_at, updated_at, release_at, relative_path, file_size, pagecount, category_id FROM archive_metadata_search WHERE relative_path = $1"
                    return db.rawOne<ArchiveData>(sql, [vtext(filePath)], { row =>
                        let archive = ArchiveData()
                        archive.id = row.getOrNullText(0) ?? ""
                        archive.title = row.getOrNullText(1) ?? ""
                        archive.filename = row.getOrNullText(2) ?? ""
                        archive.summary = row.getOrNullText(3) ?? ""
                        archive.thumbhash = row.getOrNullText(4) ?? ""
                        archive.cover_asset_id = row.getOrNullInt64(5) ?? 0
                        archive.created_at = row.getOrNullText(6) ?? ""
                        archive.updated_at = row.getOrNullText(7) ?? ""
                        archive.release_at = row.getOrNullText(8) ?? ""
                        archive.relative_path = row.getOrNullText(9) ?? ""
                        archive.file_size = row.getOrNullInt64(10) ?? 0
                        archive.pagecount = row.getOrNullInt32(11) ?? 0
                        archive.category_id = row.getOrNullInt64(12) ?? 0
                        archive
                    })
                } catch (e: Exception) {
                    getLogger("archive_dao").error("根据路径获取归档失败", ("error", e.message))
                    return None
                }
            case None =>
                getLogger("archive_dao").error("无法连接到数据库")
                return None
        }
    }

    /**
     * 根据分类、相对路径和文件名获取归档
     */
    public static func getByCategoryPathAndFilename(categoryId: Int64, relativePath: String, filename: String): Option<ArchiveData> {
        if (categoryId <= 0) {
            return None
        }
        match (DatabaseConfig.getDatabase()) {
            case Some(db) =>
                try {
                    let sql = "SELECT arcid, title, filename, summary, thumbhash, cover_asset_id, created_at, updated_at, release_at, relative_path, file_size, pagecount, category_id FROM archive_metadata_search WHERE category_id = $1 AND relative_path = $2 AND filename = $3"
                    return db.rawOne<ArchiveData>(sql, [vint(categoryId), vtext(relativePath), vtext(filename)], { row =>
                        let archive = ArchiveData()
                        archive.id = row.getOrNullText(0) ?? ""
                        archive.title = row.getOrNullText(1) ?? ""
                        archive.filename = row.getOrNullText(2) ?? ""
                        archive.summary = row.getOrNullText(3) ?? ""
                        archive.thumbhash = row.getOrNullText(4) ?? ""
                        archive.cover_asset_id = row.getOrNullInt64(5) ?? 0
                        archive.created_at = row.getOrNullText(6) ?? ""
                        archive.updated_at = row.getOrNullText(7) ?? ""
                        archive.release_at = row.getOrNullText(8) ?? ""
                        archive.relative_path = row.getOrNullText(9) ?? ""
                        archive.file_size = row.getOrNullInt64(10) ?? 0
                        archive.pagecount = row.getOrNullInt32(11) ?? 0
                        archive.category_id = row.getOrNullInt64(12) ?? 0
                        archive
                    })
                } catch (e: Exception) {
                    getLogger("archive_dao").error("根据分类+路径和文件名获取归档失败", ("error", e.message))
                    return None
                }
            case None =>
                getLogger("archive_dao").error("无法连接到数据库")
                return None
        }
    }

    /**
     * 根据相对路径和文件名获取归档
     */
    public static func getByPathAndFilename(relativePath: String, filename: String): Option<ArchiveData> {
        match (DatabaseConfig.getDatabase()) {
            case Some(db) =>
                try {
                    let sql = "SELECT arcid, title, filename, summary, thumbhash, cover_asset_id, created_at, updated_at, release_at, relative_path, file_size, pagecount, category_id FROM archive_metadata_search WHERE relative_path = $1 AND filename = $2"
                    return db.rawOne<ArchiveData>(sql, [vtext(relativePath), vtext(filename)], { row =>
                        let archive = ArchiveData()
                        archive.id = row.getOrNullText(0) ?? ""
                        archive.title = row.getOrNullText(1) ?? ""
                        archive.filename = row.getOrNullText(2) ?? ""
                        archive.summary = row.getOrNullText(3) ?? ""
                        archive.thumbhash = row.getOrNullText(4) ?? ""
                        archive.cover_asset_id = row.getOrNullInt64(5) ?? 0
                        archive.created_at = row.getOrNullText(6) ?? ""
                        archive.updated_at = row.getOrNullText(7) ?? ""
                        archive.release_at = row.getOrNullText(8) ?? ""
                        archive.relative_path = row.getOrNullText(9) ?? ""
                        archive.file_size = row.getOrNullInt64(10) ?? 0
                        archive.pagecount = row.getOrNullInt32(11) ?? 0
                        archive.category_id = row.getOrNullInt64(12) ?? 0
                        archive
                    })
                } catch (e: Exception) {
                    getLogger("archive_dao").error("根据路径和文件名获取归档失败", ("error", e.message))
                    return None
                }
            case None =>
                getLogger("archive_dao").error("无法连接到数据库")
                return None
        }
    }

    /**
     * 获取归档的缩略图hash
     */
    public static func getThumbnailHash(archiveId: String): String {
        match (DatabaseConfig.getDatabase()) {
            case Some(db) =>
                try {
                    return db.rawOne<String>("SELECT thumbhash FROM archives WHERE arcid = $1", [vtext(archiveId)], { row => row.getOrNullText(0) ?? "" }) ?? ""
                } catch (e: Exception) {
                    getLogger("archive_dao").error("获取缩略图hash失败", ("error", e.message))
                    return ""
                }
            case None =>
                getLogger("archive_dao").error("无法连接到数据库")
                return ""
        }
    }

    /**
     * 获取归档的封面资源 ID（assets.id）
     */
    public static func getCoverAssetId(archiveId: String): Int64 {
        return MetadataDao.getMetadataAssetId("archive", archiveId, "cover")
    }

    /**
     * 获取归档指定 assets key 的资源 ID（支持 cover/backdrop/clearlogo）。
     */
    public static func getArchiveAssetIdByKey(archiveId: String, assetKey: String): Int64 {
        let key = assetKey.trimAscii()
        if (key != "cover" && key != "backdrop" && key != "clearlogo") {
            return 0
        }
        return MetadataDao.getMetadataAssetId("archive", archiveId, key)
    }

    /**
     * 获取归档 assets JSON（原样透传，默认 {}）
     */
    public static func getArchiveAssetsRaw(archiveId: String): String {
        match (DatabaseConfig.getDatabase()) {
            case Some(db) =>
                try {
                    let sql = """
                        SELECT COALESCE(
                            (
                                SELECT COALESCE(
                                    jsonb_object_agg(ma.slot, to_jsonb(ma.asset_id))
                                        FILTER (WHERE ma.asset_id > 0),
                                    '{}'::jsonb
                                )
                                FROM metadata_assets ma
                                WHERE ma.metadata_id = mo.id
                            ),
                            '{}'::jsonb
                        )::TEXT
                        FROM metadata_objects mo
                        WHERE mo.entity_type = 'archive' AND mo.entity_id = $1
                        LIMIT 1
                    """
                    let raw = db.rawOne<String>(sql, [vtext(archiveId)], { row => row.getOrNullText(0) ?? "" }) ?? ""
                    let trimmed = raw.trimAscii()
                    return if (trimmed.size > 0) { trimmed } else { "{}" }
                } catch (_: Exception) {
                    return "{}"
                }
            case None => return "{}"
        }
    }

    /**
     * 批量获取归档 assets JSON（key=arcid, value=JSON文本）
     */
    public static func getBatchArchiveAssetsRaw(archiveIds: Array<String>): HashMap<String, String> {
        let result = HashMap<String, String>()
        if (archiveIds.size == 0) { return result }

        let normalizedIds = normalizeUniqueIds(archiveIds)
        let deduped = ArrayList<String>()
        for (archiveId in normalizedIds) {
            deduped.add(archiveId)
        }
        if (deduped.size == 0) { return result }

        let cacheVersion = DerivedCacheUtils.getArchiveAssetsRawVersion()
        let misses = ArrayList<String>()
        var hitCount = 0
        for (archiveId in normalizedIds) {
            let cacheKey = buildArchiveAssetsRawCacheKey(cacheVersion, archiveId)
            match (readArchiveAssetsRawCache(cacheKey)) {
                case Some(cached) =>
                    result[archiveId] = cached
                    hitCount += 1
                case None =>
                    misses.add(archiveId)
            }
        }

        if (misses.size == 0) {
            logger.debug("archive assets raw cache hit",
                ("requested", normalizedIds.size.toString()),
                ("hits", hitCount.toString()),
                ("misses", "0"))
            return result
        }

        match (DatabaseConfig.getDatabase()) {
            case Some(db) =>
                try {
                    var inClause = ""
                    var params = ArrayList<Value>()
                    for (i in 0..misses.size) {
                        if (i > 0) { inClause += "," }
                        inClause += "${'$'}${(i + 1).toString()}"
                        params.add(vtext(misses[i]))
                    }

                    let sql = """
                        SELECT
                            mo.entity_id,
                            COALESCE(
                                jsonb_object_agg(ma.slot, to_jsonb(ma.asset_id))
                                    FILTER (WHERE ma.asset_id > 0),
                                '{}'::jsonb
                            )::TEXT
                        FROM metadata_objects mo
                        LEFT JOIN metadata_assets ma ON ma.metadata_id = mo.id
                        WHERE mo.entity_type = 'archive'
                          AND mo.entity_id IN (${inClause})
                        GROUP BY mo.id, mo.entity_id
                    """
                    let rows = db.raw<(String, String)>(sql, params.toArray(), { row =>
                        (row.getOrNullText(0) ?? "", row.getOrNullText(1) ?? "")
                    })
                    for ((arcidRaw, rawRaw) in rows) {
                        let arcid = arcidRaw.trimAscii()
                        let raw = rawRaw.trimAscii()
                        if (arcid.size == 0) { continue }
                        let normalizedRaw = if (raw.size > 0) { raw } else { "{}" }
                        result[arcid] = normalizedRaw
                        let cacheKey = buildArchiveAssetsRawCacheKey(cacheVersion, arcid)
                        writeArchiveAssetsRawCache(cacheKey, normalizedRaw)
                    }
                } catch (e: Exception) {
                    logger.error("批量获取归档 assets JSON 失败", ("error", e.message))
                    return result
                }
            case None => ()
        }

        for (archiveId in misses) {
            match (result.get(archiveId)) {
                case Some(_) => ()
                case None =>
                    result[archiveId] = "{}"
                    let cacheKey = buildArchiveAssetsRawCacheKey(cacheVersion, archiveId)
                    writeArchiveAssetsRawCache(cacheKey, "{}")
            }
        }

        logger.debug("archive assets raw cache lookup",
            ("requested", normalizedIds.size.toString()),
            ("hits", hitCount.toString()),
            ("misses", misses.size.toString()))

        return result
    }

    /**
     * 原样更新归档 assets JSON，并同步 cover_asset_id。
     */
    public static func updateArchiveAssetsRaw(archiveId: String, assetsRaw: String): Bool {
        let normalized = assetsRaw.trimAscii()
        let payload = if (normalized.size > 0) { normalized } else { "{}" }
        if (!ensureArchiveMetadataRoot(archiveId)) {
            return false
        }

        match (DatabaseConfig.getDatabase()) {
            case Some(db) =>
                try {
                    let sql = """
                        WITH target AS (
                            SELECT id AS metadata_id
                            FROM metadata_objects
                            WHERE entity_type = 'archive' AND entity_id = $1
                            LIMIT 1
                        ),
                        payload AS (
                            SELECT COALESCE(CAST($2 AS JSONB), '{}'::jsonb) AS j
                        ),
                        parsed AS (
                            SELECT LOWER(TRIM(kv.key)) AS slot, kv.value AS raw_value
                            FROM payload p
                            CROSS JOIN LATERAL jsonb_each(p.j) kv(key, value)
                        ),
                        normalized AS (
                            SELECT
                                slot,
                                CASE
                                    WHEN COALESCE(raw_value #>> '{}', '') ~ '^[0-9]+$'
                                         AND (raw_value #>> '{}')::BIGINT > 0
                                        THEN (raw_value #>> '{}')::BIGINT
                                    ELSE 0
                                END AS asset_id
                            FROM parsed
                            WHERE slot != ''
                        ),
                        deleted AS (
                            DELETE FROM metadata_assets ma
                            USING target t
                            WHERE ma.metadata_id = t.metadata_id
                        )
                        INSERT INTO metadata_assets (metadata_id, slot, asset_id, created_at, updated_at)
                        SELECT t.metadata_id, n.slot, n.asset_id, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
                        FROM target t
                        JOIN normalized n ON n.asset_id > 0
                    """
                    db.execRaw(sql, [vtext(archiveId), vjson(payload)])
                    let _ = MetadataDao.touchRootMetadataObject("archive", archiveId)
                    invalidateArchiveAssetsRaw("updateArchiveAssetsRaw:${archiveId}")
                    return true
                } catch (e: Exception) {
                    logger.error("更新归档 assets JSON 失败", ("arcid", archiveId), ("error", e.message))
                    return false
                }
            case None =>
                logger.error("无法连接到数据库")
                return false
        }
    }

    /**
     * 更新归档封面资源 ID（assets.id）
     */
    public static func updateCoverAssetId(archiveId: String, assetId: Int64): Bool {
        if (!ensureArchiveMetadataRoot(archiveId)) {
            return false
        }
        if (!MetadataDao.setMetadataAssetId("archive", archiveId, "cover", assetId)) {
            return false
        }
        let _ = MetadataDao.touchRootMetadataObject("archive", archiveId)
        invalidateArchiveAssetsRaw("updateCoverAssetId:${archiveId}")
        return true
    }

    /**
     * 更新归档指定 assets key 的资源 ID（仅支持 cover/backdrop/clearlogo）。
     */
    public static func updateArchiveAssetIdByKey(archiveId: String, assetKey: String, assetId: Int64): Bool {
        let key = assetKey.trimAscii()
        if (key != "cover" && key != "backdrop" && key != "clearlogo") {
            return false
        }
        if (!ensureArchiveMetadataRoot(archiveId)) {
            return false
        }
        if (!MetadataDao.setMetadataAssetId("archive", archiveId, key, assetId)) {
            return false
        }
        let _ = MetadataDao.touchRootMetadataObject("archive", archiveId)
        invalidateArchiveAssetsRaw("updateArchiveAssetIdByKey:${archiveId}:${key}")
        return true
    }

    /**
     * Get up to `limit` cover asset ids for a category, ordered by most recently updated archives.
     */
    public static func getCategoryCoverAssetIds(categoryId: Int64, limit: Int32): Array<Int64> {
        if (categoryId <= 0 || limit <= 0) {
            return Array<Int64>()
        }

        match (DatabaseConfig.getDatabase()) {
            case Some(db) =>
                var ids = ArrayList<Int64>()
                try {
                    let sql = """
                        SELECT COALESCE(cover.asset_id, 0) AS cover_asset_id
                        FROM archives a
                        LEFT JOIN metadata_objects mo
                               ON mo.entity_type = 'archive'
                              AND mo.entity_id = a.arcid
                        LEFT JOIN metadata_assets cover
                               ON cover.metadata_id = mo.id
                              AND cover.slot = 'cover'
                        WHERE a.category_id = $1
                          AND COALESCE(cover.asset_id, 0) > 0
                        ORDER BY mo.updated_at DESC NULLS LAST, a.id DESC
                        LIMIT $2
                    """
                    let rows = db.raw<Int64>(sql, [vint(categoryId), vint(Int64(limit))], { row =>
                        row.getOrNullInt64(0) ?? 0
                    })
                    for (id in rows) {
                        if (id > 0) { ids.add(id) }
                    }
                } catch (e: Exception) {
                    getLogger("archive_dao").error("获取分类封面资源ID列表失败", ("error", e.message))
                }
                return ids.toArray()
            case None =>
                getLogger("archive_dao").error("无法连接到数据库")
                return Array<Int64>()
        }
    }

    /**
     * Check if an archive exists by arcid.
     */
    public static func archiveExists(archiveId: String): Bool {
        let trimmed = archiveId.trimAscii()
        if (trimmed.size == 0) { return false }
        match (DatabaseConfig.getDatabase()) {
            case Some(db) =>
                try {
                    return db.rawOne<Int64>("SELECT 1 FROM archives WHERE arcid = $1 LIMIT 1", [vtext(trimmed)], { row => row.getInt64(0) }).isSome()
                } catch (_: Exception) {
                    return false
                }
            case None => return false
        }
    }

    /**
     * 根据 ID 获取归档元数据（包含标签）
     */
    public static func getArchiveMetadataById(id: String): ArchiveData {
        match (DatabaseConfig.getDatabase()) {
            case Some(db) =>
                try {
                    // 使用 archive_metadata_search 视图获取包含标签的数据
                    let sql = "SELECT arcid, filename, title, summary, thumbhash, cover_asset_id, created_at, updated_at, release_at, relative_path, file_size, pagecount, archive_type, tags FROM archive_metadata_search WHERE arcid = $1"
                    let result = db.rawOne<ArchiveData>(sql, [vtext(id)], { row =>
                        let archive = ArchiveData()
                        archive.id = row.getOrNullText(0) ?? ""
                        archive.filename = row.getOrNullText(1) ?? ""
                        archive.title = row.getOrNullText(2) ?? ""
                        archive.summary = row.getOrNullText(3) ?? ""
                        archive.thumbhash = row.getOrNullText(4) ?? ""
                        archive.cover_asset_id = row.getOrNullInt64(5) ?? 0
                        archive.created_at = row.getOrNullText(6) ?? ""
                        archive.updated_at = row.getOrNullText(7) ?? ""
                        archive.release_at = row.getOrNullText(8) ?? ""
                        archive.relative_path = row.getOrNullText(9) ?? ""
                        archive.file_size = row.getOrNullInt64(10) ?? 0
                        archive.pagecount = row.getOrNullInt32(11) ?? 0
                        archive.archive_type = row.getOrNullText(12) ?? "archive"
                        archive.tags = row.getOrNullText(13) ?? ""
                        archive
                    })
                    match (result) {
                        case Some(a) => return a
                        case None => ()
                    }
                } catch (e: Exception) {
                    getLogger("archive_dao").error("查询归档元数据失败", ("error", e.message))
                }
            case None => getLogger("archive_dao").error("无法连接到数据库")
        }
        return ArchiveData()
    }

    /**
     * 获取档案所属分类的 scan_path（轻量查询，避免额外聚合）
     */
    public static func getArchiveScanPathByArcid(arcid: String): String {
        match (DatabaseConfig.getDatabase()) {
            case Some(db) =>
                try {
                    let sql = """
                        SELECT c.scan_path
                        FROM archives a
                        JOIN categories c ON c.id = a.category_id
                        WHERE a.arcid = $1
                        LIMIT 1
                    """
                    return db.rawOne<String>(sql, [vtext(arcid)], { row => row.getOrNullText(0) ?? "" }) ?? ""
                } catch (e: Exception) {
                    getLogger("archive_dao").error("获取档案扫描路径失败", ("error", e.message))
                    return ""
                }
            case None =>
                getLogger("archive_dao").error("无法连接到数据库")
                return ""
        }
    }

    /**
     * 获取档案的 category_id
     */
    public static func getArchiveCategoryId(arcid: String): Int64 {
        match (DatabaseConfig.getDatabase()) {
            case Some(db) =>
                try {
                    return db.rawOne<Int64>("SELECT category_id FROM archives WHERE arcid = $1", [vtext(arcid)], { row => row.getOrNullInt64(0) ?? 0 }) ?? 0
                } catch (e: Exception) {
                    getLogger("archive_dao").error("获取档案分类ID失败", ("error", e.message))
                    return 0
                }
            case None =>
                getLogger("archive_dao").error("无法连接到数据库")
                return 0
        }
    }

    /**
     * 清理所有 Archive 的 thumbhash 字段
     * @return 清理的记录数，失败返回 -1
     */
    public static func clearAllThumbhash(): Int64 {
        match (DatabaseConfig.getDatabase()) {
            case Some(db) =>
                try {
                    return db.execRaw("UPDATE archives SET thumbhash = '' WHERE thumbhash != '' AND thumbhash IS NOT NULL", Array<Value>())
                } catch (e: Exception) {
                    getLogger("archive_dao").error("清理所有thumbhash失败", ("error", e.message))
                    return -1
                }
            case None =>
                getLogger("archive_dao").error("无法连接到数据库")
                return -1
        }
    }

    /**
     * 更新档案的 category_id
     */
    public static func updateArchiveCategoryId(arcid: String, categoryId: Int64): Bool {
        match (DatabaseConfig.getDatabase()) {
            case Some(db) =>
                try {
                    let affected = db.execRaw("UPDATE archives SET category_id = $1 WHERE arcid = $2", [vint(categoryId), vtext(arcid)])
                    if (affected > 0) {
                        invalidateArchiveBasePath("updateArchiveCategoryId:${arcid}")
                    }
                    return affected > 0
                } catch (e: Exception) {
                    getLogger("archive_dao").error("更新档案分类ID失败", ("error", e.message))
                    return false
                }
            case None =>
                getLogger("archive_dao").error("无法连接到数据库")
                return false
        }
    }

    /**
     * 获取需要重生成封面的档案列表（用于批量任务派发）
     *
     * mode:
     * - "missing"           : cover_asset_id 缺失或 thumbhash 缺失
     * - "thumbhash_missing" : thumbhash 缺失
     * - "cover_missing"     : cover_asset_id 缺失
     * - "all"               : 全部
     */
    public static func getArchivesForCoverRegeneration(mode: String, limit: Int32): ArrayList<ArchiveCoverRegenerationRow> {
        return getArchivesForCoverRegeneration(mode, limit, 0)
    }

    /**
     * Cursor-based pagination for cover regeneration.
     * Fetches archives with internal id > afterInternalId ordered by id asc.
     */
    public static func getArchivesForCoverRegeneration(mode: String, limit: Int32, afterInternalId: Int64): ArrayList<ArchiveCoverRegenerationRow> {
        var result = ArrayList<ArchiveCoverRegenerationRow>()
        if (limit <= 0) { return result }

        let trimmedMode = mode.trimAscii()
        var whereSql = ""
        if (trimmedMode == "all") {
            whereSql = "TRUE"
        } else if (trimmedMode == "thumbhash_missing") {
            whereSql = "(a.thumbhash IS NULL OR a.thumbhash = '')"
        } else if (trimmedMode == "cover_missing") {
            whereSql = "(COALESCE(cover.asset_id, 0) = 0)"
        } else {
            // default: "missing"
            whereSql = "((COALESCE(cover.asset_id, 0) = 0) OR (a.thumbhash IS NULL OR a.thumbhash = ''))"
        }

        match (DatabaseConfig.getDatabase()) {
            case Some(db) =>
                try {
                    let sql = """
                        SELECT a.id, a.arcid, a.filename, a.relative_path, a.archive_type, a.category_id,
                               COALESCE(cover.asset_id, 0) AS cover_asset_id,
                               COALESCE(a.thumbhash, '') AS thumbhash,
                               COALESCE(c.scan_path, '') AS scan_path
                        FROM archives a
                        LEFT JOIN metadata_objects mo
                               ON mo.entity_type = 'archive'
                              AND mo.entity_id = a.arcid
                        LEFT JOIN metadata_assets cover
                               ON cover.metadata_id = mo.id
                              AND cover.slot = 'cover'
                        LEFT JOIN categories c ON c.id = a.category_id
                        WHERE ${whereSql}
                          AND a.id > $1
                        ORDER BY a.id ASC
                        LIMIT $2
                    """
                    let rows = db.raw<ArchiveCoverRegenerationRow>(sql, [vint(afterInternalId), vint(Int64(limit))], { row =>
                        let r = ArchiveCoverRegenerationRow()
                        r.archiveInternalId = row.getOrNullInt64(0) ?? 0
                        r.archiveId = row.getOrNullText(1) ?? ""
                        r.filename = row.getOrNullText(2) ?? ""
                        r.relativePath = row.getOrNullText(3) ?? ""
                        r.archiveType = row.getOrNullText(4) ?? "archive"
                        r.categoryId = row.getOrNullInt64(5) ?? 0
                        r.coverAssetId = row.getOrNullInt64(6) ?? 0
                        r.thumbhash = row.getOrNullText(7) ?? ""
                        r.categoryScanPath = row.getOrNullText(8) ?? ""
                        r
                    })
                    for (r in rows) {
                        result.add(r)
                    }
                } catch (e: Exception) {
                    getLogger("archive_dao").error("getArchivesForCoverRegeneration failed", ("error", e.message))
                }
            case None =>
                getLogger("archive_dao").error("无法连接到数据库")
        }
        return result
    }

    /**
     * 获取需要补全元数据的档案列表：
     * - 没有任何非 source 命名空间的标签（即“只有source标签”或“完全无标签”）
     */
    public static func getArchivesNeedingMetadataBackfill(limit: Int32): ArrayList<ArchiveMetadataBackfillRow> {
        return getArchivesNeedingMetadataBackfill(limit, 0)
    }

    /**
     * Cursor-based pagination for metadata backfill.
     * Fetches archives with internal id > afterInternalId ordered by id asc.
     */
    public static func getArchivesNeedingMetadataBackfill(limit: Int32, afterInternalId: Int64): ArrayList<ArchiveMetadataBackfillRow> {
        var result = ArrayList<ArchiveMetadataBackfillRow>()
        if (limit <= 0) { return result }

        match (DatabaseConfig.getDatabase()) {
            case Some(db) =>
                try {
                    let sql = """
                        SELECT a.id,
                               a.arcid,
                               a.category_id,
                               COALESCE(c.plugins, '[]') AS plugins_json
                        FROM archives a
                        LEFT JOIN categories c ON c.id = a.category_id
                        WHERE NOT EXISTS (
                            SELECT 1
                            FROM metadata_objects mo
                            JOIN metadata_tags mt ON mt.metadata_id = mo.id
                            WHERE mo.entity_type = 'archive'
                              AND mo.entity_id = a.arcid
                              AND (position(':' IN mt.tag) = 0 OR LOWER(split_part(mt.tag, ':', 1)) != 'source')
                        )
                          AND a.id > $1
                        ORDER BY a.id ASC
                        LIMIT $2
                    """
                    let rows = db.raw<ArchiveMetadataBackfillRow>(sql, [vint(afterInternalId), vint(Int64(limit))], { row =>
                        let r = ArchiveMetadataBackfillRow()
                        r.archiveInternalId = row.getOrNullInt64(0) ?? 0
                        r.archiveId = row.getOrNullText(1) ?? ""
                        r.categoryId = row.getOrNullInt64(2) ?? 0
                        r.categoryPlugins = row.getOrNullText(3) ?? "[]"
                        r
                    })
                    for (r in rows) {
                        result.add(r)
                    }
                } catch (e: Exception) {
                    getLogger("archive_dao").error("getArchivesNeedingMetadataBackfill failed", ("error", e.message))
                }
            case None =>
                getLogger("archive_dao").error("无法连接到数据库")
        }
        return result
    }

    public static func getPageMetadata(arcid: String): Array<PageMetadataData> {
        let normalizedId = arcid.trimAscii()
        if (normalizedId.size == 0) {
            return Array<PageMetadataData>()
        }
        return MetadataDao.listPageMetadata(normalizedId)
    }

    public static func getPageThumbAssetId(arcid: String, pageNumber: Int32): Int64 {
        let normalizedId = arcid.trimAscii()
        if (normalizedId.size == 0) {
            return 0
        }
        return MetadataDao.getPageThumbAssetId(normalizedId, pageNumber)
    }

    public static func getPageThumbAssetIds(arcid: String): Array<Int64> {
        let normalizedId = arcid.trimAscii()
        if (normalizedId.size == 0) {
            return Array<Int64>()
        }
        return MetadataDao.getPageThumbAssetIds(normalizedId)
    }

    public static func deletePageMetadata(arcid: String): Bool {
        let normalizedId = arcid.trimAscii()
        if (normalizedId.size == 0) {
            return false
        }
        return MetadataDao.deletePageMetadata(normalizedId)
    }
}