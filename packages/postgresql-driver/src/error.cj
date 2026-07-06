package postgresql_driver

import std.collection.*

/**
 * PostgreSQL 错误：携带 SQLSTATE 与诊断字段，供上层做约束冲突判定。
 * 由 PGResult/PGConnection 在执行失败时抛出。
 */
public class PGError <: Exception {
    public let sqlstate: String
    public let severity: String
    public let detail: String
    public let hint: String
    public let schemaName: String
    public let tableName: String
    public let columnName: String
    public let constraintName: String

    public init(message: String, sqlstate!: String = "", severity!: String = "",
        detail!: String = "", hint!: String = "", schemaName!: String = "",
        tableName!: String = "", columnName!: String = "", constraintName!: String = "") {
        super(message)
        this.sqlstate = sqlstate
        this.severity = severity
        this.detail = detail
        this.hint = hint
        this.schemaName = schemaName
        this.tableName = tableName
        this.columnName = columnName
        this.constraintName = constraintName
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
    public func isDeadlockOrSerializationFailure(): Bool { sqlstate == "40P01" || sqlstate == "40001" }

    /** 连接异常(SQLSTATE 类 08)。 */
    public func isConnectionError(): Bool { sqlstate.startsWith("08") }

    public override func toString(): String {
        var s = "PGError: " + message
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
