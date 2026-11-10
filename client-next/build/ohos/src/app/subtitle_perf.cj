package lanlu_client_next.app

import std.collection.{ArrayList, HashMap}
import std.convert.Parsable
import std.env.getVariable
import std.fs.{File, Path, exists}
import std.sort.sort
import std.sync.Mutex
import std.time.MonoTime

// 门控性能埋点（LANLU_PERF=1 时启用，默认关闭零开销）。
// 供真实媒体播放/字幕切换基准采集 todo.md P8 的六项指标；非产品功能。
// 所有计时基于 MonoTime（单调时钟，不受系统时钟调整影响），跨线程安全（进程级共享）。

public class SubtitlePerf {
    private static let _enabled = getVariable("LANLU_PERF") == Some("1")
    // 逐条明细日志门控（LANLU_PERF_VERBOSE=1）：洪泛期逐图 println 本身即是 pump 尖刺
    // 来源，默认只保留聚合采样，明细需显式打开（仍需 LANLU_PERF=1 才生效）。
    private static let _verbose = getVariable("LANLU_PERF_VERBOSE") == Some("1")
    private static let lock = Mutex()
    // 命名区间起点（覆盖式：同名重新 start 即覆盖）。
    private static let spans = HashMap<String, MonoTime>()
    // 命名计时样本（微秒），用于 percentile 汇总。
    private static let samples = HashMap<String, ArrayList<Int64>>()
    // 命名累计计数与一次性 gauge（微秒/字节等）。
    private static let counters = HashMap<String, Int64>()
    private static let gauges = HashMap<String, Int64>()

    public static func enabled(): Bool {
        _enabled
    }

    // 逐条明细日志是否输出（LANLU_PERF=1 且 LANLU_PERF_VERBOSE=1）。
    public static func verbose(): Bool {
        _enabled && _verbose
    }

    // ---- 区间计时（跨函数配对用）----

    public static func spanStart(name: String): Unit {
        if (_enabled) {
            synchronized(lock) {
                spans[name] = MonoTime.now()
            }
        }
    }

    // 结束区间并记录耗时（毫秒）；区间未开始时静默忽略。
    public static func spanEnd(name: String): Unit {
        if (!_enabled) {
            return
        }
        synchronized(lock) {
            match (spans.get(name)) {
                case Some(start) =>
                    let ms = (MonoTime.now() - start).toMilliseconds()
                    spans.remove(name)
                    gauges[name] = ms
                case None => ()
            }
        }
    }

    // ---- 计时样本（分布指标用）----

    public static func sampleUs(name: String, us: Int64): Unit {
        if (!_enabled) {
            return
        }
        synchronized(lock) {
            match (samples.get(name)) {
                case Some(list) => list.add(us)
                case None =>
                    let list = ArrayList<Int64>()
                    list.add(us)
                    samples[name] = list
            }
        }
    }

    // ---- 计数 / gauge ----

    public static func countAdd(name: String, delta: Int64): Unit {
        if (!_enabled) {
            return
        }
        synchronized(lock) {
            counters[name] = (counters.get(name) ?? 0) + delta
        }
    }

    public static func gauge(name: String, value: Int64): Unit {
        if (!_enabled) {
            return
        }
        synchronized(lock) {
            gauges[name] = value
        }
    }

    // ---- 读取 ----

    public static func getGauge(name: String): Int64 {
        synchronized(lock) {
            gauges.get(name) ?? 0
        }
    }

    public static func getCounter(name: String): Int64 {
        synchronized(lock) {
            counters.get(name) ?? 0
        }
    }

    // 返回 (p50, p99, count)，单位微秒；无样本时全 0。
    public static func percentiles(name: String): (Int64, Int64, Int64) {
        synchronized(lock) {
            match (samples.get(name)) {
                case Some(list) =>
                    if (list.size == 0) {
                        return (0, 0, 0)
                    }
                    sort(list)
                    let p50 = list[list.size / 2]
                    let p99 = list[list.size * 99 / 100]
                    (p50, p99, list.size)
                case None => (0, 0, 0)
            }
        }
    }

    // ---- 进程内存（Linux；非 /proc 平台返回 0）----

    public static func rssHwmBytes(): Int64 {
        statusField("VmHWM")
    }

    public static func rssBytes(): Int64 {
        statusField("VmRSS")
    }

    private static func statusField(key: String): Int64 {
        if (!_enabled) {
            return 0
        }
        let path = "/proc/self/status"
        try {
            if (!exists(Path(path))) {
                return 0
            }
            for (line in String.fromUtf8(File.readFrom(Path(path))).split("\n")) {
                if (line.startsWith("${key}:")) {
                    // "VmHWM:     12345 kB" -> 取数字部分（kB）。
                    let parts = line.removePrefix("${key}:").trimAscii().split(" ")
                    for (part in parts) {
                        if (part.size > 0) {
                            return Int64.parse(part) * 1024
                        }
                    }
                }
            }
            0
        } catch (_: Exception) {
            0
        }
    }

    // ---- 输出 ----

    // 输出一个机器可读结果行（供 runner 解析），并附人读 [perf] 行。
    public static func emit(name: String, value: Int64, unit: String): Unit {
        if (!_enabled) {
            return
        }
        println("@@RESULT|${name}|${value}|${unit}")
        println("[perf] ${name}=${value}${unit}")
    }

    // 输出全部计时样本的分位数，并清空该样本集。
    public static func flushSamples(name: String): Unit {
        if (!_enabled) {
            return
        }
        let (p50, p99, count) = percentiles(name)
        if (count == 0) {
            return
        }
        println("@@RESULT|${name}_p50_us|${p50}|us")
        println("@@RESULT|${name}_p99_us|${p99}|us")
        println("@@RESULT|${name}_count|${count}|n")
        println("[perf] ${name} p50=${p50}us p99=${p99}us count=${count}")
        synchronized(lock) {
            samples.remove(name)
        }
    }

    // 清空全部状态（基准各阶段之间复用）。
    public static func reset(): Unit {
        synchronized(lock) {
            spans.clear()
            samples.clear()
            counters.clear()
            gauges.clear()
        }
    }
}
