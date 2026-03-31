package lanlu.contexts.recommendation.application

import std.collection.*
import std.sort.*
import lanlu.contexts.archive.infrastructure.persistence.*
import lanlu.contexts.recommendation.infrastructure.persistence.*
import lanlu.contexts.tankoubon.infrastructure.persistence.*

public class RecommendationResultItem {
    public var itemType: String = "archive"
    public var itemId: String = ""
    public var score: Float64 = 0.0
    public var seedEntityType: String = ""
    public var seedEntityId: String = ""

    public init() {}
}

private class RecommendationScoredItem {
    public var itemType: String = "archive"
    public var itemId: String = ""
    public var score: Float64 = 0.0
    public var categoryId: Int64 = 0
    public var tags: String = ""

    public init() {}
}

public class RecommendationService {
    private static let DISCOVER_RECENT_LOOKBACK_HOURS: Int32 = 24

    private static func normalizeNamespace(tag: String): String {
        let idxOpt = tag.indexOf(":")
        match (idxOpt) {
            case Some(idx) =>
                if (idx > 0) {
                    return tag[0..idx].trimAscii().toAsciiLower()
                }
                return ""
            case None => return ""
        }
    }

    private static func tagWeight(tag: String): Float64 {
        let ns = normalizeNamespace(tag)
        if (ns == "artist" || ns == "author" || ns == "series" || ns == "source" || ns == "group") {
            return 3.0
        }
        if (ns == "character" || ns == "parody" || ns == "circle") {
            return 2.0
        }
        if (ns.size > 0) {
            return 1.25
        }
        return 1.0
    }

    private static func buildTagWeightMap(tagsString: String): HashMap<String, Float64> {
        let result = HashMap<String, Float64>()
        if (tagsString.size == 0) { return result }
        for (rawTag in tagsString.split(",")) {
            let tag = rawTag.trimAscii()
            if (tag.size == 0) { continue }
            result[tag] = tagWeight(tag)
        }
        return result
    }

    private static func weightedJaccard(seedTags: String, candidateTags: String): Float64 {
        let seedMap = buildTagWeightMap(seedTags)
        let candidateMap = buildTagWeightMap(candidateTags)
        if (seedMap.size == 0 || candidateMap.size == 0) { return 0.0 }

        var unionWeight = 0.0
        var intersectionWeight = 0.0
        let seen = HashSet<String>()
        for ((tag, weight) in seedMap) {
            seen.add(tag)
            var candidateWeight = 0.0
            match (candidateMap.get(tag)) {
                case Some(v) => candidateWeight = v
                case None => ()
            }
            if (candidateWeight > 0.0) {
                intersectionWeight += if (weight < candidateWeight) { weight } else { candidateWeight }
                unionWeight += if (weight > candidateWeight) { weight } else { candidateWeight }
            } else {
                unionWeight += weight
            }
        }
        for ((tag, weight) in candidateMap) {
            if (!seen.contains(tag)) {
                unionWeight += weight
            }
        }

        if (unionWeight <= 0.0) { return 0.0 }
        return intersectionWeight / unionWeight
    }

    private static func overlapBoost(overlapCount: Int32): Float64 {
        if (overlapCount <= 0) { return 0.0 }
        if (overlapCount >= 8) { return 1.0 }
        return Float64(overlapCount) / 8.0
    }

    private static func pageSimilarity(a: Int32, b: Int32): Float64 {
        if (a <= 0 || b <= 0) { return 0.0 }
        let maxValue = if (a > b) { a } else { b }
        let diff = if (a > b) { a - b } else { b - a }
        let ratio = 1.0 - (Float64(diff) / Float64(maxValue))
        return if (ratio > 0.0) { ratio } else { 0.0 }
    }

