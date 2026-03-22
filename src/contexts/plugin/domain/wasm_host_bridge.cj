package lanlu.contexts.plugin.domain

import std.collection.*
import std.convert.*
import std.fs.*
import std.io.*
import std.io.{ByteBuffer, readToEnd}
import std.net.*
import std.process.*
import std.sync.*
import std.time.*
import stdx.crypto.digest.*
import stdx.encoding.hex.*
import stdx.encoding.json.stream.*
import wasmedge_ffi.*
import lanlu.contexts.archive.domain.*
import lanlu.contexts.archive.infrastructure.persistence.*
import lanlu.contexts.category.infrastructure.persistence.*
import lanlu.contexts.metadata.infrastructure.persistence.*
import lanlu.contexts.tag.infrastructure.persistence.*
import lanlu.contexts.tankoubon.infrastructure.persistence.*
import lanlu.contexts.task.domain.*
import lanlu.contexts.task.infrastructure.persistence.*
import lanlu.infrastructure.archivehandler.*
import lanlu.shared.utils.*

public class WasmExecutionResult {
    public var success: Bool = false
    public var output: String = ""
    public var error: String = ""

    public init() {}

    public init(success: Bool, output: String, error: String) {
        this.success = success
        this.output = output
        this.error = error
    }
}

class WasmExecutionState {
    public var executionId: Int64 = 0
    public var taskId: Int64 = 0
    public var pluginNamespace: String = ""
    public var interactiveSelectEnabled: Bool = false
    public var responseBytes: Array<UInt8> = Array<UInt8>()
    public var errorBytes: Array<UInt8> = Array<UInt8>()
    public var permissions: HashMap<String, Bool> = HashMap<String, Bool>()
    public var adjacentBaseDirs: HashMap<String, String> = HashMap<String, String>()
    public var adjacentListings: HashMap<String, String> = HashMap<String, String>()
    public var adjacentTexts: HashMap<String, String> = HashMap<String, String>()
    public var tcpConnections: HashMap<Int64, TcpSocket> = HashMap<Int64, TcpSocket>()
    public var nextTcpHandle: Int64 = 1
    public var hostCallCounts: HashMap<String, Int64> = HashMap<String, Int64>()
    public var hostCallElapsedMs: HashMap<String, Int64> = HashMap<String, Int64>()

    public init() {}
}

class WasmRpcSelectOption {
    public var index: Int32 = 0
    public var label: String = ""
    public var description: String = ""
    public var cover: String = ""

    public init() {}

    public init(index: Int32, label: String, description: String, cover: String) {
        this.index = index
        this.label = label
        this.description = description
        this.cover = cover
    }
}

class WasmRpcSelectRequest {
    public var taskId: Int64 = 0
    public var requestId: String = ""
    public var title: String = "请选择候选项"
    public var message: String = ""
    public var defaultIndex: Int32 = 0
    public var timeoutSeconds: Int32 = 90
    public var options: Array<WasmRpcSelectOption> = Array<WasmRpcSelectOption>()
    public var createdAtSeconds: Int64 = 0
    public var responded: Bool = false
    public var selectedIndex: Int32 = -1

    public init() {}
}

@C
func lanluWasmHostLogNative(executionId: Int64, memoryCtx: CPointer<Unit>, level: Int32, ptr: Int32, len: Int32): Int32 {
    let taskId = WasmHostBridge.resolveTaskId(executionId)
    let message = WasmHostBridge.readGuestUtf8(memoryCtx, ptr, len)
    if (taskId > 0 && message.trimAscii().size > 0) {
        TaskIO.appendLog(taskId, "[wasm:${level.toString()}] ${message}")
    }
    return 0
}

@C
func lanluWasmHostProgressNative(executionId: Int64, memoryCtx: CPointer<Unit>, percent: Int32, ptr: Int32, len: Int32): Int32 {
    let taskId = WasmHostBridge.resolveTaskId(executionId)
    let message = WasmHostBridge.readGuestUtf8(memoryCtx, ptr, len)
    if (taskId > 0) {
        var bounded = percent
        if (bounded < 0) { bounded = 0 }
        if (bounded > 100) { bounded = 100 }
        let progressMessage = if (message.trimAscii().size > 0) { message } else { "WASM plugin running" }
        TaskModel.updateTaskProgress(taskId, bounded, progressMessage)
        TaskIO.appendLog(taskId, "[PROGRESS] ${bounded}% - ${progressMessage}")
    }
    return 0
}

@C
func lanluWasmHostCallNative(executionId: Int64, memoryCtx: CPointer<Unit>, _: Int32, reqPtr: Int32, reqLen: Int32): Int32 {
    let requestJson = WasmHostBridge.readGuestUtf8(memoryCtx, reqPtr, reqLen)
    let (ok, responseJson, error) = WasmHostBridge.handleHostCall(executionId, requestJson)
    WasmHostBridge.storeCallResult(executionId, ok, responseJson, error)
    return if (ok) { 0 } else { 1 }
}

@C
func lanluWasmHostResponseLenNative(executionId: Int64): Int32 {
    return Int32(WasmHostBridge.getResponseLength(executionId))
}

@C
func lanluWasmHostResponseReadNative(executionId: Int64, memoryCtx: CPointer<Unit>, dstPtr: Int32, dstLen: Int32): Int32 {
    return WasmHostBridge.writeResponseBytes(executionId, memoryCtx, dstPtr, dstLen)
}

@C
func lanluWasmHostLastErrorLenNative(executionId: Int64): Int32 {
    return Int32(WasmHostBridge.getErrorLength(executionId))
}

@C
func lanluWasmHostLastErrorReadNative(executionId: Int64, memoryCtx: CPointer<Unit>, dstPtr: Int32, dstLen: Int32): Int32 {
    return WasmHostBridge.writeErrorBytes(executionId, memoryCtx, dstPtr, dstLen)
}

@C
func lanluWasmHostTcpConnectNative(executionId: Int64, memoryCtx: CPointer<Unit>, hostPtr: Int32, hostLen: Int32, port: Int32, timeoutMs: Int32): Int32 {
    let host = WasmHostBridge.readGuestUtf8(memoryCtx, hostPtr, hostLen)
    return WasmHostBridge.tcpConnect(executionId, host, port, timeoutMs)
}

@C
func lanluWasmHostTcpReadNative(executionId: Int64, memoryCtx: CPointer<Unit>, handle: Int32, dstPtr: Int32, dstLen: Int32, timeoutMs: Int32): Int32 {
    return WasmHostBridge.tcpRead(executionId, memoryCtx, handle, dstPtr, dstLen, timeoutMs)
}

@C
func lanluWasmHostTcpWriteNative(executionId: Int64, memoryCtx: CPointer<Unit>, handle: Int32, srcPtr: Int32, srcLen: Int32, timeoutMs: Int32): Int32 {
    return WasmHostBridge.tcpWrite(executionId, memoryCtx, handle, srcPtr, srcLen, timeoutMs)
}

@C
func lanluWasmHostTcpCloseNative(executionId: Int64, handle: Int32): Int32 {
    return WasmHostBridge.tcpClose(executionId, handle)
}

public class WasmHostCallContext {
    public var executionId: Int64 = 0
    public var pluginNamespace: String = ""
    public var taskId: Int64 = 0
    public var method: String = ""
    public var effectiveParams: String = "{}"
    public var interactiveSelectEnabled: Bool = false

    public init() {}
}

public type WasmHostMethodHandler = (WasmHostCallContext) -> (Bool, String, String)

public class WasmHostBridge {
    private static let runtimeMutex: Mutex = Mutex()
    private static let stateMutex: Mutex = Mutex()
    private static let rpcSelectMutex: Mutex = Mutex()
    private static var runtimeInitialized: Bool = false
    private static var callbacksBound: Bool = false
    private static var executionSeq: Int64 = 1
    private static var executionStates: HashMap<Int64, WasmExecutionState> = HashMap<Int64, WasmExecutionState>()
    private static var rpcSelectPending: HashMap<String, WasmRpcSelectRequest> = HashMap<String, WasmRpcSelectRequest>()
    private static var hostMethodRegistryInitialized: Bool = false
    private static var hostMethodHandlers: HashMap<String, WasmHostMethodHandler> = HashMap<String, WasmHostMethodHandler>()

    public static func runMetadataPlugin(
        taskId: Int64,
        pluginNamespace: String,
        wasmPath: String,
        inputJson: String,
        targetType: String,
        targetId: String,
        permissions: String,
        interactiveSelectEnabled: Bool
    ): WasmExecutionResult {
        let trimmedPath = wasmPath.trimAscii()
        if (trimmedPath.size == 0) {
            return WasmExecutionResult(false, "", "empty wasm path")
        }
        if (!exists(Path(trimmedPath))) {
            return WasmExecutionResult(false, "", "WASM file not found: ${trimmedPath}")
        }

        try {
            ensureRuntimeAndHostImports()
        } catch (e: Exception) {
            return WasmExecutionResult(false, "", e.message)
        }

        let executionId = createExecutionState(taskId, pluginNamespace, permissions, interactiveSelectEnabled)
        var instance: Option<WasmEdgePluginInstance> = None
        var inputAddr: Int32 = 0

        try {
            let created = WasmEdgePluginInstance(executionId, true)
            let effectiveNamespace = if (pluginNamespace.trimAscii().size > 0) { pluginNamespace.trimAscii() } else { "_default" }
            let runtimeHostDir = FileUtils.joinPath(PluginPaths.getPluginRuntimeRoot(), effectiveNamespace)
            try { FileUtils.ensureDirectoryExists(Path(runtimeHostDir)) } catch (_: Exception) {}
            created.initWasiPreopen("/plugin", runtimeHostDir)
            created.loadValidateInstantiate(trimmedPath)
            instance = Some(created)

            try { let _ = created.executeI32_0("lanlu_plugin_result_len") } catch (_: Exception) {}
            try { let _ = created.executeI32_0("lanlu_plugin_last_error") } catch (_: Exception) {}
            try { let _ = created.executeI32_0("lanlu_plugin_last_error_len") } catch (_: Exception) {}

            let inputBytes = encodeUtf8(inputJson)
            inputAddr = created.executeI32_1("lanlu_plugin_alloc", Int32(inputBytes.size))
            try {
                if (inputBytes.size > 0) {
                    created.writeMemory(UInt32(inputAddr), inputBytes)
                }

                let resultPtr = created.executeI32_2("lanlu_plugin_run", inputAddr, Int32(inputBytes.size))
                let resultLen = created.executeI32_0("lanlu_plugin_result_len")
                if (taskId > 0) {
                    TaskIO.appendLog(taskId, "wasm run return: ptr=${resultPtr.toString()} len=${resultLen.toString()}")
                }

                if (resultPtr == 0 || resultLen <= 0) {
                    let errPtr = created.executeI32_0("lanlu_plugin_last_error")
                    let errLen = created.executeI32_0("lanlu_plugin_last_error_len")
                    if (taskId > 0) {
                        TaskIO.appendLog(taskId, "wasm run error buffer: ptr=${errPtr.toString()} len=${errLen.toString()}")
                    }
                    let err = if (errPtr > 0 && errLen > 0) {
                        decodeUtf8(created.readMemory(UInt32(errPtr), UInt32(errLen)))
                    } else {
                        "WASM plugin returned empty result"
                    }
                    return WasmExecutionResult(false, "", err)
                }

                let outputJson = decodeUtf8(created.readMemory(UInt32(resultPtr), UInt32(resultLen)))
                let normalized = normalizeMetadataOutputAdjacentRefs(outputJson, pluginNamespace, targetType, targetId, executionId)
                return WasmExecutionResult(true, normalized, "")
            } finally {
                if (inputAddr > 0) {
                    try { created.executeVoid_2("lanlu_plugin_free", inputAddr, Int32(inputBytes.size)) } catch (_: Exception) {}
                }
            }
        } catch (e: Exception) {
            return WasmExecutionResult(false, "", e.message)
        } finally {
            match (instance) {
                case Some(inst) =>
                    try { inst.destroy() } catch (_: Exception) {}
                case None => ()
            }
            destroyExecutionState(executionId)
        }
    }

