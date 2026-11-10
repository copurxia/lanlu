package libass_ffi

import std.collection.ArrayList

@C
struct NativeAssRenderer {
    init() {
        throw Exception("opaque libass renderer")
    }
}

@C
struct NativeAssTrack {
    init() {
        throw Exception("opaque libass track")
    }
}

@C
struct NativeAssBitmap {
    var canvasWidth: Int32 = 0
    var canvasHeight: Int32 = 0
    var x: Int32 = 0
    var y: Int32 = 0
    var width: Int32 = 0
    var height: Int32 = 0
    var changed: Int32 = 0
    var rgba = CPointer<UInt8>()
    var rgbaSize: Int64 = 0
    var error = CPointer<UInt8>()
}

type NativeRendererPtr = CPointer<NativeAssRenderer>

type NativeTrackPtr = CPointer<NativeAssTrack>

foreign func llass_runtime_version(): UInt32

foreign func llass_compiled_version(): UInt32

foreign func llass_renderer_new(width: Int32, height: Int32, error: CPointer<CPointer<UInt8>>): NativeRendererPtr

foreign func llass_renderer_configure(renderer: NativeRendererPtr, width: Int32, height: Int32, pixelAspect: Float64,
    error: CPointer<CPointer<UInt8>>): Int32

foreign func llass_renderer_free(renderer: NativeRendererPtr): Unit

foreign func llass_track_read(renderer: NativeRendererPtr, data: CPointer<UInt8>, size: Int64,
    error: CPointer<CPointer<UInt8>>): NativeTrackPtr

foreign func llass_track_new(renderer: NativeRendererPtr, data: CPointer<UInt8>, size: Int64,
    error: CPointer<CPointer<UInt8>>): NativeTrackPtr

foreign func llass_track_process_chunk(track: NativeTrackPtr, data: CPointer<UInt8>, size: Int64, startMs: Int64,
    durationMs: Int64, error: CPointer<CPointer<UInt8>>): Int32

foreign func llass_track_flush(track: NativeTrackPtr): Unit

foreign func llass_track_free(track: NativeTrackPtr): Unit

foreign func llass_render(renderer: NativeRendererPtr, tracks: CPointer<NativeTrackPtr>, trackCount: Int64, nowMs: Int64): CPointer<NativeAssBitmap>

foreign func llass_bitmap_free(bitmap: CPointer<NativeAssBitmap>): Unit

foreign func llass_error_free(error: CPointer<UInt8>): Unit

private let MAX_DIMENSION: Int64 = 16384

public class AssNativeException <: Exception {
    public init(message: String) {
        super(message)
    }
}

public class SubtitleBitmap {
    public let canvasWidth: Int32
    public let canvasHeight: Int32
    public let x: Int32
    public let y: Int32
    public let width: Int32
    public let height: Int32
    public let changed: Int32
    public let rgba: Array<UInt8>

    init(native: NativeAssBitmap) {
        let nativeCanvasWidth = native.canvasWidth
        let nativeCanvasHeight = native.canvasHeight
        let nativeX = native.x
        let nativeY = native.y
        let nativeWidth = native.width
        let nativeHeight = native.height
        let nativeSize = native.rgbaSize
        let nativeRgba = native.rgba
        let nativeChanged = native.changed
        if (nativeCanvasWidth <= 0 || nativeCanvasHeight <= 0 || Int64(nativeCanvasWidth) > MAX_DIMENSION ||
            Int64(nativeCanvasHeight) > MAX_DIMENSION || nativeX < 0 || nativeY < 0 || nativeWidth < 0 ||
            nativeHeight < 0 || Int64(nativeX) + Int64(nativeWidth) > Int64(nativeCanvasWidth) ||
            Int64(nativeY) + Int64(nativeHeight) > Int64(nativeCanvasHeight) ||
            (nativeWidth == 0) != (nativeHeight == 0)) {
            throw AssNativeException("invalid native subtitle bitmap geometry")
        }
        let expectedSize = Int64(nativeWidth) * Int64(nativeHeight) * 4
        canvasWidth = nativeCanvasWidth
        canvasHeight = nativeCanvasHeight
        x = nativeX
        y = nativeY
        width = nativeWidth
        height = nativeHeight
        changed = nativeChanged
        if (nativeChanged == 0) {
            if (nativeSize != 0 || !nativeRgba.isNull()) {
                throw AssNativeException("unchanged subtitle bitmap must not carry pixels")
            }
            rgba = Array<UInt8>(0, repeat: 0u8)
        } else if (expectedSize == 0) {
            if (nativeSize != 0 || !nativeRgba.isNull()) {
                throw AssNativeException("empty subtitle bitmap must not carry pixels")
            }
            rgba = Array<UInt8>(0, repeat: 0u8)
        } else {
            if (nativeSize != expectedSize || nativeRgba.isNull()) {
                throw AssNativeException("invalid native subtitle bitmap size ${nativeSize}")
            }
            rgba = Array<UInt8>(expectedSize, {index => unsafe { nativeRgba.read(index) }})
        }
    }
}

