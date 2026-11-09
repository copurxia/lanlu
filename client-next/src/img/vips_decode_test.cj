package lanlu_client_next.img

import std.fs.{remove, Directory, File, Path}
import stdx.encoding.base64.fromBase64String

// 1x1 PNG（与 image_cache_test 同一张标准测试图；private 顶层声明按文件隔离，不冲突）
private let PNG_1PX_B64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="

// 64x64 渐变 JPEG（PIL quality=90 生成）：用于 shrink-on-load 路径（#7）——磁盘缓存条目
// 是 .img 后缀，JPEG 判定靠内容魔数嗅探，本用例文件名即按缓存惯例取 .img。
private let JPEG_64_B64 = "/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAAMCAgMCAgMDAwMEAwMEBQgFBQQEBQoHBwYIDAoMDAsKCwsNDhIQDQ4RDgsLEBYQERMUFRUVDA8XGBYUGBIUFRT/2wBDAQMEBAUEBQkFBQkUDQsNFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBT/wAARCABAAEADASIAAhEBAxEB/8QAHwAAAQUBAQEBAQEAAAAAAAAAAAECAwQFBgcICQoL/8QAtRAAAgEDAwIEAwUFBAQAAAF9AQIDAAQRBRIhMUEGE1FhByJxFDKBkaEII0KxwRVS0fAkM2JyggkKFhcYGRolJicoKSo0NTY3ODk6Q0RFRkdISUpTVFVWV1hZWmNkZWZnaGlqc3R1dnd4eXqDhIWGh4iJipKTlJWWl5iZmqKjpKWmp6ipqrKztLW2t7i5usLDxMXGx8jJytLT1NXW19jZ2uHi4+Tl5ufo6erx8vP09fb3+Pn6/8QAHwEAAwEBAQEBAQEBAQAAAAAAAAECAwQFBgcICQoL/8QAtREAAgECBAQDBAcFBAQAAQJ3AAECAxEEBSExBhJBUQdhcRMiMoEIFEKRobHBCSMzUvAVYnLRChYkNOEl8RcYGRomJygpKjU2Nzg5OkNERUZHSElKU1RVVldYWVpjZGVmZ2hpanN0dXZ3eHl6goOEhYaHiImKkpOUlZaXmJmaoqOkpaanqKmqsrO0tba3uLm6wsPExcbHyMnK0tPU1dbX2Nna4uPk5ebn6Onq8vP09fb3+Pn6/9oADAMBAAIRAxEAPwD8z7LSOny1vWWkdPlrZstI6fLW9ZaR0+WiEwy7MdtTHstH6fLW9ZaR0+Wtmy0jp8tb1lo/T5a7oTP07Lsx21Mey0jp8tb1lpHT5a2LLSOny1v2WkdPlruhM/T8uzHbUxrLR+ny1v2WkdPlrYstI6fLW/ZaP0+Wu6Ez9Oy7MdtT5hstH6fLW9ZaR0+Wtmy0jp8tb1lo/T5a+HhM/wAxsuzHbUx7LSOny1vWWkdPlrZstI6fLW9ZaR0+Wu6Ez9Oy7MdtTGstH6fLW/ZaR0+Wtiy0jp8tb9lo/T5a7oTP07Lsx21May0jp8tb9lpHT5a2LLSOny1v2WkdPlruhM/T8uzHbU+YbLSOny1vWWkdPlrZstI6fLW9ZaR0+Wvh4TP8xcuzHbUx7LR+ny1vWWkdPlrZstI6fLW9ZaP0+Wu6Ez9Py7MdtTGstI6fLW/ZaR0+Wtiy0jp8tb9lpHT5a7oTP07Lsx21May0fp8tb1lpHT5a2bLSOny1vWWj9PlruhM/TsuzHbU+YrLR+ny1vWWkdPlrZstI6fLW9ZaP0+Wvh4TP8xsuzHbUxrLSOny1v2WkdPlrYstI6fLW/ZaR0+Wu6Ez9Oy7MdtTGstH6fLW/ZaR0+Wtiy0jp8tb9lo/T5a7oTP0/Lsx21May0jp8tb1lpHT5a2bLSOny1vWWkdPlruhM/TsuzHbU/9k="

