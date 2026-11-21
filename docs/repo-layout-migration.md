# 仓库布局迁移方案：apps/packages

状态：方案已裁决；**PR1（`extension`）已落地并经 CI 验证；PR2（`mcp`）、PR3（`client`）、PR4（`frontend`）、PR5（`client-next`）代码已完成、待统一 push 后由 CI 验证**；PR6（`src`）未开始。

盘点基线：`b3afc9e7`，2026-11-21。
硬前置（**已达成**）：桌面端 261 个用例在**当前路径**跑出绿基线——run 1511（`ba1747e9`）`client-next-test` success，13m03s，261/261 PASSED，详见 `docs/testing-roadmap.md` §10.1.7。该结果即为 PR1 的开工闸门；PR2 在其后串行执行。

## 1. 目标与理由

目标采用业界常见的两层 monorepo 布局：

```text
apps/
  server/       # 服务端可部署程序，现根目录 src/ + cjpm.toml
  desktop/      # 现 client-next/
  web/          # 现 frontend/
  mobile/       # 现 client/
  extension/    # 现 extension/
  mcp/          # 现 mcp/
packages/       # 可复用库、FFI、平台适配层，保持平铺
tools/          # 构建编排与守卫
docs/           # 文档
```

分层原则是按产物属性划分：`apps/` 存放可部署端；`packages/` 存放可复用库。这与 Nx/Turborepo/pnpm workspace 常用的 `apps/ + packages/` 结构，以及 Go 的 `cmd/ + pkg/`、Rust workspace 的 `apps/ + crates/` 思路一致。

迁移只做路径迁移，不做行为重构。锁文件策略、pnpm workspace 形态、依赖关系、构建参数和产品行为均保持不变。

## 2. 目录映射与必改面

| 现目录 | 目标目录 | 跟踪文件数 | 活跃引用概览 | 必改面 |
|---|---|---:|---|---|
| `extension/` | `apps/extension/` | 32 | 约 27 处 / 5 个活跃文件 | `extension.yaml` 的安装、构建、typecheck、artifact 路径；GitHub 同步；xtask Node target 映射 |
| `mcp/` | `apps/mcp/` | 19 | 约 29 处 / 7 个活跃文件 | `cli.yaml` 的 path filter、musl 构建、test、artifact；`build.yaml` 的 `mcp` job；GitHub 同步；xtask Cargo target 映射 |
| `client/` | `apps/mobile/` | 200 | 约 45 处 / 7 个活跃文件 | `client.yml` 的 path filter、npm cache、安装、test、Android 构建路径；`package-lock.json` 随目录整体移动 |
| `frontend/` | `apps/web/` | 274 | 约 32 处 / 6 个活跃文件 | `build.yaml` 的 pnpm install、typecheck、test、build、runtime bundle 组装；GitHub 同步；xtask 映射。镜像内 `/app/frontend/out` 的 smoke 断言不变 |
| `client-next/` | `apps/desktop/` | 97 | 约 81 处 / 14 个活跃文件 | Gitea 桌面 job、GitHub 桌面工作流、manifest/build.cj 中 `../packages/...` 改为 `../../packages/...`、xtask、依赖规则和 SDL/状态写守卫 |
| 根 `src/` + `cjpm.toml` | `apps/server/` | 285 | 约 119 处 / 17 个活跃文件，最大 | 根 Cangjie manifest 移入 `apps/server/`；path dependency 改为 `../../packages/...`；Gitea server-test/build/package 主链、CNB 构建链、xtask 根包特判、多个守卫和基线同步 |

历史文档、旧提交说明、已完成计划中的旧路径不回改。当前不作为验收通道的 `.github` 工作流仍应同步更新，避免镜像恢复后直接失效。

## 3. 特殊风险

### 3.1 服务端根包迁移

根 `cjpm.toml` 现在定义服务端可执行包。移入 `apps/server/` 后，仓库根不再默认是 Cangjie 包，`cjpm update/build/test` 必须显式进入 `apps/server/`。受影响链路包括：