    public static func runGenericPlugin(
        taskId: Int64,
        pluginNamespace: String,
        wasmPath: String,
        inputJson: String,
        permissions: String,
        interactiveSelectEnabled: Bool,
        enableWasi!: Bool = true,
        wasiGuestPath!: String = "",
        wasiHostPath!: String = ""
    ): WasmExecutionResult {
        let trimmedPath = wasmPath.trimAscii()
        if (trimmedPath.size == 0) {
            return WasmExecutionResult(false, "", "empty wasm path")
        }
        if (!exists(Path(trimmedPath))) {
            return WasmExecutionResult(false, "", "WASM file not found: ${trimmedPath}")
        }

        try {
            ensureRuntimeAndHostImports()
        } catch (e: Exception) {
            return WasmExecutionResult(false, "", e.message)
        }

        let executionId = createExecutionState(taskId, pluginNamespace, permissions, interactiveSelectEnabled)
        var instance: Option<WasmEdgePluginInstance> = None
        var inputAddr: Int32 = 0

        try {
            let created = WasmEdgePluginInstance(executionId, enableWasi)
            if (enableWasi) {
                let effectiveNamespace = if (pluginNamespace.trimAscii().size > 0) { pluginNamespace.trimAscii() } else { "_default" }
                let runtimeHostDir = if (wasiHostPath.trimAscii().size > 0) {
                    wasiHostPath.trimAscii()
                } else {
                    FileUtils.joinPath(PluginPaths.getPluginRuntimeRoot(), effectiveNamespace)
                }
                try { FileUtils.ensureDirectoryExists(Path(runtimeHostDir)) } catch (_: Exception) {}
                let guest = if (wasiGuestPath.trimAscii().size > 0) { wasiGuestPath.trimAscii() } else { "/plugin" }
                created.initWasiPreopen(guest, runtimeHostDir)
            }
            created.loadValidateInstantiate(trimmedPath)
            instance = Some(created)

            // Pre-warm zero-arg exports that are queried after plugin_run returns.
            try { let _ = created.executeI32_0("lanlu_plugin_result_len") } catch (_: Exception) {}
            try { let _ = created.executeI32_0("lanlu_plugin_last_error") } catch (_: Exception) {}
            try { let _ = created.executeI32_0("lanlu_plugin_last_error_len") } catch (_: Exception) {}

            let inputBytes = encodeUtf8(inputJson)
            inputAddr = created.executeI32_1("lanlu_plugin_alloc", Int32(inputBytes.size))
            try {
                if (inputBytes.size > 0) {
                    created.writeMemory(UInt32(inputAddr), inputBytes)
                }

                let resultPtr = created.executeI32_2("lanlu_plugin_run", inputAddr, Int32(inputBytes.size))
                let resultLen = created.executeI32_0("lanlu_plugin_result_len")
                if (taskId > 0) {
                    TaskIO.appendLog(taskId, "wasm run return: ptr=${resultPtr.toString()} len=${resultLen.toString()}")
                }

                if (resultPtr == 0 || resultLen <= 0) {
                    let errPtr = created.executeI32_0("lanlu_plugin_last_error")
                    let errLen = created.executeI32_0("lanlu_plugin_last_error_len")
                    if (taskId > 0) {
                        TaskIO.appendLog(taskId, "wasm run error buffer: ptr=${errPtr.toString()} len=${errLen.toString()}")
                    }
                    let err = if (errPtr > 0 && errLen > 0) {
                        decodeUtf8(created.readMemory(UInt32(errPtr), UInt32(errLen)))
                    } else {
                        "WASM plugin returned empty result"
                    }
                    return WasmExecutionResult(false, "", err)
                }

                let outputJson = decodeUtf8(created.readMemory(UInt32(resultPtr), UInt32(resultLen)))
                return WasmExecutionResult(true, outputJson, "")
            } finally {
                if (inputAddr > 0) {
                    try { created.executeVoid_2("lanlu_plugin_free", inputAddr, Int32(inputBytes.size)) } catch (_: Exception) {}
                }
            }
        } catch (e: Exception) {
            return WasmExecutionResult(false, "", e.message)
        } finally {
            match (instance) {
                case Some(inst) =>
                    try { inst.destroy() } catch (_: Exception) {}
                case None => ()
            }
            destroyExecutionState(executionId)
        }
    }

    public static func readPluginInfoJson(wasmPath: String): (Bool, String, String) {
        let trimmedPath = wasmPath.trimAscii()
        if (trimmedPath.size == 0) {
            return (false, "", "empty wasm path")
        }
        if (!exists(Path(trimmedPath))) {
            return (false, "", "WASM file not found: ${trimmedPath}")
        }

        try {
            ensureRuntimeAndHostImports()
        } catch (e: Exception) {
            return (false, "", e.message)
        }

        let executionId = createExecutionState(0, "", "", false)
        var instance: Option<WasmEdgePluginInstance> = None

        try {
            let created = WasmEdgePluginInstance(executionId, true)
            created.loadValidateInstantiate(trimmedPath)
            instance = Some(created)
            let ptr = created.executeI32_0("lanlu_plugin_info")
            let len = created.executeI32_0("lanlu_plugin_info_len")
            if (ptr <= 0 || len <= 0) {
                return (false, "", "plugin_info returned empty payload")
            }
            let json = decodeUtf8(created.readMemory(UInt32(ptr), UInt32(len)))
            return (true, json, "")
        } catch (e: Exception) {
            return (false, "", e.message)
        } finally {
            match (instance) {
                case Some(inst) =>
                    try { inst.destroy() } catch (_: Exception) {}
                case None => ()
            }
            destroyExecutionState(executionId)
        }
    }

    public static func materializeAdjacentRefForAssetInstall(
        rawValue: String,
        pluginNamespace: String,
        targetType: String,
        targetId: String,
        executionId!: Int64 = 0
    ): String {
        return maybeMaterializeAdjacentRef(rawValue, pluginNamespace, targetType, targetId, executionId)
    }

    public static func resolveTaskId(executionId: Int64): Int64 {
        if (executionId <= 0) {
            return 0
        }
        stateMutex.lock()
        match (executionStates.get(executionId)) {
            case Some(state) =>
                let taskId = state.taskId
                stateMutex.unlock()
                return taskId
            case None =>
                stateMutex.unlock()
                return 0
        }
    }

    public static func readGuestUtf8(memoryCtx: CPointer<Unit>, addr: Int32, len: Int32): String {
        if (memoryCtx.isNull() || addr <= 0 || len <= 0) {
            return ""
        }
        try {
            return decodeUtf8(WasmEdgeMemory.readBytes(memoryCtx, UInt32(addr), UInt32(len)))
        } catch (_: Exception) {
            return ""
        }
    }

    public static func resolveRpcSelect(taskId: Int64, requestId: String, selectedIndex: Int32): (Bool, String) {
        let rid = requestId.trimAscii()
        if (taskId <= 0 || rid.size == 0) {
            return (false, "invalid task_id/request_id")
        }

        let key = buildRpcSelectKey(taskId, rid)
        rpcSelectMutex.lock()
        match (rpcSelectPending.get(key)) {
            case Some(req) =>
                if (req.responded) {
                    rpcSelectMutex.unlock()
                    return (false, "request already resolved")
                }
                if (selectedIndex < 0 || Int64(selectedIndex) >= req.options.size) {
                    rpcSelectMutex.unlock()
                    return (false, "selected_index out of range")
                }
                req.responded = true
                req.selectedIndex = selectedIndex
                rpcSelectPending[key] = req
                rpcSelectMutex.unlock()
                return (true, "ok")
            case None =>
                rpcSelectMutex.unlock()
                return (false, "request not found")
        }
    }

    public static func abortRpcSelect(taskId: Int64, requestId: String): (Bool, String) {
        let rid = requestId.trimAscii()
        if (taskId <= 0 || rid.size == 0) {
            return (false, "invalid task_id/request_id")
        }

        let key = buildRpcSelectKey(taskId, rid)
        rpcSelectMutex.lock()
        match (rpcSelectPending.get(key)) {
            case Some(req) =>
                if (req.responded) {
                    rpcSelectMutex.unlock()
                    return (false, "request already resolved")
                }
                req.responded = true
                req.selectedIndex = -1
                rpcSelectPending[key] = req
                rpcSelectMutex.unlock()
                return (true, "ok")
            case None =>
                rpcSelectMutex.unlock()
                return (false, "request not found")
        }
    }

    public static func handleHostCall(executionId: Int64, requestJson: String): (Bool, String, String) {
        let trimmed = requestJson.trimAscii()
        let startedAt = nowMillis()
        var metricMethod = "invalid"
        var result: (Bool, String, String) = (false, "{}", "empty host request")
        if (trimmed.size == 0) {
            let elapsed = nowMillis() - startedAt
            recordHostCallMetrics(executionId, metricMethod, elapsed)
            return result
        }

        let (pluginNamespace, taskId, interactiveSelectEnabled) = getExecutionContext(executionId)
        let (method, paramsRaw) = parseHostRequest(trimmed)
        if (method.size == 0) {
            let elapsed = nowMillis() - startedAt
            recordHostCallMetrics(executionId, metricMethod, elapsed)
            return (false, "{}", "invalid host request")
        }

        let effectiveParams = if (paramsRaw.trimAscii().size > 0) { paramsRaw.trimAscii() } else { "{}" }
        let m = method.trimAscii()
        metricMethod = m
        result = dispatchHostCall(executionId, pluginNamespace, taskId, m, effectiveParams, interactiveSelectEnabled)
        let elapsed = nowMillis() - startedAt
        recordHostCallMetrics(executionId, metricMethod, elapsed)
        return result
    }

    public static func storeCallResult(executionId: Int64, success: Bool, responseJson: String, error: String): Unit {
        stateMutex.lock()
        match (executionStates.get(executionId)) {
            case Some(state) =>
                if (success) {
                    state.responseBytes = encodeUtf8(responseJson)
                    state.errorBytes = Array<UInt8>()
                } else {
                    state.responseBytes = Array<UInt8>()
                    state.errorBytes = encodeUtf8(error)
                }
                executionStates[executionId] = state
            case None => ()
        }
        stateMutex.unlock()
    }

    public static func storeExecutionError(executionId: Int64, error: String): Unit {
        stateMutex.lock()
        match (executionStates.get(executionId)) {
            case Some(state) =>
                state.responseBytes = Array<UInt8>()
                state.errorBytes = encodeUtf8(error)
                executionStates[executionId] = state
            case None => ()
        }
        stateMutex.unlock()
    }

    public static func getResponseLength(executionId: Int64): Int64 {
        stateMutex.lock()
        match (executionStates.get(executionId)) {
            case Some(state) =>
                let len = Int64(state.responseBytes.size)
                stateMutex.unlock()
                return len
            case None =>
                stateMutex.unlock()
                return 0
        }
    }

    public static func getErrorLength(executionId: Int64): Int64 {
        stateMutex.lock()
        match (executionStates.get(executionId)) {
            case Some(state) =>
                let len = Int64(state.errorBytes.size)
                stateMutex.unlock()
                return len
            case None =>
                stateMutex.unlock()
                return 0
        }
    }

    public static func writeResponseBytes(executionId: Int64, memoryCtx: CPointer<Unit>, dstPtr: Int32, dstLen: Int32): Int32 {
        let bytes = getStoredBytes(executionId, true)
        return writeGuestBytes(memoryCtx, dstPtr, dstLen, bytes)
    }

    public static func writeErrorBytes(executionId: Int64, memoryCtx: CPointer<Unit>, dstPtr: Int32, dstLen: Int32): Int32 {
        let bytes = getStoredBytes(executionId, false)
        return writeGuestBytes(memoryCtx, dstPtr, dstLen, bytes)
    }

    public static func tcpConnect(executionId: Int64, host: String, port: Int32, timeoutMs: Int32): Int32 {
        let (allowed, err) = ensureHostCapability(executionId, ["tcp.connect"], "tcp.connect")
        if (!allowed) {
            storeExecutionError(executionId, err)
            return -1
        }

        let trimmedHost = host.trimAscii()
        if (trimmedHost.size == 0) {
            storeExecutionError(executionId, "missing host")
            return -1
        }
        if (port <= 0 || port > 65535) {
            storeExecutionError(executionId, "invalid port")
            return -1
        }

        try {
            let socket = TcpSocket(trimmedHost, UInt16(port))
            socket.noDelay = true
            let timeout = durationFromTimeoutMs(timeoutMs)
            match (timeout) {
                case Some(v) =>
                    socket.readTimeout = v
                    socket.writeTimeout = v
                case None => ()
            }
            socket.connect(timeout: timeout)
            let handle = storeTcpConnection(executionId, socket)
            storeExecutionError(executionId, "")
            return Int32(handle)
        } catch (e: Exception) {
            storeExecutionError(executionId, "tcp.connect failed: ${e.message}")
            return -1
        }
    }

    public static func tcpRead(
        executionId: Int64,
        memoryCtx: CPointer<Unit>,
        handle: Int32,
        dstPtr: Int32,
        dstLen: Int32,
        timeoutMs: Int32
    ): Int32 {
        if (dstLen <= 0) {
            return 0
        }

        try {
            let buffer = Array<Byte>(Int64(dstLen), repeat: 0)
            let socket = getTcpConnection(executionId, Int64(handle))
            applySocketTimeout(socket, timeoutMs)
            let count = socket.read(buffer)
            if (count <= 0) {
                storeExecutionError(executionId, "")
                return 0
            }
            let bytes = byteArrayToUInt8(buffer[0..count])
            let written = writeGuestBytes(memoryCtx, dstPtr, dstLen, bytes)
            storeExecutionError(executionId, "")
            return written
        } catch (e: Exception) {
            storeExecutionError(executionId, "tcp.read failed: ${e.message}")
            return -1
        }
    }

    public static func tcpWrite(
        executionId: Int64,
        memoryCtx: CPointer<Unit>,
        handle: Int32,
        srcPtr: Int32,
        srcLen: Int32,
        timeoutMs: Int32
    ): Int32 {
        if (srcLen <= 0) {
            return 0
        }

        try {
            let socket = getTcpConnection(executionId, Int64(handle))
            applySocketTimeout(socket, timeoutMs)
            let bytes = WasmEdgeMemory.readBytes(memoryCtx, UInt32(srcPtr), UInt32(srcLen))
            socket.write(uint8ArrayToByte(bytes))
            storeExecutionError(executionId, "")
            return srcLen
        } catch (e: Exception) {
            storeExecutionError(executionId, "tcp.write failed: ${e.message}")
            return -1
        }
    }

    public static func tcpClose(executionId: Int64, handle: Int32): Int32 {
        stateMutex.lock()
        match (executionStates.get(executionId)) {
            case Some(state) =>
                match (state.tcpConnections.get(Int64(handle))) {
                    case Some(socket) =>
                        state.tcpConnections.remove(Int64(handle))
                        executionStates[executionId] = state
                        stateMutex.unlock()
                        try { socket.close() } catch (_: Exception) {}
                        storeExecutionError(executionId, "")
                        return 0
                    case None =>
                        stateMutex.unlock()
                        storeExecutionError(executionId, "invalid tcp handle")
                        return -1
                }
            case None =>
                stateMutex.unlock()
                return -1
        }
    }

