package postgresql_driver

// ===== libpq FFI 声明 =====
// 调用方需 link -lpq。所有 foreign 函数调用须在 unsafe 块内。
// 不透明句柄 PGconn/PGresult/PGcancel 统一用 CPointer<Unit> 表达。

// 连接管理
foreign func PQconnectdb(conninfo: CString): CPointer<Unit>
foreign func PQstatus(conn: CPointer<Unit>): Int32
foreign func PQerrorMessage(conn: CPointer<Unit>): CString
foreign func PQfinish(conn: CPointer<Unit>): Unit

// 执行：无参数(DDL / 简单语句)
foreign func PQexec(conn: CPointer<Unit>, command: CString): CPointer<Unit>

// 执行：带参数(text 协议, resultFormat=0)。占位符 $1..$n。
foreign func PQexecParams(conn: CPointer<Unit>, command: CString, nParams: Int32,
    paramTypes: CPointer<UInt32>, paramValues: CPointer<CString>,
    paramLengths: CPointer<Int32>, paramFormats: CPointer<Int32>,
    resultFormat: Int32): CPointer<Unit>

// 结果元信息
foreign func PQresultStatus(res: CPointer<Unit>): Int32
foreign func PQresultErrorMessage(res: CPointer<Unit>): CString
foreign func PQresultErrorField(res: CPointer<Unit>, fieldcode: Int32): CString
foreign func PQntuples(res: CPointer<Unit>): Int32
foreign func PQnfields(res: CPointer<Unit>): Int32
foreign func PQfname(res: CPointer<Unit>, col: Int32): CString
foreign func PQftype(res: CPointer<Unit>, col: Int32): Int32
foreign func PQgetvalue(res: CPointer<Unit>, row: Int32, col: Int32): CString
foreign func PQgetisnull(res: CPointer<Unit>, row: Int32, col: Int32): Int32
foreign func PQcmdTuples(res: CPointer<Unit>): CString
foreign func PQclear(res: CPointer<Unit>): Unit

// 查询取消(线程安全：PGcancel 独立于 PGconn，可跨线程调用)
foreign func PQgetCancel(conn: CPointer<Unit>): CPointer<Unit>
foreign func PQcancel(pgcancel: CPointer<Unit>, errbuf: CPointer<UInt8>, errbufsize: Int32): Int32
foreign func PQfreeCancel(pgcancel: CPointer<Unit>): Unit

// ===== libpq 状态码 =====
const PG_CONNECTION_OK: Int32 = 0
const PGRES_EMPTY_QUERY: Int32 = 0
const PGRES_COMMAND_OK: Int32 = 1
const PGRES_TUPLES_OK: Int32 = 2
const PGRES_BAD_RESPONSE: Int32 = 4
const PGRES_FATAL_ERROR: Int32 = 7

// ===== PQresultErrorField 字段码(libpq-fe.h，ASCII 字符)=====
let PG_DIAG_SEVERITY: Int32 = 83            // 'S'
let PG_DIAG_SQLSTATE: Int32 = 67            // 'C'
let PG_DIAG_MESSAGE_PRIMARY: Int32 = 77     // 'M'
let PG_DIAG_MESSAGE_DETAIL: Int32 = 68      // 'D'
let PG_DIAG_MESSAGE_HINT: Int32 = 72        // 'H'
let PG_DIAG_SCHEMA_NAME: Int32 = 115        // 's'
let PG_DIAG_TABLE_NAME: Int32 = 116         // 't'
let PG_DIAG_COLUMN_NAME: Int32 = 99         // 'c'
let PG_DIAG_CONSTRAINT_NAME: Int32 = 110    // 'n'
