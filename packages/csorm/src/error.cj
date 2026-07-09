package csorm

/**
 * csorm 错误：后端无关异常基类。
 * 由各 driver 的 DriverConn 实现在执行失败时抛出(包装原生错误)。
 * 若 driver 提供 DbError 诊断接口，则可通过 isUniqueViolation 等方法判定约束冲突。
 */
public class CsormError <: Exception {
    public let dbError: ?DbError
    public let sqlstate: String
    public let severity: String
    public let detail: String
    public let hint: String
    public let schemaName: String
    public let tableName: String
    public let columnName: String
    public let constraintName: String

    public init(message: String) {
        super(message)
        this.dbError = None
        this.sqlstate = ""
        this.severity = ""
        this.detail = ""
        this.hint = ""
        this.schemaName = ""
        this.tableName = ""
        this.columnName = ""
        this.constraintName = ""
    }

    public init(message: String, dbError: DbError) {
        super(message)
        this.dbError = Some(dbError)
        this.sqlstate = dbError.sqlstate()
        this.severity = dbError.severity()
        this.detail = dbError.detail()
        this.hint = dbError.hint()
        this.schemaName = dbError.schemaName()
        this.tableName = dbError.tableName()
        this.columnName = dbError.columnName()
        this.constraintName = dbError.constraintName()
    }

    /** 唯一约束冲突。 */
    public func isUniqueViolation(): Bool {
        match (dbError) {
            case Some(e) => e.isUniqueViolation()
            case None => false
        }
    }

    /** 外键约束冲突。 */
    public func isForeignKeyViolation(): Bool {
        match (dbError) {
            case Some(e) => e.isForeignKeyViolation()
            case None => false
        }
    }

    /** NOT NULL 违反。 */
    public func isNotNullViolation(): Bool {
        match (dbError) {
            case Some(e) => e.isNotNullViolation()
            case None => false
        }
    }

    /** CHECK 约束违反。 */
    public func isCheckViolation(): Bool {
        match (dbError) {
            case Some(e) => e.isCheckViolation()
            case None => false
        }
    }

    /** 死锁或序列化失败。 */
    public func isDeadlockOrSerializationFailure(): Bool {
        match (dbError) {
            case Some(e) => e.isDeadlockOrSerializationFailure()
            case None => false
        }
    }

    /** 连接异常。 */
    public func isConnectionError(): Bool {
        match (dbError) {
            case Some(e) => e.isConnectionError()
            case None => false
        }
    }

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