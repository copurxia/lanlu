package lanlu.infrastructure.migrations.versions

import csorm.*
import lanlu.infrastructure.migrations.*
import lanlu.shared.utils.*

/**
 * V030: JSONB 列规范化 —— 把以 TEXT 存 JSON 的列改为原生 JSONB。
 *
 * 转换列：
 * - plugins.pre_hooks / after_hooks / parameters（历史默认 '[]'）
 * - categories.plugins（历史默认 '[]'）
 * - tasks.parameters（任务参数 JSON）
 *
 * 明确不转换 tasks.result：其内容不保证是合法 JSON（runner 把最终 JSON 结果
 * 写 TaskIO，DB result 字段可能是任意文本），保持 TEXT 以免写路径损坏。
 *
 * 安全转换规则（USING CASE）：
 * - 空串/空白 → 默认值（'[]'::jsonb 或 NULL::jsonb），历史 DEFAULT '' 产生的空串不报错；
 * - 以 [ 或 { 开头 → 直接 ::jsonb 解析；
 * - 其余（历史脏数据）→ to_jsonb(btrim(col)) 包成 JSON 字符串，迁移不失败。
 * 转换后列默认值改为 '[]'::jsonb（tasks.parameters 无默认保持 NULL）。
 *
 * 读侧注意：libpq 文本协议下 jsonb 列以其文本形式返回，DAO 的 getOrNullText
 * 读法不变；写侧统一改绑 vjson（或 SQL 加 ::jsonb cast）。
 */
public class V030_JsonbColumns <: Migration {
    private let logger = getLogger("migration_v030")

    public func version(): String {
        return "V030"
    }

    public func description(): String {
        return "Normalize JSON-in-TEXT columns to native JSONB"
    }

    public func up(db: Database): Bool {
        if (!convertColumn(db, "plugins", "pre_hooks", "'[]'::jsonb")) { return false }
        if (!convertColumn(db, "plugins", "after_hooks", "'[]'::jsonb")) { return false }
        if (!convertColumn(db, "plugins", "parameters", "'[]'::jsonb")) { return false }
        if (!convertColumn(db, "categories", "plugins", "'[]'::jsonb")) { return false }
        if (!convertColumn(db, "tasks", "parameters", "NULL::jsonb")) { return false }
        return true
    }

    /** 列不存在跳过；已是 jsonb 跳过；否则安全转换类型并更新默认值。 */
    private func convertColumn(db: Database, table: String, column: String, emptyDefault: String): Bool {
        if (!MigrationHelpers.columnExists(db, table, column)) {
            logger.debug("${table}.${column} missing; skipping")
            return true
        }

        let typeSql = """
            SELECT data_type FROM information_schema.columns
            WHERE table_schema = current_schema()
              AND table_name = ?
              AND column_name = ?
        """
        let dataType = db.rawOne<String>(typeSql, [vtext(table), vtext(column)], { r => r.getOrNullText(0) ?? "" })
        if (dataType == Some("jsonb") || dataType == Some("json")) {
            logger.debug("${table}.${column} already jsonb/json; skipping")
            return true
        }

        // TEXT 列若带字符串默认值（如 '[]'），TYPE jsonb 前必须先 DROP DEFAULT，
        // 否则 PG 报 "default ... cannot be cast automatically to type jsonb"（本地 PG17 实测）。
        if (!MigrationHelpers.execUpdate(db, "ALTER TABLE ${table} ALTER COLUMN ${column} DROP DEFAULT")) {
            logger.error("failed to drop default for ${table}.${column}")
            return false
        }

        let alterSql = """
            ALTER TABLE ${table}
                ALTER COLUMN ${column} TYPE jsonb
                USING CASE
                    WHEN COALESCE(${column}, '') = '' THEN ${emptyDefault}
                    WHEN btrim(${column}) LIKE '[%' OR btrim(${column}) LIKE '{%' THEN btrim(${column})::jsonb
                    ELSE to_jsonb(btrim(${column}))
                END
        """
        if (!MigrationHelpers.execUpdate(db, alterSql)) {
            logger.error("failed to convert ${table}.${column} to jsonb")
            return false
        }

        // 非 NULL 默认值时同步更新列默认（tasks.parameters 保持 NULL）
        if (emptyDefault != "NULL::jsonb") {
            let defaultSql = "ALTER TABLE ${table} ALTER COLUMN ${column} SET DEFAULT ${emptyDefault}"
            if (!MigrationHelpers.execUpdate(db, defaultSql)) {
                logger.error("failed to set default for ${table}.${column}")
                return false
            }
        }

        logger.info("${table}.${column} converted to jsonb")
        return true
    }
}
