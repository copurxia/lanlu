import std.process.{execute, ProcessRedirect}

// postgresql-driver 的 pre-build 钩子：编译 native/lanlu_pg_bridge.c 为
// liblanlu_pg_bridge.a，供 [ffi.c] + -llanlu_pg_bridge 链接。
// 模式照抄 packages/rocksdb_ffi/build.cj：pre-build/pre-test/pre-run 都触发，
// 使本包独立构建与作为依赖被构建时都能自动生成。
// Windows 用 x86_64-w64-mingw32-gcc（如将来需要；当前 CI 仅 Linux/macOS）。

@When[os == "Windows"]
private func buildPgBridge(): Int64 {
    let status = execute("x86_64-w64-mingw32-gcc",
        ["-std=c11", "-Wall", "-Wextra", "-O2", "-c", "native/lanlu_pg_bridge.c", "-o",
            "native/lanlu_pg_bridge.o", "-I/usr/include/postgresql", "-I./native"],
        stdOut: ProcessRedirect.Inherit, stdErr: ProcessRedirect.Inherit)
    if (status != 0) {
        return status
    }
    return execute("ar", ["rcs", "native/liblanlu_pg_bridge.a", "native/lanlu_pg_bridge.o"],
        stdOut: ProcessRedirect.Inherit, stdErr: ProcessRedirect.Inherit)
}

@When[os != "Windows"]
private func buildPgBridge(): Int64 {
    // pg 头文件位置探测：Debian/Ubuntu 在 /usr/include/postgresql，Alpine 在 /usr/include，
    // macOS (libpq via brew) 在 /opt/homebrew/include 与 /usr/local/include。
    let candidates = ["-I/usr/include/postgresql", "-I/usr/include", "-I/opt/homebrew/include", "-I/usr/local/include"]
    var last = 0
    for (inc in candidates) {
        let status = execute("cc",
            ["-std=c11", "-Wall", "-Wextra", "-O2", "-fPIC", inc, "-I./native", "-c",
                "native/lanlu_pg_bridge.c", "-o", "native/lanlu_pg_bridge.o"],
            stdOut: ProcessRedirect.Pipe, stdErr: ProcessRedirect.Pipe)
        if (status == 0) {
            return execute("ar", ["rcs", "native/liblanlu_pg_bridge.a", "native/lanlu_pg_bridge.o"],
                stdOut: ProcessRedirect.Inherit, stdErr: ProcessRedirect.Inherit)
        }
        last = status
    }
    return last
}

main(args: Array<String>): Int64 {
    if (args.size == 0) {
        return 0
    }
    match (args[0]) {
        case "pre-build" | "pre-test" | "pre-run" =>
            return buildPgBridge()
        case _ => return 0
    }
}
