package postgresql_driver

/**
 * 阶段四迁移框架测试：验证 Migrator up/down/refresh/status + schema_migrations 元表。
 */
import csorm.*
import csorm
import std.unittest.*
import std.unittest.testmacro.*
import std.env.getVariable
import std.collection.*

func migConnStr(): String {
    getVariable("DB_STRING") ??
        "postgres://copur:e29khrowY77mGk@192.168.0.112:5432/lanludev?sslmode=disable&pool.max=5"
}

func openMigOrSkip(): ?Database {
    try {
        return Some(Database(PgConn(migConnStr())))
    } catch (_: Exception) {
        println("[skip] no PostgreSQL available (migration test)")
        return None
    }
}

// 测试迁移 V001：建表
public class MigV001 <: CsormMigration {
    public init() {}
    public func version(): String { "V001" }
    public func description(): String { "create csorm_mig_test_a" }
    public func up(mgr: SchemaManager): Unit {
        mgr.execSql("CREATE TABLE csorm_mig_test_a (id SERIAL PRIMARY KEY, name TEXT NOT NULL)")
    }
    public func down(mgr: SchemaManager): Unit {
        mgr.execSql("DROP TABLE IF EXISTS csorm_mig_test_a")
    }
}

// 测试迁移 V002：加列
public class MigV002 <: CsormMigration {
    public init() {}
    public func version(): String { "V002" }
    public func description(): String { "add age column" }
    public func up(mgr: SchemaManager): Unit {
        mgr.execSql("ALTER TABLE csorm_mig_test_a ADD COLUMN age INT8 NOT NULL DEFAULT 0")
    }
    public func down(mgr: SchemaManager): Unit {
        mgr.execSql("ALTER TABLE csorm_mig_test_a DROP COLUMN IF EXISTS age")
    }
}

// 测试迁移 V003：建第二张表
public class MigV003 <: CsormMigration {
    public init() {}
    public func version(): String { "V003" }
    public func description(): String { "create csorm_mig_test_b" }
    public func up(mgr: SchemaManager): Unit {
        mgr.execSql("CREATE TABLE csorm_mig_test_b (id SERIAL PRIMARY KEY, a_id INT8 NOT NULL)")
    }
    public func down(mgr: SchemaManager): Unit {
        mgr.execSql("DROP TABLE IF EXISTS csorm_mig_test_b")
    }
}

@Test
func test_migrator_up_and_status() {
    match (openMigOrSkip()) {
        case None => return
        case Some(db) =>
            // 清理
            db.execRawSql("DROP TABLE IF EXISTS csorm_mig_test_b")
            db.execRawSql("DROP TABLE IF EXISTS csorm_mig_test_a")
            db.execRawSql("DROP TABLE IF EXISTS schema_migrations")

            let mig = Migrator(db)
            let migrations: Array<CsormMigration> = [MigV003(), MigV001(), MigV002()]  // 乱序，应自动排序
            let applied = mig.up(migrations)
            // 应按 V001 < V002 < V003 顺序应用
            @Expect(applied.size, 3)
            @Expect(applied[0], "V001")
            @Expect(applied[1], "V002")
            @Expect(applied[2], "V003")

            // status：全部已应用
            let statuses = mig.status(migrations)
            @Expect(statuses.size, 3)
            for (s in statuses) {
                @Expect(s.applied, true)
            }
            // pendingCount：0 pending
            let (appliedN, pendingN) = mig.pendingCount(migrations)
            @Expect(appliedN, 3)
            @Expect(pendingN, 0)

            // 验证表与列存在
            db.execRaw("INSERT INTO csorm_mig_test_a (name, age) VALUES ($1, $2)", [vtext("alice"), vint(30)])
            let rows = db.raw<csorm.Row>("SELECT name, age FROM csorm_mig_test_a", [], { r => r })
            @Expect(rows.size, 1)
            @Expect(rows[0].getText("name"), "alice")
            @Expect(rows[0].getInt64("age"), 30)

            // 幂等：再次 up 应无新应用
            let applied2 = mig.up(migrations)
            @Expect(applied2.size, 0)

            db.execRawSql("DROP TABLE IF EXISTS csorm_mig_test_b")
            db.execRawSql("DROP TABLE IF EXISTS csorm_mig_test_a")
            db.execRawSql("DROP TABLE IF EXISTS schema_migrations")
            db.close()
            println("[mig-test] up + status passed")
    }
}

