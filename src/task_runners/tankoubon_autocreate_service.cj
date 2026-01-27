package lanlu.task_runners

import std.collection.*
import stdx.log.*
import lanlu.utils.*
import lanlu.archivehandler.*
import lanlu.dao.*

/**
 * Directory-based Tankoubon auto-create + sync.
 *
 * Rules (as per user):
 * - A directory qualifies if it contains 2+ "archives" and no other directories.
 *   Child directories that are recognized as folder-type archives DO NOT count as "other directories".
 * - Do not create at category root (relative_path == "").
 * - Existing order is preserved; new items append to end; missing items are removed.
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
        return (true, candidates.toArray())
    }

    public static func ensureAndSync(categoryInternalId: Int64, dirRelativePath: String, dirFullPath: String): Unit {
        let rel = dirRelativePath.trimAscii()
        if (categoryInternalId <= 0) { return }
        if (rel.size == 0) { return }

        let (ok, candidates) = inspectDirectoryForTank(dirFullPath)
        if (!ok) { return }

        let tankId = TankoubonDao.getOrCreateAutoTankoubon(categoryInternalId, rel, rel)
        if (tankId.size == 0) { return }

        syncMembers(tankId, rel, candidates)
    }

    private static func syncMembers(tankoubonId: String, dirRelativePath: String, candidatesInOrder: Array<String>): Unit {
        let current = TankoubonDao.getArchivesInTankoubon(tankoubonId)
        var currentSet: HashSet<String> = HashSet<String>()
        for (a in current) { currentSet.add(a) }

        var presentNames: HashSet<String> = HashSet<String>()
        for (n in candidatesInOrder) { presentNames.add(n) }

        // Remove missing items.
        for (arcid in current) {
            let a = ArchiveDao.getArchiveById(arcid)
            if (a.id.size == 0 || a.relative_path != dirRelativePath || !presentNames.contains(a.filename)) {
                let _ = TankoubonDao.removeArchiveFromTankoubon(tankoubonId, arcid)
            }
        }

        // Append new items at end, following directory order.
        for (entryName in candidatesInOrder) {
            match (ArchiveDao.getByPathAndFilename(dirRelativePath, entryName)) {
                case Some(arch) =>
                    if (!currentSet.contains(arch.id)) {
                        let _ = TankoubonDao.addArchiveToTankoubonAppend(tankoubonId, arch.id)
                        currentSet.add(arch.id)
                    }
                case None => ()
            }
        }
    }
}

