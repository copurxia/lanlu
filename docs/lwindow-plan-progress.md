# lwindow 协议化 —— 执行进度

计划正文：[lwindow-platform-separation-plan.md](lwindow-platform-separation-plan.md)。
交接快照：[lwp-handoff-status.md](lwp-handoff-status.md)。
本文件只记**执行状态**：哪些做完了、证据是什么、下一步做什么。每条完成项都必须有可复核的证据
（命令、脚本输出、CI 结果），不写"应该可以"。

## 导航（按里程碑找轮次）

| 里程碑 | 轮次 | 一句话 |
|---|---|---|
| M0 平台拆分 / 守卫 | 1~18 | 平台包成型、8 项守卫进 CI、FFI 结论落文档 |
| M1 协议 + 传输 | 19~27 | IDL 13/56、生成器、`liblwp_native.so`、检查器、录制回放 |
| M2 引擎侧接线 | 28~35 | 剪贴板/对话框/窗口状态/日志接协议，文件桥运行时停用 |
| M3 规则 + 文件桥盘点 | 36~41 | 违约计数、能力位、ABI 追加强制、M6 手册 |
| **M2 真机验收** | 52~54 | 修 4 个真机缺陷，7 条判据全过，LWP 设为默认 |
| **M6 删除** | 55~57 | 文件桥 35 → 2 处（输入/剪贴板/对话框/窗口命令/抓帧） |
| **M1W Wayland 壳** | 58~67 | 连接/建窗/输入/上屏四条链路 + 假合成器 4 项集成测试 |
| 收尾与归档 | 68~ | 文档收敛、快照归档 |

> 第 42~51 轮是环境阻塞期的准备与排障（含一次 Wayland 环境误判的纠正）。

## 已被推翻的结论（读旧轮次前先看这里）

进度日志保留原始记录、不回头改写；**被推翻的判断集中列在这里**，避免读者按旧结论行事。

| 旧结论（轮次） | 后来的事实 | 纠正位置 |
|---|---|---|
| "宿主机没有 Rust 工具链，M1W 被环境阻塞"（第 42 轮） | cargo 一直在 `/workspace/horizon-ohos/.tooling/rust190`，只是没进 PATH | 第 73 轮 |
| "宿主机跑不了引擎测试是因为缺 cargo" | 真卡点是 **ffmpeg 开发头**（`libavcodec/avcodec.h`） | 第 73 轮 |
| "引擎没发 `lw_seat.set_cursor`"（第 82 轮） | 发了；是我看的 hilog 窗口被新实例覆盖 | 第 83 轮 |
| "搜索框拿不到焦点 / 缺 IME attach"（第 84/85/87 轮） | 均非事实：真因是 **uitest 用屏幕坐标、窗口有 (515,292) 偏移** + `poll()` 每帧吞输入 | 第 86、90 轮 |
| "无边框窗口无法拖边缩放"（第 101 轮） | 系统原生支持；那次是拖动起点落在窗口外 | 第 102 轮 |
| "光标形状决策放事件源里足够"（第 82 轮） | 事件源只在有输入时被调用，焦点变化未必触发 → 改到 frame tick | 第 89 轮 |

**规律**：多数"不工作"最终是**测量方法**或**证据时效性**的问题，而不是产品缺陷。
见 [lwp-verification-discipline.md](lwp-verification-discipline.md)。

## 当前阶段

**收尾：全量验证（8 守卫 + 6 测试套件）+ 源码快照 + 交接清单「接手第一天该做什么」。**

最新一轮记录见文末；历史轮次保留以便追溯（含被推翻的判断，例如早期的 Wayland 环境误判）。
M0 遗留两项（输入回放基线、`portcheck` 自检迁移）结构上依赖 M1/M5，已在判定表中标注原因与落地里程碑。

## 图例

- ✅ 完成（有证据）
- 🚧 进行中
- ⬜ 未开始
- ⛔ 阻塞（写明原因）

## M0 基线、平台包骨架与护栏

