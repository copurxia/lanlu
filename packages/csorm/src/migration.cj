package csorm

/**
 * 迁移框架(对标 sea-orm-migration)。
 *
 * - CsormMigration：接口，每个迁移实现 up()/down() + version()/description()。
 * - SchemaManager：迁移内的执行入口，包装 Database，提供 execSql/createTable/dropTable 等。
 * - Migrator：维护 schema_migrations 元表(version + applied_at)，按顺序应用未执行迁移。
 *   - up(db, migrations)：应用全部待执行的迁移。
 *   - down(db, migrations, n)：回滚最后 n 个迁移(默认 1)。
 *   - refresh(db, migrations)：回滚全部 + 重新应用。
 *   - status(db, migrations)：返回 (已应用数, 待执行数)。
 *
 * 与 lanlu 自建 MigrationRegistry/MigrationRunner 对齐，可逐步替换。
 */
import std.collection.*
import std.convert.*
import std.time.*
import postgresql_driver.*

/**
 * 迁移接口：每个迁移实现 up/down + 元数据。
 * version() 返回唯一版本号(如 "V001" / "20260707_init")，按字典序排序应用。
 */
public interface CsormMigration {
    func version(): String
    func description(): String
    func up(mgr: SchemaManager): Unit
    func down(mgr: SchemaManager): Unit
}

/**
 * 迁移执行管理器：包装 Database，提供迁移内常用的 DDL 执行入口。
 * 每次 up/down 调用传入一个新的 SchemaManager，迁移体内调用其方法执行 SQL。
 */
public class SchemaManager {
    let db: Database

    public init(db: Database) {
        this.db = db
    }

    /** 执行原始 SQL(DDL/DDL 语句)。 */
    public func execSql(sql: String): Unit {
        db.execRawSql(sql)
    }

    /** 执行带参数的原始写语句(返回受影响行数)。 */
    public func execSqlWithParams(sql: String, params: Array<Value>): Int64 {
        db.execRaw(sql, params)
    }

    /** 从 Entity 生成并执行 CREATE TABLE。 */
    public func createTable(e: Entity): Unit {
        let schema = Schema()
        db.execRawSql(schema.createTableFromEntity(e))
    }

    /** DROP TABLE IF EXISTS。 */
    public func dropTable(e: Entity): Unit {
        let schema = Schema()
        db.execRawSql(schema.dropTable(e))
    }

    /** CREATE TYPE(枚举)。 */
    public func createType(typeName: String, values: Array<String>): Unit {
        let schema = Schema()
        db.execRawSql(schema.createEnumType(typeName, values))
    }

    /** DROP TYPE IF EXISTS。 */
    public func dropType(typeName: String): Unit {
        let schema = Schema()
        db.execRawSql(schema.dropEnumType(typeName))
    }

    /** 执行 SchemaBuilder 批次(按顺序执行全部 SQL)。 */
    public func execBatch(sqls: Array<String>): Unit {
        for (sql in sqls) {
            db.execRawSql(sql)
        }
    }

    /** 逃生舱：拿底层 Database(复杂操作)。 */
    public func database(): Database { db }
}

/**
 * 迁移状态信息。
 */
public struct MigrationStatus {
    public let version: String
    public let description: String
    public let applied: Bool

    public init(version: String, description: String, applied: Bool) {
        this.version = version
        this.description = description
        this.applied = applied
    }
}

/**
 * 迁移执行器：维护 schema_migrations 元表，按版本顺序应用/回滚迁移。
 */
public class Migrator {
    let db: Database
    let migrationsTable: String = "schema_migrations"

    public init(db: Database) {
        this.db = db
    }

    /** 用自定义 migrations 表名(默认 schema_migrations)。 */
    public init(db: Database, migrationsTable: String) {
        this.db = db
        // 注意：实例成员赋值仅适用于 var；这里用构造体约束。
        // 简化：仅支持默认表名；如需自定义请直接改 migrationsTable 字段。
    }

    /** 确保 schema_migrations 元表存在。 */
    func ensureMigrationsTable(): Unit {
        db.execRawSql("""
            CREATE TABLE IF NOT EXISTS schema_migrations (
                version TEXT PRIMARY KEY,
                applied_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
            )
        """)
    }

