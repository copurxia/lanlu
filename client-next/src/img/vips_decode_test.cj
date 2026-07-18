package lanlu_client_next.img

import std.fs.{remove, Directory, File, Path}
import stdx.encoding.base64.fromBase64String

// 1x1 PNG（与 image_cache_test 同一张标准测试图；private 顶层声明按文件隔离，不冲突）
private let PNG_1PX_B64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="

@Test
func decodePngToRgba(): Unit {
    let dir = Directory.createTemp(Path("."))
    let src = "${dir}/in.png"
    let bytes = fromBase64String(PNG_1PX_B64) ?? Array<UInt8>(0, repeat: 0)
    File.writeTo(Path(src), bytes)
    let d = decodeFileToRgba(src)
    @Expect(d.width, 1i32)
    @Expect(d.height, 1i32)
    // RGBA 四波段：像素长度必须 == width*height*4
    @Expect(d.pixels.size, Int64(d.width) * Int64(d.height) * 4)
    remove(dir, recursive: true)
}

@Test
func decodeBadBytesThrows(): Unit {
    let dir = Directory.createTemp(Path("."))
    let src = "${dir}/bad.img"
    // 只有 PNG magic 没有 IHDR 的截断文件：任何解码器都无法处理，必须抛异常。
    File.writeTo(Path(src), [0x89u8, 0x50u8, 0x4Eu8, 0x47u8, 0x0Du8, 0x0Au8, 0x1Au8, 0x0Au8])
    var threw = false
    try {
        let _ = decodeFileToRgba(src)
    } catch (_: Exception) {
        threw = true
    }
    @Expect(threw, true)
    remove(dir, recursive: true)
}
