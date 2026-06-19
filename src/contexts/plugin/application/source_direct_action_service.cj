package lanlu.contexts.plugin.application

import std.io.{ByteBuffer, readToEnd}
import std.sync.*
import std.time.*
import stdx.encoding.json.stream.*

/**
 * 直连 Source action 的最大并发数。
 * 每个 action 会启动一个 WASM 实例，过多并发会导致内存/CPU 压力。
 */
private let MAX_CONCURRENT_DIRECT_ACTIONS: Int64 = 4
private let DIRECT_ACTION_WAIT_TIMEOUT_MS: Int64 = 5000
private let DIRECT_ACTION_WAIT_INTERVAL_MS: Int64 = 50
private let directActionActiveCount = AtomicInt64(0)

public class SourceDirectActionService {
    /**
     * Source 插件支持的 browse action 列表。
     * 每个 action 会直接启动一个 WASM 实例执行（受并发限流控制）。
     *
     * Action 说明：
     * - source_home: 获取首页内容
     * - source_search: 搜索
     * - source_filters: 获取过滤器列表
     * - source_detail: 获取条目详情
     * - source_reader: 获取页面列表，输出 data.pages[].path 作为页面资源 key
     * - source_cover_asset: 获取封面资源
     * - source_page_asset: 获取页面资源，输入 path（必填，来自 source_reader 输出的 pages[].path）、page（可选 hint）
     */
    private static let BROWSE_ACTIONS = [
        // 已废弃 action（向后兼容过渡期保留）：
        // - source_detail       → Metadata 插件的 resolve_metadata
        // - source_reader       → 从 Metadata 插件的 children 派生
        // - source_cover_asset  → Metadata 插件的 resolve_metadata 返回 cover_asset_id
        // - source_page_asset   → Download 插件的 resolve_page_asset
        // 待所有插件迁移完成后移除。
        "source_home",
        "source_search",
        "source_filters",
        "source_detail",
        "source_reader",
        "source_cover_asset",
        "source_page_asset"
    ]

    public static func isBrowseAction(action: String): Bool {
        let trimmed = action.trimAscii()
        for (a in BROWSE_ACTIONS) {
            if (a == trimmed) { return true }
        }
        return false
    }

    private static func buildDirectGroupId(namespace: String, action: String): String {
        let safeNamespace = namespace.trimAscii().replace("/", "_").replace("\\", "_").replace(" ", "_")
        let safeAction = action.trimAscii().replace("/", "_").replace("\\", "_").replace(" ", "_")
        return "source_direct:${safeNamespace}:${safeAction}:${DateTime.now().toUnixTimeStamp().toSeconds()}"
    }

    private static func nowMillis(): Int64 {
        return DateTime.now().toUnixTimeStamp().toMilliseconds()
    }

    private static func acquireDirectActionSlot(): Bool {
        let deadline = nowMillis() + DIRECT_ACTION_WAIT_TIMEOUT_MS
        while (true) {
            let currentActive = directActionActiveCount.fetchAdd(1)
            if (currentActive < MAX_CONCURRENT_DIRECT_ACTIONS) {
                return true
            }
            directActionActiveCount.fetchSub(1)
            if (nowMillis() >= deadline) {
                return false
            }
            sleep(Duration.millisecond * DIRECT_ACTION_WAIT_INTERVAL_MS)
        }
        return false
    }

    public static func execute(
        namespace: String,
        action: String,
        request: SourceRequest
    ): String {
        let effectiveAction = action.trimAscii()
        if (!isBrowseAction(effectiveAction)) {
            return errorJson("Not a browse action: ${effectiveAction}")
        }

        // 并发保护：短暂等待槽位，避免懒加载突发请求直接打到用户侧错误。
        if (!acquireDirectActionSlot()) {
            return errorJson("Too many concurrent direct source actions (max ${MAX_CONCURRENT_DIRECT_ACTIONS.toString()}), try again later")
        }

        var shouldRelease = true
        try {
            match (SourceRequestResolver.validatePlugin(request)) {
                case Some(plugin) =>
                    let groupId = buildDirectGroupId(namespace, effectiveAction)
                    let result = PluginExecutionService.executeSourceBrowseAction(
                        plugin,
                        effectiveAction,
                        request.paramsJson,
                        0,
                        0,
                        groupId
                    )

                    directActionActiveCount.fetchSub(1)
                    shouldRelease = false

                    if (!result.success) {
                        return errorJson(result.error)
                    }

                    return wrapJson(result.output)
                case None =>
                    directActionActiveCount.fetchSub(1)
                    shouldRelease = false
                    return errorJson("Source plugin not found or disabled: ${namespace}")
            }
        } catch (e: Exception) {
            if (shouldRelease) {
                directActionActiveCount.fetchSub(1)
            }
            return errorJson(e.message)
        }
    }

    private static func errorJson(error: String): String {
        let out = ByteBuffer()
        let w = JsonWriter(out)
        w.startObject()
        w.writeName("success").writeValue(false)
        w.writeName("error").writeValue(error)
        w.endObject()
        w.flush()
        return String.fromUtf8(readToEnd(out))
    }

    private static func wrapJson(rawOutput: String): String {
        let trimmed = rawOutput.trimAscii()
        if (trimmed.size == 0) {
            let out = ByteBuffer()
            let w = JsonWriter(out)
            w.startObject()
            w.writeName("success").writeValue(true)
            w.writeName("data")
            w.startObject()
            w.endObject()
            w.endObject()
            w.flush()
            return String.fromUtf8(readToEnd(out))
        }

        try {
            var buf = ByteBuffer()
            unsafe { buf.write(trimmed.rawData()) }
            let r = JsonReader(buf)
            if (r.peek() == Some(BeginObject)) {
                r.startObject()
                var hasSuccess = false
                while (r.peek() != EndObject) {
                    let name = r.readName()
                    if (name == "success" || name == "data" || name == "error") {
                        hasSuccess = true
                    }
                    r.skip()
                }
                r.endObject()
                if (hasSuccess) {
                    return trimmed
                }
            }
        } catch (_: Exception) {}

        let out = ByteBuffer()
        let w = JsonWriter(out)
        w.startObject()
        w.writeName("success").writeValue(true)
        w.writeName("data").jsonValue(trimmed)
        w.endObject()
        w.flush()
        return String.fromUtf8(readToEnd(out))
    }
}