    /** 取已应用的版本集合。 */
    public func appliedVersions(): Array<String> {
        ensureMigrationsTable()
        let rows = db.raw<Row>("SELECT version FROM schema_migrations ORDER BY version", [],
            { r => r })
        let out = ArrayList<String>()
        for (r in rows) {
            out.add(r.getText("version"))
        }
        out.toArray()
    }

    /** 按版本排序的迁移列表(字典序)。 */
    func sortedMigrations(migrations: Array<CsormMigration>): Array<CsormMigration> {
        let arr = ArrayList<CsormMigration>()
        for (m in migrations) { arr.add(m) }
        arr.sortBy(comparator: { a, b =>
            if (a.version() < b.version()) { Ordering.LT }
            else if (a.version() > b.version()) { Ordering.GT }
            else { Ordering.EQ }
        })
        arr.toArray()
    }

    /** 记录应用。 */
    func recordApplied(version: String): Unit {
        db.execRaw("INSERT INTO schema_migrations (version) VALUES ($1)", [vtext(version)])
    }

    /** 删除应用记录。 */
    func removeApplied(version: String): Unit {
        db.execRaw("DELETE FROM schema_migrations WHERE version = $1", [vtext(version)])
    }

    /**
     * 应用全部待执行的迁移。
     * 返回已应用的版本列表。
     */
    public func up(migrations: Array<CsormMigration>): Array<String> {
        ensureMigrationsTable()
        let applied = appliedVersions()
        let appliedSet = HashSet<String>()
        for (v in applied) { appliedSet.add(v) }
        let sorted = sortedMigrations(migrations)
        let newlyApplied = ArrayList<String>()
        for (m in sorted) {
            if (!appliedSet.contains(m.version())) {
                let mgr = SchemaManager(db)
                db.transaction({
                    =>
                    m.up(mgr)
                    recordApplied(m.version())
                })
                newlyApplied.add(m.version())
            }
        }
        newlyApplied.toArray()
    }

    /**
     * 回滚最后 n 个迁移(默认 1)。返回已回滚的版本列表。
     */
    public func down(migrations: Array<CsormMigration>, n!: Int64 = 1): Array<String> {
        ensureMigrationsTable()
        let applied = appliedVersions()
        if (applied.size == 0) {
            return Array<String>()
        }
        let sorted = sortedMigrations(migrations)
        // 取已应用且在迁移列表中的，按版本倒序
        let migrationMap = HashMap<String, CsormMigration>()
        for (m in sorted) { migrationMap[m.version()] = m }
        let toRollback = ArrayList<String>()
        var count = 0
        // applied 已按版本升序；倒序遍历
        for (i in 0..applied.size) {
            let v = applied[applied.size - 1 - i]
            if (count >= n) { break }
            match (migrationMap.get(v)) {
                case Some(m) =>
                    let mgr = SchemaManager(db)
                    db.transaction({
                        =>
                        m.down(mgr)
                        removeApplied(v)
                    })
                    toRollback.add(v)
                    count += 1
                case None => ()  // 元表有但迁移列表无：跳过(或可清理)
            }
        }
        toRollback.toArray()
    }

    /**
     * 回滚全部已应用迁移 + 重新应用。
     */
    public func refresh(migrations: Array<CsormMigration>): (Array<String>, Array<String>) {
        let rolledBack = down(migrations, n: Int64(appliedVersions().size))
        let applied = up(migrations)
        (rolledBack, applied)
    }

    /**
     * 返回迁移状态列表(全部迁移 + 是否已应用)。
     */
    public func status(migrations: Array<CsormMigration>): Array<MigrationStatus> {
        ensureMigrationsTable()
        let applied = appliedVersions()
        let appliedSet = HashSet<String>()
        for (v in applied) { appliedSet.add(v) }
        let sorted = sortedMigrations(migrations)
        Array<MigrationStatus>(sorted.size, { i =>
            MigrationStatus(sorted[i].version(), sorted[i].description(),
                appliedSet.contains(sorted[i].version()))
        })
    }

    /**
     * 返回 (已应用数, 待执行数)。
     */
    public func pendingCount(migrations: Array<CsormMigration>): (Int64, Int64) {
        let applied = appliedVersions()
        let appliedSet = HashSet<String>()
        for (v in applied) { appliedSet.add(v) }
        let sorted = sortedMigrations(migrations)
        var pending = 0
        for (m in sorted) {
            if (!appliedSet.contains(m.version())) { pending += 1 }
        }
        (Int64(applied.size), Int64(pending))
    }
}