# 合并演练报告（2026-11-11）

> 目的：在主仓 `packages/cangjie-gui` 长期被他人未提交改动占用的情况下，**不碰对方工作树**地
> 验证「`p0-focus-visible` 分支合进来是否干净、合并后能否构建」。

## 一、演练方法

```bash
# 1) 复制主仓当前工作树（含他人未提交改动）到同级副本，保证 cjpm 的相对路径依赖仍成立
rsync -a --exclude target --exclude build-ohos packages/cangjie-gui/ packages/cangjie-gui-mergecheck/

# 2) 在副本里把"对方的未提交改动"先落成一个提交（模拟对方先提交）
cd packages/cangjie-gui-mergecheck
git add -A && git commit -m "rehearsal: 模拟对方未提交改动先落地"

# 3) 应用本分支的 25 个补丁
git am --3way docs/interaction-audit/patches/*.patch
```

## 二、结果

| 检查 | 结果 |
|---|---|
| 25 个补丁应用 | **全部干净应用，零冲突**（含对方改过的 `src/controls/modal.cj`：3-way 自动合并成功） |
| 应用后 tree 与分支对比（干净基线上） | 与分支 tip **完全一致**（`b902e1a3dfe413252109cafd4d52f31e1c481c27`） |
| 合并后 `cjpm test` | **被对方的 in-progress 重构阻塞**，与本分支无关（见下） |

### 合并后构建被阻塞的原因（已定位，属对方 WIP）

1. 对方把 `lgui` 的解码依赖从 `vips_ffi` 换成新包 `packages/lcodec`（`lgui/cjpm.toml` 已改）。
2. `lcodec` 自身的 `cjpm test`/build 需要 stdx 二进制依赖：
   `[target.*.bin-dependencies] path-option = ["${CANGJIE_STDX_PATH}"]`，
   且其 `target/.dep-cache` 与本机 cjv 工具链版本（1.0.5 vs 1.2.0）不匹配，
   cjpm 在 `loadDepIncrementalCache` 抛 `DataModelException`。
3. **对照实验**：把同一份副本去掉本分支补丁（纯对方 WIP 状态）跑同一命令，报**完全相同**的
   `lcodec` 错误 → 与本分支无关。

## 三、结论与建议顺序

1. 本分支合入前**不需要**改任何 code（补丁零冲突即可证明）。
2. 请对方先：
   - 提交 `packages/lcodec` 与 `lgui/cjpm.toml` 的改动；
   - 清一次 `packages/lcodec/target/.dep-cache`（工具链版本切换后的缓存不兼容）；
   - 在其构建脚本里导出正确 `CANGJIE_STDX_PATH`（如 `/workspace/.cjv/stdx/lts/static`）。
3. 上述就绪后，二选一落地本分支：
   - 合并：`git merge p0-focus-visible`；
   - 或补丁：`git am --3way docs/interaction-audit/patches/*.patch`。
4. 落地后跑 `tools/verify-cui-interactions.sh`，期望 `TOTAL 444 / PASSED 403 / ERROR 40 / FAILED 1`
   且输出「基线匹配」。

## 四、演练副本

- `packages/cangjie-gui-mergecheck`：主仓 WIP + 本分支 25 补丁（用于继续排查对方 lcodec 问题）
- `packages/cangjie-gui-wipcheck`：纯主仓 WIP 对照（**不含**本分支）
- 两者都可用 `PKG_DIR=<dir> tools/verify-cui-interactions.sh` 复跑；验证完可整体删除
  （`rm -rf packages/cangjie-gui-mergecheck packages/cangjie-gui-wipcheck`）。
