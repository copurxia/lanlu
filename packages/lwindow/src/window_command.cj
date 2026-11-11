package lwindow

// L 层窗口控制通道（M6 第 4 步后）：**只有协议**，没有命令文件。
// 引擎发 `lw_window.set_state` / `lw_window.close` / `lw_app.exit`，壳执行。

/// 请求一个窗口命令：minimize / maximize / restore / close / exit。
/// 协议不可用时静默丢弃（没有退路：命令文件已删除）。
public func requestWindowCommand(command: String): Unit {
    match (lwpWindowCommand(command)) {
        case Some(_) => ()
        case None => ()
    }
}
