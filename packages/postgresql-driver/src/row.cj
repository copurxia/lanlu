package postgresql_driver

import std.collection.*
import std.convert.*

// ===== PostgreSQL 内置类型 OID(用于读侧类型判定)=====
const OID_BOOL: Int32 = 16
const OID_BYTEA: Int32 = 17
const OID_INT8: Int32 = 20
const OID_INT2: Int32 = 21
const OID_INT4: Int32 = 23
const OID_TEXT: Int32 = 25
const OID_FLOAT4: Int32 = 700
const OID_FLOAT8: Int32 = 701
const OID_VARCHAR: Int32 = 1043
const OID_DATE: Int32 = 1082
const OID_TIMESTAMP: Int32 = 1114
const OID_TIMESTAMPTZ: Int32 = 1184
const OID_NUMERIC: Int32 = 1700
const OID_UUID: Int32 = 2950
const OID_JSON: Int32 = 114
const OID_JSONB: Int32 = 3802
const OID_TEXT_ARRAY: Int32 = 1009
const OID_INT8_ARRAY: Int32 = 1016
const OID_INT4_ARRAY: Int32 = 1007
const OID_INT2_ARRAY: Int32 = 1005
const OID_VARCHAR_ARRAY: Int32 = 1015

/** 该 OID 是否为数组类型(typcategory='A'，常见一维数组 OID)。 */
func isArrayOid(oid: Int32): Bool {
    oid == OID_TEXT_ARRAY || oid == OID_INT8_ARRAY || oid == OID_INT4_ARRAY ||
        oid == OID_INT2_ARRAY || oid == OID_VARCHAR_ARRAY
}

/**
 * 查询结果的一行(已物化)。持有列名、OID、原始文本值与 NULL 标记。
 * 类型化读取器按需解析文本，并做 OID 感知的跨类型兼容(如 bool 列读为 Int64)。
 */
public class Row {
    let names: Array<String>
    let oids: Array<Int32>
    let values: Array<String>   // 原始文本(列非空时)
    let nulls: Array<Bool>      // 是否为 NULL
    let nameIndex: HashMap<String, Int64>

    init(names: Array<String>, oids: Array<Int32>, values: Array<String>, nulls: Array<Bool>) {
        this.names = names
        this.oids = oids
        this.values = values
        this.nulls = nulls
        let m = HashMap<String, Int64>()
        for (i in 0..names.size) {
            m[names[i]] = Int64(i)
        }
        this.nameIndex = m
    }

    public func columnCount(): Int64 { Int64(names.size) }

    public func columnName(i: Int64): String { names[i] }

    public func columnOid(i: Int64): Int32 { oids[i] }

    public func isNull(col: Int64): Bool { nulls[col] }

    public func isNull(col: String): Bool { nulls[idx(col)] }

    /** 原始文本值(须非 NULL)。 */
    public func rawValue(col: Int64): String { values[col] }

    public func rawValue(col: String): String { values[idx(col)] }

    // ----- 列名 -> 索引 -----
    func idx(col: String): Int64 {
        match (nameIndex.get(col)) {
            case Some(i) => i
            case None => throw PGError("column not found: " + col)
        }
    }

    func idxChecked(col: Int64): Int64 {
        if (col < 0 || col >= names.size) {
            throw PGError("column index out of range: " + col.toString())
        }
        col
    }

    // ----- 类型化读取(by index) -----

    public func getText(col: Int64): String {
        let i = idxChecked(col)
        if (nulls[i]) { return "" }
        values[i]
    }

    public func getText(col: String): String { getText(idx(col)) }

    public func getOrNullText(col: Int64): ?String {
        let i = idxChecked(col)
        if (nulls[i]) { return None }
        Some(values[i])
    }

    public func getOrNullText(col: String): ?String { getOrNullText(idx(col)) }

    public func getInt64(col: Int64): Int64 {
        let i = idxChecked(col)
        if (nulls[i]) { return 0 }
        parseInt64(oids[i], values[i])
    }

    public func getInt64(col: String): Int64 { getInt64(idx(col)) }

    public func getOrNullInt64(col: Int64): ?Int64 {
        let i = idxChecked(col)
        if (nulls[i]) { return None }
        Some(parseInt64(oids[i], values[i]))
    }

    public func getOrNullInt64(col: String): ?Int64 { getOrNullInt64(idx(col)) }

    public func getInt32(col: Int64): Int32 { Int32(getInt64(col)) }

    public func getInt32(col: String): Int32 { getInt32(idx(col)) }

