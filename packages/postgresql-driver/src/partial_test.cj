package postgresql_driver

/**
 * 阶段六测试：PartialModel、FromQueryResult、DynamicEntity。
 */
import csorm.*
import csorm
import std.unittest.*
import std.unittest.testmacro.*
import std.env.getVariable
import std.collection.*

func pmConnStr(): String {
    getVariable("DB_STRING") ??
        "postgres://copur:e29khrowY77mGk@192.168.0.112:5432/lanludev?sslmode=disable&pool.max=5"
}

func openPmOrSkip(): ?Database {
    try {
        return Some(Database(PgConn(pmConnStr())))
    } catch (_: Exception) {
        println("[skip] no PostgreSQL available (partial test)")
        return None
    }
}

// PartialModel：只取 id + name 两列
public struct ArchiveListRow {
    public var id: Int64 = 0
    public var name: String = ""
    public init() {}
}

public class ArchiveListRowPartial <: PartialModel {
    public init() {}
    public func columns(): Array<String> { ["id", "name"] }
    public func fromRow(r: Row): Any {
        let row = ArchiveListRow()
        var out = row
        out.id = r.getInt64("id")
        out.name = r.getText("name")
        out
    }
}

// FromQueryResult：统计结果映射
public struct CountResult {
    public var total: Int64 = 0
    public init() {}
}

public class CountResultMapper <: FromQueryResult {
    public init() {}
    public func fromRow(r: Row): Any {
        let cr = CountResult()
        var out = cr
        out.total = r.getInt64(0)
        out
    }
}

// FromQueryResult：多列聚合
public struct StatsResult {
    public var total: Int64 = 0
    public var avgAge: Float64 = 0.0
    public var maxAge: Int64 = 0
    public init() {}
}

public class StatsResultMapper <: FromQueryResult {
    public init() {}
    public func fromRow(r: Row): Any {
        let sr = StatsResult()
        var out = sr
        out.total = r.getInt64(0)
        out.avgAge = r.getFloat64(1)
        out.maxAge = r.getInt64(2)
        out
    }
}

@Test
func test_partial_model_select() {
    match (openPmOrSkip()) {
        case None => return
        case Some(db) =>
            db.execRawSql("DROP TABLE IF EXISTS csorm_pm_test")
            db.execRawSql("CREATE TABLE csorm_pm_test (id SERIAL PRIMARY KEY, name TEXT NOT NULL, bio TEXT, tags TEXT[])")
            db.execRaw("INSERT INTO csorm_pm_test (name, bio, tags) VALUES ($1, $2, $3)",
                [vtext("alice"), vtext("long bio..."), textArray(["a", "b"])])
            db.execRaw("INSERT INTO csorm_pm_test (name, bio, tags) VALUES ($1, $2, $3)",
                [vtext("bob"), vtext("another bio"), textArray(["c"])])

            // PartialModel：只 SELECT id, name(不取 bio/tags)
            let pm = ArchiveListRowPartial()
            let base = selectQuery("csorm_pm_test")
            intoPartialModel(base, pm)
            let (sql, params) = base.build()
            @Expect(sql.contains("\"id\""), true)
            @Expect(sql.contains("\"name\""), true)
            @Expect(sql.contains("bio"), false)  // 不应包含 bio 列

            let rows = db.raw<ArchiveListRow>(sql, params, { r =>
                match (pm.fromRow(r) as ArchiveListRow) {
                    case Some(x) => x
                    case None => ArchiveListRow()
                }
            })
            @Expect(rows.size, 2)
            @Expect(rows[0].name, "alice")
            @Expect(rows[1].name, "bob")
            // id 应有值
            @Expect(rows[0].id > 0, true)

            db.execRawSql("DROP TABLE IF EXISTS csorm_pm_test")
            db.close()
            println("[partial-test] PartialModel select passed")
    }
}

@Test
func test_from_query_result_count() {
    match (openPmOrSkip()) {
        case None => return
        case Some(db) =>
            db.execRawSql("DROP TABLE IF EXISTS csorm_fqr_test")
            db.execRawSql("CREATE TABLE csorm_fqr_test (id SERIAL PRIMARY KEY, age INT8 NOT NULL)")
            db.execRaw("INSERT INTO csorm_fqr_test (age) VALUES ($1)", [vint(20)])
            db.execRaw("INSERT INTO csorm_fqr_test (age) VALUES ($1)", [vint(30)])
            db.execRaw("INSERT INTO csorm_fqr_test (age) VALUES ($1)", [vint(40)])

            // FromQueryResult：COUNT(*) 直查
            let mapper = CountResultMapper()
            let result = db.rawQueryOne<CountResult>("SELECT COUNT(*)::int8 FROM csorm_fqr_test", [], mapper)
            match (result) {
                case Some(cr) => @Expect(cr.total, 3)
                case None => @Expect(true, false)
            }

            // 多列聚合：COUNT, AVG, MAX
            let statsMapper = StatsResultMapper()
            let stats = db.rawQueryOne<StatsResult>(
                "SELECT COUNT(*)::int8, AVG(age)::float8, MAX(age)::int8 FROM csorm_fqr_test", [], statsMapper)
            match (stats) {
                case Some(s) =>
                    @Expect(s.total, 3)
                    @Expect(s.avgAge > 29.0 && s.avgAge < 31.0, true)  // avg = 30
                    @Expect(s.maxAge, 40)
                case None => @Expect(true, false)
            }

            db.execRawSql("DROP TABLE IF EXISTS csorm_fqr_test")
            db.close()
            println("[partial-test] FromQueryResult count/stats passed")
    }
}

@Test
func test_dynamic_entity() {
    match (openPmOrSkip()) {
        case None => return
        case Some(db) =>
            db.execRawSql("DROP TABLE IF EXISTS csorm_dyn_test")
            db.execRawSql("CREATE TABLE csorm_dyn_test (id INT8 PRIMARY KEY, name TEXT NOT NULL, active BOOL NOT NULL DEFAULT true)")

            db.execRaw("INSERT INTO csorm_dyn_test (id, name, active) VALUES ($1, $2, $3)",
                [vint(1), vtext("alice"), vbool(true)])
            db.execRaw("INSERT INTO csorm_dyn_test (id, name, active) VALUES ($1, $2, $3)",
                [vint(2), vtext("bob"), vbool(false)])

            // 动态实体：运行时定义列
            let dyn = DynamicEntity("csorm_dyn_test", None,
                ["id", "name", "active"],
                [ColType.TInt, ColType.TText, ColType.TBool])
            let q = dyn.select()
            let (sql, params) = q.build()
            let rows = db.raw<csorm.Row>(sql, params, { r => r })

            @Expect(rows.size, 2)
            let models = ArrayList<DynamicModel>()
            for (r in rows) {
                models.add(dyn.fromRow(r))
            }
            // 第一行：id=1, name=alice, active=true
            @Expect(models[0].getInt64("id").getOrThrow(), 1)
            @Expect(models[0].getText("name").getOrThrow(), "alice")
            @Expect(models[0].getBool("active").getOrThrow(), true)
            // 第二行
            @Expect(models[1].getText("name").getOrThrow(), "bob")
            @Expect(models[1].getBool("active").getOrThrow(), false)

            // toStringMap
            let sm = models[0].toStringMap()
            @Expect(sm.get("name").getOrThrow(), "alice")

            db.execRawSql("DROP TABLE IF EXISTS csorm_dyn_test")
            db.close()
            println("[partial-test] DynamicEntity passed")
    }
}