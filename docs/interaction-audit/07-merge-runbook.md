# 合并操作单页（照做即可）

> 目标：把 `p0-focus-visible`（29 个提交）与应用层 3 个补丁落到主仓，并确认没有回归。
> 全程预计 10–20 分钟（含一次全量测试）。

## 0. 前置检查

```bash
cd /path/to/lanlu
git -C packages/cangjie-gui status --short   # 期望为空：工作树干净才能 git am
```

如果有输出：说明还有未提交改动。要么让对方先提交，要么用补丁路径（见 §4-B），**不要**在脏树上 `git am`。

## 1. 落地 gui 分支（二选一）

**A. 直接合并分支**（推荐，历史最清晰）

```bash
cd packages/cangjie-gui
git merge --no-ff p0-focus-visible
```

**B. 用补丁序列**（主仓长期被占用时）

```bash
cd packages/cangjie-gui
git am --3way /path/to/lanlu/docs/interaction-audit/patches/*.patch
```

**C. 只想先要 P0**（用户反馈的那两条）

```bash
git am --3way .../patches/000{1,2}-*.patch
```

## 2. 补宿主机测试链接行（重要）

对方 lcodec 迁移删掉了宿主机 `link-option`，宿主机跑测试会缺 `SDL_*` 符号。给这两个文件各加一段：

```toml
# packages/cangjie-gui/cjpm.toml 与 packages/cangjie-gui/lgui/cjpm.toml
[target.x86_64-unknown-linux-gnu]
link-option = "-lSDL3 -lSDL3_ttf"
```

> 实测：vips 已不需要出现在宿主机链接行（`lcodec` 运行期 dlopen），SDL3 仍需要。
> 详见 [05-merge-rehearsal.md](05-merge-rehearsal.md) §七。

## 3. 跑测试确认零回归

```bash
cd /path/to/lanlu
# 若合并后的树里 lgui 依赖 lcodec（对方迁移），需要 stdx 二进制依赖路径：
export CANGJIE_STDX_PATH=/workspace/.cjv/stdx/lts/static/stdx
tools/verify-cui-interactions.sh
```

期望结尾：

```
Summary: TOTAL: 479
    PASSED: 438, SKIPPED: 0, ERROR: 40
    FAILED: 1
== 基线匹配：失败名册与 headless 基线完全一致
```

本节已按原文**逐字实跑验证**（2026-11-11，含对方 WIP 快照的演练副本）：步骤 0/1B/2/4 全部
按文档产出预期结果；步骤 3 在补上 `CANGJIE_STDX_PATH` 后输出 479/438 与基线匹配。
若打出 diff：对比 [test-baseline-names.txt](test-baseline-names.txt)，
新增失败即回归；消失的失败通常是环境变化（例如某个 headless 用例碰巧通过），也要留意。

## 4. 应用层补丁（顺序不能反）

```bash
cd /path/to/lanlu
git apply --check docs/interaction-audit/patches-app/0001-*.patch   # 先干跑
git apply docs/interaction-audit/patches-app/0001-*.patch
git apply docs/interaction-audit/patches-app/0002-*.patch
git apply docs/interaction-audit/patches-app/0003-*.patch
```

- `0001` 表单回车 + 登录/弹窗初始聚焦
- `0002` `ClickArea`/`GhostIconButton` 接入焦点环（依赖 gui 的 `registerFocusStop`、`drawFocusRing`）
- `0003` 阅读器 dock 键盘翻页（依赖 `Key.PageUp/PageDown`）

应用后用完整环境编译一次（本机缺 `cargo`，需在有构建条件的机器上做）。

## 5. 真机/桌面验收

按 [06-acceptance-checklist.md](06-acceptance-checklist.md) 逐条勾选（哪条能靠测试兜底见
[08-coverage-matrix.md](08-coverage-matrix.md)）；重点：

1. A1/A3（点进输入框、Tab 外环）——用户最初反馈的问题；
2. B1/B2（自绘卡片可 Tab、Enter 激活）——改动面最大的部分；
3. D1（阅读器 dock 键盘翻页）。

## 6. 出问题怎么办

| 现象 | 处理 |
|---|---|
| `git am` 冲突 | `git status` 看冲突文件；`git am --show-current-patch=diff` 看当前补丁；`--3way` 多数能自动合并。解完 `git am --continue`，想放弃 `git am --abort` |
| 测试失败名册多了条目 | 先看是不是环境（headless/时间/随机），再对比 [test-baseline-names.txt](test-baseline-names.txt)；确认回归就用 `git revert` 对应提交 |
| 焦点环压住内容 | 调 `drawFocusRing(rect, radius)` 的 radius/inset；框架内统一在 `core/surface_draw.cj` |
| 40+ `ClickArea` 布局有变化 | 回退 `0002`，改用逐个迁移（`FocusTarget` 用法见 `docs/components.md`） |
| 想整体回滚 | 分支是独立提交组，`git revert -m 1 <merge>` 或按分组 revert（见 [04-pr-description.md](04-pr-description.md) §八） |

## 7. 合并前想自己验证一遍

```bash
tools/rehearse-merge.sh --keep   # 复制工作树快照 → 应用 29 补丁 → 跑测试 → 比基线
```

看到「基线匹配」说明补丁与当前主仓状态兼容（不碰主仓工作树）。
