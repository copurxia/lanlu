import std.fs.{copy, Directory, exists, File, Path}
import std.process.{execute, ProcessRedirect}

private let LOGO_SOURCE = Path("assets/lanlu_logo_gold.png")
private let EMBEDDED_LOGO_OUTPUT = Path("src/ui/embedded_logo.cj")

// 将 logo PNG 字节内嵌为源码（EMBEDDED_LOGO_PNG），发布产物不再附带 PNG 文件。
// 生成内容与既有文件一致时跳过重写，避免每次构建都触发 ui 包重编译。
private func generateEmbeddedLogo(): Unit {
    let bytes = File.readFrom(LOGO_SOURCE)
    let builder = StringBuilder()
    builder.append("// 本文件由 build.cj 根据 assets/lanlu_logo_gold.png 自动生成，请勿手工修改。\n")
    builder.append("package lanlu_client_next.ui\n\n")
    builder.append("public let EMBEDDED_LOGO_PNG: Array<UInt8> = [\n")
    for (i in 0..bytes.size) {
        if (i % 16 == 0) {
            builder.append("    ")
        }
        builder.append(hexByte(bytes[i]))
        builder.append(",")
        if (i % 16 == 15) {
            builder.append("\n")
        } else {
            builder.append(" ")
        }
    }
    if (bytes.size % 16 != 0) {
        builder.append("\n")
    }
    builder.append("]\n")
    let generated = builder.toString()
    if (exists(EMBEDDED_LOGO_OUTPUT) && String.fromUtf8(File.readFrom(EMBEDDED_LOGO_OUTPUT)) == generated) {
        return
    }
    File.writeTo(EMBEDDED_LOGO_OUTPUT, generated.toArray())
}

private let HEX_CHARS = ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "A", "B", "C", "D", "E", "F"]

private func hexByte(b: UInt8): String {
    "0x${HEX_CHARS[Int64(b) / 16]}${HEX_CHARS[Int64(b) % 16]}u8"
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
    let avArchive = execute("ar",
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
    execute("ar",
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
            // logo 字节内嵌为源码；源资源缺失或生成失败都属于打包错误，直接让构建失败。
            generateEmbeddedLogo()
            0
        case _ => 0
    }
}
