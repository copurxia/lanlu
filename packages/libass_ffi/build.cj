import std.process.{execute, ProcessRedirect}

private let SOURCE = "native/lanlu_ass_bridge.c"
private let OBJECT = "native/lanlu_ass_bridge.o"
private let LIBRARY = "native/liblanlu_ass_bridge.a"

@When[os == "Windows"]
private func compileBridge(): Int64 {
    let compileStatus = execute("x86_64-w64-mingw32-gcc",
        ["-std=c11", "-Wall", "-Wextra", "-Werror", "-O2", "-c", SOURCE, "-o", OBJECT], stdOut: ProcessRedirect.Inherit,
        stdErr: ProcessRedirect.Inherit)
    if (compileStatus != 0) {
        return compileStatus
    }
    execute("x86_64-w64-mingw32-ar", ["rcs", LIBRARY, OBJECT], stdOut: ProcessRedirect.Inherit,
        stdErr: ProcessRedirect.Inherit)
}

@When[os != "Windows"]
private func compileBridge(): Int64 {
    let compileStatus = execute("cc", ["-std=c11", "-Wall", "-Wextra", "-Werror", "-O2", "-fPIC", "-c", SOURCE, "-o",
        OBJECT], stdOut: ProcessRedirect.Inherit, stdErr: ProcessRedirect.Inherit)
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
