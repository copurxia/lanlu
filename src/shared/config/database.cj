package lanlu.shared.config

import std.database.sql.*
import std.collection.*
import std.convert.*
import std.sync.*
import stdx.log.*
import cjdotenv.load
import std.env.getVariable
import lanlu.shared.utils.*
// 必须保留：通过副作用注册 postgres/opengauss 驱动，不能移除
import opengauss.driver.*
import std.fs.exists

/**
 * 数据库配置类
 */
public class DatabaseConfig {
    public static var dbString: String
    public static var dbType: String
    public static var queryTimeoutMs: Int64

    /**
     * 静态初始化器，从环境变量读取配置
     */
    static init() {
        if (exists(".env")) {
            load()
        }
        // 从环境变量中读取数据库配置
        dbString = getVariable("DB_STRING") ?? "postgres://lgr:lgr@127.0.0.1:5432/lgr?sslmode=disable"
        // 从连接字符串中解析数据库类型
        dbType = parseDbType(dbString)
        let queryTimeoutStr = getVariable("DB_QUERY_TIMEOUT_MS") ?? ""
        queryTimeoutMs = if (queryTimeoutStr.size > 0) {
            try { Int64.parse(queryTimeoutStr) } catch (_: Exception) { 0i64 }
        } else {
            0i64
        }
    }

    /**
     * 从连接字符串中解析数据库类型
     */
    private static func parseDbType(connStr: String): String {
        if (connStr.isEmpty()) {
            return "postgres"
        }
        // 提取协议部分，如 "postgres://" -> "postgres"
        let parts = connStr.split("://")
        if (parts.size >= 2) {
            return parts[0]
        }
        return "postgres"
    }

    /**
     * 获取数据库连接字符串
     */
    public static func getConnectionString(): String {
        let logger = getLogger("database")
        logger.debug("Using database connection string from DB_STRING")
        logger.debug("DB type: ${dbType}")
        return dbString
    }

    /**
     * 获取数据库驱动
     */
    public static func getDriver(): Option<Driver> {
        return DriverManager.getDriver(dbType)
    }

    /**
     * 创建数据库连接
     */
    public static func createConnection(): Option<Connection> {
        let drvopt = getDriver()
        match (drvopt) {
            case Some(drv) =>
                let connStr = getConnectionString()
                let ds = drv.open(connStr)
                try {
                    let conn = ds.connect()
                    return Some(conn)
                } catch (e: Exception) {
                    let logger = getLogger("database")
                    logger.error("数据库连接失败: ${e.toString()}")
                    logger.error("连接异常详细信息: ${e.message}")
                    return None
                }
            case None =>
                getLogger("database").error("无法获取 ${dbType} 驱动")
                return None
        }
    }

    /**
     * 从连接池获取连接（推荐使用）
     * 复用连接以提升性能
     * 使用完毕后需调用 conn.close() 归还连接到池中
     */
    public static func getPooledConnection(): Option<Connection> {
        return ConnectionPool.getInstance().getConnection()
    }

    /**
     * 使用连接池连接执行数据库操作，并统一处理连接释放、连接失败和异常日志。
     * 适合 DAO 层替代重复的 getPooledConnection/match/try/finally close 模式。
     */
    public static func withPooledConnection<T>(
        loggerName: String,
        errorMessage: String,
        defaultValue: T,
        operation: (Connection) -> T
    ): T {
        let logger = getLogger(loggerName)
        let connOpt = getPooledConnection()
        match (connOpt) {
            case Some(rawConn) =>
                var result = Option<T>.None
                try (conn = rawConn) {
                    result = Some(operation(conn))
                } catch (e: Exception) {
                    logger.error(errorMessage, ("error", e.message))
                    return defaultValue
                }
                match (result) {
                    case Some(value) => return value
                    case None => return defaultValue
                }
            case None =>
                logger.error("cannot connect to database")
                return defaultValue
        }
    }

    /**
     * 使用 PreparedStatement 执行操作，并统一关闭 Statement。
     */
    public static func withStatement<T>(conn: Connection, sql: String, operation: (Statement) -> T): T {
        return withStatementTimeout<T>(conn, sql, queryTimeoutMs, operation)
    }

    /**
     * 使用 PreparedStatement 执行操作，并在 timeoutMs 到期后尝试发送 PostgreSQL CancelRequest。
     * timeoutMs <= 0 时不启用取消线程。
     */
    public static func withStatementTimeout<T>(
        conn: Connection,
        sql: String,
        timeoutMs: Int64,
        operation: (Statement) -> T
    ): T {
        let rawStmt = conn.prepareStatement(sql)
        var result = Option<T>.None
        let completed = AtomicBool(false)
        if (timeoutMs > 0) {
            let _ = spawn {
                sleep(Duration.millisecond * timeoutMs)
                if (!completed.load()) {
                    try { let _ = cancelStatement(rawStmt) } catch (_: Exception) {}
                }
            }
        }
        try {
            try (stmt = rawStmt) {
                result = Some(operation(stmt))
            }
            completed.store(true)
        } catch (e: Exception) {
            completed.store(true)
            throw e
        }
        match (result) {
            case Some(value) => return value
            case None => throw Exception("statement operation did not produce a result")
        }
    }