- `server-test` 的根包 12 例；
- `build` job 的依赖解析、WasmEdge source patch、Cangjie build；
- `target/release/bin/main` 输出路径和 runtime bundle 组装；
- `package` job 的 Docker image 与 smoke test；
- `.cnb.yml` 的后端和 frontend 组合构建链。

Dockerfile 只 COPY 已经准备好的 `./app` runtime bundle，不需要改成 COPY 源码目录。

### 3.2 xtask 与静态守卫

xtask 按 manifest 递归发现 Cangjie 包，多数端迁移后能自然发现；但 `tools/xtask/graph.py` 对 `frontend`、`client`、`extension`、`mcp` 有硬编码路径，根包也有 `rel == "."` 的特判。所有测试 fixture 必须随路径更新。

`tools/check-deps.py` 当前只扫描 `packages/*/cjpm.toml`。服务端迁到 `apps/server/` 后需要显式登记，或把扫描规则扩展到 `apps/*/cjpm.toml`，否则服务端会脱离依赖白名单守卫。

`client-next` 迁移必须同步：

- `tools/deps-rules.toml` 的 `lanlu_client_next.path`；
- `tools/check-layering.sh`；
- `tools/check-no-sdl.sh`；
- `tools/check-state-writes.py`；
- `tools/check-image-decode.sh`；
- 相关 quality baseline。

### 3.3 Node 与 Android

`frontend/` 和 `extension/` 各自维护独立 pnpm lock，`frontend/pnpm-workspace.yaml` 只配置 allowBuilds，没有跨目录 package glob。整体移动风险低；迁移时禁止合并 workspace 或重新生成 lockfile。

`client/` 是 React Native 工程，Android Gradle、patch 脚本和依赖均基于目录内部相对路径。使用 `git mv` 整目录移动可保留结构；CI 必须同步 npm cache key、`cd` 路径和 artifact 路径。迁移后应通过 `workflow_dispatch` 验证一次 Android release，而不仅跑 quality job。

### 3.4 PR4 带出的本地开发副作用（已知，不影响 CI）

服务端静态目录的默认值是相对 CWD 的 `frontend/out`（`src/infrastructure/middleware/frontend_fallback.cj:10`，`src/contexts/system/interfaces/http/frontend_controller.cj:31/145/338/426` 的默认参数同此）。PR4 后构建产物在 `apps/web/out`：

- **Docker/CI 不受影响**：镜像内仍是 `/app/frontend/out`，`build.yaml` 用 `cp -r apps/web/out app/frontend/out` 组装，`scripts/docker-smoke-test.sh:11` 的断言也指向该路径。
- **本地直跑受影响**：`./target/release/bin/main` 找不到页面；README 已注明用 `mkdir -p frontend && ln -sfn ../apps/web/out frontend/out` 兜底。
- **根治方式（独立 PR，不属于纯路径迁移）**：把默认值改为可被环境变量覆盖，或统一改成 `apps/web/out` 并同步 bundle 组装。

### 3.5 PR5 的额外改动面（相对深度）

`client-next/` 在根下一层，`apps/desktop/` 深了一层，所以凡是从该目录**相对**指向 `packages/` 的路径都要多一级：

- `apps/desktop/cjpm.toml`：11 处 `path =` 依赖、2 处 `link-option` 的 `-L`（Linux/Windows 各一条）；
- `apps/desktop/build.cj`：fontkit/webview 的 cargo manifest 与产物目录、三座 C 桥的 `.c`/`.o`/`.a`、lwp 的 `build.sh`；
- `.github/workflows/client-next.yml` 的 deb 打包：`working-directory: apps/desktop` 后脚本引用变为 `../../packages/lpack-linux/tools/build-deb.sh`。

守卫与基线必须**同批**更新，否则会静默扫不到文件（不报错、只是不再检查）：
`tools/check-no-sdl.sh`、`check-layering.sh`、`check-no-file-bridge.sh`、`check-image-decode.sh`、`check-state-writes.py`、`check-docs-consistency.py`、`tools/deps-rules.toml`（`[package.lanlu_client_next] path`）、`tools/quality-baseline.toml`（5 条 `apps/desktop/src/...` 键）。

