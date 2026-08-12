package lanlu_client_next.app

import std.time.MonoTime
import std.convert.Parsable
import std.collection.{ArrayList, HashMap}
import std.sort.sort
import libvlc_ffi.{VideoFrame, VlcPlayer}
import libavformat_ffi.{ExtractedSubtitleTrack, SubtitlePayloadKind, SubtitleStreamInfo}
import libass_ffi.{AssRenderer, AssTrack, PlainSubtitleEvent, SubtitleBitmap, escapeAssText}
import lanlu_client_next.net.SubtitleAttachment

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
    init(timeSec: Float64, text: String) {
        this.timeSec = timeSec
        this.text = text
    }
}

// 外挂字幕 cue（SRT/VTT/ASS 解析产物，同 frontend/client 的 SubtitleCue）。
public class SubtitleCue {
    public let start: Float64
    public let end: Float64
    public let text: String
    init(start: Float64, end: Float64, text: String) {
        this.start = start
        this.end = end
        this.text = text
    }
}

public class PlaybackModel {
    // ---- 状态（只读暴露；AppModel 变更后 bump readerVersion 通知视图）----
    public var mediaKey: String = "" // "arcid:pageIndex"，空串=无媒体
    public var durationSec: Float64 = 0.0 // 0=未知，开播后由 libVLC 轮询回填；>0 时 position 钳制到它
    public var playing: Bool = false
    public var loaded: Bool = false // 媒体已就绪、可播放
    public var loading: Bool = false // 音频下载在途
    public var error: String = "" // ""=无错
    public var muted: Bool = false
    public var volume: Float64 = 1.0
    public var isVideo: Bool = false
    public var embeddedSubtitleStreams = ArrayList<SubtitleStreamInfo>()
    public var activeEmbeddedStreamIndexes = ArrayList<Int32>()
    public var subtitleProbeLoading = false
    public var subtitleScanLoading = false
    public var subtitleError = ""
    public var mediaGeneration: UInt64 = 0
    public var stableMediaCacheKey: String = ""
    public var subtitleBitmapGeneration: UInt64 = 0
    // 外挂字幕（attachments slot=subtitle）：多选语义对齐 frontend/client——
    // activeSubtitleIndexes 存选中项在 subtitleAttachments 中的下标（升序）。
    public var subtitleAttachments = ArrayList<SubtitleAttachment>()
    public var activeSubtitleIndexes = ArrayList<Int64>()
    public var lyricsLines = ArrayList<LyricLine>()
    // 已交付 UI 的视频帧代际（takeVideoFrame 每取到新帧 +1）：阅读器舞台据此
    // 只在新帧到达时续帧，而非固定 60fps。
    public var videoGeneration: UInt64 = 0

    // ---- 注入点 ----
    // 单调时钟（毫秒）；测试注入假时钟驱动位置断言。
    public var clock: () -> Int64
    // 下载出口：(arcid, pageId) 触发后台下载；完成经 onDownloaded/onFailed 回填。
    public var onDownload: ?(String, String) -> Unit = None
    public var onLyricsDownload: ?(String, Int64) -> Unit = None
    // 外挂字幕文本下载出口：(mediaKey, assetId)；完成经 onSubtitleDownloaded 回填。
    public var onSubtitleDownload: ?(String, Int64) -> Unit = None
    public var onSubtitleProbe: ?(String, UInt64, String, String) -> Unit = None
    public var onSubtitleScan: ?(String, UInt64, String, String, String) -> Unit = None
    public var onSubtitleCancel: ?(String, UInt64) -> Unit = None
    // 播放器；None 时惰性使用 libVLC（测试可注入假 runner）。
    public var processRunner: ?ProcessRunner = None

    // ---- 内部 ----
    private var localPath: String = ""
    private var authToken: String = ""
    private var subtitleSourceUrl: String = ""
    private var subtitleBearerToken: String = ""
    private var started = false // 进程是否启动过（区分 togglePlay 首次 start 与 resume）
    private var startClockMs: Int64 = 0 // 本次（恢复）播放的时钟起点
    private var startOffsetSec: Float64 = 0.0
    private var pausedOffsetSec: Float64 = 0.0
    private var vlcRunner: ?LibVlcRunner = None
    // 外挂字幕 cue 缓存：按 assetId 驻留（同 frontend subtitleCache，切页不重下）。
    private let subtitleCuesByAsset = HashMap<Int64, ArrayList<SubtitleCue>>()
    private var assRenderer: ?AssRenderer = None
    private let embeddedAssTracks = HashMap<Int32, AssTrack>()
    private let externalAssTracks = HashMap<Int64, AssTrack>()
    private var extractedSubtitleTracks = ArrayList<ExtractedSubtitleTrack>()
    private let externalSubtitleText = HashMap<Int64, (String, String)>()
    private var subtitleWidth: Int32 = 0
    private var subtitleHeight: Int32 = 0