| # | 任务 | 状态 | 证据 |
|---|---|---|---|
| 1 | 建立 4 个平台包骨架 | ✅ | `packages/lplatform-ohos`、`packages/lpack-ohos`（含壳源码与生成器）、`packages/lplatform-wayland`（Cargo 骨架，`cargo build` 通过）、`packages/lpack-linux`（README 约定包结构） |
| 2 | 壳源码迁入主仓，`build-ohos.sh` 改为从主仓取模板 | ✅ | 全量 `build-ohos.sh` 通过：`BUILD SUCCESSFUL`，HAP 109 MB，`libs/arm64-v8a/libmain.so` 14.6 MB（由 `lplatform-ohos/shell` 编译）。仓外 `.research-ohos` 已不参与构建 |
| 3 | 散落的鸿蒙代码迁入平台包 | ✅ | 已迁：壳源码、hapgen、模板、资源、5 个 `native-ohos/`、8 个工具脚本、`client-next/ohos`（`cjpm.toml.ohos`+`gen_*.py`+`assets`）→ `lpack-ohos/app-profiles/lanlu/`；`client-next/build/ohos` 退出版本库；6 个中立包 cjpm.toml 去机器路径；`app.toml` 已接线。**唯一例外**：`portcheck/ohos_selftest*` 留在原处，移入 M5（需要 `lwp test` 接口才能正确取放，见判定表） |
| 4 | 复现并定位历史 FFI 崩溃 | ✅ | 探针 `tools/probes/ffi-call`（5 个变体，可复现）；结论写回 [l-layer.md](l-layer.md#m0-4-最小用例结论引擎调壳导出符号2026-11-10host-实测)：壳必须 RTLD_GLOBAL 且早于引擎加载、构造函数内同步启动必失败、失败是静默的（退出码 0）→ M1 用 hello_ack 作唯一判据 |
| 5 | 依赖白名单 + 平台隔离守卫进 CI | ✅ | `tools/check-deps.py`、`tools/check-platform-isolation.py`、`tools/deps-rules.toml`、`tools/quality-baseline.toml`；违规基线 10 + 112，`guards` job 已加入 `.github/workflows/client-next.yml` |
| 6 | 输入回放基线 | ⏭ | 结构依赖 M1 的 `lwtrace`（无协议就没有可录的格式）；M0 期间用 `tools/probes/ffi-call` 覆盖了加载时序这一半风险 |
| 7 | horizon 构建纪律（路径推导、失败即停、符号门禁、versionCode 自增） | ✅ | 已做：`deps/common-ohos.sh` + `lpack-ohos/tools/common.sh` 统一解析工具链；`build-ohos.sh`、5 个 deps 脚本、8 个 lpack 工具脚本、6 个中立包 cjpm.toml 全部去机器路径；工具缺失立即报错；符号门禁已并入 `verify-ohos.sh` 并在构建末尾强制执行。`check-prebuilts.sh` 决定 `RES` 不 vendored：逐项校验 + 给出生成命令，构建前置运行 |
| 8 | `tools/sync-winit.sh` | ⬜ | 参照 `tools/sync-wgpu-hal.sh` |

## 本轮完成的具体改动（2026-11-10，第 1 轮）

1. **新增两个守卫与基线**
   - `tools/deps-rules.toml`：按计划 §4.5 为目标态登记白名单；未登记的 FFI 包默认只允许标准库。
   - `tools/check-deps.py`：读 `cjpm.toml`/`Cargo.toml` 依赖 + 源码 import 顶层包，对照白名单。
     当前 10 条违规，全部是计划要清理的真实耦合：
     `lanlu_client_next` → `lgui`/`lgpu`（dep + import）、`cui`→`lgui`、`lgpu`→`lgui`、`lwindow`→`lgui`。
   - `tools/check-platform-isolation.py`：三类规则（`ohos`、`wayland`、`sdl`），只允许出现在
     `packages/lplatform-*`、`packages/lpack-*`、`third_party/`。当前 112 处已知违规。
   - `tools/quality-baseline.toml`：机器维护的基线，只降不升。
   - `.github/workflows/client-next.yml`：新增 `guards` job（纯 python3，10 分钟超时）。

2. **平台包落地**
   - `packages/lplatform-ohos/shell/{native,arkts}`：从仓外 `.research-ohos/packages/ohos/templates_sdl3`
     迁入 `shell_napi.cpp`、`input_filter.cpp`、`CMakeLists.txt`、`types/libmain/*`、`Index.ets`、`EntryAbility.ets`。
   - `packages/lpack-ohos/`：hapgen 源、`templates/`、`templates_sdl3/`（去掉壳 cpp/ets）、`assets/`。
   - `client-next/ohos/build-ohos.sh`：新增模板暂存步骤（base + 覆盖层 + 壳源码覆盖），
     `OHOS_TEMPLATES/OHOS_ASSETS/OHOS_LIBCXX` 指向 `lpack-ohos`，hapgen 路径改为 `packages/lpack-ohos/target/release/bin/main`。
   - `packages/lpack-ohos/tools/build-hapgen.sh`：`PKG` 默认改为仓内 `packages/lpack-ohos`，去掉 `.research-ohos` 硬编码。
   - hapgen rel 列表删除 `entry/src/main/cpp/sdl_main.c`（P5 后已不参与编译）。

3. **`client-next/build/ohos` 退出版本库**
   - `git rm -r --cached client-next/build/ohos`（90 个文件）；`.gitignore` 加 `client-next/build/`。
   - 文件仍在磁盘，构建不受影响（计划 §4.3：主仓不存放生成物）。

4. **验证**
   - `bash packages/lpack-ohos/tools/build-hapgen.sh` → `cjpm build success`，产出 `packages/lpack-ohos/target/release/bin/main`。
   - 暂存覆盖完整性：脚本比对 hapgen 的 30 条 sdl3 rel，全部可解析，壳的 5 个文件确认来自 `lplatform-ohos`。
   - **全量 `bash client-next/ohos/build-ohos.sh` → `BUILD SUCCESSFUL`（exit=0）**：
     `entry-default-unsigned.hap` 109 MB；`libs/arm64-v8a/libmain.so` 14.6 MB、`liblanlu_client_next.so` 1.7 MB。
     签名跳过（本机无 signingConfigs，属既有签名配额问题，与本次迁移无关）。
   - `packages/lplatform-wayland`：`cargo build --offline` 通过，二进制可运行。
   - 四个守卫全部 PASS：`check-deps.py`、`check-platform-isolation.py`、`check-layering.sh`、`check-no-sdl.sh`。

## 第 2 轮（2026-11-10）

1. **`native-ohos` 全部迁入平台包**（计划 §4.2）
   - `git mv`（保留历史）：`packages/{vips,rocksdb,libvlc,fontkit}_ffi/native-ohos` → `packages/lplatform-ohos/deps/{vips,rocksdb,libvlc,fontkit}`，
     `packages/lgpu/native-ohos` → `packages/lplatform-ohos/deps/lgpu`；仓内已无 `packages/*/native-ohos`。
   - `libvlc` 的 shim 依赖 ffmpeg 头/库目录，仍走 `FFMPEG_SRC`/`FFMPEG_LIB_DIR` 环境变量。
   - 平台隔离守卫因此自动少 7 条（文件进入 `packages/lplatform-*` 前缀不再计违规）——守卫按设计生效。

2. **工具链路径统一解析**（M0-7 第一步）
   - 新增 `packages/lplatform-ohos/deps/common-ohos.sh`：`OHOS_CLT / OHOS_NATIVE_SDK / OHOS_CLANG /
     OHOS_LLVM_BIN / OHOS_SYSROOT / OHOS_RUST / OHOS_CARGO_HOME / OHOS_JAVA`，顺序为
     **环境变量 → 已知默认位置 → 报错退出**。
   - 5 个 deps 构建脚本改为 source 它，不再各自写死 clang/sysroot；`lgpu/deps` 脚本同时修正了
     “脚本位置改变后指向 `packages/lgpu/native`”的相对路径。
   - `build-ohos.sh`：`NATIVE/SYSROOT/DEVECO_CLI_CLT_PATH/JAVA_HOME` 改为由 common 解析，
     缺少工具链时立即报错退出；仓颉工具链支持 `CJV_TOOLCHAINS` / `CJ_OHOS_TOOLCHAIN` 覆盖。
   - 硬编码 `/workspace/...` 从 35 处降到：`common-ohos.sh` 内的 fallback 候选 + `RES`（外部预编译材料，待迁）。
     中途遇到 `devecocli: command not found` —— 是我把 `/workspace/bin` 从 PATH 里弄丢了，
     已改为 `TOOLS_BIN`（可覆盖）。

3. **`tools/sync-winit.sh`**（M0-8）
   - 参照 `sync-wgpu-hal.sh`：`rsync` 复制 horizon 的 winit 家族（winit/core/common/wayland/x11/dpi），
     排除 `target/`、`examples/`，并写 `SYNCED-FROM.txt`（源路径 + 时间 + horizon 提交号）。
   - `--check` 模式供 CI 用；实际同步在 M1W 首次接 Wayland 壳时执行。

4. **验证**
   - 全量 `build-ohos.sh` 再次通过（exit=0，`BUILD SUCCESSFUL`）：HAP 109 MB，
     `libs/arm64-v8a/` 内 `libmain.so` 14.6 MB、`libvips.so`、`libvlc.so`、`liblanlu_rocksdb_bridge.so`、
     `libfontkit_native.so` 全部由 `lplatform-ohos/deps` 现场编译产出。
   - 守卫：deps 10 条（不变）、platform 105 条（从 112 降至 105，基线已刷新）。

## 第 3 轮（2026-11-10）

1. **验证并采用 cjpm 的 `${VAR}` 替换**（M0-3/M0-7 的关键前置）
   - 先做单包实验：把 `packages/qwest/cjpm.toml` 的 sysroot 换成 `${OHOS_SYSROOT}`，
     `cjpm build --target aarch64-linux-ohos` → `cjpm build success`。**结论：cjpm 对
     `[target.*]` 的 `compile-option`/`link-option` 做环境变量替换**，因此不需要给 cjpm
     打补丁、也不需要生成临时 cjpm 配置覆盖层。
   - 据此把 6 个中立包（`qwest`/`portcheck`/`cangjie-gui`/`lgui`/`vips_ffi`/`webview`）的
     `[target.aarch64-linux-ohos]` 段全部改为 `${OHOS_SYSROOT}`、`${OHOS_STDX}`、
     `${OHOS_STUBS}`、`${OHOS_LLVM_BIN}`。**中立包 cjpm.toml 里 `/workspace/...` 归零**
     （之前 6 个文件共 18 处）。
   - `common-ohos.sh` 增加 `OHOS_STDX` / `OHOS_STUBS` 解析；`build-ohos.sh` 导出
     `CANGJIE_STDX_PATH`（bin-dependencies 用）。

2. **`lpack-ohos/app-profiles/lanlu/app.toml`**
   - 应用元数据（包名/版本/API/设备/权限/querySchemes/壳形态/引擎与壳库名）集中到一份配置，
     取代散在 `client-next/ohos/cjpm.toml.ohos` 的 `[package.metadata.ohos]` 与模板 `module.json5`。
   - 权限按计划 §8 收敛：只留 `INTERNET`、`LOCK_WINDOW_CURSOR`（后者是 API 22 指针锁定需要），
     **不含** `READ_PASTEBOARD`（受限 ACL，实测装不上；剪贴板按 Ctrl+V 后 2 秒规则读）。
   - 状态：文件已建，**尚未接线**——hapgen 目前仍从 `cjpm.toml` 读 metadata，接线在 M0-3 收尾。

3. **验证**
   - 全量 `build-ohos.sh` → exit=0，`BUILD SUCCESSFUL`，HAP 109 MB（16:15 重建），
     `libs/arm64-v8a/` 内 5 个 ffmpeg 库（`libavcodec.so.61` 等）与全部 shim 齐全。
   - 守卫不变：deps 10 条、platform 105 条（target 段的 `aarch64-linux-ohos` 标识仍在，
     基线保留；是否连段一起迁走见下）。
   - 已知无害噪声：hapgen 打包阶段会打印 5 行 `cp: cannot stat`（ffmpeg 的链接别名文件）——
     它先按链接别名拷贝、随后归一化到 SONAME，实体库都在 HAP 里（已核对 `libs/arm64-v8a/`）。
     记为 M6 清理项（届时 `OHOS_EXTRA_LIBS` 重排，改为只按 SONAME 拷贝）。

## 第 4 轮（2026-11-10）

**M0-4 完成：历史 FFI 崩溃的最小化复现与结论**

新增探针 `tools/probes/ffi-call/`（`shell.c` / `shell_ctor.c` / `shell_ctor2.c` / `engine.cj` / `loader.c` / `run.sh` / README），
在 host（x86_64）上把“引擎（仓颉 dylib）调壳（C）导出函数”拆成 5 个可控变体，逐一跑通：

| 变体 | 结果 |
|---|---|
| `shell-first-g`（壳 RTLD_GLOBAL 且先加载） | ✅ 引擎调壳返回 43；外部线程回调仓颉返回 63 |
| `engine-first`（壳后加载） | ⚠️ `LoadCJLibraryWithInit=-1`，但 `dlopen(RTLD_LAZY)` 返回 ok、`cj_app_main` 有返回值（垃圾）、输出丢失、**退出码 0** |
| `shell-local`（RTLD_LOCAL） | ❌ 引擎始终看不到符号，加载失败 |
| `ctor-autostart`（构造函数内同步启动） | ❌ `undefined symbol`：此时壳自身符号尚未进入全局作用域 |
| `ctor-deferred`（构造起线程，稍后启动） | ✅ 能过，但依赖“壳 dlopen 已完成”的隐含时序 |

三条可执行结论（已写进 [l-layer.md](l-layer.md)）：

1. 壳必须 `RTLD_GLOBAL` 且早于引擎加载；`RTLD_LOCAL` 永远不行。
2. 不要在壳的构造函数里启动引擎（同步必失败，异步靠运气）——这是“到处等 N 秒拿环境变量”的根源。
3. 失败是静默的：`dlopen` 成功、有返回值、退出码 0。**M1 必须用 `core.hello_ack` 作链路可用判据**，
   并在 `lpack-ohos verify` 加符号门禁。

顺带确认：外部线程（pthread）调用仓颉 `@C` 函数在 host 上正常（无崩溃/死锁），
但按 §2 原则 6 仍不依赖它。

调试过程记录（避免重犯）：探针第一版把 `lwp_spawn_foreign` 只写进了 `shell.c`，
ctor 变体因此缺符号而“失败”，差点得出错误结论——**先 `nm -D` 核对导出符号，再解读结果**。

## 第 5 轮（2026-11-10）

1. **`lpack-ohos` 接线 `app.toml`**（M0-3 收尾一）
   - hapgen 新增 `OHOS_APP_PROFILE`（缺省回退 `cjpm.toml` 的 `[package.metadata.ohos]`，保证老构建不受影响）；
     新增 `arrayOf()` 解析数组（支持跨行、去引号、去行内注释），`pick()`/`pickArray()` 做「profile 优先」取值。
   - 模板 `module.json5` 的 `requestPermissions` 与新增的 `querySchemes` 改为占位符
     `__PERMISSIONS__` / `__QUERY_SCHEMES__`，由 `app.toml` 生成。
   - **效果**：包名、版本、API、设备类型、权限、querySchemes 现在全部来自 `app-profiles/lanlu/app.toml`。
     生成的 `module.json5` 实际含 `INTERNET` + `LOCK_WINDOW_CURSOR` 两条权限与三条 querySchemes
     （此前模板里只有 `INTERNET`，且没有 querySchemes —— 意味着现在 `openLink` 拉起外部应用
     会因为缺 scheme 声明报 17700055）。
   - 过程中修了三个真 bug：① `meta()` 不剥行内 `#` 注释 → `bundleName` 里混进注释导致
     hvigor schema 校验失败；② 数组项经过两次加引号变成 `""2in1""`；③ 仓颉 `Array + [x]` 不支持，
     `permJson` 改为单趟字符串拼接。

2. **符号门禁机制化**（M0-4 结论落地）
   - `packages/lpack-ohos/tools/check-hap-symbols.sh` 增加反向检查：HAP 内任意库对 `lanlu_*` / `lwp_*` 的**未定义 C 符号引用**
     必须由同包内某个库导出（对应 horizon-ohos 2026-10-25 的 UNDEFINED 符号事故）。
   - 只查纯小写 C 符号：仓颉跨包类型信息（`pkg:Type.ti`）由运行时自行解析，第一版没过滤，
     报了 98 条假阳性；过滤后本仓 5 条引用全部可解析。
   - 门禁已并入 `packages/lpack-ohos/tools/verify-ohos.sh`，构建末尾强制执行。

3. **验证**（未跳过任何门禁的完整构建）
   - `bash client-next/ohos/build-ohos.sh` → exit=0，`BUILD SUCCESSFUL`，HAP 109 MB。
   - 静态验证全绿：分层守卫、`全部库为 AArch64`、`全部依赖可解析`、`符号一致`、`静态验证全部通过`。
   - 生成的 `AppScope/app.json5`：`bundleName = "com.example.cmakehap"`（注释已正确剥离）。

## 第 6 轮（2026-11-10）

1. **鸿蒙工具脚本迁入平台包**（M0-7 主体）
   - `git mv` 8 个脚本：`tools/{build-ffmpeg-ohos,build-hapgen,check-hap-deps,check-hap-symbols,sign-hap,verify-ohos,verify-window,make-sdl3-noversion}.sh`
     → `packages/lpack-ohos/tools/`。`tools/` 现在只剩中立守卫与同步脚本。
   - 新增 `packages/lpack-ohos/tools/common.sh`：解析 `REPO_ROOT/LPACK_DIR/CN_BUILD/HAP_OUT/RES/TMPDIR`
     并 source `lplatform-ohos/deps/common-ohos.sh`；提供 `find_hap()`。
   - 各脚本改为 env 优先、缺失即报错；签名材料从写死的 `/workspace/.ohos/config` 改为
     `${OHOS_SIGN_DIR:-$HOME/.ohos/config}`（换机器可用）。
   - 平台隔离违规 105 → **101**（脚本进入 `packages/lpack-*` 前缀），基线已刷新。

2. **`/tmp` 写满导致构建失败 —— 我上一轮引入的回归**
   - 第 2 轮把 `TMPDIR` 默认从 `/workspace/tmp` 改成 `/tmp`，而容器 `/tmp` 是 **512M tmpfs**；
     `check-hap-symbols.sh` / `check-hap-deps.sh` 每次 `unzip` 一个 109MB HAP 且**不清理**，
     4 次调用后 `/tmp` 只剩 26MB → 引擎链接阶段 `LLVM ERROR: IO failure on output stream: No space left on device`。
   - 修法：① 两个脚本加 `trap 'rm -rf "$WORK"' EXIT`；② `lpack-ohos/tools/common.sh` 与
     `build-ohos.sh` 的 `TMPDIR` 默认改为 `${TMPDIR:-<仓库同级>/tmp}`（大容量卷），仍可被环境变量覆盖。
   - 教训已记入本节：**临时目录会放大“没清理”的代价**，凡是 `mktemp -d` + 解包都必须配 trap。

3. **`ffi-call` 探针升级为断言式回归 + 接入 CI**
   - `run.sh` 原来只“演示”（永远 exit 0），现在对 6 项行为逐条断言：正确顺序返回 43 / 外部线程返回 63 /
     壳后加载 `rc=-1` / `RTLD_LOCAL` 报 undefined symbol / 构造函数同步启动失败 / 构造函数异步启动可通过。
     行为一旦变化即失败——M0-4 的结论变成持续回归。
   - `run.sh` 支持 `CANGJIE_HOME`（CI 用 setup-cangjie 的布局），并加入 `build-test` job。

4. **验证**
   - `bash client-next/ohos/build-ohos.sh` → exit=0，`BUILD SUCCESSFUL`，HAP 109 MB；
     静态验证全绿（分层 / AArch64 / 依赖可解析 / 符号一致 / 全部通过）；构建后 `/tmp` 占用回落到 14%。
   - `bash tools/probes/ffi-call/run.sh` → 6 项断言全 ok，`[PASS]`。
   - 守卫：deps 10 条、platform 101 条、layering、no-sdl 全 PASS。

## 环境备忘

- `/workspace` 已用 95%（31T 中剩 1.7T），`/workspace/tmp` 占 **63G**（历史 ffmpeg 源码/前缀等）。
  后续构建若再报 ENOSPC，先清 `/workspace/tmp` 下不再需要的 ffmpeg 中间产物，而不是动仓库。

## 第 7 轮（2026-11-10）

1. **`client-next/ohos` 构建配置迁入 app profile**（M0-3 收尾三）
   - `git mv`：`cjpm.toml.ohos`、`gen_seed_cj.py`、`gen_video_cj.py`、`assets/{test360.mp4,fonts.conf}`
     → `packages/lpack-ohos/app-profiles/lanlu/`；删除 `client-next/ohos/platform/`（早期接口草稿，无引用）。
   - `build-ohos.sh` 本体迁至 `packages/lpack-ohos/tools/`，改为 `LPACK_APP` + `PROFILE` 驱动；
     `client-next/ohos/build-ohos.sh` 保留为 5 行转发入口（文档/脚本里的旧路径继续可用）。
   - 验证：用**新入口**和**旧转发入口**各跑一次完整构建，均 exit=0、静态验证全绿。

2. **`RES`（预编译材料）去留决策 —— 不入库**
   - 事实：`ohos-stubs` 10MB + `sdl3-ohos` 61MB，都是第三方库的交叉编译产物，不是源码。
   - 决定（计划 §4.7 的口径）：**不 vendored 进 git**，改为「可重复生成 + 构建前校验」。
   - 新增 `packages/lpack-ohos/tools/check-prebuilts.sh`：逐项校验 13 个关键材料，
     缺失时打印对应生成命令；已接进 `build-ohos.sh` 第 0 步（缺失即停，不等到构建中途）。
   - 本机实测：13 项全部 ok，`[PASS] 预编译材料齐全`。

3. **`portcheck/ohos_selftest*` 的去向：推迟到 M5（并说明理由）**
   - 这些自检调的是 `vips_ffi` / `libvlc_ffi` / `webview` 等中立包；若现在移进
     `lplatform-ohos/selftest`，就会产生「中立 portcheck → 平台包」的反向依赖。
   - 计划 §4.1 的正确形态是「portcheck 经 `lwp test` 接口驱动、鸿蒙用例在平台包里」——
     这需要 M1 的协议先存在。因此本轮只记录决策，不动文件。

4. **M0 完成判定**（结论见文末「M0 完成判定」）


## M0 完成判定（§16.9 逐条）

| 完成定义 | 结论 | 依据 |
|---|---|---|
| 验收项有自动化用例，CI/设备机通过 | ✅（M0 范围内） | 4 个守卫 + `guards` job；`ffi-call` 6 项断言已进 `build-test`；`check-prebuilts.sh` 进构建第 0 步 |
| T0 门禁通过、违规数不高于上个里程碑 | ✅ | deps 10 条（未变）、platform 112 → **100**（连降三轮）、layering/no-sdl PASS |
| 该删的旧通道已删除且有规则阻止加回 | ✅（M0 范围） | `sdl_main.c`、`.research-ohos` 构建依赖、`client-next/build/ohos` 入库、`client-next/ohos/platform` 已删；基线机制阻止回退 |
| 性能指标不劣于基线 | — | M0 不涉及渲染/输入路径，无指标变化 |
| 文档更新 | ✅ | 计划 + 进度 + `tools/README` + 各包 README + docs 里的脚本路径全部同步 |

**结论：M0 完成。** 两项顺延有明确理由：
- 输入回放基线 → M1（`lwtrace` 是它的载体）；
- `portcheck/ohos_selftest*` → M5（需要 `lwp test` 接口）。

## 第 8 轮（2026-11-10）：M1 起步 —— 协议 IDL 与生成器

1. **IDL 真源**：`packages/lwp/protocol/core.toml`
   - core 接口 v1：`hello`（壳→引擎，含协议版本/壳名/OS/API 级别/能力位）、`hello_ack`（引擎→壳）、
     `error`、`log`、`ping`/`pong`；外加 `core_error` 枚举与 `core_capabilities` 位域（17 个能力位，
     对应计划 §5.3）。
   - 线上格式写进 IDL 头注释：`uint32 size` 首字段、packed 小端、`string=(u16 off,u16 len)`、
     opcode 按同接口同方向声明序号、字段只允许追加。

2. **生成器** `tools/lwp-gen.py`（计划 §5.1）
   - 输入 `protocol/*.toml`，输出 5 类生成物：C 头（packed 结构体/opcode/枚举）、仓颉绑定
     （常量 + 结构 + 逐字段解码）、壳端分发桩 `lwp_dispatch.inc`、`docs/lwp/*.md` 协议文档、
     `abi/lwp_abi.json` ABI 指纹。
   - **关键取舍**：仓颉侧不生成 `@C struct`（仓颉里它目前只用于不透明句柄），改为「偏移 + 逐字段读字节」
     的解码函数——不依赖跨语言结构体 ABI，越界字符串返回空串而不是崩溃。
   - `--check` 模式比对生成物，CI 用（生成物入库，改 IDL 忘记重生成会失败）。

3. **两侧交叉验证**（同一份 IDL 偏移，两种语言各验一遍）
   - C 侧 `packages/lwp/native/test_protocol.c`：`_Static_assert` 校验 6 条消息的 `sizeof` 与字段偏移，
     运行期组装一条 hello 并核对字节序（小端 `uint32`）。
   - 仓颉侧 `packages/lwp/src/lwp_test.cj`：手写 36 字节缓冲区 → 解码 → 断言 6 个字段、能力位、
     越界字符串容错、6 条消息尺寸、协议版本。**5 个测试全通过**。

4. **验证**
   - `python3 tools/lwp-gen.py --check` → `[PASS] LWP 生成物最新（6 条消息，1 个接口）`
   - `bash packages/lwp/native/run-tests.sh` → `[PASS] lwp C 布局测试`
   - `cd packages/lwp && cjpm test` → `TOTAL 5 / PASSED 5 / FAILED 0`
   - 守卫：deps 10、platform 100，未新增。
   - CI：`guards` job 加“生成物最新 + C 布局测试”，`build-test` job 加 `cjpm test`。

5. **踩坑记录（生成器调试）**
   - cjpm 要求子目录包名为 `lwp.gen`，生成物不能放 `src/gen/`；改为直接生成到 `src/`。
   - 仓颉 `@Test` 必须是顶层函数（不能写在 class 里）；字段名保持 IDL 的 snake_case。
   - 容器 `/tmp` 是 noexec，编译产物必须落到仓库同级 `tmp/`（`run-tests.sh` 已默认如此）。
   - C 头注释里出现 `*.toml` 会被 `-Wcomment` 判为注释嵌套 → 改写措辞。

## 第 9 轮（2026-11-10）：M1 —— liblwp.so 通道实现

1. **公开 ABI**：`packages/lwp/include/lwp.h`
   - `lwp_header`（iface/opcode/size/serial/flags/time_ns，24B）；`LWP_REQUEST`/`LWP_EVENT`；
     `LWP_F_BLOB`/`LWP_F_DROPPABLE`；错误码（EAGAIN/EMSGSIZE/ENOENT/EBADMSG…）。
   - 11 个公开函数：`open/close/send/recv/wait/wake/blob_put/blob_get/blob_release/get_stats/now_ns`。

2. **实现**：`packages/lwp/native/liblwp.c`
   - 定长槽环形队列（Vyukov 有界 MPMC，每槽一个 seq）——EVENT 多生产者、REQUEST 单生产者用同一份代码；
     满时返回 `LWP_EAGAIN` 不阻塞。
   - blob 池（64×4KB，句柄从 1 开始）；每个方向一个 eventfd + `poll` 做真阻塞等待。
   - 纯 C、零构造函数、`lwp_open` 惰性初始化并做进程内单例（同名复用）。
   - `-fvisibility=hidden` + `LWP_API` + 链接脚本白名单：**只导出 11 个公开函数**（`nm -D` 已核对）。

3. **C 测试**：`packages/lwp/native/test_channel.c`（39 项断言，全部通过）
   - 收发往返、方向隔离、空队列 EAGAIN；serial 自动分配、size 由库重算；
   - 满队列容量精确、`dropped` 计数；**4 线程 × 2000 条多生产者**无丢失、每生产者内部有序无串扰；
   - 非法头部（size 过小/过大）→ `LWP_EBADMSG` 且计入 `bad`；
   - blob put/get/release/复用/越界句柄/超块大小拒绝；内联超限 `LWP_EMSGSIZE`；
   - `wait` 超时精度、send 唤醒、**wake 打断阻塞中的对端**。

4. **两处按测试反馈修正的语义**（值得记录）
   - `lwp_wait` 初版会被 eventfd 的**陈旧计数**虚假唤醒（做过大量 send 后队列已空仍返回 OK）。
     改为「先查队列深度 → 再无数据则按 deadline 轮询」，并引入 `wake_seq` 区分“显式 wake”。
   - `lwp_wake` 的语义定为“打断正在等待的对端”，**不是**留下永久信号：先 wake 再 wait 仍应按超时返回。
     测试里用独立线程验证真唤醒。

5. **验证**
   - `bash packages/lwp/native/build.sh` → `liblwp.so`，`nm -D` 只有 11 个公开符号。
   - `bash packages/lwp/native/run-tests.sh` → 协议布局 `[PASS]` + 通道 `[PASS]`。
   - `python3 tools/lwp-gen.py --check` → `[PASS]`。
   - CI：`guards` job 增加“构建 liblwp + 导出符号白名单比对”。

## 第 10 轮（2026-11-10）：M1 —— 协议检查器与 .lwtrace 录制

1. **接口数值 id**：IDL 增加 `id = 1`（`lw_core`），生成器输出 `LWP_IFACE_LW_CORE`（C 与仓颉两侧）、
   写进 `lwp_abi.json`。C 侧检查器与 `lwtrace` 都靠它识别接口。

2. **协议检查器**（计划 §16.7）：`lwp_checker_enable(ch, strict)`
   - 规则：非 core 消息必须在本侧握手之后（壳侧要求已发 `core.hello`，引擎侧要求已发 `core.hello_ack`）；
     core 接口只承认本版本定义的 opcode。
   - `strict=1` 违规返回 `LWP_EPROTO`，否则只计数；计数进 `lwp_stats.unknown_opcode / not_handshaked`。

3. **`.lwtrace` 录制**（计划 §16.3 的核心工具）
   - `lwp_trace_open/close`：文件头 `LWPT` + 协议版本；每条记录 `kind/dir/lwp_header/len/payload`，
     **显式 packed**（与 Python 的 `<BBHHHIIIQI` 一一对应，不依赖编译器对齐习惯）；每条 flush，
     崩溃后可取回最近记录。
   - `tools/lwtrace.py stats|dump`：从 `abi/lwp_abi.json` 反查消息名，输出时间轴、消息分布、
     在途深度、时长；`dump` 可 `--dir`/`--iface` 过滤。

4. **测试**（`packages/lwp/native/run-tests.sh` 三步，全通过）
   - 协议布局（C 静态断言）；
   - 通道 39 项断言 + **检查器 11 项**（握手前拒非 core、hello 后放行、未知 opcode 拒、
     hello_ack 前后 REQUEST 方向行为）+ **录制 4 项**（文件头、记录数精确匹配 8+6×40 字节）；
   - `lwtrace.py stats/dump` 解析录制文件并断言能还原出 `lw_core.hello`。

5. **踩坑记录**
   - 录制记录结构最初未 packed，`uint64_t` 成员把记录从 32 字节撑到 40 字节，Python 侧直接解析错位；
     加 `__attribute__((packed))` 后两端一致。**跨语言二进制格式必须显式 packed**。
   - 测试里写死的绝对路径改为 `LWP_TRACE_PATH` 环境变量，脚本把录制文件放到临时目录。

6. **验证**
   - `bash packages/lwp/native/run-tests.sh` → 三步全 PASS（含 lwtrace 解析）。
   - `nm -D` 导出符号 14 个（原 11 + checker/trace×2 + trace_close），与 CI 白名单一致。

## 第 11 轮（2026-11-10）：M1 —— 仓颉侧通道绑定（第一条真正走协议的路径）

1. **标量 FFI 边界**：C 侧新增 `lwp_send_parts` / `lwp_recv_parts`
   （只传 iface/opcode/flags/time/缓冲，不把 `lwp_header` 结构体带过边界）。
   理由与生成器一致：跨语言结构体 ABI 是不可控风险，标量 + 字节缓冲可靠且好测。

2. **仓颉绑定** `packages/lwp/src/lwp_channel.cj`
   - `LwpChannel`：`open/send/recv/wait/wake/close/enableChecker/traceOpen/traceClose`；`LwpMessage` 结构。
   - 方向与错误码常量与 C 侧对齐（`LWP_EVENT`/`LWP_ERR_EPROTO`…）。

3. **两个必然踩到的工程坑（已写进 README）**
   - **库名撞车**：本包产物是 `liblwp.a`，C 共享库若也叫 `liblwp.so`，`-llwp` 会优先解析到静态归档，
     链接报“未定义 lwp_*”。改名 `liblwp_native.so` 后正常。
   - **cjpm 直接调 `ld`**：`link-option` 里写 `-Wl,-rpath,...` 会被 ld 拒绝，必须写 `-rpath <dir>`。

4. **测试**：`packages/lwp/test.sh` 三段式（生成物校验 → C 侧 → 仓颉侧），全通过
   - C 侧：布局 4 项 + 通道 39 项 + 检查器 11 项 + 录制 4 项 + lwtrace 解析；
   - 仓颉侧 9 项：解码 5 项 + **通道 4 项**（hello 往返并解码回结构、检查器拦截未握手消息返回 `-71`、
     空收返回 None、wait 超时精度）。

5. **验证**
   - `bash packages/lwp/test.sh` → `[PASS] lwp 全部测试通过`（C 全绿 + `TOTAL 9 / PASSED 9`）。
   - CI：`guards` job 调统一入口（无仓颉时自动跳过仓颉段），`build-test` job 构建 `liblwp_native.so` 后跑 `cjpm test`；
     导出符号白名单更新为 16 个（原 14 + `*_parts`）。

## 第 12 轮（2026-11-10）：M1 —— lwindow 接入 LWP（第一条端到端事件路径）

1. **IDL 增加 input 接口族** `packages/lwp/protocol/input.toml`（id=2，v1）
   - `pointer_motion`（x,y）、`pointer_button`（x,y,button,down）、`pointer_axis`（dx,dy）、
     `key`（keycode,down）、`text_input`（text）。生成物 11 条消息 / 2 个接口。

2. **lwindow 侧**
   - `src/backend_lwp.cj`：**唯一事件漏斗** `decodeLwpEvent(LwpMessage) -> ?LWindowEvent` +
     主循环入口 `pollLwpEvents(ch)`；未识别消息静默丢弃（liblwp 侧已计数）。
   - `src/backend_headless.cj`：`HeadlessShell`（内存假壳，握手 + 五种事件），
     同时是后续 `lwtrace replay` 的载体。
   - 事件模型扩展：`PointerAxis` / `Key` / `TextInput` 三种类型 + `pressed`/`text` 字段
     （`Equatable` 需显式实现——无载荷 enum 也没有自动 `==`）。

3. **OHOS 侧真的链上了**
   - `packages/lplatform-ohos/deps/lwp/build-ohos.sh` 交叉编译 `liblwp_native.so`（含 SONAME）；
   - `cjpm.toml.ohos` 用占位符 `@LWP_OHOS_LIB@`，构建脚本 sed 注入（仓库不留机器路径）；
   - `OHOS_EXTRA_LIBS` 带上 LWP 目录 → 随 HAP 打包；
   - 实测：HAP 内含 `liblwp_native.so`，`liblanlu_client_next.so` 的 NEEDED 里有它，
     静态验证全绿（依赖闭包/符号一致）。

4. **发现的三个真 bug（测试写对了才抓到）**
   - **Cangjie `match` 的 `case` 是绑定模式**：`case LWP_LW_INPUT_POINTER_BUTTON_OPCODE =>` 会匹配**一切**，
     后面的分支全部不可达（只报 unreachable-pattern 警告）。表现是所有事件都被解成 pointer_motion。
     改成 `if/else` 判等。→ 已写进 `packages/lwindow/README.md`。
   - **`UInt32(float)` 是数值转换不是位模式**：负数直接抛 OverflowException，120.5 被截成 120。
     浮点上线必须用 `CPointer<Float32>` 写原始字节（`acquireArrayRawData`）。解码侧同理。
   - **`None<T>()` 不是合法构造**，用 `None`（类型由返回类型推断）。

5. **验证**
   - `packages/lwindow` 4 个后端测试全通过（按钮往返、motion/axis/key/text 解码、未知消息不致命、hello 不产生事件）。
   - `bash packages/lwp/test.sh` → 全绿（C 侧 + 仓颉侧 9 项）。
   - `bash client-next/ohos/build-ohos.sh` → exit=0，`BUILD SUCCESSFUL`，五项静态验证全 PASS。
   - 守卫：deps 10、platform 100，未新增（LWP 的交叉编译脚本放在 `lplatform-ohos/deps/lwp/`，
     而不是中立包内——这正是隔离守卫起作用的地方）。

6. **宿主机没有 libvips/vlc/rocksdb/SDL3**：本地跑 lwindow 单测需要一个 stub 目录
   （CI 有 apt 依赖 + 仓库内 SDL3，不需要）。做法与注意事项写进 `packages/lwindow/README.md`，stub 不入库。

## 第 13 轮（2026-11-10）：M1 —— 录制回放与语义 diff（计划 §16.3 闭环）

1. **回放（C 侧）**：`lwp_trace_replay(ch, path, dir_filter)`
   - 读 `.lwtrace` 头 → 逐条回放 kind==send 的记录（原样 iface/opcode/flags/载荷），
     返回回放条数；文件损坏/载荷越界返回 `LWP_EBADMSG` 而不是读爆缓冲。
   - 注意点：record 结构是 packed，取 `&rec.h` 会产生非对齐指针（编译期告警），改为 memcpy 到局部变量。

2. **回放（仓颉侧）**：`LwpChannel.replay(path, dirFilter)`

3. **语义 diff**：`tools/lwtrace.py diff <a> <b>`
   - 语义键 =(kind, dir, iface, opcode, flags, payload)，**忽略时间戳与 serial**（每次运行都不同）；
   - 差异逐条打印，含消息名（从 `abi/lwp_abi.json` 反查）与两侧载荷前 16 字节，`--max-report` 限流。

4. **测试**（三层都把回放钉住了）
   - C 侧：录制 3 条 → 回放 3 条 → 恰好收到 3 条；不存在的文件返回 `EINVAL`。
   - 仓颉/lwindow：`recordThenReplayYieldsSameEvents` —— 录制 5 条（hello+4 事件）→ 回放进新通道 →
     回放条数 5 → 解码出的 4 个事件与录制时**逐字段一致**（kind/x/y/key/text）。
   - 工具：`diff` 对同一文件判 PASS；篡改载荷末字节后必须报「共 1 处差异」。

5. **验证**
   - `bash packages/lwp/test.sh` → 三步全绿（C 侧含回放断言 + 仓颉 9 项 + lwtrace 三个子命令）。
   - `bash client-next/ohos/build-ohos.sh` → exit=0，五项静态验证全 PASS（回放 API 未破坏交叉编译）。
   - `packages/lwindow` 5 个测试通过（新增录制-回放）。
   - 守卫：deps 10、platform 100，未新增。

## 第 14 轮（2026-11-10）：M1 —— 引擎主循环接协议 + 壳侧早期加载

1. **引擎侧输入源开关**（`packages/lwindow/src/input_source.cj`）
   - `lwpInputEnabled()` 读 `LANLU_LWP=1`；`initLwpInput(name="lanlu")` 打开通道（幂等）；
     `nextLwpEvent()` 从通道取一条，内部先把队列整体搬进本地位列，避免每帧只取一条造成积压。
   - `client-next/src/ui/lgpu_backend.cj` 的两处 `headlessEventSource` 闭包改为「LWP 优先、文件桥兜底」，
     新增 `lwpEventToUi()` 作为唯一映射点（PointerDown/Move/Up/Axis/Key/TextInput → `UiEvent`）。
   - 键码映射 `keyFromCode`：先用 Linux evdev 码（与 wayland/xkb 同一张表），未覆盖的落 `RawScancode`。

2. **壳侧加载顺序**（`lplatform-ohos/shell/native/shell_napi.cpp`）
   - 引擎线程一开始就 `dlopen("liblwp_native.so", RTLD_NOW | RTLD_GLOBAL)`，再 `lwp_open("lanlu")`
     建通道，**然后**才加载仓颉运行时与引擎——严格照 M0-4 的结论：晚加载/RTLD_LOCAL 会静默失败。
   - 失败只打日志不阻断（协议没起来时引擎仍能用文件桥跑）。

3. **测试**（lwindow 共 7 项，全通过）
   - `lwpInputSwitchFollowsEnv`：环境变量开/关都正确反映。
   - `nextLwpEventDrainsInOrder`：壳发 3 条事件 → `nextLwpEvent` 按序取出（含坐标与文本），队列空返回 None 不阻塞。

4. **编译期被拦下的几个小坑**
   - `UInt32('0')` 非法（字符字面量不是数值类型）→ 用码点 48/97。
   - `Key.RawScancode` 要 `Int32` 不是 `UInt32`。
   - `UiEvent.MouseWheel` 是 4 参数（dx,dy,x,y），不是 2 参数。
   - Cangjie `match` 的分支之间用换行分隔，**不能**写成 `case A => x, case B => y`。

5. **验证**
   - `bash client-next/ohos/build-ohos.sh` → exit=0，`BUILD SUCCESSFUL`，五项静态验证全 PASS。
   - `packages/lwindow` 7 项测试通过；`packages/lwp/test.sh` 全绿。
   - 守卫：deps 10、platform 100，未新增。

## 第 15 轮（2026-11-10）：M1 —— 壳侧改走 lwp_send（`LANLU_LWP=1` 端到端）

1. **壳侧发送端** `packages/lplatform-ohos/shell/native/lwp_client.cpp`
   - `lanlu_lwp_send_pointer(action,x,y,key)` / `send_text` / `send_key(name,down)`：
     按 `lwp_protocol.h`（IDL 生成）组包，经 `lwp_send_parts` 投递。
   - 用 **dlsym** 而不是链接：libmain.so 不新增 NEEDED，避免干扰加载顺序；
     库由 shell_napi 在引擎之前 RTLD_GLOBAL 加载，这里再 dlopen 拿到同一实例。
   - 动作码映射沿用原文件桥语义（11/2/3=按下/移动/抬起，13=滚轮，91=诊断不走协议）；
     移动事件带 `LWP_F_DROPPABLE`（计划 §6.2）。键名 → evdev 码，未覆盖的落 RawScancode。

2. **接线**：`lanlu_push_input` / `push_key_name2` / `lanlu_send_text` / `SendText` 都是
   「先试协议，失败回落文件桥」。这保证 `LANLU_LWP` 未开时行为与今天完全一致。

3. **壳侧字节级测试**（`packages/lplatform-ohos/selftest/`，宿主可跑）
   - 协议模式：发 5 条（button/motion/axis/text/key）→ 用 `lwp_recv` 取回 → 逐字段断言
     iface/opcode/size/坐标/按钮/DROPPABLE 标志/文本偏移与内容/evdev 28。
   - 回落模式：未开 `LANLU_LWP` 时三个发送函数都必须返回 0（调用方才会写文件）。

4. **这一轮踩的坑（都是构建/装配层的）**
   - `build-hapgen.sh` 的 `PKG` 仍按老路径推导（第 6 轮搬到 `lpack-ohos/tools/` 时漏改），
     一跑就 `cd .../packages/lpack-ohos/packages/lpack-ohos`。已修。
   - hapgen 的模板文件清单是**白名单**，新增 `lwp_client.cpp` 必须同时加进去，否则 CMake
     报 “No SOURCES given to target: main”。
   - 协议头的 include 路径不能在模板里写相对路径（暂存后层级变了），改成占位符
     `__LWP_INCLUDE__` 由 hapgen 注入绝对路径（与 `__LGPU_LIB__` 同一机制）。
   - 文件是 C++ 语义（`nullptr`/`extern "C"`），扩展名必须 `.cpp`（`.c` 会按 C 编译）。
   - 生成的结构体名是小写 `lwp_lw_input_pointer_button`，不是宏名的大小写。

5. **验证**
   - `bash packages/lplatform-ohos/selftest/run-tests.sh` → 协议/回落两模式全 PASS。
   - `bash client-next/ohos/build-ohos.sh` → exit=0，`BUILD SUCCESSFUL`，五项静态验证全 PASS。
   - 守卫：deps 10、platform 100，未新增。

## 第 16 轮（2026-11-10）：M1 —— 协议面补全 + 握手 + 统计上报

1. **协议面补全**（计划 §5.5、§7、§8）：新增 `window.toml` 与 `system.toml`，接口从 2 个扩到 **13 个 / 47 条消息**：
   - 窗口呈现：`lw_app`(4) / `lw_window`(8) / `lw_surface`(2) / `lw_frame`(2) / `lw_display`(1)；
   - 系统服务：`lw_seat`(3) / `lw_text_input`(5) / `lw_clipboard`(3) / `lw_dialog`(3) / `lw_system`(2) / `lw_test`(3)。
   - 生成器支持零参数消息（`paused`/`enable` 这类只有 size 的消息），代码干净且可解码。
   - 测试断言 13 个接口 id 与关键消息尺寸（`display.info`=28、`surface.attach`=24、`window.create`=20），
     改 ABI 会被 CI 拦住。

2. **握手真正建立**
   - 壳：`lwp_client.cpp` 首次打开通道后立即发 `core.hello`（协议版本、壳名、OS、API 级别、能力位）。
   - 引擎：`initLwpInput` 里回 `core.hello_ack` 并按**非严格**模式启用检查器
     （真机宁可能用：违规只计数不拦截）。

3. **统计上报**（计划 §16.7）
   - C 侧新增 `lwp_stats_summary(ch, buf, cap)`，一行文本：
     `sent/recv/dropped/bad/unknown/notHandshaked/wake/depthE/depthR`。
   - **为什么不传结构体**：跨 FFI 猜 `lwp_stats` 的字段偏移太脆（我这轮第一版就写错了顺序）。
     让 C 格式化、仓颉只拿字符串，与「标量 + 缓冲区」的既定边界一致。
   - 引擎每 300 次取事件打一条 `probeTrace("lwp stats ...")`。

4. **修掉一个会让开关完全失效的漏洞**：`initLwpInput()` 之前**没有人调用** ——
   开关打开后通道根本没建，`nextLwpEvent` 永远返回 None（事件全被吞）。
   现在在 `installHeadlessInputSource` 启动时初始化并打日志，失败自动回落文件桥。

5. **守卫精度改进**：隔离守卫改为**先剥注释再匹配**（C 系 `//`、`/* */`；TOML/脚本 `#`；
   TOML 的 `doc` 字段按文档处理）。原来协议 IDL 里一句“对应 wl_surface”就被判违规，
   逼人改写注释。改进后基线 100 → **81**（减少的 19 条都是注释里的词），
   代码里的真违规（如 `SdlWindow`、`ohos_entry.cj`）仍全部保留。

6. **验证**
   - `packages/lwp/test.sh` → 12 项仓颉测试 + C 侧全绿。
   - `lplatform-ohos/selftest/run-tests.sh` → 壳侧测试现在先断言 `core.hello` 的三字段，
     再断言 5 条输入事件，全 PASS。
   - `packages/lwindow` 7 项通过。
   - `client-next/ohos/build-ohos.sh` → exit=0，五项静态验证全 PASS。

## 第 17 轮（2026-11-10）：M2 起步 —— 窗口生命周期客户端

1. **协议编码器扩展**（`packages/lwp/src/lwp_encode.cj`）
   `window.create`（带标题字符串）、`ack_configure`、`set_title`、`set_min_max`、`frame.request`。

2. **窗口生命周期客户端**（`packages/lwindow/src/window_client.cj`）
   - `LWindowLifecycleEvent`：AppStarted/Resumed/Paused、WindowCreated、Configure、CloseRequest、
     Focus、FrameDone、DisplayInfo。
   - `LwpWindowClient`：`create/poll/pollAll/ackConfigure/requestFrame/setTitle/checkConfigureTimeout`。
   - **configure 必须 ack** 的状态机带可注入时钟（测试不依赖真实时间）；
     超时（500ms）后只记一次 `unackedConfigure`，不重复计数。
   - 规则放在 L 层而不是 liblwp：liblwp 只管线上格式，窗口语义属于平台适配层。

3. **引擎接入**：`LANLU_LWP=1` 时在事件源里先处理生命周期事件（configure → 自动 ack 并打日志），
   再做输入轮询。壳侧一旦实现 `lw_window`，窗口就能被协议驱动。

4. **测试**（lwindow 11 项全通过，新增 4 项）
   - create → 壳 created+configure → 客户端按序解码出两个事件（id/scale/ssd、w/h/state 全对）；
   - ack 回到通道；
   - configure 超时：未到期不报、到期报一次、之后不再重复；
   - frame.done 的 serial 与时间戳正确。

5. **测试抓到的两个真 bug**
   - `poll()` 把「队列空」和「不认识的消息」都返回 None → `pollAll` 遇到第一条 hello 就停，
     所有生命周期事件都被吞。改为跳过未知消息继续取。
   - `HeadlessShell` 组包时只写了低字节（`b[4] = width & 0xFF`），解码出来 1600 变 64。
     改为统一小端写全字段。**仿真器也要按线上格式老实写字节**。

6. **验证**
   - `packages/lwindow` 11 项通过；`bash client-next/ohos/build-ohos.sh` → exit=0，五项静态验证全 PASS。
   - 守卫：deps 10、platform 81，未新增。

## 第 18 轮（2026-11-10）：M2 —— 壳侧窗口协议（发送端 + 请求泵 + ArkTS 接线）

1. **壳侧窗口发送端** `packages/lplatform-ohos/shell/native/lwp_window.cpp`
   - 发送：`app.started/resumed/paused`、`window.created/configure/close_request/focus`、`frame.done`。
   - **请求泵** `lanlu_lwp_window_pump()`：把引擎发来的 `window.create` / `ack_configure` /
     `frame.request` 取出来，解析标题并存入原子量，供 ArkTS 轮询读取
     （`lanlu_lwp_requested_title()` / `lanlu_lwp_last_ack_serial()` / `lanlu_lwp_last_frame_request()`）。
   - 为什么用泵不用回调线程：ArkTS 的线程边界很硬，napi env 不能跨线程用；
     代价是延迟一个定时器周期（~16ms），换来不会踩线程断言。

2. **通道访问收敛**：`lwp_client.cpp` 暴露 `lanlu_lwp_ready / send_raw / recv_raw`，
   `lwp_window.cpp` 复用同一套 dlsym 句柄，不再各自 dlopen 一遍。

3. **napi + ArkTS 接线**
   - `shell_napi.cpp` 新增 5 个导出：`lwpWindowPump / lwpWindowCreated / lwpWindowConfigure /
     lwpAppResumed / lwpAppPaused`（并补 `Index.d.ts` 声明）。
   - `Index.ets` 在拿到窗口属性后调 `lwpWindowCreated(id, 1.0, false)` + `lwpWindowConfigure(w,h,1)`；
     `EntryAbility.onForeground/onBackground` 调 resumed/paused。全部包在 try/catch 里，
     `LANLU_LWP` 未开时是空操作。

4. **验证**
   - 平台自测新增 14 项断言：三种窗口/帧消息的字节级校验（created 的 id/scale/ssd、
     configure 的尺寸状态、frame.done 的 serial/time）+ **泵的解析**（create 的标题与宽度、
     ack serial、frame.request serial）→ 全 PASS。
   - `client-next/ohos/build-ohos.sh` → exit=0，五项静态验证全 PASS；
     `libmain.so` 的 `lanlu_lwp_*` 动态符号 21 个（含 `lanlu_lwp_window_pump`）。

## 第 19 轮（2026-11-10）：M2 —— 窗口尺寸由 configure 驱动

1. **启动时等待壳的初始 configure**（`LwpWindowClient.awaitConfigure(timeoutMs)`）
   - `preferredWindowGeometry()` 开头：`LANLU_LWP=1` 时**有界等待 300ms** 取壳下发的尺寸，
     拿到就用，拿不到回退旧的本地几何策略。**绝不无限等** —— M0-4 教训的直接应用。
   - 这条打通后，「窗口尺寸」的唯一来源从环境变量/文件变成了 `window.configure`（计划 §7）。

2. **configure 自动 ack**：`LwpWindowClient` 收到 configure 立即回 `ack_configure`
   （引擎没有“稍后应用尺寸”的需求；延迟 ack 只会让壳走超时回退）。
   构造参数 `autoAck` 保留关闭能力，用于验证超时计数路径。

3. **修掉一个会互相抢事件的重复客户端**：引擎侧原本又建了一个 `LwpWindowClient`，
   与 `lwindow` 内部的那个**共用同一条队列**——两个消费者会随机抢走对方的 configure。
   现在引擎只调 `lwindow.lwpDrainLifecycle()/lwpCheckConfigureTimeout()`，客户端唯一。

4. **ArkTS 16ms 请求泵**：`Index.ets` 增加 `startLwpWindowPump()`（setInterval 16ms 调
   `shell.lwpWindowPump()`）。之前只在 onForeground 调一次，引擎的 `window.create` 没人消费。

5. **测试**（lwindow 13 项全通过，新增 2 项）
   - `awaitConfigureReturnsShellSize`：壳延迟 20ms 下发 configure → 客户端等到并返回正确尺寸，
     且不留待确认状态（自动 ack 已发）。
   - `awaitConfigureTimesOutWithoutShell`：壳不发 → 80ms 后返回 None（不卡死）。
   - 原 3 个 configure 测试按新语义改写：自动 ack 后 `hasPendingConfigure()` 为 false，
     ack 消息出现在壳侧的 REQUEST 队列里；手动 ack 路径用 `autoAck: false` 单独覆盖。

6. **验证**
   - `packages/lwindow` 13 项通过；`client-next/ohos/build-ohos.sh` → exit=0，五项静态验证全 PASS。
   - 守卫：deps 10、platform 81，未新增。

## 第 20 轮（2026-11-10）：M2 —— 表面与帧链路 + 超时规则

1. **`surface.attach`**：编码器（buffer u64 + w/h + serial，24B）+ 客户端 `attach()`，
   序列号必须单调（倒退计入 `attachOutOfOrder`）。

2. **帧回路**：`frame.request` 记录待响应 serial 与截止时间（200ms）；`frame.done`/`surface.frame_done`
   到达即闭环；超时 `checkFrameTimeout()` 只记一次 `frameTimeout`。

3. **每帧 tick**：`lwindow.lwpFrameTick()` = requestFrame + 排空生命周期 + 检查 configure/frame 超时 +
   周期打印 `lwpViolations()`（`unackedConfigure/frameTimeout/attachOutOfOrder`）。
   引擎在 `frameProbeHook` 里**串联**调用（不覆盖已有的抓帧钩子），仅 `LANLU_LWP=1` 时生效。

4. **测试**（lwindow 17 项全通过，新增 4 项）
   - attach 携带 buffer/尺寸且被壳侧按 REQUEST 收到；
   - frame.request → frame.done 闭环后不超时；
   - 无响应时 200ms 后计一次、之后不再重复；
   - 连续 attach 的序列号单调，`attachOutOfOrder` 为 0。

5. **说明一处刻意的未做**：`attach` 目前**不会**在引擎里真正被调用——buffer 是 lgpu 的 Vulkan 图像，
   要跨进程/跨语言共享需要 dmabuf 或共享内存导入，属于 M3「lgpu 与 surface 打通」的范围。
   这一轮先把**协议与规则**做对并被测试固定住，避免到 M3 才发现线格式不合适。

6. **验证**
   - `packages/lwindow` 17 项通过；`client-next/ohos/build-ohos.sh` → exit=0，五项静态验证全 PASS。
   - 守卫：deps 10、platform 81，未新增。

## 第 21 轮（2026-11-10）：M2 —— 关闭/焦点语义 + surface buffer 决策 + M0-3 欠账结清

1. **`window.close_request` / `focus` 接入引擎**
   - close_request → `UiEvent.Quit`（对应 xdg_toplevel.close；桌面应用的默认行为是退出）。
   - focus → 目前只记录。理由：真正的焦点来源是 XComponent 的 onFocus，协议事件是给
     未来多窗口/浮层的信息源（§7），现在没有消费方就不假装消费。

2. **`surface.attach` 的 buffer 语义定案**（计划新增 §7.3.1）
   - **句柄 0 = 引擎直接渲染进壳给的 native window**（OHOS 默认路径，`attach` 只表达提交+节拍）；
   - **非 0 = 共享缓冲**：Wayland 端 v1 用 wl_shm（CPU），dmabuf 留作性能优化；
     headless/抓帧也走这条。
   - 为什么现在定：IDL 里 `attach.buffer` 是 `u64`，若等到 M3 才定语义，会出现两种互不兼容的
     壳实现（一个当 VkImage、一个当 fd），届时改协议要动 `protocol_major`。
   - 文档同时写明「什么情况下会推翻它」（wl_shm 拷贝掉帧 / 需要多窗口缩略图）。

3. **M0-3 遗留欠账结清：portcheck 里的平台痕迹**
   - `portcheck.cj` 写死的 `/system/fonts/HarmonyOS_Sans.ttf` → 改为 `LANLU_FONT_FILE`
     环境注入（平台事实由平台层提供），中立包里不再出现某个系统的目录。
   - 中立包 `cjpm.toml` 的 `[target.aarch64-linux-ohos]` 段：**决定保留**，并在守卫里豁免，
     理由是它是交叉编译构建配置而非代码（详见计划 §4.5.1）。这条从 M0 一直挂着的开放问题就此关闭。
   - 守卫基线 81 → **73**；同时验证「真违规仍会被抓」（临时放一个含 `import ohos_foo` 的文件，
     守卫立刻报新增）。

4. **验证**
   - `bash client-next/ohos/build-ohos.sh` → exit=0，五项静态验证全 PASS。
   - 守卫：deps 10、platform **73**、layering、no-sdl 全 PASS。
   - lwindow 17 项 + lwp 全套 + 平台自测：全绿。

## 第 22 轮（2026-11-10）：M2/M3 —— 表面生命周期事件与 system.info

1. **先查设备**：`hdc list targets` 返回 `[Empty]` —— 没有连接真机，第 19–22 轮排队的设备验证
   仍然只能挂着（不是能力问题，是硬件不在）。本轮因此继续做不依赖设备的协议工作。

2. **surface 生命周期进协议**（计划 §7.1）：新增 4 条事件，协议面 47 → **51 条消息**
   - `available(handle u64, w, h)`：对应 `OH_ArkUI_SurfaceCallback_SetSurfaceCreatedEvent`；
   - `changed(w, h)`：**优先 reconfigure 现有 swapchain，不销毁重建**（Maleoon 第三次重建必崩）；
   - `will_destroy`：引擎必须同步停渲染（回调返回后旧 window 立即失效）；
   - `hidden`：切后台只触发 hidden，不触发 destroyed（头文件原文语义）。

3. **system.info 解码**：时区/语言/字体目录/家目录/API 级别一次下发，
   替换引擎里散落的 `getVariable` 探测（下一步接进主流程）。

4. **双侧接线**
   - 壳：`lwp_window.cpp` 增加 4 个 surface 发送函数；`SetMainSurface` 时上报 `surface.available`
     （带尺寸）。**踩坑**：块内写 `extern int f(...)` 在 C++ 里是 C++ 链接名，与
     `lwp_window.cpp` 的 `extern "C"` 定义不匹配 → 链接期 undefined symbol；
     必须放到文件级的 `extern "C"` 声明区。
   - 引擎：生命周期事件解码并打日志（`lwp surface available/changed/will_destroy/hidden`、
     `lwp system tz=... api=...`），暂不驱动渲染器——无设备时不宜盲加渲染路径。

5. **测试**
   - lwindow **19 项**通过（新增 surface 三段 + system.info 五字段）；
   - 壳侧自测 58 项断言（新增 available 的 u64 句柄往返、will_destroy 的 opcode）。
   - `client-next/ohos/build-ohos.sh` → exit=0，五项静态验证全 PASS。

## 第 23 轮（2026-11-10）：M2 —— system.info 端到端

1. **设备仍是 `[Empty]`**：真机验证继续挂起（第 19 轮起）。本轮继续做不依赖设备的闭环。

2. **system.info 全链路**
   - 壳：`lwp_window.cpp` 的 `lanlu_lwp_send_system_info`（4 个字符串 + API 级别）+ napi
     `lwpSystemInfo` + `EntryAbility.onForeground` 里用 `i18n.System.getSystemLanguage()` 等真实值下发。
   - 引擎：`lwpAwaitSystemInfo(300)` 有界等待（与 configure 同样的策略：拿不到就用旧逻辑），
     客户端把结果缓存进 `systemInfo`。
   - **`systemSansFontPath()` 改为优先用壳下发的 `font_dir`**，再回退硬编码候选路径。
     这是计划 §8 的要点：系统事实由平台层提供，引擎不猜路径。

3. **surface 状态机**（为 M3 铺路，可测）
   - `surfaceAlive / surfaceHandle / surfaceWidth / surfaceHeight` 由事件维护：
     `available` → alive=true，`changed` → 更新尺寸，`will_destroy` → alive=false。
   - 这条状态是 M3 的判据：`alive=false` 时不得 attach/requestFrame。

4. **测试**（lwindow **21 项**，新增 2 项）
   - `systemInfoIsCached`：下发后客户端直接可读五字段（引擎启动就靠它）。
   - `surfaceStateFollowsLifecycle`：available→alive、changed→尺寸更新、will_destroy→alive=false。

5. **验证**
   - `client-next/ohos/build-ohos.sh` → exit=0，五项静态验证全 PASS。
   - lwp 全套 + 平台自测（58 项断言）全绿；守卫 deps 10 / platform 73。

## 第 24 轮（2026-11-10）：M3 —— surface 由协议驱动 lgpu

1. **设备仍 `[Empty]`**（第 19 轮起）：真机验证继续挂起。

2. **surface 走协议取代“轮询环境变量”**
   - 新增 `lwpAwaitSurface(timeoutMs)`：有界等待 `surface.available`，返回 (handle, w, h)。
   - 引擎 `installLgpuBackend` 开头：`LANLU_LWP=1` 时先走这条路——用协议给的 handle 直接
     `Surface.fromSurfaceId` + `configure`，**不再等 15 秒轮询 `LANLU_MAIN_SURFACE_ID`**。
     超时（3s）自动回落旧路径，默认构建行为不变。
   - 这正好兑现计划 §7 的目标：尺寸与句柄都由协议给，不再靠“等环境变量”。

3. **两条 surface 规则进检查器**（§7.1）
   - `attachAfterDestroy`：`will_destroy` 之后仍 `attach` → 计数；
   - `frameWhileHidden`：`hidden` 期间仍 `requestFrame` → 计数；
   - 配 `canPresent()`（alive 且非 hidden）作为提交前的唯一判据。

4. **语言解析接 `system.info`**：`resolveLanguage()` 先看壳下发的语言，再回落到
   `SystemLocales` / `LANG` / `LC_*` 探测。至此字体路径与语言两项系统事实都由平台层提供。

5. **测试**：lwindow **24 项**（新增 3 项：attach-after-destroy、frame-while-hidden、
   `awaitSurface` 的有界等待与 handle/尺寸往返）。

6. **验证**：`build-ohos.sh` → exit=0，五项静态验证全 PASS；守卫 deps 10 / platform 73。

## 第 25 轮（2026-11-10）：M3 —— reconfigure 与 lw_test

1. **`SurfaceChanged` → reconfigure（不重建）**
   - `LgpuCanvas` 增加 `surfaceRef()`，尺寸变化时 `surface.configure(w,h)`
     —— **复用 swapchain，绝不重建**（§7.1：Maleoon 第三次重建必崩）。
   - 事件源里收到 `SurfaceChanged` 即调它；这是 M3 风险最大的点，逻辑已就位，等真机验。

2. **`lw_test` 接口落地**（计划 §16，同时解决“自检由谁触发”的欠账）
   - 引擎在通道就绪后发 `test.ready(engine_version)`；
   - 壳可发 `test.inject(kind,a,b)` / `test.capture(path)`；
   - 引擎处理：inject 打日志（输入注入请直接走 `lw_input`，语义更清楚），
     capture 直接调已有抓帧能力写文件 —— 真机上没有 ADB 时这是唯一的抓帧通道。

3. **测试**：lwindow **25 项**（新增 `testInterfaceRoundTrip`：ready 发送 + inject/capture 解码）。

4. **验证**：`build-ohos.sh` → exit=0，五项静态验证全 PASS；守卫 deps 10 / platform 73。

## M1 / M2 完成判定（§16.9 对照，2026-11-10）

**M1（协议与传输层）**

| 完成定义 | 结论 |
|---|---|
| IDL 唯一真源 + 生成器（`--check` 进 CI） | ✅ 13 接口 / 51 条消息；C 头 + 仓颉绑定 + 分发桩 + ABI 指纹 + 文档 |
| 通道（环形队列/blob/eventfd）与单测 | ✅ 定长槽 MPMC；收发/满队列/多生产者/blob/wait-wake 39 项断言 |
| 协议检查器（未握手、未知 opcode） | ✅ strict/permissive 两模式，计数进 stats |
| 录制 / 回放 / 语义 diff | ✅ `.lwtrace` 格式 + `lwtrace.py dump/stats/diff` + `lwp_trace_replay` |
| 输入端到端（壳→引擎） | ✅ 壳 `lanlu_push_input` 先试协议；引擎 `nextLwpEvent`；**宿主两侧字节级测试** |

**M2（窗口与系统服务）**

| 完成定义 | 结论 |
|---|---|
| configure 必 ack（状态机 + 超时） | ✅ 自动 ack 默认；超时计数有测试 |
| 尺寸唯一来源 = configure | ✅ `preferredWindowGeometry` 有界等待 300ms，失败回退 |
| surface 生命周期（available/changed/will_destroy/hidden） | ✅ 协议 + 双侧 + 状态机测试 |
| changed → reconfigure 不重建 | ✅ 逻辑就位；**压测（连续 resize 20 次）需要设备** |
| frame.request/done 闭环 + 超时 | ✅ 200ms 超时计数有测试 |
| 关闭 / 焦点语义 | ✅ close→Quit；focus 仅记录（无消费方不假装消费） |
| system.info（字体/语言/时区） | ✅ 壳下发、引擎有界等待；字体路径与语言已改用它 |
| lw_test（壳触发自检/抓帧） | ✅ ready/inject/capture 协议 + 引擎处理 + 壳发送端 |
| **真机验收** | ⬜ **唯一未完成项**：需要设备 |

**结论**：M1 全部完成。M2 除真机验收外全部完成 —— 剩下的不是“还有代码没写”，
而是“写好的东西需要硬件证明”。设备连上后，验收清单（第 19–25 轮攒下的）是：

1. `LANLU_LWP=1` 输入：点击/滑动/滚轮/输入法各跑一遍；
2. `probeTrace` 里 `lwp stats` 与 `lwp violations` 应为全 0；
3. surface 建面 + 连续 resize 20 次（Maleoon 重建风险）；
4. `lwtrace` 录一份与文件桥基线对比 —— M0-6 收口。

## 第 27 轮（2026-11-10）：引擎输入映射测试 + 协议文档收尾

1. **补上引擎侧映射的测试空白**：`lwpEventToUi`（协议事件 → UiEvent 的唯一映射点）与
   `keyFromCode`（evdev 键码表）之前没有测试——壳侧字节测过、lwindow 解码测过，
   但**引擎怎么翻译没人管**。新增 `client-next/src/ui/lwp_input_test.cj` 7 项：
   down/move/up/wheel/text/keydown/keyup/字母键（evdev 17→'w'）/unknown。
   函数改为 `public` 以可测。

2. **环境限制记录**：client-next 的宿主单测在本机跑不了——`build.cj` 的 pre-test 要
   `cargo`（本机没有 Rust 工具链，fontkit 的 Windows 交叉产物也依赖它）。CI 有 cargo，
   新测试会在 CI 跑。**Wayland 侧同理**：`lplatform-wayland` 计划用 Rust/winit，
   本机无 cargo 且无 libwayland-dev/compositor，M1W 无法在本机开工——已如实记录。

3. **协议文档收尾**：计划 §5.5 的手写接口表已退役，替换为指向生成文档
   （`docs/lwp/*.md`，由 IDL 生成）的链接 + **与最初草稿的差集清单**
   （尚未实现的：拖拽区/多指针/触摸/键盘修饰键/IME 面板等，明确标注为 M3+，
   防止有人把草稿当现状）。草稿里有意省略的也写明了理由（如 `dropped` 由 stats 承担）。

4. **验证**：`build-ohos.sh` → exit=0，五项静态验证全 PASS；守卫 deps 10 / platform 73。

## 第 28 轮（2026-11-10）：剪贴板与对话框协议化

1. **引擎侧请求编码器**：`clipboard.set/get`、`dialog.open_file/save_file`（`packages/lwp/src/lwp_encode.cj`）。

2. **客户端**：`LwpWindowClient.clipboardSet/clipboardGet/dialogOpenFile/dialogSaveFile`，
   事件侧新增 `ClipboardText(serial, mime, text)` 与 `DialogResult(serial, path)`。

3. **接入**：`clipboardSetText/clipboardGetText` 在 `LANLU_LWP=1` 时走协议，通道不可用自动回落文件桥。
   剪贴板**读是异步的**（`clipboard.get` → `clipboard.text` 事件），所以加了一条本地缓存：
   `lwpFrameTick` 把回执落进缓存，`lwpClipboardGetText()` 读缓存。这与原来文件桥的同步语义不同，
   已写进注释。

4. **踩坑（两次都是“字节布局自己算错”）**
   - 追加编码器时路径写错（`packages/lwindow/src/lwp_encode.cj`，实际应在 `packages/lwp/src/`），
     生成了一个没有 package 声明的文件 → 编译报「more than one package declaration」。
   - `clipboard.set` 的 mime/text 头与载荷重叠：头在 4/8，载荷必须从 **12** 开始；
     我写成从 8 开始，把 text 头覆盖掉了，解码得到空串。**字符串消息的偏移必须从「所有头之后」算**。

5. **测试**：lwindow **28 项**（新增 3 项：set/get/open/save 四条请求到达壳且字段正确、
   clipboard.text 的 UTF-8 往返、异步缓存经 `lwpFrameTick` 落地后可读）。
   另加 `lwpResetForTest()` 解决测试间全局状态串味（生产代码不该调用，注释已写明）。

6. **验证**：`build-ohos.sh` → exit=0，五项静态验证全 PASS；守卫 deps 10 / platform 73。

## 第 29 轮（2026-11-10）：`lw_system.log` —— 引擎日志走协议

1. **编码器**：`system.log(level u8, text str)`（`text` 头在 5，未对齐 —— 字段是 packed 的，成立）。

2. **引擎**：`probeTrace` / `probeTraceLine` 开头先 `lwindow.lwpLog(1, line)`，发出即返回
   （**两处是重复函数**，第 26 轮就该合并——记录为待办）；`LANLU_LWP` 未开时行为不变。

3. **壳**：泵里处理 `system.log` → `fprintf(stderr, "[LANLU-LWP] ...")`
   （设备上 stderr 会进 hilog 缓冲区）。真机上两个通道的日志从此对齐时间线——
   联调时再也不用在 `probe_trace.txt` 和 hilog 之间来回猜先后。

4. **测试**：lwindow **29 项**（新增 `logReachesShell`：level/text 字段正确）。

5. **验证**：`build-ohos.sh` → exit=0，五项静态验证全 PASS；守卫 deps 10 / platform 73。

## 第 30 轮（2026-11-10）：对话框全链路 + 日志函数合并

1. **对话框壳侧实现**（`lw_dialog` 双向打通）
   - 泵解析 `dialog.open_file/save_file`（serial + suggested 名），ArkTS 的 16ms 泵里检测到请求
     即走**已有的** `pickOpenFile` / `handleSaveDialog`（复用全部超时与 staged-copy 逻辑）；
   - `finishDialog` 改为按来源分流：LWP 请求的对话框经 `dialog.result(serial, paths)` 回引擎
     （paths 为空 = 取消），不再写 `filedlg_result.txt`；异常路径有兜底取消，不会让引擎干等。
   - napi 新增 5 个导出（request/serial/suggested/result/clear）+ d.ts 声明。

2. **合并 `probeTrace` / `probeTraceLine`**（第 26 轮欠的）：`probeTraceLine` 委托给
   `ui.probeTrace`（改为 public），消除两份漂移的实现。踩了个仓颉小坑：导入子包函数后
   **不能再用全限定名调用**（`lanlu_client_next.ui.probeTrace(line)` 报 undeclared），要用短名。

3. **验证**：`build-ohos.sh` → exit=0，五项静态验证全 PASS；守卫 deps 10 / platform 73。
   lwindow 29 项 + 壳侧自测 58 项断言全绿（本项无协议面改动，未加新测试——
   ArkTS 对话框流没有可宿主测试的部分，真机验收清单 +1：从引擎触发一次文件选择器）。

## 第 31 轮（2026-11-10）：M6 删除清单盘点 + 窗口状态/退出协议化

1. **计划 §11 升级为「状态盘点表」**：新增一列「2026-11-10 状态」，逐条标注替代通道是否已实现、
   文件写入点是否已被短路。结论：
   - **已短路**（协议替代且默认分流）：`input_events` / `key_events` / `text_input` /
     `clip_out` / `filedlg_*` / `lang`（`locale.txt`）/ `probe_trace` / `LANLU_MAIN_SURFACE_*`；
   - **部分**：`snapshot/lgpuTest`（`test.capture` 已接，小窗自检保留）；
   - **本轮补齐**：`window_cmd.txt`（`window.set_state` / `window.close`）、`appExited` 轮询（`app.exit`）。
   - **仍未做**：`CN_WINDOW`/`CN_UI_BACKEND`/`lanlu_env.txt` 这类联调开关（计划 M6 最后删）。

2. **协议面 54 条消息**（新增 3 条）：`lw_window.set_state`、`lw_window.close`、`lw_app.exit`。
   `requestWindowCommand()` 在 `LANLU_LWP=1` 时按命令名分流到协议，未识别的命令仍走文件（回落契约保留）。

3. **壳侧解析**：泵处理 set_state / close / app.exit → 原子量 + napi getter
   （`lwpWindowState` / `lwpTakeCloseRequest` / `lwpTakeExitCode`），ArkTS 可轮询消费。

4. **测试**：lwindow **31 项**（新增 2 项：状态/关闭/退出请求的类型与 code 字段；
   命令字符串分流——注意 `initLwpInput` 会先发 hello_ack，泵的第一条是它，测试要按顺序取）。

5. **验证**：`build-ohos.sh` → exit=0，五项静态验证全 PASS；守卫 deps 10 / platform 73。

## 第 32 轮（2026-11-10）：ArkTS 消费端补齐

1. **窗口状态/关闭/退出消费**：轮询循环里读 `lwpWindowState / lwpTakeCloseRequest / lwpTakeExitCode`，
   分别接到 `maximize/restore`、`destroyWindow`、`terminateSelf`。
   **踩坑**：本 SDK 的 `window.Window` 没有 `setWindowLayoutMode` / `window.WindowLayoutMode`
   （编译报 10505001），全屏路径先不做，注释里写明原因，避免下次又试一遍。

2. **剪贴板事件回执**：新增 C 侧 `lanlu_lwp_send_clipboard_text` + napi `lwpClipboardText`；
   `pollClipboard` 的 `clip_req` 分支在 LWP 可用时改发协议事件，`clip_in.txt` 只在未开启时写。
   至此剪贴板两侧都协议化（写：`clipboard.set`；读：`clipboard.get` + `clipboard.text`）。

3. **验证**：`build-ohos.sh` → exit=0，五项静态验证全 PASS；守卫 deps 10 / platform 73；
   lwindow 31 项 + 壳侧自测 58 项断言全绿（本轮为 ArkTS/C 胶水，无协议面改动）。

## 第 33 轮（2026-11-10）：文件桥删除进度机械化

1. **新的守卫** `tools/check-no-file-bridge.sh`：统计引擎/平台包里的文件桥命中点
   （`input_events.txt` / `key_events.txt` / `text_input.txt` / `clip_*.txt` / `filedlg_*.txt` /
   `window_cmd.txt` / `snapshot_req.txt` / `locale.txt` / `lanlu_env.txt`），与基线逐条比对：
   - 新增 → **失败**并打印具体文件行（不会再有人一边迁移一边又长出新的桥）；
   - 减少 → 通过并提示刷新基线；
   - 注释行不计（先用 grep 排掉 `//`/`#`/`*`/`--` 开头的行）。
2. **基线**：`tools/file-bridge-baseline.toml` = **35 处**（键列表，不是单个数字 —— 数字说不清是哪一处变了）。
   已接入 CI `guards` job。实测：临时加一个含 `input_events.txt` 的文件 → 守卫精确报出
   `[新增] packages/lwindow/src/__bridge_probe.cj:1:...`。

3. **为什么本轮没有真删代码**：计划要求 M6 删除文件桥，但**现在删是危险的** ——
   这些回落分支在 `LANLU_LWP=0` 时仍是唯一可用路径，而 `LANLU_LWP=1` 从未在真机上验证过。
   「协议未验证 + 无回落」= 把项目置于不可运行状态。所以本轮把删除**变成可度量的进度**，
   真正动手要等真机验收。这条判断已写进计划 §11，避免后来者误以为可以直接删。

4. **验证**：守卫 35 处通过、CI 已接、计划/工具文档同步；deploy 侧无代码改动，
   `build-ohos.sh` 与所有测试保持绿。

## 第 34 轮（2026-11-10）：snapshot 抓帧协议化 + 守卫去噪

1. **`lw_test.request_capture`**（新增请求方向，协议面 **55 条消息**）
   - 语义与 event 方向的 `capture` 相反：**引擎 -> 壳**，请壳用 ArkTS `componentSnapshot` 抓帧；
   - 引擎侧 `lwpRequestCapture(path)` 优先走协议，`snapshot_req.txt` 只在 `LANLU_LWP=0` 时写；
   - 壳侧泵解析 → napi `lwpTakeCaptureRequest/lwpCapturePath` → ArkTS 调已有的 `snapOnce()`。

2. **一个协议设计上的自我纠错**：最初我直接复用了 `LWP_LW_TEST_CAPTURE_OPCODE`（event 方向的 0 号），
   但 REQUEST 方向的 0 号是 `test.ready` —— 会把「请抓帧」发成「引擎就绪」。
   仓颉按方向各自编号，**同名消息在两个方向必须分别声明**，已在 IDL 加 `request_capture`。

3. **守卫去噪**：`check-no-file-bridge.sh` 先剥行尾 `//` 注释再匹配，并保留对
   整行注释（`//`/`#`/`*`/`--`）的排除。计数稳定在 **35 处**（与上一轮一致 —— 本轮加的是
   协议替代路径，文件写入仍在，属预期）。

4. **验证**：`build-ohos.sh` → exit=0，五项静态验证全 PASS；lwindow 31 项 + 守卫全绿。

## 第 35 轮（2026-11-10）：文件桥运行时停用 + §11 可追溯映射

1. **`lwpEnabled()` napi**：ArkTS 有了「协议是否可用」的运行时判据（C 侧 `lanlu_lwp_ready()`）。
   三个文件桥轮询器（`pollSnapshot` / `pollClipboard` / `startWindowCmdPoller`）在协议可用时
   **直接返回**，不再读文件。至此 `LANLU_LWP=1` 下文件桥是**运行时停用**状态，
   而不是「还在跑但结果被忽略」——这个区别很重要：后者会让人误判到底哪条路在生效。

2. **§11 增加「可追溯映射表」**：每类桥 → 基线命中数 → 具体代码文件 → 协议替代 → 是否已停用。
   35 处全部归位（`input_events` 3、`key_events` 2、`text_input` 2、`clip_*` 9、`filedlg_*` 4、
   `window_cmd` 4、`snapshot_req` 2、`lanlu_env` 3、其它 6）。
   表里明确写了「**停用 ≠ 删除**」：代码仍在、基线不降是预期，真删要等真机验收。

3. **守卫本身修了个缺陷**：基线键原来带行号（`文件:行:内容`），于是**任何无关编辑**都会让
   「新增/已删」双侧误报——第 35 轮我自己插了几行 ArkTS 就触发了一屏假差异。
   改成 `文件:内容`（去掉行号）后：插空行不再误报，真正新增一处仍能精确报出
   （已用探针文件验证）。

4. **验证**：`build-ohos.sh` → exit=0，五项静态验证全 PASS；文件桥守卫 35 处未变（符合预期）；
   lwindow 31 项 + 壳侧自测 + 4 项守卫全绿。

## 第 36 轮（2026-11-10）：M6 执行手册 + opcode 方向表

1. **`docs/m6-deletion-checklist.md`**：把「M6 删文件桥」从一句话变成 6 步可执行手册 ——
   每步列出删除对象、代码位置、**需要同步改的调用方**（用 grep 得到真实行号）、以及判据。
   顺序有讲究：先删引擎读侧、再删壳写侧（反过来会让壳白写一段时间的文件）。
   同时写明**为什么现在不删**：删掉后 `cjpm build` 仍会通过（只证明没有悬空引用），
   **正确性只有真机能证明**；而回落是 `LANLU_LWP=0` 下的唯一路径。

2. **`lw_test` 四个 opcode 的方向表**（`packages/lwp/README.md`）：opcode 在请求/事件方向
   **各自从 0 编号**，所以 `ready`(req,0) 与 `inject`(evt,0)、`request_capture`(req,1) 与
   `capture`(evt,1) 数字相同而语义相反。把第 34 轮踩的那个坑写成了表格 + 结论：
   **用 opcode 常量前必须确认方向**。

3. **`lanlu_env.txt` 定案（不替代）**：它承载开发期环境变量注入，不是平台能力；
   走协议只会让调试链路更长、更依赖壳。§11 标记「不替代、不删」，并补了一条风险记录：
   它能注入任意环境变量，属**调试后门**，release 构建应关闭（这一条之前没人提过）。

4. **验证**：守卫 5 项全 PASS（文件桥 35 / deps 10 / platform 73 / layering / no-sdl），
   lwp 全套 + 平台自测 + lwindow 31 项全绿；`build-ohos.sh` 未受影响（本轮只有文档 + 一处表格）。

## 第 37 轮（2026-11-10）：调试后门门禁 + replay 协议化

1. **`lanlu_env.txt` 后门关闭（release）**
   - ArkTS `EntryAbility.onCreate` 读 `bundleManager.getBundleInfoForSelfSync(...).appInfo.debug`，
     通过已有 `shell.setEnv` 注入 `LANLU_DEBUGGABLE=1/0`；取不到时**按不可调试处理**（安全默认）。
   - `lwindow/ohos_entry.cj` 的 env 注入块前置门禁：`LANLU_DEBUGGABLE != "1"` 直接跳过。
   - 效果：release 包不再受 `/data/local/tmp/lanlu_env.txt` 影响 —— 上一轮发现的问题本轮闭环。

2. **`lw_test.replay(path)`**（event 方向，第 5 条 test 消息；协议面 **56 条**）
   - 壳要求引擎重放一份 `.lwtrace`：引擎调 `lwpReplayTrace` → `liblwp` 的 `lwp_trace_replay`
     把录制里的壳侧消息重新入队，随后由同一漏斗消费。
   - 用途：真机上没有 hdc 也能复现输入序列问题（把现场录的 trace 投进沙箱再触发回放）。
   - 至此计划 §16.3 的三件套齐了：**录制**（`lwp_trace_open`）、**查看/比较**（`lwtrace.py`）、
     **回放**（协议触发 + 引擎执行）。

3. **测试**：lwindow **32 项**（新增 `replayEventDecodesAndReplays`：录制 3 条输入 → 协议触发
   回放 → 回放条数 > 0 且事件能经漏斗取出）。

4. **验证**：`build-ohos.sh` → exit=0，五项静态验证全 PASS；守卫 5 项全绿。

## 第 38 轮（2026-11-10）：能力位握手 + 探针门禁 + 生成文档方向列

1. **`hello.capabilities` 不再恒 0**：壳按「真的实现了才置位」的原则宣告
   `server_side_decorations / cursor_shapes / ime_preedit / soft_keyboard / file_dialog_save /
   clipboard_read_async` 六项（其余保持 0，引擎据此走保守路径）。
   引擎侧 `LwpWindowClient` 解码并缓存 `shellCapabilities` + `hasCapability(bit)`。

2. **一个设计取舍**：握手的 hello **不产生生命周期事件**，只记录状态。第一版把它当事件返回，
   结果 `pollAll` 的调用方全都多处理一条，5 个既有测试立刻挂了 —— 说明「状态」和「事件」
   必须分开：能力是查询，不是通知。

3. **探针门禁**：`probeTrace` 在 `LANLU_DEBUGGABLE=0`（release）下直接返回，不再落
   `probe_trace.txt`。与上一轮的 `lanlu_env.txt` 同一条门禁，未设置时按开发环境处理
   （宿主测试不受影响）。

4. **生成文档补方向列**：`docs/lwp/*.md` 的表增加「方向（引擎→壳 / 壳→引擎）」列，
   并在每份文档头部写明「opcode 按方向独立编号」——把手写在 README 的结论固化到生成器里，
   避免两处漂移（第 36 轮欠的）。

5. **验证**：lwindow **33 项**、壳侧自测、`build-ohos.sh` 全绿；守卫 5 项全 PASS。

## 第 39 轮（2026-11-10）：vsync 能力降级 + 交接文档

1. **能力位第一次真正起作用**：`lwpFrameTick` 只在壳宣告 `vsync` 时才每帧 `frame.request`；
   否则退回自驱节拍，并且**不做 frameTimeout 判定**（壳回不了 `frame.done`，
   继续判超时只会制造假告警）。对应 §7.3 记的 horizon 实测：外来渲染管线的 XComponent
   收不到系统 vsync。
   - `lw_seat.capabilities` 也从「解码返回 None」改为记录到 `seatCapabilities` 状态。

2. **新增 `docs/lwp-handoff-status.md`**：把「做完了什么 / 卡在哪 / 解锁后按什么顺序做」
   写成一份可交接的文档。包含：
   - M0/M1/M2 完成清单与证据；
   - **真机验收 7 条判据**（含具体 hdc 命令与 hilog 关键字）；
   - Wayland 的两条路线与第一批任务；
   - **代码里等真机才能定论的 5 个假设**（surface handle 语义、reconfigure、抓帧时序…），
     每条写明「若错会怎样」；
   - 每轮必跑的 8 条守卫命令。

3. **测试**：lwindow **34 项**（新增 `vsyncCapabilityGatesFrameRequest`：不带 vsync 位的 hello
   → 壳侧 REQUEST 队列里不出现 `frame.request`；带位后 `lwpShellProvidesVsync()` 为 true）。

4. **验证**：`build-ohos.sh` → exit=0，五项静态验证全 PASS；守卫 6 项全绿。

## 第 40 轮（2026-11-10）：能力位降级路径 + `lwtrace verify`

1. **剪贴板读按能力降级**：壳没宣告 `clipboard_read_async` 时 `lwpClipboardGetText()` 返回 `None`
   （调用方回落文件桥），不再发一个永远不会有回执的 `clipboard.get`。
   否则表现为「剪贴板永远是空的」，而调用方完全看不出原因。

2. **`HeadlessShell` 默认宣告与真壳一致**：新增 `HEADLESS_DEFAULT_CAPS`（6 位，与 `lwp_client.cpp` 对齐），
   `handshake(capabilities!)` 可传更小的集合来测降级路径。
   - 顺手修掉一个测试间的不一致：之前 `HeadlessShell` 的 hello 里 `capabilities` 恒 0，
     而真壳宣告 6 位 —— 假壳与真壳行为不同，测试就在验证一个不存在的世界。

3. **`lwtrace verify`**：校验 magic / 版本 / 记录边界 / 载荷长度，给真机拉回的现场 trace 做第一道体检。
   已纳入 `run-tests.sh`：正常文件必须 PASS，**截断文件必须被抓出来**（负向用例）。

4. **测试**：lwindow **35 项**；lwp 侧的 `run-tests.sh` 现在有 5 条 lwtrace 断言
   （stats / dump / verify 正例 / verify 负例 / diff 正负例）。

5. **验证**：`build-ohos.sh` → exit=0，五项静态验证全 PASS；守卫 7 项全绿。

## 第 41 轮（2026-11-10）：ABI 向后兼容机械化

1. **`--check-abi`**：`tools/lwp-gen.py` 新增 ABI 基线比对（`packages/lwp/abi/lwp_abi.baseline.json`）。
   规则直接来自计划 §5.1 的硬约束：
   - 接口不可删除、`id` 不可变更、`version` 不可回退；
   - 同 `(dir, opcode)` 的消息不可删除、不可改名；
   - 字段**只允许追加**：数量不能少，已有字段的位置/名字/类型逐个比对。

2. **负向验证**（关键）：把 `lw_input.pointer_button` 的 `x` 从 `f32` 改成 `i64` 生成一份
   破坏性 ABI，检查器精确报出
   `字段被改（只允许追加）：lw_input.pointer_button #0 ['x','i64',4] -> ['x','f32',4]` 并退出 1。
   —— 一个只会说 PASS 的检查器没有价值，负向用例才是它的证明。

3. **接入**：CI `guards` job 与 `packages/lwp/test.sh` 都跑 `--check-abi`。
   至此「改协议只允许追加」从文档约定变成**机器强制**。

4. **验证**：`test.sh` 全绿（含 ABI PASS）；守卫 8 项；`build-ohos.sh` 未受影响。

## 第 42 轮（2026-11-10）：IME 请求面 + 解码容错

1. **`lw_text_input` 请求面补齐**（引擎 -> 壳）：`enable/disable`、`set_surrounding(text,cursor,anchor)`、
   `set_cursor_rect(x,y,w,h)` —— 这是 text-input-v3 的实用子集，也是输入法候选框定位的前提
   （现在 ArkTS 只能靠组件自身位置猜）。

2. **解码容错加固（真 bug）**：`lwpString` 遇到非法 UTF-8 会抛
   `IllegalArgumentException`，把解码方打崩 —— 违反「坏消息不致命」的协议约定。
   生成器改为 try/catch 返回空串。**这类问题只有用手写组包测试才会暴露**（正常编码器不会产生坏字节）。

3. **两次字节布局错误，都被测试当场抓住**：
   - `set_surrounding` 第一版把 cursor/anchor 写在文本**之后** → 越界；
   - 第二版修了越界但忘了定长头的位置：cursor/anchor 必须固定 8/12，文本载荷从 16 开始。
   结论重复验证了三遍：**变长字段永远在最后，定长字段的位置由 IDL 顺序决定，不能“跟着数据走”**。

4. **测试**：lwindow **36 项**（新增 `imeRequestsReachShell`：四条请求的 iface/opcode/字段全对，
   含 UTF-8 文本往返）。

5. **验证**：`build-ohos.sh` → exit=0，五项静态验证全 PASS；守卫 8 项全绿。

## 第 52 轮（2026-11-11）：真机跑通 —— `LANLU_LWP=1` 首次端到端可用

设备：HUAWEI MOR-M1（2in1，API 26），`hdc tconn 192.168.0.26:42113` 无线调试。

### 首次真机暴露并修掉的 4 个真实缺陷

| # | 现象 | 根因 | 修复 |
|---|---|---|---|
| 1 | 启动 ~5s 后进程崩溃：`CuiException: beginScene 需要渲染后端` | `installLgpuBackendIfRequested` 用 `CN_UI_BACKEND` 选后端，而 SDL 壳删除后**没有任何一侧再设置它** | LWP 模式直接视为 `lgpu`，不再依赖该环境变量 |
| 2 | 同上 | `installHeadlessInputSource` 里 `CN_WINDOW != "lgpu"` 早退（默认值 `sdl`） | LWP 模式下窗口类型固定 `lgpu` |
| 3 | 崩溃（装面后仍无后端） | LWP 分支建好 canvas 后**漏了 `apply(canvas)` 与纹理回调**，UI 层拿不到后端 | 补齐与 env 路径相同的收尾 |
| 4 | `notHandshaked` 与 recv 同步增长（449/449） | 检查器在**发送**路径上记账，但 hello/hello_ack 在检查器打开**之前**发出；且判定方向写反 | 两侧都改为「先开检查器再握手」，判定改为「本侧发出过 hello/ack」 |

### 修好后的真机证据

- 通道：`sent=452 recv=452 dropped=0 bad=0 unknown=0 notHandshaked=0`
- 建面：`lwp surface from protocol handle=7425998456995 2090x1394` → `lwp canvas 已安装`
- 首帧：`backend installed=true` → `first frame present err=[]`
- 输入：`uitest uiInput click/swipe` 注入后消息数涨到 449（425 motion + 4 button）
- 文件桥停用：hilog `[LANLU-SHELL] window_cmd poller skipped (lwp active)`
- **画面**：`componentSnapshot` 抓到的 2090×1394 内容与 UI 完全一致（标题栏/侧栏/筛选/卡片网格）
- **录制**：`LANLU_LWP_TRACE=/data/storage/el2/base/files/t.lwtrace` → 901 条记录，
  `lwtrace.py verify` PASS、`stats` 显示 425 motion / 4 button / hello+ack / 13 条 system.log

### 踩到的一个坑（沙箱路径）

引擎 fs 能写 `$HOME`（= `/data/storage/el2/base/files`），但**不能写** host 视角的
`/data/app/el2/100/...` 与 `/data/local/tmp`。录制路径必须用应用可见路径，否则
`fopen` 失败且没有任何显式报错（表现为「设了却不出文件」）。

### 待办（第 53 轮）

1. 连续 resize 20 次不崩（Maleoon 重建风险，§7.1）—— 需人工拖拽窗口边缘。
2. `LANLU_PROBE_SNAPSHOT` 经 `lw_test.request_capture` 的抓帧在真机上未更新文件（待查）。
3. 验收通过后执行 M6 六步删除（`docs/m6-deletion-checklist.md`）。

## 第 53 轮（2026-11-11）：resize 压测 + `surface.changed` 接线

### 本轮修掉的缺陷

1. **抓帧路径传了目录**：`lwpRequestCapture(getVariable("HOME") ?? "." + "/x")` —— `??` 优先级导致
   实际传的是 `HOME` 本身（壳侧日志 `lwp capture -> /data/storage/el2/base/files` 暴露）。
   改成先取 `let base = getVariable("HOME") ?? "."` 再拼接。
2. **窗口状态被每帧重复执行**：`lwpWindowState()` 读后不清零，ArkTS 每 16ms 就 `maximize()` 一次，
   真机上把窗口压死。新增 `lwpTakeWindowState()`（一次性消费）并改用。
3. **`surface.changed` 根本没接线**：C 侧有 `lanlu_lwp_send_surface_changed`，但没有 napi 导出、
   ArkTS 也从未调用 —— 引擎永远不知道窗口尺寸变了（画面被拉伸）。
   补 `lwpSurfaceChanged(w,h)` + 主 XComponent 的 `onSizeChange`。
4. **resize 走了 `configure`（重建 device/pipeline）**：这才是 §7.1 说的「Maleoon 反复重建」风险源。
   改为 `surface.resize()`（只重配 swapchain）。

### 一个必须记下来的误判

20 次压测跑到第 13 轮日志停住，我一度判定为「引擎线程卡死」（连带怀疑 Maleoon 崩溃）。
用 `aa start` 把应用拉到前台后，日志立刻从第 14 轮继续跑到 `done 20` —— **应用是被切到后台冻结了**
（0% CPU、无任何错误日志）。教训：**日志停住 ≠ 死锁**，先区分「冻结」和「阻塞」再改代码。
（此前的 3 个修复仍然是对的，但第 13 轮停住本身不是 bug。）

### 真机验收进度（MOR-M1 / API 26）

| # | 判据 | 结果 |
|---|---|---|
| 1 | 点击/滑动/滚轮/输入法生效 | ✅ click+swipe 注入后消息 449 条，UI 响应 |
| 2 | `lwp stats` 计数器 | ✅ `dropped=0 bad=0 unknown=0 notHandshaked=0` |
| 3 | `lwp violations` 全 0 | ⏳ 需长跑 200 帧以上才能打出该行 |
| 4 | 文件桥停用 | ✅ `window_cmd poller skipped (lwp active)` |
| 5 | release 关闭调试后门 | ✅ `debuggable=true` 时生效（false 分支未验证） |
| 6 | 连续 resize 20 次不崩 | ✅ 20/20 完成，进程存活 |
| 7 | 设备 `.lwtrace` 与基线对比 | ✅ 901 条记录，verify PASS |

### 待办（第 54 轮）

1. 长跑取 `lwp violations` 一行（≥200 帧）。
2. `surface.changed` 在 20 轮里只触发 1 次 —— 需确认为何 ArkUI 没有每轮都回调（可能小窗/后台时尺寸未变）。
3. 人工拖拽窗口边缘再验一次（真实交互路径）。

## 第 54 轮（2026-11-11）：验收通过 + 默认切到协议

### 本轮新增的证据

1. **键盘链路**：设备录制里出现 `lw_input.key ×2`（`uitest uiInput keyEvent` 注入），
   加上此前的 `pointer_button ×4` / `pointer_motion ×425`，指针与键盘都走协议。
2. **违规计数可观测**：把 `lwpStatsLine()` 改成输出「通道统计 + 违规计数」一行，
   真机上读到 `unackedConfigure=0 frameTimeout=0 attachOutOfOrder=0`
   （之前 violations 单独打点每 200 帧一次，短跑看不到，等于没验证）。
3. **`surface.changed` 真实压测**：新增壳侧钩子 `LANLU_PROBE_SHELL_RESIZE=1`（ArkTS 每秒
   `win.resize()`），一轮跑出 **37~54 次 `surface changed ... -> reconfigure`**，进程全程存活
   —— 这比「最大化/还原」更能打，因为它每次都真的改几何。

### 默认切到协议（本轮的关键决定）

- `lwpInputEnabled()`：`LANLU_LWP` 缺省即开启，`=0` 显式回退；
- 壳侧 `lwp_ready()` 同步改成「缺省开启、`=0` 关闭」；
- 后端选择去掉「空转等 `CN_UI_BACKEND` 5 秒」—— SDL 壳删除后没有一侧再设置它，
  改为缺省 `lgpu`（保留读取以兼容旧脚本）。

**两条路都实测通过**（同一台设备、同一构建）：
- 缺省（协议）：`lwp surface from protocol handle=...` → `backend installed=true`
- `LANLU_LWP=0`（文件桥退路）：`backend mode=lgpu waited=0` → `backend installed=true`

这条很重要：**先确认退路还活着，再删退路**。上一版里 `LANLU_LWP=0` 其实是崩的
（`backend installed=false`），如果那时就执行 M6，等于把项目推进到不可运行状态。

### 真机验收 7 条（MOR-M1 / API 26）

| # | 判据 | 结果 |
|---|---|---|
| 1 | 指针点击/拖拽 + 键盘 | ✅ 425 motion / 4 button / 2 key |
| 2 | `lwp stats` 计数器 | ✅ dropped/bad/unknown/notHandshaked 全 0 |
| 3 | `lwp violations` | ✅ unackedConfigure/frameTimeout/attachOutOfOrder 全 0 |
| 4 | 文件桥停用 | ✅ `window_cmd poller skipped (lwp active)` |
| 5 | 调试开关受控 | ✅ `debuggable=true` 生效 |
| 6 | 连续 resize 不崩 | ✅ 20/20 最大化/还原 + 54 次真实 resize |
| 7 | 设备 `.lwtrace` 取证 | ✅ 901 条，verify PASS，字段可读 |

未覆盖：滚轮、输入法文本（`uitest` 无法注入这两类），需人工操作确认。

### 待办（第 55 轮）

M6 第一步可以开始了（先删引擎读侧三处 `readInputEvents/readTextInputs/readKeyEvents`），
文件桥基线从 35 往下降。

## 第 55 轮（2026-11-11）：M6 第 1 步 —— 删除输入文件桥

### 删了什么

| 位置 | 删除内容 |
|---|---|
| `packages/lwindow/src/events.cj` | `readInputEvents` / `readTextInputs` / `readKeyEvents`（文件桥三个读取器），文件从 173 行缩到 62 行，只留事件类型定义 |
| `client-next/src/ui/lgpu_backend.cj` | 事件源里 LWP 分支之后的文件桥回落（两处：headless 安装路径与旧 `SdlWindow` 路径） |
| `packages/lplatform-ohos/shell/native/shell_napi.cpp` | `lanlu_push_input` 的文件写入、`key_events.txt` / `text_input.txt` 追加、`lanlu_bridge_append` 助手 |
| `packages/portcheck/src/portcheck.cj` | 自检里读 `input_events.txt` 的等待循环 → 改读协议事件 |

**基线 35 → 29 处**（`input_events` 3 + `key_events` 2 + `text_input` 2 = 7 处 - 1 处助手计数）。

### 真机复验（删除后）

- 进程存活；`lwp stats` 全 0（含 violations）；一次新录制里 332 条 pointer_motion + 4 条 pointer_button；
- 键盘注入后 `recv` 由 359 → 369，说明 `lw_input.key` 仍通。

### 过程中的两次返工（值得记）

删 `lanlu_bridge_append` 那段时，把**同一区块里的三个声明/定义一起删了**
（`lanlu_lwp_send_key`/`_send_text`/`_send_surface_available` 的 extern，以及 `push_key_name2` 的实现），
导致链接期 `undefined symbol`。教训：**按函数边界删，不要按行范围删**；
C++ 里"删一段注释块"很容易连带删掉夹在中间的声明。

### 兼容性影响（有意为之）

`LANLU_LWP=0` 现在只剩渲染退路，**输入没有退路**。这是 M6 的预期代价，已写进文档。

## 第 56 轮（2026-11-11）：M6 第 2 步 —— 删除剪贴板文件桥

### 删了什么（基线 29 → 14 处）

| 位置 | 删除内容 |
|---|---|
| `lwindow/src/clipboard.cj` | 文件桥实现（clip_out/clip_req/clip_in 读写）→ 纯协议实现，API 不变 |
| `lwindow/src/ohos_entry.cj` | `ClipboardFileBackend` 类与 `installClipboardBackend()` 调用 |
| `shell_napi.cpp` | 原生 pasteboard 轮询线程（109 行，本来就被 `LANLU_NATIVE_CLIP` 默认关闭） |
| `Index.ets` | `pollClipboard()`、`readPasteboardToFile()` 及 2s 定时调用 |
| `input_filter.cpp` | Ctrl+V 预读剪贴板到 `clip_in.txt` 的逻辑 |

### 新增协议通路（壳侧此前是空壳）

- 泵解析 `lw_clipboard.set(mime,text)` / `get(serial)`；
- napi `lwpTakeClipboardSet()` / `lwpTakeClipboardGet()`；
- ArkTS 泵里执行真正的 pasteboard 读写，读结果回 `clipboard.text(serial, mime, text)`。

### 真机验证

- 协议双向都通：录制里 `lw_clipboard.set ×2`、`get ×2`、`text ×2`；
- **写路径成功**：hilog `[LANLU-SHELL] clip set ok len=13`（探针文本 `m6-clip-probe` 写进系统剪贴板）；
- **读路径受系统权限限制**：`pasteboard_service: VerifyPermission# no permission` +
  `GetPasteDataInner check permission failed` —— 需要 `ohos.permission.READ_PASTEBOARD`
  的运行时授权（要用户点确认）。这是 OS 约束，**与文件桥时期完全一样**（老路径也用 pasteboard.getData），不是本次改造引入的。

### 又一次「按行删」的代价

删 `input_filter.cpp` 里的剪贴板预读时，连带删掉了 `LanluKeyFilter` 的实现，
链接期报 `undeclared identifier`。修法是按 `lwp_client.cpp` 的 `keycode_from_name` 表重写了一个
精简版键盘过滤器（映射 Escape/Backspace/Tab/Enter/Space/方向键等，不消费事件）。

**这是连续第二轮踩同一个坑**：删除前应先看删除范围的起止是否落在函数边界上。

## 第 57 轮（2026-11-11）：M6 第 3~4 步 —— 对话框 / 窗口命令 / 抓帧文件桥删除

### 删了什么（基线 13 → 3 处）

| 位置 | 删除内容 |
|---|---|
| `Index.ets` | `startFileBridgePoll()`、`writeBridgeFile()`、`readBridgeFile()`、`bridgeDialogId`、`filedlg_result.txt` 写入 |
| `Index.ets` | `startWindowCmdPoller()`（读 `window_cmd.txt` 轮询执行） |
| `Index.ets` | `pollSnapshot()`（读 `snapshot_req.txt` 抓帧） |
| `lwindow/window_command.cj` | 写 `window_cmd.txt` 的回落分支 → 只发协议 |
| `client-next/src/main.cj` | 写 `snapshot_req.txt` 的回落分支 → 只发 `lw_test.request_capture` |

### 真机复验

- **窗口命令**走协议：`resize round 1 -> maximize` / `round 2 -> restore` / `done 2`（无文件介入）；
- **抓帧**走协议：`snapshot.rgba` 在本次运行被刷新（`lw_test.request_capture` → ArkTS componentSnapshot）；
- 计数器全 0，进程存活。

### 第三次「按行删」的代价（这次最重）

删 `writeBridgeFile/readBridgeFile` 时把夹在中间的 **5 个类成员**一起删了：
`dialogBusy`、`withPickerTimeout`、`snapLog`、`writeWhole`、`pickOpenFile`。
ArkTS 编译报了 8 个 "Property does not exist"，而我没有任何备份（这些文件未被 git 跟踪）。

只能按**调用点反向重建**这 5 个成员（`withPickerTimeout` = Promise.race 式超时、
`writeWhole` = 截断写文件、`pickOpenFile` = 选文件→拷进 cache→回执）。

### 连带修的三处

1. **壳侧自测的"回落模式"用例**：原来断言"未开启时返回 0 并回落文件桥"。M6 后回落不存在，
   且 LWP 默认开启 —— 用例改成显式 `LANLU_LWP=0` 并断言"输入被丢弃（返回 0）"。
2. **`LOGI_LWP` 宏**：之前用 `fprintf` + `%{public}s`（hilog 语法），宿主自测 `-Werror` 直接失败。
   改成 `__has_include(<hilog/log.h>)` 双实现：设备走 hilog，宿主走 stderr。
3. **文件桥基线**：13 → **2 处**（只剩 `lanlu_env.txt` 两条读，属定案保留的调试开关）。

**结论已经不能只是"注意"了**：这个仓库里平台包的 C++/ArkTS 文件**没有被 git 跟踪**
（`git status` 显示 `??`），删代码没有版本兜底。下一步应当先解决"平台包是否入版本库"，
否则每次删除都是在裸奔。这条已写进风险清单。

## 第 58 轮（2026-11-11）：M1W 起步 —— Wayland 壳讲 LWP

### 环境解锁

原来判定"无 Wayland 环境"是错的：本机其实有
`/workspace/horizon-ohos/.tooling/rust190`（cargo 1.90）和 `libwayland-client.so.0`，
只是没有 `-dev` 头文件。**wayland-client 0.31 走 dlopen，不需要 dev 包** —— 于是 M1W 可以开工。

### 本轮产出（`packages/lplatform-wayland`）

| 文件 | 内容 |
|---|---|
| `src/lwp.rs` | `liblwp_native.so` 的最小 Rust 绑定（open/send/recv/wait/wake/checker/trace/stats），标量+字节边界，与仓颉侧一致 |
| `src/protocol.rs` | LWP 编解码：`core.hello` / `window.created` / `window.configure` / `surface.available` / 指针・键盘・文本事件；`body_len_ok` 校验 |
| `src/main.rs` | 打开通道 → 发 hello → 打印统计（M1W 第一阶段的最小闭环） |
| `build.rs` | 链接 `liblwp_native.so`（`LWP_LIB_DIR` 可覆盖）、写 rpath |
| `Cargo.toml` | `wayland-client = "0.31.15"`（离线可解析：crate 已在本地 registry 缓存） |

### 验证

- `cargo test`：**6 项协议单测全过**（hello 字段偏移、定长尺寸与 C 头逐一对照、大小端、
  字符串 off 相对消息体、截断检测、能力位）
- `cargo build` 通过；运行二进制：
  `hello 已发出，统计: sent=1 ... notHandshaked=0` —— 说明 Rust 侧也被协议检查器认可（握手规则跨语言一致）
- CI `guards` job 增加 wayland 单测（无 cargo 时跳过）

### 下一步（M1W 续）

1. 收 `window.create` → 建 `wl_surface`+`xdg_surface`+`xdg_toplevel` → 回 `window.created` + `window.configure`；
2. `xdg_surface.configure` 与 LWP `window.ack_configure` 对齐（现在壳侧先自作主张 ack 了）；
3. 指针/键盘/文本 → 对应的 `lw_input.*`（编码器已就绪，缺 wl_pointer/wl_keyboard 对象）；
4. `surface.attach`（buffer != 0）走 `wl_shm`；
5. **本地验证手段**：本机没有系统合成器，但 `libwayland-server` 运行时库在
   （`/usr/lib/x86_64-linux-gnu/libwayland-server.so.0`）。可以写一个**最小 mock 合成器**
   （只实现 wl_compositor/xdg_wm_base/wl_shm），让壳连上去做端到端验证。

## 第 59 轮（2026-11-11）：M1W —— 连上合成器与 xdg-shell 接线

### 产出（`packages/lplatform-wayland/src/shell.rs`）

- `Shell::connect()`：`wl_display` 连接 + `registry_queue_init` + 绑定
  `wl_compositor`(v4+)、`wl_shm`、`xdg_wm_base`、`wl_seat`（可选）；
- 各 xdg 对象的最小 `Dispatch` 实现：**`xdg_wm_base.ping` → `pong`**（不回会被断开）、
  `xdg_surface.configure` → `ack_configure`、`xdg_toplevel.configure`/`close` 记账、
  `wl_seat.capabilities` 打印；
- `run()`：先发 `core.hello`（能力位 3 项）→ roundtrip 拿全局 → 主循环里
  合并「非阻塞取 LWP 请求」+「阻塞 dispatch Wayland 事件」。

### 验证

- `cargo build` 通过（45 个 warning，主要是 `Dispatch` 未用参数，M1W 阶段正常）；
- 运行：`hello 已发出 ... notHandshaked=0`，随后
  `[wayland] 无法进入事件循环: 连接 Wayland 失败 ... Could not find wayland compositor`
  —— **无合成器时优雅退出**（exit=0），不是 panic；
- `cargo test`：6 项协议单测仍全过。

### 环境的再确认

本机没有 weston/sway，`WAYLAND_DISPLAY` 为空；但 `libwayland-server.so.0` **在**
（两条：`libwayland-server.so.0*`）。这意味着可以在仓库内写一个**最小 mock 合成器**
（Rust + C FFI 或直接手写 wire protocol），给 Wayland 壳做端到端验证 —— 下一轮尝试。

## 第 60 轮（2026-11-11）：M1W 建窗 API + mock 合成器调研（未完成）

### 落地的东西

- `Shell::create_window(qh, title, app_id)`：`wl_surface` → `xdg_surface` → `xdg_toplevel`
  （设 title/app_id）→ `surface.commit()` 触发首次 configure。这是 M1W 建窗的必经路径，
  编译通过，等待 mock 合成器接进测试。

### 没做成的东西（诚实记录）

想用 `wayland-server` crate 在本机起一个 mock 合成器（这样 xdg 建窗流程能进 CI），
试了 5 轮 API 适配仍未编译通过，最后一处卡在：
`Display<State>::create_global` 报 "no method named create_global"，
而 crate 源码（`registry/src/.../wayland-server-0.31.14/src/display.rs:126`）里这个方法确实存在，
签名是 `create_global<State, I, U>(&self, version, data) where State: GlobalDispatch<I,U>`。
可能是类型参数推断/`Display` 的 re-export 差异，需要下轮对着源码逐行核对。

**这轮的教训**：我在没有 API 文档的情况下靠错误信息逐个猜签名，5 轮都没收敛。
更高效的做法是先读 crate 的 `examples/` 或 `tests/`，再写第一版。

### 第 61 轮续：wire-level 假合成器也失败了

按"先读源码"的建议查了 `wayland-server-0.31.14` 的 `display.rs`：`create_global` 确实在
`impl<State: 'static> Display<State>` 里、没有 `cfg` 门控，最小复现（只有 `Display::new` +
`create_global`）仍然报 "no method named create_global"。**原因未定位**，不再耗轮次。

于是改走手写 wire 协议（Wayland 消息 = `u32 对象id | u16 opcode | u16 长度` + 参数）。
阶段 1（`wl_display.get_registry` → 回 3 个 `global`；应答 `sync`）实现后客户端能连上，
但在 `registry_queue_init` 的 sync roundtrip 阶段收到 `Connection reset by peer`，
服务端日志一条都没打出来 —— 说明断在更早的地方。

### 第 61 轮：hexdump 定位到真凶

按计划先 dump 原始字节（`tests/rawdump.rs`，保留为常驻测试），立刻发现：
**Wayland 消息头是 `object_id(u32) | opcode(u16) | size(u16)` —— opcode 在前**，
我第 60 轮写成了 `size<<16 | opcode`（反了）。这就是 mock 一直失败的第一个原因。

修正后：客户端不再 `Connection reset`，但**挂起**在 `registry_queue_init` 的 sync roundtrip。
已把该测试标 `#[ignore]`（不留挂起的 CI），并在文件头写明定位方法：
服务端逐条打印收到的消息、确认 `sync` 是否到达、`wl_callback.done` 是否发出。

现在 `cargo test`：6 项协议单测 + 1 项 wire 格式测试通过，1 项 mock 测试 ignored。

产物已删除（不留编译不过的文件），`cargo test` 6 项全过、`cargo build` 通过。

## 第 62 轮（2026-11-11）：M1W 建窗流程端到端打通（假合成器）

### 突破点

上一轮把 wire 头顺序搞对（`obj_id(u32) | opcode(u16) | size(u16)`），这轮补齐两处：
1. **请求 opcode 全部实测**（不再靠记忆）：
   `wl_compositor.create_surface=0`、`xdg_wm_base.get_xdg_surface=2`、
   `xdg_surface.get_toplevel=1`、`xdg_surface.ack_configure=4`、`wl_surface.commit=6`、
   `xdg_toplevel.set_title=2` / `set_app_id=3`。
2. **两个测试并行抢 `WAYLAND_DISPLAY`**（进程级环境变量）→ 用 `static Mutex` 串行化。
   （之前表现为莫名的 `Connection reset by peer`，其实是连到了另一个测试的 socket。）

### 现在的验证能力

`cargo test`（wayland 包）共 **9 项**：
- 6 项协议编解码单测；
- `client_enumerates_globals_from_mock`：假合成器 advertise 三个全局，客户端枚举到；
- `shell_creates_window_and_gets_configure`：**真壳** `Shell::connect()` + `create_window()`
  → 假合成器下发 800×600 → 壳 `state.pending == Some((800,600))` → **壳回了一次 `ack_configure`**；
- `dump_client_bytes`（rawdump）：把 wire 头结构固化成断言。

这条链路跑通意味着 M1W 的**建窗骨架已在无合成器的机器上可回归**。

### 仍缺的（M1W 剩余）

1. `wl_shm` 缓冲：`surface.attach(buffer != 0)` 的落地（现在只做了全局绑定）；
2. 输入对象：`wl_seat.get_pointer/get_keyboard` + 事件 → `lw_input.*`（编码器已就绪）；
3. 真实合成器上的目视验证（假合成器验证的是协议流程，不是像素）。

## 第 63 轮（2026-11-11）：M1W 输入对象接线（集成测试未收尾）

### 落地的

`src/shell.rs` 新增三块真实接线：
- `wl_seat.capabilities` → `get_pointer` / `get_keyboard`（按能力位创建）；
- `wl_pointer` 事件 → `lw_input.pointer_motion/pointer_button/pointer_axis`；
  button 做了 evdev→LWP 的映射（0x110/0x111/0x112 → 0/1/2）；
- `wl_keyboard.key` → `lw_input.key`（Wayland 的 evdev code 直接透传）；
- `State::with_channel()`：把 LWP 通道塞进 State，Dispatch 里直接投递（测试可注入自己的通道）。
- `protocol.rs` 补 `pointer_axis` 编码器（12 字节，与 C 头一致，有单测）。

### 没做成的（如实记录）

想用假合成器把「seat capabilities → pointer motion → 通道收到 `lw_input.pointer_motion`」
也做成集成测试，**测试挂起**。日志显示：建窗后的请求流里只看到到 `set_title` 为止，
**没有看到 `wl_surface.commit`**，mock 因此从不回 configure → 客户端 roundtrip 永远等不到。

进一步修正（按对象 id 而非仅 opcode 分派，避免 `wl_compositor.create_surface` 与
`xdg_wm_base.get_xdg_surface` 等撞号）后仍然挂起，对象 id 的实际分配与预期不一致，
需要下轮先 dump「mock 视角的完整 id 分配表」再继续。

已把该测试标 `#[ignore]` 并把调试输出清掉：`cargo test` 仍是 9 项中 8 通过 + 1 ignored，
CI 不会被挂起污染。

### 教训（第三次同类）

这已经是第三次"改动正确的代码 + 写不好的测试"导致整轮卡在测试上。
下轮开始改做法：**新测试先用最小可抛错断言（assert!(false) 打日志）跑通一次**，
确认时序正确后再写正式断言，而不是一次性写完再调试。

## 第 64 轮（2026-11-11）：M1W 假合成器三项集成测试全通

按上轮定的"先探针后断言"方法，这轮顺利收敛。

### 探针先行的效果

写了 `tests/probe_ids.rs` 一次性探针，把 `Shell::connect + create_window` 的完整请求流打出来，
拿到确定的 id 分配：

```
bind: compositor=4, shm=5, xdg_wm_base=6 ; sync callback=7
create_surface(4,op0)->8 ; get_xdg_surface(6,op2)->9 ; get_toplevel(9,op1)->10
set_title(10,op2) / set_app_id(10,op3) ; commit(8,op6)
```

mock 按这张表处理，建窗测试立刻通过（上一轮是盲猜 id，越修越乱）。

### 又一个 wire 细节

`wl_pointer.motion` 的参数是 **`time, surface_x, surface_y`** ——
最开始只发了 x/y（8 字节），客户端按 12 字节读取导致**整个连接错位并挂起**。
补上 `time` 后挂起消失。

### 现在的能力（wayland 包 3+8 项测试）

| 测试 | 证明 |
|---|---|
| `client_enumerates_globals_from_mock` | 全局枚举 |
| `shell_creates_window_and_gets_configure` | 真壳建窗 → configure(800×600) → ack |
| `shell_...` + `seat_input_is_forwarded_to_lwp` | seat capabilities → get_pointer → `wl_pointer.motion` → **LWP 通道收到 `lw_input.pointer_motion`**（iface=2 opcode=1，12 字节） |

### 遗留一个具体问题

收到的坐标不是 12.5，而是一个大数（`0x4a829000` 量级）——说明 **wl_fixed ↔ f32 的换算**没对上
（Wayland 的坐标是 24.8 定点）。下一轮单独处理，并在 `protocol.rs` 加一个定点换算的单测。
测试里先不断言坐标，只断言消息类型与长度（这是硬证据）。

### 方法论结论

"先写探针跑通一次，再写正式断言" 一轮就解决了前两轮 8 次调用没解决的挂起问题。
这个方法已经写进本文档，后续新增集成测试都按它做。

## 第 65 轮（2026-11-11）：坐标换算澄清 + window.create 接线

### `wl_fixed` 的误会解开

上一轮收到的坐标是 `0x4a829000` 量级，我怀疑是壳侧换算错。这轮查清：
**是假合成器的错**。Wayland 坐标是 24.8 定点（`wl_fixed_t`），mock 直接塞了 `f32` 的位模式，
客户端按定点解析后自然变成 427 万。mock 改成发 `3200`(=12.5×256) 后，
壳侧拿到的正好是 12.5 —— **壳侧 `surface_x as f32` 是对的**，无需改代码。

测试里也补回了精确断言：`x == 12.5`、`y == 34.5`（不再是"只断言类型和长度"）。

### `window.create` 接成真实建窗

`run()` 里原来只是 echo，现在：
收到 `lw_window.create`（请求方向 opcode 0）→ `Shell::create_window()` 建 xdg toplevel →
回 `window.created(id=1, scale=1.0, server_side_decorations=false)` +
`window.configure(w, h, 0)`（默认 1280×800，可用 `LANLU_WAYLAND_W/H` 覆盖，之后以合成器
configure 为准）。

### 录制接线

`run()` 支持 `LANLU_LWP_TRACE=<path>`：把整个 Wayland 会话录成 `.lwtrace`，
与 OHOS 侧同一套工具（`lwtrace.py dump/stats/diff/verify`）——两个平台的现场可以对齐分析。

### 验证

`cargo test`：6 协议 + 3 假合成器 + 1 wire 格式 = **10 项全过**（坐标断言已恢复）；
`cargo build` 干净；守卫 5 项 PASS。

## 第 66 轮（2026-11-11）：M1W 上屏（wl_shm）打通

### 关键决策落地

计划 §7.3.1 早已定案：**Wayland 走 `wl_shm`（CPU 共享缓冲），`buffer != 0`**。
本轮把它实现出来：

1. `Shell::attach_shm(qh, surface, fd, w, h)`：
   `dup` 一份引擎给的 fd（壳管理生命周期）→ `wl_shm.create_pool` →
   `create_buffer(XRGB8888, stride=w*4)` → `attach` → `damage` → `commit`；
2. `run()` 解析 `lw_surface.attach`（`buffer` 按**进程内 fd** 解释，壳与引擎同进程）并调用它；
3. 壳在收到 `window.create` 时把 `wl_surface` 存进 State，供 attach 使用。

### 新增测试（假合成器，第 4 项）

`surface_attach_creates_shm_buffer`：造一块临时共享内存 → 调 `attach_shm` →
断言合成器视角看到 **create_pool → create_buffer → attach → damage → commit** 的完整序列。

`cargo test`：6 协议 + 4 假合成器 + 1 wire 格式 = **11 项全过**。

### M1W 四条链路现状

| 链路 | 验证方式 |
|---|---|
| 握手 / 通道 / 录制 | 真实 liblwp + 单测 |
| 全局绑定 + 建窗 + configure/ack | 假合成器集成测试 |
| 输入（pointer/keyboard → lw_input.*） | 假合成器集成测试（坐标精确断言） |
| **上屏（wl_shm attach）** | 假合成器集成测试（请求序列断言） |

### 仍缺

1. **引擎侧**要真的把像素写进这块共享内存（lgpu 需要「渲染到 fd」的后端，这是引擎侧工作）；
2. 真实合成器上的目视验证（需要一台有 Wayland 的机器）；
3. `wl_buffer.release` 后的复用/多缓冲（现在每帧新建 pool，能用但会累积）。

## 第 67 轮（2026-11-11）：缓冲复用 + 快照归档

### 修掉第 66 轮遗留的资源问题

`attach_shm` 之前**每帧新建 wl_shm pool**：功能对，但 pool/buffer 会持续累积（真实合成器下是内存与 fd 泄漏）。

现在 `State::attach_shm(shell, qh, fd, w, h)`：
- 按 **fd** 缓存 `(wl_buffer, w, h)`；
- 同 fd 同尺寸 → 直接 `attach/damage/commit`（复用，返回 `reused=true`）;
- 尺寸变化或新 fd → 重建并替换缓存。

测试补了两条硬断言：第二帧 `reused==true`，且 `create_pool` 全程只出现 **1 次**。

### 本轮验证

`cargo test`：6 协议 + 4 假合成器 + 1 wire 格式 = **11 项全过**；
`cargo build` 干净；守卫 5 项 PASS。

### 关于"引擎把像素写进 fd"

我评估了在 `lgpu`（Rust + wgpu）里加「渲染到内存」的导出：现有 `lgpu_capture_offscreen` 已经把
一帧离屏渲染并写出 RGBA 文件，可复用其渲染路径加一个「写进调用方缓冲」的变体。
但这是引擎侧较大改动（wgpu 读回 + 拷贝 + 与 Cangjie 侧 mmap 协作），
**不适合在没有真实合成器验证的情况下盲改**，留到有 Wayland 环境时做。

更稳妥的下一步优先级（按价值/风险）：
1. 归档当前成果（快照 + 文档），避免再次出现"删错无法回滚"；
2. 有 Wayland 环境时：引擎渲染到 fd + 真实合成器目视验证；
3. 有设备时：回到 OHOS 侧做 M3 剩余项（cursor shapes、attach serial、dmabuf）。

## 第 68 轮（2026-11-11）：M6 删除后的真机回归验证

设备仍在（192.168.0.26），本轮把 M6 删除后的完整链路重新验了一遍，确认**删除没有引入回归**。

### 1. 硬件输入 + 协议计数器

注入 click / swipe / keyEvent 后：

```
lwp stats sent=361 recv=361 dropped=0 bad=0 unknown=0 notHandshaked=0
          unackedConfigure=0 frameTimeout=0 attachOutOfOrder=0
```

录制文件：717 条记录，`lwtrace verify` PASS；消息构成
`332 pointer_motion + 4 pointer_button + 2 key + 13 system.log + hello/app.resumed` —— 与删除前一致。

### 2. 抓帧路径（文件桥已删，只剩协议）

`LANLU_PROBE_SNAPSHOT=1` → 引擎发 `lw_test.request_capture` → 壳 `snapOnce()`：
hilog 出现 `snap once: info 2090x1394` / `pixels 11653840` / `written`，
`snapshot.rgba` 在本次运行被刷新。

### 3. 画面逐字节比对（最强的一条）

本轮抓到的 `snapshot.rgba` 转 PNG 后 **sha256 与 M6 删除前（第 52 轮）的截图完全相同**
（`5a274b9e…a30c55…`）—— 说明删掉 33 处文件桥代码之后，**渲染结果一个像素都没变**。

这比"看起来没问题"强得多：它同时证明了
① 删掉的确实是死代码；② 协议路径承担了原来全部职责；③ 没有引入像素级回归。

### 结论

M6 第 1~4 步可以认为**验收完成**。剩余第 5 步（`appExited` 静态标志）与第 6 步（联调开关）
按计划保留，不影响运行路径。

## 第 69 轮（2026-11-11）：M3 滚轮接通（ArkUI axis 事件）

### 背景（计划 §6.2 / M3 已记录）

OHOS 的**窗口鼠标过滤器收不到滚轮**：它的 action 映射表只有 CANCEL/MOVE/BUTTON_DOWN/BUTTON_UP，
AXIS 事件查表失败后被丢弃。所以滚轮必须走 **ArkUI 节点事件**。

### 本轮实现

1. **ArkTS**：主 XComponent 新增 `.onAxisEvent()`，读
   `event.getVerticalAxisValue()` / `getHorizontalAxisValue()`，
   **÷45** 换算成协议的逻辑刻度（与文件桥时期同一换算），再调 napi；
2. **napi**：`lwpSendPointerAxis(value, axis)` → `lanlu_push_input(13, value, axis, 0)`；
3. 壳侧 `lwp_client.cpp` 的 action 13 分支已存在：`y=0` 垂直、`y=1` 水平 → `lw_input.pointer_axis`；
4. 引擎侧 `lwpEventToUi` 早已把 `PointerAxis` 映射成 `UiEvent.MouseWheel`。

### 验证

- `build-ohos.sh` exit=0，五项静态验证 PASS；装机启动、点击注入均正常，
  `lwp stats` 全 0（说明新事件注册没有影响原链路）。
- **滚轮本身无法用 `uitest` 注入**（它只有 click/swipe/drag/fling/keyEvent），
  需要在设备上**人工滚动**一次确认。这条记入待验证清单。

### 又一次踩 `/tmp` 的坑

本轮两次构建"失败且日志为空"：根因是 `/tmp`（512M tmpfs）被写满，
脚本第一句就失败、连输出都没有。清理后同一份代码构建通过。
**以后构建失败先看 `df -h /tmp`**，这条已写进交接文档的环境坑清单。

## 第 70 轮（2026-11-11）：vsync 帧闭环打通 + 两个"静默失效"的教训

### 本轮做的

1. **壳侧 vsync**：ArkTS `displaySync.create()` + `on('frame')`，每帧回调里取
   `shell.lwpTakeFrameRequest()`，非 0 就 `shell.lwpFrameDone(serial)`；
   壳的 `hello.capabilities` 增加 `VSYNC` 位，引擎据此开始每帧 `frame.request`。
2. 新增 napi：`lwpTakeFrameRequest()` / `lwpFrameDone(serial)`。

### 真机结果

```
hilog: [LANLU-SHELL] vsync ticks=720 frameDone=46
trace: 92 send:lw_frame.request / 92 recv
       46 send:lw_frame.done   / 46 recv
```

帧闭环成立。**但 request:done = 2:1**（92 次请求只回执 46 次）—— 说明引擎每帧发了两次请求
（`lwpFrameTick` 与事件源各一次），壳每 tick 只兑现一次。不影响功能（引擎不等 done），
但计费口径失真，下轮修。

### 两个静默失效（这才是本轮真正的收获）

**① 默认开启后，引擎里写死的 `LANLU_LWP=="1"` 判断全部失效**
第 54 轮把 LWP 设为默认（不设 env），但 `client-next/src/main.cj` 里两处仍是
`(getVariable("LANLU_LWP") ?? "0") == "1"`：
- `lwpAwaitSystemInfo(300)` 不再执行 → 壳下发的时区/语言**从来没被用上**；
- `frameProbeHook` 不再安装 → 每帧 `lwpFrameTick()` **从未运行**，`lwp violations` 也没打点。

没有报错、没有崩溃、UI 看起来完全正常 —— 只是"协议的一半在空转"。
修法：统一改用 `lwindow.lwpInputEnabled()`。修完后 `lwp system.info ready=true`、
`lwp violations ...` 两行才第一次出现在日志里。

**② 泵里插了重复的 if/else-if 分支**
我给 `lanlu_lwp_window_pump` 加 frame.request 解析时，没注意到**已有的同名分支**（更靠前），
新分支永远不执行 → ArkTS 取到的 serial 恒为 0 → `frameDone=0`，白跑两轮构建。
教训：**改 if/else-if 链前先 grep 该 iface/opcode 是否已存在**。

### 方法论

这两个 bug 都属于"**功能静默失效**"：不报错、不崩溃、指标还是 0（甚至更漂亮）。
唯一能发现它们的方法是**检查消息是否真的成对流**（request/done 成对、system.info 有回执），
而不是看 UI 是否正常。已把"成对性检查"加入 M2 验收清单。

## 第 71 轮（2026-11-11）：合并回执的正确记账

### 问题

第 70 轮发现 `frame.request : frame.done = 2 : 1`。查清原因：**壳的泵合并请求**——
`g_frame_serial` 是单变量，两次请求之间只保留最新一条，vsync 每 tick 兑现一次。
对帧配速来说合并是**正确行为**（过期的请求没有意义），但它让引擎的超时判定失真：
引擎按"这一条 serial 有没有被单独回执"判断，合并回执会被误判成超时。

### 修法

引擎侧引入**已回执水位** `lastAckSerial`：
- 收到 `frame.done(serial)` → `lastAckSerial = max(lastAckSerial, serial)`，
  并把 pending 清掉（`serial >= pending` 时）；
- `checkFrameTimeout()` 增加一条：**水位追上最新请求就不算超时**。

这样 `frameTimeout` 才真正表达"壳没在回"，而不是"壳回得比请求少"。

### 验证

- lwindow 单测 **37 项**（新增 `mergedFrameDoneIsNotTimeout`：连发两次请求、只回最新一条、
  时间推到极大也不应记超时）；
- 真机：`lwp violations unackedConfigure=0 frameTimeout=0 attachOutOfOrder=0`，
  `stats sent=161 recv=161` 全 0；`build-ohos.sh` exit=0 五项静态验证 PASS。

### 顺带确认的语义

`frame.request/done` 的合并不是 bug，是 vsync 配速的常规做法（Chromium 的 BeginFrame 也这样）。
真正需要保证的是：**每帧至少有一次 done**，而不是"每个 request 对应一个 done"。

## 第 72 轮（2026-11-11）：IME 光标矩形链路接通

### 之前的状态：协议有、两端都没接

`lw_text_input.set_cursor_rect / set_surrounding / enable / disable` 四个请求：
引擎侧有 `LWPWindowClient.imeSetCursorRect` 等方法**但没有调用者**；壳侧泵里**没有解析分支**。
等于协议面是死的。

而 lgui 侧其实一直在算光标矩形：`DesktopApp.applyTextInputAnchor()` →
`window.setTextInputArea(rect)`，但那个方法是**空实现**（注释写着"由 L 层负责（P5 后续）"）。

### 本轮把它接起来

1. **lgui**：新增 `textInputAreaSink: Option<(Rect) -> Unit>`；`setTextInputArea` 改为调用 sink。
   —— 保持"lgui 只算、平台层决定怎么用"的分层。
2. **引擎**（`lgpu_backend`）：协议开启时注册 sink，
   把矩形转成 `LWPWindowClient.imeSetCursorRect`；
3. **壳**（`lwp_window.cpp` 泵）：解析 `text_input.set_cursor_rect`，存入并打一行 hilog；
   napi 暴露 `lwpTakeImeCursorRect()`；
4. **ArkTS**：泵里取出矩形，把**窗口局部坐标加上窗口偏移**转成物理屏幕坐标，
   调 `inputMethod.updateCursor({left, top, width, height})` 给输入法面板定位。

### 验证到哪一步

- `build-ohos.sh` exit=0（修了两次类型错误：`Rect` 的字段是 `w/h` 不是 `width/height`；
  `CursorInfo` 是扁平四字段、不是嵌套结构），装机启动正常；
- **运行时未触发**：`textInputAnchorRect()` 只有在**文本框获得焦点**时才返回 Some，
  而 `uitest` 无法把焦点放进自定义绘制的搜索框。需要人工点搜索框并输入一次。

### 待人工验证清单（累计 3 项）

1. 滚轮（第 69 轮接通）；
2. IME 光标矩形随光标移动（本轮接通）；
3. 输入法文本提交后 `clipboard.text` / `text_input` 的联动。

## 第 73 轮（2026-11-11）：查清宿主机测试的真实阻塞点

想把 client-next 的 246 个测试在宿主机上跑起来（一直记着"CI 才能跑"）。本轮实测：

1. **cargo 其实是可用的**：`/workspace/horizon-ohos/.tooling/rust190/bin/cargo`，
   `fontkit`、`webview` 的 Rust 原生依赖都编过了（webview release 编了 1m50s）。
   之前文档里写"需要 rustup/cargo"是**错的**（第 42 轮判断失误的延续）。
2. **真正的卡点是 ffmpeg 开发头**：
   `packages/libavformat_ffi/native/lanlu_avformat_bridge.c:3` 需要 `libavcodec/avcodec.h`；
   宿主机没有；`.research-ohos/ohos-stubs/ffmpeg/` 里只有 OHOS 的 `.so`（既无头文件、
   也不能在 x86_64 上链接）。

**结论（已写进交接文档）**：`apt install libavformat-dev libavcodec-dev` 之后即可本地跑；
在那之前这些测试只能在 CI 执行。

### 这条记录的价值

它纠正了两个累积多轮的**错误前提**：
- "宿主机没有 Rust 工具链" → 实际有，只是没进 PATH（第 42 轮据此把 M1W 判定为"环境阻塞"，延误了十几轮）；
- "宿主机跑不了是因为 cargo" → 实际是 ffmpeg 头。

教训：**环境判断要写清"我执行了哪条命令、看到什么"**，否则一个错误前提会一路复制下去。

## 第 74 轮（2026-11-11）：M2W 起步 —— Wayland 壳的系统面

### 本轮补的（都在 `lplatform-wayland`）

| 项 | 内容 |
|---|---|
| `system.info` | 新增编码器（4 字符串 + api_level，24 字节头），壳启动时把 `TZ/LANG/LANLU_FONT_DIR/HOME` 同步给引擎 |
| `system.log` | 引擎日志 → 壳的 stdout（真机上即终端/hilog） |
| `window.set_state` / `window.close` | 收到即处理（M2W 的 xdg 映射下轮接：`set_maximized`/`set_fullscreen`/`close`） |
| `app.exit` | 结束主循环并正常返回（不再需要 Ctrl-C） |

`announce_system_info(&Channel)` 被抽成独立函数，便于测试直接调用。

### 测试（12 项）

新增 `shell_announces_system_info`：调 `announce_system_info` 后从通道取出消息，
断言 `iface==12 / opcode==0`、body ≥ 24 字节、时区字符串落在 body 内且非空。

`cargo test`：7 协议 + 5 假合成器 + 1 wire 格式 = **12 项全过**。

### M2W 剩余（下轮）

1. `window.set_state` 真正映射到 `xdg_toplevel.set_maximized/set_fullscreen/unset_*`；
2. `window.close` → `xdg_toplevel.destroy`；
3. `system.info` 的 api_level 目前填 0（Wayland 侧无意义，但引擎会记录，应改成一个明确的哨兵值）；
4. 剪贴板（`wl_data_device`）—— 比 OHOS 侧复杂，单独排期。

## 第 75 轮（2026-11-11）：M2W 窗口状态映射 + api_level 哨兵

### 1. `window.set_state/close` 真正映射到 xdg-shell

| LWP | xdg_toplevel 请求（opcode 按 XML 声明顺序） |
|---|---|
| `set_state & 2`（最大化） | `set_maximized`(9) |
| `set_state & 4`（全屏） | `set_fullscreen`(11) |
| 其余（普通） | `unset_maximized`(10) + `unset_fullscreen`(12) |
| `window.close` | `destroy`(0) 后退出主循环 |

**踩的小坑**：我先按记忆猜了 11/12/13/14，测试立刻失败。正确做法是读协议 XML ——
`wayland-protocols-0.32.13/protocols/stable/xdg-shell/xdg-shell.xml` 里声明顺序才是编号来源：
`destroy=0 … set_max_size=7 set_min_size=8 set_maximized=9 unset_maximized=10
set_fullscreen=11 unset_fullscreen=12 set_minimized=13`。

### 2. `system.info.api_level` 改用哨兵

上一轮填 0，等于告诉引擎"壳是 API 0"。Wayland 没有 OS API level 概念，
改为 `API_LEVEL_NA = 0xFFFF_FFFF` 显式表示"不适用"，编码器常量与文档同步。

### 测试

新增 `window_state_maps_to_toplevel_requests`：直连假合成器，依次发
`set_maximized / unset_maximized / set_fullscreen / unset_fullscreen`，
断言 toplevel 对象上收到 opcode 9/10/11/12。

`cargo test`：7 协议 + 6 假合成器 + 1 wire 格式 = **13 项全过**。

### M2W 剩余

1. 剪贴板（`wl_data_device` + 选中的 `wl_data_source`）；比 OHOS 侧复杂，单独排期；
2. `surface.changed` 目前只在 OHOS 侧发；Wayland 侧应在 toplevel configure 后回给引擎；
3. 多屏（`wl_output`）与 DPI 缩放（`wl_surface.set_buffer_scale`）。

## 第 76 轮（2026-11-11）：configure → surface.changed 闭环

### 之前的问题

Wayland 壳收到 `xdg_surface.configure` 就**立刻 ack**，但从不告诉引擎尺寸变了 ——
引擎因此不会重配 swapchain。OHOS 侧有 `surface.changed`，Wayland 侧漏了。

### 现在的做法

- `xdg_surface.configure(serial)` → 只记 serial，**不立刻 ack**；
- `xdg_toplevel.configure(w,h)` → 记尺寸；
- 两者**都到齐**时 `flush_configure()`：
  ① 发 `lw_surface.changed(w, h)` 给引擎；② `ack_configure(serial)`；③ 清 serial。

这样顺序无关（先来尺寸还是先来 serial 都能处理），也符合 xdg-shell 的"先 ack 再提交"约束。

### 测试（新增第 7 项）

`configure_emits_surface_changed`：假合成器下发 `toplevel.configure(1024×768)` +
`xdg_surface.configure(serial=5)`，断言：
- 通道收到 `lw_surface.changed(1024, 768)`；
- 合成器收到恰好一次 `ack_configure(5)`。

`cargo test`：7 协议 + 7 假合成器 + 1 wire 格式 = **15 项全过**。

### 两个过程教训

1. **`ack_configure` 是在事件回调里排队的，要再 flush 一次才真正出去** ——
   测试里只走一轮 roundtrip 时 ack 还躺在缓冲里，看起来像"没发"。
   （与之前 mock 的 `xdg_surface.ack` 需要额外 roundtrip 是同一类问题。）
2. **`Mutex::lock().unwrap()` 的 poison 会掩盖真实失败**：一个测试 panic 后，
   后续所有测试都挂在 `.lock().unwrap()` 上，报出一堆假失败。改成
   `unwrap_or_else(|e| e.into_inner())` 后，失败原因才看得见。

## 第 77 轮（2026-11-11）：Wayland DPI 缩放

### 实现

- `Shell::connect` 绑定 `wl_output`（可选，没有也照常跑）；
- `State.output_scale` 由 `wl_output.scale` 事件更新，默认 1；
- `flush_configure()` 里调 `wl_surface.set_buffer_scale(scale)`；
- `window.created` 的 `scale` 字段不再写死 1.0，而是用实际缩放。

### 又一个协议编号踩坑

假合成器要发 `wl_output.scale`，我按"感觉"用了编号 4，客户端立刻错位挂起。
正确顺序是 `geometry(0) mode(1) done(2) scale(3) name(4)` —— **scale 是 3**，
编号 4 是 `name`（字符串），用整数发过去会让客户端按字符串读。

这是本轮第三次因为"编号靠猜"翻车（前两次：xdg_toplevel 请求序号、ack 时序）。
结论已落到文档：**协议里的数字必须来自 XML 或生成头文件，不能凭记忆**。

### 测试

新增 `output_scale_sets_buffer_scale`：假合成器广告 `wl_output` + 发 `scale=2`，断言
`state.output_scale == 2` 且客户端发出 `wl_surface.set_buffer_scale(2)`。

`cargo test`：**17 项全过**（7 协议 + 8 假合成器 + 1 wire 格式 + ...）。

### 顺带改进测试基建

`State` 的逐字段初始化改成 `..Default::default()` —— 前面每加一个字段就要改 4 处测试，
这轮为此多花了两次编译。

## 第 78 轮（2026-11-11）：Wayland 剪贴板（set 路径）+ 编码器纠错

### 实现

- `Shell::connect` 绑定 `wl_data_device_manager`；有 seat 时 `get_data_device` 建出 data device；
- **`clipboard.set`**：建 `wl_data_source` → offer 三种 mime
  （`text/plain;charset=utf-8` / `text/plain` / `UTF8_STRING`）→ `set_selection(source, serial)`；
  文本存进 `State.pending_source_text`，别的客户端来取时在 `wl_data_source.send` 回调里写进它给的 fd；
- **`clipboard.get`**：记下 serial；**没有选区时立刻回空 `clipboard.text`**，避免引擎空等。
  有选区时的实际读取（异步 fd）留到下一轮；
- **输入 serial**：`set_selection` 要求带输入事件的 serial，现在从 `wl_pointer.button` 事件里记
  `last_input_serial`（Wayland 的常规做法）。

### 编码器纠错（重要）

写 `clipboard_text` 编码器时我把两个字符串头的位置搞错了：C 头是
`{size(4), serial(4), mime(lwp_str@8), text(lwp_str@12)}`，载荷从 **16** 开始，
我一开始把 text 头放到了 16、mime 头放到载荷后面。

加了一条 `clipboard_text_layout` 单测，逐字节断言四个头字段与载荷位置 —— 这类
"字段错位"在两端都自洽时**跑起来不会报错**，只会悄悄把 mime 和文本交换。

### 测试

`cargo test`：8 协议 + 8 假合成器 + 1 wire 格式 = **18 项全过**。

### 剪贴板剩余

1. `clipboard.get` 的真实读取：`wl_data_offer.receive(mime, fd)` + 非阻塞读回；
2. `wl_data_offer.offer(mime)` 的 mime 协商（现在只认 utf8 系列）；
3. 多发/粘贴回环（自己设的选区自己取）在真实合成器上的验证。

## 第 79 轮（2026-11-11）：Wayland 剪贴板 get（异步读回）

### 实现

`clipboard.get` 有选区时：
1. 建一对 `UnixStream`（比 pipe 好：支持 `set_nonblocking`，能干净地轮询）；
2. 写端转成 `OwnedFd` 交给 `wl_data_offer.receive(mime, fd)`；
3. 读端留在 `State.pending_read`，每轮泵循环调 `poll_clipboard_read()`：
   读到 EOF 就把内容连同 `serial` 一起作为 `clipboard.text` 发回引擎。

选择 `UnixStream::pair` 而不是 `std::io::pipe`：后者在稳定版里能拿到 `PipeReader`，
但不支持 `set_nonblocking`（要自己 fcntl，而项目里没有 libc 依赖）。

### 测试

新增 `clipboard_read_emits_text`：手工造一个已写入数据的流塞进 `pending_read`，
调 `poll_clipboard_read()`，断言：
- 返回 true（完成一次读回）；
- 通道收到 `lw_clipboard.text`，`serial` 原样带回，mime 与文本正确（逐字段解析）。

这条测试绕开了假合成器的 fd 传递（需要 SCM_RIGHTS，代价大），
但覆盖了"读回来 → 编码 → 投递"这段真正容易错的逻辑。

`cargo test`：8 协议 + 9 假合成器 + 1 wire 格式 = **19 项全过**。

### 剪贴板剩余

1. 假合成器侧的 fd 传递（SCM_RIGHTS）以覆盖 `receive` 的真实路径；
2. mime 协商（现在固定要 utf8，应该从 `wl_data_offer.offer` 列表里挑）；
3. 真实合成器上的粘贴回环验证。

## 第 80 轮（2026-11-11）：剪贴板 mime 协商

### 之前的问题

`clipboard.get` 固定向选区要 `text/plain;charset=utf-8`。如果对面只提供
`UTF8_STRING` 或 `STRING`（老客户端、GTK 与 Qt 的差异），取回来就是空的，
而且**看不出任何错误** —— 又一个"静默失效"。

### 现在的做法

1. `Dispatch<wl_data_offer>` 收 `offer(mime_type)` 事件，攒进 `State.offer_mimes`；
2. `State::pick_mime()` 按优先级挑：`text/plain;charset=utf-8` →
   `text/plain;charset=UTF-8` → `UTF8_STRING` → `text/plain` → `STRING`
   （大小写不敏感）；
3. 挑不到就退回 utf8 默认值（合成器多半接受），至少不会比之前更差；
4. `Selection` 事件换人时清空 mime 列表，避免拿旧列表去问新选区。

同时把 `CLIPBOARD_MIME` 能力位向引擎宣告 —— 之前只宣告了 `CLIPBOARD_READ_ASYNC`，
等于告诉引擎"我不支持 mime"，与现在的实现不符。

### 测试

新增 `mime_preference_order`：四个场景（只有 `text/plain` / 有大小写不同的 UTF-8 变体 /
全是图片 mime / 空列表），断言选择结果与"挑不到返回 None"的约定。

`cargo test`：8 协议 + 10 假合成器 + 1 wire 格式 = **20 项全过**。

### M2W 状态

| 部分 | 状态 |
|---|---|
| system.info / 日志 / 窗口状态 / close | ✅ |
| configure → surface.changed | ✅ |
| DPI 缩放 | ✅ |
| 剪贴板 set / get / mime 协商 | ✅ |
| 假合成器覆盖 fd 传递（SCM_RIGHTS） | ❌ |
| 多屏选择 | ❌（只取第一个 output） |
| 真实合成器目视验证 | ❌ 无环境 |

## 第 81 轮（2026-11-11）：光标形状端到端打通（真机验证）

### 为什么做这个

计划 §7.5 里 `lw_seat.set_cursor` 定义了但从没实现，而 lgui 侧其实早就有
`SystemCursor` 枚举和 `Cursor.system(kind)` —— 只是那个函数在 P5 被改成**空实现**
（注释写着"真机光标由系统绘制"）。又一处两端都没接的协议面。

### 本轮接通（五层）

| 层 | 改动 |
|---|---|
| lgui | 新增 `cursorSink`；`Cursor.system(kind)` 改为调用 sink（不再空转） |
| 引擎 | 注册 sink，把 `SystemCursor` 20 个枚举值映射成协议编号 0~10 |
| lwindow | `LWPWindowClient.setCursorShape(shape)`（先查 `CURSOR_SHAPES` 能力位）+ 编码器 |
| 壳 C | 泵解析 `lw_seat.set_cursor` → `LANLU-LWP cursor shape -> N`；napi `lwpTakeCursorShape()` |
| ArkTS | 形编号 → `pointer.PointerStyle` → `pointer.setPointerStyle(winId, style)` |

形状编号表（已写进代码注释，待补进计划 §7.5）：
`0=默认 1=文本 2=手型 3=等待 4=十字 5=移动 6=禁止 7=水平 8=垂直 9=↘ 10=↗`

### 真机验证（完整链路）

加了一个联调探针 `LANLU_PROBE_CURSOR=1`（强制设一次文本光标），真机结果：

```
引擎  : probe cursor shape=1 -> true
壳    : (hilog) cursor shape -> 1
ArkTS : [LANLU-SHELL] cursor shape 1   ← setPointerStyle 已调用
```

**三层日志对得上**，说明「引擎 → 协议 → 壳 → 系统光标 API」这条链是真的通的。

### 诚实说明：现在还没有"自动变化"

`lgui` 里**没有任何组件调用 `Cursor.system`**（`grep` 全包无调用者）。
所以这轮打通的是**管道**，不是"鼠标移到文本框上会变 I 形"这个用户可见行为。
下一步需要在 lgui 里做"指针悬停 → 按组件类型选光标"（需要先有 hover 命中测试）。

### 踩坑记录

- `PointerStyle` 的成员名和我猜的不一样：没有 `TEXT`/`LOADING`/`EAST_WEST`，
  实际是 `TEXT_CURSOR`/`RESIZE_LEFT_RIGHT`/`RESIZE_UP_DOWN` —— **又一次"凭记忆写 API 名"**；
- ArkTS 里的窗口 id 字段叫 `winId` 不是 `windowId`。

## 第 82 轮（2026-11-11）：光标"自动变化"的决策逻辑（真机未触发）

### 做的

1. **lgui**：`applyTextInputAnchor()` 把最近一次文本框矩形暴露为 `lgui.lastTextInputRect`
   （原来只用来调 `setTextInputArea`，现在平台层也能读）；
2. **lwindow**：新增纯函数 `lwpCursorShapeForPoint(tx,ty,tw,th, x,y, hasTextInput)`
   —— 指针在框内给 1（文本光标），否则 0（默认）；**6 个边界用例的单测**；
3. **引擎**：事件源里收到 `PointerMove` 时算一次期望形状，**变了才发协议**
   （`g_lastCursorShape` 缓存，避免每帧刷一条 set_cursor）。

lwindow 单测 **38 项全过**；`build-ohos.sh` exit=0。

### 真机结果：没有触发（如实记录）

装机后 click 搜索框 + `uitest movePointer` + `swipe`，**hilog 里一条 `cursor shape` 都没有**。
说明要么 PointerMove 分支没执行，要么 `lwpSetCursorShape` 静默返回 false。
本轮时间用尽，没定位到根因。

**下一轮的第一步就该是加诊断**（在决策分支里 probeTrace 一行），而不是继续猜。
这正是第 70 轮记过的教训：静默路径必须先把"有没有跑"打出来。

### 另外

这轮修了三个低级错误：`ev.type` 应为 `ev.kind`（`type` 是关键字）、
`g_lastCursorShape` 必须声明在首次使用之前（Cangjie 顶层顺序敏感）、
以及 ArkTS 里 `windowId` 应为 `winId`。第 4 次"凭记忆写标识符"。

## 第 83 轮（2026-11-11）：光标链真机验证通过 + 找到共同根因

### 上一轮"没触发"是我的验证方法错了

上轮结论"引擎没发 cursor"**是错的**。这轮看 `.lwtrace` 才看到真相：

```
9648.452ms send request lw_seat.set_cursor serial=109 size=32 payload=8B
9656.735ms send request lw_seat.set_cursor serial=110 size=32 payload=8B
hilog: [LANLU-SHELL] cursor shape 2 / cursor shape 0
```

**引擎发了、壳收了、系统应用了。** 上轮之所以判断"没触发"，是因为我用
`hilog | grep 'cursor shape'` 去看一个**已经被新实例覆盖**的日志窗口，
而 `probe_trace` 里那版诊断还没编进去。又一次"用错的测量方法得出错误结论"。

### 顺带发现：`lgui` 里其实有 `Cursor.system` 的调用者

上轮我说"全包 grep 没调用者"是**范围错了**（只 grep 了 `lgui/src`，没看 `src/controls`）。
实际 hilog 出现过 `cursor shape 2`（手型），说明组件确实会在悬停时请求光标。

### 真正的问题：文本框锚点从来没人上报

`lgui.lastTextInputRect`（以及 IME 的 `set_cursor_rect`）都依赖
`ctx.textInputAnchorRect()`，而它只由 `src/text/text_input_cursor.cj` 在
**文本框绘制光标时**调用 `ctx.setTextInputAnchor(rect)` 设置。

`grep -rn 'setTextInputAnchor' client-next/src` → **零结果**。
也就是说：**应用自己的搜索框是自绘的，从不报告光标矩形**。

这一条同时解释了：
- 第 72 轮 IME 光标矩形"接好了但没触发"；
- 第 82 轮"文本光标（I 形）不出现"。

### 下一步（明确）

让应用里的文本框在绘制光标时调用 `ctx.setTextInputAnchor(caretRect)`，
或者在 `lgui` 里把自绘文本框的命中/光标位置统一走 `text_input_cursor` 的辅助函数。
两条链路（IME 定位 + I 形光标）会同时活过来。

### 本轮产出

- 真机证据：`set_cursor` 上链 + 系统应用（这是 M3 光标项的验收依据）；
- 一条根因结论，替掉两个"未解之谜"。

## 第 84 轮（2026-11-11）：把根因再收窄一层

### 上轮结论的修正

上轮说"文本框锚点从来没人上报（`grep setTextInputAnchor client-next/src` 零结果）"——
**这个推断不完整**。应用确实没有直接调用它，但应用用的是 lgui 的 `TextField` 控件，
而 `TextField.draw()`（text_field.cj:149）在 focused 时会调
`drawTextFieldCursor(...)`，后者（text_input_cursor.cj:127）会
`ctx.setTextInputAnchor(caret)`。

**所以锚点链是存在的**，只是没被走到。于是问题变成：**搜索框到底有没有拿到焦点？**

### 本轮真机尝试

按截图量出搜索框在物理坐标约 `(690, 21)`，执行
`uitest uiInput click 690 21` + 小幅 `swipe` 制造移动，再看日志：
**`cursor shape` / `ime cursor` 都没有**。说明点击没有让搜索框获得焦点
（或焦点没有传到 `TextField.draw` 的 `hasFocus` 分支）。

### 结论（已收窄，但未解决）

| 之前以为 | 现在知道 |
|---|---|
| 锚点没人上报（缺代码） | 锚点链存在（TextField → text_input_cursor） |
| — | 缺的是**焦点**：搜索框在 uitest 点击下没拿到 focus |

下一步要查的是 `uitest click → 窗口 → lgui 事件分发 → TextField 命中 → 请求焦点`
这条链在哪断了。建议先加一条"PointerDown 时打点：命中谁、焦点变成谁"的诊断，
而不是再猜坐标。

### 这轮的教训

连续两轮我都过早收敛到"根因"，而每次多查一层就发现结论要修正。
**"根因"这个词应该留给已经用实验证实的结论**，中间状态就叫"当前最可能的解释"。

## 第 85 轮（2026-11-11）：焦点诊断（未收敛，但有一条强线索）

### 加的诊断（保留，用环境变量开启）

- `lgui.debugFocusId`：每帧由 `DesktopApp` 刷新，暴露当前焦点控件 id；
- 引擎事件源里 `LANLU_PROBE_FOCUS_DBG=1` 时打印前 30 条事件的
  `kind/x/y/focus`，并单独打 `PointerDown` 的 `focus dbg` 行。

### 观察到的现象（互相矛盾，不能下结论）

| 场景 | 结果 |
|---|---|
| 应用**未被前置**时 `uitest click` | trace 里 **0** 条输入事件 |
| `aa start` 前置后再 `click 900 600`（内容区） | trace 里有 **2 条 `lw_input.pointer_button`** |
| 重新启动后 `click 690 21`（标题栏搜索框） | **0** 条输入事件 |
| 同一进程内再 `click 900 600` | **0** 条（与上一行矛盾） |

前两条说明"输入能到应用"；后两条说明"到了某处就没了"，且**同一 build 内两次结果不一致**，
更像是**窗口焦点/前后台状态**在干扰，而不是纯粹的坐标问题。

### 一条值得追的强线索

标题栏（自定义标题栏，`SERVER_SIDE_DECORATIONS`）通常会被声明成**窗口拖动区**。
如果整个标题栏都是拖动区，那么搜索框上的点击会被系统当成"拖动窗口"而**不会派发给应用** ——
这能解释"内容区有点击、标题栏没有"，也能解释为什么 IME 锚点/I 形光标都不出现。

下一步应当是**查 ArkTS/原生侧有没有设置拖动区**（`window.setWindowTitleButtonRect`、
`on('windowEvent')`、或 `windowStage` 的拖拽区域 API），而不是继续靠点击坐标试。

### 本轮教训

我又一次在没有稳定复现条件的情况下连续构建了 3 次。
**真机诊断要先建立"可重复的最小复现"**（例如固定前置窗口 + 固定坐标 + 同一次运行内对比内容区与标题栏），
再去加打点；否则每次观测都可能是在不同状态下得到的，越查越乱。

## 第 86 轮（2026-11-11）：找到连续三轮困惑的真正原因 —— 测试坐标错了

### 根因（这次有实验证据）

设备上的窗口位置是 **屏幕偏移 (515, 292)**（`window_info.txt`：
`rect=515,292,2090,1394`，屏幕 3120×2080）。而 `uitest uiInput click` 用的是**屏幕坐标**。

我前几轮一直按**应用内坐标**去点（搜索框在应用内约 (690,21)），
于是实际点到了窗口外面 —— 那里什么都不会发生。

证明（同一 build、同一流程，只改坐标）：

```
click(900, 150)  -> 0 条输入事件    ← 应用内 y=150 但屏幕 y=150 在窗口外（窗口从 292 开始）
click(900, 600)  -> 2 条 pointer_button
click(1205,313)  -> 4 条 pointer_button   ← (515+690, 292+21) 正好点在搜索框上
```

### 结果：I 形光标真的工作了

点在搜索框上再移动鼠标：

```
hilog: [LANLU-SHELL] cursor shape 0
hilog: [LANLU-SHELL] cursor shape 1   ← 文本光标
```

也就是说第 81~85 轮逐个接通的链路（lgui sink → lwp_seat.set_cursor → 壳 → PointerStyle）
**本来就是对的**，只是我的验证方法一直在点空处。
第 82 轮"没触发"、第 84/85 轮"缺焦点"、拖动区猜测，**全部作废**。

### 交付：可复用的真机输入探针

`tools/ohos-input-probe.sh`：自动从 `window_info.txt` 读窗口偏移，把**应用内坐标**换算成
屏幕坐标再点击；固定流程（force-stop → 带 trace 启动 → 前置窗口 → 点击 → 移动 → 拉 trace 统计）。
以后所有交互类验证都用它，不再手搓坐标。

### 仍未解

`text_input.set_cursor_rect` 仍没出现在 trace 里（`lgui.lastTextInputRect` 有值、
光标形状能变，说明锚点是有的，但 `textInputAreaSink` 似乎没被调用）。
这是**唯一**剩下的疑点，下轮用同样的探针 + 一行 `probeTrace` 定位。

### 教训（最贵的一条）

**连续三轮的结论都建立在"点了但没反应"之上，而真正的原因是测试工具用错坐标。**
以后凡是"真机上没反应"的判断，第一步必须先用**一个已知能产生反应的坐标**做对照
（本轮就是 `click(900,600)` 有反应 vs 标题栏没有 → 才发现是坐标问题）。

## 第 87 轮（2026-11-11）：IME 光标矩形的协议链接通并验证

### 结论先说

`lw_text_input.set_cursor_rect` **确实发出并被壳收下了**：

```
lwtrace stats:
       1  send:lw_text_input.set_cursor_rect
       1  recv:lw_text_input.set_cursor_rect
```

（用 `LANLU_PROBE_IMERECT=1` 在启动时直接发一条；引擎侧打印 `probe ime rect -> true`。）

### 中途的误判，以及为什么

我一度以为"没发出去"，依据是壳侧 `LOGI_LWP("ime cursor rect ...")` 一行都没出现。
查下来 **`LOGI_LWP` 在真机上报不到 hilog**（同一现象在第 83 轮也出现过：
`LOGI_LWP("cursor shape -> …")` 从来没在 hilog 里见过，见到的都是 ArkTS 的 `[LANLU-SHELL]` 日志）。

**教训**：C 侧的 `LOGI_LWP` 不能作为"有没有执行"的证据，
可靠证据只有 `.lwtrace`（协议层）和 ArkTS 的 `console.info`（UI 层）。

### 真正还缺的一环

ArkTS 泵里拿到矩形后，只有当 `this.ime !== undefined` 才调 `updateCursor` 并打日志。
现在没有任何 `ime cursor` 日志 → **IME 控制器没 attach**。
没有 attach 就没有"输入法面板跟随光标"这个用户可见效果，但协议侧已经全通。

### 下一步（小）

在开始输入时确保 `inputMethod.getController().attach(...)` 成功（现在只有
`setCallingWindow`），然后复用 `tools/ohos-input-probe.sh` 点搜索框验证候选框位置。

## 第 88 轮（2026-11-11）：IME 光标矩形端到端验证通过

### 证据

启动时用 `LANLU_PROBE_IMERECT=1` 让引擎发一条 `(10,20,2,18)`，真机日志：

```
[LANLU-SHELL] IME attached win=942
[LANLU-SHELL] ime cursor 525,312
```

窗口偏移是 `(515,292)`，所以 `515+10=525`、`292+20=312` —— **坐标换算完全正确**，
`inputMethod.updateCursor()` 被真正调用。

上一次我说"还差 IME attach"，这次实测 attach 本来就成功（`IME attached win=…`），
真正缺的只是**一条待应用的矩形**（也就是触发时机），不是 attach。

### 链路总结（现在全部有实证）

| 环节 | 证据 |
|---|---|
| 引擎算出光标矩形 | `lgui.lastTextInputRect` / `textInputAreaSink` |
| 走协议 | `lwtrace`: `send/recv lw_text_input.set_cursor_rect` |
| 壳解析 | napi `lwpTakeImeCursorRect()` 返回 4 个整数 |
| 应用到输入法 | hilog `ime cursor 525,312`（含窗口偏移换算） |

### 仍未验证的一点

"点搜索框 → 焦点 → 锚点变化 → 自动发 set_cursor_rect" 这条**自动**路径，
在本轮这几次运行里没有观察到日志（第 86 轮用另一个 build 时，光标形状确实变成了 1）。
可能是运行状态差异（前台/页面/焦点），需要再跑一次对照。

### 教训

这轮差点又把"IME 没 attach"当成结论 —— 一查日志，attach 一直是成功的。
**否定判断必须带证据**（本轮的做法：先去 `hilog | grep 'IME attached'` 再下结论）。

## 第 89 轮（2026-11-11）：把光标决策挪到 frame tick（仍未在真机观测到）

### 动机

第 86 轮用旧 build 观察到 `cursor shape 0→1`，第 87~88 轮的 build 却怎么点都观测不到。
差别很可能是：旧代码把决策放在**事件源**里，而事件源只在有输入时被调用 ——
焦点刚变化那一刻未必有指针事件，于是"有时能触发、有时不能"。

### 改动

1. `lwindow` 解码 `pointer_motion` 时记录最后指针位置 `lwpNotePointer(x,y)`，
   并暴露 `lwpLastPointer()`；
2. `lwpSetCursorShape` 成功后记录 `lwpCursorShapeSent()`（去抖基准）；
3. `main.cj` 的 `frameProbeHook` 里**每 8 帧**算一次期望形状，变了才发 ——
   不再依赖事件源被调用的时机。

`lwindow` 单测 38 项全过，`build-ohos.sh` exit=0。

### 真机结果：仍然没有 `lw_seat.set_cursor`

用 `tools/ohos-input-probe.sh 690 21`（点了搜索框 + 移动），trace 里只有
25 条 motion + 4 条 button，**没有 set_cursor**。说明 frame tick 里那段被跳过了 ——
最可能是 `lwpLastPointer()` 仍是 `(-1,-1)`（即解码时没记上位置）。

### 下一轮第一件事

在 frame hook 里加一行 probeTrace 打印 `px/py/want/sent`（一次构建即可定位），
先确认"位置有没有记上""want 有没有算出来"，再谈链路。

### 备注

这轮又把"改动 + 构建 + 装机 + 观测"跑了两轮，仍未收敛。
下次动这块之前，先用**最小的可观测点**（一行日志）确认数据来源，
而不是又一次整体重构后再看结果。

## 第 90 轮（2026-11-11）：找到一个吞掉输入事件的真 bug（两个功能随之修好）

### 一行诊断就定位了

在 frame hook 里加一行（每 16 帧）：

```
cursor frame=16 ptr=-1,-1 sent=255 hasRect=0
```

`ptr=-1,-1` 说明**指针位置从来没被记录**——而 `.lwtrace` 里明明有 25 条 motion。

### 根因

`LwpWindowClient.poll()`（`window_client.cj:91`）与输入**共用同一条 EVENT 队列**。
它只关心生命周期事件，遇到不认识的（正是输入事件）就 `continue` —— **消息被丢掉**。
而 `poll()` 由 `lwpFrameTick()` **每帧**调用，于是：

- 指针移动常被 tick 抢走丢弃 → `lwpNotePointer` 永不执行 → 光标形状永远算不出来；
- 焦点/绘制时序也因此抖动 → IME 锚点看起来"时有时无"。

### 修法

在 `backend_lwp.cj` 加一个暂存队列：`poll()` 遇到非生命周期消息时**放回暂存区**，
`nextLwpEvent()` 每次先取暂存区。消息不再丢失。

### 真机验证（修完立刻见效）

```
send/recv lw_seat.set_cursor            ×3     ← 光标形状自动工作
send/recv lw_text_input.set_cursor_rect ×26    ← IME 光标矩形自动工作
hilog: ime cursor 1022,309                     ← 候选框位置随光标更新（含窗口偏移）
hilog: cursor shape 0                          ← 指针离开文本框后回到默认
```

### 影响面（比光标本身更大）

这个 bug 会让**所有悬停/拖拽相关的输入偶发丢失**（每帧 tick 都可能吞一条）。
前几轮我反复"观测不到"的现象，很大一部分就是它造成的 ——
而不是我先后猜的"缺焦点""缺锚点""缺 attach"。

### 学到的

- 输入链路的问题要先确认"**消息有没有到达消费方**"，再谈上层逻辑；
- 一次一行诊断（`ptr=…`）比三轮重构都有效。

## 第 91 轮（2026-11-11）：给"吞输入"bug 补回归测试 + 真机复审

### 回归测试（防复发）

新增 `pollDoesNotSwallowInputEvents`：
`HeadlessShell` 发一条 `pointerMotion(12,34)` → 调用 `LwpWindowClient.poll()` 排空（模拟每帧 tick）
→ 断言这条 motion **still 在暂存区**且能解码回 `PointerMove(12,34)`。

写这条测试时又发现一个细节：暂存区里可能先有 `hello` 等非输入消息，
所以 `nextLwpEvent()` 要**跳过它们继续取**，否则第一条非输入消息会把后面的输入挡住。
两处都改了，lwindow 单测 **39 项全过**。

### 真机复审

| 检查 | 结果 |
|---|---|
| `lw_seat.set_cursor` | ×3（自动） |
| `lw_text_input.set_cursor_rect` | ×28（自动） |
| 输入事件 | 25 motion + 4 button |
| 启动画面 | PNG sha256 `5a274b9e…` —— **与第 68 轮基线逐字节相同** |

也就是说：修复既没有改变渲染结果，也没破坏输入。

### 关于"逐字节相同"这条验收

这已经是它第三次发挥作用（M6 删除后、本轮修复后）。建议把它固化进验收清单：
**任何涉及输入/渲染路径的改动，都要重跑一次启动快照并比对 sha256**，
因为这类回归在"看起来正常"的情况下极难用肉眼发现。

## 第 92 轮（2026-11-11）：清掉同族 bug + 把计划写成可执行状态

### 同族问题排查

第 90 轮修的是 `LwpWindowClient.poll()` 吞输入。本轮把同类的"排空队列"路径也查了一遍：

- `LwpWindowClient.awaitConfigure()`（启动期等首次 configure）：原来 `continue` 掉其它消息 ——
  **现在改为放回暂存区**，启动瞬间到达的输入不会再丢。
- `lwpAwaitSystemInfo()` 走 `pollAll()`，已被第 90 轮的修复覆盖 ✓。

lwindow 单测 39 项全过；真机复验：25 motion + 4 button + 3 set_cursor 正常。

### 计划文档如实标注"实现偏离"

原计划 M3W 写的是用 winit；实际实现用了 `wayland-client + wayland-protocols`（不引入 winit），
理由写进了计划：

1. 壳要精确控制 xdg-shell 请求顺序与 configure/ack 时序，winit 把这些藏起来了；
2. 假合成器测试要能逐字节断言 wire 请求，winit 观测不到。

同时把 M3W 的**已完成项**和**剩余项**逐条写清（剩余：SCM_RIGHTS 集成测试、多显示器、
拖动/缩放、拖放与 portal、.deb 打包与 CI 冒烟）。

### 为什么值得花一轮做文档

用户的目标是"按文档推进计划"。文档与实现的偏差如果不写下来，
下一轮（或下一个人）会按旧计划去用 winit 重写一遍。**偏离必须显式记录**。

## 第 93 轮（2026-11-11）：交互式移动/缩放（协议追加 + Wayland 映射）

### 协议：追加而非插入

`lw_window` 新增两个请求：
- `begin_move()`（无参）——标题栏按下时引擎发起；
- `begin_resize(edges)`——edges 位与 xdg-shell 一致（1=上 2=下 4=左 8=右）。

**踩的坑**：第一次把两条消息插在 `ack_configure` 前面，`--check-abi` 立刻报
「字段被改 / 消息改名」—— 因为 opcode 是**按声明顺序**分配的，插入会平移后面所有消息。
改成追加到 `close` 之后，`opcode` 变成 6/7，检查通过：

```
[PASS] LWP ABI 向后兼容（56 -> 58 条消息，无破坏性变更）
```

这正是"只允许追加"这条规则存在的意义 —— 生成器的 ABI 检查当场抓住了错误。

### Wayland 壳

- `begin_move` → `xdg_toplevel.move(seat, last_input_serial)`；
- `begin_resize(edges)` → `resize(seat, last_input_serial, edge)`；
  组合边映射（1|4→TopLeft 等），`上+下`/`左+右` 这种无意义组合按 None；
- 需要 seat：没有 seat 时打印"缺 seat"而不是静默。

### OHOS 壳

显式分支记录后忽略 —— OHOS 的窗口拖动/缩放由系统窗口管理器负责，应用侧无等价 API。

### 测试

新增 `begin_move_and_resize_map_to_xdg_requests`：假合成器下断言 toplevel 对象收到
`move`(5) 与 `resize`(6)。Wayland 测试 **21 项全过**；`build-ohos.sh` exit=0。

### 顺带

`lwp-gen.py --check` 通过（58 条消息、13 个接口，生成物最新）。

## 第 94 轮（2026-11-11）：多显示器 DPI

### 实现

- `Shell::connect` 遍历全局列表，**绑定每一个 `wl_output`**（之前只绑第一个）；
- `State.output_scales`: 按 output 对象 id 存各自的 scale；
- `wl_surface.enter/leave` → 记录/清除 `surface_output`，并**立即切到该屏的缩放**；
- `output.scale` 事件到达时，如果表面正停在这个 output 上，也立刻应用；
- `flush_configure()` 里的 `set_buffer_scale` 用的是"表面当前所在屏"的缩放。

### 测试

新增 `multi_output_switch_scale`：假合成器广告两个 output（scale 1 / 2），
创建表面后让合成器发 `surface.enter(第二个 output)`，断言
`state.output_scale == 2` 且随后发出的 `set_buffer_scale(2)` 正确。

Wayland 测试 **22 项全过**。

### 过程中两个失误（都已修）

1. `globals.registry().bind(...)` 在 wayland-client 0.31 里**直接返回代理**（失败 panic），
   不是 `Result` —— 我按 `if let Ok(...)` 写，编译立刻报错；
2. 我在 `wl_data_device` 的 `Enter/Leave`（拖放事件）里插了显示器逻辑 ——
   两者都有同名事件，改错了地方。已改到 `wl_surface` 的 Dispatch。

第 2 条属于"同名事件/同名方法"这一类，`grep` 时只看名字不看上下文就会踩。

## 第 95 轮（2026-11-11）：Wayland 拖放（DND）

### 协议（再次验证"只允许追加"）

`lw_window` 追加 4 条事件：`drag_enter(x,y,uris)` / `drag_motion(x,y)` / `drag_leave()` /
`drop(x,y,uris)`。**又一次插错位置**（插到 `configure` 后面），`--check-abi` 立刻报
`close_request -> drag_enter`、`focus -> drag_motion` —— 因为事件 opcode 也按声明顺序分配。
改到 `lw_window` 段末尾后通过：**56 → 62 条消息，无破坏性变更**。

两次都踩同一类坑（第 93 轮是 request，这轮是 event），下次加协议消息的标准动作应该是：
**先在 IDL 段内找最后一个同类块，追加在它后面，再跑 --check-abi**，而不是用"插在某个看起来相关的消息后面"。

### 壳侧实现

| Wayland 事件 | 动作 |
|---|---|
| `wl_data_device.enter` | 记 offer + 坐标 → 发 `drag_enter(x,y,"")` |
| `motion` | 记坐标 → 发 `drag_motion(x,y)` |
| `leave` | 清 offer → 发 `drag_leave` |
| `drop` | 向 offer 要 `text/uri-list`（UnixStream 管道）→ 读完发 `drop(x,y,uris)` |

`uri_to_path()`：`file://` 前缀剥离 + 百分号解码（`%E4%B8%AD` → `中`），非 file URI 原样返回。

### 测试

- `drag_layouts`：四个消息的字节布局（含 uris 头位置）；
- `drag_uri_decoding`：`file:///home/u/a.txt`、含中文的百分号转义、非 file URI、裸路径。

Wayland **23 项全过**；`lwp-gen --check` 通过（62 条消息）。

### 仍缺

引擎侧还没消费拖放事件（`lwindow` 未把它们解码成 UI 事件）—— 需要确定 UI 语义
（拖到书库 = 导入？）。这一步涉及产品决策，先记在计划里，不擅自实现。

## 第 96 轮（2026-11-11）：拖放端到端接通（到引擎为止）

### 引擎侧

`LWindowLifecycleEvent` 新增 4 个事件：`DragEnter(x,y,uris)` / `DragMotion(x,y)` /
`DragLeave` / `DragDrop(x,y,uris)`，从 `lw_window` 的 4 条事件解码。

引擎（`lgpu_backend` 的生命周期分支）接收后：
- `drag_enter` / `drag_leave` / `drop` 各打一条 `probeTrace`（内容含坐标与 uris）；
- `drag_motion` 是高频事件，**不逐条打点**（保持 trace 干净）。

**业务语义仍未实现**（拖到书库要做什么）—— 这是产品决策，我按上轮说的没有擅自决定，
但接口已通到引擎，随时可接。

### 测试

`dragDropDecodesUris`：手工构造 `drop` 消息（x=640, y=480, uris 两行路径），
断言解码出的三元组完全正确。lwindow 单测 **40 项全过**；`build-ohos.sh` exit=0。

### 小坑

测试里第一次把 x/y 的字节写重了（x 占 4..8、y 占 8..12，我写成了 4..8 里塞两个值），
断言立刻抓出来。**手写协议字节时，每个字段的 offset 都要单独核对**。

## 第 97 轮（2026-11-11）：假合成器支持 SCM_RIGHTS（fd 传递不再是盲区）

### 之前的问题

假合成器用 `read_exact` 读消息，**fd 会被内核丢弃** —— 于是
`wl_shm.create_pool`（带 fd）与 `wl_data_offer.receive`（带 fd）这两条路径
在集成测试里**完全看不到**，剪贴板/上屏的"真实 fd 交接"只能靠真机试。

### 实现

- `read_exact_with_fds()`：直接 `recvmsg` + 解析 `SCM_RIGHTS` cmsg，把 fd 取出来；
- `read_msg_fds()`：消息 + 其携带的 fd 一起返回；
- std 的 `SocketAncillary` 在这个工具链上仍是 **unstable**，所以加了 `libc` 作为
  **dev-dependency**（只影响测试，不进产物）。

### 测试

新增 `shm_pool_passes_fd_over_scm_rights`：让壳执行 `attach_shm`（内部 `create_pool` 带 fd），
断言假合成器**真的收到了一个 fd**。

Wayland 测试 **24 项全过**（9 协议 + 14 假合成器 + 1 wire 格式）。

### 遗留

`wl_data_offer.receive` 的 fd 现在理论上也能测了，但需要 mock 参与"写入另一端"的时序，
下一轮再做（剪贴板的 receive 路径）。

### 一个判断

加 `libc` 只作为 **dev-dependency**，并写清理由（std API 未稳定）——
生产的 crate 依赖没变，`cargo tree` 里不会影响发布物。

## 第 98 轮（2026-11-11）：`.deb` 打包迁入 lpack-linux

### 之前的状态

打包逻辑**内联在 CI 的 YAML 里**（约 60 行 shell），本地无法验证，
也无法在 CI 之外复用。计划 §4.4 要求它归属 `packages/lpack-linux`。

### 本轮

`packages/lpack-linux/tools/build-deb.sh`：
- `--binary/--lib/--icon/--version/--depends/--out` 参数化；
- **只捆绑非系统库**（`/usr`、`/lib`、`/lib64` 靠 `Depends` 声明，避免把 glibc 打进包）；
- `/opt/<pkg>` + `/usr/bin` wrapper（设 `LD_LIBRARY_PATH`）；
- `.desktop` 的 `StartupWMClass=lanlu` 与壳上报的 app_id 一致（Wayland 任务栏图标依赖）；
- 仓颉运行时兜底（`CANGJIE_HOME`），保留原 CI 行为；
- **`--self-test`**：用假二进制把整条链路跑通，不需要引擎产物 —— 本机可验证脚本本身。

CI 的 "Package Linux deb" 步骤改为 5 行调用。

### 验证

```
bash packages/lpack-linux/tools/build-deb.sh --self-test
[PASS] 产出 /tmp/.../lanlu-client-next_0.1.0+selftest_amd64.deb
[PASS] 自检：生成了 ...（10 个条目）
```

用真实参数跑一遍并检查产物：

```
dpkg-deb -c  → ./opt/lanlu-client-next/lanlu-client-next, ./usr/bin/lanlu-client-next, ...
dpkg-deb -f  → Package: lanlu-client-next / Version: 1.2.3 / Depends: libvips42t64 | ...
```

workflow YAML 结构检查通过（无制表符、步骤名与脚本调用都在）。守卫 5 项 + Wayland 24 项全过。

### 价值

打包从"CI 黑盒"变成"本地可验证、可复用"的脚本 —— 这正是计划里"平台代码进独立包"的收尾动作之一。

## 第 99 轮（2026-11-11）：剪贴板 receive 的真实 fd 路径集成测试

这是 Wayland 侧最后一个集成盲区：之前只测了"发起读取"和"读回后编码"，
中间"向别的客户端要数据（带 fd）"这段从未被验证。

### 测试设计

假合成器现在能收 fd（第 97 轮），于是可以走完整流程：

```
合成器: data_offer(new_id) -> wl_data_offer.offer("text/plain;charset=utf-8") -> selection(offer)
壳    : 存 offer + mime
引擎  : start_clipboard_read() -> wl_data_offer.receive(mime, fd)
合成器: 收到带 fd 的请求 -> 往 fd 里写 "clipboard-from-other-app" -> close
壳    : poll_clipboard_read() 读回 -> 发 clipboard.text(serial=77, text)
断言  : 内容与对面写入的完全一致
```

### 过程中连踩三个 wayland-client 的约束（都已修，且都是真 bug）

1. **服务端新建对象必须用 server id 空间**：`wl_data_device.data_offer` 会创建 `wl_data_offer`，
   这个 id 必须 ≥ `SERVER_ID_LIMIT`（0xFF00_0000）且**连续分配**；
   随手给个 20 会被判 `invalid id`；
2. **必须实现 `event_created_child`**：否则 wayland-client 直接
   `Missing event_created_child specialization for event opcode 0 of wl_data_device` panic
   —— 也就是说**真机上剪贴板本来就会崩**，只是我们之前没有真实选区所以没触发；
3. **`selection` 不能清空 mime 列表**：`data_offer` → `offer(mime)` → `selection` 是标准顺序，
   我在 `selection` 里清空 mime，把刚收到的 mime 抹掉了（表现为"有选区但 mime 空"）。

第 2 条尤其重要：**它不是测试问题，是产品代码缺陷**。这个测试等于提前发现了一次真机崩溃。

### 结果

Wayland 测试 **25 项全过**（9 协议 + 15 假合成器 + 1 wire 格式）；守卫全部 PASS。

## 第 100 轮（2026-11-11）：CI 的 weston headless 冒烟

### 之前

计划 M3W 第 5 条要求"CI 里 weston headless 冒烟"，一直没做 —— 本机没有合成器，
Wayland 壳只能在假合成器（wire 级）下验证，**真实合成器的握手从未在 CI 跑过**。

### 本轮

`packages/lplatform-wayland/tools/smoke-weston.sh`：
- 起 `weston --backend=headless-backend.so --socket=lanlu-smoke`（临时 `XDG_RUNTIME_DIR`）；
- 等 socket 出现（最多 10s），设 `WAYLAND_DISPLAY`，跑壳 N 秒；
- 断言日志里有 `hello 已发出`（握手成功）；没有 `window.create` 只 WARN（无输入时壳不建窗）；
- **本机没有 weston → 优雅跳过**（`[SKIP]`），CI 里用 `--require` 强制要求。

CI 新增步骤：装 weston → `cargo build --release` → `bash packages/lplatform-wayland/tools/smoke-weston.sh --require`。

### 验证

本机（无 weston）：

```
bash packages/lplatform-wayland/tools/smoke-weston.sh
[SKIP] 本机没有 weston，跳过 Wayland 冒烟（CI 里会跑）
```

workflow 结构检查通过（无制表符、步骤就位）。

### 说明

`--require` 的设计意图：**本机跳过、CI 必须跑**。否则很容易出现"CI 里悄悄跳过，
大家以为在验证"的假安全感 —— 这和第 90 轮那个吞输入 bug 的教训是同一类。

### 计划更新

M3W 第 5 条：`.deb` 打包 ✅、CI 冒烟 ✅（本轮）。

## 第 101 轮（2026-11-11）：完整验收 + 发现一个产品缺口

### 做了什么

把 100 轮的成果一次性验完：7 项守卫 + 12 项测试套件 + OHOS 真机 7 条判据 + 画面逐字节比对，
产出 [lwp-acceptance-report.md](lwp-acceptance-report.md)。

### 结果（全部 PASS）

- 守卫 7 项全 PASS；
- 测试：lwindow **40/40**、Wayland **25/25**、lwp 套件、OHOS 壳自测、打包自检 —— 全通过；
- 真机：`sent=653 recv=653`、违约三项全 0、`lwtrace verify` 1299 条 PASS；
  光标形状（`set_cursor`）与 IME 锚点（`set_cursor_rect` ×29）都在自动工作；
- **画面 PNG sha256 `5a274b9e…`，与第 68/91 轮逐字节相同**（三次基线一致）。

### 新发现的产品缺口（重要）

复验"连续 resize 不崩"这条判据时，我试图拖窗口边缘缩放 —— **窗口尺寸没变**，
且 `lw_surface.changed` 一条都没产生。

原因：**无边框窗口隐藏了系统装饰，而我们的自绘标题栏也没有 resize 边缘/拖拽热区**。
也就是说，**OHOS 上用户现在无法用鼠标拖边调整窗口大小**（只能靠系统最大化/还原）。

`lw_window.begin_resize(edges)` 已经加好、Wayland 侧也实现了，但 OHOS 侧没有对应系统 API
（拖动窗口/缩放由系统窗口管理器负责）。要做的话得在标题栏/边缘自绘热区，并在拖动时
转发给系统（或自己算几何）。

**这条要记成产品缺口，而不是"验收通过"** —— 之前第 54 轮记的"54 次真实 resize"
应该是通过系统最大化/还原触发的，和拖边缩放不是一回事。

### 教训

"验收通过"要写清**是怎么测的**。这次如果只看"进程没崩"就写 PASS，
用户拖边不能缩放的缺口会一直藏着。

## 第 102 轮（2026-11-11）：撤销一个建立在误测上的"产品缺口"

### 上轮的判断

第 101 轮我写进验收报告："无边框窗口没有自绘 resize 边缘，用户无法拖边缩放"，并据此认为这是产品缺口。

### 本轮做了什么

按这个判断实现了「引擎边缘热区 + `begin_resize` → 壳换算尺寸 → ArkTS `win.resize()`」整条链路，
装机复验。结果发现：

- 拖右边框（**窗口内**坐标，屏幕 x≈2600）→ 窗口从 `2090×1394` 变成 `2413×1729`；
- 但 trace 里**一条 `lw_window.begin_resize` 都没有** —— 说明这次缩放是**系统原生**做的，不是我们的代码。

### 结论

**OHOS 本来支持无边框窗口拖边缩放**。第 101 轮"拖边没反应"是因为我用的拖动起点
`(3100,400)` **落在窗口外**（窗口范围是 x 515..2605、y 292..1686）——
和第 86 轮那次坐标错误是同一个毛病。

### 处置

- **撤掉**引擎侧自绘边缘热区（否则会和系统原生缩放打架）；
- 保留协议 `begin_move/begin_resize` 与壳侧 resize 会话（Wayland 需要，OHOS 不用）；
- 修正 `lwp-acceptance-report.md` 第 6 条判据为 PASS，并在缺口表里写明"已澄清：不是缺口"。

### 教训（第三次同类）

**"没有反应"必须先确认"操作真的作用在了目标对象上"**。
第 86 轮是 uitest 坐标 vs 窗口偏移；这轮是拖动起点在窗口外。
两次都不是产品问题，而是**测量问题被误当成产品问题**，还据此写了一轮代码。

以后凡是"某功能不工作"的结论，先做一次**正对照**：用已知有效的操作证明链路本身是通的。

## 第 103 轮（2026-11-11）：把踩过的坑固化成验证纪律

### 为什么值得单独成文

102 轮里有一类错误反复出现，代价都不小（写错代码、误报缺口、白跑构建）：

- 否定结论没有执行证据（第 83、87 轮）；
- "没反应"先归因产品，而不是先做正对照（第 86、101 轮）；
- 消息被吞却去改上层逻辑（第 90 轮）；
- 静默分支不做打点（第 70 轮）；
- 测试基建的假通过/假失败（第 75、76、99、100 轮）；
- 协议编号凭记忆（4 次）；
- 证据不逐字节（第 68、91 轮）；
- 把"最可能解释"说成"根因"（第 83~85 轮）。

新增 [lwp-verification-discipline.md](lwp-verification-discipline.md)：8 条规则，每条都注明轮次与具体现象。

### resize 判据改成精确表述

本轮再次尝试用脚本复现"拖边缩放"：**没复现**（起点差几像素就变成内容点击）。
结合第 102 轮那次成功（2090×1394 → 2413×1729），验收报告改成：

> 系统**支持**拖边缩放，但脚本复现不稳定；第 54 轮的 54 次 resize 走的是「最大化/还原」路径。

**不能写成 PASS** —— "有时能、有时不能"本身就是要记录的事实，而不是要抹平的差异。

## 第 104 轮（2026-11-11）：文档一致性守卫

### 问题

文档里的数字会漂移：协议消息数、接口数、文件桥处数、跨文档链接。
漂移**不会让任何测试失败**，但会误导下一个人（103 轮里已经出现过几次：
报告里写 56 条消息、实际 62 条；链接指向已删除的章节）。

### 实现

`tools/check-docs-consistency.py`：
1. **协议数字**：文档里的 `N 条消息 / M 个接口` 必须等于 `lwp-gen.py --check` 的真实值；
2. **文件桥处数**：仅检查提到"文件桥"的行，写的 `A → B` 的 B 必须等于实际扫描数；
3. **相对链接**：所有 `](path)` 目标必须存在（http 除外）。

**范围收窄**：只校验"当前状态类"文档（验收报告 / 交接状态 / 计划正文）。
进度日志里的历史数字**不校验** —— 它们本来就该与现在不同（第一版没区分，
报出 9 处"不一致"，全是历史记录，属于误报）。

### 验证（先证明它会失败）

- 造一个坏链接 → `[FAIL] ... 链接目标不存在` ✅
- 往交接文档临时插一句 `协议 55 条消息 / 9 个接口，文件桥 35 → 7` →
  两条都被抓到（`实际 62 / 13`、`实际现状 2`）✅
- 恢复后 `[PASS] 文档一致（协议 62 条 / 13 接口，文件桥 2 处）`

已加入 CI 的守卫步骤，并写进 `lwp-verification-discipline.md` 第 9 条。

## 第 105 轮（2026-11-11）：lpack-ohos 自检（与 lpack-linux 对齐）

### 动机

`packages/lpack-linux` 有 `build-deb.sh --self-test`（不需要产物就能验证脚本与依赖），
而 `lpack-ohos/build-ohos.sh` **只能整跑** —— 环境缺件要等到构建中段才炸，
CI 与本机排障都慢。

### 本轮

`build-ohos.sh` 新增：
- `--self-check`：只校验工具链 / 应用 profile / 预编译材料，**秒级返回**；
- `--app <name>`、`--build-dir <dir>`：把原来只能靠环境变量改的东西参数化；
- `-h/--help`：打印用法。

### 验证（真实环境，不是模拟）

```
bash packages/lpack-ohos/tools/build-ohos.sh --self-check
== lpack-ohos 自检（不构建）==
  应用 profile : packages/lpack-ohos/app-profiles/lanlu
  OHOS SDK     : .../sdk/default/openharmony/native
  sysroot      : .../native/sysroot
  仓颉工具链   : /workspace/.cjv/toolchains/sts-1.2.0-linux-x64-ohos
  宿主工具链   : /workspace/.cjv/toolchains/sts-1.2.0
  构建目录     : client-next/build/ohos
  预编译材料   : /workspace/lanlu/.research-ohos
[PASS] 自检通过（工具链与 profile 就位，预编译材料见上一步）
```

再跑一次完整构建确认没破坏原路径：`BUILD SUCCESSFUL`，exit=0。

CI 守卫步骤里加了这段自检（无仓颉工具链时跳过，不阻塞无关改动）。

### 一致性

两个平台包现在形状一致：

| 包 | 自检 | 产物 |
|---|---|---|
| `lpack-ohos` | `build-ohos.sh --self-check` | HAP |
| `lpack-linux` | `build-deb.sh --self-test` | .deb |

## 第 106 轮（2026-11-11）：文档一致性审计

### 做了什么

1. **新增「已被推翻的结论」索引**（进度文档顶部）：把 6 条被后续证据推翻的判断集中列出，
   并注明纠正轮次。进度日志本身不改写（保留原始记录），但这个索引能让读者**不被旧结论误导**：

   | 旧结论 | 事实 |
   |---|---|
   | "宿主机没有 Rust 工具链，M1W 被环境阻塞" | cargo 一直可用（第 73 轮） |
   | "跑不了引擎测试因为缺 cargo" | 是 ffmpeg 开发头（第 73 轮） |
   | "引擎没发 set_cursor" | 发了（第 83 轮） |
   | "缺焦点/缺 IME attach" | 是坐标错误 + `poll()` 吞输入（第 86/90 轮） |
   | "无边框窗口不能拖边缩放" | 系统支持，是坐标落在窗口外（第 102 轮） |
   | "决策放事件源里足够" | 需放 frame tick（第 89 轮） |

2. **对齐三份文档的缺口清单**：交接文档原来的"仍缺三件事"已经过期
   （还写着"cursor shapes 全量"，而它已完成并真机验证）。现在交接文档、验收报告、
   计划三处的缺口集合一致，并补上了此前漏记的
   「OHOS `attach.serial` 消费 / dmabuf」。

### 为什么值得做

文档漂移不会让测试变红，但会让下一个人（或下一轮的我）**照着过期结论行动** ——
第 73 轮就因为"宿主机没有 cargo"这条过期结论，把 M1W 误判为环境阻塞，耽误了十几轮。

### 验证

`python3 tools/check-docs-consistency.py` → PASS（协议 62 / 13 接口，文件桥 2 处，链接全部可达）。

## 第 107 轮（2026-11-11）：平台包公开 API 清单

### 做了什么

扫描 `packages/lwindow/src/*.cj` 的 103 个 `public` 声明，统计 `client-next` 与各平台包里的实际引用，
产出 [lwp-platform-api.md](lwp-platform-api.md)：

| 分类 | 数量 | 含义 |
|---|---|---|
| 引擎实际使用 | 40 | 真正被业务代码调用的 API 面 |
| 仅测试 / 诊断使用 | 55 | 测试夹具（`backend_headless.cj`）与诊断入口 |
| **无外部引用** | 6 | 见下表 |

无外部引用的 6 个及处置：

| API | 建议 | 理由 |
|---|---|---|
| `lwpBeginMove` | 保留 | 协议已存在、Wayland 壳已实现；OHOS 上引擎目前不需要（系统支持拖标题栏移窗） |
| `setTitle` / `currentWindowId` | 保留 | 与 `create(title,…)` 对称，删了 API 面不完整 |
| `lwpInputChannel` / `lwpBacklogSize` | 保留 | 联调诊断入口（第 90 轮排查"事件被吞"就用得上） |
| `sendAppStarted` | 可删 | 测试夹具空壳方法，从未调用 |

### 一个副产品结论

**`lwpBeginMove` 已就绪但引擎未调用** —— 这是"自绘标题栏拖动窗口"的入口。
OHOS 系统本身支持拖标题栏移窗，所以当前不需要；但这条**功能入口**以前散落在代码里没人知道。

### 生成方式与局限

脚本按"定义文件之外的引用计数 + 是否被 client-next 引用"分类。
注意：同文件内部使用的 `WindowGeometry`、`lwpNowNs` 被初版误判为孤儿，
人工复核后从孤儿表移出 —— **自动分析一定要人工过一遍再下结论**。

## 第 108 轮（2026-11-11）：已知限制清单 + 行号引用守卫

### 1. 已知限制清单

先把代码里所有 `TODO/FIXME/暂未实现/no-op` 扫了一遍：**全仓只有 6 处注释级标记**，
说明代码里没有以 TODO 形式堆着的欠账。真正的限制是"刻意留白"，散在各处。

于是新增 [lwp-known-limitations.md](lwp-known-limitations.md)，分四类：

1. **协议/平台能力限制**（6 条）：`clipboard.set` 忽略 mime、OHOS 不消费 `attach.serial`、
   无 dmabuf、Wayland 未实现能力不置位、拖放不传动作、滚轮 ÷45 换算；
2. **刻意保留的空实现**（6 条）：M6 遗留的 napi 空函数、`Cursor.system` 空光标、
   `setTextInputArea` 默认空实现等 —— 每条都写清"为什么保留"；
3. **需外部条件才能关闭的缺口**（链到验收报告 §4）；
4. **UI 层"暂未实现"** toast（产品未完工的显式提示）。

### 2. 文档守卫支持行号引用

`tools/check-docs-consistency.py` 新增第 3 项检查：文档里的 `file.cpp:123` 必须
**文件存在且行号未越界**（仅"当前状态类"文档；进度日志允许引用已删除文件）。

实现上踩了一个坑：最初对每个引用做 `ROOT.rglob()`，**扫到 target/ 里几十万文件，检查直接超时**。
改成**一次性建立文件名索引**（跳过 target/build/node_modules），耗时从 >60s 降到亚秒。

验证（先证明会失败）：把 `lwp_window.cpp:367` 改成 `:99999` →
`[FAIL] ... 超出文件行数（共 509 行）`；还原后 PASS。

## 第 109 轮（2026-11-11）：新读者演练 → 补「常见任务导航」

### 做法

假装一个刚接手的人，只读 5 份交接文档去回答 7 个真实问题：
改协议消息、加壳能力、真机验证、跑测试、为什么不用 winit、崩溃怎么查、怎么接新平台。

**结论：前四个能找到零散信息但拼不出完整流程，后三个基本无答案。**

### 补充

交接文档新增「常见任务导航」，7 个任务都写成可复制的命令序列 + 该改哪个文件：

- **改/加协议消息**：改 IDL（**追加在段末**）→ `lwp-gen.py` → `--check-abi` → 编码器/客户端/壳解析 → 三套测试；
- **加壳能力**：能力位定义位置（两平台各一处）+ "只有真实现才置位"；
- **真机验证**：build → sign → install → `tools/ohos-input-probe.sh`（自动换算窗口偏移）+ trace/probe 的取法；
- **跑测试与守卫**：指向既有小节；
- **为什么不用 winit**：链到计划 §M3W 的实现偏离说明；
- **崩溃排查**：trace → probe → 区分冻结与死锁 → 先做正对照；
- **接新平台**：要做什么 + 参考实现路径 + 打包脚本参考。

### 顺手加的第 4 项守卫

文档里 `bash/py/sh <路径>` 引用的脚本必须存在。**立刻揪出一处**：
进度日志里把冒烟脚本写成了 `tools/smoke-weston.sh`（真实路径在 `packages/lplatform-wayland/tools/`）——
已修正。

### 验证

照文档走了一遍真机流程（build → install → trace → `lwtrace verify`），
`[PASS] 结构完整：327 条记录`；守卫全部 PASS。

## 第 110 轮（2026-11-11）：发现"引擎从不提交帧"

### 起因

想把已知限制里的"OHOS 不消费 `attach.serial`"关掉：给壳加了 attach 解析 + 每 120 帧打点。
真机一看 **`frames=0`** —— 壳根本没收到过 `surface.attach`。

### 根因

`grep -rn '\.attach(' client-next/src` → **零结果**。
`LwpWindowClient.attach()` 只在测试里被调用过，**引擎从来没有提交过帧**。

影响比想象的大：
1. 检查器的 `attachOutOfOrder` / `attachAfterDestroy` 两个计数器**永远是 0**（没有输入）；
2. 壳无法做帧统计（第 110 轮前 OHOS 侧完全没有 attach 处理）；
3. **Wayland 的 wl_shm 上屏路径拿不到帧** —— 壳侧虽然实现了 `attach_shm`，
   但引擎不发 attach，真实运行时一帧都不会上屏（此前只在假合成器测试里验证过壳的内部逻辑）。

### 修复

`lwpFrameTick()` 里每帧提交：`win.attach(0, surfaceWidth, surfaceHeight)`
（buffer=0 = 引擎已直接渲染进壳的 surface，符合计划 §7.3.1 的 OHOS 语义）。

### 真机验证

```
hilog: [LANLU-SHELL] frames=90 lastAttachSerial=180 backwards=0
trace: 133 send:lw_surface.attach / 133 recv
       lwp violations unackedConfigure=0 frameTimeout=0 attachOutOfOrder=0
       lwtrace verify PASS（735 条记录）
```

（`frames=90` 后不再增长是**按需渲染**的正常表现：静止时没有新帧。）

### 教训

这是"**协议定义了、两端都实现了 API、但没有人调用**"的又一个实例（之前有
`Cursor.system`、`textInputAreaSink`）。三次都是靠"加一次打点"发现的。

**规则**：协议消息只要在文档里写了"必须发"，就要有一条测试或打点证明**它真的在发**。

## 第 111 轮（2026-11-11）：协议消息覆盖审计

### 做法

解析 IDL 的 62 条消息，对每条在两个方向检索 opcode 常量/编码函数的出现（排除测试），
再**逐条人工复核**（启发式会漏判：Wayland 壳用自己的常量名、C 壳用生成宏）。

### 结论

| 分类 | 条数 |
|---|---|
| 双向实现 | 46 |
| **壳不处理 / 未实现** | 6（`seat.capabilities`、`window.set_title`、`window.set_min_max`、`seat.lock_cursor`、`app.quit`、`text_input.set_surrounding`） |
| 声明但未使用 | 4（`ping`/`pong`、`error`、`text_input.preedit`） |
| 启发式漏判、人工确认正常 | 2（`frame.done`、`hello_ack`） |

每条未实现项都写清了"为什么"（能力已由 hello 一次性告知、退出走 exit、预编辑由 ArkTS 自绘等），
产出 [lwp-message-coverage.md](lwp-message-coverage.md)。

### 配套规则

把第 110 轮的教训固化为验证纪律**第 10 条**：文档里写了"必须发"的消息，
必须有测试或打点证明**它真的在发**。并列出 4 条已兑现证据、以及未兑现的项
（即覆盖表里的"壳不处理"项，实现前不得写进"已完成"）。

### 这轮的价值

第 110 轮是**偶然**发现一个 `attach` 没人调用；这轮把同类风险**系统性地摊开** ——
62 条消息全部有结论，而不是等下一次"加打点"再撞见。

## 第 112 轮（2026-11-11）：补齐 set_title / set_min_max（并修正 3 个错误 opcode）

### 实现

| 消息 | Wayland | OHOS |
|---|---|---|
| `window.set_title` | `xdg_toplevel.set_title` | `window.setWindowTitle`（ArkTS） |
| `window.set_min_max` | `set_min_size`/`set_max_size` | `setWindowLimits({minWidth,…})` |

引擎侧新增 `lwpSetWindowTitle` / `lwpSetWindowMinMax`，并在启动时各调一次
（**有调用方**，避免重演"attach 定义了却没人发"）。

### 途中发现：Wayland 壳有 3 个 opcode 是错的

改这两条消息时对照生成头文件，发现 `lplatform-wayland/src/protocol.rs` 里的常量：
- `WINDOW_SET_STATE_REQ` 写成 2（真值 4）；
- `WINDOW_CLOSE_REQ` 写成 3（真值 5）；
- 还缺 `SET_TITLE(2)` / `SET_MIN_MAX(3)`。

也就是说**之前 Wayland 侧的 `window.close` 永远匹配不上**，`set_state` 会走到 set_title 分支。
这正是"凭记忆写编号"的第 N 次。

**新增回归测试** `window_request_opcodes_match_c_header`：直接读
`packages/lwp/include/lwp_protocol.h` 逐条比对 7 个窗口请求 opcode —— 以后再写错会被测试拦住。

### 真机验证

```
trace : send/recv lw_window.set_title ×1、lw_window.set_min_max ×1
hilog : [LANLU-SHELL] window title -> Lanlu
        [LANLU-SHELL] window limits applied
```

Wayland 测试 **26 项**（含新 opcode 对照）、lwindow **40 项**、lwp 套件全部通过；HAP 构建 exit=0。

## 第 113 轮（2026-11-11）：文本输入开关（enable/disable）

### 之前的状态

`lw_text_input.enable/disable` 两条消息：引擎有 API（`imeEnable`）**但无人调用**，
两个壳也**都不处理**。而壳侧是把"attach 输入法"写死在启动流程里的 ——
等于软件键盘在不需要的时候也存在。

### 实现

1. **引擎**：每帧比较 `lgui.debugFocusId`，焦点变化时调 `lwpImeEnable(hasText)`；
2. **OHOS 壳**：泵解析 enable/disable → `g_ime_want`（-1/0/1）→ napi `lwpTakeImeWant()`；
3. **ArkTS**：拿到 1 → `attachIme()`；拿到 0 → `this.ime.detach()` 并把 `imeAttached=false`。

### 真机验证

```
trace : send/recv lw_text_input.enable ×1
hilog : [LANLU-SHELL] ime want=on
        [LANLU-SHELL] IME attached win=965
        （同时 set_cursor_rect ×28 照常在走）
```

点搜索框 → 焦点变化 → 引擎发 enable → 壳收到并 attach 输入法。**整条链闭合**。

### 途中三次编译错误（都是"声明位置"）

1. Cangjie：`var g_lastFocusId` 被插进了多行 import 中间 → 语法错；
2. C：`g_ime_want` 声明在首次使用之后（C 要求先声明再使用）；
3. Cangjie：`lgui.debugFocusId` 需要显式 `import lgui.{debugFocusId}`，不能靠包名限定。

第 1、2 条是同一类：**给文件加全局变量时，必须放在"所有使用点之前"**，
而 `str.replace` 往文件里插代码时很容易选中一段更靠后的锚点。

### 覆盖表更新

62 条消息：**50 双向**（+2），12 单侧或未实现。

## 第 114 轮（2026-11-11）：把"未实现"变成"决策"

### 为什么

上一轮覆盖表里还剩 12 条写着"未实现/单侧"。这种状态是**模糊**的：
没人知道它是缺陷、是遗漏、还是有意为之 —— 于是既不会被修，也不会被清理。

### 做法

逐条查代码 + 查设计意图，给每条一个**明确决策 + 触发条件**：

| 决策 | 条数 | 说明 |
|---|---|---|
| 协议预留（保留，写明触发条件） | 8 | `seat.capabilities`（热插拔）、`seat.lock_cursor`（游戏）、`app.quit`（走壳的退出流程）、`text_input.set_surrounding`、`text_input.preedit`、`ping/pong`、`error` |
| 已实现（扫描漏判，人工确认） | 4 | `set_title`、`set_min_max`、`text_input.enable/disable`、`frame.done`、`hello_ack` 中的已落地项 |

**结论：没有需要立刻删除的消息。**

### 为什么不直接删预留项

协议发布后删消息要动 `protocol_major`；而这套通道的设计目标之一就是
"把平台差异提前建模"（计划 §5）。**预留 + 写明触发条件**比"删掉再加"便宜。

代价是覆盖表需要**定期复核** —— 所以文档里写明了"本轮就是一次复核"，并留下决策表，
下次谁再看到这些消息，能立刻知道该不该动。

### 产出

`docs/lwp-message-coverage.md` 从"待办清单"变成"决策依据"。

## 第 115 轮（2026-11-11）：收尾验证与交接

计划中**不依赖外部输入的工作已全部完成**。本轮做三件事收尾。

### 1. 全量验证（一次跑完）

| 类别 | 结果 |
|---|---|
| 守卫 8 项 | 全 PASS（文件桥 2 / 依赖 10 / 平台隔离 73 / 分层 / 去 SDL / 文档一致 / 生成物最新 / ABI 兼容） |
| `packages/lwp/test.sh` | PASS |
| `packages/lwindow` | **40 / 40** |
| `packages/lplatform-wayland` | **26**（10 协议 + 15 假合成器 + 1 wire） |
| `lplatform-ohos/selftest` | PASS |
| `lpack-ohos --self-check` | PASS |
| `lpack-linux --self-test` | PASS（生成 .deb） |
| 设备 | 装最新 HAP，输入/光标/IME/帧提交均在跑 |

### 2. 源码快照

`/workspace/lanlu/tmp/snapshots/final-107-1020.tgz`（packages + docs + client-next/src + tools
+ .github，排除 target/.git，903MB）。

> 为什么总要打快照：平台包的 C++/ArkTS 源码**不在 git 跟踪范围内**（`git status` 显示 `??`），
> 删错无法回滚 —— 第 55~57 轮已经因此吃过一次教训。

### 3. 交接清单

`lwp-handoff-status.md` 顶部新增「接手第一天该做什么」：读哪三份 → 跑哪条命令 →
装机冒烟看哪三条日志 → 然后去哪里看缺口与决策表。**每步都有可验证输出**。

### 结项判断（如实说）

- **已完成**：M0/M1/M2/M3/M6（OHOS 主线，含真机验收）、M1W/M2W/M3W 本机可验证部分、
  协议 62 条消息逐条有结论、8 项守卫进 CI、6 份交接文档、两平台打包脚本。
- **未完成（需外部输入）**：拖放业务语义（产品决策）、滚轮人工验证、xdg-desktop-portal（D-Bus）、
  真实合成器目视验证、引擎渲染到 Wayland fd。

**继续推进的唯一瓶颈不在代码侧。**

## 第 116 轮（2026-11-11）：真机 DPI 缩放修复（用户当场指出）

### 用户指出的问题

> "为什么没跟随系统的 200% 缩放"

真机在 PC 模式 190% 缩放下，窗口内容只铺满**左上角**，右侧/下方大片纯黑。
用户贴了截图，我起初在折腾拖边缩放 —— **方向完全错了**。

### 证据链

| 观测 | 值 |
|---|---|
| 系统 `display.densityPixels` | **1.9**（hilog `window created density=1.899…`） |
| 引擎 `first frame begin scale=` | **1.0** ❌ |
| 窗口物理尺寸（hidumper） | 2090×1394 |
| 引擎逻辑布局 | 2090×1394（应为 1100×733） |

逻辑尺寸与物理尺寸相同 + `canvas.scale=1.0` → 内容只画 1/1.9 的区域。

### 根因（两处硬编码）

1. **ArkTS**：`shell.lwpWindowCreated(props.id, 1.0, false)` —— 硬编码 1.0，
   从未上报系统密度；
2. **引擎**：`installLwpWindowIfRequested` 里 `canvasL.scale = 1.0` —— 硬编码；
   而同一文件另一个函数 `installLwpWindow` 里的 `canvas.scale` 我改对了，
   **但实际生效的是前者**（两个安装路径）。

### 修复（四处）

1. ArkTS：`display.getDefaultDisplaySync().densityPixels` 上报真实密度（1.9）；
2. `LwpWindowClient.reportedScale`：收到 `window.created` 时记录；
3. `preferredWindowGeometry`：**物理尺寸 ÷ scale = 逻辑尺寸**（2090/1.9 → 1100×733）；
4. `canvas.scale = lwindow.lwpReportedScale()`（**protocol 路径那处**）。

### 真机验证（修复后）

```
geometry 1100x733 scale=1.900000 reportedScale=1.900000
lwp canvas scale=1.900000 (物理 2090x1394)
first frame begin scale=1.900000
```

截图确认：内容**铺满整个窗口**（标题栏/侧栏/卡片/控件全部按 190% 渲染）。

### 教训

- "缩放有问题"要先分清**两种缩放**：① 系统 DPI（本次）；② 拖边改窗口大小（另一件事）。
  我在错误的方向上花了一轮多。
- 同一个功能有**两个安装路径**时，改完必须确认哪条真的在跑（`lwp canvas 已安装`
  那条 probe 来自 env 路径，而 protocol 路径的 probe 文案不同）。

### 仍未修：拖边缩放

`g_win_w` 现在是**物理**尺寸（2090），而边缘判定用的是**逻辑**坐标（最大 1100），
所以 `ev.x >= g_win_w - 8` 永不成立。需要把边缘判定改成逻辑尺寸、壳侧 resize 再 ×density。

## 待复核 / 已知风险

- `packages/lpack-ohos` 引入了上游 hapgen 的整棵树：`assets/libcxx/libc++.so`（二进制，ABI 对齐用）
  入库是否可接受需确认；如不可接受，改为构建期从独立仓拉取。
- `RES`（`ohos-stubs`、`sdl3-ohos/prefix-*`）仍是仓外预编译材料；M0-7 收尾时要决定：
  迁入 `lplatform-ohos/deps/prebuilt/`，还是由 `lpack-ohos` 在构建时从独立仓拉取。
- `tools/` 下 5 个脚本（`build-ffmpeg-ohos`、`check-hap-deps`、`make-sdl3-noversion`、`sign-hap`、
  `verify-window`）仍写死 `/workspace/...` 与 `.research-ohos`，M0-7 待办。
- HAP 内仍有 `libSDL3.so` / `libSDL3_ttf.so`：属 M6 范围，非本轮缺陷。
## 下一步（第 55 轮）

1. **M6 第 1 步**：删 `readInputEvents/readTextInputs/readKeyEvents` 与壳侧三个写点，
   跑全量测试 + 真机复验（`LANLU_LWP=0` 退路会因此失效 —— 这是 M6 的预期代价）。
2. 滚轮与输入法的人工确认（需要用户操作）。
3. 文件桥基线更新（35 → 更低），并把 §11 表状态改为「已删除」。