    public static func warmup(): (Bool, String) {
        try {
            ensureRuntimeAndHostImports()
            return (true, "")
        } catch (e: Exception) {
            return (false, e.message)
        }
    }

    private static func ensureRuntimeAndHostImports(): Unit {
        runtimeMutex.lock()
        try {
            if (!runtimeInitialized) {
                if (!WasmEdgeRuntime.initialize()) {
                    throw Exception("Failed to initialize WasmEdge runtime")
                }
                runtimeInitialized = true
            }
            if (!hostMethodRegistryInitialized) {
                initializeHostMethodRegistry()
            }

            if (!callbacksBound) {
                let ok = WasmEdgeRuntime.bindHostCallbacks(
                    lanluWasmHostLogNative,
                    lanluWasmHostProgressNative,
                    lanluWasmHostCallNative,
                    lanluWasmHostResponseLenNative,
                    lanluWasmHostResponseReadNative,
                    lanluWasmHostLastErrorLenNative,
                    lanluWasmHostLastErrorReadNative,
                    lanluWasmHostTcpConnectNative,
                    lanluWasmHostTcpReadNative,
                    lanluWasmHostTcpWriteNative,
                    lanluWasmHostTcpCloseNative
                )
                if (!ok) {
                    throw Exception("Failed to bind wasmedge_host callbacks into WasmEdge wrapper")
                }
                callbacksBound = true
            }
        } finally {
            runtimeMutex.unlock()
        }
    }

    public static func registerHostMethod(method: String, handler: WasmHostMethodHandler): Unit {
        let key = method.trimAscii()
        if (key.size == 0) {
            return
        }
        hostMethodHandlers[key] = handler
    }

    private static func initializeHostMethodRegistry(): Unit {
        if (hostMethodRegistryInitialized) {
            return
        }
        registerHostMethod("archive.list_adjacent_files", { ctx => handleArchiveListAdjacentFiles(ctx) })
        registerHostMethod("archive.listAdjacentFiles", { ctx => handleArchiveListAdjacentFiles(ctx) })
        registerHostMethod("archive.read_adjacent_text", { ctx => handleArchiveReadAdjacentText(ctx) })
        registerHostMethod("archive.readAdjacentText", { ctx => handleArchiveReadAdjacentText(ctx) })
        registerHostMethod("archive.read_adjacent_texts", { ctx => handleArchiveReadAdjacentTexts(ctx) })
        registerHostMethod("archive.readAdjacentTexts", { ctx => handleArchiveReadAdjacentTexts(ctx) })
        registerHostMethod("archive.list_files", { ctx => handleArchiveListFiles(ctx) })
        registerHostMethod("archive.listFiles", { ctx => handleArchiveListFiles(ctx) })
        registerHostMethod("archive.read_text", { ctx => handleArchiveReadText(ctx) })
        registerHostMethod("archive.readText", { ctx => handleArchiveReadText(ctx) })
        registerHostMethod("archive.get_metadata", { ctx => handleArchiveGetMetadata(ctx) })
        registerHostMethod("archive.export_entries", { ctx => handleArchiveExportEntries(ctx) })
        registerHostMethod("archive.exportEntries", { ctx => handleArchiveExportEntries(ctx) })
        registerHostMethod("archive.export_cover_for_search", { ctx => handleHostArchiveExportCoverForSearch(ctx) })
        registerHostMethod("tankoubon.list_archives", { ctx => handleTankoubonListArchives(ctx) })
        registerHostMethod("tags.list", { ctx => handleTagsList(ctx) })
        registerHostMethod("tags.merge", { ctx => handleTagsMerge(ctx) })
        registerHostMethod("ui.select", { ctx => handleUiSelect(ctx) })
        hostMethodRegistryInitialized = true
    }

    private static func createExecutionState(taskId: Int64, pluginNamespace: String, permissions: String, interactiveSelectEnabled: Bool): Int64 {
        stateMutex.lock()
        executionSeq += 1
        let executionId = executionSeq
        var state = WasmExecutionState()
        state.executionId = executionId
        state.taskId = taskId
        state.pluginNamespace = pluginNamespace.trimAscii()
        state.interactiveSelectEnabled = interactiveSelectEnabled
        state.permissions = parsePermissionMap(permissions)
        executionStates[executionId] = state
        stateMutex.unlock()
        return executionId
    }

    private static func destroyExecutionState(executionId: Int64): Unit {
        var removed: Option<WasmExecutionState> = None
        stateMutex.lock()
        match (executionStates.get(executionId)) {
            case Some(state) => removed = Some(state)
            case None => ()
        }
        executionStates.remove(executionId)
        stateMutex.unlock()
        match (removed) {
            case Some(state) =>
                closeTcpConnections(state)
                logHostCallSummary(state)
            case None => ()
        }
    }

    private static func getExecutionContext(executionId: Int64): (String, Int64, Bool) {
        stateMutex.lock()
        match (executionStates.get(executionId)) {
            case Some(state) =>
                let namespace = state.pluginNamespace
                let taskId = state.taskId
                let interactive = state.interactiveSelectEnabled
                stateMutex.unlock()
                return (namespace, taskId, interactive)
            case None =>
                stateMutex.unlock()
                return ("", 0, false)
        }
    }

    private static func getStoredBytes(executionId: Int64, response: Bool): Array<UInt8> {
        stateMutex.lock()
        match (executionStates.get(executionId)) {
            case Some(state) =>
                let bytes = if (response) { state.responseBytes } else { state.errorBytes }
                stateMutex.unlock()
                return bytes
            case None =>
                stateMutex.unlock()
                return Array<UInt8>()
        }
    }

    private static func writeGuestBytes(memoryCtx: CPointer<Unit>, dstPtr: Int32, dstLen: Int32, bytes: Array<UInt8>): Int32 {
        if (memoryCtx.isNull() || dstPtr <= 0 || dstLen <= 0 || bytes.size <= 0) {
            return 0
        }

        var count = Int64(dstLen)
        if (count > bytes.size) {
            count = bytes.size
        }
        if (count <= 0) {
            return 0
        }

        return WasmEdgeMemory.writeBytes(memoryCtx, UInt32(dstPtr), bytes[0..count])
    }

    private static func parseHostRequest(raw: String): (String, String) {
        var method = ""
        var paramsRaw = "{}"

        try {
            var buf = ByteBuffer()
            unsafe { buf.write(raw.rawData()) }
            let r = JsonReader(buf)
            if (r.peek() != Some(BeginObject)) {
                return (method, paramsRaw)
            }
            r.startObject()
            while (r.peek() != EndObject) {
                let name = r.readName()
                match (name) {
                    case "method" => method = r.readValue<String>().trimAscii()
                    case "params" => paramsRaw = String.fromUtf8(r.readValueBytes())
                    case _ => r.skip()
                }
            }
            r.endObject()
        } catch (_: Exception) {}

        return (method, paramsRaw)
    }

    private static func parseArchiveAdjacentListParams(raw: String): (String, Int64) {
        var archiveId = ""
        var levelsUp: Int64 = 0

        try {
            var buf = ByteBuffer()
            unsafe { buf.write(raw.rawData()) }
            let r = JsonReader(buf)
            if (r.peek() != Some(BeginObject)) {
                return ("", 0)
            }
            r.startObject()
            while (r.peek() != EndObject) {
                let name = r.readName()
                match (name) {
                    case "archive_id" => archiveId = r.readValue<String>().trimAscii()
                    case "archiveId" => archiveId = r.readValue<String>().trimAscii()
                    case "levels_up" => levelsUp = parseInt64Loose(r.readValue<String>(), 0)
                    case "levelsUp" => levelsUp = parseInt64Loose(r.readValue<String>(), 0)
                    case _ => r.skip()
                }
            }
            r.endObject()
        } catch (_: Exception) {}

        return (archiveId, levelsUp)
    }

    private static func parseArchiveReadTextParams(raw: String): (String, String, Int64) {
        var archiveId = ""
        var fileName = ""
        var levelsUp: Int64 = 0

        try {
            var buf = ByteBuffer()
            unsafe { buf.write(raw.rawData()) }
            let r = JsonReader(buf)
            if (r.peek() != Some(BeginObject)) {
                return ("", "", 0)
            }
            r.startObject()
            while (r.peek() != EndObject) {
                let name = r.readName()
                match (name) {
                    case "archive_id" => archiveId = r.readValue<String>().trimAscii()
                    case "archiveId" => archiveId = r.readValue<String>().trimAscii()
                    case "file_name" => fileName = r.readValue<String>()
                    case "fileName" => fileName = r.readValue<String>()
                    case "levels_up" => levelsUp = parseInt64Loose(r.readValue<String>(), 0)
                    case "levelsUp" => levelsUp = parseInt64Loose(r.readValue<String>(), 0)
                    case _ => r.skip()
                }
            }
            r.endObject()
        } catch (_: Exception) {}

        return (archiveId, fileName, levelsUp)
    }

    private static func parseArchiveReadTextsParams(raw: String): (String, ArrayList<String>, Int64) {
        var archiveId = ""
        var fileNames = ArrayList<String>()
        var levelsUp: Int64 = 0

        try {
            var buf = ByteBuffer()
            unsafe { buf.write(raw.rawData()) }
            let r = JsonReader(buf)
            if (r.peek() != Some(BeginObject)) {
                return ("", ArrayList<String>(), 0)
            }
            r.startObject()
            while (r.peek() != EndObject) {
                let name = r.readName()
                match (name) {
                    case "archive_id" => archiveId = r.readValue<String>().trimAscii()
                    case "archiveId" => archiveId = r.readValue<String>().trimAscii()
                    case "levels_up" => levelsUp = parseInt64Loose(r.readValue<String>(), 0)
                    case "levelsUp" => levelsUp = parseInt64Loose(r.readValue<String>(), 0)
                    case "file_names" =>
                        readFileNameArrayInto(r, fileNames)
                    case "fileNames" =>
                        readFileNameArrayInto(r, fileNames)
                    case _ => r.skip()
                }
            }
            r.endObject()
        } catch (_: Exception) {}

        return (archiveId, fileNames, levelsUp)
    }

    private static func parseArchiveListFilesParams(raw: String): String {
        var archiveId = ""

        try {
            var buf = ByteBuffer()
            unsafe { buf.write(raw.rawData()) }
            let r = JsonReader(buf)
            if (r.peek() != Some(BeginObject)) {
                return ""
            }
            r.startObject()
            while (r.peek() != EndObject) {
                let name = r.readName()
                match (name) {
                    case "archive_id" => archiveId = r.readValue<String>().trimAscii()
                    case "archiveId" => archiveId = r.readValue<String>().trimAscii()
                    case _ => r.skip()
                }
            }
            r.endObject()
        } catch (_: Exception) {}

        return archiveId
    }

    private static func parseArchiveReadEntryTextParams(raw: String): (String, String) {
        var archiveId = ""
        var entryName = ""

        try {
            var buf = ByteBuffer()
            unsafe { buf.write(raw.rawData()) }
            let r = JsonReader(buf)
            if (r.peek() != Some(BeginObject)) {
                return ("", "")
            }
            r.startObject()
            while (r.peek() != EndObject) {
                let name = r.readName()
                match (name) {
                    case "archive_id" => archiveId = r.readValue<String>().trimAscii()
                    case "archiveId" => archiveId = r.readValue<String>().trimAscii()
                    case "entry_name" => entryName = r.readValue<String>()
                    case "entryName" => entryName = r.readValue<String>()
                    case "file_name" => entryName = r.readValue<String>()
                    case "fileName" => entryName = r.readValue<String>()
                    case _ => r.skip()
                }
            }
            r.endObject()
        } catch (_: Exception) {}

        return (archiveId, entryName)
    }

    private static func parseArchiveExportEntriesParams(raw: String): (String, ArrayList<String>, Int64) {
        var archiveId = ""
        var entries = ArrayList<String>()
        var levelsUp: Int64 = 0

        try {
            var buf = ByteBuffer()
            unsafe { buf.write(raw.rawData()) }
            let r = JsonReader(buf)
            if (r.peek() != Some(BeginObject)) {
                return ("", ArrayList<String>(), 0)
            }
            r.startObject()
            while (r.peek() != EndObject) {
                let name = r.readName()
                match (name) {
                    case "archive_id" => archiveId = r.readValue<String>().trimAscii()
                    case "archiveId" => archiveId = r.readValue<String>().trimAscii()
                    case "levels_up" => levelsUp = parseInt64Loose(r.readValue<String>(), 0)
                    case "levelsUp" => levelsUp = parseInt64Loose(r.readValue<String>(), 0)
                    case "entries" => readFileNameArrayInto(r, entries)
                    case "entry_names" => readFileNameArrayInto(r, entries)
                    case "entryNames" => readFileNameArrayInto(r, entries)
                    case "entry_name" => readFileNameArrayInto(r, entries)
                    case "entryName" => readFileNameArrayInto(r, entries)
                    case _ => r.skip()
                }
            }
            r.endObject()
        } catch (_: Exception) {}

        return (archiveId, entries, levelsUp)
    }

    private static func parseTankoubonListArchivesParams(raw: String): String {
        var tankoubonId = ""

        try {
            var buf = ByteBuffer()
            unsafe { buf.write(raw.rawData()) }
            let r = JsonReader(buf)
            if (r.peek() != Some(BeginObject)) {
                return ""
            }
            r.startObject()
            while (r.peek() != EndObject) {
                let name = r.readName()
                match (name) {
                    case "tankoubon_id" => tankoubonId = r.readValue<String>().trimAscii()
                    case _ => r.skip()
                }
            }
            r.endObject()
        } catch (_: Exception) {}

        return tankoubonId
    }

