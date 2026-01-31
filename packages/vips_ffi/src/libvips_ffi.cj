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

// Auto-rotate using image metadata (EXIF orientation, etc).
foreign func vips_autorot(_in: VipsImagePtr, out: CPointer<VipsImagePtr>, ...): Int32

// Resize by a scale factor.
foreign func vips_resize(_in: VipsImagePtr, out: CPointer<VipsImagePtr>, scale: Float64, ...): Int32

// Crop/extract.
foreign func vips_extract_area(_in: VipsImagePtr, out: CPointer<VipsImagePtr>, left: Int32, top: Int32, width: Int32, height: Int32, ...): Int32

// Save image to file; writer chosen by filename extension (.avif, .png, ...).
foreign func vips_image_write_to_file(image: VipsImagePtr, filename: CString, ...): Int32

// libvips objects are GObjects; unref to release.
foreign func g_object_unref(obj: CPointer<Unit>): Unit

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

    public static func autorot(_in: VipsImagePtr, out: CPointer<VipsImagePtr>): Int32 {
        return unsafe { vips_autorot(_in, out, CPointer<Unit>()) }
    }

    public static func resize(_in: VipsImagePtr, out: CPointer<VipsImagePtr>, scale: Float64): Int32 {
        return unsafe { vips_resize(_in, out, scale, CPointer<Unit>()) }
    }

    public static func extractArea(_in: VipsImagePtr, out: CPointer<VipsImagePtr>, left: Int32, top: Int32, width: Int32, height: Int32): Int32 {
        return unsafe { vips_extract_area(_in, out, left, top, width, height, CPointer<Unit>()) }
    }

    public static func writeToFile(image: VipsImagePtr, filename: CString): Int32 {
        return unsafe { vips_image_write_to_file(image, filename, CPointer<Unit>()) }
    }

    public static func unref(image: VipsImagePtr): Unit {
        if (!image.isNull()) {
            unsafe { g_object_unref(CPointer<Unit>(image)) }
        }
    }
}
