package lanlu_client_next.net

import std.collection.ArrayList
import std.fs.{Directory, File, OpenMode, Path}
import std.time.MonoTime

private func makeBenchItems(count: Int64): ArrayList<SearchItem> {
    let items = ArrayList<SearchItem>()
    for (i in 0..count) {
        let item = SearchItem()
        item.arcid = "arc:bench:${i}"
        item.title = "档案 ${i}"
        item.description = "简介 ${i}"
        item.tagsCsv = "作者:甲,语言:中文"
        item.archivetype = "image"
        item.pagecount = 120
        item.progress = i % 100
        item.size = 4096
        items.add(item)
    }
    items
}

@Test
func perfBenchmarkSearchItemStoreAndQuery(): Unit {
    let path = Directory.createTemp(Path("/tmp")).toString()
    let cache = OfflineCache.open(path).getOrThrow()
    for (n in [1000, 10000, 100000]) {
        let items = makeBenchItems(n)
        let startWrite = MonoTime.now()
        let view = cache.storeSearchItems("srv", "acct", "bench:${n}", "zh",
            SearchItemView.memory("bench:${n}", "zh", items)).getOrThrow()
        let writeMs = (MonoTime.now() - startWrite).toMilliseconds()

        let startOpen = MonoTime.now()
        let reopened = cache.openSearchItems("srv", "acct", "bench:${n}", "zh").getOrThrow()
        let openMs = (MonoTime.now() - startOpen).toMilliseconds()

        // 冷读取：顺序扫前 100 条（热点窗口外）。
        var probe = SearchItemView.empty()
        probe = reopened
        let startRead = MonoTime.now()
        var total: Int64 = 0
        for (i in 0..min(100, probe.size)) {
            match (probe.itemAt(i)) {
                case Some(it) => total += it.pagecount
                case None => ()
            }
        }
        let readMs = (MonoTime.now() - startRead).toMilliseconds()
        // 全量物化对比（仅 100k 档）：顺序扫全部成员，模拟旧全量数组构造。
        var fullMs: Int64 = 0
        var fullCount: Int64 = 0
        if (n == 100000) {
            let startFull = MonoTime.now()
            for (i in 0..probe.size) {
                match (probe.itemAt(i)) {
                    case Some(_) => fullCount += 1
                    case None => ()
                }
            }
            fullMs = (MonoTime.now() - startFull).toMilliseconds()
        }
        let _ = File(Path("/tmp/lanlu-bench-${n}.txt"), OpenMode.Write).write(
            "writeMs=${writeMs}\nopenMs=${openMs}\nread100Ms=${readMs}\nfullScanMs=${fullMs}\nfullCount=${fullCount}\ntotal=${total}".toArray())
        @Expect(reopened.size, n)
    }
    cache.close()
}

@Test
func perfBenchmarkPrefixScanVsCursor(): Unit {
    let path = Directory.createTemp(Path("/tmp")).toString()
    let cache = OfflineCache.open(path).getOrThrow()
    let items = makeBenchItems(100000)
    let _ = cache.storeSearchItems("srv", "acct", "scan:100k", "zh",
        SearchItemView.memory("scan:100k", "zh", items)).getOrThrow()
    cache.close()
    println("BENCH scan prepared: 100000 objects in cache DB")
}
