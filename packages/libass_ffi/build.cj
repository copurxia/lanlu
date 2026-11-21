import std.collection.ArrayList
import std.process.{execute, executeWithOutput, ProcessRedirect}

private let SOURCE = "native/lanlu_ass_bridge.c"
private let OBJECT = "native/lanlu_ass_bridge.o"
private let LIBRARY = "native/liblanlu_ass_bridge.a"

// Ubuntu 把 freetype 头文件放在 /usr/include/freetype2，桥里的 `#include <ft2build.h>`
// 需要额外的 -I；路径随发行版与 pkg-config 前缀而变，不能硬编码。取不到时返回空
// 数组，让编译以原始的 "ft2build.h: No such file" 失败，而不是掩盖成别的问题。
@When[os != "Windows"]
private func freetypeCflags(): Array<String> {
    try {
        let (code, out, _) = executeWithOutput("pkg-config", ["--cflags", "freetype2"])
        if (code != 0) {
            return Array<String>()
        }
        let flags = ArrayList<String>()
        for (part in String.fromUtf8(out).trimAscii().split(" ")) {
            if (part.size > 0) {
                flags.add(part)
            }
        }
        return flags.toArray()
    } catch (e: Exception) {
        return Array<String>()
    }
}

@When[os == "Windows"]
private func compileBridge(): Int64 {
    let compileStatus = execute("x86_64-w64-mingw32-gcc",
        ["-std=c11", "-Wall", "-Wextra", "-Werror", "-O2", "-c", SOURCE, "-o", OBJECT], stdOut: ProcessRedirect.Inherit,
        stdErr: ProcessRedirect.Inherit)
    if (compileStatus != 0) {
        return compileStatus
    }
    execute("ar", ["rcs", LIBRARY, OBJECT], stdOut: ProcessRedirect.Inherit,
        stdErr: ProcessRedirect.Inherit)
}

@When[os != "Windows"]
private func compileBridge(): Int64 {
    let args = ["-std=c11", "-Wall", "-Wextra", "-Werror", "-O2", "-fPIC"]
        .concat(freetypeCflags())
        .concat(["-c", SOURCE, "-o", OBJECT])
    let compileStatus = execute("cc", args, stdOut: ProcessRedirect.Inherit, stdErr: ProcessRedirect.Inherit)
    if (compileStatus != 0) {
        return compileStatus
    }
    execute("ar", ["rcs", LIBRARY, OBJECT], stdOut: ProcessRedirect.Inherit, stdErr: ProcessRedirect.Inherit)
}

main(args: Array<String>): Int64 {
    if (args.size == 0) {
        return 0
    }
    match (args[0]) {
        case "pre-build" | "pre-test" | "pre-run" => compileBridge()
        case _ => 0
    }
}