    private static func qualityScore(title: String, summary: String, tags: String, coverAssetId: Int64): Float64 {
        var score = 0.0
        if (title.trimAscii().size > 0) { score += 0.35 }
        if (summary.trimAscii().size > 0) { score += 0.15 }
        if (tags.trimAscii().size > 0) { score += 0.25 }
        if (coverAssetId > 0) { score += 0.25 }
        return score
    }

    private static func userAffinityScore(candidateTags: String, userTagWeights: RecommendationUserTagWeights): Float64 {
        if (candidateTags.size == 0 || userTagWeights.weights.size == 0) { return 0.0 }
        var matched = 0.0
        var maxPossible = 0.0
        for ((_, weight) in userTagWeights.weights) {
            maxPossible += Float64(weight)
        }
        if (maxPossible <= 0.0) { return 0.0 }

        let candidateSet = HashSet<String>()
        for (rawTag in candidateTags.split(",")) {
            let tag = rawTag.trimAscii()
            if (tag.size > 0) {
                candidateSet.add(tag)
            }
        }
        for (tag in candidateSet) {
            match (userTagWeights.weights.get(tag)) {
                case Some(weight) => matched += Float64(weight)
                case None => ()
            }
        }
        let normalized = matched / maxPossible
        return if (normalized > 1.0) { 1.0 } else { normalized }
    }

    private static func sortScoredItems(items: ArrayList<RecommendationScoredItem>): Unit {
        sort(items, by: { a, b =>
            if (a.score > b.score) {
                Ordering.LT
            } else if (a.score < b.score) {
                Ordering.GT
            } else if (a.itemId < b.itemId) {
                Ordering.LT
            } else if (a.itemId > b.itemId) {
                Ordering.GT
            } else {
                Ordering.EQ
            }
        })
    }

    private static func diversityPenalty(candidate: RecommendationScoredItem, selected: ArrayList<RecommendationScoredItem>, scene: String): Float64 {
        if (selected.size == 0) { return 0.0 }
        var maxPenalty = 0.0
        for (picked in selected) {
            let sameCategoryPenalty = if (candidate.categoryId > 0 && candidate.categoryId == picked.categoryId) { 0.08 } else { 0.0 }
            let tagPenalty = weightedJaccard(candidate.tags, picked.tags)
            var penalty = tagPenalty * if (scene == "discover") { 0.22 } else { 0.12 }
            penalty += sameCategoryPenalty
            if (penalty > maxPenalty) {
                maxPenalty = penalty
            }
        }
        return maxPenalty
    }

    private static func selectDiverseTop(items: ArrayList<RecommendationScoredItem>, count: Int32, scene: String): Array<RecommendationScoredItem> {
        let selected = ArrayList<RecommendationScoredItem>()
        fillDiverseTop(items, selected, count, scene)
        return selected.toArray()
    }

    private static func fillDiverseTop(
        items: ArrayList<RecommendationScoredItem>,
        selected: ArrayList<RecommendationScoredItem>,
        count: Int32,
        scene: String
    ): Unit {
        let selectedKeys = HashSet<String>()
        for (item in selected) {
            selectedKeys.add("${item.itemType}:${item.itemId}")
        }
        while (Int32(selected.size) < count) {
            var bestIndex = -1
            var bestScore = -999999.0
            for (i in 0..items.size) {
                let candidate = items[i]
                let candidateKey = "${candidate.itemType}:${candidate.itemId}"
                if (selectedKeys.contains(candidateKey)) {
                    continue
                }
                let adjusted = candidate.score - diversityPenalty(candidate, selected, scene)
                if (adjusted > bestScore) {
                    bestScore = adjusted
                    bestIndex = i
                }
            }
            if (bestIndex < 0) {
                break
            }
            let chosen = items[bestIndex]
            selected.add(chosen)
            selectedKeys.add("${chosen.itemType}:${chosen.itemId}")
        }
    }

