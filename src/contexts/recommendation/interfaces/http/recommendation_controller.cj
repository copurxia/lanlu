package lanlu.contexts.recommendation.interfaces.http

import ignite.*
import lanlu.contexts.archive.infrastructure.persistence.*
import lanlu.contexts.recommendation.application.*
import lanlu.contexts.tag.infrastructure.persistence.*
import lanlu.contexts.tankoubon.infrastructure.persistence.*
import lanlu.contexts.user.infrastructure.persistence.*
import lanlu.infrastructure.middleware.*
import lanlu.shared.views.*
import std.collection.*
import std.convert.*
import std.io.{ByteBuffer, readToEnd}
import stdx.encoding.json.stream.*

public class RecommendationController {
    private static func writeArchiveAssetsJson(w: JsonWriter, assetsRaw: String): Unit {
        let raw = assetsRaw.trimAscii()
        let normalized = if (raw.size > 0) { raw } else { "{}" }
        w.writeName("assets").jsonValue(normalized)
    }

    private static func collectUniqueTags(tagsString: String, seen: HashMap<String, Bool>, out: ArrayList<String>) {
        if (tagsString.size == 0) { return }
        for (rawTag in tagsString.split(",")) {
            let tag = rawTag.trimAscii()
            if (tag.size == 0) { continue }
            match (seen.get(tag)) {
                case Some(_) => ()
                case None =>
                    seen[tag] = true
                    out.add(tag)
            }
        }
    }

    private static func parsePositiveInt32(raw: String, defaultValue: Int32): Int32 {
        let normalized = raw.trimAscii()
        if (normalized.size == 0) { return defaultValue }
        let parsed = try { Int32.parse(normalized) } catch (_: Exception) { defaultValue }
        return if (parsed > 0) { parsed } else { defaultValue }
    }

    private static func parsePositiveInt64(raw: String): Int64 {
        let normalized = raw.trimAscii()
        if (normalized.size == 0) { return 0 }
        let parsed = try { Int64.parse(normalized) } catch (_: Exception) { 0i64 }
        return if (parsed > 0) { parsed } else { 0i64 }
    }

    private static func resolveSessionKey(ctx: Ctx): String {
        let fromHeader = (ctx.header("X-Recommendation-Session") ?? "").trimAscii()
        if (fromHeader.size > 0) { return fromHeader }
        return (ctx.query("session_key") ?? "").trimAscii()
    }

    private static func parseInteractionRequest(body: String): (String, String, String, String, String, String) {
        var scene = ""
        var seedEntityType = ""
        var seedEntityId = ""
        var itemType = ""
        var itemId = ""
        var interactionType = ""

        let raw = body.trimAscii()
        if (raw.size == 0) {
            return (scene, seedEntityType, seedEntityId, itemType, itemId, interactionType)
        }
        try {
            var buf = ByteBuffer()
            unsafe { buf.write(raw.rawData()) }
            let r = JsonReader(buf)
            if (r.peek() != Some(BeginObject)) {
                return (scene, seedEntityType, seedEntityId, itemType, itemId, interactionType)
            }
            r.startObject()
            while (r.peek() != EndObject) {
                let name = r.readName()
                match (name) {
                    case "scene" => scene = r.readValue<String>().trimAscii()
                    case "seed_entity_type" => seedEntityType = r.readValue<String>().trimAscii()
                    case "seedEntityType" => seedEntityType = r.readValue<String>().trimAscii()
                    case "seed_entity_id" => seedEntityId = r.readValue<String>().trimAscii()
                    case "seedEntityId" => seedEntityId = r.readValue<String>().trimAscii()
                    case "item_type" => itemType = r.readValue<String>().trimAscii()
                    case "itemType" => itemType = r.readValue<String>().trimAscii()
                    case "item_id" => itemId = r.readValue<String>().trimAscii()
                    case "itemId" => itemId = r.readValue<String>().trimAscii()
                    case "interaction_type" => interactionType = r.readValue<String>().trimAscii()
                    case "interactionType" => interactionType = r.readValue<String>().trimAscii()
                    case _ => r.skip()
                }
            }
            r.endObject()
        } catch (_: Exception) {}
        return (scene, seedEntityType, seedEntityId, itemType, itemId, interactionType)
    }

