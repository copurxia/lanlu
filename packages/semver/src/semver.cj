package semver

import std.convert.*

/**
 * 语义化版本号
 */
public class SemVer {
    public var major: Int64 = 0
    public var minor: Int64 = 0
    public var patch: Int64 = 0

    public init() {}

    public init(major: Int64, minor: Int64, patch: Int64) {
        this.major = major
        this.minor = minor
        this.patch = patch
    }

    public func toString(): String {
        "${major}.${minor}.${patch}"
    }
}

/**
 * 版本比较结果
 */
public enum VersionCompareResult {
    | Equal           // 版本相同
    | MajorUpgrade    // 主版本升级（破坏性更新）
    | MinorUpgrade    // 次版本升级
    | PatchUpgrade    // 补丁版本升级
    | Downgrade       // 版本降级
    | Invalid         // 无效版本
}

/**
 * 解析版本字符串为 SemVer 对象
 * 支持格式: "1.2.3", "1.2", "1"
 */
public func parse(version: String): Option<SemVer> {
    let trimmed = version.trimAscii()
    if (trimmed.isEmpty()) {
        return None
    }

    let parts = trimmed.split(".")
    if (parts.size == 0 || parts.size > 3) {
        return None
    }

    var major: Int64 = 0
    var minor: Int64 = 0
    var patch: Int64 = 0

    // 解析 major
    let majorOpt = parseNumber(parts[0])
    match (majorOpt) {
        case Some(v) => major = v
        case None => return None
    }

    // 解析 minor（可选）
    if (parts.size >= 2) {
        let minorOpt = parseNumber(parts[1])
        match (minorOpt) {
            case Some(v) => minor = v
            case None => return None
        }
    }

    // 解析 patch（可选）
    if (parts.size >= 3) {
        let patchOpt = parseNumber(parts[2])
        match (patchOpt) {
            case Some(v) => patch = v
            case None => return None
        }
    }

    Some(SemVer(major, minor, patch))
}

/**
 * 比较两个版本字符串
 */
public func compare(oldVersion: String, newVersion: String): VersionCompareResult {
    let oldOpt = parse(oldVersion)
    let newOpt = parse(newVersion)

    match ((oldOpt, newOpt)) {
        case (Some(oldVer), Some(newVer)) =>
            compareVersions(oldVer, newVer)
        case _ =>
            VersionCompareResult.Invalid
    }
}

/**
 * 比较两个 SemVer 对象
 */
public func compareVersions(oldVer: SemVer, newVer: SemVer): VersionCompareResult {
    // 比较 major
    if (newVer.major > oldVer.major) {
        return VersionCompareResult.MajorUpgrade
    }
    if (newVer.major < oldVer.major) {
        return VersionCompareResult.Downgrade
    }

    // major 相同，比较 minor
    if (newVer.minor > oldVer.minor) {
        return VersionCompareResult.MinorUpgrade
    }
    if (newVer.minor < oldVer.minor) {
        return VersionCompareResult.Downgrade
    }

    // minor 相同，比较 patch
    if (newVer.patch > oldVer.patch) {
        return VersionCompareResult.PatchUpgrade
    }
    if (newVer.patch < oldVer.patch) {
        return VersionCompareResult.Downgrade
    }

    VersionCompareResult.Equal
}

/**
 * 解析数字字符串
 */
func parseNumber(s: String): Option<Int64> {
    let trimmed = s.trimAscii()
    if (trimmed.isEmpty()) {
        return None
    }

    try {
        let num = Int64.parse(trimmed)
        if (num < 0) {
            return None
        }
        Some(num)
    } catch (_: Exception) {
        None
    }
}
