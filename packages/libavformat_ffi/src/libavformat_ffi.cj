package libavformat_ffi

import std.collection.ArrayList
import std.binary.*
import std.overflow.*

@C
struct NativeCancel {
    init() {
        throw Exception("opaque subtitle cancellation token")
    }
}

@C
struct NativeStreamInfo {
    var streamIndex: Int32 = 0
    var codecId: Int32 = 0
    var codecName = CPointer<UInt8>()
    var title = CPointer<UInt8>()
    var language = CPointer<UInt8>()
    var isDefault: Int32 = 0
    var isForced: Int32 = 0
    var isText: Int32 = 0
    var supported: Int32 = 0
    var unsupportedReason = CPointer<UInt8>()
}

@C
struct NativeProbeResult {
    var items = CPointer<NativeStreamInfo>()
    var count: Int64 = 0
    var error = CPointer<UInt8>()
}

@C
struct NativeEvent {
    var startMs: Int64 = 0
    var durationMs: Int64 = 0
    var payloadKind: Int32 = 0
    var payload = CPointer<UInt8>()
    var payloadSize: Int64 = 0
}

@C
struct NativeTrack {
    var streamIndex: Int32 = 0
    var codecName = CPointer<UInt8>()
    var codecPrivate = CPointer<UInt8>()
    var codecPrivateSize: Int64 = 0
    var events = CPointer<NativeEvent>()
    var eventCount: Int64 = 0
}

@C
struct NativeExtractResult {
    var tracks = CPointer<NativeTrack>()
    var trackCount: Int64 = 0
    var error = CPointer<UInt8>()
    var cancelled: Int32 = 0
}

type NativeCancelPtr = CPointer<NativeCancel>

foreign func llav_libavformat_version(): UInt32

foreign func llav_libavcodec_version(): UInt32

foreign func llav_compiled_libavformat_version(): UInt32

foreign func llav_compiled_libavcodec_version(): UInt32

foreign func llav_cancel_new(): NativeCancelPtr

foreign func llav_cancel_request(cancel: NativeCancelPtr): Unit

foreign func llav_cancel_free(cancel: NativeCancelPtr): Unit

foreign func llav_probe_subtitle_streams(url: CString, bearer: CString, cancel: NativeCancelPtr): CPointer<NativeProbeResult>

foreign func llav_probe_result_free(result: CPointer<NativeProbeResult>): Unit

foreign func llav_extract_subtitle_tracks(url: CString, bearer: CString, cancel: NativeCancelPtr): CPointer<NativeExtractResult>

foreign func llav_extract_result_free(result: CPointer<NativeExtractResult>): Unit

private let MAX_MANAGED_STREAMS: Int64 = 4096
private let MAX_MANAGED_TRACKS: Int64 = 4096
private let MAX_MANAGED_EVENTS: Int64 = 2000000
private let MAX_MANAGED_PAYLOAD: Int64 = 16 * 1024 * 1024

/** A subtitle operation failed at the native FFmpeg boundary. */
public class SubtitleNativeException <: Exception {
    public init(message: String) {
        super(message)
    }
}

/** Stable metadata for a container subtitle stream. */
public class SubtitleStreamInfo {
    public let streamIndex: Int32
    public let codecId: Int32
    public let codecName: String
    public let title: String
    public let language: String
    public let isDefault: Bool
    public let isForced: Bool
    public let isText: Bool
    public let supported: Bool
    public let unsupportedReason: String

    init(native: NativeStreamInfo) {
        streamIndex = native.streamIndex
        codecId = native.codecId
        codecName = nativeString(native.codecName)
        title = nativeString(native.title)
        language = nativeString(native.language)
        isDefault = native.isDefault != 0
        isForced = native.isForced != 0
        isText = native.isText != 0
        supported = native.supported != 0
        unsupportedReason = nativeString(native.unsupportedReason)
    }

