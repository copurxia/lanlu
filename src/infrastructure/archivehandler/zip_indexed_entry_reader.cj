package lanlu.infrastructure.archivehandler

import std.fs.*
import std.io.*
import stdx.compress.zlib.*
import lanlu.infrastructure.archiveindex.ArchivePackageEntryRecord

class LimitedFileInputStream <: InputStream & Resource {
    private var file: File
    private let length: Int64
    private var consumed: Int64 = 0
    private var closed: Bool = false

    public init(path: String, offset: Int64, length: Int64) {
        this.file = File(Path(path), Read)
        this.length = if (length > 0) { length } else { 0 }
        this.file.seek(SeekPosition.Begin(offset))
    }

    public func read(buffer: Array<Byte>): Int64 {
        if (closed || consumed >= length) {
            return 0
        }

        let remaining = length - consumed
        if (remaining >= Int64(buffer.size)) {
            let readLen = file.read(buffer)
            if (readLen > 0) {
                consumed += readLen
            }
            return readLen
        }

        let temp = Array<Byte>(remaining, repeat: 0)
        let readLen = file.read(temp)
        if (readLen > 0) {
            for (i in 0..readLen) {
                buffer[i] = temp[i]
            }
            consumed += readLen
        }
        return readLen
    }

    public func close(): Unit {
        if (closed) {
            return
        }
        closed = true
        file.close()
    }

    public func isClosed(): Bool {
        return closed
    }
}

class ZipStoredEntryReader <: EntryReader {
    private let rawStream: LimitedFileInputStream
    private let size: Int64

    public init(rawStream: LimitedFileInputStream, size: Int64) {
        this.rawStream = rawStream
        this.size = size
    }

    public func getSize(): Int64 {
        return size
    }

    public func read(buffer: Array<Byte>): Int64 {
        return rawStream.read(buffer)
    }

    public func close(): Unit {
        rawStream.close()
    }

    public func seek(_: Int64): Bool {
        return false
    }
}

class ZipDeflateEntryReader <: EntryReader {
    private let rawStream: LimitedFileInputStream
    private let inflater: DecompressInputStream
    private let size: Int64
    private var closed: Bool = false

    public init(rawStream: LimitedFileInputStream, inflater: DecompressInputStream, size: Int64) {
        this.rawStream = rawStream
        this.inflater = inflater
        this.size = size
    }

    public func getSize(): Int64 {
        return size
    }

    public func read(buffer: Array<Byte>): Int64 {
        if (closed) {
            return 0
        }
        try {
            return inflater.read(buffer)
        } catch (_: Exception) {
            closed = true
            return 0
        }
    }

    public func close(): Unit {
        if (closed) {
            return
        }
        closed = true
        try { inflater.close() } catch (_: Exception) {}
        rawStream.close()
    }

    public func seek(_: Int64): Bool {
        return false
    }
}

public class ZipIndexedEntryReaderFactory {
    public static func open(actualPath: String, entry: ArchivePackageEntryRecord): Option<EntryReader> {
        if (entry.dataOffset < 0 || entry.compressedSize < 0 || entry.uncompressedSize < 0 || entry.isEncrypted) {
            return None
        }

        if (entry.compressionMethod == 0) {
            let stream = LimitedFileInputStream(actualPath, entry.dataOffset, entry.compressedSize)
            return Some(ZipStoredEntryReader(stream, entry.uncompressedSize))
        }

        if (entry.compressionMethod == 8) {
            try {
                let stream = LimitedFileInputStream(actualPath, entry.dataOffset, entry.compressedSize)
                let inflater = DecompressInputStream(stream, wrap: DeflateFormat, bufLen: 4096)
                return Some(ZipDeflateEntryReader(stream, inflater, entry.uncompressedSize))
            } catch (_: Exception) {
                return None
            }
        }

        return None
    }
}
