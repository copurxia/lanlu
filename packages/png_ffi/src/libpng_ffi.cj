// Minimal libpng (simplified API) bindings for decoding PNG from memory.
// Keep the surface small; we can extend as needed for encoding or more options.

package png_ffi

public const PNG_IMAGE_VERSION: UInt32 = 1u32

// Commonly used formats (see /usr/include/libpng16/png.h).
public const PNG_FORMAT_FLAG_ALPHA: UInt32 = 0x01u32
public const PNG_FORMAT_FLAG_COLOR: UInt32 = 0x02u32
public const PNG_FORMAT_FLAG_LINEAR: UInt32 = 0x04u32
public const PNG_FORMAT_FLAG_COLORMAP: UInt32 = 0x08u32
public const PNG_FORMAT_FLAG_ASSOCIATED_ALPHA: UInt32 = 0x40u32

public const PNG_FORMAT_RGB: UInt32 = PNG_FORMAT_FLAG_COLOR
public const PNG_FORMAT_RGBA: UInt32 = PNG_FORMAT_RGB | PNG_FORMAT_FLAG_ALPHA

public type png_controlp = CPointer<png_control>

@C
public struct png_control {
    init() {
        throw Exception("type should not be inited")
    }
}

@C
public struct png_color {
    public let red: UInt8
    public let green: UInt8
    public let blue: UInt8

    public init(red: UInt8, green: UInt8, blue: UInt8) {
        this.red = red
        this.green = green
        this.blue = blue
    }
}

public type png_const_colorp = CPointer<png_color>

@C
public struct png_image {
    public let opaque: png_controlp
    public let version: UInt32
    public let width: UInt32
    public let height: UInt32
    public let format: UInt32
    public let flags: UInt32
    public let colormap_entries: UInt32
    public let warning_or_error: UInt32
    public let message: VArray<UInt8, $64>

    public init(
        opaque: png_controlp,
        version: UInt32,
        width: UInt32,
        height: UInt32,
        format: UInt32,
        flags: UInt32,
        colormap_entries: UInt32,
        warning_or_error: UInt32,
        message: VArray<UInt8, $64>
    ) {
        this.opaque = opaque
        this.version = version
        this.width = width
        this.height = height
        this.format = format
        this.flags = flags
        this.colormap_entries = colormap_entries
        this.warning_or_error = warning_or_error
        this.message = message
    }
}

foreign func png_image_begin_read_from_memory(image: CPointer<png_image>, memory: CPointer<Unit>, size: UIntNative): Int32

foreign func png_image_finish_read(
    image: CPointer<png_image>,
    background: png_const_colorp,
    buffer: CPointer<Unit>,
    row_stride: Int32,
    colormap: CPointer<Unit>
): Int32

foreign func png_image_free(image: CPointer<png_image>): Unit

