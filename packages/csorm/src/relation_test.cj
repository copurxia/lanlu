package csorm

/**
 * 阶段一关系模型测试：验证 RelationDef/findRelated/loadOne/loadMany 解决 N+1。
 * 用两个实体：TestParent(主表) 与 TestChild(从表，外键 parent_id)。
 * 手工构造 RelationDef(宏支持后续补)；验证单条 IN 查询回填 N 个 parent 的关联。
 */
import std.unittest.*
import std.unittest.testmacro.*
import std.env.getVariable
import std.collection.*
import postgresql_driver.*
import csorm_macros.*

func relConnStr(): String {
    getVariable("DB_STRING") ??
        "postgres://copur:e29khrowY77mGk@192.168.0.112:5432/lanludev?sslmode=disable&pool.max=5"
}

func openRelOrSkip(): ?Database {
    try {
        return Some(Database(relConnStr()))
    } catch (_: Exception) {
        println("[skip] no PostgreSQL available (relation test)")
        return None
    }
}

@entity[table = "csorm_rel_parent"]
public struct RelParent {
    @pk[auto]
    public var id: Int64 = 0
    public var name: String = ""
}

@entity[table = "csorm_rel_child"]
public struct RelChild {
    @pk[auto]
    public var id: Int64 = 0
    @column[name = "parent_id"]
    public var parentId: Int64 = 0
    public var label: String = ""
}

// 多对多测试：Tag 实体 + 中间表 archive_tags
@entity[table = "csorm_m2m_tag"]
public struct M2mTag {
    @pk[auto]
    public var id: Int64 = 0
    public var name: String = ""
}

@entity[table = "csorm_m2m_archive"]
public struct M2mArchive {
    @pk[auto]
    public var id: Int64 = 0
    public var title: String = ""
}

@Test
func test_relation_find_related() {
    match (openRelOrSkip()) {
        case None => return
        case Some(db) =>
            db.execRawSql("DROP TABLE IF EXISTS csorm_rel_child")
            db.execRawSql("DROP TABLE IF EXISTS csorm_rel_parent")
            db.execRawSql("CREATE TABLE csorm_rel_parent (id SERIAL PRIMARY KEY, name TEXT NOT NULL)")
            db.execRawSql("CREATE TABLE csorm_rel_child (id SERIAL PRIMARY KEY, parent_id INT8 NOT NULL, label TEXT NOT NULL)")

            let pRepo = Repo<RelParentEntity>(db, RelParentEntity())
            let cRepo = Repo<RelChildEntity>(db, RelChildEntity())

            // 插入 3 个 parent
            var pIds = ArrayList<Int64>()
            for (i in 0..3) {
                let ins = insertQuery("csorm_rel_parent")
                    .columns(["name"])
                    .values([vtext("p" + i.toString())])
                    .returning(["id", "name"])
                let rows = db.execReturning<RelParent>(ins,
                    { r => (relParentEntity().fromRow(r) as RelParent).getOrThrow() })
                pIds.add(rows[0].id)
            }
            let pIdsArr = pIds.toArray()
            // 插入 4 个 child：parent0 有 2 个，parent1 有 1 个，parent2 有 1 个
            let childInserts = [
                (pIdsArr[0], "c0a"), (pIdsArr[0], "c0b"),
                (pIdsArr[1], "c1a"),
                (pIdsArr[2], "c2a")
            ]
            for ((pid, lbl) in childInserts) {
                let ins = insertQuery("csorm_rel_child")
                    .columns(["parent_id", "label"])
                    .values([vint(pid), vtext(lbl)])
                db.exec(ins)
            }

            // findRelated：单条 IN 查询取全部 child
            let rel = RelationDef.hasMany(
                RelParentEntity(), RelChildEntity(), "parent_id")
            let pks = Array<Value>(pIdsArr.size, { i => vint(pIdsArr[i]) })
            let pairs = pRepo.findRelated(rel, pks)
            @Expect(pairs.size, 4)  // 4 个 child

            // 按 parent 分组校验
            let groups = HashMap<Int64, Int64>()
            for ((fk, _) in pairs) {
                match (fk) {
                    case Value.VInt(k) =>
                        match (groups.get(k)) {
                            case Some(c) => groups[k] = c + 1
                            case None => groups[k] = 1
                        }
                    case _ => ()
                }
            }
            @Expect(groups.get(pIdsArr[0]).getOrThrow(), 2)
            @Expect(groups.get(pIdsArr[1]).getOrThrow(), 1)
            @Expect(groups.get(pIdsArr[2]).getOrThrow(), 1)

            db.execRawSql("DROP TABLE csorm_rel_child")
            db.execRawSql("DROP TABLE csorm_rel_parent")
            db.close()
            println("[rel-test] find_related passed")
    }
}

