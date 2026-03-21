package lanlu.contexts.task.application.runners

import std.collection.*
import std.convert.*
import std.fs.*
import std.io.{ByteBuffer, readToEnd}
import stdx.encoding.json.stream.*
import lanlu.shared.utils.DirectoryScanner
import lanlu.shared.utils.FileUtils
import lanlu.contexts.asset.infrastructure.persistence.{AssetDao, AssetRow}

/**
 * Shared helpers for task runners to reduce copy/paste across runners.
 *
 * Keep this focused: small IO/fs helpers + JSON helpers that are used in multiple runners.
 */
public class TaskRunnerUtils {
    public static func fail(taskId: Int64, message: String): Unit {
        TaskRunnerOutput.fail(taskId, message)
    }

    public static func removeFile(path: String): Bool {
        try {
            remove(Path(path))
            return true
        } catch (_: Exception) {
            return false
        }
    }

    public static func fileExists(path: String): Bool {
        return DirectoryScanner.fileExists(path)
    }

    public static func directoryExists(path: String): Bool {
        return DirectoryScanner.directoryExists(path)
    }

    public static func listDirectory(path: String): Array<String> {
        return DirectoryScanner.listDirectory(path)
    }

    public static func joinPath(base: String, part: String): String {
        return DirectoryScanner.joinPath(base, part)
    }

    public static func errorsToJson(errors: ArrayList<String>): String {
        if (errors.size == 0) {
            return "[]"
        }
        let out = ByteBuffer()
        let w = JsonWriter(out)
        w.startArray()
        for (e in errors) {
            w.writeValue(e)
        }
        w.endArray()
        w.flush()
        return String.fromUtf8(readToEnd(out))
    }

    public static func parseField(parameters: String, key: String): String {
        let trimmed = parameters.trimAscii()
        if (trimmed.size == 0) {
            return ""
        }
        try {
            var buf = ByteBuffer()
            unsafe { buf.write(trimmed.rawData()) }
            let r = JsonReader(buf)
            if (r.peek() != Some(BeginObject)) { return "" }
            r.startObject()
            while (r.peek() != EndObject) {
                let k = r.readName()
                if (k == key) {
                    return r.readValue<String>().trimAscii()
                } else {
                    r.skip()
                }
            }
            r.endObject()
        } catch (_: Exception) {}
        return ""
    }

    public static func parseInt64Safely(value: String): Int64 {
        if (value.size == 0) {
            return 0
        }
        try {
            return Int64.parse(value)
        } catch (_: Exception) {
            return 0
        }
    }

    public static func resolveAssetExt(asset: AssetRow, filename: String): String {
        if (asset.fileExt.trimAscii().size > 0) {
            return asset.fileExt.trimAscii().toAsciiLower()
        }
        let ext = FileUtils.getFileExtensionWithoutDot(filename).trimAscii().toAsciiLower()
        if (ext.size > 0) {
            return ext
        }
        return "bin"
    }

    public static func cleanupStagingAssetByPath(assetId: Int64, stagingPath: String): Unit {
        if (assetId <= 0) {
            return
        }
        try {
            if (exists(Path(stagingPath))) {
                try { remove(Path(stagingPath)) } catch (_: Exception) {}
            }
        } catch (_: Exception) {}
        let _ = AssetDao.deleteById(assetId)
    }

    public static func cleanupStagingAssetInRoot(assetRoot: String, assetId: Int64, extHint: String): Unit {
        if (assetId <= 0) {
            return
        }
        let row = AssetDao.getById(assetId)
        let ext = if (extHint.size > 0) { extHint }
            else if (row.fileExt.trimAscii().size > 0) { row.fileExt.trimAscii().toAsciiLower() }
            else { "bin" }
        let path = FileUtils.joinPath(assetRoot, "${assetId}.${ext}")
        cleanupStagingAssetByPath(assetId, path)
    }
}