    private static func buildDiscoverRankedItems(
        candidatesById: HashMap<String, RecommendationArchiveCandidateRow>,
        tankMap: HashMap<String, String>,
        userTagWeights: RecommendationUserTagWeights,
        recentArchiveIds: HashSet<String>,
        recentTankIds: HashSet<String>,
        categoryId: Int64,
    ): ArrayList<RecommendationScoredItem> {
        let grouped = HashMap<String, RecommendationScoredItem>()
        for ((arcid, candidate) in candidatesById) {
            if (recentArchiveIds.contains(arcid)) {
                continue
            }

            let affinity = userAffinityScore(candidate.tags, userTagWeights)
            let categoryBoost = if (categoryId > 0 && candidate.categoryId == categoryId) { 1.0 } else if (categoryId > 0) { 0.15 } else { 0.45 }
            let score =
                0.35 * overlapBoost(candidate.overlapCount) +
                0.20 * affinity +
                0.25 * categoryBoost +
                0.20 * qualityScore(candidate.title, candidate.summary, candidate.tags, candidate.coverAssetId)

            var itemType = "archive"
            var itemId = candidate.arcid
            match (tankMap.get(candidate.arcid)) {
                case Some(tankoubonId) =>
                    if (recentTankIds.contains(tankoubonId)) {
                        continue
                    }
                    itemType = "tankoubon"
                    itemId = tankoubonId
                case None => ()
            }

            let groupKey = "${itemType}:${itemId}"
            match (grouped.get(groupKey)) {
                case Some(existing) =>
                    if (score > existing.score) {
                        existing.score = score
                        existing.tags = candidate.tags
                        existing.categoryId = candidate.categoryId
                    }
                case None =>
                    let scored = RecommendationScoredItem()
                    scored.itemType = itemType
                    scored.itemId = itemId
                    scored.score = score
                    scored.tags = candidate.tags
                    scored.categoryId = candidate.categoryId
                    grouped[groupKey] = scored
            }
        }

        let ranked = ArrayList<RecommendationScoredItem>()
        for ((_, item) in grouped) {
            ranked.add(item)
        }
        sortScoredItems(ranked)
        return ranked
    }

    private static func buildResultItems(selected: Array<RecommendationScoredItem>, seedEntityType: String, seedEntityId: String): Array<RecommendationResultItem> {
        let out = ArrayList<RecommendationResultItem>()
        for (selectedItem in selected) {
            let item = RecommendationResultItem()
            item.itemType = selectedItem.itemType
            item.itemId = selectedItem.itemId
            item.score = selectedItem.score
            item.seedEntityType = seedEntityType
            item.seedEntityId = seedEntityId
            out.add(item)
        }
        return out.toArray()
    }

    public static func getDiscoverRecommendations(userId: Int64, sessionKey: String, categoryId: Int64, count: Int32): Array<RecommendationResultItem> {
        let safeCount = if (count > 0) { count } else { 12i32 }
        var recentArchiveIds = RecommendationDao.getRecentImpressionIds(userId, sessionKey, "discover", "archive", DISCOVER_RECENT_LOOKBACK_HOURS)
        var recentTankIds = RecommendationDao.getRecentImpressionIds(userId, sessionKey, "discover", "tankoubon", DISCOVER_RECENT_LOOKBACK_HOURS)
        let userTagWeights = RecommendationDao.getRecentUserTagWeights(userId, 24i32)

        let candidatesById = HashMap<String, RecommendationArchiveCandidateRow>()
        for (candidate in RecommendationDao.getDiscoverRandomArchiveCandidates(categoryId, userId, safeCount * 14i32)) {
            if (candidate.arcid.size > 0) {
                candidatesById[candidate.arcid] = candidate
            }
        }
        if (userTagWeights.orderedTags.size > 0) {
            for (candidate in RecommendationDao.getDiscoverArchiveCandidatesByTags(categoryId, userTagWeights.orderedTags, safeCount * 10i32)) {
                if (candidate.arcid.size == 0) { continue }
                match (candidatesById.get(candidate.arcid)) {
                    case Some(existing) =>
                        if (candidate.overlapCount > existing.overlapCount) {
                            candidatesById[candidate.arcid] = candidate
                        }
                    case None =>
                        candidatesById[candidate.arcid] = candidate
                }
            }
        }

        let candidateIds = ArrayList<String>()
        for ((arcid, _candidate) in candidatesById) {
            candidateIds.add(arcid)
        }

        let tankMap = RecommendationDao.getArchiveToPrimaryTankoubonMap(candidateIds.toArray())
        var freshRanked = buildDiscoverRankedItems(
            candidatesById,
            tankMap,
            userTagWeights,
            recentArchiveIds,
            recentTankIds,
            categoryId
        )

        if (freshRanked.size == 0 && (recentArchiveIds.size > 0 || recentTankIds.size > 0)) {
            let _ = RecommendationDao.clearImpressions(userId, sessionKey, "discover")
            recentArchiveIds = HashSet<String>()
            recentTankIds = HashSet<String>()
            freshRanked = buildDiscoverRankedItems(
                candidatesById,
                tankMap,
                userTagWeights,
                recentArchiveIds,
                recentTankIds,
                categoryId
            )
        }

        return buildResultItems(selectDiverseTop(freshRanked, safeCount, "discover"), "", "")
    }

