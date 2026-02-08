package lanlu.task_runners

import std.convert.*
import std.time.*
import std.io.*
import std.io.{ByteBuffer, readToEnd}
import stdx.encoding.json.stream.*
import std.collection.*
import lanlu.dao.*
import lanlu.models.*
import lanlu.utils.*

/**
 * metadata_plugin_callback 回调任务执行器
 * 在 deno_task 完成后被触发，负责读取插件输出并写回元数据
 */
public class MetadataPluginCallbackRunner {
    public static func run(taskId: Int64, parameters: String, context: TaskRunnerContext): Unit {
        TaskIO.appendLog(taskId, "metadata_plugin_callback task started")
        TaskModel.updateTaskProgress(taskId, 10, "开始处理元数据回调")

        // 解析参数
        let (targetType, targetId, namespace, denoTaskId, param, fallbackNamespaces) = parseParameters(parameters)
        if (targetId.size == 0 || denoTaskId <= 0) {
            fail(taskId, "Invalid callback parameters: missing targetId or denoTaskId")
            return
        }

        TaskIO.appendLog(taskId, "callback params: targetType=${targetType}, targetId=${targetId}, namespace=${namespace}, denoTaskId=${denoTaskId}")

        // 读取 deno_task 输出
        TaskModel.updateTaskProgress(taskId, 30, "读取插件输出")
        let output = TaskIO.readOutput(denoTaskId)
        if (output.size == 0) {
            failAndMaybeEnqueueFallback(taskId, "Deno task output is empty", targetType, targetId, param, fallbackNamespaces, context.notifyTaskAvailable)
            return
        }
        TaskIO.appendLog(taskId, "plugin output: ${output}")

        // 解析元数据输出
        TaskModel.updateTaskProgress(taskId, 50, "解析元数据")
        let parsed = parseMetadataOutput(output)
        if (!parsed.success) {
            failAndMaybeEnqueueFallback(taskId, parsed.error, targetType, targetId, param, fallbackNamespaces, context.notifyTaskAvailable)
            return
        }

        let newTitle = parsed.title
        var newTags = parsed.tags
        let newSummary = parsed.summary
        let newCover = parsed.cover
        let archivePatches = parsed.archives
        let archivesProvided = parsed.archivesProvided
        // Some metadata plugins may emit a pseudo-tag like `updated_at:<unix_seconds>`.
        // Map it to archives.updated_at and prevent it from being stored as a normal tag.
        let (pluginUpdatedAt, cleanedTags) = extractUpdatedAtFromTags(newTags)
        newTags = cleanedTags

        let effectiveType = targetType.trimAscii().toAsciiLower()
        TaskModel.updateTaskProgress(taskId, 70, "写回元数据")

        if (effectiveType == "tankoubon" || effectiveType == "tank") {
            // Write back to Tankoubon (name/summary/tankoubon_tags).
            match (TankoubonDao.getTankoubonById(targetId)) {
                case None =>
                    failAndMaybeEnqueueFallback(taskId, "Tankoubon not found when updating", effectiveType, targetId, param, fallbackNamespaces, context.notifyTaskAvailable)
                    return
                case Some(existing) =>
                    let updatedName = if (newTitle.size > 0) { newTitle } else { existing.name }
                    let updatedSummary = if (newSummary.size > 0) { newSummary } else { existing.summary }

                    let ok = TankoubonDao.updateTankoubon(targetId, updatedName, updatedSummary)
                    if (!ok) {
                        failAndMaybeEnqueueFallback(taskId, "Failed to update tankoubon metadata", effectiveType, targetId, param, fallbackNamespaces, context.notifyTaskAvailable)
                        return
                    }
                    if (newTags.size > 0 || parsed.tags.trimAscii().size == 0) {
                        // If plugin emits tags (non-empty) update; if plugin emits empty, treat as no-op.
                        if (newTags.size > 0) {
                            let _ = TankoubonDao.updateTankoubonTags(targetId, newTags)
                        }
                    }

                    if (newCover.trimAscii().size > 0) {
                        let oldCoverAssetId = TankoubonDao.getTankoubonCoverAssetId(targetId)
                        let (okCover, coverAssetId, _, coverErr) = PluginCoverUtils.installCoverAssetFromPluginPath(
                            newCover,
                            namespace,
                            "tankoubon_cover",
                            "${targetId}.avif"
                        )
                        if (okCover && coverAssetId > 0) {
                            let coverUpdated = TankoubonDao.updateTankoubonCover(targetId, coverAssetId)
                            if (coverUpdated) {
                                if (oldCoverAssetId > 0 && oldCoverAssetId != coverAssetId) {
                                    PluginCoverUtils.deleteAsset(oldCoverAssetId)
                                }
                            } else {
                                PluginCoverUtils.deleteAsset(coverAssetId)
                                TaskIO.appendLog(taskId, "WARN: failed to apply tankoubon cover asset, removed new asset id=${coverAssetId}")
                            }
                        } else {
                            TaskIO.appendLog(taskId, "WARN: failed to install tankoubon cover from plugin result: ${coverErr}")
                        }
                    }

                    // Optional: plugin can return per-archive metadata patches for this Tankoubon.
                    let (patchedCount, skippedCount) = applyArchivePatchesForTankoubon(targetId, archivePatches, taskId, namespace, archivesProvided, context.notifyTaskAvailable)
                    TaskIO.appendLog(taskId, "archive patches applied: patched=${patchedCount}, skipped=${skippedCount}")
            }
        } else {
            // Default: archive write-back.
            var archiveToUpdate = ArchiveDao.getArchiveById(targetId)
            if (archiveToUpdate.id.size == 0) {
                failAndMaybeEnqueueFallback(taskId, "Archive not found when updating", effectiveType, targetId, param, fallbackNamespaces, context.notifyTaskAvailable)
                return
            }

            var changed = false
            if (newTitle.size > 0) {
                archiveToUpdate.title = newTitle
                changed = true
            }
            if (newSummary.size > 0) {
                archiveToUpdate.summary = newSummary
                changed = true
            }
            if (newTags.size > 0) { changed = true }
            if (pluginUpdatedAt.size > 0) {
                archiveToUpdate.updated_at = pluginUpdatedAt
                changed = true
            }
            if (changed) {
                let ok = ArchiveDao.update(archiveToUpdate)
                if (!ok) {
                    failAndMaybeEnqueueFallback(taskId, "Failed to update archive metadata", effectiveType, targetId, param, fallbackNamespaces, context.notifyTaskAvailable)
                    return
                }
            }

            if (newTags.size > 0) {
                let tagOk = TagDao.updateArchiveTags(targetId, newTags)
                if (!tagOk) {
                    TaskIO.appendLog(taskId, "WARN: failed to update tags")
                }
            }

            if (newCover.trimAscii().size > 0) {
                let oldCoverAssetId = ArchiveDao.getCoverAssetId(targetId)
                let (okCover, coverAssetId, coverThumbHash, coverErr) = PluginCoverUtils.installCoverAssetFromPluginPath(
                    newCover,
                    namespace,
                    "archive_cover",
                    "${targetId}.avif"
                )
                if (okCover && coverAssetId > 0) {
                    let coverUpdated = ArchiveDao.updateCoverAssetId(targetId, coverAssetId)
                    if (coverUpdated) {
                        if (coverThumbHash.trimAscii().size > 0) {
                            let _ = ArchiveDao.updateThumbHash(targetId, coverThumbHash)
                        }
                        if (oldCoverAssetId > 0 && oldCoverAssetId != coverAssetId) {
                            PluginCoverUtils.deleteAsset(oldCoverAssetId)
                        }
                    } else {
                        PluginCoverUtils.deleteAsset(coverAssetId)
                        TaskIO.appendLog(taskId, "WARN: failed to apply archive cover asset, removed new asset id=${coverAssetId}")
                    }
                } else {
                    TaskIO.appendLog(taskId, "WARN: failed to install archive cover from plugin result: ${coverErr}")
                }
            }
        }

        // 完成任务
        TaskModel.updateTaskProgress(taskId, 100, "元数据回调完成")
        let resultJson = buildResultJson(targetId, namespace, newTitle, newSummary, newTags, newCover, output, archivePatches.size)
        TaskModel.completeTask(taskId, "metadata_plugin_callback completed")
        TaskIO.writeOutput(taskId, resultJson)
    }

