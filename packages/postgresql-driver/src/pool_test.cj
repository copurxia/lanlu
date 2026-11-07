package postgresql_driver

import std.sync.*
import std.time.*

/**
 * 连接池并发语义测试（无需真实数据库，使用假连接闭包）。
 *
 * 覆盖：
 * - 借出超时：饱和时 borrow 在 borrowTimeoutMs 内抛 PGError，且计数生效
 * - 归还唤醒：饱和等待者被 giveBack 唤醒后拿到连接
 * - 关闭语义：closeAll 后 borrow 抛错
 * - 连接串解析：pool.borrowTimeout 键进入 PoolConfig
 */
private class FakeConnRegistry {
    static let mtx = Mutex()
    static var connects = 0
    static var disconnects = 0

    static func reset(): Unit {
        synchronized(mtx) {
            connects = 0
            disconnects = 0
        }
    }

    static func fakeConnect(): CPointer<Unit> {
        synchronized(mtx) {
            connects += 1
            // 分配 1 字节真实堆内存作假连接句柄（free 在 disconnect 计数后执行）
            return unsafe { CPointer<Unit>(LibC.malloc<UInt8>(count: 1)) }
        }
    }

    static func fakeDisconnect(c: CPointer<Unit>): Unit {
        synchronized(mtx) {
            disconnects += 1
        }
        unsafe { LibC.free(c) }
    }
}

func newFakePool(maxSize: Int64, borrowTimeoutMs: Int64): ConnectionPool {
    return ConnectionPool(
        PoolConfig(maxSize, 0, 0, borrowTimeoutMs: borrowTimeoutMs),
        { => FakeConnRegistry.fakeConnect() },
        { c => FakeConnRegistry.fakeDisconnect(c) }
    )
}

@Test
func testBorrowTimesOutWhenSaturated() {
    FakeConnRegistry.reset()
    let pool = newFakePool(1, 100)
    let held = pool.borrow()
    let start = MonoTime.now()
    var timedOut = false
    try {
        let _ = pool.borrow()
    } catch (_: Exception) {
        timedOut = true
    }
    let elapsedMs = (MonoTime.now() - start).toMilliseconds()
    @Assert(timedOut, true)
    // 超时应发生在 [100ms, 2000ms] 窗口内（宽松上界防 CI 抖动）
    @Assert(elapsedMs >= 100, true)
    @Assert(elapsedMs < 2000, true)
    @Assert(pool.borrowTimeouts(), 1)
    pool.giveBack(held)
    pool.closeAll()
}

@Test
func testBorrowWakesOnGiveBack() {
    FakeConnRegistry.reset()
    let pool = newFakePool(1, 3000)
    let held = pool.borrow()

    let got = Array<CPointer<Unit>>(1, { _ => CPointer<Unit>() })
    let ok = Array<Bool>(1, { _ => false })
    let waiter = spawn {
        try {
            got[0] = pool.borrow()
            ok[0] = true
        } catch (_: Exception) {
            ok[0] = false
        }
    }
    sleep(100 * Duration.millisecond)
    @Assert(pool.waitingCount() >= 1, true)
    pool.giveBack(held)
    let _ = waiter.get()
    @Assert(ok[0], true)
    @Assert(!got[0].isNull(), true)
    pool.closeAll()
}

@Test
func testBorrowThrowsOnClosedPool() {
    FakeConnRegistry.reset()
    let pool = newFakePool(2, 1000)
    let _ = pool.borrow()
    pool.closeAll()
    var threw = false
    try {
        let _ = pool.borrow()
    } catch (_: Exception) {
        threw = true
    }
    @Assert(threw, true)
}

@Test
func testPoolStatsReflectState() {
    FakeConnRegistry.reset()
    let pool = newFakePool(4, 5000)
    let c1 = pool.borrow()
    let c2 = pool.borrow()
    @Assert(pool.size(), 2)
    pool.giveBack(c1)
    @Assert(pool.idleCount(), 1)
    @Assert(pool.waitingCount(), 0)
    pool.giveBack(c2)
    pool.closeAll()
}

@Test
func testConninfoParsesBorrowTimeout() {
    // URL 形式
    let (_, cfg1) = parseConnString("postgres://u:p@h:5432/db?pool.max=3&pool.borrowTimeout=2500")
    @Assert(cfg1.maxSize, 3)
    @Assert(cfg1.borrowTimeoutMs, 2500)

    // keyword 形式
    let (_, cfg2) = parseConnString("host=h port=5432 user=u dbname=d pool.max=5 pool.borrowTimeout=800")
    @Assert(cfg2.maxSize, 5)
    @Assert(cfg2.borrowTimeoutMs, 800)

    // 未指定时取默认 5000
    let (_, cfg3) = parseConnString("postgres://u:p@h:5432/db")
    @Assert(cfg3.borrowTimeoutMs, 5000)

    // 0 表示禁用超时（无限等待）
    let (_, cfg4) = parseConnString("postgres://u:p@h:5432/db?pool.borrowTimeout=0")
    @Assert(cfg4.borrowTimeoutMs, 0)
}

@Test
func testBorrowSkipsBrokenIdleConn() {
    FakeConnRegistry.reset()
    let validatorCalls = AtomicInt64(0)
    let firstCheck = AtomicBool(true) // 第一次校验判坏 → 丢弃重建
    let pool = ConnectionPool(
        PoolConfig(2, 0, 0, borrowTimeoutMs: 5000),
        { => FakeConnRegistry.fakeConnect() },
        { c => FakeConnRegistry.fakeDisconnect(c) },
        validate: { _ =>
            let _ = validatorCalls.fetchAdd(1)
            let v = !firstCheck.load()
            firstCheck.store(false)
            return v
        }
    )
    let c1 = pool.borrow()
    pool.giveBack(c1)
    let c2 = pool.borrow()
    @Assert(!c2.isNull(), true)
    @Assert(pool.size(), 1)
    @Assert(validatorCalls.load() >= 1)
    pool.giveBack(c2)
    pool.closeAll()
}

@Test
func testAffectedRowsThreadIsolated() {
    // lastAffected 改为 ThreadLocal 后：A 线程 exec 的受影响行数
    // 不应被 B 线程的 exec 覆盖。用 DB_STRING 可用时真实验证，否则跳过。
    let dbOpt = openOrSkip()
    match (dbOpt) {
        case None => return
        case Some(db) =>
            let aResult = Array<Int64>(1, { _ => -1 })
            let bResult = Array<Int64>(1, { _ => -1 })
            db.exec("CREATE TABLE IF NOT EXISTS _t_affected(x INT)", [])
            let t1 = spawn {
                db.exec("DELETE FROM _t_affected", []) // 0 行
                sleep(50 * Duration.millisecond)        // 等 B 线程写入它的值
                aResult[0] = db.affectedRows()
            }
            let t2 = spawn {
                db.exec("INSERT INTO _t_affected VALUES (1),(2)", []) // 2 行
                bResult[0] = db.affectedRows()
            }
            let _ = t1.get()
            let _ = t2.get()
            @Assert(aResult[0], 0)
            @Assert(bResult[0], 2)
            db.exec("DROP TABLE IF EXISTS _t_affected", [])
            db.close()
    }
}
