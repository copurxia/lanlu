package lanlu_cli

import std.argopt.ParsedArguments
import std.collection.HashMap
import std.convert.*
import stdx.encoding.json.*

/**
 * 处理 Source 插件列表
 */
public func handleSourceList(client: LanluApiClient, outputMode: String): Unit {
    let resp = client.get("/api/admin/source-plugins", HashMap<String, String>())
    let body = client.readBody(resp)
    printJsonOrText(body, outputMode, { b => printSourceList(b) })
}

/**
 * 处理 Source 首页
 */
public func handleSourceHome(client: LanluApiClient, opts: ParsedArguments, outputMode: String): Unit {
    handleSourceAction(client, opts, outputMode, "source_home")
}

/**
 * 处理 Source 搜索
 */
public func handleSourceSearch(client: LanluApiClient, opts: ParsedArguments, outputMode: String): Unit {
    handleSourceAction(client, opts, outputMode, "source_search")
}

/**
 * 处理 Source 筛选器
 */
public func handleSourceFilters(client: LanluApiClient, opts: ParsedArguments, outputMode: String): Unit {
    handleSourceAction(client, opts, outputMode, "source_filters")
}

/**
 * 处理 Source 下载
 */
public func handleSourceDownload(client: LanluApiClient, opts: ParsedArguments, outputMode: String): Unit {
    if (opts.nonOptions.size < 3) {
        throw IllegalArgumentException("usage: source-download <namespace> <remote-id> --category-id <id>")
    }
    let namespace = opts.nonOptions[1]
    let remoteId = opts.nonOptions[2]
    let categoryId = opts.options.get("category-id") ?? ""
    if (categoryId.size == 0) {
        throw IllegalArgumentException("--category-id is required")
    }
    let kind = opts.options.get("kind") ?? "archive"

    let body = JsonObject()
    body.put("remote_id", JsonString(remoteId))
    body.put("category_id", JsonString(categoryId))
    body.put("kind", JsonString(kind))

    let resp = client.post("/api/admin/source-plugins/${namespace}/download", body.toString())
    let respBody = client.readBody(resp)

    if (outputMode != "text") {
        printJson(respBody, outputMode)
        return
    }

    let root = parseJson(respBody, "source download").asObject()
    let taskId = getInt(root, "task_id") ?? 0
    if (taskId <= 0) {
        println(respBody)
        return
    }
    println("created source download task: ${taskId}")

    let (wait, interval, timeout) = resolveWait(opts)
    if (wait) {
        let result = waitForTask(client, taskId, interval, timeout, outputMode)
        println(result.toString())
    }
}

private func handleSourceAction(client: LanluApiClient, opts: ParsedArguments, outputMode: String, action: String): Unit {
    if (opts.nonOptions.size < 2) {
        throw IllegalArgumentException("usage: ${action} <namespace> [query]")
    }
    let namespace = opts.nonOptions[1]

    let body = JsonObject()
    if (action == "source_search") {
        let query = if (opts.nonOptions.size > 2) { opts.nonOptions[2] } else { "" }
        body.put("query", JsonString(query))
        let page = opts.options.get("page") ?? "1"
        try {
            body.put("page", JsonInt(Int64.parse(page)))
        } catch (_: Exception) {
            body.put("page", JsonInt(1))
        }
        let filters = opts.options.get("filters") ?? ""
        if (filters.size > 0) {
            try {
                body.put("filters", JsonValue.fromStr(filters))
            } catch (e: Exception) {
                throw IllegalArgumentException("invalid --filters JSON: ${e.message}")
            }
        }
    }

    let resp = client.post("/api/admin/source-plugins/${namespace}/action/${action}", body.toString())
    let respBody = client.readBody(resp)
    printJsonOrText(respBody, outputMode, { b => printSourceItems(b) })
}

private func printSourceList(body: String): Unit {
    let arr = JsonValue.fromStr(body).asArray()
    println("namespace\tname\tenabled")
    for (i in 0..arr.size()) {
        let o = arr[i].asObject()
        let ns = getString(o, "namespace") ?? ""
        let name = getString(o, "name") ?? ""
        let enabled = getBool(o, "enabled") ?? false
        println("${ns}\t${name}\t${enabled}")
    }
}

private func printSourceItems(body: String): Unit {
    let root = parseJson(body, "source action").asObject()
    match (getObject(root, "data")) {
        case Some(data) =>
            match (getArray(data, "items")) {
                case Some(items) =>
                    for (i in 0..items.size()) {
                        let o = items[i].asObject()
                        let title = getString(o, "title") ?? ""
                        let remoteId = getString(o, "remote_id") ?? ""
                        let kind = getString(o, "kind") ?? "archive"
                        println("[${kind}] ${remoteId} ${title}")
                    }
                case None => println(body)
            }
        case None => println(body)
    }
}

private func resolveWait(opts: ParsedArguments): (Bool, Int64, Int64) {
    let wait = opts.options.contains("wait")
    let interval = try { Int64.parse(opts.options.get("interval") ?? "1000") } catch (_: Exception) { 1000 }
    let timeout = try { Int64.parse(opts.options.get("timeout") ?? "300000") } catch (_: Exception) { 300000 }
    return (wait, interval, timeout)
}

private func printJson(body: String, outputMode: String): Unit {
    if (outputMode == "pretty-json") {
        println(JsonValue.fromStr(body).toJsonString())
    } else {
        println(body)
    }
}

private func printJsonOrText(body: String, outputMode: String, textPrinter: (String) -> Unit): Unit {
    if (outputMode == "text") {
        textPrinter(body)
    } else if (outputMode == "pretty-json") {
        println(JsonValue.fromStr(body).toJsonString())
    } else {
        println(body)
    }
}
