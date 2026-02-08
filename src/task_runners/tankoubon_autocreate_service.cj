package lanlu.task_runners

import std.collection.*
import stdx.log.*
import lanlu.utils.*
import lanlu.utils.NaturalSort
import lanlu.archivehandler.*
import lanlu.dao.*

/**
 * Directory-based Tankoubon auto-create + sync.
 *
 * Rules (as per user):
 * - A directory qualifies if it contains 2+ "archives" and no other directories.
 *   Child directories that are recognized as folder-type archives DO NOT count as "other directories".
 * - Do not create at category root (relative_path == "").
 * - Members are ordered by natural filename sort (same behavior as folder archives).
 * - Tankoubon name uses the directory relative path.
 */
public class TankoubonAutocreateService {
    private static let logger = getLogger("tankoubon_autocreate")

    public static func isLeafMediaFolder(dirPath: String): Bool {
        if (!DirectoryScanner.directoryExists(dirPath)) { return false }
        let entries = DirectoryScanner.listDirectory(dirPath)
        if (entries.size == 0) { return false }

        var hasMedia = false
        for (entry in entries) {
            let full = DirectoryScanner.joinPath(dirPath, entry)
            if (DirectoryScanner.isDirectory(full)) {
                return false
            }
            if (!DirectoryScanner.fileExists(full)) {
                return false
            }
            if (FolderHandler.isAllowedMediaFileName(entry)) {
                hasMedia = true
            } else if (FolderHandler.isAllowedAuxFileName(entry)) {
                // allow
            } else {
                return false
            }
        }
        return hasMedia
    }

    private static func isAllowedCollectionAuxFileName(entryName: String): Bool {
        // Allow JSON metadata files and media/cover images alongside archives.
        if (FolderHandler.isAllowedAuxFileName(entryName)) { return true }
        if (FolderHandler.isAllowedMediaFileName(entryName)) { return true }
        return false
    }

    public static func inspectDirectoryForTank(dirPath: String): (Bool, Array<String>) {
        if (!DirectoryScanner.directoryExists(dirPath)) { return (false, []) }
        let entries = DirectoryScanner.listDirectory(dirPath)
        if (entries.size == 0) { return (false, []) }

        let factory = ArchiveHandlerFactory.getInstance()
        var candidates: ArrayList<String> = ArrayList<String>()
        var hasOtherDirectory = false
        var hasOtherFile = false

        for (entry in entries) {
            let full = DirectoryScanner.joinPath(dirPath, entry)
            if (DirectoryScanner.isDirectory(full)) {
                if (isLeafMediaFolder(full)) {
                    candidates.add(entry)
                } else {
                    hasOtherDirectory = true
                }
                continue
            }

            match (factory.getHandlerByPath(full)) {
                case Some(_) => candidates.add(entry)
                case None =>
                    if (!isAllowedCollectionAuxFileName(entry)) {
                        hasOtherFile = true
                    }
            }
        }

        if (hasOtherDirectory || hasOtherFile) { return (false, []) }
        if (candidates.size < 2) { return (false, []) }

        NaturalSort.sortStrings(candidates)
        return (true, candidates.toArray())
    }

    public static func ensureAndSync(categoryInternalId: Int64, dirRelativePath: String, dirFullPath: String): String {
        let rel = dirRelativePath.trimAscii()
        if (categoryInternalId <= 0) { return "" }
        if (rel.size == 0) { return "" }

        let (ok, candidates) = inspectDirectoryForTank(dirFullPath)
        if (!ok) { return "" }

        let tankId = TankoubonDao.getOrCreateAutoTankoubon(categoryInternalId, rel, rel)
        if (tankId.size == 0) { return "" }

        syncMembers(tankId, rel, candidates)
        return tankId
    }

    private static func syncMembers(tankoubonId: String, dirRelativePath: String, candidatesInOrder: Array<String>): Unit {
        let current = TankoubonDao.getArchivesInTankoubon(tankoubonId)
        var desired: ArrayList<String> = ArrayList<String>()
        var desiredSet: HashSet<String> = HashSet<String>()

        // Resolve archive ids in sorted filename order.
        for (entryName in candidatesInOrder) {
            match (ArchiveDao.getByPathAndFilename(dirRelativePath, entryName)) {
                case Some(arch) =>
                    desired.add(arch.id)
                    desiredSet.add(arch.id)
                case None => ()
            }
        }

        // Default cover: use the first archive's cover if tank has no cover yet.
        if (desired.size > 0) {
            let currentCover = TankoubonDao.getTankoubonCoverAssetId(tankoubonId)
            if (currentCover <= 0) {
                let firstArchiveId = desired[0]
                let firstCover = ArchiveDao.getCoverAssetId(firstArchiveId)
                if (firstCover > 0) {
                    let _ = TankoubonDao.updateTankoubonCover(tankoubonId, firstCover)
                }
            }
        }

        // Remove members no longer present in this directory.
        for (arcid in current) {
            if (!desiredSet.contains(arcid)) {
                let _ = TankoubonDao.removeArchiveFromTankoubon(tankoubonId, arcid)
            }
        }

        // Always enforce natural-sorted order for all members.
        for (i in 0..desired.size) {
            let arcid = desired[i]
            let _ = TankoubonDao.addArchiveToTankoubon(tankoubonId, arcid, Int32(i + 1))
        }
    }

    public static func hasAllCandidatesIndexed(dirRelativePath: String, dirFullPath: String): Bool {
        let rel = dirRelativePath.trimAscii()
        if (rel.size == 0) { return false }

        let (ok, candidates) = inspectDirectoryForTank(dirFullPath)
        if (!ok) { return false }

        for (entryName in candidates) {
            match (ArchiveDao.getByPathAndFilename(rel, entryName)) {
                case Some(_) => ()
                case None => return false
            }
        }
        return true
    }
}
