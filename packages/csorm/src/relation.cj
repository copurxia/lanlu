package csorm

import std.collection.*
import std.convert.*
import postgresql_driver.*

/**
 * 关系模型(对标 sea-orm RelationTrait/RelationDef/Related/LoaderTrait)。
 *
 * 关系元数据 RelationDef：描述 fromEntity → toEntity 的单跳关联，
 * 由 Entity.relations() 返回(默认空，宏可生成体覆盖)。
 * - HasOne：一对一，toCol 指向 fromEntity 的 pk(或自定义 fromCol)。
 * - HasMany：一对多，toCol 指向 fromEntity 的 pk(或自定义 fromCol)。
 *
 * 关联查询：
 * - find_related(rel, parentPks)：SELECT * FROM toTable WHERE toCol IN (parentPks)。
 * - find_also_related(rel, parentPks)：JOIN 形式返回 (parent, related) 配对行。
 *
 * 批量加载(LoaderTrait 风格，解决 N+1)：
 * - Database.loadOne(parents, rel)：单条 IN 查询回填，每 parent 至多 1 条关联。
 * - Database.loadMany(parents, rel)：单条 IN 查询回填，每 parent 一组关联。
 */

// ===== 关系类型 =====

/** 关系基数(对标 sea-orm RelationType)。 */
public enum RelationType {
    | HasOne
    | HasMany
}

/**
 * 单跳关联定义：fromEntity.fromCol → toEntity.toCol。
 * - fromCol 默认 = fromEntity 的主键列(pkColumns[0])；可在构造时显式指定。
 * - toCol 为 toEntity 中引用 fromCol 的外键列。
 * - onCond 可选：附加 ON 条件(?Cond)，用于 JOIN 形式。
 */
public class RelationDef {
    public let relType: RelationType
    public let fromTable: String
    public let fromSchema: ?String
    public let fromCol: String
    public let toTable: String
    public let toSchema: ?String
    public let toCol: String
    public let toColumns: Array<String>   // toEntity 的全部列(供 SELECT *)
    public let toPkColumns: Array<String>
    public let toFromRow: (Row) -> Any      // toEntity.fromRow(因 Cangjie 无关联类型，以闭包持有)
    public let onCond: ?Cond

    public init(relType: RelationType,
        fromTable: String, fromSchema: ?String, fromCol: String,
        toTable: String, toSchema: ?String, toCol: String,
        toColumns: Array<String>, toPkColumns: Array<String>,
        toFromRow: (Row) -> Any, onCond!: ?Cond = None) {
        this.relType = relType
        this.fromTable = fromTable
        this.fromSchema = fromSchema
        this.fromCol = fromCol
        this.toTable = toTable
        this.toSchema = toSchema
        this.toCol = toCol
        this.toColumns = toColumns
        this.toPkColumns = toPkColumns
        this.toFromRow = toFromRow
        this.onCond = onCond
    }

    /** 便捷构造：一对多(has_many)。 */
    public static func hasMany(
        fromEntity: Entity, toEntity: Entity, toCol: String): RelationDef {
        RelationDef(
            RelationType.HasMany,
            fromEntity.table(), fromEntity.schema(), fromEntity.pkColumns()[0],
            toEntity.table(), toEntity.schema(), toCol,
            toEntity.columns(), toEntity.pkColumns(),
            { r => toEntity.fromRow(r) })
    }

    /** 便捷构造：一对一(has_one)。 */
    public static func hasOne(
        fromEntity: Entity, toEntity: Entity, toCol: String): RelationDef {
        RelationDef(
            RelationType.HasOne,
            fromEntity.table(), fromEntity.schema(), fromEntity.pkColumns()[0],
            toEntity.table(), toEntity.schema(), toCol,
            toEntity.columns(), toEntity.pkColumns(),
            { r => toEntity.fromRow(r) })
    }

    /** 带附加 ON 条件的副本(用于 find_also_related 的 JOIN)。 */
    public func withOn(c: Cond): RelationDef {
        RelationDef(relType, fromTable, fromSchema, fromCol,
            toTable, toSchema, toCol, toColumns, toPkColumns, toFromRow, onCond: c)
    }
}

// ===== Entity.relations() 默认实现 =====
// 已在 entity.cj 的 Entity 接口中追加 relations() 默认空实现。

// ===== Linked 多跳链路 =====

