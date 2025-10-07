package lrr4cj.models

import cjoy.json.*
import std.database.sql.*
import lrr4cj.config.*
import std.collection.*
import std.time.*

/**
 * 分类数据模型
 */
public class Category {
    public var id: String = ""
    public var name: String = ""
    public var search: String = ""
    public var isPinned: Bool = false
    public var archives: Array<String> = []
}

/**
 * 分类数据访问层
 */
public class CategoryModel {
    /**
     * 获取所有分类
     */
    public static func getAllCategories(): Array<Category> {
        let connOpt = DatabaseConfig.createConnection()
        match (connOpt) {
            case Some(conn) =>
                var categories: ArrayList<Category> = ArrayList<Category>()
                try {
                    let stmt = conn.prepareStatement("SELECT catid, name, search, pinned FROM categories ORDER BY id")
                    let rs = stmt.query()
                    
                    while (rs.next()) {
                        let category = Category()
                        category.id = rs.getOrNull<String>(1) ?? ""
                        category.name = rs.getOrNull<String>(2) ?? ""
                        category.search = rs.getOrNull<String>(3) ?? ""
                        category.isPinned = rs.getOrNull<Bool>(4) ?? false
                        
                        // 获取分类下的档案
                        let archiveStmt = conn.prepareStatement("SELECT arcid FROM archive_categories WHERE category_id = ?")
                        archiveStmt.set(0, category.id)
                        let archiveRs = archiveStmt.query()
                        
                        var archiveIds: ArrayList<String> = ArrayList<String>()
                        while (archiveRs.next()) {
                            archiveIds.add(archiveRs.getOrNull<String>(1) ?? "")
                        }
                        category.archives = archiveIds.toArray()
                        
                        categories.add(category)
                    }
                    
                    conn.close()
                    return categories.toArray()
                } catch (e: Exception) {
                    println("查询分类失败: ${e}")
                    conn.close()
                    return Array<Category>()
                }
            case None =>
                println("无法连接到数据库")
                return Array<Category>()
        }
    }
    
    /**
     * 根据ID获取分类
     */
    public static func getCategoryById(id: String): Category {
        let connOpt = DatabaseConfig.createConnection()
        match (connOpt) {
            case Some(conn) =>
                try {
                    let stmt = conn.prepareStatement("SELECT catid, name, search, pinned FROM categories WHERE catid = ?")
                    stmt.set(0, id)
                    let rs = stmt.query()
                    
                    if (rs.next()) {
                        let category = Category()
                        category.id = rs.getOrNull<String>(1) ?? ""
                        category.name = rs.getOrNull<String>(2) ?? ""
                        category.search = rs.getOrNull<String>(3) ?? ""
                        category.isPinned = rs.getOrNull<Bool>(4) ?? false
                        
                        // 获取分类下的档案
                        let archiveStmt = conn.prepareStatement("SELECT arcid FROM archive_categories WHERE category_id = ?")
                        archiveStmt.set(0, category.id)
                        let archiveRs = archiveStmt.query()
                        
                        var archiveIds: ArrayList<String> = ArrayList<String>()
                        while (archiveRs.next()) {
                            archiveIds.add(archiveRs.getOrNull<String>(1) ?? "")
                        }
                        category.archives = archiveIds.toArray()
                        
                        conn.close()
                        return category
                    }
                    
                    conn.close()
                } catch (e: Exception) {
                    println("查询分类失败: ${e}")
                    conn.close()
                }
            case None =>
                println("无法连接到数据库")
        }
        return Category()
    }
    
    /**
     * 创建新分类
     */
    public static func createCategory(name: String, search: String): Category {
        let connOpt = DatabaseConfig.createConnection()
        match (connOpt) {
            case Some(conn) =>
                try {
                    let newId = "SET_" + DateTime.now().toString()
                    let stmt = conn.prepareStatement("INSERT INTO categories (catid, name, search, pinned) VALUES (?, ?, ?, ?)")
                    stmt.set(0, newId)
                    stmt.set(1, name)
                    stmt.set(2, search)
                    stmt.set(3, false)
                    let result = stmt.update()
                    
                    conn.close()
                    if (result.rowCount > 0) {
                        let category = Category()
                        category.id = newId
                        category.name = name
                        category.search = search
                        category.isPinned = false
                        category.archives = Array<String>()
                        return category
                    }
                } catch (e: Exception) {
                    println("创建分类失败: ${e}")
                    conn.close()
                }
            case None =>
                println("无法连接到数据库")
        }
        return Category()
    }
    
    /**
     * 更新分类
     */
    public static func updateCategory(id: String, name: String, search: String): Bool {
        let connOpt = DatabaseConfig.createConnection()
        match (connOpt) {
            case Some(conn) =>
                try {
                    let stmt = conn.prepareStatement("UPDATE categories SET name = ?, search = ? WHERE catid = ?")
                    stmt.set(0, name)
                    stmt.set(1, search)
                    stmt.set(2, id)
                    let result = stmt.update()
                    
                    conn.close()
                    return result.rowCount > 0
                } catch (e: Exception) {
                    println("更新分类失败: ${e}")
                    conn.close()
                    return false
                }
            case None =>
                println("无法连接到数据库")
                return false
        }
    }
    
    /**
     * 删除分类
     */
    public static func deleteCategory(id: String): Bool {
        let connOpt = DatabaseConfig.createConnection()
        match (connOpt) {
            case Some(conn) =>
                try {
                    // 先删除分类与档案的关联
                    let deleteRelationsStmt = conn.prepareStatement("DELETE FROM archive_categories WHERE category_id = ?")
                    deleteRelationsStmt.set(0, id)
                    deleteRelationsStmt.update()
                    
                    // 再删除分类
                    let stmt = conn.prepareStatement("DELETE FROM categories WHERE catid = ?")
                    stmt.set(0, id)
                    let result = stmt.update()
                    
                    conn.close()
                    return result.rowCount > 0
                } catch (e: Exception) {
                    println("删除分类失败: ${e}")
                    conn.close()
                    return false
                }
            case None =>
                println("无法连接到数据库")
                return false
        }
    }
    
    /**
     * 向分类添加档案
     */
    public static func addArchiveToCategory(categoryId: String, archiveId: String): Bool {
        let connOpt = DatabaseConfig.createConnection()
        match (connOpt) {
            case Some(conn) =>
                try {
                    let stmt = conn.prepareStatement("INSERT INTO archive_categories (archive_id, category_id) VALUES (?, ?)")
                    stmt.set(0, archiveId)
                    stmt.set(1, categoryId)
                    let result = stmt.update()
                    
                    conn.close()
                    return result.rowCount > 0
                } catch (e: Exception) {
                    println("添加档案到分类失败: ${e}")
                    conn.close()
                    return false
                }
            case None =>
                println("无法连接到数据库")
                return false
        }
    }
    
    /**
     * 从分类移除档案
     */
    public static func removeArchiveFromCategory(categoryId: String, archiveId: String): Bool {
        let connOpt = DatabaseConfig.createConnection()
        match (connOpt) {
            case Some(conn) =>
                try {
                    let stmt = conn.prepareStatement("DELETE FROM archive_categories WHERE archive_id = ? AND category_id = ?")
                    stmt.set(0, archiveId)
                    stmt.set(1, categoryId)
                    let result = stmt.update()
                    
                    conn.close()
                    return result.rowCount > 0
                } catch (e: Exception) {
                    println("从分类移除档案失败: ${e}")
                    conn.close()
                    return false
                }
            case None =>
                println("无法连接到数据库")
                return false
        }
    }
}