package cui.input

import lbase.CuiException

import std.env.getVariable
import std.fs.{File, Path}
import lbase.{ClipboardBackend, clipboardBackend}
public struct ClipboardData {
    public let mimeType: String
    public let bytes: Array<UInt8>

    public init(mimeType: String, bytes: Array<UInt8>) {
        this.mimeType = mimeType
        this.bytes = bytes
    }
}

/**
 * 剪贴板（P5：无 SDL）。
 *
 * 引擎与壳层之间用文件桥通信：
 * - 写：引擎把文本写入 `$HOME/clip_out.txt`，壳层在窗口输入回调里刷进系统剪贴板；
 * - 读：壳层在用户按 Ctrl+V 时把系统剪贴板读进 `$HOME/clip_in.txt`（系统只对该路径放行），
 *   引擎随后直接读取该文件。
 */
public class Clipboard {
    public static func setText(text: String): Unit {
        match (clipboardBackend) {
            case Some(backend) =>
                backend.setText(text)
                return
            case None => ()
        }
        writeClipFile("clip_out.txt", text)
    }

    public static func hasText(): Bool {
        match (clipboardBackend) {
            case Some(backend) => return backend.hasText()
            case None => ()
        }
        readClipFile("clip_in.txt").size > 0
    }

    public static func getText(): String {
        match (clipboardBackend) {
            case Some(backend) => return backend.getText()
            case None => ()
        }
        readClipFile("clip_in.txt")
    }

    public static func setPrimarySelectionText(text: String): Unit {
        // OHOS 没有 primary selection（X11 概念），仅按剪贴板处理
        setText(text)
    }

    public static func hasPrimarySelectionText(): Bool {
        hasText()
    }

    public static func getPrimarySelectionText(): String {
        getText()
    }

    public static func setData(items: Array<ClipboardData>): Unit {
        // 只支持纯文本：取第一段 UTF-8 文本项
        for (item in items) {
            if (item.mimeType.contains("text")) {
                try {
                    setText(String.fromUtf8(item.bytes))
                } catch (_: Exception) {}
                return
            }
        }
    }

    public static func clearData(): Unit {
        writeClipFile("clip_out.txt", "")
        writeClipFile("clip_in.txt", "")
    }

    public static func hasData(mimeType: String): Bool {
        mimeType.contains("text") && hasText()
    }

    public static func getData(mimeType: String): ?Array<UInt8> {
        if (!mimeType.contains("text")) {
            return None
        }
        let text = getText()
        if (text.size == 0) {
            return None
        }
        Some(text.toArray())
    }

    public static func mimeTypes(): Array<String> {
        if (hasText()) {
            ["text/plain;charset=utf-8"]
        } else {
            Array<String>()
        }
    }
}

private func clipHome(): String {
    getVariable("HOME") ?? "."
}

private func writeClipFile(name: String, text: String): Unit {
    try {
        File.writeTo(Path(clipHome() + "/" + name), text.toArray())
    } catch (_: Exception) {}
}

private func readClipFile(name: String): String {
    let path = clipHome() + "/" + name
    try {
        String.fromUtf8(File.readFrom(Path(path)))
    } catch (_: Exception) {
        ""
    }
}
