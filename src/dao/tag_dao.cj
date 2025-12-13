package lrr4cj.dao

import std.database.sql.*
import lrr4cj.config.*
import lrr4cj.utils.*
import std.collection.*
import std.io.*
import std.time.*
import stdx.log.*

/**
 * 标签数据结构
 */
public class TagData {
    public var id: Int64 = 0
    public var name: String = ""
    public var namespace: String = ""
    public var value: String = ""
    public var weight: Int32 = 1
    public var created_at: String = ""
    public var updated_at: String = ""

    public init() {}
}

/**
 * 标签数据访问对象
 */
public class TagDao {
    
    /**
     * 更新档案的标签
     * @param archiveId 档案ID
     * @param tagsString 标签字符串（逗号分隔）
     * @return 是否更新成功
     */
    public static func updateArchiveTags(archiveId: String, tagsString: String): Bool {
        let connOpt = DatabaseConfig.createConnection()
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
                        let tagId = getOrCreateTag(conn, tag)

                        // 建立档案和标签的关联
                        let insertRelationStmt = conn.prepareStatement("INSERT INTO archive_tags (archive_id, tag_id) VALUES (?, ?)")
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
     * @param tagsString 标签字符串（逗号分隔）
     * @return 标签数组
     */
    private static func parseTagsString(tagsString: String): ArrayList<String> {
        let tags = tagsString.split(",")
        var result: ArrayList<String> = ArrayList<String>()
        
        for (tag in tags) {
            // 简单处理空格，不使用 strip
            if (tag.size > 0) {
                result.add(tag)
            }
        }
        
        return result
    }
    
    /**
     * 获取或创建标签
     * @param conn 数据库连接
     * @param tagName 标签名称
     * @return 标签ID
     */
    private static func getOrCreateTag(conn: Connection, tagName: String): Int64 {
        // 尝试查找现有标签
        let findStmt = conn.prepareStatement("SELECT id FROM tags WHERE name = ?")
        try {
            findStmt.set(0, tagName)
            let result = findStmt.query()
            try {
                if (result.next()) {
                    return result.getOrNull<Int64>(0) ?? 0
                }
            } finally {
                result.close()
            }
        } finally {
            findStmt.close()
        }

        // 创建新标签
        let insertStmt = conn.prepareStatement("INSERT INTO tags (name) VALUES (?) RETURNING id")
        try {
            insertStmt.set(0, tagName)
            let insertResult = insertStmt.query()
            try {
                if (insertResult.next()) {
                    return insertResult.getOrNull<Int64>(0) ?? 0
                }
            } finally {
                insertResult.close()
            }
        } finally {
            insertStmt.close()
        }

        0
    }
    
    /**
     * 获取档案的所有标签
     * @param archiveId 档案ID
     * @return 标签字符串（逗号分隔）
     */
    public static func getArchiveTags(archiveId: String): String {
        let connOpt = DatabaseConfig.createConnection()
        match (connOpt) {
            case None => ""
            case Some(conn) =>
                try {
                    // 使用archives_with_tags视图获取标签
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
                    try {
                        conn.close()
                    } catch (closeException: Exception) {
                        getLogger("tag_dao").warn("Error closing database connection", ("error", closeException.message))
                    }
                }
        }
    }

    /**
     * 根据名称获取标签
     */
    public static func getTagByName(name: String): TagData {
        let connOpt = DatabaseConfig.createConnection()
        match (connOpt) {
            case Some(conn) =>
                try {
                    let stmt = conn.prepareStatement(
                        "SELECT id, name, namespace, value, weight, created_at, updated_at FROM tags WHERE name = ?")
                    try {
                        stmt.set(0, name)
                        let rs = stmt.query()
                        try {
                            if (rs.next()) {
                                let tag = TagData()
                                tag.id = rs.getOrNull<Int64>(0) ?? 0
                                tag.name = rs.getOrNull<String>(1) ?? ""
                                tag.namespace = rs.getOrNull<String>(2) ?? ""
                                tag.value = rs.getOrNull<String>(3) ?? ""
                                tag.weight = rs.getOrNull<Int32>(4) ?? 1
                                tag.created_at = rs.getOrNull<String>(5) ?? ""
                                tag.updated_at = rs.getOrNull<String>(6) ?? ""
                                return tag
                            }
                        } finally {
                            rs.close()
                        }
                    } finally {
                        stmt.close()
                    }
                } catch (e: Exception) {
                    getLogger("tag_dao").error("查询标签失败", ("error", e.message), ("name", name))
                } finally {
                    try {
                        conn.close()
                    } catch (closeException: Exception) {
                        getLogger("tag_dao").warn("Error closing database connection", ("error", closeException.message))
                    }
                }
            case None => getLogger("tag_dao").error("无法连接到数据库")
        }
        return TagData()
    }

    /**
     * 创建标签
     */
    public static func create(tag: TagData): Bool {
        let connOpt = DatabaseConfig.createConnection()
        match (connOpt) {
            case Some(conn) =>
                try {
                    let stmt = conn.prepareStatement(
                        "INSERT INTO tags (name, namespace, value, weight) VALUES (?, ?, ?, ?)")
                    try {
                        stmt.set(0, tag.name)
                        stmt.set(1, tag.namespace)
                        stmt.set(2, tag.value)
                        stmt.set(3, tag.weight)
                        stmt.update()
                        return true
                    } finally {
                        stmt.close()
                    }
                } catch (e: Exception) {
                    getLogger("tag_dao").error("创建标签失败", ("error", e.message), ("name", tag.name))
                    return false
                } finally {
                    try {
                        conn.close()
                    } catch (closeException: Exception) {
                        getLogger("tag_dao").warn("Error closing database connection", ("error", closeException.message))
                    }
                }
            case None =>
                getLogger("tag_dao").error("无法连接到数据库")
                return false
        }
    }
}
