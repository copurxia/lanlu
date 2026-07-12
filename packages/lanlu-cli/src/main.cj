package lanlu_cli

import std.argopt.*
import std.env.getVariable

/**
 * Lanlu 命令行客户端入口
 */
main(args: Array<String>): Int64 {
    let specs = [
        Full("host", r'H', RequiredValue),
        Full("token", r't', RequiredValue),
        Full("output", r'o', RequiredValue),
        Long("no-proxy", NoValue),
        Full("help", r'h', NoValue),

        // search
        Full("category", r'c', RequiredValue),
        Long("page", RequiredValue),
        Long("page-size", RequiredValue),
        Long("sortby", RequiredValue),
        Long("order", RequiredValue),
        Long("new-only", NoValue),
        Long("untagged-only", NoValue),
        Long("favorite-only", NoValue),
        Long("group-by-tanks", NoValue),

        // archive detail
        Long("include-pages", NoValue),

        // source
        Long("filters", RequiredValue),
        Long("category-id", RequiredValue),
        Long("kind", RequiredValue),

        // metadata
        Long("target-type", RequiredValue),
        Long("param", RequiredValue),
        Long("write-back", NoValue),

        // upload
        Long("chunk-size", RequiredValue),
        Long("overwrite", NoValue),

        // wait
        Long("wait", NoValue),
        Long("interval", RequiredValue),
        Long("timeout", RequiredValue)
    ]

    var opts: ParsedArguments
    try {
        opts = parseArguments(args, specs)
    } catch (e: ArgumentParseException) {
        eprintln("argument error: ${e.message}")
        printUsage()
        return 1
    }

    if (opts.options.contains("help") || opts.options.contains('h')) {
        printUsage()
        return 0
    }

    if (opts.nonOptions.size == 0) {
        eprintln("missing command")
        printUsage()
        return 1
    }

    let outputMode = opts.options.get("output") ?? "text"
    if (outputMode != "text" && outputMode != "json" && outputMode != "pretty-json") {
        eprintln("invalid --output: ${outputMode}")
        return 1
    }

    var token = opts.options.get("token") ?? (getVariable("LANLU_TOKEN") ?? "")
    if (token.size == 0) {
        eprintln("LANLU_TOKEN environment variable or --token is required")
        return 1
    }

    let host = opts.options.get("host") ?? (getVariable("LANLU_HOST") ?? "http://localhost:8082")

    let cmd = opts.nonOptions[0]
    let knownCommands = ["search", "archive-show", "category-list", "source-list",
                         "source-home", "source-search", "source-filters",
                         "source-download", "download-url", "upload",
                         "metadata-run", "task"]
    var isKnown = false
    for (c in knownCommands) {
        if (c == cmd) {
            isKnown = true
            break
        }
    }
    if (!isKnown) {
        eprintln("unknown command: ${cmd}")
        printUsage()
        return 1
    }

    let noProxy = opts.options.contains("no-proxy")
    let client = LanluApiClient(host: host, token: token, noProxy: noProxy)
    try {
        match (cmd) {
            case "search" => handleSearch(client, opts, outputMode)
            case "archive-show" => handleArchiveShow(client, opts, outputMode)
            case "category-list" => handleCategoryList(client, outputMode)
            case "source-list" => handleSourceList(client, outputMode)
            case "source-home" => handleSourceHome(client, opts, outputMode)
            case "source-search" => handleSourceSearch(client, opts, outputMode)
            case "source-filters" => handleSourceFilters(client, opts, outputMode)
            case "source-download" => handleSourceDownload(client, opts, outputMode)
            case "download-url" => handleDownloadUrl(client, opts, outputMode)
            case "upload" => handleUpload(client, opts, outputMode)
            case "metadata-run" => handleMetadataRun(client, opts, outputMode)
            case "task" => handleTask(client, opts, outputMode)
            case _ => ()
        }
    } catch (e: Exception) {
        eprintln("error: ${e.message}")
        return 1
    } finally {
        client.close()
    }

    return 0
}

private func printUsage(): Unit {
    println("lanlu-cli [global options] <command> [args]")
    println("")
    println("Global options:")
    println("  -H, --host <url>          server host (env: LANLU_HOST)")
    println("  -t, --token <token>       bearer token (env: LANLU_TOKEN)")
    println("  -o, --output <mode>       text|json|pretty-json (default: text)")
    println("      --no-proxy            ignore http_proxy / https_proxy")
    println("  -h, --help                show this help")
    println("")
    println("Commands:")
    println("  search <filter>           search local archives")
    println("  archive-show <arcid>      show archive metadata")
    println("  category-list             list categories")
    println("  source-list               list source plugins")
    println("  source-home <namespace>   source plugin home")
    println("  source-search <namespace> <query>")
    println("  source-filters <namespace>")
    println("  source-download <namespace> <remote-id> --category-id <id>")
    println("  download-url <url>")
    println("  upload <file> --category-id <id>")
    println("  metadata-run <namespace> <target-id>")
    println("  task <id>                 show task detail")
    println("")
    println("Create commands support --wait [--interval <ms>] [--timeout <ms>].")
}
