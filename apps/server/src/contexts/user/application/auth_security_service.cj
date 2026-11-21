package lanlu.contexts.user.application

import std.io.{ByteBuffer, readToEnd}
import std.time.DateTime
import std.convert.*
import stdx.encoding.json.stream.*
import lanlu.infrastructure.kv.*
import lanlu.shared.utils.*

private class RateLimitCounter {
    public var failures: Int64 = 0
    public var createdAtSeconds: Int64 = 0

    public init() {}
}

private class StepUpGrant {
    public var userId: Int64 = 0
    public var tokenId: Int64 = 0
    public var method: String = ""
    public var createdAtSeconds: Int64 = 0

    public init() {}
}

private class RateLimitCounterCodec {
    public static func encode(counter: RateLimitCounter): String {
        let out = ByteBuffer()
        let w = JsonWriter(out)
        w.startObject()
        w.writeName("failures").writeValue(counter.failures)
        w.writeName("createdAtSeconds").writeValue(counter.createdAtSeconds)
        w.endObject()
        w.flush()
        return String.fromUtf8(readToEnd(out))
    }

    public static func decode(payload: String): Option<RateLimitCounter> {
        let trimmed = payload.trimAscii()
        if (trimmed.size == 0) {
            return None
        }

        try {
            var buf = ByteBuffer()
            unsafe { buf.write(trimmed.rawData()) }
            let r = JsonReader(buf)
            if (r.peek() != Some(BeginObject)) {
                return None
            }

            let out = RateLimitCounter()
            r.startObject()
            while (r.peek() != EndObject) {
                let key = r.readName()
                match (key) {
                    case "failures" => out.failures = r.readValue<Int64>()
                    case "createdAtSeconds" => out.createdAtSeconds = r.readValue<Int64>()
                    case _ => r.skip()
                }
            }
            r.endObject()
            return Some(out)
        } catch (_: Exception) {
            return None
        }
    }
}

private class StepUpGrantCodec {
    public static func encode(grant: StepUpGrant): String {
        let out = ByteBuffer()
        let w = JsonWriter(out)
        w.startObject()
        w.writeName("userId").writeValue(grant.userId)
        w.writeName("tokenId").writeValue(grant.tokenId)
        w.writeName("method").writeValue(grant.method)
        w.writeName("createdAtSeconds").writeValue(grant.createdAtSeconds)
        w.endObject()
        w.flush()
        return String.fromUtf8(readToEnd(out))
    }

    public static func decode(payload: String): Option<StepUpGrant> {
        let trimmed = payload.trimAscii()
        if (trimmed.size == 0) {
            return None
        }

        try {
            var buf = ByteBuffer()
            unsafe { buf.write(trimmed.rawData()) }
            let r = JsonReader(buf)
            if (r.peek() != Some(BeginObject)) {
                return None
            }

            let out = StepUpGrant()
            r.startObject()
            while (r.peek() != EndObject) {
                let key = r.readName()
                match (key) {
                    case "userId" => out.userId = r.readValue<Int64>()
                    case "tokenId" => out.tokenId = r.readValue<Int64>()
                    case "method" => out.method = r.readValue<String>()
                    case "createdAtSeconds" => out.createdAtSeconds = r.readValue<Int64>()
                    case _ => r.skip()
                }
            }
            r.endObject()
            return Some(out)
        } catch (_: Exception) {
            return None
        }
    }
}

public class AuthRateLimitDecision {
    public let allowed: Bool
    public let retryAfterSeconds: Int64

    public init(allowed: Bool, retryAfterSeconds!: Int64 = 0) {
        this.allowed = allowed
        this.retryAfterSeconds = retryAfterSeconds
    }
}

public class AuthSecurityService {
    private static let rateLimitNamespace = "auth_rate_limit"
    private static let stepUpNamespace = "auth_step_up"
    private static let maxFailures: Int64 = 5
    private static let failureWindowSeconds: Int64 = 300
    private static let blockSeconds: Int64 = 300
    private static let stepUpTtlSeconds: Int64 = 600

