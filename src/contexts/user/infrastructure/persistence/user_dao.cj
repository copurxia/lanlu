package lanlu.contexts.user.infrastructure.persistence

import csorm.*
import postgresql_driver.*
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

    private static func mapUserRow(row: Row): UserRow {
        let r = UserRow()
        r.id = row.getOrNullInt64(0) ?? 0
        r.username = row.getOrNullText(1) ?? ""
        r.passwordSalt = row.getOrNullText(2) ?? ""
        r.passwordHash = row.getOrNullText(3) ?? ""
        r.passwordHashVersion = row.getOrNullText(4) ?? ""
        r.isAdmin = row.getOrNullBool(5) ?? false
        r.avatarAssetId = row.getOrNullInt64(6) ?? 0
        r.createdAt = row.getOrNullText(7) ?? ""
        return r
    }

    public static func getByUsername(username: String): UserRow {
        let sql = """
            SELECT id, username, password_salt, password_hash, password_hash_version, is_admin, avatar_asset_id, created_at
            FROM users
            WHERE username = $1
        """
        let params: Array<Value> = [vtext(username)]
        match (DatabaseConfig.getDatabase()) {
            case Some(db) =>
                try {
                    let rows = db.raw<UserRow>(sql, params, { row => mapUserRow(row) })
                    if (rows.size > 0) {
                        return rows[0]
                    }
                    return UserRow()
                } catch (e: Exception) {
                    getLogger("user_dao").error("查询用户失败", ("error", e.message))
                    return UserRow()
                }
            case None => return UserRow()
        }
    }

    public static func getById(id: Int64): UserRow {
        let sql = """
            SELECT id, username, password_salt, password_hash, password_hash_version, is_admin, avatar_asset_id, created_at
            FROM users
            WHERE id = $1
        """
        let params: Array<Value> = [vint(id)]
        match (DatabaseConfig.getDatabase()) {
            case Some(db) =>
                try {
                    let rows = db.raw<UserRow>(sql, params, { row => mapUserRow(row) })
                    if (rows.size > 0) {
                        return rows[0]
                    }
                    return UserRow()
                } catch (e: Exception) {
                    getLogger("user_dao").error("查询用户失败", ("error", e.message))
                    return UserRow()
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

        let passwordRecord = match (PasswordHashService.hashPassword(password, pepper)) {
            case Some(record) => record
            case None =>
                logger.error("创建用户失败：无法生成密码哈希")
                return None
        }

        let params: Array<Value> = [
            vtext(trimmed),
            vtext(passwordRecord.salt),
            vtext(passwordRecord.hash),
            vtext(passwordRecord.version),
            vbool(isAdmin)
        ]
        let sql = """
            INSERT INTO users (username, password_salt, password_hash, password_hash_version, is_admin)
            VALUES ($1, $2, $3, $4, $5)
            RETURNING id
        """
        match (DatabaseConfig.getDatabase()) {
            case Some(db) =>
                try {
                    return db.rawOne<Int64>(sql, params, { r => r.getInt64(0) })
                } catch (e: Exception) {
                    logger.error("创建用户失败", ("error", e.message))
                    return None
                }
            case None => return None
        }
    }

    /**
     * 检查用户表是否为空（用于判断是否允许公开注册第一个用户）
     */
    public static func isEmpty(): Bool {
        let logger = getLogger("user_dao")
        logger.debug("开始查询用户表记录数量")
        let sql = "SELECT COUNT(*) FROM users"
        match (DatabaseConfig.getDatabase()) {
            case Some(db) =>
                try {
                    let rows = db.raw<Int64>(sql, [], { r => r.getOrNullInt64(0) ?? 0 })
                    let count = if (rows.size > 0) { rows[0] } else { 0 }
                    logger.debug("用户表记录数量: ${count}")
                    return count == 0
                } catch (e: Exception) {
                    logger.error("查询用户表记录数量时发生异常", ("error", e.message))
                    return true
                }
            case None => return true
        }
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

        match (DatabaseConfig.getDatabase()) {
            case Some(db) =>
                try {
                    let occupiedSql = "SELECT id FROM users WHERE username = $1 AND id <> $2"
                    let occupiedParams: Array<Value> = [vtext(trimmed), vint(userId)]
                    let occupied = db.rawOne<Int64>(occupiedSql, occupiedParams, { r => r.getInt64(0) })
                    if (occupied.isSome()) {
                        return false
                    }
                    let updateSql = "UPDATE users SET username = $1 WHERE id = $2"
                    let updateParams: Array<Value> = [vtext(trimmed), vint(userId)]
                    let affected = db.execRaw(updateSql, updateParams)
                    return affected > 0
                } catch (e: Exception) {
                    logger.error("修改用户名失败", ("error", e.message))
                    return false
                }
            case None =>
                logger.error("修改用户名失败：无法连接到数据库")
                return false
        }
    }

    /**
     * 检查用户是否为管理员
     */
    public static func isAdmin(userId: Int64): Bool {
        let sql = "SELECT is_admin FROM users WHERE id = $1"
        let params: Array<Value> = [vint(userId)]
        match (DatabaseConfig.getDatabase()) {
            case Some(db) =>
                try {
                    return db.rawOne<Bool>(sql, params, { r => r.getOrNullBool(0) ?? false }) ?? false
                } catch (e: Exception) {
                    getLogger("user_dao").error("检查管理员角色失败", ("error", e.message))
                    return false
                }
            case None => return false
        }
    }

    /**
     * 获取所有用户列表
     */
    public static func listAllUsers(): Array<UserRow> {
        let sql = """
            SELECT id, username, is_admin, created_at
            FROM users
            ORDER BY created_at DESC
        """
        match (DatabaseConfig.getDatabase()) {
            case Some(db) =>
                try {
                    return db.raw<UserRow>(sql, [], { row =>
                        let r = UserRow()
                        r.id = row.getOrNullInt64(0) ?? 0
                        r.username = row.getOrNullText(1) ?? ""
                        r.isAdmin = row.getOrNullBool(2) ?? false
                        r.createdAt = row.getOrNullText(3) ?? ""
                        return r
                    })
                } catch (e: Exception) {
                    getLogger("user_dao").error("获取用户列表失败", ("error", e.message))
                    return Array<UserRow>()
                }
            case None => return Array<UserRow>()
        }
    }

    /**
     * 删除用户
     */
    public static func deleteUser(userId: Int64): Bool {
        return DatabaseConfig.withTransaction({ db =>
            let existsSql = "SELECT id FROM users WHERE id = $1"
            let existsParams: Array<Value> = [vint(userId)]
            let exists = db.rawOne<Int64>(existsSql, existsParams, { r => r.getInt64(0) })
            if (exists.isNone()) {
                return false
            }
            db.execRaw("DELETE FROM user_tokens WHERE user_id = $1", [vint(userId)])
            let affected = db.execRaw("DELETE FROM users WHERE id = $1", [vint(userId)])
            return affected > 0
        })
    }

    /**
     * 更新用户管理员角色
     */
    public static func updateUserRole(userId: Int64, isAdmin: Bool): Bool {
        let sql = "UPDATE users SET is_admin = $1 WHERE id = $2"
        let params: Array<Value> = [vbool(isAdmin), vint(userId)]
        match (DatabaseConfig.getDatabase()) {
            case Some(db) =>
                try {
                    let affected = db.execRaw(sql, params)
                    return affected > 0
                } catch (e: Exception) {
                    getLogger("user_dao").error("更新用户角色失败", ("error", e.message))
                    return false
                }
            case None => return false
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

        let sql = """
            UPDATE users
            SET password_salt = $1, password_hash = $2, password_hash_version = $3
            WHERE id = $4
        """
        let params: Array<Value> = [
            vtext(passwordRecord.salt),
            vtext(passwordRecord.hash),
            vtext(passwordRecord.version),
            vint(userId)
        ]
        match (DatabaseConfig.getDatabase()) {
            case Some(db) =>
                try {
                    let affected = db.execRaw(sql, params)
                    return affected > 0
                } catch (e: Exception) {
                    logger.error(errorMessage, ("error", e.message))
                    return false
                }
            case None => return false
        }
    }

    public static func updateAvatarAssetId(userId: Int64, avatarAssetId: Int64): Bool {
        if (userId <= 0) { return false }
        let sql = "UPDATE users SET avatar_asset_id = $1, updated_at = CURRENT_TIMESTAMP WHERE id = $2"
        let params: Array<Value> = [
            if (avatarAssetId > 0) { vint(avatarAssetId) } else { vnull() },
            vint(userId)
        ]
        match (DatabaseConfig.getDatabase()) {
            case Some(db) =>
                try {
                    db.execRaw(sql, params)
                    return true
                } catch (e: Exception) {
                    getLogger("user_dao").error("updateAvatarAssetId failed", ("error", e.message))
                    return false
                }
            case None => return false
        }
    }
}