package lanlu.task_runners

import stdx.log.*
import std.io.{ByteBuffer, readToEnd}
import stdx.encoding.json.stream.*
import stdx.crypto.crypto.*
import std.fs.*
import std.collection.*
import std.convert.*
import std.time.*
import lanlu.models.*
import lanlu.dao.*
import lanlu.utils.*

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

    private static func escapeXml(s: String): String {
        // Minimal XML escaping for text nodes/attributes.
        return s
            .replace("&", "&amp;")
            .replace("<", "&lt;")
            .replace(">", "&gt;")
            .replace("\"", "&quot;")
            .replace("'", "&apos;")
    }

    private static func nextU64(r: SecureRandom): UInt64 {
        let bytes = r.nextBytes(8)
        var v: UInt64 = 0
        for (b in bytes) {
            // Byte is signed in some runtimes; normalize to 0..255 using & 0xFF via Int32.
            let x = UInt64(Int32(b) & 255)
            v = (v << 8) + x
        }
        return v
    }

    private static func pickRandomSubset(ids: Array<Int64>, maxCount: Int32, r: SecureRandom): Array<Int64> {
        if (maxCount <= 0 || ids.size == 0) { return Array<Int64>() }
        // Fisher-Yates shuffle on a copy, then take first N.
        var arr = Array<Int64>(Int64(ids.size), { i => ids[i] })
        var i: Int32 = Int32(arr.size) - 1
        while (i > 0) {
            let j = Int32(nextU64(r) % UInt64(i + 1))
            let tmp = arr[Int64(i)]
            arr[Int64(i)] = arr[Int64(j)]
            arr[Int64(j)] = tmp
            i -= 1
        }
        let n = if (Int32(arr.size) < maxCount) { Int32(arr.size) } else { maxCount }
        var out = ArrayList<Int64>()
        var k: Int32 = 0
        while (k < n) {
            if (arr[Int64(k)] > 0) { out.add(arr[Int64(k)]) }
            k += 1
        }
        return out.toArray()
    }

    private static func buildCoverSvg(categoryName: String, coverIds: Array<Int64>, r: SecureRandom): String {
        // A simple template: gradient bg + "cards" (no external image embeds) + title text.
        // We render to SVG first, then rasterize to AVIF via ArchiveUtils (libvips/ffmpeg).
        let title = escapeXml(categoryName)

        let palettes = [
            ("#0ea5e9", "#a78bfa"), // sky -> violet
            ("#22c55e", "#06b6d4"), // green -> cyan
            ("#f97316", "#ef4444"), // orange -> red
            ("#64748b", "#0f172a"), // slate -> dark
            ("#f59e0b", "#84cc16")  // amber -> lime
        ]
        let p = Int32(nextU64(r) % UInt64(palettes.size))
        let (c1, c2) = palettes[Int64(p)]

        // Layout constants (px)
        let w: Int32 = 1200
        let h: Int32 = 400

        // Build SVG string.
        var svg = ""
        svg = svg + "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
        svg = svg + "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"${w}\" height=\"${h}\" viewBox=\"0 0 ${w} ${h}\">\n"
        svg = svg + "  <defs>\n"
        svg = svg + "    <linearGradient id=\"bg\" x1=\"0\" y1=\"0\" x2=\"1\" y2=\"1\">\n"
        svg = svg + "      <stop offset=\"0\" stop-color=\"${c1}\"/>\n"
        svg = svg + "      <stop offset=\"1\" stop-color=\"${c2}\"/>\n"
        svg = svg + "    </linearGradient>\n"
        svg = svg + "    <filter id=\"shadow\" x=\"-20%\" y=\"-20%\" width=\"140%\" height=\"140%\">\n"
        svg = svg + "      <feDropShadow dx=\"0\" dy=\"6\" stdDeviation=\"10\" flood-color=\"#000\" flood-opacity=\"0.25\"/>\n"
        svg = svg + "    </filter>\n"
        svg = svg + "  </defs>\n"
        svg = svg + "  <rect x=\"0\" y=\"0\" width=\"${w}\" height=\"${h}\" fill=\"url(#bg)\"/>\n"
        svg = svg + "  <rect x=\"0\" y=\"0\" width=\"${w}\" height=\"${h}\" fill=\"#ffffff\" opacity=\"0.55\"/>\n"

        // Left title text.
        svg = svg + "  <text x=\"70\" y=\"210\" font-family=\"system-ui, -apple-system, Segoe UI, Roboto, sans-serif\" font-size=\"72\" font-weight=\"800\" fill=\"#0b1220\" opacity=\"0.9\">${title}</text>\n"

        // Decorative "cards" on the right (random rotations/positions), no external image embeds.
        let cardW: Int32 = 150
        let cardH: Int32 = 110
        let startX: Int32 = 1200 - (cardW * 2) - 90
        let startY: Int32 = 70
        var idx: Int32 = 0
        while (idx < 4) {
            let col = idx % 2
            let row = idx / 2
            let x: Int32 = startX + col * (cardW + 24)
            let y: Int32 = startY + row * (cardH + 22)
            let rot = Int32((Int64(nextU64(r) % 21) - 10)) // -10..10
            let cx = x + cardW / 2
            let cy = y + cardH / 2
            // A light random tint stripe.
            let stripe = if ((nextU64(r) % 2) == 0) { "#ffffff" } else { "#0b1220" }
            let stripeOpacity = if (stripe == "#ffffff") { "0.22" } else { "0.08" }
            svg = svg + "  <g filter=\"url(#shadow)\" transform=\"rotate(${rot} ${cx} ${cy})\">\n"
            svg = svg + "    <rect x=\"${x}\" y=\"${y}\" width=\"${cardW}\" height=\"${cardH}\" rx=\"20\" ry=\"20\" fill=\"#ffffff\" opacity=\"0.75\"/>\n"
            svg = svg + "    <rect x=\"${x}\" y=\"${y}\" width=\"${cardW}\" height=\"${cardH}\" rx=\"20\" ry=\"20\" fill=\"#000000\" opacity=\"0.03\"/>\n"
            svg = svg + "    <rect x=\"${x + 16}\" y=\"${y + 18}\" width=\"${cardW - 32}\" height=\"${cardH - 36}\" rx=\"14\" ry=\"14\" fill=\"${stripe}\" opacity=\"${stripeOpacity}\"/>\n"
            svg = svg + "  </g>\n"
            idx += 1
        }

        svg = svg + "</svg>\n"
        // NOTE: return the built string.
        return svg
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

    private static func regenerateForCategory(taskId: Int64, cat: CategoryData, cacheRoot: String, assetRoot: String, r: SecureRandom): Bool {
        // Generate an SVG template first (pure vector, no external images).
        let svg = buildCoverSvg(cat.name, Array<Int64>(), r)

        let ts = DateTime.now().toUnixTimeStamp().toSeconds()
        let tempDir = FileUtils.joinPath(cacheRoot, "category_cover/${cat.catid}_${ts.toString()}")
        FileUtils.ensureDirectoryExists(Path(tempDir))
        let svgPath = FileUtils.joinPath(tempDir, "cover.svg")
        let avifPath = FileUtils.joinPath(tempDir, "cover.avif")

        // Write SVG to temp.
        try {
            let f = File(Path(svgPath), Write)
            f.write(svg.toArray())
            f.close()
        } catch (e: Exception) {
            let _ = FileUtils.removeFileOrDirectory(tempDir)
            TaskIO.appendLog(taskId, "ERROR: failed to write temp svg: ${e.message}")
            return false
        }

        // Rasterize -> AVIF (1200x400 policy).
        let (convertRes, thumbHash) = ArchiveUtils.convertTagBackgroundToAvifWithThumbHash(svgPath, avifPath, tempDir)
        if (!convertRes.success) {
            let _ = FileUtils.removeFileOrDirectory(tempDir)
            TaskIO.appendLog(taskId, "ERROR: cover conversion failed: ${convertRes.error}")
            return false
        }

        let byteSize = try { Int64(FileInfo(Path(avifPath)).size) } catch (_: Exception) { 0 }

        // Delete previous generated cover (best-effort) to avoid leaking assets.
        if (cat.coverAssetId > 0) { deleteOldCoverAsset(assetRoot, cat.coverAssetId) }

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
            let r = SecureRandom()

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
                if (regenerateForCategory(taskId, cat, cacheRoot, assetRoot, r)) {
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
                let r = SecureRandom()
                TaskModel.updateTaskProgress(taskId, 10, "Selecting cover assets for ${cat.name}")
                let ok = regenerateForCategory(taskId, cat, cacheRoot, assetRoot, r)
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
