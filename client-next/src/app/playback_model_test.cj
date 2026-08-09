package lanlu_client_next.app

import std.collection.ArrayList

// PlaybackModel 单测：注入假时钟/假 runner/假下载，覆盖 load→downloaded→play→pause→
// seek→skip→位置推进→mute→stop 全链路，以及重复 load 忽略与 error 路径。

class PbFakeClock {
    var now: Int64 = 0 // 毫秒
}

// 记录调用序列的假 runner：start/pause/resume/stop 及 start 参数。
class FakeRunner <: ProcessRunner {
    let log = ArrayList<String>()
    var lastPath = ""
    var lastOffset: Float64 = -1.0
    var lastMuted = false

    public func start(path: String, offsetSec: Float64, muted: Bool): Unit {
        log.add("start")
        lastPath = path
        lastOffset = offsetSec
        lastMuted = muted
    }
    public func pause(): Unit { log.add("pause") }
    public func resume(): Unit { log.add("resume") }
    public func stop(): Unit { log.add("stop") }

    func label(): String {
        String.join(log.toArray(), delimiter: ",")
    }
}

// 记录 onDownload 触发的 (arcid, pageId) 列表。
class DownloadLog {
    let calls = ArrayList<String>()
    var count: Int64 = 0
}

// 假时钟 + 假 runner + 假下载接线完毕的 PlaybackModel。
class PbFixture {
    let clockBox = PbFakeClock()
    let runner = FakeRunner()
    let downloads = DownloadLog()
    let model = PlaybackModel()

    init() {
        let c = clockBox
        model.clock = { => c.now }
        model.processRunner = Some(runner)
        let d = downloads
        model.onDownload = { arc, pid => d.calls.add("${arc}|${pid}"); d.count++ }
    }

    // 推进假时钟（毫秒）。
    func advance(ms: Int64): Unit {
        clockBox.now += ms
    }
}

// ---- load / 下载回填 ----

@Test
func playbackLoadTriggersDownload(): Unit {
    let f = PbFixture()
    f.model.load("arc1", 4, "p4")
    @Expect(f.model.mediaKey, "arc1:4")
    @Expect(f.model.loading, true)
    @Expect(f.model.loaded, false)
    @Expect(f.downloads.calls.size, 1)
    @Expect(f.downloads.calls[0], "arc1|p4")

    f.model.onDownloaded("arc1:4", "/cache/media/arc1/p4")
    @Expect(f.model.loading, false)
    @Expect(f.model.loaded, true)
    @Expect(f.model.error, "")
}

@Test
func playbackRepeatedLoadIgnored(): Unit {
    let f = PbFixture()
    f.model.load("arc1", 4, "p4")
    f.model.onDownloaded("arc1:4", "/cache/p4")
    // 同 key 已加载：忽略，不重复触发下载
    f.model.load("arc1", 4, "p4")
    @Expect(f.downloads.count, 1)
    @Expect(f.model.loaded, true)
}

@Test
func playbackRemoteVideoDoesNotDownload(): Unit {
    let f = PbFixture()
    f.model.loadRemote("arc1", 4, "http://server/api/archives/arc1/page?path=movie.mkv", "token")
    @Expect(f.model.mediaKey, "arc1:4")
    @Expect(f.model.loading, false)
    @Expect(f.model.loaded, true)
    @Expect(f.model.isVideo, true)
    @Expect(f.downloads.count, 0)
}

@Test
func playbackLoadFailed(): Unit {
    let f = PbFixture()
    f.model.load("arc1", 4, "p4")
    f.model.onFailed("arc1:4", "网络错误")
    @Expect(f.model.loading, false)
    @Expect(f.model.loaded, false)
    @Expect(f.model.error, "网络错误")
    // 出错后 play 是空操作
    f.model.play()
    @Expect(f.model.playing, false)
    @Expect(f.runner.log.size, 0)
}

@Test
func playbackStaleDownloadIgnored(): Unit {
    let f = PbFixture()
    f.model.load("arc1", 4, "p4")
    f.model.load("arc1", 7, "p7") // 切走：旧 key 的结果必须丢弃
    f.model.onDownloaded("arc1:4", "/cache/p4")
    @Expect(f.model.loaded, false)
    @Expect(f.model.loading, true) // 仍是 p7 的在途态
    f.model.onDownloaded("arc1:7", "/cache/p7")
    @Expect(f.model.loaded, true)
}

// ---- 播放 / 暂停 / 位置推进 ----

