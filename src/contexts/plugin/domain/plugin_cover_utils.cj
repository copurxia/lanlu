package lanlu.contexts.plugin.domain

import std.fs.*
import std.time.*
import std.collection.*
import lanlu.contexts.asset.infrastructure.persistence.*
import lanlu.contexts.system.application.SystemSettingsService
import lanlu.shared.utils.*

/**
 * Plugin cover helper:
 * - resolve plugin-returned cover path under plugin cache
 * - convert cover into AVIF asset
 * - cleanup old assets
 */
public class PluginCoverUtils {
    private static let runtimeFileWaitAttempts: Int64 = 10
    private static let runtimeFileWaitIntervalMs: Int64 = 120

    private static func normalizeRelPath(input: String): String {
        var s = input.trimAscii().replace("\\", "/")
        while (s.startsWith("/")) { s = s[1..s.size] }
        let parts = s.split("/")
        var outParts = ArrayList<String>()
        for (p in parts) {
            let t = p.trimAscii()
            if (t.size == 0 || t == "." || t == "..") { continue }
            if (t.contains("/") || t.contains("\\")) { continue }
            outParts.add(t)
        }
        return String.join(outParts.toArray(), delimiter: "/")
    }

    private static func normalizePluginCoverRelativePath(coverPath: String, pluginNamespace: String): String {
        let ns = pluginNamespace.trimAscii()
        var rel = normalizeRelPath(coverPath)
        if (rel.size == 0) { return "" }

        if (rel.startsWith("plugins/")) {
            let parts = rel.split("/")
            if (parts.size < 3) { return "" }
            let nsFromPath = parts[1].trimAscii()
            if (nsFromPath.size == 0) { return "" }
            if (ns.size > 0 && nsFromPath != ns) { return "" }
            return rel
        }

        if (ns.size == 0) {
            return ""
        }

        if (rel.startsWith("cache/")) {
            return "plugins/${ns}/${rel}"
        }
        return "plugins/${ns}/cache/${rel}"
    }

    private static func waitForPluginRuntimeFile(absPath: String): Bool {
        let target = Path(absPath)
        var lastObservedSize: Int64 = -1
        var stablePositiveChecks: Int64 = 0
        var attempt: Int64 = 0
        while (attempt <= runtimeFileWaitAttempts) {
            if (exists(target)) {
                let currentSize = try {
                    Int64(FileInfo(target).size)
                } catch (_: Exception) {
                    0
                }
                if (currentSize > 0) {
                    if (currentSize == lastObservedSize) {
                        stablePositiveChecks += 1
                    } else {
                        stablePositiveChecks = 0
                    }
                    lastObservedSize = currentSize
                    if (stablePositiveChecks > 0 || attempt >= runtimeFileWaitAttempts) {
                        return true
                    }
                }
            }

            if (attempt >= runtimeFileWaitAttempts) {
                if (exists(target)) {
                    return true
                }
                break
            }

            attempt += 1
            sleep(Duration.millisecond * runtimeFileWaitIntervalMs)
        }
        return false
    }

    private static func resolvePluginRuntimePath(rawPath: String, pluginNamespace: String): (String, String) {
        let rel = normalizePluginCoverRelativePath(rawPath, pluginNamespace)
        if (rel.size == 0) {
            return ("", "invalid plugin runtime path")
        }

        let cacheRoot = SystemSettingsService.getPath("CACHE_PATH")
        let runtimeRoot = PluginPaths.getPluginRuntimeRoot()
        let abs = FileUtils.joinPath(cacheRoot, rel)

        var resolvedRuntimeRoot = runtimeRoot
        var resolvedAbs = abs
        try {
            resolvedRuntimeRoot = FileUtils.resolvePath(runtimeRoot)
            resolvedAbs = FileUtils.resolvePath(abs)
        } catch (_: Exception) {}

        var cleanRoot = resolvedRuntimeRoot.trimAscii()
        var cleanAbs = resolvedAbs.trimAscii()
        while (cleanRoot.size > 1 && cleanRoot.endsWith("/")) { cleanRoot = cleanRoot[0..(cleanRoot.size - 1)] }
        while (cleanAbs.size > 1 && cleanAbs.endsWith("/")) { cleanAbs = cleanAbs[0..(cleanAbs.size - 1)] }

        if (!(cleanAbs == cleanRoot || cleanAbs.startsWith("${cleanRoot}/"))) {
            return ("", "plugin path is outside plugin runtime root")
        }
        if (!waitForPluginRuntimeFile(cleanAbs)) {
            return ("", "plugin file not found")
        }

        return (cleanAbs, "")
    }

    private static func resolvePluginCoverPath(coverPath: String, pluginNamespace: String): (String, String) {
        let (resolvedPath, err) = resolvePluginRuntimePath(coverPath, pluginNamespace)
        if (resolvedPath.size == 0) {
            if (err.trimAscii().size == 0) {
                return ("", "invalid plugin cover path")
            }
            return ("", err.replace("plugin file", "cover file"))
        }
        return (resolvedPath, "")
    }

    private static func inferExtensionFromPath(path: String): String {
        let normalized = path.trimAscii().toAsciiLower().replace("\\", "/")
        let fileName = if (normalized.contains("/")) {
            let parts = normalized.split("/")
            parts[parts.size - 1]
        } else {
            normalized
        }
        let ext = FileUtils.getFileExtensionWithoutDot(fileName).trimAscii().toAsciiLower()
        if (ext.size == 0) {
            return "bin"
        }
        return ext
    }

