package postgresql_driver

import std.collection.*
import std.convert.*

/**
 * 参数绑定与列读取的统一值载体。
 * - 文本协议(resultFormat=0)下，所有值经 toText 序列化为 libpq 接受的文本。
 * - PGArray 用于写侧数组绑定(配合 $n::text[] 等 cast)。
 */
public enum PGValue {
    | PGInt64(Int64)
    | PGInt32(Int32)
    | PGFloat64(Float64)
    | PGBool(Bool)
    | PGText(String)
    | PGBytes(Array<UInt8>)
    | PGArray(Array<PGValue>)   // 一维(嵌套 PGArray 表多维)
    | PGJson(String)            // JSONB 文本
    | PGNull
}

/**
 * 将 PGValue 序列化为 libpq text 协议文本(用于 PQexecParams 绑定)。
 * PGNull 对应 paramValues 项为 NULL 指针(在调用层处理，此处不调用)。
 */
public func pgValueToText(v: PGValue): String {
    match (v) {
        case PGInt64(x) => x.toString()
        case PGInt32(x) => x.toString()
        case PGFloat64(x) => x.toString()
        case PGBool(b) => if (b) { "true" } else { "false" }
        case PGText(s) => s
        case PGJson(s) => s
        case PGBytes(b) => "\\x" + bytesToHex(b)   // BYTEA 文本输入格式
        case PGNull => ""
        case PGArray(elems) => formatPgArray(elems)
    }
}

// ===== PG 数组文本格式 =====
// {e1,e2,...};NULL 不加引号;数值/布尔直接字面量;字符串按需加双引号转义;空数组 {}。

public func formatPgArray(elems: Array<PGValue>): String {
    let out = ArrayList<UInt8>()
    out.add(123u8) // '{'
    for (i in 0..elems.size) {
        if (i > 0) {
            out.add(44u8) // ','
        }
        appendPgArrayElem(out, elems[i])
    }
    out.add(125u8) // '}'
    String.fromUtf8(out.toArray())
}

func appendPgArrayElem(out: ArrayList<UInt8>, e: PGValue): Unit {
    match (e) {
        case PGNull =>
            out.add(78u8); out.add(85u8); out.add(76u8); out.add(76u8) // "NULL"
        case PGInt64(x) =>
            for (c in x.toString().toArray()) { out.add(c) }
        case PGInt32(x) =>
            for (c in x.toString().toArray()) { out.add(c) }
        case PGFloat64(x) =>
            for (c in x.toString().toArray()) { out.add(c) }
        case PGBool(b) =>
            let s = if (b) { "true" } else { "false" }
            for (c in s.toArray()) { out.add(c) }
        case PGText(s) =>
            appendQuotedPgArrayElem(out, s)
        case PGJson(s) =>
            appendQuotedPgArrayElem(out, s)
        case PGBytes(b) =>
            appendQuotedPgArrayElem(out, "\\x" + bytesToHex(b))
        case PGArray(nested) =>
            let inner = formatPgArray(nested)
            for (c in inner.toArray()) { out.add(c) }
    }
}

// 字符串元素：含分隔符(逗号/花括号/双引号/反斜杠/空白)或为空串/NULL 文本时加双引号包裹，
// 内部双引号转 \"、反斜杠转 \\；否则原样追加。
func appendQuotedPgArrayElem(out: ArrayList<UInt8>, s: String): Unit {
    let bytes = s.toArray()
    var needQuote = bytes.size == 0
    for (b in bytes) {
        if (b == 44u8 || b == 123u8 || b == 125u8 || b == 34u8 || b == 92u8 || b == 32u8 || b == 9u8) {
            needQuote = true
            break
        }
    }
    if (!needQuote && (s == "NULL" || s == "null")) {
        needQuote = true
    }
    if (needQuote) {
        out.add(34u8) // '"'
        for (b in bytes) {
            if (b == 34u8 || b == 92u8) {
                out.add(92u8) // '\'
            }
            out.add(b)
        }
        out.add(34u8) // '"'
    } else {
        for (b in bytes) {
            out.add(b)
        }
    }
}

