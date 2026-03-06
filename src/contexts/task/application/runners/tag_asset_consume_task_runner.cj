package lanlu.contexts.task.application.runners

import stdx.log.*
import std.io.*
import std.io.{ByteBuffer, readToEnd}
import stdx.encoding.json.stream.*
import std.convert.*
import std.fs.*
import std.time.*
import lanlu.contexts.task.domain.*
import lanlu.shared.utils.*
import lanlu.contexts.asset.infrastructure.persistence.*
import lanlu.contexts.tag.infrastructure.persistence.*
import lanlu.contexts.user.infrastructure.persistence.*

/**
 * tag_asset_consume：消费 staging asset，转为标签图标/背景资产并更新 tag。
 */
public class TagAssetConsumeTaskRunner {
    public static func run(taskId: Int64, parameters: String, context: TaskRunnerContext): Unit {
        TaskIO.appendLog(taskId, "tag_asset_consume task started")

        let stagingAssetId = parseInt64Safely(parseField(parameters, "staging_asset_id"))
        let targetType = parseField(parameters, "target_type").trimAscii().toAsciiLower()
        let targetId = parseInt64Safely(parseField(parameters, "target_id"))
        let uploadUserId = parseInt64Safely(parseField(parameters, "upload_user_id"))
        let originalFilename = parseField(parameters, "filename")

        if (stagingAssetId <= 0) {
            fail(taskId, "staging_asset_id is required")
            return
        }
        if (targetType != "tag_icon" && targetType != "tag_background") {
            fail(taskId, "target_type must be tag_icon or tag_background")
            return
        }
        if (targetId <= 0) {
            cleanupStagingAsset(context.paths.assetPath, stagingAssetId, "")
            fail(taskId, "target_id(tag id) is required")
            return
        }
        if (uploadUserId <= 0 || !UserDao.isAdmin(uploadUserId)) {
            cleanupStagingAsset(context.paths.assetPath, stagingAssetId, "")
            fail(taskId, "admin permission required")
            return
        }

        let tagOpt = TagDao.getById(targetId)
        if (tagOpt.isNone()) {
            cleanupStagingAsset(context.paths.assetPath, stagingAssetId, "")
            fail(taskId, "tag not found")
            return
        }
        let tag = tagOpt.getOrThrow()

        let staging = AssetDao.getById(stagingAssetId)
        if (staging.id <= 0) {
            fail(taskId, "staging asset not found")
            return
        }

        let stagingExt = resolveAssetExt(staging, originalFilename)
        let assetRoot = context.paths.assetPath
        let stagingPath = FileUtils.joinPath(assetRoot, "${stagingAssetId}.${stagingExt}")
        if (!exists(Path(stagingPath))) {
            let _ = AssetDao.deleteById(stagingAssetId)
            fail(taskId, "staging asset file missing")
            return
        }

        let cacheRoot = context.paths.cachePath
        FileUtils.ensureDirectoryExists(Path(cacheRoot))
        FileUtils.ensureDirectoryExists(Path(assetRoot))
        let ts = DateTime.now().toUnixTimeStamp().toSeconds()
        let tempDir = FileUtils.joinPath(cacheRoot, "tag_asset_consume/${targetId.toString()}_${ts.toString()}_${taskId.toString()}")
        FileUtils.ensureDirectoryExists(Path(tempDir))

        let outputAvifPath = if (targetType == "tag_icon") {
            FileUtils.joinPath(tempDir, "icon.avif")
        } else {
            FileUtils.joinPath(tempDir, "background.avif")
        }

        TaskModel.updateTaskProgress(taskId, 60, "转换标签资源")
        let (convertRes, thumbHashFromConvert) = if (targetType == "tag_icon") {
            ArchiveUtils.convertAvatarToAvifWithThumbHash(stagingPath, outputAvifPath, tempDir)
        } else {
            ArchiveUtils.convertTagBackgroundToAvifWithThumbHash(stagingPath, outputAvifPath, tempDir)
        }

        if (!convertRes.success) {
            let _ = FileUtils.removeFileOrDirectory(tempDir)
            cleanupStagingAsset(assetRoot, stagingAssetId, stagingExt)
            fail(taskId, "${targetType} conversion failed")
            return
        }

        let thumbHash = if (thumbHashFromConvert.size > 0) { thumbHashFromConvert }
            else { try { ThumbHashUtils.calculateAvifThumbHashFromFile(outputAvifPath) } catch (_: Exception) { "" } }
        let byteSize = try { Int64(FileInfo(Path(outputAvifPath)).size) } catch (_: Exception) { 0 }

        let assetKind = if (targetType == "tag_icon") { "tag_icon" } else { "tag_background" }
        let newAssetIdOpt = AssetDao.create(Some(uploadUserId), assetKind, originalFilename, "image/avif", "avif", byteSize, thumbHash)
        let newAssetId = match (newAssetIdOpt) {
            case Some(id) => id
            case None =>
                let _ = FileUtils.removeFileOrDirectory(tempDir)
                cleanupStagingAsset(assetRoot, stagingAssetId, stagingExt)
                fail(taskId, "failed to create target asset")
                return
        }

        let finalPath = FileUtils.joinPath(assetRoot, "${newAssetId}.avif")
        try {
            FileUtils.safeReplaceFile(Path(finalPath), Path(outputAvifPath))
        } catch (e: Exception) {
            let _ = AssetDao.deleteById(newAssetId)
            let _ = FileUtils.removeFileOrDirectory(tempDir)
            cleanupStagingAsset(assetRoot, stagingAssetId, stagingExt)
            fail(taskId, "failed to store converted asset: ${e.message}")
            return
        }

        let oldAssetId = if (targetType == "tag_icon") { tag.iconAssetId } else { tag.backgroundAssetId }
        let updated = if (targetType == "tag_icon") {
            TagDao.updateIconAssetId(targetId, newAssetId)
        } else {
            TagDao.updateBackgroundAssetId(targetId, newAssetId)
        }

        if (!updated) {
            try { remove(Path(finalPath)) } catch (_: Exception) {}
            let _ = AssetDao.deleteById(newAssetId)
            let _ = FileUtils.removeFileOrDirectory(tempDir)
            cleanupStagingAsset(assetRoot, stagingAssetId, stagingExt)
            fail(taskId, "failed to update tag asset")
            return
        }

        if (oldAssetId > 0 && oldAssetId != newAssetId) {
            try {
                let oldPath = FileUtils.joinPath(assetRoot, "${oldAssetId}.avif")
                try { remove(Path(oldPath)) } catch (_: Exception) {}
            } catch (_: Exception) {}
            let _ = AssetDao.deleteById(oldAssetId)
        }

        let _ = FileUtils.removeFileOrDirectory(tempDir)
        cleanupStagingAsset(assetRoot, stagingAssetId, stagingExt)

        let out = ByteBuffer()
        let w = JsonWriter(out)
        w.startObject()
        w.writeName("success").writeValue(1)
        if (targetType == "tag_icon") {
            w.writeName("iconAssetId").writeValue(newAssetId)
        } else {
            w.writeName("backgroundAssetId").writeValue(newAssetId)
        }
        w.writeName("assetId").writeValue(newAssetId)
        w.endObject()
        w.flush()
        let okJson = String.fromUtf8(readToEnd(out))

        TaskModel.updateTaskProgress(taskId, 100, "标签资源更新完成")
        TaskModel.completeTask(taskId, "tag_asset_consume completed")
        TaskIO.writeOutput(taskId, okJson)
        TaskIO.appendLog(taskId, "tag_asset_consume completed: tag=${targetId.toString()} asset=${newAssetId.toString()}")
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
