package csorm

/**
 * Schema / DDL 模块(对标 sea-orm src/schema/)。
 *
 * 从 Entity 定义产出 DDL：CREATE TABLE / CREATE TYPE / ALTER TABLE。
 * - ColumnDef：列元数据(类型/null/unique/indexed/default/comment)。
 * - Schema：按 backend(先 PG)产出 SQL 文本。
 * - SchemaBuilder：链式构造，build() 出 SQL 字符串数组。
 * - EntityRegistry：显式 register(无 inventory 机制)，收集全部已注册 entity 的 DDL。
 * - Database.syncSchema(prefix)：按依赖顺序执行 DDL(DROP IF EXISTS + CREATE)。
 *
 * codegen(从 PG 反向生成 @Entity struct)见独立脚本/包(2.4)。
 */
import std.collection.*
import std.convert.*
import std.sync.*
import postgresql_driver.*

// ===== 扩展 ColType(DDL 侧完整列类型) =====
// 原 ColType 在 value.cj，用于读侧类型提示。这里另起一个 DDL 专用的 SqlColType，
// 避免破坏现有 ColType 的语义与宏生成体。

/**
 * DDL 列类型(对标 sea_query ColumnType)。覆盖 PG 常见类型 + 数组。
 * String(N) 中 N 为长度；Numeric(p,s) 为精度/标度；Array(elem) 为一维数组。
 */
public enum SqlColType {
    | TBool
    | TInt16
    | TInt32
    | TInt64
    | TSerial32           // SERIAL
    | TSerial64           // BIGSERIAL
    | TFloat32
    | TFloat64
    | TNumeric(Option<Int64>, Option<Int64>)   // (precision, scale)
    | TText
    | TStringN(Int64)     // VARCHAR(N)
    | TBytes              // BYTEA
    | TDate
    | TTime
    | TTimestamp
    | TTimestampTz
    | TUuid
    | TJson
    | TJsonb
    | TArray(SqlColType)  // 一维数组
    | TCustom(String)     // 自定义/枚举类型名(CREATE TYPE 后引用)
}

/** SqlColType → PG SQL 类型文本。 */
public func sqlColTypeToPg(t: SqlColType): String {
    match (t) {
        case TBool => "BOOLEAN"
        case TInt16 => "INT2"
        case TInt32 => "INT4"
        case TInt64 => "INT8"
        case TSerial32 => "SERIAL"
        case TSerial64 => "BIGSERIAL"
        case TFloat32 => "FLOAT4"
        case TFloat64 => "FLOAT8"
        case TNumeric(p, s) =>
            match ((p, s)) {
                case (Some(pp), Some(ss)) => "NUMERIC(" + pp.toString() + "," + ss.toString() + ")"
                case (Some(pp), None) => "NUMERIC(" + pp.toString() + ")"
                case _ => "NUMERIC"
            }
        case TText => "TEXT"
        case TStringN(n) => "VARCHAR(" + n.toString() + ")"
        case TBytes => "BYTEA"
        case TDate => "DATE"
        case TTime => "TIME"
        case TTimestamp => "TIMESTAMP"
        case TTimestampTz => "TIMESTAMPTZ"
        case TUuid => "UUID"
        case TJson => "JSON"
        case TJsonb => "JSONB"
        case TArray(elem) => sqlColTypeToPg(elem) + "[]"
        case TCustom(name) => quoteIdent(name)
    }
}

