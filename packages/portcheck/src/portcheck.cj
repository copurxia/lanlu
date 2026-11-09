package portcheck

// 移植自检入口（跨平台）：OHOS_SELFTEST=1 时执行，结果写入 HOME 下文本文件，
// 便于 `hdc file recv` 取回核对。桌面构建默认关闭，行为与之前一致。
import std.env.getVariable
import std.fs.File

public func enabled(): Bool {
    (getVariable("OHOS_SELFTEST") ?? "0") == "1"
}

public func runIfEnabled(): Unit {
    if (!enabled()) {
        return
    }
    let base = getVariable("HOME") ?? "."
    ohosImageSelftest(base)
    ohosNetSelftest(base)
    ohosMediaSelftest(base)
}
