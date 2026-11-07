package lanlu.shared.config

import std.collection.*
import std.sync.*
import csorm.{DatabaseMetric, MetricInfo}

/**
 * SQL 计数测试工具：临时接管 csorm 全局 metric 回调，统计被测代码发出的 SQL 条数。
 *
 * 用途：以「每请求 SQL 条数上限」断言锁死 N+1 类回归（见 docs/performance-fix-plan.md T1）。
 *
 * 用法：
 *   let counter = SqlCounter.install()
 *   ...被测调用...
 *   @Assert(counter.total() <= 6)
 *   counter.uninstall()
 *
 * 注意：同一进程内同时只应有一个 SqlCounter 生效（install 会覆盖前一个）。
 */
public class SqlCounter {
    private static let installMutex = Mutex()
    private let records = ArrayList<String>()
    private let mtx = Mutex()
    private var installed = false

    public static func install(): SqlCounter {
        let counter = SqlCounter()
        synchronized(installMutex) {
            DatabaseMetric.setMetricCallback({ info: MetricInfo =>
                counter.record(info.sql)
            })
            counter.installed = true
        }
        return counter
    }

    public func uninstall(): Unit {
        synchronized(installMutex) {
            if (installed) {
                DatabaseMetric.clearMetricCallback()
                installed = false
            }
        }
    }

    private func record(sql: String): Unit {
        synchronized(mtx) {
            records.add(sql)
        }
    }

    /** 已记录的 SQL 总条数。 */
    public func total(): Int64 {
        synchronized(mtx) {
            Int64(records.size)
        }
    }

    /** 包含指定片段（如 "FROM tankoubons"、"COUNT(*)"）的 SQL 条数。 */
    public func countOf(contains: String): Int64 {
        synchronized(mtx) {
            var n = 0i64
            for (sql in records) {
                if (sql.contains(contains)) {
                    n += 1
                }
            }
            return n
        }
    }

    /** 第 idx 条 SQL（0 起），便于断言具体语句形态。 */
    public func sqlAt(idx: Int64): String {
        synchronized(mtx) {
            return records[idx]
        }
    }
}
