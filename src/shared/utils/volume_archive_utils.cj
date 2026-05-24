package lanlu.shared.utils

import std.collection.*
import std.fs.*
import stdx.log.*

/**
 * 分卷/分片归档模式枚举
 */
public enum VolumePattern {
    | BinarySlice
    | SplitZip
    | RarVolume
    | NotVolume
}

/**
 * 枚举比较辅助函数（Cangjie 1.1.0 枚举不支持 Equatable 派生）
 */
public func volumePatternEq(a: VolumePattern, b: VolumePattern): Bool {
    match (a) {
        case BinarySlice => match (b) { case BinarySlice => return true; case _ => return false }
        case SplitZip => match (b) { case SplitZip => return true; case _ => return false }
        case RarVolume => match (b) { case RarVolume => return true; case _ => return false }
        case NotVolume => match (b) { case NotVolume => return true; case _ => return false }
    }
}

/**
 * 分卷文件检测结果
 */
public class VolumeGroupInfo {
    public var pattern: VolumePattern = VolumePattern.NotVolume
    public var isEntry: Bool = false
    public var entryPath: String = ""
    public var parts: Array<String> = []
    public var underlyingFormat: String = ""
    public var displayName: String = ""
    public var totalSize: Int64 = 0

    public func isValid(): Bool {
        match (pattern) {
            case VolumePattern.NotVolume => return false
            case _ => ()
        }
        return parts.size >= 1
    }
}

/**
 * 分卷/分片归档检测工具类。
 */
public class VolumeArchiveUtils {
    private static let logger = getLogger("volume_archive_utils")

    // 二进制切片前缀 → 底层格式
    private static let SLICE_PREFIX_FORMATS: Array<(String, String)> = [
        ("zip.part", "zip"),
        ("7z", "7z"),
        ("tar.gz", "tar.gz"),
        ("tgz", "tgz"),
        ("tar", "tar"),
    ]

    // ========== 公共接口 ==========

    public static func detectVolume(filePath: String): Option<VolumeGroupInfo> {
        let trimmed = filePath.trimAscii()
        if (trimmed.size == 0) {
            return None
        }

        let fileName = ArchiveUtils.getFullFileName(trimmed)
        let dirPath = FileUtils.getParentDirectory(trimmed)

        match (detectBinarySlice(fileName, dirPath)) {
            case Some(info) => return Some(info)
            case None => ()
        }
        match (detectSplitZip(fileName, dirPath)) {
            case Some(info) => return Some(info)
            case None => ()
        }
        match (detectRarVolume(fileName, dirPath)) {
            case Some(info) => return Some(info)
            case None => ()
        }
        return None
    }

    public static func isVolumeFollower(filePath: String): Bool {
        let fileName = ArchiveUtils.getFullFileName(filePath)
        let lower = fileName.toAsciiLower()

        if (endsWithDigitSequence(lower)) {
            if (lower.endsWith(".001")) {
                return false
            }
            return true
        }
        if (isSplitZipFollower(lower)) {
            return true
        }
        if (isRarVolumeFollower(lower)) {
            return true
        }
        return false
    }

    // ========== 内部工具 ==========

    private static func endsWithDigitSequence(name: String): Bool {
        if (name.size < 5) { return false }
        let dotPos = name.lastIndexOf(".")
        match (dotPos) {
            case None => return false
            case Some(pos) =>
                if (pos < 0 || pos >= name.size - 2) { return false }
                let suffix2 = name[pos..name.size]
                for (i in 1..suffix2.size) {
                    let c = suffix2[i]
                    let zero = UInt8(UInt32(r'0'))
                    let nine = UInt8(UInt32(r'9'))
                    if (c < zero || c > nine) {
                        return false
                    }
                }
                return true
        }
    }

    // ========== 二进制切片检测 ==========