    /**
     * 执行 Statement.query() 并统一关闭 QueryResult。
     */
    public static func withQueryResult<T>(stmt: Statement, operation: (QueryResult) -> T): T {
        let rawRs = stmt.query()
        var result = Option<T>.None
        try (rs = rawRs) {
            result = Some(operation(rs))
        }
        match (result) {
            case Some(value) => return value
            case None => throw Exception("query result operation did not produce a result")
        }
    }

    /**
     * 查询单行。无结果或异常时返回 defaultValue。
     */
    public static func queryOne<T>(
        loggerName: String,
        errorMessage: String,
        sql: String,
        defaultValue: T,
        bind: (Statement) -> Unit,
        map: (QueryResult) -> T
    ): T {
        return withPooledConnection<T>(loggerName, errorMessage, defaultValue, { conn =>
            withStatement<T>(conn, sql, { stmt =>
                bind(stmt)
                withQueryResult<T>(stmt, { rs =>
                    if (rs.next()) {
                        return map(rs)
                    }
                    return defaultValue
                })
            })
        })
    }

    /**
     * 查询多行。异常时返回空数组。
     */
    public static func queryList<T>(
        loggerName: String,
        errorMessage: String,
        sql: String,
        bind: (Statement) -> Unit,
        map: (QueryResult) -> T
    ): Array<T> {
        return withPooledConnection<Array<T>>(loggerName, errorMessage, Array<T>(), { conn =>
            withStatement<Array<T>>(conn, sql, { stmt =>
                bind(stmt)
                withQueryResult<Array<T>>(stmt, { rs =>
                    var rows = ArrayList<T>()
                    while (rs.next()) {
                        rows.add(map(rs))
                    }
                    return rows.toArray()
                })
            })
        })
    }

    /**
     * 执行更新语句。用于 INSERT/UPDATE/DELETE/DDL。
     */
    public static func execute(
        loggerName: String,
        errorMessage: String,
        sql: String,
        bind: (Statement) -> Unit
    ): Bool {
        return withPooledConnection<Bool>(loggerName, errorMessage, false, { conn =>
            withStatement<Bool>(conn, sql, { stmt =>
                bind(stmt)
                stmt.update()
                return true
            })
        })
    }

    /**
     * 执行 RETURNING id 模式的写入语句。
     */
    public static func executeReturningId(
        loggerName: String,
        errorMessage: String,
        sql: String,
        bind: (Statement) -> Unit
    ): Option<Int64> {
        return withPooledConnection<Option<Int64>>(loggerName, errorMessage, None, { conn =>
            withStatement<Option<Int64>>(conn, sql, { stmt =>
                bind(stmt)
                withQueryResult<Option<Int64>>(stmt, { rs =>
                    if (rs.next()) {
                        let id = rs.getOrNull<Int64>(0) ?? 0
                        if (id > 0) {
                            return Some(id)
                        }
                    }
                    return None
                })
            })
        })
    }

    /**
     * 在一个连接内执行事务。operation 返回 false 或抛异常时回滚。
     */
    public static func withTransaction(
        loggerName: String,
        errorMessage: String,
        operation: (Connection) -> Bool
    ): Bool {
        return withPooledConnection<Bool>(loggerName, errorMessage, false, { conn =>
            var committed = false
            try {
                executeOnConnection(conn, "BEGIN", { _ => () })
                let ok = operation(conn)
                if (ok) {
                    executeOnConnection(conn, "COMMIT", { _ => () })
                    committed = true
                    return true
                }
                executeOnConnection(conn, "ROLLBACK", { _ => () })
                return false
            } catch (e: Exception) {
                if (!committed) {
                    try { executeOnConnection(conn, "ROLLBACK", { _ => () }) } catch (_: Exception) {}
                }
                throw e
            }
        })
    }

    /**
     * 在已有连接上执行更新语句，适合事务内部复用。
     */
    public static func executeOnConnection(
        conn: Connection,
        sql: String,
        bind: (Statement) -> Unit
    ): Bool {
        return withStatement<Bool>(conn, sql, { stmt =>
            bind(stmt)
            stmt.update()
            return true
        })
    }

    /**
     * 在同一连接和同一 PreparedStatement 上重复执行一批绑定。
     * 这是项目侧 batch 封装，先降低连接获取和 Statement 准备开销；驱动层 pipeline 可在后续替换内部实现。
     */
    public static func executeBatch(
        loggerName: String,
        errorMessage: String,
        sql: String,
        binds: Array<(Statement) -> Unit>
    ): Int64 {
        return withPooledConnection<Int64>(loggerName, errorMessage, 0, { conn =>
            withStatement<Int64>(conn, sql, { stmt =>
                var affected: Int64 = 0
                for (bind in binds) {
                    bind(stmt)
                    affected += stmt.update().rowCount
                }
                return affected
            })
        })
    }