@Test
func playbackPlayPausePosition(): Unit {
    let f = PbFixture()
    f.model.load("arc1", 4, "p4")
    f.model.onDownloaded("arc1:4", "/cache/p4")
    f.model.play()
    @Expect(f.model.playing, true)
    @Expect(f.runner.label(), "start")
    @Expect(f.runner.lastPath, "/cache/p4")
    @Expect(f.runner.lastOffset, 0.0)
    @Expect(f.runner.lastMuted, false)

    f.advance(1500)
    @Expect(f.model.positionSec, 1.5)

    f.model.pause()
    @Expect(f.model.playing, false)
    @Expect(f.runner.label(), "start,pause")
    @Expect(f.model.positionSec, 1.5) // 暂停后位置冻结
    f.advance(2000)
    @Expect(f.model.positionSec, 1.5)

    f.model.resume()
    @Expect(f.runner.label(), "start,pause,resume")
    f.advance(500)
    @Expect(f.model.positionSec, 2.0)
}

@Test
func playbackTogglePlayFirstStart(): Unit {
    let f = PbFixture()
    f.model.load("arc1", 4, "p4")
    f.model.onDownloaded("arc1:4", "/cache/p4")
    f.model.togglePlay() // 首次 = start
    @Expect(f.runner.label(), "start")
    f.model.togglePlay() // = pause
    @Expect(f.runner.label(), "start,pause")
    @Expect(f.model.playing, false)
}

// ---- seek / skip ----

@Test
func playbackSeekWhilePlayingRestarts(): Unit {
    let f = PbFixture()
    f.model.load("arc1", 4, "p4")
    f.model.onDownloaded("arc1:4", "/cache/p4")
    f.model.play()
    f.advance(1000)
    f.model.seekTo(10.0)
    // seek = stop 后以新 offset 重启
    @Expect(f.runner.label(), "start,stop,start")
    @Expect(f.runner.lastOffset, 10.0)
    f.advance(500)
    @Expect(f.model.positionSec, 10.5)
}

@Test
func playbackSeekWhilePaused(): Unit {
    let f = PbFixture()
    f.model.load("arc1", 4, "p4")
    f.model.onDownloaded("arc1:4", "/cache/p4")
    f.model.play()
    f.advance(1000)
    f.model.pause()
    f.model.seekTo(5.0)
    @Expect(f.model.positionSec, 5.0)
    // 暂停态 seek：冻结的进程被停掉，resume 时按新位置重启
    f.model.resume()
    @Expect(f.runner.lastOffset, 5.0)
}

@Test
func playbackSkipClampsToDuration(): Unit {
    let f = PbFixture()
    f.model.load("arc1", 4, "p4")
    f.model.onDownloaded("arc1:4", "/cache/p4")
    f.model.durationSec = 12.0
    f.model.play()
    f.advance(1000)
    f.model.skip(3.0) // 1.0 + 3.0 = 4.0
    @Expect(f.model.positionSec, 4.0)
    f.model.skip(100.0) // 钳到 duration
    @Expect(f.model.positionSec, 12.0)
    f.model.skip(-100.0) // 钳到 0
    @Expect(f.model.positionSec, 0.0)
}

// ---- mute / stop ----

@Test
func playbackMuteRestartsWithVolume(): Unit {
    let f = PbFixture()
    f.model.load("arc1", 4, "p4")
    f.model.onDownloaded("arc1:4", "/cache/p4")
    f.model.play()
    f.advance(2000)
    f.model.toggleMute()
    @Expect(f.model.muted, true)
    // 记录位置后以 -volume 0 重启
    @Expect(f.runner.label(), "start,stop,start")
    @Expect(f.runner.lastMuted, true)
    @Expect(f.runner.lastOffset, 2.0)
    f.model.toggleMute()
    @Expect(f.runner.lastMuted, false)
}

@Test
func playbackStopResets(): Unit {
    let f = PbFixture()
    f.model.load("arc1", 4, "p4")
    f.model.onDownloaded("arc1:4", "/cache/p4")
    f.model.play()
    f.advance(1000)
    f.model.stop()
    @Expect(f.runner.label(), "start,stop")
    @Expect(f.model.playing, false)
    @Expect(f.model.loaded, false)
    @Expect(f.model.mediaKey, "")
    @Expect(f.model.positionSec, 0.0)
}

@Test
func playbackLoadStopsPrevious(): Unit {
    let f = PbFixture()
    f.model.load("arc1", 4, "p4")
    f.model.onDownloaded("arc1:4", "/cache/p4")
    f.model.play()
    f.model.load("arc1", 7, "p7") // 换媒体：旧进程必须停掉
    @Expect(f.runner.label(), "start,stop")
    @Expect(f.model.playing, false)
    @Expect(f.model.mediaKey, "arc1:7")
}

@Test
func formatMediaClockCases(): Unit {
    @Expect(formatMediaClock(0.0), "00:00")
    @Expect(formatMediaClock(-3.0), "00:00")   // 未知/负值按 0
    @Expect(formatMediaClock(8.9), "00:08")    // 向下取整
    @Expect(formatMediaClock(68.0), "01:08")
    @Expect(formatMediaClock(202.0), "03:22")
}