    private static func parseTagsListParams(raw: String): (String, String, String, Int64, Int64, Bool) {
        var namespaceStr = ""
        var query = ""
        var lang = "zh"
        var limit: Int64 = 1000i64
        var offset: Int64 = 0i64
        var includeTranslations = false

        try {
            var buf = ByteBuffer()
            unsafe { buf.write(raw.rawData()) }
            let r = JsonReader(buf)
            if (r.peek() != Some(BeginObject)) {
                return (namespaceStr, query, lang, limit, offset, includeTranslations)
            }
            r.startObject()
            while (r.peek() != EndObject) {
                let name = r.readName()
                match (name) {
                    case "namespace" => namespaceStr = r.readValue<String>()
                    case "q" => query = r.readValue<String>()
                    case "lang" => lang = r.readValue<String>()
                    case "limit" => limit = parseInt64Loose(r.readValue<String>(), 1000i64)
                    case "offset" => offset = parseInt64Loose(r.readValue<String>(), 0i64)
                    case "includeTranslations" => includeTranslations = parseBoolLoose(r.readValue<String>())
                    case _ => r.skip()
                }
            }
            r.endObject()
        } catch (_: Exception) {}

        if (limit <= 0) { limit = 1000i64 }
        if (limit > 2000) { limit = 2000i64 }
        if (offset < 0) { offset = 0i64 }
        if (lang.trimAscii().size == 0) { lang = "zh" }
        return (namespaceStr, query, lang, limit, offset, includeTranslations)
    }

    private static func parseTagsMergeParams(raw: String): (Int64, Int64, Bool) {
        var sourceId: Int64 = 0i64
        var targetId: Int64 = 0i64
        var deleteSource = true

        try {
            var buf = ByteBuffer()
            unsafe { buf.write(raw.rawData()) }
            let r = JsonReader(buf)
            if (r.peek() != Some(BeginObject)) {
                return (sourceId, targetId, deleteSource)
            }
            r.startObject()
            while (r.peek() != EndObject) {
                let name = r.readName()
                match (name) {
                    case "sourceId" => sourceId = parseInt64Loose(r.readValue<String>(), 0i64)
                    case "targetId" => targetId = parseInt64Loose(r.readValue<String>(), 0i64)
                    case "deleteSource" => deleteSource = parseBoolLoose(r.readValue<String>())
                    case _ => r.skip()
                }
            }
            r.endObject()
        } catch (_: Exception) {}

        return (sourceId, targetId, deleteSource)
    }

    private static func buildTagsListResponseJson(
        namespaceStr: String,
        query: String,
        lang: String,
        limit: Int64,
        offset: Int64,
        includeTranslations: Bool
    ): String {
        let nsOpt: ?String = if (namespaceStr.trimAscii().size > 0) { Some(namespaceStr.trimAscii()) } else { None }
        let qOpt: ?String = if (query.trimAscii().size > 0) { Some(query.trimAscii()) } else { None }
        let effectiveLang = if (lang.trimAscii().size > 0) { lang.trimAscii() } else { "zh" }

        let total = TagDao.count(nsOpt, qOpt)
        let out = ByteBuffer()
        let w = JsonWriter(out)
        w.startObject()
        w.writeName("total").writeValue(total)
        w.writeName("limit").writeValue(limit)
        w.writeName("offset").writeValue(offset)
        w.writeName("items")
        w.startArray()

        if (includeTranslations) {
            let rows = TagDao.list(nsOpt, qOpt, limit, offset)
            for (row in rows) {
                w.startObject()
                w.writeName("id").writeValue(row.id)
                w.writeName("namespace").writeValue(row.namespace)
                w.writeName("name").writeValue(row.name)
                w.writeName("translation_text").writeValue(row.getTranslatedText(effectiveLang))
                w.writeName("translations")
                w.startObject()
                for ((l, t) in row.translations) {
                    w.writeName(l)
                    w.startObject()
                    w.writeName("text").writeValue(t.text)
                    w.writeName("intro").writeValue(t.intro)
                    w.endObject()
                }
                w.endObject()
                w.endObject()
            }
        } else {
            let rows = TagDao.listLite(nsOpt, qOpt, effectiveLang, limit, offset)
            for (row in rows) {
                w.startObject()
                w.writeName("id").writeValue(row.id)
                w.writeName("namespace").writeValue(row.namespace)
                w.writeName("name").writeValue(row.name)
                w.writeName("translation_text").writeValue(row.translationText)
                w.endObject()
            }
        }

        w.endArray()
        w.endObject()
        w.flush()
        return String.fromUtf8(readToEnd(out))
    }

    private static func normalizeMetadataOutputAdjacentRefs(
        outputJson: String,
        pluginNamespace: String,
        targetType: String,
        targetId: String,
        executionId: Int64
    ): String {
        let trimmed = outputJson.trimAscii()
        if (trimmed.size == 0) {
            return outputJson
        }

        try {
            let out = ByteBuffer()
            let w = JsonWriter(out)
            var buf = ByteBuffer()
            unsafe { buf.write(trimmed.rawData()) }
            let r = JsonReader(buf)
            rewriteJsonValue(r, w, "", pluginNamespace, targetType, targetId, executionId)
            w.flush()
            return String.fromUtf8(readToEnd(out))
        } catch (_: Exception) {
            return outputJson
        }
    }

    private static func rewriteJsonValue(
        r: JsonReader,
        w: JsonWriter,
        currentField: String,
        pluginNamespace: String,
        targetType: String,
        targetId: String,
        executionId: Int64
    ): Unit {
        match (r.peek()) {
            case Some(BeginObject) =>
                r.startObject()
                w.startObject()
                while (r.peek() != EndObject) {
                    let name = r.readName()
                    w.writeName(name)
                    rewriteJsonValue(r, w, name.trimAscii().toAsciiLower(), pluginNamespace, targetType, targetId, executionId)
                }
                r.endObject()
                w.endObject()
            case Some(BeginArray) =>
                r.startArray()
                w.startArray()
                while (r.peek() != EndArray) {
                    rewriteJsonValue(r, w, currentField, pluginNamespace, targetType, targetId, executionId)
                }
                r.endArray()
                w.endArray()
            case Some(_) =>
                if (isAdjacentAssetField(currentField)) {
                    let rawValue = r.readValue<String>()
                    let normalized = maybeMaterializeAdjacentRef(rawValue, pluginNamespace, targetType, targetId, executionId)
                    w.writeValue(normalized)
                } else {
                    let raw = String.fromUtf8(r.readValueBytes())
                    w.jsonValue(raw)
                }
            case None =>
                w.writeValue("")
        }
    }

    private static func isAdjacentAssetField(field: String): Bool {
        let f = field.trimAscii().toAsciiLower()
        return f == "cover" || f == "backdrop" || f == "clearlogo" || f == "thumb" || f == "lyrics"
    }

    private static func maybeMaterializeAdjacentRef(
        rawValue: String,
        pluginNamespace: String,
        targetType: String,
        targetId: String,
        executionId: Int64
    ): String {
        let trimmed = rawValue.trimAscii()
        if (!trimmed.startsWith("adjacent://")) {
            return rawValue
        }

        let withoutScheme = trimmed["adjacent://".size..trimmed.size]
        let slashIndex = match (withoutScheme.indexOf("/")) {
            case Some(idx) => idx
            case None => return rawValue
        }

        let levelsRaw = withoutScheme[0..slashIndex]
        let relPath = withoutScheme[(slashIndex + 1)..withoutScheme.size]
        let levelsUp = parseInt64Loose(levelsRaw, -1)
        let safeRelPath = normalizeSafeRelPath(relPath)
        if (levelsUp < 0 || safeRelPath.size == 0 || pluginNamespace.trimAscii().size == 0) {
            return rawValue
        }

        let sourcePath = resolveAdjacentRefSourcePath(executionId, targetType, targetId, levelsUp, safeRelPath)
        if (sourcePath.size == 0) {
            return rawValue
        }

        let pluginDir = FileUtils.joinPath(PluginPaths.getPluginRuntimeRoot(), pluginNamespace.trimAscii())
        let safeTarget = normalizeSafeRelPath(targetId)
        let ownerDir = if (safeTarget.size > 0) { safeTarget } else { executionId.toString() }
        let relativeOut = "cache/wasm_adjacent/${ownerDir}/${levelsUp.toString()}/${safeRelPath}"
        let outputPath = FileUtils.joinPath(pluginDir, relativeOut)
        try {
            FileUtils.ensureDirectoryExists(Path(outputPath).parent)
            copy(Path(sourcePath), to: Path(outputPath), overwrite: true)
            return relativeOut
        } catch (_: Exception) {
            return rawValue
        }
    }

    private static func resolveAdjacentRefSourcePath(executionId: Int64, targetType: String, targetId: String, levelsUp: Int64, safeRelPath: String): String {
        let effectiveType = targetType.trimAscii().toAsciiLower()
        if (effectiveType == "tankoubon" || effectiveType == "tank") {
            let archiveIds = TankoubonDao.getArchivesInTankoubon(targetId.trimAscii())
            for (archiveId in archiveIds) {
                let sourcePath = resolveAdjacentSourcePathForArchive(executionId, archiveId.trimAscii(), levelsUp, safeRelPath)
                if (sourcePath.size > 0) {
                    return sourcePath
                }
            }
            return ""
        }
        return resolveAdjacentSourcePathForArchive(executionId, targetId.trimAscii(), levelsUp, safeRelPath)
    }

    private static func resolveAdjacentSourcePathForArchive(executionId: Int64, archiveId: String, levelsUp: Int64, safeRelPath: String): String {
        match (resolveAdjacentBaseDir(executionId, archiveId.trimAscii(), levelsUp)) {
            case Some(baseDir) =>
                let sourcePath = FileUtils.joinPath(baseDir, safeRelPath)
                if (DirectoryScanner.fileExists(sourcePath)) {
                    return sourcePath
                }
                return ""
            case None => return ""
        }
    }

    private static func resolveArchiveActualPath(archiveId: String): Option<(String, String)> {
        let trimmed = archiveId.trimAscii()
        if (trimmed.size == 0) { return None }

        let archive = ArchiveDao.getArchiveById(trimmed)
        if (archive.id.size == 0) { return None }
        if (archive.category_id <= 0) { return None }

        let basePath = match (CategoryDao.getCategoryByInternalId(archive.category_id)) {
            case Some(cat) => cat.scanPath
            case None => ""
        }
        if (basePath.trimAscii().size == 0) { return None }

        let archivePath = if (archive.relative_path.size > 0) {
            "${basePath}/${archive.relative_path}/${archive.filename}"
        } else {
            "${basePath}/${archive.filename}"
        }
        let actualPath = FileUtils.resolvePath(archivePath)
        if (actualPath.trimAscii().size == 0) { return None }
        return Some((archive.archive_type, actualPath))
    }

    private static func resolveAdjacentBaseDir(executionId: Int64, archiveId: String, levelsUpRaw: Int64): Option<String> {
        let trimmedArchiveId = archiveId.trimAscii()
        let normalizedLevelsUp = normalizeLevelsUp(levelsUpRaw)
        let cacheKey = buildAdjacentBaseDirCacheKey(trimmedArchiveId, normalizedLevelsUp)
        match (getCachedAdjacentBaseDir(executionId, cacheKey)) {
            case Some(cachedBaseDir) => return Some(cachedBaseDir)
            case None => ()
        }

        match (resolveArchiveActualPath(trimmedArchiveId)) {
            case None => return None
            case Some((archiveType, actualPath)) =>
                var baseDir = if (archiveType == ArchiveTypes.FOLDER) {
                    actualPath.trimAscii()
                } else {
                    Path(actualPath).parent.toString().trimAscii()
                }

                var levelsUp = normalizedLevelsUp

                while (levelsUp > 0) {
                    let parent = Path(baseDir).parent.toString().trimAscii()
                    if (parent.size == 0 || parent == baseDir) {
                        return None
                    }
                    baseDir = parent
                    levelsUp -= 1
                }

                if (baseDir.size == 0 || !DirectoryScanner.directoryExists(baseDir)) {
                    return None
                }
                cacheAdjacentBaseDir(executionId, cacheKey, baseDir)
                return Some(baseDir)
        }
    }

    private static func dispatchHostCall(
        executionId: Int64,
        pluginNamespace: String,
        taskId: Int64,
        method: String,
        effectiveParams: String,
        interactiveSelectEnabled: Bool
    ): (Bool, String, String) {
        let key = method.trimAscii()
        match (hostMethodHandlers.get(key)) {
            case Some(handler) =>
                var ctx = WasmHostCallContext()
                ctx.executionId = executionId
                ctx.pluginNamespace = pluginNamespace
                ctx.taskId = taskId
                ctx.method = key
                ctx.effectiveParams = effectiveParams
                ctx.interactiveSelectEnabled = interactiveSelectEnabled
                return handler(ctx)
            case None => ()
        }

        if (taskId > 0) {
            TaskIO.appendLog(taskId, "WASM host_call unsupported: ${method} namespace=${pluginNamespace}")
        }
        return (false, "{}", "unknown method: ${method}")
    }