// 64x64 渐变 WebP（PIL quality=90 生成）：WebP shrink-on-load 路径（scale= 选项，
// 与 JPEG shrink= 同构）。文件名按磁盘缓存惯例取 .img，WebP 判定靠 RIFF/WEBP 魔数嗅探。
private let WEBP_64_B64 = "UklGRkIBAABXRUJQVlA4IDYBAAAQCQCdASpAAEAAPjEWiEKiISEgrAgAQAYJYj4zoDHBseKqNgkrP8t+KvsvWbuB2pQP67kCuSZBgaGigA9HDi+d2LKDgIMo5rfft//+me///OAA/v/+0orLboXpTILoooVaGOu5P4X7R+YbMj7Dj/GKvXBfv1hf5rijK5PGgFj5AJtLWOijRXUjI31QDdcANCaJeV+jcSX78ahuMlcOvqDQ3Lij9OhP/+iUL//E6jPnZjaqNj37TT59xgaRgmGYwOQbqdedwXXPdy4qwWdcL6N/d9sblKrrACI43flJo3rKUiBaGcKn3S3vFPwmRRp5Q/0IBI8JhFb8bmG23vZSAaxd8Q/BNqFTiv6AtaP/Ynqj//E7EL6eUZ1fuYjrHOSzS8/mijxxOa44AYhfIbLyqJFFKLqoMAAA"

@Test
func decodePngToRgba(): Unit {
    let dir = Directory.createTemp(Path("."))
    let src = "${dir}/in.png"
    let bytes = fromBase64String(PNG_1PX_B64) ?? Array<UInt8>(0, repeat: 0)
    File.writeTo(Path(src), bytes)
    let d = decodeFileToRgba(src)
    @Expect(d.width, 1i32)
    @Expect(d.height, 1i32)
    // RGBA 四波段：像素长度必须 == width*height*4（原生内存按同尺寸记账）
    @Expect(d.size, Int64(d.width) * Int64(d.height) * 4)
    @Expect(d.copyPixels().size, d.size)  // 拷贝路径与大小一致（测试断言用）
    @Expect(d.isClosed(), false)
    d.close()
    @Expect(d.isClosed(), true)
    d.close()  // 幂等：二次释放不崩溃
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

@Test
func decodeJpegFullSize(): Unit {
    let dir = Directory.createTemp(Path("."))
    let src = "${dir}/cover.img" // 缓存惯例的 .img 后缀：JPEG 判定走内容魔数，不走扩展名
    let bytes = fromBase64String(JPEG_64_B64) ?? Array<UInt8>(0, repeat: 0)
    File.writeTo(Path(src), bytes)
    let d = decodeFileToRgba(src)
    @Expect(d.width, 64i32)
    @Expect(d.height, 64i32)
    @Expect(d.size, 64 * 64 * 4)
    d.close()
    remove(dir, recursive: true)
}

@Test
func decodeJpegShrinkOnLoad(): Unit {
    let dir = Directory.createTemp(Path("."))
    let src = "${dir}/cover.img"
    let bytes = fromBase64String(JPEG_64_B64) ?? Array<UInt8>(0, repeat: 0)
    File.writeTo(Path(src), bytes)
    // 64 → 目标 16：shrink-on-load 先按 2 幂因子缩（64/4=16 ≥ 16 取 shrink=4），再 resize 到 16。
    // 外部可观察语义与纯 resize 一致：精确落在目标档位，不放大、不越档。
    let d = decodeFileToRgba(src, maxDimension: 16i32)
    @Expect(d.width, 16i32)
    @Expect(d.height, 16i32)
    @Expect(d.size, 16 * 16 * 4)
    // 缩小解码 + RGBA 归一后不应是全黑/全透明（验证像素真实解出）。
    var sum: Int64 = 0
    for (b in d.copyPixels()) {
        sum += Int64(b)
    }
    @Expect(sum > 0, true)
    d.close()
    remove(dir, recursive: true)
}

@Test
func decodeWebpShrinkOnLoad(): Unit {
    let dir = Directory.createTemp(Path("."))
    let src = "${dir}/cover.img" // 缓存惯例的 .img 后缀：WebP 判定走 RIFF/WEBP 魔数，不走扩展名
    let bytes = fromBase64String(WEBP_64_B64) ?? Array<UInt8>(0, repeat: 0)
    File.writeTo(Path(src), bytes)
    // 64 → 目标 16：WebP 按 scale=4 缩档重开（64/4=16 ≥ 16），余量 resize 到 16。
    // 外部可观察语义与 JPEG shrink / 纯 resize 一致：精确落在目标档位，不放大、不越档。
    let d = decodeFileToRgba(src, maxDimension: 16i32)
    @Expect(d.width, 16i32)
    @Expect(d.height, 16i32)
    @Expect(d.size, 16 * 16 * 4)
    // 缩小解码 + RGBA 归一后不应是全黑/全透明（验证像素真实解出）。
    var sum: Int64 = 0
    for (b in d.copyPixels()) {
        sum += Int64(b)
    }
    @Expect(sum > 0, true)
    d.close()
    remove(dir, recursive: true)
}