// 字节数组 -> 小写十六进制串(无分隔)。
public func bytesToHex(b: Array<UInt8>): String {
    let digits = "0123456789abcdef".toArray()
    let out = ArrayList<UInt8>()
    for (x in b) {
        out.add(digits[Int64(x >> 4)])
        out.add(digits[Int64(x & 15u8)])
    }
    String.fromUtf8(out.toArray())
}

// 字节转 UInt8。
public func byteToHex(b: UInt8): String {
    let digits = "0123456789abcdef".toArray()
    let out = Array<UInt8>(2, { _ => 0u8 })
    out[0] = digits[Int64(b >> 4)]
    out[1] = digits[Int64(b & 15u8)]
    String.fromUtf8(out)
}

// ===== PG 数组文本解析(读侧)=====
// 解析 {e1,e2,NULL,...} 为字符串列表(去引号、反转义)。调用方按列类型再做标量解析。
public func parsePgArrayText(s: String): Array<String> {
    let bytes = s.toArray()
    let n = bytes.size
    if (n < 2) {
        return Array<String>()
    }
    if (bytes[0] != 123u8 || bytes[n - 1] != 125u8) {
        return Array<String>()
    }
    let inner = bytes[1..n - 1]
    let tokens = ArrayList<String>()
    var cur = ArrayList<UInt8>()
    var inQ = false
    var i = 0
    while (i < inner.size) {
        let b = inner[i]
        if (b == 34u8 && !inQ) {
            inQ = true
            i += 1
            continue
        }
        if (b == 34u8 && inQ) {
            // 检查转义双引号 \"(在数组内双引号以 \" 表示)
            if (i + 1 < inner.size && inner[i + 1] == 34u8) {
                cur.add(34u8)
                i += 2
                continue
            }
            inQ = false
            i += 1
            continue
        }
        if (b == 92u8 && inQ && i + 1 < inner.size) {
            // 反斜杠转义：\" -> "，\\ -> \
            cur.add(inner[i + 1])
            i += 2
            continue
        }
        if (b == 44u8 && !inQ) {
            tokens.add(String.fromUtf8(cur.toArray()))
            cur = ArrayList<UInt8>()
            i += 1
            continue
        }
        cur.add(b)
        i += 1
    }
    tokens.add(String.fromUtf8(cur.toArray()))
    // 未加引号的 NULL(任意大小写)统一为空串标记？保留原值，由调用方判定。
    return tokens.toArray()
}

/**
 * 解析 PG text 协议 BYTEA 输出格式 \xHEX 为字节数组。
 * 非 \x 前缀(传统转义格式)按尽力解析；此实现仅处理 hex 格式(PG 9.0+ 默认)。
 */
public func parseByteaHex(s: String): Array<UInt8> {
    let bytes = s.toArray()
    if (bytes.size >= 2 && bytes[0] == 92u8 && bytes[1] == 120u8) {
        // \x 前缀
        let hex = bytes[2..bytes.size]
        let out = ArrayList<UInt8>()
        var i = 0
        while (i + 1 < hex.size) {
            out.add(hexVal(hex[i]) * 16u8 + hexVal(hex[i + 1]))
            i += 2
        }
        return out.toArray()
    }
    // 非 hex 格式：返回原始字节(降级)
    return bytes
}

func hexVal(c: UInt8): UInt8 {
    if (c >= 48u8 && c <= 57u8) { return c - 48u8 }          // '0'-'9'
    if (c >= 97u8 && c <= 102u8) { return c - 97u8 + 10u8 }  // 'a'-'f'
    if (c >= 65u8 && c <= 70u8) { return c - 65u8 + 10u8 }   // 'A'-'F'
    return 0u8
}
