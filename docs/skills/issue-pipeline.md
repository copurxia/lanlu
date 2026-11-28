# Issue 自动化流水线（skill）

本文件记录本仓库 issue → PR 的标准自动化流水线。触发条件、阶段、命令、验收标准与失败处理均以仓库当前事实为准（2026-11-28）。

## 触发条件

- 代码托管平台（Gitea/CNB/GitHub）产生新 issue 的 opened 事件，且由自动化工程代理处理。
- 手动触发：对某 issue 编号执行同一流程。

## 阶段

| # | 阶段 | 产物 | 关键动作 |
| --- | --- | --- | --- |
| 1 | 项目初始化 | 基线记录 | 读 README/AGENTS/docs；`python3 -m tools.xtask doctor --json`；确认语言/构建/测试命令 |
| 2 | 需求分析 | `docs/issues/<n>/requirements.md` | 提取问题、验收标准、边界、风险、假设 |
| 3 | 方案设计 | `docs/issues/<n>/design.md` | 最小变更、涉及文件、替代方案、回滚 |
| 4 | 测试用例 | `docs/issues/<n>/tests.md` | 先写失败测试，记录预期失败 |
| 5 | 编码 | 代码 diff | 最小完整变更，遵循现有风格 |
| 6 | 审查 | `docs/issues/<n>/review.md` | diff/错误处理/安全/性能/兼容性自查 |
| 7 | 修复 | 代码 diff | 迭代到相关测试通过 |
| 8 | 系统验证 | 测试记录 | `python3 -m tools.xtask test --changed`（或 `--package <id>`） |
| 9 | 结果输出 | commit + PR + issue 评论 | 见下方命令 |
| 10 | skill 维护 | 本文件 | 独立 docs lane/PR，不混入 issue lane |

## Worktree 隔离

仓库当前**没有** `AGENTS.md`、`docs/worktree.md`、`scripts/worktree.sh`。实际可用做法：

```bash
git worktree add .agents/worktrees/issue-<n> -b issue-<n> main
cd .agents/worktrees/issue-<n>
```

- `.agents/` 已被 `.gitignore` 忽略，不会入库。
- 主 worktree 只读；所有写入在 lane 内完成。
- worktree 创建可能因仓库体积耗时长，必要时用后台执行并轮询 `git worktree list`。

## 命令

```bash
# 环境体检
python3 -m tools.xtask doctor --json

# 变更相关测试计划（dry-run 先看计划）
python3 -m tools.xtask test --changed --dry-run --json
python3 -m tools.xtask test --changed

# 指定包
python3 -m tools.xtask test --package lanlu

# 服务端原生命令（需仓颉 SDK）
cd apps/server && cjpm test --parallel nCores --timeout-each 600s
```

服务端测试目标：`lanlu`（`apps/server`，cjpm）；前端 `web:frontend`；另有 `mcp`(cargo)、`xtask`(python)。

## 验收标准

- 回归测试覆盖 issue 的验收标准，修复前失败、修复后通过（纯逻辑测试可无 DB）。
- `python3 -m tools.xtask test --changed` 无 `failed`；`config_error` 必须注明是环境缺工具链，不能当作通过。
- 只改与 issue 相关的文件；不提交 `web/dist`、`data/`、`master.key`、SQLite、日志、截图、凭证。
- PR 描述含变更、测试证据、风险、回滚；issue 评论含根因、修复、PR 链接、验证结果。
- 不合并 master、不部署、不手动 dispatch、不 push master。

## CI 触发事实（2026-11-28）

- `build.yaml` / `extension.yaml` / `build.yml` / `extension.yml` 均为 `on: [push]`，**没有** `pull_request` 触发器。
  推送分支即产生 build + extension 两个 run；开 PR 不会再触发它们。
- `cli.yaml`（`apps/mcp/**`）与 `client.yml`（`apps/mobile/**`）有路径过滤的 `pull_request` 触发。
- `client-next.yml` 为 `apps/desktop/**` 等路径的 push（及可能的 PR）触发。
- 因此「开 PR 只触发一次 PR run」的假设在本仓库对 build 主流程不成立；推送即跑。
  为控制 run 数，docs-only 的 skill/脚手架 lane 建议等主修复合并后再推，避免额外 run。
- 当前 CI 的 `Setup Cangjie` / `Set up job` 阶段存在基础设施性失败（main 同样失败），
  不能据此判定代码回归；需区分「环境失败」与「测试失败」。

## 失败处理

| 现象 | 处理 |
| --- | --- |
| `cjpm not found` / `cargo not found` | 记录为环境缺失；用静态检查 + 可运行的单测降级验证，并在 PR/issue 明示未运行编译测试 |
| `xtask test` 超时 | 用 `--timeout-each 30m` 重试；仍失败则缩小到 `--package` |
| worktree 创建卡住 | 后台执行并轮询 `git worktree list` / `target` 目录；确认 `index.lock` 消失 |
| `tea` 评论 403（缺 `write:issue` scope） | 在报告与 PR 中说明评论未发出；不要伪造评论成功 |
| 迁移版本依赖 | 在 requirements/design 中写明依赖的迁移（如 V030 将 `plugins.parameters` 转为 JSONB） |
| 测试失败 | 先修复或降级；无法完成时给出阻塞点、复现命令、已尝试步骤，禁止伪造结果 |

## 已知坑

- `plugins` 表列顺序：`has_schema`(BOOLEAN, $17) 在 `parameters`(JSONB, $18) 之前；`::jsonb` 只能落在 $18（issue #13）。
- DAO 中 `vjson()` 绑定 JSONB 文本，写 `::jsonb` 列；`vbool()` 直接绑 BOOLEAN。
- `tools.xtask` 会聚合所有 `cjpm.toml`；`apps/server` 是 `lanlu` 目标，`apps/server` 之外的 Cangjie 包为独立 target。

## 相关文件

- `tools/xtask/`（测试编排）
- `toolchain/versions.toml`（Cangjie 1.2.0 / Node / pnpm / Python 版本）
- `justfile`（`just test`、`just ci`）