    public static func checkRateLimit(scope: String, ip: String, identifier: String): AuthRateLimitDecision {
        let key = rateLimitKey(scope, ip, identifier)
        if (key.size == 0) {
            return AuthRateLimitDecision(true)
        }

        match (PersistentCacheService.get(rateLimitNamespace, "block:${key}")) {
            case Some(untilValue) =>
                try {
                    let untilSeconds = Int64.parse(untilValue)
                    let retryAfter = untilSeconds - nowSeconds()
                    return AuthRateLimitDecision(false, retryAfterSeconds: if (retryAfter > 0) { retryAfter } else { 1 })
                } catch (_: Exception) {
                    return AuthRateLimitDecision(false, retryAfterSeconds: blockSeconds)
                }
            case None => return AuthRateLimitDecision(true)
        }
    }

    public static func recordFailure(scope: String, ip: String, identifier: String): Unit {
        let key = rateLimitKey(scope, ip, identifier)
        if (key.size == 0) {
            return
        }

        let counterKey = "count:${key}"
        let blockKey = "block:${key}"
        var counter = RateLimitCounter()
        counter.createdAtSeconds = nowSeconds()

        match (PersistentCacheService.get(rateLimitNamespace, counterKey)) {
            case Some(raw) =>
                match (RateLimitCounterCodec.decode(raw)) {
                    case Some(existing) =>
                        counter.failures = existing.failures
                        counter.createdAtSeconds = existing.createdAtSeconds
                    case None => ()
                }
            case None => ()
        }

        counter.failures += 1
        let _ = PersistentCacheService.set(rateLimitNamespace, counterKey, RateLimitCounterCodec.encode(counter), failureWindowSeconds)
        if (counter.failures >= maxFailures) {
            let blockedUntil = nowSeconds() + blockSeconds
            let _ = PersistentCacheService.set(rateLimitNamespace, blockKey, blockedUntil.toString(), blockSeconds)
        }
    }

    public static func clearFailures(scope: String, ip: String, identifier: String): Unit {
        let key = rateLimitKey(scope, ip, identifier)
        if (key.size == 0) {
            return
        }

        let _ = PersistentCacheService.delete(rateLimitNamespace, "count:${key}")
        let _ = PersistentCacheService.delete(rateLimitNamespace, "block:${key}")
    }

    public static func grantStepUp(userId: Int64, tokenId: Int64, method: String): Bool {
        if (userId <= 0 || tokenId <= 0) {
            return false
        }

        let grant = StepUpGrant()
        grant.userId = userId
        grant.tokenId = tokenId
        grant.method = method.trimAscii()
        grant.createdAtSeconds = nowSeconds()
        return PersistentCacheService.set(stepUpNamespace, stepUpKey(userId, tokenId), StepUpGrantCodec.encode(grant), stepUpTtlSeconds)
    }

    public static func hasRecentStepUp(userId: Int64, tokenId: Int64): Bool {
        if (userId <= 0 || tokenId <= 0) {
            return false
        }

        match (PersistentCacheService.get(stepUpNamespace, stepUpKey(userId, tokenId))) {
            case Some(raw) =>
                match (StepUpGrantCodec.decode(raw)) {
                    case Some(grant) => return grant.userId == userId && grant.tokenId == tokenId
                    case None => return false
                }
            case None => return false
        }
    }

    public static func clearStepUp(userId: Int64, tokenId: Int64): Unit {
        if (userId <= 0 || tokenId <= 0) {
            return
        }
        let _ = PersistentCacheService.delete(stepUpNamespace, stepUpKey(userId, tokenId))
    }

    private static func rateLimitKey(scope: String, ip: String, identifier: String): String {
        let normalizedScope = scope.trimAscii()
        let normalizedIp = ip.trimAscii()
        let normalizedIdentifier = identifier.trimAscii()
        if (normalizedScope.size == 0 || normalizedIp.size == 0 || normalizedIdentifier.size == 0) {
            return ""
        }
        return AuthUtils.sha256Hex("${normalizedScope}:${normalizedIp}:${normalizedIdentifier}")
    }

    private static func stepUpKey(userId: Int64, tokenId: Int64): String {
        return "${userId}:${tokenId}"
    }

    private static func nowSeconds(): Int64 {
        return DateTime.now().toUnixTimeStamp().toSeconds()
    }
}