    private static func inferMimeTypeByExtension(ext: String): String {
        let normalized = ext.trimAscii().toAsciiLower()
        match (normalized) {
            case "txt" => return "text/plain"
            case "lrc" => return "text/plain"
            case "json" => return "application/json"
            case "xml" => return "application/xml"
            case "srt" => return "application/x-subrip"
            case "vtt" => return "text/vtt"
            case "mp3" => return "audio/mpeg"
            case "flac" => return "audio/flac"
            case "m4a" => return "audio/mp4"
            case "aac" => return "audio/aac"
            case "ogg" => return "audio/ogg"
            case "opus" => return "audio/opus"
            case "wav" => return "audio/wav"
            case "jpg" => return "image/jpeg"
            case "jpeg" => return "image/jpeg"
            case "png" => return "image/png"
            case "webp" => return "image/webp"
            case "gif" => return "image/gif"
            case "avif" => return "image/avif"
            case _ => return "application/octet-stream"
        }
    }

    /**
     * Convert plugin cache cover to AVIF asset.
     * Returns: (ok, assetId, thumbhash, error)
     */
    public static func installCoverAssetFromPluginPath(coverPath: String, pluginNamespace: String, assetKind: String, originalName: String): (Bool, Int64, String, String) {
        let (sourcePath, resolveErr) = resolvePluginCoverPath(coverPath, pluginNamespace)
        if (sourcePath.size == 0) {
            return (false, 0, "", resolveErr)
        }

        let cacheRoot = SystemSettingsService.getPath("CACHE_PATH")
        let assetPath = SystemSettingsService.getPath("ASSET_PATH")
        let stamp = DateTime.now().toUnixTimeStamp().toMilliseconds().toString()
        let tempDir = FileUtils.joinPath(cacheRoot, "plugin_cover_install/${pluginNamespace}_${stamp}")
        let tempAvifPath = FileUtils.joinPath(tempDir, "cover.avif")

        try {
            FileUtils.ensureDirectoryExists(Path(tempDir))
            FileUtils.ensureDirectoryExists(Path(assetPath))
        } catch (e: Exception) {
            return (false, 0, "", "failed to prepare temp/asset directory: ${e.message}")
        }

        let (convertResult, thumbHash) = ArchiveUtils.convertImageToAvifWithThumbHash(sourcePath, tempAvifPath, tempDir)
        if (!convertResult.success) {
            try { let _ = FileUtils.removeFileOrDirectory(tempDir) } catch (_: Exception) {}
            return (false, 0, "", "cover conversion failed: ${convertResult.error}")
        }

        let avifSize = try { Int64(FileInfo(Path(tempAvifPath)).size) } catch (_: Exception) { 0 }
        match (AssetDao.create(None, assetKind, originalName, "image/avif", "avif", avifSize, thumbHash)) {
            case Some(assetId) =>
                let finalPath = FileUtils.joinPath(assetPath, "${assetId}.avif")
                try {
                    FileUtils.safeReplaceFile(Path(finalPath), Path(tempAvifPath))
                } catch (e: Exception) {
                    let _ = AssetDao.deleteById(assetId)
                    try { let _ = FileUtils.removeFileOrDirectory(tempDir) } catch (_: Exception) {}
                    return (false, 0, "", "failed to move cover asset file: ${e.message}")
                }
                try { let _ = FileUtils.removeFileOrDirectory(tempDir) } catch (_: Exception) {}
                return (true, assetId, thumbHash, "")
            case None =>
                try { let _ = FileUtils.removeFileOrDirectory(tempDir) } catch (_: Exception) {}
                return (false, 0, "", "failed to create asset record")
        }
    }

    /**
     * Copy plugin runtime file into asset storage without conversion.
     * Returns: (ok, assetId, error)
     */
    public static func installRawAssetFromPluginPath(path: String, pluginNamespace: String, assetKind: String, originalName: String): (Bool, Int64, String) {
        let (sourcePath, resolveErr) = resolvePluginRuntimePath(path, pluginNamespace)
        if (sourcePath.size == 0) {
            return (false, 0, resolveErr)
        }

        let ext = inferExtensionFromPath(sourcePath)
        let contentType = inferMimeTypeByExtension(ext)
        let sourceSize = try { Int64(FileInfo(Path(sourcePath)).size) } catch (_: Exception) { 0 }
        let safeOriginalName = if (originalName.trimAscii().size > 0) {
            originalName.trimAscii()
        } else {
            "plugin_asset.${ext}"
        }

        let assetRoot = SystemSettingsService.getPath("ASSET_PATH")
        try {
            FileUtils.ensureDirectoryExists(Path(assetRoot))
        } catch (e: Exception) {
            return (false, 0, "failed to prepare asset directory: ${e.message}")
        }

        match (AssetDao.create(None, assetKind, safeOriginalName, contentType, ext, sourceSize, "")) {
            case Some(assetId) =>
                let finalPath = FileUtils.joinPath(assetRoot, "${assetId}.${ext}")
                try {
                    copy(Path(sourcePath), to: Path(finalPath), overwrite: true)
                    return (true, assetId, "")
                } catch (e: Exception) {
                    let _ = AssetDao.deleteById(assetId)
                    return (false, 0, "failed to copy plugin asset file: ${e.message}")
                }
            case None =>
                return (false, 0, "failed to create asset record")
        }
    }

    /**
     * Best-effort remove asset file + DB row.
     */
    public static func deleteAsset(assetId: Int64): Unit {
        if (assetId <= 0) { return }
        try {
            let row = AssetDao.getById(assetId)
            let ext = if (row.fileExt.trimAscii().size > 0) { row.fileExt.trimAscii() } else { "avif" }
            let assetPath = FileUtils.joinPath(SystemSettingsService.getPath("ASSET_PATH"), "${assetId}.${ext}")
            try { remove(Path(assetPath)) } catch (_: Exception) {}
            let _ = AssetDao.deleteById(assetId)
        } catch (_: Exception) {}
    }
}
