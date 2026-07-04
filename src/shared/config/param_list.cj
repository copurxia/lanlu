package lanlu.shared.config

import ace_orm.*
import std.collection.*

/**
 * 参数绑定辅助器:统一管理 SQL $n 占位符编号与绑定值,替代散落的 stmt.set(index, value) + ? 组合。
 *
 * 用法:
 *   let pl = ParamList()
 *   let sql = "SELECT * FROM t WHERE a = " + pl.addText(x) + " AND b = " + pl.addInt(y)
 *   drv.query(sql, pl.toParams())
 *
 * 动态 SQL 场景(archive_dao 搜索):条件片段按需 add,编号自动单调递增,无需全局手动计数。
 *   let pl = ParamList()
 *   if (hasFilter) { where.add("t.cat = " + pl.addText(cat)) }
 *   if (hasDate)  { where.add("t.date >= " + pl.addText(date)) }
 *   // countSql 与 dataSql 共用同一 pl,编号一致
 *   drv.query(countSql, pl.toParams())
 */
public class ParamList {
    private let values = ArrayList<DbValue>()
    private var counter = 0

    public init() {}

    /** 添加一个绑定值,返回对应的 $n 占位符。 */
    public func add(v: DbValue): String {
        counter += 1
        values.add(v)
        return "$${counter}"
    }

    /** 添加文本(亦承载 JSONB 文本、Date 文本等)。 */
    public func addText(s: String): String {
        add(DbText(s))
    }

    /** 添加整型。 */
    public func addInt(i: Int64): String {
        add(DbInt(i))
    }

    /** 添加布尔。 */
    public func addBool(b: Bool): String {
        add(DbBool(b))
    }

    /** 添加 NULL。 */
    public func addNull(): String {
        add(DbNull)
    }

    /**
     * 添加 PG 数组(text[]/bigint[] 等),返回 "$n"(配合 SQL 里 ::text[] 等 cast 使用)。
     * 元素按 String 数组构造(DbText 元素)。
     */
    public func addTextArray(elems: Array<String>): String {
        let arr = Array<DbValue>(elems.size, { i => DbText(elems[i]) })
        return add(DbArray(arr))
    }

    /** 添加 PG bigint 数组,返回 "$n"(配合 ::bigint[] cast)。 */
    public func addInt64Array(elems: Array<Int64>): String {
        let arr = Array<DbValue>(elems.size, { i => DbInt(elems[i]) })
        return add(DbArray(arr))
    }

    /** 当前已添加的参数个数。 */
    public func size(): Int64 {
        counter
    }

    /** 导出为 driver.query/exec 的 params 数组。 */
    public func toParams(): Array<DbValue> {
        values.toArray()
    }

    /** 重置(复用同一 ParamList 构造第二条 SQL 时调用)。 */
    public func reset(): Unit {
        values.clear()
        counter = 0
    }
}