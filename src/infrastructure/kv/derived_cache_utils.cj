package lanlu.infrastructure.kv

import std.collection.*

/**
 * Shared namespace/version helpers for derived-data caches backed by PersistentCacheService.
 *
 * Keep this in infrastructure.kv so DAOs can reuse invalidation helpers without
 * pulling kv dependencies into shared.utils and creating package cycles.
 */
public class DerivedCacheUtils {
    private static let tagTranslationSearchNamespace = "tag_translation_search"
    private static let tankoubonAggregatedPayloadNamespace = "tankoubon_aggregated_metadata"
    private static let tankoubonAggregatedContentNamespace = "tankoubon_aggregated_metadata_content"
    private static let tankoubonAggregatedUserNamespacePrefix = "tankoubon_aggregated_metadata_user"
    private static let tankoubonChildrenPayloadNamespace = "tankoubon_children_cache"
    private static let tankoubonChildrenNamespace = "tankoubon_children"
    private static let archiveAssetsRawPayloadNamespace = "archive_assets_raw_cache"
    private static let archiveAssetsRawNamespace = "archive_assets_raw"
    private static let archiveBasePathPayloadNamespace = "archive_base_path_cache"
    private static let archiveBasePathNamespace = "archive_base_path"

    public static func normalizeUniqueIds(ids: Array<String>): Array<String> {
        let deduped = ArrayList<String>()
        let seen = HashMap<String, Bool>()
        for (rawId in ids) {
            let id = rawId.trimAscii()
            if (id.size == 0) {
                continue
            }
            match (seen.get(id)) {
                case Some(_) => ()
                case None =>
                    seen[id] = true
                    deduped.add(id)
            }
        }
        return deduped.toArray()
    }

    public static func getTagTranslationSearchNamespace(): String {
        return tagTranslationSearchNamespace
    }

    public static func getTagTranslationSearchVersion(): Int64 {
        return PersistentCacheService.getNamespaceVersion(tagTranslationSearchNamespace)
    }

    public static func bumpTagTranslationSearchVersion(reason: String): Int64 {
        let _ = reason
        return PersistentCacheService.bumpNamespaceVersion(tagTranslationSearchNamespace)
    }

    public static func getTankoubonAggregatedPayloadNamespace(): String {
        return tankoubonAggregatedPayloadNamespace
    }

    public static func getTankoubonAggregatedContentVersion(): Int64 {
        return PersistentCacheService.getNamespaceVersion(tankoubonAggregatedContentNamespace)
    }

    public static func bumpTankoubonAggregatedContentVersion(reason: String): Int64 {
        let _ = reason
        return PersistentCacheService.bumpNamespaceVersion(tankoubonAggregatedContentNamespace)
    }

    public static func getTankoubonAggregatedUserVersion(userId: Int64): Int64 {
        return PersistentCacheService.getNamespaceVersion(buildTankoubonAggregatedUserNamespace(userId))
    }

    public static func bumpTankoubonAggregatedUserVersion(userId: Int64, reason: String): Int64 {
        if (userId <= 0) {
            return 1
        }
        let _ = reason
        return PersistentCacheService.bumpNamespaceVersion(buildTankoubonAggregatedUserNamespace(userId))
    }

    public static func getTankoubonChildrenVersion(): Int64 {
        return PersistentCacheService.getNamespaceVersion(tankoubonChildrenNamespace)
    }

    public static func getTankoubonChildrenPayloadNamespace(): String {
        return tankoubonChildrenPayloadNamespace
    }

    public static func bumpTankoubonChildrenVersion(reason: String): Int64 {
        let _ = reason
        return PersistentCacheService.bumpNamespaceVersion(tankoubonChildrenNamespace)
    }

    public static func getArchiveAssetsRawVersion(): Int64 {
        return PersistentCacheService.getNamespaceVersion(archiveAssetsRawNamespace)
    }

    public static func getArchiveAssetsRawPayloadNamespace(): String {
        return archiveAssetsRawPayloadNamespace
    }

    public static func bumpArchiveAssetsRawVersion(reason: String): Int64 {
        let _ = reason
        return PersistentCacheService.bumpNamespaceVersion(archiveAssetsRawNamespace)
    }

    public static func getArchiveBasePathVersion(): Int64 {
        return PersistentCacheService.getNamespaceVersion(archiveBasePathNamespace)
    }

    public static func getArchiveBasePathPayloadNamespace(): String {
        return archiveBasePathPayloadNamespace
    }

    public static func bumpArchiveBasePathVersion(reason: String): Int64 {
        let _ = reason
        return PersistentCacheService.bumpNamespaceVersion(archiveBasePathNamespace)
    }

    private static func buildTankoubonAggregatedUserNamespace(userId: Int64): String {
        return "${tankoubonAggregatedUserNamespacePrefix}:${userId.toString()}"
    }
}
