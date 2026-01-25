package lrr4cj.controllers

import cjoy.*
import std.time.*
import std.fs.*
import lrr4cj.dao.*
import lrr4cj.models.*
import lrr4cj.services.*
import lrr4cj.utils.*
import stdx.encoding.json.stream.*

class CategoryUpsertReq <: JsonDeserializable<CategoryUpsertReq> {
    var name: String = ""
    var scanPath: String = ""
    var description: String = ""
    var icon: String = ""
    var sortOrder: Int32 = 0
    var enabled: Bool = true
    // Stored as raw JSON string (array/object); defaults to [].
    var plugins: String = "[]"

    private static func readRawJson(r: JsonReader): String {
        match (r.peek()) {
            case Some(BeginObject) =>
                let bytes = r.readValueBytes()
                return String.fromUtf8(bytes)
            case Some(BeginArray) =>
                let bytes = r.readValueBytes()
                return String.fromUtf8(bytes)
            case Some(_) =>
                return r.readValue<String>()
            case None =>
                return ""
        }
    }

    public static func fromJson(r: JsonReader): CategoryUpsertReq {
        let res = CategoryUpsertReq()
        while (let Some(tok) <- r.peek()) {
            match (tok) {
                case BeginObject =>
                    r.startObject()
                    while (r.peek() != EndObject) {
                        let n = r.readName()
                        match (n) {
                            case "name" => res.name = r.readValue<String>().trimAscii()
                            case "scan_path" => res.scanPath = r.readValue<String>().trimAscii()
                            case "description" => res.description = r.readValue<String>()
                            case "icon" => res.icon = r.readValue<String>()
                            case "sort_order" =>
                                let s = r.readValue<String>().trimAscii()
                                try { res.sortOrder = Int32.parse(s) } catch (_: Exception) {}
                            case "enabled" =>
                                let s = r.readValue<String>().trimAscii()
                                res.enabled = s == "true" || s == "1"
                            case "plugins" =>
                                let raw = readRawJson(r).trimAscii()
                                if (raw.size > 0) { res.plugins = raw }
                            case _ => r.skip()
                        }
                    }
                    r.endObject()
                    break
                case _ => throw Exception("invalid json")
            }
        }
        return res
    }
}

/**
 * 分类控制器（新结构）
 * 每个分类对应一个扫描目录
 */
public class CategoryController {
    private static func categoryToJson(cat: CategoryData): String {
        var json = "{"
        json += "\"id\":${cat.id},"
        json += "\"catid\":\"${escapeJson(cat.catid)}\","
        json += "\"name\":\"${escapeJson(cat.name)}\","
        json += "\"scan_path\":\"${escapeJson(cat.scanPath)}\","
        json += "\"description\":\"${escapeJson(cat.description)}\","
        json += "\"icon\":\"${escapeJson(cat.icon)}\","
        json += "\"sort_order\":${cat.sortOrder},"
        json += "\"enabled\":${cat.enabled},"
        json += "\"plugins\":${cat.plugins},"
        json += "\"archive_count\":${cat.archiveCount},"
        json += "\"created_at\":\"${escapeJson(cat.createdAt)}\","
        json += "\"updated_at\":\"${escapeJson(cat.updatedAt)}\""
        json += "}"
        return json
    }

    /**
     * GET /api/categories - 获取所有分类
     */
    public static func getCategories(ctx: JoyContext) {
        let categories = CategoryDao.getAllCategories()

        var categoriesJson = "["
        var isFirst = true
        for (cat in categories) {
            if (!isFirst) {
                categoriesJson += ","
            }
            isFirst = false
            categoriesJson += categoryToJson(cat)
        }
        categoriesJson += "]"

        let result = "{\"operation\":\"get_categories\",\"data\":${categoriesJson},\"success\":1}"
        ctx.json(result)
    }

    /**
     * GET /api/categories/{id} - 获取分类详情
     */
    public static func getCategoryById(ctx: JoyContext) {
        let catid = ctx.getParam("id") ?? ""

        match (CategoryDao.getCategoryById(catid)) {
            case Some(cat) =>
                let result = "{\"operation\":\"get_category\",\"data\":${categoryToJson(cat)},\"success\":1}"
                ctx.json(result)
            case None =>
                ctx.status(404)
                ctx.json("{\"success\":0,\"error\":\"Category not found\"}")
        }
    }

    /**
     * POST /api/categories - 创建分类
     */
    public static func createCategory(ctx: JoyContext) {
        try {
            let body = ctx.readString()
            let req = if (body.trimAscii().size > 0) { JsonCodec.decode<CategoryUpsertReq>(body) } else { CategoryUpsertReq() }
            let name = req.name
            let scanPath = req.scanPath
            let description = req.description
            let icon = req.icon
            let sortOrder = req.sortOrder
            let enabled = req.enabled
            let plugins = req.plugins

            if (name.size == 0) {
                ctx.status(400)
                ctx.json("{\"success\":0,\"error\":\"name is required\"}")
                return
            }

            if (scanPath.size == 0) {
                ctx.status(400)
                ctx.json("{\"success\":0,\"error\":\"scan_path is required\"}")
                return
            }

            // 验证路径是否存在
            let pathExists = exists(Path(scanPath))
            if (!pathExists) {
                ctx.status(400)
                ctx.json("{\"success\":0,\"error\":\"scan_path does not exist: ${scanPath}\"}")
                return
            }

            // 生成 catid
            let catid = "CAT_${DateTime.now().toUnixTimeStamp().toMilliseconds()}"

            let data = CategoryData()
            data.catid = catid
            data.name = name
            data.scanPath = scanPath
            data.description = description
            data.icon = icon
            data.sortOrder = sortOrder
            data.enabled = enabled
            data.plugins = plugins

            match (CategoryDao.createCategory(data)) {
                case Some(created) =>
                    let result = "{\"operation\":\"create_category\",\"data\":${categoryToJson(created)},\"success\":1}"
                    ctx.json(result)
                case None =>
                    ctx.status(500)
                    ctx.json("{\"success\":0,\"error\":\"Failed to create category\"}")
            }
        } catch (e: Exception) {
            getLogger("category_controller").error("创建分类失败", ("error", e.message))
            ctx.status(500)
            ctx.json("{\"success\":0,\"error\":\"${escapeJson(e.message)}\"}")
        }
    }