    private static func handleArchiveListAdjacentFiles(ctx: WasmHostCallContext): (Bool, String, String) {
        let (allowed, err) = ensureHostCapability(ctx.executionId, ["archive.list_adjacent_files"], "archive.list_adjacent_files")
        if (!allowed) { return (false, "{}", err) }
        let (archiveId, levelsUp) = parseArchiveAdjacentListParams(ctx.effectiveParams)
        if (archiveId.size == 0) {
            return (false, "{}", "missing archive_id")
        }
        return buildAdjacentListingResponse(ctx.executionId, archiveId, levelsUp)
    }

    private static func handleArchiveReadAdjacentText(ctx: WasmHostCallContext): (Bool, String, String) {
        let (allowed, capErr) = ensureHostCapability(ctx.executionId, ["archive.read_adjacent_text"], "archive.read_adjacent_text")
        if (!allowed) { return (false, "{}", capErr) }
        let (archiveId, fileName, levelsUp) = parseArchiveReadTextParams(ctx.effectiveParams)
        if (archiveId.size == 0 || fileName.trimAscii().size == 0) {
            return (false, "{}", "missing archive_id/file_name")
        }
        let safeName = normalizeSafeRelPath(fileName)
        if (safeName.size == 0) {
            return (false, "{}", "invalid file_name")
        }
        let (ok, text, readErr) = readAdjacentTextCached(ctx.executionId, archiveId, levelsUp, safeName)
        if (!ok) {
            return (false, "{}", readErr)
        }
        return (true, buildAdjacentTextResponseJson(text), "")
    }

    private static func handleArchiveReadAdjacentTexts(ctx: WasmHostCallContext): (Bool, String, String) {
        let (allowed, err) = ensureHostCapability(ctx.executionId, ["archive.read_adjacent_texts", "archive.read_adjacent_text"], "archive.read_adjacent_texts")
        if (!allowed) { return (false, "{}", err) }
        let (archiveId, fileNames, levelsUp) = parseArchiveReadTextsParams(ctx.effectiveParams)
        if (archiveId.size == 0) {
            return (false, "{}", "missing archive_id")
        }
        if (fileNames.size == 0) {
            return (false, "{}", "missing file_names")
        }
        return buildAdjacentTextsResponse(ctx.executionId, archiveId, levelsUp, fileNames)
    }

    private static func handleArchiveListFiles(ctx: WasmHostCallContext): (Bool, String, String) {
        let (allowed, err) = ensureHostCapability(ctx.executionId, ["archive.list_files"], "archive.list_files")
        if (!allowed) { return (false, "{}", err) }
        let archiveId = parseArchiveListFilesParams(ctx.effectiveParams)
        if (archiveId.size == 0) {
            return (false, "{}", "missing archive_id")
        }
        return buildArchiveListingResponse(ctx.executionId, archiveId)
    }

    private static func handleArchiveReadText(ctx: WasmHostCallContext): (Bool, String, String) {
        let (allowed, capErr) = ensureHostCapability(ctx.executionId, ["archive.read_text"], "archive.read_text")
        if (!allowed) { return (false, "{}", capErr) }
        let (archiveId, entryName) = parseArchiveReadEntryTextParams(ctx.effectiveParams)
        if (archiveId.size == 0 || entryName.trimAscii().size == 0) {
            return (false, "{}", "missing archive_id/entry_name")
        }
        let safeName = normalizeSafeRelPath(entryName)
        if (safeName.size == 0) {
            return (false, "{}", "invalid entry_name")
        }
        let (ok, text, readErr) = readArchiveTextCached(ctx.executionId, archiveId, safeName)
        if (!ok) {
            return (false, "{}", readErr)
        }
        return (true, buildAdjacentTextResponseJson(text), "")
    }

    private static func handleArchiveGetMetadata(ctx: WasmHostCallContext): (Bool, String, String) {
        let (allowed, err) = ensureHostCapability(ctx.executionId, ["archive.get_metadata"], "archive.get_metadata")
        if (!allowed) { return (false, "{}", err) }
        return buildArchiveMetadataResponse(ctx.effectiveParams)
    }

    private static func handleArchiveExportEntries(ctx: WasmHostCallContext): (Bool, String, String) {
        let (allowed, err) = ensureHostCapability(ctx.executionId, ["archive.export_entries"], "archive.export_entries")
        if (!allowed) { return (false, "{}", err) }

        let (archiveId, entries, levelsUpRaw) = parseArchiveExportEntriesParams(ctx.effectiveParams)
        if (archiveId.size == 0) {
            return (false, "{}", "missing archive_id")
        }
        if (entries.size == 0) {
            return (false, "{}", "missing entries")
        }
        return exportArchiveEntriesToPluginRuntime(ctx.executionId, ctx.pluginNamespace, archiveId, entries, levelsUpRaw)
    }

    private static func handleHostArchiveExportCoverForSearch(ctx: WasmHostCallContext): (Bool, String, String) {
        let (allowed, err) = ensureHostCapability(ctx.executionId, ["archive.export_cover_for_search"], "archive.export_cover_for_search")
        if (!allowed) { return (false, "{}", err) }
        return handleArchiveExportCoverForSearch(ctx.pluginNamespace, ctx.effectiveParams)
    }

    private static func handleTankoubonListArchives(ctx: WasmHostCallContext): (Bool, String, String) {
        let (allowed, err) = ensureHostCapability(ctx.executionId, ["tankoubon.list_archives"], "tankoubon.list_archives")
        if (!allowed) { return (false, "{}", err) }
        let tankoubonId = parseTankoubonListArchivesParams(ctx.effectiveParams)
        if (tankoubonId.size == 0) {
            return (false, "{}", "missing tankoubon_id")
        }
        return (true, buildTankoubonArchivesResponseJson(tankoubonId), "")
    }

    private static func handleTagsList(ctx: WasmHostCallContext): (Bool, String, String) {
        let (allowed, err) = ensureHostCapability(ctx.executionId, ["tags.list"], "tags.list")
        if (!allowed) { return (false, "{}", err) }
        let (namespaceStr, query, lang, limit, offset, includeTranslations) = parseTagsListParams(ctx.effectiveParams)
        return (true, buildTagsListResponseJson(namespaceStr, query, lang, limit, offset, includeTranslations), "")
    }

    private static func handleTagsMerge(ctx: WasmHostCallContext): (Bool, String, String) {
        let (allowed, err) = ensureHostCapability(ctx.executionId, ["tags.merge"], "tags.merge")
        if (!allowed) { return (false, "{}", err) }
        let (sourceId, targetId, deleteSource) = parseTagsMergeParams(ctx.effectiveParams)
        if (sourceId <= 0 || targetId <= 0 || sourceId == targetId) {
            return (false, "{}", "invalid sourceId/targetId")
        }
        if (!TagDao.mergeById(sourceId, targetId, deleteSource)) {
            return (false, "{}", "merge failed")
        }
        return (true, "{\"merged\":true}", "")
    }

    private static func handleUiSelect(ctx: WasmHostCallContext): (Bool, String, String) {
        let (allowed, err) = ensureHostCapability(ctx.executionId, ["ui.select"], "ui.select")
        if (!allowed) { return (false, "{}", err) }
        return handleUiSelectCall(ctx.taskId, ctx.effectiveParams, ctx.interactiveSelectEnabled)
    }

    private static func ensureHostCapability(executionId: Int64, candidates: Array<String>, requiredLabel: String): (Bool, String) {
        if (hasCapability(executionId, candidates)) {
            return (true, "")
        }
        return (false, "missing permission: ${requiredLabel}")
    }

    private static func hasCapability(executionId: Int64, candidates: Array<String>): Bool {
        stateMutex.lock()
        match (executionStates.get(executionId)) {
            case Some(state) =>
                for (candidate in candidates) {
                    let key = normalizePermission(candidate)
                    if (key.size == 0) {
                        continue
                    }
                    match (state.permissions.get(key)) {
                        case Some(_) =>
                            stateMutex.unlock()
                            return true
                        case None => ()
                    }
                }
                stateMutex.unlock()
                return false
            case None =>
                stateMutex.unlock()
                return false
        }
    }

    private static func buildArchiveMetadataResponse(effectiveParams: String): (Bool, String, String) {
        var archiveId = ""
        var includePages = false

        try {
            var buf = ByteBuffer()
            unsafe { buf.write(effectiveParams.rawData()) }
            let r = JsonReader(buf)
            if (r.peek() == Some(BeginObject)) {
                r.startObject()
                while (r.peek() != EndObject) {
                    let n = r.readName()
                    match (n) {
                        case "archive_id" => archiveId = r.readValue<String>().trimAscii()
                        case "include_pages" => includePages = parseBoolLoose(r.readValue<String>())
                        case _ => r.skip()
                    }
                }
                r.endObject()
            }
        } catch (_: Exception) {}

        if (archiveId.size == 0) {
            return (false, "{}", "missing archive_id")
        }

        let archive = ArchiveDao.getArchiveById(archiveId)
        if (archive.id.size == 0) {
            return (false, "{}", "archive not found")
        }

        var metadata = MetadataObjectData()
        match (ensureArchiveMetadataObject(archiveId, archive)) {
            case Some(data) => metadata = data
            case None => return (false, "{}", "archive metadata not found")
        }

        let out = ByteBuffer()
        let w = JsonWriter(out)
        w.startObject()
        w.writeName("archive_id").writeValue(archiveId)
        w.writeName("metadata")
        w.startObject()
        w.writeName("title").writeValue(metadata.title)
        w.writeName("type").writeValue(0i32)
        w.writeName("description").writeValue(metadata.description)
        writeMetadataTagsArray(w, metadata.tags)
        writeMetadataAssetsArray(w, metadata.assets)
        w.writeName("children")
        w.startArray()
        w.endArray()
        w.writeName("arcid").writeValue(archive.id)
        w.writeName("filename").writeValue(archive.filename)
        w.writeName("relative_path").writeValue(archive.relative_path)
        w.writeName("file_size").writeValue(archive.file_size)
        w.writeName("pagecount").writeValue(archive.pagecount)
        w.writeName("progress").writeValue(0i32)
        w.writeName("isnew").writeValue(false)
        w.writeName("isfavorite").writeValue(false)
        w.writeName("lastreadtime").writeValue(0i64)
        w.writeName("archivetype").writeValue(archive.archive_type)
        w.writeName("release_at").writeValue(metadata.release_at)
        w.writeName("created_at").writeValue(resolveArchiveMetadataCreatedAt(archive, metadata))
        w.writeName("updated_at").writeValue(resolveArchiveMetadataUpdatedAt(archive, metadata))
        if (includePages) {
            writePageMetadataArray(w, archive.id, MetadataDao.listPageMetadata(archive.id))
        }
        w.endObject()
        w.endObject()
        w.flush()
        return (true, String.fromUtf8(readToEnd(out)), "")
    }

    private static func ensureArchiveMetadataObject(archiveId: String, archive: ArchiveData): Option<MetadataObjectData> {
        let normalizedId = archiveId.trimAscii()
        if (normalizedId.size == 0 || archive.id.size == 0) {
            return None
        }
        match (MetadataDao.getMetadataObject("archive", normalizedId)) {
            case Some(existing) => return Some(existing)
            case None => ()
        }

        let _ = MetadataDao.upsertRootMetadataObject(
            "archive",
            archive.id,
            "",
            "",
            releaseAt: archive.release_at,
            sourceNamespace: "system:bootstrap",
            createdAt: archive.created_at,
            updatedAt: archive.updated_at
        )
        return MetadataDao.getMetadataObject("archive", archive.id)
    }

    private static func resolveArchiveMetadataCreatedAt(archive: ArchiveData, metadata: MetadataObjectData): String {
        if (metadata.created_at.trimAscii().size > 0) {
            return metadata.created_at
        }
        return archive.created_at
    }

    private static func resolveArchiveMetadataUpdatedAt(archive: ArchiveData, metadata: MetadataObjectData): String {
        if (metadata.updated_at.trimAscii().size > 0) {
            return metadata.updated_at
        }
        let createdAt = resolveArchiveMetadataCreatedAt(archive, metadata)
        if (archive.updated_at.trimAscii().size > 0) {
            return archive.updated_at
        }
        return createdAt
    }

    private static func writeMetadataTagsArray(w: JsonWriter, tags: Array<String>): Unit {
        w.writeName("tags")
        w.startArray()
        for (tag in tags) {
            let value = tag.trimAscii()
            if (value.size > 0) {
                w.writeValue(value)
            }
        }
        w.endArray()
    }

    private static func writeMetadataAssetsArray(w: JsonWriter, assets: Array<MetadataAssetData>): Unit {
        w.writeName("assets")
        w.startArray()
        for (asset in assets) {
            let slot = asset.slot.trimAscii().toAsciiLower()
            if (slot.size == 0 || asset.asset_id <= 0) {
                continue
            }
            w.startObject()
            w.writeName("key").writeValue(slot)
            w.writeName("value").writeValue(asset.asset_id)
            w.endObject()
        }
        w.endArray()
    }

    private static func readExtraInt64(extraData: String, key: String): Int64 {
        let normalized = extraData.trimAscii()
        if (normalized.size == 0 || normalized == "null") {
            return 0
        }
        try {
            var buf = ByteBuffer()
            unsafe { buf.write(normalized.rawData()) }
            let r = JsonReader(buf)
            if (r.peek() != Some(BeginObject)) {
                return 0
            }
            r.startObject()
            while (r.peek() != EndObject) {
                let name = r.readName()
                if (name == key) {
                    let raw = String.fromUtf8(r.readValueBytes()).trimAscii()
                    try {
                        let parsed = Int64.parse(raw)
                        return if (parsed > 0) { parsed } else { 0 }
                    } catch (_: Exception) {
                        return 0
                    }
                }
                r.skip()
            }
            r.endObject()
        } catch (_: Exception) {}
        return 0
    }