/** 仓颉类型文本(宏生成体里的字段类型) → SqlColType 推断。 */
public func cjTypeToSqlColType(cjTy: String): SqlColType {
    let t = cjTy.trimAscii()
    if (t.startsWith("?")) {
        return cjTypeToSqlColType(t[1..t.size])
    }
    if (t == "Bool") { return SqlColType.TBool }
    if (t == "Int16") { return SqlColType.TInt16 }
    if (t == "Int32") { return SqlColType.TInt32 }
    if (t == "Int64") { return SqlColType.TInt64 }
    if (t == "UInt16") { return SqlColType.TInt16 }
    if (t == "UInt32") { return SqlColType.TInt32 }
    if (t == "UInt64") { return SqlColType.TInt64 }
    if (t == "Float32") { return SqlColType.TFloat32 }
    if (t == "Float64") { return SqlColType.TFloat64 }
    if (t == "String") { return SqlColType.TText }
    if (t == "Array<UInt8>") { return SqlColType.TBytes }
    // 数组：Array<T> → TArray(elem)
    if (t.startsWith("Array")) {
        let lt = indexOfByte(t, 60u8)   // '<'
        let gt = lastIndexOfByte(t, 62u8) // '>'
        if (let Some(l) <- lt) {
            if (let Some(g) <- gt) {
                if (g > l) {
                    let elemTy = t[l + 1..g].trimAscii()
                    return SqlColType.TArray(cjTypeToSqlColType(elemTy))
                }
            }
        }
    }
    // 默认 TEXT
    return SqlColType.TText
}

// indexOfByte/lastIndexOfByte 在 conninfo.cj(postgresql-driver) 中，本包另定义。
func indexOfByte(s: String, b: UInt8): ?Int64 {
    let a = s.toArray()
    for (i in 0..a.size) {
        if (a[i] == b) { return Some(i) }
    }
    None
}
func lastIndexOfByte(s: String, b: UInt8): ?Int64 {
    let a = s.toArray()
    var i = a.size - 1
    while (i >= 0) {
        if (a[i] == b) { return Some(i) }
        i -= 1
    }
    None
}

/**
 * 列元数据(对标 sea-orm ColumnDef)：DDL 侧的列定义。
 */
public class ColumnDef {
    public var name: String
    public var colType: SqlColType
    public var nullable: Bool = true
    public var unique: Bool = false
    public var indexed: Bool = false
    public var primaryKey: Bool = false
    public var autoIncrement: Bool = false
    public var defaultValue: ?String = None   // 原始 SQL 表达式
    public var comment: ?String = None

    public init(name: String, colType: SqlColType) {
        this.name = name
        this.colType = colType
    }

    public func notNull(): ColumnDef { nullable = false; this }
    public func setUnique(): ColumnDef { unique = true; this }
    public func setIndexed(): ColumnDef { indexed = true; this }
    public func setPk(): ColumnDef { primaryKey = true; nullable = false; this }
    public func setAutoIncrement(): ColumnDef { autoIncrement = true; this }
    public func setDefault(expr: String): ColumnDef { defaultValue = Some(expr); this }
    public func setComment(c: String): ColumnDef { comment = Some(c); this }

    /** 渲染为 CREATE TABLE 中的列定义片段(不含外层逗号)。 */
    public func toColumnSql(): String {
        var s = quoteIdent(name) + " " + sqlColTypeToPg(colType)
        if (!nullable) {
            s += " NOT NULL"
        }
        if (primaryKey) {
            s += " PRIMARY KEY"
        }
        if (unique && !primaryKey) {
            s += " UNIQUE"
        }
        match (defaultValue) {
            case Some(expr) => s += " DEFAULT " + expr
            case None => ()
        }
        s
    }
}

/**
 * Schema：按 backend(先 PG)产出 DDL 文本。
 * 从 Entity 的列元数据(经 columnDefs())生成 CREATE TABLE。
 */
public class Schema {
    public init() {}

    /**
     * 从 Entity 生成 CREATE TABLE SQL。
     * 依赖 Entity.columnDefs() 返回列元数据；若 Entity 未实现 columnDefs()(默认空)，
     * 则从 columns()/pkColumns()/autoIncrement() 推导一个基础 DDL。
     */
    public func createTableFromEntity(e: Entity): String {
        let colDefs = e.columnDefs()
        if (colDefs.size > 0) {
            return createTableFromDefs(e, colDefs)
        }
        // 回退：从 columns/pkColumns 推导(无类型信息时用 TEXT 兜底)
        let cols = e.columns()
        let pkCols = e.pkColumns()
        let defs = Array<ColumnDef>(cols.size, { i =>
            let cd = ColumnDef(cols[i], SqlColType.TText)
            if (pkCols.contains(cols[i])) {
                cd.setPk()
                if (e.autoIncrement() && i == 0) {
                    cd.colType = SqlColType.TSerial64
                }
            }
            cd
        })
        createTableFromDefs(e, defs)
    }

