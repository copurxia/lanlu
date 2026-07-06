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
    let cfg: PoolConfig
    let mtx = Mutex()
    let cond: Condition
    let idle = ArrayList<CPointer<Unit>>()
    let idleSince = ArrayList<Int64>()
    var total: Int64 = 0
    var closed = false

    public init(cfg: PoolConfig, connect: () -> CPointer<Unit>, disconnect: (CPointer<Unit>) -> Unit) {
        this.cfg = cfg
        this.connect = connect
        this.disconnect = disconnect
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

    /** 借一条连接：有空闲直接复用;无空闲且未达上限则新建;已达上限则阻塞等归还。 */
    public func borrow(): CPointer<Unit> {
        mtx.lock()
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
                cond.wait()
            }
            throw PGError("ConnectionPool: unreachable")
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
