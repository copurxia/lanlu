# 兰鹿四端测试与自动化维护路线图

> 状态：方案已通过“现状盘点 → 能力调研 → 架构设计 → red-team → 文档核验”五道工序。本文是后续实施与验收的基线文档。

**TL;DR**
现状是“测试能力够用、执行链不完整”：服务端根包、MCP、Web 与桌面 Windows 的关键测试没有真正进入 CI，且工具链、lock、未跟踪依赖让结果难以绑定到固定提交。
| 阶段 | 一句话目标 | 量化退出线 |
|---|---|---|
| Phase 0 | 先让构建和测试可复现 | 新 clone 可构建；工具链与 lock 唯一；无未跟踪必需依赖 |
| Phase 1 | 统一入口，让已有测试真跑 | 服务端 12、桌面 261、移动 32、MCP 30、lcodec 17、Web 至少 4 个现有用例进入 CI |
| Phase 2（2A+2B） | 补契约与四端 P0 空白 | 2A 契约 6–8 人日，2B 四端 14–20 人日；P0 模块逐项有确定性测试 |
| Phase 3 | 分层门禁与 nightly | PR p50 ≤12 分钟；nightly ≤60 分钟；依赖闭包自动触发 |
| Phase 4 | E2E、设备、性能与 ratchet | 关键路径 nightly 稳定；覆盖率和性能有基线门禁 |
三个立即行动项：① 先做 Phase 0，收敛工具链、lock、嵌套仓和分支头克隆；② 建 `justfile` + Python `tools/xtask`，让现有测试真跑；③ 固定 `summary.json` 与 XML 适配层，之后的 CI、AI 修复和覆盖率都复用它。

**版本脚注**：本文引用的 cjpm/unittest 能力，除特别说明外，锚定 **cjpm 1.2.0 手册 / std 1.0.5 文档**。桌面 CI 当前实际安装 Cangjie 1.1.3（`.github/workflows/client-next.yml:143`），manifest 另写 1.1.0（`client-next/cjpm.toml:2`），服务端为 1.2.0（`.github/workflows/build.yml:40`），版本事实源为 `toolchain/versions.toml`。因此 Phase 0 必须对 1.1.3 做一次实测，确认 `--include-tags`、`--parallel`、`--coverage` 与 `prop_test` 的行为与文档一致；确认前，不把新能力写成硬门禁。

## 1. 背景与问题

### 1.1 四端与 CI 的现状

| 端 | 现有测试资产 | CI 真实执行情况 | 主要缺口 |
|---|---|---|---|
| 服务端 | 5 个测试文件、12 个 `@Test`，位于 `src/contexts/archive/domain/`、`src/infrastructure/kv/`、`src/shared/config/` | 根包 `cjpm test` 已由独立 `server-test` job 执行（`.github/workflows/build.yml:90`，待 CI 实测）；子包 csorm / pg-driver 为 `:78`、`:84` | routes/controller/auth/migration/WASM host/DTO 基本零测试；无 HTTP 集成与 E2E |
| 桌面端 | 29 个测试文件、261 个 `@Test`，集中在 `client-next/src/net/`、`app/`、`ui/`、`storage/`、`img/`、`i18n/` | Linux 执行 `cjpm test --parallel nCores --timeout-each 60s --report-format xml`（`.github/workflows/client-next.yml:342`）；Windows 只执行 `rocksdb_ffi`（`:529`） | `model.cj` 状态机、主 API 客户端、离线恢复、UI 关键路径与真实交互 E2E 缺失 |
| Web | 3 个测试文件、19 个用例 | 已执行 frozen install + typecheck + test:ci（`.github/workflows/build.yml:323`、`:328`、`:333`），随后 build（`:338`） | 19 例已全部迁移到 Vitest 并接入 CI（`frontend/package.json:7` 起有 `typecheck`/`test`/`test:ci`）；仍无组件交互与 E2E 测试 |
| 移动端 | 8 个测试文件、32 个用例，Jest | **执行 `npm test -- --runInBand`**（`.github/workflows/client.yml:60`） | 6 个 offline store、`api/lanlu.ts`、`api/admin.ts`、session/storage、25 个 screen 缺测试；无 Detox/Maestro E2E |
| extension | 0 | 只 build + typecheck（`.github/workflows/extension.yml:29`、`:34`） | 单测、浏览器 API fake、扩展 E2E 全缺 |
| MCP | 6 个文件、30 个 Rust 用例 | **只执行 `cargo build`**（`.github/workflows/cli.yml:35`） | 有测试但不运行；无 stdio/tool 集成测试 |

服务端根 `cjpm.toml`、桌面 `client-next/cjpm.toml`、Web `frontend/package.json`、移动 `client/package.json` 是四端各自的构建事实源；目前没有统一的本地/CI 任务入口。

### 1.2 可复现性缺陷会污染测试结论

- `packages/cangjie-gui` 是独立 Git 仓库且被 `.gitignore:26` 隐藏；CI 通过 `git clone --branch lanlu-client-next` 取分支头（`.github/workflows/client-next.yml:207`；Windows 侧 `:424`），不是固定提交，README 对“固定提交”的描述与实际不一致。
- 本轮审计时 `packages/lbase`、`packages/lwindow/src/backend/`、`packages/lwindow/src/displays/` 曾为未跟踪路径；现已由 HEAD `b25f846` 跟踪（分别为 6、1、3 个文件），干净 checkout 不再缺少这些路径。Phase 0 仍需用干净 clone 验证完整性，而不是重新跟踪。
- 根 `cjpm.lock` 不是空文件：`[requires]` 锁了 14 条 git 依赖的 commitId（8 直接 + 6 传递），但整体是 v0 旧格式（`version = 0`）；`client-next/cjpm.lock` 及其余 21 个包 lock 为空属正常态——纯 path 依赖不生成锁条目。服务端 CI 执行 `cjpm update`（`.github/workflows/build.yml:176`，其后 `:177` 为 lock 漂移守卫），仍不是只读安装。实测（Codex 用 1.2.0 在全新 `HOME` 与空 `~/.cjpm` 的冷缓存下执行）：`cjpm update` 退出码 0，`cjpm.lock` SHA256 不变（`1594a8b6…d8f21417`），`version` 仍为 `0`，14 条 commitId 全部未漂移——1.2.0 既不自动升级 v0→v1，也不刷新已锁 commit。
- 工具链三处不一致：服务端 1.2.0、桌面 CI 1.1.3、桌面 manifest 1.1.0。
- 桌面路径白名单（`.github/workflows/client-next.yml:5`）至少漏掉 10 个实际被依赖的包或 FFI 包，修改 `lbase`、`lcodec`、`lwindow` 等不会触发桌面测试。
- `cangjie-repo.toml` 只是中心仓 registry 配置，与工具链版本无关；它不应出现在工具链裁决或测试缓存 key 的核心语义里。

### 1.3 测试能力不是瓶颈

