package cui.system

import lbase.CuiException

import std.collection.ArrayList
import std.fs.{Directory, FileInfo, Path, copy, exists, remove, rename}
import cui.base.{ensureSdl, lastSdlError}

public enum FileSystemEntryType {
    | Missing
    | File
    | Directory
    | Other
}

public struct PathInfo {
    public let entryType: FileSystemEntryType
    public let size: UInt64
    public let createTime: Int64
    public let modifyTime: Int64
    public let accessTime: Int64

    public init(
        entryType: FileSystemEntryType,
        size: UInt64,
        createTime: Int64,
        modifyTime: Int64,
        accessTime: Int64
    ) {
        this.entryType = entryType
        this.size = size
        this.createTime = createTime
        this.modifyTime = modifyTime
        this.accessTime = accessTime
    }
}

public class FileSystem {
    /**
     * Throws `CuiException` when the path is empty or SDL cannot create the directory tree.
     */

    public static func createDirectory(path: String) {
        ensurePathValue(path, "Path")
        // P5：改用 Cangjie 标准库（无 SDL）
        try {
            Directory.create(Path(path), recursive: true)
        } catch (e: Exception) {
            throw CuiException("createDirectory failed: ${e}")
        }
    }

    /**
     * Throws `CuiException` when the path is empty or SDL cannot remove the file or empty directory.
     */

    public static func remove(path: String) {
        ensurePathValue(path, "Path")
        try {
            remove(Path(path))
        } catch (e: Exception) {
            throw CuiException("remove failed: ${e}")
        }
    }

    /**
     * Throws `CuiException` when either path is empty or SDL cannot rename the file or directory.
     */

    public static func rename(oldPath: String, newPath: String) {
        ensurePathValue(oldPath, "Old path")
        ensurePathValue(newPath, "New path")
        try {
            rename(Path(oldPath), to: Path(newPath))
        } catch (e: Exception) {
            throw CuiException("rename failed: ${e}")
        }
    }

    /**
     * Throws `CuiException` when either path is empty or SDL cannot copy the source file.
     */

    public static func copyFile(source: String, destination: String) {
        ensurePathValue(source, "Source path")
        ensurePathValue(destination, "Destination path")
        try {
            copy(Path(source), to: Path(destination), overwrite: true)
        } catch (e: Exception) {
            throw CuiException("copyFile failed: ${e}")
        }
    }

    /**
     * Throws `CuiException` when the path is empty.
     */
    public static func pathInfo(path: String): ?PathInfo {
        ensurePathValue(path, "Path")
        // P5：改用 Cangjie 标准库（std.fs），不再经 SDL_GetPathInfo。
        // 注意：std.fs 的 FileInfo 不暴露访问/修改时间，这里以 0 表示"未知"。
        if (!exists(Path(path))) {
            return Some(PathInfo(FileSystemEntryType.Missing, 0u64, 0, 0, 0))
        }
        let info = try {
            FileInfo(Path(path))
        } catch (_: Exception) {
            return Some(PathInfo(FileSystemEntryType.Other, 0u64, 0, 0, 0))
        }
        let kind = if (info.isDirectory()) {
            FileSystemEntryType.Directory
        } else if (info.isRegular()) {
            FileSystemEntryType.File
        } else {
            FileSystemEntryType.Other
        }
        Some(PathInfo(kind, UInt64(info.size), 0, 0, 0))
    }

    /**
     * Throws `CuiException` when the path is empty.
     */

    public static func exists(path: String): Bool {
        ensurePathValue(path, "Path")
        exists(Path(path))
    }

    /**
     * Throws `CuiException` when the path is empty or SDL cannot enumerate the directory.
     */
    public static func globDirectory(
        path: String,
        pattern!: ?String = None,
        caseInsensitive!: Bool = false
    ): Array<String> {
        ensurePathValue(path, "Path")
        let cPath = unsafe { LibC.mallocCString(path) }
        let flags = globFlags(caseInsensitive)
        var results: Array<String> = []
        try (pathResource = cPath.asResource()) {
            match (pattern) {
                case Some(value) =>
                    let cPattern = unsafe { LibC.mallocCString(value) }
                    try (patternResource = cPattern.asResource()) {
                        results = globDirectoryRaw(pathResource.value, patternResource.value, flags)
                    }
                case None => results = globDirectoryRaw(pathResource.value, nullCString(), flags)
            }
        }
        results
    }
}

internal func entryTypeFromCode(code: Int32): FileSystemEntryType {
    if (code == SDL_PATHTYPE_NONE) {
        FileSystemEntryType.Missing
    } else if (code == SDL_PATHTYPE_FILE) {
        FileSystemEntryType.File
    } else if (code == SDL_PATHTYPE_DIRECTORY) {
        FileSystemEntryType.Directory
    } else if (code == SDL_PATHTYPE_OTHER) {
        FileSystemEntryType.Other
    } else {
        FileSystemEntryType.Missing
    }
}

internal func globFlags(caseInsensitive: Bool): UInt32 {
    if (caseInsensitive) {
        SDL_GLOB_CASEINSENSITIVE
    } else {
        UInt32(0)
    }
}

/**
 * Throws `CuiException` when SDL cannot enumerate the directory.
 */
private func globDirectoryRaw(path: CString, pattern: CString, flags: UInt32): Array<String> {
    var count: Int32 = 0
    let entries = unsafe { SDL_GlobDirectory(path, pattern, flags, inout count) }
    if (entries.isNull()) {
        throw CuiException("SDL_GlobDirectory failed: ${lastSdlError()}")
    }

    try {
        let results = ArrayList<String>()
        for (i in 0..Int64(count)) {
            let entry = unsafe { entries.read(i) }
            if (entry.isNotNull()) {
                results.add(CString(entry).toString())
            }
        }
        results.toArray()
    } finally {
        unsafe { SDL_free(CPointer<UInt8>(entries)) }
    }
}

private func nullCString(): CString {
    CString(CPointer<UInt8>())
}

/**
 * Throws `CuiException` when a filesystem path argument is empty.
 */
private func ensurePathValue(value: String, name: String): Unit {
    if (value.size <= 0) {
        throw CuiException("${name} cannot be empty.")
    }
}
