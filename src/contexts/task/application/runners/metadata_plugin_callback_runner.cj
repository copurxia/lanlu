package lanlu.contexts.task.application.runners
import lanlu.contexts.tankoubon.infrastructure.persistence.*
import lanlu.contexts.tag.infrastructure.persistence.*

import std.convert.*
import std.io.*
import std.io.{ByteBuffer, readToEnd}
import stdx.encoding.json.stream.*
import std.collection.*
import lanlu.contexts.plugin.application.PluginTaskService
import lanlu.contexts.plugin.application.MetadataPatchService
import lanlu.contexts.archive.infrastructure.persistence.*
import lanlu.contexts.category.infrastructure.persistence.*
import lanlu.contexts.task.infrastructure.persistence.*
import lanlu.contexts.task.domain.*
import lanlu.contexts.plugin.domain.*
import lanlu.shared.utils.*

/**
 * metadata_plugin_callback 回调任务执行器
 * 在 deno_task 完成后被触发，负责读取插件输出并写回元数据
 */
public class MetadataPluginCallbackRunner {
    public static func run(taskId: Int64, parameters: String, context: TaskRunnerContext): Unit {
        TaskIO.appendLog(taskId, "metadata_plugin_callback task started")
        TaskModel.updateTaskProgress(taskId, 10, "开始处理元数据回调")

        // 解析参数
        let (targetType, targetId, namespace, denoTaskId, param, metadataJson, fallbackNamespaces) = parseParameters(parameters)
        if (targetId.size == 0 || denoTaskId <= 0) {
            fail(taskId, "Invalid callback parameters: missing targetId or denoTaskId")
            return
        }

        let resolvedNamespace = resolvePluginNamespace(namespace, denoTaskId)
        if (namespace.trimAscii().size == 0 && resolvedNamespace.size > 0) {
            TaskIO.appendLog(taskId, "resolved callback namespace from deno task: ${resolvedNamespace}")
        }
        TaskIO.appendLog(taskId, "callback params: targetType=${targetType}, targetId=${targetId}, namespace=${resolvedNamespace}, denoTaskId=${denoTaskId}")

        // 读取 deno_task 输出
        TaskModel.updateTaskProgress(taskId, 30, "读取插件输出")
        let output = TaskIO.readOutput(denoTaskId)
        if (output.size == 0) {
            failAndMaybeEnqueueFallback(taskId, "Deno task output is empty", targetType, targetId, param, metadataJson, fallbackNamespaces, context.notifyTaskAvailable)
            return
        }
        TaskIO.appendLog(taskId, "plugin output: ${output}")

        // 解析元数据输出
        TaskModel.updateTaskProgress(taskId, 50, "解析元数据")
        let parsed = MetadataPatchService.parsePluginOutput(output)
        if (!parsed.success) {
            failAndMaybeEnqueueFallback(taskId, parsed.error, targetType, targetId, param, metadataJson, fallbackNamespaces, context.notifyTaskAvailable)
            return
        }

        let newTitle = parsed.title
        var newTags = parsed.tags
        let newSummary = parsed.summary
        let newCover = parsed.cover
        let newBackdrop = parsed.backdrop
        let newClearlogo = parsed.clearlogo
        let archivePatches = parsed.archives
        let archivesProvided = parsed.archivesProvided
        // Some metadata plugins may emit a pseudo-tag like `updated_at:<unix_seconds>`.
        // Map it to archives.updated_at and prevent it from being stored as a normal tag.
        var pluginUpdatedAt = ""
        if (parsed.tagsProvided) {
            let (updatedAtCandidate, cleanedTags) = extractUpdatedAtFromTags(newTags)
            pluginUpdatedAt = updatedAtCandidate
            newTags = cleanedTags
        }

        let effectiveType = targetType.trimAscii().toAsciiLower()
        TaskModel.updateTaskProgress(taskId, 70, "写回元数据")

        if (effectiveType == "tankoubon" || effectiveType == "tank") {
            // Write back to Tankoubon canonical metadata (title/description/tags/assets/children).
            match (TankoubonDao.getTankoubonById(targetId)) {
                case None =>
                    failAndMaybeEnqueueFallback(taskId, "Tankoubon not found when updating", effectiveType, targetId, param, metadataJson, fallbackNamespaces, context.notifyTaskAvailable)
                    return
                case Some(existing) =>
                    var topPatch = MetadataPatchService.buildArchivePatchFromParsed(parsed)
                    if (parsed.tagsProvided) {
                        topPatch.tags = newTags
                        topPatch.tagsProvided = true
                    }
                    if (pluginUpdatedAt.size > 0) {
                        topPatch.updatedAt = pluginUpdatedAt
                        topPatch.updatedAtProvided = true
                    }
                    if (parsed.backdropProvided) {
                        topPatch.backdrop = newBackdrop
                        topPatch.backdropProvided = true
                    }
                    if (parsed.clearlogoProvided) {
                        topPatch.clearlogo = newClearlogo
                        topPatch.clearlogoProvided = true
                    }

                    var effectiveTankCover = newCover.trimAscii()
                    if (effectiveTankCover.size == 0 && !parsed.coverProvided) {
                        for (patch in archivePatches) {
                            let candidate = patch.cover.trimAscii()
                            if (candidate.size > 0) {
                                effectiveTankCover = candidate
                                break
                            }
                        }
                    }
                    if (effectiveTankCover.size > 0 && !topPatch.coverProvided) {
                        topPatch.cover = effectiveTankCover
                        topPatch.coverProvided = true
                    }

                    let ok = MetadataPatchService.applyTankoubonMetadataPatch(taskId, targetId, topPatch, resolvedNamespace)
                    if (!ok) {
                        failAndMaybeEnqueueFallback(taskId, "Failed to update tankoubon metadata", effectiveType, targetId, param, metadataJson, fallbackNamespaces, context.notifyTaskAvailable)
                        return
                    }

                    // Optional: plugin can return per-archive metadata patches for this Tankoubon.
                    let (patchedCount, skippedCount) = applyArchivePatchesForTankoubon(targetId, archivePatches, taskId, resolvedNamespace, archivesProvided, context.notifyTaskAvailable)
                    TaskIO.appendLog(taskId, "archive patches applied: patched=${patchedCount}, skipped=${skippedCount}")
            }
        } else {
            // Default: archive write-back.
            let archiveToUpdate = ArchiveDao.getArchiveById(targetId)
            if (archiveToUpdate.id.size == 0) {
                failAndMaybeEnqueueFallback(taskId, "Archive not found when updating", effectiveType, targetId, param, metadataJson, fallbackNamespaces, context.notifyTaskAvailable)
                return
            }

            let topPatch = MetadataPatchService.buildArchivePatchFromParsed(parsed)
            if (parsed.tagsProvided) {
                topPatch.tags = newTags
            }
            if (pluginUpdatedAt.size > 0) {
                topPatch.updatedAt = pluginUpdatedAt
                topPatch.updatedAtProvided = true
            }
            let ok = MetadataPatchService.applyArchiveMetadataPatch(taskId, targetId, topPatch, resolvedNamespace)
            if (!ok) {
                failAndMaybeEnqueueFallback(taskId, "Failed to update archive metadata", effectiveType, targetId, param, metadataJson, fallbackNamespaces, context.notifyTaskAvailable)
                return
            }
        }

        // 完成任务
        TaskModel.updateTaskProgress(taskId, 100, "元数据回调完成")
        let resultJson = buildResultJson(effectiveType, targetId, resolvedNamespace, newTitle, newSummary, newTags, newCover, newBackdrop, newClearlogo, output, archivePatches.size)
        TaskModel.completeTask(taskId, "metadata_plugin_callback completed")
        TaskIO.writeOutput(taskId, resultJson)
    }

