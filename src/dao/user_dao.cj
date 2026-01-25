package lanlu.dao

import std.database.sql.*
import stdx.log.*
import std.collection.*
import lanlu.config.*
import lanlu.utils.*

public class UserRow {
    public var id: Int64 = 0
    public var username: String = ""
    public var passwordSalt: String = ""
    public var passwordHash: String = ""
    public var isAdmin: Bool = false
    public var avatarAssetId: Int64 = 0
    public var createdAt: String = ""

    public init() {}
}

public class UserDao {
    // 注意：表创建已由迁移系统处理，createTable() 方法已移除

    public static func getByUsername(username: String): UserRow {
        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case Some(conn) =>
                try {
                    let stmt = conn.prepareStatement("""
                        SELECT id, username, password_salt, password_hash, is_admin, avatar_asset_id, created_at
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
                                row.isAdmin = rs.getOrNull<Bool>(4) ?? false
                                row.avatarAssetId = rs.getOrNull<Int64>(5) ?? 0
                                row.createdAt = rs.getOrNull<String>(6) ?? ""
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
        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case Some(conn) =>
                try {
                    let stmt = conn.prepareStatement("""
                        SELECT id, username, password_salt, password_hash, is_admin, avatar_asset_id, created_at
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
                                row.isAdmin = rs.getOrNull<Bool>(4) ?? false
                                row.avatarAssetId = rs.getOrNull<Int64>(5) ?? 0
                                row.createdAt = rs.getOrNull<String>(6) ?? ""
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

    public static func createUser(username: String, password: String, pepper: String, isAdmin: Bool): Option<Int64> {
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

        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case Some(conn) =>
                try {
                    let stmt = conn.prepareStatement("""
                        INSERT INTO users (username, password_salt, password_hash, is_admin)
                        VALUES (?, ?, ?, ?)
                        RETURNING id
                    """)
                    try {
                        stmt.set(0, trimmed)
                        stmt.set(1, salt)
                        stmt.set(2, passHash)
                        stmt.set(3, isAdmin)
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
        let logger = getLogger("user_dao")
        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case Some(conn) =>
                try {
                    logger.debug("开始查询用户表记录数量")
                    let stmt = conn.prepareStatement("SELECT COUNT(*) FROM users")
                    try {
                        let rs = stmt.query()
                        try {
                            if (rs.next()) {
                                let count = rs.getOrNull<Int64>(0) ?? 0
                                logger.debug("用户表记录数量: ${count}")
                                return count == 0
                            } else {
                                logger.warn("查询用户表记录数量失败，无法获取结果")
                                return true
                            }
                        } finally {
                            rs.close()
                        }
                    } finally {
                        stmt.close()
                    }
                } catch (e: Exception) {
                    logger.error("查询用户表记录数量时发生异常", ("error", e.message))
                    return true
                } finally {
                    try { conn.close() } catch (_: Exception) {}
                }
            case None =>
                logger.error("无法创建数据库连接进行空表检查")
                return true
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

        let connOpt = DatabaseConfig.getPooledConnection()
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

        let connOpt = DatabaseConfig.getPooledConnection()
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

    /**
     * 检查用户是否为管理员
     */
    public static func isAdmin(userId: Int64): Bool {
        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case Some(conn) =>
                try {
                    let stmt = conn.prepareStatement("SELECT is_admin FROM users WHERE id = ?")
                    try {
                        stmt.set(0, userId)
                        let rs = stmt.query()
                        try {
                            if (rs.next()) {
                                return rs.getOrNull<Bool>(0) ?? false
                            }
                        } finally {
                            rs.close()
                        }
                    } finally {
                        stmt.close()
                    }
                    return false
                } catch (_: Exception) {
                    return false
                } finally {
                    try { conn.close() } catch (_: Exception) {}
                }
            case None => return false
        }
    }

    /**
     * 获取所有用户列表
     */
    public static func listAllUsers(): Array<UserRow> {
        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case Some(conn) =>
                try {
                    let stmt = conn.prepareStatement("""
                        SELECT id, username, is_admin, created_at
                        FROM users
                        ORDER BY created_at DESC
                    """)
                    try {
                        let rs = stmt.query()
                        try {
                            var users = ArrayList<UserRow>()
                            while (rs.next()) {
                                let row = UserRow()
                                row.id = rs.getOrNull<Int64>(0) ?? 0
                                row.username = rs.getOrNull<String>(1) ?? ""
                                row.isAdmin = rs.getOrNull<Bool>(2) ?? false
                                row.createdAt = rs.getOrNull<String>(3) ?? ""
                                users.add(row)
                            }
                            return users.toArray()
                        } finally {
                            rs.close()
                        }
                    } finally {
                        stmt.close()
                    }
                } catch (_: Exception) {
                    return []
                } finally {
                    try { conn.close() } catch (_: Exception) {}
                }
            case None => return []
        }
    }

    /**
     * 删除用户
     */
    public static func deleteUser(userId: Int64): Bool {
        let logger = getLogger("user_dao")
        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case Some(conn) =>
                try {
                    // 先检查用户是否存在
                    let checkStmt = conn.prepareStatement("SELECT id FROM users WHERE id = ?")
                    try {
                        checkStmt.set(0, userId)
                        let rs = checkStmt.query()
                        try {
                            if (!rs.next()) {
                                return false
                            }
                        } finally {
                            rs.close()
                        }
                    } finally {
                        checkStmt.close()
                    }

                    // 删除相关token
                    let deleteTokensStmt = conn.prepareStatement("DELETE FROM user_tokens WHERE user_id = ?")
                    try {
                        deleteTokensStmt.set(0, userId)
                        deleteTokensStmt.update()
                    } finally {
                        deleteTokensStmt.close()
                    }

                    // 删除用户
                    let deleteUserStmt = conn.prepareStatement("DELETE FROM users WHERE id = ?")
                    try {
                        deleteUserStmt.set(0, userId)
                        let affected = deleteUserStmt.update()
                        return affected.rowCount > 0
                    } finally {
                        deleteUserStmt.close()
                    }
                } catch (e: Exception) {
                    logger.error("删除用户失败", ("error", e.message))
                    return false
                } finally {
                    try { conn.close() } catch (_: Exception) {}
                }
            case None => return false
        }
    }

    /**
     * 更新用户管理员角色
     */
    public static func updateUserRole(userId: Int64, isAdmin: Bool): Bool {
        let logger = getLogger("user_dao")
        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case Some(conn) =>
                try {
                    let stmt = conn.prepareStatement("UPDATE users SET is_admin = ? WHERE id = ?")
                    try {
                        stmt.set(0, isAdmin)
                        stmt.set(1, userId)
                        let affected = stmt.update()
                        return affected.rowCount > 0
                    } finally {
                        stmt.close()
                    }
                } catch (e: Exception) {
                    logger.error("更新用户角色失败", ("error", e.message))
                    return false
                } finally {
                    try { conn.close() } catch (_: Exception) {}
                }
            case None => return false
        }
    }

    /**
     * 重置用户密码
     */
    public static func resetUserPassword(userId: Int64, newPassword: String, pepper: String): Bool {
        let logger = getLogger("user_dao")
        if (newPassword.size < 6 || newPassword.size > 256) {
            return false
        }

        let salt = AuthUtils.generateTokenHex(bytesLen: 16)
        let passHash = AuthUtils.sha256Hex("${salt}:${newPassword}:${pepper}")

        let connOpt = DatabaseConfig.getPooledConnection()
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
                    logger.error("重置用户密码失败", ("error", e.message))
                    return false
                } finally {
                    try { conn.close() } catch (_: Exception) {}
                }
            case None => return false
        }
    }

    public static func updateAvatarAssetId(userId: Int64, avatarAssetId: Int64): Bool {
        if (userId <= 0) { return false }
        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case Some(conn) =>
                try {
                    let stmt = conn.prepareStatement("UPDATE users SET avatar_asset_id = ?, updated_at = CURRENT_TIMESTAMP WHERE id = ?")
                    try {
                        if (avatarAssetId > 0) {
                            stmt.set(0, avatarAssetId)
                        } else {
                            stmt.setNull(0)
                        }
                        stmt.set(1, userId)
                        stmt.update()
                        return true
                    } finally {
                        stmt.close()
                    }
                } catch (e: Exception) {
                    getLogger("user_dao").error("updateAvatarAssetId failed", ("error", e.message))
                    return false
                } finally {
                    try { conn.close() } catch (_: Exception) {}
                }
            case None => return false
        }
    }
}
