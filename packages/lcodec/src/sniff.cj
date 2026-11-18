package lcodec

import std.fs.{File, OpenMode, Path}
import std.fs.exists

/*
 * 魔数嗅探（诊断口，跨平台纯仓颉）。
 *
 * 背景：解码链路的错误串在不同后端质量不一（系统 ImageSource 只给错误码，桌面
 * libvips 的 error buffer 视构建而定）。格式不被支持时 UI 只能看到 "error" 占位，
 * 无法区分"下载坏了"与"该格式落在不支持的后端链路"。sniffImageFormat 只读
 * 文件头若干字节，按魔数判定容器格式，供解码异常信息与自检输出使用。
 *
 * 判定表（与后端能力对照）：
 *   png/jpeg/webp/gif/bmp/psd  → shim 的 stb_image 可解（桌面 libvips 同样可解）
 *   avif/heic/heif             → OHOS 走系统 ImageSource（API 26+，能力依赖设备）；
 *                                桌面 libvips 视编译选项（libheif/libavif 载荷）
 *   未知/过短/不可读            → Unknown，随异常抛出便于定位坏缓存
 */
public enum SniffedImageFormat <: Equatable<SniffedImageFormat> {
    | Png | Jpeg | Webp | Gif | Bmp | Psd | Tga | Pnm | Avif | Heic | Heif | Unknown

    // 诊断短名（异常信息/自检日志用）；也作为 == 的比较键。
    public func toString(): String {
        match (this) {
            case Png => "png"
            case Jpeg => "jpeg"
            case Webp => "webp"
            case Gif => "gif"
            case Bmp => "bmp"
            case Psd => "psd"
            case Tga => "tga"
            case Pnm => "pnm"
            case Avif => "avif"
            case Heic => "heic"
            case Heif => "heif"
            case Unknown => "unknown"
        }
    }

    // 无载荷枚举也需显式实现 Equatable（参照 lwindow.LWindowEventType / qwest.Method）。
    public operator func ==(that: SniffedImageFormat): Bool {
        this.toString() == that.toString()
    }

    public operator func !=(that: SniffedImageFormat): Bool {
        !(this == that)
    }
}

// 读文件头 n 字节；失败（不存在/不可读/过短）返回空数组。
private func readHead(path: String, n: Int64): Array<UInt8> {
    try {
        if (!exists(Path(path))) {
            return Array<UInt8>(0, repeat: 0u8)
        }
        let f = File(Path(path), OpenMode.Read)
        try {
            let buf = Array<UInt8>(n, repeat: 0u8)
            let got = f.read(buf)
            if (got <= 0) {
                return Array<UInt8>(0, repeat: 0u8)
            }
            if (got == n) {
                return buf
            }
            return buf[0..got].toArray()
        } finally {
            f.close()
        }
    } catch (_: Exception) {
        return Array<UInt8>(0, repeat: 0u8)
    }
}

// AVIF/HEIC 系：ISOBMFF 容器，ftyp box 在偏移 4；major brand（8..12）决定具体格式。
private func sniffIsobmff(head: Array<UInt8>): ?SniffedImageFormat {
    if (head.size < 12) {
        return None
    }
    if (!(head[4] == 0x66u8 && head[5] == 0x74u8 && head[6] == 0x79u8 && head[7] == 0x70u8)) {
        return None
    }
    func brandIs(a: UInt8, b: UInt8, c: UInt8, d: UInt8): Bool {
        head[8] == a && head[9] == b && head[10] == c && head[11] == d
    }
    if (brandIs(0x61u8, 0x76u8, 0x69u8, 0x66u8) || brandIs(0x61u8, 0x76u8, 0x69u8, 0x73u8)) {
        return Some(Avif) // "avif" / "avis"
    }
    if (brandIs(0x68u8, 0x65u8, 0x69u8, 0x63u8) || brandIs(0x6Du8, 0x69u8, 0x66u8, 0x31u8)) {
        return Some(Heic) // "heic" / "mif1"
    }
    if (brandIs(0x68u8, 0x65u8, 0x69u8, 0x66u8) || brandIs(0x6Du8, 0x73u8, 0x66u8, 0x31u8)) {
        return Some(Heif) // "heif" / "msf1"
    }
    return Some(Unknown)
}

// 魔数嗅探公开入口：读文件头 ≤32 字节判定容器格式。纯仓颉、无 FFI。
public func sniffImageFormat(path: String): SniffedImageFormat {
    sniffHead(readHead(path, 32))
}

// 内存字节版嗅探（解码入口不再只有文件路径；异常信息同样要能报出格式）。
public func sniffImageFormatBytes(bytes: Array<UInt8>): SniffedImageFormat {
    sniffHead(if (bytes.size > 32) { bytes[0..32].toArray() } else { bytes })
}

// 嗅探核心：head 至少是文件开头若干字节（不足按 Unknown 处理）。
private func sniffHead(head: Array<UInt8>): SniffedImageFormat {
    if (head.size >= 8 && head[0] == 0x89u8 && head[1] == 0x50u8 && head[2] == 0x4Eu8 &&
        head[3] == 0x47u8 && head[4] == 0x0Du8 && head[5] == 0x0Au8 && head[6] == 0x1Au8 &&
        head[7] == 0x0Au8) {
        return Png
    }
    if (head.size < 12) {
        return Unknown
    }
    if (head[0] == 0xFFu8 && head[1] == 0xD8u8 && head[2] == 0xFFu8) {
        return Jpeg
    }
    if (head[0] == 0x52u8 && head[1] == 0x49u8 && head[2] == 0x46u8 && head[3] == 0x46u8 &&
        head[8] == 0x57u8 && head[9] == 0x45u8 && head[10] == 0x42u8 && head[11] == 0x50u8) {
        return Webp
    }
    match (sniffIsobmff(head)) {
        case Some(f) => return f
        case None => ()
    }
    if (head[0] == 0x47u8 && head[1] == 0x49u8 && head[2] == 0x46u8 && head[3] == 0x38u8) {
        return Gif
    }
    if (head[0] == 0x42u8 && head[1] == 0x4Du8) {
        return Bmp
    }
    if (head[0] == 0x38u8 && head[1] == 0x42u8 && head[2] == 0x50u8 && head[3] == 0x53u8) {
        return Psd
    }
    return Unknown
}

// 嗅探结果转诊断短名（异常信息用；等价于 toString，保留独立入口便于全仓 grep）。
public func sniffedImageFormatName(f: SniffedImageFormat): String {
    f.toString()
}