@Test
func playbackLoadResetsDuration(): Unit {
    // 换媒体时旧时长不得带入：load 复位为 0（未知），等 ffprobe 探测回填。
    let f = PbFixture()
    f.model.load("arc1", 4, "p4")
    f.model.onDownloaded("arc1:4", "/cache/p4")
    f.model.durationSec = 122.0
    f.model.load("arc1", 7, "p7")
    @Expect(f.model.durationSec, 0.0)
}


// ---- 字幕直接设轨 ----

@Test
func setSubtitleTrackIgnoredWhenNotStarted(): Unit {
    let f = PbFixture()
    f.model.loadRemote("arc1", 4, "http://server/movie.mkv", "token")
    f.model.subtitleTrackId = 0
    // 已加载但未开始播放：vlcRunner 尚未建立，直接设轨必须是空操作
    f.model.setSubtitleTrack(2)
    @Expect(f.model.subtitleTrackId, 0)
}

@Test
func setSubtitleTrackIgnoredWhenNotVideo(): Unit {
    let f = PbFixture()
    f.model.load("arc1", 4, "p4") // 音频
    f.model.onDownloaded("arc1:4", "/cache/p4")
    f.model.play()
    f.model.subtitleTrackId = 1
    f.model.setSubtitleTrack(3)
    @Expect(f.model.subtitleTrackId, 1)
}

@Test
func setSubtitleTrackIgnoredWithoutVlcRunner(): Unit {
    let f = PbFixture()
    f.model.load("arc1", 4, "p4", video: true)
    f.model.onDownloaded("arc1:4", "/cache/p4")
    f.model.play() // started=true，但注入的是 FakeRunner（无 vlcRunner）
    f.model.subtitleTrackId = 1
    f.model.setSubtitleTrack(3)
    @Expect(f.model.subtitleTrackId, 1)
}

// ---- 歌词当前行：二分 + 单调前进缓存 ----

@Test
func lyricIndexAdvanceAndSeekBack(): Unit {
    let f = PbFixture()
    f.model.load("arc1", 4, "p4")
    f.model.onDownloaded("arc1:4", "/cache/p4", lyrics: "[00:10.00]a\n[00:20.00]b\n[00:30.00]c")
    @Expect(f.model.lyricsLines.size, 3)
    f.model.play()
    // 首行未到时 -1
    @Expect(f.model.activeLyricIndex(), -1)
    f.advance(10000) // t=10：行 0
    @Expect(f.model.activeLyricIndex(), 0)
    f.advance(15000) // t=25：单调前进快路径到行 1
    @Expect(f.model.activeLyricIndex(), 1)
    f.advance(10000) // t=35：行 2
    @Expect(f.model.activeLyricIndex(), 2)
    // seek 回退：位置回退走二分，结果仍正确
    f.model.seekTo(5.0)
    @Expect(f.model.activeLyricIndex(), -1)
    f.model.seekTo(30.0)
    @Expect(f.model.activeLyricIndex(), 2)
}

@Test
func lyricIndexInvalidatedOnLyricsChange(): Unit {
    let f = PbFixture()
    f.model.load("arc1", 4, "p4")
    f.model.onDownloaded("arc1:4", "/cache/p4", lyrics: "[00:01.00]a\n[00:02.00]b\n[00:03.00]c")
    f.model.play()
    f.advance(10000) // t=10：旧歌词末行
    @Expect(f.model.activeLyricIndex(), 2)
    // 同 key 歌词热替换：缓存索引必须复位，不能沿用到新列表
    f.model.onLyricsDownloaded("arc1:4", "[00:01.00]x")
    @Expect(f.model.lyricsLines.size, 1)
    @Expect(f.model.activeLyricIndex(), 0)
    // 清空歌词后恒 -1
    f.model.loadLyrics(0)
    @Expect(f.model.activeLyricIndex(), -1)
}

// 乱序 LRC：parse 出口按 timeSec 稳定排序（二分/单调前进缓存的有序假设），
// 相同时间戳保持文件内原始先后。
@Test
func parseTimedLyricsSortsUnsortedInput(): Unit {
    let lines = parseTimedLyrics("[00:30.00]c\n[00:10.00]a\n[00:20.00]b1\n[00:20.00]b2")
    @Expect(lines.size, 4)
    @Expect(lines[0].text, "a")
    @Expect(lines[1].text, "b1") // 稳定：b1 先于 b2
    @Expect(lines[2].text, "b2")
    @Expect(lines[3].text, "c")
    @Expect(lines[0].timeSec, 10.0)
    @Expect(lines[3].timeSec, 30.0)
}
