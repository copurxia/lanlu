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
        let (targetType, targetId, namespace, denoTaskId) = parseParameters(parameters)
        if (targetId.size == 0 || denoTaskId <= 0) {
            fail(taskId, "Invalid callback parameters: missing targetId or denoTaskId")
            return
        }

        TaskIO.appendLog(taskId, "callback params: targetType=${targetType}, targetId=${targetId}, namespace=${namespace}, denoTaskId=${denoTaskId}")

        // 读取 deno_task 输出
        TaskModel.updateTaskProgress(taskId, 30, "读取插件输出")
        let output = TaskIO.readOutput(denoTaskId)
        if (output.size == 0) {
            fail(taskId, "Deno task output is empty")
            return
        }
        TaskIO.appendLog(taskId, "plugin output: ${output}")

        // 解析元数据输出
        TaskModel.updateTaskProgress(taskId, 50, "解析元数据")
        let parsed = parseMetadataOutput(output)
        if (!parsed.success) {
            fail(taskId, parsed.error)
            return
        }

        let newTitle = parsed.title
        var newTags = parsed.tags
        let newSummary = parsed.summary
        let newCover = parsed.cover
        let archivePatches = parsed.archives
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
                    fail(taskId, "Tankoubon not found when updating")
                    return
                case Some(existing) =>
                    let updatedName = if (newTitle.size > 0) { newTitle } else { existing.name }
                    let updatedSummary = if (newSummary.size > 0) { newSummary } else { existing.summary }

                    let ok = TankoubonDao.updateTankoubon(targetId, updatedName, updatedSummary)
                    if (!ok) {
                        fail(taskId, "Failed to update tankoubon metadata")
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
                    let (patchedCount, skippedCount) = applyArchivePatchesForTankoubon(targetId, archivePatches, taskId, namespace)
                    TaskIO.appendLog(taskId, "archive patches applied: patched=${patchedCount}, skipped=${skippedCount}")
            }
        } else {
            // Default: archive write-back.
            var archiveToUpdate = ArchiveDao.getArchiveById(targetId)
            if (archiveToUpdate.id.size == 0) {
                fail(taskId, "Archive not found when updating")
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
                    fail(taskId, "Failed to update archive metadata")
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

    private static func applyArchivePatchesForTankoubon(tankoubonId: String, patches: Array<ArchiveMetadataPatch>, taskId: Int64, pluginNamespace: String): (Int64, Int64) {
        if (patches.size == 0) {
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

    private static func parseParameters(parameters: String): (String, String, String, Int64) {
        let trimmed = parameters.trimAscii()
        if (trimmed.size == 0) {
            return ("", "", "", 0)
        }

        var targetType = ""
        var targetId = ""
        var namespace = ""
        var denoTaskId: Int64 = 0

        try {
            var buf = ByteBuffer()
            unsafe { buf.write(trimmed.rawData()) }
            let r = JsonReader(buf)

            func readInt64Flexible(): Int64 {
                let s = r.readValue<String>().trimAscii()
                try { return Int64.parse(s) } catch (_: Exception) { return 0 }
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
                        case _ => r.skip()
                    }
                }
                r.endObject()
            }
        } catch (_: Exception) {}

        if (targetType.size == 0) { targetType = "archive" }
        return (targetType, targetId, namespace, denoTaskId)
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
            return ParsedMetadataResult(true, "", title, summary, tags, cover, archives.toArray())
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
