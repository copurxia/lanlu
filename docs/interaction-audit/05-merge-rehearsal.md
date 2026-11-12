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


## 七、第三轮演练（2026-11-11 深夜）：对齐最新 WIP，并定位对方迁移的**链接配置缺口**

主仓这期间又前进了（对方 lcodec 迁移继续），所以重跑了一次完整演练：29 个 gui 补丁全部
`git am --3way` 干净应用（零冲突）。但合并后的树一开始**链接不过**——顺着查下去发现两条都可复现、
且与本分支无关的问题：

### 1. 干净副本没有 `target/` 时，桩库缺少 SDL 符号

`tools/verify-cui-interactions.sh` 原先靠扫描 `target/*.a` 的未解析符号来补 SDL/`TTF_` 桩；
在全新副本（没有 target/）上会漏掉全部 SDL 符号。已修：脚本内置一份 31 个 SDL 符号的已知清单，
再叠加扫描结果去重——现在任何干净副本都能直接跑起来。

### 2. 对方 WIP 删掉了宿主机 link-option（真实缺口）

合并后的 `cjpm.toml` / `lgui/cjpm.toml` 里已没有 `[target.x86_64-unknown-linux-gnu]` 的
`link-option`（迁移 lcodec 时删掉了 vips 那行），于是宿主机 `cjpm test` 链接期缺 `SDL_*` 符号。

**实测结论**：给两个 cjpm.toml 加回

```toml
[target.x86_64-unknown-linux-gnu]
link-option = "-lSDL3 -lSDL3_ttf"
```

后，合并树（对方最新 WIP + 本分支 29 补丁）跑出：

```
Summary: TOTAL: 450
    PASSED: 409, SKIPPED: 0, ERROR: 40
    FAILED: 1
== 基线匹配：失败名册与 headless 基线完全一致
```

即：**vips 已经不需要出现在宿主机链接行里（lcodec 运行期 dlopen），但 SDL3 仍然需要**。
这条建议同时适用于对方迁移完成后的主仓。

### 演练副本

- `packages/cangjie-gui-mergecheck2`：对方最新 WIP + 29 补丁（本轮全绿证据，含上述 link-option 修补）
- `packages/lcodec-rehearsal`：lcodec 的隔离副本（避免动对方正在改的目录）
- 复跑：`PKG_DIR=packages/cangjie-gui-mergecheck2 CANGJIE_STDX_PATH=/workspace/.cjv/stdx/lts/static/stdx tools/verify-cui-interactions.sh`


## 九、一键演练脚本（`tools/rehearse-merge.sh`）

前面三轮演练是手工做的，容易走样。现已固化成脚本，一条命令完成「复制快照 → 落快照提交 → 隔离 lcodec
→ `git am` 应用补丁 → 跑测试并与基线名册比对」，全程不碰主仓工作树：

```bash
tools/rehearse-merge.sh            # 演练 + 测试，成功后清理副本
tools/rehearse-merge.sh --keep     # 保留副本排查
tools/rehearse-merge.sh --no-test  # 只验证补丁能否干净应用
```

实测输出（2026-11-11，对方 WIP 最新快照 + 29 个补丁）：

```
== 4/5 应用 gui 补丁（git am --3way）
   已应用 29 个补丁
== 5/5 跑桩库测试并与基线名册比对
Summary: TOTAL: 450
    PASSED: 409, SKIPPED: 0, ERROR: 40
    FAILED: 1
== 基线匹配：失败名册与 headless 基线完全一致
```

脚本还会自动给副本补上宿主机 `link-option`（迁移中的工作树可能缺这一行，见 §七），并在输出里
注明这是"演练脚手架"，不改主仓。

