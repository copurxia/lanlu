package libvlc_ffi

import std.sync.Mutex
import std.collection.ArrayList

@C
public struct LibVlcInstance {
    init() {
        throw Exception("opaque libVLC type")
    }
}

@C
public struct LibVlcMedia {
    init() {
        throw Exception("opaque libVLC type")
    }
}

@C
public struct LibVlcMediaPlayer {
    init() {
        throw Exception("opaque libVLC type")
    }
}

@C
public struct LibVlcTrackDescription {
    var id: Int32 = 0
    var name = CPointer<UInt8>()
    var next = CPointer<LibVlcTrackDescription>()
}

private type InstancePtr = CPointer<LibVlcInstance>

private type MediaPtr = CPointer<LibVlcMedia>

private type PlayerPtr = CPointer<LibVlcMediaPlayer>

foreign func libvlc_new(argc: Int32, argv: CPointer<CString>): InstancePtr

foreign func libvlc_release(instance: InstancePtr): Unit

foreign func libvlc_media_new_path(instance: InstancePtr, path: CString): MediaPtr
foreign func libvlc_media_new_location(instance: InstancePtr, location: CString): MediaPtr
foreign func libvlc_media_add_option(media: MediaPtr, option: CString): Unit

foreign func libvlc_media_release(media: MediaPtr): Unit

foreign func libvlc_media_player_new_from_media(media: MediaPtr): PlayerPtr

foreign func libvlc_media_player_release(player: PlayerPtr): Unit

foreign func libvlc_media_player_play(player: PlayerPtr): Int32

foreign func libvlc_media_player_set_pause(player: PlayerPtr, paused: Int32): Unit

foreign func libvlc_media_player_stop(player: PlayerPtr): Unit

foreign func libvlc_media_player_set_time(player: PlayerPtr, timeMs: Int64): Int32

foreign func libvlc_media_player_get_time(player: PlayerPtr): Int64

foreign func libvlc_media_player_get_length(player: PlayerPtr): Int64

foreign func libvlc_audio_set_mute(player: PlayerPtr, muted: Int32): Int32
foreign func libvlc_audio_set_volume(player: PlayerPtr, volume: Int32): Int32

foreign func libvlc_video_get_spu(player: PlayerPtr): Int32

foreign func libvlc_video_get_spu_description(player: PlayerPtr): CPointer<LibVlcTrackDescription>

foreign func libvlc_video_set_spu(player: PlayerPtr, spu: Int32): Int32

foreign func libvlc_track_description_list_release(description: CPointer<LibVlcTrackDescription>): Unit

private type LockCallback = CFunc<(CPointer<Unit>, CPointer<CPointer<Unit>>) -> CPointer<Unit>>

private type UnlockCallback = CFunc<(CPointer<Unit>, CPointer<Unit>, CPointer<CPointer<Unit>>) -> Unit>

private type DisplayCallback = CFunc<(CPointer<Unit>, CPointer<Unit>) -> Unit>

foreign func libvlc_video_set_callbacks(player: PlayerPtr, lock: LockCallback, unlock: UnlockCallback,
    display: DisplayCallback, opaque: CPointer<Unit>): Unit

// 格式协商回调（libvlc_video_format_cb / libvlc_video_cleanup_cb）：VLC 在解码器
// 产出实际格式后回调 setup，chroma/width/height 为 IN/OUT，pitches/lines 为 OUT，
// 返回分配的缓冲平面数（0 = 失败）。cleanup 在 vout 结束时回调。
private type FormatCallback = CFunc<(CPointer<CPointer<Unit>>, CPointer<UInt8>, CPointer<UInt32>,
    CPointer<UInt32>, CPointer<UInt32>, CPointer<UInt32>) -> UInt32>

private type FormatCleanupCallback = CFunc<(CPointer<Unit>) -> Unit>

foreign func libvlc_video_set_format_callbacks(player: PlayerPtr, setup: FormatCallback,
    cleanup: FormatCleanupCallback): Unit

foreign func memcpy(destination: CPointer<Unit>, source: CPointer<Unit>, count: UIntNative): CPointer<Unit>

// client-next has one reader media lane. Keeping the callback target process-global avoids passing
// managed references through libVLC and is safe because VlcPlayer serializes ownership below.
// 帧尺寸由 videoFormatSetup 按解码器原生分辨率回填；取不到（setup 传入 0）时回退 1280x720。
private let FALLBACK_FRAME_WIDTH: Int32 = 1280
private let FALLBACK_FRAME_HEIGHT: Int32 = 720
private var frameWidth: Int32 = FALLBACK_FRAME_WIDTH
private var frameHeight: Int32 = FALLBACK_FRAME_HEIGHT
private var frameBytes: Int64 = Int64(FALLBACK_FRAME_WIDTH) * Int64(FALLBACK_FRAME_HEIGHT) * 4
private let FRAME_MUTEX = Mutex()
private var frameBuffer = CPointer<UInt8>()
private var frameBufferCapacity: Int64 = 0
private var frameGeneration: UInt64 = 0
private var playerClaimed = false

