package lrr4cj.dao

import std.database.sql.*
import lrr4cj.config.*
import std.collection.*
import std.io.*
import std.time.*

/**
 * 归档数据结构
 * 为了避免循环依赖，这个数据结构独立于 Archive 模型类
 */
public class ArchiveData {
    public var id: String = ""
    public var title: String = ""
    public var filename: String = ""
    public var summary: String = ""
    public var thumbhash: String = ""
    public var created_at: String = ""
    public var updated_at: String = ""
    public var relative_path: String = ""
    public var file_size: Int64 = 0
    public var isNew: Bool = false
    public var pagecount: Int32 = 0
    public var last_read_time: String = ""
    public var progress: Int32 = 0
    public var tags: String = ""
}

/**
 * 归档数据访问对象 (DAO)
 * 负责处理所有与归档相关的数据库操作
 */
public class ArchiveDao {
    
    /**
     * 获取所有归档
     */
    public static func getAllArchives(): Array<ArchiveData> {
        let connOpt = DatabaseConfig.createConnection()
        match (connOpt) {
            case Some(conn) =>
                var archives: ArrayList<ArchiveData> = ArrayList<ArchiveData>()
                try {
                    let stmt = conn.prepareStatement(
                        "SELECT arcid, title, filename, summary, thumbhash, created_at, updated_at, relative_path, file_size, isnew, pagecount, last_read_time, progress FROM archives ORDER BY id")
                    let rs = stmt.query()

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
                        archive.isNew = rs.getOrNull<Bool>(9) ?? false
                        archive.pagecount = rs.getOrNull<Int32>(10) ?? 0
                        archive.last_read_time = rs.getOrNull<String>(11) ?? ""
                        archive.progress = rs.getOrNull<Int32>(12) ?? 0
                        archives.add(archive)
                    }

                    conn.close()
                    return archives.toArray()
                } catch (e: Exception) {
                    println("查询归档失败: ${e}")
                    conn.close()
                    return Array<ArchiveData>()
                }
            case None =>
                println("无法连接到数据库")
                return Array<ArchiveData>()
        }
    }

    /**
     * 根据 ID 获取归档
     */
    public static func getArchiveById(id: String): ArchiveData {
        let connOpt = DatabaseConfig.createConnection()
        match (connOpt) {
            case Some(conn) => try {
                let stmt = conn.prepareStatement(
                    "SELECT arcid, title, filename, summary, thumbhash, created_at, updated_at, relative_path, file_size, isnew, pagecount, last_read_time, progress FROM archives WHERE arcid = ?")
                stmt.set(0, id)
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
                    archive.isNew = rs.getOrNull<Bool>(9) ?? false
                    archive.pagecount = rs.getOrNull<Int32>(10) ?? 0
                    archive.last_read_time = rs.getOrNull<String>(11) ?? ""
                    archive.progress = rs.getOrNull<Int32>(12) ?? 0

                    conn.close()
                    return archive
                }

                conn.close()
            } catch (e: Exception) {
                println("查询归档失败: ${e}")
                conn.close()
            }
            case None => println("无法连接到数据库")
        }
        return ArchiveData()
    }

    /**
     * 搜索归档
     */
    public static func searchArchives(filter: String, category: String, start: Int32, count: Int32, sortby: String, order: String): (Array<ArchiveData>, Int64) {
        let connOpt = DatabaseConfig.createConnection()
        match (connOpt) {
            case Some(conn) =>
                var archives: ArrayList<ArchiveData> = ArrayList<ArchiveData>()
                try {
                println("开始搜索归档，参数: filter='${filter}', category='${category}', start=${start}, count=${count}, sortby='${sortby}', order='${order}'")
                
                // 首先获取总记录数
                var countSql = "SELECT COUNT(*) FROM archives_with_tags"
                if (filter.size > 0) {
                    countSql += " WHERE title LIKE ? OR filename LIKE ?"
                }
                
                println("执行计数SQL: ${countSql}")
                let countStmt = conn.prepareStatement(countSql)
                var totalCount = 0
                
                if (filter.size > 0) {
                    countStmt.set<String>(1, "%${filter}%")
                    countStmt.set<String>(2, "%${filter}%")
                }
                
                let countRs = countStmt.query()
                if (countRs.next()) {
                    totalCount = countRs.getOrNull<Int64>(0) ?? 0
                    println("获取到总记录数: ${totalCount}")
                } else {
                    println("无法获取总记录数")
                }
                // 确保关闭第一个查询的结果集
                countRs.close()
                
                // 然后查询分页数据，使用archives_with_tags视图获取标签信息
                var sql = "SELECT arcid, filename, title, summary, thumbhash, created_at, updated_at, tags FROM archives_with_tags"
                
                if (filter.size > 0) {
                    sql += " WHERE title LIKE ? OR filename LIKE ?"
                }
                
                // 处理排序参数
                let orderByColumn = match (sortby) {
                    case "title" => "title"
                    case "lastread" => "created_at"  // archives_with_tags视图没有last_read_time，使用created_at代替
                    case _ => "title"  // 默认按标题排序
                }
                
                let orderDirection = if (order == "desc") { "DESC" } else { "ASC" }
                
                sql += " ORDER BY ${orderByColumn} ${orderDirection} LIMIT ${count} OFFSET ${start}"
                
                // 打印SQL语句用于调试
                println("执行数据SQL: ${sql}")
                println("参数 - filter: '${filter}', start: ${start}, count: ${count}")
                
                let stmt = conn.prepareStatement(sql)
                
                if (filter.size > 0) {
                    stmt.set<String>(1, "%${filter}%")
                    stmt.set<String>(2, "%${filter}%")
                }
                
                let rs = stmt.query()
                println("SQL查询执行完成")

                while (rs.next()) {
                    let archive = ArchiveData()
                    try {
                        archive.id = rs.getOrNull<String>(0) ?? ""
                        archive.filename = rs.getOrNull<String>(1) ?? ""
                        archive.title = rs.getOrNull<String>(2) ?? ""
                        archive.summary = rs.getOrNull<String>(3) ?? ""
                        archive.thumbhash = rs.getOrNull<String>(4) ?? ""
                        archive.created_at = rs.getOrNull<String>(5) ?? ""
                        archive.updated_at = rs.getOrNull<String>(6) ?? ""
                        archive.tags = rs.getOrNull<String>(7) ?? ""
                        // 设置默认值，这些字段在archives_with_tags视图中没有
                        archive.relative_path = ""
                        archive.file_size = 0
                        archive.isNew = false
                        archive.pagecount = 0
                        archive.last_read_time = ""
                        archive.progress = 0
                        archives.add(archive)
                    } catch (e: Exception) {
                        println("读取字段时出错: ${e}")
                        throw e
                    }
                }

                let resultArray = archives.toArray()
                println("返回${resultArray.size}条记录，总记录数: ${totalCount}")
                conn.close()
                return (resultArray, totalCount)
            } catch (e: Exception) {
                println("搜索归档失败: ${e}")
                conn.close()
                return (Array<ArchiveData>(), 0)
            }
            case None =>
                println("无法连接到数据库")
                return (Array<ArchiveData>(), 0)
        }
    }

    /**
     * 创建归档记录
     */
    public static func create(archive: ArchiveData): Bool {
        let connOpt = DatabaseConfig.createConnection()
        match (connOpt) {
            case Some(conn) => try {
                let stmt = conn.prepareStatement(
                    "INSERT INTO archives (arcid, title, filename, summary, thumbhash, created_at, updated_at, relative_path, file_size, isnew, pagecount, last_read_time, progress) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)")
                
                stmt.set(0, archive.id)
                stmt.set(1, archive.title)
                stmt.set(2, archive.filename)
                stmt.set(3, archive.summary)
                stmt.set(4, archive.thumbhash)
                stmt.set(5, archive.created_at)
                stmt.set(6, archive.updated_at)
                stmt.set(7, archive.relative_path)
                stmt.set(8, archive.file_size)
                stmt.set(9, archive.isNew)
                stmt.set(10, archive.pagecount)
                stmt.set(11, archive.last_read_time)
                stmt.set(12, archive.progress)
                
                let result = stmt.update()
                conn.close()
                return true  // 简化实现，假设更新成功
            } catch (e: Exception) {
                println("创建归档失败: ${e}")
                conn.close()
                return false
            }
            case None =>
                println("无法连接到数据库")
                return false
        }
    }

    /**
     * 插入归档记录 - 专门为 ShinobuService 提供的方法
     */
    public static func insertArchive(archiveId: String, title: String, fileName: String, fileSize: Int64, fileModTime: Int64, filePath: String): Bool {
        let connOpt = DatabaseConfig.createConnection()
        match (connOpt) {
            case Some(conn) =>
                try {
                    // 使用数据库的默认值来处理时间戳，避免格式问题
                    let sql = "INSERT INTO archives (arcid, title, filename, summary, thumbhash, relative_path, file_size, isnew, pagecount, last_read_time, progress) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)"
                    
                    let stmt = conn.prepareStatement(sql)
                    
                    stmt.set(0, archiveId)
                    stmt.set(1, title)  // 使用传入的标题
                    stmt.set(2, fileName)
                    stmt.set(3, "")  // summary
                    stmt.set(4, "")  // thumbhash
                    stmt.set(5, filePath)  // relative_path
                    stmt.set(6, fileSize)
                    stmt.set(7, true)  // isnew
                    stmt.set(8, 0)  // pagecount
                    stmt.set(9, DateTime.now())  // last_read_time
                    stmt.set(10, 0)  // progress
                    
                    let result = stmt.update()
                    conn.close()
                    println("Successfully inserted archive record: ${archiveId}")
                    return true
                } catch (e: Exception) {
                    println("Failed to execute insert statement: ${e.message}")
                    conn.close()
                    return false
                }
            case None =>
                println("Failed to connect to database")
                return false
        }
    }

    /**
     * 更新归档记录
     */
    public static func update(archive: ArchiveData): Bool {
        let connOpt = DatabaseConfig.createConnection()
        match (connOpt) {
            case Some(conn) => try {
                let stmt = conn.prepareStatement(
                    "UPDATE archives SET title = ?, filename = ?, summary = ?, thumbhash = ?, updated_at = ?, relative_path = ?, file_size = ?, isnew = ?, pagecount = ?, last_read_time = ?, progress = ? WHERE arcid = ?")
                
                stmt.set(0, archive.title)
                stmt.set(1, archive.filename)
                stmt.set(2, archive.summary)
                stmt.set(3, archive.thumbhash)
                stmt.set(4, archive.updated_at)
                stmt.set(5, archive.relative_path)
                stmt.set(6, archive.file_size)
                stmt.set(7, archive.isNew)
                stmt.set(8, archive.pagecount)
                stmt.set(9, archive.last_read_time)
                stmt.set(10, archive.progress)
                stmt.set(11, archive.id)
                
                let result = stmt.update()
                conn.close()
                return true  // 简化实现，假设更新成功
            } catch (e: Exception) {
                println("更新归档失败: ${e}")
                conn.close()
                return false
            }
            case None =>
                println("无法连接到数据库")
                return false
        }
    }

    /**
     * 删除归档记录
     */
    public static func delete(id: String): Bool {
        let connOpt = DatabaseConfig.createConnection()
        match (connOpt) {
            case Some(conn) => try {
                let stmt = conn.prepareStatement("DELETE FROM archives WHERE arcid = ?")
                stmt.set(0, id)
                
                let result = stmt.update()
                conn.close()
                return true  // 简化实现，假设更新成功
            } catch (e: Exception) {
                println("删除归档失败: ${e}")
                conn.close()
                return false
            }
            case None =>
                println("无法连接到数据库")
                return false
        }
    }
    
    /**
     * 更新归档的页数
     */
    public static func updatePageCount(archiveId: String, pageCount: Int32): Bool {
        let connOpt = DatabaseConfig.createConnection()
        match (connOpt) {
            case Some(conn) => try {
                let stmt = conn.prepareStatement("UPDATE archives SET pagecount = ? WHERE arcid = ?")
                stmt.set(0, pageCount)
                stmt.set(1, archiveId)
                
                let result = stmt.update()
                conn.close()
                return true
            } catch (e: Exception) {
                println("更新归档页数失败: ${e}")
                conn.close()
                return false
            }
            case None =>
                println("无法连接到数据库")
                return false
        }
    }
    
    /**
     * 更新归档的缩略图hash
     */
    public static func updateThumbHash(archiveId: String, thumbHash: String): Bool {
        let connOpt = DatabaseConfig.createConnection()
        match (connOpt) {
            case Some(conn) => try {
                let stmt = conn.prepareStatement("UPDATE archives SET thumbhash = ? WHERE arcid = ?")
                stmt.set(0, thumbHash)
                stmt.set(1, archiveId)
                
                let result = stmt.update()
                conn.close()
                return true
            } catch (e: Exception) {
                println("更新归档缩略图hash失败: ${e}")
                conn.close()
                return false
            }
            case None =>
                println("无法连接到数据库")
                return false
        }
    }
    
    /**
     * 同时更新归档的页数和缩略图hash
     */
    public static func updateArchiveDetails(archiveId: String, pageCount: Int32, thumbHash: String): Bool {
        let connOpt = DatabaseConfig.createConnection()
        match (connOpt) {
            case Some(conn) => try {
                let stmt = conn.prepareStatement("UPDATE archives SET pagecount = ?, thumbhash = ? WHERE arcid = ?")
                stmt.set(0, pageCount)
                stmt.set(1, thumbHash)
                stmt.set(2, archiveId)
                
                let result = stmt.update()
                conn.close()
                return true
            } catch (e: Exception) {
                println("更新归档详情失败: ${e}")
                conn.close()
                return false
            }
            case None =>
                println("无法连接到数据库")
                return false
        }
    }

    /**
     * 获取所有没有缩略图的归档
     */
    public static func getArchivesWithoutThumbnails(): Array<ArchiveData> {
        let connOpt = DatabaseConfig.createConnection()
        match (connOpt) {
            case Some(conn) => try {
                var archives: ArrayList<ArchiveData> = ArrayList<ArchiveData>()
                let stmt = conn.prepareStatement(
                    "SELECT arcid, title, filename, summary, thumbhash, created_at, updated_at, relative_path, file_size, isnew, pagecount, last_read_time, progress FROM archives WHERE thumbhash = '' OR thumbhash IS NULL ORDER BY id")
                let rs = stmt.query()

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
                    archive.isNew = rs.getOrNull<Bool>(9) ?? false
                    archive.pagecount = rs.getOrNull<Int32>(10) ?? 0
                    archive.last_read_time = rs.getOrNull<String>(11) ?? ""
                    archive.progress = rs.getOrNull<Int32>(12) ?? 0
                    archives.add(archive)
                }
                conn.close()
                return archives.toArray()
            } catch (e: Exception) {
                println("获取无缩略图归档失败: ${e}")
                conn.close()
                return Array<ArchiveData>()
            }
            case None =>
                println("无法连接到数据库")
                return Array<ArchiveData>()
        }
    }

    /**
     * 检查归档是否存在
     */
    public static func exists(id: String): Bool {
        let connOpt = DatabaseConfig.createConnection()
        match (connOpt) {
            case Some(conn) => try {
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
                println("检查归档存在性失败: ${e}")
                conn.close()
                return false
            }
            case None =>
                println("无法连接到数据库")
                return false
        }
    }

    /**
     * 根据文件路径获取归档信息
     */
    public static func getByPath(filePath: String): Option<ArchiveData> {
        let connOpt = DatabaseConfig.createConnection()
        match (connOpt) {
            case Some(conn) => try {
                let stmt = conn.prepareStatement("SELECT arcid, title, filename, summary, thumbhash, created_at, updated_at, relative_path, file_size, isnew, pagecount, last_read_time, progress FROM archives WHERE relative_path = ?")
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
                    archive.isNew = rs.getOrNull<Bool>(9) ?? false
                    archive.pagecount = rs.getOrNull<Int32>(10) ?? 0
                    archive.last_read_time = rs.getOrNull<String>(11) ?? ""
                    archive.progress = rs.getOrNull<Int32>(12) ?? 0
                    
                    conn.close()
                    return Some(archive)
                } else {
                    conn.close()
                    return None
                }
            } catch (e: Exception) {
                println("根据路径获取归档失败: ${e}")
                conn.close()
                return None
            }
            case None =>
                println("无法连接到数据库")
                return None
        }
    }

    /**
     * 根据相对路径和文件名获取归档
     */
    public static func getByPathAndFilename(relativePath: String, filename: String): Option<ArchiveData> {
        let connOpt = DatabaseConfig.createConnection()
        match (connOpt) {
            case Some(conn) => try {
                let stmt = conn.prepareStatement("SELECT arcid, title, filename, summary, thumbhash, created_at, updated_at, relative_path, file_size, isnew, pagecount, last_read_time, progress FROM archives WHERE relative_path = ? AND filename = ?")
                stmt.set(0, relativePath)
                stmt.set(1, filename)
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
                    archive.isNew = rs.getOrNull<Bool>(9) ?? false
                    archive.pagecount = rs.getOrNull<Int32>(10) ?? 0
                    archive.last_read_time = rs.getOrNull<String>(11) ?? ""
                    archive.progress = rs.getOrNull<Int32>(12) ?? 0
                    
                    conn.close()
                    return Some(archive)
                } else {
                    conn.close()
                    return None
                }
            } catch (e: Exception) {
                println("根据路径和文件名获取归档失败: ${e}")
                conn.close()
                return None
            }
            case None =>
                println("无法连接到数据库")
                return None
        }
    }
    
    /**
     * 获取归档的缩略图hash
     */
    public static func getThumbnailHash(archiveId: String): String {
        let connOpt = DatabaseConfig.createConnection()
        match (connOpt) {
            case Some(conn) => try {
                let stmt = conn.prepareStatement("SELECT thumbhash FROM archives WHERE arcid = ?")
                stmt.set(0, archiveId)
                let rs = stmt.query()
                
                if (rs.next()) {
                    let thumbhash = rs.getOrNull<String>(0) ?? ""
                    conn.close()
                    return thumbhash
                }
                
                conn.close()
                return ""
            } catch (e: Exception) {
                println("获取缩略图hash失败: ${e}")
                conn.close()
                return ""
            }
            case None =>
                println("无法连接到数据库")
                return ""
        }
    }
}