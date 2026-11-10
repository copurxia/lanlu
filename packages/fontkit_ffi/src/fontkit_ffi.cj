package fontkit_ffi

import std.collection.ArrayList

foreign {
    func lanlu_font_list_create(): CPointer<Unit>
    func lanlu_font_list_count(list: CPointer<Unit>): UIntNative
    func lanlu_font_list_label(list: CPointer<Unit>, index: UIntNative): CString
    func lanlu_font_list_path(list: CPointer<Unit>, index: UIntNative): CString
    func lanlu_font_list_destroy(list: CPointer<Unit>): Unit
}

/** A system font family and the filesystem path of a representative face. */
public class SystemFont {
    public let family: String
    public let path: String

    public init(family: String, path: String) {
        this.family = family
        this.path = path
    }
}

/** Enumerates fonts through the platform source selected by font-kit. */
public func systemFonts(): ArrayList<SystemFont> {
    let fonts = ArrayList<SystemFont>()
    unsafe {
        let nativeList = lanlu_font_list_create()
        if (nativeList.isNull()) {
            return fonts
        }
        try {
            let count = lanlu_font_list_count(nativeList)
            for (index in 0..Int64(count)) {
                let family = lanlu_font_list_label(nativeList, UIntNative(index))
                let path = lanlu_font_list_path(nativeList, UIntNative(index))
                if (!family.isNull() && !path.isNull()) {
                    fonts.add(SystemFont(family.toString(), path.toString()))
                }
            }
        } finally {
            lanlu_font_list_destroy(nativeList)
        }
    }
    fonts
}

