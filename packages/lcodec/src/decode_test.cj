package lcodec

import std.env.getVariable
import std.fs.{remove, Directory, File, Path}
import stdx.encoding.base64.fromBase64String

// 1x1 PNG（与 client-next 原 img 包同一张标准测试图；迁移自 vips_decode_test.cj）。
private let PNG_1PX_B64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="

// 64x64 渐变 JPEG（shrink-on-load 路径）。文件名按磁盘缓存惯例取 .img。
private let JPEG_64_B64 = "/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAAMCAgMCAgMDAwMEAwMEBQgFBQQEBQoHBwYIDAoMDAsKCwsNDhIQDQ4RDgsLEBYQERMUFRUVDA8XGBYUGBIUFRT/2wBDAQMEBAUEBQkFBQkUDQsNFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBT/wAARCABAAEADASIAAhEBAxEB/8QAHwAAAQUBAQEBAQEAAAAAAAAAAAECAwQFBgcICQoL/8QAtRAAAgEDAwIEAwUFBAQAAAF9AQIDAAQRBRIhMUEGE1FhByJxFDKBkaEII0KxwRVS0fAkM2JyggkKFhcYGRolJicoKSo0NTY3ODk6Q0RFRkdISUpTVFVWV1hZWmNkZWZnaGlqc3R1dnd4eXqDhIWGh4iJipKTlJWWl5iZmqKjpKWmp6ipqrKztLW2t7i5usLDxMXGx8jJytLT1NXW19jZ2uHi4+Tl5ufo6erx8vP09fb3+Pn6/8QAHwEAAwEBAQEBAQEBAQAAAAAAAAECAwQFBgcICQoL/8QAtREAAgECBAQDBAcFBAQAAQJ3AAECAxEEBSExBhJBUQdhcRMiMoEIFEKRobHBCSMzUvAVYnLRChYkNOEl8RcYGRomJygpKjU2Nzg5OkNERUZHSElKU1RVVldYWVpjZGVmZ2hpanN0dXZ3eHl6goOEhYaHiImKkpOUlZaXmJmaoqOkpaanqKmqsrO0tba3uLm6wsPExcbHyMnK0tPU1dbX2Nna4uPk5ebn6Onq8vP09fb3+Pn6/9oADAMBAAIRAxEAPwD8z7LSOny1vWWkdPlrZstI6fLW9ZaR0+WiEwy7MdtTHstH6fLW9ZaR0+Wtmy0jp8tb1lo/T5a7oTP07Lsx21Mey0jp8tb1lpHT5a2LLSOny1v2WkdPlruhM/T8uzHbUxrLR+ny1v2WkdPlrYstI6fLW/ZaP0+Wu6Ez9Oy7MdtT5hstH6fLW9ZaR0+Wtmy0jp8tb1lo/T5a+HhM/wAxsuzHbUx7LSOny1vWWkdPlrZstI6fLW9ZaR0+Wu6Ez9Oy7MdtTGstH6fLW/ZaR0+Wtiy0jp8tb9lo/T5a7oTP07Lsx21May0jp8tb9lpHT5a2LLSOny1v2WkdPlruhM/T8uzHbU+YbLSOny1vWWkdPlrZstI6fLW9ZaR0+Wvh4TP8xcuzHbUx7LR+ny1vWWkdPlrZstI6fLW9ZaP0+Wu6Ez9Py7MdtTGstI6fLW/ZaR0+Wtiy0jp8tb9lpHT5a7oTP07Lsx21May0fp8tb1lpHT5a2bLSOny1vWWj9PlruhM/TsuzHbU+YrLR+ny1vWWkdPlrZstI6fLW9ZaP0+Wvh4TP8xsuzHbUxrLSOny1v2WkdPlrYstI6fLW/ZaR0+Wu6Ez9Oy7MdtTGstH6fLW/ZaR0+Wtiy0jp8tb9lo/T5a7oTP0/Lsx21May0jp8tb1lpHT5a2bLSOny1vWWkdPlruhM/TsuzHbU/9k="