    public static func getArchiveRelatedRecommendations(userId: Int64, sessionKey: String, archiveId: String, count: Int32): Array<RecommendationResultItem> {
        let seed = ArchiveDao.getArchiveMetadataById(archiveId)
        if (seed.id.size == 0) { return Array<RecommendationResultItem>() }
        let safeCount = if (count > 0) { count } else { 12i32 }
        var recentArchiveIds = RecommendationDao.getRecentImpressionIds(userId, sessionKey, "archive_related", "archive", 72i32)
        let userTagWeights = RecommendationDao.getRecentUserTagWeights(userId, 24i32)

        func buildArchiveRelatedRankedItems(recentIds: HashSet<String>): ArrayList<RecommendationScoredItem> {
            let ranked = ArrayList<RecommendationScoredItem>()
            for (candidate in RecommendationDao.getArchiveRelatedCandidates(archiveId, safeCount * 16i32)) {
                if (candidate.arcid.size == 0 || candidate.arcid == archiveId) { continue }
                if (recentIds.contains(candidate.arcid)) { continue }

                let tagSim = weightedJaccard(seed.tags, candidate.tags)
                let affinity = userAffinityScore(candidate.tags, userTagWeights)
                let categoryScore = if (candidate.categoryId > 0 && candidate.categoryId == seed.category_id) { 1.0 } else { 0.0 }
                let structureScore = pageSimilarity(seed.pagecount, candidate.pagecount)
                let quality = qualityScore(candidate.title, candidate.summary, candidate.tags, candidate.coverAssetId)

                let scored = RecommendationScoredItem()
                scored.itemType = "archive"
                scored.itemId = candidate.arcid
                scored.categoryId = candidate.categoryId
                scored.tags = candidate.tags
                scored.score =
                    0.48 * tagSim +
                    0.17 * overlapBoost(candidate.overlapCount) +
                    0.15 * categoryScore +
                    0.10 * structureScore +
                    0.05 * affinity +
                    0.05 * quality
                ranked.add(scored)
            }
            return ranked
        }

        var ranked = buildArchiveRelatedRankedItems(recentArchiveIds)
        if (ranked.size == 0 && recentArchiveIds.size > 0) {
            let _ = RecommendationDao.clearImpressions(userId, sessionKey, "archive_related")
            recentArchiveIds = HashSet<String>()
            ranked = buildArchiveRelatedRankedItems(recentArchiveIds)
        }

        sortScoredItems(ranked)
        return buildResultItems(selectDiverseTop(ranked, safeCount, "archive_related"), "archive", archiveId)
    }