    /**
     * PUT /api/categories/{id} - 更新分类
     */
    public static func updateCategory(ctx: JoyContext) {
        let catid = ctx.getParam("id") ?? ""

        // 先获取现有分类
        let existingOpt = CategoryDao.getCategoryById(catid)
        match (existingOpt) {
            case None =>
                ctx.status(404)
                ctx.json("{\"success\":0,\"error\":\"Category not found\"}")
                return
            case Some(_) => ()
        }
        let existing = existingOpt.getOrThrow()

        try {
            let body = ctx.readString()
            var name = existing.name
            var scanPath = existing.scanPath
            var description = existing.description
            var icon = existing.icon
            var sortOrder = existing.sortOrder
            var enabled = existing.enabled
            var plugins = existing.plugins

            if (body.trimAscii().size > 0) {
                let req = JsonCodec.decode<CategoryUpsertReq>(body)
                if (req.name.size > 0) { name = req.name }
                if (req.scanPath.size > 0) { scanPath = req.scanPath }
                if (req.description.size > 0) { description = req.description }
                if (req.icon.size > 0) { icon = req.icon }
                sortOrder = req.sortOrder
                enabled = req.enabled
                if (req.plugins.trimAscii().size > 0) { plugins = req.plugins }
            }

            if (name.size == 0) {
                ctx.status(400)
                ctx.json("{\"success\":0,\"error\":\"name is required\"}")
                return
            }

            // 如果路径变更，验证新路径是否存在
            if (scanPath != existing.scanPath) {
                let pathExists = exists(Path(scanPath))
                if (!pathExists) {
                    ctx.status(400)
                    ctx.json("{\"success\":0,\"error\":\"scan_path does not exist: ${scanPath}\"}")
                    return
                }
            }

            let data = CategoryData()
            data.name = name
            data.scanPath = scanPath
            data.description = description
            data.icon = icon
            data.sortOrder = sortOrder
            data.enabled = enabled
            data.plugins = plugins

            if (CategoryDao.updateCategory(catid, data)) {
                ctx.json("{\"operation\":\"update_category\",\"success\":1}")
            } else {
                ctx.status(500)
                ctx.json("{\"success\":0,\"error\":\"Failed to update category\"}")
            }
        } catch (e: Exception) {
            getLogger("category_controller").error("更新分类失败", ("error", e.message))
            ctx.status(500)
            ctx.json("{\"success\":0,\"error\":\"${escapeJson(e.message)}\"}")
        }
    }

    /**
     * DELETE /api/categories/{id} - 删除分类
     */
    public static func deleteCategory(ctx: JoyContext) {
        let catid = ctx.getParam("id") ?? ""

        let (ok, deletedArchives, err) = CategoryDao.deleteCategory(catid)
        if (ok) {
            ctx.json("{\"operation\":\"delete_category\",\"success\":1,\"deleted_archives\":${deletedArchives.toString()}}")
            return
        }

        if (err == "Category not found") {
            ctx.status(404)
            ctx.json("{\"success\":0,\"error\":\"Category not found\"}")
            return
        }

        ctx.status(500)
        let msg = if (err.size > 0) { escapeJson(err) } else { "Failed to delete category" }
        ctx.json("{\"success\":0,\"error\":\"${msg}\"}")
    }

    /**
     * POST /api/categories/{id}/scan - 触发分类扫描
     */
    public static func scanCategory(ctx: JoyContext) {
        let catid = ctx.getParam("id") ?? ""

        match (CategoryDao.getCategoryById(catid)) {
            case Some(cat) =>
                // 创建扫描任务
                let params = "{\"category_id\":\"${escapeJson(cat.catid)}\"}"
                let task = TaskModel.createTaskWithOptions(
                    "扫描分类: ${cat.name}",
                    "scan_single_category",
                    params,
                    20i32,
                    "category_scan:${cat.id}",
                    "manual"
                )

                if (task.id > 0) {
                    TaskPoolService.getInstance().notifyTaskAvailable()
                    getLogger("category_controller").info("创建分类扫描任务", ("catid", catid), ("task_id", task.id.toString()))
                    ctx.json("{\"operation\":\"scan_category\",\"success\":1,\"task_id\":${task.id}}")
                } else {
                    ctx.status(500)
                    ctx.json("{\"success\":0,\"error\":\"Failed to create scan task\"}")
                }
            case None =>
                ctx.status(404)
                ctx.json("{\"success\":0,\"error\":\"Category not found\"}")
        }
    }
}