仓颉/cjpm 已具备过滤、标签、并行、超时、XML 报告、覆盖率、mock、参数化/属性测试和 bench 基线对比。真正的限制有三类：流水线未接入；设备侧缺少官方自动化驱动；本仓部分内部依赖尚未接口化，导致测试替身无法注入。

## 2. 目标与非目标

### 2.1 目标

1. 新同学执行 `git clone` 后，只需 `just setup && just build`，不手工 clone 依赖。
2. 本地与 CI 共用同一任务入口和同一套退出码。
3. 已有测试先真正执行，再补空白；覆盖率先采基线，再 ratchet。
4. PR 只承担快速、确定性的 L0–L3；慢测试下沉 nightly/release。
5. 所有机器结果可落到 `summary.json`，失败可定位到 target、test_id、文件与行号。
6. Windows、OHOS 按可兑现的能力分档，不承诺“全平台自动全绿”。

### 2.2 非目标

- 短期不引入 mutation testing。
- 不建设“一套平台统管四端 E2E”的重型方案；先用各端原生工具。
- v1 不用仓颉重写 xtask；仓颉版只保留给后续需要类型系统、测试运行时或包图深度集成的任务。
- 不在本轮把 OpenAPI 3.0 升级为 3.1；3.1 单独立项。
- 不把 `frontend`、`extension`、React Native `client` 的 pnpm workspace/包管理器迁移与测试门禁混做；RN 迁移风险高，延后。
- 不要求所有服务端 context 立刻完成 repository 接口化；“真 Postgres + `handleForTest`”先落地，接口化单列前置改造。
- 不把 OHOS 设备测试写成 PR 自动门禁；只承诺 TestClass 粒度可跑和 release 前置检查。

## 3. 决策记录

| ID | 决策 | 理由与边界 |
|---|---|---|
| D-01 | v1 的 `tools/xtask` 用 Python 实现 | 解决 bootstrap：`setup/doctor` 必须在仓颉工具链缺失时仍能运行；CI 已依赖 Python；Windows 行为比 shell 稳定。要求 Python ≥3.11，CI 显式固定 3.12 |
| D-02 | Python xtask 只做编排与守卫 | 包图、任务选择、报告汇总、依赖守卫、退出码归 xtask；具体测试逻辑留在各端原生框架。`setup/doctor` 永久保留非仓颉实现 |
| D-03 | 仓颉版 xtask 作为远期候选 | 保留给三类任务：需要包图/类型系统耦合的分析；需要与测试运行时同进程的 reporter/覆盖合并/fixture 生成；长期替代 Python 编排层 |
| D-04 | PR 门禁固定为 L0–L3 | L0 全局；L1/L2 按 affected 包；L3 契约变更必跑。L4/L5 不进 PR |
| D-05 | 工具链单一事实源放 `toolchain/` | 允许按 target 声明例外：server 1.2.0，desktop 暂留 1.1.x。`xtask doctor` 校验 workflow、manifest、lock 与事实源一致。Phase 0 做一次 desktop 升 1.2.0 的验证性构建，成功则消除例外 |
| D-06 | 覆盖率先测基线，再 ratchet | 禁止现在拍 70%。先出报告，再按包锁 baseline，最后对增量/核心包阻断。`--branches` 只报告 |
| D-07 | Windows/OHOS 分档承诺 | Windows 承诺编译 + FFI 子集 + 无 GUI 冒烟；OHOS 主机逻辑自动化，设备侧 TestClass 粒度 + `ability_delegator`（SA 65866）就绪性前置检查 + release 人工清单。后者仅单例社区报告，未证实为普遍约束 |
| D-08 | 契约复用 ignite，而不是另写一套描述 | 用 `app.interfaceSpecs()` + `SwaggerGenerator` 导出；先接受 OpenAPI 3.0.0，3.1 升级单独立项 |
| D-09 | 服务端 L2 用同进程真实 HTTP + 真 Postgres | 抽出 `bootstrapForTest()`，调用 `handleForTest`。controller 当前直接依赖静态 DAO，不能假装已有 fake repository 缝隙 |
| D-10 | 统一报告消费层 | `summary.json` 是 CI、PR 评论和 AI 自诊断的机器接口；cjpm XML 非 JUnit 同构，必须自建适配器 |
| D-11 | pnpm 版本先统一到 10.33.0 | `frontend/package.json:6` 与 `extension/package.json:6` 已声明 10.33.0，`extension.yml:19` 已在工作树改为 10.33.0；workspace 迁移另开 PR |

## 4. 测试分层与矩阵

### 4.1 L0–L5

| 层 | 测什么 | 工具 | 单次预算 | 触发 | 进 PR |
|---|---|---|---|---|---|
| L0 静态/契约 | 格式、lint、类型、依赖白名单、生成物无 diff、OpenAPI breaking diff | `cjfmt`、`cjlint`、`tsc`、eslint、`cargo fmt/clippy`、`xtask check` | ≤2 分钟 | 每 PR | 是，全局 |
| L1 单测 | 纯函数、DTO、状态机、重试/超时、解析器；禁真实网络与时钟 | `cjpm test`、Jest、Vitest、`cargo test` | ≤5 分钟/分片 | PR、merge queue、nightly | 是，按包 |
| L2 模块集成 | 路由 + 真 PG、鉴权中间件、迁移、临时目录存储、fake HTTP | `cjpm test`、Postgres service、MSW、Jest fake timers | ≤12 分钟/分片 | PR、merge queue、nightly | 是，按模块 |
| L3 跨端契约 | wire fixture、DTO 双向序列化、版本兼容 | OpenAPI JSON、golden fixtures、`xtask contract` | ≤3 分钟 | PR、nightly | 是，契约变更必跑 |
| L4 系统冒烟 | 桌面 Xvfb/Weston、Web Playwright、Android debug 启动、MCP stdio | Xvfb、Weston、Playwright、Detox、`cargo run` | 45–60 分钟 | nightly、release | 否 |
| L5 设备/性能 | OHOS 真机、Windows GUI、GPU、soak、benchmark | `hdc`、Windows runner、lavapipe、`cjpm bench` | 90–120 分钟 | nightly 可选、release | 否 |

### 4.2 服务端与桌面端矩阵

图例：CI = 当前真实执行；有 = 有测试但未执行；坏 = 有测试但不可运行；无 = 零测试。

