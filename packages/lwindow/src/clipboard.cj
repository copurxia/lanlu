package lwindow

// L 层剪贴板通道（P5）：引擎与 ArkTS 之间没有可用的同步 FFI，用文件传递。
// - 写：引擎把文本写 clip_out.txt，ArkTS 轮询写入系统剪贴板；
// - 读：引擎写 clip_req.txt，ArkTS 读系统剪贴板后写 clip_in.txt，引擎轮询取回。

import std.env.getVariable
import std.fs.{File, Path}

private func clipDir(): String {
    getVariable("HOME") ?? "."
}

private func writeFileText(name: String, text: String): Unit {
    try {
        File.writeTo(Path(clipDir() + "/" + name), text.toArray())
    } catch (_) {}
}

private func readFileText(name: String): String {
    try {
        String.fromUtf8(File.readFrom(Path(clipDir() + "/" + name)))
    } catch (_) {
        ""
    }
}

private func removeFile(name: String): Unit {
    try {
        File.writeTo(Path(clipDir() + "/" + name), Array<UInt8>())
    } catch (_) {}
}

/// 写系统剪贴板（交给 ArkTS 执行）。
public func clipboardSetText(text: String): Unit {
    writeFileText("clip_out.txt", text)
}

/// 读系统剪贴板（阻塞等待 ArkTS 回写，最多 800ms）。
public func clipboardGetText(): String {
    removeFile("clip_in.txt")
    writeFileText("clip_req.txt", "1")
    var waited = 0
    while (waited < 80) {
        let text = readFileText("clip_in.txt")
        if (text.size > 0) {
            removeFile("clip_in.txt")
            return text
        }
        sleep(Duration.millisecond * 10)
        waited++
    }
    ""
}

public func clipboardHasText(): Bool {
    clipboardGetText().size > 0
}