@Test
func test_relation_load_many_nplus1() {
    match (openRelOrSkip()) {
        case None => return
        case Some(db) =>
            db.execRawSql("DROP TABLE IF EXISTS csorm_rel_child")
            db.execRawSql("DROP TABLE IF EXISTS csorm_rel_parent")
            db.execRawSql("CREATE TABLE csorm_rel_parent (id SERIAL PRIMARY KEY, name TEXT NOT NULL)")
            db.execRawSql("CREATE TABLE csorm_rel_child (id SERIAL PRIMARY KEY, parent_id INT8 NOT NULL, label TEXT NOT NULL)")

            // 插入 5 个 parent，每个 2 个 child
            var pIds = ArrayList<Int64>()
            for (i in 0..5) {
                let ins = insertQuery("csorm_rel_parent")
                    .columns(["name"]).values([vtext("p" + i.toString())]).returning(["id", "name"])
                let rows = db.execReturning<RelParent>(ins,
                    { r => (relParentEntity().fromRow(r) as RelParent).getOrThrow() })
                pIds.add(rows[0].id)
                for (j in 0..2) {
                    let ci = insertQuery("csorm_rel_child")
                        .columns(["parent_id", "label"])
                        .values([vint(rows[0].id), vtext("c" + j.toString())])
                    db.exec(ci)
                }
            }

            // 模拟"列表页"：先查全部 parent(1 条 SQL)，再 loadMany(1 条 SQL) = 2 条总
            let parents = db.all<RelParent>(
                selectQuery("csorm_rel_parent").select(["id", "name"]),
                { r => (relParentEntity().fromRow(r) as RelParent).getOrThrow() })
            @Expect(parents.size, 5)

            let rel = RelationDef.hasMany(RelParentEntity(), RelChildEntity(), "parent_id")
            // loadMany：单条 IN 查询回填全部 parent 的 child
            let result = loadMany<RelChild, RelParent>(db, rel, parents,
                { p: RelParent => vint(p.id) },
                { r => (relChildEntity().fromRow(r) as RelChild).getOrThrow() })
            @Expect(result.size, 5)
            // 每个 parent 2 个 child
            for (i in 0..5) {
                @Expect(result[i].size, 2)
                @Expect(result[i][0].parentId, parents[i].id)
            }

            db.execRawSql("DROP TABLE csorm_rel_child")
            db.execRawSql("DROP TABLE csorm_rel_parent")
            db.close()
            println("[rel-test] loadMany N+1 solved passed")
    }
}

@Test
func test_relation_load_one() {
    match (openRelOrSkip()) {
        case None => return
        case Some(db) =>
            db.execRawSql("DROP TABLE IF EXISTS csorm_rel_child")
            db.execRawSql("DROP TABLE IF EXISTS csorm_rel_parent")
            db.execRawSql("CREATE TABLE csorm_rel_parent (id SERIAL PRIMARY KEY, name TEXT NOT NULL)")
            db.execRawSql("CREATE TABLE csorm_rel_child (id SERIAL PRIMARY KEY, parent_id INT8 NOT NULL, label TEXT NOT NULL)")

            // 插入 3 个 parent，仅 parent0 有 1 个 child(模拟 hasOne 场景)
            var pIds = ArrayList<Int64>()
            for (i in 0..3) {
                let ins = insertQuery("csorm_rel_parent")
                    .columns(["name"]).values([vtext("p" + i.toString())]).returning(["id", "name"])
                let rows = db.execReturning<RelParent>(ins,
                    { r => (relParentEntity().fromRow(r) as RelParent).getOrThrow() })
                pIds.add(rows[0].id)
            }
            let ci = insertQuery("csorm_rel_child")
                .columns(["parent_id", "label"])
                .values([vint(pIds[0]), vtext("only-child")])
            db.exec(ci)

            let parents = db.all<RelParent>(
                selectQuery("csorm_rel_parent").select(["id", "name"]),
                { r => (relParentEntity().fromRow(r) as RelParent).getOrThrow() })
            let rel = RelationDef.hasOne(RelParentEntity(), RelChildEntity(), "parent_id")
            let result = loadOne<RelChild, RelParent>(db, rel, parents,
                { p: RelParent => vint(p.id) },
                { r => (relChildEntity().fromRow(r) as RelChild).getOrThrow() })
            @Expect(result.size, 3)
            // parent0 有 child
            match (result[0]) {
                case Some(c) => @Expect(c.label, "only-child")
                case None => @Expect(true, false)
            }
            // parent1/2 无 child
            match (result[1]) { case None => @Expect(true, true); case Some(_) => @Expect(true, false) }
            match (result[2]) { case None => @Expect(true, true); case Some(_) => @Expect(true, false) }

            db.execRawSql("DROP TABLE csorm_rel_child")
            db.execRawSql("DROP TABLE csorm_rel_parent")
            db.close()
            println("[rel-test] loadOne passed")
    }
}