    private static func writeRecommendationItemsJson(ctx: Ctx, scene: String, items: Array<RecommendationResultItem>, lang: String): Unit {
        let archiveIds = ArrayList<String>()
        let tankIds = ArrayList<String>()
        for (item in items) {
            if (item.itemType == "tankoubon") {
                tankIds.add(item.itemId)
            } else {
                archiveIds.add(item.itemId)
            }
        }

        let userId = match (AuthMiddleware.optionalUser(ctx)) {
            case Some(id) => id
            case None => 0
        }

        let archiveMap = ArchiveDao.getBatchArchivesById(archiveIds.toArray())
        let archiveAssetsMap = ArchiveDao.getBatchArchiveAssetsRaw(archiveIds.toArray())
        let tankoubonMap = TankoubonDao.getBatchAggregatedMetadata(tankIds.toArray(), userId)
        let tankChildrenMap = TankoubonDao.getBatchArchivesInTankoubon(tankIds.toArray())
        let tankFavoriteMap = UserTankoubonFavoriteDao.getBatchFavoriteStatus(userId, tankIds.toArray())
        let tankFavoriteTimeMap = UserTankoubonFavoriteDao.getBatchFavoriteTime(userId, tankIds.toArray())

        var isNewMap = HashMap<Int64, Bool>()
        var isFavoriteMap = HashMap<Int64, Bool>()
        var favoriteTimeMap = HashMap<Int64, Int64>()
        var progressMap = HashMap<Int64, Int32>()
        var lastReadTimeMap = HashMap<Int64, Int64>()
        if (userId > 0 && archiveIds.size > 0) {
            let archiveInternalIds = ArrayList<Int64>()
            for ((_, archive) in archiveMap) {
                if (archive.internalId > 0) {
                    archiveInternalIds.add(archive.internalId)
                }
            }
            if (archiveInternalIds.size > 0) {
                isNewMap = UserArchiveStatusDao.getBatchStatus(userId, archiveInternalIds.toArray())
                isFavoriteMap = UserFavoriteDao.getBatchFavoriteStatus(userId, archiveInternalIds.toArray())
                favoriteTimeMap = UserFavoriteDao.getBatchFavoriteTime(userId, archiveInternalIds.toArray())
                let (progressResult, lastReadResult) = UserArchiveStatusDao.getBatchProgressAndTime(userId, archiveInternalIds.toArray())
                progressMap = progressResult
                lastReadTimeMap = lastReadResult
            }
        }

        var tagTranslations = HashMap<String, String>()
        if (lang.size > 0) {
            let uniqueTags = ArrayList<String>()
            let seenTags = HashMap<String, Bool>()
            for ((_, archive) in archiveMap) {
                collectUniqueTags(archive.tags, seenTags, uniqueTags)
            }
            for ((_, tank) in tankoubonMap) {
                collectUniqueTags(tank.tags, seenTags, uniqueTags)
            }
            if (uniqueTags.size > 0) {
                tagTranslations = TagDao.batchGetTranslations(uniqueTags.toArray(), lang)
            }
        }

        let out = ByteBuffer()
        let w = JsonWriter(out)
        w.startObject()
        w.writeName("scene").writeValue(scene)
        w.writeName("data")
        w.startArray()
        for (item in items) {
            if (item.itemType == "tankoubon") {
                match (tankoubonMap.get(item.itemId)) {
                    case Some(tank) =>
                        let translatedTags = if (lang.size > 0) {
                            TagDao.translateTagsString(tank.tags, lang, tagTranslations)
                        } else {
                            tank.tags
                        }
                        var isFavorite = false
                        var favoriteTime = 0i64
                        match (tankFavoriteMap.get(item.itemId)) {
                            case Some(v) => isFavorite = v
                            case None => ()
                        }
                        match (tankFavoriteTimeMap.get(item.itemId)) {
                            case Some(v) => favoriteTime = v
                            case None => ()
                        }

                        w.startObject()
                        w.writeName("type").writeValue("tankoubon")
                        w.writeName("tankoubon_id").writeValue(tank.tankoubon_id)
                        w.writeName("title").writeValue(tank.name)
                        w.writeName("description").writeValue(tank.summary)
                        writeArchiveAssetsJson(w, tank.assets_raw)
                        w.writeName("tags").writeValue(translatedTags)
                        w.writeName("children")
                        w.startArray()
                        match (tankChildrenMap.get(item.itemId)) {
                            case Some(children) =>
                                for (child in children) {
                                    w.writeValue(child)
                                }
                            case None => ()
                        }
                        w.endArray()
                        w.writeName("pagecount").writeValue(tank.pagecount)
                        w.writeName("progress").writeValue(tank.progress)
                        w.writeName("lastreadtime").writeValue(tank.last_read_time)
                        w.writeName("release_at").writeValue(tank.release_at)
                        w.writeName("created_at").writeValue(tank.created_at)
                        w.writeName("updated_at").writeValue(tank.updated_at)
                        w.writeName("isnew").writeValue(tank.isnew)
                        w.writeName("archive_count").writeValue(tank.archive_count)
                        w.writeName("isfavorite").writeValue(isFavorite)
                        w.writeName("favoritetime").writeValue(favoriteTime)
                        w.writeName("score").writeValue(item.score)
                        w.endObject()
                    case None => ()
                }
                continue
            }

            match (archiveMap.get(item.itemId)) {
                case Some(archive) =>
                    var isNew = true
                    var isFavorite = false
                    var favoriteTime = 0i64
                    var progress = 0i32
                    var lastReadTime = 0i64
                    if (archive.internalId > 0) {
                        match (isNewMap.get(archive.internalId)) {
                            case Some(v) => isNew = v
                            case None => ()
                        }
                        match (isFavoriteMap.get(archive.internalId)) {
                            case Some(v) => isFavorite = v
                            case None => ()
                        }
                        match (favoriteTimeMap.get(archive.internalId)) {
                            case Some(v) => favoriteTime = v
                            case None => ()
                        }
                        match (progressMap.get(archive.internalId)) {
                            case Some(v) => progress = v
                            case None => ()
                        }
                        match (lastReadTimeMap.get(archive.internalId)) {
                            case Some(v) => lastReadTime = v
                            case None => ()
                        }
                    }

                    let translatedTags = if (lang.size > 0) {
                        TagDao.translateTagsString(archive.tags, lang, tagTranslations)
                    } else {
                        archive.tags
                    }
                    let assetsRaw = match (archiveAssetsMap.get(archive.id)) {
                        case Some(v) => v
                        case None => "{}"
                    }

                    w.startObject()
                    w.writeName("type").writeValue("archive")
                    w.writeName("arcid").writeValue(archive.id)
                    w.writeName("archivetype").writeValue(archive.archive_type)
                    w.writeName("filename").writeValue(archive.filename)
                    w.writeName("isnew").writeValue(isNew)
                    w.writeName("isfavorite").writeValue(isFavorite)
                    w.writeName("favoritetime").writeValue(favoriteTime)
                    w.writeName("lastreadtime").writeValue(lastReadTime)
                    w.writeName("pagecount").writeValue(archive.pagecount)
                    w.writeName("progress").writeValue(progress)
                    w.writeName("size").writeValue(archive.size())
                    writeArchiveAssetsJson(w, assetsRaw)
                    w.writeName("description").writeValue(archive.summary)
                    w.writeName("tags").writeValue(translatedTags)
                    w.writeName("title").writeValue(archive.title)
                    w.writeName("release_at").writeValue(archive.release_at)
                    w.writeName("created_at").writeValue(archive.created_at)
                    w.writeName("updated_at").writeValue(archive.updated_at)
                    w.writeName("score").writeValue(item.score)
                    w.endObject()
                case None => ()
            }
        }
        w.endArray()
        w.endObject()
        w.flush()
        ResponseView.json(ctx, String.fromUtf8(readToEnd(out)))
    }