    /**
     * 使用 PostgreSQL cursor 分批读取大结果集。selectSql 必须是 SELECT/VALUES 等可声明游标的查询。
     */
    public static func forEachCursor(
        loggerName: String,
        errorMessage: String,
        selectSql: String,
        fetchSize: Int64,
        bind: (Statement) -> Unit,
        consume: (QueryResult) -> Bool
    ): Bool {
        if (fetchSize <= 0) {
            return false
        }
        return withTransaction(loggerName, errorMessage, { conn =>
            let cursorName = "lanlu_cursor"
            executeOnConnection(conn, "DECLARE ${cursorName} NO SCROLL CURSOR FOR ${selectSql}", bind)
            var keepGoing = true
            try {
                while (keepGoing) {
                    keepGoing = withStatement<Bool>(conn, "FETCH ${fetchSize} FROM ${cursorName}", { stmt =>
                        withQueryResult<Bool>(stmt, { rs =>
                            var hasRow = false
                            while (rs.next()) {
                                hasRow = true
                                if (!consume(rs)) {
                                    return false
                                }
                            }
                            return hasRow
                        })
                    })
                }
                return true
            } finally {
                try { executeOnConnection(conn, "CLOSE ${cursorName}", { _ => () }) } catch (_: Exception) {}
            }
        })
    }

    public static func setOptionString(stmt: Statement, index: Int, value: Option<String>): Unit {
        match (value) {
            case Some(v) => stmt.set(index, v)
            case None => stmt.setNull(index)
        }
    }

    public static func setOptionInt64(stmt: Statement, index: Int, value: Option<Int64>): Unit {
        match (value) {
            case Some(v) => stmt.set(index, v)
            case None => stmt.setNull(index)
        }
    }

    public static func setJsonb(stmt: Statement, index: Int, json: String): Unit {
        let normalized = json.trimAscii()
        stmt.set(index, if (normalized.size > 0) { normalized } else { "{}" })
    }

    public static func setJsonbArray(stmt: Statement, index: Int, json: String): Unit {
        let normalized = json.trimAscii()
        stmt.set(index, if (normalized.size > 0) { normalized } else { "[]" })
    }

    public static func setTextArray(stmt: Statement, index: Int, values: Array<String>): Unit {
        stmt.set(index, PgTextArray(values))
    }

    public static func setInt64Array(stmt: Statement, index: Int, values: Array<Int64>): Unit {
        stmt.set(index, PgInt64Array(values))
    }

    public static func cancelStatement(stmt: Statement): Bool {
        match (stmt) {
            case ogStmt: Stmt =>
                ogStmt.cancel()
                return true
            case _ => return false
        }
    }

    public static func cancelConnection(conn: Connection): Bool {
        match (conn) {
            case ogConn: PGConnection =>
                ogConn.cancel()
                return true
            case _ => return false
        }
    }

    public static func getStringOrEmpty(rs: QueryResult, index: Int): String {
        return rs.getOrNull<String>(index) ?? ""
    }

    public static func getInt64OrZero(rs: QueryResult, index: Int): Int64 {
        return rs.getOrNull<Int64>(index) ?? 0
    }

    public static func getInt32OrZero(rs: QueryResult, index: Int): Int32 {
        return rs.getOrNull<Int32>(index) ?? 0
    }

    public static func getBoolOrFalse(rs: QueryResult, index: Int): Bool {
        return rs.getOrNull<Bool>(index) ?? false
    }

    public static func sqlStateOf(e: Exception): String {
        let marker = "SQLSTATE "
        let message = e.message
        match (message.indexOf(marker)) {
            case Some(start) =>
                let codeStart = start + marker.size
                if (message.size >= codeStart + 5) {
                    return message[codeStart..codeStart + 5]
                }
                return ""
            case None => return ""
        }
    }

    public static func isUniqueViolation(e: Exception): Bool {
        return sqlStateOf(e) == "23505"
    }

    public static func isForeignKeyViolation(e: Exception): Bool {
        return sqlStateOf(e) == "23503"
    }

    public static func isDeadlockOrSerializationFailure(e: Exception): Bool {
        let state = sqlStateOf(e)
        return state == "40P01" || state == "40001"
    }

    public static func isConnectionFailure(e: Exception): Bool {
        return sqlStateOf(e).startsWith("08")
    }

    /**
     * 初始化连接池
     */
    public static func initializePool(): Bool {
        return ConnectionPool.getInstance().initialize()
    }

    // 注意：数据库表初始化已由迁移系统处理
    // 原 initializeDatabase() 和 initializeArchiveSchema() 方法已移除
    // 请参考 src/migrations/ 目录下的迁移文件

}
