package cui.dialogs

import std.env.getVariable
import std.fs.{File, Path}
import cui.base.SdlWindow
/**
 * 文件选择对话框（P5：无 SDL，走文件桥）。
 *
 * 引擎把请求写入 `$HOME/filedlg_req.txt`（"id|kind|allowMany|defaultLocation"），
 * 壳层（ArkTS）轮询到后弹系统 picker，并把结果写入 `$HOME/filedlg_result.txt`
 * （"id|ok|canceled|failed|path1;path2"）。引擎在 [FileDialogRequest.result] 里
 * 惰性读取结果文件完成请求，因此调用方原有的轮询逻辑无需改动。
 */
public class FileDialogs {
    public static func openFile(
        options!: FileDialogOptions = FileDialogOptions(),
        window!: ?SdlWindow = None
    ): FileDialogRequest {
        let request = createFileDialogRequest(options)
        submitRequest(request, "open", options)
        request
    }

    public static func saveFile(
        options!: FileDialogOptions = FileDialogOptions(),
        window!: ?SdlWindow = None
    ): FileDialogRequest {
        let request = createFileDialogRequest(options)
        submitRequest(request, "save", options)
        request
    }

    public static func openFolder(
        options!: FileDialogOptions = FileDialogOptions(),
        window!: ?SdlWindow = None
    ): FileDialogRequest {
        let request = createFileDialogRequest(options)
        submitRequest(request, "folder", options)
        request
    }
}

internal func dialogBridgeHome(): String {
    getVariable("HOME") ?? "."
}

private func submitRequest(request: FileDialogRequest, kind: String, options: FileDialogOptions): Unit {
    // 平台派发优先：宿主注册的 dispatcher 走 lw_dialog 协议（OHOS picker / 桌面 portal）。
    match (dialogDispatcher) {
        case Some(dispatch) =>
            match (dispatch(request, kind, options)) {
                case Some(serial) =>
                    registerPendingDialog(serial, request)
                    return
                case None => ()   // 派发失败：回落文件桥
            }
        case None => ()
    }
    let location = match (options.defaultLocation) {
        case Some(v) => v
        case None => ""
    }
    let line = "${request.id}|${kind}|${if (options.allowMany) { "1" } else { "0" }}|${location}\n"
    try {
        File.writeTo(Path(dialogBridgeHome() + "/filedlg_req.txt"), line.toArray())
    } catch (_: Exception) {}
}

/// 惰性消费壳层写回的结果文件；匹配到当前请求 id 时完成请求。
internal func pollDialogBridge(request: FileDialogRequest): Unit {
    let path = Path(dialogBridgeHome() + "/filedlg_result.txt")
    let text = try {
        String.fromUtf8(File.readFrom(path))
    } catch (_: Exception) {
        return
    }
    let trimmed = text.trimAscii()
    if (trimmed.size == 0) {
        return
    }
    let parts = trimmed.split("|")
    if (parts.size < 2) {
        return
    }
    let id = parseDialogId(parts[0])
    if (id < 0 || id != request.id) {
        return
    }
    let status = parts[1]
    match (status) {
        case "canceled" => request.complete(FileDialogResult.FileDialogCanceled)
        case "failed" => request.complete(FileDialogResult.FileDialogFailed(if (parts.size > 2) { parts[2] } else { "failed" }))
        case "ok" =>
            let paths: Array<String> = if (parts.size > 2 && parts[2].size > 0) {
                parts[2].split(";")
            } else {
                Array<String>()
            }
            if (paths.size == 0) {
                request.complete(FileDialogResult.FileDialogCanceled)
            } else {
                request.complete(FileDialogResult.FileDialogSelected(paths, Some(0)))
            }
        case _ => ()
    }
    // 消费后清空，避免旧结果影响后续请求
    try {
        File.writeTo(path, Array<UInt8>())
    } catch (_: Exception) {}
}

/// 解析请求 id（纯数字）；非法返回 -1。
private func parseDialogId(text: String): Int64 {
    if (text.size == 0) {
        return -1
    }
    var value: Int64 = 0
    for (ch in text.toArray()) {
        if (ch < UInt8(48) || ch > UInt8(57)) {
            return -1
        }
        value = value * 10 + Int64(ch - UInt8(48))
    }
    value
}