    /** Managed constructor for model tests and offline UI fixtures. */
    public init(streamIndex: Int32, codecId: Int32, codecName: String, title: String, language: String, isDefault: Bool,
        isForced: Bool, isText: Bool, supported: Bool, unsupportedReason: String) {
        this.streamIndex = streamIndex
        this.codecId = codecId
        this.codecName = codecName
        this.title = title
        this.language = language
        this.isDefault = isDefault
        this.isForced = isForced
        this.isText = isText
        this.supported = supported
        this.unsupportedReason = unsupportedReason
    }
}

/** Native subtitle packet representation understood by libass_ffi. */
public enum SubtitlePayloadKind {
    | MatroskaAssChunk
    | PlainText
}

/** A managed subtitle event; no FFmpeg pointer escapes the extraction call. */
public class SubtitleEvent {
    public let startMs: Int64
    public let durationMs: Int64
    public let payloadKind: SubtitlePayloadKind
    public let payload: Array<UInt8>

    init(native: NativeEvent) {
        startMs = native.startMs
        durationMs = native.durationMs
        payloadKind = match (native.payloadKind) {
            case 1 => SubtitlePayloadKind.MatroskaAssChunk
            case 2 => SubtitlePayloadKind.PlainText
            case value => throw SubtitleNativeException("unknown native subtitle payload kind ${value}")
        }
        payload = copyNativeBytes(native.payload, native.payloadSize)
    }

    public init(startMs: Int64, durationMs: Int64, payloadKind: SubtitlePayloadKind, payload: Array<UInt8>) {
        if (startMs < 0 || durationMs < 0 || payload.size > MAX_MANAGED_PAYLOAD) {
            throw SubtitleNativeException("invalid cached subtitle event")
        }
        this.startMs = startMs
        this.durationMs = durationMs
        this.payloadKind = payloadKind
        this.payload = payload.clone()
    }
}

/** A complete extracted text track, including Matroska ASS CodecPrivate when present. */
public class ExtractedSubtitleTrack {
    public let streamIndex: Int32
    public let codecName: String
    public let codecPrivate: Array<UInt8>
    public let events: ArrayList<SubtitleEvent>

    init(native: NativeTrack) {
        validateCount(native.eventCount, MAX_MANAGED_EVENTS, "subtitle event")
        streamIndex = native.streamIndex
        codecName = nativeString(native.codecName)
        codecPrivate = copyNativeBytes(native.codecPrivate, native.codecPrivateSize)
        events = ArrayList<SubtitleEvent>()
        for (index in 0..native.eventCount) {
            events.add(SubtitleEvent(unsafe { native.events.read(index) }))
        }
    }

    public init(streamIndex: Int32, codecName: String, codecPrivate: Array<UInt8>, events: ArrayList<SubtitleEvent>) {
        if (codecName.toArray().size > 1024 || codecPrivate.size > MAX_MANAGED_PAYLOAD || events.size >
            MAX_MANAGED_EVENTS) {
            throw SubtitleNativeException("invalid cached subtitle track")
        }
        this.streamIndex = streamIndex
        this.codecName = codecName
        this.codecPrivate = codecPrivate.clone()
        this.events = events
    }
}

private let CACHE_MAGIC = "LLSUB\u{0}\u{1}".toArray()
private let CACHE_MAX_BYTES: Int64 = 512 * 1024 * 1024

/** Stable, length-prefixed cache encoding. The trailing FNV-1a checksum covers every prior byte. */
public func encodeSubtitleTracks(tracks: ArrayList<ExtractedSubtitleTrack>): Array<UInt8> {
    validateCount(tracks.size, MAX_MANAGED_TRACKS, "cached subtitle track")
    let out = ArrayList<UInt8>()
    appendBytes(out, CACHE_MAGIC)
    appendU32(out, UInt32(tracks.size))
    for (track in tracks) {
        appendI32(out, track.streamIndex)
        appendSizedBytes(out, track.codecName.toArray())
        appendSizedBytes(out, track.codecPrivate)
        validateCount(track.events.size, MAX_MANAGED_EVENTS, "cached subtitle event")
        appendU32(out, UInt32(track.events.size))
        for (event in track.events) {
            appendI64(out, event.startMs)
            appendI64(out, event.durationMs)
            out.add(match (event.payloadKind) {
                case SubtitlePayloadKind.MatroskaAssChunk => 1u8
                case SubtitlePayloadKind.PlainText => 2u8
            })
            appendSizedBytes(out, event.payload)
            if (out.size > CACHE_MAX_BYTES) {
                throw SubtitleNativeException("subtitle cache exceeds ${CACHE_MAX_BYTES} bytes")
            }
        }
    }
    let body = out.toArray()
    appendU64(out, fnv1a64(body))
    out.toArray()
}

