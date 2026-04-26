package lanlu.contexts.user.infrastructure.persistence

import std.database.sql.*
import stdx.log.*
import lanlu.shared.config.*
import lanlu.shared.utils.*

public class UserRow {
    public var id: Int64 = 0
    public var username: String = ""
    public var passwordSalt: String = ""
    public var passwordHash: String = ""
    public var passwordHashVersion: String = ""
    public var isAdmin: Bool = false
    public var avatarAssetId: Int64 = 0
    public var createdAt: String = ""

    public init() {}
}

public class UserDao {
    // 注意：表创建已由迁移系统处理，createTable() 方法已移除

    private static func mapUserRow(rs: QueryResult): UserRow {
        let row = UserRow()
        row.id = DatabaseConfig.getInt64OrZero(rs, 0)
        row.username = DatabaseConfig.getStringOrEmpty(rs, 1)
        row.passwordSalt = DatabaseConfig.getStringOrEmpty(rs, 2)
        row.passwordHash = DatabaseConfig.getStringOrEmpty(rs, 3)
        row.passwordHashVersion = DatabaseConfig.getStringOrEmpty(rs, 4)
        row.isAdmin = DatabaseConfig.getBoolOrFalse(rs, 5)
        row.avatarAssetId = DatabaseConfig.getInt64OrZero(rs, 6)
        row.createdAt = DatabaseConfig.getStringOrEmpty(rs, 7)
        return row
    }

    public static func getByUsername(username: String): UserRow {
        return DatabaseConfig.queryOne<UserRow>(
            "user_dao",
            "查询用户失败",
            """
                SELECT id, username, password_salt, password_hash, password_hash_version, is_admin, avatar_asset_id, created_at
                FROM users
                WHERE username = ?
            """,
            UserRow(),
            { stmt => stmt.set(0, username) },
            { rs => mapUserRow(rs) }
        )
    }

    public static func getById(id: Int64): UserRow {
        return DatabaseConfig.queryOne<UserRow>(
            "user_dao",
            "查询用户失败",
            """
                SELECT id, username, password_salt, password_hash, password_hash_version, is_admin, avatar_asset_id, created_at
                FROM users
                WHERE id = ?
            """,
            UserRow(),
            { stmt => stmt.set(0, id) },
            { rs => mapUserRow(rs) }
        )
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

        let passwordRecord = match (PasswordHashService.hashPassword(password, pepper)) {
            case Some(record) => record
            case None =>
                logger.error("创建用户失败：无法生成密码哈希")
                return None
        }

        return DatabaseConfig.executeReturningId(
            "user_dao",
            "创建用户失败",
            """
                INSERT INTO users (username, password_salt, password_hash, password_hash_version, is_admin)
                VALUES (?, ?, ?, ?, ?)
                RETURNING id
            """,
            { stmt =>
                stmt.set(0, trimmed)
                stmt.set(1, passwordRecord.salt)
                stmt.set(2, passwordRecord.hash)
                stmt.set(3, passwordRecord.version)
                stmt.set(4, isAdmin)
            }
        )
    }

    /**
     * 检查用户表是否为空（用于判断是否允许公开注册第一个用户）
     */
    public static func isEmpty(): Bool {
        let logger = getLogger("user_dao")
        logger.debug("开始查询用户表记录数量")
        return DatabaseConfig.queryOne<Bool>(
            "user_dao",
            "查询用户表记录数量时发生异常",
            "SELECT COUNT(*) FROM users",
            true,
            { _ => () },
            { rs =>
                let count = DatabaseConfig.getInt64OrZero(rs, 0)
                logger.debug("用户表记录数量: ${count}")
                return count == 0
            }
        )
    }

    public static func verifyPassword(username: String, password: String, pepper: String): Option<Int64> {
        let row = getByUsername(username.trimAscii())
        if (row.id <= 0 || row.passwordHash.size == 0) {
            return None
        }
        if (verifyPasswordRow(row, password, pepper)) {
            return Some(row.id)
        }
        return None
    }

    public static func verifyPasswordByUserId(userId: Int64, password: String, pepper: String): Bool {
        let row = getById(userId)
        if (row.id <= 0 || row.passwordHash.size == 0) {
            return false
        }
        return verifyPasswordRow(row, password, pepper)
    }

    /**
     * 修改用户密码
     */
    public static func changePassword(userId: Int64, newPassword: String, pepper: String): Bool {
        if (newPassword.size < 6 || newPassword.size > 256) {
            return false
        }
        return updatePasswordHash(userId, newPassword, pepper, "修改密码失败")
    }

    /**
     * 修改用户名
     * 返回值为用户名是否可用（未被其他用户使用）
     */
    public static func changeUsername(userId: Int64, newUsername: String): Bool {
        let trimmed = newUsername.trimAscii()
        if (trimmed.size < 3 || trimmed.size > 64) {
            return false
        }

        return DatabaseConfig.withPooledConnection<Bool>("user_dao", "修改用户名失败", false, { conn =>
            let occupied = DatabaseConfig.withStatement<Bool>(conn, "SELECT id FROM users WHERE username = ? AND id <> ?", { stmt =>
                stmt.set(0, trimmed)
                stmt.set(1, userId)
                DatabaseConfig.withQueryResult<Bool>(stmt, { rs => rs.next() })
            })
            if (occupied) {
                return false
            }
            return DatabaseConfig.withStatement<Bool>(conn, "UPDATE users SET username = ? WHERE id = ?", { stmt =>
                stmt.set(0, trimmed)
                stmt.set(1, userId)
                return stmt.update().rowCount > 0
            })
        })
    }

