package csorm

/**
 * PartialModel / FromQueryResult / Dynamic Entity(对标 sea-orm partial_model.rs / FromQueryResult / dynamic)。
 *
 * - PartialModel：部分列投影，只取需要的列，避免 SELECT * 宽表过取。
 * - FromQueryResult：任意 struct → 行映射(按字段名匹配列名)，支持原始 SQL 直查。
 * - DynamicEntity：运行时 schema，fromRow 产出 Map<String, Value>(多租户动态表)。
 *
 * 宏支持(@PartialModel/@FromQuery)后续补；当前手写实现即可使用。
 */
import std.collection.*
import std.convert.*
import postgresql_driver.*

// ===== PartialModel =====

/**
 * 部分模型接口：只声明需要的字段，SELECT 只取这些列。
 * 实现者提供 columns()(投影列) 与 fromRow(行映射)。
 * 对标 sea-orm PartialModelTrait。
 */
public interface PartialModel {
    /** 投影列名(只 SELECT 这些列)。 */
    func columns(): Array<String>
    /** 行 → 模型。 */
    func fromRow(r: Row): Any
}

/**
 * 把 SelectQuery 的投影改为 PartialModel 指定的列。
 * 返回修改后的 SelectQuery(原查询的 cols 被替换)。
 */
public func intoPartialModel(q: SelectQuery, pm: PartialModel): SelectQuery {
    q.select(pm.columns())
    q
}

// ===== FromQueryResult =====

/**
 * 通用行映射接口：任意 struct → 行映射(按字段名匹配列名)。
 * 对标 sea-orm FromQueryResult。用于原始 SQL 直查 / 聚合查询结果映射。
 */
public interface FromQueryResult {
    /** 行 → 模型。 */
    func fromRow(r: Row): Any
}

/**
 * 执行原始 SQL，按 FromQueryResult 映射为 T 数组。
 * 占位符用 $1..$n(PG 文本协议)。
 */
public func queryAll<T>(db: Database, sql: String, params: Array<Value>, mapper: FromQueryResult): Array<T> {
    let rows = db.raw<Row>(sql, params, { r => r })
    let out = ArrayList<T>()
    for (r in rows) {
        match (mapper.fromRow(r) as T) {
            case Some(t) => out.add(t)
            case None => ()
        }
    }
    out.toArray()
}

/**
 * 执行原始 SQL，取首行按 FromQueryResult 映射(无结果 None)。
 */
public func queryOne<T>(db: Database, sql: String, params: Array<Value>, mapper: FromQueryResult): ?T {
    match (db.rawOne<Row>(sql, params, { r => r })) {
        case Some(r) =>
            match (mapper.fromRow(r) as T) {
                case Some(t) => Some(t)
                case None => None
            }
        case None => None
    }
}

/**
 * 执行 SelectQuery，按 FromQueryResult 映射为 T 数组。
 */
public func queryAll<T>(db: Database, q: SelectQuery, mapper: FromQueryResult): Array<T> {
    let (sql, params) = q.build()
    queryAll<T>(db, sql, params, mapper)
}

// ===== Dynamic Entity =====

/**
 * 动态实体：运行时才知道表结构的实体(多租户动态表)。
 * fromRow 产出 DynModel(Map<String, Value>)，列名 → 值。
 */
public class DynamicEntity {
    public let tableName: String
    public let schema: ?String
    public let columnNames: Array<String>
    public let columnTypes: Array<ColType>

    public init(tableName: String, schema: ?String, columnNames: Array<String>, columnTypes: Array<ColType>) {
        this.tableName = tableName
        this.schema = schema
        this.columnNames = columnNames
        this.columnTypes = columnTypes
    }

    /** SELECT 全部列(按 columnNames + columnTypes 映射)。 */
    public func select(): SelectQuery {
        let q = SelectQuery()
        match (schema) {
            case Some(s) => q.from(s, table: tableName)
            case None => q.from(tableName)
        }
        q.select(columnNames)
        q
    }

