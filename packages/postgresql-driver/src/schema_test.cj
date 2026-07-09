package postgresql_driver

/**
 * 阶段二 Schema/DDL 测试：验证从 Entity 产出 CREATE TABLE、SchemaBuilder、
 * EntityRegistry + syncSchema，以及 codegen(从 PG information_schema 反向生成)。
 */
import csorm.*
import csorm
import std.unittest.*
import std.unittest.testmacro.*
import std.env.getVariable
import std.collection.*
import csorm_macros.*

func schemaConnStr(): String {
    getVariable("DB_STRING") ??
        "postgres://copur:e29khrowY77mGk@192.168.0.112:5432/lanludev?sslmode=disable&pool.max=5"
}

func openSchemaOrSkip(): ?Database {
    try {
        return Some(Database(PgConn(schemaConnStr())))
    } catch (_: Exception) {
        println("[skip] no PostgreSQL available (schema test)")
        return None
    }
}

// 带显式 columnDefs 的 Entity(手写实现 columnDefs())
@entity[table = "csorm_schema_demo"]
public struct SchemaDemo {
    @pk[auto]
    public var id: Int64 = 0
    public var name: String = ""
    public var age: Int64 = 0
    public var active: Bool = true
    public var bio: ?String = None
}

// 手写一个 Entity 子类覆盖 columnDefs()，演示从 Entity 产出类型化 DDL。
public class SchemaDemoEntityTyped <: Entity {
    public init() {}
    public func table(): String { "csorm_schema_typed_demo" }
    public func schema(): ?String { None }
    public func columns(): Array<String> { ["id", "name", "age", "active", "bio"] }
    public func pkColumns(): Array<String> { ["id"] }
    public func autoIncrement(): Bool { true }
    public func fromRow(r: Row): Any { SchemaDemo() }
    public func emptyActive(): ActiveModel { SchemaDemoActive() }
    public func columnDefs(): Array<ColumnDef> {
        let id = ColumnDef("id", SqlColType.TSerial64).setPk()
        let name = ColumnDef("name", SqlColType.TStringN(255)).notNull()
        let age = ColumnDef("age", SqlColType.TInt64).notNull().setDefault("0")
        let active = ColumnDef("active", SqlColType.TBool).notNull().setDefault("true")
        let bio = ColumnDef("bio", SqlColType.TText)
        [id, name, age, active, bio]
    }
}

@Test
func test_schema_create_table_sql() {
    let schema = Schema()
    let e = SchemaDemoEntityTyped()
    let sql = schema.createTableFromEntity(e)
    // 校验关键片段
    @Expect(sql.contains("CREATE TABLE"), true)
    @Expect(sql.contains("\"csorm_schema_typed_demo\""), true)
    @Expect(sql.contains("\"id\" BIGSERIAL"), true)
    @Expect(sql.contains("PRIMARY KEY"), true)
    @Expect(sql.contains("\"name\" VARCHAR(255) NOT NULL"), true)
    @Expect(sql.contains("\"age\" INT8 NOT NULL DEFAULT 0"), true)
    @Expect(sql.contains("\"active\" BOOLEAN NOT NULL DEFAULT true"), true)
    @Expect(sql.contains("\"bio\" TEXT"), true)
    println("[schema-test] createTableFromEntity SQL: " + sql)
    println("[schema-test] create_table_sql passed")
}

@Test
func test_schema_create_enum_type() {
    let schema = Schema()
    let sql = schema.createEnumType("csorm_status", ["pending", "running", "done"])
    @Expect(sql, "CREATE TYPE \"csorm_status\" AS ENUM ('pending', 'running', 'done')")
    let dropSql = schema.dropEnumType("csorm_status")
    @Expect(dropSql, "DROP TYPE IF EXISTS \"csorm_status\"")
    println("[schema-test] create_enum_type passed")
}

@Test
func test_schema_builder_and_sync() {
    match (openSchemaOrSkip()) {
        case None => return
        case Some(db) =>
            EntityRegistry.clear()
            EntityRegistry.register(SchemaDemoEntityTyped())
            // syncSchema with dropFirst
            let (ok, sqls) = syncSchema(db, dropFirst: true)
            @Expect(ok, true)
            @Expect(sqls.size >= 2, true)  // DROP + CREATE
            // 验证表存在：插入并查询
            let ins = insertQuery("csorm_schema_typed_demo")
                .columns(["name", "age", "active"])
                .values([vtext("alice"), vint(30), vbool(true)])
                .returning(["id", "name", "age", "active", "bio"])
            let rows = db.execReturning<SchemaDemo>(ins,
                { r => (schemaDemoEntity().fromRow(r) as SchemaDemo).getOrThrow() })
            @Expect(rows.size, 1)
            @Expect(rows[0].name, "alice")
            @Expect(rows[0].age, 30)
            @Expect(rows[0].active, true)
            // bio 应为 None(未插入)
            @Expect(rows[0].bio.isSome(), false)
            // 清理
            db.execRawSql("DROP TABLE IF EXISTS csorm_schema_typed_demo")
            EntityRegistry.clear()
            db.close()
            println("[schema-test] builder + syncSchema passed")
    }
}

@Test
func test_schema_codegen_from_pg() {
    match (openSchemaOrSkip()) {
        case None => return
        case Some(db) =>
            // 先建一张表
            db.execRawSql("DROP TABLE IF EXISTS csorm_codegen_demo")
            db.execRawSql("CREATE TABLE csorm_codegen_demo (id SERIAL PRIMARY KEY, title TEXT NOT NULL, score INT8 NOT NULL DEFAULT 0, created_at TIMESTAMPTZ NOT NULL DEFAULT now())")
            // codegen：从 information_schema 读取列 → 输出 @Entity struct 源文本
            let source = codegenEntityFromPg(db, "csorm_codegen_demo", "CodegenDemo")
            @Expect(source.contains("@entity[table = \"csorm_codegen_demo\"]"), true)
            @Expect(source.contains("public struct CodegenDemo"), true)
            @Expect(source.contains("@pk[]"), true)
            @Expect(source.contains("public var id: Int32 = 0"), true)
            @Expect(source.contains("public var title: String = \"\""), true)
            @Expect(source.contains("public var score: Int64 = 0"), true)
            @Expect(source.contains("@column[name = \"created_at\"]"), true)
            @Expect(source.contains("public var createdAt: String = \"\""), true)
            println("[schema-test] codegen source:\n" + source)
            db.execRawSql("DROP TABLE IF EXISTS csorm_codegen_demo")
            db.close()
            println("[schema-test] codegen_from_pg passed")
    }
}