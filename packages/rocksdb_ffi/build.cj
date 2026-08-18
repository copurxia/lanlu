import std.process.{execute, ProcessRedirect}

// rocksdb_ffi 的 pre-build 钩子：自动编译版本探测 bridge（native/lanlu_rocksdb_bridge.c），
// 生成 [ffi.c] 需要的 liblanlu_rocksdb_bridge.a。这样本包独立 `cjpm build/test` 或作为
// 依赖被构建时都能自动生成，无需先跑 client-next。
// 平台分支：Linux/macOS 用 g++（version.h 是 C++ 头），Windows 用 x86_64-w64-mingw32-g++。

@When[os == "Windows"]
private func buildRocksBridge(): Int64 {
    let status = execute("x86_64-w64-mingw32-g++",
        ["-std=c++17", "-Wall", "-Wextra", "-O2", "-c", "native/lanlu_rocksdb_bridge.c", "-o",
            "native/lanlu_rocksdb_bridge.o"], stdOut: ProcessRedirect.Inherit, stdErr: ProcessRedirect.Inherit)
    if (status != 0) {
        return status
    }
    return execute("ar", ["rcs", "native/liblanlu_rocksdb_bridge.a", "native/lanlu_rocksdb_bridge.o"],
        stdOut: ProcessRedirect.Inherit, stdErr: ProcessRedirect.Inherit)
}

@When[os != "Windows"]
private func buildRocksBridge(): Int64 {
    let status = execute("g++",
        ["-std=c++17", "-Wall", "-Wextra", "-O2", "-fPIC", "-c", "native/lanlu_rocksdb_bridge.c", "-o",
            "native/lanlu_rocksdb_bridge.o"], stdOut: ProcessRedirect.Inherit, stdErr: ProcessRedirect.Inherit)
    if (status != 0) {
        return status
    }
    return execute("ar", ["rcs", "native/liblanlu_rocksdb_bridge.a", "native/lanlu_rocksdb_bridge.o"],
        stdOut: ProcessRedirect.Inherit, stdErr: ProcessRedirect.Inherit)
}

main(args: Array<String>): Int64 {
    if (args.size == 0) {
        return 0
    }
    match (args[0]) {
        case "pre-build" | "pre-test" | "pre-run" =>
            return buildRocksBridge()
        case _ => return 0
    }
}