// 帧格式协商：chroma 固定改写为 RGBA；width/height 保留解码器原生值（0 时回退），
// 按需增长全局帧缓冲（缩容不释放，后续同尺寸/更小分辨率直接复用），pitch 紧密排列。
// 在 VLC 解码线程上调用；与 takeFrame 经 FRAME_MUTEX 串行化，缓冲重分配不会撞上拷贝。
@C
private func videoFormatSetup(_: CPointer<CPointer<Unit>>, chroma: CPointer<UInt8>, width: CPointer<UInt32>,
    height: CPointer<UInt32>, pitches: CPointer<UInt32>, lines: CPointer<UInt32>): UInt32 {
    unsafe {
        (chroma + 0).write(0x52u8) // 'R'
        (chroma + 1).write(0x47u8) // 'G'
        (chroma + 2).write(0x42u8) // 'B'
        (chroma + 3).write(0x41u8) // 'A'
        var w = width.read()
        var h = height.read()
        if (w == 0 || h == 0) {
            w = UInt32(FALLBACK_FRAME_WIDTH)
            h = UInt32(FALLBACK_FRAME_HEIGHT)
            width.write(w)
            height.write(h)
        }
        pitches.write(w * 4)
        lines.write(h)
        let need = Int64(w) * Int64(h) * 4
        synchronized(FRAME_MUTEX) {
            if (need > frameBufferCapacity) {
                if (!frameBuffer.isNull()) {
                    LibC.free(frameBuffer)
                }
                frameBuffer = LibC.malloc<UInt8>(count: need)
                frameBufferCapacity = if (frameBuffer.isNull()) {
                    0
                } else {
                    need
                }
            }
            if (frameBufferCapacity > 0) {
                frameWidth = Int32(w)
                frameHeight = Int32(h)
                frameBytes = need
            }
        }
    }
    if (frameBufferCapacity == 0) {
        return 0
    }
    1
}

@C
private func videoFormatCleanup(_: CPointer<Unit>): Unit {
    // 全局帧缓冲跨 open 复用（尺寸变化时由 setup 按需增长），这里不做释放。
}

@C
private func videoLock(_: CPointer<Unit>, planes: CPointer<CPointer<Unit>>): CPointer<Unit> {
    FRAME_MUTEX.lock()
    unsafe { planes.write(CPointer<Unit>(frameBuffer)) }
    CPointer<Unit>()
}

@C
private func videoUnlock(_: CPointer<Unit>, _: CPointer<Unit>, _: CPointer<CPointer<Unit>>): Unit {
    frameGeneration++
    FRAME_MUTEX.unlock()
}

@C
private func videoDisplay(_: CPointer<Unit>, _: CPointer<Unit>): Unit {}

public class VideoFrame {
    public let width: Int32
    public let height: Int32
    public let generation: UInt64
    // 借用语义：该数组由 VlcPlayer 持有并在下次 takeFrame 返回新帧时原地覆写
    // （尺寸变化才重新分配）。需要跨帧持久持有的调用方必须自行拷贝；
    // client-next 的用法（当帧同步上传纹理）不受此限制。
    public let rgba: Array<UInt8>

    init(width: Int32, height: Int32, generation: UInt64, rgba: Array<UInt8>) {
        this.width = width
        this.height = height
        this.generation = generation
        this.rgba = rgba
    }
}

public class SubtitleTrack {
    public let id: Int32
    public let name: String

    init(id: Int32, name: String) {
        this.id = id
        this.name = name
    }
}

public class VlcPlayer <: Resource {
    private var instance = InstancePtr()
    private var player = PlayerPtr()
    private var lastFrameGeneration: UInt64 = 0
    // takeFrame 复用的出帧数组：尺寸（frameBytes）不变时原地覆写，避免每帧分配。
    private var framePixels = Array<UInt8>(0, repeat: 0u8)

    public init() {
        synchronized(FRAME_MUTEX) {
            if (playerClaimed) {
                throw Exception("only one VlcPlayer may be active")
            }
            playerClaimed = true
        }
        instance = unsafe { libvlc_new(0, CPointer<CString>()) }
        if (instance.isNull()) {
            synchronized(FRAME_MUTEX) {
                playerClaimed = false
            }
            throw Exception("libVLC initialization failed")
        }
    }

