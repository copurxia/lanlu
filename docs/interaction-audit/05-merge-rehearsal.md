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


## 五、第二轮演练（2026-11-11 晚）：合并后测试**全绿**

第一轮只验证了「补丁零冲突」。这一轮把「合并后能不能跑过测试」也验了：

### 做法（不改对方任何源码）

1. 复制主仓工作树 → `packages/cangjie-gui-mergecheck`，把对方未提交改动先落成提交；
2. 把对方的 `lcodec` 也复制一份（`packages/lcodec-rehearsal`），只在**副本**里把
   `lgui/cjpm.toml` 的 `../../lcodec` 改指该副本，避免动对方正在改的目录；
3. `git am --3way patches/*.patch` 应用 25 个补丁；
4. 用 `CANGJIE_STDX_PATH=/workspace/.cjv/stdx/lts/static/stdx`（`lcodec` 的 stdx 二进制依赖）
   跑 `PKG_DIR=... tools/verify-cui-interactions.sh`。

### 结果

```
Summary: TOTAL: 444
    PASSED: 403, SKIPPED: 0, ERROR: 40
    FAILED: 1
== 基线匹配：失败名册与 headless 基线完全一致
```

合并后的树（对方 WIP + 本分支）**与分支单独跑的结果完全相同**：444 例、403 通过、失败名册与基线逐条一致。

### 合并时唯一需要的适配（已提前消除）

对方分支的 `Canvas` 接口新增了抽象方法 `releaseTexture(id: Int64)`（纹理回收）。我的测试探针
`ChromeProbe` 只实现了 `c39458f` 时的接口 → 合并后编译报 `missing abstract function`。

已在分支侧提交 `2289704` 预置该方法（探针无语义），**因此合并/应用补丁后无需任何手工适配**。
其余 4 个新增接口方法（`snapshotTexture`/`layerMark`/`discardRecorded`/`glowRing`）在接口里都有默认实现，无需实现。

### 注意：主仓是移动靶

演练期间对方仍在改：主仓 `packages/cangjie-gui` 未提交文件在几小时内从 9 个增至 11 个
（新增 `cjpm.toml`、`bench/micro/cjpm.toml`、`examples/calculator/cjpm.toml`，属 lcodec 迁移的链接配置）。
用**同一套补丁**在新快照上重跑会因对方 `cui/cjpm.toml` 尚未写入 `-lvips/-L stdx` 而链接失败——
这是对方 WIP 的中间态，不是本分支问题（与本轮第一轮的对照实验同型）。

**结论**：本分支合并/落地在代码层面已完全就绪；等对方把 lcodec 迁移与链接配置提交完即可合并。

## 六、演练副本

- `packages/cangjie-gui-mergecheck`：主仓 WIP + 本分支 25 补丁（用于继续排查对方 lcodec 问题）
- `packages/cangjie-gui-wipcheck`：纯主仓 WIP 对照（**不含**本分支）
- 两者都可用 `PKG_DIR=<dir> tools/verify-cui-interactions.sh` 复跑；验证完可整体删除
  （`rm -rf packages/cangjie-gui-mergecheck packages/cangjie-gui-wipcheck`）。