@Test
func test_migrator_down() {
    match (openMigOrSkip()) {
        case None => return
        case Some(db) =>
            db.execRawSql("DROP TABLE IF EXISTS csorm_mig_test_b")
            db.execRawSql("DROP TABLE IF EXISTS csorm_mig_test_a")
            db.execRawSql("DROP TABLE IF EXISTS schema_migrations")

            let mig = Migrator(db)
            let migrations: Array<CsormMigration> = [MigV001(), MigV002(), MigV003()]
            mig.up(migrations)
            // 回滚最后 1 个(V003)
            let rolled = mig.down(migrations)
            @Expect(rolled.size, 1)
            @Expect(rolled[0], "V003")
            // V003 表应已删除，V001/V002 仍在
            let (appliedN, pendingN) = mig.pendingCount(migrations)
            @Expect(appliedN, 2)
            @Expect(pendingN, 1)  // V003 待重新应用

            // 回滚 2 个(V002, V001)
            let rolled2 = mig.down(migrations, n: 2)
            @Expect(rolled2.size, 2)
            @Expect(rolled2[0], "V002")
            @Expect(rolled2[1], "V001")
            // 全部回滚，元表为空
            let applied = mig.appliedVersions()
            @Expect(applied.size, 0)

            db.execRawSql("DROP TABLE IF EXISTS csorm_mig_test_b")
            db.execRawSql("DROP TABLE IF EXISTS csorm_mig_test_a")
            db.execRawSql("DROP TABLE IF EXISTS schema_migrations")
            db.close()
            println("[mig-test] down passed")
    }
}

@Test
func test_migrator_refresh() {
    match (openMigOrSkip()) {
        case None => return
        case Some(db) =>
            db.execRawSql("DROP TABLE IF EXISTS csorm_mig_test_b")
            db.execRawSql("DROP TABLE IF EXISTS csorm_mig_test_a")
            db.execRawSql("DROP TABLE IF EXISTS schema_migrations")

            let mig = Migrator(db)
            let migrations: Array<CsormMigration> = [MigV001(), MigV002(), MigV003()]
            mig.up(migrations)
            // refresh：回滚全部 + 重新应用
            let (rolledBack, reApplied) = mig.refresh(migrations)
            @Expect(rolledBack.size, 3)
            @Expect(reApplied.size, 3)
            // 全部已应用
            let (appliedN, pendingN) = mig.pendingCount(migrations)
            @Expect(appliedN, 3)
            @Expect(pendingN, 0)

            db.execRawSql("DROP TABLE IF EXISTS csorm_mig_test_b")
            db.execRawSql("DROP TABLE IF EXISTS csorm_mig_test_a")
            db.execRawSql("DROP TABLE IF EXISTS schema_migrations")
            db.close()
            println("[mig-test] refresh passed")
    }
}

// 测试迁移 VE001：用 SchemaManager.createTable(Entity) 验证与阶段二联动
public class MigEntityEntity <: Entity {
    public init() {}
    public func table(): String { "csorm_mig_entity_demo" }
    public func schema(): ?String { None }
    public func columns(): Array<String> { ["id", "name"] }
    public func pkColumns(): Array<String> { ["id"] }
    public func autoIncrement(): Bool { true }
    public func fromRow(r: Row): Any { 0 }
    public func emptyActive(): ActiveModel { SchemaDemoActive() }
}

public class MigEntityV001 <: CsormMigration {
    public init() {}
    public func version(): String { "VE001" }
    public func description(): String { "create via Entity" }
    public func up(mgr: SchemaManager): Unit {
        mgr.createTable(MigEntityEntity())
    }
    public func down(mgr: SchemaManager): Unit {
        mgr.execSql("DROP TABLE IF EXISTS csorm_mig_entity_demo")
    }
}

@Test
func test_migrator_uses_entity_schema() {
    match (openMigOrSkip()) {
        case None => return
        case Some(db) =>
            db.execRawSql("DROP TABLE IF EXISTS csorm_mig_entity_demo")
            db.execRawSql("DROP TABLE IF EXISTS schema_migrations")

            // 用 SchemaManager.createTable(Entity) 验证与阶段二联动
            let mig = Migrator(db)
            let migrations: Array<CsormMigration> = [MigEntityV001()]
            let applied = mig.up(migrations)
            @Expect(applied.size, 1)
            // 验证表存在
            db.execRaw("INSERT INTO csorm_mig_entity_demo (name) VALUES ($1)", [vtext("test")])
            let rows = db.raw<csorm.Row>("SELECT name FROM csorm_mig_entity_demo", [], { r => r })
            @Expect(rows.size, 1)
            @Expect(rows[0].getText("name"), "test")

            db.execRawSql("DROP TABLE IF EXISTS csorm_mig_entity_demo")
            db.execRawSql("DROP TABLE IF EXISTS schema_migrations")
            db.close()
            println("[mig-test] uses entity schema passed")
    }
}