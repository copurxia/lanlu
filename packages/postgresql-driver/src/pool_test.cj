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