@Test
func test_relation_load_many_to_many() {
    match (openRelOrSkip()) {
        case None => return
        case Some(db) =>
            db.execRawSql("DROP TABLE IF EXISTS csorm_m2m_archive_tags")
            db.execRawSql("DROP TABLE IF EXISTS csorm_m2m_tag")
            db.execRawSql("DROP TABLE IF EXISTS csorm_m2m_archive")
            db.execRawSql("CREATE TABLE csorm_m2m_archive (id SERIAL PRIMARY KEY, title TEXT NOT NULL)")
            db.execRawSql("CREATE TABLE csorm_m2m_tag (id SERIAL PRIMARY KEY, name TEXT NOT NULL)")
            db.execRawSql("CREATE TABLE csorm_m2m_archive_tags (archive_id INT8 NOT NULL, tag_id INT8 NOT NULL, PRIMARY KEY (archive_id, tag_id))")

            // 插入 3 个 archive
            var aIds = ArrayList<Int64>()
            for (i in 0..3) {
                let ins = insertQuery("csorm_m2m_archive")
                    .columns(["title"]).values([vtext("a" + i.toString())])
                    .returning(["id", "title"])
                let rows = db.execReturning<M2mArchive>(ins,
                    { r => (m2mArchiveEntity().fromRow(r) as M2mArchive).getOrThrow() })
                aIds.add(rows[0].id)
            }
            let aIdsArr = aIds.toArray()

            // 插入 3 个 tag
            var tIds = ArrayList<Int64>()
            for (i in 0..3) {
                let ins = insertQuery("csorm_m2m_tag")
                    .columns(["name"]).values([vtext("t" + i.toString())])
                    .returning(["id", "name"])
                let rows = db.execReturning<M2mTag>(ins,
                    { r => (m2mTagEntity().fromRow(r) as M2mTag).getOrThrow() })
                tIds.add(rows[0].id)
            }
            let tIdsArr = tIds.toArray()

            // 关联：a0-t0, a0-t1, a1-t1, a2-t0, a2-t2
            let links = [
                (aIdsArr[0], tIdsArr[0]),
                (aIdsArr[0], tIdsArr[1]),
                (aIdsArr[1], tIdsArr[1]),
                (aIdsArr[2], tIdsArr[0]),
                (aIdsArr[2], tIdsArr[2])
            ]
            for ((aid, tid) in links) {
                db.execRaw("INSERT INTO csorm_m2m_archive_tags (archive_id, tag_id) VALUES ($1, $2)",
                    [vint(aid), vint(tid)])
            }

            // loadManyToMany：2 条 SQL 查全部
            let parentPks = Array<Value>(aIdsArr.size, { i => vint(aIdsArr[i]) })
            let result = loadManyToMany<M2mTag>(db, parentPks,
                "csorm_m2m_archive_tags", "archive_id", "tag_id",
                m2mTagEntity(),
                { r => (m2mTagEntity().fromRow(r) as M2mTag).getOrThrow() })
            @Expect(result.size, 3)
            // a0 有 t0, t1
            @Expect(result[0].size, 2)
            // a1 有 t1
            @Expect(result[1].size, 1)
            // a2 有 t0, t2
            @Expect(result[2].size, 2)
            // 验证 tag 名(按 id 升序不保证，检查包含)
            let a0Names = ArrayList<String>()
            for (t in result[0]) { a0Names.add(t.name) }
            @Expect(a0Names.contains("t0"), true)
            @Expect(a0Names.contains("t1"), true)

            db.execRawSql("DROP TABLE IF EXISTS csorm_m2m_archive_tags")
            db.execRawSql("DROP TABLE IF EXISTS csorm_m2m_tag")
            db.execRawSql("DROP TABLE IF EXISTS csorm_m2m_archive")
            db.close()
            println("[rel-test] loadManyToMany passed")
    }
}

// ===== findLinked 单测：User → Post → Comment 多跳链路 =====

@entity[table = "csorm_link_user"]
public struct LinkUser {
    @pk[auto]
    public var id: Int64 = 0
    public var name: String = ""
}

@entity[table = "csorm_link_post"]
public struct LinkPost {
    @pk[auto]
    public var id: Int64 = 0
    @column[name = "user_id"]
    public var userId: Int64 = 0
    public var title: String = ""
}

@entity[table = "csorm_link_comment"]
public struct LinkComment {
    @pk[auto]
    public var id: Int64 = 0
    @column[name = "post_id"]
    public var postId: Int64 = 0
    public var body: String = ""
}

