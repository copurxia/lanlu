package lanlu.infrastructure.middleware

import ignite.*
import ignite.middleware.*
import ignite.governance.*
import lanlu.shared.utils.*
import lanlu.shared.views.*
import std.time.{MonoTime, DateTime}

private let accessLogger = getLogger("http_access")
private let recoverLogger = getLogger("http_recover")
private let auditLogger = getLogger("http_audit")

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
    app.use(httpAccessLogMiddleware())
    app.use(lanluCompressMiddleware())
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

private func lanluCompressMiddleware(): Handler {
    let inner = compressMiddleware(config: CompressConfig(minBytes: 2048))
    { ctx =>
        if (shouldSkipCompression(ctx.path)) {
            ctx.next()
            return
        }
        inner(ctx)
    }
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
