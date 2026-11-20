package cui.dialogs

import std.collection.HashMap
import std.sync.Mutex

public enum FileDialogResult {
    | FileDialogPending
    | FileDialogCanceled
    | FileDialogSelected(Array<String>, ?Int32)
    | FileDialogFailed(String)
}

// ── 平台对话框派发（P6：替代文件桥的主路径）────────────────────────────
// 宿主（client-next 胶水）启动时注册 dispatcher：内部调 lw_dialog.* 协议并返回 serial；
// 结果经 LWindowLifecycleEvent.DialogResult 回来后，宿主调 resolveDialogBySerial 回填。
// dispatcher 未注册或派发失败时，submitRequest 回落文件桥（无壳环境/测试用）。
//
// 线程约定：dispatcher 在发起线程调用；resolveDialogBySerial 可能在事件线程 ——
// 登记表由 dialogLock 保护。

internal let dialogLock = Mutex()
internal var pendingBySerial = HashMap<UInt32, FileDialogRequest>()

/// 平台对话框派发钩子。参数：(请求, kind = "open"|"save"|"folder", 选项)。
/// 返回 Some(serial) = 已派发（宿主随后经 resolveDialogBySerial 回填）；
/// 返回 None = 派发失败（回落文件桥）。
public var dialogDispatcher: ?((FileDialogRequest, String, FileDialogOptions) -> ?UInt32) = None

internal func registerPendingDialog(serial: UInt32, request: FileDialogRequest): Unit {
    synchronized(dialogLock) {
        pendingBySerial[serial] = request
    }
}

internal func takePendingDialog(serial: UInt32): ?FileDialogRequest {
    synchronized(dialogLock) {
        let found = pendingBySerial.get(serial)
        pendingBySerial.remove(serial)
        found
    }
}

/// 宿主把平台对话框结果按 serial 回填（path 空 = 取消）。
/// 返回 false = 没有对应的待定请求（陈旧回执，忽略）。
public func resolveDialogBySerial(serial: UInt32, value: FileDialogResult): Bool {
    let request = takePendingDialog(serial)
    match (request) {
        case Some(req) =>
            req.complete(value)
            true
        case None => false
    }
}

public struct FileDialogFilter {
    public let name: String
    public let pattern: String

    public init(name: String, pattern: String) {
        this.name = name
        this.pattern = pattern
    }
}

public struct FileDialogOptions {
    public var filters: Array<FileDialogFilter>
    public var defaultLocation: ?String
    public var allowMany: Bool

    public init(
        filters!: Array<FileDialogFilter> = [],
        defaultLocation!: ?String = None,
        allowMany!: Bool = false
    ) {
        this.filters = filters
        this.defaultLocation = defaultLocation
        this.allowMany = allowMany
    }
}

public class FileDialogRequest {
    private let lock = Mutex()
    private var current = FileDialogResult.FileDialogPending
    private var nativeResources: ?FileDialogNativeResources
    internal let id: Int64

    internal init(id: Int64, nativeResources: FileDialogNativeResources) {
        this.id = id
        this.nativeResources = Some(nativeResources)
    }

    public func result(): FileDialogResult {
        var value = FileDialogResult.FileDialogPending
        synchronized(lock) {
            value = current
        }
        // P5：结果由壳层（ArkTS picker）写入文件，这里惰性消费
        if (match (value) { case FileDialogResult.FileDialogPending => true; case _ => false }) {
            pollDialogBridge(this)
            synchronized(lock) {
                value = current
            }
        }
        value
    }

    public func isDone(): Bool {
        match (result()) {
            case FileDialogResult.FileDialogPending => false
            case _ => true
        }
    }

    internal func complete(value: FileDialogResult): Unit {
        synchronized(lock) {
            current = value
        }
    }

    internal func userdata(): CPointer<Unit> {
        match (nativeResources) {
            case Some(resources) => resources.userdata()
            case None => CPointer<Unit>()
        }
    }

    internal func rawFilters(): CPointer<SdlDialogFileFilter> {
        match (nativeResources) {
            case Some(resources) => resources.rawFilters
            case None => CPointer<SdlDialogFileFilter>()
        }
    }

    internal func filterCount(): Int32 {
        match (nativeResources) {
            case Some(resources) => resources.filterCount
            case None => 0
        }
    }

    internal func defaultLocation(): CString {
        match (nativeResources) {
            case Some(resources) => resources.defaultLocation
            case None => nullDialogCString()
        }
    }

    internal func releaseNativeResources(): Unit {
        match (nativeResources) {
            case Some(resources) =>
                resources.close()
                nativeResources = None<FileDialogNativeResources>
            case None => ()
        }
    }
}
