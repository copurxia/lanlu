package lrr4cj.controllers

import cjoy.*
import cjoy.json.*
import lrr4cj.models.*
import lrr4cj.views.*
import std.convert.*
import std.time.*
import std.random.*

/**
 * 搜索控制器
 */
public class SearchController {
    /**
     * 搜索归档
     */
    public static func searchArchives(ctx: JoyContext) {
        let category = ctx.getQuery("category") ?? ""
        let filter = ctx.getQuery("filter") ?? ""
        
        // 处理分页参数，设置默认值
        let startStr = ctx.getQuery("start") ?? "0"
        let countStr = ctx.getQuery("count") ?? "20"
        let sortby = ctx.getQuery("sortby") ?? "title"
        let order = ctx.getQuery("order") ?? "asc"
        
        // 解析分页参数
        let start = try {
            Int32.parse(startStr)
        } catch (e: Exception) {
            0i32
        }
        let count = try {
            Int32.parse(countStr)
        } catch (e: Exception) {
            20i32
        }
        
        let (archives, totalCount) = ArchiveModel.searchArchives(filter, category, Int32(start), Int32(count), sortby, order)
        
        // 手动构建JSON数组，按照API文档要求的格式
        var archivesJson = "["
        var isFirst = true
        for (archive in archives) {
            if (!isFirst) {
                archivesJson += ","
            }
            isFirst = false
            
            archivesJson += "{"
            archivesJson = archivesJson + "\"arcid\":\"${archive.id}\","
            archivesJson = archivesJson + "\"extension\":\"${archive.extension()}\","
            archivesJson = archivesJson + "\"filename\":\"${archive.filename}\","
            archivesJson = archivesJson + "\"isnew\":\"${archive.isNew}\","
            archivesJson = archivesJson + "\"lastreadtime\":${archive.lastreadtime()},"
            archivesJson = archivesJson + "\"pagecount\":${archive.pagecount},"
            archivesJson = archivesJson + "\"progress\":${archive.progress},"
            archivesJson = archivesJson + "\"size\":${archive.size()},"
            archivesJson = archivesJson + "\"summary\":\"${archive.summary}\","
            archivesJson = archivesJson + "\"tags\":\"${archive.tags}\","
            archivesJson = archivesJson + "\"title\":\"${archive.title}\""
            archivesJson += "}"
        }
        archivesJson += "]"
        
        let result = "{\"data\":" + archivesJson + ",\"draw\":0,\"recordsFiltered\":" + totalCount.toString() + ",\"recordsTotal\":" + totalCount.toString() + "}"
        ctx.json(result)
    }

    /**
     * 随机获取归档
     */
    public static func getRandomArchives(ctx: JoyContext) {
        let category = ctx.getQuery("category") ?? ""
        let filter = ctx.getQuery("filter") ?? ""
        let countStr = ctx.getQuery("count") ?? "5"
        let newOnlyStr = ctx.getQuery("newonly") ?? "false"
        let untaggedOnlyStr = ctx.getQuery("untaggedonly") ?? "false"
        
        let count = try {
            Int32.parse(countStr)
        } catch (e: Exception) {
            5i32
        }
        let newOnly = newOnlyStr == "true"
        let untaggedOnly = untaggedOnlyStr == "true"
        
        // 使用数据库级别的随机排序和过滤条件来获取随机归档
        // 将过滤条件移到SQL查询中，提高性能
        let (resultArchives, totalCount) = ArchiveModel.searchArchives(filter, category, 0, count, "RANDOM()", "desc", newOnly, untaggedOnly)
        
        // 手动构建JSON数组，按照API文档要求的格式
        var archivesJson = "["
        var isFirst = true
        for (archive in resultArchives) {
            if (!isFirst) {
                archivesJson += ","
            }
            isFirst = false
            
            archivesJson += "{"
            archivesJson = archivesJson + "\"arcid\":\"${archive.id}\","
            archivesJson = archivesJson + "\"extension\":\"${archive.extension()}\","
            archivesJson = archivesJson + "\"filename\":\"${archive.filename}\","
            archivesJson = archivesJson + "\"isnew\":\"${archive.isNew}\","
            archivesJson = archivesJson + "\"lastreadtime\":${archive.lastreadtime()},"
            archivesJson = archivesJson + "\"pagecount\":${archive.pagecount},"
            archivesJson = archivesJson + "\"progress\":${archive.progress},"
            archivesJson = archivesJson + "\"size\":${archive.size()},"
            archivesJson = archivesJson + "\"summary\":\"${archive.summary}\","
            archivesJson = archivesJson + "\"tags\":\"${archive.tags}\","
            archivesJson = archivesJson + "\"title\":\"${archive.title}\""
            archivesJson += "}"
        }
        archivesJson += "]"
        
        let result = "{\"data\":" + archivesJson + ",\"recordsTotal\":" + count.toString() + "}"
        ctx.json(result)
    }

    /**
     * 清除搜索缓存
     */
    public static func clearSearchCache(ctx: JoyContext) {
        let result = "{\"operation\":\"clear_cache\",\"success\":1}"
        ResponseView.successJson(ctx, result, "清除搜索缓存成功")
    }

    /**
     * 获取搜索建议
     */
    public static func getSearchSuggestions(ctx: JoyContext) {
        let query = ctx.getQuery("q") ?? ""
        let suggestions = "[\"suggestion1\",\"suggestion2\",\"suggestion3\"]"
        ResponseView.successJson(ctx, suggestions, "获取搜索建议成功")
    }

}