    private static func detectBinarySlice(fileName: String, dirPath: String): Option<VolumeGroupInfo> {
        let lower = fileName.toAsciiLower()
        if (!lower.endsWith(".001")) {
            return None
        }

        let baseLen = lower.size - 4
        let baseName = fileName[0..baseLen]
        let lowerBase = lower[0..baseLen]

        var matchedPrefix = ""
        var matchedFormat = ""
        for (pair in SLICE_PREFIX_FORMATS) {
            let prefix = pair[0]
            if (lowerBase.endsWith(prefix)) {
                matchedPrefix = prefix
                matchedFormat = pair[1]
                break
            }
        }
        if (matchedPrefix.size == 0) {
            return None
        }

        let prefixTrimmed = matchedPrefix.trimEnd(".")
        let displayBase = if (lowerBase.endsWith(prefixTrimmed)) {
            baseName[0..baseLen - prefixTrimmed.size]
        } else {
            baseName
        }
        let cleanDisplay = displayBase.trimEnd(".")

        let partFiles = scanBinaryParts(lowerBase, dirPath)
        if (partFiles.size == 0) {
            logger.warn("binary slice detected but no parts found", ("baseName", baseName))
            return None
        }

        var totalSize: Int64 = 0
        for (p in partFiles) {
            totalSize += getFileSize(p)
        }

        let info = VolumeGroupInfo()
        info.pattern = VolumePattern.BinarySlice
        info.isEntry = true
        info.entryPath = FileUtils.joinPath(dirPath, "${baseName}.001")
        info.parts = partFiles
        info.underlyingFormat = matchedFormat
        info.displayName = cleanDisplay
        info.totalSize = totalSize
        return Some(info)
    }

    private static func scanBinaryParts(lowerBase: String, dirPath: String): Array<String> {
        let parts = ArrayList<String>()
        if (dirPath.size == 0 || !DirectoryScanner.directoryExists(dirPath)) {
            return parts.toArray()
        }

        let entries = DirectoryScanner.listDirectory(dirPath)
        var candidates = ArrayList<(String, Int64)>()

        for (entry in entries) {
            let lower = entry.toAsciiLower()
            if (!lower.startsWith(lowerBase)) { continue }
            let suffix = lower[lowerBase.size..lower.size]
            if (suffix.size < 2) { continue }
            let firstChar = suffix[0]
            let dotByte = UInt8(UInt32(r'.'))
            if (firstChar != dotByte) { continue }
            let numStr = suffix[1..suffix.size]
            let partNum = try {
                toInt64(numStr)
            } catch (_: Exception) {
                continue
            }
            if (partNum < 1) { continue }
            candidates.add((FileUtils.joinPath(dirPath, entry), partNum))
        }

        sortByPartNumber(candidates)

        for (pair in candidates) {
            parts.add(pair[0])
        }
        return parts.toArray()
    }

    // ========== Split Zip 检测 ==========

    private static func detectSplitZip(fileName: String, dirPath: String): Option<VolumeGroupInfo> {
        let lower = fileName.toAsciiLower()
        let isZipEntry = lower.endsWith(".zip")
        let isZ01Entry = lower.endsWith(".z01")
        if (!isZipEntry && !isZ01Entry) {
            return None
        }

        let baseLen = 4
        let baseName = fileName[0..fileName.size - baseLen]
        let lowerBase = baseName.toAsciiLower()

        let hasZ01 = hasSiblingWithExtension(dirPath, lowerBase, ".z01")
        if (!hasZ01 && isZipEntry) {
            return None
        }

        let entryPath = FileUtils.joinPath(dirPath, fileName)
        let parts = collectSplitZipParts(lowerBase, dirPath)
        if (parts.size == 0) {
            return None
        }

        var totalSize: Int64 = 0
        for (p in parts) {
            totalSize += getFileSize(p)
        }

        let info = VolumeGroupInfo()
        info.pattern = VolumePattern.SplitZip
        info.isEntry = true
        info.entryPath = entryPath
        info.parts = parts
        info.underlyingFormat = "zip"
        info.displayName = baseName
        info.totalSize = totalSize
        return Some(info)
    }

    private static func hasSiblingWithExtension(dirPath: String, baseName: String, ext: String): Bool {
        if (dirPath.size == 0 || !DirectoryScanner.directoryExists(dirPath)) {
            return false
        }
        let entries = DirectoryScanner.listDirectory(dirPath)
        for (entry in entries) {
            let lower = entry.toAsciiLower()
            if (lower.startsWith(baseName) && lower.endsWith(ext) && lower.size == baseName.size + ext.size) {
                return true
            }
        }
        return false
    }

    private static func collectSplitZipParts(lowerBase: String, dirPath: String): Array<String> {
        let parts = ArrayList<String>()
        if (dirPath.size == 0 || !DirectoryScanner.directoryExists(dirPath)) {
            return parts.toArray()
        }

        let entries = DirectoryScanner.listDirectory(dirPath)
        var indexedParts = ArrayList<(String, Int64)>()

        for (entry in entries) {
            let lower = entry.toAsciiLower()
            if (!lower.startsWith(lowerBase)) { continue }
            let suffix = lower[lowerBase.size..lower.size]

            if (suffix == ".zip") {
                // Split zip 的中央目录在最终 .zip，拼接时必须排在 .zNN 之后。
                indexedParts.add((FileUtils.joinPath(dirPath, entry), 1000))
                continue
            }
            let dotByte2 = UInt8(UInt32(r'.'))
            let zByte = UInt8(UInt32(r'z'))
            if (suffix.size == 4 && suffix[0] == dotByte2 && suffix[1] == zByte) {
                let numStr = suffix[2..4]
                let num = try {
                    toInt64(numStr)
                } catch (_: Exception) {
                    continue
                }
                if (num >= 1 && num <= 99) {
                    indexedParts.add((FileUtils.joinPath(dirPath, entry), num))
                }
            }
        }

        sortByPartNumber(indexedParts)
        for (pair in indexedParts) {
            parts.add(pair[0])
        }
        return parts.toArray()
    }

