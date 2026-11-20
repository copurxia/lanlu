/*
 * 进程管理器的共享状态与刷新常量。
 *
 * 视图层只读取这里的 State/DerivedState：快照进度、字节数说明与“N 秒前刷新”
 * 全部由源状态派生，写入 output 或帧计数后无需手工同步任何展示字段。
 */
package cui_process_manager

import std.collection.ArrayList
import cui.{DerivedState, State, derive}

/* 自动刷新节奏。 */
struct Refresh {
    /** 两次自动刷新的最小间隔：tasklist 枚举全部进程有成本，5 秒足够跟上变化。 */
    static let INTERVAL_MS: UInt64 = 5000
    /** 毫秒到秒的换算基数，避免文案计算里出现裸写的 1000。 */
    static let MS_PER_SECOND: UInt64 = 1000
}

/* 快照大小进度条的参照刻度。 */
struct SnapshotGauge {
    /** 满格对应的快照字节数：典型 Windows 桌面的 tasklist 输出约为几万字节。 */
    static let FULL_BYTES: Float32 = 60000.0
}

class ProcessModel {
    let output = State<String>("正在载入进程快照……")
    /** 选中的进程行（原始行索引）；-1 表示未选中。 */
    let selectedRow = State<Int64>(-1)
    /** 由 output 解析出的进程表格行（映像名称、PID、会话名、内存 KB），供 Table 展示。 */
    let processRows: DerivedState<Array<Array<String>>>
    let tab = State<Int64>(0)
    /** 当前帧的启动毫秒计数，tick 每帧写入，是“几秒前”文案的时间基准。 */
    let nowTick = State<UInt64>(0)
    /** 上一份快照真正上屏时的帧计数；0 表示还没有任何快照完成。 */
    let refreshedTick = State<UInt64>(0)
    /** 上一次发起刷新请求的帧计数，供自动刷新做节流判断。 */
    let requestedTick = State<UInt64>(0)
    /** 快照大小换算成的进度条占比，由 output 派生。 */
    let snapshotFraction: DerivedState<Float32>
    /** 快照字节数说明文字，由 output 派生。 */
    let snapshotBytes: DerivedState<String>
    /** 距上次刷新完成的秒数文案，由当前帧与完成帧两个计数派生。 */
    let refreshAge: DerivedState<String>

    init() {
        this.snapshotFraction = this
            .output
            .map<Float32>({text => clampUnit(Float32(text.size) / SnapshotGauge.FULL_BYTES)})
        this.snapshotBytes = this.output.map<String>({text => "tasklist 返回 ${text.size} 字节"})
        this.refreshAge = derive(this.nowTick, this.refreshedTick, {now, done => refreshAgeText(now, done)})
        this.processRows = this.output.map<Array<Array<String>>>({text => parseProcessRows(text)})
    }
}

/*
 * 把 tasklist 的 CSV 输出（无表头，形如 "映像名称","PID","会话名","会话#","内存"）解析成表格行。
 * 每行取映像名称、PID、会话名与内存（换算成纯 KB 数字便于数值排序）。非 CSV 行（加载中/错误
 * 提示）被跳过，返回空表由视图回退到文本提示。
 */
func parseProcessRows(text: String): Array<Array<String>> {
    let rows = ArrayList<Array<String>>()
    for (line in text.split("\n", removeEmpty: true)) {
        let trimmed = line.trimAscii()
        if (!trimmed.startsWith("\"")) {
            continue
        }
        // 按字段边界 "," 切分（保留内存里的千分位逗号），再去掉残留的首尾引号。
        let fields = trimmed.split("\",\"")
        if (fields.size < 5) {
            continue
        }
        let name = fields[0].replace("\"", "")
        let pid = fields[1].replace("\"", "")
        let session = fields[2].replace("\"", "")
        let memory = memoryKb(fields[4].replace("\"", ""))
        rows.add([name, pid, session, memory])
    }
    rows.toArray()
}

/** 把 "1,234 K" 形式的内存用量归一成纯 KB 数字字符串 "1234"，供数值列排序。 */
func memoryKb(memory: String): String {
    memory.replace(",", "").replace(" ", "").replace("K", "")
}

/** 当前选中行对应进程的 PID；未选中或越界时为 None。行结构见 parseProcessRows。 */
func selectedPid(model: ProcessModel): ?String {
    let rows = model.processRows.value
    let index = model.selectedRow.value
    if (index < 0 || index >= rows.size) {
        return None
    }
    Some(rows[index][1])
}

/** 在快照行里按 PID 定位行索引；无选中或进程已退出时返回 -1（取消选中）。 */
func rowIndexOfPid(rows: Array<Array<String>>, pid: ?String): Int64 {
    match (pid) {
        case None => -1
        case Some(target) =>
            var i = 0
            while (i < rows.size) {
                if (rows[i][1] == target) {
                    return i
                }
                i += 1
            }
            -1
    }
}

/*
 * 把“当前帧 − 上次刷新完成”换算成状态栏文案。elapsedMs 是程序启动至今的绝对
 * 毫秒数，直接展示毫无意义，必须与完成时刻相减才是“距上次刷新”的真实时长。
 */
func refreshAgeText(now: UInt64, done: UInt64): String {
    if (done == 0) {
        return "正在启动"
    }
    // 完成帧内 now == done；显式钳制以防任何次序意外触发无符号下溢。
    let age = if (now >= done) {
        now - done
    } else {
        UInt64(0)
    }
    "${age / Refresh.MS_PER_SECOND} 秒前刷新"
}

/** 进度条占比只在 [0, 1] 内有意义，超长快照一律视为满格。 */
func clampUnit(value: Float32): Float32 {
    if (value > 1.0) {
        1.0
    } else if (value < 0.0) {
        0.0
    } else {
        value
    }
}
