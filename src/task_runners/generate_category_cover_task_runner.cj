package lanlu.task_runners

import stdx.log.*
import std.io.{ByteBuffer, readToEnd}
import stdx.encoding.json.stream.*
import std.fs.*
import std.collection.*
import std.convert.*
import std.time.*
import lanlu.models.*
import lanlu.dao.*
import lanlu.utils.*
import avif_ffi.*

// NOTE: DO NOT use SecureRandom for cover generation: on some systems it can block waiting
// for entropy, which will "hang" the task runner. Cover generation only needs a fast PRNG.
private class CategoryCoverRng {
    public var state: UInt64
    public init(seed: UInt64) {
        // Avoid the all-zero state (xorshift would get stuck).
        state = if (seed == 0u64) { 0x9e3779b97f4a7c15u64 } else { seed }
    }
    public func nextU64(): UInt64 {
        var x = state
        x ^= (x << 13)
        x ^= (x >> 7)
        x ^= (x << 17)
        state = x
        return x
    }
}

private class CoverSlotImage {
    public let pixels: Array<UInt8>
    public let w: Int32
    public let h: Int32
    public init(pixels: Array<UInt8>, w: Int32, h: Int32) {
        this.pixels = pixels
        this.w = w
        this.h = h
    }
}

/**
 * Generate "cover" for a category by selecting representative archive cover assets.
 *
 * Output:
 * - Generates an AVIF cover image, stores in assets(kind='category_cover'),
 * - Updates categories.cover_asset_id to point to the created asset id.
 */
public class GenerateCategoryCoverTaskRunner {
    private static func parseParameters(parameters: String): String {
        let trimmed = parameters.trimAscii()
        if (trimmed.size == 0) { return "" }

        var catid = ""
        try {
            var buf = ByteBuffer()
            unsafe { buf.write(trimmed.rawData()) }
            let r = JsonReader(buf)
            if (r.peek() != Some(BeginObject)) { return "" }
            r.startObject()
            while (r.peek() != EndObject) {
                let k = r.readName()
                match (k) {
                    case "category_id" => catid = r.readValue<String>().trimAscii()
                    case _ => r.skip()
                }
            }
            r.endObject()
        } catch (_: Exception) {}
        return catid
    }

    private static func fnv1a64(s: String): UInt64 {
        // Deterministic seed mixer for CategoryCoverRng.
        //
        // IMPORTANT: avoid multiplication here. The runtime traps on overflow for `mul`,
        // and "hash multipliers" are expected to overflow in 64-bit arithmetic.
        var h: UInt64 = 0x9e3779b97f4a7c15u64
        unsafe {
            for (b in s.rawData()) {
                let x = UInt64(Int32(b) & 255)
                h ^= x
                // A few xorshift-like mixes (no mul/add).
                h ^= (h << 7)
                h ^= (h >> 9)
                h ^= (x << 1)
            }
        }
        return h
    }

    private static func pickPalette(r: CategoryCoverRng): ((Int32, Int32, Int32), (Int32, Int32, Int32)) {
        let palettes = [
            ((14i32, 165i32, 233i32), (167i32, 139i32, 250i32)), // sky -> violet
            ((34i32, 197i32, 94i32), (6i32, 182i32, 212i32)),    // green -> cyan
            ((249i32, 115i32, 22i32), (239i32, 68i32, 68i32)),   // orange -> red
            ((59i32, 130i32, 246i32), (16i32, 185i32, 129i32)),  // blue -> emerald
            ((139i32, 92i32, 246i32), (236i32, 72i32, 153i32))   // violet -> pink
        ]
        let p = Int64(r.nextU64() % UInt64(palettes.size))
        return palettes[p]
    }

    private static func clamp8(x: Int32): UInt8 {
        if (x < 0i32) { return 0u8 }
        if (x > 255i32) { return 255u8 }
        return UInt8(x)
    }