    public init() {
        let start = MonoTime.now()
        clock = {=> (MonoTime.now() - start).toMilliseconds()}
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
        if (key == mediaKey && (loaded || loading)) {
            return
        }
        stopInternal()
        mediaGeneration += 1
        mediaKey = key
        isVideo = video
        durationSec = 0.0 // 旧媒体时长不得带入新媒体；开播后由 libVLC 轮询回填
        loading = true
        error = ""
        match (onDownload) {
            case Some(cb) => cb(arcid, pageId)
            case None => ()
        }
    }

    // 视频由 libVLC 直接通过 HTTP Range 读取，不预下载完整文件。
    public func loadRemote(arcid: String, pageIndex: Int64, url: String, token: String, video!: Bool = true,
        stableCacheKey!: String = "", subtitleUrl!: String = "", subtitleBearer!: String = ""): Unit {
        let key = "${arcid}:${pageIndex}"
        if (key == mediaKey && loaded && isVideo) {
            return
        }
        stopInternal()
        mediaGeneration += 1
        mediaKey = key
        stableMediaCacheKey = if (stableCacheKey.size > 0) {
            stableCacheKey
        } else {
            key
        }
        isVideo = video
        loaded = true
        loading = false
        error = ""
        localPath = url
        authToken = token
        subtitleSourceUrl = if (subtitleUrl.size > 0) {
            subtitleUrl
        } else {
            url
        }
        subtitleBearerToken = subtitleBearer
        if (video) {
            subtitleProbeLoading = true
            match (onSubtitleProbe) {
                case Some(callback) => callback(mediaKey, mediaGeneration, subtitleSourceUrl, subtitleBearerToken)
                case None => ()
            }
        }
    }

    public func loadLyrics(assetId: Int64): Unit {
        lyricsLines.clear()
        invalidateLyricCursor()
        if (assetId <= 0) {
            return
        }
        match (onLyricsDownload) {
            case Some(cb) => cb(mediaKey, assetId)
            case None => ()
        }
    }

    public func onLyricsDownloaded(key: String, lyrics: String): Unit {
        if (key == mediaKey) {
            lyricsLines = parseTimedLyrics(lyrics)
            invalidateLyricCursor()
        }
    }

    public func refreshVlcState(): Unit {
        if (!started || processRunner.isSome()) {
            return
        }
        match (vlcRunner) {
            case Some(r) =>
                let duration = r.durationSec()
                if (duration > 0.0) {
                    durationSec = duration
                }
            case None => ()
        }
    }

    // 下载完成回填（AppModel worker drain 调用）：迟到结果按 key 对号入座，
    // 用户已切走（mediaKey 变了）时静默丢弃。
    public func onDownloaded(key: String, path: String, lyrics!: String = ""): Unit {
        if (key != mediaKey) {
            return
        }
        loading = false
        loaded = true
        error = ""
        localPath = path
        lyricsLines = parseTimedLyrics(lyrics)
        invalidateLyricCursor()
    }

    // 下载失败回填（同 onDownloaded 的对号入座语义）。
    public func onFailed(key: String, err: String): Unit {
        if (key != mediaKey) {
            return
        }
        loading = false
        loaded = false
        playing = false
        started = false
        error = err
    }

    // 开始播放：未加载/出错时忽略。重复调用 = 从头继续当前位置（幂等）。
    public func play(): Unit {
        if (!loaded || error.size > 0) {
            return
        }
        startOffsetSec = positionSec
        startClockMs = clock()
        runner().start(localPath, startOffsetSec, muted)
        applyVolume()
        started = true
        playing = true
    }

    public func pause(): Unit {
        if (!playing) {
            return
        }
        pausedOffsetSec = positionSec
        runner().pause()
        playing = false
    }

    public func resume(): Unit {
        if (playing || !loaded) {
            return
        }
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
        if (playing) {
            pause()
        } else {
            resume()
        }
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
                case Some(r) =>
                    r.setMuted(muted);
                    return
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
        if (volume > 0.0 && muted) {
            muted = false
        }
        applyVolume()
    }

