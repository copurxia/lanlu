package lanlu.contexts.plugin.infrastructure.persistence

/**
 * plugins 插入 SQL 占位符/类型强转回归测试（无需 DB）。
 *
 * 背景：V030 将 plugins.parameters 转为 JSONB，但 has_schema 仍是 BOOLEAN。
 * 曾因 INSERT 写成 `$17::jsonb, $18`，把 jsonb 强转落到 has_schema 列，
 * 导致 WASM 插件入库报 "column has_schema is of type boolean but expression is of type jsonb"。
 *
 * 这里锁死两件事：
 * 1. has_schema（$17）不得带 ::jsonb；
 * 2. parameters（$18）必须带 ::jsonb。
 */
@Test
func pluginInsertCastMappingTest() {
    let sql = PluginDao.INSERT_SQL
    @Assert(!sql.contains("$17::jsonb"))
    @Assert(sql.contains("$18::jsonb"))
    @Expect(sql.contains("$17, $18::jsonb"), true)
    @Expect(sql.contains("has_schema, parameters, update_url"), true)
}