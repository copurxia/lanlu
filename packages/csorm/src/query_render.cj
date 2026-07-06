package csorm

import std.collection.*
import std.convert.*

/**
 * SQL 渲染工具：标识符引号、占位符编号、片段拼接。
 * PG 文本协议下占位符 $1..$n，跨子句连续编号。
 */

/** 给标识符(表名/列名)加双引号，内部双引号转义为 ""，防注入。 */
public func quoteIdent(s: String): String {
    let bytes = s.toArray()
    let out = ArrayList<UInt8>()
    out.add(34u8) // '"'
    for (b in bytes) {
        if (b == 34u8) {
            out.add(34u8) // 双引号转义
        }
        out.add(b)
    }
    out.add(34u8) // '"'
    String.fromUtf8(out.toArray())
}

/** 带可选 schema 的表引用：schema.tbl → "schema"."tbl"。 */
public func quoteTable(schema: ?String, table: String): String {
    match (schema) {
        case Some(s) => quoteIdent(s) + "." + quoteIdent(table)
        case None => quoteIdent(table)
    }
}

/** 占位符编号自增器：每 append 一次返回 $n 并 n+=1。 */
public class Placeholder {
    var n: Int64 = 0
    public init() {}
    public init(start!: Int64) { n = start }
    public func next(): String {
        n += 1
        return "$" + n.toString()
    }
    public func current(): Int64 { n }
}

/** 生成 N 个占位符，逗号分隔：$1,$2,...$n。 */
public func placeholders(n: Int64, ph: Placeholder): String {
    let parts = ArrayList<String>()
    var i = 0
    while (i < n) {
        parts.add(ph.next())
        i += 1
    }
    joinComma(parts.toArray())
}

/** 逗号拼接字符串数组。 */
public func joinComma(parts: Array<String>): String {
    let sb = StringBuilder()
    var first = true
    for (p in parts) {
        if (!first) { sb.append(", ") }
        sb.append(p)
        first = false
    }
    sb.toString()
}

/** 空格拼接字符串数组。 */
public func joinSpace(parts: Array<String>): String {
    let sb = StringBuilder()
    var first = true
    for (p in parts) {
        if (!first) { sb.append(" ") }
        sb.append(p)
        first = false
    }
    sb.toString()
}

/** 拼接 SQL 片段，片段间用空格分隔。 */
public func joinSql(parts: Array<String>): String { joinSpace(parts) }