    private static func applyArchivePatchesForTankoubon(tankoubonId: String, patches: Array<ArchiveMetadataPatch>, taskId: Int64, pluginNamespace: String, archivesProvided: Bool, notifier: TaskNotifier): (Int64, Int64) {
        if (patches.size == 0 && !archivesProvided) {
            return (0, 0)
        }

        let memberArchiveIds = TankoubonDao.getArchivesInTankoubon(tankoubonId)
        if (memberArchiveIds.size == 0) {
            return (0, Int64(patches.size))
        }

        var memberSet = HashSet<String>()
        for (arcid in memberArchiveIds) {
            memberSet.add(arcid)
        }

        if (archivesProvided) {
            let restoredCount = restoreArchiveMetadataForTankoubon(memberArchiveIds, taskId, notifier)
            TaskIO.appendLog(taskId, "restored archive metadata: restored=${restoredCount}")
        }

        var patched: Int64 = 0
        var skipped: Int64 = 0

        for (patch in patches) {
            var targetArchiveId = patch.archiveId.trimAscii()

            // Match by volume number when archive id is absent.
            if (targetArchiveId.size == 0 && patch.volumeNo > 0) {
                let idx = Int64(patch.volumeNo - 1)
                if (idx >= 0 && idx < Int64(memberArchiveIds.size)) {
                    targetArchiveId = memberArchiveIds[idx]
                }
            }

            if (targetArchiveId.size == 0 || !memberSet.contains(targetArchiveId)) {
                skipped += 1
                TaskIO.appendLog(taskId, "skip archive patch: unresolved archive target (archive_id=${patch.archiveId}, volume_no=${patch.volumeNo.toString()})")
                continue
            }

            var archive = ArchiveDao.getArchiveById(targetArchiveId)
            if (archive.id.size == 0) {
                skipped += 1
                TaskIO.appendLog(taskId, "skip archive patch: archive not found id=${targetArchiveId}")
                continue
            }

            let (updatedAtFromTags, cleanedPatchTags) = extractUpdatedAtFromTags(patch.tags)
            let effectiveUpdatedAt = if (patch.updatedAt.trimAscii().size > 0) { patch.updatedAt.trimAscii() } else { updatedAtFromTags }

            var changed = false
            if (patch.title.trimAscii().size > 0) {
                archive.title = patch.title.trimAscii()
                changed = true
            }
            if (patch.summary.trimAscii().size > 0) {
                archive.summary = patch.summary
                changed = true
            }
            if (effectiveUpdatedAt.size > 0) {
                archive.updated_at = effectiveUpdatedAt
                changed = true
            }

            if (changed) {
                let ok = ArchiveDao.update(archive)
                if (!ok) {
                    skipped += 1
                    TaskIO.appendLog(taskId, "skip archive patch: archive update failed id=${targetArchiveId}")
                    continue
                }
            }

            if (cleanedPatchTags.trimAscii().size > 0) {
                let tagOk = TagDao.updateArchiveTags(targetArchiveId, cleanedPatchTags)
                if (!tagOk) {
                    TaskIO.appendLog(taskId, "WARN: archive tag update failed id=${targetArchiveId}")
                }
            }

            if (patch.cover.trimAscii().size > 0) {
                let oldCoverAssetId = ArchiveDao.getCoverAssetId(targetArchiveId)
                let (okCover, coverAssetId, coverThumbHash, coverErr) = PluginCoverUtils.installCoverAssetFromPluginPath(
                    patch.cover,
                    pluginNamespace,
                    "archive_cover",
                    "${targetArchiveId}.avif"
                )
                if (okCover && coverAssetId > 0) {
                    let coverUpdated = ArchiveDao.updateCoverAssetId(targetArchiveId, coverAssetId)
                    if (coverUpdated) {
                        if (coverThumbHash.trimAscii().size > 0) {
                            let _ = ArchiveDao.updateThumbHash(targetArchiveId, coverThumbHash)
                        }
                        if (oldCoverAssetId > 0 && oldCoverAssetId != coverAssetId) {
                            PluginCoverUtils.deleteAsset(oldCoverAssetId)
                        }
                    } else {
                        PluginCoverUtils.deleteAsset(coverAssetId)
                        TaskIO.appendLog(taskId, "WARN: archive cover update failed for patch id=${targetArchiveId}")
                    }
                } else {
                    TaskIO.appendLog(taskId, "WARN: archive patch cover install failed id=${targetArchiveId}: ${coverErr}")
                }
            }

            patched += 1
        }

        return (patched, skipped)
    }

