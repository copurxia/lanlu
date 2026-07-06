package csorm

import std.collection.*
import std.convert.*
import postgresql_driver.*

/**
 * csorm 运行时值类型(对标 sea_query::Value)。驱动边界处转换为 PGValue。
 * - VJson 承载 JSONB 文本(上层按需解析)。
 * - VArr 用于 PG 数组(写侧绑定 $n::type[])。
 */
public enum Value {
    | VInt(Int64)
    | VFloat(Float64)
    | VText(String)
    | VBool(Bool)
    | VBytes(Array<UInt8>)
    | VJson(String)
    | VArr(Array<Value>)
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

/** ?T 也能转为 Value(None → VNull)。 */
public func optionToValue<T>(v: ?T): Value where T <: IntoValue {
    match (v) {
        case Some(x) => x.intoValue()
        case None => Value.VNull
    }
}

/** Value → postgresql_driver.PGValue(驱动绑定边界)。 */
public func valueToPG(v: Value): PGValue {
    match (v) {
        case VInt(x) => PGValue.PGInt64(x)
        case VFloat(x) => PGValue.PGFloat64(x)
        case VText(s) => PGValue.PGText(s)
        case VBool(b) => PGValue.PGBool(b)
        case VBytes(b) => PGValue.PGBytes(b)
        case VJson(s) => PGValue.PGJson(s)
        case VArr(elems) => PGValue.PGArray(Array<PGValue>(elems.size, { i => valueToPG(elems[i]) }))
        case VNull => PGValue.PGNull
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

/** PGValue → Value(读侧回包)。 */
public func pgValueToValue(v: PGValue): Value {
    match (v) {
        case PGInt64(x) => Value.VInt(x)
        case PGInt32(x) => Value.VInt(Int64(x))
        case PGFloat64(x) => Value.VFloat(x)
        case PGBool(b) => Value.VBool(b)
        case PGText(s) => Value.VText(s)
        case PGBytes(b) => Value.VBytes(b)
        case PGJson(s) => Value.VJson(s)
        case PGArray(elems) =>
            Value.VArr(Array<Value>(elems.size, { i => pgValueToValue(elems[i]) }))
        case PGNull => Value.VNull
    }
}

/**
 * 行 → 值(按列名 + 类型提示)。typeHint 用列 OID 决定走哪种 Row 读取器。
 * 由宏生成的 Entity.fromRow 调用，也可手动使用。
 */
public func rowToValue(r: Row, col: String, hint: ColType): Value {
    let idx = col
    if (r.isNull(idx)) {
        return Value.VNull
    }
    match (hint) {
        case ColType.TInt | ColType.TBool => Value.VInt(r.getInt64(idx))
        case ColType.TFloat => Value.VFloat(r.getFloat64(idx))
        case ColType.TText => Value.VText(r.getText(idx))
        case ColType.TJson => Value.VJson(r.getJson(idx))
        case ColType.TBytes => Value.VBytes(r.getBytes(idx))
        case ColType.TTextArray => textArray(r.getTextArray(idx))
        case ColType.TInt64Array => int64Array(r.getInt64Array(idx))
        case ColType.TInt32Array => int32Array(r.getInt32Array(idx))
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
}
