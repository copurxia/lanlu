package postgresql_driver

import std.collection.*
import std.convert.*
import std.sync.*
import std.time.*

/**
 * 通用连接池：池化底层 PGconn 句柄(CPointer<Unit>)。
 * 并发模型：Mutex + Condition。空闲连接放 idle 栈(LIFO);借时优先复用空闲,
 * 否则未达上限则新建(在锁外执行避免阻塞),达上限则 wait 等归还。
 * 连接的新建/销毁由构造时传入的 connect/disconnect 闭包完成。
 */
public class ConnectionPool {
    let connect: () -> CPointer<Unit>
    let disconnect: (CPointer<Unit>) -> Unit
    // 借出校验（如 libpq 的 PQstatus == CONNECTION_OK）。返回 false 的连接
    // 会被断开并从池中移除，再借时新建；避免 PG 重启/网络抖动后把陈旧连接
    // 交给业务（原实现会直接抛 SQL 失败，直到 idleTimeout 回收才恢复）。
    let validate: (CPointer<Unit>) -> Bool
    let cfg: PoolConfig
    let mtx = Mutex()
    let cond: Condition
    let idle = ArrayList<CPointer<Unit>>()
    let idleSince = ArrayList<Int64>()
    var total: Int64 = 0
    var closed = false
    var waiting: Int64 = 0
    var borrowTimeoutCount: Int64 = 0

    public init(cfg: PoolConfig, connect: () -> CPointer<Unit>, disconnect: (CPointer<Unit>) -> Unit,
        validate!: (CPointer<Unit>) -> Bool = { _ => true }) {
        this.cfg = cfg
        this.connect = connect
        this.disconnect = disconnect
        this.validate = validate
        this.cond = synchronized(mtx) {
            mtx.condition()
        }
        var made = 0
        while (made < cfg.minSize) {
            let c = connect()
            synchronized(mtx) {
                idle.add(c)
                idleSince.add(nowMillis())
                total += 1
            }
            made += 1
        }
    }

    public func idleCount(): Int64 {
        synchronized(mtx) { Int64(idle.size) }
    }

    public func size(): Int64 {
        synchronized(mtx) { total }
    }

    /** 当前阻塞在 borrow 等待队列中的数量（饱和监控指标）。 */
    public func waitingCount(): Int64 {
        synchronized(mtx) { waiting }
    }

    /** borrow 超时累计次数（饱和监控指标）。 */
    public func borrowTimeouts(): Int64 {
        synchronized(mtx) { borrowTimeoutCount }
    }

    /** 借一条连接：有空闲直接复用;无空闲且未达上限则新建;已达上限则限时等待归还，超时抛 PGError。 */
    public func borrow(): CPointer<Unit> {
        mtx.lock()
        try {
            waiting += 1
            try {
                while (true) {
                    if (closed) {
                        throw PGError("ConnectionPool: pool closed")
                    }
                    reapIdleLocked()
                    if (!idle.isEmpty()) {
                        let last = idle.size - 1
                        let c = idle[last]
                        idle.remove(at: last)
                        idleSince.remove(at: last)
                        if (!validate(c)) {
                            // 陈旧连接：池已关闭则直接销毁，否则在锁外断开并调整计数，
                            // 继续循环重借（未达上限时会新建）。
                            total -= 1
                            mtx.unlock()
                            disconnect(c)
                            mtx.lock()
                            cond.notify()
                            continue
                        }
                        return c
                    }
                    if (total < cfg.maxSize) {
                        total += 1
                        mtx.unlock()
                        let made = try {
                            connect()
                        } catch (e: Exception) {
                            mtx.lock()
                            total -= 1
                            cond.notify()
                            throw e
                        }
                        mtx.lock()
                        return made
                    }
                    // 饱和：限时等待归还，避免慢查询占池导致全站无界排队。
                    if (cfg.borrowTimeoutMs > 0) {
                        let notified = cond.wait(timeout: Duration.millisecond * cfg.borrowTimeoutMs)
                        if (!notified) {
                            // 超时醒来后仍持锁；再检查一次空闲（notify 后竞争失败的兜底）。
                            reapIdleLocked()
                            if (!idle.isEmpty()) {
                                let last = idle.size - 1
                                let c = idle[last]
                                idle.remove(at: last)
                                idleSince.remove(at: last)
                                if (!validate(c)) {
                                    total -= 1
                                    mtx.unlock()
                                    disconnect(c)
                                    mtx.lock()
                                    cond.notify()
                                    continue
                                }
                                return c
                            }
                            borrowTimeoutCount += 1
                            // SQLSTATE 用类池超时代码（非 libpq 标准码，前缀 P1 避免与
                            // PG 官方码冲突），供应用层识别并转 503。
                            throw PGError(
                                "ConnectionPool: borrow timed out after ${cfg.borrowTimeoutMs.toString()}ms " +
                                "(pool saturated: max=${cfg.maxSize.toString()}, waiting=${waiting.toString()})",
                                sqlstate: "P1001")
                        }
                    } else {
                        cond.wait()
                    }
                }
                throw PGError("ConnectionPool: unreachable")
            } finally {
                waiting -= 1
            }
        } finally {
            mtx.unlock()
        }
    }

    /** 归还连接：池未关则入空闲栈并唤醒等待者;池已关则直接销毁。 */
    public func giveBack(c: CPointer<Unit>): Unit {
        synchronized(mtx) {
            if (closed) {
                disconnect(c)
                total -= 1
            } else {
                idle.add(c)
                idleSince.add(nowMillis())
                reapIdleLocked()
            }
            cond.notify()
        }
    }

    /** 关闭池：销毁所有空闲连接并置关闭位(借出的连接将在归还时销毁)。 */
    public func closeAll(): Unit {
        synchronized(mtx) {
            for (c in idle) {
                disconnect(c)
            }
            total -= Int64(idle.size)
            idle.clear()
            idleSince.clear()
            closed = true
            cond.notifyAll()
        }
    }

    /** 惰性回收：关闭并移除空闲超时且总数仍高于 minSize 的连接。调用方须持锁。 */
    func reapIdleLocked(): Unit {
        if (cfg.idleTimeoutMs <= 0) {
            return
        }
        let now = nowMillis()
        while (!idle.isEmpty() && total > cfg.minSize) {
            if (now - idleSince[0] < cfg.idleTimeoutMs) {
                break
            }
            let c = idle[0]
            idle.remove(at: 0)
            idleSince.remove(at: 0)
            disconnect(c)
            total -= 1
        }
    }

    public func reapIdle(): Unit {
        synchronized(mtx) {
            if (!closed) {
                reapIdleLocked()
            }
        }
    }
}

func nowMillis(): Int64 {
    DateTime.nowUTC().toUnixTimeStamp().toMilliseconds()
}
