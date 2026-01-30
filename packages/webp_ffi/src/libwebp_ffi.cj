package webp_ffi

/**
 * Minimal libwebp decode bindings.
 *
 * Reference: /usr/include/webp/decode.h
 */

foreign func WebPGetInfo(data: CString, data_size: UIntNative, width: CPointer<Int32>, height: CPointer<Int32>): Int32

foreign func WebPDecodeRGBA(data: CString, data_size: UIntNative, width: CPointer<Int32>, height: CPointer<Int32>): CPointer<UInt8>

foreign func WebPFree(ptr: CPointer<Unit>): Unit