    private static func restoreArchiveMetadataForTankoubon(memberArchiveIds: Array<String>, taskId: Int64, notifier: TaskNotifier): Int64 {
        var restored: Int64 = 0
        for (arcid in memberArchiveIds) {
            let targetId = arcid.trimAscii()
            if (targetId.size == 0) {
                continue
            }

            var archive = ArchiveDao.getArchiveById(targetId)
            if (archive.id.size == 0) {
                TaskIO.appendLog(taskId, "skip restore archive metadata: archive not found id=${targetId}")
                continue
            }

            let archivePath = resolveArchivePath(archive)
            var defaultTitle = ""
            if (archivePath.trimAscii().size > 0) {
                defaultTitle = ArchiveUtils.generateDefaultTitle(archivePath)
            } else if (archive.filename.trimAscii().size > 0) {
                defaultTitle = ArchiveUtils.generateDefaultTitle(archive.filename)
            }

            var changed = false
            if (defaultTitle.trimAscii().size > 0 && archive.title != defaultTitle) {
                archive.title = defaultTitle
                changed = true
            }
            if (archive.summary.trimAscii().size > 0) {
                archive.summary = ""
                changed = true
            }

            if (changed) {
                let ok = ArchiveDao.update(archive)
                if (!ok) {
                    TaskIO.appendLog(taskId, "skip restore archive metadata: archive update failed id=${targetId}")
                    continue
                }
            }

            let tagOk = TagDao.updateArchiveTags(targetId, "")
            if (!tagOk) {
                TaskIO.appendLog(taskId, "WARN: failed to clear archive tags id=${targetId}")
            }

            let oldCoverAssetId = ArchiveDao.getCoverAssetId(targetId)
            if (oldCoverAssetId > 0) {
                let coverUpdated = ArchiveDao.updateCoverAssetId(targetId, 0)
                if (coverUpdated) {
                    let _ = ArchiveDao.updateThumbHash(targetId, "")
                    PluginCoverUtils.deleteAsset(oldCoverAssetId)
                } else {
                    TaskIO.appendLog(taskId, "WARN: failed to clear archive cover asset id=${targetId}")
                }
            } else if (archive.thumbhash.trimAscii().size > 0) {
                let _ = ArchiveDao.updateThumbHash(targetId, "")
            }

            if (archivePath.trimAscii().size > 0) {
                enqueueThumbnailRegeneration(taskId, targetId, archivePath, archive.archive_type, notifier)
            } else {
                TaskIO.appendLog(taskId, "WARN: unable to resolve archive path for thumbnail regeneration id=${targetId}")
            }

            restored += 1
        }

        return restored
    }

