package postgresql_driver

import std.collection.*
import std.sync.*

/**
 * 每连接 prepared statement 缓存（LRU）。
 *
 * 背景：原实现每次执行都走 PQexecParams 重发完整 SQL 文本，服务端每次重新
 * parse/plan。对高频重复语句（DAO 热路径）改走 PQprepare 一次 + PQexecPrepared
 * 多次，节省每语句的解析与计划开销。
 *
 * 语句名：SQL 文本经 FNV-1a 64 哈希 + 参数个数编码成 "llpg_<hash>_<n>"，
 * 保证不同 SQL/参数形状不冲突；PG 语句名在连接内唯一即可。
 *
 * LRU：访问即移到队尾；超过 capacity 淘汰队首并 DEALLOCATE（忽略失败——
 * 连接已断时 DEALLOCATE 也会失败，语句随连接销毁）。capacity<=0 关闭缓存。
 *
 * 并发：单个 PGconn 非线程安全，同一时刻只会有一条仓颉线程在使用某条连接
 * （池的借还语义 + 事务 ThreadLocal 钉连接），因此缓存本身不需要独立锁；
 * 但构造/析构路径加了防御性 sync 以便未来复用。
 */
public class StmtCache {
    static let CAPACITY_DEFAULT: Int64 = 32

    private let capacity: Int64
    // 双向链表节点：语句名 <-> SQL 文本。用 ArrayList 模拟 LRU 队列（容量小，O(n) 移动可接受）。
    private var order = ArrayList<String>()          // 语句名，队尾 = 最近使用
    private let names = HashMap<String, String>()    // 语句名 -> SQL 文本
    private var hits = 0
    private var misses = 0
    private var evictions = 0
    private var fallbacks = 0                        // 执行失败回退 PQexecParams 的次数

    public init(capacity!: Int64 = CAPACITY_DEFAULT) {
        this.capacity = capacity
    }

    public func enabled(): Bool { capacity > 0 }

    /** 语句名（SQL 哈希 + 参数个数）。未启用缓存返回 ""。 */
    public func stmtName(sql: String, nParams: Int64): String {
        if (!enabled()) {
            return ""
        }
        "llpg_" + fnv1a64(sql).toString() + "_" + nParams.toString()
    }

    /** 命中则返回语句名并刷新 LRU；未命中返回 None（调用方负责 PQprepare）。 */
    public func lookup(name: String): ?String {
        if (!enabled() || name.isEmpty()) {
            return None
        }
        if (names.contains(name)) {
            touch(name)
            hits += 1
            return Some(name)
        }
        misses += 1
        return None
    }

    /** PQprepare 成功后登记。超出容量淘汰最旧。 */
    public func register(name: String, sql: String): Unit {
        if (!enabled() || name.isEmpty()) {
            return
        }
        if (names.contains(name)) {
            touch(name)
            return
        }
        while (order.size >= capacity) {
            let oldest = order[0]
            order.remove(at: 0)
            names.remove(oldest)
            evictions += 1
            // 注意：DEALLOCATE 由调用方（连接持有者）执行，这里只记淘汰名。
        }
        order.add(name)
        names[name] = sql
    }

    /** 取被淘汰（应 DEALLOCATE）的语句名（register 内部淘汰时无法通知调用方，改为显式两段式）。 */
    public func registerCollectingEvictions(name: String, sql: String, evicted: (String) -> Unit): Unit {
        if (!enabled() || name.isEmpty()) {
            return
        }
        if (names.contains(name)) {
            touch(name)
            return
        }
        while (order.size >= capacity) {
            let oldest = order[0]
            order.remove(at: 0)
            names.remove(oldest)
            evictions += 1
            evicted(oldest)
        }
        order.add(name)
        names[name] = sql
    }

    /** 语句执行失败（如 42P05/0A000）后从缓存移除并计入回退。 */
    public func invalidate(name: String): Unit {
        if (name.isEmpty()) {
            return
        }
        names.remove(name)
        let idx = listIndexOf(order, name)
        if (idx >= 0) {
            order.remove(at: idx)
        }
        fallbacks += 1
    }

    /** 全清（连接重置时）。 */
    public func clear(): Unit {
        order.clear()
        names.clear()
    }

    public func size(): Int64 { Int64(names.size) }
    public func hitCount(): Int64 { hits }
    public func missCount(): Int64 { misses }
    public func evictionCount(): Int64 { evictions }
    public func fallbackCount(): Int64 { fallbacks }

    private func touch(name: String): Unit {
        let idx = listIndexOf(order, name)
        if (idx >= 0) {
            order.remove(at: idx)
            order.add(name)
        }
    }
}

/** ArrayList<String> 线性查找（无 indexOf 成员）。 */
func listIndexOf(l: ArrayList<String>, v: String): Int64 {
    for (i in 0..l.size) {
        if (l[i] == v) {
            return i
        }
    }
    -1
}

/** FNV-1a 64：SQL 文本 -> 稳定哈希（用于语句名）。 */
public func fnv1a64(s: String): UInt64 {
    let bytes = s.toArray()
    var hash: UInt64 = 14695981039346656037u64
    for (b in bytes) {
        hash = mulMod2p64(hash ^ UInt64(b), 1099511628211u64)
    }
    hash
}

/**
 * 模 2^64 乘法（wrap 语义）：仓颉 UInt64 * 有溢出检查，FNV 需要自然回绕。
 * 32 位分解：a*b mod 2^64 = (高32位拼接 | 低32位)，其中
 *   ll  = aLo*bLo          (< 2^64，不溢出)
 *   mid = aLo*bHi + aHi*bLo (< 2^33，不溢出)
 * 结果高 32 位 = ((ll >> 32) + mid) 的低 32 位（更高位丢弃 = mod 2^64）；
 * 结果低 32 位 = ll 的低 32 位。全部中间量 <= 2^35，无溢出。
 */
func mulMod2p64(a: UInt64, b: UInt64): UInt64 {
    let aLo = a & 0xFFFFFFFFu64
    let aHi = a >> 32
    let bLo = b & 0xFFFFFFFFu64
    let bHi = b >> 32
    let ll = aLo * bLo
    let mid = aLo * bHi + aHi * bLo
    let hi = ((ll >> 32) + mid) & 0xFFFFFFFFu64
    let lo = ll & 0xFFFFFFFFu64
    return (hi << 32) | lo
}