/** Decode and fully validate a subtitle cache entry before publishing managed tracks. */
public func decodeSubtitleTracks(bytes: Array<UInt8>): ArrayList<ExtractedSubtitleTrack> {
    if (bytes.size < CACHE_MAGIC.size + 4 + 8 || bytes.size > CACHE_MAX_BYTES) {
        throw SubtitleNativeException("invalid subtitle cache size ${bytes.size}")
    }
    let bodyEnd = bytes.size - 8
    let expected = UInt64.readBigEndian(bytes[bodyEnd..])
    if (fnv1a64(bytes[..bodyEnd]) != expected) {
        throw SubtitleNativeException("subtitle cache checksum mismatch")
    }
    let reader = CacheReader(bytes, bodyEnd)
    if (reader.readBytes(CACHE_MAGIC.size) != CACHE_MAGIC) {
        throw SubtitleNativeException("subtitle cache magic/schema mismatch")
    }
    let trackCount = Int64(reader.readU32())
    validateCount(trackCount, MAX_MANAGED_TRACKS, "cached subtitle track")
    let tracks = ArrayList<ExtractedSubtitleTrack>()
    for (_ in 0..trackCount) {
        let streamIndex = reader.readI32()
        let codecBytes = reader.readSizedBytes(1024)
        let codecName = try {
            String.fromUtf8(codecBytes)
        } catch (_: Exception) {
            throw SubtitleNativeException("subtitle cache codec is not UTF-8")
        }
        let codecPrivate = reader.readSizedBytes(MAX_MANAGED_PAYLOAD)
        let eventCount = Int64(reader.readU32())
        validateCount(eventCount, MAX_MANAGED_EVENTS, "cached subtitle event")
        let events = ArrayList<SubtitleEvent>()
        for (_ in 0..eventCount) {
            let startMs = reader.readI64()
            let durationMs = reader.readI64()
            let kind = match (reader.readByte()) {
                case 1 => SubtitlePayloadKind.MatroskaAssChunk
                case 2 => SubtitlePayloadKind.PlainText
                case value => throw SubtitleNativeException("unknown cached payload kind ${value}")
            }
            events.add(SubtitleEvent(startMs, durationMs, kind, reader.readSizedBytes(MAX_MANAGED_PAYLOAD)))
        }
        tracks.add(ExtractedSubtitleTrack(streamIndex, codecName, codecPrivate, events))
    }
    if (reader.position != bodyEnd) {
        throw SubtitleNativeException("subtitle cache contains trailing data")
    }
    tracks
}

private class CacheReader {
    private let bytes: Array<UInt8>
    private let end: Int64
    public var position: Int64 = 0

    init(bytes: Array<UInt8>, end: Int64) {
        this.bytes = bytes
        this.end = end
    }

    func readByte(): UInt8 {
        require(1)
        let value = bytes[position]
        position++
        value
    }

    func readI32(): Int32 {
        Int32.readBigEndian(readBytes(4))
    }
    func readU32(): UInt32 {
        UInt32.readBigEndian(readBytes(4))
    }
    func readI64(): Int64 {
        Int64.readBigEndian(readBytes(8))
    }

    func readSizedBytes(maximum: Int64): Array<UInt8> {
        let size = Int64(readU32())
        if (size > maximum) {
            throw SubtitleNativeException("subtitle cache field is too large")
        }
        readBytes(size)
    }

    func readBytes(size: Int64): Array<UInt8> {
        require(size)
        let result = bytes[position..position + size]
        position += size
        result
    }

