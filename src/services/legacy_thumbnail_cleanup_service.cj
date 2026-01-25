package lanlu.services

import std.fs.*
import stdx.log.*
import lanlu.dao.*
import lanlu.models.*
import lanlu.utils.*

/**
 * One-time best-effort migration of legacy thumbnails from ./data/thumb into assets storage,
 * then deletes the legacy directory.
 *
 * This exists to support upgrading from the old {THUMBNAIL_PATH}/{arcid}.avif layout.
 */
public class LegacyThumbnailCleanupService {
    private static let logger = getLogger("legacy_thumbnail_cleanup")

    public static func migrateAndCleanup(): Unit {
        let legacyDir = "./data/thumb"
        let legacyPath = Path(legacyDir)
        if (!exists(legacyPath)) {
            return
        }

        let assetDir = SystemSettingsService.getPath("ASSET_PATH")
        if (assetDir.trimAscii().size == 0) {
            logger.warn("ASSET_PATH is empty; skip legacy thumbnail migration")
            return
        }
        FileUtils.ensureDirectoryExists(Path(assetDir))

        var migrated: Int64 = 0
        var skipped: Int64 = 0
        var failed: Int64 = 0

        try {
            let entries = DirectoryScanner.listDirectory(legacyDir)
            for (name in entries) {
                if (!name.endsWith(".avif")) {
                    continue
                }
                let arcid = name[0..name.size - 5] // strip ".avif"
                if (arcid.size == 0) {
                    continue
                }

                // Only migrate if the archive exists and doesn't already have a cover asset.
                if (!ArchiveDao.archiveExists(arcid)) {
                    skipped += 1
                    continue
                }
                if (ArchiveDao.getCoverAssetId(arcid) > 0) {
                    skipped += 1
                    continue
                }

                let fromPathStr = FileUtils.joinPath(legacyDir, name)
                if (!exists(Path(fromPathStr))) {
                    continue
                }

                try {
                    var thumbHash = ArchiveDao.getThumbnailHash(arcid)
                    if (thumbHash.size == 0) {
                        thumbHash = try { ThumbHashUtils.calculateAvifThumbHashFromFile(fromPathStr) } catch (_: Exception) { "" }
                        if (thumbHash.size > 0) { let _ = ArchiveDao.updateThumbHash(arcid, thumbHash) }
                    }
                    let byteSize = try { Int64(FileInfo(Path(fromPathStr)).size) } catch (_: Exception) { 0 }
                    match (AssetDao.create(None, "archive_cover", name, "image/avif", "avif", byteSize, thumbHash)) {
                        case Some(assetId) =>
                            let toPathStr = FileUtils.joinPath(assetDir, "${assetId}.avif")
                            FileUtils.safeReplaceFile(Path(toPathStr), Path(fromPathStr))
                            let _ = ArchiveDao.updateCoverAssetId(arcid, assetId)
                            migrated += 1
                        case None =>
                            failed += 1
                    }
                } catch (e: Exception) {
                    logger.warn("Failed to migrate legacy thumbnail", ("arcid", arcid), ("error", e.message))
                    failed += 1
                }
            }
        } catch (e: Exception) {
            logger.warn("Failed to scan legacy thumbnail directory", ("error", e.message))
            return
        }

        // Delete legacy dir if empty (or only contains non-avif leftovers).
        try {
            let remaining = DirectoryScanner.listDirectory(legacyDir)
            var hasAvif = false
            for (n in remaining) {
                if (n.endsWith(".avif")) {
                    hasAvif = true
                    break
                }
            }
            if (!hasAvif) {
                let _ = FileUtils.removeFileOrDirectory(legacyDir)
            }
        } catch (_: Exception) {}

        logger.info("Legacy thumbnail migration complete", ("migrated", migrated.toString()), ("skipped", skipped.toString()), ("failed", failed.toString()))
    }
}