    private static func blendOver(
        pixels: Array<UInt8>,
        width: Int32,
        x: Int32,
        y: Int32,
        r: Int32,
        g: Int32,
        b: Int32,
        a: Int32
    ): Unit {
        if (x < 0i32 || y < 0i32) { return }
        if (x >= width) { return }
        let idx = (Int64(y) * Int64(width) + Int64(x)) * 4
        if (idx < 0 || idx + 3 >= Int64(pixels.size)) { return }
        let dstR = Int32(pixels[idx])
        let dstG = Int32(pixels[idx + 1])
        let dstB = Int32(pixels[idx + 2])

        let alpha = if (a < 0i32) { 0i32 } else if (a > 255i32) { 255i32 } else { a }
        let inv = 255i32 - alpha

        pixels[idx] = clamp8((dstR * inv + r * alpha) / 255i32)
        pixels[idx + 1] = clamp8((dstG * inv + g * alpha) / 255i32)
        pixels[idx + 2] = clamp8((dstB * inv + b * alpha) / 255i32)
        pixels[idx + 3] = 255u8
    }

    private static func drawImageRounded(
        dst: Array<UInt8>,
        dstW: Int32,
        dstH: Int32,
        x0: Int32,
        y0: Int32,
        w: Int32,
        h: Int32,
        radius: Int32,
        src: Array<UInt8>
    ): Unit {
        if (w <= 0i32 || h <= 0i32) { return }
        // src must be exactly w*h*4.
        if (Int64(src.size) != Int64(w) * Int64(h) * 4) { return }
        let rr = radius * radius
        let x1 = x0 + w - 1
        let y1 = y0 + h - 1
        for (yy in 0..dstH) {
            if (yy < y0 || yy > y1) { continue }
            for (xx in 0..dstW) {
                if (xx < x0 || xx > x1) { continue }
                // Rounded corner mask.
                let dx = if (xx - x0 < x1 - xx) { xx - x0 } else { x1 - xx }
                let dy = if (yy - y0 < y1 - yy) { yy - y0 } else { y1 - yy }
                var inside = true
                if (dx < radius && dy < radius) {
                    let cx = radius - dx
                    let cy = radius - dy
                    inside = (cx * cx + cy * cy) <= rr
                }
                if (!inside) { continue }

                let sx = xx - x0
                let sy = yy - y0
                let sidx = (Int64(sy) * Int64(w) + Int64(sx)) * 4
                let sr = Int32(src[sidx])
                let sg = Int32(src[sidx + 1])
                let sb = Int32(src[sidx + 2])
                let sa = Int32(src[sidx + 3])
                if (sa <= 0i32) { continue }
                blendOver(dst, dstW, xx, yy, sr, sg, sb, sa)
            }
        }
    }

    private static func drawRoundedRect(
        pixels: Array<UInt8>,
        width: Int32,
        height: Int32,
        x0: Int32,
        y0: Int32,
        w: Int32,
        h: Int32,
        radius: Int32,
        r: Int32,
        g: Int32,
        b: Int32,
        a: Int32
    ): Unit {
        if (w <= 0i32 || h <= 0i32) { return }
        let rr = radius * radius
        let x1 = x0 + w - 1
        let y1 = y0 + h - 1
        for (yy in 0..height) {
            if (yy < y0 || yy > y1) { continue }
            for (xx in 0..width) {
                if (xx < x0 || xx > x1) { continue }

                // Inside rounded rect?
                let dx = if (xx - x0 < x1 - xx) { xx - x0 } else { x1 - xx }
                let dy = if (yy - y0 < y1 - yy) { yy - y0 } else { y1 - yy }

                var inside = true
                if (dx < radius && dy < radius) {
                    let cx = radius - dx
                    let cy = radius - dy
                    inside = (cx * cx + cy * cy) <= rr
                }
                if (inside) {
                    blendOver(pixels, width, xx, yy, r, g, b, a)
                }
            }
        }
    }

