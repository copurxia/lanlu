package lanlu_client_next.app

import std.time.MonoTime
import std.process.executeWithOutput
import std.convert.Parsable
import std.collection.ArrayList
import libvlc_ffi.{SubtitleTrack, VideoFrame, VlcPlayer}

// 阅读器媒体 lane 的播放引擎（纯逻辑可单测：进程/时钟/下载全部注入，同 ReaderModel 风格）。
// 音视频统一通过鉴权代理 URL 按 HTTP Range 交给 libVLC 流式读取。

// 播放器抽象保留为测试注入点；生产环境统一使用 LibVlcRunner。
public interface ProcessRunner {
    func start(path: String, offsetSec: Float64, muted: Bool): Unit
    func pause(): Unit
    func resume(): Unit
    func stop(): Unit
}

public class LyricLine {
    public let timeSec: Float64
    public let text: String
    init(timeSec: Float64, text: String) { this.timeSec = timeSec; this.text = text }
}

public class PlaybackModel {
    // ---- 状态（只读暴露；AppModel 变更后 bump readerVersion 通知视图）----
    public var mediaKey: String = ""       // "arcid:pageIndex"，空串=无媒体
    public var durationSec: Float64 = 0.0  // 0=未知（无 ffprobe 接线，YAGNI）；>0 时 position 钳制到它
    public var playing: Bool = false
    public var loaded: Bool = false        // 媒体已就绪、可播放
    public var loading: Bool = false       // 音频下载在途
    public var error: String = ""          // ""=无错
    public var muted: Bool = false
    public var volume: Float64 = 1.0
    public var isVideo: Bool = false
    public var subtitleTracks = ArrayList<SubtitleTrack>()
    public var subtitleTrackId: Int32 = -1
    public var lyricsLines = ArrayList<LyricLine>()

    // ---- 注入点 ----
    // 单调时钟（毫秒）；测试注入假时钟驱动位置断言。
    public var clock: () -> Int64
    // 下载出口：(arcid, pageId) 触发后台下载；完成经 onDownloaded/onFailed 回填。
    public var onDownload: ?(String, String) -> Unit = None
    public var onLyricsDownload: ?(String, Int64) -> Unit = None
    // 播放器；None 时惰性使用 libVLC（测试可注入假 runner）。
    public var processRunner: ?ProcessRunner = None

    // ---- 内部 ----
    private var localPath: String = ""
    private var authToken: String = ""
    private var started = false            // 进程是否启动过（区分 togglePlay 首次 start 与 resume）
    private var startClockMs: Int64 = 0    // 本次（恢复）播放的时钟起点
    private var startOffsetSec: Float64 = 0.0
    private var pausedOffsetSec: Float64 = 0.0
    private var vlcRunner: ?LibVlcRunner = None

    public init() {
        let start = MonoTime.now()
        clock = { => (MonoTime.now() - start).toMilliseconds() }
    }

