package lanlu_client_next.app

import std.env.getVariable
import std.fs.{File, OpenMode}

/**
 * 性能/诊断日志落盘（跨平台，无平台专有标识）。
 *
 * 为什么需要：引擎的 println 在 HarmonyOS 上不进 hilog，真机联调时看不到
 * [video-perf]/[subtitle-bench] 这类输出。LANLU_PERF_LOG=1 时把它们同时写入
 * $HOME/perf.txt，便于 hdc 取回核对（字幕上传数、帧率等）。
 */
public func perfLogEnabled(): Bool {
    return getVariable("LANLU_PERF_LOG") == Some("1")
}

public func perfLog(line: String): Unit {
    if (!perfLogEnabled()) {
        return
    }
    let home = getVariable("HOME") ?? "."
    let body = (line + "\n").toArray()
    try {
        let f = File(home + "/perf.txt", OpenMode.Append)
        f.write(body)
        f.close()
    } catch (_) {
        try {
            let f2 = File(home + "/perf.txt", OpenMode.Write)
            f2.write(body)
            f2.close()
        } catch (_) {}
    }
}