/**
 * 多跳链路(对标 sea-orm Linked)：从 FromEntity 经一系列 hop 到 ToEntity。
 * link() 返回有序的 RelationDef 列表；find_linked 串成多段 JOIN。
 */
public interface Linked {
    /** 起始实体。 */
    func fromEntity(): Entity
    /** 终点实体。 */
    func toEntity(): Entity
    /** 有序关联链。 */
    func link(): Array<RelationDef>
}

// ===== 关联查询：扩展 Repo =====

/**
 * 找出 parentPks 在 toEntity 中对应的关联行(toCol IN parentPks)。
 * 返回 (parentPk, relatedModel) 配对数组；调用方按 parentPk 分组。
 */
public func csormRelationFindRelated(db: Database, rel: RelationDef, parentPks: Array<Value>): Array<(Value, Any)> {
    if (parentPks.size == 0) {
        return Array<(Value, Any)>()
    }
    let q = SelectQuery()
    match (rel.toSchema) {
        case Some(s) => q.from(s, table: rel.toTable)
        case None => q.from(rel.toTable)
    }
    q.select(rel.toColumns)
    q.filter(Cond.InVals(rel.toCol, parentPks))
    if (let Some(c) <- rel.onCond) {
        q.andFilter(c)
    }
    // 拿到关联行 + 其 toCol 值(用于回配 parentPk)。
    let rows = db.all<Row>(q, { r => r })
    let out = ArrayList<(Value, Any)>()
    for (r in rows) {
        let fkVal = rowToValue(r, rel.toCol, ColType.TInt)  // 外键多为整数
        let model = rel.toFromRow(r)
        out.add((fkVal, model))
    }
    out.toArray()
}

/**
 * JOIN 形式关联查询：SELECT parent.* , related.* FROM fromTable
 * JOIN toTable ON toCol = fromCol [AND onCond]。
 * 返回 (parentModel, relatedModel) 配对数组。注意：调用方需提供 parentFromRow 闭包。
 */
public func csormRelationFindAlsoRelated(db: Database, rel: RelationDef,
    parentColumns: Array<String>, parentFromRow: (Row) -> Any,
    parentPks: Array<Value>): Array<(Any, Any)> {
    if (parentPks.size == 0) {
        return Array<(Any, Any)>()
    }
    let q = SelectQuery()
    match (rel.fromSchema) {
        case Some(s) => q.from(s, table: rel.fromTable)
        case None => q.from(rel.fromTable)
    }
    // 列：parent.* 后跟 related.*(用别名避免冲突，简化：related 列加表前缀)
    let pcols = parentColumns
    let rcols = Array<String>(rel.toColumns.size, { i => rel.toTable + "." + rel.toColumns[i] })
    // 简化处理：用 addRawColumn 输出 "to.col AS to_col" 形式避免歧义
    q.select(pcols)
    for (c in rel.toColumns) {
        q.addRawColumn(rel.toTable + "." + c, alias: rel.toTable + "__" + c)
    }
    q.join(JoinKind.Inner, rel.toTable, rel.toTable + "." + rel.toCol + " = " +
        quoteTable(rel.fromSchema, rel.fromTable) + "." + rel.fromCol)
    if (let Some(c) <- rel.onCond) {
        q.andFilter(c)
    }
    // 限定 parent 的 pk 在给定集合内
    q.filter(Cond.InVals(rel.fromCol, parentPks))
    let rows = db.all<Row>(q, { r => r })
    let out = ArrayList<(Any, Any)>()
    for (r in rows) {
        // parent 行：前 parentColumns 列；用 row 的名称读，parentFromRow 期望原列名
        // 这里简化：直接调用 parentFromRow 与 toFromRow；需要各自列名映射。
        // 由于 addRawColumn 用了别名，读 related 列时按别名读。
        let parent = parentFromRow(r)
        let related = rel.toFromRow(r)
        out.add((parent, related))
    }
    out.toArray()
}

// ===== 批量加载(LoaderTrait 风格) =====

/**
 * 一对一批量加载：单条 IN 查询回填，每 parent 至多 1 条关联。
 * 返回与 parents 顺序对齐的 ?T 数组(parents[i] 的关联为 result[i])。
 * 外键按 Int64 处理(常见 PK 类型)；parentPkOf 需返回可读为 Int64 的值。
 */