    private static func resolveArchivePath(archive: ArchiveData): String {
        if (archive.category_id <= 0) {
            return ""
        }
        match (CategoryDao.getCategoryByInternalId(archive.category_id)) {
            case None => return ""
            case Some(cat) =>
                let base = cat.scanPath.trimAscii()
                if (base.size == 0) {
                    return ""
                }
                let rel = archive.relative_path.trimAscii()
                let dirPath = if (rel.size > 0) { FileUtils.joinPath(base, rel) } else { base }
                if (archive.filename.trimAscii().size == 0) {
                    return ""
                }
                return FileUtils.joinPath(dirPath, archive.filename.trimAscii())
        }
    }

    private static func enqueueThumbnailRegeneration(taskId: Int64, archiveId: String, archivePath: String, archiveType: String, notifier: TaskNotifier): Unit {
        try {
            let out = ByteBuffer()
            let w = JsonWriter(out)
            w.startObject()
            w.writeName("archive_path").writeValue(archivePath)
            w.writeName("archive_id").writeValue(archiveId)
            w.writeName("type").writeValue(archiveType)
            w.endObject()
            w.flush()
            let parameters = String.fromUtf8(readToEnd(out))
            let task = TaskModel.createTaskWithOptions(
                "生成封面",
                "generate_thumbnail",
                parameters,
                10i32,
                archiveId,
                "metadata_plugin_callback"
            )
            if (task.id > 0) {
                notifier()
                TaskIO.appendLog(taskId, "enqueued generate_thumbnail for archive_id=${archiveId}")
            } else {
                TaskIO.appendLog(taskId, "WARN: failed to enqueue generate_thumbnail for archive_id=${archiveId}")
            }
        } catch (e: Exception) {
            TaskIO.appendLog(taskId, "WARN: enqueue generate_thumbnail failed for archive_id=${archiveId}, error=${e.message}")
        }
    }

