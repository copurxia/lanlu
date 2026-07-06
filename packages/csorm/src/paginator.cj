package csorm

import std.collection.*
import std.convert.*
import postgresql_driver.*

/**
 * 分页器(对标 sea-orm Paginator)。两种模式：
 * - 偏移分页：fetchPage(n) 设 limit(pageSize) offset(pageSize*n)。
 * - keyset 分页：以 afterCol > $lastVal 推进，适合深翻页不偏移。
 * numItems() 通过把原查询包成子查询 SELECT COUNT(*) 计算。
 */
public class Paginator<T> {
    let db: Database
    let base: SelectQuery        // 不会被修改(每次 clone 后修改)
    let pageSize: Int64
    let map: (Row) -> T
    var page: Int64 = 0

    public init(db: Database, base: SelectQuery, pageSize: Int64, map: (Row) -> T) {
        if (pageSize <= 0) { throw CsormError("Paginator: pageSize must be > 0") }
        this.db = db
        this.base = base
        this.pageSize = pageSize
        this.map = map
    }

    /** 当前页码(从 0 起)。 */
    public func curPage(): Int64 { page }

    /** 推进到下一页。 */
    public func next(): Unit { page += 1 }

    /** 取指定页(0-based)的数据。 */
    public func fetchPage(p: Int64): Array<T> {
        let q = base.clone()
        q.limit(pageSize).offset(pageSize * p)
        db.all<T>(q, map)
    }

    /** 取当前页数据。 */
    public func fetch(): Array<T> { fetchPage(page) }

    /** 取当前页并推进；返回 None 表示已无数据。 */
    public func fetchAndNext(): ?Array<T> {
        let rows = fetch()
        if (rows.size == 0) { return None }
        next()
        Some(rows)
    }

    /** 总条数：SELECT COUNT(*) FROM (<原查询去掉 limit/offset/order>) sub。 */
    public func numItems(): Int64 {
        let q = base.clone()
        q.orderBys = ArrayList<(String, Order, String)>()
        q.limitVal = None
        q.offsetVal = None
        let (subSql, subParams) = q.build()
        let countSql = "SELECT COUNT(*) AS cnt FROM (" + subSql + ") AS sub_count"
        match (db.rawOne<Int64>(countSql, subParams, { r => r.getInt64(0) })) {
            case Some(n) => n
            case None => 0
        }
    }

    /** 总页数(向上取整)。 */
    public func numPages(): Int64 {
        let n = numItems()
        if (n == 0) { return 0 }
        n / pageSize + (if (n % pageSize > 0) { 1 } else { 0 })
    }

    /** 同时取总数与页数。 */
    public func numItemsAndPages(): (Int64, Int64) { (numItems(), numPages()) }
}

/**
 * keyset 分页器：基于 afterCol > $lastVal 推进，避免深翻页偏移。
 * 典型用法：lanlu 后台任务 WHERE id > ? ORDER BY id ASC LIMIT ?。
 * map 返回 (T, cursorValue)：调用方需从行中取出 afterCol 的值用于游标推进。
 */
public class KeysetPaginator<T> {
    let db: Database
    let base: SelectQuery
    let afterCol: String
    let pageSize: Int64
    let map: (Row) -> (T, Value)
    var lastVal: Value

    public init(db: Database, base: SelectQuery, afterCol: String, pageSize: Int64,
        startVal: Value, map: (Row) -> (T, Value)) {
        if (pageSize <= 0) { throw CsormError("KeysetPaginator: pageSize must be > 0") }
        this.db = db
        this.base = base
        this.afterCol = afterCol
        this.pageSize = pageSize
        this.lastVal = startVal
        this.map = map
    }

    /** 当前游标值。 */
    public func cursor(): Value { lastVal }

    /** 取下一页：在 base 上加 afterCol > $lastVal ORDER BY afterCol LIMIT pageSize。 */
    public func fetchNext(): Array<T> {
        let q = base.clone()
        let cursorCond = Cond.Cmp(afterCol, ">", lastVal)
        match (q.whereCond) {
            case Some(existing) => q.filter(Cond.And([existing, cursorCond]))
            case None => q.filter(cursorCond)
        }
        q.orderBy(afterCol, Order.Asc).limit(pageSize)
        let (sql, params) = q.build()
        let rows = db.pgdb().query(sql, Array<PGValue>(params.size, { i => valueToPG(params[i]) }))
        let out = ArrayList<T>()
        for (r in rows) {
            let (item, cur) = map(r)
            out.add(item)
            lastVal = cur
        }
        out.toArray()
    }

    /** 是否还有下一页(取到少于 pageSize 行即视为到底)。 */
    public func hasNext(lastRowCount: Int64): Bool { lastRowCount >= pageSize }
}