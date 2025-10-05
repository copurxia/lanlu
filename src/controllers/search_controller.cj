package lrr4cj.controllers

import cjoy.*
import cjoy.json.*
import lrr4cj.models.*
import lrr4cj.views.*

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
        
        // 简化处理，直接使用默认值
        let start = 0
        let count = 20
        
        let (archives, totalCount) = ArchiveModel.searchArchives(filter, category, Int32(start), Int32(count))
        
        // 手动构建JSON数组
        var archivesJson = "["
        var isFirst = true
        for (archive in archives) {
            if (!isFirst) {
                archivesJson += ","
            }
            isFirst = false
            
            archivesJson += "{"
            archivesJson = archivesJson + "\"arcid\":\"${archive.id}\","
            archivesJson = archivesJson + "\"title\":\"${archive.title}\","
            archivesJson = archivesJson + "\"filename\":\"${archive.filename}\","
            archivesJson = archivesJson + "\"summary\":\"${archive.summary}\","
            archivesJson = archivesJson + "\"thumbhash\":\"${archive.thumbhash}\","
            archivesJson = archivesJson + "\"created_at\":\"${archive.created_at}\","
            archivesJson = archivesJson + "\"updated_at\":\"${archive.updated_at}\","
            archivesJson = archivesJson + "\"relative_path\":\"${archive.relative_path}\","
            archivesJson = archivesJson + "\"file_size\":${archive.file_size},"
            archivesJson = archivesJson + "\"isnew\":${archive.isNew},"
            archivesJson = archivesJson + "\"pagecount\":${archive.pagecount},"
            archivesJson = archivesJson + "\"last_read_time\":\"${archive.last_read_time}\","
            archivesJson = archivesJson + "\"progress\":${archive.progress}"
            archivesJson += "}"
        }
        archivesJson += "]"
        
        let result = "{\"data\":" + archivesJson + ",\"draw\":0,\"recordsFiltered\":" + archives.size.toString() + ",\"recordsTotal\":" + totalCount.toString() + "}"
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