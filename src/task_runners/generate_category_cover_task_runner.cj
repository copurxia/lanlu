package lanlu.task_runners

import stdx.log.*
import std.io.{ByteBuffer, readToEnd}
import stdx.encoding.json.stream.*
import lanlu.models.*
import lanlu.dao.*
import lanlu.utils.*

/**
 * Generate "cover" for a category by selecting representative archive cover assets.
 *
 * Output:
 * - Updates categories.cover_assets to a JSON array of asset ids (e.g. [1,2,3]).
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

    private static func jsonArrayString(ids: Array<Int64>): String {
        let out = ByteBuffer()
        let w = JsonWriter(out)
        w.startArray()
        for (id in ids) {
            if (id > 0) { w.writeValue(id) }
        }
        w.endArray()
        w.flush()
        return String.fromUtf8(readToEnd(out))
    }

    public static func run(taskId: Int64, parameters: String, context: TaskRunnerContext): Unit {
        let logger = getLogger("generate_category_cover")
        TaskIO.appendLog(taskId, "generate_category_cover task started")
        TaskIO.appendLog(taskId, "Task parameters: ${parameters}")

        let catid = parseParameters(parameters)
        // If category_id is empty, regenerate covers for ALL categories (cron-friendly).
        if (catid.size == 0) {
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
                let coverIds = ArchiveDao.getCategoryCoverAssetIds(cat.id, 6)
                let coverJson = jsonArrayString(coverIds)
                if (CategoryDao.updateCoverAssets(cat.catid, coverJson)) {
                    updated += 1
                }
            }

            let result = "{\"success\":1,\"updated\":${updated},\"total\":${total}}"
            TaskModel.updateTaskProgress(taskId, 100, "Category covers updated (${updated}/${total})")
            TaskModel.completeTask(taskId, result)
            TaskIO.writeOutput(taskId, result)
            TaskIO.appendLog(taskId, "generate_category_cover completed: ${result}")
            logger.info("Category covers updated", ("updated", updated.toString()), ("total", total.toString()))
            return
        }

        match (CategoryDao.getCategoryById(catid)) {
            case None =>
                TaskRunnerOutput.fail(taskId, "Category not found: ${catid}")
                return
            case Some(cat) =>
                TaskModel.updateTaskProgress(taskId, 10, "Selecting cover assets for ${cat.name}")

                // Pick up to 6 recent archive covers from this category.
                let coverIds = ArchiveDao.getCategoryCoverAssetIds(cat.id, 6)
                let coverJson = jsonArrayString(coverIds)

                let ok = CategoryDao.updateCoverAssets(catid, coverJson)
                if (!ok) {
                    TaskRunnerOutput.fail(taskId, "Failed to update category cover_assets")
                    return
                }

                let out = ByteBuffer()
                let w = JsonWriter(out)
                w.startObject()
                w.writeName("success").writeValue(1)
                w.writeName("category_id").writeValue(catid)
                w.writeName("count").writeValue(Int64(coverIds.size))
                w.writeName("cover_assets").jsonValue(coverJson)
                w.endObject()
                w.flush()
                let result = String.fromUtf8(readToEnd(out))

                TaskModel.updateTaskProgress(taskId, 100, "Category cover updated (${coverIds.size})")
                TaskModel.completeTask(taskId, result)
                TaskIO.writeOutput(taskId, result)
                TaskIO.appendLog(taskId, "generate_category_cover completed: ${result}")
                logger.info("Category cover updated", ("catid", catid), ("count", coverIds.size.toString()))
        }
    }
}
