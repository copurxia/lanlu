package lanlu_client_next.img

import std.collection.{ArrayList, HashMap, HashSet}
import std.fs.{exists, removeIfExists, rename, Directory, File, OpenMode, Path}
import std.io.OutputStream
import std.sort.sort
import std.sync.{Condition, Mutex}
import std.time.DateTime

// 缓存 key → 安全文件名：仅保留 ASCII 字母/数字和 . - _，其余一律替换为 _。
public func sanitizeKey(s: String): String {
    let out = ArrayList<UInt8>(s.size)
    for (b in s.toArray()) {
        let ok = (b >= 0x61u8 && b <= 0x7Au8) || (b >= 0x41u8 && b <= 0x5Au8) ||
            (b >= 0x30u8 && b <= 0x39u8) || b == 0x2Eu8 || b == 0x2Du8 || b == 0x5Fu8
        out.add(if (ok) { b } else { 0x5Fu8 })
    }
    String.fromUtf8(out.toArray())
}

// 缓存写入回调接口：把原始字节流式写入 output，返回写入字节数。
// 用接口而非函数闭包：仓颉 1.1.3 运行时存在缺陷——被函数参数传递的闭包在 spawn
// 线程中调用时若写捕获的引用字段会触发 GC WriteStaticRef 屏障 SIGSEGV；接口方法
// 调用不触发（探针验证）。
public interface CacheWriter {
    func writeTo(output: OutputStream): Int64
}

// single-flight 门闩：leader 下载期间等待者阻塞在 cond 上；done 后携带结果
//（成功 = 文件已定稿，失败 = 同一异常，等待者原样抛出）。cond 绑定本门闩的 mutex，
// 且必须在持有该锁时创建（std.sync 约定）。
private class DownloadGate {
    let mutex = Mutex()
    let cond: Condition
    var done = false
    var failure: ?Exception = None
    init() {
        cond = synchronized(mutex) { mutex.condition() }
    }
}

// 磁盘图片缓存：key → <root>/<sanitize(key)>.img，存原始编码字节（AVIF/JPEG/PNG 原样）。
// 未命中时 writer 流式写入 .bin，再原子 rename 定稿（半成品不暴露给解码方）。
// 同一 relKey 的并发未命中由 single-flight 保证只允许一个下载者，其余等待定稿结果；
// 下载者失败时等待者抛同一异常（其上层任务置 error，重试可重新拉取）。
public class ImageCache {
    private let root: String
    // single-flight：relKey → 在途下载门闩。锁保护；leader 完成（成败都算）后移除并通知。
    private let flightMutex = Mutex()
    private var flightGates = HashMap<String, DownloadGate>()
    // 解码中引用（P2.9）：sweep 不得删除正被解码的 .img。同一把锁保护。
    private var referencedKeys = HashSet<String>()

    public init(root: String) {
        this.root = root
        // cjc 1.1.3 的 Directory.create 对已存在目录抛异常，先判断。
        if (!exists(Path(root))) {
            Directory.create(Path(root), recursive: true)
        }
    }

    private func imgPath(relKey: String): String { "${root}/${sanitizeKey(relKey)}.img" }
    private func binPath(relKey: String): String { "${root}/${sanitizeKey(relKey)}.bin" }

    // 命中直接返回；未命中：writer 把原始字节流式写入同目录唯一 .bin 临时文件，
    // flush/close 成功后原子 rename 定稿为 .img。writer 返回写入字节数；返回 0
    // 视为空响应，不生成正式缓存文件。任意失败路径清理 .bin 后重新抛出。
    // 并发未命中同一 relKey 时：只有第一个调用者执行下载，其余在门闩上等待定稿结果。
    public func ensureCached(relKey: String, writer: CacheWriter): String {
        let dst = imgPath(relKey)
        if (exists(Path(dst))) { return dst }
        let gate: DownloadGate
        var isLeader = false
        synchronized(flightMutex) {
            match (flightGates.get(relKey)) {
                case Some(g) => gate = g
                case None =>
                    gate = DownloadGate()
                    flightGates[relKey] = gate
                    isLeader = true
            }
        }
        if (!isLeader) {
            // 等待者：等 leader 定稿（成功或失败都会唤醒），命中即返回，失败抛同一异常。
            // cond 绑定 gate.mutex，wait 必须持有该锁（std.sync 约定）。
            synchronized(gate.mutex) {
                while (!gate.done) {
                    gate.cond.wait()
                }
            }
            if (exists(Path(dst))) { return dst }
            match (gate.failure) {
                case Some(e) => throw e
                case None => throw Exception("图片下载未完成")
            }
        }
        // leader：下载并定稿；成败都通知等待者并移出门闩。
        var failure: ?Exception = None
        try {
            return finalize(relKey, dst, writer)
        } catch (e: Exception) {
            failure = Some(e)
            throw e
        } finally {
            synchronized(gate.mutex) {
                gate.done = true
                gate.failure = failure
                gate.cond.notifyAll()
            }
            synchronized(flightMutex) {
                flightGates.remove(relKey)
            }
        }
    }

