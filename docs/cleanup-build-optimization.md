# 代码清理与构建优化建议

- 日期：2026-11-06
- 三个问题：① 旧代码可清理项；② LTO 能否启用；③ cjv（https://github.com/Zxilly/cjv ）在项目中的定位。
- 性质：均为零行为变更（或编译期变更），不依赖性能修复计划（performance-fix-plan.md）的里程碑，可随时独立做。

## 一、旧代码清理清单

### A. 可直接删除（git 里有历史，随时可找回）

| 对象 | 证据 | 建议 |
| :-- | :-- | :-- |
| 根目录 10 个 `*-redesign.html` 设计稿（共约 500KB） | 仅 `frontend/src/app/globals.css:671,721` 的**注释**提到其中之一的文件名，无任何构建/路由引用；git 历史 2026-08-05 引入 | 删除；如想保留设计溯源，移入 `docs/design/` 或删除后靠 git 历史回溯 |
| `src/contexts/task/infrastructure/persistence/task_group_kv_dao.cj` | 文件头自述"@Deprecated … 此 DAO 为死代码，保留仅作历史参考。所有方法仍操作已删除的表，运行时会失败"（v016 已删表）；全仓库无 import | 删除 |
| `SearchController.getSearchSuggestions`（`search_controller.cj:578-581`） | 返回硬编码占位 `["suggestion1","suggestion2","suggestion3"]`，且 `src/routes` 下无任何路由挂载 | 删除 |
| `src/main.cj:30,44,47` 调试残留 | `println("MAIN: LOG_LEVEL ...")`、`=== LOGGING SYSTEM TEST ===`、`This is a debug message`，每次启动必然打印 INFO 级噪声 | 删除（`Starting LANLU server` 等 step 日志保留） |
| `packages/postgresql-driver/src/std_db.cj:273,328` 两个 `@Deprecated` 方法 | 实现已是直接 `throw`，占接口适配位 | 保留（实现 std.database.sql 接口所必需），但可确认仓颉 1.1 的接口是否已去除这两个方法签名，若已去除则连带删除 |

### B. 需要决策后处理（不建议自动删）

| 对象 | 现状 | 建议 |
| :-- | :-- | :-- |
| `client/`（旧 React Native 客户端） | git 仅追踪 190 个文件（package-lock、ts 源码），node_modules(6.4G)/android 构建产物(4.2G) 是本地未忽略垃圾；`.cnb.yml:266` 仍有其 CI 流水线；`/workspace/lanlu` 下已有 3 个该客户端 APK | 若 `client-next`（仓颉客户端）已是替代方案，开 issue 决定归档时间表：删除 CI 流水线 → 移入独立归档仓库 → 主仓库删除 |
| `packages/qwest`、`packages/webview` | 服务端 `src/` 未引用；仅 `client-next` 引用（HTTP 客户端与 WebView 封装） | 不是死代码，是 client-next 的依赖；注意 client-next 与服务端共用同一 cjpm 工作区，清理时不可误删 |
| `todo.md`（70KB，gitignore 已列但文件在库中） | 内容是 client-next RocksDB 计划，状态"全部完成" | 已完成的历史计划文档，移入 `docs/` 或删除 |

### C. 不算死代码但值得注意

- `v006` 迁移编号缺失（v005→v007）：历史上跳过或删除过迁移，版本链仍连续，**不要**补文件，只需确认 `MigrationRegistry` 注册顺序与文件号一致（main.cj 中注册列表无 v006，一致）。
- `v027` 删除了 `user_tankoubon_favorites` 表，但 `UserTankoubonFavoriteDao` 仍在使用——已核实其改查 `user_favorites + tankoubon_archives`（v027 的"合集合收藏跟随子档案"新语义），是活代码，仅类名过时。可择机重命名为 `TankoubonFavoriteDao` 之类，非必需。

## 二、LTO 启用分析

### 工具链现状

- `cjpm.toml:41`：当前 `compile-option = "-O2 --disable-reflection --cfg \"ohos=false\""`，包级 `--static`；
- 全仓库（含 CI 配置）无任何 `--lto` 使用；
- 官方文档（cjc 编译选项）：`--lto=[full|thin]`，Linux 支持（Windows/macOS 不支持）；full 全局优化最强但编译最慢，thin 并行+增量、效果略低；LTO 下静态库需以 `.bc` 形式参与链接（`--output-type=staticlib -o libpkg.bc`）；不允许与 `-Os/-Oz` 同用；`--compile-as-exe` 可在 LTO 下启用 LLVM 激进死符号删除。

### 适配本项目的关键问题：多包 bin-dependencies 结构

本项目是**多包工作区**（`packages/` 下 15+ 个包），主程序通过 cjpm 依赖聚合。官方 LTO 路径要求：参与 LTO 的静态库必须先以 `--lto --output-type=staticlib` 编译成 `.bc`，再把 `.bc` 路径传给最终链接。这意味着：