    private static func parseParameters(parameters: String): (String, String, String, Int64, String, Array<String>) {
        let trimmed = parameters.trimAscii()
        if (trimmed.size == 0) {
            return ("", "", "", 0, "", Array<String>())
        }

        var targetType = ""
        var targetId = ""
        var namespace = ""
        var denoTaskId: Int64 = 0
        var param = ""
        var fallbackNamespaces = ArrayList<String>()

        try {
            var buf = ByteBuffer()
            unsafe { buf.write(trimmed.rawData()) }
            let r = JsonReader(buf)

            func readInt64Flexible(): Int64 {
                let s = r.readValue<String>().trimAscii()
                try { return Int64.parse(s) } catch (_: Exception) { return 0 }
            }

            func readRawJson(): String {
                match (r.peek()) {
                    case Some(BeginObject) =>
                        let bytes = r.readValueBytes()
                        return String.fromUtf8(bytes)
                    case Some(BeginArray) =>
                        let bytes = r.readValueBytes()
                        return String.fromUtf8(bytes)
                    case Some(_) =>
                        return r.readValue<String>()
                    case None => return ""
                }
            }

            if (r.peek() == Some(BeginObject)) {
                r.startObject()
                while (r.peek() != EndObject) {
                    let k = r.readName()
                    match (k) {
                        case "targetType" => targetType = r.readValue<String>().trimAscii()
                        case "targetId" => targetId = r.readValue<String>().trimAscii()
                        case "archiveId" =>
                            if (targetId.size == 0) { targetId = r.readValue<String>().trimAscii() } else { r.skip() }
                        case "namespace" => namespace = r.readValue<String>().trimAscii()
                        case "denoTaskId" => denoTaskId = readInt64Flexible()
                        case "param" => param = readRawJson().trimAscii()
                        case "fallback_namespaces" =>
                            if (r.peek() == Some(BeginArray)) {
                                r.startArray()
                                while (r.peek() != EndArray) {
                                    match (r.peek()) {
                                        case Some(_) =>
                                            let v = r.readValue<String>().trimAscii()
                                            if (v.size > 0) { fallbackNamespaces.add(v) }
                                        case None => break
                                    }
                                }
                                r.endArray()
                            } else {
                                r.skip()
                            }
                        case _ => r.skip()
                    }
                }
                r.endObject()
            }
        } catch (_: Exception) {}

        if (targetType.size == 0) { targetType = "archive" }
        return (targetType, targetId, namespace, denoTaskId, param, fallbackNamespaces.toArray())
    }

    private static func writeParamField(w: JsonWriter, param: String): Unit {
        let trimmed = param.trimAscii()
        if (trimmed.size == 0) { return }

        w.writeName("param")
        if ((trimmed.startsWith("{") && trimmed.endsWith("}")) || (trimmed.startsWith("[") && trimmed.endsWith("]"))) {
            w.jsonValue(trimmed)
        } else {
            w.writeValue(trimmed)
        }
    }

