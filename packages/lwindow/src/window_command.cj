package lwindow

// L 层窗口控制通道（P5）：引擎侧把"最小化/最大化/恢复/关闭"写成命令文件，
// ArkTS 侧轮询执行（引擎进程与 ArkTS 之间没有可用的同步 FFI 通道）。

import std.env.getVariable
import std.fs.{File, Path}

/// 命令文件路径（应用沙箱内，ArkTS 与引擎两侧都可访问）。
private func commandPath(): String {
    let home = getVariable("HOME") ?? "."
    home + "/window_cmd.txt"
}

/// 请求一个窗口命令：minimize / maximize / restore / close。
public func requestWindowCommand(command: String): Unit {
    try {
        File.writeTo(Path(commandPath()), command.toArray())
    } catch (_) {}
}
