package cli

import std.argopt.ParsedArguments
import std.collection.HashMap
import stdx.encoding.json.*

/**
 * 处理本地归档搜索
 */
public func handleSearch(client: LanluApiClient, opts: ParsedArguments, outputMode: String): Unit {
    let filter = if (opts.nonOptions.size > 1) { opts.nonOptions[1] } else { "" }
    let params = HashMap<String, String>()
    params["filter"] = filter
    addIfPresent(opts, params, "category")
    addIfPresent(opts, params, "page")
    addIfPresent(opts, params, "page-size", "pageSize")
    addIfPresent(opts, params, "sortby")
    addIfPresent(opts, params, "order")
    addFlagIfPresent(opts, params, "new-only", "newonly")
    addFlagIfPresent(opts, params, "untagged-only", "untaggedonly")
    addFlagIfPresent(opts, params, "favorite-only", "favoriteonly")
    addFlagIfPresent(opts, params, "group-by-tanks", "groupby_tanks")

    let resp = client.get("/api/search", params)
    let body = client.readBody(resp)

    if (outputMode != "text") {
        printJson(body, outputMode)
        return
    }

    let root = parseJson(body, "search result").asObject()
    match (getArray(root, "data")) {
        case Some(data) => printSearchItems(data)
        case None => println(body)
    }
    match (getArray(root, "groups")) {
        case Some(groups) =>
            for (i in 0..groups.size()) {
                println("")
                let g = groups[i].asObject()
                println("group category_id=${getString(g, "category_id") ?? ""}")
                match (getArray(g, "data")) {
                    case Some(items) => printSearchItems(items)
                    case None => ()
                }
            }
        case None => ()
    }
    let total = getInt(root, "recordsTotal") ?? 0
    println("total: ${total}")
}

/**
 * 处理归档详情查询
 */
public func handleArchiveShow(client: LanluApiClient, opts: ParsedArguments, outputMode: String): Unit {
    if (opts.nonOptions.size < 2) {
        throw IllegalArgumentException("usage: archive-show <arcid>")
    }
    let arcid = opts.nonOptions[1]
    let params = HashMap<String, String>()
    if (opts.options.contains("include-pages")) {
        params["include_pages"] = "true"
    }
    let resp = client.get("/api/archives/${arcid}/metadata", params)
    let body = client.readBody(resp)
    printJsonOrText(body, outputMode, { b => printArchiveDetail(b) })
}

/**
 * 处理分类列表查询
 */
public func handleCategoryList(client: LanluApiClient, outputMode: String): Unit {
    let resp = client.get("/api/categories", HashMap<String, String>())
    let body = client.readBody(resp)

    if (outputMode != "text") {
        printJson(body, outputMode)
        return
    }

    let root = parseJson(body, "category list").asObject()
    match (getArray(root, "data")) {
        case Some(arr) =>
            println("id\tname\tcount")
            for (i in 0..arr.size()) {
                let o = arr[i].asObject()
                let id = getString(o, "id") ?? ""
                let name = getString(o, "name") ?? ""
                let count = getInt(o, "archive_count") ?? 0
                println("${id}\t${name}\t${count}")
            }
        case None => println(body)
    }
}

private func printSearchItems(data: JsonArray): Unit {
    for (i in 0..data.size()) {
        let o = data[i].asObject()
        let itemType = getString(o, "type") ?? "archive"
        if (itemType == "tankoubon") {
            let tid = getString(o, "tankoubon_id") ?? ""
            let title = getString(o, "title") ?? ""
            let count = getInt(o, "archive_count") ?? 0
            println("[tank] ${tid} ${title} (${count} archives)")
        } else {
            let arcid = getString(o, "arcid") ?? ""
            let title = getString(o, "title") ?? ""
            let pagecount = getInt(o, "pagecount") ?? 0
            let tags = getString(o, "tags") ?? ""
            println("${arcid} | ${title} | ${pagecount}p | ${tags}")
        }
    }
}

private func printArchiveDetail(body: String): Unit {
    let root = parseJson(body, "archive detail").asObject()
    println("arcid: ${getString(root, "arcid") ?? ""}")
    println("title: ${getString(root, "title") ?? ""}")
    println("filename: ${getString(root, "filename") ?? ""}")
    println("pagecount: ${getInt(root, "pagecount") ?? 0}")
    println("archivetype: ${getString(root, "archivetype") ?? ""}")
    println("tags: ${getString(root, "tags") ?? ""}")
    println("description: ${getString(root, "description") ?? ""}")
    match (getArray(root, "pages")) {
        case Some(pages) => println("pages: ${pages.size()}")
        case None => ()
    }
}

private func addIfPresent(opts: ParsedArguments, params: HashMap<String, String>, optName: String, paramName: String): Unit {
    let v = opts.options.get(optName) ?? ""
    if (v.size > 0) {
        params[paramName] = v
    }
}

private func addIfPresent(opts: ParsedArguments, params: HashMap<String, String>, name: String): Unit {
    addIfPresent(opts, params, name, name)
}

private func addFlagIfPresent(opts: ParsedArguments, params: HashMap<String, String>, optName: String, paramName: String): Unit {
    if (opts.options.contains(optName)) {
        params[paramName] = "true"
    }
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
