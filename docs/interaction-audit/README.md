# 交互审计 · 交付索引

> 一句话：用户报告"点击输入框没有描边"，调查扩展为对整个基础组件库交互面的审计与修复。
> 状态：**框架侧全部完成**（**95 提交 / 514 测试通过 / 95 补丁对最新 WIP 零冲突演练全绿**；
> 交互修复 + media 五项防御 + 示例 30/30 与 bench 6/6 可编译），
> 合并被唯一外部条件阻塞：`packages/cangjie-gui` 里另一任务方的 13 个未提交文件。

## 按角色进入

| 你是… | 先看 |
|---|---|
| 想知道"为什么点输入框没描边" | [00-root-cause.md](00-root-cause.md)（2 分钟）|
| Reviewer | [04-pr-description.md](04-pr-description.md)（分组 A–G + 用户可感知 25 条）|
| 负责合并的人 | [07-merge-runbook.md](07-merge-runbook.md) §0 一条命令，或 [05-merge-rehearsal.md](05-merge-rehearsal.md) 看就绪心跳 |
| 真机验收 | [06-acceptance-checklist.md](06-acceptance-checklist.md)（31+ 条，含自动化兜底标注）|
| 想了解某个缺口怎么修的 | [09-gap-final-status.md](09-gap-final-status.md)（20 类逐条落点）|
| 要判断"现在能不能交付" | [11-rc-report.md](11-rc-report.md)（时间戳 + 四条实测输出）|
| 接手纹理/封面调试 | [12-findings-for-other-party.md](12-findings-for-other-party.md)（3 项已修 + 排查顺序）|
| 看全貌与批次明细 | [01-summary.md](01-summary.md)、[02-p0-batch.md](02-p0-batch.md)（逐批提交与验证）|
| 看应用层接线方案 | [03-app-wiring-plan.md](03-app-wiring-plan.md)、[app-layer.md](app-layer.md) |
| 看框架控件/浮层的实测清单 | [framework-controls.md](framework-controls.md)、[framework-text-overlays.md](framework-text-overlays.md) |
| 看交付自检与覆盖矩阵 | [10-delivery-selfcheck.md](10-delivery-selfcheck.md)、[08-coverage-matrix.md](08-coverage-matrix.md) |
| 想知道哪些豁免是环境而非回归 | [test-baseline-notes.md](test-baseline-notes.md)（7 条逐条定性）|
| 想复现测试 | `tools/verify-cui-interactions.sh p0`（无需 GPU/SDL）|

## 数字速览（2026-11-12 01:05）

| 维度 | 值 |
|---|---|
| gui 分支提交 | 63（47 代码 + 16 文档）|
| 测试 | 491 例 / **484 通过** / 失败名册与 7 条环境基线逐条一致（零回归；每条豁免依据见 [test-baseline-notes.md](test-baseline-notes.md)）|
| 新增测试用例 | 104 + 改写 1 |
| 补丁 | gui 63 + 应用层 3（与分支 `app-focus-wiring` 一致性已核对）|
| 审计维度 | 原 20 类缺口 + 9 个维度系统审计（键盘/悬停/焦点环/浮层三路/边界/光标/滚动/浮层栈/指针）|
| 交互面判定 | 缺口全部落地或判定为刻意设计；键盘导航约定覆盖全部列表类交互面 |

## 关键结论（防误读）

1. **"点击没描边"是刻意约定**（`:focus-visible`）：指针聚焦画激活边、键盘聚焦叠外环。
   曾因应用层顶栏搜索框用错 API 出现两种表现，已修。
2. **方向键边界有两种刻意约定**：位置类钳制、周期类（Picker/时间）回绕——各有测试固定，
   别"修"成一致。
3. **滚动到边界穿透**依赖 `SmoothScroll.wheel` 返回值，容器必须 `return` 它而非恒 true。
4. **MenuBar 没有 Home/End 是刻意的**（条目少，避免镀金）。

## 当前阻塞（唯一）

`packages/cangjie-gui` 有另一任务方 12 个未提交文件（真机诊断 + lcodec 迁移的链接配置）。
对方仍在活跃工作（最近改动 00:59）。不能代为提交。解除后：

```bash
tools/land-focus-interactions.sh --check   # 前置确认
tools/land-focus-interactions.sh           # 合并 + 补 link-option + 跑测试 + cherry-pick 应用层
```
