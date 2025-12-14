package lrr4cj.dao

import std.database.sql.*
import stdx.log.*
import lrr4cj.config.*
import lrr4cj.utils.*

public class UserRow {
    public var id: Int64 = 0
    public var username: String = ""
    public var passwordSalt: String = ""
    public var passwordHash: String = ""
    public var createdAt: String = ""

    public init() {}
}

public class UserDao {
    public static func createTable(): Bool {
        let logger = getLogger("user_dao")
        let connOpt = DatabaseConfig.createConnection()
        match (connOpt) {
            case Some(conn) =>
                try {
                    // 先检查表是否已存在
                    let checkStmt = conn.prepareStatement("SELECT COUNT(*) FROM information_schema.tables WHERE table_name = 'users' AND table_schema = 'public'")
                    let rs = checkStmt.query()
                    var tableExists = false
                    if (rs.next()) {
                        let count = rs.getOrNull<Int64>(0) ?? 0
                        tableExists = count > 0
                    }
                    rs.close()
                    checkStmt.close()

                    if (!tableExists) {
                        logger.info("users表不存在，创建新表")
                        let sql = """
                            CREATE TABLE users (
                                id INTEGER PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
                                username VARCHAR(64) UNIQUE NOT NULL,
                                password_salt VARCHAR(64) NOT NULL,
                                password_hash VARCHAR(64) NOT NULL,
                                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                            )
                        """
                        let stmt = conn.prepareStatement(sql)
                        stmt.update()
                        stmt.close()
                    } else {
                        logger.info("users表已存在，跳过创建")
                    }
                    return true
                } catch (e: Exception) {
                    logger.error("创建 users 表失败", ("error", e.message))
                    logger.error("异常类型: ${e.toString()}")
                    return false
                } finally {
                    try { conn.close() } catch (_: Exception) {}
                }
            case None =>
                logger.error("无法创建数据库连接")
                return false
        }
    }

    public static func getByUsername(username: String): UserRow {
        let connOpt = DatabaseConfig.createConnection()
        match (connOpt) {
            case Some(conn) =>
                try {
                    let stmt = conn.prepareStatement("""
                        SELECT id, username, password_salt, password_hash, created_at
                        FROM users
                        WHERE username = ?
                    """)
                    try {
                        stmt.set(0, username)
                        let rs = stmt.query()
                        try {
                            if (rs.next()) {
                                let row = UserRow()
                                row.id = rs.getOrNull<Int64>(0) ?? 0
                                row.username = rs.getOrNull<String>(1) ?? ""
                                row.passwordSalt = rs.getOrNull<String>(2) ?? ""
                                row.passwordHash = rs.getOrNull<String>(3) ?? ""
                                row.createdAt = rs.getOrNull<String>(4) ?? ""
                                return row
                            }
                        } finally {
                            rs.close()
                        }
                    } finally {
                        stmt.close()
                    }
                    return UserRow()
                } catch (_: Exception) {
                    return UserRow()
                } finally {
                    try { conn.close() } catch (_: Exception) {}
                }
            case None => return UserRow()
        }
    }

    public static func getById(id: Int64): UserRow {
        let connOpt = DatabaseConfig.createConnection()
        match (connOpt) {
            case Some(conn) =>
                try {
                    let stmt = conn.prepareStatement("""
                        SELECT id, username, password_salt, password_hash, created_at
                        FROM users
                        WHERE id = ?
                    """)
                    try {
                        stmt.set(0, id)
                        let rs = stmt.query()
                        try {
                            if (rs.next()) {
                                let row = UserRow()
                                row.id = rs.getOrNull<Int64>(0) ?? 0
                                row.username = rs.getOrNull<String>(1) ?? ""
                                row.passwordSalt = rs.getOrNull<String>(2) ?? ""
                                row.passwordHash = rs.getOrNull<String>(3) ?? ""
                                row.createdAt = rs.getOrNull<String>(4) ?? ""
                                return row
                            }
                        } finally {
                            rs.close()
                        }
                    } finally {
                        stmt.close()
                    }
                    return UserRow()
                } catch (_: Exception) {
                    return UserRow()
                } finally {
                    try { conn.close() } catch (_: Exception) {}
                }
            case None => return UserRow()
        }
    }

