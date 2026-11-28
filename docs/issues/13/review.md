# Issue #13 审查记录

## 自查项

| 项目 | 结论 |
| --- | --- |
| 根因是否被消除 | 是。`create()` 的 INSERT 现为 `$16, $17, $18::jsonb, $19`，`has_schema` 不再被强转 jsonb |
| 是否只改相关文件 | 是。仅 `plugin_dao.cj` + 新增测试 + 本文档 |
| 占位符数量/顺序 | 19 列 ↔ 19 参数，SQL 反查每个 `$n` 与列位置一一对应（见下） |
| params 绑定类型 | `$17` = `vbool(has_schema)`；`$18` = `vjson(parameters)`，与列类型一致 |
| 错误处理 | `create()` 原有 try/catch 与日志保留，未改变失败语义 |
| 安全 | SQL 为静态常量，参数化绑定，无注入面 |
| 性能 | 无额外查询/解析，零热路径影响 |
| 兼容性 | 依赖 V030 已把 `parameters` 转为 JSONB；未迁移库需先迁移（见 requirements 风险） |
| 文档 | 需求/设计/测试/审查已落盘 |
| 脚手架 | 仓库缺少 `AGENTS.md`/`docs/worktree.md`/`scripts/worktree.sh`，已在变化说明中标注假设 |

## 静态映射验证（替代无法运行的编译测试）

用脚本解析 `INSERT_SQL`，按列位置校验每个 `$n` 与强转：

```text
columns: 19 values: 19
errors: none
```

规则：`has_schema`/`enabled`/`installed` 不得有 cast；`pre_hooks`/`after_hooks`/`parameters`
必须 `::jsonb`；其余列不得有 cast。全部满足。

## 未执行项

- `cjpm test` / `cjpm build`：环境无 Cangjie 工具链（`cjc`/`cjpm` 不在 PATH），无法运行。
  不伪造通过结论；需在有 SDK 的 CI 重跑。
- 未启动 PostgreSQL 做端到端上传验证；同一根因可由上述静态映射 + 回归测试覆盖。

## 结论

变更最小、影响面收敛，建议合并；合并后由 1 次 PR run 在具备工具链的环境中验证测试。