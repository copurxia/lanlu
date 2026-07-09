package csorm

import std.collection.*
import std.convert.*
import std.time.*

/**
 * csorm 运行时值类型(对标 sea_query::Value)。驱动边界处转换为原生参数。
 * - VJson 承载 JSONB 文本(上层按需解析)。
 * - VArr 用于 PG 数组(写侧绑定 $n::type[])。
 * - VTimestamp/VDate/VUuid/VDecimal：阶段五新增的类型化变体。
 * - VEnum：ActiveEnum 枚举值(enumName + 原始字符串值)。
 */
public enum Value {
    | VInt(Int64)
    | VFloat(Float64)
    | VText(String)
    | VBool(Bool)
    | VBytes(Array<UInt8>)
    | VJson(String)
    | VArr(Array<Value>)
    | VTimestamp(Int64)        // epoch 微秒
    | VTimestampTz(Int64)      // epoch 微秒(带时区)
    | VDate(Int64)             // epoch 天数(从 1970-01-01 起)
    | VTime(Int64)             // 一日内的微秒数
    | VUuid(String)            // UUID 文本形式
    | VDecimal(String)         // Decimal 文本透传(避免精度损失)
    | VEnum(String, String)    // (enumName, rawValue) — ActiveEnum
    | VNull
}

/** 可转为 Value 的类型约束，供列操作符泛型使用。 */
public interface IntoValue {
    func intoValue(): Value
}

extend Int64 <: IntoValue { public func intoValue(): Value { Value.VInt(this) } }
extend Int32 <: IntoValue { public func intoValue(): Value { Value.VInt(Int64(this)) } }
extend UInt64 <: IntoValue { public func intoValue(): Value { Value.VInt(Int64(this)) } }
extend Float64 <: IntoValue { public func intoValue(): Value { Value.VFloat(this) } }
extend Float32 <: IntoValue { public func intoValue(): Value { Value.VFloat(Float64(this)) } }
extend Bool <: IntoValue { public func intoValue(): Value { Value.VBool(this) } }
extend String <: IntoValue { public func intoValue(): Value { Value.VText(this) } }
extend Array<UInt8> <: IntoValue { public func intoValue(): Value { Value.VBytes(this) } }
// 阶段五：DateTime → VTimestamp(epoch μs)
extend DateTime <: IntoValue {
    public func intoValue(): Value {
        Value.VTimestamp(this.toUnixTimeStamp().toMicroseconds())
    }
}

/** ?T 也能转为 Value(None → VNull)。 */
public func optionToValue<T>(v: ?T): Value where T <: IntoValue {
    match (v) {
        case Some(x) => x.intoValue()
        case None => Value.VNull
    }
}

/** 便捷构造。 */
public func vint(x: Int64): Value { Value.VInt(x) }
public func vtext(s: String): Value { Value.VText(s) }
public func vbool(b: Bool): Value { Value.VBool(b) }
public func vfloat(x: Float64): Value { Value.VFloat(x) }
public func vjson(s: String): Value { Value.VJson(s) }
public func varr(elems: Array<Value>): Value { Value.VArr(elems) }
public func vbytes(b: Array<UInt8>): Value { Value.VBytes(b) }
public func vtimestamp(us: Int64): Value { Value.VTimestamp(us) }
public func vtimestampTz(us: Int64): Value { Value.VTimestampTz(us) }
public func vdate(days: Int64): Value { Value.VDate(days) }
public func vtime(us: Int64): Value { Value.VTime(us) }
public func vuuid(s: String): Value { Value.VUuid(s) }
public func vdecimal(s: String): Value { Value.VDecimal(s) }
public func venum(enumName: String, raw: String): Value { Value.VEnum(enumName, raw) }
public func vnull(): Value { Value.VNull }

/**
 * JSONB 列载体：持有原始 JSON 文本，写入时经 VJson 绑定($n::jsonb)。
 * 上层可按需用 JSON 库解析；空串归一化为 "{}"。
 */
public struct Jsonb {
    public let text: String
    public init(text: String) {
        let t = text.trimAscii()
        this.text = if (t.isEmpty()) { "{}" } else { t }
    }
    public static func empty(): Jsonb { Jsonb("{}") }
    public func toValue(): Value { Value.VJson(text) }
    public func toString(): String { text }
}

/** 文本数组便捷构造。 */
public func textArray(elems: Array<String>): Value {
    Value.VArr(Array<Value>(elems.size, { i => Value.VText(elems[i]) }))
}

/** Int64 数组便捷构造。 */
public func int64Array(elems: Array<Int64>): Value {
    Value.VArr(Array<Value>(elems.size, { i => Value.VInt(elems[i]) }))
}

/** Int32 数组便捷构造。 */
public func int32Array(elems: Array<Int32>): Value {
    Value.VArr(Array<Value>(elems.size, { i => Value.VInt(Int64(elems[i])) }))
}