    /** 从显式 ColumnDef 列表生成 CREATE TABLE。 */
    public func createTableFromDefs(e: Entity, defs: Array<ColumnDef>): String {
        let sb = StringBuilder()
        sb.append("CREATE TABLE ")
        match (e.schema()) {
            case Some(s) => sb.append(quoteTable(Some(s), e.table()))
            case None => sb.append(quoteTable(None, e.table()))
        }
        sb.append(" (")
        let parts = ArrayList<String>()
        for (cd in defs) {
            parts.add(cd.toColumnSql())
        }
        // 复合主键(若多列 pk 且未在列定义上标 PRIMARY KEY)
        var pkCount = 0
        for (cd in defs) {
            if (cd.primaryKey) { pkCount += 1 }
        }
        if (pkCount > 1) {
            let pks = ArrayList<String>()
            for (cd in defs) {
                if (cd.primaryKey) {
                    pks.add(quoteIdent(cd.name))
                }
            }
            // 移除各列上的 PRIMARY KEY(改为表级)
            // 简化：直接追加表级约束
            parts.add("PRIMARY KEY (" + joinComma(pks.toArray()) + ")")
        }
        sb.append(joinComma(parts.toArray()))
        sb.append(")")
        sb.toString()
    }

    /** DROP TABLE IF EXISTS。 */
    public func dropTable(e: Entity): String {
        match (e.schema()) {
            case Some(s) => "DROP TABLE IF EXISTS " + quoteTable(Some(s), e.table())
            case None => "DROP TABLE IF EXISTS " + quoteTable(None, e.table())
        }
    }

    /**
     * CREATE TYPE(用于枚举/自定义类型)。typeName 为 PG 枚举类型名，values 为枚举成员。
     * 产出：CREATE TYPE "typeName" AS ENUM ('v1','v2',...)
     */
    public func createEnumType(typeName: String, values: Array<String>): String {
        let parts = ArrayList<String>()
        for (v in values) {
            parts.add("'" + v.replace("'", "''") + "'")
        }
        "CREATE TYPE " + quoteIdent(typeName) + " AS ENUM (" + joinComma(parts.toArray()) + ")"
    }

    public func dropEnumType(typeName: String): String {
        "DROP TYPE IF EXISTS " + quoteIdent(typeName)
    }
}

/**
 * SchemaBuilder：链式构造 DDL 批次，build() 返回 SQL 字符串数组(按顺序执行)。
 */
public class SchemaBuilder {
    let schema: Schema
    let stmts = ArrayList<String>()

    public init() {
        schema = Schema()
    }

    /** 注册一个 entity 的 CREATE TABLE。 */
    public func table(e: Entity): SchemaBuilder {
        stmts.add(schema.createTableFromEntity(e))
        this
    }

    /** DROP 一个 entity。 */
    public func dropTable(e: Entity): SchemaBuilder {
        stmts.add(schema.dropTable(e))
        this
    }

    /** 创建枚举类型。 */
    public func createType(typeName: String, values: Array<String>): SchemaBuilder {
        stmts.add(schema.createEnumType(typeName, values))
        this
    }

    /** 删除枚举类型。 */
    public func dropType(typeName: String): SchemaBuilder {
        stmts.add(schema.dropEnumType(typeName))
        this
    }

    /** 追加原始 SQL。 */
    public func rawSql(sql: String): SchemaBuilder {
        stmts.add(sql)
        this
    }

    /** 产出全部 SQL 语句(按添加顺序)。 */
    public func build(): Array<String> {
        stmts.toArray()
    }
}

// ===== Entity.columnDefs() 默认实现 =====
// 已在 entity.cj 的 Entity 接口追加 columnDefs() 默认空实现。
// 宏生成体可覆盖：按字段类型 + @[column] 属性派生 ColumnDef 列表。

