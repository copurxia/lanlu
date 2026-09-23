package lanlu_client_next

import lanlu_client_next.app.*
import cui.media.pixelCacheDiagnosticsPublic
import std.collection.ArrayList
import std.convert.Parsable
import std.env.{exit, getVariable}
import std.fs.{File, OpenMode}
import std.time.MonoTime

// ── 脚本化字幕性能基准（--subtitle-bench）──
// 复用真实 AppModel/PlaybackModel/SubtitleCache/libVLC/libass/SDL，不 mock I/O。
// 以 AppModel.pump 为驱动、按阶段状态机推进；帧拉取与字幕渲染走真实 widget 树
// （drawVideoStage），本类只负责编排状态切换、采样与结果输出。
// 需设置 LANLU_PERF=1 才能拿到 SubtitlePerf 采集的计时样本。
//
// 环境变量配置：
//   LANLU_BENCH_ARCID     目标档案 id（必填）
//   LANLU_BENCH_PAGE      视频页 1 基页码（默认 6）
//   LANLU_BENCH_PLAY_MS   静止播放采样时长（默认 10000）
//   LANLU_BENCH_TOGGLES   逗号分隔的 streamIndex（空 = 自动取前两条内嵌轨）
//   LANLU_BENCH_SEEK_MS   逗号分隔的 seek 目标毫秒（默认 6250000,6264000）
//   LANLU_BENCH_OUT       结果 JSON 输出路径（可选）

public class SubtitleBench {
    private let arcid: String
    private let page: Int64
    private let playMs: Int64
    private let toggles: ArrayList<Int32>
    private let seeks: ArrayList<Int64>
    private let outPath: String

    private var phase: Int64 = 0
    private var steadyDeadline = MonoTime.now()
    private var waitGen: UInt64 = 0
    private var toggleIdx: Int64 = 0
    private var seekIdx: Int64 = 0
    private var seekStart = MonoTime.now()
    private var rssPeak: Int64 = 0
    private var done = false

    public init() {
        arcid = getVariable("LANLU_BENCH_ARCID") ?? ""
        page = SubtitleBench.parseEnvInt("LANLU_BENCH_PAGE", 6)
        playMs = SubtitleBench.parseEnvInt("LANLU_BENCH_PLAY_MS", 10000)
        toggles = SubtitleBench.parseToggles(getVariable("LANLU_BENCH_TOGGLES"))
        seeks = SubtitleBench.parseSeeks(getVariable("LANLU_BENCH_SEEK_MS"))
        outPath = getVariable("LANLU_BENCH_OUT") ?? ""
    }

    public func isEnabled(): Bool {
        arcid.size > 0
    }

    // 每个 UI tick 调一次（在 model.pump 之后）。返回 true 表示基准结束（已 exit）。
    public func step(model: AppModel): Bool {
        if (done || arcid.size == 0) {
            return done
        }
        sampleRss()
        match (phase) {
            case 0 => stepInit(model)
            case 1 => stepWaitPages(model)
            case 2 => stepWaitCold(model)
            case 3 => stepPlay(model)
            case 4 => stepWaitPlaying(model)
            case 5 => stepSteady(model)
            case 6 => stepToggle(model)
            case 7 => stepSeek(model)
            case 8 => stepReopen(model)
            case 9 => stepFinish(model)
            case _ => stepFinish(model)
        }
        done
    }

    // P1 冷扫描：清缓存 + 打开阅读器视频页。
    private func stepInit(model: AppModel): Unit {
        SubtitlePerf.reset()
        model.clearSubtitleCache()
        println("[subtitle-bench] clearing subtitle cache, opening ${arcid} page ${page}")
        model.openReader(arcid, page)
        phase = 1
    }

    // 等待页表到货且当前页确为视频页。
    private func stepWaitPages(model: AppModel): Unit {
        let idx = page - 1
        match (model.reader.pageAt(idx)) {
            case Some(p) =>
                if (p.pageType == "video") {
                    println("[subtitle-bench] video page ready (pages=${model.pages.value.size})")
                    phase = 2
                }
            case None => ()
        }
    }

    // 等待 probe + scan 完成（内嵌轨已枚举且无在途）。
    private func stepWaitCold(model: AppModel): Unit {
        let pb = model.playback
        if (pb.embeddedSubtitleStreams.size > 0 && !pb.subtitleProbeLoading && !pb.subtitleScanLoading) {
            SubtitlePerf.emit("probe_ms", SubtitlePerf.getGauge("subtitle_probe_e2e"), "ms")
            SubtitlePerf.emit("scan_ms", SubtitlePerf.getGauge("subtitle_scan_e2e"), "ms")
            SubtitlePerf.emit("subtitle_track_count", SubtitlePerf.getGauge("subtitle_track_count"), "n")
            SubtitlePerf.emit("subtitle_event_count", SubtitlePerf.getGauge("subtitle_event_count"), "n")
            SubtitlePerf.emit("subtitle_cache_bytes", SubtitlePerf.getGauge("subtitle_cache_bytes"), "B")
            SubtitlePerf.emit("managed_subtitle_bytes", SubtitlePerf.getGauge("managed_subtitle_bytes"), "B")
            println("[subtitle-bench] cold scan done: ${pb.embeddedSubtitleStreams.size} streams")
            // 选择首条受支持内嵌轨，使静止播放阶段带字幕渲染（贴近真实场景）。
            selectFirstSupported(model)
            phase = 3
        }
    }

