package lrr4cj.dao

import std.database.sql.*
import stdx.log.*
import lrr4cj.config.*
import lrr4cj.utils.*
import std.collection.*

public class UserTokenRow {
    public var id: Int64 = 0
    public var userId: Int64 = 0
    public var name: String = ""
    public var tokenType: String = ""  // "session" 登录设备, "api" 手动创建的API token
    public var tokenPrefix: String = ""
    public var tokenHash: String = ""
    public var createdAt: String = ""
    public var lastUsedAt: String = ""
    public var revokedAt: String = ""

    public init() {}
}

public class CreateTokenResult {
    public var tokenId: Int64
    public var token: String
    public var prefix: String

    public init(tokenId: Int64, token: String, prefix: String) {
        this.tokenId = tokenId
        this.token = token
        this.prefix = prefix
    }
}

public class UserTokenDao {
    public static func createTable(): Bool {
        let logger = getLogger("user_token_dao")
        let handleOpt = DatabaseConfig.getPooledConnection()
        match (handleOpt) {
            case Some(handle) =>
                let conn = handle.connection
                try {
                    // 先检查表是否已存在
                    let checkStmt = conn.prepareStatement("SELECT COUNT(*) FROM information_schema.tables WHERE table_name = 'user_tokens' AND table_schema = 'public'")
                    let rs = checkStmt.query()
                    var tableExists = false
                    if (rs.next()) {
                        let count = rs.getOrNull<Int64>(0) ?? 0
                        tableExists = count > 0
                    }
                    rs.close()
                    checkStmt.close()

                    if (!tableExists) {
                        logger.debug("user_tokens表不存在，创建新表")
                        let sql = """
                            CREATE TABLE user_tokens (
                                id INTEGER PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
                                user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
                                name VARCHAR(128) NOT NULL DEFAULT '',
                                token_type VARCHAR(16) NOT NULL DEFAULT 'session',
                                token_prefix VARCHAR(16) NOT NULL,
                                token_hash VARCHAR(64) NOT NULL UNIQUE,
                                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                                last_used_at TIMESTAMP,
                                revoked_at TIMESTAMP
                            )
                        """
                        let stmt = conn.prepareStatement(sql)
                        stmt.update()
                        stmt.close()

                        // 创建索引
                        let idxStmt = conn.prepareStatement("CREATE INDEX idx_user_tokens_user_id ON user_tokens(user_id)")
                        idxStmt.update()
                        idxStmt.close()
                    } else {
                        logger.debug("user_tokens表已存在，跳过创建")
                    }

                    // 如果表已存在，检查并添加缺失的列
                    if (tableExists) {
                        logger.debug("检查并添加缺失的列")
                        // 检查 token_type 列是否存在
                        let checkColumnStmt = conn.prepareStatement("SELECT COUNT(*) FROM information_schema.columns WHERE table_name = 'user_tokens' AND column_name = 'token_type'")
                        let columnRs = checkColumnStmt.query()
                        var columnExists = false
                        if (columnRs.next()) {
                            let count = columnRs.getOrNull<Int64>(0) ?? 0
                            columnExists = count > 0
                        }
                        columnRs.close()
                        checkColumnStmt.close()

                        if (!columnExists) {
                            logger.debug("添加 token_type 列")
                            let alterStmt = conn.prepareStatement("ALTER TABLE user_tokens ADD COLUMN token_type VARCHAR(16) NOT NULL DEFAULT 'session'")
                            alterStmt.update()
                            alterStmt.close()
                        }
                    }
                    return true
                } catch (e: Exception) {
                    logger.error("创建 user_tokens 表失败", ("error", e.message))
                    logger.error("异常类型: ${e.toString()}")
                    return false
                } finally {
                    try { DatabaseConfig.releasePooledConnection(handle) } catch (_: Exception) {}
                }
            case None =>
                logger.error("无法创建数据库连接")
                return false
        }
    }

    public static func createToken(userId: Int64, name: String, tokenType: String, pepper: String): Option<CreateTokenResult> {
        let token = AuthUtils.generateTokenHex(bytesLen: 32)
        let prefix = if (token.size >= 8) {
            String.fromUtf8(token.toArray().slice(0, 8))
        } else {
            token
        }
        let tokenHash = AuthUtils.sha256Hex("${token}:${pepper}")
        let actualType = if (tokenType == "api" || tokenType == "session") { tokenType } else { "session" }

        let handleOpt = DatabaseConfig.getPooledConnection()
        match (handleOpt) {
            case Some(handle) =>
                let conn = handle.connection
                try {
                    let stmt = conn.prepareStatement("""
                        INSERT INTO user_tokens (user_id, name, token_type, token_prefix, token_hash)
                        VALUES (?, ?, ?, ?, ?)
                        RETURNING id
                    """)
                    try {
                        stmt.set(0, userId)
                        stmt.set(1, name.trimAscii())
                        stmt.set(2, actualType)
                        stmt.set(3, prefix)
                        stmt.set(4, tokenHash)
                        let rs = stmt.query()
                        try {
                            if (rs.next()) {
                                let tokenId = rs.getOrNull<Int64>(0) ?? 0
                                if (tokenId > 0) {
                                    return Some(CreateTokenResult(tokenId, token, prefix))
                                }
                            }
                        } finally {
                            rs.close()
                        }
                        return None
                    } finally {
                        stmt.close()
                    }
                } catch (_: Exception) {
                    return None
                } finally {
                    try { DatabaseConfig.releasePooledConnection(handle) } catch (_: Exception) {}
                }
            case None => return None
        }
    }

