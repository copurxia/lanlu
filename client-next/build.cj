import std.process.{execute, ProcessRedirect}

main(args: Array<String>): Int64 {
    if (args.size == 0) {
        return 0
    }
    match (args[0]) {
        case "pre-build" | "pre-test" | "pre-run" =>
            execute("cargo", ["build", "--release", "--manifest-path", "../packages/fontkit_ffi/native/Cargo.toml"],
                stdOut: ProcessRedirect.Inherit, stdErr: ProcessRedirect.Inherit)
        case _ => 0
    }
}