1. 不能只在主包 `compile-option` 加 `--lto` 了事——每个 packages/* 子包都要切到 `.bc` 产物模式，cjpm 自动传递是否支持需要实测（cjpm 对 `bin-dependencies` 的 `.bc` 传递在 1.1 工具链上的行为待验证）；
2. `--static`（现有）与 `--static-std` 组合：静态链接标准库时 stdx/标准库代码也参与 LTO，收益更大、编译时间显著更长；
3. CI 构建时间会增加（估算 thin +30%~100%，full 2~5 倍），CNB 缓存（`build-script-cache`）不覆盖编译产物，需要评估。

### 预期收益与优先级

性能瓶颈在 **DB 往返与 FFI 内的 C 代码**（libpq/libarchive/rocksdb 是预编译 `.so`，不参与仓颉 LTO）。仓颉侧代码主要是 JSON 组装、字符串处理等薄胶水层，LTO 的跨模块内联收益预计**个位数百分比**。结论：

- **可以启用，但排低优先级**。对 `/api/tankoubons` 这类秒级接口是噪声；对每请求毫秒级胶水开销可能有 1~3% 的改善；
- `--compile-as-exe` + LTO 的死符号删除倒是能实打实**减小二进制体积**（当前链接了 vips/avif/libavformat/libvlc 等大库的桥接层）。

### 建议路径（低风险渐进）

1. **实验分支**：仅改主包 `[target.x86_64-unknown-linux-gnu] compile-option` 为 `-O2 --lto=thin`，packages 子包先不动，看 cjpm 是否报错（若子包 `.so/.a` 无法参与 LTO，thin 仍能优化主包内跨模块调用）；
2. CI 加一个 nightly 构建矩阵（thin LTO × 现状）对比：二进制体积、构建时长、`cjpm test` 全绿；
3. 若 thin 无损：主包 + `packages/postgresql-driver`、`packages/csorm`（纯仓颉、无 C 绑定、热路径）改 `.bc` 产物做 thin LTO；**FFI 桥接包（archive_ffi/rocksdb_ffi 等）不参与**——它们只是薄绑定，LTO 收益趋零还拖慢编译；
4. full LTO 仅在 release tag 构建时考虑，配合 `--compile-as-exe`；
5. 禁止组合：`-Os/-Oz` 与 `--lto`（官方约束）；保持 `--disable-reflection` 不变（已核实代码无反射使用，安全）。

## 三、cjv（Cangjie Version Manager）评估

cjv 是 Zxilly（同时也是本项目 GitHub CI 用的 `Zxilly/setup-cangjie@v3` 的作者）做的仓颉 SDK 版本管理器：多工具链安装、`cangjie-sdk.toml` 项目级固定版本、stdx 组件管理、nightly/LTS/STS 通道。

### 与本项目现状的对照

| 维度 | 现状 | cjv 带来的变化 |
| :-- | :-- | :-- |
| GitHub CI | 已用 `Zxilly/setup-cangjie@v3`（cjv 作者的 action，内部就是 cjv 生态） | 无实质变化 |
| CNB CI | 手写 `wget $CANGJIE_URL + tar`，依赖项目变量里的 tar 包 URL，版本漂移靠人肉更新变量 | 改用 `cjv` + `cangjie-sdk.toml` 后版本固定进 git，不再依赖两个环境变量；SDK 缓存由 cjv 自管理 |
| 本地开发 | 无版本约定，开发者手动下载 | `cjv pin lts` 生成 `cangjie-sdk.toml` 提交入库，进目录自动用对版本，缺 SDK 自动装 |
| stdx | 手动下载 zip + `CANGJIE_STDX_PATH` 环境变量拼接 | `components = ["stdx"]` 声明式管理（注意：本项目的 `CANGJIE_STDX_PATH` 指向 **static** 子目录，迁移时要确认 cjv 提供的路径等价） |
| 特殊构建 | WasmEdge 源码 clone、xmake 等自定义步骤 | 无关，cjv 只管 SDK/工具链 |

### 建议

1. **值得引入，收益主要在可复现性与 CNB CI 简化**：
   - `cjv pin`（选与 `cjpm.toml` 的 `cjc-version = "1.1.0"` 匹配的 STS 通道）生成 `cangjie-sdk.toml`，加 `components = ["stdx"]`，提交入库；
   - CNB 的 "Download Cangjie SDK + stdx" 步骤替换为 `cjv` 安装 + `cjv doctor`（离线环境可用 cjv 的镜像与缓存目录配置，继续挂 `build-script-cache` 做 copy-on-write 缓存）；
   - GitHub workflow 保持 `setup-cangjie@v3` 不动（已是同一生态）。
2. **注意点**：
   - `cjpm.toml` 的 `cjc-version = "1.1.0"` 与 cjv 固定的版本必须一致，否则 cjpm 会拒绝构建——建议同一 PR 内核对；
   - `CANGJIE_STDX_PATH="$PWD/stdx/linux_x86_64_cjnative/static/stdx"` 这一路径语义要在 cjv 安装布局中找到等价物（GitHub workflow 里 `CANGJIE_STDX_PATH_STATIC` 就是 cjv 生态提供的变量，说明兼容）；
   - WasmEdge/xmake/rocksdb_ffi 的 build.cj 钩子流程不受影响，但首次迁移建议跑一次完整 release 构建验证 `.cnb.yml:119` 提到的 `[ffi.c]` 校验时序问题不再触发。
3. 与 LTO 的联动：cjv 装 nightly 工具链很方便，正好支撑第二节第 2 步的 LTO 对比矩阵——这也是引入 cjv 的额外理由。

## 四、执行顺序

1. **随时可做（半小时级）**：删 10 个根 HTML、task_group_kv_dao、getSearchSuggestions、main.cj 调试残留、todo.md 归档——每项删除前跑一次 `cjpm build` 确认无隐式引用。
2. **一个 PR**：cjv 引入（`cangjie-sdk.toml` + CNB CI 改造 + 验证一次完整构建）。
3. **实验分支（不阻塞发版）**：thin LTO 对比矩阵，数据好看再合入。
4. **开 issue 决策**：`client/` 旧客户端归档时间表。

以上清理与构建优化不解决性能问题本身（见 performance-fix-plan.md），但减小仓库/二进制体积、让构建可复现，属于维护性收益。