// ===== EntityRegistry(显式注册，无 inventory 机制) =====

/**
 * Entity 注册表：显式 register(对标 sea-orm EntityRegistry，但仓颉无 inventory，
 * 改为运行时显式注册)。供 Database.syncSchema 收集全部 entity 的 DDL。
 */
public class EntityRegistry {
    static let entities = ArrayList<Entity>()
    static let mu = Mutex()

    /** 注册一个 entity(幂等，按 table+schema 去重)。 */
    public static func register(e: Entity): Unit {
        synchronized(mu) {
            for (existing in entities) {
                if (existing.table() == e.table() && existing.schema() == e.schema()) {
                    return
                }
            }
            entities.add(e)
        }
    }

    /** 取全部已注册 entity。 */
    public static func all(): Array<Entity> {
        synchronized(mu) {
            entities.toArray()
        }
    }

    /** 清空(测试用)。 */
    public static func clear(): Unit {
        synchronized(mu) {
            entities.clear()
        }
    }
}

// ===== Database.syncSchema =====

/**
 * 同步 schema：DROP IF EXISTS + CREATE，按注册顺序执行。
 * - dropFirst=true 时先 DROP 全部(逆序)，再 CREATE。
 * - 返回 (成功?, 执行的 SQL 列表)。
 */
public func syncSchema(db: Database, dropFirst!: Bool = false): (Bool, Array<String>) {
    let schema = Schema()
    let executed = ArrayList<String>()
    let all = EntityRegistry.all()
    try {
        if (dropFirst) {
            // 逆序 DROP
            for (i in 0..all.size) {
                let e = all[all.size - 1 - i]
                let sql = schema.dropTable(e)
                db.execRawSql(sql)
                executed.add(sql)
            }
        }
        for (e in all) {
            let sql = schema.createTableFromEntity(e)
            db.execRawSql(sql)
            executed.add(sql)
        }
        (true, executed.toArray())
    } catch (e: Exception) {
        (false, executed.toArray())
    }
}

// ===== codegen：从 PG information_schema 反向生成 @Entity struct 源文本 =====

/**
 * codegen 列信息(从 information_schema.columns 读取)。
 */
public class CodegenColumn {
    public let name: String
    public let dataType: String       // information_schema.data_type
    public let isNullable: Bool
    public let isIdentity: Bool       // identity 列(自增主键)
    public let charLen: Int64         // character_maximum_length
    public let numericPrecision: Int64
    public let numericScale: Int64
    public let columnDefault: ?String

    public init(name: String, dataType: String, isNullable: Bool, isIdentity: Bool,
        charLen: Int64, numericPrecision: Int64, numericScale: Int64, columnDefault: ?String) {
        this.name = name
        this.dataType = dataType
        this.isNullable = isNullable
        this.isIdentity = isIdentity
        this.charLen = charLen
        this.numericPrecision = numericPrecision
        this.numericScale = numericScale
        this.columnDefault = columnDefault
    }
}

/**
 * 从 PG information_schema.columns 读取指定表的列元数据。
 * 按 ordinal_position 排序。
 */
public func codegenReadColumns(db: Database, tableName: String): Array<CodegenColumn> {
    let sql = """
        SELECT column_name, data_type, is_nullable, is_identity,
               character_maximum_length, numeric_precision, numeric_scale, column_default
        FROM information_schema.columns
        WHERE table_name = $1 ORDER BY ordinal_position
    """
    let rows = db.raw<Row>(sql, [vtext(tableName)], { r => r })
    let out = ArrayList<CodegenColumn>()
    for (r in rows) {
        let name = r.getText("column_name")
        let dataType = r.getText("data_type")
        let nullable = r.getText("is_nullable") == "YES"
        let identity = r.getText("is_identity") == "YES"
        let charLen = match (r.getOrNullInt64("character_maximum_length")) {
            case Some(v) => v; case None => 0
        }
        let prec = match (r.getOrNullInt64("numeric_precision")) {
            case Some(v) => v; case None => 0
        }
        let scale = match (r.getOrNullInt64("numeric_scale")) {
            case Some(v) => v; case None => 0
        }
        let dft = r.getOrNullText("column_default")
        out.add(CodegenColumn(name, dataType, nullable, identity, charLen, prec, scale, dft))
    }
    out.toArray()
}