    // ========== RAR 分卷检测 ==========

    private static func detectRarVolume(fileName: String, dirPath: String): Option<VolumeGroupInfo> {
        let lower = fileName.toAsciiLower()

        if (detectRarPartEntry(lower)) {
            return buildRarPartInfo(fileName, lower, dirPath)
        }

        if (lower.endsWith(".rar")) {
            let baseName = fileName[0..fileName.size - 4]
            let lowerBase = baseName.toAsciiLower()
            if (hasSiblingWithExtension(dirPath, lowerBase, ".r00")) {
                return buildRarLegacyInfo(baseName, lowerBase, dirPath)
            }
        }
        return None
    }

    private static func detectRarPartEntry(lower: String): Bool {
        if (!lower.endsWith(".rar") && !lower.endsWith(".rev")) {
            return false
        }
        let extLen = 4
        let base = lower[0..lower.size - extLen]
        if (base.size < 6) { return false }
        let partIdx = base.lastIndexOf(".part")
        match (partIdx) {
            case None => return false
            case Some(idx) =>
                if (idx < 0) { return false }
                let numStr = base[idx + 5..base.size]
                if (numStr.size == 0) { return false }
                for (r in numStr) {
                    let zeroDigit = UInt8(UInt32(r'0'))
                    let nineDigit = UInt8(UInt32(r'9'))
                    if (r < zeroDigit || r > nineDigit) {
                        return false
                    }
                }
                let num = try { toInt64(numStr) } catch (_: Exception) { 0 }
                return num >= 1
        }
    }

    private static func buildRarPartInfo(fileName: String, lower: String, dirPath: String): Option<VolumeGroupInfo> {
        let extLen = 4
        let lowerBase = lower[0..lower.size - extLen]
        let partIdx = lowerBase.lastIndexOf(".part")
        match (partIdx) {
            case None => return None
            case Some(idx) =>
                let baseName = fileName[0..idx]
                let lowerBaseName = lowerBase[0..idx]
                let parts = collectRarParts(lowerBaseName, dirPath)
                var totalSize: Int64 = 0
                for (p in parts) {
                    totalSize += getFileSize(p)
                }
                let info = VolumeGroupInfo()
                info.pattern = VolumePattern.RarVolume
                info.isEntry = true
                info.entryPath = FileUtils.joinPath(dirPath, fileName)
                info.parts = parts
                info.underlyingFormat = "rar"
                info.displayName = baseName
                info.totalSize = totalSize
                return Some(info)
        }
    }

    private static func buildRarLegacyInfo(baseName: String, lowerBase: String, dirPath: String): Option<VolumeGroupInfo> {
        let parts = ArrayList<String>()
        if (dirPath.size == 0 || !DirectoryScanner.directoryExists(dirPath)) {
            return None
        }

        let entries = DirectoryScanner.listDirectory(dirPath)
        var indexedParts = ArrayList<(String, Int64)>()

        for (entry in entries) {
            let lower = entry.toAsciiLower()
            if (!lower.startsWith(lowerBase)) { continue }
            let suffix = lower[lowerBase.size..lower.size]
            if (suffix == ".rar") {
                indexedParts.add((FileUtils.joinPath(dirPath, entry), 0))
                continue
            }
            let dotByte3 = UInt8(UInt32(r'.'))
            let rByte = UInt8(UInt32(r'r'))
            if (suffix.size == 4 && suffix[0] == dotByte3 && suffix[1] == rByte) {
                let numStr = suffix[2..4]
                let num = try {
                    toInt64(numStr)
                } catch (_: Exception) {
                    continue
                }
                indexedParts.add((FileUtils.joinPath(dirPath, entry), num + 1))
            }
        }

        sortByPartNumber(indexedParts)

        var totalSize: Int64 = 0
        for (pair in indexedParts) {
            parts.add(pair[0])
            totalSize += getFileSize(pair[0])
        }

        if (parts.size <= 1) {
            return None
        }

        let info = VolumeGroupInfo()
        info.pattern = VolumePattern.RarVolume
        info.isEntry = true
        info.entryPath = parts[0]
        info.parts = parts.toArray()
        info.underlyingFormat = "rar"
        info.displayName = baseName
        info.totalSize = totalSize
        return Some(info)
    }