    private func applyVolume(): Unit {
        if (processRunner.isSome()) {
            return
        }
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
        if (!isVideo) {
            return None
        }
        match (vlcRunner) {
            case Some(r) =>
                let duration = r.durationSec()
                if (duration > 0.0) {
                    durationSec = duration
                }
                disableVlcSubtitlesThrottled(r)
                let frame = r.takeFrame()
                if (frame.isSome()) {
                    videoGeneration += 1
                }
                frame
            case None => None
        }
    }

    // VLC 可能在播放开始后延迟发现并自动选择字幕轨，因此播放中每秒重申关闭一次。
    // 用注入时钟计时，测试可驱动。
    private var lastSubtitleRefreshMs: Int64 = -10000

    private func disableVlcSubtitlesThrottled(r: LibVlcRunner): Unit {
        let now = clock()
        if (now - lastSubtitleRefreshMs < 1000) {
            return
        }
        lastSubtitleRefreshMs = now
        let _ = r.setSubtitleTrack(-1)
    }

    private func stopInternal(): Unit {
        if (mediaKey.size > 0) {
            match (onSubtitleCancel) {
                case Some(cancel) => cancel(mediaKey, mediaGeneration)
                case None => ()
            }
        }
        if (started) {
            runner().stop()
        }
        started = false
        playing = false
        loaded = false
        loading = false
        localPath = ""
        authToken = ""
        subtitleSourceUrl = ""
        subtitleBearerToken = ""
        isVideo = false
        embeddedSubtitleStreams.clear()
        activeEmbeddedStreamIndexes.clear()
        subtitleProbeLoading = false
        subtitleScanLoading = false
        subtitleError = ""
        extractedSubtitleTracks.clear()
        subtitleAttachments.clear()
        activeSubtitleIndexes.clear()
        lyricsLines.clear()
        videoGeneration = 0
        subtitleBitmapGeneration = 0
        lastSubtitleRefreshMs = -10000
        invalidateLyricCursor()
        closeAssRenderer()
        startOffsetSec = 0.0
        pausedOffsetSec = 0.0
    }

    // 当前歌词行：二分查找最后一条 timeSec <= now（O(log n)）；播放中位置单调前进时
    // 从上次命中索引向前扫（均摊 O(1)），回退/seek 走二分。结果缓存于 lastLyric*，
    // 歌词列表替换时由 invalidateLyricCursor 复位。
    private var lastLyricCursor: Int64 = -1
    private var lastLyricPositionSec: Float64 = -1.0

    private func invalidateLyricCursor(): Unit {
        lastLyricCursor = -1
        lastLyricPositionSec = -1.0
    }

    public func activeLyricIndex(): Int64 {
        let now = positionSec
        let n = lyricsLines.size
        if (n == 0) {
            invalidateLyricCursor()
            return -1
        }
        // 单调前进快路径：上次命中仍有效（行存在且不晚于 now），向前扫到本行。
        if (now >= lastLyricPositionSec && lastLyricCursor < n && (lastLyricCursor < 0 ||
            lyricsLines[lastLyricCursor].timeSec <= now)) {
            var i = lastLyricCursor
            while (i + 1 < n && lyricsLines[i + 1].timeSec <= now) {
                i += 1
            }
            lastLyricCursor = i
            lastLyricPositionSec = now
            return i
        }
        // 回退/seek/歌词热替换：二分最后一条 timeSec <= now。
        var lo: Int64 = 0
        var hi = n - 1
        var ans: Int64 = -1
        while (lo <= hi) {
            let mid = (lo + hi) / 2
            if (lyricsLines[mid].timeSec <= now) {
                ans = mid
                lo = mid + 1
            } else {
                hi = mid - 1
            }
        }
        lastLyricCursor = ans
        lastLyricPositionSec = now
        ans
    }

    public func onEmbeddedSubtitleProbed(key: String, generation: UInt64, streams: ArrayList<SubtitleStreamInfo>): Unit {
        if (key != mediaKey || generation != mediaGeneration) {
            return
        }
        subtitleProbeLoading = false
        subtitleError = ""
        embeddedSubtitleStreams = streams
        var defaultIndex: Int32 = -1
        for (stream in streams) {
            if (stream.supported && stream.isDefault) {
                defaultIndex = stream.streamIndex
                break
            }
        }
        if (defaultIndex < 0) {
            for (stream in streams) {
                if (stream.supported) {
                    defaultIndex = stream.streamIndex
                    break
                }
            }
        }
        if (defaultIndex >= 0 && !subtitleScanLoading) {
            subtitleScanLoading = true
            match (onSubtitleScan) {
                case Some(callback) => callback(mediaKey, mediaGeneration, subtitleSourceUrl, subtitleBearerToken,
                    stableMediaCacheKey)
                case None => ()
            }
        }
    }