| 端/模块 | L0 | L1 | L2 | L3 | L4 | L5 | 阶段 |
|---|---|---|---|---|---|---|---|
| 服务端 routes/controller | route 清单/OpenAPI diff｜无 | handler 纯逻辑、DTO 序列化｜`cjpm test`｜无 | `bootstrapForTest` + `handleForTest` + 真 PG｜无 | 响应 golden fixture｜无 | 黑盒 API 冒烟｜无 | 负载/soak｜无 | Ph2 |
| 服务端 auth/session | 权限矩阵 lint｜无 | token 过期/刷新/撤销｜无 | 401/403 中间件集成｜无 | cookie/header fixture｜无 | 登录链路 E2E｜无 | — | Ph2 |
| 服务端 migrations | 顺序/lint｜无 | 版本解析｜无 | 空库 up/down + 事务｜无 | schema snapshot｜无 | 空库启动｜无 | 升级 soak｜无 | Ph2 |
| 服务端 WASM host/plugin | capability manifest｜无 | 沙箱边界单测｜无 | wasm fixture host｜无 | host ABI fixture｜无 | 插件 E2E｜无 | fuzz/soak｜无 | Ph2 |
| 服务端 DTO/interfaces | OpenAPI diff｜无 | 序列化单测｜无 | 路由响应快照｜无 | golden fixtures｜无 | — | — | Ph2 |
| `csorm`/`postgresql-driver` | schema lint｜部分 | 24 + 87 例｜CI | PG container｜部分 | — | 启动冒烟｜无 | — | Ph1/Ph2 |
| 桌面 `net/` | DTO/API lint｜无 | 重试/超时/假时钟｜`cjpm test`｜14 个测试文件 | fake HTTP server｜无 | 服务端 fixture｜无 | — | 断网 soak｜无 | Ph2 |
| 桌面 `app/model.cj` | 状态枚举 lint｜无 | 登录/切服/上传/taskpool 状态机｜无 | fake net/storage｜无 | — | headless 场景｜无 | — | Ph2 |
| 桌面 storage/offline | schema/version｜无 | 临时目录 CRUD｜部分 | 崩溃/重启恢复｜无 | schema fixture｜无 | — | 长时 soak｜无 | Ph2 |
| 桌面 ui reader/library/login | `cjlint`｜仅报告 | helper/logic｜5 个测试文件 | widget 状态｜无 | — | Xvfb snapshot/Weston｜部分 | 视觉差异/性能｜无 | Ph3/Ph4 |
| 桌面 lcodec/lwindow/lgpu | ABI/符号｜部分 | 17/47 等现有例｜部分 | stub FFI/离屏渲染｜部分 | 协议 fixture｜无 | render smoke｜部分 | GPU/真机｜无 | Ph1/Ph4 |

### 4.3 Web、移动端、extension、MCP 矩阵

| 端/模块 | L0 | L1 | L2 | L3 | L4 | L5 | 阶段 |
|---|---|---|---|---|---|---|---|
| Web layout hooks | `tsc`/eslint｜无 | 4 例 `node:test` 可跑；3 例 vitest 坏 | RTL 组件测试｜无 | — | Playwright｜无 | 性能｜无 | Ph1/Ph4 |
| Web unified-menu | `tsc`/eslint｜无 | 12 例 vitest 坏 | RTL 交互｜无 | — | Playwright｜无 | — | Ph1/Ph2 |
| Web 页面/API client | typecheck｜无 | 无 | MSW 网络 mock｜无 | OpenAPI fixture｜无 | 关键路径 Playwright｜无 | — | Ph2/Ph4 |
| 移动 offline stores | eslint/tsc｜CI | 6 个 store｜无 | fake timers/队列重放｜无 | — | Detox｜无 | 电池/soak｜无 | Ph2 |
| 移动 api/lanlu.ts/拦截器 | typecheck｜CI | 1186 行客户端｜无 | axios mock/MSW｜无 | fixture｜无 | Detox｜无 | — | Ph2 |
| 移动 screens | typecheck｜CI | 仅 4 个 reader helper｜CI | 渲染测试｜无 | — | Detox｜无 | — | Ph2/Ph4 |
| extension | typecheck/build｜CI | 0 | 浏览器 API fake｜无 | — | 扩展 Playwright｜无 | — | Ph2/Ph4 |
| MCP | `cargo fmt/clippy`｜无 | 30 例存在｜CI 不跑 | stdio/tool 集成｜无 | tool schema｜无 | 客户端冒烟｜无 | — | Ph1/Ph2 |

### 4.4 桌面三档

| 档位 | 范围 | 门禁 |
|---|---|---|
| Linux 全量 | L0–L3 全部桌面测试；L4 Xvfb/Weston 冒烟 | PR 跑 affected L1/L2；nightly 跑全量与 headless 冒烟 |
| Windows 子集 | L0 编译/格式；`rocksdb_ffi` 现有 10 例；后续最多扩到可离屏的纯逻辑包 | nightly/release；**不承诺 GUI 自动化** |
| OHOS 手工门禁 | 主机侧纯逻辑用 `cjpm test`；设备侧 TestClass 粒度结果与清单；`ability_delegator`（SA 65866）就绪性检查（仅单例社区报告，未证实为普遍约束） | release 前置检查；**不承诺 PR 自动全绿** |

## 5. CI 架构

### 5.1 四条流水线

| 流水线 | 触发 | 内容 | 预算 | required |
|---|---|---|---|---|
| PR 快速门禁 | 所有 PR；仅 docs/`*.md` 可 `paths-ignore` | L0 全局；L1/L2 受影响包；L3 契约 | p50 10–12 分钟，p95 ≤15 | 单一 `ci-required` 聚合 |
| Merge queue | `merge_group` | 同 PR，强制受影响 L2 | ≤18 分钟 | 同一聚合检查 |
| Nightly | 每日定时 + 手动 | 全量 L0–L4、覆盖率、Windows 子集、Web E2E、Android debug、MCP | 45–60 分钟 | 失败通知，不阻塞 PR |
| Release | tag/手动 | 全量、签名产物、OHOS 人工清单、性能/bench | 90–120 分钟 | release gate |

### 5.2 affected 依赖闭包

测试 workflow 不再手写 `paths` 白名单。每个 PR 先跑轻量 `plan` job：

1. `python3 -m tools.xtask affected --base <sha>` 读取 `cjpm.toml`、`Cargo.toml`、`package.json`、lock 与 path 映射。
2. 建包图，按依赖反向闭包。示例：`lbase` → `lgpu/lwindow/portcheck/client-next`；`lcodec` → `portcheck/client-next`；`lwp` → `lwindow`。
3. 输出 `plan.json` / `matrix.json`，GitHub `fromJSON` 直接消费。
4. 守卫：path 依赖目标不存在或未被 Git 跟踪，`xtask affected` 直接失败。

至少纳入以下曾被漏掉的依赖：`lbase`、`lcodec`、`lwindow`、`lwp`、`lgpu`、`portcheck`、`lplatform-ohos`、`lplatform-wayland`、`lpack-ohos`、`sdl_stub_ffi`。以后新增包只改 manifest，不改 workflow 清单；依赖图缓存到 job artifact，允许一键回退“全量模式”。

### 5.3 缓存、产物与并发