/** A libass track owned by the renderer thread that created it. */
public class AssTrack <: Resource {
    private var native: NativeTrackPtr

    init(native: NativeTrackPtr) {
        this.native = native
    }

    public func close(): Unit {
        if (!native.isNull()) {
            unsafe { llass_track_free(native) }
            native = NativeTrackPtr()
        }
    }

    public func isClosed(): Bool {
        native.isNull()
    }

    public func flush(): Unit {
        ensureOpen()
        unsafe { llass_track_flush(native) }
    }

    internal func pointer(): NativeTrackPtr {
        ensureOpen()
        native
    }

    public func addChunk(bytes: Array<UInt8>, startMs: Int64, durationMs: Int64): Unit {
        ensureOpen()
        if (bytes.size == 0) {
            return
        }
        var error = CPointer<UInt8>()
        unsafe {
            let handle = acquireArrayRawData(bytes)
            try {
                let status = llass_track_process_chunk(native, handle.pointer, bytes.size, startMs, durationMs,
                    CPointer<CPointer<UInt8>>(inout error))
                if (status != 0) {
                    throwOwnedError(error, "ass_process_chunk failed")
                }
            } finally {
                releaseArrayRawData(handle)
            }
        }
    }

    private func ensureOpen(): Unit {
        if (native.isNull()) {
            throw AssNativeException("ASS track is closed")
        }
    }
}

/** Renderer and library owner. Create, access and close it on one UI/render thread. */
public class AssRenderer <: Resource {
    private var native: NativeRendererPtr
    private let ownedTracks = ArrayList<AssTrack>()

    public init(width: Int32, height: Int32) {
        ensureCompatibleLibassRuntime()
        var error = CPointer<UInt8>()
        native = unsafe { llass_renderer_new(width, height, CPointer<CPointer<UInt8>>(inout error)) }
        if (native.isNull()) {
            throwOwnedError(error, "libass renderer initialization failed")
        }
    }

    public func configure(width: Int32, height: Int32, pixelAspect!: Float64 = 1.0): Unit {
        ensureOpen()
        var error = CPointer<UInt8>()
        let status = unsafe { llass_renderer_configure(native, width, height, pixelAspect,
            CPointer<CPointer<UInt8>>(inout error)) }
        if (status != 0) {
            throwOwnedError(error, "libass renderer configuration failed")
        }
    }

    public func readAssDocument(bytes: Array<UInt8>): AssTrack {
        ensureOpen()
        if (bytes.size == 0) {
            throw AssNativeException("ASS document must not be empty")
        }
        var error = CPointer<UInt8>()
        let track = unsafe {
            let handle = acquireArrayRawData(bytes)
            try {
                llass_track_read(native, handle.pointer, bytes.size, CPointer<CPointer<UInt8>>(inout error))
            } finally {
                releaseArrayRawData(handle)
            }
        }
        if (track.isNull()) {
            throwOwnedError(error, "ASS document parse failed")
        }
        let owned = AssTrack(track)
        ownedTracks.add(owned)
        owned
    }

    public func newMatroskaTrack(codecPrivate: Array<UInt8>): AssTrack {
        ensureOpen()
        var error = CPointer<UInt8>()
        let track = if (codecPrivate.size == 0) {
            unsafe { llass_track_new(native, CPointer<UInt8>(), 0, CPointer<CPointer<UInt8>>(inout error)) }
        } else {
            unsafe {
                let handle = acquireArrayRawData(codecPrivate)
                try {
                    llass_track_new(native, handle.pointer, codecPrivate.size, CPointer<CPointer<UInt8>>(inout error))
                } finally {
                    releaseArrayRawData(handle)
                }
            }
        }
        if (track.isNull()) {
            throwOwnedError(error, "ASS track initialization failed")
        }
        let owned = AssTrack(track)
        ownedTracks.add(owned)
        owned
    }

