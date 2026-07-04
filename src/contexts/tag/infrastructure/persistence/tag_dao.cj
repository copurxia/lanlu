package lanlu.contexts.tag.infrastructure.persistence

import ace_orm.*
import lanlu.shared.config.*
import lanlu.shared.utils.*
import lanlu.infrastructure.kv.*
import std.collection.*
import stdx.log.*
import std.io.{ByteBuffer, readToEnd}
import stdx.encoding.json.stream.*

/**
 * 标签翻译数据结构
 */
public class TagTranslation {
    public var text: String = ""
    public var intro: String = ""

    public init() {}

    public init(text: String, intro: String) {
        this.text = text
        this.intro = intro
    }
}

/**
 * 标签数据结构（新版：支持 JSONB translations）
 */
public class TagData {
    public var id: Int64 = 0
    public var namespace: String = ""
    public var name: String = ""
    public var translations: HashMap<String, TagTranslation> = HashMap<String, TagTranslation>()
    public var links: String = ""
    public var iconAssetId: Int64 = 0
    public var backgroundAssetId: Int64 = 0
    public var created_at: String = ""
    public var updated_at: String = ""

    public init() {}

    /**
     * 获取完整标签名（namespace:name 格式）
     */
    public func getFullName(): String {
        if (namespace.size > 0) {
            return "${namespace}:${name}"
        }
        return name
    }

    /**
     * 获取指定语言的翻译
     */
    public func getTranslation(lang: String): ?TagTranslation {
        return translations.get(lang)
    }

    /**
     * 获取指定语言的翻译文本，如果不存在则返回原始名称
     */
    public func getTranslatedText(lang: String): String {
        match (translations.get(lang)) {
            case Some(t) => if (t.text.size > 0) { return t.text }
            case None => ()
        }
        return name
    }
}

/**
 * 轻量标签结构（用于分页/批处理场景，避免解析完整 translations JSON）
 */
public class TagLiteData {
    public var id: Int64 = 0
    public var namespace: String = ""
    public var name: String = ""
    // 指定语言的翻译文本（不存在则为空字符串）
    public var translationText: String = ""

    public init() {}
}

/**
 * 标签数据访问对象
 */
public class TagDao {
    private static let logger = getLogger("tag_dao")
    private static let translationSearchCacheTtlSeconds: Int64 = 6 * 60 * 60

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
     * 解析 namespace:name 格式的标签
     */
    public static func parseTagName(fullName: String): (String, String) {
        let parts = fullName.split(":", 2)
        if (parts.size >= 2) {
            return (parts[0], parts[1])
        }
        return ("", fullName)
    }

    /**
     * 规范化标签字符串为 canonical tag：
     * - trim 前后空白
     * - namespace:name 仅按首个冒号拆分
     * - 去掉空 namespace / 空 name
     */
    public static func canonicalizeTag(fullName: String): String {
        let trimmed = fullName.trimAscii()
        if (trimmed.size == 0) {
            return ""
        }

        let (rawNamespace, rawName) = parseTagName(trimmed)
        let namespace = rawNamespace.trimAscii()
        let name = rawName.trimAscii()
        if (name.size == 0) {
            return ""
        }
        if (namespace.size > 0) {
            return "${namespace}:${name}"
        }
        return name
    }

    /**
     * 规范化标签数组：
     * - canonicalize
     * - 去重
     * - 保持首次出现顺序
     */
    public static func normalizeTags(tags: Array<String>): Array<String> {
        let out = ArrayList<String>()
        let seen = HashSet<String>()
        for (rawTag in tags) {
            let canonical = canonicalizeTag(rawTag)
            if (canonical.size == 0 || seen.contains(canonical)) {
                continue
            }
            seen.add(canonical)
            out.add(canonical)
        }
        return out.toArray()
    }

    /**
     * 判断标签是否属于 source 命名空间（source:xxx）
     */
    public static func isSourceTag(fullName: String): Bool {
        let trimmed = fullName.trimAscii()
        if (trimmed.size == 0) { return false }
        if (trimmed.startsWith("source:")) { return true }
        let (namespace, _) = parseTagName(trimmed)
        return namespace == "source"
    }

    /**
     * 根据 namespace 和 name 获取或创建标签
     */
    public static func getOrCreate(namespace: String, name: String): Int64 {
        try {
            return getOrCreateTagInternal(namespace, name)
        } catch (_: Exception) {
            return 0
        }
    }

    /**
     * 内部方法：获取或创建标签
     */
    private static func getOrCreateTagInternal(namespace: String, name: String): Int64 {
        try {
            let rows = DatabaseConfig.driver().query("SELECT id FROM tags WHERE namespace = $1 AND name = $2 LIMIT 1", [DbText(namespace), DbText(name)])
            if (rows.size > 0) {
                return rows[0].getInt("id")
            }
        } catch (_: Exception) {}

        try {
            DatabaseConfig.driver().exec("""
                INSERT INTO tags (namespace, name)
                SELECT $1, $2
                WHERE NOT EXISTS (
                    SELECT 1 FROM tags WHERE namespace = $3 AND name = $4
                )
            """, [DbText(namespace), DbText(name), DbText(namespace), DbText(name)])
        } catch (_: Exception) {
            // Concurrent inserts may race; reload the row below.
        }

        try {
            let rows = DatabaseConfig.driver().query("SELECT id FROM tags WHERE namespace = $1 AND name = $2 LIMIT 1", [DbText(namespace), DbText(name)])
            if (rows.size > 0) {
                return rows[0].getInt("id")
            }
        } catch (_: Exception) {}

        0
    }

    /**
     * 补齐 tags 字典记录，不修改 metadata_tags。
     * (原 ensureTagDictionaryEntriesWithConnection；ACE 下 driver() 通过 ThreadLocal 自动走事务连接。)
     */
    public static func ensureTagDictionaryEntriesWithConnection(tags: Array<String>): Bool {
        let normalizedTags = normalizeTags(tags)
        try {
            for (tag in normalizedTags) {
                let (rawNamespace, rawName) = parseTagName(tag)
                let namespace = rawNamespace.trimAscii()
                let name = rawName.trimAscii()
                if (name.size == 0) {
                    continue
                }
                let tagId = getOrCreateTagInternal(namespace, name)
                if (tagId <= 0) {
                    logger.error("Failed to ensure tag dictionary entry", ("tag", tag))
                    return false
                }
            }
            return true
        } catch (e: Exception) {
            logger.error("Failed to ensure tag dictionary entries", ("error", e.message))
            return false
        }
    }

    /**
     * 补齐 tags 字典记录，不修改 metadata_tags。
     */
    public static func ensureTagDictionaryEntries(tags: Array<String>): Bool {
        return ensureTagDictionaryEntriesWithConnection(tags)
    }