| 项 | 规则 |
|---|---|
| Cangjie 缓存 | `key = cangjie-${os}-${hashFiles('**/cjpm.lock','**/cjpm.toml')}-${matrix.pkg}`；**不放 `cangjie-repo.toml`** |
| Node 缓存 | pnpm store 按各自 lock；npm 按 `client/package-lock.json` |
| Rust 缓存 | 按 `**/Cargo.lock` 与 `rust-toolchain.toml` |
| 产物 | `test-results/**/*.xml`、`coverage/{merged.json,html,xml}`、`screenshots/{actual,expected,diff}`、`summary.json`、`logs/*.log` |
| 并发 | `concurrency.group = ci-${pr_number || ref}`，`cancel-in-progress: true` |
| fork PR | 仅 GitHub-hosted runner；不注入 secrets；不做签名发布 |
| required | `ci-required` 只读取 `summary.json` 和 job 结果，不承载业务测试 |

### 5.4 可执行骨架

```yaml
# PR 门禁（伪代码）
on:
  pull_request:
    paths-ignore: ["docs/**", "**/*.md"]
  merge_group:
concurrency:
  group: ci-${{ github.event.pull_request.number || github.ref }}
  cancel-in-progress: true
jobs:
  plan:
    runs-on: ubuntu-24.04
    outputs:
      matrix: ${{ steps.p.outputs.matrix }}
    steps:
      - uses: actions/checkout@v4
        with: { fetch-depth: 0 }
      - id: p
        run: |
          python3 -m tools.xtask affected --base "${{ github.event.pull_request.base.sha || 'HEAD^' }}" > plan.json
          echo "matrix=$(cat plan.json)" >> "$GITHUB_OUTPUT"
  static:
    runs-on: ubuntu-24.04
    steps:
      - run: python3 -m tools.xtask lint --layer L0
  cangjie:
    needs: plan
    if: fromJSON(needs.plan.outputs.matrix).cangjie != '[]'
    strategy:
      matrix:
        pkg: ${{ fromJSON(needs.plan.outputs.matrix).cangjie }}
    runs-on: ubuntu-24.04
    steps:
      - run: python3 -m tools.xtask test --layer L1 --package "${{ matrix.pkg }}"
  clients:
    needs: plan
    if: fromJSON(needs.plan.outputs.matrix).clients != '[]'
    strategy:
      matrix:
        target: ${{ fromJSON(needs.plan.outputs.matrix).clients }}
    runs-on: ubuntu-24.04
    steps:
      - run: python3 -m tools.xtask test --layer L1-L2 --target "${{ matrix.target }}"
  contracts:
    runs-on: ubuntu-24.04
    steps:
      - run: python3 -m tools.xtask contract check
  required:
    if: always()
    needs: [static, cangjie, clients, contracts]
    runs-on: ubuntu-24.04
    steps:
      - run: python3 -m tools.xtask gate-result '${{ toJSON(needs) }}'
```

`clients` 是 Web、Mobile、extension、MCP 的统一 affected job；`xtask` 根据 target 选择 Jest、Vitest、TypeScript、Cargo 等原生命令，并在 L1/L2 内执行受影响测试。

```yaml
# Nightly（伪代码）
on:
  schedule: [{ cron: "30 20 * * *" }]
  workflow_dispatch:
jobs:
  full:
    strategy:
      matrix:
        shard: [server-pg, desktop-headless, windows-subset, web-e2e, mobile-jest, mcp-rust]
    runs-on: ${{ matrix.shard == 'windows-subset' && 'windows-2025' || 'ubuntu-24.04' }}
    steps:
      - run: python3 -m tools.xtask nightly --shard "${{ matrix.shard }}"
  coverage:
    runs-on: ubuntu-24.04
    steps:
      - run: python3 -m tools.xtask coverage --ratchet
  summary:
    if: always()
    needs: [full, coverage]
    steps:
      - run: python3 -m tools.xtask gate-result '${{ toJSON(needs) }}'
```

### 5.5 预算

| 档位 | 并发 job | 冷启动 p50 | p95 | runner 峰值 |
|---|---:|---:|---:|---:|
| PR | 7 | 10–12 分钟 | 15 分钟 | 8 |
| Merge queue | 8 | 12 分钟 | 18 分钟 | 9 |
| Nightly | 9 | 45–55 分钟 | 60 分钟 | 10 |
| Release | 10 | 90–120 分钟 | 150 分钟 | 12 |

## 6. 契约测试

### 6.1 现有基础与结论

服务端已经使用 ignite，并在 `src/main.cj:230` 开启 `enableSwagger: true`。ignite 提供 `app.interfaceSpecs()`（`~/.cjpm/git/ignite/887723.../src/app.cj:314`）和 `SwaggerGenerator.generate()`（`~/.cjpm/git/ignite/887723.../src/swagger.cj:269`），`RouteOption` 支持 summary、tags、parameters、requestBody、responses、security（`swagger.cj:6`）。

但当前契约是空壳：137 个路由没有任何 `RouteOption`/`withResponse`/`withRequestBody`；响应大量使用 `ctx.json`/`JsonRaw`；生成器在无 responses 时写死 `200 OK`（`swagger.cj:433`），并写死 `"openapi": "3.0.0"`（`swagger.cj:272`）。全仓共有 39 个 `<: JsonSerializable` 响应 DTO 和 23 个 `<: JsonDeserializable` 请求 DTO；响应 DTO 均手写 `toJson`，例如 `src/shared/views/api_response.cj:21`。

**决策**：契约单一事实源复用 ignite 的路由元数据和生成器，不在仓库里另维护一份 controller 描述；先接受 OpenAPI 3.0.0，3.1 单独立项。

### 6.2 导出方向与目录

```text
contracts/
├── openapi/lanlu.v1.json          # 生成物，入库并做 diff
├── fixtures/v1/
│   ├── auth/login.request.json
│   └── auth/login.response.json
├── generated/ts/api.d.ts          # openapi-typescript 生成
├── generated/cj/contract_ids.json # 仓颉侧契约 ID/版本映射
└── reports/breaking.json
```

生成链：`tools/contract-export` 调 `Routes.register(app)` → `app.interfaceSpecs()` → `SwaggerGenerator`，不需要数据库。TS 从 OpenAPI 生成类型；桌面 `dto.cj` 先保留手写，但必须通过同一批 fixture 的双向序列化测试，稳定后再评估生成仓颉 DTO。

### 6.3 版本、失败形态与工作量

- v1 只允许追加字段；删字段/改类型必须升 v2，服务端双版本并存；CI 用 `oasdiff breaking` 阻断。
- 失败信息必须机器可读：`pointer=/data/items/0/id expected=string actual=number fixture=contracts/fixtures/v1/...`。
- golden fixture 是 wire 行为锁，OpenAPI 是 schema 源；两者都不能省。

| 工作项 | 人日（1 人） |
|---|---:|
| 契约导出器：`Routes.register` → `interfaceSpecs()` → `SwaggerGenerator` | 1.5–2 |
| 137 个路由补 `RouteOption` 或维护路由清单并做集合相等守卫 | 3–4 |
| 39 个响应 DTO + ad-hoc view/raw JSON 的 response schema（23 个请求 DTO 的 fixture 校验另计） | 5–7（全量 response 口径） |
| OpenAPI 3.1 支持：改 ignite fork 或后处理 | 0.5–1 |
| 关键端点 request/response fixture + 双端反序列化 | 3–5 |