    private func selectFirstSupported(model: AppModel): Unit {
        for (stream in model.playback.embeddedSubtitleStreams) {
            if (stream.supported) {
                model.playback.toggleEmbeddedSubtitle(stream.streamIndex)
                return
            }
        }
    }

    private func stepPlay(model: AppModel): Unit {
        if (model.playback.loaded) {
            model.playback.play()
            println("[subtitle-bench] play started")
            phase = 4
        }
    }

    // 等待首个视频帧交付（videoGeneration 前进）。
    private func stepWaitPlaying(model: AppModel): Unit {
        if (model.playback.playing && model.playback.videoGeneration > 0) {
            println("[subtitle-bench] first video frame delivered")
            steadyDeadline = MonoTime.now() + Duration.millisecond * playMs
            SubtitlePerf.reset()
            phase = 5
        }
    }

    // P2 静止播放：采集播放帧与字幕渲染耗时，持续 playMs。
    private func stepSteady(model: AppModel): Unit {
        if (MonoTime.now() >= steadyDeadline) {
            SubtitlePerf.flushSamples("playback_frame")
            SubtitlePerf.flushSamples("subtitle_render")
            SubtitlePerf.emit("subtitle_upload_count", SubtitlePerf.getCounter("subtitle_upload_count"), "n")
            SubtitlePerf.emit("subtitle_bitmap_changed_count", SubtitlePerf.getCounter("subtitle_bitmap_changed_count"), "n")
            println("[subtitle-bench] steady playback sampled")
            SubtitlePerf.reset()
            prepareToggleList(model)
            phase = 6
        }
    }

    // 准备要切换的轨列表：显式指定或自动取前两条受支持内嵌轨。
    private func prepareToggleList(model: AppModel): Unit {
        if (toggles.isEmpty()) {
            var count: Int64 = 0
            for (stream in model.playback.embeddedSubtitleStreams) {
                if (stream.supported && count < 2) {
                    toggles.add(stream.streamIndex)
                    count++
                }
            }
        }
        toggleIdx = 0
    }

    // P3 字幕切换：逐个 toggle，等待首个 changed bitmap 渲染。
    private func stepToggle(model: AppModel): Unit {
        let pb = model.playback
        if (toggleIdx >= toggles.size) {
            println("[subtitle-bench] subtitle switch done")
            SubtitlePerf.reset()
            seekIdx = 0
            phase = 7
            return
        }
        let target = toggles[toggleIdx]
        // 首次进入本轨切换：toggle 前记录当前代际，等待其前进。
        if (waitGen == 0) {
            waitGen = pb.subtitleBitmapGeneration
            SubtitlePerf.spanStart("subtitle_switch")
            pb.toggleEmbeddedSubtitle(target)
            println("[subtitle-bench] toggling embedded stream ${target}")
            return
        }
        if (pb.subtitleBitmapGeneration > waitGen) {
            SubtitlePerf.spanEnd("subtitle_switch")
            SubtitlePerf.emit("subtitle_switch_ms", SubtitlePerf.getGauge("subtitle_switch"), "ms")
            println("[subtitle-bench] switch to ${target} rendered in ${SubtitlePerf.getGauge("subtitle_switch")}ms")
            waitGen = 0
            toggleIdx++
        }
    }

    // P4 seek：跳到真实事件位置，测量 seek 后首帧字幕渲染延迟。
    private func stepSeek(model: AppModel): Unit {
        let pb = model.playback
        if (seekIdx >= seeks.size) {
            println("[subtitle-bench] seek done")
            SubtitlePerf.reset()
            phase = 8
            return
        }
        if (waitGen == 0) {
            waitGen = pb.subtitleBitmapGeneration
            seekStart = MonoTime.now()
            pb.seekTo(Float64(seeks[seekIdx]) / 1000.0)
            println("[subtitle-bench] seek to ${seeks[seekIdx]}ms")
            return
        }
        if (pb.subtitleBitmapGeneration > waitGen) {
            let ms = (MonoTime.now() - seekStart).toMilliseconds()
            SubtitlePerf.emit("subtitle_seek_ms", ms, "ms")
            println("[subtitle-bench] seek ${seeks[seekIdx]} rendered in ${ms}ms")
            waitGen = 0
            seekIdx++
        }
    }