    private static func generateTemplateCoverAvif(
        taskId: Int64,
        title: String,
        outputAvifPath: String,
        seed: UInt64,
        hero: ?CoverSlotImage,
        c1: ?CoverSlotImage,
        c2: ?CoverSlotImage,
        c3: ?CoverSlotImage
    ): (Bool, String, String) {
        // Returns (ok, thumbhash, error).
        // We generate pixels in-memory and encode directly to AVIF (no external tools like ffmpeg/convert).
        try {
            TaskIO.appendLog(taskId, "Cover step: init")

            let w: Int32 = 1200
            let h: Int32 = 400
            let pixelsLen = Int64(w) * Int64(h) * 4
            var pixels = Array<UInt8>(pixelsLen, repeat: 0u8)
            TaskIO.appendLog(taskId, "Cover step: alloc_pixels (${pixelsLen.toString()})")

            let rng = CategoryCoverRng(seed)
            let ((r1, g1, b1), (r2, g2, b2)) = pickPalette(rng)
            TaskIO.appendLog(taskId, "Cover step: palette (${r1.toString()},${g1.toString()},${b1.toString()}) -> (${r2.toString()},${g2.toString()},${b2.toString()})")

            // Background: diagonal gradient + vignette + subtle grain.
            TaskIO.appendLog(taskId, "Cover step: background")
            let halfW = Float64(w) / 2.0
            let halfH = Float64(h) / 2.0
            for (yy in 0..h) {
                for (xx in 0..w) {
                    let t = (Float64(xx) + Float64(yy) * 0.35) / Float64(w)
                    let tr = Float64(r1) + (Float64(r2 - r1) * t)
                    let tg = Float64(g1) + (Float64(g2 - g1) * t)
                    let tb = Float64(b1) + (Float64(b2 - b1) * t)

                    // Vignette.
                    let dx = (Float64(xx) - halfW) / halfW
                    let dy = (Float64(yy) - halfH) / halfH
                    var v = 1.0 - 0.28 * (dx * dx + dy * dy)
                    if (v < 0.65) { v = 0.65 }

                    // Grain (tiny random delta).
                    let n = Int32(rng.nextU64() & 255u64) - 128i32
                    let delta = n / 28i32  // ~[-4..4]

                    let idx = (Int64(yy) * Int64(w) + Int64(xx)) * 4
                    pixels[idx] = clamp8(Int32(tr * v) + delta)
                    pixels[idx + 1] = clamp8(Int32(tg * v) + delta)
                    pixels[idx + 2] = clamp8(Int32(tb * v) + delta)
                    pixels[idx + 3] = 255u8
                }
            }

            // Left "glass" overlay to make the UI title pop.
            TaskIO.appendLog(taskId, "Cover step: overlays")
            // Hero card background.
            drawRoundedRect(pixels, w, h, 54, 56, 520, 288, 30, 255, 255, 255, 190)
            drawRoundedRect(pixels, w, h, 58, 60, 512, 280, 28, 0, 0, 0, 16)
            if (let Some(img) <- hero) {
                // Fit image into the inner area (padding).
                drawImageRounded(pixels, w, h, 66, 68, 496, 264, 22, img.pixels)
            } else {
                // Fallback: subtle glass if no archive covers available.
                drawRoundedRect(pixels, w, h, 66, 68, 496, 264, 22, 255, 255, 255, 22)
            }

            // Floating cards on the right.
            // Card 1
            drawRoundedRect(pixels, w, h, 760, 48, 220, 150, 24, 255, 255, 255, 182)
            drawRoundedRect(pixels, w, h, 764, 52, 212, 142, 22, 0, 0, 0, 14)
            if (let Some(img1) <- c1) {
                drawImageRounded(pixels, w, h, 772, 60, 196, 126, 18, img1.pixels)
            } else {
                drawRoundedRect(pixels, w, h, 772, 60, 196, 126, 18, 255, 255, 255, 20)
            }

            // Card 2
            drawRoundedRect(pixels, w, h, 1000, 40, 180, 132, 22, 255, 255, 255, 170)
            drawRoundedRect(pixels, w, h, 1004, 44, 172, 124, 20, 0, 0, 0, 14)
            if (let Some(img2) <- c2) {
                drawImageRounded(pixels, w, h, 1012, 52, 156, 108, 16, img2.pixels)
            } else {
                drawRoundedRect(pixels, w, h, 1012, 52, 156, 108, 16, 255, 255, 255, 20)
            }

            // Card 3
            drawRoundedRect(pixels, w, h, 840, 220, 250, 160, 26, 255, 255, 255, 185)
            drawRoundedRect(pixels, w, h, 844, 224, 242, 152, 24, 0, 0, 0, 14)
            if (let Some(img3) <- c3) {
                drawImageRounded(pixels, w, h, 852, 232, 226, 136, 20, img3.pixels)
            } else {
                drawRoundedRect(pixels, w, h, 852, 232, 226, 136, 20, 255, 255, 255, 20)
            }

            // Encode to AVIF.
            TaskIO.appendLog(taskId, "Cover step: encode_avif")
            let ok = AvifEncoder.encodeRGBAFile(UInt32(w), UInt32(h), pixels, outputAvifPath)
            if (!ok) {
                return (false, "", "AVIF encode failed (title=${title})")
            }
            TaskIO.appendLog(taskId, "Cover step: encode_avif_done")

            let thumbHash = try { ThumbHashUtils.calculateThumbHashFromRgbaPixels(pixels) } catch (_: Exception) { "" }
            return (true, thumbHash, "")
        } catch (e: Exception) {
            return (false, "", "Exception: ${e.message}")
        }
    }

