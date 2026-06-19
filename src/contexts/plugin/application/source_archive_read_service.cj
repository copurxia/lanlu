package lanlu.contexts.plugin.application

import std.collection.*
import std.convert.*
import std.io.{ByteBuffer, readToEnd}
import stdx.encoding.json.stream.*

/**
 * Source 档案读取服务（新架构）。
 *
 * 职责边界：
 * - Metadata 插件负责解析 source 的统一 metadata（含 page children）
 * - Download 插件负责单页资源解析
 *
 * 不再依赖 Source 插件的 source_detail / source_reader / source_page_asset action。
 *
 * 页面定位只使用 path，不再传 page 参数，不再支持 asset_ref。
 * children 中 entity_type=page 的条目带 path 字段用于页面资源定位。
 */
public class SourceDetailResult {
    public var title: String = ""
    public var description: String = ""
    public var tags: Array<String> = Array<String>()
    public var pageCount: Int64 = 0
    public var coverAssetId: Int64 = 0
    public var mediaType: String = "image"
    public var children: Array<SourceChildItem> = Array<SourceChildItem>()
    public var capabilities: Array<String> = Array<String>()
    public var errorMessage: String = ""
    public func hasError(): Bool { errorMessage.size > 0 }
}

public class SourceChildItem {
    public var entityType: String = ""     // "archive" | "page"
    public var sourceNamespace: String = ""
    public var remoteId: String = ""       // entity_id 如 "source:ns:id" 或 "source:ns:id#page:1"
    public var title: String = ""
    public var description: String = ""
    public var tags: Array<String> = Array<String>()
    public var path: String = ""           // 页面资源 key（仅 entity_type=page 时有值）
    public var mediaType: String = "image"
    public var sortOrder: Int64 = 0
}

public class SourcePageItem {
    public var path: String = ""
    public var assetId: Int64 = 0
}

public class SourcePagesResult {
    public var pages: Array<SourcePageItem> = Array<SourcePageItem>()
    public var errorMessage: String = ""
    public func hasError(): Bool { errorMessage.size > 0 }
}

public class SourceArchiveReadService {

    /**
     * 通过 Metadata 插件解析 source 详情。
     *
     * @param sourceId 完整 sourceId 如 "source:ehentaisource:123/token"
     */
    public static func fetchDetail(sourceId: String): SourceDetailResult {
        let result = SourceDetailResult()

        // 1. 执行 Metadata 插件获取统一 metadata
        let metadataJson = SourcePluginExecutionService.resolveMetadata(sourceId)
        if (metadataJson.trimAscii().size == 0) {
            result.errorMessage = "Metadata plugin returned empty response for ${sourceId}"
            return result
        }

        // 2. 解析 metadata JSON → SourceDetailResult
        try {
            return parseMetadataResponse(metadataJson)
        } catch (e: Exception) {
            result.errorMessage = "Failed to parse metadata response: ${e.message}"
            return result
        }
    }

    /**
     * 从 Metadata 插件的输出中提取页面列表。
     * 页面数据来源于 metadata.children[] 中 entity_type=page 的条目。
     *
     * @param sourceId 完整 sourceId
     */
    public static func fetchPages(sourceId: String): SourcePagesResult {
        let detail = fetchDetail(sourceId)
        if (detail.hasError()) {
            let result = SourcePagesResult()
            result.errorMessage = detail.errorMessage
            return result
        }

        let result = SourcePagesResult()
        let pages = ArrayList<SourcePageItem>()

        for (child in detail.children) {
            if (child.entityType == "page") {
                let page = SourcePageItem()
                page.path = child.path
                page.assetId = 0
                pages.add(page)
            }
        }

        result.pages = pages.toArray()
        return result
    }

