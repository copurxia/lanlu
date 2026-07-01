package lanlu.infrastructure.middleware

import ace_web.*
import ace_observability.*
import brotli_middleware.*
import lanlu.shared.http_ext.*
import lanlu.shared.utils.*
import lanlu.shared.views.*
import std.time.MonoTime

private let accessLogger = getLogger("http_access")
private let recoverLogger = getLogger("http_recover")
private let auditLogger = getLogger("http_audit")
private let uploadEntryLogger = getLogger("upload_entry")

public func installObservabilityMiddleware(app: App): Unit {
    app.use(requestId())
    app.use({ ctx: Context, next: Next =>
        try {
            next()
        } catch (e: Exception) {
            let requestId = getLocalStr(ctx, "requestId") ?? "-"
            recoverLogger.error(
                "Recovered unhandled HTTP exception",
                ("request_id", requestId),
                ("method", ctx.method),
                ("path", ctx.path),
                ("error", e.message)
            )
            ctx.status = 500
            ResponseView.errorJson(ctx, "Internal Server Error", 500)
        }
    })
    app.use(uploadChunkDebugMiddleware())
    app.use(httpAccessLogMiddleware())
    app.use(brotliMiddleware(
        config: BrotliConfig(minBytes: 2048),
        shouldSkip: { path => shouldSkipCompression(path) }
    ))
}

/** 审计包装：记录操作日志（简化版，无 AuditEvent 结构）。保留 audited() 签名以免 83 处调用改动。 */
public func audited(action: String, handler: Middleware, riskLevel!: Int64 = 4): Middleware {
    { ctx: Context, next: Next =>
        let start = MonoTime.now()
        try {
            handler(ctx, next)
            emitLanluAudit(ctx, action, (MonoTime.now() - start).toMilliseconds())
        } catch (e: Exception) {
            emitLanluAudit(ctx, action, (MonoTime.now() - start).toMilliseconds(), statusOverride: 500, resultOverride: "deny")
            throw e
        }
    }
}

private func httpAccessLogMiddleware(): Middleware {
    { ctx: Context, next: Next =>
        let start = MonoTime.now()
        next()

        let requestId = getLocalStr(ctx, "requestId") ?? "-"
        let latencyMs = (MonoTime.now() - start).toMilliseconds()
        accessLogger.info(
            "HTTP request",
            ("request_id", requestId),
            ("method", ctx.method),
            ("path", ctx.path),
            ("status", "${ctx.status}"),
            ("latency_ms", "${latencyMs}"),
            ("ip", "")
        )
    }
}

private func uploadChunkDebugMiddleware(): Middleware {
    { ctx: Context, next: Next =>
        if (!isUploadChunkRoute(ctx)) {
            next()
            return
        }

        let start = MonoTime.now()
        let requestId = getLocalStr(ctx, "requestId") ?? "-"
        let taskId = ctx.queryParam("taskId") ?? ""
        let chunkIndex = ctx.queryParam("chunkIndex") ?? ""
        let totalChunks = ctx.queryParam("totalChunks") ?? ""
        let contentType = ctx.header("content-type") ?? ""
        let contentLength = ctx.header("content-length") ?? ""
        let transferEncoding = ctx.header("transfer-encoding") ?? ""
        let userAgent = ctx.header("user-agent") ?? ""

        uploadEntryLogger.debug(
            "upload chunk request received",
            ("request_id", requestId),
            ("method", ctx.method),
            ("path", ctx.path),
            ("task_id", taskId),
            ("chunk_index", chunkIndex),
            ("total_chunks", totalChunks),
            ("content_type", contentType),
            ("content_length", contentLength),
            ("transfer_encoding", transferEncoding),
            ("user_agent", userAgent),
            ("ip", "")
        )

        next()

        let latencyMs = (MonoTime.now() - start).toMilliseconds()
        uploadEntryLogger.debug(
            "upload chunk request completed",
            ("request_id", requestId),
            ("method", ctx.method),
            ("path", ctx.path),
            ("task_id", taskId),
            ("chunk_index", chunkIndex),
            ("total_chunks", totalChunks),
            ("status", "${ctx.status}"),
            ("latency_ms", "${latencyMs}")
        )
    }
}

private func isUploadChunkRoute(ctx: Context): Bool {
    return ctx.method == "PUT" && ctx.path == "/api/assets/upload/chunk"
}

private func shouldSkipCompression(path: String): Bool {
    path.startsWith("/api/assets/") ||
    path.startsWith("/api/archives/") && path.endsWith("/page") ||
    path.endsWith("/download") ||
    path.endsWith("/stream")
}

private func emitLanluAudit(
    ctx: Context,
    action: String,
    latencyMs: Int64,
    statusOverride!: UInt16 = 0,
    resultOverride!: String = ""
): Unit {
    let statusCode = if (statusOverride > 0) { statusOverride } else { ctx.status }
    let requestId = getLocalStr(ctx, "requestId") ?? "-"
    let actor = getLocalStr(ctx, "actor") ?? "anonymous"
    let result = if (resultOverride.size > 0) {
        resultOverride
    } else if (statusCode >= 400) {
        "deny"
    } else {
        "allow"
    }
    let authFailureReason = getLocalStr(ctx, "auth_failure_reason") ?? ""
    let rateLimitScope = getLocalStr(ctx, "auth_rate_limit_scope") ?? ""
    auditLogger.info(
        "audit action=${action} result=${result} status=${statusCode} latency=${latencyMs}ms route=${ctx.path} actor=${actor}",
        ("request_id", requestId),
        ("actor", actor),
        ("action", action),
        ("status", "${statusCode}"),
        ("auth_failure_reason", authFailureReason),
        ("auth_rate_limit_scope", rateLimitScope)
    )
}