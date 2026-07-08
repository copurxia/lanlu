package csorm

/**
 * 阶段一 1.1 宏测试：验证 @Entity 的 @[hasMany]/@[hasOne] 生成 relations() 实现。
 */
import std.unittest.*
import std.unittest.testmacro.*
import std.env.getVariable
import std.collection.*
import postgresql_driver.*
import csorm_macros.*

func rmConnStr(): String {
    getVariable("DB_STRING") ??
        "postgres://copur:e29khrowY77mGk@192.168.0.112:5432/lanludev?sslmode=disable&pool.max=5"
}

func openRmOrSkip(): ?Database {
    try {
        return Some(Database(rmConnStr()))
    } catch (_: Exception) {
        println("[skip] no PostgreSQL available (relation macro test)")
        return None
    }
}

// 父实体：用户
@entity[table = "csorm_rm_user"]
public struct RmUser {
    @pk[auto]
    public var id: Int64 = 0
    public var name: String = ""
    @hasMany[target = "RmPost", to = "user_id"]
    public var posts: Array<Int64> = Array<Int64>()
}

// 子实体：文章(多对一)
@entity[table = "csorm_rm_post"]
public struct RmPost {
    @pk[auto]
    public var id: Int64 = 0
    @column[name = "user_id"]
    public var userId: Int64 = 0
    public var title: String = ""
}

// 一对一：用户档案
@entity[table = "csorm_rm_profile"]
public struct RmProfile {
    @pk[auto]
    public var id: Int64 = 0
    @column[name = "user_id"]
    public var userId: Int64 = 0
    public var bio: String = ""
}

// 父实体带 hasOne
@entity[table = "csorm_rm_user2"]
public struct RmUser2 {
    @pk[auto]
    public var id: Int64 = 0
    public var name: String = ""
    @hasOne[target = "RmProfile", to = "user_id"]
    public var profile: Int64 = 0
}

@Test
func test_relation_macro_has_many() {
    // 验证 RmUserEntity.relations() 生成了 HasMany 关系
    let entity = rmUserEntity()
    let rels = entity.relations()
    @Expect(rels.size, 1)
    match (rels[0].relType) {
        case RelationType.HasMany => @Expect(true, true)
        case _ => @Expect(true, false)
    }
    @Expect(rels[0].fromTable, "csorm_rm_user")
    @Expect(rels[0].toTable, "csorm_rm_post")
    @Expect(rels[0].toCol, "user_id")
    // fromCol = pkColumns[0] = "id"
    @Expect(rels[0].fromCol, "id")
    println("[rel-macro-test] hasMany relations() passed")
}

@Test
func test_relation_macro_has_one() {
    let entity = rmUser2Entity()
    let rels = entity.relations()
    @Expect(rels.size, 1)
    match (rels[0].relType) {
        case RelationType.HasOne => @Expect(true, true)
        case _ => @Expect(true, false)
    }
    @Expect(rels[0].toTable, "csorm_rm_profile")
    @Expect(rels[0].toCol, "user_id")
    println("[rel-macro-test] hasOne relations() passed")
}

@Test
func test_relation_macro_columns_skip_relation_fields() {
    // 关系字段(posts/profile)不应出现在 columns() 中
    let userEntity = rmUserEntity()
    let cols = userEntity.columns()
    @Expect(cols.size, 2)  // id, name (posts 不算列)
    @Expect(cols.contains("id"), true)
    @Expect(cols.contains("name"), true)
    @Expect(cols.contains("posts"), false)

    let user2Entity = rmUser2Entity()
    let cols2 = user2Entity.columns()
    @Expect(cols2.size, 2)  // id, name (profile 不算列)
    @Expect(cols2.contains("profile"), false)
    println("[rel-macro-test] columns skip relation fields passed")
}

@Test
func test_relation_macro_pg_roundtrip() {
    match (openRmOrSkip()) {
        case None => return
        case Some(db) =>
            db.execRawSql("DROP TABLE IF EXISTS csorm_rm_post")
            db.execRawSql("DROP TABLE IF EXISTS csorm_rm_user")
            db.execRawSql("CREATE TABLE csorm_rm_user (id SERIAL PRIMARY KEY, name TEXT NOT NULL)")
            db.execRawSql("CREATE TABLE csorm_rm_post (id SERIAL PRIMARY KEY, user_id INT8 NOT NULL, title TEXT NOT NULL)")

            // 插入 2 个 user
            var userIds = ArrayList<Int64>()
            for (i in 0..2) {
                let ins = insertQuery("csorm_rm_user")
                    .columns(["name"]).values([vtext("u" + i.toString())])
                    .returning(["id", "name"])
                let rows = db.execReturning<RmUser>(ins,
                    { r => (rmUserEntity().fromRow(r) as RmUser).getOrThrow() })
                userIds.add(rows[0].id)
            }
            // 插入 3 个 post：user0 有 2 个，user1 有 1 个
            db.execRaw("INSERT INTO csorm_rm_post (user_id, title) VALUES ($1, $2)",
                [vint(userIds[0]), vtext("p0a")])
            db.execRaw("INSERT INTO csorm_rm_post (user_id, title) VALUES ($1, $2)",
                [vint(userIds[0]), vtext("p0b")])
            db.execRaw("INSERT INTO csorm_rm_post (user_id, title) VALUES ($1, $2)",
                [vint(userIds[1]), vtext("p1a")])

            // 用宏生成的 relations() + loadMany 批量加载
            let users = db.all<RmUser>(
                selectQuery("csorm_rm_user").select(["id", "name"]),
                { r => (rmUserEntity().fromRow(r) as RmUser).getOrThrow() })
            @Expect(users.size, 2)

            let rels = rmUserEntity().relations()
            @Expect(rels.size, 1)
            let result = loadMany<RmPost, RmUser>(db, rels[0], users,
                { u: RmUser => vint(u.id) },
                { r => (rmPostEntity().fromRow(r) as RmPost).getOrThrow() })
            @Expect(result.size, 2)
            @Expect(result[0].size, 2)  // user0 有 2 个 post
            @Expect(result[1].size, 1)  // user1 有 1 个 post
            @Expect(result[0][0].title, "p0a")

            db.execRawSql("DROP TABLE IF EXISTS csorm_rm_post")
            db.execRawSql("DROP TABLE IF EXISTS csorm_rm_user")
            db.close()
            println("[rel-macro-test] PG roundtrip passed")
    }
}

