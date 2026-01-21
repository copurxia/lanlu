package lrr4cj.dao

import std.database.sql.*
import lrr4cj.config.*
import lrr4cj.utils.*
import std.collection.*
import stdx.log.*
import stdx.encoding.json.*
import std.sync.*

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
 * 标签数据访问对象
 */
public class TagDao {
    // Cache for translation-text lookup used by ArchiveDao search expansion.
    // This avoids repeated DB scans of tags.translations on common terms.
    private static var translationSearchCache: HashMap<String, ArrayList<String>> = HashMap<String, ArrayList<String>>()
    private static var translationSearchCacheMutex: Mutex = Mutex()
    private static let translationSearchCacheMaxSize: Int64 = 1024i64

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
        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case None => return 0
            case Some(conn) =>
                try {
                    return getOrCreateTagInternal(conn, namespace, name)
                } finally {
                    try { conn.close() } catch (_: Exception) {}
                }
        }
    }

    /**
     * 内部方法：获取或创建标签（使用已有连接）
     * 使用 INSERT ... ON CONFLICT 避免并发插入时的重复键错误
     */
    private static func getOrCreateTagInternal(conn: Connection, namespace: String, name: String): Int64 {
        // 使用 upsert 模式：尝试插入，如果冲突则返回现有记录的 id
        let stmt = conn.prepareStatement("""
            INSERT INTO tags (namespace, name)
            VALUES (?, ?)
            ON CONFLICT (namespace, name) DO UPDATE SET updated_at = CURRENT_TIMESTAMP
            RETURNING id
        """)
        try {
            stmt.set(0, namespace)
            stmt.set(1, name)
            let result = stmt.query()
            try {
                if (result.next()) {
                    return result.getOrNull<Int64>(0) ?? 0
                }
            } finally {
                result.close()
            }
        } finally {
            stmt.close()
        }

        0
    }

    /**
     * 更新档案的标签
     * @param archiveId 档案ID
     * @param tagsString 标签字符串（逗号分隔，支持 namespace:name 格式）
     * @return 是否更新成功
     */
    public static func updateArchiveTags(archiveId: String, tagsString: String): Bool {
        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case None => false
            case Some(conn) =>
                try {
                    // 首先获取档案的内部ID
                    let getArchiveIdStmt = conn.prepareStatement("SELECT id FROM archives WHERE arcid = ?")
                    var archiveInternalId: Int64 = 0
                    try {
                        getArchiveIdStmt.set(0, archiveId)
                        let archiveIdResult = getArchiveIdStmt.query()
                        try {
                            if (!archiveIdResult.next()) {
                                return false
                            }
                            archiveInternalId = archiveIdResult.getOrNull<Int64>(0) ?? 0
                        } finally {
                            archiveIdResult.close()
                        }
                    } finally {
                        getArchiveIdStmt.close()
                    }

                    // 删除现有的标签关联
                    let deleteStmt = conn.prepareStatement("DELETE FROM archive_tags WHERE archive_id = ?")
                    try {
                        deleteStmt.set(0, archiveInternalId)
                        deleteStmt.update()
                    } finally {
                        deleteStmt.close()
                    }

                    // 如果标签字符串为空，直接返回
                    if (tagsString.size == 0 || tagsString == "") {
                        return true
                    }

                    // 解析标签字符串
                    let tags = parseTagsString(tagsString)

                    // 为每个标签创建或获取标签ID，并建立关联
                    for (tag in tags) {
                        let (namespace, name) = parseTagName(tag)
                        let tagId = getOrCreateTagInternal(conn, namespace, name)

                        // 建立档案和标签的关联
                        let insertRelationStmt = conn.prepareStatement("INSERT INTO archive_tags (archive_id, tag_id) VALUES (?, ?) ON CONFLICT DO NOTHING")
                        try {
                            insertRelationStmt.set(0, archiveInternalId)
                            insertRelationStmt.set(1, tagId)
                            insertRelationStmt.update()
                        } finally {
                            insertRelationStmt.close()
                        }
                    }

                    true
                } catch (e: Exception) {
                    getLogger("tag_dao").error("Error updating archive tags", ("error", e.message))
                    false
                } finally {
                    try {
                        conn.close()
                    } catch (closeException: Exception) {
                        getLogger("tag_dao").warn("Error closing database connection", ("error", closeException.message))
                    }
                }
        }
    }

    /**
     * 解析标签字符串
     */
    private static func parseTagsString(tagsString: String): ArrayList<String> {
        let tags = tagsString.split(",")
        var result: ArrayList<String> = ArrayList<String>()

        for (tag in tags) {
            let trimmed = tag.trimAscii()
            if (trimmed.size > 0) {
                result.add(trimmed)
            }
        }

        return result
    }

    /**
     * 获取档案的所有标签
     */
    public static func getArchiveTags(archiveId: String): String {
        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case None => ""
            case Some(conn) =>
                
                try {
                    let stmt = conn.prepareStatement("SELECT tags FROM archives_with_tags WHERE arcid = ?")
                    try {
                        stmt.set(0, archiveId)
                        let result = stmt.query()
                        try {
                            if (result.next()) {
                                return result.getOrNull<String>(0) ?? ""
                            }
                            return ""
                        } finally {
                            result.close()
                        }
                    } finally {
                        stmt.close()
                    }
                } catch (e: Exception) {
                    getLogger("tag_dao").error("Error getting archive tags", ("error", e.message))
                    ""
                } finally {
                    try { conn.close() } catch (_: Exception) {}
                }
        }
    }

    /**
     * 获取所有标签（支持分页和搜索）
     */
    public static func list(namespace: ?String, query: ?String, limit: Int64, offset: Int64): ArrayList<TagData> {
        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case Some(conn) =>
                
                try {
                    var sql = "SELECT id, namespace, name, translations, links, icon_asset_id, background_asset_id, created_at, updated_at FROM tags WHERE 1=1"
                    var params: ArrayList<String> = ArrayList<String>()

                    match (namespace) {
                        case Some(ns) =>
                            sql += " AND namespace = ?"
                            params.add(ns)
                        case None => ()
                    }

                    match (query) {
                        case Some(q) =>
                            if (q.size > 0) {
                                sql += " AND (name ILIKE ? OR translations::text ILIKE ?)"
                                let searchPattern = "%${q}%"
                                params.add(searchPattern)
                                params.add(searchPattern)
                            }
                        case None => ()
                    }

                    sql += " ORDER BY namespace, name LIMIT ? OFFSET ?"

                    let stmt = conn.prepareStatement(sql)
                    var idx = 0
                    for (p in params) {
                        stmt.set(idx, p)
                        idx++
                    }
                    stmt.set(idx, limit)
                    stmt.set(idx + 1, offset)

                    let rs = stmt.query()
                    var list: ArrayList<TagData> = ArrayList<TagData>()
                    try {
                        while (rs.next()) {
                            let tag = TagData()
                            tag.id = rs.getOrNull<Int64>(0) ?? 0
                            tag.namespace = rs.getOrNull<String>(1) ?? ""
                            tag.name = rs.getOrNull<String>(2) ?? ""
                            let translationsJson = rs.getOrNull<String>(3) ?? "{}"
                            tag.translations = parseTranslationsJson(translationsJson)
                            tag.links = rs.getOrNull<String>(4) ?? ""
                            tag.iconAssetId = rs.getOrNull<Int64>(5) ?? 0
                            tag.backgroundAssetId = rs.getOrNull<Int64>(6) ?? 0
                            tag.created_at = rs.getOrNull<String>(7) ?? ""
                            tag.updated_at = rs.getOrNull<String>(8) ?? ""
                            list.add(tag)
                        }
                    } finally {
                        rs.close()
                        stmt.close()
                    }
                    return list
                } catch (e: Exception) {
                    getLogger("tag_dao").error("查询标签列表失败", ("error", e.message))
                    return ArrayList<TagData>()
                } finally {
                    try { conn.close() } catch (_: Exception) {}
                }
            case None =>
                getLogger("tag_dao").error("无法连接到数据库")
                return ArrayList<TagData>()
        }
    }

    /**
     * 统计标签数量
     */
    public static func count(namespace: ?String, query: ?String): Int64 {
        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case Some(conn) =>
                
                try {
                    var sql = "SELECT COUNT(*) FROM tags WHERE 1=1"
                    var params: ArrayList<String> = ArrayList<String>()

                    match (namespace) {
                        case Some(ns) =>
                            sql += " AND namespace = ?"
                            params.add(ns)
                        case None => ()
                    }

                    match (query) {
                        case Some(q) =>
                            if (q.size > 0) {
                                sql += " AND (name ILIKE ? OR translations::text ILIKE ?)"
                                let searchPattern = "%${q}%"
                                params.add(searchPattern)
                                params.add(searchPattern)
                            }
                        case None => ()
                    }

                    let stmt = conn.prepareStatement(sql)
                    var idx = 0
                    for (p in params) {
                        stmt.set(idx, p)
                        idx++
                    }

                    let rs = stmt.query()
                    try {
                        if (rs.next()) {
                            return rs.getOrNull<Int64>(0) ?? 0
                        }
                    } finally {
                        rs.close()
                        stmt.close()
                    }
                    return 0
                } catch (e: Exception) {
                    getLogger("tag_dao").error("统计标签数量失败", ("error", e.message))
                    return 0
                } finally {
                    try { conn.close() } catch (_: Exception) {}
                }
            case None =>
                return 0
        }
    }

    /**
     * 根据ID获取标签
     */
    public static func getById(id: Int64): ?TagData {
        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case Some(conn) =>
                
                try {
                    let stmt = conn.prepareStatement(
                        "SELECT id, namespace, name, translations, links, icon_asset_id, background_asset_id, created_at, updated_at FROM tags WHERE id = ?")
                    try {
                        stmt.set(0, id)
                        let rs = stmt.query()
                        try {
                            if (rs.next()) {
                                let tag = TagData()
                                tag.id = rs.getOrNull<Int64>(0) ?? 0
                                tag.namespace = rs.getOrNull<String>(1) ?? ""
                                tag.name = rs.getOrNull<String>(2) ?? ""
                                let translationsJson = rs.getOrNull<String>(3) ?? "{}"
                                tag.translations = parseTranslationsJson(translationsJson)
                                tag.links = rs.getOrNull<String>(4) ?? ""
                                tag.iconAssetId = rs.getOrNull<Int64>(5) ?? 0
                                tag.backgroundAssetId = rs.getOrNull<Int64>(6) ?? 0
                                tag.created_at = rs.getOrNull<String>(7) ?? ""
                                tag.updated_at = rs.getOrNull<String>(8) ?? ""
                                return Some(tag)
                            }
                        } finally {
                            rs.close()
                        }
                    } finally {
                        stmt.close()
                    }
                    return None
                } catch (e: Exception) {
                    getLogger("tag_dao").error("查询标签失败", ("error", e.message), ("id", id.toString()))
                    return None
                } finally {
                    try { conn.close() } catch (_: Exception) {}
                }
            case None =>
                return None
        }
    }

    /**
     * 根据 namespace 和 name 获取标签
     */
    public static func getByNamespaceName(namespace: String, name: String): ?TagData {
        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case Some(conn) =>
                
                try {
                    let stmt = conn.prepareStatement(
                        "SELECT id, namespace, name, translations, links, icon_asset_id, background_asset_id, created_at, updated_at FROM tags WHERE namespace = ? AND name = ?")
                    try {
                        stmt.set(0, namespace)
                        stmt.set(1, name)
                        let rs = stmt.query()
                        try {
                            if (rs.next()) {
                                let tag = TagData()
                                tag.id = rs.getOrNull<Int64>(0) ?? 0
                                tag.namespace = rs.getOrNull<String>(1) ?? ""
                                tag.name = rs.getOrNull<String>(2) ?? ""
                                let translationsJson = rs.getOrNull<String>(3) ?? "{}"
                                tag.translations = parseTranslationsJson(translationsJson)
                                tag.links = rs.getOrNull<String>(4) ?? ""
                                tag.iconAssetId = rs.getOrNull<Int64>(5) ?? 0
                                tag.backgroundAssetId = rs.getOrNull<Int64>(6) ?? 0
                                tag.created_at = rs.getOrNull<String>(7) ?? ""
                                tag.updated_at = rs.getOrNull<String>(8) ?? ""
                                return Some(tag)
                            }
                        } finally {
                            rs.close()
                        }
                    } finally {
                        stmt.close()
                    }
                    return None
                } catch (e: Exception) {
                    getLogger("tag_dao").error("查询标签失败", ("error", e.message))
                    return None
                } finally {
                    try { conn.close() } catch (_: Exception) {}
                }
            case None =>
                return None
        }
    }

    /**
     * 创建标签
     */
    public static func create(namespace: String, name: String, translations: HashMap<String, TagTranslation>, links: String): Int64 {
        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case Some(conn) =>
                
                try {
                    let translationsJson = serializeTranslationsJson(translations)
                    let stmt = conn.prepareStatement(
                        "INSERT INTO tags (namespace, name, translations, links) VALUES (?, ?, ?::jsonb, ?) RETURNING id")
                    try {
                        stmt.set(0, namespace)
                        stmt.set(1, name)
                        stmt.set(2, translationsJson)
                        stmt.set(3, links)
                        let rs = stmt.query()
                        try {
                            if (rs.next()) {
                                return rs.getOrNull<Int64>(0) ?? 0
                            }
                        } finally {
                            rs.close()
                        }
                    } finally {
                        stmt.close()
                    }
                    return 0
                } catch (e: Exception) {
                    getLogger("tag_dao").error("创建标签失败", ("error", e.message), ("namespace", namespace), ("name", name))
                    return 0
                } finally {
                    try { conn.close() } catch (_: Exception) {}
                }
            case None =>
                return 0
        }
    }

    /**
     * 更新标签
     */
    public static func update(id: Int64, translations: HashMap<String, TagTranslation>, links: String): Bool {
        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case Some(conn) =>
                
                try {
                    let translationsJson = serializeTranslationsJson(translations)
                    let stmt = conn.prepareStatement(
                        "UPDATE tags SET translations = ?::jsonb, links = ?, updated_at = CURRENT_TIMESTAMP WHERE id = ?")
                    try {
                        stmt.set(0, translationsJson)
                        stmt.set(1, links)
                        stmt.set(2, id)
                        stmt.update()
                        return true
                    } finally {
                        stmt.close()
                    }
                } catch (e: Exception) {
                    getLogger("tag_dao").error("更新标签失败", ("error", e.message), ("id", id.toString()))
                    return false
                } finally {
                    try { conn.close() } catch (_: Exception) {}
                }
            case None =>
                return false
        }
    }

    /**
     * 删除标签
     */
    public static func delete(id: Int64): Bool {
        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case Some(conn) =>
                
                try {
                    let stmt = conn.prepareStatement("DELETE FROM tags WHERE id = ?")
                    try {
                        stmt.set(0, id)
                        stmt.update()
                        return true
                    } finally {
                        stmt.close()
                    }
                } catch (e: Exception) {
                    getLogger("tag_dao").error("删除标签失败", ("error", e.message), ("id", id.toString()))
                    return false
                } finally {
                    try { conn.close() } catch (_: Exception) {}
                }
            case None =>
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

        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case Some(conn) =>
                
                try {
                    // Use row-wise IN to avoid long OR chains and keep it index-friendly.
                    // WHERE (namespace, name) IN ((?, ?), (?, ?), ...)
                    var tuples: ArrayList<String> = ArrayList<String>()
                    var namespaces: ArrayList<String> = ArrayList<String>()
                    var names: ArrayList<String> = ArrayList<String>()
                    for (tag in tags) {
                        let (namespace, name) = parseTagName(tag)
                        tuples.add("(?, ?)")
                        namespaces.add(namespace)
                        names.add(name)
                    }

                    let tuplesStr = String.join(tuples.toArray(), delimiter: ", ")
                    let sql = "SELECT namespace, name, translations FROM tags WHERE (namespace, name) IN (" + tuplesStr + ")"
                    let stmt = conn.prepareStatement(sql)
                    try {
                        // 绑定 (namespace, name) 参数对
                        var paramIndex = 0
                        for (i in 0..namespaces.size) {
                            stmt.set(paramIndex, namespaces[i])
                            stmt.set(paramIndex + 1, names[i])
                            paramIndex += 2
                        }

                        let rs = stmt.query()
                        try {
                            while (rs.next()) {
                                let namespace = rs.getOrNull<String>(0) ?? ""
                                let name = rs.getOrNull<String>(1) ?? ""
                                let translationsJson = rs.getOrNull<String>(2) ?? "{}"
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
                        } finally {
                            rs.close()
                        }
                    } finally {
                        stmt.close()
                    }
                } catch (e: Exception) {
                    getLogger("tag_dao").error("批量获取标签翻译失败", ("error", e.message))
                } finally {
                    try { conn.close() } catch (_: Exception) {}
                }
            case None => ()
        }
        return result
    }

    /**
     * 获取指定语言的所有标签翻译映射
     */
    public static func getTranslationsMap(lang: String): HashMap<String, String> {
        var result: HashMap<String, String> = HashMap<String, String>()

        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case Some(conn) =>
                
                try {
                    let stmt = conn.prepareStatement("SELECT namespace, name, translations FROM tags")
                    let rs = stmt.query()
                    try {
                        while (rs.next()) {
                            let namespace = rs.getOrNull<String>(0) ?? ""
                            let name = rs.getOrNull<String>(1) ?? ""
                            let translationsJson = rs.getOrNull<String>(2) ?? "{}"
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
                    } finally {
                        rs.close()
                        stmt.close()
                    }
                } catch (e: Exception) {
                    getLogger("tag_dao").error("获取标签翻译映射失败", ("error", e.message))
                } finally {
                    try { conn.close() } catch (_: Exception) {}
                }
            case None => ()
        }
        return result
    }

    /**
     * 获取所有命名空间
     */
    public static func listNamespaces(): Array<String> {
        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case Some(conn) =>
                
                try {
                    let stmt = conn.prepareStatement("SELECT DISTINCT namespace FROM tags WHERE namespace != '' ORDER BY namespace")
                    let rs = stmt.query()
                    var list: ArrayList<String> = ArrayList<String>()
                    try {
                        while (rs.next()) {
                            let ns = rs.getOrNull<String>(0) ?? ""
                            if (ns.size > 0) {
                                list.add(ns)
                            }
                        }
                    } finally {
                        rs.close()
                        stmt.close()
                    }
                    return list.toArray()
                } catch (e: Exception) {
                    getLogger("tag_dao").error("获取命名空间列表失败", ("error", e.message))
                    return Array<String>()
                } finally {
                    try { conn.close() } catch (_: Exception) {}
                }
            case None =>
                return Array<String>()
        }
    }

    /**
     * 获取当前系统已存在的所有标签名（用于自动补全等）
     */
    public static func listAllTagNames(): Array<String> {
        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case Some(conn) =>
                
                try {
                    let stmt = conn.prepareStatement("""
                        SELECT DISTINCT
                            CASE WHEN namespace != '' AND namespace IS NOT NULL
                                 THEN namespace || ':' || name
                                 ELSE name
                            END AS full_name
                        FROM tags
                        ORDER BY full_name
                    """)
                    let rs = stmt.query()
                    var list: ArrayList<String> = ArrayList<String>()
                    try {
                        while (rs.next()) {
                            let name = rs.getOrNull<String>(0) ?? ""
                            if (name.trimAscii().size > 0) {
                                list.add(name)
                            }
                        }
                    } finally {
                        rs.close()
                        stmt.close()
                    }
                    return list.toArray()
                } catch (e: Exception) {
                    getLogger("tag_dao").error("获取全量标签失败", ("error", e.message))
                    return Array<String>()
                } finally {
                    try { conn.close() } catch (_: Exception) {}
                }
            case None =>
                return Array<String>()
        }
    }

    /**
     * 插入或更新标签（用于导入）
     */
    public static func upsert(namespace: String, name: String, translations: HashMap<String, TagTranslation>, links: String): Bool {
        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case Some(conn) =>
                
                try {
                    let translationsJson = serializeTranslationsJson(translations)
                    let stmt = conn.prepareStatement("""
                        INSERT INTO tags (namespace, name, translations, links)
                        VALUES (?, ?, ?::jsonb, ?)
                        ON CONFLICT (namespace, name)
                        DO UPDATE SET translations = ?::jsonb, links = ?, updated_at = CURRENT_TIMESTAMP
                    """)
                    try {
                        stmt.set(0, namespace)
                        stmt.set(1, name)
                        stmt.set(2, translationsJson)
                        stmt.set(3, links)
                        stmt.set(4, translationsJson)
                        stmt.set(5, links)
                        stmt.update()
                        return true
                    } finally {
                        stmt.close()
                    }
                } catch (e: Exception) {
                    getLogger("tag_dao").error("upsert标签失败", ("error", e.message), ("namespace", namespace), ("name", name))
                    return false
                } finally {
                    try { conn.close() } catch (_: Exception) {}
                }
            case None =>
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
        // let allTags = listAllTagNames()  // 移除：不再获取所有标签，避免性能问题
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
        var result: ArrayList<String> = ArrayList<String>()

        if (searchTerm.size == 0) {
            return result
        }

        // Fast path: serve from cache to avoid repeated translations::text scans.
        translationSearchCacheMutex.lock()
        match (translationSearchCache.get(searchTerm)) {
            case Some(cached) =>
                translationSearchCacheMutex.unlock()
                return cached
            case None => ()
        }
        translationSearchCacheMutex.unlock()

        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case Some(conn) =>
                
                try {
                    // 使用 translations::text ILIKE 在 JSONB 文本中模糊搜索
                    let sql = "SELECT namespace, name FROM tags WHERE translations::text ILIKE ?"
                    let stmt = conn.prepareStatement(sql)
                    try {
                        let pattern = "%" + searchTerm + "%"
                        stmt.set(0, pattern)
                        let rs = stmt.query()
                        try {
                            while (rs.next()) {
                                let namespace = rs.getOrNull<String>(0) ?? ""
                                let name = rs.getOrNull<String>(1) ?? ""
                                let fullName = if (namespace.size > 0) {
                                    "${namespace}:${name}"
                                } else {
                                    name
                                }
                                result.add(fullName)
                            }
                        } finally {
                            rs.close()
                        }
                    } finally {
                        stmt.close()
                    }
                } catch (e: Exception) {
                    getLogger("tag_dao").error("根据翻译查找标签失败", ("error", e.message), ("searchTerm", searchTerm))
                } finally {
                    try { conn.close() } catch (_: Exception) {}
                }
            case None => ()
        }

        // Store into cache (best-effort). If cache grows too much, drop it.
        translationSearchCacheMutex.lock()
        if (translationSearchCache.size >= translationSearchCacheMaxSize) {
            translationSearchCache = HashMap<String, ArrayList<String>>()
        }
        translationSearchCache[searchTerm] = result
        translationSearchCacheMutex.unlock()

        return result
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
            let jsonValue = JsonValue.fromStr(jsonStr)
            match (jsonValue) {
                case obj: JsonObject =>
                    let fields = obj.getFields()
                    for ((lang, value) in fields) {
                        let translation = TagTranslation()
                        match (value) {
                            case innerObj: JsonObject =>
                                let innerFields = innerObj.getFields()
                                if (innerFields.contains("text")) {
                                    match (innerFields["text"]) {
                                        case s: JsonString => translation.text = s.getValue()
                                        case _ => ()
                                    }
                                }
                                if (innerFields.contains("intro")) {
                                    match (innerFields["intro"]) {
                                        case s: JsonString => translation.intro = s.getValue()
                                        case _ => ()
                                    }
                                }
                            case _ => ()
                        }
                        result[lang] = translation
                    }
                case _ => ()
            }
        } catch (e: Exception) {
            getLogger("tag_dao").warn("解析translations JSON失败", ("error", e.message), ("json", jsonStr))
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

        var parts: ArrayList<String> = ArrayList<String>()
        for ((lang, t) in translations) {
            let textEscaped = escapeJsonString(t.text)
            let introEscaped = escapeJsonString(t.intro)
            parts.add("\"${lang}\":{\"text\":\"${textEscaped}\",\"intro\":\"${introEscaped}\"}")
        }

        let joined = String.join(parts.toArray(), delimiter: ",")
        return "{${joined}}"
    }

    /**
     * 转义 JSON 字符串
     */
    private static func escapeJsonString(s: String): String {
        var result = s
        result = result.replace("\\", "\\\\")
        result = result.replace("\"", "\\\"")
        result = result.replace("\n", "\\n")
        result = result.replace("\r", "\\r")
        result = result.replace("\t", "\\t")
        return result
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

        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case Some(conn) =>
                
                try {
                    // 搜索标签名(namespace:name)和翻译文本。
                    // 默认只返回“已绑定档案”的标签，供全局搜索框等场景使用；
                    // 但编辑档案标签时需要可选到“未绑定任何档案”的标签，因此支持关闭该约束。
                    // 使用 JSONB 提取指定语言的翻译文本进行搜索。
                    // 优先级：1=name精确匹配, 2=name前缀匹配, 3=翻译精确匹配, 4=翻译前缀匹配, 5=模糊匹配
                    let sql = if (requireBound) {
                        """
                        SELECT DISTINCT t.namespace, t.name, t.translations,
                               CASE
                                   WHEN t.name ILIKE ? THEN 1
                                   WHEN t.name ILIKE ? THEN 2
                                   WHEN t.translations->?->>'text' ILIKE ? THEN 3
                                   WHEN t.translations->?->>'text' ILIKE ? THEN 4
                                   ELSE 5
                               END as match_priority
                        FROM tags t
                        INNER JOIN archive_tags at ON at.tag_id = t.id
                        WHERE t.name ILIKE ?
                           OR (t.namespace != '' AND t.namespace || ':' || t.name ILIKE ?)
                           OR t.translations->?->>'text' ILIKE ?
                           OR t.translations::text ILIKE ?
                        ORDER BY match_priority, t.name
                        LIMIT ?
                        """
                    } else {
                        """
                        SELECT DISTINCT t.namespace, t.name, t.translations,
                               CASE
                                   WHEN t.name ILIKE ? THEN 1
                                   WHEN t.name ILIKE ? THEN 2
                                   WHEN t.translations->?->>'text' ILIKE ? THEN 3
                                   WHEN t.translations->?->>'text' ILIKE ? THEN 4
                                   ELSE 5
                               END as match_priority
                        FROM tags t
                        WHERE t.name ILIKE ?
                           OR (t.namespace != '' AND t.namespace || ':' || t.name ILIKE ?)
                           OR t.translations->?->>'text' ILIKE ?
                           OR t.translations::text ILIKE ?
                        ORDER BY match_priority, t.name
                        LIMIT ?
                        """
                    }
                    let stmt = conn.prepareStatement(sql)
                    try {
                        let exactPattern = query
                        let prefixPattern = query + "%"
                        let likePattern = "%" + query + "%"
                        // CASE 中的参数
                        stmt.set(0, exactPattern)       // name 精确匹配优先级
                        stmt.set(1, prefixPattern)      // name 前缀匹配优先级
                        stmt.set(2, lang)               // 翻译精确匹配的语言
                        stmt.set(3, exactPattern)       // 翻译精确匹配
                        stmt.set(4, lang)               // 翻译前缀匹配的语言
                        stmt.set(5, prefixPattern)      // 翻译前缀匹配
                        // WHERE 中的参数
                        stmt.set(6, likePattern)        // name 模糊搜索
                        stmt.set(7, likePattern)        // namespace:name 模糊搜索
                        stmt.set(8, lang)               // 翻译搜索的语言
                        stmt.set(9, likePattern)        // 翻译模糊搜索
                        stmt.set(10, likePattern)       // 全文本模糊搜索（备用）
                        stmt.set(11, limit)

                        let rs = stmt.query()
                        try {
                            while (rs.next()) {
                                let namespace = rs.getOrNull<String>(0) ?? ""
                                let name = rs.getOrNull<String>(1) ?? ""
                                let translationsJson = rs.getOrNull<String>(2) ?? "{}"

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
                        } finally {
                            rs.close()
                        }
                    } finally {
                        stmt.close()
                    }
                } catch (e: Exception) {
                    getLogger("tag_dao").error("自动补全搜索失败", ("error", e.message), ("query", query))
                } finally {
                    try { conn.close() } catch (_: Exception) {}
                }
            case None => ()
        }
        return result
    }

    /**
     * 获取标签词云数据（按归档使用次数降序）
     * 返回: [(fullName, display, count)]
     */
    public static func getTagCloud(lang: String, limit: Int64): ArrayList<(String, String, Int64)> {
        var result: ArrayList<(String, String, Int64)> = ArrayList<(String, String, Int64)>()
        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case None => return result
            case Some(conn) =>
                try {
                    let sql = """
                        SELECT t.namespace, t.name,
                               COALESCE(t.translations->?->>'text', '') as translated_text,
                               COUNT(at.archive_id)::BIGINT as usage_count
                        FROM tags t
                        INNER JOIN archive_tags at ON at.tag_id = t.id
                        WHERE COALESCE(LOWER(t.namespace), '') != 'source'
                        GROUP BY t.id, t.namespace, t.name, translated_text
                        ORDER BY usage_count DESC, t.name
                        LIMIT ?
                    """
                    let stmt = conn.prepareStatement(sql)
                    try {
                        stmt.set(0, lang)
                        stmt.set(1, limit)
                        let rs = stmt.query()
                        try {
                            while (rs.next()) {
                                let namespace = rs.getOrNull<String>(0) ?? ""
                                let name = rs.getOrNull<String>(1) ?? ""
                                let translated = rs.getOrNull<String>(2) ?? ""
                                let count = rs.getOrNull<Int64>(3) ?? 0

                                let fullName = if (namespace.size > 0) { "${namespace}:${name}" } else { name }
                                let display = if (translated.trimAscii().size > 0) { translated } else { name }
                                result.add((fullName, display, count))
                            }
                        } finally {
                            rs.close()
                        }
                    } finally {
                        stmt.close()
                    }
                } catch (e: Exception) {
                    getLogger("tag_dao").error("获取标签词云失败", ("error", e.message))
                } finally {
                    try { conn.close() } catch (_: Exception) {}
                }
        }
        return result
    }

    public static func updateIconAssetId(id: Int64, iconAssetId: Int64): Bool {
        if (id <= 0) { return false }
        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case Some(conn) =>
                try {
                    let stmt = conn.prepareStatement("UPDATE tags SET icon_asset_id = ?, updated_at = CURRENT_TIMESTAMP WHERE id = ?")
                    try {
                        if (iconAssetId > 0) {
                            stmt.set(0, iconAssetId)
                        } else {
                            stmt.setNull(0)
                        }
                        stmt.set(1, id)
                        stmt.update()
                        return true
                    } finally {
                        stmt.close()
                    }
                } catch (e: Exception) {
                    getLogger("tag_dao").error("updateIconAssetId failed", ("error", e.message))
                    return false
                } finally {
                    try { conn.close() } catch (_: Exception) {}
                }
            case None => return false
        }
    }

    public static func updateBackgroundAssetId(id: Int64, backgroundAssetId: Int64): Bool {
        if (id <= 0) { return false }
        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case Some(conn) =>
                try {
                    let stmt = conn.prepareStatement("UPDATE tags SET background_asset_id = ?, updated_at = CURRENT_TIMESTAMP WHERE id = ?")
                    try {
                        if (backgroundAssetId > 0) {
                            stmt.set(0, backgroundAssetId)
                        } else {
                            stmt.setNull(0)
                        }
                        stmt.set(1, id)
                        stmt.update()
                        return true
                    } finally {
                        stmt.close()
                    }
                } catch (e: Exception) {
                    getLogger("tag_dao").error("updateBackgroundAssetId failed", ("error", e.message))
                    return false
                } finally {
                    try { conn.close() } catch (_: Exception) {}
                }
            case None => return false
        }
    }
}
