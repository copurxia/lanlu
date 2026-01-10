package lrr4cj.dao

import std.database.sql.*
import lrr4cj.config.*
import lrr4cj.utils.*
import lrr4cj.utils.SearchFilter
import std.collection.*
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
 * 归档数据访问对象 (DAO)
 * 负责处理所有与归档相关的数据库操作
 */
public class ArchiveDao {
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

    /**
     * 为 tags 字段构建“完全匹配单个 tag token”的条件（tags 为逗号分隔字符串，无空格）。
     * 匹配四种情况：唯一标签/开头/中间/结尾。
     */
    private static func buildExactTagMatchCondition(tagToken: String, params: ArrayList<String>): String {
        let escaped = SearchFilter.toExactLikePattern(tagToken)
        params.add(escaped)                 // tags = ?
        params.add(escaped + ",%")          // tags LIKE 'tag,%'
        params.add("%," + escaped + ",%")   // tags LIKE '%,tag,%'
        params.add("%," + escaped)          // tags LIKE '%,tag'
        return "(tags = ? OR tags LIKE ? ESCAPE '\\' OR tags LIKE ? ESCAPE '\\' OR tags LIKE ? ESCAPE '\\')"
    }

    /**
     * 带翻译扩展的精确标签匹配条件：
     * `tag$` 将匹配 tag 本身以及通过翻译检索到的原始标签（namespace:name）。
     */
    private static func buildExactTagMatchConditionWithTranslations(tagToken: String, params: ArrayList<String>): String {
        var candidates: ArrayList<String> = ArrayList<String>()
        var seen: HashMap<String, Bool> = HashMap<String, Bool>()

        // 原 token
        if (tagToken.size > 0) {
            candidates.add(tagToken)
            seen[tagToken] = true
        }

        // 翻译命中标签（去重）
        let translatedTags = TagDao.findTagsByTranslation(tagToken)
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
            condition += buildExactTagMatchCondition(candidates[i], params)
        }
        condition += ")"
        return condition
    }
    
    /**
     * 获取所有归档
     */
    public static func getAllArchives(): Array<ArchiveData> {
        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case Some(conn) =>
                
                var archives: ArrayList<ArchiveData> = ArrayList<ArchiveData>()
                try {
                    let stmt = conn.prepareStatement(
                        "SELECT arcid, title, filename, summary, thumbhash, created_at, updated_at, relative_path, file_size, pagecount, archive_type FROM archives ORDER BY id")
                    try {
                        let rs = stmt.query()
                        try {
                            while (rs.next()) {
                                let archive = ArchiveData()
                                archive.id = rs.getOrNull<String>(0) ?? ""
                                archive.title = rs.getOrNull<String>(1) ?? ""
                                archive.filename = rs.getOrNull<String>(2) ?? ""
                                archive.summary = rs.getOrNull<String>(3) ?? ""
                                archive.thumbhash = rs.getOrNull<String>(4) ?? ""
                                archive.created_at = rs.getOrNull<String>(5) ?? ""
                                archive.updated_at = rs.getOrNull<String>(6) ?? ""
                                archive.relative_path = rs.getOrNull<String>(7) ?? ""
                                archive.file_size = rs.getOrNull<Int64>(8) ?? 0
                                archive.pagecount = rs.getOrNull<Int32>(9) ?? 0
                                archive.archive_type = rs.getOrNull<String>(10) ?? "archive"
                                archives.add(archive)
                            }
                        } finally {
                            rs.close()
                        }
                    } finally {
                        stmt.close()
                    }
                    return archives.toArray()
                } catch (e: Exception) {
                    getLogger("archive_dao").error("查询归档失败", ("error", e.message))
                    return Array<ArchiveData>()
                } finally {
                    try { conn.close() } catch (closeException: Exception) {}
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
        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case Some(conn) =>
                
                try {
                    let stmt = conn.prepareStatement(
                        "SELECT arcid, title, filename, summary, thumbhash, created_at, updated_at, relative_path, file_size, pagecount, archive_type FROM archives WHERE arcid = ?")
                    try {
                        stmt.set(0, id)
                        let rs = stmt.query()
                        try {
                            if (rs.next()) {
                                let archive = ArchiveData()
                                archive.id = rs.getOrNull<String>(0) ?? ""
                                archive.title = rs.getOrNull<String>(1) ?? ""
                                archive.filename = rs.getOrNull<String>(2) ?? ""
                                archive.summary = rs.getOrNull<String>(3) ?? ""
                                archive.thumbhash = rs.getOrNull<String>(4) ?? ""
                                archive.created_at = rs.getOrNull<String>(5) ?? ""
                                archive.updated_at = rs.getOrNull<String>(6) ?? ""
                                archive.relative_path = rs.getOrNull<String>(7) ?? ""
                                archive.file_size = rs.getOrNull<Int64>(8) ?? 0
                                archive.pagecount = rs.getOrNull<Int32>(9) ?? 0
                                archive.archive_type = rs.getOrNull<String>(10) ?? "archive"
                                return archive
                            }
                        } finally {
                            rs.close()
                        }
                    } finally {
                        stmt.close()
                    }
                } catch (e: Exception) {
                    getLogger("archive_dao").error("查询归档失败", ("error", e.message))
                } finally {
                    try { conn.close() } catch (closeException: Exception) {}
                }
            case None => getLogger("archive_dao").error("无法连接到数据库")
        }
        return ArchiveData()
    }

    /**
     * 根据 arcid 获取 archives 表的内部 ID（INTEGER）
     */
    public static func getArchiveInternalId(arcid: String): Int64 {
        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case Some(conn) =>
                
                try {
                    let stmt = conn.prepareStatement("SELECT id FROM archives WHERE arcid = ?")
                    try {
                        stmt.set(0, arcid)
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
                } catch (e: Exception) {
                    getLogger("archive_dao").error("查询归档内部ID失败", ("error", e.message))
                } finally {
                    try { conn.close() } catch (closeException: Exception) {}
                }
            case None => getLogger("archive_dao").error("无法连接到数据库")
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
    private static func buildRelevanceExpr(filter: String): String {
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
            ilikeScoreExpr = ilikeScoreExpr + " + CASE WHEN title ILIKE '%" + escapedTerm + "%' THEN 0.15 ELSE 0 END"
            ilikeScoreExpr = ilikeScoreExpr + " + CASE WHEN filename ILIKE '%" + escapedTerm + "%' THEN 0.1 ELSE 0 END"
            ilikeScoreExpr = ilikeScoreExpr + " + CASE WHEN tags ILIKE '%" + escapedTerm + "%' THEN 0.05 ELSE 0 END"
        }

        // 构建用于全文搜索的查询字符串
        var tsQueryTerms: ArrayList<String> = ArrayList<String>()
        for (term in relevanceTerms) {
            tsQueryTerms.add(term.replace("'", "''"))
        }
        let tsQueryStr = String.join(tsQueryTerms.toArray(), delimiter: " ")

        // 构建完整的评分表达式（全文搜索 + ILIKE 匹配）
        let relevanceExpr = "COALESCE(ts_rank(search_tsv, websearch_to_tsquery('simple', '" + tsQueryStr + "')) * 2, 0) + (" + ilikeScoreExpr + ")"

        return relevanceExpr
    }

    public static func searchArchives(filter: String, category: String, start: Int32, count: Int32, sortby: String, order: String, newOnly: Bool, untaggedOnly: Bool, favoriteOnly: Bool, dateFrom: String, dateTo: String, userId: Int64): (Array<ArchiveData>, Int64) {
        return searchArchives(filter, category, start, count, sortby, order, newOnly, untaggedOnly, favoriteOnly, dateFrom, dateTo, userId, "")
    }

    public static func searchArchives(filter: String, category: String, start: Int32, count: Int32, sortby: String, order: String, newOnly: Bool, untaggedOnly: Bool, favoriteOnly: Bool, dateFrom: String, dateTo: String, userId: Int64, tankoubonId: String): (Array<ArchiveData>, Int64) {
        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case Some(conn) =>
                
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
                
                // 首先获取总记录数
                var countSql = "SELECT COUNT(*) FROM archives_with_tags"
                var whereConditions: ArrayList<String> = ArrayList<String>()
                
                // 解析搜索过滤器
                let searchResult = SearchFilter.parse(filter)
                var filterParams: ArrayList<String> = ArrayList<String>()

                getLogger("archive_dao").info("搜索过滤器解析结果",
                    ("filter", filter),
                    ("terms", searchResult.terms.size.toString()))

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
                            whereConditions.add(buildExactTagMatchConditionWithTranslations(termValue, filterParams))
                            continue
                        }

                        let pattern = SearchFilter.toLikePattern(termValue)
                        // 原有的字段匹配条件
                        var fieldCondition = "(title LIKE ? ESCAPE '\\' OR filename LIKE ? ESCAPE '\\' OR tags LIKE ? ESCAPE '\\' OR summary LIKE ? ESCAPE '\\'"
                        filterParams.add(pattern)
                        filterParams.add(pattern)
                        filterParams.add(pattern)
                        filterParams.add(pattern)

                        // 查询翻译匹配的标签，添加 OR 条件
                        let translatedTags = TagDao.findTagsByTranslation(termValue)
                        for (tagName in translatedTags) {
                            fieldCondition += " OR tags LIKE ? ESCAPE '\\'"
                            filterParams.add("%" + tagName + "%")
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
                            whereConditions.add(buildExactTagMatchConditionWithTranslations(phraseValue, filterParams))
                            continue
                        }

                        let pattern = SearchFilter.toLikePattern(phraseValue)
                        var fieldCondition = "(title LIKE ? ESCAPE '\\' OR filename LIKE ? ESCAPE '\\' OR tags LIKE ? ESCAPE '\\' OR summary LIKE ? ESCAPE '\\'"
                        filterParams.add(pattern)
                        filterParams.add(pattern)
                        filterParams.add(pattern)
                        filterParams.add(pattern)

                        // 查询翻译匹配的标签
                        let translatedTags = TagDao.findTagsByTranslation(phraseValue)
                        for (tagName in translatedTags) {
                            fieldCondition += " OR tags LIKE ? ESCAPE '\\'"
                            filterParams.add("%" + tagName + "%")
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
                            whereConditions.add("NOT " + buildExactTagMatchConditionWithTranslations(excludeValue, filterParams))
                            continue
                        }

                        let pattern = SearchFilter.toLikePattern(excludeValue)
                        var fieldCondition = "(title LIKE ? ESCAPE '\\' OR filename LIKE ? ESCAPE '\\' OR tags LIKE ? ESCAPE '\\' OR summary LIKE ? ESCAPE '\\'"
                        filterParams.add(pattern)
                        filterParams.add(pattern)
                        filterParams.add(pattern)
                        filterParams.add(pattern)

                        // 查询翻译匹配的标签
                        let translatedTags = TagDao.findTagsByTranslation(excludeValue)
                        for (tagName in translatedTags) {
                            fieldCondition += " OR tags LIKE ? ESCAPE '\\'"
                            filterParams.add("%" + tagName + "%")
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
                    whereConditions.add("NOT EXISTS (SELECT 1 FROM user_archive_status uas JOIN archives a ON a.id = uas.archive_id WHERE a.arcid = archives_with_tags.arcid AND uas.user_id = ${userId} AND uas.is_new = false)")
                }

                // 按 lastread 排序时，移除从未阅读的记录
                // 根据 API 文档："If you sort by lastread, IDs that have never been read will be removed from the search."
                // 使用 user_archive_status 表判断用户是否阅读过（is_new = false 表示已读）
                // 注意：未登录用户会被重定向到登录页，所以这里只处理已登录用户
                if ((sortby == "lastread" || sortby == "lastreadtime") && userId > 0) {
                    // 只显示用户已读的档案（在 user_archive_status 表中有记录且 is_new = false）
                    whereConditions.add("EXISTS (SELECT 1 FROM user_archive_status uas JOIN archives a ON a.id = uas.archive_id WHERE a.arcid = archives_with_tags.arcid AND uas.user_id = ${userId} AND uas.is_new = false)")
                }

                // 添加无标签过滤条件
                if (untaggedOnly) {
                    whereConditions.add("(tags IS NULL OR tags = '')")
                }

                // favoriteOnly 过滤 - 只显示用户收藏的档案
                // 当 favoriteOnly=true 且 userId > 0 时，只返回用户收藏的归档
                if (favoriteOnly && userId > 0) {
                    whereConditions.add("EXISTS (SELECT 1 FROM user_favorites uf JOIN archives a ON a.id = uf.archive_id WHERE a.arcid = archives_with_tags.arcid AND uf.user_id = ${userId})")
                }

                // tankoubon_id 过滤 - 只返回某个合集中的归档
                if (tankoubonId.size > 0) {
                    whereConditions.add("EXISTS (SELECT 1 FROM tankoubons t JOIN tankoubon_archives ta ON ta.tankoubon_id = t.id WHERE t.tankoubon_id = ? AND ta.archive_id = archives_with_tags.id)")
                    filterParams.add(tankoubonId)
                }

                // 日期范围过滤
                if (dateFrom.size > 0) {
                    whereConditions.add("created_at >= ?")
                    filterParams.add(dateFrom)
                }
                if (dateTo.size > 0) {
                    whereConditions.add("created_at <= ?")
                    filterParams.add(dateTo + " 23:59:59")
                }

                // 构建相关度评分表达式（用于过滤）
                let relevanceExpr = buildRelevanceExpr(filter)
                let minRelevanceThreshold = 0.05  // 最低相关度阈值

                // 组合 WHERE 条件
                if (whereConditions.size > 0 || filter.size > 0) {
                    var whereClause = ""
                    for (i in 0..whereConditions.size) {
                        if (i > 0) {
                            whereClause += " AND "
                        }
                        whereClause += whereConditions[i]
                    }

                    // 当有搜索词时，添加相关度阈值过滤
                    if (filter.size > 0 && relevanceExpr != "1") {
                        if (whereClause.size > 0) {
                            whereClause += " AND "
                        }
                        whereClause += "(" + relevanceExpr + ") >= " + minRelevanceThreshold.toString()
                    }

                    countSql += " WHERE " + whereClause
                }
                
                getLogger("archive_dao").debug("执行计数SQL", ("sql", countSql))
                let countStmt = conn.prepareStatement(countSql)
                var totalCount = 0

                // 绑定搜索过滤器参数
                for (i in 0..filterParams.size) {
                    countStmt.set<String>(i, filterParams[i])
                }
                
                let countRs = countStmt.query()
                try {
                    if (countRs.next()) {
                        totalCount = countRs.getOrNull<Int64>(0) ?? 0
                        getLogger("archive_dao").debug("获取到总记录数", ("count", totalCount.toString()))
                    } else {
                        getLogger("archive_dao").error("无法获取总记录数")
                    }
                } finally {
                    countRs.close()
                    countStmt.close()
                }

                // 然后查询分页数据，使用archives_with_tags视图获取标签信息
                var sql = "SELECT id, arcid, filename, title, summary, thumbhash, created_at, updated_at, relative_path, file_size, pagecount, archive_type, tags FROM archives_with_tags"

                // 使用相同的 WHERE 条件（包含相关度阈值过滤）
                if (whereConditions.size > 0 || filter.size > 0) {
                    var whereClause = ""
                    for (i in 0..whereConditions.size) {
                        if (i > 0) {
                            whereClause += " AND "
                        }
                        whereClause += whereConditions[i]
                    }

                    // 当有搜索词时，添加相关度阈值过滤
                    if (filter.size > 0 && relevanceExpr != "1") {
                        if (whereClause.size > 0) {
                            whereClause += " AND "
                        }
                        whereClause += "(" + relevanceExpr + ") >= " + minRelevanceThreshold.toString()
                    }

                    sql += " WHERE " + whereClause
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
                    sql += " ORDER BY (SELECT uas.updated_at FROM user_archive_status uas JOIN archives a ON a.id = uas.archive_id WHERE a.arcid = archives_with_tags.arcid AND uas.user_id = ${userId}) ${orderDirection}"
                } else if (sortby == "date_added") {
                    let orderDirection = if (order == "desc") { "DESC" } else { "ASC" }
                    sql += " ORDER BY created_at ${orderDirection}"
                } else if (sortby == "pagecount") {
                    let orderDirection = if (order == "desc") { "DESC" } else { "ASC" }
                    sql += " ORDER BY pagecount ${orderDirection}"
                } else if (sortby == "tank_order" && tankoubonId.size > 0) {
                    let orderDirection = if (order == "desc") { "DESC" } else { "ASC" }
                    sql += " ORDER BY (SELECT ta.sort_order FROM tankoubons t JOIN tankoubon_archives ta ON ta.tankoubon_id = t.id WHERE t.tankoubon_id = ? AND ta.archive_id = archives_with_tags.id LIMIT 1) ${orderDirection}, created_at DESC"
                    // ORDER BY 子查询需要再次绑定 tankId
                    filterParams.add(tankoubonId)
                } else if (sortby == "size") {
                    let orderDirection = if (order == "desc") { "DESC" } else { "ASC" }
                    sql += " ORDER BY file_size ${orderDirection}"
                } else if (sortby == "relevance" && filter.size > 0 && relevanceExpr != "1") {
                    // 相关度排序：使用已构建的评分表达式
                    sql += " ORDER BY (" + relevanceExpr + ") DESC, created_at DESC"
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
                
                let stmt = conn.prepareStatement(sql)

                // 绑定搜索过滤器参数
                for (i in 0..filterParams.size) {
                    stmt.set<String>(i, filterParams[i])
                }
                
                let rs = stmt.query()
                try {
                    getLogger("archive_dao").debug("SQL查询执行完成")

                    while (rs.next()) {
                        let archive = ArchiveData()
                        try {
                            archive.internalId = rs.getOrNull<Int64>(0) ?? 0
                            archive.id = rs.getOrNull<String>(1) ?? ""
                            archive.filename = rs.getOrNull<String>(2) ?? ""
                            archive.title = rs.getOrNull<String>(3) ?? ""
                            archive.summary = rs.getOrNull<String>(4) ?? ""
                            archive.thumbhash = rs.getOrNull<String>(5) ?? ""
                            archive.created_at = rs.getOrNull<String>(6) ?? ""
                            archive.updated_at = rs.getOrNull<String>(7) ?? ""
                            archive.relative_path = rs.getOrNull<String>(8) ?? ""
                            archive.file_size = rs.getOrNull<Int64>(9) ?? 0
                            archive.pagecount = rs.getOrNull<Int32>(10) ?? 0
                            archive.archive_type = rs.getOrNull<String>(11) ?? "archive"
                            archive.tags = rs.getOrNull<String>(12) ?? ""
                            archives.add(archive)
                        } catch (e: Exception) {
                            getLogger("archive_dao").error("读取字段时出错", ("error", e.message))
                            throw e
                        }
                    }
                } finally {
                    rs.close()
                    stmt.close()
                }

                let resultArray = archives.toArray()
                getLogger("archive_dao").info("查询完成", ("records", resultArray.size.toString()), ("total_count", totalCount.toString()))
                conn.close()
                return (resultArray, totalCount)
            } catch (e: Exception) {
                getLogger("archive_dao").error("搜索归档失败", ("error", e.message))
                conn.close()
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

        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case Some(conn) =>
                
                try {
                    // 构建 IN 子句的占位符
                    var placeholders = ""
                    for (i in 0..arcids.size) {
                        if (i > 0) {
                            placeholders += ","
                        }
                        placeholders += "?"
                    }

                    let sql = """
                        SELECT a.arcid, t.tankoubon_id
                        FROM tankoubon_archives ta
                        JOIN tankoubons t ON t.id = ta.tankoubon_id
                        JOIN archives a ON a.id = ta.archive_id
                        WHERE a.arcid IN (${placeholders})
                    """

                    let stmt = conn.prepareStatement(sql)
                    try {
                        // 绑定参数
                        for (i in 0..arcids.size) {
                            stmt.set(i, arcids[i])
                        }

                        let rs = stmt.query()
                        try {
                            while (rs.next()) {
                                let arcid = rs.getOrNull<String>(0) ?? ""
                                let tankoubonId = rs.getOrNull<String>(1) ?? ""
                                if (arcid != "" && tankoubonId != "") {
                                    mapping[arcid] = tankoubonId
                                }
                            }
                        } finally {
                            rs.close()
                        }
                    } finally {
                        stmt.close()
                    }
                } catch (e: Exception) {
                    getLogger("archive_dao").error("获取归档Tankoubon映射失败", ("error", e.message))
                } finally {
                    try { conn.close() } catch (closeException: Exception) {}
                }
            case None =>
                getLogger("archive_dao").error("无法连接到数据库")
        }

        return mapping
    }

    /**
     * 创建归档记录
     */
    public static func create(archive: ArchiveData): Bool {
        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case Some(conn) =>
                
                try {
                    let stmt = conn.prepareStatement(
                        "INSERT INTO archives (arcid, title, filename, summary, thumbhash, created_at, updated_at, relative_path, file_size, pagecount) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)")
                    try {
                        stmt.set(0, archive.id)
                        stmt.set(1, archive.title)
                        stmt.set(2, archive.filename)
                        stmt.set(3, archive.summary)
                        stmt.set(4, archive.thumbhash)
                        stmt.set(5, archive.created_at)
                        stmt.set(6, archive.updated_at)
                        stmt.set(7, archive.relative_path)
                        stmt.set(8, archive.file_size)
                        stmt.set(9, archive.pagecount)
                        stmt.update()
                        return true  // 简化实现，假设更新成功
                    } finally {
                        stmt.close()
                    }
                } catch (e: Exception) {
                    getLogger("archive_dao").error("创建归档失败", ("error", e.message))
                    return false
                } finally {
                    try { conn.close() } catch (closeException: Exception) {}
                }
            case None =>
                getLogger("archive_dao").error("无法连接到数据库")
                return false
        }
    }

    /**
     * 插入归档记录 - 专门为 ShinobuService 提供的方法
     */
    public static func insertArchive(archiveId: String, title: String, fileName: String, fileSize: Int64, _: Int64, relativePath: String, archiveType: String, categoryId: Int64): Bool {
        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case Some(conn) =>
                
                try {
                    // 使用数据库的默认值来处理时间戳，避免格式问题
                    let sql = "INSERT INTO archives (arcid, title, filename, summary, thumbhash, relative_path, file_size, pagecount, archive_type, category_id) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)"

                    let stmt = conn.prepareStatement(sql)
                    try {
                        stmt.set(0, archiveId)
                        stmt.set(1, title)  // 使用传入的标题
                        stmt.set(2, fileName)
                        stmt.set(3, "")  // summary
                        stmt.set(4, "")  // thumbhash
                        stmt.set(5, relativePath)  // 相对路径
                        stmt.set(6, fileSize)
                        stmt.set(7, 0)  // pagecount
                        stmt.set(8, archiveType)
                        stmt.set(9, categoryId)
                        stmt.update()
                    } finally {
                        stmt.close()
                    }
                    getLogger("archive_dao").info("归档记录插入成功", ("archive_id", archiveId))
                    return true
                } catch (e: Exception) {
                    getLogger("archive_dao").error("插入语句执行失败", ("error", e.message))
                    return false
                } finally {
                    try { conn.close() } catch (closeException: Exception) {}
                }
            case None =>
                getLogger("archive_dao").error("Failed to connect to database")
                return false
        }
    }

    /**
     * 更新归档记录
     */
    public static func update(archive: ArchiveData): Bool {
        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case Some(conn) =>
                
                try {
                    let stmt = conn.prepareStatement(
                        "UPDATE archives SET title = ?, filename = ?, summary = ?, thumbhash = ?, updated_at = ?, relative_path = ?, file_size = ?, pagecount = ? WHERE arcid = ?")
                    try {
                        stmt.set(0, archive.title)
                        stmt.set(1, archive.filename)
                        stmt.set(2, archive.summary)
                        stmt.set(3, archive.thumbhash)
                        stmt.set(4, archive.updated_at)
                        stmt.set(5, archive.relative_path)
                        stmt.set(6, archive.file_size)
                        stmt.set(7, archive.pagecount)
                        stmt.set(8, archive.id)
                        stmt.update()
                        return true
                    } finally {
                        stmt.close()
                    }
                } catch (e: Exception) {
                    getLogger("archive_dao").error("更新归档失败", ("error", e.message))
                    return false
                } finally {
                    try { conn.close() } catch (closeException: Exception) {}
                }
            case None =>
                getLogger("archive_dao").error("无法连接到数据库")
                return false
        }
    }

    /**
     * 删除归档记录
     */
    public static func delete(id: String): Bool {
        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case Some(conn) =>
                
                try {
                    let stmt = conn.prepareStatement("DELETE FROM archives WHERE arcid = ?")
                    try {
                        stmt.set(0, id)
                        stmt.update()
                        return true  // 简化实现，假设更新成功
                    } finally {
                        stmt.close()
                    }
                } catch (e: Exception) {
                    getLogger("archive_dao").error("删除归档失败", ("error", e.message))
                    return false
                } finally {
                    try { conn.close() } catch (closeException: Exception) {}
                }
            case None =>
                getLogger("archive_dao").error("无法连接到数据库")
                return false
        }
    }
    
    /**
     * 更新归档的页数
     */
    public static func updatePageCount(archiveId: String, pageCount: Int32): Bool {
        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case Some(conn) =>
                
                try {
                    let stmt = conn.prepareStatement("UPDATE archives SET pagecount = ? WHERE arcid = ?")
                    try {
                        stmt.set(0, pageCount)
                        stmt.set(1, archiveId)
                        stmt.update()
                        return true
                    } finally {
                        stmt.close()
                    }
                } catch (e: Exception) {
                    getLogger("archive_dao").error("更新归档页数失败", ("error", e.message))
                    return false
                } finally {
                    try { conn.close() } catch (closeException: Exception) {}
                }
            case None =>
                getLogger("archive_dao").error("无法连接到数据库")
                return false
        }
    }
    
    /**
     * 更新归档的缩略图hash
     */
    public static func updateThumbHash(archiveId: String, thumbHash: String): Bool {
        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case Some(conn) =>
                
                try {
                    let stmt = conn.prepareStatement("UPDATE archives SET thumbhash = ? WHERE arcid = ?")
                    try {
                        stmt.set(0, thumbHash)
                        stmt.set(1, archiveId)
                        stmt.update()
                        return true
                    } finally {
                        stmt.close()
                    }
                } catch (e: Exception) {
                    getLogger("archive_dao").error("更新归档缩略图hash失败", ("error", e.message))
                    return false
                } finally {
                    try { conn.close() } catch (closeException: Exception) {}
                }
            case None =>
                getLogger("archive_dao").error("无法连接到数据库")
                return false
        }
    }
    
    /**
     * 同时更新归档的页数和缩略图hash
     */
    public static func updateArchiveDetails(archiveId: String, pageCount: Int32, thumbHash: String): Bool {
        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case Some(conn) =>
                
                try {
                    let stmt = conn.prepareStatement("UPDATE archives SET pagecount = ?, thumbhash = ? WHERE arcid = ?")
                    try {
                        stmt.set(0, pageCount)
                        stmt.set(1, thumbHash)
                        stmt.set(2, archiveId)
                        stmt.update()
                        return true
                    } finally {
                        stmt.close()
                    }
                } catch (e: Exception) {
                    getLogger("archive_dao").error("更新归档详情失败", ("error", e.message))
                    return false
                } finally {
                    try { conn.close() } catch (closeException: Exception) {}
                }
            case None =>
                getLogger("archive_dao").error("无法连接到数据库")
                return false
        }
    }

    /**
     * 更新归档的相对路径
     */
    public static func updateArchiveRelativePath(archiveId: String, relativePath: String): Bool {
        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case Some(conn) =>
                
                try {
                    let stmt = conn.prepareStatement("UPDATE archives SET relative_path = ? WHERE arcid = ?")
                    try {
                        stmt.set(0, relativePath)
                        stmt.set(1, archiveId)
                        stmt.update()
                        return true
                    } finally {
                        stmt.close()
                    }
                } catch (e: Exception) {
                    getLogger("archive_dao").error("更新归档相对路径失败", ("error", e.message))
                    return false
                } finally {
                    try { conn.close() } catch (closeException: Exception) {}
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
        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case Some(conn) =>
                
                try {
                    var archives: ArrayList<ArchiveData> = ArrayList<ArchiveData>()
                    let stmt = conn.prepareStatement(
                        "SELECT arcid, title, filename, summary, thumbhash, created_at, updated_at, relative_path, file_size, pagecount FROM archives WHERE thumbhash = '' OR thumbhash IS NULL ORDER BY id")
                    try {
                        let rs = stmt.query()
                        try {
                            while (rs.next()) {
                                let archive = ArchiveData()
                                archive.id = rs.getOrNull<String>(0) ?? ""
                                archive.title = rs.getOrNull<String>(1) ?? ""
                                archive.filename = rs.getOrNull<String>(2) ?? ""
                                archive.summary = rs.getOrNull<String>(3) ?? ""
                                archive.thumbhash = rs.getOrNull<String>(4) ?? ""
                                archive.created_at = rs.getOrNull<String>(5) ?? ""
                                archive.updated_at = rs.getOrNull<String>(6) ?? ""
                                archive.relative_path = rs.getOrNull<String>(7) ?? ""
                                archive.file_size = rs.getOrNull<Int64>(8) ?? 0
                                archive.pagecount = rs.getOrNull<Int32>(9) ?? 0
                                archives.add(archive)
                            }
                        } finally {
                            rs.close()
                        }
                    } finally {
                        stmt.close()
                    }
                    return archives.toArray()
                } catch (e: Exception) {
                    getLogger("archive_dao").error("获取无缩略图归档失败", ("error", e.message))
                    return Array<ArchiveData>()
                } finally {
                    try { conn.close() } catch (closeException: Exception) {}
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
        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case Some(conn) =>
                
                try {
                let stmt = conn.prepareStatement("SELECT COUNT(*) FROM archives WHERE arcid = ?")
                stmt.set(0, id)
                let rs = stmt.query()
                
                var count: Int64 = 0
                if (rs.next()) {
                    count = rs.getOrNull<Int64>(0) ?? 0
                }
                
                conn.close()
                return count > 0
            } catch (e: Exception) {
                getLogger("archive_dao").error("检查归档存在性失败", ("error", e.message))
                conn.close()
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
        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case Some(conn) =>
                
                try {
                let stmt = conn.prepareStatement("SELECT arcid, title, filename, summary, thumbhash, created_at, updated_at, relative_path, file_size, pagecount FROM archives WHERE relative_path = ?")
                stmt.set(0, filePath)
                let rs = stmt.query()

                if (rs.next()) {
                    let archive = ArchiveData()
                    archive.id = rs.getOrNull<String>(0) ?? ""
                    archive.title = rs.getOrNull<String>(1) ?? ""
                    archive.filename = rs.getOrNull<String>(2) ?? ""
                    archive.summary = rs.getOrNull<String>(3) ?? ""
                    archive.thumbhash = rs.getOrNull<String>(4) ?? ""
                    archive.created_at = rs.getOrNull<String>(5) ?? ""
                    archive.updated_at = rs.getOrNull<String>(6) ?? ""
                    archive.relative_path = rs.getOrNull<String>(7) ?? ""
                    archive.file_size = rs.getOrNull<Int64>(8) ?? 0
                    archive.pagecount = rs.getOrNull<Int32>(9) ?? 0

                    conn.close()
                    return Some(archive)
                } else {
                    conn.close()
                    return None
                }
            } catch (e: Exception) {
                getLogger("archive_dao").error("根据路径获取归档失败", ("error", e.message))
                conn.close()
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
        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case Some(conn) =>
                
                try {
                    let stmt = conn.prepareStatement("SELECT arcid, title, filename, summary, thumbhash, created_at, updated_at, relative_path, file_size, pagecount FROM archives WHERE relative_path = ? AND filename = ?")
                    try {
                        stmt.set(0, relativePath)
                        stmt.set(1, filename)
                        let rs = stmt.query()
                        try {
                            if (rs.next()) {
                                let archive = ArchiveData()
                                archive.id = rs.getOrNull<String>(0) ?? ""
                                archive.title = rs.getOrNull<String>(1) ?? ""
                                archive.filename = rs.getOrNull<String>(2) ?? ""
                                archive.summary = rs.getOrNull<String>(3) ?? ""
                                archive.thumbhash = rs.getOrNull<String>(4) ?? ""
                                archive.created_at = rs.getOrNull<String>(5) ?? ""
                                archive.updated_at = rs.getOrNull<String>(6) ?? ""
                                archive.relative_path = rs.getOrNull<String>(7) ?? ""
                                archive.file_size = rs.getOrNull<Int64>(8) ?? 0
                                archive.pagecount = rs.getOrNull<Int32>(9) ?? 0
                                return Some(archive)
                            }
                            return None
                        } finally {
                            rs.close()
                        }
                    } finally {
                        stmt.close()
                    }
                } catch (e: Exception) {
                    getLogger("archive_dao").error("根据路径和文件名获取归档失败", ("error", e.message))
                    return None
                } finally {
                    try { conn.close() } catch (closeException: Exception) {}
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
        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case Some(conn) =>
                
                try {
                    let stmt = conn.prepareStatement("SELECT thumbhash FROM archives WHERE arcid = ?")
                    try {
                        stmt.set(0, archiveId)
                        let rs = stmt.query()
                        try {
                            if (rs.next()) {
                                return rs.getOrNull<String>(0) ?? ""
                            }
                            return ""
                        } finally {
                            rs.close()
                        }
                    } finally {
                        stmt.close()
                    }
                } catch (e: Exception) {
                    getLogger("archive_dao").error("获取缩略图hash失败", ("error", e.message))
                    return ""
                } finally {
                    try { conn.close() } catch (closeException: Exception) {}
                }
            case None =>
                getLogger("archive_dao").error("无法连接到数据库")
                return ""
        }
    }
    
    /**
     * 根据 ID 获取归档元数据（包含标签）
     */
    public static func getArchiveMetadataById(id: String): ArchiveData {
        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case Some(conn) =>
                
                try {
                // 使用 archives_with_tags 视图获取包含标签的数据
                let stmt = conn.prepareStatement(
                    "SELECT arcid, filename, title, summary, thumbhash, created_at, updated_at, relative_path, file_size, pagecount, archive_type, tags FROM archives_with_tags WHERE arcid = ?")
                stmt.set(0, id)
                let rs = stmt.query()

                if (rs.next()) {
                    let archive = ArchiveData()
                    archive.id = rs.getOrNull<String>(0) ?? ""
                    archive.filename = rs.getOrNull<String>(1) ?? ""
                    archive.title = rs.getOrNull<String>(2) ?? ""
                    archive.summary = rs.getOrNull<String>(3) ?? ""
                    archive.thumbhash = rs.getOrNull<String>(4) ?? ""
                    archive.created_at = rs.getOrNull<String>(5) ?? ""
                    archive.updated_at = rs.getOrNull<String>(6) ?? ""
                    archive.relative_path = rs.getOrNull<String>(7) ?? ""
                    archive.file_size = rs.getOrNull<Int64>(8) ?? 0
                    archive.pagecount = rs.getOrNull<Int32>(9) ?? 0
                    archive.archive_type = rs.getOrNull<String>(10) ?? "archive"
                    archive.tags = rs.getOrNull<String>(11) ?? ""

                    // 关闭查询的资源
                    rs.close()
                    stmt.close()
                    conn.close()
                    return archive
                }

                // 关闭资源
                rs.close()
                stmt.close()
                conn.close()
            } catch (e: Exception) {
                getLogger("archive_dao").error("查询归档元数据失败", ("error", e.message))
                conn.close()
            }
            case None => getLogger("archive_dao").error("无法连接到数据库")
        }
        return ArchiveData()
    }

    /**
     * 获取档案的 category_id
     */
    public static func getArchiveCategoryId(arcid: String): Int64 {
        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case Some(conn) =>
                
                try {
                    let stmt = conn.prepareStatement("SELECT category_id FROM archives WHERE arcid = ?")
                    try {
                        stmt.set(0, arcid)
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
                    getLogger("archive_dao").error("获取档案分类ID失败", ("error", e.message))
                    return 0
                } finally {
                    try { conn.close() } catch (_: Exception) {}
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
        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case Some(conn) =>
                try {
                    let stmt = conn.prepareStatement("UPDATE archives SET thumbhash = '' WHERE thumbhash != '' AND thumbhash IS NOT NULL")
                    try {
                        let result = stmt.update()
                        return result.rowCount
                    } finally {
                        stmt.close()
                    }
                } catch (e: Exception) {
                    getLogger("archive_dao").error("清理所有thumbhash失败", ("error", e.message))
                    return -1
                } finally {
                    try { conn.close() } catch (_: Exception) {}
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
        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case Some(conn) =>
                
                try {
                    let stmt = conn.prepareStatement("UPDATE archives SET category_id = ? WHERE arcid = ?")
                    try {
                        stmt.set(0, categoryId)
                        stmt.set(1, arcid)
                        let result = stmt.update()
                        return result.rowCount > 0
                    } finally {
                        stmt.close()
                    }
                } catch (e: Exception) {
                    getLogger("archive_dao").error("更新档案分类ID失败", ("error", e.message))
                    return false
                } finally {
                    try { conn.close() } catch (_: Exception) {}
                }
            case None =>
                getLogger("archive_dao").error("无法连接到数据库")
                return false
        }
    }
}