    public func onEmbeddedSubtitleFailed(key: String, generation: UInt64, message: String): Unit {
        if (key != mediaKey || generation != mediaGeneration) {
            return
        }
        subtitleProbeLoading = false
        subtitleScanLoading = false
        subtitleError = message
    }

    public func toggleEmbeddedSubtitle(streamIndex: Int32): Unit {
        var found: Int64 = -1
        for (index in 0..activeEmbeddedStreamIndexes.size) {
            if (activeEmbeddedStreamIndexes[index] == streamIndex) {
                found = index
                break
            }
        }
        if (found >= 0) {
            let _ = activeEmbeddedStreamIndexes.remove(at: found)
            return
        }
        var supported = false
        for (stream in embeddedSubtitleStreams) {
            if (stream.streamIndex == streamIndex) {
                supported = stream.supported
                break
            }
        }
        if (!supported) {
            return
        }
        activeEmbeddedStreamIndexes.add(streamIndex)
        sort(activeEmbeddedStreamIndexes, lessThan: {a, b => a < b}, stable: true)
        if (!embeddedAssTracks.contains(streamIndex) && !subtitleScanLoading) {
            subtitleScanLoading = true
            match (onSubtitleScan) {
                case Some(callback) => callback(mediaKey, mediaGeneration, subtitleSourceUrl, subtitleBearerToken,
                    stableMediaCacheKey)
                case None => ()
            }
        }
    }

    public func onEmbeddedSubtitleScanned(key: String, generation: UInt64, tracks: ArrayList<ExtractedSubtitleTrack>): Unit {
        if (key != mediaKey || generation != mediaGeneration) {
            return
        }
        subtitleScanLoading = false
        subtitleError = ""
        extractedSubtitleTracks = tracks
        prepareEmbeddedTracks(tracks)
    }

    public func takeSubtitleBitmap(width: Int32, height: Int32): ?SubtitleBitmap {
        if (!isVideo || width <= 0 || height <= 0) {
            return None
        }
        ensureAssRenderer(width, height)
        let active = ArrayList<AssTrack>()
        for (index in activeSubtitleIndexes) {
            if (index < 0 || index >= subtitleAttachments.size) {
                continue
            }
            match (externalAssTracks.get(subtitleAttachments[index].assetId)) {
                case Some(track) => active.add(track)
                case None => ()
            }
        }
        for (index in activeEmbeddedStreamIndexes) {
            match (embeddedAssTracks.get(index)) {
                case Some(track) => active.add(track)
                case None => ()
            }
        }
        if (active.isEmpty()) {
            return None
        }
        match (assRenderer) {
            case Some(renderer) =>
                let bitmap = renderer.render(Int64(positionSec * 1000.0), active.toArray())
                if (bitmap.changed != 0) {
                    subtitleBitmapGeneration += 1
                }
                Some(bitmap)
            case None => None
        }
    }

    // ── 外挂字幕（多选，同 frontend/client activeSubtitleIndexes）──

    // 装载当前媒体的外挂字幕选项（Video lane 激活时调）：换媒体即重置选中。
    public func loadSubtitles(attachments: ArrayList<SubtitleAttachment>): Unit {
        subtitleAttachments = attachments
        activeSubtitleIndexes.clear()
    }

    // 切换外挂字幕选中态：已选→移除；未选→加入（升序维持）并首次触发文本下载。
    public func toggleSubtitleIndex(index: Int64): Unit {
        if (index < 0 || index >= subtitleAttachments.size) {
            return
        }
        var found: Int64 = -1
        for (i in 0..activeSubtitleIndexes.size) {
            if (activeSubtitleIndexes[Int64(i)] == index) {
                found = Int64(i)
                break
            }
        }
        if (found >= 0) {
            let _ = activeSubtitleIndexes.remove(at: found)
            return
        }
        activeSubtitleIndexes.add(index)
        sort(activeSubtitleIndexes, lessThan: {a, b => a < b}, stable: true)
        let assetId = subtitleAttachments[index].assetId
        // cue 缓存命中（本会话内已下过）不重复下载。
        if (subtitleCuesByAsset.contains(assetId)) {
            return
        }
        match (onSubtitleDownload) {
            case Some(cb) => cb(mediaKey, assetId)
            case None => ()
        }
    }

