package lanlu.controllers

import cjoy.*
import lanlu.models.*
import lanlu.dao.*
import lanlu.middleware.*
import lanlu.services.*
import lanlu.utils.*
import std.collection.*
import std.io.{ByteBuffer, readToEnd}
import std.time.*
import stdx.net.http.HttpStatusCode
import stdx.encoding.json.stream.*

/**
 * 单行本控制器
 */
public class TankoubonController {
    /**
     * 获取所有单行本
     */
    public static func getTankoubons(ctx: JoyContext) {
        let userIdOpt = AuthMiddleware.optionalUser(ctx)
        let tankoubons = match (userIdOpt) {
            case Some(userId) => TankoubonModel.getAllTankoubonsWithUser(userId)
            case None => TankoubonModel.getAllTankoubonsWithUser(0)
        }
        let out = ByteBuffer()
        let w = JsonWriter(out)
        w.startObject()
        w.writeName("filtered").writeValue(tankoubons.size)
        w.writeName("result")
        w.startArray()
        for (i in 0..tankoubons.size) {
            tankoubons[i].writeJson(w)
        }
        w.endArray()
        w.writeName("total").writeValue(tankoubons.size)
        w.endObject()
        w.flush()
        ctx.json(String.fromUtf8(readToEnd(out)))
    }
    
    /**
     * 根据ID获取单行本
     */
    public static func getTankoubonById(ctx: JoyContext) {
        let id = ctx.getParam("id") ?? ""
        let userIdOpt = AuthMiddleware.optionalUser(ctx)
        let tankoubon = match (userIdOpt) {
            case Some(userId) => TankoubonModel.getTankoubonByIdWithUser(id, userId)
            case None => TankoubonModel.getTankoubonById(id)
        }
        
        if (tankoubon.id.size == 0) {
            let errorResponse = "{\"error\":\"The given tankoubon does not exist.\",\"operation\":\"get_tankoubon\",\"success\":0}"
            ctx.json(errorResponse)
            return
        }

        // 查询收藏状态（登录用户）
        match (userIdOpt) {
            case Some(userId) => tankoubon.isfavorite = UserTankoubonFavoriteDao.isFavorite(userId, id)
            case None => tankoubon.isfavorite = false
        }
        
        let out = ByteBuffer()
        let w = JsonWriter(out)
        w.startObject()
        w.writeName("filtered").writeValue(tankoubon.archives.size)
        w.writeName("result")
        tankoubon.writeJson(w)
        w.writeName("total").writeValue(tankoubon.archives.size)
        w.endObject()
        w.flush()
        ctx.json(String.fromUtf8(readToEnd(out)))
    }
    
    /**
     * 创建新单行本
     */
    public static func createTankoubon(ctx: JoyContext) {
        let name = ctx.getQuery("name") ?? ""
        
        if (name.size == 0) {
            let errorResponse = "{\"error\":\"Tankoubon name not specified.\",\"operation\":\"create_tankoubon\",\"success\":0}"
            ctx.json(errorResponse)
            return
        }
        
        let tankoubon = TankoubonModel.createTankoubon(name)
        let successResponse = "{\"operation\":\"create_tankoubon\",\"success\":1,\"tankoubon_id\":\"${tankoubon.id}\"}"
        ctx.json(successResponse)
    }
    
