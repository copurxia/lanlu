package lanlu.contexts.task.application.runners

import std.io.*
import std.io.{ByteBuffer, readToEnd}
import stdx.encoding.json.stream.*
import std.convert.*
import std.fs.*
import lanlu.contexts.task.domain.*
import lanlu.shared.utils.*
import lanlu.contexts.asset.infrastructure.persistence.*
import lanlu.contexts.plugin.application.*

/**
 * plugin_asset_consume：消费 staging asset，校验插件元信息后落盘并写入插件数据库。
 */
public class PluginAssetConsumeTaskRunner {
    public static func run(taskId: Int64, parameters: String, context: TaskRunnerContext): Unit {
        TaskIO.appendLog(taskId, "plugin_asset_consume task started")

        let stagingAssetId = parseInt64Safely(parseField(parameters, "staging_asset_id"))
        let targetType = parseField(parameters, "target_type").trimAscii().toAsciiLower()
        let originalFilenameRaw = parseField(parameters, "filename")

        if (stagingAssetId <= 0) {
            fail(taskId, "staging_asset_id is required")
            return
        }
        if (targetType != "plugin") {
            fail(taskId, "target_type must be plugin")
            return
        }

        let staging = AssetDao.getById(stagingAssetId)
        if (staging.id <= 0) {
            fail(taskId, "staging asset not found")
            return
        }

        let ext = resolveAssetExt(staging, originalFilenameRaw)
        let assetRoot = context.paths.assetPath
        let stagingPath = FileUtils.joinPath(assetRoot, "${stagingAssetId}.${ext}")
        if (!exists(Path(stagingPath))) {
            let _ = AssetDao.deleteById(stagingAssetId)
            fail(taskId, "staging asset file missing")
            return
        }

        let originalFilename = if (originalFilenameRaw.trimAscii().size > 0) { originalFilenameRaw.trimAscii() } else { staging.originalFilename }
        if (!originalFilename.toAsciiLower().endsWith(".wasm")) {
            cleanupStagingAsset(assetRoot, stagingAssetId, ext)
            fail(taskId, "uploaded file must be a .wasm plugin")
            return
        }

        TaskModel.updateTaskProgress(taskId, 60, "解析插件元信息")
        let installResult = PluginManagerService.installFromUploadedFile(stagingPath, originalFilename)

        // installFromUploadedFile 成功时会移动文件，失败时尽量删除临时文件并清理记录
        cleanupStagingAsset(assetRoot, stagingAssetId, ext)

        if (!installResult.success) {
            fail(taskId, installResult.message)
            return
        }

        let out = ByteBuffer()
        let w = JsonWriter(out)
        w.startObject()
        w.writeName("success").writeValue(1)
        w.writeName("namespace").writeValue(installResult.namespace)
        w.writeName("plugin_type").writeValue(installResult.plugin_type)
        w.writeName("filename").writeValue(installResult.filename)
        w.writeName("old_version").writeValue(installResult.old_version)
        w.writeName("new_version").writeValue(installResult.new_version)
        w.writeName("clear_parameters").writeValue(installResult.clear_parameters)
        w.writeName("reason").writeValue(installResult.reason)
        w.writeName("scan_task_id").writeValue(installResult.scan_task_id)
        w.endObject()
        w.flush()
        let okJson = String.fromUtf8(readToEnd(out))

        TaskModel.updateTaskProgress(taskId, 100, "插件已上传并进入扫描")
        TaskModel.completeTask(taskId, "plugin_asset_consume completed")
        TaskIO.writeOutput(taskId, okJson)
        TaskIO.appendLog(taskId, "plugin_asset_consume completed: namespace=${installResult.namespace} scan_task=${installResult.scan_task_id.toString()}")
    }

    private static func parseField(parameters: String, key: String): String {
        let trimmed = parameters.trimAscii()
        if (trimmed.size == 0) {
            return ""
        }
        try {
            var buf = ByteBuffer()
            unsafe { buf.write(trimmed.rawData()) }
            let r = JsonReader(buf)
            if (r.peek() != Some(BeginObject)) { return "" }
            r.startObject()
            while (r.peek() != EndObject) {
                let k = r.readName()
                if (k == key) {
                    return r.readValue<String>().trimAscii()
                } else {
                    r.skip()
                }
            }
            r.endObject()
        } catch (_: Exception) {}
        return ""
    }

    private static func parseInt64Safely(value: String): Int64 {
        if (value.size == 0) {
            return 0
        }
        try {
            return Int64.parse(value)
        } catch (_: Exception) {
            return 0
        }
    }

    private static func resolveAssetExt(asset: AssetRow, filename: String): String {
        if (asset.fileExt.trimAscii().size > 0) {
            return asset.fileExt.trimAscii().toAsciiLower()
        }
        let ext = FileUtils.getFileExtensionWithoutDot(filename).trimAscii().toAsciiLower()
        if (ext.size > 0) {
            return ext
        }
        return "bin"
    }

    private static func cleanupStagingAsset(assetRoot: String, assetId: Int64, extHint: String): Unit {
        if (assetId <= 0) {
            return
        }
        let row = AssetDao.getById(assetId)
        let ext = if (extHint.size > 0) { extHint }
            else if (row.fileExt.trimAscii().size > 0) { row.fileExt.trimAscii().toAsciiLower() }
            else { "bin" }
        let path = FileUtils.joinPath(assetRoot, "${assetId}.${ext}")
        try {
            if (exists(Path(path))) {
                try { remove(Path(path)) } catch (_: Exception) {}
            }
        } catch (_: Exception) {}
        let _ = AssetDao.deleteById(assetId)
    }

    private static func fail(taskId: Int64, message: String): Unit {
        TaskRunnerOutput.fail(taskId, message)
    }
}