    public func getOrNullInt32(col: Int64): ?Int32 {
        match (getOrNullInt64(col)) {
            case Some(v) => Some(Int32(v))
            case None => None
        }
    }

    public func getBool(col: Int64): Bool {
        let i = idxChecked(col)
        if (nulls[i]) { return false }
        parseBool(oids[i], values[i])
    }

    public func getBool(col: String): Bool { getBool(idx(col)) }

    public func getOrNullBool(col: Int64): ?Bool {
        let i = idxChecked(col)
        if (nulls[i]) { return None }
        Some(parseBool(oids[i], values[i]))
    }

    public func getOrNullBool(col: String): ?Bool { getOrNullBool(idx(col)) }

    public func getFloat64(col: Int64): Float64 {
        let i = idxChecked(col)
        if (nulls[i]) { return 0.0 }
        parseFloat64(values[i])
    }

    public func getFloat64(col: String): Float64 { getFloat64(idx(col)) }

    public func getOrNullFloat64(col: Int64): ?Float64 {
        let i = idxChecked(col)
        if (nulls[i]) { return None }
        Some(parseFloat64(values[i]))
    }

    public func getOrNullFloat64(col: String): ?Float64 { getOrNullFloat64(idx(col)) }

    /** BYTEA 解码(\xHEX)。 */
    public func getBytes(col: Int64): Array<UInt8> {
        let i = idxChecked(col)
        if (nulls[i]) { return Array<UInt8>() }
        parseByteaHex(values[i])
    }

    public func getBytes(col: String): Array<UInt8> { getBytes(idx(col)) }

    public func getOrNullBytes(col: Int64): ?Array<UInt8> {
        let i = idxChecked(col)
        if (nulls[i]) { return None }
        Some(parseByteaHex(values[i]))
    }

    public func getOrNullBytes(col: String): ?Array<UInt8> { getOrNullBytes(idx(col)) }

    /** JSON/JSONB 原始文本(上层按需解析)。 */
    public func getJson(col: Int64): String { getText(col) }

    public func getJson(col: String): String { getText(col) }

    public func getOrNullJson(col: Int64): ?String { getOrNullText(col) }

    public func getOrNullJson(col: String): ?String { getOrNullText(col) }

    /** text[] / varchar[] 读取为字符串数组。 */
    public func getTextArray(col: Int64): Array<String> {
        let i = idxChecked(col)
        if (nulls[i]) { return Array<String>() }
        let toks = parsePgArrayText(values[i])
        let out = ArrayList<String>()
        for (t in toks) {
            let trimmed = t.trimAscii()
            if (trimmed == "NULL" || trimmed.isEmpty()) {
                out.add("")
            } else {
                out.add(t)
            }
        }
        out.toArray()
    }

    public func getTextArray(col: String): Array<String> { getTextArray(idx(col)) }

    /** int8[] 读取为 Int64 数组。 */
    public func getInt64Array(col: Int64): Array<Int64> {
        let i = idxChecked(col)
        if (nulls[i]) { return Array<Int64>() }
        let toks = parsePgArrayText(values[i])
        let out = ArrayList<Int64>()
        for (t in toks) {
            let trimmed = t.trimAscii()
            if (trimmed == "NULL" || trimmed.isEmpty()) {
                continue
            }
            try { out.add(Int64.parse(trimmed)) } catch (_: Exception) {}
        }
        out.toArray()
    }

    public func getInt64Array(col: String): Array<Int64> { getInt64Array(idx(col)) }

    /** int4[] 读取为 Int32 数组。 */
    public func getInt32Array(col: Int64): Array<Int32> {
        let arr = getInt64Array(col)
        Array<Int32>(arr.size, { i => Int32(arr[i]) })
    }

    public func getInt32Array(col: String): Array<Int32> { getInt32Array(idx(col)) }
}

// ----- 解析辅助(OID 感知)-----

func parseInt64(oid: Int32, raw: String): Int64 {
    if (oid == OID_BOOL) {
        return if (raw == "t" || raw == "true" || raw == "TRUE") { 1 } else { 0 }
    }
    try { Int64.parse(raw.trimAscii()) } catch (_: Exception) { 0 }
}

func parseBool(oid: Int32, raw: String): Bool {
    if (oid == OID_BOOL) {
        return raw == "t" || raw == "true" || raw == "TRUE"
    }
    raw == "t" || raw == "true" || raw == "TRUE" || raw == "1"
}

func parseFloat64(raw: String): Float64 {
    try { Float64.parse(raw.trimAscii()) } catch (_: Exception) { 0.0 }
}