    public static func createUser(username: String, password: String, pepper: String): Option<Int64> {
        let logger = getLogger("user_dao")
        let trimmed = username.trimAscii()
        if (trimmed.size < 3 || trimmed.size > 64) {
            return None
        }
        if (password.size < 6 || password.size > 256) {
            return None
        }

        // 每个用户一份 salt（hex）
        let salt = AuthUtils.generateTokenHex(bytesLen: 16) // 16 bytes -> 32 hex chars
        let passHash = AuthUtils.sha256Hex("${salt}:${password}:${pepper}")

        let connOpt = DatabaseConfig.createConnection()
        match (connOpt) {
            case Some(conn) =>
                try {
                    let stmt = conn.prepareStatement("""
                        INSERT INTO users (username, password_salt, password_hash)
                        VALUES (?, ?, ?)
                        RETURNING id
                    """)
                    try {
                        stmt.set(0, trimmed)
                        stmt.set(1, salt)
                        stmt.set(2, passHash)
                        let rs = stmt.query()
                        try {
                            if (rs.next()) {
                                let id = rs.getOrNull<Int64>(0) ?? 0
                                if (id > 0) {
                                    return Some(id)
                                }
                            }
                        } finally {
                            rs.close()
                        }
                        return None
                    } finally {
                        stmt.close()
                    }
                } catch (e: Exception) {
                    // unique violation 等错误统一返回 None，由 controller 解释
                    logger.warn("创建用户失败", ("error", e.message))
                    return None
                } finally {
                    try { conn.close() } catch (_: Exception) {}
                }
            case None => return None
        }
    }

    /**
     * 检查用户表是否为空（用于判断是否允许公开注册第一个用户）
     */
    public static func isEmpty(): Bool {
        let connOpt = DatabaseConfig.createConnection()
        match (connOpt) {
            case Some(conn) =>
                try {
                    let stmt = conn.prepareStatement("SELECT COUNT(*) FROM users")
                    try {
                        let rs = stmt.query()
                        try {
                            if (rs.next()) {
                                let count = rs.getOrNull<Int64>(0) ?? 0
                                return count == 0
                            }
                        } finally {
                            rs.close()
                        }
                    } finally {
                        stmt.close()
                    }
                    return true
                } catch (_: Exception) {
                    return true
                } finally {
                    try { conn.close() } catch (_: Exception) {}
                }
            case None => return true
        }
    }

    public static func verifyPassword(username: String, password: String, pepper: String): Option<Int64> {
        let row = getByUsername(username.trimAscii())
        if (row.id <= 0 || row.passwordSalt.size == 0 || row.passwordHash.size == 0) {
            return None
        }
        let computed = AuthUtils.sha256Hex("${row.passwordSalt}:${password}:${pepper}")
        if (computed == row.passwordHash) {
            return Some(row.id)
        }
        return None
    }

    /**
     * 修改用户密码
     */
    public static func changePassword(userId: Int64, newPassword: String, pepper: String): Bool {
        let logger = getLogger("user_dao")
        if (newPassword.size < 6 || newPassword.size > 256) {
            return false
        }

        let salt = AuthUtils.generateTokenHex(bytesLen: 16)
        let passHash = AuthUtils.sha256Hex("${salt}:${newPassword}:${pepper}")

        let connOpt = DatabaseConfig.createConnection()
        match (connOpt) {
            case Some(conn) =>
                try {
                    let stmt = conn.prepareStatement("""
                        UPDATE users SET password_salt = ?, password_hash = ? WHERE id = ?
                    """)
                    try {
                        stmt.set(0, salt)
                        stmt.set(1, passHash)
                        stmt.set(2, userId)
                        let affected = stmt.update()
                        return affected.rowCount > 0
                    } finally {
                        stmt.close()
                    }
                } catch (e: Exception) {
                    logger.error("修改密码失败", ("error", e.message))
                    return false
                } finally {
                    try { conn.close() } catch (_: Exception) {}
                }
            case None => return false
        }
    }

    /**
     * 修改用户名
     * 返回值为用户名是否可用（未被其他用户使用）
     */
    public static func changeUsername(userId: Int64, newUsername: String): Bool {
        let logger = getLogger("user_dao")
        let trimmed = newUsername.trimAscii()
        if (trimmed.size < 3 || trimmed.size > 64) {
            return false
        }

        let connOpt = DatabaseConfig.createConnection()
        match (connOpt) {
            case Some(conn) =>
                try {
                    // 检查新用户名是否已被其他用户使用
                    let checkStmt = conn.prepareStatement("SELECT id FROM users WHERE username = ? AND id <> ?")
                    try {
                        checkStmt.set(0, trimmed)
                        checkStmt.set(1, userId)
                        let rs = checkStmt.query()
                        try {
                            if (rs.next()) {
                                // 用户名已被使用
                                return false
                            }
                        } finally {
                            rs.close()
                        }
                    } finally {
                        checkStmt.close()
                    }

                    // 更新用户名
                    let updateStmt = conn.prepareStatement("UPDATE users SET username = ? WHERE id = ?")
                    try {
                        updateStmt.set(0, trimmed)
                        updateStmt.set(1, userId)
                        let affected = updateStmt.update()
                        return affected.rowCount > 0
                    } finally {
                        updateStmt.close()
                    }
                } catch (e: Exception) {
                    logger.error("修改用户名失败", ("error", e.message))
                    return false
                } finally {
                    try { conn.close() } catch (_: Exception) {}
                }
            case None => return false
        }
    }
}
