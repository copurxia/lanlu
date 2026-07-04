package lanlu.contexts.user.infrastructure.persistence

import ace_orm.*
import std.collection.*
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

    private static func mapUserRow(r: Row): UserRow {
        let row = UserRow()
        row.id = r.getInt("id")
        row.username = r.getText("username")
        row.passwordSalt = r.getText("password_salt")
        row.passwordHash = r.getText("password_hash")
        row.passwordHashVersion = r.getText("password_hash_version")
        row.isAdmin = r.getBool("is_admin")
        row.avatarAssetId = r.getInt("avatar_asset_id")
        row.createdAt = r.getText("created_at")
        return row
    }

    public static func getByUsername(username: String): UserRow {
        try {
            let rows = DatabaseConfig.driver().query("""
                SELECT id, username, password_salt, password_hash, password_hash_version, is_admin, avatar_asset_id, created_at
                FROM users
                WHERE username = $1
            """, [DbText(username)])
            if (rows.size > 0) {
                return mapUserRow(rows[0])
            }
        } catch (e: Exception) {
            getLogger("user_dao").error("查询用户失败", ("username", username), ("error", e.message))
        }
        return UserRow()
    }

    public static func getById(id: Int64): UserRow {
        try {
            let rows = DatabaseConfig.driver().query("""
                SELECT id, username, password_salt, password_hash, password_hash_version, is_admin, avatar_asset_id, created_at
                FROM users
                WHERE id = $1
            """, [DbInt(id)])
            if (rows.size > 0) {
                return mapUserRow(rows[0])
            }
        } catch (e: Exception) {
            getLogger("user_dao").error("查询用户失败", ("id", id.toString()), ("error", e.message))
        }
        return UserRow()
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

        try {
            let rows = DatabaseConfig.driver().query("""
                INSERT INTO users (username, password_salt, password_hash, password_hash_version, is_admin)
                VALUES ($1, $2, $3, $4, $5)
                RETURNING id
            """, [
                DbText(trimmed),
                DbText(passwordRecord.salt),
                DbText(passwordRecord.hash),
                DbText(passwordRecord.version),
                DbBool(isAdmin)
            ])
            if (rows.size > 0) {
                return Some(rows[0].getInt("id"))
            }
            return None
        } catch (e: Exception) {
            logger.error("创建用户失败", ("error", e.message))
            return None
        }
    }

    /**
     * 检查用户表是否为空（用于判断是否允许公开注册第一个用户）
     */
    public static func isEmpty(): Bool {
        let logger = getLogger("user_dao")
        logger.debug("开始查询用户表记录数量")
        try {
            let rows = DatabaseConfig.driver().query("SELECT COUNT(*) AS cnt FROM users", [])
            if (rows.size > 0) {
                let count = rows[0].getInt("cnt")
                logger.debug("用户表记录数量: ${count}")
                return count == 0
            }
        } catch (e: Exception) {
            logger.error("查询用户表记录数量时发生异常", ("error", e.message))
            return true
        }
        return false
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
        let logger = getLogger("user_dao")
        let trimmed = newUsername.trimAscii()
        if (trimmed.size < 3 || trimmed.size > 64) {
            return false
        }

        try {
            let occupiedRows = DatabaseConfig.driver().query(
                "SELECT id FROM users WHERE username = $1 AND id <> $2",
                [DbText(trimmed), DbInt(userId)]
            )
            if (occupiedRows.size > 0) {
                return false
            }
            return DatabaseConfig.driver().exec(
                "UPDATE users SET username = $1 WHERE id = $2",
                [DbText(trimmed), DbInt(userId)]
            ) > 0
        } catch (e: Exception) {
            logger.error("修改用户名失败", ("userId", userId.toString()), ("error", e.message))
            return false
        }
    }

    /**
     * 检查用户是否为管理员
     */
    public static func isAdmin(userId: Int64): Bool {
        try {
            let rows = DatabaseConfig.driver().query(
                "SELECT is_admin FROM users WHERE id = $1",
                [DbInt(userId)]
            )
            if (rows.size > 0) {
                return rows[0].getBool("is_admin")
            }
        } catch (e: Exception) {
            getLogger("user_dao").error("检查管理员角色失败", ("userId", userId.toString()), ("error", e.message))
        }
        return false
    }

    /**
     * 获取所有用户列表
     */
    public static func listAllUsers(): Array<UserRow> {
        let out = ArrayList<UserRow>()
        try {
            let rows = DatabaseConfig.driver().query("""
                SELECT id, username, is_admin, created_at
                FROM users
                ORDER BY created_at DESC
            """, [])
            for (r in rows) {
                let row = UserRow()
                row.id = r.getInt("id")
                row.username = r.getText("username")
                row.isAdmin = r.getBool("is_admin")
                row.createdAt = r.getText("created_at")
                out.add(row)
            }
        } catch (e: Exception) {
            getLogger("user_dao").error("获取用户列表失败", ("error", e.message))
        }
        return out.toArray()
    }

    /**
     * 删除用户
     */
    public static func deleteUser(userId: Int64): Bool {
        return DatabaseConfig.withTransaction("user_dao", "删除用户失败", { =>
            let existsRows = DatabaseConfig.driver().query(
                "SELECT id FROM users WHERE id = $1",
                [DbInt(userId)]
            )
            if (existsRows.size == 0) {
                return false
            }
            DatabaseConfig.driver().exec(
                "DELETE FROM user_tokens WHERE user_id = $1",
                [DbInt(userId)]
            )
            return DatabaseConfig.driver().exec(
                "DELETE FROM users WHERE id = $1",
                [DbInt(userId)]
            ) > 0
        })
    }

    /**
     * 更新用户管理员角色
     */
    public static func updateUserRole(userId: Int64, isAdmin: Bool): Bool {
        try {
            return DatabaseConfig.driver().exec(
                "UPDATE users SET is_admin = $1 WHERE id = $2",
                [DbBool(isAdmin), DbInt(userId)]
            ) > 0
        } catch (e: Exception) {
            getLogger("user_dao").error("更新用户角色失败", ("userId", userId.toString()), ("error", e.message))
            return false
        }
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

        try {
            return DatabaseConfig.driver().exec("""
                UPDATE users
                SET password_salt = $1, password_hash = $2, password_hash_version = $3
                WHERE id = $4
            """, [
                DbText(passwordRecord.salt),
                DbText(passwordRecord.hash),
                DbText(passwordRecord.version),
                DbInt(userId)
            ]) > 0
        } catch (e: Exception) {
            logger.error(errorMessage, ("error", e.message))
            return false
        }
    }

    public static func updateAvatarAssetId(userId: Int64, avatarAssetId: Int64): Bool {
        if (userId <= 0) { return false }
        let logger = getLogger("user_dao")
        let params: Array<DbValue> = if (avatarAssetId > 0) {
            [DbInt(avatarAssetId), DbInt(userId)]
        } else {
            [DbNull, DbInt(userId)]
        }
        try {
            DatabaseConfig.driver().exec(
                "UPDATE users SET avatar_asset_id = $1, updated_at = CURRENT_TIMESTAMP WHERE id = $2",
                params
            )
            return true
        } catch (e: Exception) {
            logger.error("updateAvatarAssetId failed", ("userId", userId.toString()), ("error", e.message))
            return false
        }
    }
}