P0 端点（auth/archive/search/tankoubon/asset，约 40 条）先做：**6–8 人日**；137 条全量：**12–16 人日**。3.1 不在 P0 范围内。

## 7. 覆盖率与性能

### 7.1 覆盖率先基线后门禁

当前覆盖率基线不可信：服务端根 `cjpm test` 未在 CI 执行，Web 15 个用例不可运行。顺序必须是：

1. Phase 1 让所有现有可运行测试进入 CI。
2. 首次采集按包 baseline，只报告，不阻断。
3. Phase 3 按包锁 baseline，启用 ratchet。
4. Phase 4 对核心包和变更行阻断，外围包保持包级 ratchet。

### 7.2 采集与合并

- v1 覆盖率作业按包执行，**不使用 `--parallel`**；`cjpm test --coverage` 产生原始数据，`cjcov --root=./ --html-details -o html_output` 生成报告。
- “多轮 capture 取行并集”目前只是社区实践，官方未确认；`-k` 保留中间文件会导致执行次数累加并影响准确性。Phase 2 必须实测后再决定是否合并、如何合并。
- `--branches` 是实验特性，只进报告，不阻断。
- 门禁公式：`threshold(pkg) = baseline(pkg) - 0.5pp`。核心包 `net/storage/decode/protocol` 额外要求变更行覆盖；外围包只做包级 ratchet。
- 新增核心包若无覆盖率数据，直接失败，避免“新包绕过门禁”。

### 7.3 性能

`@Bench` + `cjpm bench --baseline-path` 作为 nightly/性能任务；基线入库，退化超过阈值失败。GPU、OHOS、Windows GUI 性能只做 release 记录，不进 PR。

## 8. xtask 设计

### 8.1 形态与边界

```text
justfile                 # 薄入口：setup/ci/test/lint/contract/coverage/nightly
tools/xtask/             # Python 3.11+ 标准库包；不做业务测试实现
├── __main__.py          # 命令路由与退出码
├── affected.py          # 包图、依赖闭包、path_map
├── test.py              # 选择 target、调用各端测试、收集 XML
├── contract.py          # 导出/openapi diff/fixture 校验
├── coverage.py          # 按包采集、报告、ratchet
└── report.py            # summary.json、XML 适配器、gate-result
```

`setup/doctor` 永久留在非仓颉侧；Python 只做编排与守卫。`tools/` 现有脚本已使用 `tomllib`，最低 Python 3.11；CI 必须加 `actions/setup-python` 固定 3.12，并在 `xtask doctor` 校验版本。

### 8.2 命令清单

| 命令 | 语义 |
|---|---|
| `just setup` | `xtask doctor` + 构建 native、pnpm install、校验 SDL/vips；工具链缺失时先给安装指引 |
| `just ci` | 本地与 CI 唯一入口，串起 L0–L3 |
| `just test` | 默认 `xtask test --changed` |
| `just lint` | `cjlint` + `cjpm build -l` + eslint + `tools/check-*.py` |
| `just contract` | `xtask contract check` |
| `just coverage` | `xtask coverage --ratchet` |
| `just nightly` | `xtask nightly`，按 shard 运行 |

xtask 子命令至少包括：`doctor`、`setup`、`affected`、`build <target>`、`test <layer> [--changed]`、`lint`、`fmt --check`、`contract check`、`coverage [--ratchet]`、`bench [--baseline]`、`nightly --shard`、`gate-result`。

### 8.3 报告契约

`summary.json` 是稳定接口，至少包含：

```json
{
  "version": 1,
  "run_id": "pr-123-abcd",
  "status": "failed",
  "layers": ["L0", "L1", "L3"],
  "duration_ms": 412000,
  "targets": [
    {
      "target": "client-next",
      "tool": "cjpm",
      "status": "failed",
      "total": 261,
      "passed": 258,
      "failed": 2,
      "skipped": 1,
      "flaky": 0,
      "report": "target/test-results/client-next.xml",
      "failures": [
        {
          "test_id": "net.lanlu_api_test.timeout",
          "kind": "assertion",
          "message": "expected retry_count=3, actual=2",
          "file": "client-next/src/net/lanlu_api_test.cj",
          "line": 88
        }
      ]
    }
  ]
}
```

**cjpm XML 非 JUnit 同构，`summary.json` 消费层必须自建适配器**；不能直接喂标准 JUnit 解析器。退出码约定：0 通过；1 测试断言失败；2 配置/依赖/工具链错误；3 基础设施失败；4 被 quarantine 且不阻塞；未知错误统一非零并在 summary 标 `kind=internal`。

## 9. 工程规范

### 9.1 测试与 fixture

| 规范 | 要求 |
|---|---|
| 仓颉测试位置 | 只允许 `src/**/*_test.cj`；`test/` 目录不会被 cjpm 发现。新增测试必须能被对应 `cjpm test` 选中 |
| 标签 | `Smoke`：PR 快速；`Integration`：需要 fake service/container；`Slow`：nightly；`Device`：真机/模拟器；`Quarantine`：带 owner 和到期日期 |
| 单测边界 | 禁真实网络、真实时钟、随机顺序依赖、全局可变状态；时间注入 clock；网络用 fake transport/HTTP server；随机固定 seed |
| fixture | golden fixture 只放 `contracts/` 或包内 `fixtures/`；禁止写仓库源码路径；临时文件用 test-scoped 目录并在 teardown 清理 |
| DB | 每 case 独立 schema 或事务回滚；迁移测试从空库 + fixture SQL 开始；禁止依赖前一个测试的状态 |
| 快照 | 快照入库；更新必须单独说明；CI 不自动提交；本地需显式 `SNAPSHOT_UPDATE=1` 后 review diff |
| 服务端 L2 | `bootstrapForTest()` 初始化连接池/迁移；`handleForTest` 走真实 TCP 与完整中间件；repository 接口化作为后续前置改造，不用假 DAO 冒充 |

### 9.2 AI 代理提交前条款

建议写入 `AGENTS.md` / `CLAUDE.md`：

```text
提交前必须：
1. 改动后运行 `python3 -m tools.xtask fmt --check`、`lint --changed`、`test --changed`。
2. 触碰 workflow、xtask、contracts、toolchain、依赖规则时，必须运行 `just ci`。
3. 失败先读 target/test-results/*.xml 与 summary.json，按 test_id/file/line 定位。
4. 禁止用 skip、注释断言、降低阈值来“修复”失败；quarantine 必须带 owner 和到期日。
5. 不得修改 .gitignore 隐藏必需依赖，不得新增嵌套 Git 仓库。
6. 不能确认基础设施失败时，不得把断言失败归因于 flaky。
```

### 9.3 lint 从 advisory 转 blocking