    // Off：同时清空外挂与内嵌字幕选中。
    public func clearSubtitles(): Unit {
        activeSubtitleIndexes.clear()
        activeEmbeddedStreamIndexes.clear()
    }

    // 字幕文本到货：按 mediaKey 对号入座，解析成 cue 缓存（迟到/切走静默丢弃）。
    public func onSubtitleDownloaded(key: String, assetId: Int64, text: String): Unit {
        if (key != mediaKey) {
            return
        }
        var kind = ""
        for (a in subtitleAttachments) {
            if (a.assetId == assetId) {
                kind = a.kind
                break
            }
        }
        subtitleCuesByAsset[assetId] = parseSubtitleText(text, kind)
        externalSubtitleText[assetId] = (text, kind)
        prepareExternalTrack(assetId, text, kind)
    }

    // 当前命中外挂字幕的 overlay 文本（每条选中字幕至多一条，顺序同选中序，
    // 同 frontend activeCues）；cue 未到货/无命中不占位。
    public func activeSubtitleTexts(): ArrayList<String> {
        let result = ArrayList<String>()
        if (!isVideo || activeSubtitleIndexes.isEmpty()) {
            return result
        }
        let now = positionSec
        for (idx in activeSubtitleIndexes) {
            if (idx < 0 || idx >= subtitleAttachments.size) {
                continue
            }
            match (subtitleCuesByAsset.get(subtitleAttachments[idx].assetId)) {
                case Some(cues) =>
                    // cue 按 start 升序（解析产物即文件序，常规字幕文件时间单调）：
                    // 二分最后一条 start<=now，再验证未超 end。
                    var lo: Int64 = 0
                    var hi = cues.size - 1
                    var hit: Int64 = -1
                    while (lo <= hi) {
                        let mid = (lo + hi) / 2
                        if (cues[mid].start <= now) {
                            hit = mid
                            lo = mid + 1
                        } else {
                            hi = mid - 1
                        }
                    }
                    if (hit >= 0 && cues[hit].end >= now) {
                        result.add(cues[hit].text)
                    }
                case None => ()
            }
        }
        result
    }

    private func ensureAssRenderer(width: Int32, height: Int32): Unit {
        if (assRenderer.isSome() && width == subtitleWidth && height == subtitleHeight) {
            return
        }
        closeAssRenderer()
        assRenderer = Some(AssRenderer(width, height))
        subtitleWidth = width
        subtitleHeight = height
        for ((assetId, cues) in subtitleCuesByAsset) {
            match (externalSubtitleText.get(assetId)) {
                case Some((text, kind)) => prepareExternalTrack(assetId, text, kind)
                case None => prepareExternalCueTrack(assetId, cues)
            }
        }
        prepareEmbeddedTracks(extractedSubtitleTracks)
    }

    private func prepareEmbeddedTracks(tracks: ArrayList<ExtractedSubtitleTrack>): Unit {
        match (assRenderer) {
            case Some(renderer) => for (extracted in tracks) {
                let track = renderer.newMatroskaTrack(extracted.codecPrivate)
                var plainReadOrder: Int64 = 0
                for (event in extracted.events) {
                    let bytes = match (event.payloadKind) {
                        case SubtitlePayloadKind.MatroskaAssChunk => event.payload
                        case SubtitlePayloadKind.PlainText =>
                            let payload = "${plainReadOrder},0,Default,,0,0,0,,${escapeAssText(String.fromUtf8(event.payload))}"
                                .toArray()
                            plainReadOrder++
                            payload
                    }
                    track.addChunk(bytes, event.startMs, event.durationMs)
                }
                embeddedAssTracks[extracted.streamIndex] = track
            }
            case None => ()
        }
    }

    private func prepareExternalTrack(assetId: Int64, text: String, kind: String): Unit {
        match (assRenderer) {
            case Some(renderer) =>
                if (kind.toAsciiLower().contains("ass") || kind.toAsciiLower().contains("ssa") || startsWithIgnoreCase(
                    text, "[Script Info]")) {
                    externalAssTracks[assetId] = renderer.readAssDocument(text.toArray())
                } else {
                    match (subtitleCuesByAsset.get(assetId)) {
                        case Some(cues) => prepareExternalCueTrack(assetId, cues)
                        case None => ()
                    }
                }
            case None => ()
        }
    }

