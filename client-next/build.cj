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

// fontkit native 静态库需与 cjpm 目标链接器匹配：
// - Linux：cargo 默认 target 与 cjpm 目标（x86_64-unknown-linux-gnu）一致，产物 libfontkit_native.a 可直接链接。
// - Windows：cargo 默认 host 为 MSVC，产物是 fontkit_native.lib，而 cjpm 的 x86_64-w64-mingw32 目标用
//   MinGW 链接器，需要以 GNU target 构建 libfontkit_native.a 并拷贝到 ffi.c 指向的 target/release 目录。
@When[os == "Windows"]
private func buildFontkitNative(): Int64 {
    let exitCode = execute("cargo",
        ["build", "--release", "--target", "x86_64-pc-windows-gnu", "--manifest-path",
            "../packages/fontkit_ffi/native/Cargo.toml"], stdOut: ProcessRedirect.Inherit,
        stdErr: ProcessRedirect.Inherit)
    if (exitCode != 0) {
        return exitCode
    }
    let built = Path("../packages/fontkit_ffi/native/target/x86_64-pc-windows-gnu/release/libfontkit_native.a")
    let stagedDir = Path("../packages/fontkit_ffi/native/target/release")
    if (!exists(stagedDir)) {
        Directory.create(stagedDir, recursive: true)
    }
    copy(built, to: stagedDir.join("libfontkit_native.a"), overwrite: true)
    0
}

@When[os != "Windows"]
private func buildFontkitNative(): Int64 {
    execute("cargo", ["build", "--release", "--manifest-path", "../packages/fontkit_ffi/native/Cargo.toml"],
        stdOut: ProcessRedirect.Inherit, stdErr: ProcessRedirect.Inherit)
}

// webview native 与 fontkit native 遵循同一套 FFI 产物约定：Windows 下必须生成
// GNU 格式静态库，并暂存到 packages/webview/cjpm.toml 的 ffi.c 搜索目录。
@When[os == "Windows"]
private func buildWebviewNative(): Int64 {
    let exitCode = execute("cargo",
        ["build", "--release", "--target", "x86_64-pc-windows-gnu", "--manifest-path",
            "../packages/webview/native/Cargo.toml"], stdOut: ProcessRedirect.Inherit, stdErr: ProcessRedirect.Inherit)
    if (exitCode != 0) {
        return exitCode
    }
    let built = Path("../packages/webview/native/target/x86_64-pc-windows-gnu/release/libwebview_native.a")
    let stagedDir = Path("../packages/webview/native/target/release")
    if (!exists(stagedDir)) {
        Directory.create(stagedDir, recursive: true)
    }
    copy(built, to: stagedDir.join("libwebview_native.a"), overwrite: true)
    0
}

@When[os == "Windows"]
private func buildSubtitleNative(): Int64 {
    let avStatus = execute("x86_64-w64-mingw32-gcc",
        ["-std=c11", "-Wall", "-Wextra", "-Werror", "-O2", "-c",
            "../packages/libavformat_ffi/native/lanlu_avformat_bridge.c", "-o",
            "../packages/libavformat_ffi/native/lanlu_avformat_bridge.o"], stdOut: ProcessRedirect.Inherit,
        stdErr: ProcessRedirect.Inherit)
    if (avStatus != 0) {
        return avStatus
    }
    let avArchive = execute("x86_64-w64-mingw32-ar",
        ["rcs", "../packages/libavformat_ffi/native/liblanlu_avformat_bridge.a",
            "../packages/libavformat_ffi/native/lanlu_avformat_bridge.o"], stdOut: ProcessRedirect.Inherit,
        stdErr: ProcessRedirect.Inherit)
    if (avArchive != 0) {
        return avArchive
    }
    let assStatus = execute("x86_64-w64-mingw32-gcc",
        ["-std=c11", "-Wall", "-Wextra", "-Werror", "-O2", "-c", "../packages/libass_ffi/native/lanlu_ass_bridge.c",
            "-o", "../packages/libass_ffi/native/lanlu_ass_bridge.o"], stdOut: ProcessRedirect.Inherit,
        stdErr: ProcessRedirect.Inherit)
    if (assStatus != 0) {
        return assStatus
    }
    execute("x86_64-w64-mingw32-ar",
        ["rcs", "../packages/libass_ffi/native/liblanlu_ass_bridge.a",
            "../packages/libass_ffi/native/lanlu_ass_bridge.o"], stdOut: ProcessRedirect.Inherit,
        stdErr: ProcessRedirect.Inherit)
}

@When[os != "Windows"]
private func buildSubtitleNative(): Int64 {
    let avStatus = execute("cc",
        ["-std=c11", "-Wall", "-Wextra", "-Werror", "-O2", "-fPIC", "-c",
            "../packages/libavformat_ffi/native/lanlu_avformat_bridge.c", "-o",
            "../packages/libavformat_ffi/native/lanlu_avformat_bridge.o"], stdOut: ProcessRedirect.Inherit,
        stdErr: ProcessRedirect.Inherit)
    if (avStatus != 0) {
        return avStatus
    }
    let avArchive = execute("ar",
        ["rcs", "../packages/libavformat_ffi/native/liblanlu_avformat_bridge.a",
            "../packages/libavformat_ffi/native/lanlu_avformat_bridge.o"], stdOut: ProcessRedirect.Inherit,
        stdErr: ProcessRedirect.Inherit)
    if (avArchive != 0) {
        return avArchive
    }
    let assStatus = execute("cc",
        ["-std=c11", "-Wall", "-Wextra", "-Werror", "-O2", "-fPIC", "-c",
            "../packages/libass_ffi/native/lanlu_ass_bridge.c", "-o", "../packages/libass_ffi/native/lanlu_ass_bridge.o"],
        stdOut: ProcessRedirect.Inherit, stdErr: ProcessRedirect.Inherit)
    if (assStatus != 0) {
        return assStatus
    }
    execute("ar",
        ["rcs", "../packages/libass_ffi/native/liblanlu_ass_bridge.a",
            "../packages/libass_ffi/native/lanlu_ass_bridge.o"], stdOut: ProcessRedirect.Inherit,
        stdErr: ProcessRedirect.Inherit)
}

@When[os != "Windows"]
private func buildWebviewNative(): Int64 {
    execute("cargo", ["build", "--release", "--manifest-path", "../packages/webview/native/Cargo.toml"],
        stdOut: ProcessRedirect.Inherit, stdErr: ProcessRedirect.Inherit)
}

main(args: Array<String>): Int64 {
    if (args.size == 0) {
        return 0
    }
    match (args[0]) {
        case "pre-build" | "pre-test" | "pre-run" =>
            let exitCode = buildFontkitNative()
            if (exitCode != 0) {
                return exitCode
            }
            let webviewExitCode = buildWebviewNative()
            if (webviewExitCode != 0) {
                return webviewExitCode
            }
            let subtitleExitCode = buildSubtitleNative()
            if (subtitleExitCode != 0) {
                return subtitleExitCode
            }
            // 源资源缺失或复制失败都属于打包错误，直接让构建失败。
            stageDesktopAssets()
            0
        case _ => 0
    }
}