    private func require(size: Int64): Unit {
        if (size < 0 || position > end - size) {
            throw SubtitleNativeException("truncated subtitle cache")
        }
    }
}

private func appendBytes(out: ArrayList<UInt8>, bytes: Array<UInt8>): Unit {
    for (value in bytes) {
        out.add(value)
    }
}

private func appendI32(out: ArrayList<UInt8>, value: Int32): Unit {
    let bytes = Array<UInt8>(4, repeat: 0u8)
    let _ = value.writeBigEndian(bytes)
    appendBytes(out, bytes)
}

private func appendU32(out: ArrayList<UInt8>, value: UInt32): Unit {
    let bytes = Array<UInt8>(4, repeat: 0u8)
    let _ = value.writeBigEndian(bytes)
    appendBytes(out, bytes)
}

private func appendI64(out: ArrayList<UInt8>, value: Int64): Unit {
    let bytes = Array<UInt8>(8, repeat: 0u8)
    let _ = value.writeBigEndian(bytes)
    appendBytes(out, bytes)
}

private func appendU64(out: ArrayList<UInt8>, value: UInt64): Unit {
    let bytes = Array<UInt8>(8, repeat: 0u8)
    let _ = value.writeBigEndian(bytes)
    appendBytes(out, bytes)
}

private func appendSizedBytes(out: ArrayList<UInt8>, bytes: Array<UInt8>): Unit {
    if (bytes.size > Int64(UInt32.Max)) {
        throw SubtitleNativeException("subtitle cache field is too large")
    }
    appendU32(out, UInt32(bytes.size))
    appendBytes(out, bytes)
}

private func fnv1a64(bytes: Array<UInt8>): UInt64 {
    var hash: UInt64 = 0xcbf29ce484222325
    for (value in bytes) {
        hash = (hash ^ UInt64(value)).wrappingMul(0x100000001b3)
    }
    hash
}

/** Cooperative cancellation token observed by FFmpeg's interrupt callback. */
public class SubtitleCancelToken <: Resource {
    private var native = unsafe { llav_cancel_new() }

    public init() {
        if (native.isNull()) {
            throw SubtitleNativeException("failed to allocate subtitle cancellation token")
        }
    }

    public func cancel(): Unit {
        if (!native.isNull()) {
            unsafe { llav_cancel_request(native) }
        }
    }

    public func close(): Unit {
        if (!native.isNull()) {
            unsafe { llav_cancel_free(native) }
            native = NativeCancelPtr()
        }
    }

    public func isClosed(): Bool {
        native.isNull()
    }

    internal func pointer(): NativeCancelPtr {
        native
    }
}

/** Runtime and compile-time FFmpeg versions encoded as MAJOR.MINOR.MICRO. */
public func libavVersions(): (UInt32, UInt32, UInt32, UInt32) {
    unsafe {
        (llav_libavformat_version(), llav_libavcodec_version(), llav_compiled_libavformat_version(),
            llav_compiled_libavcodec_version())
    }
}

/** Reject an incompatible runtime before any FFmpeg-owned object crosses the bridge. */
public func ensureCompatibleLibavRuntime(): Unit {
    let (formatRuntime, codecRuntime, formatCompiled, codecCompiled) = libavVersions()
    if ((formatRuntime >> 16) != (formatCompiled >> 16) || (codecRuntime >> 16) != (codecCompiled >> 16)) {
        throw SubtitleNativeException(
            "incompatible FFmpeg runtime: libavformat=${formatRuntime}, libavcodec=${codecRuntime}, " +
                "compiled=${formatCompiled}/${codecCompiled}")
    }
}