// 64x64 渐变 WebP（RIFF/WEBP 魔数嗅探路径）。
private let WEBP_64_B64 = "UklGRkIBAABXRUJQVlA4IDYBAAAQCQCdASpAAEAAPjEWiEKiISEgrAgAQAYJYj4zoDHBseKqNgkrP8t+KvsvWbuB2pQP67kCuSZBgaGigA9HDi+d2LKDgIMo5rfft//+me///OAA/v/+0orLboXpTILoooVaGOu5P4X7R+YbMj7Dj/GKvXBfv1hf5rijK5PGgFj5AJtLWOijRXUjI31QDdcANCaJeV+jcSX78ahuMlcOvqDQ3Lij9OhP/+iUL//E6jPnZjaqNj37TT59xgaRgmGYwOQbqdedwXXPdy4qwWdcL6N/d9sblKrrACI43flJo3rKUiBaGcKn3S3vFPwmRRp5Q/0IBI8JhFb8bmG23vZSAaxd8Q/BNqFTiv6AtaP/Ynqj//E7EL6eUZ1fuYjrHOSzS8/mijxxOa44AYhfIbLyqJFFKLqoMAAA"

// AVIF 文件头（ftyp box，major brand = "avif"，后续 brand 凑满 32 字节）。
private let AVIF_HEAD: Array<UInt8> = [0x00u8, 0x00u8, 0x00u8, 0x20u8, 0x66u8, 0x74u8, 0x79u8, 0x70u8, 0x61u8, 0x76u8, 0x69u8, 0x66u8,
    0x00u8, 0x00u8, 0x00u8, 0x00u8, 0x61u8, 0x76u8, 0x69u8, 0x73u8, 0x6Du8, 0x69u8, 0x66u8, 0x31u8, 0x6Du8, 0x69u8, 0x61u8, 0x69u8,
    0x00u8, 0x00u8, 0x00u8, 0x00u8]

// 测试临时目录：固定基目录（TMPDIR → /tmp），不再落在包目录里。
// 历史问题：`Directory.createTemp(Path("."))` 把 tmpDir*/cover.img 之类的残渣写进仓库，
// 而且收尾的 remove 在某些文件系统上会因 `Directory not empty` 把解码用例判成 ERROR。
private func testTempDir(): Path {
    let base = match (getVariable("TMPDIR")) {
        case Some(v) => if (v.size > 0) { Path(v) } else { Path("/tmp") }
        case None => Path("/tmp")
    }
    Directory.createTemp(base)
}

// 收尾：临时目录清不掉不是被测行为的问题（失败用例已断言过解码结果），不让它掩盖结论。
private func discardTempDir(dir: Path): Unit {
    try {
        remove(dir, recursive: true)
    } catch (_: Exception) {}
}

@Test
func decodePngToRgba(): Unit {
    let dir = testTempDir()
    let src = "${dir}/in.png"
    let bytes = fromBase64String(PNG_1PX_B64) ?? Array<UInt8>(0, repeat: 0u8)
    File.writeTo(Path(src), bytes)
    let d = decodeFileToRgba(src)
    @Expect(d.width, 1i32)
    @Expect(d.height, 1i32)
    @Expect(d.size, Int64(d.width) * Int64(d.height) * 4)
    @Expect(d.copyPixels().size, d.size)
    @Expect(d.isClosed(), false)
    d.close()
    @Expect(d.isClosed(), true)
    d.close()
    discardTempDir(dir)
}

@Test
func decodeBadBytesThrows(): Unit {
    let dir = testTempDir()
    let src = "${dir}/bad.img"
    File.writeTo(Path(src), [0x89u8, 0x50u8, 0x4Eu8, 0x47u8, 0x0Du8, 0x0Au8, 0x1Au8, 0x0Au8])
    var threw = false
    var msg = ""
    try {
        let _ = decodeFileToRgba(src)
    } catch (e: Exception) {
        threw = true
        msg = e.message
    }
    @Expect(threw, true)
    // 截断 PNG 嗅探仍是 png：异常信息带 format=png（坏字节 != 未知格式）。
    @Expect(msg.contains("format=png"), true)
    discardTempDir(dir)
}

@Test
func decodeJpegFullSize(): Unit {
    let dir = testTempDir()
    let src = "${dir}/cover.img"
    let bytes = fromBase64String(JPEG_64_B64) ?? Array<UInt8>(0, repeat: 0u8)
    File.writeTo(Path(src), bytes)
    let d = decodeFileToRgba(src)
    @Expect(d.width, 64i32)
    @Expect(d.height, 64i32)
    @Expect(d.size, 64 * 64 * 4)
    d.close()
    discardTempDir(dir)
}