    private static func resolvePluginNamespace(namespace: String, denoTaskId: Int64): String {
        let direct = namespace.trimAscii()
        if (direct.size > 0) {
            return direct
        }
        if (denoTaskId <= 0) {
            return ""
        }

        let denoTask = TaskDao.getTaskDataById(denoTaskId)
        return denoTask.pluginNamespace.trimAscii()
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

        var coverPatchedArchiveIds = HashSet<String>()
        for (patch in patches) {
            if (!patch.coverProvided || patch.cover.trimAscii().size == 0) {
                continue
            }

            var targetArchiveId = patch.archiveId.trimAscii()
            if (targetArchiveId.size == 0 && patch.volumeNo > 0) {
                let idx = Int64(patch.volumeNo - 1)
                if (idx >= 0 && idx < Int64(memberArchiveIds.size)) {
                    targetArchiveId = memberArchiveIds[idx]
                }
            }
            if (targetArchiveId.size > 0 && memberSet.contains(targetArchiveId)) {
                coverPatchedArchiveIds.add(targetArchiveId)
            }
        }

        if (archivesProvided) {
            let restoredCount = restoreArchiveMetadataForTankoubon(memberArchiveIds, coverPatchedArchiveIds, taskId, notifier)
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

            let archive = ArchiveDao.getArchiveById(targetArchiveId)
            if (archive.id.size == 0) {
                skipped += 1
                TaskIO.appendLog(taskId, "skip archive patch: archive not found id=${targetArchiveId}")
                continue
            }

            let ok = MetadataPatchService.applyArchiveMetadataPatch(taskId, targetArchiveId, patch, pluginNamespace)
            if (!ok) {
                skipped += 1
                TaskIO.appendLog(taskId, "skip archive patch: archive update failed id=${targetArchiveId}")
                continue
            }

            patched += 1
        }

        return (patched, skipped)
    }