/**
 * 行 → 值(按列名 + 类型提示)。经后端无关 Row 接口读取。
 * 由宏生成的 Entity.fromRow 调用，也可手动使用。
 */
public func rowToValue(r: Row, col: String, hint: ColType): Value {
    let idx = col
    if (r.isNull(idx)) {
        return Value.VNull
    }
    match (hint) {
        case ColType.TInt => Value.VInt(r.getInt64(idx))
        case ColType.TBool => Value.VBool(r.getBool(idx))
        case ColType.TFloat => Value.VFloat(r.getFloat64(idx))
        case ColType.TText => Value.VText(r.getText(idx))
        case ColType.TJson => Value.VJson(r.getJson(idx))
        case ColType.TBytes => Value.VBytes(r.getBytes(idx))
        case ColType.TTextArray => textArray(r.getTextArray(idx))
        case ColType.TInt64Array => int64Array(r.getInt64Array(idx))
        case ColType.TInt32Array => int32Array(r.getInt32Array(idx))
        case ColType.TTimestamp | ColType.TTimestampTz => Value.VTimestamp(r.getInt64(idx))
        case ColType.TDate => Value.VDate(r.getInt64(idx))
        case ColType.TTime => Value.VTime(r.getInt64(idx))
        case ColType.TUuid => Value.VUuid(r.getText(idx))
        case ColType.TDecimal => Value.VDecimal(r.getText(idx))
        case ColType.TEnum => Value.VText(r.getText(idx))  // 枚举读为文本，由 ActiveEnum.fromValue 转换
    }
}

/** 列类型提示(供 rowToValue 与宏生成体使用)。 */
public enum ColType {
    | TInt
    | TFloat
    | TBool
    | TText
    | TJson
    | TBytes
    | TTextArray
    | TInt64Array
    | TInt32Array
    | TTimestamp        // 阶段五新增
    | TTimestampTz
    | TDate
    | TTime
    | TUuid
    | TDecimal
    | TEnum
}

// ===== 阶段五：时间/UUID/Decimal 文本格式化 =====

/** epoch 微秒 → PG TIMESTAMP 文本(YYYY-MM-DD HH:MM:SS.ffffff)。 */
public func timestampUsToPgText(us: Int64): String {
    let dt = DateTime.fromUnixTimeStamp(Duration.microsecond * us)
    dt.format("yyyy-MM-dd HH:mm:ss.ffffff")
}

/** epoch 微秒 → PG TIMESTAMPTZ 文本(UTC，YYYY-MM-DD HH:MM:SS.ffffff+00)。 */
public func timestampTzUsToPgText(us: Int64): String {
    let dt = DateTime.fromUnixTimeStamp(Duration.microsecond * us).inUTC()
    dt.format("yyyy-MM-dd HH:mm:ss.ffffff+00")
}

/** epoch 天数 → PG DATE 文本(YYYY-MM-DD)。 */
public func dateDaysToPgText(days: Int64): String {
    let dt = DateTime.fromUnixTimeStamp(Duration.day * days)
    dt.format("yyyy-MM-dd")
}

/** 一日内微秒数 → PG TIME 文本(HH:MM:SS.ffffff)。 */
public func timeUsToPgText(us: Int64): String {
    let totalSec = us / 1_000_000
    let h = totalSec / 3600
    let m = (totalSec % 3600) / 60
    let s = totalSec % 60
    let frac = us % 1_000_000
    let hStr = if (h < 10) { "0" + h.toString() } else { h.toString() }
    let mStr = if (m < 10) { "0" + m.toString() } else { m.toString() }
    let sStr = if (s < 10) { "0" + s.toString() } else { s.toString() }
    let fracStr = if (frac == 0) { "" } else { "." + padLeft(frac.toString(), 6, 48u8) }
    hStr + ":" + mStr + ":" + sStr + fracStr
}

/** 字符串左填充到指定长度(用字节 fillByte 填充)。 */
public func padLeft(s: String, len: Int64, fillByte: UInt8): String {
    let bytes = s.toArray()
    if (bytes.size >= len) { return s }
    let padLen = len - bytes.size
    let out = ArrayList<UInt8>()
    for (_ in 0..padLen) { out.add(fillByte) }
    for (b in bytes) { out.add(b) }
    String.fromUtf8(out.toArray())
}

// ===== ActiveEnum =====

/**
 * ActiveEnum 接口(对标 sea-orm ActiveEnum)：DB 枚举 ↔ 仓颉 enum。
 * 实现者提供 enumName() 与 toValue()/fromValue() 映射。
 * 宏支持(@ActiveEnum)后续补；当前手写实现即可使用。
 */
public interface ActiveEnum {
    func enumName(): String
    func toValue(): String          // 枚举成员 → DB 原始字符串
    func fromValue(raw: String): Bool  // DB 原始字符串 → 当前枚举(匹配则 true)
}

/** ActiveEnum → Value.VEnum。 */
public func activeEnumToValue(e: ActiveEnum): Value {
    Value.VEnum(e.enumName(), e.toValue())
}