**不要跟着改的**：`~/.config/lanlu-client-next/` 与 `~/.cache/lanlu-client-next/` 是用户磁盘上的运行时缓存目录，`cjpm` 包名 `lanlu_client_next`、artifact 名与 workflow 文件名同理——改它们会造成用户数据迁移与发布产物改名，超出纯路径迁移范围。

### 3.6 单 runner 串行

Gitea 当前单 runner 串行，`build.yaml` 没有细粒度 path filter，迁移 PR 会进入完整主链。因此禁止一次混迁多个端；每个 PR 都要单独等待对应 job 出结论后再开下一批。

## 4. PR 拆分与验收

| PR | 内容 | 预计人日 | 验收 |
|---|---|---:|---|
| PR0 | 新增本迁移方案文档 | 0.25 | 文档-only diff；`git diff --check` 通过；不改生产文件 |
| PR1 | `extension/` → `apps/extension/` | 0.25 | **已完成（`abdaf76e` 移动目录、`fa3066c3` 更新引用）**；CI 已验证：run 1503/1504 `build-extension` **success**，1512 在 04:33 断线窗口内 7 个 job 全挂（基础设施失败，不是本迁移回归） |
| PR2 | `mcp/` → `apps/mcp/` | 0.25–0.5 | **代码已完成，待 CI 验证**：`cli` job 与 `build.yaml:mcp` 绿；affected 能命中 mcp |
| PR3 | `client/` → `apps/mobile/` | 0.5 | **代码已完成，待 CI 验证**：`client.yml quality` 绿；用 `workflow_dispatch` 验证 Android release；affected 能命中 mobile。本地已验：`apps/mobile` 下 `tsc --noEmit` 0、jest 13 suites / 114 例全过；`android/` 与 `package-lock` 随目录移动，Jest/Metro 配置为相对路径无需改 |
| PR4 | `frontend/` → `apps/web/` | 0.5–1 | **代码已完成，待 CI 验证**：`build` job 中 frontend typecheck/test/build 绿；`package` Docker 构建与 smoke 绿。本地已验：`apps/web` 下 typecheck 0、`test:ci` 19/19、`build` 成功；镜像内 `app/frontend/out` 与 `FrontendController` 的 `frontend/out` 默认值均不受源码目录迁移影响 |
| PR5 | `client-next/` → `apps/desktop/` | 1 | **代码已完成，待 CI 验证**：Gitea `client-next-test` 绿（261 例）；本地 layering/no-SDL/state-write/image-decode 守卫需在 push 后跑。已同步：`cjpm.toml` 与 `build.cj` 的 `../packages` → `../../packages`（17+25 处）、`cjpm.lock` 无路径、守卫脚本与基线、`deps-rules.toml`、Gitea/GitHub workflow、xtask fixture |
| PR6 | 根 `src/` + manifest → `apps/server/` | 1–2 | `orm-test`、`server-test` 12/12 0 skip、`build` + lcodec、`package` Docker/smoke/`.so.9.11`、`mcp`、`extension` 全绿；doctor 和守卫绿 |

总估算为 4–6 人日，不含 CI 排队和首波路径遗漏调试。

## 5. 执行顺序与规则

执行顺序固定为：

1. PR0：迁移方案落档。
2. 等待桌面 261 例绿基线。
3. PR1：extension。
4. PR2：mcp。
5. PR3：mobile。
6. PR4：web。
7. PR5：desktop。
8. PR6：server。

每个迁移 PR 必须满足：

- 只做 `git mv`、路径引用、path filter、artifact path、manifest 相对路径和必要守卫映射更新；
- 不改变依赖版本、锁文件策略、构建行为、运行时行为或公共接口；
- 不合并多个端的迁移；
- 不把移动目录与功能修复混在同一 PR；
- 使用非 force push；
- CI 未出结论前不开下一个迁移 PR。

## 6. 回滚

每个 PR 只包含一个端的路径迁移。失败时可直接 revert 对应提交，避免影响其他端。服务端 PR6 因为涉及根 manifest 和主构建链，必须在单独分支验证通过后才能进入 main。