    /**
     * 通过 Download 插件解析 source 单页资源。
     *
     * @param namespace source 命名空间
     * @param remoteId 远端 ID
     * @param path 页面定位 key（由 Metadata 插件的 children[].path 提供）
     * @return 结果含 asset_id (>0 成功) 和错误信息
     */
    public static func resolvePageAsset(
        namespace: String,
        remoteId: String,
        path: String
    ): PageAssetResult {
        let errorResult = PageAssetResult()

        if (namespace.trimAscii().size == 0 || remoteId.trimAscii().size == 0 || path.trimAscii().size == 0) {
            errorResult.errorMessage = "invalid parameters: namespace/remoteId/path"
            return errorResult
        }

        let sourceId = "source:${namespace}:${remoteId}"
        return SourcePluginExecutionService.resolvePageAsset(sourceId, path)
    }

    // ─── Metadata JSON 解析 ───

    /**
     * 解析 Metadata 插件返回的统一 metadata JSON。
     *
     * 期望格式：
     * ```json
     * {
     *   "success": true,
     *   "data": {
     *     "title": "...",
     *     "description": "...",
     *     "tags": [],
     *     "cover_asset_id": 123,
     *     "media_type": "image",
     *     "page_count": 10,
     *     "children": [
     *       { "entity_type": "page", "entity_id": "...", "title": "...", "path": "...", "media_type": "image" }
     *     ]
     *   }
     * }
     * ```
     */
    private static func parseMetadataResponse(json: String): SourceDetailResult {
        var buf = ByteBuffer()
        unsafe { buf.write(json.rawData()) }
        let r = JsonReader(buf)

        if (r.peek() != Some(BeginObject)) {
            let result = SourceDetailResult()
            result.errorMessage = "Metadata response is not a JSON object"
            return result
        }

        var dataRaw: Option<String> = None
        var success = true
        var errorMessage = ""

        r.startObject()
        while (r.peek() != EndObject) {
            let name = r.readName()
            if (name == "success") {
                success = r.readValue<Bool>()
            } else if (name == "error") {
                errorMessage = r.readValue<String>()
            } else if (name == "data") {
                let bytes = r.readValueBytes()
                dataRaw = Some(String.fromUtf8(bytes))
            } else {
                r.skip()
            }
        }
        r.endObject()

        if (!success) {
            let result = SourceDetailResult()
            result.errorMessage = if (errorMessage.trimAscii().size > 0) {
                errorMessage
            } else {
                "Metadata plugin returned success=false"
            }
            return result
        }

        match (dataRaw) {
            case Some(dataJson) =>
                let result = SourceDetailResult()
                parseDetailDataFields(dataJson, result)
                return result
            case None =>
                let result = SourceDetailResult()
                result.errorMessage = "Metadata response missing data"
                return result
        }
    }

    private static func parseDetailDataFields(dataJson: String, result: SourceDetailResult): Unit {
        var buf = ByteBuffer()
        unsafe { buf.write(dataJson.rawData()) }
        let r = JsonReader(buf)

        if (r.peek() != Some(BeginObject)) {
            return
        }

        var childrenRaw: Option<String> = None

        r.startObject()
        while (r.peek() != EndObject) {
            let name = r.readName()
            if (name == "title") {
                result.title = r.readValue<String>()
            } else if (name == "description") {
                result.description = r.readValue<String>()
            } else if (name == "tags") {
                result.tags = parseStringArray(r)
            } else if (name == "page_count") {
                result.pageCount = parsePageCountValue(r)
            } else if (name == "cover_asset_id") {
                result.coverAssetId = readPositiveInt64(r)
            } else if (name == "media_type") {
                result.mediaType = r.readValue<String>()
            } else if (name == "children") {
                let bytes = r.readValueBytes()
                childrenRaw = Some(String.fromUtf8(bytes))
            } else {
                r.skip()
            }
        }
        r.endObject()

        // 解析 children
        match (childrenRaw) {
            case Some(childrenJson) =>
                result.children = parseChildrenArrayRaw(childrenJson)
                // 从 children 中统计 page 数量
                var pageCount: Int64 = 0
                var hasPageChildren = false
                for (child in result.children) {
                    if (child.entityType == "page") {
                        pageCount += 1
                        hasPageChildren = true
                    }
                }
                if (hasPageChildren && result.pageCount <= 0) {
                    result.pageCount = pageCount
                }
            case None => ()
        }
    }