    public func open(path: String, offsetSec!: Float64 = 0.0, muted!: Bool = false,
        authToken!: String = ""): Unit {
        stop()
        let cpath = unsafe { LibC.mallocCString(path) }
        try {
            let media = if (path.startsWith("http://") || path.startsWith("https://")) {
                unsafe { libvlc_media_new_location(instance, cpath) }
            } else {
                unsafe { libvlc_media_new_path(instance, cpath) }
            }
            if (media.isNull()) {
                throw Exception("libVLC could not open media")
            }
            try {
                if (authToken.size > 0) {
                    let cookie = unsafe { LibC.mallocCString(":http-cookie=auth_token=${authToken}") }
                    try { unsafe { libvlc_media_add_option(media, cookie) } }
                    finally { unsafe { LibC.free(cookie) } }
                }
                player = unsafe { libvlc_media_player_new_from_media(media) }
            } finally {
                unsafe { libvlc_media_release(media) }
            }
            if (player.isNull()) {
                throw Exception("libVLC could not create media player")
            }
            unsafe {
                libvlc_video_set_callbacks(player, videoLock, videoUnlock, videoDisplay, CPointer<Unit>())
                // 帧尺寸不由本侧指定：格式协商回调（videoFormatSetup）按解码器
                // 原生分辨率设置 chroma/pitch 并增长全局帧缓冲，取不到时回退 1280x720。
                libvlc_video_set_format_callbacks(player, videoFormatSetup, videoFormatCleanup)
                let _ = libvlc_audio_set_mute(player, if (muted) {
                    1
                } else {
                    0
                })
                if (libvlc_media_player_play(player) != 0) {
                    throw Exception("libVLC playback failed")
                }
                if (offsetSec > 0.0) {
                    let _ = libvlc_media_player_set_time(player, Int64(offsetSec * 1000.0))
                }
            }
        } finally {
            unsafe { LibC.free(cpath) }
        }
    }

    public func pause(): Unit {
        if (!player.isNull()) {
            unsafe { libvlc_media_player_set_pause(player, 1) }
        }
    }
    public func resume(): Unit {
        if (!player.isNull()) {
            unsafe { libvlc_media_player_set_pause(player, 0) }
        }
    }
    public func seek(sec: Float64): Unit {
        if (!player.isNull()) {
            unsafe { let _ = libvlc_media_player_set_time(player, Int64(max(0.0, sec) * 1000.0)) }
        }
    }
    public func setMuted(muted: Bool): Unit {
        if (!player.isNull()) {
            unsafe { let _ = libvlc_audio_set_mute(player, if (muted) {
                1
            } else {
                0
            }) }
        }
    }
    public func setVolume(volume: Int32): Unit {
        if (!player.isNull()) {
            unsafe { let _ = libvlc_audio_set_volume(player, max(0, min(100, volume))) }
        }
    }
    public func timeSec(): Float64 {
        if (player.isNull()) {
            return 0.0
        }
        Float64(max(0, unsafe { libvlc_media_player_get_time(player) })) / 1000.0
    }
    public func durationSec(): Float64 {
        if (player.isNull()) {
            return 0.0
        }
        Float64(max(0, unsafe { libvlc_media_player_get_length(player) })) / 1000.0
    }

    public func subtitleTracks(): ArrayList<SubtitleTrack> {
        let tracks = ArrayList<SubtitleTrack>()
        if (player.isNull()) { return tracks }
        let head = unsafe { libvlc_video_get_spu_description(player) }
        var cursor = head
        while (!cursor.isNull()) {
            let item = unsafe { cursor.read() }
            let name = if (item.name.isNull()) { "字幕 ${item.id}" } else { CString(item.name).toString() }
            tracks.add(SubtitleTrack(item.id, name))
            cursor = item.next
        }
        if (!head.isNull()) { unsafe { libvlc_track_description_list_release(head) } }
        tracks
    }

    public func currentSubtitleTrack(): Int32 {
        if (player.isNull()) { return -1 }
        unsafe { libvlc_video_get_spu(player) }
    }

    public func setSubtitleTrack(id: Int32): Bool {
        if (player.isNull()) { return false }
        unsafe { libvlc_video_set_spu(player, id) == 0 }
    }

    public func takeFrame(): ?VideoFrame {
        synchronized(FRAME_MUTEX) {
            if (frameGeneration == lastFrameGeneration || frameBuffer.isNull()) {
                return None
            }
            // 复用上帧数组：frameBytes 不变（同分辨率连续帧）时原地覆写，
            // 分辨率切换（videoFormatSetup 更新 frameBytes）才重新分配。
            if (framePixels.size != frameBytes) {
                framePixels = Array<UInt8>(frameBytes, repeat: 0u8)
            }
            unsafe {
                let handle = acquireArrayRawData(framePixels)
                let _ = memcpy(CPointer<Unit>(handle.pointer), CPointer<Unit>(frameBuffer), UIntNative(frameBytes))
                releaseArrayRawData(handle)
            }
            lastFrameGeneration = frameGeneration
            Some(VideoFrame(frameWidth, frameHeight, frameGeneration, framePixels))
        }
    }

    public func stop(): Unit {
        if (!player.isNull()) {
            unsafe {
                libvlc_media_player_stop(player)
                libvlc_media_player_release(player)
            }
            player = PlayerPtr()
        }
    }

    public func close(): Unit {
        stop()
        if (!instance.isNull()) {
            unsafe { libvlc_release(instance) }
            instance = InstancePtr()
        }
        synchronized(FRAME_MUTEX) {
            playerClaimed = false
        }
    }

    public func isClosed(): Bool {
        instance.isNull()
    }
}
