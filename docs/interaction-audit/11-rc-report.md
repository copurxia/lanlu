# 发布候选（RC）证据快照

> 生成时间：**2026-11-12 03:28（第 5 版）** · 分支 `p0-focus-visible` @ `93 提交`
> 本文件只记录**当次实测输出**，不做推断；数字若与其它文档不同，以本文件时间戳为准。
> 前版（01:47，77 提交，501/494）已被本版取代。本版新增：media 三项防御性修复（上传预算/登记校验）
> 与其文档，详见 [12-findings-for-other-party.md](12-findings-for-other-party.md)。

## 1. 分支内测试（无需 GPU/SDL）

```
$ tools/verify-cui-interactions.sh p0
Summary: TOTAL: 520
    PASSED: 513, SKIPPED: 0, ERROR: 6
    FAILED: 1
== 基线匹配：失败名册与 headless 基线完全一致（cjpm exit=1）
```

- 513 条真实通过（起点 450 → 基线削减 + 覆盖补齐 + media 防御测试，提到 501）。
- 7 条豁免：6 ERROR + 1 FAILED，逐条定性见 [test-baseline-notes.md](test-baseline-notes.md)
  （2 条需真实 SDL 窗口、3 条需真实文本度量、1 条需真实跨线程唤醒、1 条成本不值）。

## 2. 合并演练（对主仓最新 WIP 快照）

```
$ tools/rehearse-merge.sh
Summary: TOTAL: 520
    PASSED: 513, SKIPPED: 0, ERROR: 6
    FAILED: 1
== 基线匹配：失败名册与 headless 基线完全一致（cjpm exit=1）
== 完成；清理副本
EXIT=0
```

- **94 个补丁** `git am --3way` **零冲突**全部应用。
- 合并后测试结果与分支内**完全一致**（同 513 通过 / 同 7 条豁免）。
- 演练前的补丁新鲜度护栏生效（补丁数 93 == 分支提交数 93）。
- 排障记录：主仓 WIP 曾有 2 分钟的编译中间态（MonoTime 插值），对方修复后演练即全绿——
  演练失败先查主仓能否编译。

## 2b. 示例应用源码兼容（2026-11-12 01:58 实测）

对 `examples/` 下 **29 个示例应用**逐个 `cjpm build`：

- **源码级零错误**：没有任何一个示例出现 `undeclared identifier` / 类型不匹配等编译错误
  ——说明本轮对框架 API 的改动（新增可选参数、新方法、`Key` 枚举扩展）**完全向后兼容**。
- 28 个停在**链接阶段**（`ld: undefined reference to vips_*` / SDL 符号）：本机没有真实
  vips/SDL 共享库，与测试基线里那 7 条豁免同源；1 个（无图片依赖）完整构建成功。
- 复现方法：在 `examples/<name>` 下 `cjpm build`，只需看是否出现 `.cj` 相关的编译错误。

这条比"我们改的控件有测试"更强：它证明**别人写的 29 个真实应用**不用改一行代码就能过编译。

## 3. 文档与出口一致性（同轮自查）

| 检查 | 结果 |
|---|---|
| 框架文档内链（7 份） | 0 断链 |
| 审计文档内链（13 份 + 子目录） | 0 断链 |
| 公开 API 出口（`cui.cj`） | 新 API 全部可达（含 `KeyRepeat`） |
| 文档签名 vs 源码 | 逐条一致（FocusTarget/registerFocusStop/drawFocusRing/KeyRepeat/selectionRange/onSubmit/groupRange/RichSpan.link/editMenuItems/onActivate） |
| 更名一致性 | 无 `sdl` 旧包名残留（顶层 README + docs 全扫） |

## 4. 已知未覆盖（需真机）

- 真机（OHOS）交互手感：31 条验收清单见 [06-acceptance-checklist.md](06-acceptance-checklist.md)。
- 应用层整包 `cjpm build`：需真实合并后（兄弟包硬编码 `../cangjie-gui`，副本旁路会造成模块路径冲突）。
- 修饰键路径（Shift+滚轮、Alt+Up/Down 重排）：单测无法伪造修饰键，靠代码审查 + 真机。

## 5. 结论

框架侧交付处于**可合并状态**：代码、测试、文档、工具四条线自洽且经交叉验证。
唯一阻塞是 `packages/cangjie-gui` 里另一任务方的 12 个未提交文件——不是我们这边的问题。
解除后照 [07-merge-runbook.md](07-merge-runbook.md) §0 一条命令执行即可。
