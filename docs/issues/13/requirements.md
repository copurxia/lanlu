# Issue #13 需求分析

## 问题

网页端上传 WASM 插件时，`plugin_asset_consume` 任务在进度 60% 失败，报
`Failed to create plugin in database`。PostgreSQL 日志显示：

```text
ERROR:  column "has_schema" is of type boolean but expression is of type jsonb at character 315
STATEMENT:  INSERT INTO plugins (...) VALUES (..., $17::jsonb, $18, $19)
```

`plugins` 表列顺序中第 17 列是 `has_schema`（BOOLEAN），第 18 列是 `parameters`
（V030 迁移后为 JSONB）。`PluginDao.create()` 的 INSERT 把 `::jsonb` 错放在 `$17`
上，导致参数类型与目标列不匹配，整条 INSERT 失败。

## 根因

`apps/server/src/contexts/plugin/infrastructure/persistence/plugin_dao.cj` 的
`create()` 内联 SQL 中占位符类型强转错位：

- 现状：`... $16, $17::jsonb, $18, $19` → `$17::jsonb` 落在 `has_schema`（boolean）
- 期望：`... $16, $17, $18::jsonb, $19` → `$18` 是 `parameters`（jsonb），`$17` 无强转

`update()` 的 SQL 映射正确，可作为对照。

## 验收标准

1. `PluginDao.create()` 生成的 INSERT 语句中：
   - `has_schema` 对应 `$17`，不带 `::jsonb`；
   - `parameters` 对应 `$18::jsonb`；
   - 其余列（`pre_hooks`/`after_hooks` 为 `$11::jsonb`/`$12::jsonb`）保持既有正确映射。
2. 新增回归测试，禁止再次出现 `$17::jsonb`，并要求 `$18::jsonb` 存在。
3. 不改变表结构、不修改无关文件。
4. `scripts/worktree.sh check`（或等价 `cjpm test`）在可用环境下通过。

## 边界与风险

- 只影响 `PluginDao.create()`；`update()`/读取路径列映射正确，不动。
- 历史数据库若未跑 V030，`parameters` 仍是 TEXT；`$18::jsonb` 对 TEXT 列会失败。
  但迁移在启动时运行，且 V030 已是既定版本，本次按“已迁移”处理。若需兼容
  未迁移库，应回退到 `vtext` 而非改回错位强转。
- `has_schema` 由 `vbool` 绑定，无需文本转换。
- 无数据丢失风险：修复前该 INSERT 必然失败，不产生写入。

## 假设

- 运行环境应已按顺序执行到 V030（`parameters` 为 JSONB）。
- issue 描述中的列/占位符编号与仓库当前代码一致（已核对）。
- 仓库当前没有 `AGENTS.md`、`docs/worktree.md`、`scripts/worktree.sh`，按任务硬性规则
  改用 `git worktree` 在 `.agents/worktrees/issue-13`（gitignore 目录）创建隔离 lane，
  主 worktree 保持只读。