    public static func getRecommendations(ctx: Ctx): Unit {
        let scene = (ctx.query("scene") ?? "").trimAscii().toAsciiLower()
        let count = parsePositiveInt32(ctx.query("count") ?? "", 12i32)
        let archiveId = (ctx.query("archive_id") ?? "").trimAscii()
        let tankoubonId = (ctx.query("tankoubon_id") ?? "").trimAscii()
        let categoryId = parsePositiveInt64(ctx.query("category_id") ?? (ctx.query("category") ?? ""))
        let sessionKey = resolveSessionKey(ctx)
        let lang = (ctx.query("lang") ?? "").trimAscii()
        let userId = match (AuthMiddleware.optionalUser(ctx)) {
            case Some(id) => id
            case None => 0
        }

        var items = Array<RecommendationResultItem>()
        var seedEntityType = ""
        var seedEntityId = ""
        match (scene) {
            case "discover" =>
                items = RecommendationService.getDiscoverRecommendations(userId, sessionKey, categoryId, count)
            case "archive_related" =>
                if (archiveId.size == 0) {
                    ctx.status(400)
                    ResponseView.errorJson(ctx, "archive_id is required")
                    return
                }
                seedEntityType = "archive"
                seedEntityId = archiveId
                items = RecommendationService.getArchiveRelatedRecommendations(userId, sessionKey, archiveId, count)
            case "tankoubon_related" =>
                if (tankoubonId.size == 0) {
                    ctx.status(400)
                    ResponseView.errorJson(ctx, "tankoubon_id is required")
                    return
                }
                seedEntityType = "tankoubon"
                seedEntityId = tankoubonId
                items = RecommendationService.getTankoubonRelatedRecommendations(userId, sessionKey, tankoubonId, count)
            case _ =>
                ctx.status(400)
                ResponseView.errorJson(ctx, "unsupported recommendation scene")
                return
        }

        let _ = RecommendationService.recordImpressions(userId, sessionKey, scene, seedEntityType, seedEntityId, items)
        writeRecommendationItemsJson(ctx, scene, items, lang)
    }

    public static func recordInteraction(ctx: Ctx): Unit {
        let body = ctx.bodyString()
        let (scene, seedEntityType, seedEntityId, itemType, itemId, interactionType) = parseInteractionRequest(body)
        if (scene.size == 0 || itemType.size == 0 || itemId.size == 0 || interactionType.size == 0) {
            ctx.status(400)
            ResponseView.errorJson(ctx, "scene, item_type, item_id and interaction_type are required")
            return
        }

        let sessionKey = resolveSessionKey(ctx)
        let userId = match (AuthMiddleware.optionalUser(ctx)) {
            case Some(id) => id
            case None => 0
        }
        let ok = RecommendationService.recordInteraction(
            userId,
            sessionKey,
            scene,
            seedEntityType,
            seedEntityId,
            itemType,
            itemId,
            interactionType
        )
        if (!ok) {
            ctx.status(500)
            ResponseView.errorJson(ctx, "failed to record recommendation interaction")
            return
        }
        ResponseView.successJson(ctx, "{\"success\":1}", "ok")
    }
}
