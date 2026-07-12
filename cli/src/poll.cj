package cli

import stdx.encoding.json.*
import std.collection.HashMap
import std.core.sleep

/**
 * 轮询任务直到完成或超时
 */
public func waitForTask(
    client: LanluApiClient,
    taskId: Int64,
    intervalMs: Int64,
    timeoutMs: Int64,
    outputMode: String
): JsonObject {
    var maxIter = timeoutMs / intervalMs
    if (maxIter <= 0) {
        maxIter = 1
    }

    for (_ in 0..maxIter) {
        let resp = client.get("/api/admin/taskpool/${taskId}", HashMap<String, String>())
        let body = client.readBody(resp)
        let root = parseJson(body, "task detail").asObject()

        let status = getString(root, "status") ?? ""
        let progress = getInt(root, "progress") ?? 0
        let message = getString(root, "message") ?? ""

        if (outputMode == "text") {
            println("[task ${taskId}] status=${status} progress=${progress}% ${message}")
        }

        if (status == "completed" || status == "failed" || status == "stopped") {
            return root
        }

        sleep(Duration.millisecond * intervalMs)
    }

    throw TimeoutException("task ${taskId} did not finish within ${timeoutMs}ms")
}