    // 当前播放位置（秒）：播放中 = 起点偏移 + 时钟推进；暂停 = 暂停时快照。钳制到 [0, duration]。
    public prop positionSec: Float64 {
        get() {
            if (processRunner.isNone()) {
                match (vlcRunner) {
                    case Some(r) => return clampPos(r.timeSec())
                    case None => ()
                }
            }
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
    public func load(arcid: String, pageIndex: Int64, pageId: String, video!: Bool = false): Unit {
        let key = "${arcid}:${pageIndex}"
        if (key == mediaKey && (loaded || loading)) { return }
        stopInternal()
        mediaKey = key
        isVideo = video
        durationSec = 0.0 // 旧媒体时长不得带入新媒体；下载完成后由 ffprobe 探测回填
        loading = true
        error = ""
        match (onDownload) {
            case Some(cb) => cb(arcid, pageId)
            case None => ()
        }
    }

    // 视频由 libVLC 直接通过 HTTP Range 读取，不预下载完整文件。
    public func loadRemote(arcid: String, pageIndex: Int64, url: String, token: String,
        video!: Bool = true): Unit {
        let key = "${arcid}:${pageIndex}"
        if (key == mediaKey && loaded && isVideo) { return }
        stopInternal()
        mediaKey = key
        isVideo = video
        loaded = true
        loading = false
        error = ""
        localPath = url
        authToken = token
    }

    public func loadLyrics(assetId: Int64): Unit {
        lyricsLines.clear()
        if (assetId <= 0) { return }
        match (onLyricsDownload) {
            case Some(cb) => cb(mediaKey, assetId)
            case None => ()
        }
    }

    public func onLyricsDownloaded(key: String, lyrics: String): Unit {
        if (key == mediaKey) { lyricsLines = parseTimedLyrics(lyrics) }
    }

    public func refreshVlcState(): Unit {
        if (!started || processRunner.isSome()) { return }
        match (vlcRunner) {
            case Some(r) =>
                let duration = r.durationSec()
                if (duration > 0.0) { durationSec = duration }
            case None => ()
        }
    }

    // 下载完成回填（AppModel worker drain 调用）：迟到结果按 key 对号入座，
    // 用户已切走（mediaKey 变了）时静默丢弃。
    public func onDownloaded(key: String, path: String, lyrics!: String = ""): Unit {
        if (key != mediaKey) { return }
        loading = false
        loaded = true
        error = ""
        localPath = path
        lyricsLines = parseTimedLyrics(lyrics)
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
        applyVolume()
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

    // libVLC 生产路径使用原生 seek；测试注入的通用 runner 保留重启回退语义。
    public func seekTo(sec: Float64): Unit {
        let target = clampPos(sec)
        if (started && processRunner.isNone()) {
            match (vlcRunner) {
                case Some(r) =>
                    r.seek(target)
                    startOffsetSec = target
                    pausedOffsetSec = target
                    startClockMs = clock()
                    return
                case None => ()
            }
        }
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

    // libVLC 原生静音，不中断当前媒体或网络流。
    public func toggleMute(): Unit {
        muted = !muted
        if (started && processRunner.isNone()) {
            match (vlcRunner) {
                case Some(r) => r.setMuted(muted); return
                case None => ()
            }
        }
        if (playing) {
            let pos = positionSec
            runner().stop()
            startOffsetSec = pos
            startClockMs = clock()
            runner().start(localPath, pos, muted)
        }
    }

    public func setVolume(value: Float64): Unit {
        volume = max(0.0, min(1.0, value))
        if (volume > 0.0 && muted) { muted = false }
        applyVolume()
    }

    private func applyVolume(): Unit {
        if (processRunner.isSome()) { return }
        match (vlcRunner) {
            case Some(r) =>
                r.setVolume(Int32(volume * 100.0))
                r.setMuted(muted)
            case None => ()
        }
    }

    // 复位并关进程（切 Book lane / 离开阅读器）：清空全部媒体状态。
    public func stop(): Unit {
        stopInternal()
        mediaKey = ""
        error = ""
    }

    public func takeVideoFrame(): ?VideoFrame {
        if (!isVideo) { return None }
        match (vlcRunner) {
            case Some(r) =>
                let duration = r.durationSec()
                if (duration > 0.0) { durationSec = duration }
                subtitleTracks = r.subtitleTracks()
                subtitleTrackId = r.currentSubtitleTrack()
                r.takeFrame()
            case None => None
        }
    }

    private func stopInternal(): Unit {
        if (started) { runner().stop() }
        started = false
        playing = false
        loaded = false
        loading = false
        localPath = ""
        authToken = ""
        isVideo = false
        subtitleTracks.clear()
        subtitleTrackId = -1
        lyricsLines.clear()
        startOffsetSec = 0.0
        pausedOffsetSec = 0.0
    }

    public func activeLyricIndex(): Int64 {
        let now = positionSec
        var active: Int64 = -1
        for (i in 0..lyricsLines.size) {
            if (lyricsLines[Int64(i)].timeSec <= now) { active = Int64(i) } else { break }
        }
        active
    }

    public func cycleSubtitleTrack(): Unit {
        if (!isVideo || !started) { return }
        match (vlcRunner) {
            case Some(r) =>
                let tracks = r.subtitleTracks()
                var nextId: Int32 = -1
                for (i in 0..tracks.size) {
                    if (tracks[Int64(i)].id == subtitleTrackId && i + 1 < tracks.size) {
                        nextId = tracks[Int64(i + 1)].id
                    }
                }
                let _ = r.setSubtitleTrack(nextId)
                subtitleTracks = tracks
                subtitleTrackId = nextId
            case None => ()
        }
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
            case None => match (vlcRunner) {
                case Some(r) => r.setAuthToken(authToken)
                case None =>
                    let r = LibVlcRunner()
                    let _ = r.setAuthToken(authToken)
                    vlcRunner = Some(r)
                    r
            }
        }
    }
}

public func parseTimedLyrics(raw: String): ArrayList<LyricLine> {
    let result = ArrayList<LyricLine>()
    if (raw.size == 0 || raw.size > 1048576) { return result }
    for (line in raw.replace("\r", "").split("\n")) {
        if (!line.startsWith("[")) { continue }
        let close = line.indexOf("]")
        match (close) {
            case Some(end) =>
                let stamp = line[1..end]
                let parts = stamp.split(":")
                if (parts.size != 2) { continue }
                let secParts = parts[1].split(".")
                try {
                    let minutes = Float64.parse(parts[0])
                    let seconds = Float64.parse(secParts[0])
                    var fraction = 0.0
                    if (secParts.size > 1) {
                        let digits = secParts[1]
                        fraction = Float64.parse(digits) / if (digits.size == 1) { 10.0 } else if (digits.size == 2) { 100.0 } else { 1000.0 }
                    }
                    result.add(LyricLine(minutes * 60.0 + seconds + fraction,
                        line[(end + 1)..line.size].trimAscii()))
                } catch (_: Exception) {}
            case None => ()
        }
    }
    result
}

public class LibVlcRunner <: ProcessRunner {
    private let player = VlcPlayer()
    private var authToken: String = ""

    public func setAuthToken(token: String): LibVlcRunner { authToken = token; this }

    public func start(path: String, offsetSec: Float64, muted: Bool): Unit {
        try { player.open(path, offsetSec: offsetSec, muted: muted, authToken: authToken) }
        catch (_: Exception) { player.stop() }
    }
    public func pause(): Unit { player.pause() }
    public func resume(): Unit { player.resume() }
    public func stop(): Unit { player.stop() }
    public func takeFrame(): ?VideoFrame { player.takeFrame() }
    public func durationSec(): Float64 { player.durationSec() }
    public func timeSec(): Float64 { player.timeSec() }
    public func seek(sec: Float64): Unit { player.seek(sec) }
    public func setMuted(muted: Bool): Unit { player.setMuted(muted) }
    public func setVolume(volume: Int32): Unit { player.setVolume(volume) }
    public func subtitleTracks(): ArrayList<SubtitleTrack> { player.subtitleTracks() }
    public func currentSubtitleTrack(): Int32 { player.currentSubtitleTrack() }
    public func setSubtitleTrack(id: Int32): Bool { player.setSubtitleTrack(id) }
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