    public static func findActiveByHash(tokenHash: String): UserTokenRow {
        let handleOpt = DatabaseConfig.getPooledConnection()
        match (handleOpt) {
            case Some(handle) =>
                let conn = handle.connection
                try {
                    let stmt = conn.prepareStatement("""
                        SELECT id, user_id, name, token_type, token_prefix, token_hash, created_at,
                               COALESCE(last_used_at::text, ''), COALESCE(revoked_at::text, '')
                        FROM user_tokens
                        WHERE token_hash = ? AND revoked_at IS NULL
                    """)
                    try {
                        stmt.set(0, tokenHash)
                        let rs = stmt.query()
                        try {
                            if (rs.next()) {
                                let row = UserTokenRow()
                                row.id = rs.getOrNull<Int64>(0) ?? 0
                                row.userId = rs.getOrNull<Int64>(1) ?? 0
                                row.name = rs.getOrNull<String>(2) ?? ""
                                row.tokenType = rs.getOrNull<String>(3) ?? "session"
                                row.tokenPrefix = rs.getOrNull<String>(4) ?? ""
                                row.tokenHash = rs.getOrNull<String>(5) ?? ""
                                row.createdAt = rs.getOrNull<String>(6) ?? ""
                                row.lastUsedAt = rs.getOrNull<String>(7) ?? ""
                                row.revokedAt = rs.getOrNull<String>(8) ?? ""
                                return row
                            }
                        } finally {
                            rs.close()
                        }
                    } finally {
                        stmt.close()
                    }
                    return UserTokenRow()
                } catch (_: Exception) {
                    return UserTokenRow()
                } finally {
                    try { DatabaseConfig.releasePooledConnection(handle) } catch (_: Exception) {}
                }
            case None => return UserTokenRow()
        }
    }

    public static func touch(tokenId: Int64): Bool {
        let handleOpt = DatabaseConfig.getPooledConnection()
        match (handleOpt) {
            case Some(handle) =>
                let conn = handle.connection
                try {
                    let stmt = conn.prepareStatement("UPDATE user_tokens SET last_used_at = CURRENT_TIMESTAMP WHERE id = ?")
                    stmt.set(0, tokenId)
                    stmt.update()
                    stmt.close()
                    return true
                } catch (_: Exception) {
                    return false
                } finally {
                    try { DatabaseConfig.releasePooledConnection(handle) } catch (_: Exception) {}
                }
            case None => return false
        }
    }

    public static func listByUser(userId: Int64): Array<UserTokenRow> {
        return listByUserAndType(userId, None)
    }

    public static func listByUserAndType(userId: Int64, tokenType: Option<String>): Array<UserTokenRow> {
        var out: ArrayList<UserTokenRow> = ArrayList<UserTokenRow>()
        let handleOpt = DatabaseConfig.getPooledConnection()
        match (handleOpt) {
            case Some(handle) =>
                let conn = handle.connection
                try {
                    let sql = match (tokenType) {
                        case Some(t) => """
                            SELECT id, user_id, name, token_type, token_prefix, token_hash, created_at,
                                   COALESCE(last_used_at::text, ''), COALESCE(revoked_at::text, '')
                            FROM user_tokens
                            WHERE user_id = ? AND token_type = ? AND revoked_at IS NULL
                            ORDER BY id DESC
                        """
                        case None => """
                            SELECT id, user_id, name, token_type, token_prefix, token_hash, created_at,
                                   COALESCE(last_used_at::text, ''), COALESCE(revoked_at::text, '')
                            FROM user_tokens
                            WHERE user_id = ? AND revoked_at IS NULL
                            ORDER BY id DESC
                        """
                    }
                    let stmt = conn.prepareStatement(sql)
                    try {
                        stmt.set(0, userId)
                        match (tokenType) {
                            case Some(t) => stmt.set(1, t)
                            case None => ()
                        }
                        let rs = stmt.query()
                        try {
                            while (rs.next()) {
                                let row = UserTokenRow()
                                row.id = rs.getOrNull<Int64>(0) ?? 0
                                row.userId = rs.getOrNull<Int64>(1) ?? 0
                                row.name = rs.getOrNull<String>(2) ?? ""
                                row.tokenType = rs.getOrNull<String>(3) ?? "session"
                                row.tokenPrefix = rs.getOrNull<String>(4) ?? ""
                                row.tokenHash = rs.getOrNull<String>(5) ?? ""
                                row.createdAt = rs.getOrNull<String>(6) ?? ""
                                row.lastUsedAt = rs.getOrNull<String>(7) ?? ""
                                row.revokedAt = rs.getOrNull<String>(8) ?? ""
                                out.add(row)
                            }
                        } finally {
                            rs.close()
                        }
                    } finally {
                        stmt.close()
                    }
                } catch (_: Exception) {
                    ()
                } finally {
                    try { DatabaseConfig.releasePooledConnection(handle) } catch (_: Exception) {}
                }
            case None => ()
        }
        return out.toArray()
    }

    public static func revoke(userId: Int64, tokenId: Int64): Bool {
        let handleOpt = DatabaseConfig.getPooledConnection()
        match (handleOpt) {
            case Some(handle) =>
                let conn = handle.connection
                try {
                    let stmt = conn.prepareStatement("UPDATE user_tokens SET revoked_at = CURRENT_TIMESTAMP WHERE id = ? AND user_id = ? AND revoked_at IS NULL")
                    stmt.set(0, tokenId)
                    stmt.set(1, userId)
                    let updated = stmt.update()
                    stmt.close()
                    return updated.rowCount > 0
                } catch (_: Exception) {
                    return false
                } finally {
                    try { DatabaseConfig.releasePooledConnection(handle) } catch (_: Exception) {}
                }
            case None => return false
        }
    }
}