/** Probe subtitle streams synchronously. Call from a worker, never from the UI thread. */
public func probeSubtitleStreams(url: String, bearer!: String = "", cancel!: ?SubtitleCancelToken = None): ArrayList<SubtitleStreamInfo> {
    ensureCompatibleLibavRuntime()
    withSource(
        url,
        bearer,
        {
            nativeUrl, nativeBearer =>
                let result = unsafe { llav_probe_subtitle_streams(nativeUrl, nativeBearer, cancelPointer(cancel)) }
                if (result.isNull()) {
                    throw SubtitleNativeException("native subtitle probe allocation failed")
                }
                try {
                    let value = unsafe { result.read() }
                    throwNativeError(value.error)
                    validateCount(value.count, MAX_MANAGED_STREAMS, "subtitle stream")
                    let streams = ArrayList<SubtitleStreamInfo>()
                    for (index in 0..value.count) {
                        streams.add(SubtitleStreamInfo(unsafe { value.items.read(index) }))
                    }
                    streams
                } finally {
                    unsafe { llav_probe_result_free(result) }
                }
        }
    )
}

/** Extract every supported text subtitle stream in one sequential scan. */
public func extractSubtitleTracks(url: String, bearer!: String = "", cancel!: ?SubtitleCancelToken = None): ArrayList<ExtractedSubtitleTrack> {
    ensureCompatibleLibavRuntime()
    withSource(
        url,
        bearer,
        {
            nativeUrl, nativeBearer =>
                let result = unsafe { llav_extract_subtitle_tracks(nativeUrl, nativeBearer, cancelPointer(cancel)) }
                if (result.isNull()) {
                    throw SubtitleNativeException("native subtitle extraction allocation failed")
                }
                try {
                    let value = unsafe { result.read() }
                    if (value.cancelled != 0) {
                        throw SubtitleNativeException("subtitle extraction cancelled")
                    }
                    throwNativeError(value.error)
                    validateCount(value.trackCount, MAX_MANAGED_TRACKS, "extracted subtitle track")
                    let tracks = ArrayList<ExtractedSubtitleTrack>()
                    for (index in 0..value.trackCount) {
                        tracks.add(ExtractedSubtitleTrack(unsafe { value.tracks.read(index) }))
                    }
                    tracks
                } finally {
                    unsafe { llav_extract_result_free(result) }
                }
        }
    )
}

private func cancelPointer(cancel: ?SubtitleCancelToken): NativeCancelPtr {
    match (cancel) {
        case Some(token) => token.pointer()
        case None => NativeCancelPtr()
    }
}

private func withSource<T>(url: String, bearer: String, action: (CString, CString) -> T): T {
    if (url.size == 0) {
        throw SubtitleNativeException("subtitle media URL must not be empty")
    }
    let nativeUrl = unsafe { LibC.mallocCString(url) }
    if (nativeUrl.isNull()) {
        throw SubtitleNativeException("failed to allocate subtitle media URL")
    }
    let nativeBearer = unsafe { LibC.mallocCString(bearer) }
    if (nativeBearer.isNull()) {
        unsafe { LibC.free(nativeUrl) }
        throw SubtitleNativeException("failed to allocate subtitle bearer token")
    }
    try {
        action(nativeUrl, nativeBearer)
    } finally {
        unsafe { LibC.free(nativeUrl) }
        unsafe { LibC.free(nativeBearer) }
    }
}

private func nativeString(pointer: CPointer<UInt8>): String {
    if (pointer.isNull()) {
        return ""
    }
    CString(pointer).toString()
}

private func throwNativeError(pointer: CPointer<UInt8>): Unit {
    if (!pointer.isNull()) {
        throw SubtitleNativeException(CString(pointer).toString())
    }
}

private func validateCount(value: Int64, maximum: Int64, label: String): Unit {
    if (value < 0 || value > maximum) {
        throw SubtitleNativeException("invalid ${label} count ${value}")
    }
}

private func copyNativeBytes(pointer: CPointer<UInt8>, size: Int64): Array<UInt8> {
    if (size == 0) {
        return Array<UInt8>()
    }
    if (size < 0 || size > MAX_MANAGED_PAYLOAD || pointer.isNull()) {
        throw SubtitleNativeException("invalid native subtitle payload size ${size}")
    }
    let bytes = Array<UInt8>(size, repeat: 0u8)
    for (index in 0..size) {
        bytes[index] = unsafe { pointer.read(index) }
    }
    bytes
}
