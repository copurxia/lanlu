# 分层守卫与质量基线

计划：[docs/lwindow-platform-separation-plan.md](../docs/lwindow-platform-separation-plan.md) §4.5、§16.2（T0）。

这些检查是**机器判据**：平台是否真的从业务层分出去了，不靠人读代码，靠 CI 脚本。全部在
`guards` job 里跑（`.github/workflows/client-next.yml`），本地可直接执行。

> 本目录只保留**中立**的守卫与同步脚本。鸿蒙构建/打包/门禁脚本已迁至
> [packages/lpack-ohos/tools](../packages/lpack-ohos/tools)（计划 §4.2），
> 它们需要 OHOS 工具链，不属于中立层。

| 脚本 | 判什么 |
|---|---|
| `check-deps.py` | 每个包的依赖与 import 是否在白名单内（§4.5 依赖表） |
| `check-platform-isolation.py` | 平台标识（`OH_*`/NAPI/ArkTS、`wl_*`/`xdg_*`/xkb、SDL）是否只出现在平台包与 `third_party/` |
| `check-layering.sh` | （旧）业务/UI/绑定层不得出现平台专有字样 |
| `check-no-file-bridge.sh` | 文件桥命中点只允许减少（计划 §11 / M6 删除进度），新增即失败 |
| `check-no-sdl.sh` | （旧）SDL 引用数只允许下降 |
| `check-image-decode.sh` | 图片解码只有一个实现：lgui/cui/lgpu 不得自带解码器、渲染器不得引入解码 crate、`uploadTexturePng` 类旁路不得复活 |

规则与基线：

- `deps-rules.toml` —— 白名单规则，人工维护。新增包要在这里登记，否则按“只允许标准库”处理。
- `quality-baseline.toml` —— **由脚本生成**，记录迁移起点的问题集合。数量只允许下降。

## 迁移期怎么用

```bash
python3 tools/check-deps.py --report                 # 看还有哪些违规
python3 tools/check-platform-isolation.py --report   # 按规则聚合，看工作量
python3 tools/check-deps.py                          # CI 同款判定
```

清理完一批之后，把基线刷小（**只在违规确实减少后执行**）：

```bash
python3 tools/check-deps.py --update-baseline
python3 tools/check-platform-isolation.py --update-baseline
```

两个脚本各自只重写自己那一段（`[deps]` / `[platform]`），互不覆盖。

## 判定语义

- 现状 ⊆ 基线 → 通过；比基线少了会提示刷新。
- 现状 ⊄ 基线 → 失败，并逐条打印 `[新增]`，即“你引入了一个新的耦合”。
- 平台包目录前缀固定为 `packages/lplatform-` 与 `packages/lpack-`；新增平台 = 新增两个包，
  不需要改这两个脚本（计划 §2 原则 10）。

## 交互审计的三个脚本（cui 侧，中立）

| 脚本 | 做什么 |
|---|---|
| `verify-cui-interactions.sh [main\|p0]` | 生成 SDL/vips 桩库跑 `cjpm test`，并把失败名册与 `docs/interaction-audit/test-baseline-names.txt` 逐条 diff；只有名单完全一致才返回 0。无需 GPU/SDL 设备。支持 `CJV/STUB/LOG/PKG_DIR` 环境覆盖。 |
| `rehearse-merge.sh [--keep\|--no-test]` | 合并演练：主仓快照副本 → 应用 `docs/interaction-audit/patches/*.patch` → 跑测试比对基线 → 清理。带补丁新鲜度护栏（补丁数必须等于分支提交数）与 linked-worktree 提示。 |
| `land-focus-interactions.sh [--check\|--emit-patches]` | 一把落地：脏树自检 → 合并/应用补丁 → 补宿主机 link-option → 跑测试 → cherry-pick 应用层。`--check` 只校验前置；`--emit-patches` 从分支重新生成补丁序列。 |
| `verify-examples.sh [p0|<worktree>]` | 编译框架仓库全部示例，确认“示例即文档”没有腐坏。链接期缺 SDL/vips 原生符号视为通过（本机无真实渲染后端）；语义/类型错误才算失败。 |
| `check-audit-numbers.sh` | 审计一致性：文档里的“当前数字”是否与实际提交/补丁数一致、两棵树文档内链是否可达、覆盖矩阵引用的测试名是否存在。 |

三条护栏的设计来历（2026-11-11 误提交事故、11-12 补丁过期假失败）见
[docs/interaction-audit/07-merge-runbook.md](../docs/interaction-audit/07-merge-runbook.md) §0-0。

## 另见

- `sync-wgpu-hal.sh`：从 horizon 同步 vendored wgpu-hal（lgpu 用）
- `sync-winit.sh`：从 horizon 同步 vendored winit（Wayland 壳用，M1W 首次实际同步）
- `probes/ffi-call/`：M0-4 的“引擎调壳导出符号”最小探针（5 个变体）
- `packages/lpack-ohos/tools/`：OHOS 侧构建、打包、签名与静态门禁