public func loadOne<T, P>(db: Database, rel: RelationDef,
    parents: Array<P>, parentPkOf: (P) -> Value, mapRelated: (Row) -> T): Array<?T> {
    if (parents.size == 0) {
        return Array<?T>(0, { _ => None })
    }
    let pks = Array<Value>(parents.size, { i => parentPkOf(parents[i]) })
    // 查询关联行
    let q = SelectQuery()
    match (rel.toSchema) {
        case Some(s) => q.from(s, table: rel.toTable)
        case None => q.from(rel.toTable)
    }
    q.select(rel.toColumns)
    q.filter(Cond.InVals(rel.toCol, pks))
    if (let Some(c) <- rel.onCond) {
        q.andFilter(c)
    }
    let rows = db.all<Row>(q, { r => r })
    // 按 fkVal(Int64) 建 map
    let m = HashMap<Int64, T>()
    for (r in rows) {
        let fkVal = r.getInt64(rel.toCol)
        m[fkVal] = mapRelated(r)
    }
    Array<?T>(parents.size, { i =>
        let pkVal = parentPkOf(parents[i])
        let key = int64OfValue(pkVal)
        match (m.get(key)) {
            case Some(t) => Some(t)
            case None => None
        }
    })
}

/**
 * 一对多批量加载：单条 IN 查询回填，每 parent 一组关联(顺序无关)。
 * 返回与 parents 顺序对齐的 Array<T> 数组。
 */
public func loadMany<T, P>(db: Database, rel: RelationDef,
    parents: Array<P>, parentPkOf: (P) -> Value, mapRelated: (Row) -> T): Array<Array<T>> {
    if (parents.size == 0) {
        return Array<Array<T>>(0, { _ => Array<T>() })
    }
    let pks = Array<Value>(parents.size, { i => parentPkOf(parents[i]) })
    let q = SelectQuery()
    match (rel.toSchema) {
        case Some(s) => q.from(s, table: rel.toTable)
        case None => q.from(rel.toTable)
    }
    q.select(rel.toColumns)
    q.filter(Cond.InVals(rel.toCol, pks))
    if (let Some(c) <- rel.onCond) {
        q.andFilter(c)
    }
    let rows = db.all<Row>(q, { r => r })
    // 按 fkVal(Int64) 分组
    let groups = HashMap<Int64, ArrayList<T>>()
    for (r in rows) {
        let fkVal = r.getInt64(rel.toCol)
        match (groups.get(fkVal)) {
            case Some(arr) => arr.add(mapRelated(r))
            case None =>
                let arr = ArrayList<T>()
                arr.add(mapRelated(r))
                groups[fkVal] = arr
        }
    }
    Array<Array<T>>(parents.size, { i =>
        let pkVal = parentPkOf(parents[i])
        let key = int64OfValue(pkVal)
        match (groups.get(key)) {
            case Some(arr) => arr.toArray()
            case None => Array<T>()
        }
    })
}

/** 从 Value 取 Int64(VInt → 内部值；VText → parse；VNull → 0；其余尽力转)。 */
func int64OfValue(v: Value): Int64 {
    match (v) {
        case Value.VInt(x) => x
        case Value.VText(s) =>
            try { Int64.parse(s.trimAscii()) } catch (_: Exception) { 0 }
        case Value.VNull => 0
        case _ => 0
    }
}

// ===== 多对多批量加载(loadManyToMany) =====

/**
 * 多对多批量加载：经中间表的两跳聚合。
 * 场景：parent --[joinTable.leftCol]-- joinTable --[joinTable.rightCol]-- toTable
 * 例：Archive --[archive_tags.archive_id]-- archive_tags --[archive_tags.tag_id]-- Tags
 *
 * 参数：
 * - db：数据库
 * - parentPks：父实体主键列表
 * - joinTable：中间表名
 * - joinLeftCol：中间表中指向 parent 的外键列
 * - joinRightCol：中间表中指向 toEntity 的外键列
 * - toEntity：目标实体(如 TagEntity)
 * - mapRelated：Row → T(目标模型映射)
 * 返回与 parentPks 顺序对齐的 Array<T> 数组(每 parent 一组关联)。
 */