    private static func enqueueFallbackTask(targetType: String, targetId: String, param: String, fallbackNamespaces: Array<String>, taskId: Int64, notifier: TaskNotifier): Bool {
        if (fallbackNamespaces.size == 0 || targetId.trimAscii().size == 0) { return false }

        let nextNamespace = fallbackNamespaces[0].trimAscii()
        if (nextNamespace.size == 0) { return false }

        var remainingBuilder = ArrayList<String>()
        for (i in 1..fallbackNamespaces.size) {
            let value = fallbackNamespaces[i].trimAscii()
            if (value.size > 0) {
                remainingBuilder.add(value)
            }
        }
        let remaining = remainingBuilder.toArray()

        try {
            let out = ByteBuffer()
            let w = JsonWriter(out)
            w.startObject()
            w.writeName("target_type").writeValue(targetType)
            w.writeName("target_id").writeValue(targetId)
            if (targetType == "tankoubon" || targetType == "tank") {
                w.writeName("tankoubon_id").writeValue(targetId)
            } else {
                w.writeName("archive_id").writeValue(targetId)
            }
            w.writeName("namespace").writeValue(nextNamespace)
            writeParamField(w, param)
            if (remaining.size > 0) {
                w.writeName("fallback_namespaces")
                w.startArray()
                for (ns in remaining) {
                    let value = ns.trimAscii()
                    if (value.size > 0) {
                        w.writeValue(value)
                    }
                }
                w.endArray()
            }
            w.endObject()
            w.flush()

            let params = String.fromUtf8(readToEnd(out))
            let fallbackTask = TaskModel.createTaskWithOptions(
                "元数据扫描: ${nextNamespace}",
                "metadata_plugin",
                params,
                15i32,
                targetId,
                "metadata_plugin_callback_fallback:${taskId}"
            )

            if (fallbackTask.id > 0) {
                notifier()
                TaskIO.appendLog(taskId, "enqueued fallback metadata plugin namespace=${nextNamespace} task_id=${fallbackTask.id}")
                return true
            }
        } catch (e: Exception) {
            TaskIO.appendLog(taskId, "WARN: failed to enqueue fallback metadata plugin: ${e.message}")
        }

        return false
    }

    private static func failAndMaybeEnqueueFallback(taskId: Int64, message: String, targetType: String, targetId: String, param: String, fallbackNamespaces: Array<String>, notifier: TaskNotifier): Unit {
        let enqueued = enqueueFallbackTask(targetType, targetId, param, fallbackNamespaces, taskId, notifier)
        if (enqueued) {
            TaskIO.appendLog(taskId, "current metadata callback failed, fallback plugin has been scheduled")
        }
        fail(taskId, message)
    }

