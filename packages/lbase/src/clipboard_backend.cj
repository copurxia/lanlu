package lbase

// 平台剪贴板后端接口（P6 自 lgui.input 迁入：接口归中立层，平台层注册实现，
// UI 框架的门面消费它 —— 三方无需互相依赖）。
//
// 背景：某些平台（如 HarmonyOS）SDL 自带的剪贴板实现在真机上读写都取不到系统
// 剪贴板内容，由平台适配层（lwindow）注册自己的实现；无后端时消费方走各自的回落路径。

public interface ClipboardBackend {
    func setText(text: String): Unit
    func getText(): String
    func hasText(): Bool
}

/// 当前平台的剪贴板后端；由平台适配层启动时注册，None 时走调用方的回落路径。
public var clipboardBackend: ?ClipboardBackend = None
