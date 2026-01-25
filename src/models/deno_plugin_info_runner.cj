package lrr4cj.models

import std.convert.*
import std.fs.*
import std.io.*
import std.process.*
import std.time.*
import stdx.encoding.json.stream.*

/**
 * Helper to execute a TypeScript plugin in a sandboxed temp directory and fetch its plugin_info.
 *
 * Used by both plugin scan and install/update flows.
 */
public class DenoPluginInfoRunner {
    private static func getCurrentTimeMillis(): Int64 {
        // DateTime resolution is seconds; scale to ms for readability.
        // Uniqueness also includes uniqueId + fileName.
        DateTime.now().toUnixTimeStamp().toSeconds() * 1000
    }

    /**
     * Execute the plugin file with stdin `{action:"plugin_info"}`.
     * Returns: (exitCode, stdout, stderr)
     *
     * Security: --allow-read is scoped to the temporary root only.
     */
    public static func runPluginInfo(filePath: String, uniqueId: String): (Int32, String, String) {
        let inputPath = filePath.trimAscii()
        if (inputPath.size == 0) { return (1, "", "empty filePath") }

        // Infer a type directory name from the parent folder (best-effort).
        let pathParts = inputPath.split("/")
        let pluginTypeDir = if (pathParts.size >= 2) { pathParts[pathParts.size - 2] } else { "Temp" }

        let fileName = Path(inputPath).fileName.toString()
        let safeFileName = fileName.replace(".", "_")

        // Avoid path traversal / separators in uniqueId.
        let safeId = uniqueId.replace("/", "_").replace("..", "_")

        let tempRoot = Path("${PluginPaths.getPluginInfoTempRoot()}/${safeId}/${getCurrentTimeMillis().toString()}_${pluginTypeDir}_${safeFileName}")
        let pluginsRoot = Path("${tempRoot.toString()}/plugins")
        let tempTypeDir = Path("${pluginsRoot.toString()}/${pluginTypeDir}")

        try {
            Directory.create(tempTypeDir, recursive: true)

            // Copy base_plugin.ts so plugins can import `../base_plugin.ts`.
            let baseSource = Path("./plugins/base_plugin.ts")
            let baseTarget = Path("${pluginsRoot.toString()}/base_plugin.ts")
            if (exists(baseSource)) {
                copy(baseSource, to: baseTarget, overwrite: true)
            }

            // Copy plugin file into the simulated ./plugins/<Type>/ layout.
            let tempPluginFile = Path("${tempTypeDir.toString()}/${fileName}")
            copy(Path(inputPath), to: tempPluginFile, overwrite: true)

            let process = launch("deno", [
                "run",
                "--allow-read=${tempRoot.toString()}",
                tempPluginFile.toString()
            ],
                stdIn: ProcessRedirect.Pipe,
                stdOut: ProcessRedirect.Pipe,
                stdErr: ProcessRedirect.Pipe)

            let inputJson = "{\"action\":\"plugin_info\",\"pluginType\":\"\"}\n"
            process.stdInPipe.write(inputJson.toArray())
            process.stdInPipe.flush()

            let (exitCode, stdoutBytes, stderrBytes) = process.waitOutput()

            let stdoutStr = if (stdoutBytes.size > 0) { String.fromUtf8(stdoutBytes) } else { "" }
            let stderrStr = if (stderrBytes.size > 0) { String.fromUtf8(stderrBytes) } else { "" }

            try { remove(tempRoot, recursive: true) } catch (_: Exception) {}
            return (Int32(exitCode), stdoutStr, stderrStr)
        } catch (e: Exception) {
            try {
                if (exists(tempRoot)) {
                    remove(tempRoot, recursive: true)
                }
            } catch (_: Exception) {}
            return (1, "", e.message)
        }
    }

    /**
     * Extract the `data` payload from an NDJSON stream.
     *
     * Supports:
     * - NDJSON lines: {type:"result", success:true, data:{...}}
     * - Single JSON object (legacy): {success:true, data:{...}}
     */
    public static func extractPluginInfoDataFromNdjson(output: String): String {
        let trimmedAll = output.trimAscii()
        if (trimmedAll.size == 0) { return "" }

        let lines = trimmedAll.split("\n")
        for (line in lines) {
            let trimmed = line.trimAscii()
            if (trimmed.size == 0) { continue }

            try {
                var buf = ByteBuffer()
                unsafe { buf.write(trimmed.rawData()) }
                let r = JsonReader(buf)

                func readBoolFlexible(): Bool {
                    let v = r.readValue<String>().trimAscii().toAsciiLower()
                    return v == "true" || v == "1"
                }

                var msgType = ""
                var hasType = false
                var successSeen = false
                var success = false
                var dataRaw: Option<String> = None

                if (r.peek() != Some(BeginObject)) { continue }
                r.startObject()
                while (r.peek() != EndObject) {
                    let k = r.readName()
                    match (k) {
                        case "type" =>
                            hasType = true
                            msgType = r.readValue<String>().trimAscii()
                        case "success" =>
                            successSeen = true
                            success = readBoolFlexible()
                        case "data" =>
                            let bytes = r.readValueBytes()
                            dataRaw = Some(String.fromUtf8(bytes))
                        case _ =>
                            r.skip()
                    }
                }
                r.endObject()

                // NDJSON result message.
                if (hasType && msgType == "result" && success) {
                    match (dataRaw) {
                        case Some(s) => return s
                        case None => ()
                    }
                }

                // Legacy single-object output.
                if (!hasType && successSeen && success) {
                    match (dataRaw) {
                        case Some(s) => return s
                        case None => ()
                    }
                }
            } catch (_: Exception) {
                // Ignore parse errors and keep scanning.
            }
        }

        return ""
    }
}
