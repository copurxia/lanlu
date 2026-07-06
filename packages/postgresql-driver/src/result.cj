package postgresql_driver

import std.collection.*
import std.convert.*

/**
 * 包装 libpq PGresult。own 该指针，close() 时 PQclear。
 * 文本协议下所有列值均为文本字符串；类型信息经 PQftype(OID) 提供，供 Row 做类型化读取。
 *
 * 生命周期：通常由 PGConnection 的 query/exec 创建、物化后立即 close。
 * 对游标场景，每次 FETCH 产生一个短生命周期的 PGResult。
 */
public class PGResult {
    let res: CPointer<Unit>
    var cleared = false

    init(res: CPointer<Unit>) {
        this.res = res
    }

    /** 底层指针(供同包内 FFI 调用)。 */
    func raw(): CPointer<Unit> { res }

    public func isClosed(): Bool { cleared }

    public func close(): Unit {
        if (!cleared) {
            unsafe { PQclear(res) }
            cleared = true
        }
    }

    public func status(): Int32 {
        unsafe { PQresultStatus(res) }
    }

    public func isCommandOk(): Bool { status() == PGRES_COMMAND_OK }
    public func isTuplesOk(): Bool { status() == PGRES_TUPLES_OK }

    /** 行数(PQntuples)。 */
    public func rowCount(): Int64 {
        Int64(unsafe { PQntuples(res) })
    }

    /** 列数(PQnfields)。 */
    public func fieldCount(): Int64 {
        Int64(unsafe { PQnfields(res) })
    }

    /** 列名。 */
    public func fieldName(col: Int64): String {
        unsafe { PQfname(res, Int32(col)) }.toString()
    }

    /** 列类型 OID(PQftype)。 */
    public func fieldType(col: Int64): Int32 {
        unsafe { PQftype(res, Int32(col)) }
    }

    /** 指定单元格是否为 NULL。 */
    public func isNull(row: Int64, col: Int64): Bool {
        unsafe { PQgetisnull(res, Int32(row), Int32(col)) } == 1
    }

    /** 指定单元格的原始文本值(text 协议)。调用方须先确认非 NULL。 */
    public func getValue(row: Int64, col: Int64): String {
        unsafe { PQgetvalue(res, Int32(row), Int32(col)) }.toString()
    }

    /** 受影响行数(PQcmdTuples 文本→Int64)；非 DML 返回 -1。 */
    public func affectedRows(): Int64 {
        let s = unsafe { PQcmdTuples(res) }.toString()
        if (s.isEmpty()) {
            return -1
        }
        try {
            Int64.parse(s)
        } catch (_: Exception) {
            -1
        }
    }

    /**
     * 从失败结果构建 PGError(读取 SQLSTATE/严重级别/详情/提示/约束名等诊断字段)。
     * 调用方须先确认 status 非 COMMAND_OK/TUPLES_OK。
     */
    public func buildError(sql: String): PGError {
        let msg = unsafe { PQresultErrorMessage(res) }.toString()
        let sqlstate = readField(PG_DIAG_SQLSTATE)
        let severity = readField(PG_DIAG_SEVERITY)
        let detail = readField(PG_DIAG_MESSAGE_DETAIL)
        let hint = readField(PG_DIAG_MESSAGE_HINT)
        let schema = readField(PG_DIAG_SCHEMA_NAME)
        let table = readField(PG_DIAG_TABLE_NAME)
        let column = readField(PG_DIAG_COLUMN_NAME)
        let constraint = readField(PG_DIAG_CONSTRAINT_NAME)
        var full = msg
        if (!sql.isEmpty()) {
            full = full + " | sql=" + sql
        }
        return PGError(full, sqlstate: sqlstate, severity: severity, detail: detail,
            hint: hint, schemaName: schema, tableName: table, columnName: column,
            constraintName: constraint)
    }

    func readField(code: Int32): String {
        let p = unsafe { PQresultErrorField(res, code) }
        if (p.isNull()) {
            return ""
        }
        return p.toString()
    }
}