    private static func writePageMetadataArray(w: JsonWriter, archiveId: String, pages: Array<PageMetadataData>): Unit {
        w.writeName("pages")
        w.startArray()
        for (page in pages) {
            let lyricsAssetId = readExtraInt64(page.extra_data, "lyrics_asset_id")
            w.startObject()
            w.writeName("title").writeValue(page.title)
            w.writeName("description").writeValue(page.description)
            w.writeName("page_number").writeValue(page.page_number)
            w.writeName("entry_path").writeValue(page.entry_path)
            w.writeName("archive_id").writeValue(archiveId)
            w.writeName("thumb").writeValue(page.thumb_asset_id)
            w.writeName("lyrics_asset_id").writeValue(lyricsAssetId)
            w.writeName("release_at").writeValue(page.release_at)
            w.writeName("created_at").writeValue(page.created_at)
            w.writeName("updated_at").writeValue(page.updated_at)
            w.endObject()
        }
        w.endArray()
    }

    private static func handleArchiveExportCoverForSearch(pluginNamespace: String, effectiveParams: String): (Bool, String, String) {
        var archiveId = ""
        var pluginDir = ""
        var cacheSubdir = "cache"
        var overwrite = true
        var exportJpeg = true
        var includeUploadBytes = false
        var maxSide: Int64 = 1280i64
        var jpegQuality: Int64 = 85i64

        try {
            var buf = ByteBuffer()
            unsafe { buf.write(effectiveParams.rawData()) }
            let r = JsonReader(buf)
            if (r.peek() == Some(BeginObject)) {
                r.startObject()
                while (r.peek() != EndObject) {
                    let n = r.readName()
                    match (n) {
                        case "archive_id" => archiveId = r.readValue<String>().trimAscii()
                        case "plugin_dir" => pluginDir = r.readValue<String>().trimAscii()
                        case "cache_subdir" => cacheSubdir = r.readValue<String>().trimAscii()
                        case "overwrite" => overwrite = parseBoolLoose(r.readValue<String>())
                        case "export_jpeg" => exportJpeg = parseBoolLoose(r.readValue<String>())
                        case "include_upload_bytes" => includeUploadBytes = parseBoolLoose(r.readValue<String>())
                        case "max_side" => maxSide = parseInt64Loose(r.readValue<String>(), 1280i64)
                        case "jpeg_quality" => jpegQuality = parseInt64Loose(r.readValue<String>(), 85i64)
                        case _ => r.skip()
                    }
                }
                r.endObject()
            }
        } catch (_: Exception) {}

        if (archiveId.size == 0) {
            return (false, "{}", "missing archive_id")
        }
        if (pluginNamespace.trimAscii().size == 0) {
            return (false, "{}", "missing pluginNamespace context")
        }

        let expectedPluginDir = "${PluginPaths.getPluginRuntimeRoot()}/${pluginNamespace.trimAscii()}"
        if (pluginDir.size > 0 && pluginDir.trimAscii() != expectedPluginDir) {
            return (false, "{}", "invalid pluginDir (must match expected plugin runtime dir)")
        }
        pluginDir = expectedPluginDir
        if (!ensureUnderRuntimeRoot(pluginDir)) {
            return (false, "{}", "invalid pluginDir (not under runtime root)")
        }

        let safeArchiveId = normalizeSafeRelPath(archiveId)
        if (safeArchiveId.size == 0 || safeArchiveId != archiveId.trimAscii()) {
            return (false, "{}", "invalid archive_id")
        }

        var sub = cacheSubdir.trimAscii()
        if (sub.size == 0) { sub = "cache" }
        sub = normalizeSafeRelPath(sub)
        if (sub.size == 0) { sub = "cache" }

        let resolved = resolveArchiveActualPath(archiveId)
        match (resolved) {
            case None => return (false, "{}", "archive not found or path unresolved")
            case Some((archiveType, actualPath)) =>
                let handler = ArchiveHandlerFactory.getInstance().getHandlerByType(archiveType)
                let (entryName, _) = handler.getFirstCoverEntry(actualPath)
                if (entryName.trimAscii().size == 0) {
                    return (false, "{}", "no cover media found in archive")
                }

                var inferredExt = ""
                let parts = entryName.split(".")
                if (parts.size > 1) { inferredExt = parts[parts.size - 1].trimAscii().toAsciiLower() }
                if (inferredExt.size == 0) { inferredExt = "bin" }

                let baseDir = "${pluginDir}/${sub}/${archiveId}"
                let originalPath = "${baseDir}/cover_original.${inferredExt}"
                let uploadPath = "${baseDir}/cover_upload.jpg"
                try { FileUtils.ensureDirectoryExists(Path(baseDir)) } catch (_: Exception) {}

                if (overwrite || !exists(Path(originalPath))) {
                    let ok = handler.extractEntryToFile(actualPath, entryName, originalPath)
                    if (!ok) {
                        return (false, "{}", "extract failed")
                    }
                }
                let originalSha1 = sha1HexFromFile(originalPath)

                var uploadSha1 = ""
                var uploadBytes = Array<UInt8>()
                if (exportJpeg) {
                    if (overwrite || !exists(Path(uploadPath))) {
                        if (inferredExt == "jpg" || inferredExt == "jpeg") {
                            try {
                                FileUtils.safeReplaceFile(Path(uploadPath), Path(originalPath))
                            } catch (e: Exception) {
                                return (false, "{}", "failed to copy jpeg: ${e.message}")
                            }
                        } else {
                            let (exitCode, err1) = runFfmpegToJpeg(originalPath, uploadPath, maxSide, jpegQuality)
                            if (exitCode != 0 || !exists(Path(uploadPath))) {
                                let (exit2, err2) = runImageMagickToJpeg(originalPath, uploadPath, maxSide, jpegQuality)
                                if (exit2 != 0 || !exists(Path(uploadPath))) {
                                    return (false, "{}", "jpeg convert failed: ffmpeg=${err1}; convert=${err2}")
                                }
                            }
                        }
                    }
                    uploadSha1 = sha1HexFromFile(uploadPath)
                    if (includeUploadBytes) {
                        let (okBytes, bytes) = readFileBytesAsUInt8(uploadPath)
                        if (!okBytes) {
                            return (false, "{}", "failed to read upload bytes")
                        }
                        uploadBytes = bytes
                    }
                }

                let out = ByteBuffer()
                let w = JsonWriter(out)
                w.startObject()
                w.writeName("archive_id").writeValue(archiveId)
                w.writeName("entry_name").writeValue(entryName)
                w.writeName("original_path").writeValue(originalPath)
                w.writeName("original_sha1").writeValue(originalSha1)
                w.writeName("upload_path").writeValue(if (exportJpeg) { uploadPath } else { "" })
                w.writeName("upload_sha1").writeValue(if (exportJpeg) { uploadSha1 } else { "" })
                w.writeName("upload_bytes")
                w.startArray()
                if (exportJpeg && includeUploadBytes) {
                    for (b in uploadBytes) {
                        w.writeValue(Int64(b))
                    }
                }
                w.endArray()
                w.endObject()
                w.flush()
                return (true, String.fromUtf8(readToEnd(out)), "")
        }
    }

    private static func exportArchiveEntriesToPluginRuntime(
        executionId: Int64,
        pluginNamespace: String,
        archiveIdRaw: String,
        entries: ArrayList<String>,
        levelsUpRaw: Int64
    ): (Bool, String, String) {
        let trimmedArchiveId = archiveIdRaw.trimAscii()
        if (trimmedArchiveId.size == 0) {
            return (false, "{}", "missing archive_id")
        }
        if (pluginNamespace.trimAscii().size == 0) {
            return (false, "{}", "missing pluginNamespace context")
        }

        let safeArchiveId = normalizeSafeRelPath(trimmedArchiveId)
        if (safeArchiveId.size == 0 || safeArchiveId != trimmedArchiveId) {
            return (false, "{}", "invalid archive_id")
        }

        let pluginDir = FileUtils.joinPath(PluginPaths.getPluginRuntimeRoot(), pluginNamespace.trimAscii())
        if (!ensureUnderRuntimeRoot(pluginDir)) {
            return (false, "{}", "invalid plugin runtime dir")
        }
        let levelsUp = normalizeLevelsUp(levelsUpRaw)

        var archiveType = ""
        var actualPath = ""
        match (resolveArchiveActualPath(trimmedArchiveId)) {
            case Some((resolvedType, resolvedPath)) =>
                archiveType = resolvedType
                actualPath = resolvedPath
            case None => ()
        }

        var handler: Option<ArchiveHandler> = None
        if (archiveType.size > 0 && actualPath.size > 0) {
            handler = Some(ArchiveHandlerFactory.getInstance().getHandlerByType(archiveType))
        }

        var seen = HashMap<String, Bool>()
        var exported = ArrayList<(String, String)>()

        for (rawEntry in entries) {
            let safeRelPath = normalizeSafeRelPath(rawEntry)
            if (safeRelPath.size == 0) {
                continue
            }
            match (seen.get(safeRelPath)) {
                case Some(_) => continue
                case None => seen[safeRelPath] = true
            }

            let relativeOut = "exports/${safeArchiveId}/${safeRelPath}"
            let outputPath = FileUtils.joinPath(pluginDir, relativeOut)
            var exportedOk = false

            match (handler) {
                case Some(h) =>
                    exportedOk = h.extractEntryToFile(actualPath, safeRelPath, outputPath)
                case None => ()
            }

            if (!exportedOk) {
                let sourcePath = resolveAdjacentSourcePathForArchive(executionId, trimmedArchiveId, levelsUp, safeRelPath)
                if (sourcePath.size > 0) {
                    try {
                        FileUtils.ensureDirectoryExists(Path(outputPath).parent)
                        copy(Path(sourcePath), to: Path(outputPath), overwrite: true)
                        exportedOk = true
                    } catch (_: Exception) {}
                }
            }

            if (exportedOk) {
                exported.add((safeRelPath, relativeOut))
            }
        }

        if (exported.size <= 0) {
            return (false, "{}", "no entries exported")
        }

        let out = ByteBuffer()
        let w = JsonWriter(out)
        w.startObject()
        w.writeName("archive_id").writeValue(trimmedArchiveId)
        w.writeName("levels_up").writeValue(levelsUp)
        w.writeName("files")
        w.startArray()
        for ((sourcePath, relativePath) in exported) {
            w.startObject()
            w.writeName("source").writeValue(sourcePath)
            w.writeName("relative_path").writeValue(relativePath)
            w.endObject()
        }
        w.endArray()
        w.writeName("count").writeValue(Int64(exported.size))
        w.endObject()
        w.flush()
        return (true, String.fromUtf8(readToEnd(out)), "")
    }

    private static func ensureUnderRuntimeRoot(pluginDir: String): Bool {
        return ensureUnderDir(PluginPaths.getPluginRuntimeRoot(), pluginDir)
    }

    private static func ensureUnderDir(rootDir: String, targetPath: String): Bool {
        let root = rootDir.trimAscii()
        var p = targetPath.trimAscii()
        if (root.size == 0 || p.size == 0) { return false }
        var cleanRoot = root
        while (cleanRoot.size > 1 && cleanRoot.endsWith("/")) { cleanRoot = cleanRoot[0..(cleanRoot.size - 1)] }
        while (p.size > 1 && p.endsWith("/")) { p = p[0..(p.size - 1)] }
        return p == cleanRoot || p.startsWith("${cleanRoot}/")
    }

    private static func sha1HexFromFile(filePath: String): String {
        let p = Path(filePath)
        if (!exists(p)) { return "" }
        var sha1 = SHA1()
        try {
            let f = File(p, Read)
            try {
                let bufSize: Int64 = 1024 * 1024
                var buf = Array<Byte>(bufSize, repeat: 0)
                while (true) {
                    let n = f.read(buf)
                    if (n <= 0) { break }
                    sha1.write(buf[0..n])
                }
                return toHexString(sha1.finish())
            } finally {
                try { f.close() } catch (_: Exception) {}
            }
        } catch (_: Exception) {
            return ""
        }
    }

    private static func readFileBytesAsUInt8(filePath: String): (Bool, Array<UInt8>) {
        let p = Path(filePath)
        if (!exists(p)) { return (false, Array<UInt8>()) }
        try {
            let f = File(p, Read)
            try {
                let bufSize: Int64 = 1024 * 1024
                var buf = Array<Byte>(bufSize, repeat: 0)
                var out = ArrayList<UInt8>()
                while (true) {
                    let n = f.read(buf)
                    if (n <= 0) { break }
                    for (i in 0..n) {
                        out.add(UInt8(buf[i]))
                    }
                }
                return (true, out.toArray())
            } finally {
                try { f.close() } catch (_: Exception) {}
            }
        } catch (_: Exception) {
            return (false, Array<UInt8>())
        }
    }