| 阶段 | 规则 |
|---|---|
| Phase 1 | `cjfmt`/`cjlint` 出机器可读报告，继续 advisory；现有问题建 baseline |
| Phase 2 | 新增文件必须通过格式/ lint；存量按包 baseline |
| Phase 3 | 按包 ratchet；触碰的包若恶化则失败 |
| Phase 4 | 核心包全量 blocking；例外必须 CODEOWNERS 审批并有到期日 |

### 9.4 自动化治理

- flaky：同一用例 24 小时内最多自动复跑一次；连续 2 次同结果才隔离。隔离必须带 owner、到期日、关联 issue。
- 覆盖率 ratchet：由 `xtask coverage --ratchet` 比较当前与 `coverage/baseline.json`，只允许上升或持平；下降需显式 `--allow-drop` 并记录理由。
- 工具链：`toolchain/` 单一事实源；workflow、manifest、lock 由 `doctor` 校验。`cjpm.lock` 必须入库；CI 中 `cjpm update` 仅作为依赖获取步骤保留（wasmedge 补丁依赖其先 clone），其后必须跑 `git diff --exit-code -- cjpm.lock`，漂移即失败。
- 文档一致性：`check-docs-consistency.py` 扩展校验命令、版本、路径真实存在。
- CODEOWNERS：保护 `.github/workflows/**`、`.gitea/workflows/**`、`tools/xtask/**`、`contracts/**`、`toolchain/**`、`justfile`、依赖规则文件。

## 10. 路线图

### 10.1 Phase 0 重审（HEAD `b25f846`）

| Phase 0 待办 | 状态 | 证据 | 剩余动作 |
|---|---|---|---|
| `packages/lbase`、`lwindow/src/backend/`、`lwindow/src/displays/` 缺失跟踪 | **已在 b25f846 解决** | HEAD 跟踪数分别为 6、1、3 | 用干净 clone 验证，不再重复跟踪 |
| `packages/cangjie-gui` 嵌套独立仓 | **仍待办** | 目录内存在 `.git`；Git 跟踪文件数 0；被 `.gitignore:26` 隐藏 | 收编或移除；CI 同步停止克隆。注意：`client-next/cjpm.toml` 与 `packages/portcheck/cjpm.toml` 以 path 依赖指向它；缺失时 xtask 默认记 `missing_path_dep` warning 并跳过该边，`--strict` 才升级为 error |
| lock 文件停留在 v0 旧格式 | **已定案（不迁移）** | 1.2.0 冷缓存实测：`cjpm update` 不升级 v0→v1、不刷新 commitId；lock SHA256 `1594a8b6…d8f21417` 不变 | 守卫定位改为“漂移探测器”而非“迁移门禁”：lock 保持 v0 可接受；若未来工具链改变行为，守卫会先红，届时按需显式解析并单独提交 |
| CI 克隆分支头而非固定提交 | **仍待办** | `.github/workflows/client-next.yml:207`、`:424` | 改固定提交/lock；同步修正 README |
| 工具链三处不一致 | **部分解决（工作树）** | 已建 `toolchain/versions.toml` 作为事实源；当前值：服务端 `build.yml:40` 1.2.0、桌面 CI `client-next.yml:143` 1.1.3、桌面 manifest `client-next/cjpm.toml:2` 1.1.0、根 manifest `cjpm.toml:2` 1.2.0 | 由 `doctor` 持续校验事实源与 workflow 一致；桌面升 1.2.0 仍待验证 |
| 无效 submodule 步骤 | **已解决** | 三侧均无 `submodules: true`：`.github/workflows/build.yml`、`.gitea/workflows/build.yaml`、`.cnb.yml`；仓库无 `.gitmodules` | 保持；新增嵌套仓守卫（待办） |
| 服务端 CI 执行 `cjpm update` | **已解决（守卫生效）** | 三侧 update 后均有 `git diff --exit-code -- cjpm.lock`：`build.yml:176`（守卫 `:177`，主构建 update `:296`/守卫 `:297`）、`.gitea/workflows/build.yaml:173`（守卫 `:174`）、`.cnb.yml:120`（守卫 `:121`）；冷缓存实测无漂移 | 保留 update（wasmedge 补丁依赖其先 clone）；若未来实测刷新 commitId，再把刷新作为显式提交 |
| 桌面 1.1.3 能力一致性未实测 | **仍待办** | 本文版本脚注所列四项能力 | Phase 0 实测 `--include-tags`、`--parallel`、`--coverage`、`prop_test` |
| xtask 接入 CI | **已接线（干净 checkout 实测通过）** | `.github/workflows/client-next.yml:53-61` 的 guards job 已加 `setup-python@v5`/3.12 与 `doctor --json`（`:58`）、`test --package xtask`（`:61`），均**不带 `--strict`** | 缺失 path 依赖默认 warning；`--strict` 留给 clone 出 `packages/cangjie-gui` 之后的完整树校验（如 nightly） |
| 服务端根包测试 job | **已接线（待 CI 实测）** | `.github/workflows/build.yml:90` 起 `server-test`：PG service + `DB_STRING` + `cjpm test --show-all-output --report-path`，输出含 `[skip]` 即失败（`--show-all-output` 在 `:192`，守卫 `:197`）；产物 `if: always()` 上传 | 首次实跑核对 PG 连通、原生库与 WasmEdge 前置；确认无静默跳过 |

Phase 0 退出标准只保留仍待办项：干净 clone 可构建；无嵌套 `.git`；`cjpm.lock` 守卫三侧生效且实测无漂移（lock 保持 v0 亦可）；`doctor` 通过且 CI 不 clone 分支头；无效 submodule 步骤移除；desktop 1.2.0 验证完成，或 target 例外有明确到期日。

**缺失 path 依赖策略**：path 依赖目标不存在时，xtask 默认记 `missing_path_dep: <pkg> -> <path>` warning 并跳过该边（`tools/xtask/graph.py:266-275`），`doctor` 退出 0、`affected` 与 `test --package` 仍能产出计划；`--strict` 才把该 warning 提升为 error（exit 2）。CI guards 使用默认容错模式；`--strict` 保留给已 clone `packages/cangjie-gui` 的完整树校验（如 nightly）。回归测试 `tools/xtask/tests/test_missing_dep.py` 用临时 git 仓模拟干净 checkout。

### 10.2 五阶段路线图

