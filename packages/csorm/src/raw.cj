package csorm

import std.collection.*
import std.convert.*

/**
 * RawQuery：原始 SQL 兜底，供复杂查询(CTE + 窗口 + 多表 EXISTS，如 lanlu searchArchives)使用。
 * 调用方自行管理占位符编号($1..$n)，append() 追加片段与对应参数(参数顺序需与占位符一致)。
 * 与 builder 不同，RawQuery 不做标识符引号/占位符重排，直接交给 driver 文本协议。
 */
public class RawQuery {
    var sql: String
    var params: ArrayList<Value> = ArrayList<Value>()

    public init(sql: String) { this.sql = sql }
    public init(sql: String, params: Array<Value>) {
        this.sql = sql
        for (p in params) { this.params.add(p) }
    }

    /** 追加 SQL 片段(直接字符串拼接，空格分隔)与对应参数。 */
    public func append(sqlFragment: String, params: Array<Value>): RawQuery {
        if (sqlFragment.isEmpty()) { return this }
        sql = if (sql.isEmpty()) { sqlFragment } else { sql + " " + sqlFragment }
        for (p in params) { this.params.add(p) }
        this
    }

    public func build(): (String, Array<Value>) {
        (sql, params.toArray())
    }
}