    private static func runFfmpegToJpeg(inputPath: String, outputPath: String, maxSide: Int64, jpegQuality: Int64): (Int64, String) {
        let scale = if (maxSide > 0) { maxSide } else { 1280i64 }
        let q = if (jpegQuality > 0) { jpegQuality } else { 85i64 }
        var qv = 31i64 - (q * 29i64 / 100i64)
        if (qv < 2i64) { qv = 2i64 }
        if (qv > 31i64) { qv = 31i64 }
        let vf = "scale=${scale}:${scale}:force_original_aspect_ratio=decrease"
        let lowerInputPath = inputPath.toAsciiLower()
        let isVideoInput = lowerInputPath.endsWith(".mp4") ||
                           lowerInputPath.endsWith(".webm") ||
                           lowerInputPath.endsWith(".mkv") ||
                           lowerInputPath.endsWith(".avi") ||
                           lowerInputPath.endsWith(".mov") ||
                           lowerInputPath.endsWith(".m4v")
        let args = if (isVideoInput) {
            [
                "-hide_banner",
                "-loglevel", "error",
                "-y",
                "-ss", "1",
                "-i", inputPath,
                "-frames:v", "1",
                "-vf", vf,
                "-q:v", qv.toString(),
                "-map_metadata", "-1",
                outputPath
            ]
        } else {
            [
                "-hide_banner",
                "-loglevel", "error",
                "-y",
                "-i", inputPath,
                "-frames:v", "1",
                "-vf", vf,
                "-q:v", qv.toString(),
                "-map_metadata", "-1",
                outputPath
            ]
        }
        try {
            let proc = launch("ffmpeg", args, stdOut: ProcessRedirect.Pipe, stdErr: ProcessRedirect.Pipe)
            let (exitCode, _, stderr) = proc.waitOutput()
            let stderrStr = try { String.fromUtf8(stderr) } catch (_: Exception) { "" }
            return (exitCode, stderrStr)
        } catch (e: Exception) {
            return (1, e.message)
        }
    }

    private static func runImageMagickToJpeg(inputPath: String, outputPath: String, maxSide: Int64, jpegQuality: Int64): (Int64, String) {
        let scale = if (maxSide > 0) { maxSide } else { 1280i64 }
        let q = if (jpegQuality > 0) { jpegQuality } else { 85i64 }
        let firstFrameInput = "${inputPath}[0]"
        let args = [
            firstFrameInput,
            "-strip",
            "-resize", "${scale}x${scale}>",
            "-quality", q.toString(),
            outputPath
        ]
        try {
            let proc = launch("convert", args, stdOut: ProcessRedirect.Pipe, stdErr: ProcessRedirect.Pipe)
            let (exitCode, _, stderr) = proc.waitOutput()
            let stderrStr = try { String.fromUtf8(stderr) } catch (_: Exception) { "" }
            return (exitCode, stderrStr)
        } catch (e: Exception) {
            return (1, e.message)
        }
    }

    private static func handleUiSelectCall(taskId: Int64, effectiveParams: String, interactiveSelectEnabled: Bool): (Bool, String, String) {
        var title = "请选择候选项"
        var message = ""
        var defaultIndex = 0i32
        var timeoutSeconds = 90i32
        var options = ArrayList<WasmRpcSelectOption>()

        try {
            var buf = ByteBuffer()
            unsafe { buf.write(effectiveParams.rawData()) }
            let r = JsonReader(buf)
            if (r.peek() == Some(BeginObject)) {
                r.startObject()
                while (r.peek() != EndObject) {
                    let n = r.readName()
                    match (n) {
                        case "title" => title = r.readValue<String>()
                        case "message" => message = r.readValue<String>()
                        case "defaultIndex" => defaultIndex = Int32(parseInt64Loose(r.readValue<String>(), 0))
                        case "default_index" => defaultIndex = Int32(parseInt64Loose(r.readValue<String>(), 0))
                        case "timeoutSeconds" => timeoutSeconds = Int32(parseInt64Loose(r.readValue<String>(), 90))
                        case "timeout_seconds" => timeoutSeconds = Int32(parseInt64Loose(r.readValue<String>(), 90))
                        case "options" =>
                            if (r.peek() == Some(BeginArray)) {
                                var idx = 0i32
                                r.startArray()
                                while (r.peek() != EndArray) {
                                    var label = ""
                                    var desc = ""
                                    var cover = ""
                                    match (r.peek()) {
                                        case Some(BeginObject) =>
                                            r.startObject()
                                            while (r.peek() != EndObject) {
                                                let k = r.readName()
                                                match (k) {
                                                    case "label" => label = r.readValue<String>()
                                                    case "description" => desc = r.readValue<String>()
                                                    case "cover" => cover = r.readValue<String>()
                                                    case _ => r.skip()
                                                }
                                            }
                                            r.endObject()
                                        case Some(_) =>
                                            label = r.readValue<String>()
                                        case None => ()
                                    }
                                    let fallbackLabel = if (label.trimAscii().size > 0) { label } else { "选项 ${idx + 1}" }
                                    options.add(WasmRpcSelectOption(idx, fallbackLabel, desc, cover))
                                    idx += 1
                                }
                                r.endArray()
                            } else {
                                r.skip()
                            }
                        case _ => r.skip()
                    }
                }
                r.endObject()
            }
        } catch (_: Exception) {}

        if (options.size <= 0) {
            return (false, "{}", "ui.select requires non-empty options")
        }
        if (defaultIndex < 0 || Int64(defaultIndex) >= options.size) {
            defaultIndex = 0
        }
        if (timeoutSeconds < 10) { timeoutSeconds = 10 }
        if (timeoutSeconds > 900) { timeoutSeconds = 900 }

        if (!interactiveSelectEnabled) {
            let out = ByteBuffer()
            let w = JsonWriter(out)
            w.startObject()
            w.writeName("index").writeValue(defaultIndex)
            w.endObject()
            w.flush()
            return (true, String.fromUtf8(readToEnd(out)), "")
        }

        let request = WasmRpcSelectRequest()
        request.taskId = taskId
        request.requestId = "${DateTime.now().toUnixTimeStamp().toMilliseconds()}_${taskId}"
        request.title = if (title.trimAscii().size > 0) { title } else { "请选择候选项" }
        request.message = message
        request.defaultIndex = defaultIndex
        request.timeoutSeconds = timeoutSeconds
        request.options = options.toArray()
        request.createdAtSeconds = DateTime.now().toUnixTimeStamp().toSeconds()

        let key = buildRpcSelectKey(taskId, request.requestId)
        rpcSelectMutex.lock()
        rpcSelectPending[key] = request
        rpcSelectMutex.unlock()

        let currentProgress = TaskDao.getTaskDataById(taskId).progress
        TaskModel.updateTaskProgress(taskId, currentProgress, buildRpcSelectMessage(request))

        let deadline = DateTime.now().toUnixTimeStamp().toSeconds() + Int64(timeoutSeconds)
        while (true) {
            var selected = -1i32
            var done = false
            rpcSelectMutex.lock()
            match (rpcSelectPending.get(key)) {
                case Some(req) =>
                    if (req.responded) {
                        selected = req.selectedIndex
                        done = true
                        rpcSelectPending.remove(key)
                    }
                case None =>
                    done = true
            }
            rpcSelectMutex.unlock()

            if (done) {
                if (selected >= 0) {
                    let out = ByteBuffer()
                    let w = JsonWriter(out)
                    w.startObject()
                    w.writeName("index").writeValue(selected)
                    w.endObject()
                    w.flush()
                    TaskModel.updateTaskProgress(taskId, currentProgress, "已接收人工选择结果")
                    return (true, String.fromUtf8(readToEnd(out)), "")
                }
                if (selected == -1) {
                    return (false, "{}", "ui.select cancelled by user")
                }
            }

            if (DateTime.now().toUnixTimeStamp().toSeconds() >= deadline) {
                rpcSelectMutex.lock()
                rpcSelectPending.remove(key)
                rpcSelectMutex.unlock()
                return (false, "{}", "ui.select timeout: no response")
            }

            sleep(Duration.second)
        }

        return (false, "{}", "ui.select finished without response")
    }

    private static func buildRpcSelectKey(taskId: Int64, requestId: String): String {
        return "${taskId}:${requestId.trimAscii()}"
    }

    private static func buildRpcSelectMessage(request: WasmRpcSelectRequest): String {
        let out = ByteBuffer()
        let w = JsonWriter(out)
        w.startObject()
        w.writeName("type").writeValue("rpc_select")
        w.writeName("request_id").writeValue(request.requestId)
        w.writeName("title").writeValue(request.title)
        w.writeName("message").writeValue(request.message)
        w.writeName("default_index").writeValue(request.defaultIndex)
        w.writeName("timeout_seconds").writeValue(request.timeoutSeconds)
        w.writeName("options")
        w.startArray()
        for (opt in request.options) {
            w.startObject()
            w.writeName("index").writeValue(opt.index)
            w.writeName("label").writeValue(opt.label)
            w.writeName("description").writeValue(opt.description)
            w.writeName("cover").writeValue(opt.cover)
            w.endObject()
        }
        w.endArray()
        w.endObject()
        w.flush()
        return "[RPC_SELECT]" + String.fromUtf8(readToEnd(out))
    }

    private static func buildAdjacentListingResponse(executionId: Int64, archiveId: String, levelsUp: Int64): (Bool, String, String) {
        let trimmedArchiveId = archiveId.trimAscii()
        let normalizedLevelsUp = normalizeLevelsUp(levelsUp)
        let cacheKey = buildAdjacentBaseDirCacheKey(trimmedArchiveId, normalizedLevelsUp)
        match (getCachedAdjacentListing(executionId, cacheKey)) {
            case Some(cachedJson) => return (true, cachedJson, "")
            case None => ()
        }

        match (resolveAdjacentBaseDir(executionId, trimmedArchiveId, normalizedLevelsUp)) {
            case None => return (false, "{}", "adjacent directory not found")
            case Some(baseDir) =>
                let responseJson = buildAdjacentListingResponseJson(trimmedArchiveId, baseDir)
                cacheAdjacentListing(executionId, cacheKey, responseJson)
                return (true, responseJson, "")
        }
    }

    private static func buildAdjacentListingResponseJson(archiveId: String, baseDir: String): String {
        let entries = DirectoryScanner.listDirectory(baseDir)
        let out = ByteBuffer()
        let w = JsonWriter(out)
        w.startObject()
        w.writeName("archive_id").writeValue(archiveId)
        w.writeName("base_dir").writeValue(baseDir)
        w.writeName("files")
        w.startArray()
        var count: Int64 = 0
        for (e in entries) {
            let fullPath = FileUtils.joinPath(baseDir, e)
            if (DirectoryScanner.fileExists(fullPath)) {
                w.writeValue(e)
                count += 1
            }
        }
        w.endArray()
        w.writeName("count").writeValue(count)
        w.endObject()
        w.flush()
        return String.fromUtf8(readToEnd(out))
    }

    private static func buildArchiveListingResponse(executionId: Int64, archiveId: String): (Bool, String, String) {
        let trimmedArchiveId = archiveId.trimAscii()
        let cacheKey = buildArchiveListingCacheKey(trimmedArchiveId)
        match (getCachedAdjacentListing(executionId, cacheKey)) {
            case Some(cachedJson) => return (true, cachedJson, "")
            case None => ()
        }

        match (resolveArchiveActualPath(trimmedArchiveId)) {
            case None => return (false, "{}", "archive not found or path unresolved")
            case Some((archiveType, actualPath)) =>
                let handler = ArchiveHandlerFactory.getInstance().getHandlerByType(archiveType)
                let entries = handler.listEntries(actualPath)
                let responseJson = buildArchiveListingResponseJson(trimmedArchiveId, entries)
                cacheAdjacentListing(executionId, cacheKey, responseJson)
                return (true, responseJson, "")
        }
    }

    private static func buildArchiveListingResponseJson(archiveId: String, entries: Array<String>): String {
        let out = ByteBuffer()
        let w = JsonWriter(out)
        w.startObject()
        w.writeName("archive_id").writeValue(archiveId)
        w.writeName("files")
        w.startArray()
        for (entry in entries) {
            w.writeValue(entry)
        }
        w.endArray()
        w.writeName("count").writeValue(Int64(entries.size))
        w.endObject()
        w.flush()
        return String.fromUtf8(readToEnd(out))
    }

    private static func buildAdjacentTextResponseJson(text: String): String {
        let out = ByteBuffer()
        let w = JsonWriter(out)
        w.startObject()
        w.writeName("text").writeValue(text)
        w.endObject()
        w.flush()
        return String.fromUtf8(readToEnd(out))
    }

    private static func buildAdjacentTextsResponse(
        executionId: Int64,
        archiveId: String,
        levelsUp: Int64,
        fileNames: ArrayList<String>
    ): (Bool, String, String) {
        let trimmedArchiveId = archiveId.trimAscii()
        let normalizedLevelsUp = normalizeLevelsUp(levelsUp)
        let collected = HashMap<String, String>()
        var count: Int64 = 0
        for (rawFileName in fileNames) {
            let safeName = normalizeSafeRelPath(rawFileName)
            if (safeName.size == 0) {
                continue
            }
            match (collected.get(safeName)) {
                case Some(_) => continue
                case None => ()
            }
            let (ok, text, _) = readAdjacentTextCached(executionId, trimmedArchiveId, normalizedLevelsUp, safeName)
            if (!ok) {
                continue
            }
            collected[safeName] = text
            count += 1
        }

        let out = ByteBuffer()
        let w = JsonWriter(out)
        w.startObject()
        w.writeName("archive_id").writeValue(trimmedArchiveId)
        w.writeName("levels_up").writeValue(normalizedLevelsUp)
        w.writeName("texts")
        w.startObject()
        for (fileName in fileNames) {
            let safeName = normalizeSafeRelPath(fileName)
            if (safeName.size == 0) {
                continue
            }
            match (collected.get(safeName)) {
                case Some(text) =>
                    w.writeName(safeName).writeValue(text)
                case None => ()
            }
        }
        w.endObject()
        w.writeName("count").writeValue(count)
        w.endObject()
        w.flush()
        return (true, String.fromUtf8(readToEnd(out)), "")
    }

