package lanlu.contexts.system.interfaces.http

import ignite.*
import stdx.log.*
import std.collection.*
import std.convert.*
import lanlu.shared.config.*
import lanlu.shared.views.*
import lanlu.shared.utils.*
import stdx.encoding.json.stream.*
import csorm.{Value, vtext, vint, vfloat, vbool, vnull}

/**
 * 管理端数据库 EXPLAIN 观测口。
 *
 * POST /api/admin/db/explain
 * Body: {"sql": "SELECT ...", "params": [...], "analyze": false, "limit": 200}
 *
 * 安全约束：
 * - 仅允许 SELECT / WITH 开头的单条语句（拒绝分号、注释与危险函数）；
 * - 强制包裹 SELECT * FROM (...) _explain_sub LIMIT N，无论原 SQL 是否自带 LIMIT；
 * - analyze=true 时在事务内先 SET LOCAL statement_timeout，防止慢查询长期占用连接；
 * - 复用 AuthMiddleware.requireAdminMiddleware（路由侧挂载），并经 audited 审计。
 */
class DbExplainReq <: JsonDeserializable<DbExplainReq> {
    var sql: String = ""
    var analyze: Bool = false
    var limit: Int64 = 200
    var params: Array<Value> = Array<Value>()

    private static func readJsonScalar(r: JsonReader): Value {
        match (r.peek()) {
            case Some(BeginObject) =>
                let bytes = r.readValueBytes()
                return vtext(String.fromUtf8(bytes))
            case Some(BeginArray) =>
                let bytes = r.readValueBytes()
                return vtext(String.fromUtf8(bytes))
            case Some(JsonNull) =>
                return vnull()
            case Some(JsonNumber) =>
                let s = r.readValue<String>()
                try { return vint(Int64.parse(s)) } catch (_: Exception) {}
                try { return vfloat(Float64.parse(s)) } catch (_: Exception) { return vtext(s) }
            case Some(JsonBool) =>
                let s = r.readValue<String>().trimAscii()
                return vbool(s == "true" || s == "1")
            case Some(_) =>
                return vtext(r.readValue<String>())
            case None =>
                return vnull()
        }
    }

    public static func fromJson(r: JsonReader): DbExplainReq {
        let res = DbExplainReq()
        while (let Some(tok) <- r.peek()) {
            match (tok) {
                case BeginObject =>
                    r.startObject()
                    while (r.peek() != EndObject) {
                        let n = r.readName()
                        match (n) {
                            case "sql" => res.sql = r.readValue<String>()
                            case "analyze" =>
                                let s = r.readValue<String>().trimAscii()
                                res.analyze = s == "true" || s == "1"
                            case "limit" =>
                                let s = r.readValue<String>().trimAscii()
                                try { res.limit = Int64.parse(s) } catch (_: Exception) { res.limit = 200 }
                            case "params" =>
                                var collected = ArrayList<Value>()
                                match (r.peek()) {
                                    case Some(BeginArray) =>
                                        r.startArray()
                                        while (r.peek() != EndArray) {
                                            collected.add(readJsonScalar(r))
                                        }
                                        r.endArray()
                                    case Some(_) => r.skip()
                                    case None => ()
                                }
                                res.params = collected.toArray()
                            case _ => r.skip()
                        }
                    }
                    r.endObject()
                    break
                case _ => r.skip()
            }
        }
        return res
    }
}

public class DbExplainController {
    private static let forbiddenTokens: Array<String> = [
        "pg_sleep", "pg_read_file", "pg_ls_dir", "pg_read_binary_file",
        "dblink", "lo_import", "lo_export", "copy_from",
        "pg_terminate_backend", "pg_cancel_backend", "pg_logdir_ls"
    ]

    /// 校验用户 SQL：仅单条 SELECT/WITH；拒绝分号与危险函数。
    private static func validateUserSql(raw: String): Option<String> {
        var sql = raw.trimAscii()
        // 允许结尾一个分号
        if (sql.endsWith(";")) {
            sql = sql[0..sql.size - 1].trimAscii()
        }
        if (sql.size == 0) {
            return None
        }
        // 任何内部分号 → 多语句，拒绝
        if (sql.contains(";")) {
            return None
        }
        // 拒绝 SQL 注释（可能被用来隐藏语句边界语义）
        if (sql.contains("--") || sql.contains("/*")) {
            return None
        }
        let lower = sql.toAsciiLower()
        if (!(lower.startsWith("select") || lower.startsWith("with"))) {
            return None
        }
        for (token in forbiddenTokens) {
            if (lower.contains(token)) {
                return None
            }
        }
        return Some(sql)
    }

    /**
     * POST /api/admin/db/explain
     * 输出 EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) 的 JSON 计划。
     */
    public static func explain(ctx: Ctx): Unit {
        let logger = getLogger("db_explain_controller")
        try {
            let body = ctx.bodyString()
            if (body.trimAscii().size == 0) {
                ctx.status(400)
                ResponseView.errorJson(ctx, "Empty body", 400)
                return
            }
            let req = JsonCodec.decode<DbExplainReq>(body)

            match (validateUserSql(req.sql)) {
                case None =>
                    ctx.status(400)
                    ResponseView.errorJson(ctx, "Only a single SELECT/WITH statement is allowed", 400)
                    return
                case Some(userSql) =>
                    // 强制 LIMIT 包裹：EXPLAIN 的对象始终是受限子查询
                    var limit = req.limit
                    if (limit <= 0) { limit = 200 }
                    if (limit > 5000) { limit = 5000 }
                    let wrapped = "SELECT * FROM (" + userSql + ") AS _explain_sub LIMIT " + limit.toString()
                    let planSql = if (req.analyze) {
                        "EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) " + wrapped
                    } else {
                        "EXPLAIN (FORMAT JSON) " + wrapped
                    }

                    match (DatabaseConfig.getDatabase()) {
                        case None =>
                            ctx.status(503)
                            ResponseView.errorJson(ctx, "database unavailable", 503)
                            return
                        case Some(db) =>
                            let planCell = Array<String>(1, { _ => "" })
                            db.transaction<String>({ d =>
                                // 事务级超时，防止 ANALYZE 慢查询长期占用连接（事务结束自动还原）
                                let _ = d.execRawSql("SET LOCAL statement_timeout = '5000ms'")
                                let rows = d.raw<String>(planSql, req.params, { r => r.getOrNullText(0) ?? "" })
                                if (rows.size > 0) {
                                    planCell[0] = rows[0]
                                }
                                return planCell[0]
                            })
                            if (planCell[0].size == 0) {
                                ctx.status(500)
                                ResponseView.errorJson(ctx, "EXPLAIN returned no plan", 500)
                                return
                            }
                            logger.info("admin db explain", ("analyze", req.analyze.toString()), ("sql", userSql))
                            // planCell[0] 是 FORMAT JSON 的原始 JSON 文本，直接作为响应体透传
                            ResponseView.successJson(ctx, planCell[0], "EXPLAIN ok")
                    }
            }
        } catch (e: Exception) {
            logger.error("db explain failed", ("error", e.message))
            ctx.status(400)
            ResponseView.errorJson(ctx, "EXPLAIN failed: " + e.message, 400)
        }
    }
}
