package lrr4cj.dao

import std.database.sql.*
import lrr4cj.config.*
import lrr4cj.utils.*
import std.collection.*
import std.io.*
import std.time.*
import stdx.log.*

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
            case Some(conn) => try {
                // 首先获取档案的内部ID
                let getArchiveIdStmt = conn.prepareStatement("SELECT id FROM archives WHERE arcid = ?")
                getArchiveIdStmt.set(0, archiveId)
                let archiveIdResult = getArchiveIdStmt.query()
                
                if (!archiveIdResult.next()) {
                    return false
                }
                
                let archiveInternalId = archiveIdResult.getOrNull<Int64>(0) ?? 0
                
                // 删除现有的标签关联
                let deleteStmt = conn.prepareStatement("DELETE FROM archive_tags WHERE archive_id = ?")
                deleteStmt.set(0, archiveInternalId)
                deleteStmt.update()
                
                // 如果标签字符串为空，直接返回
                if (tagsString.size == 0 || tagsString == "") {
                    conn.close()
                    return true
                }
                
                // 解析标签字符串
                let tags = parseTagsString(tagsString)
                
                // 为每个标签创建或获取标签ID，并建立关联
                for (tag in tags) {
                    let tagId = getOrCreateTag(conn, tag)
                    
                    // 建立档案和标签的关联
                    let insertRelationStmt = conn.prepareStatement("INSERT INTO archive_tags (archive_id, tag_id) VALUES (?, ?)")
                    insertRelationStmt.set(0, archiveInternalId)
                    insertRelationStmt.set(1, tagId)
                    insertRelationStmt.update()
                }
                
                conn.close()
                true
            } catch (e: Exception) {
                getLogger("tag_dao").error("Error updating archive tags", ("error", e.message))
                try {
                    conn.close()
                } catch (closeException: Exception) {
                    getLogger("tag_dao").warn("Error closing database connection", ("error", closeException.message))
                }
                false
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
        findStmt.set(0, tagName)
        let result = findStmt.query()
        
        if (result.next()) {
            return result.getOrNull<Int64>(0) ?? 0
        }
        
        // 创建新标签
        let insertStmt = conn.prepareStatement("INSERT INTO tags (name) VALUES (?) RETURNING id")
        insertStmt.set(0, tagName)
        let insertResult = insertStmt.query()
        
        if (insertResult.next()) {
            return insertResult.getOrNull<Int64>(0) ?? 0
        }
        
        return 0
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
            case Some(conn) => try {
                // 使用archives_with_tags视图获取标签
                let stmt = conn.prepareStatement("SELECT tags FROM archives_with_tags WHERE arcid = ?")
                stmt.set(0, archiveId)
                let result = stmt.query()
                
                if (result.next()) {
                    return result.getOrNull<String>(0) ?? ""
                }
                
                ""
            } catch (e: Exception) {
                getLogger("tag_dao").error("Error getting archive tags", ("error", e.message))
                ""
            }
        }
    }
}