    private func prepareExternalCueTrack(assetId: Int64, cues: ArrayList<SubtitleCue>): Unit {
        match (assRenderer) {
            case Some(renderer) =>
                let events = ArrayList<PlainSubtitleEvent>()
                for (cue in cues) {
                    events.add(
                        PlainSubtitleEvent(Int64(cue.start * 1000.0), Int64(max(0.0, cue.end - cue.start) * 1000.0),
                            cue.text))
                }
                externalAssTracks[assetId] = renderer.newPlainTrack(events)
            case None => ()
        }
    }

    private func closeAssRenderer(): Unit {
        embeddedAssTracks.clear()
        externalAssTracks.clear()
        match (assRenderer) {
            case Some(renderer) => renderer.close()
            case None => ()
        }
        assRenderer = None
        subtitleWidth = 0
        subtitleHeight = 0
    }

    private func clampPos(v: Float64): Float64 {
        var x = v
        if (x < 0.0) {
            x = 0.0
        }
        if (durationSec > 0.0 && x > durationSec) {
            x = durationSec
        }
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
    if (raw.size == 0 || raw.size > 1048576) {
        return result
    }
    for (line in raw.replace("\r", "").split("\n")) {
        if (!line.startsWith("[")) {
            continue
        }
        let close = line.indexOf("]")
        match (close) {
            case Some(end) =>
                let stamp = line[1..end]
                let parts = stamp.split(":")
                if (parts.size != 2) {
                    continue
                }
                let secParts = parts[1].split(".")
                try {
                    let minutes = Float64.parse(parts[0])
                    let seconds = Float64.parse(secParts[0])
                    var fraction = 0.0
                    if (secParts.size > 1) {
                        let digits = secParts[1]
                        fraction = Float64.parse(digits) / if (digits.size == 1) {
                            10.0
                        } else if (digits.size == 2) {
                            100.0
                        } else {
                            1000.0
                        }
                    }
                    result.add(LyricLine(minutes * 60.0 + seconds + fraction, line[(end + 1)..line.size].trimAscii()))
                } catch (_: Exception) {}
            case None => ()
        }
    }
    // 出口按 timeSec 升序稳定排序：activeLyricIndex 的二分/单调前进缓存都假设时间戳有序，
    // 乱序 LRC 不再改变命中语义；时间戳相同保持文件内原始先后（稳定排序）。
    sort(result, lessThan: {a, b => a.timeSec < b.timeSec}, stable: true)
    result
}

public class LibVlcRunner <: ProcessRunner {
    private let player = VlcPlayer()
    private var authToken: String = ""

    public func setAuthToken(token: String): LibVlcRunner {
        authToken = token
        this
    }

