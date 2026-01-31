package webp_ffi

/**
 * Minimal libwebp decode bindings.
 *
 * Reference: /usr/include/webp/decode.h
 *            /usr/include/webp/demux.h (animation decoder)
 */

foreign func WebPGetInfo(data: CString, data_size: UIntNative, width: CPointer<Int32>, height: CPointer<Int32>): Int32

foreign func WebPDecodeRGBA(data: CString, data_size: UIntNative, width: CPointer<Int32>, height: CPointer<Int32>): CPointer<UInt8>

foreign func WebPFree(ptr: CPointer<Unit>): Unit

// ---- Animated WebP decode (WebPAnimDecoder*) ----
// We only bind the minimal surface needed to decode the first frame as RGBA.

// From /usr/include/webp/demux.h
public const WEBP_DEMUX_ABI_VERSION: Int32 = 0x0107

@C
public struct WebPAnimDecoder {
    init() {
        throw Exception("type should not be inited")
    }
}

@C
public struct WebPData {
    public let bytes: CPointer<UInt8>
    public let size: UIntNative

    public init(bytes: CPointer<UInt8>, size: UIntNative) {
        this.bytes = bytes
        this.size = size
    }
}

@C
public struct WebPAnimInfo {
    public let canvas_width: UInt32
    public let canvas_height: UInt32
    public let loop_count: UInt32
    public let bgcolor: UInt32
    public let frame_count: UInt32
    public let pad: VArray<UInt32, $4>

    public init(canvas_width: UInt32, canvas_height: UInt32, loop_count: UInt32, bgcolor: UInt32, frame_count: UInt32, pad: VArray<UInt32, $4>) {
        this.canvas_width = canvas_width
        this.canvas_height = canvas_height
        this.loop_count = loop_count
        this.bgcolor = bgcolor
        this.frame_count = frame_count
        this.pad = pad
    }
}

// demux.h exposes WebPAnimDecoderNew() as a static inline wrapper, so the
// exported symbol is the version-checked internal entry point.
foreign func WebPAnimDecoderNewInternal(data: CPointer<WebPData>, options: CPointer<Unit>, abi_version: Int32): CPointer<WebPAnimDecoder>

foreign func WebPAnimDecoderGetInfo(dec: CPointer<WebPAnimDecoder>, info: CPointer<WebPAnimInfo>): Int32

foreign func WebPAnimDecoderGetNext(dec: CPointer<WebPAnimDecoder>, buf: CPointer<CPointer<UInt8>>, timestamp: CPointer<Int32>): Int32

foreign func WebPAnimDecoderDelete(dec: CPointer<WebPAnimDecoder>): Unit