    /** 行 → 动态模型(列名 → Value)。 */
    public func fromRow(r: Row): DynamicModel {
        let m = HashMap<String, Value>()
        for (i in 0..columnNames.size) {
            let col = columnNames[i]
            let ty = if (i < columnTypes.size) { columnTypes[i] } else { ColType.TText }
            m[col] = rowToValue(r, col, ty)
        }
        DynamicModel(m)
    }
}

/**
 * 动态模型：列名 → Value 的映射(运行时行数据)。
 */
public class DynamicModel {
    public let data: HashMap<String, Value>

    public init(data: HashMap<String, Value>) {
        this.data = data
    }

    /** 按列名取值。 */
    public func get(col: String): ?Value {
        match (data.get(col)) {
            case Some(v) => Some(v)
            case None => None
        }
    }

    /** 按列名取 Int64。 */
    public func getInt64(col: String): ?Int64 {
        match (data.get(col)) {
            case Some(Value.VInt(x)) => Some(x)
            case _ => None
        }
    }

    /** 按列名取 String。 */
    public func getText(col: String): ?String {
        match (data.get(col)) {
            case Some(Value.VText(s)) => Some(s)
            case Some(Value.VJson(s)) => Some(s)
            case Some(Value.VUuid(s)) => Some(s)
            case Some(Value.VDecimal(s)) => Some(s)
            case _ => None
        }
    }

    /** 按列名取 Bool。 */
    public func getBool(col: String): ?Bool {
        match (data.get(col)) {
            case Some(Value.VBool(b)) => Some(b)
            case _ => None
        }
    }

    /** 全部列名。 */
    public func columns(): Array<String> {
        let out = ArrayList<String>()
        for ((k, _) in data) { out.add(k) }
        out.toArray()
    }

    /** 转 Map<String, String>(值用 toString，便于序列化)。 */
    public func toStringMap(): Map<String, String> {
        let m = HashMap<String, String>()
        for ((k, v) in data) {
            m[k] = valueToString(v)
        }
        m
    }
}

/** Value → 字符串(用于 DynamicModel.toStringMap)。 */
func valueToString(v: Value): String {
    match (v) {
        case Value.VInt(x) => x.toString()
        case Value.VFloat(x) => x.toString()
        case Value.VText(s) => s
        case Value.VBool(b) => b.toString()
        case Value.VBytes(b) => "bytes[" + b.size.toString() + "]"
        case Value.VJson(s) => s
        case Value.VArr(_) => "[array]"
        case Value.VTimestamp(us) => us.toString()
        case Value.VTimestampTz(us) => us.toString()
        case Value.VDate(d) => d.toString()
        case Value.VTime(t) => t.toString()
        case Value.VUuid(s) => s
        case Value.VDecimal(s) => s
        case Value.VEnum(_, raw) => raw
        case Value.VNull => "NULL"
    }
}

// ===== Database 扩展：FromQueryResult 直查 =====

/**
 * 扩展 Database：rawQueryAll<T> 原始 SQL + FromQueryResult 直查。
 */
extend Database {
    /** 原始 SQL + FromQueryResult 直查为 T 数组。 */
    public func rawQueryAll<T>(sql: String, params: Array<Value>, mapper: FromQueryResult): Array<T> {
        queryAll<T>(this, sql, params, mapper)
    }

    /** 原始 SQL + FromQueryResult 取首行。 */
    public func rawQueryOne<T>(sql: String, params: Array<Value>, mapper: FromQueryResult): ?T {
        queryOne<T>(this, sql, params, mapper)
    }

    /** SelectQuery + FromQueryResult 映射为 T 数组。 */
    public func queryAllMapped<T>(q: SelectQuery, mapper: FromQueryResult): Array<T> {
        queryAll<T>(this, q, mapper)
    }
}