    public func start(path: String, offsetSec: Float64, muted: Bool): Unit {
        try {
            player.open(path, offsetSec: offsetSec, muted: muted, authToken: authToken)
            let _ = player.setSubtitleTrack(-1)
        } catch (_: Exception) {
            player.stop()
        }
    }
    public func pause(): Unit {
        player.pause()
    }
    public func resume(): Unit {
        player.resume()
    }
    public func stop(): Unit {
        player.stop()
    }
    public func takeFrame(): ?VideoFrame {
        player.takeFrame()
    }
    public func durationSec(): Float64 {
        player.durationSec()
    }
    public func timeSec(): Float64 {
        player.timeSec()
    }
    public func seek(sec: Float64): Unit {
        player.seek(sec)
        let _ = player.setSubtitleTrack(-1)
    }
    public func setMuted(muted: Bool): Unit {
        player.setMuted(muted)
    }
    public func setVolume(volume: Int32): Unit {
        player.setVolume(volume)
    }
    public func setSubtitleTrack(id: Int32): Bool {
        player.setSubtitleTrack(id)
    }
}

// mm:ss 时钟格式化（音频舞台/dock 的进度文案）：未知/负值按 0:00，超 1 小时也只滚分钟
// （原型 .audio-dock .t 同款 tabular 展示，播客级时长不引入小时位）。
public func formatMediaClock(sec: Float64): String {
    var s = Int64(sec)
    if (s < 0) {
        s = 0
    }
    let m = s / 60
    let r = s % 60
    let ms = if (m < 10) {
        "0${m}"
    } else {
        "${m}"
    }
    let rs = if (r < 10) {
        "0${r}"
    } else {
        "${r}"
    }
    "${ms}:${rs}"
}

// ===== 外挂字幕解析（SRT/VTT/ASS，逐行移植 client ReaderScreen 同名函数）=====

// 字幕时间戳 "hh:mm:ss[.mmm]" / "mm:ss[.mmm]"：非法/空返 0（同 client parseTimestamp）。
private func parseSubtitleTimestamp(raw: String): Float64 {
    let parts = raw.trimAscii().replace(",", ".").split(":")
    var values = ArrayList<Float64>()
    for (p in parts) {
        try {
            values.add(Float64.parse(p))
        } catch (_: Exception) {
            return 0.0
        }
    }
    if (values.size == 3) {
        values[0] * 3600.0 + values[1] * 60.0 + values[2]
    } else if (values.size == 2) {
        values[0] * 60.0 + values[1]
    } else if (values.size == 1) {
        values[0]
    } else {
        0.0
    }
}

// 首个空白分隔前的 token（VTT 时间截去 align: 等位置参数）。
private func firstToken(s: String): String {
    var i: Int64 = 0
    while (i < s.size) {
        let b = s[i]
        if (b == 0x20u8 || b == 0x09u8) {
            break
        }
        i += 1
    }
    s[0..i]
}

private func isDigitsOnly(s: String): Bool {
    if (s.size == 0) {
        return false
    }
    for (c in s) {
        if (c < 0x30u8 || c > 0x39u8) {
            return false
        }
    }
    true
}

private func startsWithIgnoreCase(text: String, prefix: String): Bool {
    text.toAsciiLower().startsWith(prefix.toAsciiLower())
}

public func parseSrtCues(raw: String): ArrayList<SubtitleCue> {
    let cues = ArrayList<SubtitleCue>()
    let text = raw.replace("\r\n", "\n").replace("\r", "\n")
    for (block in text.split("\n\n")) {
        let trimmed = block.trimAscii()
        if (trimmed.size == 0) {
            continue
        }
        let lines = trimmed.split("\n")
        var timeLine = ""
        for (line in lines) {
            let l = line.trimAscii()
            if (timeLine.size == 0 && l.contains("-->")) {
                timeLine = l
            }
        }
        if (timeLine.size == 0) {
            continue
        }
        let halves = timeLine.split("-->")
        if (halves.size < 2) {
            continue
        }
        let startRaw = halves[0].trimAscii()
        let endRaw = halves[1].trimAscii()
        if (startRaw.size == 0 || endRaw.size == 0) {
            continue
        }
        // 正文：非空、非时间行、非纯数字序号行。
        var body = ""
        for (line in lines) {
            let l = line.trimAscii()
            if (l.size == 0 || l == timeLine || isDigitsOnly(l)) {
                continue
            }
            if (body.size > 0) {
                body += "\n"
            }
            body += l
        }
        body = body.trimAscii()
        if (body.size == 0) {
            continue
        }
        cues.add(SubtitleCue(parseSubtitleTimestamp(startRaw), parseSubtitleTimestamp(endRaw), body))
    }
    cues
}

public func parseVttCues(raw: String): ArrayList<SubtitleCue> {
    let cues = ArrayList<SubtitleCue>()
    var text = raw.replace("\r\n", "\n").replace("\r", "\n")
    if (startsWithIgnoreCase(text, "WEBVTT")) {
        var i: Int64 = 6
        while (i < text.size) {
            let b = text[i]
            if (b != 0x20u8 && b != 0x09u8 && b != 0x0Au8) {
                break
            }
            i += 1
        }
        text = text[i..text.size]
    }
    for (block in text.split("\n\n")) {
        let trimmed = block.trimAscii()
        if (trimmed.size == 0) {
            continue
        }
        var lines = ArrayList<String>()
        for (line in trimmed.split("\n")) {
            let l = line.trimAscii()
            if (l.size > 0) {
                lines.add(l)
            }
        }
        var timeLine = ""
        for (line in lines) {
            if (timeLine.size == 0 && line.contains("-->")) {
                timeLine = line
            }
        }
        if (timeLine.size == 0) {
            continue
        }
        let halves = timeLine.split("-->")
        if (halves.size < 2) {
            continue
        }
        let startRaw = firstToken(halves[0].trimAscii())
        let endRaw = firstToken(halves[1].trimAscii())
        if (startRaw.size == 0 || endRaw.size == 0) {
            continue
        }
        var body = ""
        for (line in lines) {
            if (line == timeLine) {
                continue
            }
            if (body.size > 0) {
                body += "\n"
            }
            body += line
        }
        body = body.trimAscii()
        if (body.size == 0) {
            continue
        }
        cues.add(SubtitleCue(parseSubtitleTimestamp(startRaw), parseSubtitleTimestamp(endRaw), body))
    }
    cues
}

// ASS/SSA 正文清洗：{...} override 块剔除，\N \n 换行、\h 空格（同 client）。
private func stripAssFormatting(raw: String): String {
    var out = ""
    var rest = raw
    var open = rest.indexOf("{")
    while (open.isSome()) {
        match (open) {
            case Some(o) =>
                out += rest[0..o]
                match (rest.indexOf("}")) {
                    case Some(c) => rest = rest[(c + 1)..rest.size]
                    case None => rest = ""
                }
            case None => ()
        }
        open = rest.indexOf("{")
    }
    out += rest
    out = out.replace("\\N", "\n").replace("\\n", "\n").replace("\\h", " ")
    out.trimAscii()
}

public func parseAssCues(raw: String): ArrayList<SubtitleCue> {
    let cues = ArrayList<SubtitleCue>()
    let text = raw.replace("\r\n", "\n").replace("\r", "\n")
    var eventSection = false
    var formatFields = ArrayList<String>()
    for (line in text.split("\n")) {
        let trimmed = line.trimAscii()
        if (trimmed.size == 0) {
            continue
        }
        if (trimmed.toAsciiLower() == "[events]") {
            eventSection = true
            continue
        }
        if (trimmed.startsWith("[") && trimmed.endsWith("]")) {
            eventSection = false
            continue
        }
        if (!eventSection) {
            continue
        }
        if (startsWithIgnoreCase(trimmed, "Format:")) {
            formatFields = ArrayList<String>()
            for (f in trimmed[7..trimmed.size].split(",")) {
                formatFields.add(f.trimAscii().toAsciiLower())
            }
            continue
        }
        if (!startsWithIgnoreCase(trimmed, "Dialogue:")) {
            continue
        }
        let payload = trimmed[9..trimmed.size].trimAscii()
        let parts = payload.split(",")
        let fieldCount = if (formatFields.size > 10) {
            formatFields.size
        } else {
            10
        }
        if (parts.size < fieldCount) {
            continue
        }
        var startIndex: Int64 = -1
        var endIndex: Int64 = -1
        var textIndex: Int64 = -1
        for (i in 0..formatFields.size) {
            let f = formatFields[Int64(i)]
            if (f == "start" && startIndex < 0) {
                startIndex = Int64(i)
            }
            if (f == "end" && endIndex < 0) {
                endIndex = Int64(i)
            }
            if (f == "text" && textIndex < 0) {
                textIndex = Int64(i)
            }
        }
        if (startIndex < 0) {
            startIndex = 1
        }
        if (endIndex < 0) {
            endIndex = 2
        }
        if (textIndex < 0) {
            textIndex = 9
        }
        let headLen = if (startIndex > endIndex) {
            startIndex
        } else {
            endIndex
        }
        if (textIndex <= headLen || textIndex >= parts.size) {
            continue
        }
        var body = ""
        for (i in textIndex..parts.size) {
            if (i > textIndex) {
                body += ","
            }
            body += parts[i]
        }
        body = stripAssFormatting(body)
        if (body.size == 0) {
            continue
        }
        cues.add(SubtitleCue(parseSubtitleTimestamp(parts[startIndex]), parseSubtitleTimestamp(parts[endIndex]), body))
    }
    cues
}

// 按 kind/内容嗅探选择解析器（同 client parseSubtitleText）。
public func parseSubtitleText(raw: String, kind: String): ArrayList<SubtitleCue> {
    var text = raw
    if (text.startsWith("\u{FEFF}")) {
        text = text[3..text.size]
    }
    text = text.trimAscii()
    let lowerKind = kind.toAsciiLower()
    if (lowerKind.contains("ass") || lowerKind.contains("ssa") || startsWithIgnoreCase(text, "[Script Info]")) {
        return parseAssCues(text)
    }
    if (lowerKind.contains("vtt") || startsWithIgnoreCase(text, "WEBVTT")) {
        return parseVttCues(text)
    }
    parseSrtCues(text)
}