    private static func collectRarParts(lowerBaseName: String, dirPath: String): Array<String> {
        let parts = ArrayList<String>()
        if (dirPath.size == 0 || !DirectoryScanner.directoryExists(dirPath)) {
            return parts.toArray()
        }

        let entries = DirectoryScanner.listDirectory(dirPath)
        var indexedParts = ArrayList<(String, Int64)>()

        for (entry in entries) {
            let lower = entry.toAsciiLower()
            if (!lower.startsWith(lowerBaseName)) { continue }
            let suffix = lower[lowerBaseName.size..lower.size]
            if (suffix.startsWith(".part") && (suffix.endsWith(".rar") || suffix.endsWith(".rev"))) {
                let mid = suffix[5..suffix.size]
                let extDot = mid.lastIndexOf(".")
                match (extDot) {
                    case None => continue
                    case Some(dotIdx) =>
                        let numStr = mid[0..dotIdx]
                        let num = try {
                            toInt64(numStr)
                        } catch (_: Exception) {
                            continue
                        }
                        if (num >= 1) {
                            indexedParts.add((FileUtils.joinPath(dirPath, entry), num))
                        }
                }
            }
        }

        sortByPartNumber(indexedParts)
        for (pair in indexedParts) {
            parts.add(pair[0])
        }
        return parts.toArray()
    }

    private static func isRarVolumeFollower(lower: String): Bool {
        if (lower.endsWith(".rar") || lower.endsWith(".rev")) {
            let extLen = 4
            let base = lower[0..lower.size - extLen]
            if (base.size >= 6) {
                let partIdxOpt = base.lastIndexOf(".part")
                match (partIdxOpt) {
                    case Some(idx) =>
                        let numStr = base[idx + 5..base.size]
                        if (numStr.size > 0) {
                            let num = try { toInt64(numStr) } catch (_: Exception) { 0 }
                            return num >= 2
                        }
                    case None => ()
                }
            }
        }
        // .r00 ~ .r99
        if (lower.size >= 4) {
            let ext = lower[lower.size - 4..lower.size]
            let r0 = ext[0]
            let r1 = ext[1]
            let r2 = ext[2]
            let r3 = ext[3]
            let dot = UInt8(UInt32(r'.'))
            let rChar = UInt8(UInt32(r'r'))
            let zero = UInt8(UInt32(r'0'))
            let nine = UInt8(UInt32(r'9'))
            if (r0 == dot && r1 == rChar && r2 >= zero && r2 <= nine && r3 >= zero && r3 <= nine) {
                let numStr = ext[2..4]
                let num = try { toInt64(numStr) } catch (_: Exception) { -1 }
                if (num >= 0) {
                    return true
                }
            }
        }
        return false
    }

    private static func isSplitZipFollower(lower: String): Bool {
        if (lower.size < 4) {
            return false
        }
        let ext = lower[lower.size - 4..lower.size]
        let dot = UInt8(UInt32(r'.'))
        let zChar = UInt8(UInt32(r'z'))
        let zero = UInt8(UInt32(r'0'))
        let nine = UInt8(UInt32(r'9'))
        if (ext[0] != dot || ext[1] != zChar || ext[2] < zero || ext[2] > nine || ext[3] < zero || ext[3] > nine) {
            return false
        }
        let num = try { toInt64(ext[2..4]) } catch (_: Exception) { 0 }
        return num >= 2 && num <= 99
    }

    // ========== 通用工具 ==========

    private static func getFileSize(filePath: String): Int64 {
        try {
            let path = Path(filePath)
            if (!exists(path)) { return 0 }
            let file = File(path, Read)
            let size = file.info.size
            file.close()
            return size
        } catch (_: Exception) {
            return 0
        }
    }

    private static func toInt64(s: String): Int64 {
        var result: Int64 = 0
        for (r in s.toRuneArray()) {
            let digit = Int64(UInt32(r) - UInt32(r'0'))
            result = result * 10 + digit
        }
        return result
    }

    private static func sortByPartNumber(candidates: ArrayList<(String, Int64)>): Unit {
        let n = candidates.size
        for (i in 0..n) {
            for (j in 0..(n - i - 1)) {
                if (candidates[j][1] > candidates[j + 1][1]) {
                    let tmp = candidates[j]
                    candidates[j] = candidates[j + 1]
                    candidates[j + 1] = tmp
                }
            }
        }
    }
}
