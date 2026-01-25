package lanlu.controllers

import cjoy.*
import stdx.log.*
import std.collection.*
import std.convert.*
import std.io.*
import std.io.{ByteBuffer, readToEnd}
import lanlu.dao.*
import lanlu.views.*
import lanlu.utils.*
import stdx.encoding.json.stream.*

class SmartFilterUpsertReq <: JsonDeserializable<SmartFilterUpsertReq> {
    var name: String = ""
    var translations: String = "{}" // raw JSON object string
    var icon: String = ""
    var query: String = ""
    var sortBy: String = ""
    var sortOrder: String = ""
    var dateFrom: String = ""
    var dateTo: String = ""
    var newOnly: Bool = false
    var untaggedOnly: Bool = false
    var sortOrderNum: Int32 = 0
    var enabled: Bool = false

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

    private static func readBoolFlexible(r: JsonReader): Bool {
        let s = r.readValue<String>().trimAscii()
        return s == "true" || s == "1"
    }

    private static func readInt32Flexible(r: JsonReader): Int32 {
        let s = r.readValue<String>().trimAscii()
        try { return Int32.parse(s) } catch (_: Exception) { return 0 }
    }

    public static func fromJson(r: JsonReader): SmartFilterUpsertReq {
        let res = SmartFilterUpsertReq()
        while (let Some(tok) <- r.peek()) {
            match (tok) {
                case BeginObject =>
                    r.startObject()
                    while (r.peek() != EndObject) {
                        let n = r.readName()
                        match (n) {
                            case "name" => res.name = r.readValue<String>()
                            case "translations" =>
                                let raw = readRawJson(r).trimAscii()
                                res.translations = if (raw.size > 0) { raw } else { "{}" }
                            case "icon" => res.icon = r.readValue<String>()
                            case "query" => res.query = r.readValue<String>()
                            case "sort_by" => res.sortBy = r.readValue<String>()
                            case "sort_order" => res.sortOrder = r.readValue<String>()
                            case "date_from" => res.dateFrom = r.readValue<String>()
                            case "date_to" => res.dateTo = r.readValue<String>()
                            case "newonly" => res.newOnly = readBoolFlexible(r)
                            case "untaggedonly" => res.untaggedOnly = readBoolFlexible(r)
                            case "sort_order_num" => res.sortOrderNum = readInt32Flexible(r)
                            case "enabled" => res.enabled = readBoolFlexible(r)
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
 * 智能分类控制器
 * - 公开接口：获取启用的智能分类列表（用于前端展示）
 * - 管理接口：管理员维护智能分类
 */
public class SmartFilterController {

    private static func filterToJson(filter: SmartFilterData): String {
        let out = ByteBuffer()
        let w = JsonWriter(out)
        w.startObject()
        w.writeName("id").writeValue(filter.id)
        w.writeName("name").writeValue(filter.name)
        // Stored as raw JSON object string.
        let translations = filter.translations.trimAscii()
        w.writeName("translations").jsonValue(if (translations.size > 0) { translations } else { "{}" })
        w.writeName("icon").writeValue(filter.icon)
        w.writeName("query").writeValue(filter.query)
        w.writeName("sort_by").writeValue(filter.sort_by)
        w.writeName("sort_order").writeValue(filter.sort_order)
        w.writeName("date_from").writeValue(filter.date_from)
        w.writeName("date_to").writeValue(filter.date_to)
        w.writeName("newonly").writeValue(filter.newonly)
        w.writeName("untaggedonly").writeValue(filter.untaggedonly)
        w.writeName("sort_order_num").writeValue(filter.sort_order_num)
        w.writeName("enabled").writeValue(filter.enabled)
        w.writeName("created_at").writeValue(filter.created_at)
        w.writeName("updated_at").writeValue(filter.updated_at)
        w.endObject()
        w.flush()
        return String.fromUtf8(readToEnd(out))
    }

    /**
     * GET /api/smart_filters
     * 获取所有启用的智能分类（用于前端展示）
     */
    public static func getEnabledFilters(ctx: JoyContext): Unit {
        let filters = SmartFilterDao.getEnabledFilters()
        let out = ByteBuffer()
        let w = JsonWriter(out)
        w.startObject()
        w.writeName("items")
        w.startArray()
        for (filter in filters) {
            w.jsonValue(filterToJson(filter))
        }
        w.endArray()
        w.endObject()
        w.flush()
        ResponseView.successJson(ctx, String.fromUtf8(readToEnd(out)), "获取智能分类成功")
    }

    /**
     * GET /api/admin/smart_filters
     * 获取所有智能分类（管理用）
     */
    public static func adminList(ctx: JoyContext): Unit {
        let filters = SmartFilterDao.getAllFilters()
        let out = ByteBuffer()
        let w = JsonWriter(out)
        w.startObject()
        w.writeName("items")
        w.startArray()
        for (filter in filters) {
            w.jsonValue(filterToJson(filter))
        }
        w.endArray()
        w.endObject()
        w.flush()
        ResponseView.successJson(ctx, String.fromUtf8(readToEnd(out)), "获取智能分类列表成功")
    }

    /**
     * GET /api/admin/smart_filters/:id
     * 获取单个智能分类
     */
    public static func adminGet(ctx: JoyContext): Unit {
        let idStr = ctx.getParam("id") ?? ""
        if (idStr.size == 0) {
            ctx.status(400)
            ResponseView.errorJson(ctx, "id is required", 400)
            return
        }

        var id: Int64 = 0
        try {
            id = Int64.parse(idStr)
        } catch (_: Exception) {
            ctx.status(400)
            ResponseView.errorJson(ctx, "invalid id", 400)
            return
        }

        match (SmartFilterDao.getById(id)) {
            case Some(filter) =>
                ResponseView.successJson(ctx, filterToJson(filter), "获取智能分类成功")
            case None =>
                ctx.status(404)
                ResponseView.errorJson(ctx, "not found", 404)
        }
    }

    /**
     * POST /api/admin/smart_filters
     * 创建智能分类
     */
    public static func adminCreate(ctx: JoyContext): Unit {
        let logger = getLogger("smart_filter_controller")
        try {
            let body = ctx.readString()
            if (body.trimAscii().size == 0) {
                ctx.status(400)
                ResponseView.errorJson(ctx, "Empty body", 400)
                return
            }

            var filter = SmartFilterData()
            try {
                let req = JsonCodec.decode<SmartFilterUpsertReq>(body)
                filter.name = req.name.trimAscii()
                filter.translations = req.translations
                filter.icon = req.icon
                filter.query = req.query
                filter.sort_by = req.sortBy
                filter.sort_order = req.sortOrder
                filter.date_from = req.dateFrom
                filter.date_to = req.dateTo
                filter.newonly = req.newOnly
                filter.untaggedonly = req.untaggedOnly
                filter.sort_order_num = req.sortOrderNum
                filter.enabled = req.enabled
            } catch (_: Exception) {
                ctx.status(400)
                ResponseView.errorJson(ctx, "Invalid JSON", 400)
                return
            }

            if (filter.name.size == 0) {
                ctx.status(400)
                ResponseView.errorJson(ctx, "name is required", 400)
                return
            }

            if (filter.sort_order.size == 0) {
                filter.sort_order = "desc"
            }

            match (SmartFilterDao.create(filter)) {
                case Some(id) =>
                    filter.id = id
                    ResponseView.successJson(ctx, "{\"success\":1,\"id\":${id.toString()}}", "创建成功")
                case None =>
                    ctx.status(500)
                    ResponseView.errorJson(ctx, "Create failed", 500)
            }
        } catch (e: Exception) {
            logger.error("adminCreate异常", ("error", e.message))
            ctx.status(500)
            ResponseView.errorJson(ctx, "Internal error", 500)
        }
    }

    /**
     * PUT /api/admin/smart_filters/:id
     * 更新智能分类
     */
    public static func adminUpdate(ctx: JoyContext): Unit {
        let logger = getLogger("smart_filter_controller")
        try {
            let idStr = ctx.getParam("id") ?? ""
            if (idStr.size == 0) {
                ctx.status(400)
                ResponseView.errorJson(ctx, "id is required", 400)
                return
            }

            var id: Int64 = 0
            try {
                id = Int64.parse(idStr)
            } catch (_: Exception) {
                ctx.status(400)
                ResponseView.errorJson(ctx, "invalid id", 400)
                return
            }

            // 检查是否存在
            match (SmartFilterDao.getById(id)) {
                case None =>
                    ctx.status(404)
                    ResponseView.errorJson(ctx, "not found", 404)
                    return
                case Some(_) => ()
            }

            let body = ctx.readString()
            if (body.trimAscii().size == 0) {
                ctx.status(400)
                ResponseView.errorJson(ctx, "Empty body", 400)
                return
            }

            var filter = SmartFilterData()
            filter.id = id
            try {
                let req = JsonCodec.decode<SmartFilterUpsertReq>(body)
                filter.name = req.name.trimAscii()
                filter.translations = req.translations
                filter.icon = req.icon
                filter.query = req.query
                filter.sort_by = req.sortBy
                filter.sort_order = req.sortOrder
                filter.date_from = req.dateFrom
                filter.date_to = req.dateTo
                filter.newonly = req.newOnly
                filter.untaggedonly = req.untaggedOnly
                filter.sort_order_num = req.sortOrderNum
                filter.enabled = req.enabled
            } catch (_: Exception) {
                ctx.status(400)
                ResponseView.errorJson(ctx, "Invalid JSON", 400)
                return
            }

            if (filter.name.size == 0) {
                ctx.status(400)
                ResponseView.errorJson(ctx, "name is required", 400)
                return
            }

            if (filter.sort_order.size == 0) {
                filter.sort_order = "desc"
            }

            if (SmartFilterDao.update(filter)) {
                ResponseView.successJson(ctx, "{\"success\":1}", "更新成功")
            } else {
                ctx.status(500)
                ResponseView.errorJson(ctx, "Update failed", 500)
            }
        } catch (e: Exception) {
            logger.error("adminUpdate异常", ("error", e.message))
            ctx.status(500)
            ResponseView.errorJson(ctx, "Internal error", 500)
        }
    }

    /**
     * DELETE /api/admin/smart_filters/:id
     * 删除智能分类
     */
    public static func adminDelete(ctx: JoyContext): Unit {
        let idStr = ctx.getParam("id") ?? ""
        if (idStr.size == 0) {
            ctx.status(400)
            ResponseView.errorJson(ctx, "id is required", 400)
            return
        }

        var id: Int64 = 0
        try {
            id = Int64.parse(idStr)
        } catch (_: Exception) {
            ctx.status(400)
            ResponseView.errorJson(ctx, "invalid id", 400)
            return
        }

        if (SmartFilterDao.delete(id)) {
            ResponseView.successJson(ctx, "{\"success\":1}", "删除成功")
        } else {
            ctx.status(500)
            ResponseView.errorJson(ctx, "Delete failed", 500)
        }
    }

    /**
     * POST /api/admin/smart_filters/reorder
     * 批量更新排序顺序
     */
    public static func adminReorder(ctx: JoyContext): Unit {
        let logger = getLogger("smart_filter_controller")
        try {
            let body = ctx.readString()
            if (body.trimAscii().size == 0) {
                ctx.status(400)
                ResponseView.errorJson(ctx, "Empty body", 400)
                return
            }

            var orders: ArrayList<(Int64, Int32)> = ArrayList<(Int64, Int32)>()
            var buf = ByteBuffer()
            unsafe { buf.write(body.rawData()) }
            let r = JsonReader(buf)

            func readInt64Flexible(): Int64 {
                let s = r.readValue<String>().trimAscii()
                try { return Int64.parse(s) } catch (_: Exception) { return 0 }
            }
            func readInt32Flexible(): Int32 {
                let s = r.readValue<String>().trimAscii()
                try { return Int32.parse(s) } catch (_: Exception) { return 0 }
            }

            // Expect: {"orders":[{"id":1,"sort_order_num":0}, ...]}
            match (r.peek()) {
                case Some(BeginObject) =>
                    r.startObject()
                    while (r.peek() != EndObject) {
                        let n = r.readName()
                        match (n) {
                            case "orders" =>
                                match (r.peek()) {
                                    case Some(BeginArray) =>
                                        r.startArray()
                                        while (r.peek() != EndArray) {
                                            match (r.peek()) {
                                                case Some(BeginObject) =>
                                                    var id: Int64 = 0
                                                    var sortOrder: Int32 = 0
                                                    r.startObject()
                                                    while (r.peek() != EndObject) {
                                                        let fn = r.readName()
                                                        match (fn) {
                                                            case "id" => id = readInt64Flexible()
                                                            case "sort_order_num" => sortOrder = readInt32Flexible()
                                                            case _ => r.skip()
                                                        }
                                                    }
                                                    r.endObject()
                                                    if (id > 0) { orders.add((id, sortOrder)) }
                                                case Some(_) => r.skip()
                                                case None => break
                                            }
                                        }
                                        r.endArray()
                                    case Some(_) =>
                                        ctx.status(400)
                                        ResponseView.errorJson(ctx, "orders must be an array", 400)
                                        return
                                    case None => ()
                                }
                            case _ => r.skip()
                        }
                    }
                    r.endObject()
                case _ =>
                    ctx.status(400)
                    ResponseView.errorJson(ctx, "Invalid JSON", 400)
                    return
            }

            if (orders.size == 0) {
                ctx.status(400)
                ResponseView.errorJson(ctx, "No valid orders provided", 400)
                return
            }

            if (SmartFilterDao.batchUpdateSortOrder(orders.toArray())) {
                ResponseView.successJson(ctx, "{\"success\":1}", "排序更新成功")
            } else {
                ctx.status(500)
                ResponseView.errorJson(ctx, "Reorder failed", 500)
            }
        } catch (e: Exception) {
            logger.error("adminReorder异常", ("error", e.message))
            ctx.status(500)
            ResponseView.errorJson(ctx, "Internal error", 500)
        }
    }

    /**
     * POST /api/admin/smart_filters/:id/toggle
     * 切换启用状态
     */
    public static func adminToggle(ctx: JoyContext): Unit {
        let idStr = ctx.getParam("id") ?? ""
        if (idStr.size == 0) {
            ctx.status(400)
            ResponseView.errorJson(ctx, "id is required", 400)
            return
        }

        var id: Int64 = 0
        try {
            id = Int64.parse(idStr)
        } catch (_: Exception) {
            ctx.status(400)
            ResponseView.errorJson(ctx, "invalid id", 400)
            return
        }

        if (SmartFilterDao.toggleEnabled(id)) {
            ResponseView.successJson(ctx, "{\"success\":1}", "切换成功")
        } else {
            ctx.status(500)
            ResponseView.errorJson(ctx, "Toggle failed", 500)
        }
    }
}
