# 交付自检（2026-11-11）

> 对 `main` 上的交接包做了一次完整自洽性检查，全部通过。

| 检查 | 方法 | 结果 |
|---|---|---|
| 文档内部链接 | 脚本扫描 49 个 md 的相对链接并验证目标存在 | **全部可达**（含 patches/、test-baseline-names.txt 等跨目录引用） |
| gui 补丁序列完整性 | 干净基线 `c39458f` 克隆上 `git am --3way` 全部 30 个补丁 | **全部应用，exit 0**；重建 tree `7d07b4fa` 与分支 tip **完全一致** |
| gui 补丁对当前主仓 | `tools/rehearse-merge.sh`（复制工作树快照 + 应用补丁） | **30 个补丁零冲突** |
| 应用层补丁 | 对当前主仓工作树 `git apply --check` 逐个 | **3/3 通过** |
| 补丁分组表覆盖 | 程序化解析 README 的区间标记（如 0003–0004）对照实际补丁号 | **1–30 无缺失、无多余** |
| 基线名册 | 行数与测试输出对照 | **41 条环境失败**，脚本逐条 diff |
| 工具脚本 | `verify-cui-interactions.sh`（含 SDL 符号内置清单）、`rehearse-merge.sh` 实跑 | 均按文档输出预期结果 |
| 测试 | `tools/verify-cui-interactions.sh p0` | **TOTAL 474 / PASSED 433 / 基线匹配** |

> 已知未验证项（非缺陷，环境限制）：应用层补丁的整包 `cjpm build`（本机缺 cargo）；
> 真机（OHOS）表现（需对应工具链重编）。两者都在 [07-merge-runbook.md](07-merge-runbook.md) 标注。
