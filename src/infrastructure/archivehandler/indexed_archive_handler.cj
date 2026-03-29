package lanlu.infrastructure.archivehandler

import std.collection.*
import lanlu.infrastructure.archiveindex.*

public class IndexedArchiveHandler <: ArchiveHandler {
    private let base: ArchiveHandler

    public init(base: ArchiveHandler) {
        this.base = base
    }

    public func getType(): String {
        return base.getType()
    }

    public func listEntries(archivePath: String): Array<String> {
        return base.listEntries(archivePath)
    }

    public func extractEntryToStream(archivePath: String, entryName: String): (Int64, Array<UInt8>, Array<UInt8>) {
        return base.extractEntryToStream(archivePath, entryName)
    }

    public func getEntryReader(archivePath: String, entryName: String): (Int64, Option<EntryReader>, String) {
        match (ArchivePackageIndexStore.getOrBuild(base.getType(), archivePath, { path => base.listEntriesWithTitle(path) })) {
            case Some(index) =>
                match (index.findEntry(entryName)) {
                    case Some(entry) =>
                        match (ZipIndexedEntryReaderFactory.open(archivePath, entry)) {
                            case Some(reader) => return (0i64, Some(reader), "")
                            case None => ()
                        }
                    case None => ()
                }
            case None => ()
        }
        return base.getEntryReader(archivePath, entryName)
    }

    public func extractEntryToFile(archivePath: String, entryName: String, outputPath: String): Bool {
        return base.extractEntryToFile(archivePath, entryName, outputPath)
    }

    public func getMediaCount(archivePath: String): Int32 {
        return base.getMediaCount(archivePath)
    }

    public func getFirstCoverEntry(archivePath: String): (String, String) {
        return base.getFirstCoverEntry(archivePath)
    }

    public func getCoverImage(archivePath: String): (Int64, Array<UInt8>, Array<UInt8>) {
        return base.getCoverImage(archivePath)
    }

    public func canHandle(filePath: String): Bool {
        return base.canHandle(filePath)
    }

    public func listEntriesWithTitle(archivePath: String): Array<(String, String)> {
        match (ArchivePackageIndexStore.getOrBuild(base.getType(), archivePath, { path => base.listEntriesWithTitle(path) })) {
            case Some(index) =>
                let entries = ArrayList<(String, String)>()
                for (entry in index.entries) {
                    entries.add((entry.name, entry.title))
                }
                return entries.toArray()
            case None => return base.listEntriesWithTitle(archivePath)
        }
    }
}