| 阶段 | 范围 | 角色 | 人日 | 退出标准 | 指标 | 回滚 |
|---|---|---|---:|---|---|---|
| Phase 0 可复现性前置 | 验证 b25f846 已跟踪完整性；处理嵌套仓；工具链单一事实源；lock 守卫三侧生效（不要求迁移 v1）；移除无效 submodule；desktop 1.2.0 验证构建 | 平台/构建 + 桌面 owner | 2–3 | 干净 clone 可构建；无嵌套 `.git`；lock 守卫生效且实测无漂移；doctor 通过；CI 不 clone 分支头；无效 submodule 移除 | 依赖完整性 100%；工具链版本唯一 | 每项独立 PR；工具链/lock 可单独 revert |
| Phase 1 统一入口 + 已有测试真跑 | `justfile` + Python xtask；服务端根测试、MCP `cargo test`、Web test runner、移动维持 Jest、`packages/lcodec` 17 例、XML + summary | 平台 + 各端 owner | 3–5 | 服务端 12、桌面 261、移动 32、MCP 30、lcodec 17 执行；Web 至少 4 例；summary 上传。若 lcodec 原生依赖阻断，必须在 issue 与 summary 中记录原因并显式延后 | 新增执行用例数；XML 上传率 100% | 可临时回落旧 workflow，但 required 保持旧命令 |
| Phase 2A 契约 | OpenAPI 3.0 导出、P0 约 40 条路由元数据、关键 request/response fixture | 契约 owner + 服务端 owner | 6–8 | 契约导出可运行；P0 端点 fixture 入库；3.1 有独立 issue | 契约 diff 接入；P0 fixture 覆盖率 | 导出器 non-blocking；3.1 不反向阻塞 3.0 |
| Phase 2B 其余四端 P0 | 服务端 HTTP/auth/migration/WASM/DTO；桌面 model/offline/net；移动 offline/api/拦截器；extension | 各端 owner | 14–20（并行） | 每个 P0 模块至少 1 个确定性测试；6 个 offline store 覆盖 | P0 空白清零；新增测试数 | 新测试先 non-blocking 一周 |
| Phase 3 分层门禁 + nightly | affected 闭包；PR L0–L3；merge queue；nightly Windows 子集、覆盖率基线、桌面 headless | 平台 owner + CI reviewer | 5–8 | 10 个漏包可正确触发；PR p50 ≤12 分钟；nightly ≤60 分钟；单一 required | 误触发/漏触发；PR p50/p95 | plan 支持全量兜底；新 required 观察一周 |
| Phase 4 E2E/设备/性能/ratchet | Web Playwright、桌面视觉/交互、移动 Detox、MCP stdio、bench、覆盖率阻断、OHOS 清单 | 各端 owner + QA | 10–15 | 关键路径 nightly 稳定；bench 有基线；核心包 ratchet；OHOS release 清单自动收集 | nightly 成功率、flaky 率、覆盖率增量 | E2E/ratchet 默认不阻塞 PR |

Phase 2 合计 **20–28 人日**（2A 6–8 + 2B 14–20）。

**串并行关系**：Phase 0 必须先完成；Phase 1 可在 Phase 0 的“工具链 + lock”独立 PR 后开始；Phase 2A 先定 schema/导出链，2B 可在契约骨架稳定后并行；Phase 3 必须等 summary 稳定；Phase 4 后半可与 Phase 3 并行，但不进 PR required。

## 11. 风险清单与未决问题

| 风险/未决项 | 影响 | 缓解 |
|---|---|---|
| 依赖闭包解析器漂移 | 漏触发或误触发 | v1 只解析已声明 path/workspace 依赖；结果入库为 `plan.json`；path 目标必须被 Git 跟踪；支持全量兜底 |
| PR 中跑 PG 不稳定 | 拖慢门禁、产生假失败 | 服务端拆 unit/db-integration shard；独立 schema；健康检查；只重试基础设施启动，不重试业务断言 |
| cjcov 合并未证实 | 覆盖率数字不可信 | v1 串行分包；“行并集”标为社区实践，Phase 2 实测后再定 |
| Windows/OHOS 不可全自动 | 承诺无法兑现 | 按 D-07 分档；OHOS release 前置检查 `ability_delegator`（SA 65866，仅单例社区报告）；不写入 PR required |
| flaky 与 agent 绕过 | 门禁失效 | 限制自动复跑；quarantine 有 owner/到期；CODEOWNERS 保护关键文件；AI 必须交 summary |
| 服务端静态 DAO | 当前无法 fake repository | 先 `handleForTest` + 真 PG；repository 接口化列为 §4/§10 的前置改造 |
| OpenAPI 3.0 与 3.1 | Alice 原方案过强 | 先接受 3.0.0；3.1 单独立项 |
| `cangjie-repo.toml` 误用 | 噪声缓存、错误版本源 | 从工具链事实源、缓存 key 语义和路径过滤中移除 |
| Python 版本分叉 | 本地/CI 行为不同 | doctor 要求 ≥3.11；CI `setup-python` 固定 3.12 |
| cjpm XML 非 JUnit | 报告解析错误 | 自建适配器；`summary.json` 是唯一消费接口 |
| lock 格式与工具链行为不一致 | 手册称解析时升级 v1；1.2.0 实测不升级，后人可能误以为可自动迁移 | 守卫三侧只报漂移不隐式更新；未来需升级时显式解析并单独提交（`--locked`/`--frozen` 文档未载） |
| 服务端 5 例 DB 测试静默跳过 | CI 无 PG 仍全绿，通过数虚高 | `server-test` job 提供 PG service，并以 `--show-all-output` + `grep -Fq '[skip]'` 硬失败（`.github/workflows/build.yml:90-207`） |
| `cjpm test` 默认吞测试 stdout | 通过的用例里 `println("[skip]")` 不进日志，skip 守卫会永远不触发 | 必须加 `--show-all-output`；Kimi 以 1.2.0 最小工程复现（默认 grep 计 0，加参数后计 1） |
| `--report-path` 语义是目录 | 按文件名传入会生成同名目录，产物错位 | 传目录；XML 落在 `<dir>/tests/test-<pkg>.<case>.xml`；Kimi 以 1.2.0 最小工程复现 |
| 1.1.3 能力未实测 | 新门禁可能幻觉 | Phase 0 实测 `--include-tags`、`--parallel`、`--coverage`、`prop_test` |
| 本机有 `packages/cangjie-gui`、CI 干净 checkout 没有 | 本地 `doctor`/`affected` 全绿、CI 曾因缺失 path 依赖误报 error（exit 2），门禁假红 | 缺失默认降级为 warning、`--strict` 才报错；`tools/xtask/tests/test_missing_dep.py` 用临时仓模拟干净 checkout 防止复发；行号以 grep 实测为准 |

## 12. 验收清单

### 12.1 对照用户原始诉求

| 用户诉求 | 本文对应章节 | 验收证据 |
|---|---|---|
| 分析移动、服务端、Web、桌面现状 | §1、§4 | 四端测试资产表、CI 执行事实、P0 空白矩阵 |
| 调研仓颉测试与工程化特性 | §2、§4、§7、§13 | L0–L5 能力映射、覆盖率/标签/mock/平台限制、官方来源 |
| 给出 xtask 方案 | §3、§8 | Python xtask 决策、边界、命令、summary 契约 |
| 建立全自动维护的测试与规范 | §3、§5、§9、§10 | 分层门禁、affected 闭包、AI 提交条款、五阶段路线图 |

### 12.2 技术与流程验收

