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

foreign func libvlc_video_set_format(player: PlayerPtr, chroma: CString, width: UInt32, height: UInt32, pitch: UInt32): Unit

foreign func memcpy(destination: CPointer<Unit>, source: CPointer<Unit>, count: UIntNative): CPointer<Unit>

// client-next has one reader media lane. Keeping the callback target process-global avoids passing
// managed references through libVLC and is safe because VlcPlayer serializes ownership below.
private let FRAME_WIDTH: Int32 = 1280
private let FRAME_HEIGHT: Int32 = 720
private let FRAME_BYTES: Int64 = Int64(FRAME_WIDTH) * Int64(FRAME_HEIGHT) * 4
private let FRAME_MUTEX = Mutex()
private var frameBuffer = CPointer<UInt8>()
private var frameGeneration: UInt64 = 0
private var playerClaimed = false

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

    public init() {
        synchronized(FRAME_MUTEX) {
            if (playerClaimed) {
                throw Exception("only one VlcPlayer may be active")
            }
            playerClaimed = true
            if (frameBuffer.isNull()) {
                frameBuffer = unsafe { LibC.malloc<UInt8>(count: FRAME_BYTES) }
            }
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
            let chroma = unsafe { LibC.mallocCString("RGBA") }
            try {
                unsafe {
                    libvlc_video_set_callbacks(player, videoLock, videoUnlock, videoDisplay, CPointer<Unit>())
                    libvlc_video_set_format(player, chroma, UInt32(FRAME_WIDTH), UInt32(FRAME_HEIGHT),
                        UInt32(FRAME_WIDTH * 4))
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
                unsafe { LibC.free(chroma) }
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
            let pixels = Array<UInt8>(FRAME_BYTES, repeat: 0u8)
            unsafe {
                let handle = acquireArrayRawData(pixels)
                let _ = memcpy(CPointer<Unit>(handle.pointer), CPointer<Unit>(frameBuffer), UIntNative(FRAME_BYTES))
                releaseArrayRawData(handle)
            }
            lastFrameGeneration = frameGeneration
            Some(VideoFrame(FRAME_WIDTH, FRAME_HEIGHT, frameGeneration, pixels))
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
