package lanlu.contexts.tankoubon.interfaces.http
import lanlu.contexts.tankoubon.infrastructure.persistence.*

import ignite.*
import lanlu.contexts.tankoubon.domain.*
import lanlu.contexts.plugin.application.*
import lanlu.contexts.metadata.infrastructure.persistence.*
import lanlu.contexts.user.infrastructure.persistence.*
import lanlu.infrastructure.middleware.*
import std.collection.*
import std.io.{ByteBuffer, readToEnd}
import stdx.net.http.HttpStatusCode
import stdx.encoding.json.stream.*

/**
 * 单行本控制器
 */
public class TankoubonController {
    /**
     * 获取所有单行本
     */
    public static func getTankoubons(ctx: Ctx) {
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
     * 创建新单行本
     */
    public static func createTankoubon(ctx: Ctx) {
        let name = ctx.query("name") ?? ""
        
        if (name.size == 0) {
            let errorResponse = "{\"error\":\"Tankoubon name not specified.\",\"operation\":\"create_tankoubon\",\"success\":0}"
            ctx.json(errorResponse)
            return
        }
        
        let tankoubon = TankoubonModel.createTankoubon(name)
        let successResponse = "{\"operation\":\"create_tankoubon\",\"success\":1,\"tankoubon_id\":\"${tankoubon.id}\"}"
        ctx.json(successResponse)
    }
    

    public static func getMetadata(ctx: Ctx): Unit {
        let id = ctx.paramsOpt("id") ?? ""
        let lang = (ctx.query("lang") ?? "").trimAscii()
        if (id.trimAscii().size == 0) {
            ctx.status(HttpStatusCode.STATUS_BAD_REQUEST)
            ctx.json("{\"error\":\"Tankoubon ID not specified.\",\"operation\":\"get_tankoubon_metadata\",\"success\":0}")
            return
        }

        let includePagesRaw = (ctx.query("include_pages") ?? "").trimAscii().toAsciiLower()
        let includePages = includePagesRaw == "1" || includePagesRaw == "true"
        let tank = match (AuthMiddleware.optionalUser(ctx)) {
            case Some(userId) => TankoubonModel.getTankoubonByIdWithUser(id, userId)
            case None => TankoubonModel.getTankoubonById(id)
        }
        if (tank.id.trimAscii().size == 0) {
            ctx.status(HttpStatusCode.STATUS_NOT_FOUND)
            ctx.json("{\"error\":\"Tankoubon not found\",\"operation\":\"get_tankoubon_metadata\",\"success\":0}")
            return
        }
        let (okMetadata, metadataJson, metadataErr) = MetadataPatchService.buildTankoubonMetadataObjectJson(
            id,
            includePages: includePages,
            includeArchiveDetails: false,
            archiveCount: tank.archive_count,
            pageCount: tank.pagecount,
            progress: tank.progress,
            isNew: tank.isnew,
            isFavorite: tank.isfavorite,
            lastReadTime: tank.last_read_time,
            lang: lang
        )
        if (!okMetadata) {
            let errorText = if (metadataErr.trimAscii().size > 0) { metadataErr } else { "Tankoubon not found" }
            ctx.status(HttpStatusCode.STATUS_NOT_FOUND)
            ctx.json("{\"error\":\"${errorText}\",\"operation\":\"get_tankoubon_metadata\",\"success\":0}")
            return
        }
        ctx.json(metadataJson)
    }

    public static func updateMetadata(ctx: Ctx): Unit {
        let id = ctx.paramsOpt("id") ?? ""
        let requestBody = (ctx.bodyString()).trimAscii()
        if (id.trimAscii().size == 0) {
            ctx.status(HttpStatusCode.STATUS_BAD_REQUEST)
            ctx.json("{\"error\":\"Tankoubon ID not specified.\",\"operation\":\"update_tankoubon_metadata\",\"success\":0}")
            return
        }
        if (requestBody.size == 0) {
            ctx.status(HttpStatusCode.STATUS_BAD_REQUEST)
            ctx.json("{\"error\":\"Request body is required\",\"operation\":\"update_tankoubon_metadata\",\"success\":0}")
            return
        }

        let parsed = MetadataPatchService.parseMetadataObject(requestBody)
        if (!parsed.success) {
            ctx.status(HttpStatusCode.STATUS_BAD_REQUEST)
            ctx.json("{\"error\":\"${parsed.error}\",\"operation\":\"update_tankoubon_metadata\",\"success\":0}")
            return
        }

        match (TankoubonDao.getTankoubonById(id)) {
            case None =>
                ctx.status(HttpStatusCode.STATUS_NOT_FOUND)
                ctx.json("{\"error\":\"Tankoubon doesn't exist in the database!\",\"operation\":\"update_tankoubon_metadata\",\"success\":0}")
                return
            case Some(existing) =>
                let namespace = MetadataPatchService.extractMetadataNamespace(requestBody)
                var topPatch = MetadataPatchService.buildArchivePatchFromParsed(parsed)
                var effectiveCover = topPatch.cover.trimAscii()
                if (effectiveCover.size == 0 && !topPatch.coverProvided) {
                    for (patch in parsed.archives) {
                        let candidate = patch.cover.trimAscii()
                        if (candidate.size > 0) {
                            effectiveCover = candidate
                            break
                        }
                    }
                }
                if (effectiveCover.size > 0 && !topPatch.coverProvided) {
                    topPatch.cover = effectiveCover
                    topPatch.coverProvided = true
                }

                var success = MetadataPatchService.applyTankoubonMetadataPatch(0, id, topPatch, namespace)

                let memberArchiveIds = TankoubonDao.getArchivesInTankoubon(id)
                let memberSet = HashSet<String>()
                for (arcid in memberArchiveIds) {
                    memberSet.add(arcid)
                }
                var patched: Int64 = 0
                var skipped: Int64 = 0
                if (success) {
                    for (patch in parsed.archives) {
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
                        let ok = MetadataPatchService.applyArchiveMetadataPatch(0, targetArchiveId, patch, namespace)
                        if (ok) {
                            patched += 1
                        } else {
                            skipped += 1
                        }
                    }
                }

                if (!success) {
                    ctx.status(HttpStatusCode.STATUS_INTERNAL_SERVER_ERROR)
                    ctx.json("{\"error\":\"Failed to update tankoubon metadata\",\"operation\":\"update_tankoubon_metadata\",\"success\":0}")
                    return
                }

                let out = ByteBuffer()
                let w = JsonWriter(out)
                w.startObject()
                w.writeName("error").writeValue("")
                w.writeName("operation").writeValue("update_tankoubon_metadata")
                w.writeName("success").writeValue(1)
                w.writeName("archives_patched").writeValue(patched)
                w.writeName("archives_skipped").writeValue(skipped)
                w.endObject()
                w.flush()
                ctx.json(String.fromUtf8(readToEnd(out)))
        }
    }


    /**
     * 删除单行本
     */
    public static func deleteTankoubon(ctx: Ctx) {
        let id = ctx.paramsOpt("id") ?? ""
        let assetIds = HashSet<Int64>()
        match (MetadataDao.getMetadataObject("tankoubon", id)) {
            case Some(metadata) =>
                for (asset in metadata.assets) {
                    if (asset.asset_id > 0) {
                        assetIds.add(asset.asset_id)
                    }
                }
            case None => ()
        }

        let success = TankoubonModel.deleteTankoubon(id)
        if (success) {
            let _ = MetadataDao.deleteEntity("tankoubon", id)
            for (assetId in assetIds) {
                if (assetId > 0) {
                    PluginTaskService.deleteCoverAsset(assetId)
                }
            }
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
    public static func addArchiveToTankoubon(ctx: Ctx) {
        let tankoubonId = ctx.paramsOpt("id") ?? ""
        let archiveId = ctx.paramsOpt("archive") ?? ""
        
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
    public static func removeArchiveFromTankoubon(ctx: Ctx) {
        let tankoubonId = ctx.paramsOpt("id") ?? ""
        let archiveId = ctx.paramsOpt("archive") ?? ""
        
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
    public static func addFavorite(ctx: Ctx): Unit {
        match (AuthMiddleware.requireUser(ctx)) {
            case Some(userId) =>
                let id = ctx.paramsOpt("id") ?? ""
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
    public static func removeFavorite(ctx: Ctx): Unit {
        match (AuthMiddleware.requireUser(ctx)) {
            case Some(userId) =>
                let id = ctx.paramsOpt("id") ?? ""
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

}