    private static func tryLoadCoverSlotImage(taskId: Int64, assetRoot: String, assetId: Int64, w: Int32, h: Int32): ?CoverSlotImage {
        if (assetId <= 0 || w <= 0i32 || h <= 0i32) { return None }
        let row = AssetDao.getById(assetId)
        if (row.id <= 0) { return None }
        let ext = if (row.fileExt.size > 0) { row.fileExt } else { "bin" }
        let path = FileUtils.joinPath(assetRoot, "${assetId}.${ext}")
        if (!exists(Path(path))) {
            TaskIO.appendLog(taskId, "Cover slot asset missing on disk: ${path}")
            return None
        }

        match (VipsConvertUtils.tryDecodeRgbaCoverPixels(path, w, h)) {
            case Some(pixels) =>
                if (pixels.size == 0) {
                    TaskIO.appendLog(taskId, "Cover slot decode failed: asset ${assetId} (${path})")
                    return None
                }
                return Some(CoverSlotImage(pixels, w, h))
            case None =>
                TaskIO.appendLog(taskId, "Cover slot decode unavailable (libvips init failed)")
                return None
        }
    }

    private static func pickDistinctCoverIds(pool: Array<Int64>, count: Int32, seed: UInt64): Array<Int64> {
        if (count <= 0i32 || pool.size == 0) { return Array<Int64>() }
        var picked = ArrayList<Int64>()
        var seen: HashMap<Int64, Bool> = HashMap<Int64, Bool>()
        let rng = CategoryCoverRng(seed)

        var attempts: Int32 = 0
        // Hard cap attempts to avoid infinite loops when pool is small.
        while (picked.size < Int64(count) && attempts < 200i32) {
            attempts += 1
            let idx = Int64(rng.nextU64() % UInt64(pool.size))
            let id = pool[idx]
            if (id <= 0) { continue }
            match (seen.get(id)) {
                case Some(_) => ()
                case None =>
                    seen[id] = true
                    picked.add(id)
            }
        }
        return picked.toArray()
    }