    private static func buildTankoubonArchivesResponseJson(tankoubonId: String): String {
        let archiveIds = TankoubonDao.getArchivesInTankoubon(tankoubonId)
        let out = ByteBuffer()
        let w = JsonWriter(out)
        w.startObject()
        w.writeName("tankoubon_id").writeValue(tankoubonId)
        w.writeName("archive_ids")
        w.startArray()
        for (archiveId in archiveIds) {
            let trimmedId = archiveId.trimAscii()
            if (trimmedId.size > 0) {
                w.writeValue(trimmedId)
            }
        }
        w.endArray()
        w.endObject()
        w.flush()
        return String.fromUtf8(readToEnd(out))
    }

    private static func readAdjacentTextCached(executionId: Int64, archiveId: String, levelsUp: Int64, safeName: String): (Bool, String, String) {
        let trimmedArchiveId = archiveId.trimAscii()
        let normalizedLevelsUp = normalizeLevelsUp(levelsUp)
        let cacheKey = buildAdjacentTextCacheKey(trimmedArchiveId, normalizedLevelsUp, safeName)
        match (getCachedAdjacentText(executionId, cacheKey)) {
            case Some(cachedText) => return (true, cachedText, "")
            case None => ()
        }

        let sourcePath = resolveAdjacentSourcePathForArchive(executionId, trimmedArchiveId, normalizedLevelsUp, safeName)
        if (sourcePath.size == 0) {
            return (false, "", "adjacent file not found")
        }
        try {
            let text = decodeUtf8(File.readFrom(Path(sourcePath)))
            cacheAdjacentText(executionId, cacheKey, text)
            return (true, text, "")
        } catch (e: Exception) {
            return (false, "", "read failed: ${e.message}")
        }
    }

    private static func readArchiveTextCached(executionId: Int64, archiveId: String, safeName: String): (Bool, String, String) {
        let trimmedArchiveId = archiveId.trimAscii()
        let cacheKey = buildArchiveTextCacheKey(trimmedArchiveId, safeName)
        match (getCachedAdjacentText(executionId, cacheKey)) {
            case Some(cachedText) => return (true, cachedText, "")
            case None => ()
        }

        match (resolveArchiveActualPath(trimmedArchiveId)) {
            case None => return (false, "", "archive not found or path unresolved")
            case Some((archiveType, actualPath)) =>
                let handler = ArchiveHandlerFactory.getInstance().getHandlerByType(archiveType)
                let (exitCode, data, error) = handler.extractEntryToStream(actualPath, safeName)
                if (exitCode != 0) {
                    let err = try {
                        String.fromUtf8(error)
                    } catch (_: Exception) {
                        ""
                    }
                    return (false, "", if (err.trimAscii().size > 0) { err } else { "extract failed" })
                }

                let text = try {
                    String.fromUtf8(data)
                } catch (e: Exception) {
                    return (false, "", "read failed: ${e.message}")
                }
                cacheAdjacentText(executionId, cacheKey, text)
                return (true, text, "")
        }
    }

    private static func readFileNameArrayInto(r: JsonReader, out: ArrayList<String>): Unit {
        match (r.peek()) {
            case Some(BeginArray) =>
                r.startArray()
                while (r.peek() != EndArray) {
                    match (r.peek()) {
                        case Some(_) =>
                            let value = r.readValue<String>().trimAscii()
                            if (value.size > 0) {
                                out.add(value)
                            }
                        case None => break
                    }
                }
                r.endArray()
            case Some(_) =>
                let value = r.readValue<String>().trimAscii()
                if (value.size > 0) {
                    out.add(value)
                }
            case None => ()
        }
    }

    private static func normalizeLevelsUp(levelsUpRaw: Int64): Int64 {
        var levelsUp = levelsUpRaw
        if (levelsUp < 0) { levelsUp = 0 }
        if (levelsUp > 8) { levelsUp = 8 }
        return levelsUp
    }

    private static func buildAdjacentBaseDirCacheKey(archiveId: String, levelsUp: Int64): String {
        return "${archiveId.trimAscii()}#${levelsUp.toString()}"
    }

    private static func buildAdjacentTextCacheKey(archiveId: String, levelsUp: Int64, safeRelPath: String): String {
        return "${buildAdjacentBaseDirCacheKey(archiveId, levelsUp)}#${safeRelPath}"
    }

    private static func buildArchiveListingCacheKey(archiveId: String): String {
        return "archive#${archiveId.trimAscii()}"
    }

    private static func buildArchiveTextCacheKey(archiveId: String, safeRelPath: String): String {
        return "${buildArchiveListingCacheKey(archiveId)}#${safeRelPath}"
    }

    private static func getCachedAdjacentBaseDir(executionId: Int64, cacheKey: String): Option<String> {
        stateMutex.lock()
        match (executionStates.get(executionId)) {
            case Some(state) =>
                let cached = state.adjacentBaseDirs.get(cacheKey)
                stateMutex.unlock()
                return cached
            case None =>
                stateMutex.unlock()
                return None
        }
    }

    private static func cacheAdjacentBaseDir(executionId: Int64, cacheKey: String, baseDir: String): Unit {
        stateMutex.lock()
        match (executionStates.get(executionId)) {
            case Some(state) =>
                state.adjacentBaseDirs[cacheKey] = baseDir
                executionStates[executionId] = state
            case None => ()
        }
        stateMutex.unlock()
    }

    private static func getCachedAdjacentListing(executionId: Int64, cacheKey: String): Option<String> {
        stateMutex.lock()
        match (executionStates.get(executionId)) {
            case Some(state) =>
                let cached = state.adjacentListings.get(cacheKey)
                stateMutex.unlock()
                return cached
            case None =>
                stateMutex.unlock()
                return None
        }
    }

    private static func cacheAdjacentListing(executionId: Int64, cacheKey: String, responseJson: String): Unit {
        stateMutex.lock()
        match (executionStates.get(executionId)) {
            case Some(state) =>
                state.adjacentListings[cacheKey] = responseJson
                executionStates[executionId] = state
            case None => ()
        }
        stateMutex.unlock()
    }

    private static func getCachedAdjacentText(executionId: Int64, cacheKey: String): Option<String> {
        stateMutex.lock()
        match (executionStates.get(executionId)) {
            case Some(state) =>
                let cached = state.adjacentTexts.get(cacheKey)
                stateMutex.unlock()
                return cached
            case None =>
                stateMutex.unlock()
                return None
        }
    }

    private static func cacheAdjacentText(executionId: Int64, cacheKey: String, text: String): Unit {
        stateMutex.lock()
        match (executionStates.get(executionId)) {
            case Some(state) =>
                state.adjacentTexts[cacheKey] = text
                executionStates[executionId] = state
            case None => ()
        }
        stateMutex.unlock()
    }

    private static func storeTcpConnection(executionId: Int64, socket: TcpSocket): Int64 {
        stateMutex.lock()
        match (executionStates.get(executionId)) {
            case Some(state) =>
                let handle = state.nextTcpHandle
                state.nextTcpHandle += 1
                state.tcpConnections[handle] = socket
                executionStates[executionId] = state
                stateMutex.unlock()
                return handle
            case None =>
                stateMutex.unlock()
                try { socket.close() } catch (_: Exception) {}
                throw Exception("execution state not found")
        }
    }

    private static func getTcpConnection(executionId: Int64, handle: Int64): TcpSocket {
        stateMutex.lock()
        match (executionStates.get(executionId)) {
            case Some(state) =>
                match (state.tcpConnections.get(handle)) {
                    case Some(socket) =>
                        stateMutex.unlock()
                        return socket
                    case None =>
                        stateMutex.unlock()
                        throw Exception("invalid tcp handle")
                }
            case None =>
                stateMutex.unlock()
                throw Exception("execution state not found")
        }
    }

    private static func closeTcpConnections(state: WasmExecutionState): Unit {
        for ((_, socket) in state.tcpConnections) {
            try { socket.close() } catch (_: Exception) {}
        }
    }

    private static func applySocketTimeout(socket: TcpSocket, timeoutMs: Int32): Unit {
        match (durationFromTimeoutMs(timeoutMs)) {
            case Some(timeout) =>
                socket.readTimeout = timeout
                socket.writeTimeout = timeout
            case None => ()
        }
    }

    private static func durationFromTimeoutMs(timeoutMs: Int32): Option<Duration> {
        if (timeoutMs <= 0) {
            return None
        }
        return Some(Duration.millisecond * Int64(timeoutMs))
    }

    private static func parsePermissionMap(permissions: String): HashMap<String, Bool> {
        let out = HashMap<String, Bool>()
        let trimmed = permissions.trimAscii()
        if (trimmed.size == 0) {
            return out
        }
        for (raw in trimmed.split(",")) {
            let key = normalizePermission(raw)
            if (key.size > 0) {
                out[key] = true
            }
        }
        return out
    }

    private static func normalizePermission(permission: String): String {
        var perm = permission.trimAscii().toAsciiLower()
        if (perm.startsWith("\"") && perm.endsWith("\"") && perm.size >= 2) {
            perm = perm[1..perm.size - 1]
        }
        if (perm.contains("=")) {
            let parts = perm.split("=", 2)
            perm = parts[0].trimAscii()
        }
        return perm
    }

    private static func recordHostCallMetrics(executionId: Int64, method: String, elapsedMs: Int64): Unit {
        let metricKey = if (method.trimAscii().size > 0) { method.trimAscii() } else { "invalid" }
        stateMutex.lock()
        match (executionStates.get(executionId)) {
            case Some(state) =>
                let count = match (state.hostCallCounts.get(metricKey)) {
                    case Some(v) => v
                    case None => 0
                }
                let totalElapsed = match (state.hostCallElapsedMs.get(metricKey)) {
                    case Some(v) => v
                    case None => 0
                }
                state.hostCallCounts[metricKey] = count + 1
                state.hostCallElapsedMs[metricKey] = totalElapsed + elapsedMs
                executionStates[executionId] = state
            case None => ()
        }
        stateMutex.unlock()
    }

    private static func logHostCallSummary(state: WasmExecutionState): Unit {
        if (state.taskId <= 0) {
            return
        }
        appendHostCallMetricLog(state, "archive.list_adjacent_files")
        appendHostCallMetricLog(state, "archive.read_adjacent_text")
        appendHostCallMetricLog(state, "archive.read_adjacent_texts")
        appendHostCallMetricLog(state, "archive.list_files")
        appendHostCallMetricLog(state, "archive.read_text")
        appendHostCallMetricLog(state, "archive.get_metadata")
        appendHostCallMetricLog(state, "archive.export_entries")
        appendHostCallMetricLog(state, "tankoubon.list_archives")
        appendHostCallMetricLog(state, "tags.list")
        appendHostCallMetricLog(state, "tags.merge")
        appendHostCallMetricLog(state, "ui.select")
    }

    private static func appendHostCallMetricLog(state: WasmExecutionState, method: String): Unit {
        let count = match (state.hostCallCounts.get(method)) {
            case Some(v) => v
            case None => 0
        }
        if (count <= 0) {
            return
        }
        let totalElapsed = match (state.hostCallElapsedMs.get(method)) {
            case Some(v) => v
            case None => 0
        }
        let avgElapsed = if (count > 0) { totalElapsed / count } else { 0 }
        TaskIO.appendLog(
            state.taskId,
            "[wasm-host-metric] ${method} count=${count.toString()} total_ms=${totalElapsed.toString()} avg_ms=${avgElapsed.toString()}"
        )
    }

    private static func nowMillis(): Int64 {
        return DateTime.now().toUnixTimeStamp().toMilliseconds()
    }

    private static func normalizeSafeRelPath(input: String): String {
        var s = input.trimAscii().replace("\\", "/")
        while (s.startsWith("/")) { s = s[1..s.size] }
        let parts = s.split("/")
        var outParts = ArrayList<String>()
        for (part in parts) {
            let trimmed = part.trimAscii()
            if (trimmed.size == 0 || trimmed == "." || trimmed == "..") {
                continue
            }
            if (trimmed.contains("/") || trimmed.contains("\\")) {
                continue
            }
            outParts.add(trimmed)
        }
        return String.join(outParts.toArray(), delimiter: "/")
    }

    private static func parseBoolLoose(raw: String): Bool {
        let v = raw.trimAscii().toAsciiLower()
        return v == "true" || v == "1" || v == "yes" || v == "y" || v == "on"
    }

    private static func parseInt64Loose(raw: String, defaultValue: Int64): Int64 {
        let trimmed = raw.trimAscii()
        if (trimmed.size == 0) { return defaultValue }
        try {
            return Int64.parse(trimmed)
        } catch (_: Exception) {
            return defaultValue
        }
    }

    private static func decodeUtf8(bytes: Array<UInt8>): String {
        if (bytes.size == 0) {
            return ""
        }
        try {
            return String.fromUtf8(bytes)
        } catch (_: Exception) {
            return ""
        }
    }

    private static func encodeUtf8(text: String): Array<UInt8> {
        let size = text.size
        var out = Array<UInt8>(size, repeat: 0u8)
        for (i in 0..size) {
            out[i] = UInt8(text[i])
        }
        return out
    }

    private static func uint8ArrayToByte(bytes: Array<UInt8>): Array<Byte> {
        var out = Array<Byte>(bytes.size, repeat: 0)
        for (i in 0..bytes.size) {
            out[i] = bytes[i]
        }
        return out
    }

    private static func byteArrayToUInt8(bytes: Array<Byte>): Array<UInt8> {
        var out = Array<UInt8>(bytes.size, repeat: 0u8)
        for (i in 0..bytes.size) {
            out[i] = UInt8(bytes[i])
        }
        return out
    }
}
