# Issue #13 方案设计

## 最小变更方案

1. 将 `PluginDao.create()` 的内联 INSERT 提取为 `PluginDao.INSERT_SQL`，修正占位符强转：
   - `$17::jsonb` → `$17`
   - `$18` → `$18::jsonb`
2. `create()` 使用该常量，避免 SQL 与 params 再次漂移。
3. 新增 `plugin_dao_test.cj`（纯单元测试，无需数据库）锁定映射关系。

## 涉及文件

| 文件 | 变更 |
| --- | --- |
| `apps/server/src/contexts/plugin/infrastructure/persistence/plugin_dao.cj` | 提取并修正 INSERT SQL |
| `apps/server/src/contexts/plugin/infrastructure/persistence/plugin_dao_test.cj` | 新增回归测试 |
| `docs/issues/13/*.md` | 流程文档 |

## 替代方案

- **方案 B：去掉所有 `::jsonb` 强转，依赖驱动推断。** 驱动文本协议下 JSON 参数
  无显式类型，PG 可能把 `$n` 推断为 text 而无法写入 jsonb 列；现有代码统一用
  `::jsonb`，保持一致更稳妥。
- **方案 C：改为 `CAST($18 AS jsonb)`。** 语义等价，但改动面更大且无收益。
- **方案 D：调整表列顺序。** 会引入迁移风险和兼容问题，否决。

## 回滚方式

单行 SQL 修复 + 新增测试文件，`git revert <commit>` 即可；无 schema/数据变更。

## 兼容性

- `INSERT_SQL` 新增为 `public static let`，仅为测试与其他调用方可复用；无行为变化。
- 不改接口、不改 DTO、不改迁移。