    private static func restoreArchiveMetadataForTankoubon(memberArchiveIds: Array<String>, skipCoverArchiveIds: HashSet<String>, taskId: Int64, notifier: TaskNotifier): Int64 {
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

            if (!skipCoverArchiveIds.contains(targetId)) {
                let oldCoverAssetId = ArchiveDao.getCoverAssetId(targetId)
                if (oldCoverAssetId > 0) {
                    let coverUpdated = ArchiveDao.updateCoverAssetId(targetId, 0)
                    if (coverUpdated) {
                        let _ = ArchiveDao.updateThumbHash(targetId, "")
                        PluginTaskService.deleteCoverAsset(oldCoverAssetId)
                    } else {
                        TaskIO.appendLog(taskId, "WARN: failed to clear archive cover asset id=${targetId}")
                    }
                } else if (archive.thumbhash.trimAscii().size > 0) {
                    let _ = ArchiveDao.updateThumbHash(targetId, "")
                } else {
                    // keep thumbhash empty when no cover exists
                }
            } else {
                TaskIO.appendLog(taskId, "skip thumbnail regeneration: plugin patch provides cover id=${targetId}")
            }

            if (!skipCoverArchiveIds.contains(targetId)) {
                if (archivePath.trimAscii().size > 0) {
                    enqueueThumbnailRegeneration(taskId, targetId, archivePath, archive.archive_type, notifier)
                } else {
                    TaskIO.appendLog(taskId, "WARN: unable to resolve archive path for thumbnail regeneration id=${targetId}")
                }
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

    private static func parseParameters(parameters: String): (String, String, String, Int64, String, String, Array<String>) {
        let trimmed = parameters.trimAscii()
        if (trimmed.size == 0) {
            return ("", "", "", 0, "", "", Array<String>())
        }

        var targetType = ""
        var targetId = ""
        var namespace = ""
        var denoTaskId: Int64 = 0
        var param = ""
        var metadataJson = ""
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
                        case "namespace" => namespace = r.readValue<String>().trimAscii()
                        case "denoTaskId" => denoTaskId = readInt64Flexible()
                        case "param" => param = readRawJson().trimAscii()
                        case "metadata" => metadataJson = normalizeMetadataJson(readRawJson())
                        case "target_type" => targetType = r.readValue<String>().trimAscii()
                        case "target_id" => targetId = r.readValue<String>().trimAscii()
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
        return (targetType, targetId, namespace, denoTaskId, param, metadataJson, fallbackNamespaces.toArray())
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

    private static func normalizeMetadataJson(raw: String): String {
        let trimmed = raw.trimAscii()
        if (trimmed.size == 0) { return "" }

        try {
            var buf = ByteBuffer()
            unsafe { buf.write(trimmed.rawData()) }
            let r = JsonReader(buf)
            if (r.peek() == Some(BeginObject)) {
                return trimmed
            }
        } catch (_: Exception) {}
        return ""
    }

    private static func writeMetadataField(w: JsonWriter, metadataJson: String): Unit {
        let normalized = normalizeMetadataJson(metadataJson)
        if (normalized.size == 0) { return }
        w.writeName("metadata").jsonValue(normalized)
    }

    private static func enqueueFallbackTask(targetType: String, targetId: String, param: String, metadataJson: String, fallbackNamespaces: Array<String>, taskId: Int64, notifier: TaskNotifier): Bool {
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
            w.writeName("namespace").writeValue(nextNamespace)
            writeParamField(w, param)
            writeMetadataField(w, metadataJson)
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

    private static func failAndMaybeEnqueueFallback(taskId: Int64, message: String, targetType: String, targetId: String, param: String, metadataJson: String, fallbackNamespaces: Array<String>, notifier: TaskNotifier): Unit {
        let enqueued = enqueueFallbackTask(targetType, targetId, param, metadataJson, fallbackNamespaces, taskId, notifier)
        if (enqueued) {
            TaskIO.appendLog(taskId, "current metadata callback failed, fallback plugin has been scheduled")
        }
        fail(taskId, message)
    }

    private static func fail(taskId: Int64, message: String): Unit {
        TaskRunnerOutput.fail(taskId, message)
    }

    private static func buildResultJson(targetType: String, targetId: String, namespace: String, title: String, summary: String, tags: String, cover: String, backdrop: String, clearlogo: String, output: String, archivesCount: Int64): String {
        let effectiveType = targetType.trimAscii().toAsciiLower()
        let metadataType = if (effectiveType == "tankoubon" || effectiveType == "tank") { 1i32 } else { 0i32 }
        let tagsArray = tags.trimAscii().split(",")

        let out = ByteBuffer()
        let w = JsonWriter(out)
        w.startObject()
        w.writeName("success").writeValue(1)
        w.writeName("target_type").writeValue(effectiveType)
        w.writeName("target_id").writeValue(targetId)
        w.writeName("namespace").writeValue(namespace)
        w.writeName("metadata")
        w.startObject()
        w.writeName("title").writeValue(title)
        w.writeName("type").writeValue(metadataType)
        w.writeName("description").writeValue(summary)
        w.writeName("tags")
        w.startArray()
        for (tag in tagsArray) {
            let value = tag.trimAscii()
            if (value.size > 0) {
                w.writeValue(value)
            }
        }
        w.endArray()
        w.writeName("assets")
        w.startArray()
        if (cover.trimAscii().size > 0) {
            w.startObject()
            w.writeName("key").writeValue("cover")
            w.writeName("value").writeValue(cover.trimAscii())
            w.endObject()
        }
        if (backdrop.trimAscii().size > 0) {
            w.startObject()
            w.writeName("key").writeValue("backdrop")
            w.writeName("value").writeValue(backdrop.trimAscii())
            w.endObject()
        }
        if (clearlogo.trimAscii().size > 0) {
            w.startObject()
            w.writeName("key").writeValue("clearlogo")
            w.writeName("value").writeValue(clearlogo.trimAscii())
            w.endObject()
        }
        w.endArray()
        w.writeName("children")
        w.startArray()
        w.endArray()
        w.endObject()
        w.writeName("archives_count").writeValue(archivesCount)
        w.writeName("plugin_output").writeValue(output)
        w.endObject()
        w.flush()
        return String.fromUtf8(readToEnd(out))
    }

}
