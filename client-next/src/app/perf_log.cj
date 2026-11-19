package lanlu_client_next.app

import std.env.getVariable
import std.fs.{File, OpenMode}
import std.sync.Mutex
import std.time.MonoTime

/**
 * 性能/诊断日志落盘（跨平台，无平台专有标识）。
 *
 * 为什么需要：引擎的 println 在 HarmonyOS 上不进 hilog，真机联调时看不到
 * [video-perf]/[subtitle-bench] 这类输出。LANLU_PERF_LOG=1 时把它们同时写入
 * $HOME/perf.txt，便于 hdc 取回核对（字幕上传数、帧率等）。
 *
 * G2 改动：旧实现每次 perfLog 都 `getVariable` ×2 + open-append-close（字幕播放时
 * 每帧一行 = 每帧 3 次文件系统调用）。现在环境变量启动期读一次，文件句柄进程级
 * 复用，行先进内存缓冲，按"缓冲 ≥ 8KB 或 距上次 flush ≥ 500ms"落盘——字幕逐帧
 * 打点时从每帧 3 次 syscall 降到约 1 次/半秒。进程退出时的最后 ≤500ms 行可能
 * 仍在缓冲里：需要"退出必落盘"的话在 main 的收尾处调 perfLogFlush()（见 G2 执行记录）。
 */

// 启动期一次性读取（perfLog 出现在字幕逐帧等高频路径上，不再反复 getVariable）。
private let PERF_LOG_ENABLED: Bool = getVariable("LANLU_PERF_LOG") == Some("1")
private let PERF_LOG_HOME: String = getVariable("HOME") ?? "."

private const PERF_LOG_FLUSH_BYTES: Int64 = 8192
private const PERF_LOG_FLUSH_INTERVAL_MS: Int64 = 500

// 并发保护：perfLog 是 public API，UI 线程（帧循环）与 worker 线程（字幕/解码）都
// 可能调用；无锁时 StringBuilder/File 上的并发 append 会丢行或串内容。
private let PERF_LOG_MUTEX = Mutex()
private var perfLogFile: ?File = None
private var perfLogBuffer = StringBuilder()
private var perfLogLastFlush: MonoTime = MonoTime.now()
private var perfLogOpened = false

public func perfLogEnabled(): Bool {
    return PERF_LOG_ENABLED
}

/// 立即把缓冲落盘（周期 flush 由 perfLog 自动触发；进程退出前可手动调用）。
/// 线程安全（内部加锁），可在任意线程调用。
public func perfLogFlush(): Unit {
    synchronized(PERF_LOG_MUTEX) {
        perfLogFlushLocked()
    }
}

/// 调用方必须持有 PERF_LOG_MUTEX（Mutex 不可重入，拆出锁定版供 perfLog 复用）。
private func perfLogFlushLocked(): Unit {
    if (!perfLogOpened || perfLogBuffer.size == 0) {
        return
    }
    let body = perfLogBuffer.toString().toArray()
    try {
        match (perfLogFile) {
            case Some(f) => f.write(body)
            case None => ()
        }
    } catch (_) {}
    perfLogBuffer.reset()
    perfLogLastFlush = MonoTime.now()
}

/// 调用方必须持有 PERF_LOG_MUTEX。
private func perfLogEnsureFileLocked(): Unit {
    if (perfLogOpened) {
        return
    }
    perfLogOpened = true
    try {
        perfLogFile = Some(File(PERF_LOG_HOME + "/perf.txt", OpenMode.Append))
    } catch (_) {
        // Append 失败（如目录不可写）时退回截断写一次的旧行为兜底。
        try {
            perfLogFile = Some(File(PERF_LOG_HOME + "/perf.txt", OpenMode.Write))
        } catch (_) {
            perfLogFile = None
        }
    }
}

public func perfLog(line: String): Unit {
    if (!PERF_LOG_ENABLED) {
        return
    }
    synchronized(PERF_LOG_MUTEX) {
        perfLogBuffer.append(line)
        perfLogBuffer.append("\n")
        perfLogEnsureFileLocked()
        if (Int64(perfLogBuffer.size) >= PERF_LOG_FLUSH_BYTES ||
            (MonoTime.now() - perfLogLastFlush).toMilliseconds() >= PERF_LOG_FLUSH_INTERVAL_MS) {
            perfLogFlushLocked()
        }
    }
}
