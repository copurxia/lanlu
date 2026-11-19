# lwindow 协议化与平台层彻底分离 —— 开发计划

- 日期：2026-11-10
- 范围：`client-next`（业务）、`packages/cangjie-gui`（cui + lgui）、`packages/lwindow`、`packages/lgpu`、鸿蒙壳与工程生成器（当前在仓外 `.research-ohos/packages/ohos`）、Wayland 桌面后端（新建）
- 修订：2026-11-10 第二版——取消 SDL 过渡壳，SDL 从仓库彻底删除；桌面直接对接 Wayland；平台代码限定在 4 个独立平台包，鸿蒙工程继续由独立生成器包生成
- 目标一句话：**像 Chromium 维护 ozone + mojo 一样，自己定义并维护一套“壳 ↔ 引擎”的 L 层协议（LWP，Lanlu Window Protocol），所有 OS 差异只存在于协议的“壳端实现”里；业务层与 UI 框架只认识协议抽象出来的跨平台类型。键盘、鼠标、触摸、滚轮、IME、光标、窗口、Surface/帧、剪贴板、对话框、路径、语言/主题全部纳入协议。**

相关文档：[lwindow.md](lwindow.md)（适配层现状说明）、[l-layer.md](l-layer.md)（lgpu 渲染器与去 SDL 进度）、[client-next-ohos-plan.md](client-next-ohos-plan.md)（OHOS 可行性调研）。

---

## 0. 结论速览

| 问题 | 结论 |
|---|---|
| 现在有“协议”吗？ | **没有。** 壳与引擎之间靠 13 个轮询文本文件 + 环境变量 + volatile 全局标志 + 30 个 NAPI 函数通信，没有类型、版本、序号、背压，也没有唤醒机制（§1.2） |
| 键鼠现状 | 有损且有丢事件 bug：物理按键根本没送进引擎；每次轮询只取第一条事件、其余被清空丢弃；鼠标一律当左键；滚轮根本到不了引擎（窗口过滤器收不到滚轮）；修饰键被当作 repeat 标志；`Keyboard.modifiers()` 仍调 SDL；IME 没有预编辑；剪贴板读取方式违反系统规则（§1.3） |
| 平台是否已分离 | 只做到“字符串层面”：守卫脚本查不到 `ohos_` 字样即算通过。结构上 `client-next` 仍直接用 `SdlWindow`/`SdlHints`/`lgpu.capture*`/`lgui.input`，cui 仍依赖 `lgui`（SDL 绑定包）。平台代码散落在 9 类位置：`lwindow`（`ohos_*.cj`）、`lgpu`（`OH_NativeWindow_*`）、5 个 `native-ohos/` 目录（4 个 FFI 包 + lgpu）、`portcheck`（`ohos_selftest*`）、`client-next/ohos/`、`client-next/cjpm.toml` 的鸿蒙/mingw 段、`tools/` 下的鸿蒙脚本、6 个中立包 `cjpm.toml` 里的鸿蒙交叉编译段、仓外的壳模板（§1.4、§4.2） |
| 桌面端 | **当前没有可用的窗口后端**：`lgui` 里建窗/取事件的 SDL 代码已删，`lgpu` 只支持 OHOS 窗口句柄（§1.5）。**决定：不做 SDL 过渡壳，直接实现 Wayland 原生壳；SDL 从仓库彻底删除**（lgui 中 31 个 SDL 声明、24 MB + 4.2 MB 预编译库、libdecor 插件、CI 的 SDL 步骤与 Windows 构建任务）。桌面只支持 Wayland 会话 |
| 做法 | 1）定义 LWP 协议：IDL 描述 → 生成 C 头 + 仓颉绑定 + 壳端分发桩 + 文档；2）传输用进程内环形队列 + eventfd 唤醒（引擎真阻塞空闲，取代 4ms 轮询读文件）；3）鸿蒙壳：NDK C API 能做的全部下沉到 C，ArkTS 只保留系统强制的薄壳；4）Wayland 壳：Rust 宿主程序，wayland-client + xkbcommon + text-input-v3 + xdg-desktop-portal；5）cui/业务只依赖 `lwindow` 的跨平台 API；6）**平台代码只允许出现在 4 个独立包**：`lplatform-ohos`、`lpack-ohos`、`lplatform-wayland`、`lpack-linux`；鸿蒙工程继续由独立的生成器包生成（现有 hapgen 演进为 `lpack-ohos`），主仓不存放鸿蒙工程；7）依赖白名单 + 平台标识守卫在 CI 强制 |
| 借鉴谁 | Chromium（ozone 平台抽象、mojo 的 IDL + 版本规则、DEPS 依赖白名单、DomCode 单表生成键码）、Wayland（对象/接口/版本、请求 vs 事件、configure/ack 双缓冲状态、text-input-v3 的 IME 模型、pointer.frame 分组）、Flutter Embedder（`struct_size` 版本化 C ABI、platform channel）、winit（KeyEvent = 物理码 + 逻辑键 + 文本；`Ime::Preedit/Commit`；`pre_present_notify`）、Qt QPA（单一事件注入漏斗 + 能力枚举）、GPUI/Slint（Platform/PlatformWindow trait + TestPlatform 无头测试）、Android GameTextInput（状态式 IME） |
| 工期估算 | 单人约 15–16 周；M1 之后分“鸿蒙线 / Wayland 线”两人并行约 10–11 周，含调试与测试设施（§10、§16） |
| 测试与调试 | 分 T0–T7 八层；核心工具是协议录制回放（`.lwtrace`）与 headless 后端，真机只验证系统那一跳；每个里程碑有“完成定义”，未满足不进入下一个（§16） |

---

## 1. 现状诊断（全部基于本仓代码与构建产物核对）

### 1.1 分层现状

```
client-next/src (业务 87 个 .cj, ~4.5 万行)
   │  import cui.* / lgui.* / lgpu.* / lwindow.* / portcheck.*   ← 业务直接碰底层
   ▼
packages/cangjie-gui (cui, ~2.6 万行) ──► packages/cangjie-gui/lgui ("Safe SDL3 bindings", 57 个非测试文件, 42 个仍含 SDL 标识)
   │      ▲
   │      │ lwindow 反向依赖 lgui（DisplayInfo / SdlHints / ClipboardBackend）
   ▼      │
packages/lwindow (~460 行) ──────────────────┘
packages/lgpu (Rust wgpu staticlib + 仓颉绑定；Canvas 接口还在 lgui 里)

OHOS 壳（真源在仓外 /workspace/lanlu/.research-ohos/packages/ohos/templates_sdl3，1 个提交、有未提交改动）
   Index.ets 813 行 / shell_napi.cpp 911 行 / input_filter.cpp 252 行 / sdl_main.c 170 行（已不编译）
   主仓只有构建副本：client-next/build/ohos/**（其中 90 个文件被 git 跟踪）
```

### 1.2 壳 ↔ 引擎的通信渠道清单（即“隐式协议”）

| 渠道 | 方向 | 介质 | 写方 | 读方 |
|---|---|---|---|---|
| 指针事件 | 壳→引擎 | `$HOME/input_events.txt`（`action x y key` 文本行） | `input_filter.cpp` / `shell_napi.cpp::lanlu_push_input` | `lwindow/events.cj::readInputEvents` |
| 按键 | 壳→引擎 | `key_events.txt`（`down|名字|修饰`） | `shell_napi.cpp::push_key_name`（仅 IME 回调触发） | `readKeyEvents` |
| IME 提交文本 | 壳→引擎 | `text_input.txt` | `sendText` | `readTextInputs` |
| 窗口命令 | 引擎→壳 | `window_cmd.txt`（minimize/maximize/restore/close） | `lwindow/window_command.cj` | `Index.ets` 300ms 轮询 |
| 剪贴板写 | 引擎→壳 | `clip_out.txt` | `lgui/input/clipboard.cj` 或 `lwindow/clipboard.cj` | 鼠标/键盘过滤器回调里 flush |
| 剪贴板读 | 壳→引擎 | `clip_req.txt` → `clip_in.txt`（读方最多阻塞 800ms） | Ctrl+V 键过滤器 / ArkTS 每 2s 同步 | `clipboardGetText` |
| 文件对话框 | 双向 | `filedlg_req.txt` / `filedlg_result.txt` + `takeFileDialogRequest` 标志 | lgui dialogs / ArkTS picker | 同左 |
| 抓帧 | 双向 | `snapshot_req.txt` → `snapshot.rgba/.meta` | 引擎 / ArkTS componentSnapshot | 引擎侧无消费者 |
| 语言 | 壳→引擎 | `locale.txt` | （无写方，缺省 zh-CN） | `lgui/system/locale.cj` |
| Surface | 壳→引擎 | 环境变量 `LANLU_MAIN_SURFACE_ID / LANLU_MAIN_W / LANLU_MAIN_H` | `setMainSurface` | `lgpu_backend.cj` 最长等 15s |
| 后端选择 | 壳→引擎 | 环境变量 `CN_WINDOW / CN_UI_BACKEND`（Want 参数注入） | `EntryAbility.onCreate` | `desktop_app.cj` / `lgpu_backend.cj` 最长等 5s |
| 引擎退出 / 最小化 | 引擎→壳 | volatile 全局 `g_lanlu_app_exited / g_lanlu_minimize_requested` | 壳内 | ArkTS 400ms 轮询 |
| 测试注入 | 外部→引擎 | `lanlu_env.txt`、`LANLU_PROBE_*`（约 20 个） | hdc | 各处 |

NAPI 导出共 30 个（`startFilter … setEnv`，见构建产物 `cpp/types/libmain/Index.d.ts` 与 `shell_napi.cpp::ShellInit`）。