    /**
     * 更新档案的标签
     * @param archiveId 档案ID
     * @param tagsString 标签字符串（逗号分隔，支持 namespace:name 格式）
     * @return 是否更新成功
     */
    public static func updateArchiveTags(archiveId: String, tagsString: String): Bool {
        try {
            // Ensure archive root metadata exists and resolve metadata id.
            var metadataId: Int64 = 0
            let getRows = DatabaseConfig.driver().query("""
                SELECT id
                FROM metadata_objects
                WHERE entity_type = 'archive' AND entity_id = $1
                LIMIT 1
            """, [DbText(archiveId)])
            if (getRows.size > 0) {
                metadataId = getRows[0].getInt("id")
            }

            if (metadataId <= 0) {
                let createRows = DatabaseConfig.driver().query("""
                    INSERT INTO metadata_objects (
                        entity_type, entity_id, title, description, created_at, updated_at
                    )
                    SELECT
                        'archive',
                        a.arcid,
                        '',
                        '',
                        CURRENT_TIMESTAMP,
                        CURRENT_TIMESTAMP
                    FROM archives a
                    WHERE a.arcid = $1
                    RETURNING id
                """, [DbText(archiveId)])
                if (createRows.size > 0) {
                    metadataId = createRows[0].getInt("id")
                }
            }
            if (metadataId <= 0) {
                return false
            }

            // Delete existing tags for this archive metadata object.
            DatabaseConfig.driver().exec("DELETE FROM metadata_tags WHERE metadata_id = $1", [DbInt(metadataId)])

            // 如果标签字符串为空，直接返回
            if (tagsString.size == 0 || tagsString == "") {
                DatabaseConfig.driver().exec("UPDATE metadata_objects SET updated_at = CURRENT_TIMESTAMP WHERE id = $1", [DbInt(metadataId)])
                let _ = DerivedCacheUtils.bumpTankoubonAggregatedContentVersion("updateArchiveTags:${archiveId}")
                return true
            }

            // 解析标签字符串
            let tags = normalizeTags(parseTagsString(tagsString).toArray())

            if (!ensureTagDictionaryEntriesWithConnection(tags)) {
                return false
            }

            // 为每个标签创建或获取标签ID，并建立关联
            for (tag in tags) {
                let (namespace, name) = parseTagName(tag)
                let normalizedTag = if (namespace.size > 0) { "${namespace}:${name}" } else { name }
                if (normalizedTag.trimAscii().size == 0) {
                    continue
                }

                // Write unified relation into metadata_tags.
                DatabaseConfig.driver().exec("""
                    INSERT INTO metadata_tags (metadata_id, tag)
                    SELECT $1, $2
                    WHERE NOT EXISTS (
                        SELECT 1 FROM metadata_tags WHERE metadata_id = $3 AND tag = $4
                    )
                """, [DbInt(metadataId), DbText(normalizedTag), DbInt(metadataId), DbText(normalizedTag)])
            }

            DatabaseConfig.driver().exec("UPDATE metadata_objects SET updated_at = CURRENT_TIMESTAMP WHERE id = $1", [DbInt(metadataId)])
            let _ = DerivedCacheUtils.bumpTankoubonAggregatedContentVersion("updateArchiveTags:${archiveId}")
            return true
        } catch (e: Exception) {
            logger.error("Error updating archive tags", ("error", e.message))
            return false
        }
    }

    /**
     * 解析标签字符串
     */
    private static func parseTagsString(tagsString: String): ArrayList<String> {
        let tags = tagsString.split(",")
        var result: ArrayList<String> = ArrayList<String>()
        let seen = HashSet<String>()

        for (tag in tags) {
            let canonical = canonicalizeTag(tag)
            if (canonical.size > 0 && !seen.contains(canonical)) {
                seen.add(canonical)
                result.add(canonical)
            }
        }

        return result
    }

    /**
     * 获取档案的所有标签
     */
    public static func getArchiveTags(archiveId: String): String {
        try {
            let rows = DatabaseConfig.driver().query("""
                SELECT COALESCE(string_agg(mt.tag, ',' ORDER BY mt.tag), '') AS tags
                FROM metadata_objects mo
                LEFT JOIN metadata_tags mt ON mt.metadata_id = mo.id
                WHERE mo.entity_type = 'archive'
                  AND mo.entity_id = $1
            """, [DbText(archiveId)])
            if (rows.size > 0) {
                return rows[0].getText("tags")
            }
            return ""
        } catch (e: Exception) {
            logger.error("Error getting archive tags", ("error", e.message))
            return ""
        }
    }

    /**
     * 批量获取档案标签（key=arcid, value=逗号分隔 tags）
     */
    public static func getBatchArchiveTags(archiveIds: Array<String>): HashMap<String, String> {
        let result = HashMap<String, String>()
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
            var placeholders = ""
            var params = ArrayList<DbValue>(0)
            var idx = 1
            for (i in 0..deduped.size) {
                if (i > 0) { placeholders += "," }
                placeholders += "\$${idx.toString()}"
                params.add(DbText(deduped[i]))
                idx += 1
            }

            let rows = DatabaseConfig.driver().query("""
                SELECT mo.entity_id AS entity_id, COALESCE(string_agg(mt.tag, ',' ORDER BY mt.tag), '') AS tags
                FROM metadata_objects mo
                LEFT JOIN metadata_tags mt ON mt.metadata_id = mo.id
                WHERE mo.entity_type = 'archive'
                  AND mo.entity_id IN (${placeholders})
                GROUP BY mo.entity_id
            """, params.toArray())
            for (r in rows) {
                let arcid = r.getText("entity_id").trimAscii()
                if (arcid.size == 0) { continue }
                result[arcid] = r.getText("tags")
            }
        } catch (e: Exception) {
            logger.error("批量获取 archive tags 失败", ("error", e.message))
            return result
        }

