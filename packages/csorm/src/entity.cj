package csorm

import std.collection.*
import std.convert.*

/**
 * ActiveValue 三态(对标 sea-orm ActiveValue)：
 * - Set：显式赋值，参与 INSERT/UPDATE 写入。
 * - Unchanged：从 DB 读回的现有值，UPDATE 时不写入。
 * - NotSet：未设置，INSERT/UPDATE 时该列省略。
 */
public enum ActiveValue {
    | Set(Value)
    | Unchanged(Value)
    | NotSet
}

/** ActiveValue 工具：判定状态/取值。 */
public func avSet(v: Value): ActiveValue { ActiveValue.Set(v) }
public func avUnchanged(v: Value): ActiveValue { ActiveValue.Unchanged(v) }
public func avNotSet(): ActiveValue { ActiveValue.NotSet }

public func avIsSet(av: ActiveValue): Bool {
    match (av) { case Set(_) => true; case _ => false }
}
public func avIsUnchanged(av: ActiveValue): Bool {
    match (av) { case Unchanged(_) => true; case _ => false }
}
public func avIsNotSet(av: ActiveValue): Bool {
    match (av) { case NotSet => true; case _ => false }
}

/** 取值：Set/Unchanged 返回内部值，NotSet 返回 VNull。 */
public func avValue(av: ActiveValue): Value {
    match (av) {
        case Set(v) => v
        case Unchanged(v) => v
        case NotSet => Value.VNull
    }
}

/**
 * Entity：表元数据 + 行映射。Cangjie 无关联类型，fromRow 返回 Any，
 * 由宏生成体强转回具体 Model 类型(调用方拿到的就是该 Model 类型，向下转安全)。
 */
public interface Entity {
    func table(): String
    func schema(): ?String
    func columns(): Array<String>               // 全部列名(顺序固定)
    func pkColumns(): Array<String>             // 主键列
    func autoIncrement(): Bool
    func fromRow(r: Row): Any                   // 宏生成体构造具体 Model(csorm.Row 接口)
    func emptyActive(): ActiveModel
    /** 关系定义列表(默认空；宏可生成体覆盖)。对标 sea-orm RelationTrait。 */
    func relations(): Array<RelationDef> { Array<RelationDef>() }
    /** 列元数据(DDL 侧；默认空，回退到从 columns/pkColumns 推导)。对标 sea-orm ColumnDef。 */
    func columnDefs(): Array<ColumnDef> { Array<ColumnDef>() }
}

/** ActiveModel：可变行载体，逐列三态。 */
public interface ActiveModel {
    func entity(): Entity
    /** 取列的 ActiveValue。 */
    func get(col: String): ActiveValue
    /** 设列值(Set 态)。 */
    func set(col: String, v: Value): Unit
    /** 置 NotSet(从写入中省略该列)。 */
    func unset(col: String): Unit
    /** 列是否为 Set 态(参与 INSERT/UPDATE)。 */
    func isChanged(col: String): Bool
    /** 列当前值(Set/Unchanged 给值，NotSet 给 VNull)。 */
    func getValue(col: String): Value
    /** 主键当前值数组(顺序对齐 pkColumns)。 */
    func pkValue(): Array<Value>
    /** 仅 Set 列 → (colName, value) 列表(供 INSERT)。 */
    func setEntries(): Array<(String, Value)>
    /** 仅 Set 列且非主键 → (colName, value) 列表(供 UPDATE SET)。 */
    func setNonPkEntries(): Array<(String, Value)>
    /** 任意列是否为 Set(用于判断是否需要写入)。 */
    func isAnyChanged(): Bool
}

/**
 * 泛型仓储：基于 Entity + ActiveModel 提供 CRUD 入口。
 * 不依赖宏；用户手写 Entity/ActiveModel 实现即可使用。
 */
public class Repo<E> where E <: Entity {
    let db: Database
    let entity: E

    public init(db: Database, entity: E) {
        this.db = db
        this.entity = entity
    }

    /** SELECT * FROM table(预填列名 + FROM)。 */
    public func find(): SelectQuery {
        let q = SelectQuery()
        match (entity.schema()) {
            case Some(s) => q.from(s, table: entity.table())
            case None => q.from(entity.table())
        }
        // 列名显式列出(便于宏 fromRow 按列名读)
        q.select(entity.columns())
        q
    }

    /** 按主键查询(单列 PK 取首值；复合 PK 按 pkColumns 顺序 AND)。 */
    public func findById(pk: Array<Value>): SelectQuery {
        let q = find()
        let pkCols = entity.pkColumns()
        if (pk.size != pkCols.size) {
            throw CsormError("findById: pk arity mismatch, expected " + pkCols.size.toString() +
                " got " + pk.size.toString())
        }
        let conds = ArrayList<Cond>()
        for (i in 0..pkCols.size) {
            conds.add(Cond.Cmp(pkCols[i], "=", pk[i]))
        }
        if (conds.size == 1) {
            q.filter(conds[0])
        } else {
            q.filter(Cond.And(conds.toArray()))
        }
        q
    }

