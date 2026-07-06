package csorm

import postgresql_driver.*

/**
 * csorm 错误：包装底层 PGError，保留 SQLSTATE 与诊断字段，供上层做约束冲突判定。
 * 由 Database 在执行失败时抛出（捕获 PGError 后包成 CsormError）。
 */
public class CsormError <: Exception {
    public let pgError: PGError
    public let sqlstate: String
    public let severity: String
    public let detail: String
    public let hint: String
    public let schemaName: String
    public let tableName: String
    public let columnName: String
    public let constraintName: String

    public init(message: String, pgError!: PGError = PGError("")) {
        super(message)
        this.pgError = pgError
        this.sqlstate = pgError.sqlstate
        this.severity = pgError.severity
        this.detail = pgError.detail
        this.hint = pgError.hint
        this.schemaName = pgError.schemaName
        this.tableName = pgError.tableName
        this.columnName = pgError.columnName
        this.constraintName = pgError.constraintName
    }

    /** 唯一约束冲突(23505)。 */
    public func isUniqueViolation(): Bool { sqlstate == "23505" }

    /** 外键约束冲突(23503)。 */
    public func isForeignKeyViolation(): Bool { sqlstate == "23503" }

    /** NOT NULL 违反(23502)。 */
    public func isNotNullViolation(): Bool { sqlstate == "23502" }

    /** CHECK 约束违反(23514)。 */
    public func isCheckViolation(): Bool { sqlstate == "23514" }

    /** 死锁(40P01)或序列化失败(40001)。 */
    public func isDeadlockOrSerializationFailure(): Bool {
        sqlstate == "40P01" || sqlstate == "40001"
    }

    /** 连接异常(SQLSTATE 类 08)。 */
    public func isConnectionError(): Bool { sqlstate.startsWith("08") }

    public override func toString(): String {
        var s = "CsormError: " + message
        if (!sqlstate.isEmpty()) {
            s += " [SQLSTATE=" + sqlstate + "]"
        }
        if (!detail.isEmpty()) {
            s += " DETAIL: " + detail
        }
        if (!hint.isEmpty()) {
            s += " HINT: " + hint
        }
        s
    }
}

/** 把 PGError 包成 CsormError（保留原始诊断）。 */
internal func wrapPgError(e: PGError, ctx: String): CsormError {
    let msg = if (ctx.isEmpty()) { e.message } else { ctx + ": " + e.message }
    CsormError(msg, pgError: e)
}