package lwindow

// L 层剪贴板通道（M6 第 2 步后）：**只有协议**，没有文件桥。
// - 写：引擎发 `lw_clipboard.set(mime, text)`，壳负责写系统剪贴板；
// - 读：引擎发 `lw_clipboard.get(serial)`，壳读系统剪贴板后回 `clipboard.text`，
//   结果落进 lwpFrameTick 维护的缓存（异步语义，第一次读大概率是空串）。

/// 写系统剪贴板。协议不可用时返回 false（没有退路：M6 已删除文件桥）。
public func clipboardSetText(text: String): Unit {
    match (lwpClipboardSetText(text)) {
        case Some(_) => ()
        case None => ()   // 通道未就绪：丢弃。上层不做重试（剪贴板丢一次可接受）
    }
}

/// 读系统剪贴板：返回本地缓存（异步填充）。首次调用可能为空。
public func clipboardGetText(): String {
    match (lwpClipboardGetText()) {
        case Some(v) => v
        case None => ""
    }
}

/// 缓存里是否有文本（不额外发起请求）。
public func clipboardHasText(): Bool {
    match (lwpClipboardGetText()) {
        case Some(v) => v.size > 0
        case None => false
    }
}
