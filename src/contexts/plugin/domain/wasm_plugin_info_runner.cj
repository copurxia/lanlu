package lanlu.contexts.plugin.domain

import std.fs.*

public class WasmPluginInfoRunner {
    public static func resolveWasmPath(wasmPath: String): (Bool, String, String) {
        let trimmedPath = wasmPath.trimAscii()
        if (trimmedPath.size == 0) {
            return (false, "", "empty wasm path")
        }
        if (!exists(Path(trimmedPath))) {
            return (false, "", "wasm not found: ${trimmedPath}")
        }
        if (!trimmedPath.toAsciiLower().endsWith(".wasm")) {
            return (false, "", "not a wasm plugin file: ${trimmedPath}")
        }
        return (true, trimmedPath, "")
    }

    public static func runPluginInfo(wasmPath: String): (Bool, String, String, String) {
        let (okPath, normalizedPath, pathErr) = resolveWasmPath(wasmPath)
        if (!okPath) {
            return (false, "", "", pathErr)
        }
        let (ok, json, err) = WasmHostBridge.readPluginInfoJson(normalizedPath)
        return (ok, normalizedPath, json, err)
    }
}