    private static func deleteOldCoverAsset(assetRoot: String, assetId: Int64): Unit {
        if (assetId <= 0) { return }
        try {
            let row = AssetDao.getById(assetId)
            if (row.id <= 0) { return }
            let ext = if (row.fileExt.size > 0) { row.fileExt } else { "bin" }
            let filePath = FileUtils.joinPath(assetRoot, "${assetId}.${ext}")
            try { remove(Path(filePath)) } catch (_: Exception) {}
            let _ = AssetDao.deleteById(assetId)
        } catch (_: Exception) {}
    }

    private static func regenerateForCategory(taskId: Int64, cat: CategoryData, cacheRoot: String, assetRoot: String): Bool {
        let ts = DateTime.now().toUnixTimeStamp().toSeconds()
        let tempDir = FileUtils.joinPath(cacheRoot, "category_cover/${cat.catid}_${ts.toString()}")
        FileUtils.ensureDirectoryExists(Path(tempDir))
        let avifPath = FileUtils.joinPath(tempDir, "cover.avif")

        TaskIO.appendLog(taskId, "Generating cover template: ${cat.catid} (${cat.name})")
        let seed = fnv1a64("${cat.catid}:${ts.toString()}")

        // Pull real archive cover assets to compose into the category cover.
        // We sample from a larger pool to keep the result "template-like but unique".
        let poolIds = ArchiveDao.getCategoryCoverAssetIds(cat.id, 24i32)
        let pickedIds = pickDistinctCoverIds(poolIds, 4i32, seed)
        if (pickedIds.size > 0) {
            TaskIO.appendLog(taskId, "Using archive cover assets: ${pickedIds.size.toString()}/${poolIds.size.toString()}")
        } else {
            TaskIO.appendLog(taskId, "No archive cover assets available; using placeholders")
        }

        // Slot sizes must match the hard-coded layout in generateTemplateCoverAvif().
        let heroImg: ?CoverSlotImage = if (pickedIds.size >= 1) { tryLoadCoverSlotImage(taskId, assetRoot, pickedIds[0], 496i32, 264i32) } else { None }
        let c1: ?CoverSlotImage = if (pickedIds.size >= 2) { tryLoadCoverSlotImage(taskId, assetRoot, pickedIds[1], 196i32, 126i32) } else { None }
        let c2: ?CoverSlotImage = if (pickedIds.size >= 3) { tryLoadCoverSlotImage(taskId, assetRoot, pickedIds[2], 156i32, 108i32) } else { None }
        let c3: ?CoverSlotImage = if (pickedIds.size >= 4) { tryLoadCoverSlotImage(taskId, assetRoot, pickedIds[3], 226i32, 136i32) } else { None }

        let (ok, thumbHash, err) = generateTemplateCoverAvif(taskId, cat.name, avifPath, seed, heroImg, c1, c2, c3)
        if (!ok) {
            let _ = FileUtils.removeFileOrDirectory(tempDir)
            TaskIO.appendLog(taskId, "ERROR: cover template generation failed: ${err}")
            return false
        }

        let byteSize = try { Int64(FileInfo(Path(avifPath)).size) } catch (_: Exception) { 0 }

        // Delete previous generated cover (best-effort) to avoid leaking assets.
        if (cat.coverAssetId > 0) { deleteOldCoverAsset(assetRoot, cat.coverAssetId) }

        TaskIO.appendLog(taskId, "Creating asset record: ${cat.catid}")
        match (AssetDao.create(None, "category_cover", "${cat.catid}.avif", "image/avif", "avif", byteSize, thumbHash)) {
            case Some(assetId) =>
                let finalPath = FileUtils.joinPath(assetRoot, "${assetId}.avif")
                try {
                    FileUtils.safeReplaceFile(Path(finalPath), Path(avifPath))
                } catch (e: Exception) {
                    let _ = FileUtils.removeFileOrDirectory(tempDir)
                    let _ = AssetDao.deleteById(assetId)
                    TaskIO.appendLog(taskId, "ERROR: failed to store cover asset: ${e.message}")
                    return false
                }
                let _ = FileUtils.removeFileOrDirectory(tempDir)
                let ok = CategoryDao.updateCoverAssetId(cat.catid, assetId)
                if (!ok) {
                    // Cleanup best-effort.
                    try { remove(Path(finalPath)) } catch (_: Exception) {}
                    let _ = AssetDao.deleteById(assetId)
                    return false
                }
                TaskIO.appendLog(taskId, "Cover updated: ${cat.catid} -> asset ${assetId}")
                return true
            case None =>
                let _ = FileUtils.removeFileOrDirectory(tempDir)
                TaskIO.appendLog(taskId, "ERROR: failed to create asset record for category cover")
                return false
        }
    }

