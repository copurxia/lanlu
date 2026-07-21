package lanlu_client_next.app

import std.time.MonoTime
import std.process.{launch, execute, executeWithOutput, ProcessRedirect, SubProcess}
import std.convert.Parsable

// 阅读器媒体 lane 的播放引擎（纯逻辑可单测：进程/时钟/下载全部注入，同 ReaderModel 风格）。
//
// 系统没有应用内解码后端，务实方案：媒体页字节先经后台 worker 下载到缓存目录，
// 再 spawn 外部 ffplay 子进程播放（/usr/bin/ffplay，-nodisp 无窗口纯播放）。
// 范围取舍：本模型只服务音频 lane；视频播放后续接入（UI 侧另行处理），
// AppModel 的 lane 同步逻辑不会对 Video lane 调 load()。

// 播放进程抽象：测试注入假实现断言调用序列；生产默认 FfplayRunner（见文件末尾）。
// start 带 muted：ffplay 不支持运行期改音量，静音/取消静音 = 记录位置后以
// -volume 0/100 重启进程（见 toggleMute），故音量必须是 start 的参数。
public interface ProcessRunner {
    func start(path: String, offsetSec: Float64, muted: Bool): Unit
    func pause(): Unit
    func resume(): Unit
    func stop(): Unit
}

public class PlaybackModel {
    // ---- 状态（只读暴露；AppModel 变更后 bump readerVersion 通知视图）----
    public var mediaKey: String = ""       // "arcid:pageIndex"，空串=无媒体
    public var durationSec: Float64 = 0.0  // 0=未知（无 ffprobe 接线，YAGNI）；>0 时 position 钳制到它
    public var playing: Bool = false
    public var loaded: Bool = false        // 下载完成、可播放
    public var loading: Bool = false       // 下载在途
    public var error: String = ""          // ""=无错
    public var muted: Bool = false

    // ---- 注入点 ----
    // 单调时钟（毫秒）；测试注入假时钟驱动位置断言。
    public var clock: () -> Int64
    // 下载出口：(arcid, pageId) 触发后台下载；完成经 onDownloaded/onFailed 回填。
    public var onDownload: ?(String, String) -> Unit = None
    // 播放进程；None 时惰性用默认 FfplayRunner（测试注入假 runner，不会碰 ffplay）。
    public var processRunner: ?ProcessRunner = None

    // ---- 内部 ----
    private var localPath: String = ""
    private var started = false            // 进程是否启动过（区分 togglePlay 首次 start 与 resume）
    private var startClockMs: Int64 = 0    // 本次（恢复）播放的时钟起点
    private var startOffsetSec: Float64 = 0.0
    private var pausedOffsetSec: Float64 = 0.0
    private var defaultRunner: ?FfplayRunner = None

    public init() {
        let start = MonoTime.now()
        clock = { => (MonoTime.now() - start).toMilliseconds() }
    }

    // 当前播放位置（秒）：播放中 = 起点偏移 + 时钟推进；暂停 = 暂停时快照。钳制到 [0, duration]。
    public prop positionSec: Float64 {
        get() {
            let raw = if (playing) {
                startOffsetSec + Float64(clock() - startClockMs) / 1000.0
            } else {
                pausedOffsetSec
            }
            clampPos(raw)
        }
    }

    // 加载媒体页：同 key 且已加载/在途则忽略（重复激活同一 lane 不重复下载）；
    // 否则停掉旧媒体、置 loading 态并触发下载。完成经 onDownloaded/onFailed 回填。
    public func load(arcid: String, pageIndex: Int64, pageId: String): Unit {
        let key = "${arcid}:${pageIndex}"
        if (key == mediaKey && (loaded || loading)) { return }
        stopInternal()
        mediaKey = key
        durationSec = 0.0 // 旧媒体时长不得带入新媒体；下载完成后由 ffprobe 探测回填
        loading = true
        error = ""
        match (onDownload) {
            case Some(cb) => cb(arcid, pageId)
            case None => ()
        }
    }

    // 下载完成回填（AppModel worker drain 调用）：迟到结果按 key 对号入座，
    // 用户已切走（mediaKey 变了）时静默丢弃。
    public func onDownloaded(key: String, path: String): Unit {
        if (key != mediaKey) { return }
        loading = false
        loaded = true
        error = ""
        localPath = path
    }

    // 下载失败回填（同 onDownloaded 的对号入座语义）。
    public func onFailed(key: String, err: String): Unit {
        if (key != mediaKey) { return }
        loading = false
        loaded = false
        playing = false
        started = false
        error = err
    }

    // 开始播放：未加载/出错时忽略。重复调用 = 从头继续当前位置（幂等）。
    public func play(): Unit {
        if (!loaded || error.size > 0) { return }
        startOffsetSec = positionSec
        startClockMs = clock()
        runner().start(localPath, startOffsetSec, muted)
        started = true
        playing = true
    }

    public func pause(): Unit {
        if (!playing) { return }
        pausedOffsetSec = positionSec
        runner().pause()
        playing = false
    }

    public func resume(): Unit {
        if (playing || !loaded) { return }
        if (!started) {
            play()
            return
        }
        startOffsetSec = pausedOffsetSec
        startClockMs = clock()
        runner().resume()
        playing = true
    }