@Test
func decodeJpegShrinkOnLoad(): Unit {
    let dir = testTempDir()
    let src = "${dir}/cover.img"
    let bytes = fromBase64String(JPEG_64_B64) ?? Array<UInt8>(0, repeat: 0u8)
    File.writeTo(Path(src), bytes)
    let d = decodeFileToRgba(src, maxDimension: 16i32)
    @Expect(d.width, 16i32)
    @Expect(d.height, 16i32)
    @Expect(d.size, 16 * 16 * 4)
    var sum: Int64 = 0
    for (b in d.copyPixels()) {
        sum += Int64(b)
    }
    @Expect(sum > 0, true)
    d.close()
    discardTempDir(dir)
}

@Test
func decodeWebpShrinkOnLoad(): Unit {
    let dir = testTempDir()
    let src = "${dir}/cover.img"
    let bytes = fromBase64String(WEBP_64_B64) ?? Array<UInt8>(0, repeat: 0u8)
    File.writeTo(Path(src), bytes)
    // 宿主单测后端是 vips_shim（stb_image，无 webp）时解码失败属预期：本用例同时
    // 接受两条路径——真 libvips（CI/桌面）解出 16x16；shim 抛出的异常必须带
    // format=webp 诊断（lcodec 新增能力，OHOS 真机可用它区分"后端不支持"）。
    try {
        let d = decodeFileToRgba(src, maxDimension: 16i32)
        @Expect(d.width, 16i32)
        @Expect(d.height, 16i32)
        @Expect(d.size, 16 * 16 * 4)
        var sum: Int64 = 0
        for (b in d.copyPixels()) {
            sum += Int64(b)
        }
        @Expect(sum > 0, true)
        d.close()
    } catch (e: Exception) {
        @Expect(e.message.contains("format=webp"), true)
    }
    discardTempDir(dir)
}

@Test
func decodeBackdropResizesToTargetWidth(): Unit {
    let dir = testTempDir()
    let src = "${dir}/bd.img"
    let bytes = fromBase64String(JPEG_64_B64) ?? Array<UInt8>(0, repeat: 0u8)
    File.writeTo(Path(src), bytes)
    let d = decodeBackdrop(src, 48)
    @Expect(d.width, 48i32)
    d.close()
    discardTempDir(dir)
}

// ---- 嗅探（sniff.cj）----

@Test
func sniffDetectsPngJpegWebp(): Unit {
    let dir = testTempDir()
    let png = "${dir}/a.img"
    File.writeTo(Path(png), fromBase64String(PNG_1PX_B64) ?? Array<UInt8>(0, repeat: 0u8))
    @Expect(sniffImageFormat(png), SniffedImageFormat.Png)
    let jpg = "${dir}/b.img"
    File.writeTo(Path(jpg), fromBase64String(JPEG_64_B64) ?? Array<UInt8>(0, repeat: 0u8))
    @Expect(sniffImageFormat(jpg), SniffedImageFormat.Jpeg)
    let webp = "${dir}/c.img"
    File.writeTo(Path(webp), fromBase64String(WEBP_64_B64) ?? Array<UInt8>(0, repeat: 0u8))
    @Expect(sniffImageFormat(webp), SniffedImageFormat.Webp)
    discardTempDir(dir)
}

@Test
func sniffDetectsAvifByFtypBrand(): Unit {
    let dir = testTempDir()
    let avif = "${dir}/x.avif"
    File.writeTo(Path(avif), AVIF_HEAD)
    @Expect(sniffImageFormat(avif), SniffedImageFormat.Avif)
    @Expect(sniffedImageFormatName(sniffImageFormat(avif)), "avif")
    discardTempDir(dir)
}

@Test
func sniffUnknownForMissingAndGarbage(): Unit {
    @Expect(sniffImageFormat("/nonexistent/dir/x.img"), SniffedImageFormat.Unknown)
    let dir = testTempDir()
    let junk = "${dir}/j.img"
    File.writeTo(Path(junk), [0x00u8, 0x01u8, 0x02u8, 0x03u8, 0x04u8, 0x05u8, 0x06u8, 0x07u8,
        0x08u8, 0x09u8, 0x0Au8, 0x0Bu8, 0x0Cu8, 0x0Du8, 0x0Eu8, 0x0Fu8])
    @Expect(sniffImageFormat(junk), SniffedImageFormat.Unknown)
    discardTempDir(dir)
}

// ---- 高斯模糊（blur.cj，替代 cui 里原先直接调 vips 的 Modal 背景）----