/**
 * PG data_type → 仓颉类型文本(用于生成 struct 字段)。
 */
func pgDataTypeToCjType(dt: String, nullable: Bool, charLen: Int64): String {
    let base = match (dt) {
        case "boolean" => "Bool"
        case "smallint" => "Int16"
        case "integer" => "Int32"
        case "bigint" => "Int64"
        case "real" => "Float32"
        case "double precision" => "Float64"
        case "numeric" | "decimal" => "Float64"  // 简化：Decimal 待阶段五
        case "text" | "character varying" | "character" => "String"
        case "bytea" => "Array<UInt8>"
        case "uuid" => "String"
        case "json" | "jsonb" => "String"
        case "date" => "String"  // 待阶段五类型化
        case "timestamp" | "timestamp with time zone" | "time" | "time with time zone" => "String"
        case "integer[]" | "bigint[]" | "smallint[]" => "Array<Int64>"
        case "text[]" | "character varying[]" | "character[]" => "Array<String>"
        case _ => "String"  // 未知类型兜底为 String
    }
    if (nullable) {
        "?" + base
    } else {
        base
    }
}

/**
 * 蛇形命名(snake_case) → 驼峰命名(camelCase)。
 */
func snakeToCamel(s: String): String {
    let bytes = s.toArray()
    let out = ArrayList<UInt8>()
    var upperNext = false
    for (i in 0..bytes.size) {
        let b = bytes[i]
        if (b == 95u8) { // '_'
            upperNext = true
        } else if (upperNext) {
            if (b >= 97u8 && b <= 122u8) {
                out.add(b - 32u8)
            } else {
                out.add(b)
            }
            upperNext = false
        } else {
            out.add(b)
        }
    }
    String.fromUtf8(out.toArray())
}

/**
 * 从 PG 反向生成 @Entity struct 源文本(可直接写入 .cj 文件)。
 * tableName：DB 表名；structName：生成的仓颉 struct 名。
 */
public func codegenEntityFromPg(db: Database, tableName: String, structName: String): String {
    let cols = codegenReadColumns(db, tableName)
    let sb = StringBuilder()
    sb.append("@entity[table = \"")
    sb.append(tableName)
    sb.append("\"]\n")
    sb.append("public struct ")
    sb.append(structName)
    sb.append(" {\n")
    for (c in cols) {
        let fieldName = snakeToCamel(c.name)
        let cjType = pgDataTypeToCjType(c.dataType, c.isNullable, c.charLen)
        // 主键标记：identity 列 或 列名 id 且整数类型
        let isPk = c.isIdentity || (c.name == "id" && (c.dataType == "integer" || c.dataType == "bigint" || c.dataType == "smallint"))
        let isAuto = c.isIdentity
        if (isPk) {
            if (isAuto) {
                sb.append("    @pk[auto]\n")
            } else {
                sb.append("    @pk[]\n")
            }
        }
        // column 别名(若字段名与列名不同)
        if (fieldName != c.name) {
            sb.append("    @column[name = \"")
            sb.append(c.name)
            sb.append("\"]\n")
        }
        sb.append("    public var ")
        sb.append(fieldName)
        sb.append(": ")
        sb.append(cjType)
        // 默认值
        if (c.isNullable) {
            sb.append(" = None")
        } else if (cjType == "String") {
            sb.append(" = \"\"")
        } else if (cjType.startsWith("Array")) {
            sb.append(" = ")
            sb.append(cjType)
            sb.append("()")
        } else if (cjType == "Bool") {
            sb.append(" = false")
        } else {
            sb.append(" = 0")
        }
        sb.append("\n")
    }
    sb.append("}\n")
    sb.toString()
}