- [ ] 新机器 `git clone` 后 `just setup && just build` 可构建，无需手工 clone 依赖。
- [ ] `git status` 干净；`find` 找不到嵌套 `.git`；`.gitignore` 不再隐藏必需依赖。
- [ ] CI 不使用分支头；`cjpm.lock` 守卫三侧生效且实测无漂移（保持 v0 亦可）；工具链由 `toolchain/` 单一事实源管理，Phase 0 例外有到期日。
- [ ] 服务端根 `cjpm test`、MCP `cargo test`、Web 的现有可运行测试均进入 CI；mobile Jest 保持执行；`packages/lcodec` 17 例执行，若原生依赖阻断则显式记录并延后。
- [ ] `xtask affected` 对 10 个曾漏包给出正确闭包；新增包只改 manifest。
- [ ] PR required 只有 `ci-required` 聚合；L4/L5 不阻塞 PR。
- [ ] `summary.json` 可被 CI、PR 评论和 AI 代理消费；XML 由自建适配器转换。
- [ ] 契约导出可运行，P0 端点 fixture 入库；OpenAPI 3.0 可 diff，3.1 有独立 issue。
- [ ] 服务端 L2 使用 `bootstrapForTest` + `handleForTest` + 真 PG；repository 接口化有独立计划。
- [ ] 覆盖率先有 baseline 再 ratchet；“行并集”标注为待实测，不作为已证实能力。
- [ ] Windows 只承诺编译 + FFI 子集 + 无 GUI 冒烟；OHOS 设备侧只承诺 TestClass 粒度、`ability_delegator`（SA 65866）就绪性前置检查与 release 清单，不承诺自动全绿。

## 13. 附录

### 13.1 证据索引

| 路径 | 用途 |
|---|---|
| `.github/workflows/build.yml:78`、`:84` | 服务端 CI 执行 csorm 与 postgresql-driver 两个子包测试 |
| `.github/workflows/build.yml:90-207` | 服务端根包 `server-test` job：PG service、`DB_STRING`、`--show-all-output`、`[skip]` 硬失败、产物上传 |
| `.github/workflows/build.yml:176`、`:177` | 服务端 server-test 执行 `cjpm update`，其后为 lock 漂移守卫 |
| `.github/workflows/build.yml:296`、`:297` | 主构建执行 `cjpm update`，其后为 lock 漂移守卫 |
| `.github/workflows/build.yml:323`、`:328`、`:333`、`:338` | Web CI frozen 安装、typecheck、test:ci、build |
| `.github/workflows/client-next.yml:53-61` | guards job 接入 `setup-python@v5`/3.12 与 xtask `doctor`、自测 |
| `.gitea/workflows/build.yaml:173`、`:174` | 发布链路 `cjpm update` 与 lock 漂移守卫 |
| `.cnb.yml:120`、`:121` | CNB 构建 `cjpm update` 与 lock 漂移守卫 |
| `.github/workflows/client-next.yml:143` | 桌面 CI 安装 Cangjie 1.1.3 |
| `.github/workflows/client-next.yml:207`、`:424` | 桌面 CI（Linux / Windows）clone 分支头 |
| `.github/workflows/client-next.yml:342` | 桌面测试命令与 XML 报告 |
| `.github/workflows/client-next.yml:529` | Windows 只跑 `rocksdb_ffi` |
| `.github/workflows/client.yml:60` | 移动端真实执行 Jest |
| `.github/workflows/extension.yml:19`、`:29`、`:34` | extension pnpm 版本与只 build/typecheck |
| `.github/workflows/cli.yml:35` | MCP 只 build |
| `frontend/package.json:7` | Web 测试脚本：`typecheck:12`、`test:13`、`test:ci:15`，随 `da4c58e1` 入库 |
| `client/package.json:11` | 移动端 `test` = jest |
| `extension/package.json:6` | extension 声明 pnpm 10.33.0 |
| `client-next/cjpm.toml:2` | 桌面 manifest 写 1.1.0 |
| `src/main.cj:230` | 服务端开启 Swagger |
| `src/shared/views/api_response.cj:21` | 手写 `toJson` 的代表 |
| `~/.cjpm/git/ignite/887723.../src/app.cj:314` | `interfaceSpecs()` |
| `~/.cjpm/git/ignite/887723.../src/app.cj:495` | `handleForTest` |
| `~/.cjpm/git/ignite/887723.../src/swagger.cj:269` | `SwaggerGenerator.generate()` |
| `~/.cjpm/git/ignite/887723.../src/swagger.cj:272` | 写死 OpenAPI 3.0.0 |
| `~/.cjpm/git/ignite/887723.../src/swagger.cj:433` | 默认 200 OK |
| `cangjie-repo.toml:1` | registry 配置，不锁工具链 |
| `tools/check-deps.py:24` | 使用 `tomllib`，要求 Python ≥3.11 |

### 13.2 官方与能力来源

- [cjpm 手册](https://raw.gitcode.com/Cangjie/cangjie_docs/raw/main/docs/tools/source_zh_cn/cmd-tools/cjpm_manual.md)：workspace、test、bench、filter、tag、parallel、coverage、report。
- [std.unittest 包概览](https://docs.cangjie-lang.cn/docs/1.0.5/libs/std/unittest/unittest_package_overview.html)：`@Test`、`@Bench`、断言、prop_test 重导出。
- [unittest_testmacro 概览](https://docs.cangjie-lang.cn/docs/1.0.5/libs/std/unittest_testmacro/unittest_testmacro_package_overview.html)：参数化、策略、`@Tag`。
- [cjcov 手册](https://docs.cangjie-lang.cn/docs/1.0.0/tools/source_zh_cn/tools/cjcov_manual_cjnative.html)：覆盖率报告、`--branches` 实验标记。
- [unittest_mock 入门](https://docs.cangjie-lang.cn/docs/1.0.0/libs/std/unittest_mock/unittest_mock_samples/mock_framework_getting_started.html)：可打桩与不可打桩边界。
- [OHOS 测试框架指南](https://github.com/super3001/harmonyos_testfwk_cangjie_api/blob/38644ec883f33620503c14d3ffbbccb8c0e179dc/docs/zh_cn/cj-arkxtest-guidelines.md)：`aa test`、TestClass 粒度。
- [Cangjie 1.2.0 发布说明](https://cangjie-lang.cn/en/article/classify/16893)：版本时间与升级注意。

### 13.3 术语

| 术语 | 含义 |
|---|---|
| L0–L5 | 从静态检查到设备/性能的测试分层 |
| affected | 根据改动文件反向计算需运行的包/任务 |
| ratchet | 只允许覆盖率或质量指标变好、不允许无声下降 |
| quarantine | 被隔离的 flaky 测试，必须带 owner 和到期日 |
| wire fixture | 跨端真实 JSON 请求/响应样例，用于锁定序列化行为 |
| bootstrap | 工具链尚未安装时仍能运行 setup/doctor 的能力 |
