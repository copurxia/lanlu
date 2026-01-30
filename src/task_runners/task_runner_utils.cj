package lanlu.task_runners

import std.collection.*
import std.fs.*
import std.io.{ByteBuffer, readToEnd}
import stdx.encoding.json.stream.*
import lanlu.utils.DirectoryScanner

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
}

