package lanlu_client_next.app

import lanlu_client_next.net.SearchItem
import std.collection.ArrayList
import std.unittest.*
import std.unittest.testmacro.*

// D1 回归：书架派生数据（可见列表 / 历史计数 / 最近在读）必须按视图条件缓存。
// 条件不变时不能再遍历 SearchItemView —— 那是 UI 线程上每帧数千次 RocksDB 点查。
// 判据：同一个 key 第二次调用必须返回缓存对象（构造出来的 99 不应出现）。

private func emptyDerived(count: Int64): ShelfDerived {
    ShelfDerived(ArrayList<SearchItem>(), count, None)
}

@Test
func shelfDerivedCacheReusesResultForSameKey(): Unit {
    let m = AppModel(AppSettings())
    let first = m.shelfDerived("k1", {=> emptyDerived(1)})
    let second = m.shelfDerived("k1", {=> emptyDerived(99)})
    @Expect(first.historyCount, 1)
    // 命中缓存：仍是第一次的结果
    @Expect(second.historyCount, 1)
}

@Test
func shelfDerivedCacheInvalidatesOnDataChange(): Unit {
    let m = AppModel(AppSettings())
    let first = m.shelfDerived("k", {=> emptyDerived(1)})
    @Expect(first.historyCount, 1)
    m.invalidateShelfDerived()
    let after = m.shelfDerived("k", {=> emptyDerived(3)})
    @Expect(after.historyCount, 3)
}

@Test
func shelfDerivedDifferentKeysAreComputedSeparately(): Unit {
    let m = AppModel(AppSettings())
    let a = m.shelfDerived("tab0", {=> emptyDerived(1)})
    let b = m.shelfDerived("tab1", {=> emptyDerived(2)})
    @Expect(a.historyCount, 1)
    @Expect(b.historyCount, 2)
    // 回到旧 key 时必须重算（只保留最近一次缓存），不能串数据
    let a2 = m.shelfDerived("tab0", {=> emptyDerived(7)})
    @Expect(a2.historyCount, 7)
}
