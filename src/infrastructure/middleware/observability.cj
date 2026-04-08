package lanlu.infrastructure.middleware

import ignite.*
import ignite.middleware.*
import ignite.governance.*
import brotli_middleware.*
import lanlu.shared.utils.*
import lanlu.shared.views.*
import std.time.{MonoTime, DateTime}

private let accessLogger = getLogger("http_access")
private let recoverLogger = getLogger("http_recover")
private let auditLogger = getLogger("http_audit")
private let uploadEntryLogger = getLogger("upload_entry")

public func installObservabilityMiddleware(app: App): Unit {
    app.use(requestIdMiddleware(config: RequestIdConfig()))
    app.use(recoverMiddleware(config: RecoverConfig(
        customHandler: { ctx, e =>
            let requestId = ctx.getLocal("request_id") ?? "-"
            recoverLogger.error(
                "Recovered unhandled HTTP exception",
                ("request_id", requestId),
                ("method", ctx.method),
                ("path", ctx.path),
                ("error", e.message)
            )
            ctx.status(500)
            ResponseView.errorJson(ctx, "Internal Server Error", 500)
        }
    )))
    app.use(uploadChunkDebugMiddleware())
    app.use(httpAccessLogMiddleware())
    app.use(brotliMiddleware(
        config: BrotliConfig(minBytes: 2048),
        shouldSkip: { path => shouldSkipCompression(path) }
    ))
}

public func audited(action: String, handler: Handler, riskLevel!: Int64 = 4): Handler {
    { ctx =>
        let start = MonoTime.now()
        try {
            handler(ctx)
            emitLanluAudit(ctx, action, riskLevel, (MonoTime.now() - start).toMilliseconds())
        } catch (e: Exception) {
            emitLanluAudit(ctx, action, 2, (MonoTime.now() - start).toMilliseconds(), statusOverride: 500, resultOverride: "deny")
            throw e
        }
    }
}

private func httpAccessLogMiddleware(): Handler {
    { ctx =>
        let start = MonoTime.now()
        ctx.next()

        let requestId = ctx.getLocal("request_id") ?? "-"
        let latencyMs = (MonoTime.now() - start).toMilliseconds()
        accessLogger.info(
            "HTTP request",
            ("request_id", requestId),
            ("method", ctx.method),
            ("path", ctx.path),
            ("status", "${ctx.responseStatus}"),
            ("latency_ms", "${latencyMs}"),
            ("ip", ctx.ip)
        )
    }
}

private func uploadChunkDebugMiddleware(): Handler {
    { ctx =>
        if (!isUploadChunkRoute(ctx)) {
            ctx.next()
            return
        }

        let start = MonoTime.now()
        let requestId = ctx.getLocal("request_id") ?? "-"
        let taskId = ctx.query("taskId") ?? ""
        let chunkIndex = ctx.query("chunkIndex") ?? ""
        let totalChunks = ctx.query("totalChunks") ?? ""
        let contentType = ctx.header("Content-Type") ?? ""
        let contentLength = ctx.header("Content-Length") ?? ""
        let transferEncoding = ctx.header("Transfer-Encoding") ?? ""
        let userAgent = ctx.header("User-Agent") ?? ""

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
            ("ip", ctx.ip)
        )

        ctx.next()

        let latencyMs = (MonoTime.now() - start).toMilliseconds()
        uploadEntryLogger.debug(
            "upload chunk request completed",
            ("request_id", requestId),
            ("method", ctx.method),
            ("path", ctx.path),
            ("task_id", taskId),
            ("chunk_index", chunkIndex),
            ("total_chunks", totalChunks),
            ("status", "${ctx.responseStatus}"),
            ("latency_ms", "${latencyMs}")
        )
    }
}

private func isUploadChunkRoute(ctx: Ctx): Bool {
    return ctx.method == "PUT" && ctx.path == "/api/assets/upload/chunk"
}

private func shouldSkipCompression(path: String): Bool {
    path.startsWith("/api/assets/") ||
    path.endsWith("/download") ||
    path.endsWith("/stream")
}

private func emitLanluAudit(
    ctx: Ctx,
    action: String,
    configuredRisk: Int64,
    latencyMs: Int64,
    statusOverride!: UInt16 = 0,
    resultOverride!: String = ""
): Unit {
    let statusCode = if (statusOverride > 0) { statusOverride } else { ctx.responseStatus }
    let event = AuditEvent()
    event.timestamp = DateTime.now().toString()
    event.requestId = ctx.getLocal("request_id") ?? "-"
    event.actor = ctx.getLocal("actor") ?? "anonymous"
    event.ip = ctx.ip
    event.route = ctx.path
    event.action = action
    event.statusCode = statusCode
    event.latencyMs = latencyMs
    event.result = if (resultOverride.size > 0) {
        resultOverride
    } else if (statusCode >= 400) {
        "deny"
    } else {
        "allow"
    }
    let statusRisk = riskByStatus(statusCode)
    event.riskLevel = if (statusRisk < configuredRisk) { statusRisk } else { configuredRisk }
    emitAudit(event, config: AuditConfig(
        output: { msg =>
            auditLogger.info(
                msg,
                ("request_id", event.requestId),
                ("actor", event.actor),
                ("action", event.action),
                ("status", "${event.statusCode}")
            )
        }
    ))
    ctx.setLocal("audit_event_id", event.eventId)
}