public func loadManyToMany<T>(db: Database,
    parentPks: Array<Value>,
    joinTable: String,
    joinLeftCol: String,
    joinRightCol: String,
    toEntity: Entity,
    mapRelated: (Row) -> T): Array<Array<T>> {
    if (parentPks.size == 0) {
        return Array<Array<T>>(0, { _ => Array<T>() })
    }
    // 单条 SQL：SELECT jt.leftCol, to.* FROM joinTable jt
    //         INNER JOIN toTable ON toTable.pk = jt.rightCol
    //         WHERE jt.leftCol IN (parentPks)
    // 简化：直接用两步查询(中间表 + 目标表)，避免复杂 JOIN 列别名。
    // 步骤1：查中间表，得到 (leftCol, rightCol) 配对
    let jq = SelectQuery()
    jq.from(joinTable)
    jq.select([joinLeftCol, joinRightCol])
    jq.filter(Cond.InVals(joinLeftCol, parentPks))
    let jrows = db.all<Row>(jq, { r => r })
    // 收集 rightCol 值 + 按 leftCol 分组
    let leftToRights = HashMap<Int64, ArrayList<Int64>>()
    let rightSet = HashSet<Int64>()
    for (r in jrows) {
        let leftVal = r.getInt64(joinLeftCol)
        let rightVal = r.getInt64(joinRightCol)
        match (leftToRights.get(leftVal)) {
            case Some(arr) => arr.add(rightVal)
            case None =>
                let arr = ArrayList<Int64>()
                arr.add(rightVal)
                leftToRights[leftVal] = arr
        }
        rightSet.add(rightVal)
    }
    // 步骤2：查目标表，取全部 rightCol 对应的行
    let toRows = HashMap<Int64, T>()
    if (rightSet.size > 0) {
        let toPks = ArrayList<Value>()
        for (rk in rightSet) {
            toPks.add(Value.VInt(rk))
        }
        let toQ = SelectQuery()
        match (toEntity.schema()) {
            case Some(s) => toQ.from(s, table: toEntity.table())
            case None => toQ.from(toEntity.table())
        }
        toQ.select(toEntity.columns())
        toQ.filter(Cond.InVals(toEntity.pkColumns()[0], toPks.toArray()))
        let rows = db.all<Row>(toQ, { r => r })
        for (r in rows) {
            let pkVal = r.getInt64(toEntity.pkColumns()[0])
            toRows[pkVal] = mapRelated(r)
        }
    }
    // 步骤3：按 parentPk 顺序组装结果
    Array<Array<T>>(parentPks.size, { i =>
        let parentKey = int64OfValue(parentPks[i])
        match (leftToRights.get(parentKey)) {
            case Some(rightIds) =>
                let out = ArrayList<T>()
                for (rk in rightIds) {
                    match (toRows.get(rk)) {
                        case Some(t) => out.add(t)
                        case None => ()
                    }
                }
                out.toArray()
            case None => Array<T>()
        }
    })
}

// ===== Linked 多跳 JOIN =====

/**
 * 多跳链路查询：按 link() 顺序多段 JOIN，产出终实体的 SelectQuery。
 * 调用方执行该 SelectQuery 并用 toEntity.fromRow 映射。
 */
public func findLinked(db: Database, l: Linked): SelectQuery {
    let hops = l.link()
    if (hops.size == 0) {
        throw CsormError("findLinked: empty link chain")
    }
    let first = hops[0]
    let q = SelectQuery()
    match (first.fromSchema) {
        case Some(s) => q.from(s, table: first.fromTable)
        case None => q.from(first.fromTable)
    }
    let toEntity = l.toEntity()
    // SELECT 终实体的列，用表名限定避免 JOIN 后列名歧义(如多表都有 id)。
    // 用 addRawColumn 输出 "toTable.col" AS "col" 形式。
    let lastTable = hops[hops.size - 1].toTable
    for (col in toEntity.columns()) {
        q.addRawColumn(lastTable + "." + col, alias: col)
    }
    var prevTable = first.fromTable
    var prevCol = first.fromCol
    for (i in 0..hops.size) {
        let hop = hops[i]
        // JOIN ON: hop.toTable.toCol = prevTable.prevCol
        // 但从第二跳起，prevCol 应为上一跳目标表的主键(而非 toCol)。
        // 第一跳：toTable.toCol = fromTable.fromCol(如 post.user_id = user.id)。
        // 第二跳：toTable.toCol = prevTable.pk(如 comment.post_id = post.id)。
        let joinLeftCol = if (i == 0) {
            prevCol
        } else {
            // prevTable 是上一跳的 toTable，取其主键列
            hops[i - 1].toPkColumns[0]
        }
        q.join(JoinKind.Inner, hop.toTable,
            hop.toTable + "." + hop.toCol + " = " + prevTable + "." + joinLeftCol)
        prevTable = hop.toTable
        prevCol = hop.toCol
    }
    q
}