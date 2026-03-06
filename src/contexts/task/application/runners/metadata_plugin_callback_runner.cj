package lanlu.contexts.task.application.runners
import lanlu.contexts.tankoubon.infrastructure.persistence.*
import lanlu.contexts.tag.infrastructure.persistence.*

import std.convert.*
import std.time.*
import std.io.*
import std.io.{ByteBuffer, readToEnd}
import stdx.encoding.json.stream.*
import std.collection.*
import lanlu.contexts.plugin.application.PluginTaskService
import lanlu.contexts.archive.infrastructure.persistence.*
import lanlu.contexts.asset.infrastructure.persistence.*
import lanlu.contexts.task.infrastructure.persistence.*
import lanlu.contexts.category.infrastructure.persistence.*
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
        let parsed = parseMetadataOutput(output)
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
        let pagePatches = parsed.pages
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
            // Write back to Tankoubon (name/summary/tankoubon_tags).
            match (TankoubonDao.getTankoubonById(targetId)) {
                case None =>
                    failAndMaybeEnqueueFallback(taskId, "Tankoubon not found when updating", effectiveType, targetId, param, metadataJson, fallbackNamespaces, context.notifyTaskAvailable)
                    return
                case Some(existing) =>
                    let updatedName = if (parsed.titleProvided) { newTitle } else { existing.name }
                    let updatedSummary = if (parsed.summaryProvided) { newSummary } else { existing.summary }

                    let ok = TankoubonDao.updateTankoubon(targetId, updatedName, updatedSummary)
                    if (!ok) {
                        failAndMaybeEnqueueFallback(taskId, "Failed to update tankoubon metadata", effectiveType, targetId, param, metadataJson, fallbackNamespaces, context.notifyTaskAvailable)
                        return
                    }
                    if (parsed.tagsProvided) {
                        let _ = TankoubonDao.updateTankoubonTags(targetId, newTags)
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

                    if (parsed.coverProvided || effectiveTankCover.size > 0) {
                        applyTankoubonAssetFromPluginOutput(taskId, targetId, "cover", effectiveTankCover, resolvedNamespace)
                    }
                    if (parsed.backdropProvided) {
                        applyTankoubonAssetFromPluginOutput(taskId, targetId, "backdrop", newBackdrop, resolvedNamespace)
                    }
                    if (parsed.clearlogoProvided) {
                        applyTankoubonAssetFromPluginOutput(taskId, targetId, "clearlogo", newClearlogo, resolvedNamespace)
                    }

                    // Optional: plugin can return per-archive metadata patches for this Tankoubon.
                    let (patchedCount, skippedCount) = applyArchivePatchesForTankoubon(targetId, archivePatches, taskId, resolvedNamespace, archivesProvided, context.notifyTaskAvailable)
                    TaskIO.appendLog(taskId, "archive patches applied: patched=${patchedCount}, skipped=${skippedCount}")
            }
        } else {
            // Default: archive write-back.
            var archiveToUpdate = ArchiveDao.getArchiveById(targetId)
            if (archiveToUpdate.id.size == 0) {
                failAndMaybeEnqueueFallback(taskId, "Archive not found when updating", effectiveType, targetId, param, metadataJson, fallbackNamespaces, context.notifyTaskAvailable)
                return
            }

            var changed = false
            if (parsed.titleProvided && archiveToUpdate.title != newTitle) {
                archiveToUpdate.title = newTitle
                changed = true
            }
            if (parsed.summaryProvided && archiveToUpdate.summary != newSummary) {
                archiveToUpdate.summary = newSummary
                changed = true
            }
            if (parsed.tagsProvided) { changed = true }
            if (pluginUpdatedAt.size > 0) {
                archiveToUpdate.updated_at = pluginUpdatedAt
                changed = true
            }
            if (changed) {
                let ok = ArchiveDao.update(archiveToUpdate)
                if (!ok) {
                    failAndMaybeEnqueueFallback(taskId, "Failed to update archive metadata", effectiveType, targetId, param, metadataJson, fallbackNamespaces, context.notifyTaskAvailable)
                    return
                }
            }

            if (parsed.tagsProvided) {
                let tagOk = TagDao.updateArchiveTags(targetId, newTags)
                if (!tagOk) {
                    TaskIO.appendLog(taskId, "WARN: failed to update tags")
                }
            }

            if (parsed.coverProvided) {
                applyArchiveAssetFromPluginOutput(taskId, targetId, "cover", newCover, resolvedNamespace)
            }
            if (parsed.backdropProvided) {
                applyArchiveAssetFromPluginOutput(taskId, targetId, "backdrop", newBackdrop, resolvedNamespace)
            }
            if (parsed.clearlogoProvided) {
                applyArchiveAssetFromPluginOutput(taskId, targetId, "clearlogo", newClearlogo, resolvedNamespace)
            }
        }

        // 处理页面元数据（如果插件返回了 pages）
        if (pagePatches.size > 0 && targetType.trimAscii().toAsciiLower() != "tankoubon" && targetType.trimAscii().toAsciiLower() != "tank") {
            let archiveInternalId = ArchiveDao.getArchiveInternalId(targetId)
            if (archiveInternalId > 0) {
                var savedPages: Int64 = 0
                for (patch in pagePatches) {
                    let entryPath = patch.path.trimAscii()
                    if (patch.page <= 0 && entryPath.size == 0) {
                        continue
                    }

                    var existingMeta = if (entryPath.size > 0) {
                        ArchivePageMetadataDao.getByArchiveAndPath(archiveInternalId, entryPath)
                    } else {
                        Option<PageMetadataData>.None
                    }
                    var hasExistingMeta = false
                    match (existingMeta) {
                        case Some(_) => hasExistingMeta = true
                        case None => ()
                    }
                    if (!hasExistingMeta && patch.page > 0) {
                        existingMeta = ArchivePageMetadataDao.getByArchiveAndPage(archiveInternalId, patch.page)
                    }

                    let pageNumber = if (patch.page > 0) {
                        patch.page
                    } else {
                        match (existingMeta) {
                            case Some(existing) => existing.page_number
                            case None => 0i32
                        }
                    }
                    let normalizedEntryPath = if (entryPath.size > 0) {
                        entryPath
                    } else {
                        match (existingMeta) {
                            case Some(existing) => existing.entry_path
                            case None => ""
                        }
                    }

                    var titleToSave = patch.title
                    var descriptionToSave = patch.description
                    var thumbAssetId: Int64 = 0
                    var thumbHash = ""
                    var sortIndex: Int32 = 0
                    var hiddenInFiles = false

                    match (existingMeta) {
                        case Some(existing) =>
                            if (titleToSave.trimAscii().size == 0) {
                                titleToSave = existing.title
                            }
                            if (descriptionToSave.trimAscii().size == 0) {
                                descriptionToSave = existing.description
                            }
                            thumbAssetId = existing.thumb_asset_id
                            thumbHash = existing.thumbhash
                            sortIndex = existing.sort_index
                            hiddenInFiles = existing.hidden_in_files
                        case None => ()
                    }

                    if (patch.sortProvided) {
                        sortIndex = patch.sort
                    }
                    if (patch.hiddenInFilesProvided) {
                        hiddenInFiles = patch.hiddenInFiles
                    }

                    let patchThumb = patch.thumb.trimAscii()
                    if (patchThumb.size > 0) {
                        let pageToken = if (pageNumber > 0) {
                            pageNumber.toString()
                        } else {
                            DateTime.now().toUnixTimeStamp().toMilliseconds().toString()
                        }
                        let oldThumbAssetId = thumbAssetId
                        let (okThumb, newThumbAssetId, newThumbHash, thumbErr) = PluginTaskService.installCoverAssetFromPluginPath(
                            patchThumb,
                            resolvedNamespace,
                            "page_thumb",
                            "${targetId}_${pageToken}.avif"
                        )
                        if (okThumb && newThumbAssetId > 0) {
                            thumbAssetId = newThumbAssetId
                            thumbHash = newThumbHash
                            if (oldThumbAssetId > 0 && oldThumbAssetId != newThumbAssetId) {
                                PluginTaskService.deleteCoverAsset(oldThumbAssetId)
                            }
                        } else {
                            TaskIO.appendLog(taskId, "WARN: failed to install page thumb from plugin result (archive=${targetId}, page=${pageNumber.toString()}, path=${entryPath}): ${thumbErr}")
                        }
                    }

                    let ok = ArchivePageMetadataDao.insertOrUpdate(
                        archiveInternalId,
                        pageNumber,
                        normalizedEntryPath,
                        titleToSave,
                        descriptionToSave,
                        thumbAssetId: thumbAssetId,
                        thumbHash: thumbHash,
                        extraData: "{}",
                        sortIndex: sortIndex,
                        hiddenInFiles: hiddenInFiles
                    )
                    if (ok) {
                        savedPages += 1
                    }
                }
                TaskIO.appendLog(taskId, "Saved ${savedPages} page metadata entries from plugin")
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

    private static func parsePositiveAssetId(rawValue: String): Int64 {
        let trimmed = rawValue.trimAscii()
        if (trimmed.size == 0) { return 0 }
        try {
            let parsed = Int64.parse(trimmed)
            return if (parsed > 0) { parsed } else { 0 }
        } catch (_: Exception) {
            return 0
        }
    }

    private static func applyArchiveAssetFromPluginOutput(taskId: Int64, archiveId: String, assetKey: String, assetValue: String, pluginNamespace: String): Unit {
        let key = assetKey.trimAscii().toAsciiLower()
        if (key != "cover" && key != "backdrop" && key != "clearlogo") {
            return
        }

        let value = assetValue.trimAscii()
        let oldAssetId = ArchiveDao.getArchiveAssetIdByKey(archiveId, key)
        if (value.size == 0) {
            let cleared = if (key == "cover") {
                let ok = ArchiveDao.updateCoverAssetId(archiveId, 0)
                if (ok) {
                    let _ = ArchiveDao.updateThumbHash(archiveId, "")
                }
                ok
            } else {
                ArchiveDao.updateArchiveAssetIdByKey(archiveId, key, 0)
            }
            if (cleared && oldAssetId > 0) {
                PluginTaskService.deleteCoverAsset(oldAssetId)
            }
            return
        }

        let directAssetId = parsePositiveAssetId(value)
        if (directAssetId > 0) {
            let updated = if (key == "cover") {
                let ok = ArchiveDao.updateCoverAssetId(archiveId, directAssetId)
                if (ok) {
                    let asset = AssetDao.getById(directAssetId)
                    let thumbHash = asset.thumbhash.trimAscii()
                    if (thumbHash.size > 0) {
                        let _ = ArchiveDao.updateThumbHash(archiveId, thumbHash)
                    }
                }
                ok
            } else {
                ArchiveDao.updateArchiveAssetIdByKey(archiveId, key, directAssetId)
            }

            if (updated) {
                if (oldAssetId > 0 && oldAssetId != directAssetId) {
                    PluginTaskService.deleteCoverAsset(oldAssetId)
                }
            } else {
                TaskIO.appendLog(taskId, "WARN: failed to apply archive ${key} asset id=${directAssetId} archive=${archiveId}")
            }
            return
        }

        let assetKind = if (key == "cover") {
            "archive_cover"
        } else if (key == "backdrop") {
            "archive_backdrop"
        } else {
            "archive_clearlogo"
        }
        let outputName = if (key == "cover") {
            "${archiveId}.avif"
        } else {
            "${archiveId}_${key}.avif"
        }

        let (okInstall, newAssetId, thumbHash, installErr) = PluginTaskService.installCoverAssetFromPluginPath(
            value,
            pluginNamespace,
            assetKind,
            outputName
        )
        if (!(okInstall && newAssetId > 0)) {
            TaskIO.appendLog(taskId, "WARN: failed to install archive ${key} from plugin result archive=${archiveId}: ${installErr}")
            return
        }

        let updated = if (key == "cover") {
            let ok = ArchiveDao.updateCoverAssetId(archiveId, newAssetId)
            if (ok && thumbHash.trimAscii().size > 0) {
                let _ = ArchiveDao.updateThumbHash(archiveId, thumbHash)
            }
            ok
        } else {
            ArchiveDao.updateArchiveAssetIdByKey(archiveId, key, newAssetId)
        }

        if (updated) {
            if (oldAssetId > 0 && oldAssetId != newAssetId) {
                PluginTaskService.deleteCoverAsset(oldAssetId)
            }
        } else {
            PluginTaskService.deleteCoverAsset(newAssetId)
            TaskIO.appendLog(taskId, "WARN: failed to apply archive ${key} asset, removed new asset id=${newAssetId} archive=${archiveId}")
        }
    }

    private static func applyTankoubonAssetFromPluginOutput(taskId: Int64, tankoubonId: String, assetKey: String, assetValue: String, pluginNamespace: String): Unit {
        let key = assetKey.trimAscii().toAsciiLower()
        if (key != "cover" && key != "backdrop" && key != "clearlogo") {
            return
        }

        let value = assetValue.trimAscii()
        let oldAssetId = TankoubonDao.getTankoubonAssetIdByKey(tankoubonId, key)
        if (value.size == 0) {
            let cleared = if (key == "cover") {
                TankoubonDao.updateTankoubonCover(tankoubonId, 0)
            } else {
                TankoubonDao.updateTankoubonAssetIdByKey(tankoubonId, key, 0)
            }
            if (cleared && oldAssetId > 0) {
                PluginTaskService.deleteCoverAsset(oldAssetId)
            }
            return
        }

        let directAssetId = parsePositiveAssetId(value)
        if (directAssetId > 0) {
            let updated = if (key == "cover") {
                TankoubonDao.updateTankoubonCover(tankoubonId, directAssetId)
            } else {
                TankoubonDao.updateTankoubonAssetIdByKey(tankoubonId, key, directAssetId)
            }

            if (updated) {
                if (oldAssetId > 0 && oldAssetId != directAssetId) {
                    PluginTaskService.deleteCoverAsset(oldAssetId)
                }
            } else {
                TaskIO.appendLog(taskId, "WARN: failed to apply tankoubon ${key} asset id=${directAssetId} tankoubon=${tankoubonId}")
            }
            return
        }

        let assetKind = if (key == "cover") {
            "tankoubon_cover"
        } else if (key == "backdrop") {
            "tankoubon_backdrop"
        } else {
            "tankoubon_clearlogo"
        }
        let outputName = if (key == "cover") {
            "${tankoubonId}.avif"
        } else {
            "${tankoubonId}_${key}.avif"
        }

        let (okInstall, newAssetId, _, installErr) = PluginTaskService.installCoverAssetFromPluginPath(
            value,
            pluginNamespace,
            assetKind,
            outputName
        )
        if (!(okInstall && newAssetId > 0)) {
            TaskIO.appendLog(taskId, "WARN: failed to install tankoubon ${key} from plugin result tankoubon=${tankoubonId}: ${installErr}")
            return
        }

        let updated = if (key == "cover") {
            TankoubonDao.updateTankoubonCover(tankoubonId, newAssetId)
        } else {
            TankoubonDao.updateTankoubonAssetIdByKey(tankoubonId, key, newAssetId)
        }

        if (updated) {
            if (oldAssetId > 0 && oldAssetId != newAssetId) {
                PluginTaskService.deleteCoverAsset(oldAssetId)
            }
        } else {
            PluginTaskService.deleteCoverAsset(newAssetId)
            TaskIO.appendLog(taskId, "WARN: failed to apply tankoubon ${key} asset, removed new asset id=${newAssetId} tankoubon=${tankoubonId}")
        }
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

            var archive = ArchiveDao.getArchiveById(targetArchiveId)
            if (archive.id.size == 0) {
                skipped += 1
                TaskIO.appendLog(taskId, "skip archive patch: archive not found id=${targetArchiveId}")
                continue
            }

            let (updatedAtFromTags, cleanedPatchTags) = extractUpdatedAtFromTags(patch.tags)
            let hasPatchUpdatedAt = patch.updatedAtProvided || updatedAtFromTags.size > 0
            let effectiveUpdatedAt = if (patch.updatedAt.trimAscii().size > 0) { patch.updatedAt.trimAscii() } else { updatedAtFromTags }

            var changed = false
            if (patch.titleProvided && archive.title != patch.title.trimAscii()) {
                archive.title = patch.title.trimAscii()
                changed = true
            }
            if (patch.summaryProvided && archive.summary != patch.summary) {
                archive.summary = patch.summary
                changed = true
            }
            if (hasPatchUpdatedAt && archive.updated_at != effectiveUpdatedAt) {
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

            if (patch.tagsProvided) {
                let tagOk = TagDao.updateArchiveTags(targetArchiveId, cleanedPatchTags)
                if (!tagOk) {
                    TaskIO.appendLog(taskId, "WARN: archive tag update failed id=${targetArchiveId}")
                }
            }

            if (patch.coverProvided) {
                applyArchiveAssetFromPluginOutput(taskId, targetArchiveId, "cover", patch.cover, pluginNamespace)
            }
            if (patch.backdropProvided) {
                applyArchiveAssetFromPluginOutput(taskId, targetArchiveId, "backdrop", patch.backdrop, pluginNamespace)
            }
            if (patch.clearlogoProvided) {
                applyArchiveAssetFromPluginOutput(taskId, targetArchiveId, "clearlogo", patch.clearlogo, pluginNamespace)
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
            var dataSeen = false
            var title = ""
            var summary = ""
            var tags = ""
            var cover = ""
            var backdrop = ""
            var clearlogo = ""
            var titleProvided = false
            var summaryProvided = false
            var tagsProvided = false
            var coverProvided = false
            var backdropProvided = false
            var clearlogoProvided = false
            var archives = ArrayList<ArchiveMetadataPatch>()
            var archivesProvided = false
            var pages = ArrayList<PageMetadataPatch>()

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

            func readTagsArrayAsCsv(): String {
                if (r.peek() != Some(BeginArray)) {
                    r.skip()
                    return ""
                }
                let seen = HashSet<String>()
                let out = ArrayList<String>()
                r.startArray()
                while (r.peek() != EndArray) {
                    let tag = readStringFlexible().trimAscii()
                    if (tag.size == 0 || seen.contains(tag)) {
                        continue
                    }
                    seen.add(tag)
                    out.add(tag)
                }
                r.endArray()
                return String.join(out.toArray(), delimiter: ", ")
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
                        case "volume_no" => patch.volumeNo = readInt32Flexible()
                        case "title" =>
                            patch.title = r.readValue<String>()
                            patch.titleProvided = true
                        case "description" =>
                            patch.summary = r.readValue<String>()
                            patch.summaryProvided = true
                        case "tags" =>
                            patch.tags = readTagsArrayAsCsv()
                            patch.tagsProvided = true
                        case "updated_at" =>
                            patch.updatedAt = readStringFlexible().trimAscii()
                            patch.updatedAtProvided = true
                        case "assets" =>
                            match (r.peek()) {
                                case Some(BeginArray) =>
                                    r.startArray()
                                    while (r.peek() != EndArray) {
                                        if (r.peek() != Some(BeginObject)) {
                                            r.skip()
                                            continue
                                        }
                                        var key = ""
                                        var value = ""
                                        r.startObject()
                                        while (r.peek() != EndObject) {
                                            let assetKey = r.readName()
                                            match (assetKey) {
                                                case "key" => key = readStringFlexible().trimAscii().toAsciiLower()
                                                case "value" => value = readStringFlexible().trimAscii()
                                                case _ => r.skip()
                                            }
                                        }
                                        r.endObject()
                                        if (key == "cover") {
                                            patch.cover = value
                                            patch.coverProvided = true
                                        } else if (key == "backdrop") {
                                            patch.backdrop = value
                                            patch.backdropProvided = true
                                        } else if (key == "clearlogo") {
                                            patch.clearlogo = value
                                            patch.clearlogoProvided = true
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
                return patch
            }

            func parsePagePatchObject(): PageMetadataPatch {
                let patch = PageMetadataPatch()
                if (r.peek() != Some(BeginObject)) {
                    return patch
                }

                r.startObject()
                while (r.peek() != EndObject) {
                    let pk = r.readName()
                    match (pk) {
                        case "page" => patch.page = readInt32Flexible()
                        case "page_number" => patch.page = readInt32Flexible()
                        case "pageNumber" => patch.page = readInt32Flexible()
                        case "path" => patch.path = readStringFlexible().trimAscii()
                        case "entry" => patch.path = readStringFlexible().trimAscii()
                        case "entry_path" => patch.path = readStringFlexible().trimAscii()
                        case "entryPath" => patch.path = readStringFlexible().trimAscii()
                        case "title" => patch.title = r.readValue<String>()
                        case "description" => patch.description = r.readValue<String>()
                        case "thumb" => patch.thumb = readStringFlexible().trimAscii()
                        case "sort" =>
                            patch.sort = readInt32Flexible()
                            patch.sortProvided = true
                        case "hidden_in_files" =>
                            patch.hiddenInFiles = readBoolFlexible()
                            patch.hiddenInFilesProvided = true
                        case "hiddenInFiles" =>
                            patch.hiddenInFiles = readBoolFlexible()
                            patch.hiddenInFilesProvided = true
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
                                dataSeen = true
                                r.startObject()
                                while (r.peek() != EndObject) {
                                    let dk = r.readName()
                                    match (dk) {
                                        case "title" =>
                                            title = r.readValue<String>()
                                            titleProvided = true
                                        case "description" =>
                                            summary = r.readValue<String>()
                                            summaryProvided = true
                                        case "tags" =>
                                            tags = readTagsArrayAsCsv()
                                            tagsProvided = true
                                        case "assets" =>
                                            match (r.peek()) {
                                                case Some(BeginArray) =>
                                                    r.startArray()
                                                    while (r.peek() != EndArray) {
                                                        if (r.peek() != Some(BeginObject)) {
                                                            r.skip()
                                                            continue
                                                        }
                                                        var key = ""
                                                        var value = ""
                                                        r.startObject()
                                                        while (r.peek() != EndObject) {
                                                            let assetKey = r.readName()
                                                            match (assetKey) {
                                                                case "key" => key = readStringFlexible().trimAscii().toAsciiLower()
                                                                case "value" => value = readStringFlexible().trimAscii()
                                                                case _ => r.skip()
                                                            }
                                                        }
                                                        r.endObject()
                                                        if (key == "cover") {
                                                            cover = value
                                                            coverProvided = true
                                                        } else if (key == "backdrop") {
                                                            backdrop = value
                                                            backdropProvided = true
                                                        } else if (key == "clearlogo") {
                                                            clearlogo = value
                                                            clearlogoProvided = true
                                                        }
                                                    }
                                                    r.endArray()
                                                case Some(_) => r.skip()
                                                case None => ()
                                            }
                                        case "archive" =>
                                            match (r.peek()) {
                                                case Some(BeginArray) =>
                                                    var parsedAny = false
                                                    r.startArray()
                                                    while (r.peek() != EndArray) {
                                                        let patch = parseArchivePatchObject()
                                                        if (patch.archiveId.trimAscii().size > 0 || patch.volumeNo > 0) {
                                                            archives.add(patch)
                                                            parsedAny = true
                                                        }
                                                    }
                                                    r.endArray()
                                                    archivesProvided = parsedAny
                                                case Some(_) => r.skip()
                                                case None => ()
                                            }
                                        case "pages" =>
                                            match (r.peek()) {
                                                case Some(BeginArray) =>
                                                    r.startArray()
                                                    while (r.peek() != EndArray) {
                                                        let patch = parsePagePatchObject()
                                                        if (patch.page > 0 || patch.path.trimAscii().size > 0) {
                                                            pages.add(patch)
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
            if (!dataSeen) {
                return ParsedMetadataResult(false, "Plugin output missing metadata data object", "", "", "")
            }
            let parsed = ParsedMetadataResult(true, "", title, summary, tags, cover, archives.toArray(), archivesProvided, pages.toArray())
            parsed.backdrop = backdrop
            parsed.clearlogo = clearlogo
            parsed.titleProvided = titleProvided
            parsed.summaryProvided = summaryProvided
            parsed.tagsProvided = tagsProvided
            parsed.coverProvided = coverProvided
            parsed.backdropProvided = backdropProvided
            parsed.clearlogoProvided = clearlogoProvided
            return parsed
        } catch (e: Exception) {
            return ParsedMetadataResult(false, "Failed to parse plugin output: ${e.message}", "", "", "")
        }
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
        w.writeName("archive")
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
