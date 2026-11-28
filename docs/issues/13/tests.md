# Issue #13 测试说明

## 回归测试

`apps/server/src/contexts/plugin/infrastructure/persistence/plugin_dao_test.cj`

- `pluginInsertCastMappingTest`
  - 断言 `PluginDao.INSERT_SQL` 不含 `$17::jsonb`（防止强转再次落到 boolean 列）；
  - 断言含 `$18::jsonb`（parameters 写入 jsonb）；
  - 断言 `$17, $18::jsonb` 相邻序列与 `has_schema, parameters, update_url` 列序一致。

测试为纯字符串/常量断言，不需要数据库连接。

## 先失败后修复

在修复前，`INSERT_SQL` 等价文本为 `$17::jsonb, $18`，`pluginInsertCastMappingTest`
的 `!contains("$17::jsonb")` 与 `contains("$18::jsonb")` 均会失败；修复后通过。

## 运行命令

```bash
cd apps/server
cjpm test --parallel nCores --timeout-each 600s \
  --report-path ../../target/test-results/lanlu.xml --report-format xml
```

或仓库封装：

```bash
python3 -m tools.xtask test --package lanlu
```

## 本次执行环境

- `python3 -m tools.xtask doctor --json`：`cjc`/`cjpm`/`cargo`/`pnpm` 均未安装（`path: null`）。
- 因此本环境**无法实际编译/运行** Cangjie 测试，不能声称测试通过。
- 已执行的降级验证见 `docs/issues/13/review.md`（静态映射检查与 diff 自查）。
- 在具备 Cangjie 1.2.0 的 CI/开发机上需重跑上述命令确认。

## 本次实际执行记录

| 命令 | 结果 |
| --- | --- |
| `python3 -m tools.xtask doctor --json` | `status=warning`，`cjc`/`cjpm`/`cargo`/`pnpm` 均 `path:null` |
| `python3 -m tools.xtask test --changed --json` | `status=config_error`，exit 2，`command not found: cjpm` |
| `python3 -m unittest discover -s tools/xtask/tests -t .` | 30 tests OK，exit 0 |
| 静态映射检查脚本（解析 INSERT_SQL 19 列/19 值） | `errors: none`，exit 0 |