    public static func getTankoubonRelatedRecommendations(userId: Int64, sessionKey: String, tankoubonId: String, count: Int32): Array<RecommendationResultItem> {
        match (TankoubonDao.getAggregatedMetadata(tankoubonId, userId)) {
            case None => return Array<RecommendationResultItem>()
            case Some(seed) =>
                let safeCount = if (count > 0) { count } else { 12i32 }
                var recentTankIds = RecommendationDao.getRecentImpressionIds(userId, sessionKey, "tankoubon_related", "tankoubon", 72i32)
                let userTagWeights = RecommendationDao.getRecentUserTagWeights(userId, 24i32)
                func buildTankoubonRelatedRankedItems(recentIds: HashSet<String>): ArrayList<RecommendationScoredItem> {
                    let ranked = ArrayList<RecommendationScoredItem>()
                    for (candidate in RecommendationDao.getTankoubonRelatedCandidates(tankoubonId, safeCount * 16i32)) {
                        if (candidate.tankoubonId.size == 0 || candidate.tankoubonId == tankoubonId) { continue }
                        if (recentIds.contains(candidate.tankoubonId)) { continue }

                        let tagSim = weightedJaccard(seed.tags, candidate.tags)
                        let affinity = userAffinityScore(candidate.tags, userTagWeights)
                        let pageScore = pageSimilarity(seed.pagecount, candidate.pagecount)
                        let categoryScore = if (candidate.categoryId > 0) { 0.45 } else { 0.0 }
                        let quality = qualityScore(candidate.title, candidate.summary, candidate.tags, candidate.coverAssetId)

                        let scored = RecommendationScoredItem()
                        scored.itemType = "tankoubon"
                        scored.itemId = candidate.tankoubonId
                        scored.categoryId = candidate.categoryId
                        scored.tags = candidate.tags
                        scored.score =
                            0.50 * tagSim +
                            0.18 * overlapBoost(candidate.overlapCount) +
                            0.12 * pageScore +
                            0.10 * categoryScore +
                            0.05 * affinity +
                            0.05 * quality
                        ranked.add(scored)
                    }
                    return ranked
                }

                var ranked = buildTankoubonRelatedRankedItems(recentTankIds)
                if (ranked.size == 0 && recentTankIds.size > 0) {
                    let _ = RecommendationDao.clearImpressions(userId, sessionKey, "tankoubon_related")
                    recentTankIds = HashSet<String>()
                    ranked = buildTankoubonRelatedRankedItems(recentTankIds)
                }

                sortScoredItems(ranked)
                return buildResultItems(selectDiverseTop(ranked, safeCount, "tankoubon_related"), "tankoubon", tankoubonId)
        }
    }

    public static func recordImpressions(
        userId: Int64,
        sessionKey: String,
        scene: String,
        seedEntityType: String,
        seedEntityId: String,
        items: Array<RecommendationResultItem>
    ): Bool {
        let rows = ArrayList<RecommendationImpressionWriteRow>()
        for (i in 0..items.size) {
            let item = items[i]
            if (item.itemId.trimAscii().size == 0) { continue }
            let row = RecommendationImpressionWriteRow()
            row.userId = userId
            row.sessionKey = sessionKey
            row.scene = scene
            row.seedEntityType = seedEntityType
            row.seedEntityId = seedEntityId
            row.itemType = item.itemType
            row.itemId = item.itemId
            row.position = Int32(i)
            rows.add(row)
        }
        return RecommendationDao.insertImpressions(rows.toArray())
    }

    public static func recordInteraction(
        userId: Int64,
        sessionKey: String,
        scene: String,
        seedEntityType: String,
        seedEntityId: String,
        itemType: String,
        itemId: String,
        interactionType: String
    ): Bool {
        return RecommendationDao.insertInteraction(
            userId,
            sessionKey,
            scene,
            seedEntityType,
            seedEntityId,
            itemType,
            itemId,
            interactionType
        )
    }
}