    public func togglePlay(): Unit {
        if (playing) { pause() } else { resume() }
    }

    // seek = 停掉进程后以新 offset 重启（ffplay 无运行期 seek 控制通道）。
    // 暂停态只更新位置快照，进程在 resume 时按新位置重启。
    public func seekTo(sec: Float64): Unit {
        let target = clampPos(sec)
        if (playing) {
            runner().stop()
            startOffsetSec = target
            startClockMs = clock()
            runner().start(localPath, target, muted)
        } else {
            pausedOffsetSec = target
            if (started) {
                // 暂停中的进程是 SIGSTOP 冻结在旧位置的，重启对齐到新位置。
                runner().stop()
                started = false
            }
        }
    }

    public func skip(deltaSec: Float64): Unit {
        seekTo(positionSec + deltaSec)
    }

    // 静音切换：ffplay 无运行期音量控制，记录位置后以 -volume 0/100 重启
    //（简单可靠；暂停态只翻标志，下次 play/resume 生效）。
    public func toggleMute(): Unit {
        muted = !muted
        if (playing) {
            let pos = positionSec
            runner().stop()
            startOffsetSec = pos
            startClockMs = clock()
            runner().start(localPath, pos, muted)
        }
    }

    // 复位并关进程（切 Book lane / 离开阅读器）：清空全部媒体状态。
    public func stop(): Unit {
        stopInternal()
        mediaKey = ""
        error = ""
    }

    private func stopInternal(): Unit {
        if (started) { runner().stop() }
        started = false
        playing = false
        loaded = false
        loading = false
        localPath = ""
        startOffsetSec = 0.0
        pausedOffsetSec = 0.0
    }

    private func clampPos(v: Float64): Float64 {
        var x = v
        if (x < 0.0) { x = 0.0 }
        if (durationSec > 0.0 && x > durationSec) { x = durationSec }
        x
    }

    private func runner(): ProcessRunner {
        match (processRunner) {
            case Some(r) => r
            case None =>
                match (defaultRunner) {
                    case Some(r) => r
                    case None =>
                        let r = FfplayRunner()
                        defaultRunner = r
                        r
                }
        }
    }
}

// mm:ss 时钟格式化（音频舞台/dock 的进度文案）：未知/负值按 0:00，超 1 小时也只滚分钟
// （原型 .audio-dock .t 同款 tabular 展示，播客级时长不引入小时位）。
public func formatMediaClock(sec: Float64): String {
    var s = Int64(sec)
    if (s < 0) { s = 0 }
    let m = s / 60
    let r = s % 60
    let ms = if (m < 10) { "0${m}" } else { "${m}" }
    let rs = if (r < 10) { "0${r}" } else { "${r}" }
    "${ms}:${rs}"
}

// ffprobe 探测媒体时长（秒）：0=未知（ffprobe 缺失/退出码非 0/输出不可解析）。
// 在 worker 线程同步执行（AppModel 的 playback 下载任务末尾调用），UI 线程不得调用。
public func probeMediaDuration(path: String): Float64 {
    try {
        let (code, out, _) = executeWithOutput("ffprobe",
            ["-v", "quiet", "-show_entries", "format=duration", "-of", "csv=p=0", path])
        if (code != 0) { return 0.0 }
        Float64.parse(String.fromUtf8(out).trimAscii())
    } catch (_: Exception) {
        0.0
    }
}

// 默认 ProcessRunner：外部 ffplay 子进程（仅音频：恒 -nodisp 无窗口播放；
// 视频 lane 本阶段不接入，见文件头注释）。
// - 自然退出由 -autoexit 保证；调用方按 position>=duration 推断播完即可，不检测子进程退出。
// - pause/resume：std.process 没有信号 API，仓颉也没有现成 kill(2) 绑定，
//   最简可行方案是 shell out 到 /bin/kill 发 SIGSTOP/SIGCONT（Linux 桌面环境必有）。
public class FfplayRunner <: ProcessRunner {
    private var proc: ?SubProcess = None

    public func start(path: String, offsetSec: Float64, muted: Bool): Unit {
        stop()
        let args = [
            "-nodisp",
            "-autoexit",
            "-v",
            "quiet",
            "-ss",
            "${offsetSec}",
            "-volume",
            if (muted) { "0" } else { "100" },
            path
        ]
        try {
            proc = Some(launch("ffplay", args,
                stdOut: ProcessRedirect.Discard, stdErr: ProcessRedirect.Discard))
        } catch (_: Exception) {
            proc = None // ffplay 缺失等情况：静默失败，状态机侧不受影响
        }
    }

    public func pause(): Unit {
        signal("-STOP")
    }

    public func resume(): Unit {
        signal("-CONT")
    }

    public func stop(): Unit {
        match (proc) {
            case Some(p) =>
                try { p.terminate(force: true) } catch (_: Exception) {}
                proc = None
            case None => ()
        }
    }

    private func signal(sig: String): Unit {
        match (proc) {
            case Some(p) =>
                try { let _ = execute("kill", [sig, "${p.pid}"]) } catch (_: Exception) {}
            case None => ()
        }
    }
}
