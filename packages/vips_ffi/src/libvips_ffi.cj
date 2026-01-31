// Minimal libvips bindings.
// Keep this small and focused on the operations we need (load/autorot/resize/crop/save).

package vips_ffi

@C
public struct VipsImage {
    init() {
        throw Exception("type should not be inited")
    }
}

public type VipsImagePtr = CPointer<VipsImage>

foreign func vips_init(argv0: CString): Int32
foreign func vips_shutdown(): Unit

foreign func vips_error_buffer(): CString
foreign func vips_error_clear(): Unit

// Load image from file. Options are passed as a NULL-terminated varargs list.
foreign func vips_image_new_from_file(filename: CString, ...): VipsImagePtr

foreign func vips_image_get_width(image: VipsImagePtr): Int32
foreign func vips_image_get_height(image: VipsImagePtr): Int32
foreign func vips_image_get_bands(image: VipsImagePtr): Int32

// Auto-rotate using image metadata (EXIF orientation, etc).
foreign func vips_autorot(_in: VipsImagePtr, out: CPointer<VipsImagePtr>, ...): Int32

// Resize by a scale factor.
foreign func vips_resize(_in: VipsImagePtr, out: CPointer<VipsImagePtr>, scale: Float64, ...): Int32

// Crop/extract.
foreign func vips_extract_area(_in: VipsImagePtr, out: CPointer<VipsImagePtr>, left: Int32, top: Int32, width: Int32, height: Int32, ...): Int32

// Colorspace conversion (we use sRGB for a stable pixel space).
public const VIPS_INTERPRETATION_sRGB: Int32 = 22
foreign func vips_colourspace(_in: VipsImagePtr, out: CPointer<VipsImagePtr>, space: Int32, ...): Int32

// Cast to 8-bit unsigned.
foreign func vips_cast_uchar(_in: VipsImagePtr, out: CPointer<VipsImagePtr>, ...): Int32

// Join constant bands (used to add alpha=255).
foreign func vips_bandjoin_const1(_in: VipsImagePtr, out: CPointer<VipsImagePtr>, c: Float64, ...): Int32

// Join bands from multiple images (used to expand GREY -> RGB by replication).
foreign func vips_bandjoin(_in: CPointer<VipsImagePtr>, out: CPointer<VipsImagePtr>, n: Int32, ...): Int32

// Save image to file; writer chosen by filename extension (.avif, .png, ...).
foreign func vips_image_write_to_file(image: VipsImagePtr, filename: CString, ...): Int32

// Write pixels to memory (caller frees with g_free).
foreign func vips_image_write_to_memory(image: VipsImagePtr, size: CPointer<UIntNative>): CPointer<Unit>

// libvips objects are GObjects; unref to release.
foreign func g_object_unref(obj: CPointer<Unit>): Unit
foreign func g_free(mem: CPointer<Unit>): Unit

/**
 * Public wrapper API.
 *
 * Cangjie currently disallows exporting `foreign func` directly across packages,
 * so we expose a tiny wrapper surface as regular `public` functions.
 */
public class VipsApi {
    public static func initialize(argv0: CString): Int32 {
        return unsafe { vips_init(argv0) }
    }

    public static func shutdown(): Unit {
        unsafe { vips_shutdown() }
    }

    public static func takeErrorString(): String {
        var s = ""
        try {
            let p = unsafe { vips_error_buffer() }
            if (!p.isNull()) {
                s = unsafe { p.toString() }
            }
            unsafe { vips_error_clear() }
        } catch (_: Exception) {}
        return s
    }

    public static func imageNewFromFile(filename: CString): VipsImagePtr {
        return unsafe { vips_image_new_from_file(filename, CPointer<Unit>()) }
    }

    public static func imageWidth(image: VipsImagePtr): Int32 {
        return unsafe { vips_image_get_width(image) }
    }

    public static func imageHeight(image: VipsImagePtr): Int32 {
        return unsafe { vips_image_get_height(image) }
    }

    public static func imageBands(image: VipsImagePtr): Int32 {
        return unsafe { vips_image_get_bands(image) }
    }

    public static func autorot(_in: VipsImagePtr, out: CPointer<VipsImagePtr>): Int32 {
        return unsafe { vips_autorot(_in, out, CPointer<Unit>()) }
    }

    public static func resize(_in: VipsImagePtr, out: CPointer<VipsImagePtr>, scale: Float64): Int32 {
        return unsafe { vips_resize(_in, out, scale, CPointer<Unit>()) }
    }

    public static func extractArea(_in: VipsImagePtr, out: CPointer<VipsImagePtr>, left: Int32, top: Int32, width: Int32, height: Int32): Int32 {
        return unsafe { vips_extract_area(_in, out, left, top, width, height, CPointer<Unit>()) }
    }

    public static func colourspaceSRgb(_in: VipsImagePtr, out: CPointer<VipsImagePtr>): Int32 {
        return unsafe { vips_colourspace(_in, out, VIPS_INTERPRETATION_sRGB, CPointer<Unit>()) }
    }

    public static func castUChar(_in: VipsImagePtr, out: CPointer<VipsImagePtr>): Int32 {
        return unsafe { vips_cast_uchar(_in, out, CPointer<Unit>()) }
    }

    public static func bandjoinConstAlpha255(_in: VipsImagePtr, out: CPointer<VipsImagePtr>): Int32 {
        return unsafe { vips_bandjoin_const1(_in, out, 255.0, CPointer<Unit>()) }
    }

    public static func bandjoin(images: CPointer<VipsImagePtr>, out: CPointer<VipsImagePtr>, n: Int32): Int32 {
        return unsafe { vips_bandjoin(images, out, n, CPointer<Unit>()) }
    }

    public static func writeToFile(image: VipsImagePtr, filename: CString): Int32 {
        return unsafe { vips_image_write_to_file(image, filename, CPointer<Unit>()) }
    }

    public static func writeToMemory(image: VipsImagePtr, outSize: CPointer<UIntNative>): CPointer<Unit> {
        return unsafe { vips_image_write_to_memory(image, outSize) }
    }

    public static func free(mem: CPointer<Unit>): Unit {
        if (!mem.isNull()) {
            unsafe { g_free(mem) }
        }
    }

    public static func unref(image: VipsImagePtr): Unit {
        if (!image.isNull()) {
            unsafe { g_object_unref(CPointer<Unit>(image)) }
        }
    }
}
