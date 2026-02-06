package lanlu.models

import std.fs.*
import std.time.*
import std.collection.*
import lanlu.dao.*
import lanlu.utils.*

/**
 * Plugin cover helper:
 * - resolve plugin-returned cover path under plugin cache
 * - convert cover into AVIF asset
 * - cleanup old assets
 */
public class PluginCoverUtils {
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

    private static func resolvePluginCoverPath(coverPath: String, pluginNamespace: String): (String, String) {
        let rel = normalizePluginCoverRelativePath(coverPath, pluginNamespace)
        if (rel.size == 0) {
            return ("", "invalid plugin cover path")
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
            return ("", "cover path is outside plugin runtime root")
        }
        if (!exists(Path(cleanAbs))) {
            return ("", "cover file not found")
        }

        return (cleanAbs, "")
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