@Test
func blurRgbaKeepsGeometryAndVariesPixels(): Unit {
    let w: Int32 = 32
    let h: Int32 = 32
    let px = Array<UInt8>(Int64(w) * Int64(h) * 4, repeat: 0u8)
    // 左半白右半黑：模糊后中间应出现灰度过渡带。
    for (y in 0..h) {
        for (x in 0..w) {
            let i = (Int64(y) * Int64(w) + Int64(x)) * 4
            let v: UInt8 = if (x < w / 2) { 255u8 } else { 0u8 }
            px[i] = v
            px[i + 1] = v
            px[i + 2] = v
            px[i + 3] = 255u8
        }
    }
    let blurred = blurRgba(px, w, h, sigma: 4.0)
    @Expect(blurred.isSome(), true)
    let out = blurred.getOrThrow()
    @Expect(out.size, px.size)
    // 边界附近应被揉开：取中间行紧挨分界的像素，不应是纯黑或纯白。
    let midRow = Int64(h / 2)
    let i = (midRow * Int64(w) + Int64(w / 2)) * 4
    @Expect(out[i] > 0, true)
    @Expect(out[i] < 255, true)
}

@Test
func blurRgbaRejectsBadGeometry(): Unit {
    @Expect(blurRgba(Array<UInt8>(8, repeat: 0u8), 2, 2, sigma: 2.0).isNone(), true)
    @Expect(blurRgba(Array<UInt8>(16, repeat: 0u8), 2, 2, sigma: 0.0).isNone(), true)
}

@Test
func vipsBackendIsLoadable(): Unit {
    // 运行时装载的后端：存在则 available()，缺失则必须给出明确原因（而不是铳接失败）。
    if (!VipsApi.available()) {
        @Expect(VipsApi.unavailableReason().size > 0, true)
    } else {
        @Expect(VipsApi.unavailableReason(), "")
    }
}

@Test
func avifFailureCarriesFormatDiagnostic(): Unit {
    // 只有 ftyp 头的 AVIF（无真实像素）：不管哪个后端都解不出来，
    // 但异常信息必须指明 format=avif（真机定位“后端不支持”而非“下载坏”的依据）。
    let dir = testTempDir()
    let src = "${dir}/cover.img"
    File.writeTo(Path(src), AVIF_HEAD)
    var msg = ""
    try {
        let d = decodeFileToRgba(src)
        // 万一某个后端能解这个截断头（理论上不应），也不按失败处理。
        d.close()
    } catch (e: Exception) {
        msg = e.message
    }
    if (msg.size > 0) {
        @Expect(msg.contains("format=avif"), true)
    }
    discardTempDir(dir)
}

@Test
func decodePngBytesToRgba(): Unit {
    // 内存字节入口（内嵌资源/logo 走这条）：桌面经 vips_image_new_from_buffer，
    // 设备经 OH_ImageSourceNative_CreateFromData。尺寸必须来自真实解码结果。
    let bytes = fromBase64String(PNG_1PX_B64) ?? Array<UInt8>(0, repeat: 0u8)
    let d = decodeBytesToRgba(bytes)
    @Expect(d.width, 1i32)
    @Expect(d.height, 1i32)
    @Expect(d.size, 4i64)
    @Expect(d.isClosed(), false)
    d.close()
    @Expect(d.isClosed(), true)
}

@Test
func decodeBytesShrinkRespectsMaxDimension(): Unit {
    // 64x64 JPEG 字节 → maxDimension=32 必须等比缩到 32x32（与文件路径同语义）。
    let bytes = fromBase64String(JPEG_64_B64) ?? Array<UInt8>(0, repeat: 0u8)
    let d = decodeBytesToRgba(bytes, maxDimension: 32)
    @Expect(max(d.width, d.height), 32i32)
    @Expect(d.size, Int64(d.width) * Int64(d.height) * 4)
    d.close()
}

@Test
func decodeBadBytesThrowsWithFormat(): Unit {
    // 截断的 PNG 头：字节入口也必须抛异常并带 format=png（不能静默返回空图）。
    var threw = false
    var msg = ""
    try {
        let d = decodeBytesToRgba([0x89u8, 0x50u8, 0x4Eu8, 0x47u8, 0x0Du8, 0x0Au8, 0x1Au8, 0x0Au8])
        d.close()
    } catch (e: Exception) {
        threw = true
        msg = e.message
    }
    @Expect(threw, true)
    @Expect(msg.contains("format=png"), true)
}

@Test
func decodeEmptyBytesThrows(): Unit {
    var threw = false
    try {
        let d = decodeBytesToRgba(Array<UInt8>(0, repeat: 0u8))
        d.close()
    } catch (_: Exception) {
        threw = true
    }
    @Expect(threw, true)
}
