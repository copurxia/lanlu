package lanlu.contexts.archive.infrastructure.persistence

import ace_orm.*
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
 * 动态参数构造器：维护编号占位符 ($n) 与绑定值列表的对应关系。
 * 取代旧版 `ArrayList<String> filterParams` + `?` 占位符的“两个数组”写法。
 * 通过 `paramIdx` 运行计数器在 WHERE 条件拼接过程中生成 $1, $2, ... 占位符。
 */
class ParamBuilder {
    public var values: ArrayList<DbValue> = ArrayList<DbValue>()
    public var idx: Int64 = 0  // 当前已用最大编号；下一个占位符为 idx+1

    /** 追加一个文本参数，返回该参数对应的 $n 占位符字符串，并推进计数器。 */
    public func addText(v: String): String {
        idx += 1
        values.add(DbText(v))
        return placeholder(idx)
    }

    /** 追加一个任意 DbValue 参数。 */
    public func addRaw(v: DbValue): String {
        idx += 1
        values.add(v)
        return placeholder(idx)
    }

    public func placeholder(n: Int64): String {
        return "${'$'}${n}"
    }
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

    private static func extensionInstalled(extensionName: String): Bool {
        try {
            let rows = DatabaseConfig.driver().query("SELECT 1 FROM pg_extension WHERE extname = $1 LIMIT 1", [DbText(extensionName)])
            return rows.size > 0
        } catch (_: Exception) {
            return false
        }
    }

    private static func functionExists(functionName: String): Bool {
        try {
            let rows = DatabaseConfig.driver().query("SELECT 1 FROM pg_proc WHERE proname = $1 LIMIT 1", [DbText(functionName)])
            return rows.size > 0
        } catch (_: Exception) {
            return false
        }
    }