    private static func parseMetadataOutput(output: String): ParsedMetadataResult {
        if (output.trimAscii().size == 0) {
            return ParsedMetadataResult(false, "Plugin returned empty output", "", "", "")
        }

        try {
            var buf = ByteBuffer()
            unsafe { buf.write(output.rawData()) }
            let r = JsonReader(buf)

            func readBoolFlexible(): Bool {
                let v = r.readValue<String>().trimAscii().toAsciiLower()
                return v == "true" || v == "1"
            }

            if (r.peek() != Some(BeginObject)) {
                return ParsedMetadataResult(false, "Plugin output is not a JSON object", "", "", "")
            }

            var successSeen = false
            var success = false
            var err = ""
            var title = ""
            var summary = ""
            var tags = ""
            var cover = ""
            var archives = ArrayList<ArchiveMetadataPatch>()
            var archivesProvided = false

            func readStringFlexible(): String {
                match (r.peek()) {
                    case Some(BeginObject) =>
                        let bytes = r.readValueBytes()
                        return String.fromUtf8(bytes)
                    case Some(BeginArray) =>
                        let bytes = r.readValueBytes()
                        return String.fromUtf8(bytes)
                    case Some(_) => return r.readValue<String>()
                    case None => return ""
                }
            }

            func readInt32Flexible(): Int32 {
                let s = readStringFlexible().trimAscii()
                try { return Int32.parse(s) } catch (_: Exception) { return 0 }
            }

            func parseArchivePatchObject(): ArchiveMetadataPatch {
                let patch = ArchiveMetadataPatch()
                if (r.peek() != Some(BeginObject)) {
                    return patch
                }

                r.startObject()
                while (r.peek() != EndObject) {
                    let ak = r.readName()
                    match (ak) {
                        case "archive_id" => patch.archiveId = r.readValue<String>().trimAscii()
                        case "archiveId" => patch.archiveId = r.readValue<String>().trimAscii()
                        case "target_id" =>
                            if (patch.archiveId.size == 0) { patch.archiveId = r.readValue<String>().trimAscii() } else { r.skip() }
                        case "targetId" =>
                            if (patch.archiveId.size == 0) { patch.archiveId = r.readValue<String>().trimAscii() } else { r.skip() }
                        case "id" =>
                            if (patch.archiveId.size == 0) { patch.archiveId = r.readValue<String>().trimAscii() } else { r.skip() }
                        case "volume_no" => patch.volumeNo = readInt32Flexible()
                        case "volumeNo" => patch.volumeNo = readInt32Flexible()
                        case "title" => patch.title = r.readValue<String>()
                        case "summary" => patch.summary = r.readValue<String>()
                        case "tags" => patch.tags = readStringFlexible().trimAscii()
                        case "updated_at" => patch.updatedAt = readStringFlexible().trimAscii()
                        case "updatedAt" => patch.updatedAt = readStringFlexible().trimAscii()
                        case "cover" => patch.cover = readStringFlexible().trimAscii()
                        case _ => r.skip()
                    }
                }
                r.endObject()
                return patch
            }

            r.startObject()
            while (r.peek() != EndObject) {
                let k = r.readName()
                match (k) {
                    case "success" =>
                        successSeen = true
                        success = readBoolFlexible()
                    case "error" =>
                        err = r.readValue<String>()
                    case "data" =>
                        match (r.peek()) {
                            case Some(BeginObject) =>
                                r.startObject()
                                while (r.peek() != EndObject) {
                                    let dk = r.readName()
                                    match (dk) {
                                        case "title" => title = r.readValue<String>()
                                        case "summary" => summary = r.readValue<String>()
                                        case "tags" => tags = readStringFlexible()
                                        case "cover" => cover = readStringFlexible().trimAscii()
                                        case "tankoubon" =>
                                            match (r.peek()) {
                                                case Some(BeginObject) =>
                                                    r.startObject()
                                                    while (r.peek() != EndObject) {
                                                        let tk = r.readName()
                                                        match (tk) {
                                                            case "title" => title = r.readValue<String>()
                                                            case "summary" => summary = r.readValue<String>()
                                                            case "tags" => tags = readStringFlexible()
                                                            case "cover" => cover = readStringFlexible().trimAscii()
                                                            case _ => r.skip()
                                                        }
                                                    }
                                                    r.endObject()
                                                case Some(_) => r.skip()
                                                case None => ()
                                            }
                                        case "archives" =>
                                            archivesProvided = true
                                            match (r.peek()) {
                                                case Some(BeginArray) =>
                                                    r.startArray()
                                                    while (r.peek() != EndArray) {
                                                        let patch = parseArchivePatchObject()
                                                        if (patch.archiveId.trimAscii().size > 0 || patch.volumeNo > 0) {
                                                            archives.add(patch)
                                                        }
                                                    }
                                                    r.endArray()
                                                case Some(_) => r.skip()
                                                case None => ()
                                            }
                                        case _ => r.skip()
                                    }
                                }
                                r.endObject()
                            case Some(_) => r.skip()
                            case None => ()
                        }
                    case _ => r.skip()
                }
            }
            r.endObject()

            if (!successSeen || !success) {
                let msg = if (err.trimAscii().size > 0) { err.trimAscii() } else { "Plugin returned success=false" }
                return ParsedMetadataResult(false, msg, "", "", "")
            }
            return ParsedMetadataResult(true, "", title, summary, tags, cover, archives.toArray(), archivesProvided)
        } catch (e: Exception) {
            return ParsedMetadataResult(false, "Failed to parse plugin output: ${e.message}", "", "", "")
        }
    }

    private static func fail(taskId: Int64, message: String): Unit {
        TaskRunnerOutput.fail(taskId, message)
    }

    private static func buildResultJson(archiveId: String, namespace: String, title: String, summary: String, tags: String, cover: String, output: String, archivesCount: Int64): String {
        let out = ByteBuffer()
        let w = JsonWriter(out)
        w.startObject()
        w.writeName("success").writeValue(1)
        w.writeName("archive_id").writeValue(archiveId)
        w.writeName("namespace").writeValue(namespace)
        w.writeName("title").writeValue(title)
        w.writeName("summary").writeValue(summary)
        w.writeName("tags").writeValue(tags)
        w.writeName("cover").writeValue(cover)
        w.writeName("archives_count").writeValue(archivesCount)
        w.writeName("plugin_output").writeValue(output)
        w.endObject()
        w.flush()
        return String.fromUtf8(readToEnd(out))
    }

}