    public static func run(taskId: Int64, parameters: String, context: TaskRunnerContext): Unit {
        let logger = getLogger("generate_category_cover")
        TaskIO.appendLog(taskId, "generate_category_cover task started")
        TaskIO.appendLog(taskId, "Task parameters: ${parameters}")

        let catid = parseParameters(parameters)
        // If category_id is empty, regenerate covers for ALL categories (cron-friendly).
        if (catid.size == 0) {
            let cacheRoot = context.paths.cachePath
            let assetRoot = context.paths.assetPath
            FileUtils.ensureDirectoryExists(Path(assetRoot))

            let categories = CategoryDao.getAllCategories()
            if (categories.size == 0) {
                let result = "{\"success\":1,\"updated\":0,\"total\":0,\"message\":\"No categories\"}"
                TaskModel.updateTaskProgress(taskId, 100, "No categories")
                TaskModel.completeTask(taskId, result)
                TaskIO.writeOutput(taskId, result)
                TaskIO.appendLog(taskId, "generate_category_cover completed: ${result}")
                return
            }

            var updated: Int64 = 0
            var idx: Int64 = 0
            let total = Int64(categories.size)

            for (cat in categories) {
                idx += 1
                let progress = 10i32 + Int32((idx * 80) / total)  // 10..90
                TaskModel.updateTaskProgress(taskId, progress, "Updating cover: ${cat.name}")
                if (regenerateForCategory(taskId, cat, cacheRoot, assetRoot)) {
                    updated += 1
                }
            }

            let result = "{\"success\":1,\"updated\":${updated},\"total\":${total}}"
            TaskModel.updateTaskProgress(taskId, 100, "Category covers updated (${updated}/${total})")
            TaskModel.completeTask(taskId, result)
            TaskIO.writeOutput(taskId, result)
            TaskIO.appendLog(taskId, "generate_category_cover completed: ${result}")
            logger.info("Category covers updated", [("updated", updated.toString()), ("total", total.toString())])
            return
        }

        match (CategoryDao.getCategoryById(catid)) {
            case None =>
                TaskRunnerOutput.fail(taskId, "Category not found: ${catid}")
                return
            case Some(cat) =>
                let cacheRoot = context.paths.cachePath
                let assetRoot = context.paths.assetPath
                FileUtils.ensureDirectoryExists(Path(assetRoot))
                TaskModel.updateTaskProgress(taskId, 10, "Selecting cover assets for ${cat.name}")
                let ok = regenerateForCategory(taskId, cat, cacheRoot, assetRoot)
                if (!ok) { TaskRunnerOutput.fail(taskId, "Failed to regenerate category cover") ; return }

                let out = ByteBuffer()
                let w = JsonWriter(out)
                w.startObject()
                w.writeName("success").writeValue(1)
                w.writeName("category_id").writeValue(catid)
                w.writeName("message").writeValue("ok")
                w.endObject()
                w.flush()
                let result = String.fromUtf8(readToEnd(out))

                TaskModel.updateTaskProgress(taskId, 100, "Category cover updated")
                TaskModel.completeTask(taskId, result)
                TaskIO.writeOutput(taskId, result)
                TaskIO.appendLog(taskId, "generate_category_cover completed: ${result}")
                logger.info("Category cover updated", [("catid", catid)])
        }
    }
}