    /**
     * 检查用户是否为管理员
     */
    public static func isAdmin(userId: Int64): Bool {
        return DatabaseConfig.queryOne<Bool>(
            "user_dao",
            "检查管理员角色失败",
            "SELECT is_admin FROM users WHERE id = ?",
            false,
            { stmt => stmt.set(0, userId) },
            { rs => DatabaseConfig.getBoolOrFalse(rs, 0) }
        )
    }

    /**
     * 获取所有用户列表
     */
    public static func listAllUsers(): Array<UserRow> {
        return DatabaseConfig.queryList<UserRow>(
            "user_dao",
            "获取用户列表失败",
            """
                SELECT id, username, is_admin, created_at
                FROM users
                ORDER BY created_at DESC
            """,
            { _ => () },
            { rs =>
                let row = UserRow()
                row.id = DatabaseConfig.getInt64OrZero(rs, 0)
                row.username = DatabaseConfig.getStringOrEmpty(rs, 1)
                row.isAdmin = DatabaseConfig.getBoolOrFalse(rs, 2)
                row.createdAt = DatabaseConfig.getStringOrEmpty(rs, 3)
                return row
            }
        )
    }

    /**
     * 删除用户
     */
    public static func deleteUser(userId: Int64): Bool {
        return DatabaseConfig.withTransaction("user_dao", "删除用户失败", { conn =>
            let exists = DatabaseConfig.withStatement<Bool>(conn, "SELECT id FROM users WHERE id = ?", { stmt =>
                stmt.set(0, userId)
                DatabaseConfig.withQueryResult<Bool>(stmt, { rs => rs.next() })
            })
            if (!exists) {
                return false
            }
            DatabaseConfig.executeOnConnection(conn, "DELETE FROM user_tokens WHERE user_id = ?", { stmt => stmt.set(0, userId) })
            return DatabaseConfig.withStatement<Bool>(conn, "DELETE FROM users WHERE id = ?", { stmt =>
                stmt.set(0, userId)
                return stmt.update().rowCount > 0
            })
        })
    }

    /**
     * 更新用户管理员角色
     */
    public static func updateUserRole(userId: Int64, isAdmin: Bool): Bool {
        return DatabaseConfig.withPooledConnection<Bool>("user_dao", "更新用户角色失败", false, { conn =>
            DatabaseConfig.withStatement<Bool>(conn, "UPDATE users SET is_admin = ? WHERE id = ?", { stmt =>
                stmt.set(0, isAdmin)
                stmt.set(1, userId)
                return stmt.update().rowCount > 0
            })
        })
    }

    /**
     * 重置用户密码
     */
    public static func resetUserPassword(userId: Int64, newPassword: String, pepper: String): Bool {
        if (newPassword.size < 6 || newPassword.size > 256) {
            return false
        }
        return updatePasswordHash(userId, newPassword, pepper, "重置用户密码失败")
    }

    private static func verifyPasswordRow(row: UserRow, password: String, pepper: String): Bool {
        let result = PasswordHashService.verifyPassword(
            row.passwordHashVersion,
            row.passwordSalt,
            row.passwordHash,
            password,
            pepper
        )
        if (!result.valid) {
            return false
        }
        if (result.needsUpgrade) {
            let upgraded = updatePasswordHash(row.id, password, pepper, "旧密码哈希透明迁移失败")
            if (!upgraded) {
                getLogger("user_dao").warn("旧密码哈希验证成功，但迁移到 Argon2id 失败", ("user_id", row.id.toString()))
            }
        }
        return true
    }

    private static func updatePasswordHash(userId: Int64, password: String, pepper: String, errorMessage: String): Bool {
        let logger = getLogger("user_dao")
        let passwordRecord = match (PasswordHashService.hashPassword(password, pepper)) {
            case Some(record) => record
            case None =>
                logger.error(errorMessage, ("error", "failed to generate password hash"))
                return false
        }

        return DatabaseConfig.withPooledConnection<Bool>("user_dao", errorMessage, false, { conn =>
            DatabaseConfig.withStatement<Bool>(conn, """
                UPDATE users
                SET password_salt = ?, password_hash = ?, password_hash_version = ?
                WHERE id = ?
            """, { stmt =>
                stmt.set(0, passwordRecord.salt)
                stmt.set(1, passwordRecord.hash)
                stmt.set(2, passwordRecord.version)
                stmt.set(3, userId)
                return stmt.update().rowCount > 0
            })
        })
    }

    public static func updateAvatarAssetId(userId: Int64, avatarAssetId: Int64): Bool {
        if (userId <= 0) { return false }
        return DatabaseConfig.execute(
            "user_dao",
            "updateAvatarAssetId failed",
            "UPDATE users SET avatar_asset_id = ?, updated_at = CURRENT_TIMESTAMP WHERE id = ?",
            { stmt =>
                if (avatarAssetId > 0) {
                    stmt.set(0, avatarAssetId)
                } else {
                    stmt.setNull(0)
                }
                stmt.set(1, userId)
            }
        )
    }
}