    private static func getUnaccentFunction(): String {
        if (functionExists("lanlu_immutable_unaccent")) {
            return "lanlu_immutable_unaccent"
        }
        if (extensionInstalled("unaccent")) {
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

    /**
     * 构建归档文本匹配条件（title/filename/summary/tag 模糊匹配）。
     * 使用 ParamBuilder 生成编号占位符。
     */
    private static func buildArchiveTextMatchCondition(
        pattern: String,
        params: ParamBuilder,
        tableAlias: String,
        unaccentFunction: String
    ): String {
        let p1 = params.addText(pattern)
        let p2 = params.addText(pattern)
        let p3 = params.addText(pattern)
        let titleExpr = wrapSearchExpr("${tableAlias}.title", unaccentFunction)
        let filenameExpr = wrapSearchExpr("${tableAlias}.filename", unaccentFunction)
        let summaryExpr = wrapSearchExpr("${tableAlias}.summary", unaccentFunction)
        // 三个占位符分别用于 title/filename/summary；tag 条件使用各自的占位符。
        let titlePh = if (unaccentFunction.size > 0) { "${unaccentFunction}(${p1})" } else { p1 }
        let filenamePh = if (unaccentFunction.size > 0) { "${unaccentFunction}(${p2})" } else { p2 }
        let summaryPh = if (unaccentFunction.size > 0) { "${unaccentFunction}(${p3})" } else { p3 }
        return "(${titleExpr} LIKE ${titlePh} ESCAPE '\\' OR ${filenameExpr} LIKE ${filenamePh} ESCAPE '\\' OR ${summaryExpr} LIKE ${summaryPh} ESCAPE '\\' OR " +
            buildTagLikeCondition(pattern, params, tableAlias, unaccentFunction)
    }

    private static func buildMetadataTagLikeCondition(
        pattern: String,
        params: ParamBuilder,
        entityType: String,
        entityIdExpr: String,
        unaccentFunction: String
    ): String {
        let p1 = params.addText(pattern)
        let p2 = params.addText(pattern)
        let nameExpr = if (unaccentFunction.size > 0) {
            "${unaccentFunction}(substring(mt.tag FROM position(':' IN mt.tag) + 1))"
        } else {
            "substring(mt.tag FROM position(':' IN mt.tag) + 1)"
        }
        let tagExpr = if (unaccentFunction.size > 0) { "${unaccentFunction}(mt.tag)" } else { "mt.tag" }
        let namePh = if (unaccentFunction.size > 0) { "${unaccentFunction}(${p1})" } else { p1 }
        let tagPh = if (unaccentFunction.size > 0) { "${unaccentFunction}(${p2})" } else { p2 }
        return "EXISTS (SELECT 1 FROM metadata_objects mo JOIN metadata_tags mt ON mt.metadata_id = mo.id WHERE mo.entity_type = '${entityType}' AND mo.entity_id = ${entityIdExpr} AND ((position(':' IN mt.tag) > 0 AND ${nameExpr} LIKE ${namePh} ESCAPE '\\') OR ${tagExpr} LIKE ${tagPh} ESCAPE '\\'))"
    }

    private static func buildTankoubonTextMatchCondition(
        pattern: String,
        params: ParamBuilder,
        unaccentFunction: String
    ): String {
        let p1 = params.addText(pattern)
        let p2 = params.addText(pattern)
        let p3 = params.addText(pattern)
        let titleExpr = wrapSearchExpr("tankoubon_metadata.title", unaccentFunction)
        let summaryExpr = wrapSearchExpr("tankoubon_metadata.description", unaccentFunction)
        let idExpr = wrapSearchExpr("tb.tankoubon_id", unaccentFunction)
        let titlePh = if (unaccentFunction.size > 0) { "${unaccentFunction}(${p1})" } else { p1 }
        let summaryPh = if (unaccentFunction.size > 0) { "${unaccentFunction}(${p2})" } else { p2 }
        let idPh = if (unaccentFunction.size > 0) { "${unaccentFunction}(${p3})" } else { p3 }
        return "(${titleExpr} LIKE ${titlePh} ESCAPE '\\' OR ${summaryExpr} LIKE ${summaryPh} ESCAPE '\\' OR ${idExpr} LIKE ${idPh} ESCAPE '\\' OR " +
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

    private static func appendCategoryFilter(whereConditions: ArrayList<String>, filterParams: ParamBuilder, category: String) {
        let categoryValues = parseCategoryFilterValues(category)
        if (categoryValues.size > 0) {
            if (categoryValues.size == 1) {
                let ph = filterParams.addText(categoryValues[0])
                whereConditions.add("archive_metadata_search.category_id = ${ph}")
                return
            }

            // 多值：使用 ANY($n::bigint[]) 以单个占位符绑定数组，保持 $n 编号与值一一对应。
            let arr = Array<DbValue>(categoryValues.size, { k => DbText(categoryValues[k]) })
            let ph = filterParams.addRaw(DbArray(arr))
            whereConditions.add("archive_metadata_search.category_id IN (SELECT CAST(unnest(${ph}::text[])) AS BIGINT)")
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
    private static func buildExactTagMatchCondition(tagToken: String, params: ParamBuilder, tableAlias: String): String {
        let t = tagToken.trimAscii()
        if (t.contains(":")) {
            let idxOpt = t.indexOf(":")
            match (idxOpt) {
                case Some(idx) =>
                    let ns = if (idx > 0) { t[0..idx] } else { "" }
                    let name = if (idx + 1 < t.size) { t[idx + 1..t.size] } else { "" }
                    let namespaced = if (ns.size > 0) { "${ns}:${name}" } else { name }
                    let ph = params.addText(namespaced)
                    return "EXISTS (SELECT 1 FROM metadata_objects mo JOIN metadata_tags mt ON mt.metadata_id = mo.id WHERE mo.entity_type = 'archive' AND mo.entity_id = ${tableAlias}.arcid AND mt.tag = ${ph})"
                case None => ()
            }
        }
        let ph = params.addText(t)
        return "EXISTS (SELECT 1 FROM metadata_objects mo JOIN metadata_tags mt ON mt.metadata_id = mo.id WHERE mo.entity_type = 'archive' AND mo.entity_id = ${tableAlias}.arcid AND mt.tag = ${ph})"
    }

    private static func buildExactTagMatchConditionWithCandidates(
        tagToken: String,
        translatedTags: ArrayList<String>,
        params: ParamBuilder,
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

    private static func preloadTranslatedTags(searchResult: SearchFilterResult): HashMap<String, ArrayList<String>> {
        let terms = collectTranslationLookupTerms(searchResult)
        if (terms.size == 0) {
            return HashMap<String, ArrayList<String>>()
        }
        return TagDao.batchFindTagsByTranslationWithConn(terms)
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
    private static func buildTagLikeCondition(pattern: String, params: ParamBuilder, tableAlias: String, unaccentFunction: String): String {
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
     * 获取所有归档
     */
    public static func getAllArchives(): Array<ArchiveData> {
        try {
            let rows = DatabaseConfig.driver().query(
                "SELECT arcid AS arcid, title AS title, filename AS filename, summary AS summary, thumbhash AS thumbhash, cover_asset_id AS cover_asset_id, created_at AS created_at, updated_at AS updated_at, release_at AS release_at, relative_path AS relative_path, file_size AS file_size, pagecount AS pagecount, archive_type AS archive_type, category_id AS category_id FROM archive_metadata_search ORDER BY id",
                Array<DbValue>()
            )
            var archives = ArrayList<ArchiveData>()
            for (r in rows) {
                let archive = ArchiveData()
                archive.id = r.getText("arcid")
                archive.title = r.getText("title")
                archive.filename = r.getText("filename")
                archive.summary = r.getText("summary")
                archive.thumbhash = r.getText("thumbhash")
                archive.cover_asset_id = r.getInt("cover_asset_id")
                archive.created_at = r.getText("created_at")
                archive.updated_at = r.getText("updated_at")
                archive.release_at = r.getText("release_at")
                archive.relative_path = r.getText("relative_path")
                archive.file_size = r.getInt("file_size")
                archive.pagecount = Int32(r.getInt("pagecount"))
                archive.archive_type = r.getText("archive_type")
                if (archive.archive_type.size == 0) { archive.archive_type = "archive" }
                archive.category_id = r.getInt("category_id")
                archives.add(archive)
            }
            return archives.toArray()
        } catch (e: Exception) {
            getLogger("archive_dao").error("查询归档失败", ("error", e.message))
            return Array<ArchiveData>()
        }
    }

    /**
     * 根据 ID 获取归档
     */
    public static func getArchiveById(id: String): ArchiveData {
        try {
            let rows = DatabaseConfig.driver().query(
                "SELECT arcid AS arcid, title AS title, filename AS filename, summary AS summary, thumbhash AS thumbhash, cover_asset_id AS cover_asset_id, created_at AS created_at, updated_at AS updated_at, release_at AS release_at, relative_path AS relative_path, file_size AS file_size, pagecount AS pagecount, archive_type AS archive_type, category_id AS category_id FROM archive_metadata_search WHERE arcid = $1",
                [DbText(id)]
            )
            if (rows.size > 0) {
                let r = rows[0]
                let archive = ArchiveData()
                archive.id = r.getText("arcid")
                archive.title = r.getText("title")
                archive.filename = r.getText("filename")
                archive.summary = r.getText("summary")
                archive.thumbhash = r.getText("thumbhash")
                archive.cover_asset_id = r.getInt("cover_asset_id")
                archive.created_at = r.getText("created_at")
                archive.updated_at = r.getText("updated_at")
                archive.release_at = r.getText("release_at")
                archive.relative_path = r.getText("relative_path")
                archive.file_size = r.getInt("file_size")
                archive.pagecount = Int32(r.getInt("pagecount"))
                archive.archive_type = r.getText("archive_type")
                if (archive.archive_type.size == 0) { archive.archive_type = "archive" }
                archive.category_id = r.getInt("category_id")
                return archive
            }
        } catch (e: Exception) {
            getLogger("archive_dao").error("查询归档失败", ("error", e.message))
        }
        return ArchiveData()
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

        try {
            let idsArr = Array<DbValue>(deduped.size, { k => DbText(deduped[k]) })
            let rows = DatabaseConfig.driver().query(
                "SELECT arcid AS arcid, id AS id, title AS title, filename AS filename, summary AS summary, thumbhash AS thumbhash, cover_asset_id AS cover_asset_id, created_at AS created_at, updated_at AS updated_at, release_at AS release_at, relative_path AS relative_path, file_size AS file_size, pagecount AS pagecount, archive_type AS archive_type, category_id AS category_id, tags AS tags FROM archive_metadata_search WHERE arcid = ANY($1::text[])",
                [DbArray(idsArr)]
            )
            for (r in rows) {
                let archive = ArchiveData()
                archive.id = r.getText("arcid")
                archive.internalId = r.getInt("id")
                archive.title = r.getText("title")
                archive.filename = r.getText("filename")
                archive.summary = r.getText("summary")
                archive.thumbhash = r.getText("thumbhash")
                archive.cover_asset_id = r.getInt("cover_asset_id")
                archive.created_at = r.getText("created_at")
                archive.updated_at = r.getText("updated_at")
                archive.release_at = r.getText("release_at")
                archive.relative_path = r.getText("relative_path")
                archive.file_size = r.getInt("file_size")
                archive.pagecount = Int32(r.getInt("pagecount"))
                archive.archive_type = r.getText("archive_type")
                if (archive.archive_type.size == 0) { archive.archive_type = "archive" }
                archive.category_id = r.getInt("category_id")
                archive.tags = r.getText("tags")
                if (archive.id.trimAscii().size > 0) {
                    result[archive.id] = archive
                }
            }
        } catch (e: Exception) {
            getLogger("archive_dao").error("批量查询归档失败", ("error", e.message))
        }

        return result
    }

    /**
     * 根据 arcid 获取 archives 表的内部 ID（INTEGER）
     */
    public static func getArchiveInternalId(arcid: String): Int64 {
        try {
            let rows = DatabaseConfig.driver().query("SELECT id AS id FROM archives WHERE arcid = $1", [DbText(arcid)])
            if (rows.size > 0) {
                return rows[0].getInt("id")
            }
        } catch (e: Exception) {
            getLogger("archive_dao").error("查询归档内部ID失败", ("error", e.message))
        }
        return 0
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

    /**
     * 构建搜索的 WHERE 条件片段与对应的参数列表。
     * 由于 countSql 与 dataSql 共享同一组 WHERE 条件，但 dataSql 在 WHERE 之前可能
     * 存在前置参数（orderJoinPrefix，即 tank_order 的 JOIN 占位符），导致 WHERE 中
     * 的 $n 起始编号不同。因此本函数接受一个 `base` 偏移：WHERE 中首个占位符编号为
     * `base + 1`。countSql 传入 base=0；dataSql 传入 base=orderJoinPrefix.size。
     * 返回 (whereClause 字符串, 对应的 params 列表)。
     */
    private static func buildSearchWhereClause(
        filter: String,
        category: String,
        newOnly: Bool,
        untaggedOnly: Bool,
        favoriteOnly: Bool,
        dateFrom: String,
        dateTo: String,
        userId: Int64,
        tankoubonId: String,
        sortby: String,
        resolvedDateField: String,
        unaccentFunction: String,
        translatedTagsLookup: HashMap<String, ArrayList<String>>,
        base: Int64
    ): (String, ArrayList<DbValue>) {
        var whereConditions = ArrayList<String>()
        let searchResult = SearchFilter.parse(filter)
        let filterParams = ParamBuilder()
        filterParams.idx = base  // WHERE 占位符从 base+1 开始编号

        // 处理普通搜索词（支持通配符和翻译搜索）
        if (searchResult.terms.size > 0) {
            var termConditions = ArrayList<String>()
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
            whereConditions.add("NOT EXISTS (SELECT 1 FROM user_archive_status uas JOIN archives a ON a.id = uas.archive_id WHERE a.arcid = archive_metadata_search.arcid AND uas.user_id = ${userId} AND uas.is_new = false)")
        }

        // 按 lastread 排序时，移除从未阅读的记录
        // 根据 API 文档："If you sort by lastread, IDs that have never been read will be removed from the search."
        // 使用 user_archive_status 表判断用户是否阅读过（is_new = false 表示已读）
        // 注意：未登录用户会被重定向到登录页，所以这里只处理已登录用户
        if ((sortby == "lastread" || sortby == "lastreadtime") && userId > 0) {
            // 只显示用户已读的档案（在 user_archive_status 表中有记录且 is_new = false）
            whereConditions.add("EXISTS (SELECT 1 FROM user_archive_status uas JOIN archives a ON a.id = uas.archive_id WHERE a.arcid = archive_metadata_search.arcid AND uas.user_id = ${userId} AND uas.is_new = false)")
        }

        // 添加无标签过滤条件
        if (untaggedOnly) {
            whereConditions.add("NOT EXISTS (SELECT 1 FROM metadata_objects mo JOIN metadata_tags mt ON mt.metadata_id = mo.id WHERE mo.entity_type = 'archive' AND mo.entity_id = archive_metadata_search.arcid)")
        }

        // favoriteOnly 过滤 - 只显示用户收藏的档案
        // 当 favoriteOnly=true 且 userId > 0 时，只返回用户收藏的归档
        if (favoriteOnly && userId > 0) {
            whereConditions.add("EXISTS (SELECT 1 FROM user_favorites uf JOIN archives a ON a.id = uf.archive_id WHERE a.arcid = archive_metadata_search.arcid AND uf.user_id = ${userId})")
        }

        // 分类过滤
        appendCategoryFilter(whereConditions, filterParams, category)

        // tankoubon_id 过滤 - 只返回某个合集中的归档
        if (tankoubonId.size > 0) {
            let ph = filterParams.addText(tankoubonId)
            whereConditions.add("EXISTS (SELECT 1 FROM tankoubons t JOIN tankoubon_archives ta ON ta.tankoubon_id = t.id WHERE t.tankoubon_id = ${ph} AND ta.archive_id = archive_metadata_search.id)")
        }

        // 日期范围过滤
        if (dateFrom.size > 0) {
            let ph = filterParams.addText(dateFrom)
            whereConditions.add("${resolvedDateField} >= ${ph}")
        }
        if (dateTo.size > 0) {
            let ph = filterParams.addText(dateTo + " 23:59:59")
            whereConditions.add("${resolvedDateField} <= ${ph}")
        }

        // 组合基础 WHERE（不包含相关度阈值）
        var baseWhereClause = ""
        for (i in 0..whereConditions.size) {
            if (i > 0) {
                baseWhereClause += " AND "
            }
            baseWhereClause += whereConditions[i]
        }

        return (baseWhereClause, filterParams.values)
    }

    public static func searchArchives(filter: String, category: String, start: Int32, count: Int32, sortby: String, order: String, newOnly: Bool, untaggedOnly: Bool, favoriteOnly: Bool, dateFrom: String, dateTo: String, userId: Int64, tankoubonId: String): (Array<ArchiveData>, Int64) {
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
            let unaccentFunction = getUnaccentFunction()
            let searchResult = SearchFilter.parse(filter)
            let translatedTagsLookup = preloadTranslatedTags(searchResult)

            getLogger("archive_dao").info("搜索过滤器解析结果",
                ("filter", filter),
                ("terms", searchResult.terms.size.toString()))

            // 构建相关度评分表达式。
            // 优化：当存在 relevance 时，在 SQL 内部用 CTE 计算一次 relevance_score，
            // 然后复用于阈值过滤/排序，避免重复拼接/重复计算表达式。
            let relevanceExpr = buildRelevanceExpr(filter, "", unaccentFunction)
            let hasRelevance = filter.size > 0 && relevanceExpr != "1"
            let minRelevanceThreshold = 0.05  // 最低相关度阈值

            // countSql：WHERE 条件占位符从 $1 开始（base = 0）。
            let (baseWhereClause, countFilterValues) = buildSearchWhereClause(
                filter, category, newOnly, untaggedOnly, favoriteOnly,
                dateFrom, dateTo, userId, tankoubonId, sortby, resolvedDateField,
                unaccentFunction, translatedTagsLookup, 0
            )

            // 构建计数 SQL
            var countSql = "SELECT COUNT(*) FROM archive_metadata_search"
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
            var totalCount: Int64 = 0
            let countRows = DatabaseConfig.driver().query(countSql, countFilterValues.toArray())
            if (countRows.size > 0) {
                totalCount = countRows[0].getInt("count")
                getLogger("archive_dao").debug("获取到总记录数", ("count", totalCount.toString()))
            } else {
                getLogger("archive_dao").error("无法获取总记录数")
            }

            // 然后查询分页数据
            var sql = ""
            var orderJoinPrefix: ArrayList<DbValue> = ArrayList<DbValue>()
            var hasTankOrderJoin = false
            if (!hasRelevance) {
                // 无 relevance：保持原查询形态
                sql = "SELECT archive_metadata_search.id AS id, archive_metadata_search.arcid AS arcid, archive_metadata_search.filename AS filename, archive_metadata_search.title AS title, archive_metadata_search.summary AS summary, archive_metadata_search.thumbhash AS thumbhash, archive_metadata_search.cover_asset_id AS cover_asset_id, archive_metadata_search.created_at AS created_at, archive_metadata_search.updated_at AS updated_at, archive_metadata_search.release_at AS release_at, archive_metadata_search.relative_path AS relative_path, archive_metadata_search.file_size AS file_size, archive_metadata_search.pagecount AS pagecount, archive_metadata_search.archive_type AS archive_type, archive_metadata_search.tags AS tags FROM archive_metadata_search"
                if (sortby == "tank_order" && tankoubonId.size > 0) {
                    sql += " LEFT JOIN tankoubons t_order ON t_order.tankoubon_id = $1"
                    sql += " LEFT JOIN tankoubon_archives ta_order ON ta_order.tankoubon_id = t_order.id AND ta_order.archive_id = archive_metadata_search.id"
                    orderJoinPrefix.add(DbText(tankoubonId))
                    hasTankOrderJoin = true
                }
                if (baseWhereClause.size > 0) {
                    sql += " WHERE " + baseWhereClause
                }
            } else {
                // 有 relevance：在 base CTE 里计算 relevance_score，并在外层应用阈值过滤
                sql = "WITH base AS (SELECT archive_metadata_search.id AS id, archive_metadata_search.arcid AS arcid, archive_metadata_search.filename AS filename, archive_metadata_search.title AS title, archive_metadata_search.summary AS summary, archive_metadata_search.thumbhash AS thumbhash, archive_metadata_search.cover_asset_id AS cover_asset_id, archive_metadata_search.created_at AS created_at, archive_metadata_search.updated_at AS updated_at, archive_metadata_search.release_at AS release_at, archive_metadata_search.relative_path AS relative_path, archive_metadata_search.file_size AS file_size, archive_metadata_search.pagecount AS pagecount, archive_metadata_search.archive_type AS archive_type, archive_metadata_search.tags AS tags, (" + relevanceExpr + ") AS relevance_score"
                if (sortby == "tank_order" && tankoubonId.size > 0) {
                    sql += ", ta_order.sort_order AS tank_sort_order"
                }
                sql += " FROM archive_metadata_search"
                if (sortby == "tank_order" && tankoubonId.size > 0) {
                    sql += " LEFT JOIN tankoubons t_order ON t_order.tankoubon_id = $1"
                    sql += " LEFT JOIN tankoubon_archives ta_order ON ta_order.tankoubon_id = t_order.id AND ta_order.archive_id = archive_metadata_search.id"
                    orderJoinPrefix.add(DbText(tankoubonId))
                    hasTankOrderJoin = true
                }
                if (baseWhereClause.size > 0) {
                    sql += " WHERE " + baseWhereClause
                }
                sql += ") SELECT id AS id, arcid AS arcid, filename AS filename, title AS title, summary AS summary, thumbhash AS thumbhash, cover_asset_id AS cover_asset_id, created_at AS created_at, updated_at AS updated_at, release_at AS release_at, relative_path AS relative_path, file_size AS file_size, pagecount AS pagecount, archive_type AS archive_type, tags AS tags FROM base WHERE relevance_score >= " + minRelevanceThreshold.toString()
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
                sql += " ORDER BY (SELECT MAX(uas.updated_at) FROM user_archive_status uas JOIN (SELECT id, arcid AS archive_arcid FROM archives) a ON a.id = uas.archive_id WHERE a.archive_arcid = arcid AND uas.user_id = ${userId}) ${orderDirection}"
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

            // 当存在 tank_order JOIN 前置占位符时，WHERE 中的 $n 需要从 orderJoinPrefix.size+1 开始。
            // 因此这里重新构建 dataSql 使用的 WHERE 条件，以正确的 base 偏移重新编号占位符。
            var dataParams = ArrayList<DbValue>()
            var dataWhereClause = baseWhereClause
            if (hasTankOrderJoin) {
                // 重新以 base = orderJoinPrefix.size 构建 WHERE，使 $n 编号在 dataSql 中正确衔接。
                let (rewrittenWhere, rewrittenValues) = buildSearchWhereClause(
                    filter, category, newOnly, untaggedOnly, favoriteOnly,
                    dateFrom, dateTo, userId, tankoubonId, sortby, resolvedDateField,
                    unaccentFunction, translatedTagsLookup, Int64(orderJoinPrefix.size)
                )
                dataWhereClause = rewrittenWhere
                dataParams = orderJoinPrefix
                for (v in rewrittenValues) {
                    dataParams.add(v)
                }
            } else {
                dataParams = orderJoinPrefix
                for (v in countFilterValues) {
                    dataParams.add(v)
                }
            }

            // 用重新编号后的 WHERE 替换 sql 中原本的 baseWhereClause。
            // （baseWhereClause 与 dataWhereClause 内容相同，仅 $n 编号不同。）
            if (baseWhereClause.size > 0) {
                // sql 中包含 " WHERE " + baseWhereClause 片段；替换为 dataWhereClause。
                let oldFragment = " WHERE " + baseWhereClause
                let newFragment = " WHERE " + dataWhereClause
                sql = sql.replace(oldFragment, newFragment)
            }

            let rows = DatabaseConfig.driver().query(sql, dataParams.toArray())

            getLogger("archive_dao").info("SQL查询执行完成")

            for (r in rows) {
                let archive = ArchiveData()
                try {
                    archive.internalId = r.getInt("id")
                    archive.id = r.getText("arcid")
                    archive.filename = r.getText("filename")
                    archive.title = r.getText("title")
                    archive.summary = r.getText("summary")
                    archive.thumbhash = r.getText("thumbhash")
                    archive.cover_asset_id = r.getInt("cover_asset_id")
                    archive.created_at = r.getText("created_at")
                    archive.updated_at = r.getText("updated_at")
                    archive.release_at = r.getText("release_at")
                    archive.relative_path = r.getText("relative_path")
                    archive.file_size = r.getInt("file_size")
                    archive.pagecount = Int32(r.getInt("pagecount"))
                    archive.archive_type = r.getText("archive_type")
                    if (archive.archive_type.size == 0) { archive.archive_type = "archive" }
                    archive.tags = r.getText("tags")
                    archives.add(archive)
                } catch (e: Exception) {
                    getLogger("archive_dao").error("读取字段时出错", ("error", e.message))
                    throw e
                }
            }

            let resultArray = archives.toArray()
            getLogger("archive_dao").info("查询完成", ("records", resultArray.size.toString()), ("total_count", totalCount.toString()))
            return (resultArray, totalCount)
        } catch (e: Exception) {
            getLogger("archive_dao").error("搜索归档失败", ("error", e.message))
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
            let unaccentFunction = getUnaccentFunction()
            let searchResult = SearchFilter.parse(filter)
            let translatedTagsLookup = preloadTranslatedTags(searchResult)

            // Build WHERE conditions (mostly copied from searchArchives to keep semantics identical).
            // grouped 版的 WHERE 构建与 searchArchives 一致，但本方法中 dataSql 的 tank_order JOIN
            // 前置占位符也需重新编号。这里先以 base=0 构建 countSql 用 WHERE。
            let (baseWhereClauseRaw, _) = buildGroupedWhereClause(
                filter, category, newOnly, untaggedOnly, favoriteOnly,
                dateFrom, dateTo, userId, tankoubonId, resolvedDateField,
                unaccentFunction, translatedTagsLookup, sortby, 0
            )

            let archiveRelevanceExpr = buildRelevanceExpr(filter, "archive_metadata_search.", unaccentFunction)
            let tankRelevanceExpr = buildTankoubonRelevanceExpr(filter, unaccentFunction)
            let relevanceExpr = if (archiveRelevanceExpr == "1") {
                "1"
            } else {
                "(" + archiveRelevanceExpr + ") + (" + tankRelevanceExpr + ")"
            }
            let minRelevanceThreshold = 0.05

            var whereClause = ""
            if (baseWhereClauseRaw.size > 0 || filter.size > 0) {
                whereClause = baseWhereClauseRaw
                if (filter.size > 0 && relevanceExpr != "1") {
                    if (whereClause.size > 0) { whereClause += " AND " }
                    whereClause += "(" + relevanceExpr + ") >= " + minRelevanceThreshold.toString()
                }
            }

            // Count distinct groups (tankoubon_id or arcid).
            var countSql = """
                SELECT COUNT(DISTINCT COALESCE(tb.tankoubon_id, archive_metadata_search.arcid)) AS count
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

            // 重新构建 countSql 用的 WHERE 与参数（base=0）。
            let (countWhere, countValuesList) = buildGroupedWhereClause(
                filter, category, newOnly, untaggedOnly, favoriteOnly,
                dateFrom, dateTo, userId, tankoubonId, resolvedDateField,
                unaccentFunction, translatedTagsLookup, sortby, 0
            )
            var countWhereFinal = countWhere
            if (countWhereFinal.size > 0 || filter.size > 0) {
                if (filter.size > 0 && relevanceExpr != "1") {
                    if (countWhereFinal.size > 0) { countWhereFinal += " AND " }
                    countWhereFinal += "(" + relevanceExpr + ") >= " + minRelevanceThreshold.toString()
                }
            }
            if (countWhereFinal.size > 0) {
                countSql = countSql.replace(" WHERE " + whereClause, " WHERE " + countWhereFinal)
            }

            getLogger("archive_dao").debug("执行分组计数SQL", ("sql", countSql))
            var totalGroups: Int64 = 0
            let countRows = DatabaseConfig.driver().query(countSql, countValuesList.toArray())
            if (countRows.size > 0) {
                totalGroups = countRows[0].getInt("count")
            }

            // Build ORDER BY for representative row selection (must match ungrouped search ordering).
            var windowOrderBy = ""
            var finalOrderBy = ""
            var orderJoinPrefix: ArrayList<DbValue> = ArrayList<DbValue>()
            if (sortby == "RANDOM()") {
                windowOrderBy = "RANDOM() DESC"
                finalOrderBy = "RANDOM() DESC"
            } else if (sortby == "title") {
                let dir = if (order == "desc") { "DESC" } else { "ASC" }
                windowOrderBy = "title ${dir}"
                finalOrderBy = "title ${dir}"
            } else if ((sortby == "lastread" || sortby == "lastreadtime") && userId > 0) {
                let dir = if (order == "desc") { "DESC" } else { "ASC" }
                let windowExpr = "(SELECT MAX(uas.updated_at) FROM user_archive_status uas JOIN (SELECT id, arcid AS archive_arcid FROM archives) a ON a.id = uas.archive_id WHERE a.archive_arcid = base.arcid AND uas.user_id = ${userId})"
                let finalExpr = "(SELECT MAX(uas.updated_at) FROM user_archive_status uas JOIN (SELECT id, arcid AS archive_arcid FROM archives) a ON a.id = uas.archive_id WHERE a.archive_arcid = arcid AND uas.user_id = ${userId})"
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
                orderJoinPrefix.add(DbText(tankoubonId))
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
            // dataSql 中 tank_order JOIN 前置占位符为 $1，WHERE 占位符从 $2 开始（base = 1）。
            let dataBase = Int64(orderJoinPrefix.size)
            let (dataWhereClause, dataValuesList) = buildGroupedWhereClause(
                filter, category, newOnly, untaggedOnly, favoriteOnly,
                dateFrom, dateTo, userId, tankoubonId, resolvedDateField,
                unaccentFunction, translatedTagsLookup, sortby, dataBase
            )
            var dataWhereFinal = dataWhereClause
            if (dataWhereFinal.size > 0 || filter.size > 0) {
                if (filter.size > 0 && relevanceExpr != "1") {
                    if (dataWhereFinal.size > 0) { dataWhereFinal += " AND " }
                    dataWhereFinal += "(" + relevanceExpr + ") >= " + minRelevanceThreshold.toString()
                }
            }

            var dataSql = """
                WITH base AS (
                    SELECT
                        archive_metadata_search.id AS id,
                        archive_metadata_search.arcid AS arcid,
                        archive_metadata_search.filename AS filename,
                        archive_metadata_search.title AS title,
                        archive_metadata_search.summary AS summary,
                        archive_metadata_search.thumbhash AS thumbhash,
                        archive_metadata_search.cover_asset_id AS cover_asset_id,
                        archive_metadata_search.created_at AS created_at,
                        archive_metadata_search.updated_at AS updated_at,
                        archive_metadata_search.release_at AS release_at,
                        archive_metadata_search.relative_path AS relative_path,
                        archive_metadata_search.file_size AS file_size,
                        archive_metadata_search.pagecount AS pagecount,
                        archive_metadata_search.archive_type AS archive_type,
                        archive_metadata_search.tags AS tags,
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
                dataSql += " LEFT JOIN tankoubons t_order ON t_order.tankoubon_id = $1"
                dataSql += " LEFT JOIN tankoubon_archives ta_order ON ta_order.tankoubon_id = t_order.id AND ta_order.archive_id = archive_metadata_search.id"
            }
            if (dataWhereFinal.size > 0) {
                dataSql += " WHERE " + dataWhereFinal
            }

            dataSql += """
                ),
                ranked AS (
                    SELECT base.*,
                           ROW_NUMBER() OVER (PARTITION BY base.group_item_id ORDER BY ${windowOrderBy}) AS rn
                    FROM base
                )
                SELECT
                    id AS id, arcid AS arcid, filename AS filename, title AS title, summary AS summary, thumbhash AS thumbhash, cover_asset_id AS cover_asset_id, created_at AS created_at, updated_at AS updated_at, release_at AS release_at,
                    relative_path AS relative_path, file_size AS file_size, pagecount AS pagecount, archive_type AS archive_type, tags AS tags, group_item_type AS group_item_type, group_item_id AS group_item_id
                FROM ranked
                WHERE rn = 1
                ORDER BY ${finalOrderBy}
                LIMIT ${count} OFFSET ${start}
            """

            // 组装 dataSql 参数：orderJoinPrefix 前置 + WHERE 参数。
            var dataParams = ArrayList<DbValue>()
            for (v in orderJoinPrefix) {
                dataParams.add(v)
            }
            for (v in dataValuesList) {
                dataParams.add(v)
            }

            getLogger("archive_dao").debug("执行分组数据SQL", ("sql", dataSql))
            let rows = DatabaseConfig.driver().query(dataSql, dataParams.toArray())

            for (r in rows) {
                let archive = ArchiveData()
                archive.internalId = r.getInt("id")
                archive.id = r.getText("arcid")
                archive.filename = r.getText("filename")
                archive.title = r.getText("title")
                archive.summary = r.getText("summary")
                archive.thumbhash = r.getText("thumbhash")
                archive.cover_asset_id = r.getInt("cover_asset_id")
                archive.created_at = r.getText("created_at")
                archive.updated_at = r.getText("updated_at")
                archive.release_at = r.getText("release_at")
                archive.relative_path = r.getText("relative_path")
                archive.file_size = r.getInt("file_size")
                archive.pagecount = Int32(r.getInt("pagecount"))
                archive.archive_type = r.getText("archive_type")
                if (archive.archive_type.size == 0) { archive.archive_type = "archive" }
                archive.tags = r.getText("tags")
                archive.group_item_type = r.getText("group_item_type")
                archive.group_item_id = r.getText("group_item_id")
                archives.add(archive)
            }

            return (archives.toArray(), totalGroups)
        } catch (e: Exception) {
            getLogger("archive_dao").error("分组搜索归档失败", ("error", e.message))
            return (Array<ArchiveData>(), 0)
        }
    }

    /**
     * 构建 grouped search 的 WHERE 条件（含 tankoubon 文本匹配）。
     * 与 buildSearchWhereClause 类似，但额外加入 buildTankoubonTextMatchCondition 的 OR 条件。
     * 同样接受 base 偏移以支持 dataSql 的前置 JOIN 占位符重编号。
     */
    private static func buildGroupedWhereClause(
        filter: String,
        category: String,
        newOnly: Bool,
        untaggedOnly: Bool,
        favoriteOnly: Bool,
        dateFrom: String,
        dateTo: String,
        userId: Int64,
        tankoubonId: String,
        resolvedDateField: String,
        unaccentFunction: String,
        translatedTagsLookup: HashMap<String, ArrayList<String>>,
        sortby: String,
        base: Int64
    ): (String, ArrayList<DbValue>) {
        var whereConditions = ArrayList<String>()
        let searchResult = SearchFilter.parse(filter)
        let filterParams = ParamBuilder()
        filterParams.idx = base

        // 处理普通搜索词（支持通配符和翻译搜索）
        if (searchResult.terms.size > 0) {
            var termConditions = ArrayList<String>()
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
            whereConditions.add("NOT EXISTS (SELECT 1 FROM user_archive_status uas JOIN archives a ON a.id = uas.archive_id WHERE a.arcid = archive_metadata_search.arcid AND uas.user_id = ${userId} AND uas.is_new = false)")
        }

        // 按 lastread 排序时，移除从未阅读的记录
        if ((sortby == "lastread" || sortby == "lastreadtime") && userId > 0) {
            whereConditions.add("EXISTS (SELECT 1 FROM user_archive_status uas JOIN archives a ON a.id = uas.archive_id WHERE a.arcid = archive_metadata_search.arcid AND uas.user_id = ${userId} AND uas.is_new = false)")
        }

        if (untaggedOnly) {
            whereConditions.add("NOT EXISTS (SELECT 1 FROM metadata_objects mo JOIN metadata_tags mt ON mt.metadata_id = mo.id WHERE mo.entity_type = 'archive' AND mo.entity_id = archive_metadata_search.arcid)")
        }

        if (favoriteOnly && userId > 0) {
            whereConditions.add("EXISTS (SELECT 1 FROM user_favorites uf JOIN archives a ON a.id = uf.archive_id WHERE a.arcid = archive_metadata_search.arcid AND uf.user_id = ${userId})")
        }

        appendCategoryFilter(whereConditions, filterParams, category)

        if (tankoubonId.size > 0) {
            let ph = filterParams.addText(tankoubonId)
            whereConditions.add("EXISTS (SELECT 1 FROM tankoubons t JOIN tankoubon_archives ta ON ta.tankoubon_id = t.id WHERE t.tankoubon_id = ${ph} AND ta.archive_id = archive_metadata_search.id)")
        }

        if (dateFrom.size > 0) {
            let ph = filterParams.addText(dateFrom)
            whereConditions.add("archive_metadata_search.${resolvedDateField} >= ${ph}")
        }
        if (dateTo.size > 0) {
            let ph = filterParams.addText(dateTo + " 23:59:59")
            whereConditions.add("archive_metadata_search.${resolvedDateField} <= ${ph}")
        }

        var whereClause = ""
        for (i in 0..whereConditions.size) {
            if (i > 0) { whereClause += " AND " }
            whereClause += whereConditions[i]
        }

        return (whereClause, filterParams.values)
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

        try {
            let idsArr = Array<DbValue>(arcids.size, { k => DbText(arcids[k]) })
            let rows = DatabaseConfig.driver().query("""
                SELECT a.arcid AS arcid, t.tankoubon_id AS tankoubon_id
                FROM tankoubon_archives ta
                JOIN tankoubons t ON t.id = ta.tankoubon_id
                JOIN archives a ON a.id = ta.archive_id
                WHERE a.arcid = ANY($1::text[])
            """, [DbArray(idsArr)])
            for (r in rows) {
                let arcid = r.getText("arcid")
                let tankoubonId = r.getText("tankoubon_id")
                if (arcid != "" && tankoubonId != "") {
                    mapping[arcid] = tankoubonId
                }
            }
        } catch (e: Exception) {
            logger.error("获取归档Tankoubon映射失败", ("error", e.message))
        }

        return mapping
    }

    /**
     * 创建归档记录
     */
    public static func create(archive: ArchiveData): Bool {
        try {
            let affected = DatabaseConfig.driver().exec(
                "INSERT INTO archives (arcid, filename, thumbhash, relative_path, file_size, pagecount, archive_type, category_id) VALUES ($1, $2, $3, $4, $5, $6, $7, $8)",
                [DbText(archive.id), DbText(archive.filename), DbText(archive.thumbhash), DbText(archive.relative_path), DbInt(archive.file_size), DbInt(Int64(archive.pagecount)), DbText(archive.archive_type), DbInt(archive.category_id)]
            )
            if (affected <= 0) {
                return false
            }
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
        try {
            // 使用数据库的默认值来处理时间戳，避免格式问题
            let affected = DatabaseConfig.driver().exec(
                "INSERT INTO archives (arcid, filename, thumbhash, relative_path, file_size, pagecount, archive_type, category_id) VALUES ($1, $2, $3, $4, $5, $6, $7, $8)",
                [DbText(archiveId), DbText(fileName), DbText(""), DbText(relativePath), DbInt(fileSize), DbInt(Int64(pageCount)), DbText(archiveType), DbInt(categoryId)]
            )
            if (affected <= 0) {
                return false
            }
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
    }

    /**
     * 更新归档记录
     */
    public static func update(archive: ArchiveData): Bool {
        try {
            let affected = DatabaseConfig.driver().exec(
                "UPDATE archives SET filename = $1, thumbhash = $2, relative_path = $3, file_size = $4, pagecount = $5, archive_type = $6, category_id = $7 WHERE arcid = $8",
                [DbText(archive.filename), DbText(archive.thumbhash), DbText(archive.relative_path), DbInt(archive.file_size), DbInt(Int64(archive.pagecount)), DbText(archive.archive_type), DbInt(archive.category_id), DbText(archive.id)]
            )
            if (affected <= 0) {
                return false
            }
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
    }

    /**
     * 删除归档记录
     */
    public static func delete(id: String): Bool {
        try {
            let affected = DatabaseConfig.driver().exec("DELETE FROM archives WHERE arcid = $1", [DbText(id)])
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
    }

    /**
     * 更新归档的页数
     */
    public static func updatePageCount(archiveId: String, pageCount: Int32): Bool {
        try {
            DatabaseConfig.driver().exec(
                "UPDATE archives SET pagecount = $1 WHERE arcid = $2",
                [DbInt(Int64(pageCount)), DbText(archiveId)]
            )
            invalidateTankoubonAggregatedContent("updatePageCount:${archiveId}")
            return true
        } catch (e: Exception) {
            logger.error("更新归档页数失败", ("error", e.message))
            return false
        }
    }

    /**
     * 更新归档的缩略图hash
     */
    public static func updateThumbHash(archiveId: String, thumbHash: String): Bool {
        try {
            DatabaseConfig.driver().exec(
                "UPDATE archives SET thumbhash = $1 WHERE arcid = $2",
                [DbText(thumbHash), DbText(archiveId)]
            )
            return true
        } catch (e: Exception) {
            logger.error("更新归档缩略图hash失败", ("error", e.message))
            return false
        }
    }

    /**
     * 同时更新归档的页数和缩略图hash
     */
    public static func updateArchiveDetails(archiveId: String, pageCount: Int32, thumbHash: String): Bool {
        try {
            DatabaseConfig.driver().exec(
                "UPDATE archives SET pagecount = $1, thumbhash = $2 WHERE arcid = $3",
                [DbInt(Int64(pageCount)), DbText(thumbHash), DbText(archiveId)]
            )
            invalidateTankoubonAggregatedContent("updateArchiveDetails:${archiveId}")
            return true
        } catch (e: Exception) {
            logger.error("更新归档详情失败", ("error", e.message))
            return false
        }
    }

    /**
     * 更新归档的相对路径
     */
    public static func updateArchiveRelativePath(archiveId: String, relativePath: String): Bool {
        try {
            DatabaseConfig.driver().exec(
                "UPDATE archives SET relative_path = $1 WHERE arcid = $2",
                [DbText(relativePath), DbText(archiveId)]
            )
            return true
        } catch (e: Exception) {
            getLogger("archive_dao").error("更新归档相对路径失败", ("error", e.message))
            return false
        }
    }

    /**
     * 获取所有没有缩略图的归档
     */
    public static func getArchivesWithoutThumbnails(): Array<ArchiveData> {
        try {
            let rows = DatabaseConfig.driver().query(
                "SELECT arcid AS arcid, title AS title, filename AS filename, summary AS summary, thumbhash AS thumbhash, cover_asset_id AS cover_asset_id, created_at AS created_at, updated_at AS updated_at, release_at AS release_at, relative_path AS relative_path, file_size AS file_size, pagecount AS pagecount, category_id AS category_id FROM archive_metadata_search WHERE thumbhash = '' OR thumbhash IS NULL ORDER BY id",
                Array<DbValue>()
            )
            var archives = ArrayList<ArchiveData>()
            for (r in rows) {
                let archive = ArchiveData()
                archive.id = r.getText("arcid")
                archive.title = r.getText("title")
                archive.filename = r.getText("filename")
                archive.summary = r.getText("summary")
                archive.thumbhash = r.getText("thumbhash")
                archive.cover_asset_id = r.getInt("cover_asset_id")
                archive.created_at = r.getText("created_at")
                archive.updated_at = r.getText("updated_at")
                archive.release_at = r.getText("release_at")
                archive.relative_path = r.getText("relative_path")
                archive.file_size = r.getInt("file_size")
                archive.pagecount = Int32(r.getInt("pagecount"))
                archive.category_id = r.getInt("category_id")
                archives.add(archive)
            }
            return archives.toArray()
        } catch (e: Exception) {
            getLogger("archive_dao").error("获取无缩略图归档失败", ("error", e.message))
            return Array<ArchiveData>()
        }
    }

    /**
     * 检查归档是否存在
     */
    public static func exists(id: String): Bool {
        try {
            let rows = DatabaseConfig.driver().query("SELECT COUNT(*) AS count FROM archives WHERE arcid = $1", [DbText(id)])
            if (rows.size > 0) {
                let count = rows[0].getInt("count")
                return count > 0
            }
            return false
        } catch (e: Exception) {
            getLogger("archive_dao").error("检查归档存在性失败", ("error", e.message))
            return false
        }
    }

    /**
     * 根据文件路径获取归档信息
     */
    public static func getByPath(filePath: String): Option<ArchiveData> {
        try {
            let rows = DatabaseConfig.driver().query(
                "SELECT arcid AS arcid, title AS title, filename AS filename, summary AS summary, thumbhash AS thumbhash, cover_asset_id AS cover_asset_id, created_at AS created_at, updated_at AS updated_at, release_at AS release_at, relative_path AS relative_path, file_size AS file_size, pagecount AS pagecount, category_id AS category_id FROM archive_metadata_search WHERE relative_path = $1",
                [DbText(filePath)]
            )
            if (rows.size > 0) {
                let r = rows[0]
                let archive = ArchiveData()
                archive.id = r.getText("arcid")
                archive.title = r.getText("title")
                archive.filename = r.getText("filename")
                archive.summary = r.getText("summary")
                archive.thumbhash = r.getText("thumbhash")
                archive.cover_asset_id = r.getInt("cover_asset_id")
                archive.created_at = r.getText("created_at")
                archive.updated_at = r.getText("updated_at")
                archive.release_at = r.getText("release_at")
                archive.relative_path = r.getText("relative_path")
                archive.file_size = r.getInt("file_size")
                archive.pagecount = Int32(r.getInt("pagecount"))
                archive.category_id = r.getInt("category_id")
                return Some(archive)
            }
            return None
        } catch (e: Exception) {
            getLogger("archive_dao").error("根据路径获取归档失败", ("error", e.message))
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
        try {
            let rows = DatabaseConfig.driver().query(
                "SELECT arcid AS arcid, title AS title, filename AS filename, summary AS summary, thumbhash AS thumbhash, cover_asset_id AS cover_asset_id, created_at AS created_at, updated_at AS updated_at, release_at AS release_at, relative_path AS relative_path, file_size AS file_size, pagecount AS pagecount, category_id AS category_id FROM archive_metadata_search WHERE category_id = $1 AND relative_path = $2 AND filename = $3",
                [DbInt(categoryId), DbText(relativePath), DbText(filename)]
            )
            if (rows.size > 0) {
                let r = rows[0]
                let archive = ArchiveData()
                archive.id = r.getText("arcid")
                archive.title = r.getText("title")
                archive.filename = r.getText("filename")
                archive.summary = r.getText("summary")
                archive.thumbhash = r.getText("thumbhash")
                archive.cover_asset_id = r.getInt("cover_asset_id")
                archive.created_at = r.getText("created_at")
                archive.updated_at = r.getText("updated_at")
                archive.release_at = r.getText("release_at")
                archive.relative_path = r.getText("relative_path")
                archive.file_size = r.getInt("file_size")
                archive.pagecount = Int32(r.getInt("pagecount"))
                archive.category_id = r.getInt("category_id")
                return Some(archive)
            }
            return None
        } catch (e: Exception) {
            getLogger("archive_dao").error("根据分类+路径和文件名获取归档失败", ("error", e.message))
            return None
        }
    }

    /**
     * 根据相对路径和文件名获取归档
     */
    public static func getByPathAndFilename(relativePath: String, filename: String): Option<ArchiveData> {
        try {
            let rows = DatabaseConfig.driver().query(
                "SELECT arcid AS arcid, title AS title, filename AS filename, summary AS summary, thumbhash AS thumbhash, cover_asset_id AS cover_asset_id, created_at AS created_at, updated_at AS updated_at, release_at AS release_at, relative_path AS relative_path, file_size AS file_size, pagecount AS pagecount, category_id AS category_id FROM archive_metadata_search WHERE relative_path = $1 AND filename = $2",
                [DbText(relativePath), DbText(filename)]
            )
            if (rows.size > 0) {
                let r = rows[0]
                let archive = ArchiveData()
                archive.id = r.getText("arcid")
                archive.title = r.getText("title")
                archive.filename = r.getText("filename")
                archive.summary = r.getText("summary")
                archive.thumbhash = r.getText("thumbhash")
                archive.cover_asset_id = r.getInt("cover_asset_id")
                archive.created_at = r.getText("created_at")
                archive.updated_at = r.getText("updated_at")
                archive.release_at = r.getText("release_at")
                archive.relative_path = r.getText("relative_path")
                archive.file_size = r.getInt("file_size")
                archive.pagecount = Int32(r.getInt("pagecount"))
                archive.category_id = r.getInt("category_id")
                return Some(archive)
            }
            return None
        } catch (e: Exception) {
            getLogger("archive_dao").error("根据路径和文件名获取归档失败", ("error", e.message))
            return None
        }
    }

    /**
     * 获取归档的缩略图hash
     */
    public static func getThumbnailHash(archiveId: String): String {
        try {
            let rows = DatabaseConfig.driver().query("SELECT thumbhash AS thumbhash FROM archives WHERE arcid = $1", [DbText(archiveId)])
            if (rows.size > 0) {
                return rows[0].getText("thumbhash")
            }
            return ""
        } catch (e: Exception) {
            getLogger("archive_dao").error("获取缩略图hash失败", ("error", e.message))
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
        try {
            let rows = DatabaseConfig.driver().query("""
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
                )::TEXT AS assets_raw
                FROM metadata_objects mo
                WHERE mo.entity_type = 'archive' AND mo.entity_id = $1
                LIMIT 1
            """, [DbText(archiveId)])
            if (rows.size > 0) {
                let raw = rows[0].getText("assets_raw").trimAscii()
                return if (raw.size > 0) { raw } else { "{}" }
            }
            return "{}"
        } catch (_: Exception) {
            return "{}"
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

        try {
            let idsArr = Array<DbValue>(misses.size, { k => DbText(misses[k]) })
            let rows = DatabaseConfig.driver().query("""
                SELECT
                    mo.entity_id AS entity_id,
                    COALESCE(
                        jsonb_object_agg(ma.slot, to_jsonb(ma.asset_id))
                            FILTER (WHERE ma.asset_id > 0),
                        '{}'::jsonb
                    )::TEXT AS assets_raw
                FROM metadata_objects mo
                LEFT JOIN metadata_assets ma ON ma.metadata_id = mo.id
                WHERE mo.entity_type = 'archive'
                  AND mo.entity_id = ANY($1::text[])
                GROUP BY mo.id, mo.entity_id
            """, [DbArray(idsArr)])
            for (r in rows) {
                let arcid = r.getText("entity_id").trimAscii()
                let raw = r.getText("assets_raw").trimAscii()
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

        try {
            DatabaseConfig.driver().exec("""
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
            """, [DbText(archiveId), DbText(payload)])
            let _ = MetadataDao.touchRootMetadataObject("archive", archiveId)
            invalidateArchiveAssetsRaw("updateArchiveAssetsRaw:${archiveId}")
            return true
        } catch (e: Exception) {
            logger.error("更新归档 assets JSON 失败", ("arcid", archiveId), ("error", e.message))
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

        var ids = ArrayList<Int64>()
        try {
            let rows = DatabaseConfig.driver().query("""
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
            """, [DbInt(categoryId), DbInt(Int64(limit))])
            for (r in rows) {
                let id = r.getInt("cover_asset_id")
                if (id > 0) { ids.add(id) }
            }
        } catch (e: Exception) {
            getLogger("archive_dao").error("获取分类封面资源ID列表失败", ("error", e.message))
        }
        return ids.toArray()
    }

    /**
     * Check if an archive exists by arcid.
     */
    public static func archiveExists(archiveId: String): Bool {
        let trimmed = archiveId.trimAscii()
        if (trimmed.size == 0) { return false }
        try {
            let rows = DatabaseConfig.driver().query("SELECT 1 AS one FROM archives WHERE arcid = $1 LIMIT 1", [DbText(trimmed)])
            return rows.size > 0
        } catch (_: Exception) {
            return false
        }
    }

    /**
     * 根据 ID 获取归档元数据（包含标签）
     */
    public static func getArchiveMetadataById(id: String): ArchiveData {
        try {
            // 使用 archive_metadata_search 视图获取包含标签的数据
            let rows = DatabaseConfig.driver().query(
                "SELECT arcid AS arcid, filename AS filename, title AS title, summary AS summary, thumbhash AS thumbhash, cover_asset_id AS cover_asset_id, created_at AS created_at, updated_at AS updated_at, release_at AS release_at, relative_path AS relative_path, file_size AS file_size, pagecount AS pagecount, archive_type AS archive_type, tags AS tags FROM archive_metadata_search WHERE arcid = $1",
                [DbText(id)]
            )
            if (rows.size > 0) {
                let r = rows[0]
                let archive = ArchiveData()
                archive.id = r.getText("arcid")
                archive.filename = r.getText("filename")
                archive.title = r.getText("title")
                archive.summary = r.getText("summary")
                archive.thumbhash = r.getText("thumbhash")
                archive.cover_asset_id = r.getInt("cover_asset_id")
                archive.created_at = r.getText("created_at")
                archive.updated_at = r.getText("updated_at")
                archive.release_at = r.getText("release_at")
                archive.relative_path = r.getText("relative_path")
                archive.file_size = r.getInt("file_size")
                archive.pagecount = Int32(r.getInt("pagecount"))
                archive.archive_type = r.getText("archive_type")
                if (archive.archive_type.size == 0) { archive.archive_type = "archive" }
                archive.tags = r.getText("tags")
                return archive
            }
        } catch (e: Exception) {
            getLogger("archive_dao").error("查询归档元数据失败", ("error", e.message))
        }
        return ArchiveData()
    }

    /**
     * 获取档案所属分类的 scan_path（轻量查询，避免额外聚合）
     */
    public static func getArchiveScanPathByArcid(arcid: String): String {
        try {
            let rows = DatabaseConfig.driver().query("""
                SELECT c.scan_path AS scan_path
                FROM archives a
                JOIN categories c ON c.id = a.category_id
                WHERE a.arcid = $1
                LIMIT 1
            """, [DbText(arcid)])
            if (rows.size > 0) {
                return rows[0].getText("scan_path")
            }
            return ""
        } catch (e: Exception) {
            getLogger("archive_dao").error("获取档案扫描路径失败", ("error", e.message))
            return ""
        }
    }

    /**
     * 获取档案的 category_id
     */
    public static func getArchiveCategoryId(arcid: String): Int64 {
        try {
            let rows = DatabaseConfig.driver().query("SELECT category_id AS category_id FROM archives WHERE arcid = $1", [DbText(arcid)])
            if (rows.size > 0) {
                return rows[0].getInt("category_id")
            }
            return 0
        } catch (e: Exception) {
            getLogger("archive_dao").error("获取档案分类ID失败", ("error", e.message))
            return 0
        }
    }

    /**
     * 清理所有 Archive 的 thumbhash 字段
     * @return 清理的记录数，失败返回 -1
     */
    public static func clearAllThumbhash(): Int64 {
        try {
            return DatabaseConfig.driver().exec("UPDATE archives SET thumbhash = '' WHERE thumbhash != '' AND thumbhash IS NOT NULL", Array<DbValue>())
        } catch (e: Exception) {
            getLogger("archive_dao").error("清理所有thumbhash失败", ("error", e.message))
            return -1
        }
    }

    /**
     * 更新档案的 category_id
     */
    public static func updateArchiveCategoryId(arcid: String, categoryId: Int64): Bool {
        try {
            let affected = DatabaseConfig.driver().exec(
                "UPDATE archives SET category_id = $1 WHERE arcid = $2",
                [DbInt(categoryId), DbText(arcid)]
            )
            if (affected > 0) {
                invalidateArchiveBasePath("updateArchiveCategoryId:${arcid}")
            }
            return affected > 0
        } catch (e: Exception) {
            getLogger("archive_dao").error("更新档案分类ID失败", ("error", e.message))
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

        try {
            let rows = DatabaseConfig.driver().query("""
                SELECT a.id AS id, a.arcid AS arcid, a.filename AS filename, a.relative_path AS relative_path, a.archive_type AS archive_type, a.category_id AS category_id,
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
            """, [DbInt(afterInternalId), DbInt(Int64(limit))])
            for (r in rows) {
                let row = ArchiveCoverRegenerationRow()
                row.archiveInternalId = r.getInt("id")
                row.archiveId = r.getText("arcid")
                row.filename = r.getText("filename")
                row.relativePath = r.getText("relative_path")
                row.archiveType = r.getText("archive_type")
                if (row.archiveType.size == 0) { row.archiveType = "archive" }
                row.categoryId = r.getInt("category_id")
                row.coverAssetId = r.getInt("cover_asset_id")
                row.thumbhash = r.getText("thumbhash")
                row.categoryScanPath = r.getText("scan_path")
                result.add(row)
            }
        } catch (e: Exception) {
            getLogger("archive_dao").error("getArchivesForCoverRegeneration failed", ("error", e.message))
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

        try {
            let rows = DatabaseConfig.driver().query("""
                SELECT a.id AS id,
                       a.arcid AS arcid,
                       a.category_id AS category_id,
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
            """, [DbInt(afterInternalId), DbInt(Int64(limit))])
            for (r in rows) {
                let row = ArchiveMetadataBackfillRow()
                row.archiveInternalId = r.getInt("id")
                row.archiveId = r.getText("arcid")
                row.categoryId = r.getInt("category_id")
                let plugins = r.getText("plugins_json")
                row.categoryPlugins = if (plugins.size > 0) { plugins } else { "[]" }
                result.add(row)
            }
        } catch (e: Exception) {
            getLogger("archive_dao").error("getArchivesNeedingMetadataBackfill failed", ("error", e.message))
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