    public func newPlainTrack(events: ArrayList<PlainSubtitleEvent>): AssTrack {
        let track = newMatroskaTrack(defaultAssCodecPrivate())
        var readOrder: Int64 = 0
        for (event in events) {
            if (event.durationMs <= 0 || event.text.size == 0) {
                continue
            }
            let chunk = "${readOrder},0,Default,,0,0,0,,${escapeAssText(event.text)}".toArray()
            track.addChunk(chunk, event.startMs, event.durationMs)
            readOrder++
        }
        track
    }

    public func render(nowMs: Int64, tracks: Array<AssTrack>): SubtitleBitmap {
        ensureOpen()
        let pointers = Array<NativeTrackPtr>(tracks.size, {index => tracks[index].pointer()})
        let result = unsafe {
            let handle = acquireArrayRawData(pointers)
            try {
                llass_render(native, handle.pointer, pointers.size, nowMs)
            } finally {
                releaseArrayRawData(handle)
            }
        }
        if (result.isNull()) {
            throw AssNativeException("native subtitle render allocation failed")
        }
        try {
            let value = unsafe { result.read() }
            throwBorrowedError(value.error)
            SubtitleBitmap(value)
        } finally {
            unsafe { llass_bitmap_free(result) }
        }
    }

    public func close(): Unit {
        for (track in ownedTracks) {
            track.close()
        }
        ownedTracks.clear()
        if (!native.isNull()) {
            unsafe { llass_renderer_free(native) }
            native = NativeRendererPtr()
        }
    }

    public func isClosed(): Bool {
        native.isNull()
    }

    private func ensureOpen(): Unit {
        if (native.isNull()) {
            throw AssNativeException("ASS renderer is closed")
        }
    }
}

public class PlainSubtitleEvent {
    public let startMs: Int64
    public let durationMs: Int64
    public let text: String

    public init(startMs: Int64, durationMs: Int64, text: String) {
        this.startMs = startMs
        this.durationMs = durationMs
        this.text = text
    }
}

public func libassVersions(): (UInt32, UInt32) {
    unsafe { (llass_runtime_version(), llass_compiled_version()) }
}

public func ensureCompatibleLibassRuntime(): Unit {
    let (runtime, compiled) = libassVersions()
    if ((runtime >> 24) != (compiled >> 24)) {
        throw AssNativeException("incompatible libass runtime ${runtime}; compiled ${compiled}")
    }
}

public func escapeAssText(value: String): String {
    value
        .replace("\\", "\\\\")
        .replace("{", "\\{")
        .replace("}", "\\}")
        .replace("\r\n", "\\N")
        .replace("\r", "\\N")
        .replace("\n", "\\N")
        .replace("<b>", "{\\b1}")
        .replace("</b>", "{\\b0}")
        .replace("<i>", "{\\i1}")
        .replace("</i>", "{\\i0}")
        .replace("<u>", "{\\u1}")
        .replace("</u>", "{\\u0}")
}

private func defaultAssCodecPrivate(): Array<UInt8> {
    ("[Script Info]\nScriptType: v4.00+\nPlayResX: 1920\nPlayResY: 1080\nWrapStyle: 0\n" +
        "ScaledBorderAndShadow: yes\nYCbCr Matrix: None\n\n[V4+ Styles]\n" +
        "Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, " +
        "BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, " +
        "BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding\n" +
        "Style: Default,sans-serif,54,&H00FFFFFF,&H000000FF,&H00101010,&H80000000," +
        "0,0,0,0,100,100,0,0,1,2,1,2,60,60,48,1\n\n[Events]\n" +
        "Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text\n").toArray()
}

private func throwOwnedError(error: CPointer<UInt8>, fallback: String): Nothing {
    if (error.isNull()) {
        throw AssNativeException(fallback)
    }
    let message = CString(error).toString()
    unsafe { llass_error_free(error) }
    throw AssNativeException(message)
}

private func throwBorrowedError(error: CPointer<UInt8>): Unit {
    if (!error.isNull()) {
        throw AssNativeException(CString(error).toString())
    }
}