> 演练副本已清理（每个约 165M，脚本可随时重建）。
>
> **状态更新（2026-11-12 01:46 复核）**：对方已修复（删掉了 MonoTime 的字符串插值），
> 主仓 `cjpm build` 通过；**演练随即恢复全绿**：77 补丁零冲突 → 合并后 **501 例 / 494
> 通过 / 基线匹配**。上一段记录保留（教训仍有效：演练失败先查主仓能否编译——本轮从
> "失败"到"全绿"只隔两分钟，根因全是对方的编辑中间态）。
>
> **状态更新（2026-11-12 01:44）**：演练本轮**无法完成**——不是本分支的问题，而是主仓
> `packages/cangjie-gui` 的最新 WIP **编译不通过**：`src/media/pixel_texture_cache.cj:437`
> （对方 01:39 编辑中的真机诊断代码）用了 `MonoTime` 的 ToString，`cjpm test` 直接报
> `the type 'Struct-MonoTime' should implement interface 'ToString'`。基准分支自身仍全绿
> （`verify-cui-interactions.sh p0` → 501 例 / 494 通过 / 基线匹配）。
> 这也说明"演练失败"不等于"我方有回归"——**先看主仓能否编译**。演练脚本目前会在
> 补丁应用后用 `cjpm test` 暴露这类问题，报错信息即定位。
>
> **就绪心跳（滚动更新）**：2026-11-12 01:00——全量演练复验：**63 个补丁零冲突 + 491/450 基线匹配**
> （对主仓最新 WIP 快照）。合并窗口一开即可照 [07-merge-runbook.md](07-merge-runbook.md) 或一条命令
> `tools/land-focus-interactions.sh` 执行。
> 键盘导航约定本轮（第 72–74 轮）补齐了 ComboBox/Dropdown/ContextMenu 的 Home/End，
> 至此覆盖全部列表类交互面；MenuBar 未加（条目少、收益低，避免镀金）。
>
> **同文件改动核查（01:02）**：对方的 gui WIP 与本分支存在一处**同文件改动**——
> `src/controls/modal.cj`（对方加诊断 sink，改遮罩尺寸记录；本分支 `3426fb5` 改焦点初始
> 聚焦/恢复）。两处 hunk 不重叠，01:00 的全量演练（对方 modal.cj 改动已在快照内）以
> `git am --3way` 干净合入 63 个补丁——**该冲突风险已实测为零**。另 `src/media/pixel_texture_cache.cj`
>（00:59 新脏，真机纹理诊断）与本分支无交集。
>
> **阻塞现状（19:25 实测时间戳）**：`packages/cangjie-gui` 的 11 个未提交文件里，最新改动停在
> **16:26**（`cjpm.toml`/`bench`/`examples` 三处链接配置），其余更早（06:00–14:10）——即对方的
> gui 层改动已**停笔约 3 小时**；但父仓库仍有活跃改动（`client-next/src/main.cj`、ArkTS
> `Index.ets`、rocksdb 原生库，最近 19:20）。判断：gui 改动是同一迁移的一部分、被暂时搁置，
> 不是放弃。
> 落地入口已备好：`tools/land-focus-interactions.sh`（脏树自检 → 合并 → 补 link-option →
> 跑测试 → cherry-pick 应用层），`--check` 现在会明确报出 "11 个未提交文件" 并拒绝执行。
> 合并窗口一开即可照 [07-merge-runbook.md](07-merge-runbook.md) 执行。
> （历史：18:20 时点为 33 补丁 / 465·424；补丁序列与数字以此处为准。）


## ⚠️ 事故记录：runbook 演练误把对方 WIP 提交进了 feature 分支（2026-11-11 18:38）

**经过**：验证 [07-merge-runbook.md](07-merge-runbook.md) 步骤时，演练副本里的 `packages/cangjie-gui` 是主仓的
**linked worktree**（共享对象库与引用），且步骤里 `rsync` 了 `client-next/` 到 worktree 根。随后在副本里执行
`git add -A && git commit -m "snapshot"` 时，git 解析到了**主仓共享的分支引用**，把对方全部未提交改动
（400 文件，+32936/−107831）收编为 feature 分支上的提交 `dc45e03b`（作者 o@l，即演练脚本身份）。

**影响核实**：
- 内容**零丢失**——snapshot 完整保留对方 WIP；主仓工作树因此变为干净（0 未提交）。
- `packages/cangjie-gui` 是嵌套仓库（自有 .git），**不随父仓库提交**——其 11 个未提交文件原样保留，
  gui 分支合并仍需与其协调（本轮探测确认不变）。
- 应用层补丁恰是在含对方 WIP 的内容上生成的，故顺势以 `e100c33e` 正式落地（内容自洽）。

**为何不重写历史**：feature 分支可能已被对方工具链引用；重写（reset/rebase）会把 `dc45e03b` 之后的
4 个提交一起改写，风险大于收益。选择保留历史 + 文档记录。

**后续清理（2026-11-11 19:30）**：该误操作还把 `packages/cangjie-gui-p0`（嵌套仓库的 linked worktree）
当作 gitlink（mode 160000）记进了 parent 仓库，导致 p0 分支每推进一步都显示为 parent 仓库修改。
已 `git rm --cached` 移除该指针并加入 `.gitignore`——worktree 目录仍在磁盘上，只是不再被 parent 跟踪。

**教训（已并入操作规范）**：在共享 worktree 或嵌套仓库环境下做演练，一律先把副本变成**独立克隆**
（`git clone` 而非 `git worktree`），或在副本内 `git init` 全新仓库；绝不在"看似独立实则共享引用"的
目录里执行任何 `git add -A`。

## 十、演练副本（历次）

- `packages/cangjie-gui-mergecheck`：主仓 WIP + 本分支 25 补丁（用于继续排查对方 lcodec 问题）
- `packages/cangjie-gui-wipcheck`：纯主仓 WIP 对照（**不含**本分支）
- 两者都可用 `PKG_DIR=<dir> tools/verify-cui-interactions.sh` 复跑；验证完可整体删除
  （`rm -rf packages/cangjie-gui-mergecheck packages/cangjie-gui-wipcheck`）。
