import std.fs.{copy, Directory, exists, Path}
import std.process.{execute, ProcessRedirect}

private let LOGO_SOURCE = Path("assets/lanlu_logo_gold.png")

private func stageDesktopAssets(): Unit {
    // cjpm 1.1.3 只调用 pre-* 钩子；预先准备两个 profile，保证普通/调试产物目录都自带资源。
    for (output in [Path("target/release/bin/lanlu_logo_gold.png"), Path("target/debug/bin/lanlu_logo_gold.png")]) {
        if (!exists(output.parent)) {
            Directory.create(output.parent, recursive: true)
        }
        copy(LOGO_SOURCE, to: output, overwrite: true)
    }
}

main(args: Array<String>): Int64 {
    if (args.size == 0) {
        return 0
    }
    match (args[0]) {
        case "pre-build" | "pre-test" | "pre-run" =>
            let exitCode = execute("cargo",
                ["build", "--release", "--manifest-path", "../packages/fontkit_ffi/native/Cargo.toml"],
                stdOut: ProcessRedirect.Inherit, stdErr: ProcessRedirect.Inherit)
            if (exitCode != 0) {
                return exitCode
            }
            // 源资源缺失或复制失败都属于打包错误，直接让构建失败。
            stageDesktopAssets()
            0
        case _ => 0
    }
}