这些渠道的共同问题：
1. **无类型无版本**：文本行格式散落在 C++、ArkTS、仓颉三处各写一遍，改一处另两处不会报错。
2. **无唤醒**：`SdlWindow.waitEventTimeout` 是 4ms 短轮询（[window.cj](../packages/cangjie-gui/lgui/src/window.cj#L126-L139)），每次轮询读 3 个文件；“空闲不耗 CPU”的设计在 OHOS 上失效。
3. **无序号无背压**：文件“读完即清空”，写方与读方之间存在竞态（读到一半时写入的内容会被清掉）。
4. **环境变量不可靠**：`shell_napi.cpp::lanlu_push_input` 注释记录“仓颉的 `setVariable` 只改自己的 env，native `getenv` 看不到”，因此壳端被迫硬编码 `/data/storage/el2/base/files`。

### 1.3 键盘 / 鼠标 / 触摸 / IME 的具体缺陷

| # | 缺陷 | 证据 |
|---|---|---|
| K1 | **物理键盘事件没有送进引擎**：窗口级键过滤器只处理 Ctrl+V 读剪贴板然后 `return false`，没有转发；ArkTS 也没有 `onKeyEvent` 转发。引擎只收得到 IME 回调映射出来的少数键（Backspace/Enter/方向键/复制粘贴） | `input_filter.cpp::LanluKeyFilter`；`Index.ets` 中 `onKeyEvent|sendKey` 出现 0 次 |
| K2 | 按键用字符串名传递，`keyFromName` 只认 12 个名字，其余变 `Key.RawScancode(0)` | [lgpu_backend.cj](../client-next/src/ui/lgpu_backend.cj#L188-L209) |
| K3 | 修饰键字段被当成 repeat：`KeyDown(key, tuple[2].size > 0)` | [lgpu_backend.cj](../client-next/src/ui/lgpu_backend.cj#L161) |
| K4 | `Keyboard.modifiers()` 仍调 `SDL_GetModState`（SDL 在 OHOS 上未初始化），cui 8 处依赖它（Shift+Tab、Shift 选择、Ctrl 快捷键） | [keyboard.cj](../packages/cangjie-gui/lgui/src/input/keyboard.cj#L31-L35)；`text_field.cj`/`text_area.cj`/`modal.cj`/`desktop_app.cj` |
| K5 | 业务层直接写 SDL scancode：`/` 聚焦搜索（`SCANCODE_SLASH = 56`）、PgUp/PgDn（75/78） | [titlebar.cj](../client-next/src/ui/titlebar.cj#L115-L116)、[reader_view.cj](../client-next/src/ui/reader_view.cj#L42-L49) |
| M1 | **丢事件**：`readInputEvents` 读出全部行并清空文件，但 `headlessEventSource` 只返回 `events[0]`，其余丢弃（同一批里的按下+抬起会丢掉抬起） | [lgpu_backend.cj](../client-next/src/ui/lgpu_backend.cj#L164-L175) + [events.cj](../packages/lwindow/src/events.cj#L35-L75) |
| M2 | 所有按下/抬起都映射成 `MouseButton.Left`；鼠标 `OH_Input_GetMouseEventButton` 的值只写在 key 字段里没用上 | 同上 |
| M3 | 滚轮不可用，有两层原因：(1) 窗口鼠标过滤器根本收不到滚轮，它的 action 表只有 MOVE/DOWN/UP/CANCEL，AXIS 被丢弃；(2) 即使收到，壳端写 action 13，引擎端也解析为 `Unknown` | `oh_window_event_filter.cpp`（window_window_manager 源码）；`input_filter.cpp` 与 `events.cj` 的 action 表对照 |
| M4 | 诊断用的 action 90/91/92 也写进同一事件流，变成 `UiEvent.Unknown` | `input_filter.cpp` |
| M5 | 没有 enter/leave、悬停态、触摸多指、取消（CANCEL） | 事件模型只有 Down/Move/Up |
| I1 | IME 只有“提交文本”，无预编辑（拼音组合串不显示在输入框里）、无光标区域（候选框不跟随）；`setTextInputArea` 是空实现；cui 文本编辑状态里没有任何组合/预编辑概念 | [window.cj](../packages/cangjie-gui/lgui/src/window.cj#L114-L116)；`text_edit_state.cj` 中 compos/preedit/marked 出现 0 次 |
| C1 | 光标样式全部空实现（`cursorsEnabled = false`） | [cursor.cj](../packages/cangjie-gui/lgui/src/input/cursor.cj) |
| W1 | **窗口尺寸固定**：surface 尺寸只在启动时从环境变量读一次，全仓没有 `Surface.resize` 的调用方；`UiEvent.WindowResized` 只由已不运行的 SDL 解码路径产生 | `grep` 结果；[lgpu_backend.cj](../client-next/src/ui/lgpu_backend.cj#L74-L85) |
| W2 | 标题栏拖动区 `setDragRegions` 是空实现，自绘标题栏无法拖动窗口 | [window_controls.cj](../packages/cangjie-gui/lgui/src/window_controls.cj#L85-L93) |
| P1 | 剪贴板读取方式不合规：ArkTS 申请受限 ACL 权限 `READ_PASTEBOARD`，并每 2 秒轮询读取系统剪贴板。系统规则禁止后台/轮询读取，普通应用只能在 Ctrl+V 后 2 秒内读一次或通过 PasteButton 读 | `Index.ets::ensurePasteboardPermission/readPasteboardToFile`；`pasteboard_service.cpp::VerifyPermission` |

### 1.4 业务层/框架层的平台泄漏

| 位置 | 泄漏内容 |
|---|---|
| `client-next/src/main.cj` | `SdlHints`/`SdlHint.AppId`、`app.sdlWindow`、`cui.desktop.frameProbeHook`、`lgpu.capture*`、`lgui.input.Clipboard`、`prepareRendererHints`、`prepareDesktopIntegration`、约 10 个 `LANLU_PROBE_*` 联调分支 |
| `client-next/src/ui/lgpu_backend.cj` | 整个文件是平台后端代码（读 surface 环境变量、建 lgpu Surface、装事件源、键名映射、剪贴板后端）却放在业务包 |
| `titlebar.cj / reader_bar.cj / upload_drawer.cj` | 以 `SdlWindow` 为参数做最小化/最大化/拖动区 |
| cui `desktop_app.cj` | 读 `CN_WINDOW` 环境变量选窗口实现；`SdlHints`/`AppMetadata`；`Cursor`/`Keyboard` 来自 lgui |
| `lwindow` | 反向依赖 `lgui`；`prepareDesktopIntegration` 里写死已不存在的路径 `packages/cangjie-gui/sdl/libdecor-plugins` |
| 守卫脚本 | `check-layering.sh` / `check-no-sdl.sh` 只做字符串匹配，上述耦合都能通过 |

### 1.5 构建与链接层的问题

| 问题 | 证据 |
|---|---|
| OHOS 引擎仍链接 SDL：`liblanlu_client_next.so` 的 NEEDED 含 `libSDL3.so`、`libSDL3_ttf.so`，HAP 仍打包这两个库 | `llvm-readelf -d`；`cjpm.toml.ohos` 的 `-lSDL3 -lSDL3_ttf` |
| **lgpu 静态库被链接了两份**：`libmain.so` 定义 39 个 `lgpu_*` 符号，`liblanlu_client_next.ui.so` 定义 55 个。Rust 侧的全局状态（`INSTANCE`、`SURF_LOCK`、`GPU_ERROR`、`CAPTURE_DATA`）在进程里存在两份 | `llvm-nm -D --defined-only` |
| 引擎由 `libmain.so` 的构造函数在 dlopen 时自启动（早于 ArkTS 设置 Want 参数与 surface），所以引擎侧到处“最多等 N 秒”拿环境变量 | `shell_napi.cpp::lanlu_autostart_engine` |
| CI 与 README 仍引用已不存在的 `packages/cangjie-gui/sdl`（workflow 11 处、README 7 处） | `.github/workflows/client-next.yml` |
| 桌面后端缺失：`lgui` 中 `SDL_CreateWindow/SDL_PollEvent/SDL_Init` 出现 0 次；`lgpu` 只构造 `RawWindowHandle::OhosNdk` | `lgui/src`、`lgpu/native/src/lib.rs` |

> 关于历史上“引擎调 libmain 的 FFI 必崩”（commit `d722178c`、`03461092` 记录的两次 SIGSEGV/SIGABRT，之后才改走文件）：当时的结论是“C++ 静态对象 / 加载时序冲突”，**根因未定位**。本次核对发现的“lgpu 双份静态链接 + 引擎在 libmain 构造函数里自启动”是两个可疑因素，需在 M0 中用最小用例复现确认（§10 M0-3）。新协议的传输层设计正是为了绕开这两点：通道代码放进**独立的共享库**（壳与引擎都依赖它，进程内只有一份），引擎由显式握手启动而不是构造函数。
>
> 补充：外部线程调用仓颉 `@C` 函数在运行时实现上是支持的。反汇编本地探针库可见 `@C` 入口先 `bl CJ_MCC_N2CStub`，该桩调用 `MRT_NewForeignCJThread` 给当前 OS 线程建 foreign cjthread（见 cangjie_runtime 源码 `N2CStub.S`、`CjScheduler.cpp`）。但官方文档没有说明，`CLIENTNEXT-PORT-STATUS.md` Round26 记录过一次外部线程回调死锁，musl 默认线程栈只有 128 KiB，而且每个短命的外部线程首次进入都会新建子调度器。所以协议**仍然不依赖**外部线程调仓颉（原则 6）。

---

## 2. 设计原则

1. **协议是唯一边界**。壳与引擎之间只允许 LWP 一条通道：没有文件桥、没有用于通信的环境变量、没有全局标志、没有“临时”专用 NAPI 函数。联调/测试也走协议（专门的 `test` 接口，release 构建可关闭）。
2. **协议定义只有一份**（IDL），C 头、仓颉绑定、壳端分发桩、参考文档全部由生成器产出，三方不再各写一遍格式。（Chromium mojom、Wayland XML + wayland-scanner 的做法）
3. **版本化、只增不改**。每个接口有版本号；新增字段只能追加，接收方按 `size` 读取自己认识的部分；枚举必须可扩展（未知值落到 `Unknown`）；废弃消息保留到大版本。（mojo `[MinVersion]`/`[Extensible]`、Wayland interface version、Flutter `struct_size`）
4. **请求 / 事件 / 状态提交分清楚**。引擎→壳是请求（request），壳→引擎是事件（event）；需要成组生效的状态（窗口尺寸 + 缩放 + 状态位、IME 文本 + 光标）用 `configure → ack` 或 `… → done(serial)` 双缓冲提交，避免中间态。（Wayland xdg_surface.configure/ack_configure、text-input-v3 done）
5. **能下沉到 C 就不进 ArkTS**。OHOS NDK 有 C API 的能力（输入、IME、vsync、显示、剪贴板、光标、应用路径）全部在 C/C++ 壳里完成；ArkTS 只保留系统强制或没有 C API 的部分（Ability 生命周期、XComponent 声明、窗口最小化/最大化/拖动、系统 picker、拉起链接、权限弹窗）。
6. **引擎拉取，不被回调**。外部线程（输入过滤器、IME 回调、vsync 线程、Wayland 事件循环）只往队列里写并唤醒；仓颉代码只在引擎自己的线程上读队列。
7. **坐标与单位只在一处换算**。壳端负责“系统坐标 → 窗口局部物理像素”；lwindow 负责“物理像素 → 逻辑像素（除以 scale）”；cui 及以上只见逻辑像素。
8. **每个平台后端都要能无头跑**。headless 后端 + 事件录制/回放是协议的一等公民，CI 对 headless 与 Wayland 跑同一份协议一致性测试。（Ozone headless、GPUI TestPlatform）
9. **分层由脚本强制**。每个包声明允许依赖的包，CI 违规即失败。（Chromium DEPS/checkdeps）
10. **平台代码只在平台包里**。OS API（`OH_*`、NAPI、ArkTS、`wl_*`/`xdg_*`/`zwp_*`、xkbcommon、D-Bus/portal）、平台路径、平台构建与打包配置只能出现在 `packages/lplatform-<os>` 与 `packages/lpack-<os>`；中立包里出现即 CI 失败。新增平台 = 新增这两个包，不改中立包。`third_party/` 下的上游代码（含准备回馈上游的补丁）不受此限。
11. **不保留过渡后端**。不做 SDL 过渡壳；一个平台要么有原生壳，要么不支持。桌面只支持 Wayland。
12. **引擎永远是被宿主加载的动态库，两个平台对称**。宿主（鸿蒙：ArkTS + `libmain.so`；Wayland：`lanlu` 可执行文件）先建协议通道、发出初始状态，再执行 `InitCJRuntime → LoadCJLibraryWithInit → cj_app_main`。这一启动序列已在本机 linux-x86_64 验证过（[client-next-ohos-plan.md](client-next-ohos-plan.md) 附录 E.2），Linux 版仓颉运行时同样导出这三个符号。

---

## 3. 业界参考与可借鉴点

| 项目 | 机制 | 我们借什么 |
|---|---|---|
| Chromium `ui/ozone` | `OzonePlatform` 工厂（`CreatePlatformWindow`、`GetCursorFactory`、`GetInputController`、`CreateInputMethod`、`GetPlatformClipboard`、`CreateScreen`、`GetSurfaceFactoryOzone`）+ `PlatformProperties` / `PlatformRuntimeProperties` 能力位；平台由编译期 `ozone_platforms` 列表 + 运行期 `--ozone-platform` 选择；自带 `headless` 平台 | lwindow 的 `Platform` 抽象与能力位（`supports_server_side_window_decorations`、`custom_frame_pref_default` 之类）；headless 后端 |
| Chromium `PlatformWindowDelegate` | 平台窗口 → 上层的回调：`OnBoundsChanged`、`OnDamageRect`、`DispatchEvent`、`OnCloseRequest`、`OnClosed`、`OnWindowStateChanged`、`OnLostCapture`、`OnAcceleratedWidgetAvailable`、`OnWillDestroyAcceleratedWidget`、`OnAcceleratedWidgetDestroyed`、`OnActivationChanged`、`OnCursorUpdate`、`OnOcclusionStateChanged`、`OnStateUpdate`（带 sequence 的状态同步） | `lw_window` 事件清单基本照此设计；surface“可用 / 即将销毁 / 已销毁”三段生命周期 |
| Chromium `dom_code_data.inc` | 一张表同时给出 USB HID、evdev、XKB、Windows、Mac 码与 W3C `code` 字符串，`DomCode` 枚举与各平台映射都由这张表宏展开生成 | 键码单表：增加 OHOS `KEYCODE_*` 一列，生成仓颉 `KeyCode` 枚举与每个后端的映射表 |
| Chromium mojo | IDL（mojom）→ 生成绑定；接口/结构可加 `[MinVersion]`，枚举 `[Extensible]`，`[Stable]` 接口禁止破坏性修改；消息管道 + 关联接口保证顺序 | IDL + 版本规则 + “同一管道内保序” |
| Chromium GPU 命令缓冲 | 共享内存环形缓冲 + get/put 偏移 + transfer buffer 传大数据 + sync token | 传输层：环形队列放定长头 + 小载荷，大载荷（长文本、文件列表、像素）放 blob 区按句柄引用 |
| Wayland | XML 协议 + scanner 生成；对象/接口/版本；registry 宣告全局能力；`wl_pointer.frame` 把一组指针事件打包；`xdg_toplevel` 的 `move/resize/set_min_size/set_maximized/set_minimized` 请求与 `configure/close/wm_capabilities` 事件；`xdg_surface.configure/ack_configure` | 握手宣告接口与版本；指针 frame 分组；窗口操作模型（自绘标题栏用 `move(serial)` 请求交给系统拖动） |
| Wayland text-input-v3 | 请求：`enable/disable/set_surrounding_text/set_text_change_cause/set_content_type/set_cursor_rectangle/commit`；事件：`enter/leave/preedit_string/commit_string/delete_surrounding_text/done(serial)` | IME 协议几乎照搬（§6.4） |
| xdg-desktop-portal FileChooser | `OpenFile/SaveFile/SaveFiles`，异步请求句柄 + 结果信号 | 文件对话框：请求 id + 异步结果事件，壳端负责 uri ↔ 沙箱路径 |
| Flutter Embedder API (`embedder.h`) | 纯 C ABI；52 个结构体首字段是 `size_t struct_size`；`FlutterEngineSendPointerEvent`（phase/device/buttons/signal_kind/scroll_delta/device_kind/pressure…）、`SendKeyEvent`、`SendWindowMetricsEvent`、`OnVsync`、`ScheduleFrame`、`SendPlatformMessage`（具名通道 + 二进制编解码） | `struct_size` 式向前兼容；指针事件字段集；“具名通道”作为扩展口（业务自定义消息不必改核心协议） |
| winit | `KeyEvent { physical_key, logical_key, text, location, state, repeat, … }`；`Ime::{Enabled, Preedit(String, Option<(usize,usize)>), Commit, Disabled}`；`set_ime_cursor_area`；`EventLoopProxy` 唤醒；OHOS 后端（`openharmony-ability`，事件含 SurfaceCreate/Destroy、WindowResize、ContentRectChange、AvoidAreaChange、ConfigChanged、TextInputReadyChanged、Input 等） | 引擎侧键盘事件结构与 IME 事件；OHOS 生命周期事件清单 |
| Qt QPA | `QPlatformIntegration::Capability` 能力枚举；`QWindowSystemInterface::handle*` 是平台层向上注入事件的**唯一漏斗**，支持同步/异步投递 | lwindow 内部只有一个事件入口（协议解码器），任何后端都不能绕过它直接调 cui |
| Zed GPUI | `Platform` / `PlatformWindow`（含 `start_window_move`、`start_window_resize`、`update_ime_position`、`on_hit_test_window_control`、`show_soft_keyboard`…）/ `PlatformDispatcher` / `PlatformTextSystem` / `InputHandler`（`marked_text_range`、`replace_and_mark_text_in_range`、`bounds_for_range`…）；`TestPlatform` 可模拟显示器增删、路径选择、弹窗应答 | 文本输入处理器接口形状；测试平台可模拟系统交互 |
| Slint | `Platform` trait（`create_window_adapter`、`run_event_loop`、`new_event_loop_proxy`、剪贴板、`open_url`）+ `WindowAdapter`（`set_mouse_cursor`、`input_method_request`、`safe_area_inset`、`start_window_move`…） | 小团队可维护的最小平台面 |
| SDL3 | `VideoBootStrap` 驱动表（按名字选择后端）；`SDL_EVENT_TEXT_EDITING(_CANDIDATES)`、`WINDOW_DISPLAY_SCALE_CHANGED`、`WINDOW_SAFE_AREA_CHANGED`；OHOS 移植用 `OH_NativeXComponent_RegisterCallback/RegisterMouseEventCallback/RegisterKeyEventCallback/RegisterOnFrameCallback` + `napi_threadsafe_function` 回调 ArkTS | 桌面过渡后端可直接基于 SDL；OHOS 侧 C 回调注册方式可参考 |
| Android GameTextInput | 状态式 IME：`{ text_UTF8, text_length, selection, composingRegion }` 整体同步 | IME 状态整体同步作为增量事件的兜底（重连/错位时一次性对齐） |
| horizon-ohos（本机先例） | 键盘走窗口级过滤器、按 US 布局合成 `text`、从按键集合推导修饰键并自判 repeat；键过滤器与 IME 互斥；候选框跟随；`napi_call_function(env, recv, func, …)` 参数顺序踩坑；外来管线 XComponent 收不到 vsync 需自驱帧 | 直接采纳（§6、§7） |

OHOS 能力边界另有一份逐项调研（本地 SDK 头文件 + window_window_manager / inputmethod_imf / distributeddatamgr_pasteboard / cangjie_runtime 开源实现 + 官方文档），结论已并入 §5.4、§6、§7、§8 与附录 A。

参考链接：
[platform_window_delegate.h](https://raw.githubusercontent.com/chromium/chromium/main/ui/platform_window/platform_window_delegate.h)、
[ozone_platform.h](https://raw.githubusercontent.com/chromium/chromium/main/ui/ozone/public/ozone_platform.h)、
[dom_code_data.inc](https://raw.githubusercontent.com/chromium/chromium/main/ui/events/keycodes/dom/dom_code_data.inc)、
[Flutter embedder.h](https://raw.githubusercontent.com/flutter/flutter/master/engine/src/flutter/shell/platform/embedder/embedder.h)、
[winit Ime](https://docs.rs/winit/latest/winit/event/enum.Ime.html)、
[wayland-protocols（xdg-shell / text-input-v3 / fractional-scale / presentation-time）](https://gitlab.freedesktop.org/wayland/wayland-protocols)、
本机 horizon-ohos：`/workspace/horizon-ohos/port/docs/PORTING.md`。

---

## 4. 目标架构

### 4.1 分层与包

```
┌────────────────────────────────────────────────────────────────────────────┐
│ client-next/     业务（只 import cui.*，及 lwindow.app 的应用级 API）      │
│        产物：引擎动态库 liblanlu_engine.so（两个平台同一份源码、同一个 cjpm 工程）  │
├────────────────────────────────────────────────────────────────────────────┤
│ packages/cangjie-gui (cui)   控件/布局/事件分发/文本编辑（含 IME 预编辑）      │
│        依赖：lbase、lwindow.api        │
├────────────────────────────────────────────────────────────────────────────┤
│ packages/lwindow       平台抽象（对标 ozone/public + QPA），零平台代码   │
│   api/   Platform, Window, Seat(Pointer/Keyboard/Touch), TextInput, Clipboard,  │
│   Dialogs, Cursor, Display, SystemInfo, Frame        │
│   core/  唯一事件漏斗、坐标/缩放换算、修饰键/repeat 状态机、键码表（生成）、能力位   │
│   backend/lwp       经 LWP 通道连接任意壳       │
│   backend/headless  内存通道：测试 / 快照 / CI         │
├────────────────────────────────────────────────────────────────────────────┤
│ packages/lwp           协议本体，零平台代码           │
│   protocol/*.toml IDL；gen/ 生成物；native/ liblwp.so（环形队列 + blob + eventfd）  │
├────────────────────────────────────────────────────────────────────────────┤
│ packages/lgpu   渲染（Rust wgpu），零平台代码：只接收“原始窗口句柄”  │
│        句柄由壳在 surface.available 里给出（kind + 指针），lgpu 不调用任何 OS API    │
├────────────────────────────────────────────────────────────────────────────┤
│ packages/lbase         几何/颜色/Canvas 接口/输入类型（从 lgui 拆出的中立部分）    │
╞════════════════════════════════════════════════════════════════════════════╡
│ 平台包（仅此 4 个包允许出现平台代码）   │
│   packages/lplatform-ohos     鸿蒙壳（C/C++ NDK + ArkTS 模板）+ 鸿蒙原生依赖 shim   │
│   packages/lpack-ohos         鸿蒙工程生成器 + 打包签名（由 hapgen 演进）    │
│   packages/lplatform-wayland  Wayland 壳（Rust 宿主程序）            │
│   packages/lpack-linux        Linux 打包（.deb / .desktop / 图标 / 依赖清单）       │
└────────────────────────────────────────────────────────────────────────────┘
```

- `lbase`：从 `lgui` 中拆出**与平台无关**的部分（`geometry.cj`、`Color/Pen/Rect/Size`、`canvas.cj`、`icon_draw.cj`、`surface_style.cj`、`render_geometry.cj` 中纯计算部分、`text/metrics`、`shaped_text_cache`）。`lgui` 剩下的 SDL 代码全部删除，`lgui` 包随之消失。
- `lwindow` 不再依赖 `lgui`；只依赖 `lbase` 与 `lwp`。
- `lgpu` 不再依赖 `lgui`（Canvas 接口改从 `lbase` 取）。
- `portcheck`（移植自检）改为通过协议的 `test` 接口驱动；其中鸿蒙专用自检用例移入 `lplatform-ohos/selftest/`。

### 4.2 平台代码隔离：现状 → 归属

现在平台代码散落在下表各处（含仓外）。目标是每一处都搬进上面 4 个平台包之一，中立包里不留任何平台代码，包括中立包 `cjpm.toml` 里的鸿蒙交叉编译段。

| 现在的位置 | 内容 | 迁往 |
|---|---|---|
| `.research-ohos/packages/ohos/templates_sdl3`（仓外） | ArkTS 页面、`shell_napi.cpp`、`input_filter.cpp`、`sdl_main.c` | `lplatform-ohos/shell/`（ArkTS 与 C++ 重写，`sdl_main.c` 删除） |
| `.research-ohos/packages/ohos`（hapgen，独立远端 `git.copur.xyz/cangjie-ohos/ohos`） | 鸿蒙工程模板、生成、hvigor 打包、签名 | `lpack-ohos`（以 git subtree 或同步脚本引入主仓；独立仓可继续作为上游） |
| `packages/lwindow/src/ohos_entry.cj`、`ohos_fontsconf.cj`、`ohos_seed.cj` | 沙箱路径、openssl 路径、fonts.conf、首启种子、`lanlu_env.txt` | 路径/字体 → 壳端 C 代码经 `system.paths`/`system.fonts` 下发；fonts.conf 生成 → `lplatform-ohos/shell`；首启种子 → `lpack-ohos`（构建期投放）；`lanlu_env.txt` → 删除（改由 `test` 接口） |
| `packages/lwindow/src/window_policy.cj` | `XDG_SESSION_TYPE`、`LIBDECOR_PLUGIN_DIR`、`SDL_RENDER_DRIVER`、`/system/fonts` | 删除；几何/缩放由壳的 `display.info`/`window.configure` 给出 |
| `packages/lgpu/native/src/lib.rs` 的 `OH_NativeWindow_*` | surfaceId → OHNativeWindow、设置缓冲几何 | 壳端完成；lgpu 只接收 `(kind, handle)` |
| `packages/lgpu/native/third_party/wgpu-hal`（打了 `VK_OHOS_surface` 补丁） | 上游 wgpu-hal 补丁 | 保留在 `lgpu/native/third_party`（上游代码，`#[cfg(target_env = "ohos")]`），README 记录补丁来源与回馈上游计划 |
| `packages/{vips,rocksdb,libvlc,fontkit}_ffi/native-ohos/`、`packages/lgpu/native-ohos/` | 鸿蒙交叉编译脚本与 shim（vips shim、rocksdb 桥、vlc shim 含 `OH_AudioRenderer`） | `lplatform-ohos/deps/<包名>/`；FFI 包只保留与平台无关的 C 头与仓颉绑定 |
| `packages/portcheck/src/ohos_selftest*.cj` | 真机自检 | `lplatform-ohos/selftest/`，通过 `test` 接口触发 |
| `client-next/ohos/`（`build-ohos.sh`、`cjpm.toml.ohos`、`gen_seed_cj.py`、`gen_video_cj.py`、`assets/`、`platform/`） | 鸿蒙构建配置 | `lpack-ohos/app-profiles/lanlu/`；`client-next/ohos/platform`（早期 platform 接口草稿）删除 |
| `client-next/cjpm.toml` 的 `[package.metadata.ohos]` 与 `[target.x86_64-w64-mingw32]` | 鸿蒙元数据、Windows 链接选项 | 鸿蒙元数据 → `lpack-ohos/app-profiles/lanlu/app.toml`；mingw 段删除（桌面只支持 Wayland） |
| `client-next/build/ohos/**`（90 个文件被 git 跟踪） | 构建副本 | 退出版本库（`.gitignore` + `git rm --cached`） |
| `packages/{cangjie-gui,portcheck,qwest,vips_ffi,webview}/cjpm.toml` 与 `lgui/cjpm.toml` 里的 `[target.aarch64-linux-ohos]` 段 | 写死的 `/workspace/horizon-ohos/.tooling/...` sysroot 与链接路径 | 从中立包删除；由 `lpack-ohos` 构建时通过 `cjpm --target aarch64-linux-ohos` 加 `--compile-option`/`--link-options` 统一注入（需在 M0 验证 cjpm 对依赖包的传递方式；不行就由 `lpack-ohos` 生成临时 cjpm 配置覆盖层） |
| `tools/{build-ffmpeg-ohos,build-hapgen,check-hap-deps,check-hap-symbols,sign-hap,verify-ohos,verify-window,make-sdl3-noversion,sync-wgpu-hal}.sh` | 鸿蒙/SDL 工具脚本 | 鸿蒙相关 → `lpack-ohos/tools/`；`make-sdl3-noversion.sh` 删除；`sync-wgpu-hal.sh` → `lgpu/native/` |
| `packages/cangjie-gui/lgui/.sdl3`、`.sdl3-nolibdecor`、`libdecor-plugins` | SDL 与 libdecor 预编译库 | 删除 |

### 4.3 鸿蒙：工程由独立包生成，主仓不放鸿蒙工程

```
输入（全部在主仓，全部是“源”）
  client-next/   中立引擎源码，唯一的 cjpm.toml
  packages/lplatform-ohos/
    shell/native/       C/C++ 壳源码 → libmain.so
    shell/arkts/        ArkTS 薄壳模板片段
    deps/        鸿蒙原生依赖 shim 与交叉编译脚本
  packages/lpack-ohos/
    templates/          鸿蒙工程骨架（AppScope、entry、hvigor 配置）
    app-profiles/lanlu/app.toml   包名、版本、权限、设备类型、图标、首启种子

lpack-ohos build --app lanlu --sign
  1. cjpm build --target aarch64-linux-ohos（client-next）   → liblanlu_engine*.so
  2. 构建 lplatform-ohos 壳与 deps           → libmain.so、liblwp.so、依赖 .so
  3. 模板 + app.toml + shell/arkts → 生成工程 → build/ohos/lanlu/（不入库）
  4. hvigor 打包 → 签名 → 静态门禁（依赖闭包、关键符号、无 SDL）→ .hap
```

- **一条命令**：`lpack-ohos build --app lanlu [--sign] [--install]`。它依次：交叉编译引擎（`client-next`）→ 构建 `lplatform-ohos` 壳与依赖 → 用模板与 `app.toml` 生成鸿蒙工程到 `build/ohos/`（不入库）→ hvigor 打包 → 签名 → 运行静态门禁（依赖闭包、关键符号、无 SDL）。
- 主仓里**没有**任何鸿蒙工程文件（`module.json5`、`build-profile.json5`、`oh-package.json5`、hvigor 配置）。它们只以模板形式存在于 `lpack-ohos/templates`，以生成物形式存在于不入库的 `build/ohos/`。
- `client-next` 不再有 `cjpm.toml.ohos`：同一个 `cjpm.toml`，交叉编译所需的 sysroot、链接路径由 `lpack-ohos` 通过 cjpm 的 `--target` 与环境变量注入；`output-type` 统一为 `dynamic`。
- 现在 `build-ohos.sh` 里写死的路径（`/workspace/horizon-ohos/.tooling/...`、`/workspace/lanlu/.research-ohos/...`）全部变成 `lpack-ohos` 的配置项（`~/.config/lpack-ohos/toolchains.toml` 或环境变量），并给出缺失时的明确报错。
- `lpack-ohos` 与独立仓 `git.copur.xyz/cangjie-ohos/ohos` 的关系：主仓以 git subtree 引入并作为日常开发位置，定期回推；如果维护者希望主仓只引用外部版本，也可改为 cjpm `git` 依赖，但模板中与 LWP 协议相关的部分（ArkTS 薄壳）必须随 `lplatform-ohos` 走，不放进通用生成器。

### 4.4 Linux（Wayland）：宿主程序加载引擎

```
lplatform-wayland/  (Rust, 产物：lanlu 可执行文件)
  main ─► lwp_open ─► 连接 Wayland、建窗、发 hello + 初始状态
       ─► dlopen libcangjie-runtime.so ─► InitCJRuntime ─► LoadCJLibraryWithInit("liblanlu_engine.so")
       ─► 引擎线程调用 cj_app_main()
       ─► 主线程：Wayland 事件循环 + LWP 请求处理

lpack-linux/
  打出 .deb：/usr/bin/lanlu（宿主）、/usr/lib/lanlu/{liblanlu_engine*.so, liblwp.so, 仓颉运行时, 依赖}、
  /usr/share/applications/lanlu.desktop（app_id = lanlu，Wayland 任务栏图标据此匹配）、图标
```

- 现在 `client-next` 的 `main()` 桌面入口删除，引擎在两个平台都只导出 `cj_app_main`。
- 现在 CI 里内联在 workflow 的 .deb 打包步骤（`dpkg-deb`、`lanlu.desktop` 生成）迁入 `lpack-linux`，CI 只调用它。

### 4.5 依赖白名单与平台标识守卫（M0 落地，CI 强制）

| 包 | 允许依赖 | 禁止 |
|---|---|---|
| `client-next` | `cui`、`lwindow.app`、业务需要的 FFI 包（vips/vlc/rocksdb/webview/qwest…） | `lgui`、`lgpu`、`lwp`、`lwindow` 其他子包、任何平台包 |
| `cui` | `lbase`、`lwindow.api` | `lgpu`、`lwp`、`lwindow.backend.*`、`std.env.getVariable`（配置走 Platform） |
| `lwindow` | `lbase`、`lwp`、`lgpu`（仅 `backend.lwp` 子包，用于把句柄交给渲染器） | 任何平台包 |
| `lgpu`、`lwp`、`lbase` | 各自的中立依赖 | 任何平台包、任何 OS API |
| `lplatform-<os>` | 本平台 SDK、`lwp`（C 头与 `liblwp.so`） | 引擎内部任何包 |
| `lpack-<os>` | 构建工具 | 被任何运行时包依赖 |

两个检查脚本，替换现在只做字符串匹配的 `check-layering.sh` / `check-no-sdl.sh`：
- `tools/check-deps.py`：读取每个包的 `cjpm.toml` / `Cargo.toml` 依赖与源码 `import`，对照 `tools/deps-rules.toml`。
- `tools/check-platform-isolation.py`：在平台包与 `third_party/` 之外扫描平台标识，出现即失败。规则表：
  - 鸿蒙：`OH_[A-Z]`、`napi_`、`@ohos.`、`@kit.`、`ArkTS`、`XComponent`、`/data/storage`、`/system/lib64`、`/system/fonts`、`.ets` 文件、`module.json5`、`hvigor`、`aarch64-linux-ohos`；
  - Wayland/Linux 桌面：`wl_[a-z]`、`xdg_[a-z]`、`zwp_`、`wp_[a-z]`、`xkb_`、`XDG_SESSION_TYPE`、`WAYLAND_DISPLAY`、`org.freedesktop`、`libdecor`；
  - SDL：`SDL_`、`TTF_`、`Sdl[A-Z]`（全仓禁止，SDL 删除后对平台包也生效）。

#### 4.5.0 P6 吸收后的 cui 内部结构（2026-11-19 定）

`lgui` 并入 `cui` 时，SDL 基元（`Key`/`UiEvent`/`Renderer`/`SdlWindow`/`Texture`/
`SurfaceStyle` 等）落在**新子包 `cui.base`**，不能放在根包 `cui`：根包 `public import`
所有子包，子包若再 import 根包（如 `import cui.{Key}`）会形成「cui → 子包 → cui」的
**包级循环依赖**，cjpm 直接拒绝构建（P6 落地时实测 13 条循环）。

- 子包间共享的基元只经 `cui.base`；子包**不得** import 根包 `cui`（吸收时已把
  `src/{core,controls,media,system,dialogs,text,desktop,input,textkit}` 的根包 import
  全部改写为 `cui.base.*`）。
- 根包只做再导出（`public import cui.base.*` + 各子包），业务层继续 `import cui.*`。
- 新增子包时同样遵守：需要基元就依赖 `cui.base`，别图省事 import 根包。

---

### 4.5.1 守卫的两类豁免（2026-11-10 定）

守卫判的是「**代码**里出现了平台专有标识」。两类东西不算，且都有明确理由：

1. **注释与文档字段**（`//`、`/* */`、`#`、TOML 的 `doc`）：协议 IDL 里写“对应 `wl_surface`”
   是设计依据，不该因为提到 wayland 就被判违规。剥注释后基线从 100 降到 81。
2. **中立包 `cjpm.toml` 的 `[target.<triple>]` 段**：那是交叉编译的 sysroot/链接配置，
   没有任何 import/API 因它进入业务层。剥离后基线 81 → 73。

两条豁免都验证过「真违规仍会被抓」：临时在 `packages/qwest/src/` 放一个含 `import ohos_foo`
的文件，守卫立刻报「新增 1 处」。

## 5. LWP 协议设计

### 5.1 IDL 与生成器

- 位置：`packages/lwp/protocol/*.toml`，一个文件一个接口族（`core`、`window`、`seat`、`text_input`、`clipboard`、`dialog`、`system`、`frame`、`test`）。选 TOML 是因为仓库里已经大量使用、Python 3.13 自带 `tomllib`，生成器无需第三方依赖。
- 描述单元：

```toml
[interface.lw_window]
version = 1
doc = "顶层窗口（对标 xdg_toplevel + PlatformWindowDelegate）"

[[interface.lw_window.request]]        # 引擎 → 壳
name = "set_title"
since = 1
args = [{ name = "title", type = "string" }]

[[interface.lw_window.request]]
name = "move"            # 自绘标题栏拖动：交给系统窗口管理器
since = 1
args = [{ name = "pointer_serial", type = "u32" }]

[[interface.lw_window.event]]   # 壳 → 引擎
name = "configure"
since = 1
args = [
  { name = "serial", type = "u32" },
  { name = "width_px", type = "i32" }, { name = "height_px", type = "i32" },
  { name = "scale", type = "f32" },
  { name = "states", type = "bitfield:lw_window_state" },
]

[enum.lw_window_state]
bitfield = true
extensible = true
entries = [ ["maximized", 1], ["minimized", 2], ["fullscreen", 4], ["activated", 8], ["resizing", 16] ]
```

- 生成器 `tools/lwp-gen.py` 产出（全部放 `packages/lwp/gen/`，入库，CI 校验“重新生成后无 diff”）：
  1. `lwp_protocol.h`：C 结构体（每个消息体首字段 `uint32_t size`）、opcode 常量、枚举、`LWP_IFACE_*_VERSION`；
  2. `lwp_protocol.cj`：仓颉 `@C struct`、编码/解码函数、`enum`（含 `Unknown(UInt32)` 兜底）；
  3. `lwp_dispatch.inc`：壳端 `switch(iface, opcode)` 分发桩，未实现的消息编译期就能看出来；
  4. `docs/lwp/*.md`：协议参考文档；
  5. `lwp_abi.json`：ABI 指纹（接口、版本、每个消息的字段布局），CI 比对“只允许追加”。

### 5.2 传输层：`liblwp.so`

```
   壳端（任意线程：输入过滤器、IME 回调、vsync、ArkTS 线程）
      │ lwp_send(EVENT, …)        ▲ lwp_recv(REQUEST)
      ▼      │
   ┌──────────────── liblwp.so（进程内唯一一份）──────────────────┐
   │ ring[EVENT]   : MPSC，多生产者（壳的多个线程）→ 引擎单消费者     │
   │ ring[REQUEST] : SPSC，引擎单生产者 → 壳端调度线程单消费者        │
   │ blob arena    : 大载荷（>256B 文本、文件列表、像素）按句柄引用    │
   │ eventfd ×2    : 有数据即写 1；接收方 poll() 阻塞等待，真空闲      │
   │ handshake     : 版本/能力/接口表；首个消息必须是 core.hello│
   └──────────────────────────────────────────────────────────────┘
      │ lwp_recv(EVENT)     ▲ lwp_send(REQUEST, …)
      ▼      │
    引擎线程（仓颉 lwindow.backend.lwp）
```

C API 草案（生成头之外的手写部分，极小）：

```c
typedef struct lwp_channel lwp_channel;
typedef struct { /* 24 字节定长头 */
    uint16_t iface;  uint16_t opcode;
    uint32_t size;      /* 头 + 消息体总长，接收方据此跳过未知消息 */
    uint32_t serial;           /* 发送方单调递增 */
    uint32_t flags;     /* bit0: 体内含 blob 句柄 */
    uint64_t time_ns;   /* CLOCK_MONOTONIC */
} lwp_header;

int  lwp_open(const char* name, uint32_t ring_bytes, lwp_channel** out);   /* 同名复用，进程内单例 */
int  lwp_send(lwp_channel*, int dir, const lwp_header*, const void* body);  /* 满则返回 -EAGAIN，不阻塞 */
int  lwp_recv(lwp_channel*, int dir, lwp_header* hdr, void* body, uint32_t cap);
int  lwp_wait(lwp_channel*, int dir, int timeout_ms);  /* poll(eventfd) */
int  lwp_wake(lwp_channel*, int dir);    /* 跨线程唤醒（requestWake） */
uint32_t lwp_blob_put(lwp_channel*, const void* data, uint32_t len);
int  lwp_blob_get(lwp_channel*, uint32_t handle, void* out, uint32_t cap);
void lwp_blob_release(lwp_channel*, uint32_t handle);
```

要点：
- **纯 C、固定数组、原子索引**，不用 `std::deque/std::mutex`，不在构造函数里做事（吸取 l-layer.md 记录的教训）。
- MPSC 用“原子 fetch_add 预留 + 每槽提交标志”；容量默认 256 KiB，满时丢弃**可合并**事件（连续 pointer.motion 只保留最后一条）并计数上报，不可合并事件（按键、按钮、IME）绝不丢。
- 引擎侧 `waitEventTimeout(ms)` = `lwp_wait(EVENT, ms)`：没有事件就真阻塞，`requestWake()` = `lwp_wake`，取代 4ms 轮询读文件。
- **liblwp.so 是独立共享库**：`libmain.so`（壳）与引擎 `.so` 都以 NEEDED 依赖它，进程里只有一份全局状态；不再把任何带状态的静态库同时链进壳和引擎（顺带修掉 lgpu 双份链接）。
- 两个平台的宿主都与引擎同进程（鸿蒙由系统决定；Wayland 宿主 dlopen 引擎）。将来若要把壳放进独立进程，同一 API 可换成 `memfd` 共享内存 + 两个 eventfd，消息格式不变。

#### 5.2.1 进程模型：现在同进程，将来可拆（2026-11-11 补）

**现状**：壳与引擎同进程是当前实现的隐含前提，有两处直接依赖它：
1. `lwp_open()` 用进程内单例表返回同一个通道实例；
2. `lw_surface.attach.buffer` 直接当**进程内 fd** 用（壳 `dup` 后交给 `wl_shm`）。

**新选项**：HarmonyOS 26.0.1 起提供子进程能力
（`childProcessManager.startNativeChildProcess` / `startArkChildProcess` /
`getChildProcessInfos`，以及 `processMode = NEW_PROCESS_ATTACH_TO_PARENT`，
并配套 C API）。这意味着「引擎放进子进程、壳留在主进程」在鸿蒙上**变得可行**，
好处是引擎崩溃/卡死不再拖垮壳（对 4K 阅读页 + GPU 驱动风险是实打实的收益）。

**要拆的话，必须改的只有边界，不改协议**：
| 位置 | 同进程做法 | 跨进程做法 |
|---|---|---|
| 通道本体 | 进程内环形队列 + eventfd | `memfd` 共享内存 + 两个 eventfd（消息字节完全不变） |
| 通道发现 | `lwp_open("lanlu")` 单例 | 父进程建 memfd，子进程继承 fd 编号后 `lwp_attach(fd_a, fd_b)` |
| `surface.attach.buffer` | 进程内 fd 直接 `dup` | **必须走 `SCM_RIGHTS`**（Unix socket 传 fd），或改用 dmabuf 名字 |
| `liblwp` 加载 | 双方 `dlopen` 同一 `.so` | 子进程独立加载，版本需一致（握手已带 `protocol_major`） |

**决策**：**暂不拆**。理由：① 当前真机验收刚通过，拆进程会重新引入启动时序问题；
② `attach` 的 fd 语义一旦跨进程就要动（第 3 行），属于 `protocol_major` 级别的改动，
应等有明确收益（例如实测到引擎崩溃频率高）再做。**先记在这里，避免以后误以为"随手就能拆"**。

### 5.3 握手、版本与能力

1. 壳启动 → `lwp_open` → 发送 `core.hello { protocol_major, protocol_minor, shell_name, os_name, os_api_level, interfaces[]{name, version}, capabilities(bitfield) }`。
2. 引擎（由壳显式调用 `cj_app_main` 启动，**不再在 libmain 构造函数里自启动**）读到 `hello` 后回 `core.hello_ack { engine_version, interfaces[]{name, version_used} }`，双方按 `min(壳版本, 引擎版本)` 使用每个接口。
3. 之后壳发送初始状态快照：`system.config`（语言、深浅色、字体缩放、设备类型）、`system.paths`（files/cache/temp 目录）、`display.info`、`window.configure`、`surface.available`——取代现在的环境变量和“等 N 秒”。
4. 能力位（壳宣告，lwindow 暴露给 cui，借鉴 ozone `PlatformRuntimeProperties`、Qt `Capability`）：`server_side_decorations`、`window_move`、`window_resize_edges`、`min_max_size`、`cursor_shapes`、`cursor_lock`、`ime_preedit`、`ime_surrounding_text`、`clipboard_read_async`、`clipboard_mime`、`drag_drop`、`file_dialog_save`、`file_dialog_folder`、`vsync`、`fractional_scale`、`multi_window`、`soft_keyboard`。cui 根据能力位降级（例如没有 `window_move` 时标题栏不注册拖动区）。

版本规则（写进 `packages/lwp/README.md`，由 `lwp_abi.json` 比对强制）：
- 字段只追加，不删除、不改类型、不改顺序；接收方读 `min(size, sizeof(已知结构))`，多出的部分忽略，缺失的部分取默认值。
- 新消息必须带 `since`；对方版本不够时发送方不发（或降级）。
- 枚举全部 `extensible`，解码出未知值得到 `Unknown(n)` 而不是异常。
- 不复用 opcode；废弃消息标 `deprecated`，保留到下一个大版本。
- 任何破坏性修改 = `protocol_major + 1`，壳与引擎大版本不一致时拒绝握手并给出明确错误。

### 5.4 线程模型（鸿蒙；Wayland 见 §8A 末尾）

| 线程 | 做什么 | 与通道的关系 |
|---|---|---|
| ArkTS/UI 主线程 | Ability 生命周期、XComponent、ArkTS-only 操作（最小化/最大化/拖动/picker/拉起链接/权限） | 经 `napi_threadsafe_function` 接收壳调度线程转来的请求；结果直接 `lwp_send(EVENT)` |
| 壳调度线程（C，新增） | `lwp_wait(REQUEST)`；能用 NDK C API 完成的请求就地执行（光标样式、IME 光标位置、显示查询、vsync 请求…）；ArkTS-only 的转给 tsfn；需要“输入回调上下文”的（剪贴板读写）挂到待办队列 | REQUEST 的唯一消费者 |
| 输入过滤器回调线程 | 鼠标/键盘/触摸 → 协议事件；顺带执行剪贴板待办 | EVENT 生产者 |
| IME 回调线程 | `OH_TextEditorProxy_*` 回调 → 协议事件；`GetLeftTextOfCursor` 等需要同步返回的查询读取引擎最近一次 `set_surrounding_text` 的缓存 | EVENT 生产者 |
| vsync 回调线程 | `OH_NativeVSync_RequestFrame` 回调 → `frame.done` | EVENT 生产者 |
| 引擎线程（仓颉） | 事件循环：`lwp_wait(EVENT)` → 解码 → cui 分发 → 渲染 → 发请求 | EVENT 唯一消费者、REQUEST 唯一生产者 |

规则：
- 任何回调里都不阻塞等待引擎（避免 ANR / 死锁，client-next-ohos-plan.md 附录 F 已强调）。
- **`OH_WindowManager_*`（包括 `LockCursor`）内部会用 `PostSyncTask` 同步转到主线程执行**（`window_window_manager` 源码 `wm/src/oh_window.cpp`，36 个函数中 25 处）。这些调用只能放在壳调度线程，引擎线程不直接调用；主线程也绝不能同步等待壳调度线程，否则互锁。
- 引擎线程由壳显式创建，栈 16 MiB（musl 默认 128 KiB；与 horizon-ohos 一致）；`InitCJRuntime` 的 `RuntimeParam.coParam` 显式设置协程栈大小。
- 高于最低 API 的符号（光标 22、`OH_ArkUI_PostUITask` 22、IME 主线程回调 22、密度回调 24、触摸窗口坐标 24 等）一律用 `dlsym` 或弱符号加 `OH_GetSdkApiVersion()` 运行时判断，否则低版本设备上 `.so` 加载失败。
- 需要同步答复的系统回调（IME 查询光标左侧文本）一律用壳端缓存回答，引擎负责让缓存保持最新。
- `napi_call_function(env, recv, func, argc, argv, result)` 的参数顺序写成生成的辅助函数，避免 horizon-ohos 踩过的“回调永远不执行”。

### 5.5 接口目录（v1，2026-11-10 起以生成物为准）

> **本节的手写表格已退役。** 权威来源是 IDL 与生成物（改协议只改 `packages/lwp/protocol/*.toml`）：
>
> - IDL：`packages/lwp/protocol/{core,input,window,system}.toml`
> - 生成文档：[docs/lwp/lw_core.md](lwp/lw_core.md)、[lw_input.md](lwp/lw_input.md)、
>   [lw_app.md](lwp/lw_app.md)、[lw_window.md](lwp/lw_window.md)、[lw_surface.md](lwp/lw_surface.md)、
>   [lw_frame.md](lwp/lw_frame.md)、[lw_display.md](lwp/lw_display.md)、[lw_seat.md](lwp/lw_seat.md)、
>   [lw_text_input.md](lwp/lw_text_input.md)、[lw_clipboard.md](lwp/lw_clipboard.md)、
>   [lw_dialog.md](lwp/lw_dialog.md)、[lw_system.md](lwp/lw_system.md)、[lw_test.md](lwp/lw_test.md)
> - ABI 指纹：`packages/lwp/abi/lwp_abi.json`（只允许追加）
>
> 现状：**13 个接口 / 51 条消息**（v1）。
>
> 与最初草稿的差集（**尚未实现，属 M3+ 范围**，勿当作已有能力）：
> - `app`：`open_url` / `request_permission` / `want(params)` / `low_memory`
> - `window`：`move(serial)` / `resize(serial, edge)` / `set_drag_regions` / `occlusion`
> - `seat`：多指针 id、触摸（`down/motion/up/cancel/frame`）、键盘 `modifiers` / `repeat_policy`
> - `text_input`：`commit(serial)` / `show_panel` / `edit_command` / `panel_inset`
> - `surface`：`destroyed` / `shown`
>
> 草稿里有、实现里**有意省略**的：`core.dropped(count)`（由 stats 的 `dropped` 计数承担，
> 不占协议消息）；`log` 放在 `lw_system` 而不是 `lw_core`（壳只负责转发到 hilog）。

## 6. 输入模型（键盘、鼠标、触摸、滚轮、IME、光标）

### 6.1 坐标与单位

- 壳端输出：**窗口局部物理像素**（浮点）。OHOS：触摸用 `OH_Input_GetTouchEventWindowX/Y`；鼠标只有 display 坐标，用 `display − 窗口原点`，原点来自 `window.configure` 时壳端已知的窗口矩形（壳内计算，不再经文件/ArkTS 往返）；`OH_Input_GetMouseEventGlobalX/Y`（API 20）与 ArkUI `OH_ArkUI_PointerEvent_*` 作为备选通道。
- lwindow 统一除以 `scale` 得逻辑像素（替代 `lgui.scaleEventCoordinates`）。
- 时间戳统一 `CLOCK_MONOTONIC` 纳秒；双击/长按判定在 cui 用事件时间戳而不是“处理时刻”。

### 6.2 键盘

**键码单表**：`packages/lwindow/data/keycodes.tsv`，列为 `code(W3C) | usb_hid | evdev | ohos_keycode | location | default_key`。`code/usb_hid/evdev` 从 Chromium `dom_code_data.inc`（BSD 许可，需在文件头保留出处）导入，`evdev` 列供 Wayland（`wl_keyboard.key` 给的就是 evdev 码），OHOS 列按 `multimodalinput/oh_key_code.h`（358 个 `KEYCODE_*`）补齐。表是中立数据；生成出的“平台码 → KeyCode”映射表放进各平台包（`lplatform-ohos/.../keymap_ohos.inc`、`lplatform-wayland/src/keymap_evdev.inc`）。生成：
- 仓颉 `enum KeyCode { KeyA | … | PageUp | Slash | … | Unknown(UInt32) }`（物理键，与布局无关）；
- 每个平台包的 `平台码 → KeyCode` 查找表。

**引擎侧事件结构**（对标 winit `KeyEvent` / W3C KeyboardEvent）：

```cangjie
public struct KeyEvent {
    public let code: KeyCode   // 物理键（快捷键、游戏式按键用它）
    public let key: LogicalKey        // 逻辑键：Named(NamedKey) | Character(String) | Unidentified
    public let text: ?String   // 这次按键应插入的文本（无 IME 时由壳按布局合成）
    public let location: KeyLocation  // Standard / Left / Right / Numpad
    public let repeat: Bool
    public let modifiers: Modifiers   // shift/ctrl/alt/meta + capsLock/numLock
}
```

**OHOS 壳端处理**（采纳 horizon-ohos 已验证方案）：
1. 键盘走**窗口级过滤器** `OH_NativeWindowManager_RegisterKeyEventFilter`（API 12），不依赖 XComponent 焦点。过滤器实现（`wm/src/oh_window_event_filter.cpp`）只填 keyCode、action、actionTime、windowId、displayId，**没有 unicode、scancode、修饰键、repeat**，下面 3–5 条都是为此补的；
2. IME 激活期间过滤器不消费（返回 false），让拼音键到达输入法；IME 不消费的键（Esc、数字、方向键…）经 XComponent 的键回调（`OH_NativeXComponent_RegisterKeyEventCallbackWithResult`，API 14）回到协议；
3. OHOS 没有 repeat 标志：壳端维护“已按下键集合”，同键再次 DOWN 即 `repeat = true`；
4. 修饰键状态由按键集合推导，锁定键用 `OH_Input_GetFunctionKeyState`（API 15）；每次变化发 `seat.keyboard.modifiers`；
5. `text`：窗口过滤器只给键码，壳端按 US 布局 + Shift/CapsLock 合成（同 horizon-ohos `keycodes.rs::text`）；若 ArkUI 键事件可用，优先用 `OH_ArkUI_KeyEvent_GetUnicode`（API 14）。

**cui 迁移**（154 处 `UiEvent.KeyDown` 分布在 29 个文件，分两步，避免一次性大改）：
- 第 1 步（兼容）：`Key` 枚举补齐命名键（`PageUp/PageDown/Insert/F1…F24/ContextMenu` 等）并删掉 `RawScancode`；新增 `ctx.modifiers`（由事件流维护）替换 `Keyboard.modifiers()` 的 8 处调用；业务层 4 处 scancode 硬编码改为 `Key.PageUp/PageDown` 与 `KeyEvent.key == Character("/")`。现有模式匹配写法保持不变。
- 第 2 步：`UiEvent.KeyDown(KeyEvent)` / `UiEvent.KeyUp(KeyEvent)`，用 codemod 脚本改写模式匹配（`case UiEvent.KeyDown(Key.Escape, _)` → `case UiEvent.KeyDown(ev) where ev.isNamed(NamedKey.Escape)`），一次提交完成，配合 cui 单测。
- 快捷键在 cui 里集中定义（`Shortcut(mods, code)`），Mac 的 Cmd 与其他平台的 Ctrl 由 `Modifiers.command` 统一。

### 6.3 鼠标、触摸、滚轮

- **指针统一模型**（对标 W3C PointerEvent / `wl_pointer`）：`pointer_id`、`kind(mouse/touch/pen)`、`buttons`（位掩码，左/右/中/后退/前进）、`changed_button`、`pressure`；一组相关事件以 `frame` 结尾，lwindow 按 frame 合并后再分发（解决 M1 丢事件，也让“按下 + 移动”在同一帧原子生效）。
- 按钮映射：OHOS `MOUSE_BUTTON_LEFT/RIGHT/MIDDLE/…` → 协议按钮枚举 → cui `MouseButton.Left/Right/Middle/Back/Forward`（解决 M2，右键菜单才能工作）。
- **滚轮**：`axis(source, dx, dy, discrete)`。`source = wheel | finger | continuous`；`discrete` 为刻度数（对标 `axis_value120`），连续量为逻辑像素。OHOS：**窗口鼠标过滤器收不到滚轮**。它的 action 映射表只有 CANCEL/MOVE/BUTTON_DOWN/BUTTON_UP，AXIS 事件查表失败后打印 `find mouse event action fail` 并丢弃（源码 `oh_window_event_filter.cpp`；与 horizon-ohos 在 2in1 上的实测一致）。所以现在 `input_filter.cpp` 里的滚轮分支实际不会触发，这也解释了 M3。滚轮必须走 ArkUI 节点事件：在 XComponent 上叠一层透明 NDK 节点（或用 XComponent 本身）注册 `NODE_ON_AXIS`（API 17），读 `OH_ArkUI_AxisEvent_GetVerticalAxisValue/HorizontalAxisValue`、`GetAxisAction`（15，区分开始/更新/结束，供惯性滚动）、`GetScrollStep`（17）；触控板惯性 `OH_ArkUI_CoastingAxisEvent_*`（22）为可选能力。这类回调都在 UI 线程。现有的“÷45 换算刻度”移到壳端并写进协议文档。
- 同一个 ArkUI 节点还能提供：`OH_ArkUI_MouseEvent_GetRawDeltaX/Y`（指针锁定时的相对位移）、`OH_ArkUI_HoverEvent_IsHovered`（17）、`NODE_ON_KEY_EVENT` 的 `OH_ArkUI_KeyEvent_GetUnicode`（14）。窗口过滤器负责“不依赖焦点的键鼠主通道”，ArkUI 节点负责“滚轮、unicode、相对位移”这些过滤器拿不到的字段；壳端按时间戳去重后合并成一条协议事件流。
- enter/leave、hover：壳端发 `pointer.enter/leave`，lwindow 在 leave 时向 cui 合成“清除悬停”。
- **触摸**：`seat.touch` 独立接口保留多指信息；lwindow 对主触点按浏览器“兼容鼠标事件”规则合成 MouseDown/Move/Up，现有控件无需改动即可点选；之后按需在 cui 增加手势（拖动滚动、长按、双指缩放 `OH_ArkUI_AxisEvent_GetPinchAxisScaleValue`）。
- `CANCEL`（OHOS 三类事件都有 `*_ACTION_CANCEL = 0`）映射为 `pointer.cancel`，cui 收到后清理按下/拖动状态。
- 诊断信息（现在的 action 90/91/92）改走 `core.log` / `test.probe`，不再混入输入流（M4）。

### 6.4 IME（文本输入）

协议照搬 Wayland text-input-v3 的“增量事件 + done(serial) 原子提交”模型，加 GameTextInput 式的整体状态同步兜底：

```
引擎（TextField 获得焦点）
  text_input.enable(content_type=text, enter_key=done)
  text_input.set_surrounding_text("你好wo", cursor=8, anchor=8)
  text_input.set_cursor_rect(x, y, w, h)   // 逻辑像素 → 壳端换算到屏幕
  text_input.commit(serial=7)
壳（输入法）
  text_input.preedit("wo", 0, 2)           // 组合串，在输入框里画下划线
  text_input.done(7)
  text_input.preedit("", 0, 0); text_input.commit_text("我"); text_input.done(7)
引擎：在 done 时一次性应用 preedit/commit/delete，并回发新的 surrounding_text + commit(8)
```

- C API 的硬约束（`inputmethod_imf` 源码 `frameworks/ndk/src/inputmethod_controller_capi.cpp` 与头文件）：
  - **15 个 `OH_TextEditorProxy_Set*Func` 必须全部设置**，少一个 Attach 就返回 `IME_ERR_NULL_POINTER`；
  - 要拿到预编辑，必须在 `GetTextConfig` 回调里调用 `OH_TextConfig_SetPreviewTextSupport(config, true)`，否则组合串只留在候选条里，只能收到 `InsertText`（horizon-ohos 目前就是这样）；
  - 回调中的文本是 UTF-16（`char16_t*`），指针只在回调期间有效，必须立即复制；
  - 官方建议在主线程调用 API；`GetTextConfig` 在 Attach 内同步执行，其余回调默认在 IPC 线程；
  - textEditorProxy 在下次 Attach/Detach 之前不能释放；
  - 2in1 上 `showKeyboard=false` 只出候选条；不在文本框时必须 Detach；
  - 候选框坐标 horizon-ohos 用的是显示器绝对像素（窗口原点 + 文本框矩形），官方坐标系定义未核实。
- **OHOS 实现全部下沉到 C**（`inputmethod/*_capi.h`，API 12 起）：`OH_InputMethodController_Attach(textEditorProxy, attachOptions, &proxy)`；回调 `InsertText → commit_text`、`SetPreviewText / FinishTextPreview → preedit`（这正是现在缺失的预编辑）、`DeleteForward/Backward → delete_surrounding`、`MoveCursor / HandleExtendAction / SendEnterKey → edit_command / action`、`GetLeftTextOfCursor / GetRightTextOfCursor / GetTextIndexAtCursor → 用壳端缓存的 surrounding_text 同步回答`；引擎请求 `set_cursor_rect → OH_InputMethodProxy_NotifyCursorUpdate`、`set_surrounding_text → NotifySelectionChange`、`show_panel/hide_panel → ShowKeyboard/HideKeyboard`。回调线程：API 22 起可用 `OH_TextEditorProxy_SetCallbackInMainThread` 选择主线程或 IPC 线程；低于 22 时按 IPC 线程处理（只写队列，天然安全）。现在 ArkTS 里约 80 行 IME 代码与 13 个 `send*` NAPI 函数全部删除。
- 软键盘：2in1/tablet 不弹、phone 弹（沿用现有判断，改由壳端读设备类型）；`panel_inset` 事件让 cui 把焦点输入框滚到软键盘上方。
- **cui 改造**：`text_edit_state.cj` 增加 `composition: ?(range, text, cursor)`；`TextField/TextArea` 绘制预编辑下划线；光标矩形每帧上报改为“变化才发”；Backspace/方向键在有组合串时交给 IME。Wayland 壳直接对接 `zwp_text_input_v3`，与本协议几乎一一对应（§8A）。

### 6.5 光标

- 协议光标形状取 CSS `cursor` 子集：`default/pointer/text/wait/progress/crosshair/move/not-allowed/grab/grabbing/ew-resize/ns-resize/nesw-resize/nwse-resize/col-resize/row-resize/help/zoom-in/zoom-out`。
- OHOS：`OH_Input_SetPointerStyle`（API 22，`oh_pointer_style.h` 有 `DEFAULT/HAND_POINTING/TEXT_CURSOR/RESIZE_LEFT_RIGHT/RESIZE_UP_DOWN/MOVE/CROSS/CURSOR_FORBID/HAND_OPEN/HAND_GRABBING/HELP/ZOOM_IN/ZOOM_OUT…`），`OH_Input_SetPointerVisible`；锁定用 `OH_WindowManager_LockCursor/UnlockCursor`（API 22，需 `ohos.permission.LOCK_WINDOW_CURSOR`）。低于 22 的系统由能力位降级为“不支持”，不再静默空实现。
- cui 的 `CursorShape` 扩展为上述集合，`desktop_app` 只发“变化”。

---

## 7. 窗口、Surface 与帧

### 7.1 Surface 生命周期

- OHOS：优先 ArkUI NDK `OH_ArkUI_SurfaceHolder` + `OH_ArkUI_SurfaceCallback_SetSurfaceCreated/Changed/Destroyed/Show/HideEvent`（API 19/20），拿 `OH_ArkUI_XComponent_GetNativeWindow`；API < 19 退回 `OH_NativeXComponent_RegisterCallback`。壳端发 `surface.available/changed/will_destroy/destroyed`，引擎在 `will_destroy` 时停止渲染并释放 wgpu surface，在下一个 `available` 时重建。
- 引擎与 lgpu 的接口改为：`lgpu.Surface.fromRawHandle(kind, handle)` + `resize(w, h)`；`fromSurfaceId`/`LANLU_MAIN_SURFACE_ID` 退役。修复 W1（窗口尺寸固定）。
- 后台：**切后台或息屏不会触发 SurfaceDestroyed，只触发 SurfaceHide**（头文件原文 "invoked after the application is switched to the background"），Destroyed 只在下树或 `Finalize` 时出现。所以 `surface.hidden` 与 `app.lifecycle(background)` 时引擎必须自己停帧，wgpu surface 保留不重建。`OH_NativeXComponent_Callback` 结构体必须是静态存活（框架只保存指针）。Destroyed 回调返回后旧 window 立即失效，引擎线程要先同步停渲染，并持有一次 `NativeObjectReference`。
- 风险：horizon-ohos 实测 Maleoon Vulkan 驱动**第三次重建 swapchain 必崩**。尺寸变化时优先 `surface_configure`（reconfigure 现有 swapchain），不要销毁重建，并把“连续 resize 20 次”加入真机验收。

### 7.2 configure / ack（窗口状态原子生效）

壳把“尺寸 + 缩放 + 状态位 + 安全区”打包成一次 `window.configure(serial, …)`；引擎按新尺寸布局、渲染、`present` 后回 `window.ack_configure(serial)`。拖拽调整窗口大小时壳可连续发多个 configure，引擎只处理最后一个（中间的直接 ack）。缩放来源：`OH_WindowManager_DensityInfo_*`（API 24）/ `OH_NativeDisplayManager_GetDefaultDisplayVirtualPixelRatio`（API 12）。安全区：ArkTS `getWindowAvoidArea` 或 `OH_WindowManager_GetWindowAvoidArea`（API 15）。

### 7.3 帧调度

- 引擎有脏帧时发 `frame.request`，壳用 `OH_NativeVSync_RequestFrame`（`OH_NativeVSync_Create_ForAssociatedWindow`，API 14）或 XComponent `OnFrameCallback` 回 `frame.done(time, period)`；没有请求就不发，空闲时引擎阻塞在 `lwp_wait`。
- horizon-ohos 记录过“外来渲染管线的 XComponent 收不到系统 vsync”：能力位 `vsync=false` 时 lwindow 退回自驱节拍（按 `display.refresh_hz`）。
- cui `desktop_app` 的 `paceFrame` 改为以 `frame.done` 为节拍源，`present` 不再兼任节流。

### 7.3.1 `surface.attach` 的 buffer 语义（决策，2026-11-10）

问题：引擎把像素交给壳，有两种可能形态——(a) 引擎直接渲染进壳给的 native window；
(b) 引擎渲染到自己的 buffer，`attach(buffer_handle)` 交给壳合成。二者对 `attach` 的含义完全不同。

**决策：v1 用「句柄 0 = 直接渲染，非 0 = 共享缓冲」，按平台分别落地。**

- **OHOS（默认线上路径）**：`buffer == 0`。引擎通过 `lgpu` 直接渲染进 XComponent 的
  `OHNativeWindow`（Vulkan swapchain），壳不参与像素搬运。`attach` 此时只表达**帧提交 + 节拍**
  （与 `frame.request/done` 配对），不携带像素。理由：多一次拷贝对 4K 阅读页是纯亏损，
  且 Maleoon 驱动对 swapchain 重建极敏感（§7.1 风险），少一层交接少一类崩溃。
- **Wayland（M3W 之后）**：`buffer != 0`，走 **wl_shm（CPU 共享缓冲）**，即
  `wl_surface.attach(wl_buffer)` + `wl_surface.commit`。理由：wl_shm 不需要 dmabuf 协商、
  不需要 GPU 导出扩展，是唯一在两套驱动上都稳的起点；`zwp_linux_dmabuf_v1` 留作性能优化，
  等实测表明拷贝成为瓶颈（阅读页 present > 8ms）再上。
- **headless / 抓帧**：`buffer != 0`，共享内存 + `lw_surface.attach` 后由壳（或测试夹具）读像素。

**为什么现在定**：IDL 里 `attach.buffer` 是 `u64`，若等到 M3 才确定语义，会出现两种不兼容的
壳实现（一个当 VkImage 用、一个当文件描述符用），届时改协议要动 `protocol_major`。
现在把「0 与非 0」写进文档与测试，M3 只需补实现，不必改协议。

**什么情况下会推翻它**：① Wayland 端实测 wl_shm 拷贝导致掉帧（则引入 dmabuf，`buffer` 仍保持 u64，
含义按 capability 位 `dmabuf=true` 切换）；② OHOS 需要多窗口缩略图（则壳需要读引擎像素，
届时增加 `surface.export(serial)` 请求，而不是改变 `attach` 的语义）。

### 7.4 窗口操作与自绘标题栏

| 操作 | OHOS 实现 | 依据 |
|---|---|---|
| 最小化 / 最大化 / 恢复 | ArkTS `window.minimize()/maximize()/recover()`（经 tsfn） | `oh_window.h` 中没有对应 C 函数（已核对 API 26 头文件函数列表） |
| 关闭 | 引擎 `window.close` → 壳 `terminateSelf()`；系统关闭 → `window.close_requested` 事件，引擎决定是否退出 | — |
| 标题栏拖动 | **拖动区由引擎下发、由壳在按下的那一刻同步命中**：引擎每次布局变化发 `window.set_drag_regions(rects)`（逻辑像素，壳换算），ArkTS 的 XComponent `onTouch` 在 `TouchType.Down` 回调里同步判断是否落在拖动区，命中就立即调用 `startMoving()`，并通知引擎吞掉这次按下。`window.move(serial)` 用于 Wayland（`xdg_toplevel.move` 允许异步请求，§8A） | `@ohos.window.d.ts` 写明 `startMoving()`（14）只有在 onTouch 的 Down 回调里（或 Down 之后的 Move 里）调用窗口才会跟手；经 tsfn 异步触发是否生效未核实，所以不采用“引擎命中后发请求”。同时**鼠标过滤器在拖动区内必须返回 false**，否则 ArkUI 收不到 onTouch。freeform 之外的主窗口 `startMoving` 不生效，手机上基本是 801 |
| 边缘调整大小 | 没有“开始缩放”接口，只有开关 `setResizeByDragEnabled`（14），由系统热区处理；壳在隐藏装饰后显式打开 | — |
| 全屏 | 2in1 上 `setWindowLayoutFullScreen`/`setWindowSystemBarEnable` 不生效也不报错；用 `maximize(MaximizePresentation.ENTER_IMMERSIVE_DISABLE_TITLE_AND_DOCK_HOVER)` 进入、`recover()` 退出，真实状态以 `getWindowStatus()`/`on('windowStatusChange')` 为准 | horizon-ohos 实测；窗口状态只能有一个控制源，EntryAbility 不再设置窗口模式 |
| 尺寸/状态事件 | C 侧只能轮询 `OH_WindowManager_GetWindowProperties`；用 ArkTS `win.on('windowSizeChange'/'windowStatusChange'/'avoidAreaChange')` 转发给壳，再合成 `window.configure` | 现在完全没有监听，这是 W1 的另一半原因 |
| 最小尺寸 | ArkTS `setWindowLimits` | — |
| 去系统装饰 | ArkTS `setWindowDecorVisible(false)`（现有做法，已真机验证 sysTop=0） | lwindow.md / l-layer.md R49 |

ArkTS-only 操作统一经一个通用入口，分两步：
- **方案 B（先做）**：壳调度线程 → `napi_threadsafe_function` → ArkTS `host.dispatch(op, argsJson): Promise<string>` → 结果经一个 NAPI 函数 `lwp_send`。ArkTS 约 100–150 行，有编译期类型检查。
- **方案 A（稳定后逐项替换）**：C++ 在主线程（NAPI 导出函数内或 tsfn 回调内）用 `napi_load_module(env, "@ohos.window", …)`（11，**只能主线程**，不能在模块 Init 里调用）或 `napi_load_module_with_info`（12，子线程也可）直接调用系统模块，ArkTS 只传一次 `UIAbilityContext`、`window.Window`、`resourceManager` 对象（C++ 用 `napi_ref` 持有）。Promise 需要用 `napi_create_function` 造 then/catch。ArkTS 可降到约 30 行，但这条链路整体未实测。
- 两种方案对协议是同一个 C ABI（请求 id + op + 载荷，异步完成），切换不影响引擎。
- `napi_create_ark_runtime`（子线程 ArkTS 运行时）里不能用 Window、Picker 等依赖主线程环境的 Kit，不能用它绕开主线程。API 22 起 `OH_ArkUI_PostUITask` 可以不经 JS 切到 UI 线程执行 C 任务，20–21 只能用 tsfn。

---

## 8. 其他系统服务

| 能力 | 协议 | OHOS 实现 | 备注 |
|---|---|---|---|
| 剪贴板 | `clipboard.set/request/offer/data` | `OH_Pasteboard_*` + UDMF（API 13）；多 MIME `OH_Pasteboard_GetMimeTypes`（API 14） | **写入不需要权限**，原生 `OH_Pasteboard_SetData` 在普通线程返回 0（实测；ArkTS 定时器里 `setData` 报 13900002 的原因没有定论），壳调度线程直接写。**读取**按 `pasteboard_service.cpp::VerifyPermission`，普通应用只有两条合法路径：(1) 物理键盘 Ctrl+V 按下后 **2000 ms 内、读一次**（调用方 pid 等于目标窗口 pid 即放行，任意线程都行）；(2) ArkTS `PasteButton` 安全控件。`ohos.permission.READ_PASTEBOARD` 是受限 ACL 权限，实测声明后装不上，**现在 Index.ets 申请它、每 2 秒轮询读剪贴板的做法要删掉**（违反“禁止后台/轮询读取”规则）。壳端在键过滤器看到 Ctrl+V 时立即读取并发 `offer + data`；右键菜单的“粘贴”在 2in1 上用 PasteButton 实现（能力位 `clipboard_read_async` 告知 cui）。引擎 API 改为异步（`requestText(callback)`），删除 800ms 阻塞读。注意：hdc/uitest 注入的按键进不了窗口过滤器，Ctrl+V 只能用物理键盘验证 |
| 文件对话框 | `dialog.*` 请求 id + 异步结果 | ArkTS `DocumentViewPicker`（无 C API）；壳负责 uri → 沙箱路径复制、保存时的回写、120s 超时 | 现有 ArkTS 逻辑保留但只在一个模块里；结果走协议 |
| 应用路径 | `system.paths` | `OH_AbilityRuntime_ApplicationContextGetFilesDir/CacheDir/TempDir`（API 16）、`OH_Environment_GetUserDownloadDir/DocumentDir`（API 12） | 删除所有硬编码 `/data/storage/el2/base/files`；`HOME` 只作为兼容由 lwindow 设置给第三方库 |
| 语言 / 深浅色 / 字体缩放 | `system.config` | `OH_ResourceManager_GetResourceConfiguration`（20；旧 `GetConfiguration` 12 起有，20 起废弃）取 locale、colorMode、deviceType，需要 ArkTS 传一次 `resourceManager`；变化监听 `OH_ArkUI_RegisterSystemColorModeChangeEvent` / `…FontStyleChangeEvent`（12，需要 NDK 节点、UI 线程），语言变化订阅公共事件 `COMMON_EVENT_LOCALE_CHANGED`（`oh_commonevent.h`）；兜底是 ArkTS `onConfigurationUpdate` 一行转发 | 取代 `locale.txt` 与写死的 zh-CN；没有“取系统语言”的 i18n C API |
| 时区 | `system.config.timezone` | `OH_TimeService_GetTimeZone`（12） | horizon-ohos 实测：按 `/etc/localtime` 探测时区会段错误 |
| 显示器 | `display.*` | `OH_NativeDisplayManager_*`（API 12/14/20：尺寸、密度、刷新率、刘海、可用区、增删监听） | 取代 `primaryDisplayInfo`（SDL） |
| 字体 | `system.fonts` | 现在写死 `/system/fonts/HarmonyOS_Sans_SC.ttf`；改为壳端用 `OH_Drawing_GetSystemFontConfigInfo`（12）、`OH_Drawing_GetSystemFontFullNamesByType`（14）枚举后下发（任意线程） | fontconfig 配置生成留在壳端 |
| 生命周期 | `app.lifecycle/low_memory/terminate_requested` | UIAbility `onForeground/onBackground/onDestroy`、`onMemoryLevel` | 引擎据此暂停播放、停止帧、刷盘 |
| 打开链接 / 拉起 | `app.open_url` | ArkTS `context.openLink/startAbility` | ArkTS-only |
| 权限 | `app.request_permission` | ArkTS `requestPermissionsFromUser` | 剪贴板 READ_PASTEBOARD 等 |
| 拖放（后续） | `data_device.*` | `OH_ArkUI_DragEvent_*` + UDMF | v2 |
| 联调 / 自检 | `test.*` | 取代 `LANLU_PROBE_*`、`lanlu_env.txt`、`snapshot_req.txt` | release 构建不注册该接口 |

---

## 8A. Wayland 后端：协议映射

LWP 的大部分接口本来就是照 Wayland 设计的，桌面壳基本是一一翻译。下表写的是 Wayland 协议层面的对应关系；实现上这些对象大多由 winit-wayland 管理（§9.3），壳只在 winit 未覆盖的地方（cursor-shape-v1、portal、剪贴板 MIME）直接操作协议对象。

| LWP | Wayland 实现 | 说明 |
|---|---|---|
| `core.hello` 能力位 | `wl_registry` 绑定到的全局对象及版本 | 没有 `zwp_text_input_manager_v3` → `ime_preedit=false`；没有 `wp_cursor_shape_manager_v1` → 退回主题光标；没有 `zxdg_decoration_manager_v1` 或合成器只给客户端装饰 → `server_side_decorations=false` |
| `surface.available` | `wl_surface` 建好且收到首个 `xdg_surface.configure` 并 ack 后，发 `kind=wayland_surface, handle=(wl_display*, wl_surface*)` | lgpu 用 wgpu-hal 的 `create_surface_from_wayland`（已在 vendored 的 `instance.rs` 中）。lgpu 只拿指针，不链接 libwayland |
| `window.configure/ack_configure` | `xdg_toplevel.configure(w,h,states)` + `xdg_surface.configure(serial)` 打包成一次 LWP configure；引擎 present 后回 ack，壳再 `xdg_surface.ack_configure(serial)` + `wl_surface.commit` | 与 Wayland 的双缓冲语义一致 |
| 缩放 | `wp_fractional_scale_v1.preferred_scale`（/120）+ `wp_viewporter`；缺失时用 `wl_surface.preferred_buffer_scale`（wl_compositor v6）或 `wl_output.scale` | 引擎按物理像素渲染，viewport 设逻辑尺寸 |
| `window.move(serial)` / `resize(serial, edge)` | `xdg_toplevel.move(seat, serial)` / `resize(seat, serial, edges)` | serial 必须是最近一次按下的 `wl_pointer.button` serial，壳端保存并在协议事件中带给引擎 |
| `window.set_drag_regions` | 不需要 | Wayland 允许异步 move 请求，引擎命中后直接发 `move`；该请求在 Wayland 上忽略 |
| 最小化/最大化/全屏/最小尺寸/标题/app_id | `xdg_toplevel.set_minimized/set_maximized/unset_maximized/set_fullscreen/set_min_size/set_title/set_app_id` | `wm_capabilities` 事件决定能力位（有的合成器不支持最小化） |
| 窗口装饰 | `zxdg_toplevel_decoration_v1.set_mode(client_side)`，应用自绘标题栏（现有 `titlebar.cj`）；合成器只支持服务端装饰时由能力位告知 cui 隐藏自绘按钮 | **不使用 libdecor**；现在为绕开 libdecor GTK 插件崩溃而随仓库带的 `libdecor-cairo` 插件一并删除 |
| `seat.pointer.*` | `wl_pointer.enter/leave/motion/button/axis/axis_source/axis_value120/axis_stop/frame` | `frame` 一一对应；`axis_value120/120` = 刻度数 |
| `seat.touch.*` | `wl_touch.down/up/motion/frame/cancel` | 一一对应 |
| `seat.keyboard.*` | `wl_keyboard.keymap`（fd → `xkb_keymap_new_from_string`）、`key`（evdev 码 +8 = xkb 码）、`modifiers`（`xkb_state_update_mask`）、`repeat_info` | `text` 由 `xkb_state_key_get_utf8` 给出，死键/组合键用 xkb compose（`xkb_compose_table_new_from_locale`）；Wayland 不发重复按键，壳端按 `repeat_info` 的速率和延迟自己用定时器生成 repeat |
| `text_input.*` | `zwp_text_input_v3` | 请求/事件/`done(serial)` 一一对应；`set_cursor_rect` → `set_cursor_rectangle`（surface 局部逻辑坐标） |
| `seat.pointer.set_cursor` | `wp_cursor_shape_device_v1.set_shape`（形状名与 CSS cursor 同源）；缺失时 `wayland-cursor` 读 `XCURSOR_THEME/XCURSOR_SIZE` | `set_cursor` 需要 `wl_pointer.enter` 的 serial |
| `seat.pointer.lock` | `zwp_pointer_constraints_v1.lock_pointer` + `zwp_relative_pointer_v1` | 可选能力 |
| `clipboard.*` | `wl_data_device_manager`：`set_selection`（需要最近一次输入事件 serial）/ `data_offer.receive(mime, fd)` | 异步，通过 pipe fd 传数据；与 LWP 的异步剪贴板模型一致。中键粘贴 `zwp_primary_selection_v1` 为可选 |
| 拖放（v2） | `wl_data_device.enter/motion/drop` + `text/uri-list` | 对应现在 cui 已有的 `UiEvent.DropFile/DropText` |
| `dialog.*` | xdg-desktop-portal `org.freedesktop.portal.FileChooser.OpenFile/SaveFile`（D-Bus，异步 `Response` 信号） | 父窗口标识用 `zxdg_exporter_v2` 导出的 handle（`wayland:<handle>`）；portal 不可用时能力位置 false，cui 隐藏相关入口 |
| `app.open_url` | portal `OpenURI.OpenURI`；兜底 `xdg-open` | — |
| `system.config` | portal `Settings.Read("org.freedesktop.appearance", "color-scheme")` + `SettingChanged` 信号；语言取 `LC_ALL/LC_MESSAGES/LANG` | 深浅色变化实时下发 |
| `system.paths` | `XDG_CONFIG_HOME/XDG_DATA_HOME/XDG_CACHE_HOME`（缺省 `~/.config` 等）、`xdg-user-dirs` 的 Download/Documents | 取代现在由 `HOME` 推导的写法 |
| `system.fonts` | fontconfig（`fc-match` 等价调用或直接读取配置） | 现在 fontkit/webview 已依赖 fontconfig |
| `display.*` | `wl_output` + `zxdg_output_manager_v1`（逻辑位置/尺寸）+ `wl_surface.enter/leave`（窗口所在输出） | — |
| `frame.*` | `wl_surface.frame` 回调；可选 `wp_presentation` 反馈精确时间 | 窗口被遮挡时合成器会停发 frame 回调，引擎自然停帧 |
| `app.lifecycle` | `xdg_toplevel.configure` 的 `activated`/`suspended` 状态 | `suspended`（xdg-shell v6）对应鸿蒙的 Hide |
| `app.exit` / `window.close_requested` | `xdg_toplevel.close` 事件 → `close_requested`；引擎退出 → 宿主退出 | — |
| 激活 | `xdg_activation_v1`（从桌面启动时读取 `XDG_ACTIVATION_TOKEN`） | 可选 |

线程模型（Wayland 壳）：主线程跑 winit 事件循环（内部是 calloop），LWP 请求 eventfd 通过 winit 的 `EventLoopProxy` 唤醒；引擎线程由宿主创建（16 MiB 栈）。所有 Wayland 对象只在主线程访问；引擎需要的 `wl_surface*` 指针只交给 lgpu 在引擎线程创建 Vulkan surface（`libwayland-client` 的 proxy 线程安全规则允许这样做，但 lgpu 不得在 surface 上做其他 Wayland 调用）。

无法支持的能力（Wayland 设计如此）：窗口绝对位置读写（`window.setPosition`、`position()`）、全局鼠标坐标、置顶、窗口透明度。cui 里对应的 API 删除，或由能力位明确标为不支持。

---

## 9. 壳的形态

### 9.1 鸿蒙壳（`packages/lplatform-ohos`）

```
packages/lplatform-ohos/
  shell/native/        # C/C++，被 lpack-ohos 生成的 CMake 工程引用，产物 libmain.so
    lshell_main.cpp      # NAPI 模块注册；start()：lwp_open → hello/初始快照 → 引擎线程（16 MiB 栈）
#   InitCJRuntime → LoadCJLibraryWithInit("liblanlu_engine.so") → cj_app_main
    lshell_dispatch.cpp  # 壳调度线程：lwp_wait(REQUEST) + 生成的分发桩
    lshell_input.cpp     # 窗口级 鼠标/键盘/触摸 过滤器（主通道）+ ArkUI 节点 NODE_ON_AXIS/NODE_ON_KEY_EVENT（滚轮、unicode、rawDelta）→ seat.*
    lshell_ime.cpp# OH_InputMethodController / TextEditorProxy（15 个回调全设）→ text_input.*
    lshell_surface.cpp   # XComponent / SurfaceHolder 回调 → surface.*；OH_NativeVSync → frame.*
    lshell_system.cpp    # 路径、显示、配置、光标、剪贴板（Ctrl+V 读、任意线程写）、fonts.conf 生成
    lshell_host.cpp      # tsfn ↔ ArkTS dispatch（方案 B）；后续逐项换成 napi_load_module（方案 A）
    keymap_ohos.inc      # 生成：OHOS KEYCODE → KeyCode
  shell/arkts/         # 模板片段，由 lpack-ohos 拼进生成的工程
    EntryAbility.ets     # loadContent；把 context / window / resourceManager 各传给 native 一次；
#   生命周期与 onConfigurationUpdate 每项一行转发；不设置窗口模式
    Index.ets     # 一个 XComponent(SURFACE)（已真机验证的路径）+ onTouch(Down) 同步命中拖动区 → startMoving；
#   dispatch(op, argsJson)：minimize/maximize/recover/setWindowLimits/setResizeByDragEnabled/
#   setWindowDecorVisible/picker/openLink/requestPermission；
#   win.on('windowSizeChange'/'windowStatusChange'/'avoidAreaChange') 转发；可选 PasteButton
  deps/  # 鸿蒙原生依赖：vips shim、rocksdb 桥、vlc shim（OH_AudioRenderer）、fontkit shim、ffmpeg 交叉编译
  selftest/     # 原 portcheck/ohos_selftest*，经协议 test 接口触发
  README.md
```

- ArkTS 目标规模：方案 B 两个文件合计 **≤ 200 行**（现在 863 行），方案 A 后约 50 行；不含任何业务逻辑、轮询定时器、文件读写。
- 生成的 `module.json5`（模板在 `lpack-ohos`，取值来自 `app.toml`）：删除 `READ_PASTEBOARD`；按需声明 `INTERNET`、`LOCK_WINDOW_CURSOR`（normal）、`GET_NETWORK_INFO`（normal）、`querySchemes`（`openLink` 拉起外部应用需要，否则 17700055）。
- 引擎启动：ArkTS 在 `XComponent.onLoad` 之后调用 `lshell.start()`。删除 `libmain` 构造函数自启动与所有“等环境变量”的循环。

### 9.2 鸿蒙生成器（`packages/lpack-ohos`）

- 由 `.research-ohos/packages/ohos`（hapgen，`src/main.cj` 253 行）演进；必须用 host 工具链构建（交叉工具链编出的二进制运行时 `SIGABRT`，见 ohos-port.md）。
- 输入：`app-profiles/<app>/app.toml` + 引擎 `.so` + `lplatform-ohos` 构建产物；输出：`build/ohos/<app>/` 工程与 `.hap`。
- 子命令：`build`、`sign`、`install`、`run`、`verify`（合并现有 `check-hap-deps.sh`、`check-hap-symbols.sh`、`verify-ohos.sh`，并新增“HAP 内无 `libSDL3*`”“引擎 NEEDED 无 SDL”检查）。
- 工具链路径、签名材料路径、设备地址全部是配置项。

### 9.3 Wayland 壳（`packages/lplatform-wayland`）

**选型：Rust 宿主程序，窗口与输入基于 horizon 已 vendored 的 winit 0.31（`winit-wayland` 后端）**（第二版曾选“直接写 wayland-client”，参考 horizon 后改为此方案，理由见 §15.3）。

| 选项 | 结论 | 理由 |
|---|---|---|
| **winit 0.31 + `winit-wayland`（horizon `third_party/winit` 同一份源码）** | **采用** | `/workspace/horizon-ohos/horizon/third_party/winit` 含完整 `winit-wayland`（约 6.7 千行）：xdg-shell、fractional-scale、viewporter、xdg-activation、`zwp_text_input_v3`（预编辑、`set_surrounding_text`、`set_content_type`）、`drag_window`/`drag_resize_window`（`xdg_toplevel.move/resize`）、`pre_present_notify`（frame 回调节拍）、`data_device`、主题光标。依赖树在本机离线缓存里能完整解析（`cargo tree --offline` 已验证）。winit 的事件循环只在壳内运行，不会挡住协议：壳把 `WindowEvent` 翻译成 LWP 事件，把 LWP 请求翻译成 `Window` 方法调用 |
| 直接写 `wayland-client` | 备选 | 只有在 winit 缺失关键能力且无法补丁时才对单个协议对象下沉（例如 cursor-shape-v1：本版 winit-wayland 未使用，可在壳内直接绑定该全局对象） |
| 仓颉直接 FFI `libwayland-client` | 不用 | listener 是 C 回调，会出现“外部线程调用仓颉”（原则 6 禁止） |

剪贴板：horizon 用 `arboard 3.6.1`（`wayland-data-control` 特性）与 `wl-clipboard-rs 0.9.4`，两者都在离线缓存；在 winit 自带 `data_device` 不够用时直接复用。**仍缺** D-Bus 客户端 crate（`zbus`/`dbus` 不在缓存）——portal 相关功能需联网 vendor，或 dlopen 系统 `libdbus-1.so.3`。

```
packages/lplatform-wayland/
  Cargo.toml     # bin "lanlu"；[patch.crates-io] 指向与 horizon 共用的 winit / wgpu-hal 源码
  src/
    main.rs      # 参数、lwp_open、加载引擎（dlopen 仓颉运行时 → InitCJRuntime → LoadCJLibraryWithInit → 引擎线程 cj_app_main）
    app.rs       # winit ApplicationHandler：WindowEvent → LWP 事件；LWP 请求 → Window 方法（唯一翻译层）
    keys.rs      # winit KeyEvent（physical_key/logical_key/text/repeat/location）→ seat.keyboard.key
    ime.rs# winit Ime::{Enabled,Preedit,Commit,DeleteSurrounding,Disabled} ↔ text_input；request_ime_update
    cursor.rs    # 光标：winit Cursor；cursor-shape-v1 直接绑定（winit 未用时）
    clipboard.rs # arboard / wl-clipboard-rs
    portal.rs    # xdg-desktop-portal：FileChooser、OpenURI、Settings（color-scheme）
    system.rs    # XDG 目录、LANG/LC_*、fontconfig 字体
  tests/         # 在 headless weston 下跑协议一致性测试
```

### 9.4 Linux 打包（`packages/lpack-linux`）

- `lpack-linux deb`：组装 `/usr/bin/lanlu`、`/usr/lib/lanlu/`（引擎、`liblwp.so`、仓颉运行时、业务依赖库）、`lanlu.desktop`（`StartupWMClass=lanlu`，与 `xdg_toplevel.set_app_id("lanlu")` 一致）、图标，`Depends:` 写入 `libwayland-client0, libxkbcommon0, libvulkan1` 等。
- 现在 workflow 里内联的 `dpkg-deb` 打包步骤迁入这里；CI 只调用脚本。

### 9.5 headless 壳（`lwindow.backend.headless`）

纯仓颉内存通道，实现与 LWP 相同的消息语义：可脚本化注入事件、回放录制文件、截取 Canvas 输出。用于 cui/业务单测、快照装置（替代 `snapshot_harness.cj` 与 CI 中依赖 SDL dummy/x11 驱动的 `--snapshot` 冒烟）。

---

## 10. 里程碑与任务分解

每个里程碑以 §16.9 的“完成定义”为准，至少包括：主仓构建通过；`check-deps.py` 与 `check-platform-isolation.py` 通过（M0 起为“只降不升”模式，M6 起严格模式）；鸿蒙真机冒烟（启动、书库、搜索输入、阅读翻页）通过；M3W 之后另加 Wayland 冒烟。估时按 1 人全职。

### M0 基线、平台包骨架与护栏（1 周）
1. 建立 4 个平台包骨架：`lplatform-ohos`、`lpack-ohos`、`lplatform-wayland`、`lpack-linux`。
2. 把壳源码从仓外 `.research-ohos/packages/ohos/templates_sdl3` 迁入 `lplatform-ohos/shell`，把 hapgen 以 subtree 引入为 `lpack-ohos`（先原样迁移，保持可构建）；`build-ohos.sh` 改为调用 `lpack-ohos`。
3. 按 §4.2 迁移散落的鸿蒙代码：`*_ffi/native-ohos`、`lgpu/native-ohos` → `lplatform-ohos/deps`；`client-next/ohos` → `lpack-ohos/app-profiles/lanlu`；鸿蒙工具脚本 → `lpack-ohos/tools`；`client-next/build/ohos` 退出版本库。
4. **复现并定位历史 FFI 崩溃**：最小用例验证“引擎调用壳导出的 C 函数”在 (a) lgpu 只链接一份、(b) 引擎不在构造函数里自启动 时是否稳定。结论写回 l-layer.md。这是传输层方案的前置验证。
5. `tools/check-deps.py`、`tools/check-platform-isolation.py` + 规则表进入 CI（记录现状，违规数只降不升）。
6. 输入回放基线：录一份“书库滚动 + 搜索输入 + 阅读翻页”事件脚本，作为后续回归。
7. 照搬 horizon 的构建纪律：工具链路径只从 `OHOS_SDK_HOME`/`DEVECO_SDK_HOME` 推导（`common.sh` 做法）；每一步失败即停；`llvm-nm` 符号门禁；安装时 versionCode 自增。
8. 新增 `tools/sync-winit.sh`（同 `sync-wgpu-hal.sh`），从 horizon 同步 vendored winit，记录来源提交号。

验收：主仓内能一条命令打出与现在等价的 HAP；仓外 `.research-ohos` 不再参与构建；崩溃根因有结论；两个守卫进入 CI。

### M1 协议与传输（1.5–2 周）
1. `packages/lwp`：IDL（core/app/surface/window/seat/text_input/clipboard/dialog/display/system/frame/test 的 v1 骨架）、`tools/lwp-gen.py`、`liblwp.so`（环形队列、blob、eventfd、握手）、C 单测（多线程压测、满队列合并、未知消息跳过、版本协商）。
2. lwindow：`backend.lwp` 解码器 + 唯一事件漏斗；`waitEventTimeout` 改为 `lwp_wait`；`requestWake` 改为 `lwp_wake`；`backend.headless`。
3. 鸿蒙壳：`hello`/初始快照、壳调度线程、tsfn 通用 `dispatch`；输入过滤器改写为发协议事件（先保持现有能力等价：指针 + IME 文本）。
4. 引擎统一为动态库 + `cj_app_main`；启动改为显式握手；删除 `lanlu_autostart_engine`、`LANLU_MAIN_SURFACE_ID` 等待循环、`CN_WINDOW/CN_UI_BACKEND` 等待循环、`client-next` 的 `main()` 桌面入口。

验收：鸿蒙空闲时引擎线程 CPU 接近 0（对比现状 4ms 轮询）；回放脚本 0 丢事件；`input_events.txt/key_events.txt/text_input.txt` 不再被读写。

M1 之后分两条线，可两人并行：

**鸿蒙线**

### M2 完整键鼠（1.5 周）
1. `keycodes.tsv` + 生成器（列：W3C code、USB HID、OHOS、evdev、location、默认键）；`KeyCode`/`NamedKey`/`Modifiers`/`KeyEvent`。
2. 鸿蒙壳：窗口级键过滤器转发全部物理键、repeat 自判、修饰键推导、US 布局 text 合成、与 IME 互斥；鼠标按钮/enter/leave/cancel；**滚轮改走 ArkUI `NODE_ON_AXIS`**（窗口过滤器收不到滚轮）；触摸多指；`frame` 分组；两条输入通道按时间戳去重。
3. cui 第 1 步迁移（命名键补齐、`ctx.modifiers`、删 `RawScancode`、业务 4 处 scancode）；第 2 步 `KeyEvent` codemod。
4. cui：右键/中键事件路径打通；`MouseWheel` 语义（刻度 vs 像素）写清并在滚动容器中正确使用；触摸兼容鼠标事件。

验收（真机，物理键鼠）：`/` 聚焦搜索、PgUp/PgDn 翻页、Shift+Tab、Shift+方向键选择、Ctrl+A/C/V/X、Esc 关闭弹层、右键菜单、滚轮滚动书库与阅读器、触屏点击；协议回放测试覆盖以上序列。

### M3 IME（1 周）
1. 协议 `text_input` v1；鸿蒙壳用 C API 重写 IME（15 个回调全设、`SetPreviewTextSupport(true)` 开预编辑、UTF-16 转换、IPC 线程只入队）；删除 ArkTS IME 代码与 13 个 `send*` NAPI。
2. cui 组合态：`text_edit_state` 支持预编辑、下划线绘制、候选框位置上报、软键盘 inset。

验收：物理键盘拼音输入时组合串显示在输入框内、候选框跟随光标、选词上屏、删除/移动光标正确；手机形态弹软键盘且输入框不被遮挡。

### M4 窗口 / Surface / 帧 / 光标（1.5 周）
1. Surface 生命周期（保留已验证的 ArkTS XComponent + surfaceId 路径，surfaceId → OHNativeWindow 在壳内完成；SurfaceHolder 作为 API 19+ 可选）；Hide/Show 停帧不重建；lgpu 改为 `fromRawHandle(kind, handle)` + `resize`（reconfigure，不重建 swapchain），**lgpu 中的 `OH_NativeWindow_*` 调用移除**；lgpu 的 `request_adapter` 改为 horizon 的 HAL 直接导入（`platform/ohos.rs::pick_adapter`）；`win.on(...)` 转发合成 `window.configure/ack`；缩放与安全区。
2. vsync 帧调度（`OH_NativeVSync`，含自驱降级）；`desktop_app` 节拍改造。
3. 窗口操作：最小化/最大化/恢复/关闭/全屏（`maximize(ENTER_IMMERSIVE…)`）/最小尺寸/`setResizeByDragEnabled`；标题栏拖动 = 引擎下发拖动区 + ArkTS onTouch(Down) 同步 `startMoving()`，鼠标过滤器在拖动区不消费；cui `Window` 取代 `SdlWindow` 传给标题栏。
4. 光标样式与可见性（API 22+ C API；20–21 经 dispatch 调 ArkTS `pointer.setPointerStyle`），能力位降级。
5. 探索方案 A：C++ 主线程 `napi_load_module("@ohos.window")` 直接调用，先替换 minimize/maximize 两项验证。

验收：2in1 上拖动标题栏移动窗口、双击最大化/还原、拖动边缘或系统分屏改变窗口大小后布局正确重排、连续 resize 20 次不崩、悬停按钮/文本时光标形状正确、切后台再回来画面恢复。

### M5 系统服务（1 周）
剪贴板（写任意线程；读只在 Ctrl+V 后 2 秒内，右键粘贴用 PasteButton；删除 `READ_PASTEBOARD` 与 2 秒轮询）、文件对话框（请求 id）、路径（ApplicationContext C API）、语言/深浅色/字体缩放/时区（含变化通知）、显示器、生命周期、打开链接、权限；`test` 接口替代全部 `LANLU_PROBE_*` 与 `portcheck` 的文件读写；鸿蒙自检移入 `lplatform-ohos/selftest`。

验收：沙箱内不再出现任何 `*.txt` 桥接文件；切换系统深浅色/语言时应用即时响应；`/data/storage` 只出现在 `lplatform-ohos`。

**Wayland 线**（与 M2–M5 并行，只依赖 M1）

### M1W lgpu 去平台化 + Wayland 窗口出图（1 周）
1. lgpu：删除 `OH_NativeWindow_*` 与 `lgpu_surface_create_from_id` / `lgpu_native_window_set_geometry`，改为 `lgpu_surface_create_raw(kind, display_ptr, window_ptr)`；Linux 目标编译（`x86_64-unknown-linux-gnu`，Vulkan 后端，wgpu-hal 的 `create_surface_from_wayland` 已存在）。
2. `lplatform-wayland`：宿主加载引擎（`InitCJRuntime → LoadCJLibraryWithInit → cj_app_main`）；用 winit 建窗（`Resumed` → `surface.available`，`SurfaceResized`/`ScaleFactorChanged` → `window.configure`，`RedrawRequested` + `pre_present_notify` → `frame.*`）；`raw-window-handle` 取 `wl_display*`/`wl_surface*` 交给 lgpu。
3. 开发与 CI 环境：headless weston（`weston --backend=headless`）+ Vulkan 软件实现（lavapipe）。容器里没有 Wayland 开发头文件，`wayland-sys` 用 `dlopen` 特性，运行库已存在。

验收：在 weston headless 下启动应用并出图（截图比对）；改变窗口尺寸后布局正确重排；`ldd lanlu liblanlu_engine.so` 中没有 SDL。

### M2W Wayland 键鼠 + IME（1 周）
1. winit `PointerMoved/PointerButton/MouseWheel/PointerEntered/PointerLeft`、触摸、`KeyboardInput`/`ModifiersChanged` → `seat.*`（winit 已完成 xkbcommon keymap、compose、repeat、utf8 text）。
2. `keycodes.tsv`：winit `KeyCode` 本身就是 W3C code，与 LWP 的 `KeyCode` 一一对应，Wayland 壳不需要 evdev 映射表。
3. winit `Ime` 事件 + `request_ime_update`（surrounding text、content type、cursor area）↔ LWP `text_input`。
4. 光标：winit `Cursor`（主题光标）；cursor-shape-v1 作为增强；指针锁定（可选）。

验收：GNOME（mutter）与 KDE（kwin）实机：与 M2/M3 相同的键鼠验收清单；fcitx5 / ibus 中文输入（预编辑显示在输入框内、候选框跟随）。

### M3W Wayland 窗口操作与系统服务（1.5 周）

> **实现偏离（2026-11-11 记录）**：本项原计划用 winit；实际 `packages/lplatform-wayland`
> 直接用 **`wayland-client` + `wayland-protocols`**（不引入 winit）。理由：
> ① 壳需要精确控制 xdg-shell 请求顺序与 configure/ack 时序（winit 把这些藏起来了）；
> ② 假合成器测试要能逐字节断言 wire 请求，winit 无法观测。
> 代价是自己实现事件循环与对象生命周期管理（已在上面的 M1W/M2W 工作里完成）。
>
> **已完成**（可复核）：连接/全局绑定、xdg 建窗 + configure/ack、`surface.changed`、
> 指针/键盘转发、wl_shm 上屏（含缓冲复用）、窗口状态映射、DPI 缩放、
> 剪贴板 set/get/mime 协商、`system.info`/日志。测试 20 项（`cargo test`）。
>
> **剩余**：
> 1. ~~`wl_data_offer.receive` 的真实 fd 传递集成测试~~ ✅ 已完成（2026-11-11，第 97/99 轮）；
> 2. ~~多显示器选择~~ ✅ 已完成（2026-11-11，按 `surface.enter/leave` 切换缩放）；
> 3. ~~拖动/缩放~~ ✅ 已完成（`begin_move/begin_resize` → `xdg_toplevel.move/resize`）；
> 4. 拖放文件：壳侧**已完成**（`drag_enter/motion/leave/drop` + uri 解码），
>    引擎侧消费（拖到书库=导入？）**待产品决策**；xdg-desktop-portal 未做；
> 5. `lpack-linux` 出 .deb：**已完成**（`tools/build-deb.sh` + `--self-test`，CI 改为调用脚本）；
>    CI 里 weston headless 冒烟**已完成**（`tools/smoke-weston.sh` + CI 步骤）。
1. 客户端装饰：winit `with_decorations(false)`（不启用 sctk-adwaita 装饰），应用自绘标题栏；`drag_window()`/`drag_resize_window()`（即 `xdg_toplevel.move/resize`）、最小化/最大化/全屏/`set_min_surface_size` → 能力位。
2. 剪贴板（arboard / wl-clipboard-rs，horizon 同款）、拖放文件（winit `DragDropped` → `DropFile`）。
3. xdg-desktop-portal：FileChooser、OpenURI、Settings(color-scheme)。先确定 D-Bus 方案：联网 vendor `zbus`，或 dlopen 系统 `libdbus-1.so.3`。
4. 输出信息、XDG 路径、语言、fontconfig。
5. `lpack-linux` 出 .deb；CI 的 Linux 任务改为：构建宿主 + 引擎 → weston headless 冒烟 → `lpack-linux deb`。

验收：GNOME 与 KDE 上拖动标题栏移动窗口、双击最大化、边缘拖拽缩放、复制粘贴（与其他应用互通）、打开/保存文件对话框、系统切换深浅色时应用即时响应、安装 .deb 后任务栏显示正确图标。

**汇合**

### M6 删除 SDL 与包重组（1 周）
1. 拆出 `lbase`；cui/lgpu/lwindow 改依赖 `lbase`；删除 `lgui` 包：31 个 SDL 符号声明、`.sdl3/`（24 MB）、`.sdl3-nolibdecor/`（4.2 MB）、`libdecor-plugins/`、依赖 SDL 的 examples。
2. 业务层清理：`lgpu_backend.cj` 删除（职责已在 `lwindow.backend.lwp`）；`main.cj` 去掉 `SdlHints`、`frameProbeHook`、`capture*`、`prepareRendererHints`、`prepareDesktopIntegration`、各类 probe 分支。
3. 鸿蒙：引擎链接去掉 `-lSDL3 -lSDL3_ttf`；HAP 中无 `libSDL3*.so`；删除 `.research-ohos/sdl3-ohos` 的构建依赖与 SDL 钩子补丁。
4. CI：删除 SDL 下载/软链接/`SDL_VIDEODRIVER` 步骤；**删除 Windows 构建任务**与 `client-next/cjpm.toml` 的 mingw 段（桌面只支持 Wayland）；README 更新支持矩阵。
5. 两个守卫切换为严格模式；SDL 标识全仓禁止。

验收：全仓 `SDL_|TTF_|Sdl[A-Z]` 为 0；`readelf -d` 引擎与宿主无 SDL NEEDED；`client-next/src` 中 `import lgui|lgpu|lwp` 为 0；平台标识只出现在 4 个平台包与 `third_party/`。

### M7 测试与工具（贯穿，收尾 1 周；完整方案见 §16）
- 协议一致性测试：同一组脚本分别跑 headless、Wayland（weston headless，CI 每次跑）、鸿蒙（真机经 `test.inject`，手动或定期），比较 cui 收到的事件序列。
- 录制/回放：壳端 `LWP_TRACE=1` 把双向消息写成 `.lwtrace`；回放器在 headless 下重现问题，替代现在的截图 + 文件探针调试方式。
- 解码器模糊测试（随机/截断/未知 opcode/超长 size）。
- ABI 守卫：`lwp_abi.json` 只允许追加。
- `verify-window.sh` 改为 `lpack-ohos verify --window`，读取协议 trace 而不是 `window_info.txt/filter_origin.txt`。
- 自验收控制口（借鉴 horizon `horizon-ctl`）：debug 构建下 `test` 接口额外开一个带 token 的本地 TCP 口，`lpack-ohos ctl` 封装 `hdc fport`，可远程注入事件、截图、查询状态；命令表单一来源，生成 CLI 帮助与参考文档，测试保证文档不过期。

### 里程碑依赖与工期

```
M0 ─► M1 ─┬─► 鸿蒙线：M2 ─► M3     ┐
   │          M4      ├─► M6 ─► M7 收尾
          │   M5      │
   └─► Wayland 线：M1W ─► M2W ─► M3W ┘
M7 的测试设施从 M1 起逐步建立
```

| 安排 | 工期 |
|---|---|
| 单人串行 | M0 1 + M1 2 + 鸿蒙线 5 + Wayland 线 3.5 + M6 1 + M7 1 ≈ 13–14 周，加测试设施约 2 周（§16.10）≈ **15–16 周** |
| 两人并行（M1 后一人鸿蒙线、一人 Wayland 线） | ≈ **10–11 周**（含测试设施） |

---

## 11. 现状渠道 → 新协议对照（删除清单）

> **状态盘点（2026-11-10，M2/M3 阶段）**：下表是 M6 删除工作的依据。每行标注
> 「替代通道是否已实现 + 文件写入点是否已被短路」。替代通道未实现的行，M6 前必须先补。

| 现在 | 替代 | 删除时机 |
|---|---|---|
| 现在 | 替代（实现状态） | 删除时机 | 2026-11-10 状态 |
|---|---|---|---|
| `input_events.txt` / `lanlu_push_input` / `readInputEvents` | `lw_input.pointer_*` ✅ | M2 | **已短路**：`lanlu_push_input` 先试协议；`readInputEventsAuto` 走 `nextLwpEvent`（`LANLU_LWP=1`） |
| `key_events.txt` / `push_key_name` | `lw_input.key` ✅ | M2 | **已短路**：`push_key_name2` 先试协议 |
| `text_input.txt` / `sendText` | `lw_input.text_input` ✅ | M2 | **已短路**：`lanlu_send_text` / `SendText` 先试协议 |
| `clip_out/clip_req/clip_in.txt` | `lw_clipboard.set/get/text` ✅ | M5 | **已短路（写）**：`clipboardSetText/GetText` 在 `LANLU_LWP=1` 走协议；`clip_in` 的后台同步还在 ArkTS 轮询里，未摘 |
| `filedlg_req/result.txt` | `lw_dialog.open/save/result` ✅ | M5 | **已分流**：LWP 请求的对话框经 `dialog.result` 回引擎；`finishDialog` 按来源分流 |
| `LANLU_MAIN_SURFACE_ID/W/H` | `lw_surface.available/changed` ✅ | M4 | **已短路（LANLU_LWP=1）**：`lwpAwaitSurface` 优先；15s 轮询仅作回落 |
| `window_cmd.txt` / `takeMinimizeRequest` | `lw_window.set_minimized` ❌ 未实现 | M4 | **未做**：引擎仍写命令文件（`requestWindowCommand`）；需补 `window.*` 请求编码器 + 壳消费 |
| `g_lanlu_app_exited` / `appExited` 轮询 | `lw_app.quit` ✅（协议有） | M2 | **未接**：协议有 `app.quit`，但引擎退出仍走静态标志 + ArkTS 轮询 |
| `CN_WINDOW`、`CN_UI_BACKEND`、`setEnv`、`lanlu_env.txt` | **不替代（结论）** | 不删 | **已定案**：这些是开发期开关（换渲染后端、注环境变量、开探针），不是平台能力。走协议只会让调试链路更长且依赖壳。保留，但要求 `LANLU_LWP=1` 下不干扰协议路径（已满足：只读环境变量）。附带风险记录：`lanlu_env.txt` 可注入任意环境变量，属**调试后门**，release 构建应关闭 |
| `locale.txt` | `lw_system.info` ✅ | M5 | **已替代**：`resolveLanguage` 优先用壳下发的语言 |
| `probe_trace.txt` / `LANLU_PROBE_LGPU` | `lw_system.log` ✅ | M6 | **已短路（LANLU_LWP=1）**：`probeTrace(Line)` 先发协议；文件输出保留给无协议环境 |
| `snapshot_req.txt/snapshot.rgba`、`lgpuTest/stagePng` | `lw_test.capture` / `request_capture` ✅ | M6 | **已短路（LANLU_LWP=1）**：引擎发 `test.request_capture` → 壳用 componentSnapshot 抓帧；`snapshot_req.txt` 仅在未开启时写。`lgpuTest`（240x160 小窗自检）保留 |

**机械化的删除进度**：`tools/check-no-file-bridge.sh` 把这些点做成「只允许减少」的基线
（`tools/file-bridge-baseline.toml`）。**2026-11-11：35 → 3 处**（M6 第 1~4 步已执行，
剩 2 处 `lanlu_env.txt`（定案保留）+ 1 处注释误计）。加一处新文件桥会直接失败，
删掉一处则计数下降 —— M6 的进度从此是数字，不是印象。

**注意**：真正的删除（删掉回落分支的代码）**必须等真机验收通过**。现在这些分支在
`LANLU_LWP=0` 时仍是唯一可用路径：提前删会把项目置于「协议未验证 + 无回落」的状态。

**M6 执行手册**：具体删除顺序、每步的删除对象与调用方清单、判据，见
[docs/m6-deletion-checklist.md](m6-deletion-checklist.md)（6 步，含「为什么现在不删」）。

**§11 表 ↔ 基线 ↔ 代码 的可追溯映射**（`tools/file-bridge-baseline.toml`，35 处）：

| 桥 | 基线命中 | 代码位置 | 协议替代 | LANLU_LWP=1 时是否停用 |
|---|---|---|---|---|
| `input_events.txt` | 3 | `lwindow/src/events.cj` ×1、`shell_napi.cpp` ×2（写点 + 默认路径） | `lw_input.pointer_*` | 是（`lanlu_push_input` 先试协议） |
| `key_events.txt` | 2 | `events.cj` ×1、`shell_napi.cpp` ×1 | `lw_input.key` | 是（`push_key_name2` 先试协议） |
| `text_input.txt` | 2 | `events.cj` ×1、`shell_napi.cpp` ×1 | `lw_input.text_input` | 是（`lanlu_send_text` 先试协议） |
| `clip_*.txt` | 9 | `lwindow/src/clipboard.cj` ×5、`ohos_entry.cj` ×4 | `lw_clipboard.*` | 是（`pollClipboard` 直接返回） |
| `filedlg_*.txt` | 4 | `Index.ets` ×4 | `lw_dialog.*` | 是（LWP 请求走协议，`finishDialog` 分流） |
| `window_cmd.txt` | 4 | `Index.ets` ×2、`lwindow/window_command.cj` ×2 | `lw_window.set_state/close` | 是（轮询器启动时即跳过） |
| `snapshot_req.txt` | 2 | `Index.ets` ×1、`client-next/src/main.cj` ×1 | `lw_test.request_capture` | 是（`pollSnapshot` 直接返回） |
| `locale.txt` | 0 | （已删） | `lw_system.info` | — |
| `lanlu_env.txt` | 3 | `ohos_entry.cj` ×3 | 未替代（联调开关） | 否（计划 M6 最后删） |
| `Index.ets` 其它（`clip_in` 等） | 5 | `Index.ets` | 见上 | 是 |

> ~~合计 35 处~~ **2026-11-11 更新：已执行 M6 第 1~4 步，基线降到 2 处**
> （只剩 `lanlu_env.txt` 两条读 —— 定案保留的调试开关）。
> 真机验收通过后执行（见 `docs/m6-deletion-checklist.md`），删除过程与验证记录见
> `docs/lwindow-plan-progress.md` 第 55~57 轮。

**剩余工作排序**（全部是仓颉/C 可测项）：① `window.set_minimized` 等 4 个窗口请求编码器 + 壳消费；
② `app.quit` 接引擎退出；③ ArkTS 摘掉 `clip_in` 后台同步；④ 最后删 `lanlu_env.txt` 等联调开关。
| `startFilter(winId, ox, oy)` 与原点文件 | 壳内部状态 | M2 |
| `sdl_main.c`、SDL 钩子补丁、`sdl3-ohos` 预编译库 | — | M0 删 `sdl_main.c`；M6 删其余 |
| `lgui` 包（31 个 SDL 声明、`.sdl3/`、`.sdl3-nolibdecor/`、`libdecor-plugins/`）、CI 的 SDL 步骤与 Windows 任务、`client-next` mingw 段 | — | M6 |
| `lwindow/window_policy.cj`（`XDG_SESSION_TYPE`、`LIBDECOR_PLUGIN_DIR`、`SDL_RENDER_DRIVER`） | `window.configure` / `display.info` | M1W |
| `lwindow/ohos_*.cj`、`portcheck/ohos_selftest*`、`*_ffi/native-ohos`、`client-next/ohos` | 迁入 `lplatform-ohos` / `lpack-ohos` | M0 |

---

## 12. 风险与对策

| # | 风险 | 对策 |
|---|---|---|
| R1 | 引擎 ↔ 壳 FFI 历史崩溃根因不明，新传输层同样依赖 FFI | M0 先做最小复现；`liblwp.so` 独立、无构造函数、纯 C；若仍不稳定，备选方案是通道放在引擎 `.so` 内、壳通过 `dlsym` 取函数（方向反转），协议与上层不受影响 |
| R2 | 外部线程调用仓颉 `@C` 在机制上支持（N2CStub → `MRT_NewForeignCJThread`），但没有文档，有死锁前科，栈只有 128 KiB | 设计上不依赖：引擎只在自己线程上 `lwp_recv`；需要回调的地方全部改为“写队列 + 唤醒” |
| R3 | 剪贴板读取只能在 Ctrl+V 后 2 秒内读一次，或通过 PasteButton | Ctrl+V 时壳端立即读取并推送；右键粘贴用 PasteButton；协议层面剪贴板为异步；能力位告知 cui |
| R4 | 部分能力只有较新 API（光标 22、IME 主线程回调 22、密度信息 24、ApplicationContext 路径 16） | 握手宣告 `os_api_level` 与能力位，lwindow 统一降级；最低支持版本写进 README |
| R5 | ArkTS-only 操作（最小化/拖动/picker）仍需 tsfn 往返 | 统一 `dispatch` 入口、生成参数编解码；结果全部异步，引擎不等待 |
| R6 | cui `KeyDown` 154 处迁移量大 | 两步走：先兼容扩展枚举，再 codemod 一次性替换；配合回放回归 |
| R7 | 删除 SDL 后，到 M1W 完成前桌面端不可运行（现状其实已经不可运行） | Wayland 线从 M1 后立即开始，M1W 只做“出图 + 尺寸变化”，尽快恢复桌面冒烟；期间 CI 的 Linux 任务只跑 headless 后端测试 |
| R8 | 协议膨胀、维护成本 | v1 只做 §5.5 列出的接口；业务私有需求走具名扩展通道（类似 Flutter platform channel），不进核心协议 |
| R9 | `lpack-ohos` 与 hapgen 独立仓的同步 | 主仓以 git subtree 引入并作为日常开发位置，定期回推；与 LWP 相关的 ArkTS 薄壳放 `lplatform-ohos`，不放进通用生成器 |
| R10 | `startMoving` 必须在 onTouch Down 回调里同步调用 | 拖动区由引擎下发、壳同步命中（§7.4）；鼠标过滤器在拖动区不消费事件 |
| R11 | Maleoon 驱动第三次重建 swapchain 必崩（horizon-ohos 实测） | resize 只做 reconfigure 不重建；切后台只停帧不销毁；真机连续 resize 压测 |
| R12 | `OH_WindowManager_*` 同步转主线程，可能和主线程互锁 | 只在壳调度线程调用；主线程永不同步等待壳/引擎 |
| R13 | 桌面只支持 Wayland：X11 会话、Windows、macOS 用户无法使用 | 支持矩阵写进 README；新增平台按原则 10 只需新增两个平台包；X11 若有需求可作为 `lplatform-x11` 后续加入 |
| R14 | 合成器差异：GNOME 不支持服务端装饰，部分合成器缺 text-input-v3 / cursor-shape / fractional-scale / 最小化 | 全部走能力位降级；验收至少覆盖 GNOME（mutter）与 KDE（kwin）；CI 用 weston headless |
| R15 | Wayland 壳的 D-Bus 依赖（portal）不在离线 cargo 缓存 | M3W 开始前联网 vendor `zbus`，或 dlopen 系统 `libdbus-1.so.3`；portal 不可用时能力位降级 |
| R16 | 容器内缺 Wayland 开发头文件与 wayland-protocols XML 包 | `wayland-sys` 用 `dlopen` 特性、协议 XML 取自 cargo 缓存的 `wayland-protocols` crate，编译不依赖系统头文件；运行库 `libwayland-client.so.0`、`libxkbcommon.so.0`、`libvulkan.so.1` 已存在 |

---

## 13. 附录 A：OHOS 能力 → 实现位置（依据 API 26 SDK 头文件核对）

SDK 头文件位置：`/workspace/lanlu/.research-ohos/tools/clt-7.0/command-line-tools/sdk/default/openharmony/native/sysroot/usr/include`。“未核实”表示未在头文件或真机上确认。

| 能力 | NDK C API（since） | 线程/上下文约束 | ArkTS 兜底 |
|---|---|---|---|
| 窗口级键/鼠/触摸过滤器 | `OH_NativeWindowManager_RegisterKeyEventFilter`(12)、`…MouseEventFilter`/`…TouchEventFilter`(15)；返回 true 表示拦截（ArkUI 与 IME 都收不到） | 窗口输入分发线程（推测主线程，未核实）；不依赖组件焦点 | Key 只有 keyCode/action/time；Mouse 只有 MOVE/DOWN/UP/CANCEL（**无滚轮**）；坐标只有 display/global |
| 全局输入监听/拦截 | `OH_Input_Add*EventMonitor`/`Interceptor`(12) | 需要 system_basic 权限，普通应用不可用 | — |
| 输入事件字段 | `OH_Input_GetKeyEvent*`(12)、`OH_Input_GetMouseEvent*`(12；Global 坐标 20)、`OH_Input_GetTouchEventWindowX/Y`(24)、`OH_Input_GetFunctionKeyState`(15) | — | — |
| XComponent 回调 | `OH_NativeXComponent_RegisterCallback`(8)、`RegisterMouseEventCallback`(9)、`RegisterKeyEventCallbackWithResult`(14)、`RegisterOnFrameCallback`(11)、`RegisterUIInputEventCallback`(12)、`RegisterSurfaceShow/HideCallback`(12) | UI 线程 | — |
| 新版 Surface 管理 | `OH_ArkUI_SurfaceHolder_*`、`OH_ArkUI_SurfaceCallback_*`(19/20)、`OH_ArkUI_XComponent_GetNativeWindow`(19) | UI 线程 | — |
| ArkUI 输入细节 | `OH_ArkUI_AxisEvent_*`(12/15/17)、`OH_ArkUI_CoastingAxisEvent_*`(22)、`OH_ArkUI_KeyEvent_GetUnicode`(14)、`OH_ArkUI_UIInputEvent_GetModifierKeyStates`(17) | UI 线程 | — |
| IME | `OH_InputMethodController_Attach`(12)、`AttachWithUIContext`(23)、`OH_InputMethodProxy_ShowKeyboard/HideKeyboard/NotifyCursorUpdate/NotifySelectionChange/NotifyConfigurationChange`(12)、15 个 `OH_TextEditorProxy_Set*Func`(12，须全部设置)、`OH_TextConfig_SetPreviewTextSupport`(12)、`OH_TextEditorProxy_SetCallbackInMainThread`(22) | 官方建议主线程调用；GetTextConfig 在 Attach 线程同步执行，其余回调默认在 IPC 线程；文本为 UTF-16 且仅回调内有效 | `@kit.IMEKit`（现状） |
| 光标 | `OH_Input_SetPointerStyle`、`OH_Input_SetPointerVisible`、`OH_Input_SetCustomCursor`(22)，只能设本进程窗口；`OH_WindowManager_LockCursor/UnlockCursor`(22，仅焦点窗口，需 `LOCK_WINDOW_CURSOR`；第二参数须为 true，未就绪返回 1300002 需重试) | 样式 API 线程未核实；LockCursor 内部同步转主线程 | 20–21：`pointer.setPointerStyle/setPointerVisible`；锁定无兜底 |
| vsync | `OH_NativeVSync_Create`(9)、`Create_ForAssociatedWindow`(14)、`RequestFrame`(9，一次性，每帧重新请求)、`GetPeriod`(10，首次回调后才有效)、`SetExpectedFrameRateRange`(20)；`OH_DisplaySoloist_*`(12) | 每个实例自建的 vsync 线程（不是 UI 线程） | XComponent OnFrame（UI 线程；自绘管线可能收不到） |
| 窗口属性 | `OH_WindowManager_GetWindowProperties/GetWindowAvoidArea/ShowWindow/SetWindowFocusable/SetWindowKeepScreenOn/…`(15)、`DensityInfo_*`(24) | 未核实 | `@ohos.window` |
| 最小化/最大化/恢复/拖动/尺寸限制/标题栏 | **头文件中无对应函数** | — | `window.minimize`(11)/`maximize`(12)/`recover`(11)/`startMoving`(14，须在 onTouch Down 内)/`setWindowLimits`(11)/`setResizeByDragEnabled`(14)/`setWindowDecorVisible`(11) |
| 窗口属性类 C API 的线程 | `OH_WindowManager_*` 内部 `PostSyncTask` 到主线程 | 可从非 UI 线程调用，但同步等待主线程 | — |
| 显示器 | `OH_NativeDisplayManager_*`(12/14/20) | — | — |
| 剪贴板 | `OH_Pasteboard_*`(13)、`GetMimeTypes`(14)、`GetChangeCount`(18) | 写：无权限、任意线程；读：物理 Ctrl+V 后 2000 ms 内读一次，或 PasteButton；`READ_PASTEBOARD` 是受限 ACL | `@ohos.pasteboard`（规则相同）；PasteButton 只有 ArkTS |
| 应用路径 | `OH_AbilityRuntime_ApplicationContextGetFilesDir/CacheDir/TempDir`(16)、`GetCacheDir/GetBundleName`(13)、`OH_Environment_GetUserDownloadDir/DocumentDir/DesktopDir`(12) | — | `context.filesDir` |
| 系统配置 | `OH_ResourceManager_GetResourceConfiguration`(20；旧 `GetConfiguration` 20 起废弃，需 ArkTS 传 resourceManager)、`OH_ArkUI_RegisterSystemColorModeChangeEvent`/`…FontStyleChangeEvent`(12)、公共事件 `COMMON_EVENT_LOCALE_CHANGED`、`OH_TimeService_GetTimeZone`(12)、`OH_GetDeviceType`/`OH_GetSdkApiVersion`(10) | 变化监听需 NDK 节点、UI 线程 | `onConfigurationUpdate` |
| 文件 URI / 授权 | `OH_FileUri_*`(12/13)、`OH_FileShare_*`(12) | — | picker 只有 ArkTS |
| 拉起自身 Ability | `OH_AbilityRuntime_StartSelfUIAbility`(15)、`…WithStartOptions`(17) | 需 `NDK_START_SELF_UI_ABILITY`；仅 2in1/tablet | `startAbility`；拉起外部用 `openLink`（需 querySchemes） |
| 权限 | 仅检查：`OH_AT_CheckSelfPermission`(12) | — | 申请只能 `requestPermissionsFromUser`（需 ctx） |
| 文件选择器 / 通知发布 | 无 | — | `DocumentViewPicker`（需 ctx，本机 picker 进程会崩，要超时）、`notificationManager` |
| 从 C 调 ArkTS 模块 | `napi_load_module`(11)、`napi_load_module_with_info`(12)、`napi_call_threadsafe_function_with_priority`(12)；`OH_ArkUI_PostUITask`(22) 不经 JS 切 UI 线程 | `napi_load_module` 只能主线程、不能在模块 Init 里调；`with_info` 子线程也可；`napi_create_ark_runtime` 环境里用不了 Window/Picker；`napi_get_uv_event_loop` 12 起不建议使用 | — |
| 仓颉运行时 | `InitCJRuntime(RuntimeParam*)`（可设堆、GC、线程/协程栈）、`LoadCJLibraryWithInit`、`FindCJSymbol`、`FiniCJRuntime`、`RunCJTask`（在仓颉调度器线程执行）；`@C` 入口经 `CJ_MCC_N2CStub` → `MRT_NewForeignCJThread` | 外部线程直接调 `@C` 机制上可行，但无文档、有死锁前科、栈小（不依赖）；`ohos.ark_interop` 不在 cjv 交叉工具链里 | — |

## 14. 附录 B：本计划依据的数据

| 数据 | 值 | 获取方式 |
|---|---|---|
| NAPI 导出函数 | 30 | `shell_napi.cpp::ShellInit` |
| ArkTS 壳行数 | Index.ets 813 + EntryAbility.ets 50 | `wc -l` |
| lgui 非测试文件 / 含 SDL 标识 | 57 / 42；声明的 SDL 符号 31 | `grep` |
| cui+业务 输入用法 | `KeyDown` 154 处/29 文件、`MouseDown` 63/39、`MouseMove` 62/37、`MouseUp` 41/24、`MouseWheel` 15/14、`Keyboard.modifiers` 8/4、`RawScancode` 4/3、光标相关 132/38、`SdlWindow` 26/7 | `grep`（不含测试） |
| lgpu 双份链接 | libmain.so 定义 39 个 `lgpu_*`；liblanlu_client_next.ui.so 定义 55 个 | `llvm-nm -D --defined-only` |
| 引擎 SDL 依赖 | NEEDED `libSDL3.so`、`libSDL3_ttf.so` | `llvm-readelf -d` |
| 构建副本入库 | `client-next/build/ohos` 下 90 个跟踪文件 | `git ls-files` |
| SDL 预编译库体积 | `lgui/.sdl3` 24 MB、`.sdl3-nolibdecor` 4.2 MB、`libdecor-plugins` 64 KB | `du -sh` |
| 平台代码散落位置 | `lwindow/src/ohos_*.cj`（3 个）、`lgpu/native/src/lib.rs`（`OH_NativeWindow_*`）、5 个 `native-ohos/` 目录、`portcheck/src/ohos_selftest*`（5 个）、`client-next/ohos/`、`client-next/cjpm.toml` 鸿蒙/mingw 段、`tools/` 9 个脚本、仓外壳模板 | `ls` / `grep` |
| Wayland 离线依赖 | 有：wayland-client 0.31.15、wayland-backend 0.3.17、wayland-sys 0.31.11（dlopen）、wayland-protocols 0.32.13、wayland-cursor、xkbcommon-dl 0.4.2、calloop 0.14.5、smithay-client-toolkit 0.21.1；无：winit、xkbcommon、zbus/dbus | `/workspace/.cargo/registry/cache` |
| Wayland 运行库 / 开发头 | 运行库：`libwayland-client.so.0`、`libwayland-cursor.so.0`、`libxkbcommon.so.0`、`libvulkan.so.1`、`libdbus-1.so.3`；开发头与 `wayland-protocols` 系统包：无 | `ldconfig -p`、`pkg-config` |
| wgpu-hal Wayland 支持 | vendored `wgpu-hal/src/vulkan/instance.rs` 含 `create_surface_from_wayland`、`khr::wayland_surface` | `grep` |
| Linux 仓颉运行时入口 | `InitCJRuntime`、`LoadCJLibraryWithInit`、`FiniCJRuntime` 均导出 | `llvm-nm -D` |

---

## 15. horizon-ohos 的启示

`/workspace/horizon-ohos` 是本机上另一个已在同一台 2in1 真机跑通的移植：Rust 写的 Minecraft 重写版 Horizon（`horizon/`，24+ crate），加上鸿蒙移植物（`port/`）。它和我们的处境几乎相同：自研渲染（wgpu + 打补丁的 wgpu-hal，我们的 wgpu-hal 补丁就是从它同步来的）、ArkTS + C++ 壳、窗口级输入过滤器、系统输入法。区别是它的引擎是 Rust、并且以 winit 作为平台抽象。下面按“直接照搬 / 改进后采用 / 它没做好、我们要避开”三类整理。

### 15.1 结构上的启示

| horizon 的做法 | 证据 | 对本计划的影响 |
|---|---|---|
| **上游与移植物物理分离**：`horizon/` 是上游游戏，`port/` 收全部鸿蒙移植物（`hap/`、`scripts/`、`assets/`、`docs/`） | `README.md`、`port/docs/PORTING.md` 仓库布局表 | 与我们“平台包独立”的目标一致，验证了可行性。区别：horizon 把整个 DevEco 工程（`port/hap/`）入库；我们按你的要求由 `lpack-ohos` 生成，更彻底 |
| **游戏侧只有一个平台接缝模块**：`horizon-client/src/platform/{mod,desktop,ohos}.rs`，门面签名两端一致，“唯一允许 `target_env = "ohos"` 的游戏侧模块” | `platform/mod.rs` 注释；实测 `target_env = "ohos"` 还漏在 `packs.rs`、`audio.rs`、`Cargo.toml` 共 10 处 | 说明“约定一个接缝”而没有机器检查时一定会漏。印证 §4.5 必须有 `check-platform-isolation.py` 并在 CI 强制 |
| **平台壳是独立 crate**：`crates/horizon-ohos`（staticlib，818 行）负责 C ABI、hilog、崩溃处理、资源解包、启动游戏线程 | `crates/horizon-ohos/src/{abi,shell,logging,resources}.rs` | 对应我们的 `lplatform-ohos/shell/native`。可以照搬它的职责划分：日志桥、崩溃钩子、资源解包都属于壳，不进引擎 |
| **用 winit 作为“协议”**：游戏只认 winit 的 `ApplicationHandler`/`WindowEvent`；鸿蒙是自写的 `winit-ohos` 后端（1541 行），桌面用上游 winit 的 wayland/x11/win32/appkit 后端 | `third_party/winit-ohos/src/event_loop.rs` 的 `HostEvent` 队列；`Cargo.toml` 的 `[patch.crates-io]` | 这正是“自己维护协议、平台各自实现”的模式。我们的引擎是仓颉、不能直接用 winit，所以需要 LWP；但 **Wayland 壳可以直接复用 winit-wayland**（§15.3） |
| **构建脚本无机器路径**：`port/scripts/common.sh` 从 `OHOS_SDK_HOME`/`DEVECO_SDK_HOME` 推导一切；`.cargo/config.toml` 不写路径，linker 由脚本注入 | `common.sh`、`.cargo/config.toml` 注释 | 直接照搬到 `lpack-ohos`：取代我们 `build-ohos.sh` 与 6 个中立包 `cjpm.toml` 里写死的 `/workspace/horizon-ohos/.tooling/...` |
| **构建门禁抓真实事故**：`build.sh` 用 `llvm-nm` 检查 C++ 声明的 `horizon_*` 符号必须由 Rust 导出（未导出时链接成功、首调 SIGSEGV，2026-10-25 事故）；cargo / hvigor 失败必须停（曾用旧产物装机跑了几天） | `port/scripts/build.sh` 第 1、3、5 步注释 | `lpack-ohos verify` 加同类门禁：壳声明的 `lwp_*`/`cj_app_main` 符号必须存在；每一步失败即停，绝不用上次产物 |
| **versionCode 每次安装自增**：同版本 `install -r` 不保证替换 native so | `build.sh` 第 5 步 | 我们 handoff 文档里也踩过；`lpack-ohos install` 默认自增 |

### 15.2 鸿蒙壳细节：可以直接照搬的结论

这些在 horizon 的 `PORTING.md`/`HANDOFF.md` 里有真机证据，本计划已采纳的标“已并入”，新增的标“新增”：

| 结论 | 状态 |
|---|---|
| 键盘走窗口级过滤器，不依赖组件焦点；IME 激活时过滤器返回 false；IME 不吃的键经 XComponent `.onKeyEvent` 回流 | 已并入 §6.2 |
| 过滤器只给 keyCode，`text` 按 US 布局 + Shift/CapsLock 合成；修饰键由按键集合推导；repeat 以“已按下”判定 | 已并入 §6.2。**新增**：horizon 的 `winit-ohos/src/keycodes.rs`（175 个映射，注释写明 OHOS 键码不连续、早期按 Android 排布整体错位 4 的事故）直接作为 `keycodes.tsv` OHOS 列的来源与校验数据 |
| 2in1 上窗口过滤器收不到滚轮，滚轮走 NDK 覆盖节点 `NODE_ON_AXIS`（`ContentSlot(NodeContent)` + `bindRawNode`）；同一节点的 `NODE_ON_MOUSE` 提供 rawDelta | 已并入 §6.3；**新增**：覆盖节点的挂载方式照抄 `Index.ets` 第 40、624、691 行与 `input.cpp` 第 202–232 行 |
| XComponent 鼠标回调会“饿死”数秒，只作原点校准 | 已并入 |
| **`libraryname` 形式的 XComponent 不派发 ArkUI 组件级 onMouse/onKeyEvent**；`requestFocus` 报 150003 时要用 `.id()` 属性；切后台后焦点被抢，`onPageShow` 重取 | **新增**到 §9.1 的 ArkTS 模板注意事项 |
| 外来渲染管线的 XComponent 收不到系统 vsync → 引擎自驱帧（`HostEvent::Kick`），并在队列里合并连续的 Frame/Kick | 已并入 §7.3；**新增**：LWP 的 `frame.done` 在环形队列里做同样合并（与 pointer.motion 合并同一机制） |
| musl 线程默认 128 KiB 栈，游戏线程给 16 MiB | 已并入（引擎线程统一 16 MiB） |
| Maleoon 驱动第三次 swapchain 重建必崩；`request_adapter` 在 OHOS 不可靠，改为从 HAL 直接导入适配器（`platform/ohos.rs::pick_adapter`） | 前者已并入 R11。**新增**：我们的 `lgpu` 现在用的正是 `request_adapter`（`lib.rs` 第 400 行），M4 要改成 horizon 的 HAL 导入方式 |
| `napi_call_function(env, recv, func, …)` 参数顺序；tsfn 推送 + 低频看门狗兜底，两路幂等 | 已并入 §5.4；**新增**：所有“壳 → ArkTS”请求都带看门狗重放（horizon 1500 ms），因为推送静默失效时不会报错 |
| 2in1 全屏用 `maximize(ENTER_IMMERSIVE…)`；窗口状态只能有一个控制源（EntryAbility 不设窗口模式） | 已并入 §7.4 |
| 打开文件夹/链接只能经 ArkTS `openLink`，`querySchemes` 要声明 | 已并入 §8、§9.1 |
| 时区：`OH_TimeService_GetTimeZone` 注入，不让运行时探测 `/etc/localtime` | 已并入 §8 |
| 音频走 OHAudio（只用 API 10 接口，旧设备也能加载） | 与我们 `vlc_shim.c` 已有做法一致；随 `deps/` 迁入 `lplatform-ohos` |
| 资源随 HAP 以伪装 `.so` 的 tar 入包、首启解包；沙箱与公共 Download 都不能建 symlink | **新增**：我们的首启种子、测试视频若变大，按此办法放进 `lpack-ohos`；缓存目录不得依赖 symlink |
| 远程注入（`uinput`/`uitest`）的鼠标按键进不了窗口过滤器 | 已并入；**新增**：这正是 LWP `test.inject` 的价值——远程验证不再依赖系统注入 |
| **开发用自验收通道**：游戏目录放 `.horizon-dev` 时开启带 token 的本地控制口，`hdc fport` 转发后用 `horizon-ctl` 远程 tp/look/截图；命令表生成 CLI、MCP 工具与参考文档，测试保证文档不过期 | **新增**到 M7：LWP `test` 接口在 debug 构建上额外暴露一个本地控制口（带 token），`lpack-ohos` 提供 `hdc fport` 包装；命令表单一来源、生成文档 |

### 15.3 对 Wayland 壳选型的修正

第二版计划写的是“直接用 wayland-client，不用 winit，因为离线缓存没有 winit”。这条依据不成立：

- horizon 在 `horizon/third_party/winit` vendored 了完整的 winit 0.31.0-beta.3，包括 `winit-wayland`（xdg-shell、fractional-scale、viewporter、xdg-activation、`zwp_text_input_v3` 含预编辑与 surrounding text、`drag_window`/`drag_resize_window`、`pre_present_notify`、`data_device`、主题光标）。
- 本机 `/workspace/.cargo/registry` 就是 horizon 构建留下的缓存，`cargo tree --offline -p winit --target x86_64-unknown-linux-gnu` 能完整解析。
- 自己写 wayland-client 要重做的 xkbcommon keymap/compose、按键重复、text-input-v3 状态机、configure 合并，winit-wayland 都已经做完并在 horizon 的桌面版里跑着。

因此 §9.3 改为：Wayland 壳 = 薄的 Rust 宿主 + winit-wayland，壳内只有一个翻译层（`WindowEvent` ↔ LWP）。winit 只是壳的实现细节，不进入协议，不影响“引擎只认 LWP”的原则；以后若 winit 某处不合适，可以单独替换那一部分。Wayland 线工期因此减少约 1 周。

vendored 源码的维护方式：`lgpu` 的 wgpu-hal 已经是从 horizon 同步（`tools/sync-wgpu-hal.sh`）；winit 同理，新增同步脚本，记录 horizon 的提交号，两边共用一份补丁。这两个都是上游代码，放在 `third_party/`，不受平台隔离规则限制（原则 10）。

### 15.4 horizon 没做好、我们要避开的

| 问题 | horizon 现状 | 我们的做法 |
|---|---|---|
| 壳 ↔ 引擎通道是一堆专用函数 | C++ → Rust 13 个 `horizon_on_*`/`horizon_set_*`，Rust → C++ 7 个 `horizon_platform_*`，ArkTS ↔ C++ 16 个 NAPI；每加一个能力要改三处，无版本 | LWP：一份 IDL 生成三端代码，带版本与能力位 |
| 队列是 `Mutex<VecDeque>` + `Condvar`，每次 push 加锁 | `winit-ohos/src/event_loop.rs::OhosHost::push` | 无锁环形队列 + eventfd（§5.2）；输入过滤器线程不拿锁 |
| 部分状态仍靠轮询标志兜底 | 全屏/光标“推送失败时退回 pollFullscreen 轮询标志” | 只保留看门狗重放，不保留轮询标志 |
| 引擎静态链进壳 | `libhorizon_ohos.a` 链进 `libhorizonshell.so`，壳与引擎是一个 .so | 我们的引擎是仓颉动态库，必须分开；状态型代码（`liblwp`）只能有一份，避免我们现在 lgpu 双份链接的问题（§1.5） |
| 平台 cfg 仍有泄漏 | `target_env = "ohos"` 出现在接缝模块之外 10 处 | `check-platform-isolation.py` 在 CI 强制（§4.5） |
| 鸿蒙工程整体入库 | `port/hap/`（含 `build-profile.json5`、签名占位、hvigor 配置）入库，`build.sh` 直接改写 `app.json5` 的 versionCode | 工程由 `lpack-ohos` 生成到不入库目录，版本号由生成器写入 |

---

## 16. 调试与测试方案

目标：每一步改动都有能自动跑的证据，真机只用来验证“只有真机才能验证的东西”。现在的问题是反过来的：协议、输入、窗口这类逻辑几乎只能靠真机截图、`hilog` 和写进沙箱的探针文件验证（`probe_trace.txt`、`input_log.txt`、`draw_error.txt` 等 20 多个），一次回归要构建、签名、装机、人工操作，而且签名受账号配额限制。

### 16.1 现状基线

| 项 | 现状 | 问题 |
|---|---|---|
| 单元测试 | client-next 246 个 `@Test`、cui 386 个、lgui 81 个，用 `cjpm test`；cui 测试用 `Renderer.headless()` + `UiContext` 跑控件逻辑 | 底子不错，继续用。但全部绑在 SDL/lgui 类型上，M6 删 lgui 时需要随 lbase 迁移 |
| 渲染快照 | `snapshot_harness.cj` 的 `--seed-*` 离线种子 + `--snapshot out.bmp`；CI 在 Xvfb + SDL software 下只检查文件非空 | 不比对像素，只能发现“崩了”；依赖 SDL，M6 后失效 |
| 性能打点 | `SubtitlePerf` 25 个指标（`boot_to_loop_ms`、`first_rows_ms`、`reader_turn_ms`、`peak_rss_bytes`…），`LANLU_PERF=1` 输出 | 指标有了，但没有基线和阈值，CI 不跑 |
| 鸿蒙验证 | `verify-cn.sh`（构建→装机→看进程/mock 请求/截图像素差）、`verify-window.sh`、`ohos-manual-test.md` 人工清单、`mock-backend.py` | 写死设备地址与路径；判据是“像素有变化”；输入只能物理操作（`uitest` 注入进不了窗口过滤器） |
| 原生库 | vips/rocksdb/fontkit 的 `run-host-test.sh`（含 ASAN） | 好用，保留并纳入 CI |
| lgpu | Rust 侧 0 个 `#[test]`；真机 `lgpu_selftest`（离屏读回 + bbox） | 只能真机验证 |
| 调试手段 | 文件探针 + `hilog`（会丢行）+ 截图颜色直方图 | 每次加探针都要改代码、重新装机；探针格式各写各的 |

### 16.2 测试分层

按“越往下越快、越多；越往上越慢、越少”组织。每一层都写明在哪跑、多久跑一次、谁来跑。

| 层 | 测什么 | 怎么跑 | 运行位置 | 频率 |
|---|---|---|---|---|
| T0 静态门禁 | 依赖白名单、平台隔离、ABI 只增不改、生成物无 diff、SDL 零引用、符号门禁 | `tools/check-*.py`、`lwp-gen.py --check`、`llvm-nm` | 本地 pre-commit + CI | 每次提交 |
| T1 单元测试 | 协议编解码、环形队列、键码表、修饰键/repeat 状态机、坐标换算、cui 控件逻辑、文本编辑与预编辑、业务模型 | `cjpm test`、`cargo test`、C 单测（`liblwp`） | 本地 + CI | 每次提交 |
| T2 协议契约测试 | 引擎对一段协议事件流的反应是否正确：给定 `.lwtrace` 输入，断言 cui 收到的 `UiEvent` 序列、引擎发出的请求序列 | headless 后端回放 | 本地 + CI | 每次提交 |
| T3 渲染快照 | 典型页面的像素输出 | headless 后端 + lgpu 离屏渲染（Vulkan 软件实现 lavapipe）+ 像素比对 | CI（Linux） | 每次提交 |
| T4 Wayland 集成 | 真实 Wayland 合成器 + 真实壳：建窗、configure、键鼠、IME、剪贴板 | weston headless + 虚拟输入（见 16.5） | CI（Linux） | 每次提交 |
| T5 鸿蒙集成 | 真实设备 + 真实壳：启动、协议握手、输入通道、窗口、系统服务 | `lpack-ohos test`，通过 `test` 控制口注入与断言 | 自托管设备机 | 每天 + 合并前 |
| T6 人工验收 | 只能人做的：物理键盘拼音、PasteButton、系统 picker 交互、手感（滚动、拖动窗口） | 清单 + 录制 `.lwtrace` 存证 | 真机 / 实体桌面 | 每个里程碑结束 |
| T7 性能与稳定性 | 启动时间、首屏、翻页、空闲 CPU、内存、长时运行 | `LANLU_PERF` 指标 + 阈值；冷启动 ×N、播放循环、60 分钟 soak | CI（Linux 指标）+ 设备机（夜间） | 每天 |

原则：**任何真机上发现的 bug，修复时必须先在 T1–T4 补一个能复现它的用例**（通常是一段 `.lwtrace`），做不到的要在 T5 补自动化用例，最后才是 T6 清单。这样真机问题只需要真机发现一次。

### 16.3 协议录制与回放（`.lwtrace`）

这是整套方案的核心工具，从 M1 起和协议一起建。

- **录制**：`liblwp` 内置录制开关（`LWP_TRACE=<文件>`，或运行时经 `test.trace_start/stop`）。两个方向的每条消息按收发顺序写入：头（接口、opcode、serial、`time_ns`）+ 消息体 + 引用的 blob。格式就是协议的线上格式加一个文件头（协议版本、壳名、OS、能力位），不另设格式。
- **查看**：`lwp-gen` 同时生成 `lwtrace` 命令行工具：`lwtrace dump`（人类可读，每条一行，`pointer.button id=0 btn=left down x=120.0 y=80.0 serial=42`）、`lwtrace filter --iface seat`、`lwtrace diff a b`（按语义比较，忽略时间戳）、`lwtrace stats`（每秒事件数、合并/丢弃计数、最大排队深度）。
- **回放**：headless 后端读入 `.lwtrace` 的“壳 → 引擎”部分按原时序（或加速）投递，记录引擎发出的请求与 cui 收到的 `UiEvent`，生成新的 trace。
- **用途**：
  1. 真机问题的复现与回归：用户（或测试员）在设备上开录制操作一遍，trace 带回来在 Linux 上回放；
  2. T2 契约测试的输入数据；
  3. 跨平台一致性：同一个操作在鸿蒙与 Wayland 上录的 trace，经 `lwtrace diff --semantic` 比较 cui 层事件应当一致（坐标按 scale 归一）；
  4. 性能定位：`lwtrace stats` 直接看出输入延迟、队列积压、帧请求与 `frame.done` 的间隔。
- **隐私**：trace 中的文本（IME 提交、剪贴板）默认打码为长度与字符类别，`--raw-text` 才保留原文；trace 只在 debug 构建或显式开启时写出。

### 16.4 headless 后端与渲染快照

- `lwindow.backend.headless` 实现完整的 LWP 语义（握手、能力位可配置、configure/ack、frame 节拍由测试驱动），不依赖任何平台代码，`cjpm test` 里直接用。
- 测试写法（示意）：

```cangjie
@Test
func slashFocusesSearch(): Unit {
    let h = HeadlessHarness(width: 1440, height: 900, scale: 1.0, seed: Seed.Browse)
    h.key(KeyCode.Slash, text: "/")
    h.frame()
    @Expect(h.app.focusId, "titlebar:search")
    h.expectRequest(TextInput.Enable)        // 聚焦输入框应请求输入法
}
```

- 渲染快照：headless 后端加 lgpu 离屏目标（lgpu 已有 `lgpu_capture_offscreen`），在 Linux CI 用 lavapipe 跑 Vulkan。
  - 快照集合沿用 `snapshot_harness` 的 8 个种子页面 × 3 个宽度（960/1440/1920）× 深浅两套主题；
  - 比对用“容差像素比例 + 感知差异”两个阈值，基准图入库（`tests/snapshots/`），更新基准必须单独提交并附差异图；
  - 文字渲染跨驱动可能有亚像素差异：阈值按页面单独可调，失败时输出差异热图作为 CI 附件。
- `snapshot_harness.cj` 的种子逻辑保留并改为调用 headless 后端，不再依赖 SDL dummy/x11 驱动和 Xvfb。

### 16.5 Wayland 集成测试（T4）

- 合成器：`weston --backend=headless --renderer=noop`（或 pixman），每个测试一个独立 `XDG_RUNTIME_DIR` 和 socket。
- 渲染：lavapipe（`mesa-vulkan-drivers`，horizon 的 CI 已安装同一组包）。
- 输入注入：Wayland 客户端不能给自己注入输入，所以走两条路：
  1. **weston 测试插件**：weston 自己的测试套件用 `weston-test` 模块和同名私有协议模拟指针、键盘、触摸，能覆盖 `wl_pointer/wl_keyboard/wl_touch` 到壳的真实路径。发行版 weston 包是否附带该模块**未核实**，不带就在 CI 里从源码构建 weston（M1W 第一件事确认）；
  2. 输入法：weston 实现的是 `input-method-unstable-v1`，测试里写一个最小输入法客户端发预编辑与提交，验证壳侧 `zwp_text_input_v3` 全链路。weston 对 text-input-v3 的支持版本需在 M2W 开始前确认（**未核实**）；不满足时 IME 全链路改在 T6 的 GNOME/KDE 上验证，T4 只覆盖到 winit 的 `Ime` 事件这一层；
  3. 兜底：以上都不可用时，壳提供与鸿蒙相同的 `test.inject`，从壳的输入入口注入（只绕过合成器这一跳）。
- 断言：同时检查 (a) 壳发给引擎的 LWP 事件（录制 trace）和 (b) 应用状态（经 `test` 控制口查询）。截图用壳内 lgpu 离屏抓帧，不依赖合成器截图。
- 覆盖矩阵：weston 每次提交跑；GNOME（mutter）与 KDE（kwin）放在 T6，每个 Wayland 里程碑结束时人工跑一遍同一份清单，并录 trace 存档。

### 16.6 鸿蒙设备自动化（T5）

真机自动化的障碍是：`uitest`/`uinput` 注入的鼠标按键进不了窗口过滤器（horizon-ohos 与我们都实测过），截图判定只能看“像素有没有变”。解决办法是不依赖系统注入，走协议：

- **`test` 控制口**（借鉴 horizon 的 `horizon-ctl`）：debug 构建的壳在 `127.0.0.1` 开一个带一次性 token 的 TCP 口，`lpack-ohos ctl` 自动 `hdc fport` 转发。命令：
  - `inject <lwtrace片段或单条事件>`：从壳的输入入口注入，经过与真实输入相同的协议路径（只绕过系统过滤器这一跳）；
  - `query <路径>`：查询应用状态（当前页面、焦点控件、输入框文本、窗口状态、能力位）；
  - `snapshot`：lgpu 离屏抓帧，回传 PNG（替代 `snapshot_display` + jpeg 裁剪）；
  - `trace start/stop/pull`：录制与取回 `.lwtrace`；
  - `log tail`：取引擎日志（替代会丢行的 hilog 与散落的 `*.txt`）；
  - `perf`：取 `SubtitlePerf` 指标。
- 命令表只定义一次，生成 CLI 帮助、协议 `test` 接口定义和参考文档；有测试保证文档不过期（horizon 同样做法）。
- **设备用例**写成脚本（Python），每个用例 = 启动 → 等握手 → 注入 → 查询断言 → 抓帧比对 → 取 trace。冷启动、登录（mock 后端）、书库、搜索、阅读翻页、视频播放、窗口最大化/恢复、深浅色切换作为第一批。
- **系统路径的覆盖**：注入绕过了“系统过滤器 → 壳”这一跳，所以每个里程碑的 T6 人工清单必须包含物理键鼠项，并在人工操作时开录制；录下的 trace 进入 T2 回归集。这样系统那一跳由人工验证、其后的全链路由自动化覆盖。
- **设备机**：一台自托管 runner 连接 2in1 真机，夜间跑全量 T5 + T7；合并到主分支前跑 T5 冒烟子集（约 5 分钟）。签名材料只存在设备机上（解决现在的签名配额问题：CI 产出未签名 HAP，设备机负责签名安装）。
- **mock 后端**：`mock-backend.py` 迁入 `tests/mock-backend/`，地址由参数给出，不再写死 `192.168.0.131`；Linux CI 与设备机共用。

### 16.7 调试工具

| 工具 | 解决什么 | 怎么用 |
|---|---|---|
| `lwtrace` | 看清壳与引擎之间到底发生了什么 | 见 16.3 |
| 统一日志 | 取代 20 多个探针文件和会丢行的 hilog | 引擎与壳都写同一个环形日志（`core.log` 请求 + 壳本地文件），带级别、模块、单调时间戳；`lpack-ohos ctl log tail` / Wayland 下 `--log-stderr` |
| 协议检查器 | 发现协议误用 | debug 构建的 `liblwp` 校验：未握手先发消息、未知 opcode、`size` 越界、configure 未 ack 超时、`frame.request` 未得到 `frame.done`、同一 IME `done(serial)` 之前的悬挂预编辑；违规写日志并计数，测试中视为失败 |
| 调试覆盖层 | 现场看输入与帧 | `test.overlay on`：在画面上叠加指针位置、按下的键与修饰键、IME 预编辑、拖动区矩形、帧时间曲线、队列深度（cui 绘制，平台无关） |
| 崩溃取证 | 进程直接没了、hilog 不全 | 照搬 horizon：壳与引擎都装崩溃钩子，崩溃前把最近 N 条协议消息和日志写入沙箱 `crash/` 目录；下次启动时经 `test` 接口取回 |
| 能力位模拟 | 在 Linux 上测“设备不支持某能力”的降级路径 | headless 与 Wayland 壳支持 `--disable-cap cursor_shapes,ime_preedit…` |
| 构建门禁报告 | 少一个导出符号、少一个依赖库 | `lpack-ohos verify` 输出依赖闭包、`DT_NEEDED`、导出符号、HAP 内容清单，失败即停 |

现有探针的处理：`LANLU_PROBE_*`、`probe_trace.txt`、`input_log.txt`、`draw_error.txt`、`draw_skip.txt`、`lgpu_textures.txt`、`cap_step.txt`、`snap_log.txt`、`poll_log.txt` 等，在 M5 随 `test` 接口上线后全部删除；`draw_error` 一类“不能让单个控件异常拖垮整帧”的保护保留，但改为写统一日志。

### 16.8 性能与稳定性（T7）

- 指标沿用 `SubtitlePerf`，新增协议层指标：输入事件从壳收到到 cui 分发的延迟（p50/p99）、`frame.request` → `frame.done` 间隔、队列最大深度、合并/丢弃计数、空闲时引擎线程 CPU。
- 每个指标在 `tests/perf/baseline-<平台>.toml` 记录基线与阈值；CI（Linux headless）与设备机（夜间）超过阈值即失败或报警。
- 第一批阈值（以现状为基线，M1 后重新校准）：空闲引擎线程 CPU 接近 0（现状 4 ms 轮询）；输入延迟 p99 < 1 帧；冷启动 `boot_to_loop_ms`、`first_rows_ms` 不劣于现状；60 分钟浏览 + 播放 soak RSS 无持续增长（现状约 263–271 MB，见 ohos-port-acceptance.md）；冷启动 ×8、播放开关 ×5 零崩溃（沿用现有压力测试）。
- 驱动风险专项：连续 resize 20 次、切后台/前台 20 次、深浅色切换 20 次（针对 Maleoon 驱动 swapchain 重建崩溃，R11）。

### 16.9 每个里程碑的“完成定义”

一个里程碑只有同时满足以下条件才算完成，否则不进入下一个依赖它的里程碑：

1. 该里程碑列出的验收项全部有对应的自动化用例（T1–T5），并在 CI/设备机上通过；只能人工验证的项在 T6 清单中勾选，且附人工操作时录制的 `.lwtrace`。
2. T0 门禁通过，违规数不高于上一个里程碑（M6 起为零）。
3. 删除清单（§11）中计划在本里程碑删除的旧通道已经删除，并有 T0 规则阻止它被加回来（例如文件桥文件名、旧 NAPI 函数名进入禁用标识表）。
4. 性能指标不劣于基线（T7）。
5. 文档更新：协议参考文档自动生成无 diff；`PORTING`/handoff 文档记录本里程碑新发现的设备怪癖和对应的回归用例名。

各里程碑新增的测试重点：

| 里程碑 | 必须新增的测试 |
|---|---|
| M0 | T0 两个守卫进 CI；现有 `cjpm test` 与原生库 host 测试进 CI；录制第一份人工 trace 作为基线（用现有文件桥临时实现一个最小录制器） |
| M1 | `liblwp` C 单测（多生产者压测、满队列合并、未知消息跳过、版本协商、blob 生命周期）；编解码往返测试（每个 IDL 消息自动生成）；headless 后端 + `lwtrace` 工具；协议检查器；空闲 CPU 指标 |
| M2 / M2W | 键码表完整性（每个 OHOS/evdev 码都有映射或显式标为忽略）；修饰键/repeat 状态机；按钮/滚轮/触摸兼容鼠标的契约测试；§1.3 每条缺陷（K1–K5、M1–M5）各一个回归用例 |
| M3 / M2W | IME 契约测试：拼音组合（预编辑更新、选词提交、删除、光标移动）、`done(serial)` 原子性、焦点切换时 disable；weston 输入法全链路 |
| M4 / M3W | configure/ack 合并、resize 后重排快照、拖动区命中、最大化/恢复状态往返、切后台停帧；resize/前后台压力测试 |
| M5 / M3W | 剪贴板（含“只在 Ctrl+V 后 2 秒读一次”的规则模拟）、对话框请求 id 匹配与超时、配置变化下发、路径；所有探针文件不再出现的 T0 规则 |
| M6 | 快照基线迁移到 lbase/headless；全仓 SDL 零引用；HAP 内容清单无 SDL |
| M7 | 跨平台 trace 一致性测试；性能基线定稿；设备机夜间流水线稳定运行 1 周 |

### 16.10 落地顺序与工期影响

- 测试设施不是独立阶段，按上表随各里程碑建设；额外工作量主要在三处：`lwtrace` 工具与 headless 后端（M1 内，约 +3 天）、lavapipe 渲染快照（M1W 内，约 +2 天）、设备控制口与设备机流水线（M4/M5 内，约 +4 天）。总工期相应增加约 2 周：单人约 15–16 周，两人并行约 10–11 周。
- 设备机与签名：在 M0 确定一台常驻设备与签名材料存放位置；在此之前 T5 以“开发者本机 + 手动触发 `lpack-ohos test`”方式运行。