    private static func parseChildrenArrayRaw(childrenJson: String): Array<SourceChildItem> {
        var buf = ByteBuffer()
        unsafe { buf.write(childrenJson.rawData()) }
        let r = JsonReader(buf)

        if (r.peek() != Some(BeginArray)) {
            return Array<SourceChildItem>()
        }

        let children = ArrayList<SourceChildItem>()
        r.startArray()
        while (r.peek() != EndArray) {
            if (r.peek() != Some(BeginObject)) {
                r.skip()
                continue
            }
            let child = parseSingleChildFromMetadata(r)
            children.add(child)
        }
        r.endArray()
        return children.toArray()
    }

    /**
     * 解析统一 metadata 的 child 条目。
     *
     * 输入格式：
     * ```json
     * {
     *   "entity_type": "archive|page",
     *   "entity_id": "source:ns:id",
     *   "title": "...",
     *   "sort_order": 1,
     *   "path": "opaque-page-key",
     *   "media_type": "image",
     *   "tags": ["tag1", "tag2"]
     * }
     * ```
     */
    private static func parseSingleChildFromMetadata(r: JsonReader): SourceChildItem {
        let child = SourceChildItem()
        r.startObject()
        while (r.peek() != EndObject) {
            let name = r.readName()
            if (name == "entity_type") {
                child.entityType = r.readValue<String>()
            } else if (name == "entity_id") {
                child.remoteId = r.readValue<String>()
            } else if (name == "title") {
                child.title = r.readValue<String>()
            } else if (name == "path") {
                child.path = r.readValue<String>()
            } else if (name == "media_type") {
                child.mediaType = r.readValue<String>()
            } else if (name == "sort_order") {
                child.sortOrder = r.readValue<Int64>()
            } else if (name == "description") {
                child.description = r.readValue<String>()
            } else if (name == "tags") {
                child.tags = parseStringArray(r)
            } else {
                r.skip()
            }
        }
        r.endObject()

        // 从 entity_id 提取 sourceNamespace
        if (child.remoteId.startsWith("source:")) {
            let parts = child.remoteId.split(":")
            if (parts.size >= 3) {
                child.sourceNamespace = parts[1]
            }
        }

        return child
    }

    // ─── 解析辅助方法 ───

    private static func parsePageCountValue(r: JsonReader): Int64 {
        try {
            return r.readValue<Int64>()
        } catch (_: Exception) {
            try {
                let pf = r.readValue<Float64>()
                let intVal = Int64(pf)
                return if (intVal > 0) { intVal } else { 0 }
            } catch (_: Exception) {
                r.skip()
                return 0
            }
        }
    }

    private static func parseStringArray(r: JsonReader): Array<String> {
        if (r.peek() != Some(BeginArray)) {
            r.skip()
            return Array<String>()
        }
        let items = ArrayList<String>()
        r.startArray()
        while (r.peek() != EndArray) {
            match (r.peek()) {
                case Some(_) =>
                    let val = r.readValue<String>().trimAscii()
                    if (val.size > 0) {
                        items.add(val)
                    }
                case None => break
            }
        }
        r.endArray()
        return items.toArray()
    }

    private static func readPositiveInt64(r: JsonReader): Int64 {
        try {
            let v = r.readValue<Int64>()
            return if (v > 0) { v } else { 0 }
        } catch (_: Exception) {
            try {
                let s = r.readValue<String>().trimAscii()
                if (s.size == 0) { return 0 }
                let parsed = Int64.parse(s)
                return if (parsed > 0) { parsed } else { 0 }
            } catch (_: Exception) {
                r.skip()
                return 0
            }
        }
    }
}
