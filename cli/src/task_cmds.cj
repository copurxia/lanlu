package cli

import std.argopt.ParsedArguments
import std.collection.HashMap
import std.convert.*
import std.fs.*
import std.io.readToEnd
import stdx.encoding.json.*

/**
 * 处理 URL 下载
 */
public func handleDownloadUrl(client: LanluApiClient, opts: ParsedArguments, outputMode: String): Unit {
    if (opts.nonOptions.size < 2) {
        throw IllegalArgumentException("usage: download-url <url>")
    }
    let url = opts.nonOptions[1]
    let body = JsonObject()
    body.put("url", JsonString(url))

    let resp = client.post("/api/download_url", body.toString())
    let respBody = client.readBody(resp)

    if (outputMode != "text") {
        printJson(respBody, outputMode)
        return
    }

    let root = parseJson(respBody, "download url").asObject()
    let job = getInt(root, "job") ?? 0
    if (job <= 0) {
        println(respBody)
        return
    }
    println("created download task: ${job}")

    let (wait, interval, timeout) = resolveWait(opts)
    if (wait) {
        let result = waitForTask(client, job, interval, timeout, outputMode)
        println(result.toString())
    }
}

/**
 * 处理归档分片上传
 */
public func handleUpload(client: LanluApiClient, opts: ParsedArguments, outputMode: String): Unit {
    if (opts.nonOptions.size < 2) {
        throw IllegalArgumentException("usage: upload <file> --category-id <id>")
    }
    let filePath = opts.nonOptions[1]
    let categoryId = opts.options.get("category-id") ?? ""
    if (categoryId.size == 0) {
        throw IllegalArgumentException("--category-id is required")
    }

    let chunkSize = try { Int64.parse(opts.options.get("chunk-size") ?? "8388608") } catch (_: Exception) { 8388608 }
    if (chunkSize <= 0) {
        throw IllegalArgumentException("--chunk-size must be positive")
    }
    let targetType = opts.options.get("target-type") ?? "archive"
    let overwrite = opts.options.contains("overwrite")

    let file = File(filePath, Read)
    let allBytes = readToEnd(file)
    let fileSize = allBytes.size
    let filename = basename(filePath)

    var totalChunks = fileSize / chunkSize
    if (fileSize % chunkSize != 0) {
        totalChunks += 1
    }

    let initBody = JsonObject()
    initBody.put("filename", JsonString(filename))
    initBody.put("filesize", JsonInt(fileSize))
    initBody.put("chunk_size", JsonInt(chunkSize))
    initBody.put("total_chunks", JsonInt(totalChunks))
    initBody.put("category_id", JsonString(categoryId))
    initBody.put("target_type", JsonString(targetType))
    initBody.put("overwrite", JsonBool(overwrite))

    let initResp = client.post("/api/assets/upload/init", initBody.toString())
    let initBodyStr = client.readBody(initResp)
    let initRoot = parseJson(initBodyStr, "upload init").asObject()
    let taskIdStr = requireString(initRoot, "taskId")
    let taskId = Int64.parse(taskIdStr)

    if (outputMode == "text") {
        println("upload session: ${taskId}, total chunks: ${totalChunks}")
    }

    var offset = 0
    for (i in 0..totalChunks) {
        let end = min(offset + chunkSize, fileSize)
        let chunk = allBytes.slice(offset, end)
        let query = HashMap<String, String>()
        query["taskId"] = taskIdStr
        query["chunkIndex"] = "${i}"
        query["totalChunks"] = "${totalChunks}"

        let chunkResp = client.putBytes("/api/assets/upload/chunk", query, chunk)
        let chunkBody = client.readBody(chunkResp)
        if (outputMode == "text") {
            println("chunk ${i + 1}/${totalChunks} uploaded")
        }
        if (outputMode == "json" || outputMode == "pretty-json") {
            println(chunkBody)
        }
        offset = end
    }

    let (wait, interval, timeout) = resolveWait(opts)
    if (wait) {
        let result = waitForTask(client, taskId, interval, timeout, outputMode)
        println(result.toString())
    }
}

/**
 * 处理元数据插件运行
 */
public func handleMetadataRun(client: LanluApiClient, opts: ParsedArguments, outputMode: String): Unit {
    if (opts.nonOptions.size < 3) {
        throw IllegalArgumentException("usage: metadata-run <namespace> <target-id>")
    }
    let namespace = opts.nonOptions[1]
    let targetId = opts.nonOptions[2]
    let targetType = opts.options.get("target-type") ?? "archive"
    let param = opts.options.get("param") ?? ""
    let writeBack = opts.options.contains("write-back")

    let body = JsonObject()
    body.put("target_type", JsonString(targetType))
    body.put("target_id", JsonString(targetId))
    body.put("namespace", JsonString(namespace))
    if (param.size > 0) {
        body.put("param", JsonString(param))
    }
    body.put("write_back", JsonString(if (writeBack) { "1" } else { "0" }))

    let resp = client.post("/api/metadata_plugin", body.toString())
    let respBody = client.readBody(resp)

    if (outputMode != "text") {
        printJson(respBody, outputMode)
        return
    }

    let root = parseJson(respBody, "metadata run").asObject()
    let job = getInt(root, "job") ?? 0
    if (job <= 0) {
        println(respBody)
        return
    }
    println("created metadata task: ${job}")

    let (wait, interval, timeout) = resolveWait(opts)
    if (wait) {
        let result = waitForTask(client, job, interval, timeout, outputMode)
        println(result.toString())
    }
}

/**
 * 处理任务详情查询
 */
public func handleTask(client: LanluApiClient, opts: ParsedArguments, outputMode: String): Unit {
    if (opts.nonOptions.size < 2) {
        throw IllegalArgumentException("usage: task <id>")
    }
    let taskId = try { Int64.parse(opts.nonOptions[1]) } catch (e: Exception) {
        throw IllegalArgumentException("invalid task id: ${e.message}")
    }
    let resp = client.get("/api/admin/taskpool/${taskId}", HashMap<String, String>())
    let body = client.readBody(resp)
    printJson(body, outputMode)
}

private func basename(path: String): String {
    let parts = path.split("/")
    if (parts.size == 0) {
        return path
    }
    return parts[parts.size - 1]
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