    /** INSERT 一行(仅 Set 列)。 */
    public func insert(am: ActiveModel): InsertQuery {
        let q = InsertQuery()
        match (entity.schema()) {
            case Some(s) => q.intoSchema(s, table: entity.table())
            case None => q.into(entity.table())
        }
        let entries = am.setEntries()
        if (entries.size == 0) {
            throw CsormError("insert: no Set columns")
        }
        let cols = Array<String>(entries.size, { i => entries[i][0] })
        let vals = Array<Value>(entries.size, { i => entries[i][1] })
        q.columns(cols).values(vals)
        // 自增 PK 且未 Set → RETURNING pk 列
        if (entity.autoIncrement()) {
            q.returning(entity.pkColumns())
        }
        q
    }

    /** UPDATE 一行：用 pk 做 WHERE，仅更新 Set 且非 pk 的列。 */
    public func update(am: ActiveModel): UpdateQuery {
        let q = UpdateQuery()
        match (entity.schema()) {
            case Some(s) => q.tableSchema(s, table: entity.table())
            case None => q.updateTable(entity.table())
        }
        let entries = am.setNonPkEntries()
        for ((col, v) in entries) {
            q.set(col, v)
        }
        let pkCols = entity.pkColumns()
        let pkVals = am.pkValue()
        if (pkCols.size == 0) {
            throw CsormError("update: no primary key defined")
        }
        if (pkCols.size == 1) {
            q.filter(Cond.Cmp(pkCols[0], "=", pkVals[0]))
        } else {
            let conds = ArrayList<Cond>()
            for (i in 0..pkCols.size) {
                conds.add(Cond.Cmp(pkCols[i], "=", pkVals[i]))
            }
            q.filter(Cond.And(conds.toArray()))
        }
        q
    }

    /** DELETE 一行：用 pk 做 WHERE。 */
    public func delete(am: ActiveModel): DeleteQuery {
        let q = DeleteQuery()
        match (entity.schema()) {
            case Some(s) => q.fromSchema(s, table: entity.table())
            case None => q.from(entity.table())
        }
        let pkCols = entity.pkColumns()
        let pkVals = am.pkValue()
        if (pkCols.size == 0) {
            throw CsormError("delete: no primary key defined")
        }
        if (pkCols.size == 1) {
            q.filter(Cond.Cmp(pkCols[0], "=", pkVals[0]))
        } else {
            let conds = ArrayList<Cond>()
            for (i in 0..pkCols.size) {
                conds.add(Cond.Cmp(pkCols[i], "=", pkVals[i]))
            }
            q.filter(Cond.And(conds.toArray()))
        }
        q
    }

    /** 按主键删除(无需 ActiveModel)。 */
    public func deleteById(pk: Array<Value>): DeleteQuery {
        let q = DeleteQuery()
        match (entity.schema()) {
            case Some(s) => q.fromSchema(s, table: entity.table())
            case None => q.from(entity.table())
        }
        let pkCols = entity.pkColumns()
        if (pk.size != pkCols.size) {
            throw CsormError("deleteById: pk arity mismatch")
        }
        if (pkCols.size == 1) {
            q.filter(Cond.Cmp(pkCols[0], "=", pk[0]))
        } else {
            let conds = ArrayList<Cond>()
            for (i in 0..pkCols.size) {
                conds.add(Cond.Cmp(pkCols[i], "=", pk[i]))
            }
            q.filter(Cond.And(conds.toArray()))
        }
        q
    }

    /** 查询全部并映射为 Model(返回 Any 数组，调用方按需向下转)。 */
    public func all(): Array<Any> {
        db.all<Any>(find(), { r => entity.fromRow(r) })
    }

    /** 按主键查询单行(返回 Any 或 None)。 */
    public func one(pk: Array<Value>): ?Any {
        db.one<Any>(findById(pk), { r => entity.fromRow(r) })
    }

    /**
     * 单跳关联查询：返回 parentPks 在指定 RelationDef 的 toEntity 中对应的关联行。
     * 返回 (fkVal, relatedModel) 配对数组；fkVal 为 toCol 的值，用于回配 parent。
     * 对标 sea-orm find_related。N+1 安全：单条 IN 查询。
     */
    public func findRelated(rel: RelationDef, parentPks: Array<Value>): Array<(Value, Any)> {
        csormRelationFindRelated(db, rel, parentPks)
    }

    /**
     * JOIN 形式关联查询：返回 (parentModel, relatedModel) 配对数组。
     * parentPks 限定 parent 的 fromCol 集合。对标 sea-orm find_also_related。
     */
    public func findAlsoRelated(rel: RelationDef, parentFromRow: (Row) -> Any,
        parentPks: Array<Value>): Array<(Any, Any)> {
        csormRelationFindAlsoRelated(db, rel, entity.columns(), parentFromRow, parentPks)
    }
}