// ===== 阶段二 2.1：宏自动派生 columnDefs() 测试 =====

@entity[table = "csorm_cd_demo"]
public struct CdDemo {
    @pk[auto]
    public var id: Int64 = 0
    public var name: String = ""
    public var age: Int64 = 0
    public var active: Bool = true
    public var bio: ?String = None
    @jsonb[]
    public var meta: String = ""
    public var tags: Array<String> = Array<String>()
}

@Test
func test_macro_column_defs() {
    let e = cdDemoEntity()
    let cds = e.columnDefs()
    // 应有 7 列(不含关系字段)
    @Expect(cds.size, 7)

    // 找 id 列
    var idCd: ?ColumnDef = None
    var nameCd: ?ColumnDef = None
    var activeCd: ?ColumnDef = None
    var bioCd: ?ColumnDef = None
    var metaCd: ?ColumnDef = None
    var tagsCd: ?ColumnDef = None
    for (cd in cds) {
        if (cd.name == "id") { idCd = Some(cd) }
        if (cd.name == "name") { nameCd = Some(cd) }
        if (cd.name == "active") { activeCd = Some(cd) }
        if (cd.name == "bio") { bioCd = Some(cd) }
        if (cd.name == "meta") { metaCd = Some(cd) }
        if (cd.name == "tags") { tagsCd = Some(cd) }
    }

    // id：pk + autoIncrement + notNull(隐含)
    match (idCd) {
        case Some(cd) =>
            @Expect(cd.primaryKey, true)
            @Expect(cd.autoIncrement, true)
        case None => @Expect(true, false)
    }

    // name：TEXT + notNull(非 ?T)
    match (nameCd) {
        case Some(cd) =>
            @Expect(cd.nullable, false)
            @Expect(cd.primaryKey, false)
        case None => @Expect(true, false)
    }

    // active：Bool + notNull
    match (activeCd) {
        case Some(cd) => @Expect(cd.nullable, false)
        case None => @Expect(true, false)
    }

    // bio：?String → nullable
    match (bioCd) {
        case Some(cd) => @Expect(cd.nullable, true)
        case None => @Expect(true, false)
    }

    // meta：jsonb → TJsonb
    match (metaCd) {
        case Some(cd) =>
            // 类型为 TJsonb
            match (cd.colType) {
                case SqlColType.TJsonb => @Expect(true, true)
                case _ => @Expect(true, false)
            }
        case None => @Expect(true, false)
    }

    // tags：Array<String> → TArray(TText)
    match (tagsCd) {
        case Some(cd) =>
            match (cd.colType) {
                case SqlColType.TArray(SqlColType.TText) => @Expect(true, true)
                case _ => @Expect(true, false)
            }
        case None => @Expect(true, false)
    }

    println("[cd-macro-test] columnDefs passed")
}

@Test
func test_macro_column_defs_to_ddl() {
    match (openRmOrSkip()) {
        case None => return
        case Some(db) =>
            // 用宏派生的 columnDefs() 产出 DDL 并建表
            let e = cdDemoEntity()
            let schema = Schema()
            let ddl = schema.createTableFromEntity(e)
            println("[cd-macro-test] DDL: " + ddl)
            @Expect(ddl.contains("CREATE TABLE"), true)
            @Expect(ddl.contains("\"id\" BIGSERIAL"), true)
            @Expect(ddl.contains("PRIMARY KEY"), true)
            @Expect(ddl.contains("\"name\" TEXT NOT NULL"), true)
            @Expect(ddl.contains("\"active\" BOOLEAN NOT NULL"), true)
            @Expect(ddl.contains("\"meta\" JSONB"), true)
            @Expect(ddl.contains("\"tags\" TEXT[]"), true)

            // 实际执行 DDL 验证语法正确
            db.execRawSql("DROP TABLE IF EXISTS csorm_cd_demo")
            db.execRawSql(ddl)
            // 插入数据验证
            db.execRaw("INSERT INTO csorm_cd_demo (name, age, active, meta, tags) VALUES ($1, $2, $3, $4, $5)",
                [vtext("test"), vint(25), vbool(true), vjson("{}"), textArray(["a", "b"])])
            let rows = db.raw<Row>("SELECT name, age, active FROM csorm_cd_demo", [], { r => r })
            @Expect(rows.size, 1)
            @Expect(rows[0].getText("name"), "test")
            @Expect(rows[0].getInt64("age"), 25)

            db.execRawSql("DROP TABLE IF EXISTS csorm_cd_demo")
            db.close()
            println("[cd-macro-test] columnDefs to DDL passed")
    }
}