    // P5 缓存命中：停播放 + 关阅读器 → 重新打开同一视频页，等待轨就绪（应命中缓存）。
    private func stepReopen(model: AppModel): Unit {
        let pb = model.playback
        match (phase) {
            case 8 =>
                pb.stop()
                model.openReader(arcid, page)
                SubtitlePerf.spanStart("subtitle_cache_hit_e2e")
                println("[subtitle-bench] reopened reader for cache-hit measurement")
                phase = 80
            case 80 =>
                let idx = page - 1
                match (model.reader.pageAt(idx)) {
                    case Some(p) =>
                        if (p.pageType == "video" && pb.embeddedSubtitleStreams.size > 0 && !pb.subtitleScanLoading) {
                            SubtitlePerf.spanEnd("subtitle_cache_hit_e2e")
                            SubtitlePerf.emit("cache_hit_ms", SubtitlePerf.getGauge("subtitle_cache_hit_e2e"), "ms")
                            SubtitlePerf.emit("subtitle_cache_hit_count", SubtitlePerf.getCounter("subtitle_cache_hit_count"), "n")
                            SubtitlePerf.emit("subtitle_scan_count", SubtitlePerf.getCounter("subtitle_scan_count"), "n")
                            SubtitlePerf.emit("subtitle_cache_bytes", model.subtitleCacheBytes(), "B")
                            SubtitlePerf.emit("subtitle_cache_files", model.subtitleCacheFileCount(), "n")
                            println("[subtitle-bench] cache hit done (${SubtitlePerf.getGauge("subtitle_cache_hit_e2e")}ms)")
                            phase = 9
                        }
                    case None => ()
                }
            case _ => ()
        }
    }

    // P6 峰值内存 + 汇总输出。
    private func stepFinish(model: AppModel): Unit {
        sampleRss()
        SubtitlePerf.emit("peak_rss_bytes", rssPeak, "B")
        let (staged, texture, entries, evicts) = pixelCacheDiagnosticsPublic()
        SubtitlePerf.emit("pixel_staged_bytes", staged, "B")
        SubtitlePerf.emit("pixel_texture_bytes", texture, "B")
        SubtitlePerf.emit("pixel_entry_count", entries, "n")
        SubtitlePerf.emit("pixel_evict_count", evicts, "n")
        println("[subtitle-bench] finished. peak_rss=${rssPeak}B")
        if (outPath.size > 0) {
            writeSummary(outPath)
        }
        done = true
        model.playback.stop()
        exit(0)
    }

    private func sampleRss(): Unit {
        let rss = SubtitlePerf.rssHwmBytes()
        if (rss > rssPeak) {
            rssPeak = rss
        }
    }

    private func writeSummary(path: String): Unit {
        try {
            let probe = SubtitlePerf.getGauge("subtitle_probe_e2e")
            let scan = SubtitlePerf.getGauge("subtitle_scan_e2e")
            let hit = SubtitlePerf.getGauge("subtitle_cache_hit_e2e")
            let json = "{\"probe_ms\":${probe},\"scan_ms\":${scan},\"cache_hit_ms\":${hit}," +
                "\"peak_rss_bytes\":${rssPeak},\"track_count\":${SubtitlePerf.getGauge("subtitle_track_count")}," +
                "\"event_count\":${SubtitlePerf.getGauge("subtitle_event_count")}," +
                "\"cache_bytes\":${SubtitlePerf.getGauge("subtitle_cache_bytes")}," +
                "\"managed_subtitle_bytes\":${SubtitlePerf.getGauge("managed_subtitle_bytes")}}"
            File(path, OpenMode.Write).write(json.toArray())
        } catch (e: Exception) {
            println("[subtitle-bench] failed to write summary: ${e}")
        }
    }

    private static func parseEnvInt(name: String, default: Int64): Int64 {
        match (getVariable(name)) {
            case Some(v) => Int64.parse(v)
            case None => default
        }
    }

    private static func parseToggles(raw: ?String): ArrayList<Int32> {
        let list = ArrayList<Int32>()
        match (raw) {
            case Some(s) =>
                for (part in s.split(",")) {
                    let t = part.trimAscii()
                    if (t.size > 0) {
                        list.add(Int32(Int64.parse(t)))
                    }
                }
            case None => ()
        }
        list
    }

    private static func parseSeeks(raw: ?String): ArrayList<Int64> {
        let list = ArrayList<Int64>()
        match (raw) {
            case Some(s) =>
                for (part in s.split(",")) {
                    let t = part.trimAscii()
                    if (t.size > 0) {
                        list.add(Int64.parse(t))
                    }
                }
            case None =>
                list.add(6250000)
                list.add(6264000)
        }
        list
    }
}