    // 未命中时的实际下载与定稿：临时文件 → flush/close → 原子 rename；失败清 .bin。
    private func finalize(relKey: String, dst: String, writer: CacheWriter): String {
        let bin = binPath(relKey)
        let f = File(Path(bin), OpenMode.Write)
        var written: Int64 = 0
        try {
            written = writer.writeTo(f)
            f.flush()
            f.close()
        } catch (e: Exception) {
            try { f.close() } catch (_: Exception) { () }
            removeIfExists(Path(bin), recursive: false)
            throw e
        }
        if (written <= 0) {
            removeIfExists(Path(bin), recursive: false)
            throw Exception("图片内容为空")
        }
        try {
            rename(Path(bin), to: Path(dst), overwrite: true)
        } catch (e: Exception) {
            removeIfExists(Path(bin), recursive: false)
            throw e
        }
        dst
    }

    public func totalBytes(): Int64 {
        var total: Int64 = 0
        if (!exists(Path(root))) { return 0 }
        // 缓存目录是扁平的，readFrom 一层即可（walk 的回调不能捕获可变变量）。
        for (info in Directory.readFrom(Path(root))) {
            total += info.size
        }
        return total
    }

    public func clear(): Unit {
        removeIfExists(Path(root), recursive: true)
        Directory.create(Path(root), recursive: true)
    }

    // 剔除指定 key 已定稿的 .img（解码失败重试前调用）；文件不存在时静默。
    // 删除本身的 I/O 失败会抛给调用方，调用方需自行兜底（见 model 的图片任务）。
    public func evict(relKey: String): Unit {
        removeIfExists(Path(imgPath(relKey)), recursive: false)
    }

    // 解码引用标记（P2.9）：解码开始前 mark、结束（成败都算）后 clear，sweep 跳过
    // 被引用的 .img，避免删除正在被 vips 打开的文件导致解码失败重拉。
    public func markReferenced(relKey: String): Unit {
        synchronized(flightMutex) {
            referencedKeys.add(relKey)
        }
    }

    public func clearReferenced(relKey: String): Unit {
        synchronized(flightMutex) {
            referencedKeys.remove(relKey)
        }
    }

    private func isReferenced(relKey: String): Bool {
        synchronized(flightMutex) {
            referencedKeys.contains(relKey)
        }
    }

    // 简单 LRU：按修改时间升序删到阈值内。
    // 基准（P2.9）：缓存目录扁平，一次 Directory.readFrom + sort 在 1 万文件内 <10ms，
    // 当前单服务器规模（千级文件）保留全量实现；若实测过万再改增量索引（逻辑访问时间
    // 持久化），不做无收益重构。
    // 竞态缓解：在途下载（.bin）被 single-flight 门闩与超龄清理规则保护；解码中的 .img
    // 经 markReferenced 跳过；其余窗口按 mtime 最旧优先删除（刚定稿、即将被解码的文件
    // mtime 最新，最后被考虑），解码侧打开失败会置 error 态自愈重拉。
    public func sweep(maxBytes: Int64, staleBinMs!: Int64 = 24 * 3600 * 1000): Unit {
        if (!exists(Path(root))) { return }
        let nowMs = DateTime.now().toUnixTimeStamp().toMilliseconds()
        let entries = ArrayList<(Int64, String, Int64)>()  // (mtimeMs, path, size)
        for (info in Directory.readFrom(Path(root))) {
            if (info.name.endsWith(".bin")) {
                // 超龄 .bin = 异常退出遗留的半成品，清理；正常在途下载的 .bin mtime 新鲜
                //（single-flight 门闩保证同一 key 只有一个写者，24h 内不可能超龄）。
                let age = nowMs - info.lastModificationTime.toUnixTimeStamp().toMilliseconds()
                if (age > staleBinMs) {
                    removeIfExists(Path(info.path.toString()), recursive: false)
                }
                continue
            }
            // 候选 = 目录内除 .bin 外的所有文件（旧管线遗留的 .png 等一并纳入清理），
            // 解码中引用的 key 跳过。
            if (!isReferenced(info.name.removeSuffix(".img"))) {
                entries.add((info.lastModificationTime.toUnixTimeStamp().toMilliseconds(), info.path.toString(), info.size))
            }
        }
        var total: Int64 = 0
        for (e in entries) { total += e[2] }
        if (total <= maxBytes) { return }
        sort(entries, lessThan: { a, b => a[0] < b[0] })
        for (e in entries) {
            if (total <= maxBytes) { break }
            removeIfExists(Path(e[1]), recursive: false)
            total -= e[2]
        }
    }
}
