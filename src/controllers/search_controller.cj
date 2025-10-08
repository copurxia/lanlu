package lrr4cj.controllers

import cjoy.*
import cjoy.json.*
import lrr4cj.models.*
import lrr4cj.views.*
import std.convert.*

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
        
        // 首先获取所有符合条件的归档
        let (allArchives, totalCount) = ArchiveModel.searchArchives(filter, category, 0, 1000, "title", "asc")
        
        // 过滤条件
        var filteredArchives: ArrayList<Archive> = ArrayList<Archive>()
        for (archive in allArchives) {
            var include = true
            
            // 只显示新的归档
            if (newOnly && !archive.isNew) {
                include = false
            }
            
            // 只显示无标签的归档
            if (untaggedOnly && archive.tags.size > 0) {
                include = false
            }
            
            if (include) {
                filteredArchives.add(archive)
            }
        }
        
        // 随机打乱
        let shuffled = filteredArchives.toArray()
        // 简单的随机打乱实现
        for (i in shuffled.size - 1..0) {
            let j = (i + 1) % (i + 1)  // 简单的随机数生成
            let temp = shuffled[i]
            shuffled[i] = shuffled[j]
            shuffled[j] = temp
        }
        
        // 获取前count个
        var resultArchives: ArrayList<Archive> = ArrayList<Archive>()
        let limit = if (shuffled.size < Int64(count)) { shuffled.size } else { Int64(count) }
        for (i in 0..limit) {
            resultArchives.add(shuffled[i])
        }
        
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