// 多跳链路：User → Post → Comment
public class UserToCommentLink <: Linked {
    public init() {}
    public func fromEntity(): Entity { linkUserEntity() }
    public func toEntity(): Entity { linkCommentEntity() }
    public func link(): Array<RelationDef> {
        // hop1: User → Post (post.user_id = user.id)
        let hop1 = RelationDef.hasMany(linkUserEntity(), linkPostEntity(), "user_id")
        // hop2: Post → Comment (comment.post_id = post.id)
        let hop2 = RelationDef.hasMany(linkPostEntity(), linkCommentEntity(), "post_id")
        [hop1, hop2]
    }
}

@Test
func test_relation_find_linked() {
    match (openRelOrSkip()) {
        case None => return
        case Some(db) =>
            db.execRawSql("DROP TABLE IF EXISTS csorm_link_comment")
            db.execRawSql("DROP TABLE IF EXISTS csorm_link_post")
            db.execRawSql("DROP TABLE IF EXISTS csorm_link_user")
            db.execRawSql("CREATE TABLE csorm_link_user (id SERIAL PRIMARY KEY, name TEXT NOT NULL)")
            db.execRawSql("CREATE TABLE csorm_link_post (id SERIAL PRIMARY KEY, user_id INT8 NOT NULL, title TEXT NOT NULL)")
            db.execRawSql("CREATE TABLE csorm_link_comment (id SERIAL PRIMARY KEY, post_id INT8 NOT NULL, body TEXT NOT NULL)")

            // 插入 2 个 user
            var uIds = ArrayList<Int64>()
            for (i in 0..2) {
                let ins = insertQuery("csorm_link_user")
                    .columns(["name"]).values([vtext("u" + i.toString())])
                    .returning(["id", "name"])
                let rows = db.execReturning<LinkUser>(ins,
                    { r => (linkUserEntity().fromRow(r) as LinkUser).getOrThrow() })
                uIds.add(rows[0].id)
            }
            let uIdsArr = uIds.toArray()

            // 插入 3 个 post：u0 有 2 个，u1 有 1 个
            var pIds = ArrayList<Int64>()
            let postInserts = [
                (uIdsArr[0], "p0a"), (uIdsArr[0], "p0b"), (uIdsArr[1], "p1a")
            ]
            for ((uid, title) in postInserts) {
                let ins = insertQuery("csorm_link_post")
                    .columns(["user_id", "title"])
                    .values([vint(uid), vtext(title)])
                    .returning(["id", "user_id", "title"])
                let rows = db.execReturning<LinkPost>(ins,
                    { r => (linkPostEntity().fromRow(r) as LinkPost).getOrThrow() })
                pIds.add(rows[0].id)
            }
            let pIdsArr = pIds.toArray()

            // 插入 4 个 comment：p0a 有 2 个，p0b 有 1 个，p1a 有 1 个
            let commentInserts = [
                (pIdsArr[0], "c0a1"), (pIdsArr[0], "c0a2"),
                (pIdsArr[1], "c0b1"),
                (pIdsArr[2], "c1a1")
            ]
            for ((pid, body) in commentInserts) {
                let ins = insertQuery("csorm_link_comment")
                    .columns(["post_id", "body"])
                    .values([vint(pid), vtext(body)])
                db.exec(ins)
            }

            // findLinked：User → Post → Comment，查 u0 的全部 comment(经 p0a, p0b)
            let l = UserToCommentLink()
            let q = findLinked(db, l)
            // 加 WHERE：限定 user.id = u0(用表名限定避免 JOIN 后列名歧义)
            q.filter(rawCond("csorm_link_user.id = ?", [vint(uIdsArr[0])]))
            let (sql, params) = q.build()
            println("[rel-test] findLinked SQL: " + sql)
            // SQL 应含 2 个 JOIN
            @Expect(sql.contains("INNER JOIN"), true)

            let rows = db.raw<LinkComment>(sql, params, { r =>
                (linkCommentEntity().fromRow(r) as LinkComment).getOrThrow()
            })
            // u0 经 p0a(2 comments) + p0b(1 comment) = 3 comments
            @Expect(rows.size, 3)
            // 验证 body 内容
            let bodies = ArrayList<String>()
            for (c in rows) { bodies.add(c.body) }
            @Expect(bodies.contains("c0a1"), true)
            @Expect(bodies.contains("c0a2"), true)
            @Expect(bodies.contains("c0b1"), true)
            // 不应包含 u1 的 comment
            @Expect(bodies.contains("c1a1"), false)

            db.execRawSql("DROP TABLE IF EXISTS csorm_link_comment")
            db.execRawSql("DROP TABLE IF EXISTS csorm_link_post")
            db.execRawSql("DROP TABLE IF EXISTS csorm_link_user")
            db.close()
            println("[rel-test] findLinked passed")
    }
}