    /**
     * 更新单行本
     */
    public static func updateTankoubon(ctx: JoyContext) {
        let id = ctx.getParam("id") ?? ""
        let requestBody = (ctx.readString()).trimAscii()
        if (requestBody.size == 0) {
            ctx.status(HttpStatusCode.STATUS_BAD_REQUEST)
            ctx.json("{\"error\":\"Request body is required\",\"operation\":\"update_tankoubon\",\"success\":0}")
            return
        }

        var hasName = false
        var hasSummary = false
        var hasTags = false
        var hasCoverAssetId = false
        var hasCover = false
        var name = ""
        var summary = ""
        var tags = ""
        var cover = ""
        var coverAssetId: Int64 = -1i64
        var archivePatches = ArrayList<ArchiveMetadataPatch>()

        try {
            var buf = ByteBuffer()
            unsafe { buf.write(requestBody.rawData()) }
            let r = JsonReader(buf)

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

            func readInt64Flexible(): Int64 {
                let s = readStringFlexible().trimAscii()
                try { return Int64.parse(s) } catch (_: Exception) { return -1i64 }
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

            if (r.peek() == Some(BeginObject)) {
                r.startObject()
                while (r.peek() != EndObject) {
                    let k = r.readName()
                    match (k) {
                        case "name" =>
                            hasName = true
                            name = r.readValue<String>()
                        case "summary" =>
                            hasSummary = true
                            summary = r.readValue<String>()
                        case "tags" =>
                            hasTags = true
                            tags = readStringFlexible().trimAscii()
                        case "cover_asset_id" =>
                            hasCoverAssetId = true
                            coverAssetId = readInt64Flexible()
                        case "coverAssetId" =>
                            hasCoverAssetId = true
                            coverAssetId = readInt64Flexible()
                        case "cover" =>
                            hasCover = true
                            cover = readStringFlexible().trimAscii()
                        case "archives" =>
                            match (r.peek()) {
                                case Some(BeginArray) =>
                                    r.startArray()
                                    while (r.peek() != EndArray) {
                                        let patch = parseArchivePatchObject()
                                        if (patch.archiveId.trimAscii().size > 0 || patch.volumeNo > 0) {
                                            archivePatches.add(patch)
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
            }
        } catch (_: Exception) {
            ctx.status(HttpStatusCode.STATUS_BAD_REQUEST)
            ctx.json("{\"error\":\"Invalid JSON body\",\"operation\":\"update_tankoubon\",\"success\":0}")
            return
        }

        // Partial update support: keep existing values when not provided.
        let existing = TankoubonModel.getTankoubonById(id)
        if (existing.id.size == 0) {
            let errorResponse = "{\"error\":\"Tankoubon doesn't exist in the database!\",\"operation\":\"update_tankoubon\",\"success\":0}"
            ctx.json(errorResponse)
            return
        }

        let effectiveName = if (hasName) { name } else { existing.name }
        let effectiveSummary = if (hasSummary) { summary } else { existing.summary }
        
        var success = TankoubonModel.updateTankoubon(id, effectiveName, effectiveSummary, "", [])
        // If tags key is present (even empty), update tank tags accordingly.
        if (success && hasTags) {
            success = TankoubonModel.updateTankoubonTags(id, tags)
        }

        // cover_asset_id: only update when provided and non-negative
        if (success && hasCoverAssetId && coverAssetId >= 0) {
            let _ = TankoubonModel.updateTankoubonCover(id, coverAssetId)
        }

        // cover: plugin cache relative path -> assets + tankoubon cover
        if (success && hasCover && cover.trimAscii().size > 0) {
            let oldCoverAssetId = TankoubonDao.getTankoubonCoverAssetId(id)
            let (okCover, newCoverAssetId, _, _) = PluginCoverUtils.installCoverAssetFromPluginPath(
                cover,
                "",
                "tankoubon_cover",
                "${id}.avif"
            )
            if (okCover && newCoverAssetId > 0) {
                let coverUpdated = TankoubonModel.updateTankoubonCover(id, newCoverAssetId)
                if (coverUpdated) {
                    if (oldCoverAssetId > 0 && oldCoverAssetId != newCoverAssetId) {
                        PluginCoverUtils.deleteAsset(oldCoverAssetId)
                    }
                } else {
                    PluginCoverUtils.deleteAsset(newCoverAssetId)
                }
            }
        }

        var queuedCount: Int64 = 0
        var callbackTaskId: Int64 = 0
        var callbackTaskErr = ""
        if (success && archivePatches.size > 0) {
            queuedCount = Int64(archivePatches.size)
            let (taskId, err) = enqueueArchivePatchCallback(id, archivePatches.toArray())
            callbackTaskId = taskId
            callbackTaskErr = err
        }

        if (success) {
            let out = ByteBuffer()
            let w = JsonWriter(out)
            w.startObject()
            w.writeName("error").writeValue("")
            w.writeName("operation").writeValue("update_tankoubon")
            w.writeName("success").writeValue(1)
            w.writeName("successMessage").writeValue("Updated tankoubon \"${effectiveName}\"!")
            w.writeName("archives_queued").writeValue(queuedCount)
            w.writeName("archives_task_id").writeValue(callbackTaskId)
            w.writeName("archives_task_error").writeValue(callbackTaskErr)
            w.endObject()
            w.flush()
            ctx.json(String.fromUtf8(readToEnd(out)))
        } else {
            let errorResponse = "{\"error\":\"Tankoubon doesn't exist in the database!\",\"operation\":\"update_tankoubon\",\"success\":0}"
            ctx.json(errorResponse)
        }
    }

    private static func enqueueArchivePatchCallback(tankoubonId: String, patches: Array<ArchiveMetadataPatch>): (Int64, String) {
        if (patches.size == 0) {
            return (0, "")
        }

        let outputJson = buildMetadataFallbackOutput(patches)
        if (outputJson.trimAscii().size == 0) {
            return (0, "Failed to build metadata fallback output")
        }

        // Create a completed placeholder deno_task to store the plugin-like output.
        let denoTaskIdOpt = TaskDao.createTaskDataFull(
            "metadata_fallback_output",
            "deno_task",
            "completed",
            100,
            "metadata_fallback output ready",
            "",
            50,
            "tankoubon:update"
        )

        let denoTaskId = match (denoTaskIdOpt) { case Some(id) => id case None => 0 }
        if (denoTaskId <= 0) {
            return (0, "Failed to create fallback output task")
        }

        TaskIO.writeOutput(denoTaskId, outputJson)

        let paramsOut = ByteBuffer()
        let pw = JsonWriter(paramsOut)
        pw.startObject()
        pw.writeName("targetType").writeValue("tankoubon")
        pw.writeName("targetId").writeValue(tankoubonId)
        pw.writeName("archiveId").writeValue(tankoubonId)
        pw.writeName("namespace").writeValue("")
        pw.writeName("denoTaskId").writeValue(denoTaskId)
        pw.endObject()
        pw.flush()
        let callbackParams = String.fromUtf8(readToEnd(paramsOut))

        let groupId = "tankoubon_update_${tankoubonId}_${DateTime.now().toUnixTimeStamp().toSeconds().toString()}"
        let callbackTask = TaskModel.createTaskWithOptions(
            "Tankoubon archive metadata fallback",
            "metadata_plugin_callback",
            callbackParams,
            50,
            groupId,
            "tankoubon:update"
        )

        if (callbackTask.id <= 0) {
            return (0, "Failed to create metadata_plugin_callback task")
        }

        TaskPoolService.getInstance().notifyTaskAvailable()
        return (callbackTask.id, "")
    }

    private static func buildMetadataFallbackOutput(patches: Array<ArchiveMetadataPatch>): String {
        let out = ByteBuffer()
        let w = JsonWriter(out)
        w.startObject()
        w.writeName("success").writeValue(true)
        w.writeName("data")
        w.startObject()
        w.writeName("archives")
        w.startArray()
        for (patch in patches) {
            w.startObject()
            if (patch.archiveId.trimAscii().size > 0) { w.writeName("archive_id").writeValue(patch.archiveId.trimAscii()) }
            if (patch.volumeNo > 0) { w.writeName("volume_no").writeValue(patch.volumeNo) }
            if (patch.title.trimAscii().size > 0) { w.writeName("title").writeValue(patch.title.trimAscii()) }
            if (patch.summary.trimAscii().size > 0) { w.writeName("summary").writeValue(patch.summary) }
            if (patch.tags.trimAscii().size > 0) { w.writeName("tags").writeValue(patch.tags.trimAscii()) }
            if (patch.updatedAt.trimAscii().size > 0) { w.writeName("updated_at").writeValue(patch.updatedAt.trimAscii()) }
            if (patch.cover.trimAscii().size > 0) { w.writeName("cover").writeValue(patch.cover.trimAscii()) }
            w.endObject()
        }
        w.endArray()
        w.endObject()
        w.endObject()
        w.flush()
        return String.fromUtf8(readToEnd(out))
    }

    private static func applyArchivePatchesForTankoubon(tankoubonId: String, patches: Array<ArchiveMetadataPatch>): (Int64, Int64) {
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
            if (targetArchiveId.size == 0 && patch.volumeNo > 0) {
                let idx = Int64(patch.volumeNo - 1)
                if (idx >= 0 && idx < Int64(memberArchiveIds.size)) {
                    targetArchiveId = memberArchiveIds[idx]
                }
            }

            if (targetArchiveId.size == 0 || !memberSet.contains(targetArchiveId)) {
                skipped += 1
                continue
            }

            var archive = ArchiveDao.getArchiveById(targetArchiveId)
            if (archive.id.size == 0) {
                skipped += 1
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
                    continue
                }
            }

            if (cleanedPatchTags.trimAscii().size > 0) {
                let _ = TagDao.updateArchiveTags(targetArchiveId, cleanedPatchTags)
            }

            if (patch.cover.trimAscii().size > 0) {
                let oldCoverAssetId = ArchiveDao.getCoverAssetId(targetArchiveId)
                let (okCover, coverAssetId, coverThumbHash, _) = PluginCoverUtils.installCoverAssetFromPluginPath(
                    patch.cover,
                    "",
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
                    }
                }
            }

            patched += 1
        }

        return (patched, skipped)
    }
    
    /**
     * 删除单行本
     */
    public static func deleteTankoubon(ctx: JoyContext) {
        let id = ctx.getParam("id") ?? ""
        
        let success = TankoubonModel.deleteTankoubon(id)
        if (success) {
            let successResponse = "{\"error\":\"\",\"operation\":\"delete_tankoubon\",\"success\":1,\"successMessage\":null}"
            ctx.json(successResponse)
        } else {
            let errorResponse = "{\"error\":\"Locked resource: ${id}\",\"operation\":\"delete_tankoubon\",\"success\":0}"
            ctx.json(errorResponse)
        }
    }
    
    /**
     * 向单行本添加档案
     */
    public static func addArchiveToTankoubon(ctx: JoyContext) {
        let tankoubonId = ctx.getParam("id") ?? ""
        let archiveId = ctx.getParam("archive") ?? ""
        
        let success = TankoubonModel.addArchiveToTankoubon(tankoubonId, archiveId)
        if (success) {
            let successResponse = "{\"error\":\"\",\"operation\":\"add_to_tankoubon\",\"success\":1,\"successMessage\":\"Added archive to tankoubon!\"}"
            ctx.json(successResponse)
        } else {
            let errorResponse = "{\"error\":\"Tankoubon doesn't exist in the database!\",\"operation\":\"add_to_tankoubon\",\"success\":0}"
            ctx.json(errorResponse)
        }
    }
    
    /**
     * 从单行本移除档案
     */
    public static func removeArchiveFromTankoubon(ctx: JoyContext) {
        let tankoubonId = ctx.getParam("id") ?? ""
        let archiveId = ctx.getParam("archive") ?? ""
        
        let success = TankoubonModel.removeArchiveFromTankoubon(tankoubonId, archiveId)
        if (success) {
            let successResponse = "{\"error\":\"\",\"operation\":\"remove_from_tankoubon\",\"success\":1,\"successMessage\":\"Removed archive from tankoubon!\"}"
            ctx.json(successResponse)
        } else {
            let errorResponse = "{\"error\":\"Tankoubon doesn't exist in the database!\",\"operation\":\"remove_from_tankoubon\",\"success\":0}"
            ctx.json(errorResponse)
        }
    }

    /**
     * 添加收藏（PUT /api/tankoubons/{id}/favorite）
     */
    public static func addFavorite(ctx: JoyContext): Unit {
        match (AuthMiddleware.requireUser(ctx)) {
            case Some(userId) =>
                let id = ctx.getParam("id") ?? ""
                if (id.size == 0) {
                    let errorResponse = "{\"operation\":\"add_tankoubon_favorite\",\"error\":\"No tankoubon ID specified.\",\"success\":0}"
                    ctx.status(HttpStatusCode.STATUS_BAD_REQUEST)
                    ctx.json(errorResponse)
                    return
                }

                let tank = TankoubonModel.getTankoubonById(id)
                if (tank.id.size == 0) {
                    let errorResponse = "{\"operation\":\"add_tankoubon_favorite\",\"error\":\"Tankoubon not found\",\"success\":0}"
                    ctx.status(HttpStatusCode.STATUS_NOT_FOUND)
                    ctx.json(errorResponse)
                    return
                }

                let addSuccess = UserTankoubonFavoriteDao.addFavorite(userId, id)
                if (addSuccess) {
                    let result = "{\"operation\":\"add_tankoubon_favorite\",\"success\":1}"
                    ctx.json(result)
                } else {
                    let errorResponse = "{\"operation\":\"add_tankoubon_favorite\",\"error\":\"Failed to add favorite\",\"success\":0}"
                    ctx.status(HttpStatusCode.STATUS_INTERNAL_SERVER_ERROR)
                    ctx.json(errorResponse)
                }
            case None => return
        }
    }

    /**
     * 取消收藏（DELETE /api/tankoubons/{id}/favorite）
     */
    public static func removeFavorite(ctx: JoyContext): Unit {
        match (AuthMiddleware.requireUser(ctx)) {
            case Some(userId) =>
                let id = ctx.getParam("id") ?? ""
                if (id.size == 0) {
                    let errorResponse = "{\"operation\":\"remove_tankoubon_favorite\",\"error\":\"No tankoubon ID specified.\",\"success\":0}"
                    ctx.status(HttpStatusCode.STATUS_BAD_REQUEST)
                    ctx.json(errorResponse)
                    return
                }

                let removeSuccess = UserTankoubonFavoriteDao.removeFavorite(userId, id)
                if (removeSuccess) {
                    let result = "{\"operation\":\"remove_tankoubon_favorite\",\"success\":1}"
                    ctx.json(result)
                } else {
                    let errorResponse = "{\"operation\":\"remove_tankoubon_favorite\",\"error\":\"Failed to remove favorite\",\"success\":0}"
                    ctx.status(HttpStatusCode.STATUS_INTERNAL_SERVER_ERROR)
                    ctx.json(errorResponse)
                }
            case None => return
        }
    }

    /**
     * GET /api/tankoubons/{id}/thumbnail
     * - If Tankoubon cover_asset_id is set, redirect to /api/assets/{cover_asset_id}
     * - Else fallback to first archive thumbnail
     */
    public static func getThumbnail(ctx: JoyContext): Unit {
        let id = ctx.getParam("id") ?? ""
        if (id.size == 0) {
            ctx.status(HttpStatusCode.STATUS_BAD_REQUEST)
            ctx.json("{\"success\":0,\"error\":\"No tankoubon ID specified\"}")
            return
        }

        let tank = TankoubonModel.getTankoubonById(id)
        if (tank.id.size == 0) {
            ctx.status(HttpStatusCode.STATUS_NOT_FOUND)
            ctx.json("{\"success\":0,\"error\":\"Tankoubon not found\"}")
            return
        }

        let coverAssetId = TankoubonDao.getTankoubonCoverAssetId(id)
        if (coverAssetId > 0) {
            // Redirect to assets endpoint (supports arbitrary content types).
            ctx.status(HttpStatusCode.STATUS_FOUND)
            ctx.header("Location", "/api/assets/${coverAssetId}")
            return
        }

        if (tank.archives.size > 0) {
            ctx.status(HttpStatusCode.STATUS_FOUND)
            ctx.header("Location", "/api/archives/${tank.archives[0]}/thumbnail")
            return
        }

        // No cover and no archives: redirect to placeholder archive thumbnail (will fallback to placeholder).
        ctx.status(HttpStatusCode.STATUS_FOUND)
        ctx.header("Location", "/api/archives/unknown/thumbnail")
    }
}