        return result
    }

    /**
     * 构造搜索 ILIKE 子句：对 name 与 translations::text 各占一个独立编号占位符。
     * 返回 (sqlFragment, paramsToAdd, nextIdx)。unaccentFunction 为受控 SQL 标识符，直接插值。
     */
    private static func buildSearchClause(unaccentFunction: String, searchPattern: String, startIdx: Int64): (String, Array<DbValue>, Int64) {
        let namePh = "\$${startIdx.toString()}"
        let transPh = "\$${(startIdx + 1).toString()}"
        let nameExpr = wrapSearchExpr("name", unaccentFunction)
        let transExpr = wrapSearchExpr("translations::text", unaccentFunction)
        let nameLike = if (unaccentFunction.size > 0) { "${unaccentFunction}(${namePh})" } else { namePh }
        let transLike = if (unaccentFunction.size > 0) { "${unaccentFunction}(${transPh})" } else { transPh }
        let fragment = " AND (" + nameExpr + " ILIKE " + nameLike +
            " OR " + transExpr + " ILIKE " + transLike + ")"
        return (fragment, [DbText(searchPattern), DbText(searchPattern)], startIdx + 2)
    }

    /**
     * 获取所有标签（支持分页和搜索）
     */
    public static func list(namespace: ?String, query: ?String, limit: Int64, offset: Int64): ArrayList<TagData> {
        try {
            var sql = "SELECT id, namespace, name, translations, links, icon_asset_id, background_asset_id, created_at, updated_at FROM tags WHERE 1=1"
            var params = ArrayList<DbValue>(0)
            let unaccentFunction = getUnaccentFunction()
            var idx: Int64 = 1

            match (namespace) {
                case Some(ns) =>
                    sql += " AND namespace = \$${idx.toString()}"
                    params.add(DbText(ns))
                    idx += 1
                case None => ()
            }

            match (query) {
                case Some(q) =>
                    if (q.size > 0) {
                        let (fragment, addParams, nextIdx) = buildSearchClause(unaccentFunction, "%${q}%", idx)
                        sql += fragment
                        for (p in addParams) {
                            params.add(p)
                        }
                        idx = nextIdx
                    }
                case None => ()
            }

            sql += " ORDER BY namespace, name LIMIT \$${idx.toString()} OFFSET \$${(idx + 1).toString()}"
            params.add(DbInt(limit))
            params.add(DbInt(offset))

            let rows = DatabaseConfig.driver().query(sql, params.toArray())
            var list: ArrayList<TagData> = ArrayList<TagData>()
            for (r in rows) {
                let tag = TagData()
                tag.id = r.getInt("id")
                tag.namespace = r.getText("namespace")
                tag.name = r.getText("name")
                let translationsJson = r.getText("translations")
                tag.translations = parseTranslationsJson(translationsJson)
                tag.links = r.getText("links")
                tag.iconAssetId = r.getInt("icon_asset_id")
                tag.backgroundAssetId = r.getInt("background_asset_id")
                tag.created_at = r.getText("created_at")
                tag.updated_at = r.getText("updated_at")
                list.add(tag)
            }
            return list
        } catch (e: Exception) {
            logger.error("查询标签列表失败", ("error", e.message))
            return ArrayList<TagData>()
        }
    }

    /**
     * 获取标签列表（轻量版，返回指定语言翻译文本；用于大批量分页拉取）
     * - translations JSONB 通过 SQL 提取，不解析整个对象
     */
    public static func listLite(namespace: ?String, query: ?String, lang: String, limit: Int64, offset: Int64): ArrayList<TagLiteData> {
        var effectiveLang = lang.trimAscii()
        if (effectiveLang.size == 0) { effectiveLang = "zh" }
        try {
            var sql = """
                SELECT
                    id,
                    namespace,
                    name,
                    COALESCE(translations -> $1 ->> 'text', '') AS translation_text
                FROM tags
                WHERE 1=1
            """
            var params = ArrayList<DbValue>(0)
            let unaccentFunction = getUnaccentFunction()
            var idx: Int64 = 2

            // First param is lang for JSONB extraction.
            params.add(DbText(effectiveLang))

            match (namespace) {
                case Some(ns) =>
                    sql += " AND namespace = \$${idx.toString()}"
                    params.add(DbText(ns))
                    idx += 1
                case None => ()
            }

            match (query) {
                case Some(q) =>
                    if (q.size > 0) {
                        let (fragment, addParams, nextIdx) = buildSearchClause(unaccentFunction, "%${q}%", idx)
                        sql += fragment
                        for (p in addParams) {
                            params.add(p)
                        }
                        idx = nextIdx
                    }
                case None => ()
            }

            sql += " ORDER BY namespace, name LIMIT \$${idx.toString()} OFFSET \$${(idx + 1).toString()}"
            params.add(DbInt(limit))
            params.add(DbInt(offset))

            let rows = DatabaseConfig.driver().query(sql, params.toArray())
            var list: ArrayList<TagLiteData> = ArrayList<TagLiteData>()
            for (r in rows) {
                let row = TagLiteData()
                row.id = r.getInt("id")
                row.namespace = r.getText("namespace")
                row.name = r.getText("name")
                row.translationText = r.getText("translation_text")
                list.add(row)
            }
            return list
        } catch (e: Exception) {
            logger.error("查询标签轻量列表失败", ("error", e.message))
            // Fallback: use the full list() and derive translation text in-process.
            let full = list(namespace, query, limit, offset)
            var out: ArrayList<TagLiteData> = ArrayList<TagLiteData>()
            for (row in full) {
                let lite = TagLiteData()
                lite.id = row.id
                lite.namespace = row.namespace
                lite.name = row.name
                lite.translationText = row.getTranslatedText(effectiveLang)
                out.add(lite)
            }
            return out
        }
    }

    /**
     * 统计标签数量
     */
    public static func count(namespace: ?String, query: ?String): Int64 {
        try {
            var sql = "SELECT COUNT(*) AS count FROM tags WHERE 1=1"
            var params = ArrayList<DbValue>(0)
            let unaccentFunction = getUnaccentFunction()
            var idx: Int64 = 1

            match (namespace) {
                case Some(ns) =>
                    sql += " AND namespace = \$${idx.toString()}"
                    params.add(DbText(ns))
                    idx += 1
                case None => ()
            }

            match (query) {
                case Some(q) =>
                    if (q.size > 0) {
                        let (fragment, addParams, nextIdx) = buildSearchClause(unaccentFunction, "%${q}%", idx)
                        sql += fragment
                        for (p in addParams) {
                            params.add(p)
                        }
                        idx = nextIdx
                    }
                case None => ()
            }

            let rows = DatabaseConfig.driver().query(sql, params.toArray())
            if (rows.size > 0) {
                return rows[0].getInt("count")
            }
            return 0
        } catch (e: Exception) {
            logger.error("统计标签数量失败", ("error", e.message))
            return 0
        }
    }

    /**
     * 根据ID获取标签
     */
    public static func getById(id: Int64): ?TagData {
        try {
            let rows = DatabaseConfig.driver().query("SELECT id, namespace, name, translations, links, icon_asset_id, background_asset_id, created_at, updated_at FROM tags WHERE id = $1", [DbInt(id)])
            if (rows.size > 0) {
                let r = rows[0]
                let tag = TagData()
                tag.id = r.getInt("id")
                tag.namespace = r.getText("namespace")
                tag.name = r.getText("name")
                let translationsJson = r.getText("translations")
                tag.translations = parseTranslationsJson(translationsJson)
                tag.links = r.getText("links")
                tag.iconAssetId = r.getInt("icon_asset_id")
                tag.backgroundAssetId = r.getInt("background_asset_id")
                tag.created_at = r.getText("created_at")
                tag.updated_at = r.getText("updated_at")
                return Some(tag)
            }
            return None
        } catch (e: Exception) {
            logger.error("查询标签失败", ("error", e.message), ("id", id.toString()))
            return None
        }
    }

    /**
     * 根据 namespace 和 name 获取标签
     */
    public static func getByNamespaceName(namespace: String, name: String): ?TagData {
        try {
            let rows = DatabaseConfig.driver().query("SELECT id, namespace, name, translations, links, icon_asset_id, background_asset_id, created_at, updated_at FROM tags WHERE namespace = $1 AND name = $2", [DbText(namespace), DbText(name)])
            if (rows.size > 0) {
                let r = rows[0]
                let tag = TagData()
                tag.id = r.getInt("id")
                tag.namespace = r.getText("namespace")
                tag.name = r.getText("name")
                let translationsJson = r.getText("translations")
                tag.translations = parseTranslationsJson(translationsJson)
                tag.links = r.getText("links")
                tag.iconAssetId = r.getInt("icon_asset_id")
                tag.backgroundAssetId = r.getInt("background_asset_id")
                tag.created_at = r.getText("created_at")
                tag.updated_at = r.getText("updated_at")
                return Some(tag)
            }
            return None
        } catch (e: Exception) {
            logger.error("查询标签失败", ("error", e.message))
            return None
        }
    }

    /**
     * 创建标签
     */
    public static func create(namespace: String, name: String, translations: HashMap<String, TagTranslation>, links: String): Int64 {
        try {
            let translationsJson = serializeTranslationsJson(translations)
            let rows = DatabaseConfig.driver().query("INSERT INTO tags (namespace, name, translations, links) VALUES ($1, $2, $3::jsonb, $4) RETURNING id", [DbText(namespace), DbText(name), DbText(translationsJson), DbText(links)])
            if (rows.size > 0) {
                let id = rows[0].getInt("id")
                if (id > 0) {
                    invalidateTranslationSearchCache()
                }
                return id
            }
            return 0
        } catch (e: Exception) {
            logger.error("创建标签失败", ("error", e.message), ("namespace", namespace), ("name", name))
            return 0
        }
    }

    /**
     * 更新标签
     */
    public static func update(id: Int64, translations: HashMap<String, TagTranslation>, links: String): Bool {
        try {
            let translationsJson = serializeTranslationsJson(translations)
            DatabaseConfig.driver().exec("UPDATE tags SET translations = $1::jsonb, links = $2, updated_at = CURRENT_TIMESTAMP WHERE id = $3", [DbText(translationsJson), DbText(links), DbInt(id)])
            invalidateTranslationSearchCache()
            return true
        } catch (e: Exception) {
            logger.error("更新标签失败", ("error", e.message), ("id", id.toString()))
            return false
        }
    }

    /**
     * 删除标签
     */
    public static func delete(id: Int64): Bool {
        try {
            DatabaseConfig.driver().exec("DELETE FROM tags WHERE id = $1", [DbInt(id)])
            invalidateTranslationSearchCache()
            return true
        } catch (e: Exception) {
            logger.error("删除标签失败", ("error", e.message), ("id", id.toString()))
            return false
        }
    }

    /**
     * 批量获取标签翻译（用于前端展示）
     * @param tags 标签名数组（namespace:name 格式）
     * @param lang 语言代码
     * @return 标签名 -> 翻译文本的映射
     */
    public static func batchGetTranslations(tags: Array<String>, lang: String): HashMap<String, String> {
        var result: HashMap<String, String> = HashMap<String, String>()
        if (tags.size == 0) {
            return result
        }

        try {
            // Use row-wise IN to avoid long OR chains and keep it index-friendly.
            // WHERE (namespace, name) IN (($1, $2), ($3, $4), ...)
            var tuples: ArrayList<String> = ArrayList<String>()
            var params = ArrayList<DbValue>(0)
            var namespaces = ArrayList<String>()
            var names = ArrayList<String>()
            var idx = 1
            for (tag in tags) {
                let (namespace, name) = parseTagName(tag)
                tuples.add("(\$${idx.toString()}, \$${(idx + 1).toString()})")
                namespaces.add(namespace)
                names.add(name)
                params.add(DbText(namespace))
                params.add(DbText(name))
                idx += 2
            }

            let tuplesStr = String.join(tuples.toArray(), delimiter: ", ")
            let sql = "SELECT namespace AS namespace, name AS name, translations AS translations FROM tags WHERE (namespace, name) IN (" + tuplesStr + ")"
            let rows = DatabaseConfig.driver().query(sql, params.toArray())
            for (r in rows) {
                let namespace = r.getText("namespace")
                let name = r.getText("name")
                let translationsJson = r.getText("translations")
                let translations = parseTranslationsJson(translationsJson)

                let fullName = if (namespace.size > 0) { "${namespace}:${name}" } else { name }

                match (translations.get(lang)) {
                    case Some(t) =>
                        if (t.text.size > 0) {
                            result[fullName] = t.text
                        }
                    case None => ()
                }
            }
        } catch (e: Exception) {
            logger.error("批量获取标签翻译失败", ("error", e.message))
        }
        return result
    }

    /**
     * 获取指定语言的所有标签翻译映射
     */
    public static func getTranslationsMap(lang: String): HashMap<String, String> {
        var result: HashMap<String, String> = HashMap<String, String>()

        try {
            let rows = DatabaseConfig.driver().query("SELECT namespace AS namespace, name AS name, translations AS translations FROM tags", [])
            for (r in rows) {
                let namespace = r.getText("namespace")
                let name = r.getText("name")
                let translationsJson = r.getText("translations")
                let translations = parseTranslationsJson(translationsJson)

                let fullName = if (namespace.size > 0) { "${namespace}:${name}" } else { name }

                match (translations.get(lang)) {
                    case Some(t) =>
                        if (t.text.size > 0) {
                            result[fullName] = t.text
                        }
                    case None => ()
                }
            }
        } catch (e: Exception) {
            logger.error("获取标签翻译映射失败", ("error", e.message))
        }
        return result
    }

    /**
     * 获取所有命名空间
     */
    public static func listNamespaces(): Array<String> {
        try {
            let rows = DatabaseConfig.driver().query("SELECT DISTINCT namespace FROM tags WHERE namespace != '' ORDER BY namespace", [])
            var list: ArrayList<String> = ArrayList<String>()
            for (r in rows) {
                let ns = r.getText("namespace")
                if (ns.size > 0) {
                    list.add(ns)
                }
            }
            return list.toArray()
        } catch (e: Exception) {
            logger.error("获取命名空间列表失败", ("error", e.message))
            return Array<String>()
        }
    }

    /**
     * 获取当前系统已存在的所有标签名（用于自动补全等）
     */
    public static func listAllTagNames(): Array<String> {
        try {
            let rows = DatabaseConfig.driver().query("""
                SELECT DISTINCT
                    CASE WHEN namespace != '' AND namespace IS NOT NULL
                         THEN namespace || ':' || name
                         ELSE name
                    END AS full_name
                FROM tags
                ORDER BY full_name
            """, [])
            var list: ArrayList<String> = ArrayList<String>()
            for (r in rows) {
                let name = r.getText("full_name")
                if (name.trimAscii().size > 0) {
                    list.add(name)
                }
            }
            return list.toArray()
        } catch (e: Exception) {
            logger.error("获取全量标签失败", ("error", e.message))
            return Array<String>()
        }
    }

    /**
     * 插入或更新标签（用于导入）
     */
    public static func upsert(namespace: String, name: String, translations: HashMap<String, TagTranslation>, links: String): Bool {
        try {
            let translationsJson = serializeTranslationsJson(translations)
            let affected = DatabaseConfig.driver().exec("""
                UPDATE tags
                SET translations = $1::jsonb, links = $2, updated_at = CURRENT_TIMESTAMP
                WHERE namespace = $3 AND name = $4
            """, [DbText(translationsJson), DbText(links), DbText(namespace), DbText(name)])
            if (affected <= 0) {
                DatabaseConfig.driver().exec("""
                    INSERT INTO tags (namespace, name, translations, links)
                    SELECT $1, $2, $3::jsonb, $4
                    WHERE NOT EXISTS (
                        SELECT 1 FROM tags WHERE namespace = $5 AND name = $6
                    )
                """, [DbText(namespace), DbText(name), DbText(translationsJson), DbText(links), DbText(namespace), DbText(name)])
            }
            invalidateTranslationSearchCache()
            return true
        } catch (e: Exception) {
            logger.error("upsert标签失败", ("error", e.message), ("namespace", namespace), ("name", name))
            return false
        }
    }

    /**
     * 翻译标签字符串（用于API返回）
     * 将逗号分隔的标签字符串翻译为指定语言，格式为 "namespace:翻译文本"
     * @param tagsString 原始标签字符串（逗号分隔，namespace:name 格式）
     * @param lang 语言代码
     * @return 翻译后的标签字符串
     */
    public static func translateTagsString(tagsString: String, lang: String): String {
        if (tagsString.size == 0 || lang.size == 0) {
            return tagsString
        }

        let tags = parseTagsString(tagsString)
        if (tags.size == 0) {
            return tagsString
        }

        // 获取翻译映射
        let translationsMap = batchGetTranslations(tags.toArray(), lang)

        // 构建翻译后的标签字符串
        var translatedTags: ArrayList<String> = ArrayList<String>()
        for (tag in tags) {
            let (namespace, _) = parseTagName(tag)
            // 查找翻译
            match (translationsMap.get(tag)) {
                case Some(translatedText) =>
                    // 有翻译：namespace:翻译文本
                    if (namespace.size > 0) {
                        translatedTags.add("${namespace}:${translatedText}")
                    } else {
                        translatedTags.add(translatedText)
                    }
                case None =>
                    // 无翻译：保持原样 namespace:name
                    translatedTags.add(tag)
            }
        }

        return String.join(translatedTags.toArray(), delimiter: ", ")
    }

    /**
     * 翻译标签字符串（使用外部提供的翻译映射，避免重复查询数据库）
     * @param tagsString 原始标签字符串（逗号分隔，namespace:name 格式）
     * @param lang 语言代码
     * @param translationsMap 标签全名 -> 翻译文本 的映射（由 batchGetTranslations 生成）
     */
    public static func translateTagsString(tagsString: String, lang: String, translationsMap: HashMap<String, String>): String {
        if (tagsString.size == 0 || lang.size == 0) {
            return tagsString
        }

        let tags = parseTagsString(tagsString)
        if (tags.size == 0) {
            return tagsString
        }

        var translatedTags: ArrayList<String> = ArrayList<String>()
        for (tag in tags) {
            let (namespace, _) = parseTagName(tag)
            match (translationsMap.get(tag)) {
                case Some(translatedText) =>
                    if (namespace.size > 0) {
                        translatedTags.add("${namespace}:${translatedText}")
                    } else {
                        translatedTags.add(translatedText)
                    }
                case None => translatedTags.add(tag)
            }
        }

        return String.join(translatedTags.toArray(), delimiter: ", ")
    }

    /**
     * 反向翻译标签字符串（用于后端存储）
     * 将翻译后的标签字符串还原为原始标签字符串，格式为 "namespace:原始name"
     * @param translatedTagsString 翻译后的标签字符串（逗号分隔，namespace:翻译文本 或 namespace:原始name）
     * @param lang 语言代码
     * @return 原始标签字符串
     */
    public static func reverseTranslateTagsString(translatedTagsString: String, lang: String): String {
        if (translatedTagsString.size == 0 || lang.size == 0) {
            return translatedTagsString
        }

        let tags = parseTagsString(translatedTagsString)
        if (tags.size == 0) {
            return translatedTagsString
        }

        // 获取当前标签的翻译映射（只查询需要的标签，而不是所有标签）
        let allTranslationsMap = batchGetTranslations(tags.toArray(), lang)

        // 构建反向映射：翻译文本 -> 原始标签
        var reverseMap: HashMap<String, String> = HashMap<String, String>()
        for ((originalTag, translatedText) in allTranslationsMap) {
            let (namespace, _) = parseTagName(originalTag)
            let key = if (namespace.size > 0) {
                "${namespace}:${translatedText}"
            } else {
                translatedText
            }
            reverseMap[key] = originalTag
        }

        // 构建还原后的标签字符串
        var originalTags: ArrayList<String> = ArrayList<String>()
        for (translatedTag in tags) {
            let (namespace, translatedText) = parseTagName(translatedTag)
            // 尝试反向查找
            let lookupKey = if (namespace.size > 0) {
                "${namespace}:${translatedText}"
            } else {
                translatedText
            }

            match (reverseMap.get(lookupKey)) {
                case Some(originalTag) =>
                    // 找到原始标签
                    originalTags.add(originalTag)
                case None =>
                    // 没找到，可能是原始标签（无翻译）或无法识别，保持原样
                    originalTags.add(translatedTag)
            }
        }

        return String.join(originalTags.toArray(), delimiter: ", ")
    }

    // ============ 翻译搜索方法 ============

    /**
     * 根据翻译文本模糊查找标签（所有语言）
     * 用于普通搜索词的翻译匹配
     * @param searchTerm 搜索词
     * @return 匹配的标签全名列表（namespace:name 格式）
     */
    public static func findTagsByTranslation(searchTerm: String): ArrayList<String> {
        let normalizedSearchTerm = normalizeTranslationSearchTerm(searchTerm)
        let result = ArrayList<String>()
        if (normalizedSearchTerm.size == 0) {
            return result
        }

        let cacheVersion = DerivedCacheUtils.getTagTranslationSearchVersion()
        let cacheKey = buildTranslationSearchCacheKey(cacheVersion, normalizedSearchTerm)
        match (readTranslationSearchCache(cacheKey)) {
            case Some(cached) =>
                logger.debug("tag translation search cache hit",
                    ("searchTerm", normalizedSearchTerm),
                    ("version", cacheVersion.toString()),
                    ("resultCount", cached.size.toString()))
                return cached
            case None => ()
        }
        logger.debug("tag translation search cache miss",
            ("searchTerm", normalizedSearchTerm),
            ("version", cacheVersion.toString()))

        try {
            let queried = queryTagsByTranslation(normalizedSearchTerm)
            writeTranslationSearchCache(cacheKey, queried)
            logger.debug("tag translation search cache store",
                ("searchTerm", normalizedSearchTerm),
                ("version", cacheVersion.toString()),
                ("resultCount", queried.size.toString()))
            return queried
        } catch (e: Exception) {
            logger.error("根据翻译查找标签失败", ("error", e.message), ("searchTerm", normalizedSearchTerm))
        }

        return result
    }

    /**
     * 根据翻译文本查找标签（避免嵌套连接泄漏）
     * 用于在持有连接/事务的情况下调用，ACE 下 driver() 通过 ThreadLocal 自动走事务连接。
     */
    public static func findTagsByTranslationWithConn(searchTerm: String): ArrayList<String> {
        let normalizedSearchTerm = normalizeTranslationSearchTerm(searchTerm)
        let result = ArrayList<String>()
        if (normalizedSearchTerm.size == 0) {
            return result
        }

        let cacheVersion = DerivedCacheUtils.getTagTranslationSearchVersion()
        let cacheKey = buildTranslationSearchCacheKey(cacheVersion, normalizedSearchTerm)
        match (readTranslationSearchCache(cacheKey)) {
            case Some(cached) =>
                logger.debug("tag translation search cache hit",
                    ("searchTerm", normalizedSearchTerm),
                    ("version", cacheVersion.toString()),
                    ("resultCount", cached.size.toString()),
                    ("withConn", "true"))
                return cached
            case None => ()
        }
        logger.debug("tag translation search cache miss",
            ("searchTerm", normalizedSearchTerm),
            ("version", cacheVersion.toString()),
            ("withConn", "true"))

        let queried = queryTagsByTranslation(normalizedSearchTerm)
        writeTranslationSearchCache(cacheKey, queried)
        logger.debug("tag translation search cache store",
            ("searchTerm", normalizedSearchTerm),
            ("version", cacheVersion.toString()),
            ("resultCount", queried.size.toString()),
            ("withConn", "true"))
        return queried
    }

    /**
     * 批量根据翻译文本查找标签
     * 返回 raw searchTerm -> 匹配标签列表 的映射。
     */
    public static func batchFindTagsByTranslationWithConn(searchTerms: Array<String>): HashMap<String, ArrayList<String>> {
        let result = HashMap<String, ArrayList<String>>()
        if (searchTerms.size == 0) {
            return result
        }

        let normalizedToRawTerms = HashMap<String, ArrayList<String>>()
        let orderedNormalizedTerms = ArrayList<String>()
        for (rawSearchTerm in searchTerms) {
            let raw = rawSearchTerm.trimAscii()
            if (raw.size == 0) {
                continue
            }
            let normalized = normalizeTranslationSearchTerm(raw)
            if (normalized.size == 0) {
                continue
            }

            match (normalizedToRawTerms.get(normalized)) {
                case Some(existing) =>
                    var duplicated = false
                    for (term in existing) {
                        if (term == raw) {
                            duplicated = true
                            break
                        }
                    }
                    if (!duplicated) {
                        existing.add(raw)
                    }
                case None =>
                    let terms = ArrayList<String>()
                    terms.add(raw)
                    normalizedToRawTerms[normalized] = terms
                    orderedNormalizedTerms.add(normalized)
            }
        }

        if (orderedNormalizedTerms.size == 0) {
            return result
        }

        let cacheVersion = DerivedCacheUtils.getTagTranslationSearchVersion()
        let normalizedMatches = HashMap<String, ArrayList<String>>()
        let uncachedNormalizedTerms = ArrayList<String>()
        for (normalized in orderedNormalizedTerms) {
            let cacheKey = buildTranslationSearchCacheKey(cacheVersion, normalized)
            match (readTranslationSearchCache(cacheKey)) {
                case Some(cached) =>
                    normalizedMatches[normalized] = cached
                case None =>
                    uncachedNormalizedTerms.add(normalized)
            }
        }

        if (uncachedNormalizedTerms.size > 0) {
            let queried = queryTagsByTranslations(uncachedNormalizedTerms.toArray())
            for (normalized in uncachedNormalizedTerms) {
                let matches = match (queried.get(normalized)) {
                    case Some(found) => found
                    case None => ArrayList<String>()
                }
                let cacheKey = buildTranslationSearchCacheKey(cacheVersion, normalized)
                writeTranslationSearchCache(cacheKey, matches)
                normalizedMatches[normalized] = matches
            }
        }

        for (normalized in orderedNormalizedTerms) {
            let matches = match (normalizedMatches.get(normalized)) {
                case Some(found) => found
                case None => ArrayList<String>()
            }
            match (normalizedToRawTerms.get(normalized)) {
                case Some(rawTerms) =>
                    for (raw in rawTerms) {
                        result[raw] = matches
                    }
                case None => ()
            }
        }

        return result
    }

    public static func bumpTranslationSearchCacheVersion(): Int64 {
        return DerivedCacheUtils.bumpTagTranslationSearchVersion("tag_dao")
    }

    private static func invalidateTranslationSearchCache(): Unit {
        let nextVersion = bumpTranslationSearchCacheVersion()
        logger.debug("tag translation search cache version bumped", ("version", nextVersion.toString()))
    }

    private static func normalizeTranslationSearchTerm(searchTerm: String): String {
        var normalized = searchTerm
            .replace("　", " ")
            .replace("\t", " ")
            .replace("\r", " ")
            .replace("\n", " ")
            .trimAscii()
            .toAsciiLower()
        if (normalized.size == 0) {
            return ""
        }
        return String.join(normalized.split(" ", removeEmpty: true), delimiter: " ")
    }

    private static func buildTranslationSearchCacheKey(version: Int64, normalizedSearchTerm: String): String {
        return "v${version.toString()}:${normalizedSearchTerm}"
    }

    private static func readTranslationSearchCache(cacheKey: String): Option<ArrayList<String>> {
        let cacheNamespace = DerivedCacheUtils.getTagTranslationSearchNamespace()
        match (PersistentCacheService.get(cacheNamespace, cacheKey)) {
            case Some(payload) =>
                match (decodeCachedTranslationSearchResult(payload)) {
                    case Some(cached) => return Some(cached)
                    case None =>
                        let _ = PersistentCacheService.delete(cacheNamespace, cacheKey)
                        logger.warn("tag translation search cache payload decode failed; evicted key", ("key", cacheKey))
                        return None
                }
            case None => return None
        }
    }

    private static func writeTranslationSearchCache(cacheKey: String, result: ArrayList<String>): Unit {
        let cacheNamespace = DerivedCacheUtils.getTagTranslationSearchNamespace()
        let payload = encodeCachedTranslationSearchResult(result.toArray())
        let _ = PersistentCacheService.set(
            cacheNamespace,
            cacheKey,
            payload,
            translationSearchCacheTtlSeconds
        )
    }

    private static func queryTagsByTranslation(normalizedSearchTerm: String): ArrayList<String> {
        let result = ArrayList<String>()
        try {
            let unaccentFunction = getUnaccentFunction()
            // 使用 translations::text ILIKE 在 JSONB 文本中模糊搜索。
            // Add a LIMIT to cap worst-case work and response size (caller expands matches into OR tags LIKE ...).
            let patternExpr = if (unaccentFunction.size > 0) { "${unaccentFunction}($1)" } else { "$1" }
            let sql = "SELECT namespace AS namespace, name AS name FROM tags WHERE " + wrapSearchExpr("translations::text", unaccentFunction) + " ILIKE " + patternExpr + " LIMIT 200"
            let pattern = "%" + normalizedSearchTerm + "%"
            let rows = DatabaseConfig.driver().query(sql, [DbText(pattern)])
            for (r in rows) {
                let namespace = r.getText("namespace")
                let name = r.getText("name")
                let fullName = if (namespace.size > 0) {
                    "${namespace}:${name}"
                } else {
                    name
                }
                result.add(fullName)
            }
        } catch (e: Exception) {
            logger.error("根据翻译查找标签失败", ("error", e.message), ("searchTerm", normalizedSearchTerm))
        }
        return result
    }

    private static func queryTagsByTranslations(normalizedSearchTerms: Array<String>): HashMap<String, ArrayList<String>> {
        let result = HashMap<String, ArrayList<String>>()
        if (normalizedSearchTerms.size == 0) {
            return result
        }

        let uniqueTerms = ArrayList<String>()
        let seenTerms = HashMap<String, Bool>()
        for (normalizedSearchTerm in normalizedSearchTerms) {
            let normalized = normalizeTranslationSearchTerm(normalizedSearchTerm)
            if (normalized.size == 0 || seenTerms.contains(normalized)) {
                continue
            }
            seenTerms[normalized] = true
            uniqueTerms.add(normalized)
            result[normalized] = ArrayList<String>()
        }

        if (uniqueTerms.size == 0) {
            return result
        }

        try {
            let unaccentFunction = getUnaccentFunction()
            let searchExpr = wrapSearchExpr("translations::text", unaccentFunction)
            let subqueries = ArrayList<String>()
            var params = ArrayList<DbValue>(0)
            var idx = 1
            for (normalized in uniqueTerms) {
                let termPh = "\$${idx.toString()}"
                let patPh = "\$${(idx + 1).toString()}"
                let patExprLocal = if (unaccentFunction.size > 0) { "${unaccentFunction}(${patPh})" } else { patPh }
                subqueries.add("SELECT ${termPh} AS matched_term, namespace AS namespace, name AS name FROM tags WHERE ${searchExpr} ILIKE ${patExprLocal} LIMIT 200")
                params.add(DbText(normalized))
                params.add(DbText("%" + normalized + "%"))
                idx += 2
            }
            let sql = String.join(subqueries.toArray(), delimiter: " UNION ALL ")
            let rows = DatabaseConfig.driver().query(sql, params.toArray())
            let seenByTerm = HashMap<String, HashMap<String, Bool>>()
            for (r in rows) {
                let matchedTerm = r.getText("matched_term")
                let namespace = r.getText("namespace")
                let name = r.getText("name")
                let fullName = if (namespace.size > 0) { "${namespace}:${name}" } else { name }
                if (matchedTerm.size == 0 || fullName.size == 0) {
                    continue
                }

                let seenForTerm = match (seenByTerm.get(matchedTerm)) {
                    case Some(existing) => existing
                    case None =>
                        let created = HashMap<String, Bool>()
                        seenByTerm[matchedTerm] = created
                        created
                }
                if (seenForTerm.contains(fullName)) {
                    continue
                }
                seenForTerm[fullName] = true

                match (result.get(matchedTerm)) {
                    case Some(matches) => matches.add(fullName)
                    case None =>
                        let matches = ArrayList<String>()
                        matches.add(fullName)
                        result[matchedTerm] = matches
                }
            }
        } catch (_: Exception) {
            for (normalized in uniqueTerms) {
                result[normalized] = queryTagsByTranslation(normalized)
            }
        }

        return result
    }

    private static func encodeCachedTranslationSearchResult(tags: Array<String>): String {
        let out = ByteBuffer()
        let w = JsonWriter(out)
        w.startArray()
        for (tag in tags) {
            w.writeValue(tag)
        }
        w.endArray()
        w.flush()
        return String.fromUtf8(readToEnd(out))
    }

    private static func decodeCachedTranslationSearchResult(payload: String): Option<ArrayList<String>> {
        let trimmed = payload.trimAscii()
        if (trimmed.size == 0) {
            return None
        }

        try {
            var buf = ByteBuffer()
            unsafe { buf.write(trimmed.rawData()) }
            let reader = JsonReader(buf)
            if (reader.peek() != Some(BeginArray)) {
                return None
            }

            let result = ArrayList<String>()
            reader.startArray()
            while (reader.peek() != EndArray) {
                result.add(reader.readValue<String>())
            }
            reader.endArray()
            return Some(result)
        } catch (_: Exception) {
            return None
        }
    }

    // ============ JSON 序列化/反序列化辅助方法 ============

    /**
     * 解析 translations JSON 字符串
     */
    private static func parseTranslationsJson(jsonStr: String): HashMap<String, TagTranslation> {
        var result: HashMap<String, TagTranslation> = HashMap<String, TagTranslation>()

        if (jsonStr.size == 0 || jsonStr == "{}") {
            return result
        }

        try {
            var buf = ByteBuffer()
            unsafe { buf.write(jsonStr.rawData()) }
            let r = JsonReader(buf)

            match (r.peek()) {
                case Some(BeginObject) =>
                    r.startObject()
                    while (r.peek() != EndObject) {
                        let lang = r.readName()
                        let translation = TagTranslation()
                        match (r.peek()) {
                            case Some(BeginObject) =>
                                r.startObject()
                                while (r.peek() != EndObject) {
                                    let k = r.readName()
                                    match (k) {
                                        case "text" => translation.text = r.readValue<String>()
                                        case "intro" => translation.intro = r.readValue<String>()
                                        case _ => r.skip()
                                    }
                                }
                                r.endObject()
                                result[lang] = translation
                            case Some(_) =>
                                r.skip()
                            case None => break
                        }
                    }
                    r.endObject()
                case _ => ()
            }
        } catch (e: Exception) {
            logger.warn("解析translations JSON失败", ("error", e.message), ("json", jsonStr))
        }

        return result
    }

    /**
     * 序列化 translations 为 JSON 字符串
     */
    private static func serializeTranslationsJson(translations: HashMap<String, TagTranslation>): String {
        if (translations.size == 0) {
            return "{}"
        }

        let out = ByteBuffer()
        let w = JsonWriter(out)
        w.startObject()
        for ((lang, t) in translations) {
            w.writeName(lang)
            w.startObject()
            w.writeName("text").writeValue(t.text)
            w.writeName("intro").writeValue(t.intro)
            w.endObject()
        }
        w.endObject()
        w.flush()
        return String.fromUtf8(readToEnd(out))
    }

    // ============ 自动补全搜索方法 ============

    /**
     * 自动补全搜索标签
     * 搜索标签名和翻译文本，返回带翻译的结果
     * @param query 搜索词
     * @param lang 语言代码
     * @param limit 返回数量限制
     * @return 匹配的标签列表 [(fullName, translatedText)]
     */
    public static func autocompleteSearch(query: String, lang: String, limit: Int64, requireBound: Bool): ArrayList<(String, String)> {
        var result: ArrayList<(String, String)> = ArrayList<(String, String)>()

        if (query.size == 0) {
            return result
        }

        try {
            let unaccentFunction = getUnaccentFunction()
            // patternExpr 占位符由调用方动态编号填充。
            let nameExpr = wrapSearchExpr("t.name", unaccentFunction)
            let fullNameExpr = wrapSearchExpr("CASE WHEN t.namespace != '' THEN t.namespace || ':' || t.name ELSE t.name END", unaccentFunction)
            let translationTextExpr = wrapSearchExpr("t.translations->$NLANG->>'text'", unaccentFunction)
            let translationsExpr = wrapSearchExpr("t.translations::text", unaccentFunction)
            // 搜索标签名(namespace:name)和翻译文本。
            // 默认只返回“已绑定档案”的标签，供全局搜索框等场景使用；
            // 但编辑档案标签时需要可选到“未绑定任何档案”的标签，因此支持关闭该约束。
            // 使用 JSONB 提取指定语言的翻译文本进行搜索。
            // 优先级：1=name精确匹配, 2=name前缀匹配, 3=翻译精确匹配, 4=翻译前缀匹配, 5=模糊匹配
            //
            // 占位符布局（按绑定顺序）：
            //  $1 exactPattern  (CASE name 精确)
            //  $2 prefixPattern  (CASE name 前缀)
            //  $3 lang           (CASE 翻译精确 语言)
            //  $4 exactPattern   (CASE 翻译精确)
            //  $5 lang           (CASE 翻译前缀 语言)
            //  $6 prefixPattern  (CASE 翻译前缀)
            //  $7 likePattern    (WHERE name 模糊)
            //  $8 likePattern    (WHERE fullName 模糊)
            //  $9 lang           (WHERE 翻译模糊 语言)
            //  $10 likePattern   (WHERE 翻译模糊)
            //  $11 likePattern   (WHERE 全文本模糊)
            //  $12 limit
            let nameExprCase = nameExpr
            // Build SQL with numbered placeholders.
            let caseClause = " CASE" +
                " WHEN " + nameExprCase + " ILIKE $1 THEN 1" +
                " WHEN " + nameExprCase + " ILIKE $2 THEN 2" +
                " WHEN " + translationTextExpr.replace("$NLANG", "$3") + " ILIKE $4 THEN 3" +
                " WHEN " + translationTextExpr.replace("$NLANG", "$5") + " ILIKE $6 THEN 4" +
                " ELSE 5 END as match_priority"
            let sql = if (requireBound) {
                "SELECT DISTINCT t.namespace AS namespace, t.name AS name, t.translations AS translations," +
                caseClause +
                " FROM tags t" +
                " INNER JOIN metadata_tags mt ON mt.tag = CASE WHEN COALESCE(t.namespace, '') != '' THEN t.namespace || ':' || t.name ELSE t.name END" +
                " INNER JOIN metadata_objects mo ON mo.id = mt.metadata_id AND mo.entity_type = 'archive'" +
                " WHERE " + nameExpr + " ILIKE $7" +
                " OR " + fullNameExpr + " ILIKE $8" +
                " OR " + translationTextExpr.replace("$NLANG", "$9") + " ILIKE $10" +
                " OR " + translationsExpr + " ILIKE $11" +
                " ORDER BY match_priority, t.name" +
                " LIMIT $12"
            } else {
                "SELECT DISTINCT t.namespace AS namespace, t.name AS name, t.translations AS translations," +
                caseClause +
                " FROM tags t" +
                " WHERE " + nameExpr + " ILIKE $7" +
                " OR " + fullNameExpr + " ILIKE $8" +
                " OR " + translationTextExpr.replace("$NLANG", "$9") + " ILIKE $10" +
                " OR " + translationsExpr + " ILIKE $11" +
                " ORDER BY match_priority, t.name" +
                " LIMIT $12"
            }
            let exactPattern = query
            let prefixPattern = query + "%"
            let likePattern = "%" + query + "%"
            let rows = DatabaseConfig.driver().query(sql, [
                DbText(exactPattern),       // $1 name 精确匹配优先级
                DbText(prefixPattern),      // $2 name 前缀匹配优先级
                DbText(lang),               // $3 翻译精确匹配的语言
                DbText(exactPattern),       // $4 翻译精确匹配
                DbText(lang),               // $5 翻译前缀匹配的语言
                DbText(prefixPattern),      // $6 翻译前缀匹配
                DbText(likePattern),        // $7 name 模糊搜索
                DbText(likePattern),        // $8 namespace:name 模糊搜索
                DbText(lang),               // $9 翻译搜索的语言
                DbText(likePattern),        // $10 翻译模糊搜索
                DbText(likePattern),        // $11 全文本模糊搜索（备用）
                DbInt(limit)                // $12 limit
            ])
            for (r in rows) {
                let namespace = r.getText("namespace")
                let name = r.getText("name")
                let translationsJson = r.getText("translations")

                let fullName = if (namespace.size > 0) {
                    "${namespace}:${name}"
                } else {
                    name
                }

                // 获取对应语言的翻译
                let translations = parseTranslationsJson(translationsJson)
                let translatedText = match (translations.get(lang)) {
                    case Some(t) => if (t.text.size > 0) { t.text } else { name }
                    case None => name
                }

                result.add((fullName, translatedText))
            }
        } catch (e: Exception) {
            logger.error("自动补全搜索失败", ("error", e.message), ("query", query))
        }
        return result
    }

    /**
     * 获取标签词云数据（按归档使用次数降序）
     * 返回: [(fullName, display, count)]
     */
    public static func getTagCloud(lang: String, limit: Int64): ArrayList<(String, String, Int64)> {
        var result: ArrayList<(String, String, Int64)> = ArrayList<(String, String, Int64)>()
        try {
            let rows = DatabaseConfig.driver().query("""
                SELECT t.namespace AS namespace, t.name AS name,
                       COALESCE(t.translations->$1->>'text', '') AS translated_text,
                       COUNT(DISTINCT mo.entity_id)::BIGINT AS usage_count
                FROM tags t
                INNER JOIN metadata_tags mt ON mt.tag = CASE WHEN COALESCE(t.namespace, '') != '' THEN t.namespace || ':' || t.name ELSE t.name END
                INNER JOIN metadata_objects mo ON mo.id = mt.metadata_id AND mo.entity_type = 'archive'
                WHERE COALESCE(LOWER(t.namespace), '') != 'source'
                GROUP BY t.id, t.namespace, t.name, translated_text
                ORDER BY usage_count DESC, t.name
                LIMIT $2
            """, [DbText(lang), DbInt(limit)])
            for (r in rows) {
                let namespace = r.getText("namespace")
                let name = r.getText("name")
                let translated = r.getText("translated_text")
                let count = r.getInt("usage_count")

                let fullName = if (namespace.size > 0) { "${namespace}:${name}" } else { name }
                let display = if (translated.trimAscii().size > 0) { translated } else { name }
                result.add((fullName, display, count))
            }
        } catch (e: Exception) {
            logger.error("获取标签词云失败", ("error", e.message))
        }
        return result
    }

    public static func updateIconAssetId(id: Int64, iconAssetId: Int64): Bool {
        if (id <= 0) { return false }
        try {
            DatabaseConfig.driver().exec("UPDATE tags SET icon_asset_id = $1, updated_at = CURRENT_TIMESTAMP WHERE id = $2",
                [if (iconAssetId > 0) { DbInt(iconAssetId) } else { DbNull }, DbInt(id)])
            return true
        } catch (e: Exception) {
            logger.error("updateIconAssetId failed", ("error", e.message))
            return false
        }
    }

    public static func updateBackgroundAssetId(id: Int64, backgroundAssetId: Int64): Bool {
        if (id <= 0) { return false }
        try {
            DatabaseConfig.driver().exec("UPDATE tags SET background_asset_id = $1, updated_at = CURRENT_TIMESTAMP WHERE id = $2",
                [if (backgroundAssetId > 0) { DbInt(backgroundAssetId) } else { DbNull }, DbInt(id)])
            return true
        } catch (e: Exception) {
            logger.error("updateBackgroundAssetId failed", ("error", e.message))
            return false
        }
    }

    /**
     * 合并标签（按 id）：将 sourceId 的关联关系迁移到 targetId，并可选删除 sourceId。
     * - metadata_tags：将 source tag string 迁移到 target tag string
     * - tags.translations：将 source 的 translations 合并到 target（target 同 key 优先）
     * - links/icon/background：仅在 target 为空时回填 source 的值
     */
    public static func mergeById(sourceId: Int64, targetId: Int64, deleteSource: Bool): Bool {
        if (sourceId <= 0 || targetId <= 0 || sourceId == targetId) { return false }

        // 使用 ACE 事务（ThreadLocal 钉连接，内部 driver.exec 自动走事务连接）。
        let ok = DatabaseConfig.withTransaction("tag_dao", "mergeById failed", { =>
            // Merge translations/fields: update target from source.
            DatabaseConfig.driver().exec("""
                UPDATE tags t
                SET
                    translations = s.translations || t.translations,
                    links = CASE WHEN COALESCE(t.links, '') = '' THEN COALESCE(s.links, '') ELSE t.links END,
                    icon_asset_id = CASE WHEN COALESCE(t.icon_asset_id, 0) = 0 THEN COALESCE(s.icon_asset_id, 0) ELSE t.icon_asset_id END,
                    background_asset_id = CASE WHEN COALESCE(t.background_asset_id, 0) = 0 THEN COALESCE(s.background_asset_id, 0) ELSE t.background_asset_id END,
                    updated_at = CURRENT_TIMESTAMP
                FROM tags s
                WHERE s.id = $1 AND t.id = $2
            """, [DbInt(sourceId), DbInt(targetId)])

            // Resolve source/target canonical tag strings.
            var sourceTag = ""
            var targetTag = ""
            let tagInfoRows = DatabaseConfig.driver().query("""
                SELECT
                    id AS id,
                    CASE
                        WHEN COALESCE(namespace, '') != '' THEN namespace || ':' || name
                        ELSE name
                    END AS tag_str
                FROM tags
                WHERE id = $1 OR id = $2
            """, [DbInt(sourceId), DbInt(targetId)])
            for (r in tagInfoRows) {
                let id = r.getInt("id")
                let tagStr = r.getText("tag_str")
                if (id == sourceId) {
                    sourceTag = tagStr
                } else if (id == targetId) {
                    targetTag = tagStr
                }
            }

            if (sourceTag.trimAscii().size > 0 && targetTag.trimAscii().size > 0) {
                DatabaseConfig.driver().exec("""
                    INSERT INTO metadata_tags (metadata_id, tag)
                    SELECT mt.metadata_id, $1
                    FROM metadata_tags mt
                    WHERE mt.tag = $2
                      AND NOT EXISTS (
                          SELECT 1 FROM metadata_tags existing
                          WHERE existing.metadata_id = mt.metadata_id AND existing.tag = $3
                      )
                """, [DbText(targetTag), DbText(sourceTag), DbText(targetTag)])

                DatabaseConfig.driver().exec("DELETE FROM metadata_tags WHERE tag = $1", [DbText(sourceTag)])
            }

            if (deleteSource) {
                DatabaseConfig.driver().exec("DELETE FROM tags WHERE id = $1", [DbInt(sourceId)])
            }
            return true
        })
        // withTransaction 返回 true 表示事务已提交成功，此时再失效缓存。
        if (ok) {
            invalidateTranslationSearchCache()
            return true
        }
        return false
    }
}