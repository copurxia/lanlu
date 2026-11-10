# client-next 增加 OHOS（鸿蒙）目标 —— 可行性调研与落地方案

- 调研日期：2026-11-08
- 结论先行：**可行**。本机已端到端打通并部分真机验证：(1) 仓颉交叉编译出 aarch64-linux-ohos 共享库；(2) @C 导出可被 NAPI/ArkTS 调用；(3) 由脚本**生成**鸿蒙 HAP 工程并打包出未签名/已签名 HAP，且**已签名 HAP 已在 2in1 真机安装并运行**（hilog 打印 hello-from-cjcore / add=9）。真正的工作量与风险不在“能不能编译打包”，而在 **UI 层（CangjieGUI/SDL → OHOS）**、**原生依赖交叉编译（vips/vlc/rocksdb/ffmpeg/libass）**、**文字/CJK 排版**、**IME** 与 **线程模型**。
- 推荐路线：把 client-next 拆成“纯仓颉核心 + platform 抽象 + 后端”；OHOS 后端、ArkTS 壳与 HAP 全部放**生成目录/独立仓**，主仓不出现任何鸿蒙工程；对 OHOS 的 C 接口绑定以 packages/ohos_* 形式沉淀。

---

## 0. 结论速览（TL;DR）

| 问题 | 结论 | 证据 |
|---|---|---|
| 仓颉是否有 OHOS 编译目标？ | **有**。官方 cjv target add ohos 提供 sts-1.2.0-linux-x64-ohos，含 linux_ohos_aarch64_cjnative 标准库与运行时 | 3.1 |
| 能否交叉编译出可用 .so？ | **能**。cjc --target=aarch64-linux-ohos 产出 aarch64 ELF；cjpm build --target aarch64-linux-ohos 亦然 | 3.2 / 3.3 |
| 仓颉函数能否被 ArkTS/NAPI 调用？ | **能**。@C 导出 cj_add/cj_hello；经 NAPI shim 或 ArkTS import 直接调用（真机已跑通 shim 调用） | 3.2 / 3.4 |
| 能否“自己生成鸿蒙工程再打包”？ | **能**。generate.sh（devecocli create + 模板 + hvigor assembleHap）产出未签名/已签名 HAP；PoC 中 ArkTS 成功 import 原生模块并调用，signed HAP 已装到 2in1 真机运行 | 3.4 / 6 |
| ArkTS 能否隔离、不污染主项目？ | **能**。所有 ArkTS/module.json5/签名/HAP 脚手架都在生成目录；主仓只交出编译好的 .so（+ 可选 ArkTS 模板） | 5 / 6 |
| 官方是否有“仓颉版 web-sys”式的绑定？ | **有**：ohos.ark_interop + @Interop[ArkTS] 声明式宏自动生成 Index.d.ts 与互操作层；另有 kit.ArkUI 纯仓颉 ArkUI 框架 | 2 / 4 |
| UI 能否复用现有 CangjieGUI/SDL？ | **有希望**：SDL3 已官方移植 HarmonyOS（并入 SDL 3.6） | 7 |
| 当前最大的不确定性 | SDL3-OHOS 与 CangjieGUI 的适配；原生依赖交叉编译；文字/CJK 与 IME | 7 / 8 |

---

## 1. 背景与需求拆解

当前仓 lanlu（仓颉全栈）。其中：

- client-next/：仓颉写的原生桌面客户端，UI 基于 **CangjieGUI（cui）**，cui 又包 **SDL3**；业务/网络/存储/图片/媒体都在仓颉侧（见 client-next/README.md、client-next/src/main.cj）。
- packages/：大量本地 FFI 包（webview、libvlc_ffi、libavformat_ffi、libass_ffi、rocksdb_ffi、qwest、fontkit_ffi 等），模式统一为“仓颉 foreign func + 原生静态/动态库”。

需求（用户原话拆解）：

1. **参考 Rust 的 web-sys**，给 client-next 增加 OHOS 目标；
2. **隔离 ArkTS 代码**，不要让它成为主项目的一部分；
3. **尽可能建立 cj（仓颉）绑定，放到 packages 里**；
4. **甚至用自己生成鸿蒙工程再打包**，而不是把一整个鸿蒙工程直接嵌进主仓。

对应到本方案：Web-sys 的设计精髓（**生成式、独立的 host-API 绑定 + 与 app 解耦**）映射到仓颉/OHOS 上；ArkTS/HAP 采用“生成 + 隔离”；C 侧能力以 packages/ohos_* 绑定包沉淀；最终由一条脚本把“交叉编译好的仓颉 .so + 一套模板”装配成 HAP。

---

## 2. “参考 Rust web-sys” 的正确映射

### 2.1 web-sys 到底是什么

- web-sys 是 wasm-bindgen 生态里**用工具从 WebIDL 自动生成**的一套 Rust 绑定，覆盖 DOM/Canvas/WebGL/WebAudio 等浏览器 API；它与业务 crate **分离**，业务只依赖它，就能以近乎原生方式调用宿主（浏览器）能力。
- 关键性质：**(a) 绑定由宿主接口自动生成；(b) 绑定是独立 crate；(c) 业务代码不感知宿主实现细节。**

### 2.2 注意：本项目不是 wasm 场景

Rust 的 web-sys 之所以成立，是因为 Rust 能编译成 **wasm** 跑在浏览器里，由宿主注入 Web API。**仓颉这里没有 wasm 目标**（cjv target list 只有 android/ohos，cjc 面向原生）。所以“参考 web-sys”应是**架构思想上的对标**，而不是“把仓颉编译成 wasm 塞进 ArkWeb”。即：把 OHOS 原生运行时当作“宿主”，为它做一套**生成式、独立的仓颉绑定层**，业务/引擎编译成 native .so 由 ArkTS 进程加载。

> 若未来确要“ArkWeb + wasm”路线，那是另一条独立技术线（需仓颉 wasm 后端，目前不具备），不在本次范围。

### 2.3 映射表

| web-sys 概念 | OHOS / 仓颉 对应物 | 说明 |
|---|---|---|
| WebIDL（宿主接口定义） | OHOS SDK 的 .d.ts / C 头（native/sysroot） | 宿主 API 的权威定义来源 |
| wasm-bindgen（生成器） | 官方 @Interop[ArkTS] 宏 + ohos.ark_interop；或自研脚本按头文件生成 foreign func | 前者最接近 wasm-bindgen（自动出 Index.d.ts + 互操作层） |
| web-sys（生成的绑定 crate） | packages/ohos_arkui、packages/ohos_napi、packages/ohos_window… 等绑定包 | 独立、可复用、与 app 解耦 |
| 浏览器宿主注入 Web API | ArkTS 进程 dlopen 原生 .so；NAPI 提供 JS↔native 通道 | 仓颉 .so 是“被加载方” |
| app 只写业务 | client-next 核心只写业务；平台差异收口到 backend | 见 5 |

### 2.4 官方“生成式互操作”的三个机制（可直接用）

1. **@Interop[ArkTS] 声明式互操作宏**：在仓颉函数/类/接口/枚举上加注解，DevEco “Generate… > Cangjie-ArkTS Interop API” 自动生成 Index.d.ts 与 ark_interop_api.d.ts，ArkTS 侧 import 直接调用。**这就是“仓颉版 web-sys 生成器”**（源码：docs_cangjie/.../FFI/cangjie-arkts/interoperability_macro.md）。
2. **ohos.ark_interop 底层库**：JSContext / JSCallInfo / JSValue / JSModule.registerModule/registerFunc / SharedObject —— 相当于“仓颉版 NAPI”，手写注册导出亦可。
3. **kit.ArkUI（arkui_arkui_cangjie_wrapper）+ @HybridComponentEntry / CJHybridComponent**：仓颉可直接用声明式写 ArkUI 组件，或作为 NodeContainer 内容嵌入 ArkTS 页面（官方“混合开发”）。

> 注意：ohos.ark_interop / kit.ArkUI 随 **DevEco 的仓颉 SDK** 发布（DEVECO_CANGJIE_PATH），**不在** cjv 的 OHOS 交叉目标里（本机验证：交叉目标仅含 std）。详见 3.1、4 的取舍。

---

## 3. 可行性实证（本机端到端，2026-11-08）

> 明细见 .research-ohos/toolchain/toolchain-findings.md 与 .research-ohos/hap/hap-recipe.md；以下为要点。

### 3.1 安装仓颉 OHOS 交叉目标

```bash
/workspace/bin/cjv target add ohos --toolchain sts-1.2.0
# => Toolchain 'sts-1.2.0-linux-x64-ohos' installed successfully
/workspace/bin/cjv target list --toolchain sts-1.2.0 --json
# => {"targets":[{"name":"android","installed":false},{"name":"ohos","installed":true}]}
```

- SDK 目录：/workspace/.cjv/toolchains/sts-1.2.0-linux-x64-ohos
- 模块：modules/linux_ohos_aarch64_cjnative、modules/linux_ohos_x86_64_cjnative —— **仅 std**，无 ohos.ark_interop。
- 运行时：runtime/lib/linux_ohos_aarch64_cjnative/（libcangjie-runtime.so、libcangjie-std-*.so、libboundscheck.so 等）。
- 链接用 OHOS sysroot：/workspace/horizon-ohos/.tooling/sdk26/clt/command-line-tools/sdk/default/openharmony/native/sysroot。

### 3.2 裸 cjc 交叉编译 + @C 导出

```cangjie
package probe
@C public func cj_add(a: Int64, b: Int64): Int64 { a + b }
```

```bash
cjc --target=aarch64-linux-ohos --output-type=dylib --sysroot=<OHOS sysroot> -L <sysroot>/usr/lib/aarch64-linux-ohos -o libexp.so exp.cj
# 注意：cjc 驱动把 crti.o/crtn.o 当裸文件名交给 ld.lld，
#       需预先把 <sysroot>/usr/lib/aarch64-linux-ohos/{crti.o,crtn.o} 放到 cwd（或 -B 目录）。
```

结果：libexp.so 为 aarch64 ELF；nm -D 可见 T cj_add、T cj_hello。

### 3.3 cjpm 工程化交叉构建（最贴近 client-next 用法）

```toml
[package]
cjc-version = "1.2.0"
name = "cjpmprobe"
version = "0.1.0"
output-type = "dynamic"

[target.aarch64-linux-ohos]
compile-option = "--sysroot=<OHOS sysroot>"
link-option = "-L <sysroot>/usr/lib/aarch64-linux-ohos"
```

```bash
CANGJIE_HOME=/workspace/.cjv/toolchains/sts-1.2.0-linux-x64-ohos LD_LIBRARY_PATH=/workspace/.cjv/toolchains/sts-1.2.0/runtime/lib/linux_x86_64_cjnative /workspace/.cjv/toolchains/sts-1.2.0/tools/bin/cjpm build --target aarch64-linux-ohos
# => cjpm build success
# 产物： target/aarch64-linux-ohos/release/cjpmprobe/libcjpmprobe.so  (aarch64 ELF)
```

- 依赖：NEEDED libcangjie-runtime.so / libcangjie-std-core.so / libboundscheck.so / libc.so。这些仓颉运行时 .so **必须随 HAP 打进 libs/arm64-v8a/**，或用 --static-std/--static 静态化（待验证收益）。

### 3.4 生成式 HAP 打包 + NAPI 桥（PoC，含真机）

由 generate.sh（.research-ohos/hap/scaffold/）驱动，两种模式：

- **direct**：预编译 .so 本身就是 NAPI 模块（导出 napi_module_register，nm_modname=模块名），直接放 entry/libs/arm64-v8a/，ArkTS import 加载。
- **shim**：预编译 .so 只导出普通 C ABI，脚本生成 cpp/napi_init.cpp（NAPI 注册）+ CMakeLists.txt（链接预编译 .so 与 libace_napi.z.so），hvigor 编出 shim .so 并把两者一起打进 HAP。

PoC 产物（.research-ohos/hap/work/）：

| 目录 | 内容 | 结果 |
|---|---|---|
| HelloHap | devecocli 原生脚手架 | entry-default-unsigned.hap（约 22 KB） |
| DemoHap | ArkTS import “liblanludemo.so”，调用 demo.add(2,3) | unsigned HAP（约 27 KB），已打包 liblanludemo.so |
| CmakeHap | NAPI shim 链接预编译 libcjcore.so，ArkTS 调 cmdemo.hello()/add() | **unsigned + signed**；signed 已安装并在 2in1 真机运行，hilog: “CMDEMO: RESULT hello=hello-from-cjcore add=9” |
| GenShim | 用 generate.sh --mode shim 完整构建 | unsigned HAP，含 libcangjie.so + libcjcore.so |

关键命令（DEVECO_CLI_CLT_PATH 指向本机 CLT，另需 JAVA_HOME）：

```bash
export DEVECO_CLI_CLT_PATH=/workspace/horizon-ohos/.tooling/sdk26/clt/command-line-tools
export JAVA_HOME=/workspace/horizon-ohos/.tooling/jdk17
export PATH=$JAVA_HOME/bin:/workspace/bin:$PATH
devecocli create --app-name HelloHap --project-path ./HelloHap --api-level 23 --device-types phone
cd HelloHap && devecocli build --assemble-type assembleHap
# 产物： entry/build/default/outputs/default/entry-default-unsigned.hap
# 签名： devecocli signature generate --type debug  ->  entry-default-signed.hap
```

> 说明：CmakeHap 的 libcjcore.so 由一段**纯 C**（nativetest/cjcore.c 提供 cj_hello/cj_add）编译，用于隔离验证“NAPI + HAP 打包 + 真机运行”链路；仓颉这一侧我已用**真实仓颉 .so**（3.2/3.3）验证其 @C ABI 完全一致。两者拼起来即为“真实仓颉 .so → NAPI → HAP → 真机”的完整链路（唯一尚未联调的是“真实仓颉 .so 装进 HAP 后真机运行”这最后一步）。

---

## 4. 集成模型与互操作（三选一 + 推荐）

| 模型 | 做法 | 优点 | 代价/前提 |
|---|---|---|---|
| **A. 仓颉 .so + NAPI 桥**（本机已证到真机） | 仓颉编成 .so（@C 导出或直接绑 napi.h 自注册），由 C/C++ NAPI shim 或 ArkTS 直接 import 加载；ArkTS 仅做窗口/输入/生命周期宿主 | 自包含、可完全脚本化生成、与“隔离 ArkTS / 自己生成 HAP”完全契合；只用 cjv 交叉工具链 | 需自己维护绑定与 shim；JS 值转换需手写 |
| **B. 官方 ohos.ark_interop + @Interop 宏** | 仓颉加 @Interop[ArkTS]，自动生成 Index.d.ts+互操作层，ArkTS 直接 import | 最接近 web-sys 的“生成式”体验，DX 最好 | 依赖 **DevEco 仓颉 SDK**；需在（生成的）鸿蒙工程里挂“仓颉模块”，构建走 hvigor 仓颉插件 |
| **C. 纯 ArkTS UI + 仓颉逻辑** | UI 全用 ArkTS/ArkUI 重写，仓颉只做逻辑经 NAPI 暴露 | UI 最“原生” | UI 重写量最大；偏离“复用现有 CangjieGUI” |

**推荐**：**A 作为 v1 主干**（本机已证、完全满足“隔离 + 生成 + 绑定沉淀”），**B 作为 DX 升级**（待接入 DevEco 仓颉 SDK 后，用手写 Index.d.ts + shim 的流程替换为 @Interop 自动生成）。**C 仅当产品明确要求“原生 ArkUI 观感”时**再考虑。

补充两种“仓颉侧 UI”选择（与 7 呼应）：
- **复用 CangjieGUI/SDL**：SDL3 官方已支持 HarmonyOS（见 7），UI 代码基本不动，最省。
- **仓颉原生 ArkUI**（kit.ArkUI）：可纯仓颉或 @HybridComponentEntry + CJHybridComponent 混入 ArkTS 页面，观感原生，但需把现有 CangjieGUI UI 重写为 ArkUI 声明式。

---
## 5. 架构：分层改造与目录布局（“绑定进 packages、鸿蒙工程隔离/生成”）

### 5.1 现状：UI 与 SDL 深度耦合

client-next/src/main.cj 直接 import cui.*，创建 SDL 窗口/渲染器、事件循环、DRAG 区域、IME 锚点、--snapshot 无头装置；ui/* 直接用 cui 的 Renderer/Texture/TextField。视频与 HTML 已经是“离屏 RGBA（像素进像素出）”，这是好消息——真正要替换的集中在 **cui/SDL 这层**（窗口、渲染器+文字、事件循环、IME、对话框、路径）。逐条 file:line 见 .research-ohos/seams/clientnext-seams.md。

### 5.2 关键平台缝（seam）清单（节选）

| 域 | 桌面机制（file:line） | OHOS 替代 |
|---|---|---|
| 入口/主循环/快照 | main.cj:89-307；cui desktop_app.cj:151-247（SDL_WaitEventTimeout、脏帧跳过、captureBmp --snapshot） | 自驱帧循环 + XComponent/vsync |
| 窗口/渲染器/DPI/vsync | main.cj:190-229；cui sdl/window.cj:87-160；renderer.cj:232-291（超采样离屏） | OH_NativeWindow + EGL/GLES + FBO |
| 输入 | cui sdl/events.cj:38-109；desktop_app.cj:330-378；触摸被当鼠标；Key.RawScancode 泄漏 SDL 码 | NAPI/window filter → ArkTS/ndk 触摸键盘 |
| IME/焦点 | window.cj:150-153,191-194；desktop_app.cj:427-440；TextField text_field.cj:225-239 | ArkUI IME 代理编辑器 + caret 锚点 |
| 渲染/纹理 | renderer.cj primitives + textWidth/Height/text(809-890)；texture.cj:334-487；captureTextureGpu 678-726 | GLES 纹理上传 / OH_Pixelmap |
| 图片管线 | vips_decode.cj:101-208 → stageNativePixelImage；image_cache.cj | 交叉编译 vips 或 ImageSource/AVIF 解码 |
| 媒体视频 | libvlc_ffi set_callbacks 离屏 RGBA playback_model.cj:900-948；reader_stage 合字幕 1046-1139 | AVPlayer/VideoDecoder + AudioRenderer（无 libVLC） |
| HTML | Blitz 离屏 webview；html_page_model.cj:205-295,514-564 | 交叉编译 Rust 或用 ArkUI Web |
| 路径/存储 | 全部由 getVariable("HOME")：settings.cj:264-296；offline_cache.cj:53-56；subtitle_cache.cj:13-16；RocksDB | ability filesDir/cacheDir |
| 网络/TLS/SSE | qwest 纯 std.net + stdx TLS 根 conn.cj:44-86；SSE model.cj:5669-5752 | 注意 OHOS CA 根 |
| 线程 | 2/6/4/1 worker 池 net/worker.cj:44-99；onResult→requestWake | UI 线程仅属 ArkUI，需 NAPI/uv_async 转投 |

### 5.3 目标分层

```text
client-next/
├── src/                     # 纯仓颉核心（绝大部分保持不动）
│   ├── app/ net/ storage/ i18n/ img/ ui/ theme.cj main.cj
│   └── platform/            # 【新增】只放接口：Renderer/Texture/Window/AppRuntime/
│                            #   PlatformPaths/SystemService/ImageDecoder/MediaOutput/
│                            #   HtmlRenderService/PlatformBackend（同一套类型名，ui/* 无感）
packages/
├── platform-sdl/            # 【新增】把今天的 cui/SDL 实现挪到此（桌面后端）
├── ohos_napi/               # 【新增】napi.h 的 foreign func 绑定 + 模块注册
├── ohos_window/ ohos_egl/   # 【新增】NativeWindow/EGL/GLES 绑定
├── ohos_input/ ohos_ime/    # 【新增】输入/IME 绑定
├── ohos_media/              # 【新增】AVPlayer/VideoDecoder/AudioRenderer 绑定
├── ohos_pixelmap/           # 【新增】图片解码/像素图
├── ohos_paths/              # 【新增】沙箱路径（filesDir/cacheDir 由 ArkTS 注入）
└── ohos_arkui/              # 【可选】ArkUI NDK / kit.ArkUI 绑定（模型 B/C 用）
client-next-ohos/            # 【新增/可独立仓】OHOS 引擎包：组合核心 + ohos_* 后端，
                             #   output-type=dynamic，@C 导出引擎入口
port-ohos/ (生成物，不入主仓)  # 由 generate.sh 生成：ArkTS 页面 + cpp NAPI shim +
                             #   module.json5/build-profile + 签名 + HAP
```

- **纯仓颉留核心**：app/* 模型、net/*（dto/api/sse/worker/stores）、storage/*、i18n、theme、image_cache、ui/*、main.cj（若 platform 重新导出同名类型，几乎不改）。
- **后端专属**：窗口/循环/DPI/vsync、渲染器+文字+纹理、输入/IME/光标/剪贴板、对话框/拖拽/窗口控制/语言/显示/字体/路径、媒体输出、HTML 引擎、图片解码。
- **后端选择**：编译期（一个二进制一个后端；cjpm 按 target 依赖 + 一个极小的 platform_select.cj 切换）。
- **绑定沉淀**：对 OHOS 的 C 接口以 packages/ohos_* 承载（正是用户要的“cj 绑定放 packages”）；这些包只依赖 native 头/库，可被任何 OHOS 仓颉工程复用。

---

## 6. 构建与打包流水线（生成式 HAP，主仓零鸿蒙工程）

```text
client-next (仓颉核心 + ohos_* 后端)
      │  cjpm build --target aarch64-linux-ohos
      ▼
lib<engine>.so  (+ libcangjie-runtime/std/boundscheck.so 或静态化)
      │  generate.sh（devecocli create 脚手架 + 模板渲染）
      ▼
port-ohos/  (throwaway)  entry/libs/arm64-v8a/lib<engine>.so + cpp/napi_init.cpp +
                          CMakeLists.txt + ets/pages/Index.ets + types/lib<mod>/Index.d.ts
      │  devecocli build --assemble-type assembleHap   (可选 signature generate)
      ▼
entry-default-unsigned.hap  /  entry-default-signed.hap
      │  hdc install -r -g + aa start
      ▼
真机运行
```

- generate.sh 已验证：direct / shim 两种模式；--lib/--module-name/--dts/--page demo|xcomponent/--sign/--install/--run 等参数；输入一个预编译 .so 即可产出完整 HAP，并打印 HAP 内打包的 .so 列表。
- **隔离**：所有 ArkTS、module.json5、build-profile、cpp shim、签名材料都在 OUT 生成目录；主仓只提交“仓颉源码 + 绑定包 + generate.sh 模板”。建议把 port-ohos/（或 build/）加入 .gitignore，或把整个 OHOS 壳放独立仓（与 horizon-ohos 的 port/ 同做法）。
- **CI 草案**：job 依次 (1) cjv 安装 ohos target；(2) cjpm 交叉构建 lib<engine>.so；(3) 用 CLT+JDK+node/pnpm 跑 generate.sh 出未签名 HAP（Push/PR 产物）；(4) tag 时 signature generate 出已签名 HAP 并 Release。
- **已记录的坑（必须写进 CI/脚本）**：构建需要 JAVA_HOME（CLT 不带 JRE，否则 “No Java runtime found”）；ohpm/pnpm 需联网装 hypium/hamock；签名受代理环境变量干扰（HTTPS_PROXY 等会触发 “Invalid proxy authorization / ERR_BAD_OPTION”，需 unset 代理 + no_proxy='*'，且需 auth login + 连接设备）；重装要自增 versionCode 才会替换包内 .so。

---

## 7. UI / 渲染策略（关键难点）

这是整个移植里**唯一无法只靠“绑定 + 打包”解决**的部分，必须做技术选型。三条路：

1. **复用 CangjieGUI/SDL（推荐先做 PoC）**：SDL3 已在 2026-09 官方合入 HarmonyOS/OpenHarmony 移植（合并进 SDL 3.6，随附完整的 openharmony-project/ 脚手架与 docs/README-harmonyos.md）。因此理论上可交叉编译 SDL3（OHOS 后端）→ CangjieGUI 链接之 → 现有 UI 代码基本不改，仅补输入/IME/路径适配。**风险**：CangjieGUI 是私有 fork，其对 SDL 的用法（超采样离屏、GPU 纹理、drag region、text input area）需逐项在 OHOS 后端验证；文字渲染（CJK 排版/度量）与性能是最大不确定项。
2. **仓颉原生 ArkUI（kit.ArkUI）**：用官方 arkui_arkui_cangjie_wrapper 的声明式 UI（或 @HybridComponentEntry 混入 ArkTS 页面）。观感最原生、最“鸿蒙”，但要把现有 CangjieGUI 的五个页面全部重写为 ArkUI 声明式 —— 工作量最大，且依赖 DevEco 仓颉 SDK。
3. **离屏渲染 + 上屏**：CangjieGUI 渲染到 RGBA（已有 captureTextureGpu 能力），再经 XComponent 贴图。最快能“先看到画面”，但交互/滚动/输入延迟与功耗较差，只适合过渡验证。

**建议**：先用路线 1 做 PoC（复用现有渲染器，最小改动），同时用路线 3 作为“先把画面跑起来”的兜底；只有当产品明确要求原生观感且愿意重写 UI 时，才投入路线 2。

---

## 8. 风险与缓解

| # | 风险 | 影响 | 缓解 |
|---|---|---|---|
| R1 | 文字/CJK 排版与度量不齐 | 全站 UI 观感/布局错位 | 优先验证字体加载与 textWidth/textHeight；必要时内嵌字体 + 自绘度量 |
| R2 | 无 libVLC on OHOS，阅读器需要 RGBA 帧做字幕合成 | 视频/字幕功能不可用 | 改用 AVPlayer/VideoDecoder 出 RGBA + AudioRenderer；libass 仍可离屏合成 |
| R3 | 原生依赖交叉编译（vips/glib、rocksdb、ffmpeg、libass、freetype、Rust Blitz/fontkit） | 编译链爆炸 | 分阶段：先纯仓颉核心（net/storage/i18n）跑通，再逐个替换原生依赖 |
| R4 | IME/CJK 键盘 + caret 锚点 | 中文输入不可用 | NAPI window key filter + ArkUI IME 代理（参考 horizon-ohos 设备怪癖清单） |
| R5 | ArkUI UI 线程 vs 阻塞式引擎循环 | 卡死/ANR | 引擎跑独立线程，UI 事件经 NAPI/uv_async 转投；surface 生命周期回调驱动 |
| R6 | TLS CA 根缺失 | https 请求失败 | 注入 OHOS 系统根证书；qwest/stdx x509 适配 |
| R7 | RocksDB/路径落沙箱 | 存储不可写 | 由 ArkTS 注入 filesDir/cacheDir，PlatformPaths 适配 |
| R8 | RawScancode/hover 泄漏、触摸当鼠标 | 输入错乱 | 输入层重写键码映射与指针语义 |
| R9 | 真机未做“真实仓颉 .so 进 HAP”联调 | 最后一步未证 | 作为 Phase 1 的验收项 |

---

## 9. 分阶段实施计划

| 阶段 | 目标 | 产出 | 验收 |
|---|---|---|---|
| P0（已完成） | 证明“能编译/能加载/能打包” | toolchain-findings、hap-recipe、generate.sh；真机跑通 shim HAP | 本文 3.1–3.4 |
| P1 | 打通“真实仓颉 .so 进 HAP 真机跑” | client-next-ohos 最小包（只导出 1~2 个 @C），generate.sh 生成并装机 | 真机 hilog 显示仓颉返回 |
| P2 | 抽 platform 抽象 + 桌面绿 | src/platform 接口；platform-sdl 承接现有实现；桌面 CI 全绿 | 桌面构建/测试/快照不变 |
| P3 | 核心能力上 OHOS | packages/ohos_paths、net（qwest+TLS）、storage 适配；图片用 ImageSource/AVIF 或交叉 vips | 书库列表/封面/登录在真机可用 |
| P4 | UI 渲染 + 输入/IME | 选路线 1 或 3；阅读器翻页；中文输入 | 主要页面真机可用 |
| P5 | 媒体 + 字幕 | AVPlayer/VideoDecoder + AudioRenderer + libass 合成 | 视频/字幕可用 |
| P6 | 打包/签名/发布 | CI 出 unsigned/signed HAP；AGC 上架流程 | 可分发 |

---

## 10. 结论与建议

1. **技术可行性成立**：仓颉官方有 OHOS 交叉目标；本机已证 cjc/cjpm 交叉编译、@C 导出、NAPI 加载、生成式 HAP 打包，并已把一个 signed HAP 装到 2in1 真机运行。
2. **用户设想的四点全部可行且正是最佳实践**：参考 web-sys 的“生成式独立绑定”思想；ArkTS 完全隔离在生成目录；C 接口绑定沉淀到 packages/ohos_*；用 generate.sh 自己生成鸿蒙工程再打包，而不是把鸿蒙工程塞进主仓。
3. **真正的成本在 UI 与原生依赖**，不在编译打包。建议以“P0→P1→P2→P3→P4”小步快跑，每步都有可验收产物；UI 优先尝试复用 SDL3-OHOS 以最大化复用现有代码。
4. **官方生成式互操作（@Interop/ohos.ark_interop、kit.ArkUI）是 web-sys 的正统对应**，待接入 DevEco 仓颉 SDK 后可把手写 shim/Index.d.ts 升级为自动生成，进一步降低维护成本。

---

## 附录 A：本次调研证据清单

- .research-ohos/toolchain/toolchain-findings.md —— 交叉工具链安装、cjc/cjpm 交叉编译、@C 导出、运行时依赖。
- .research-ohos/seams/clientnext-seams.md —— 979 行平台缝清单（S1–S17，file:line）+ platform 接口草图 + 迁移/风险。
- .research-ohos/hap/hap-recipe.md（316 行）+ .research-ohos/hap/scaffold/（generate.sh + 6 模板）—— 生成式 HAP 打包 recipe 与生成器。
- .research-ohos/hap/work/{HelloHap,DemoHap,CmakeHap,GenShim}/ —— 实测工程与 HAP 产物（含 signed HAP 真机运行证据）。
- .research-ohos/probe/、.research-ohos/cjpmprobe/ —— 最小 cjc / cjpm 交叉编译实证产物（aarch64 ELF）。

## 附录 B：关键参考链接

- 仓颉-ArkTS 声明式互操作宏：https://developer.huawei.com/consumer/cn/doc/cangjie-guides-V5/interoperability_macro-V5
- 仓颉-ArkTS 互操作库：https://developer.huawei.com/consumer/cn/doc/cangjie-guides-V5/interoperability_lib-V5
- ArkTS 侧使用互操作代码（第三方 .so 放 libs/arm64-v8a 直接 import）：docs_cangjie/.../FFI/cangjie-arkts/arkts_import_cangjie.md
- 混合开发（@HybridComponentEntry / CJHybridComponent）：docs_cangjie/.../arkui-cj/cj-appendix-hybrid.md
- 仓颉 UI on ArkUI：https://github.com/openharmony/arkui_arkui_cangjie_wrapper
- SDL3 HarmonyOS 移植（并入 SDL 3.6）：https://github.com/libsdl-org/SDL/commit/a24429c192cfee5ae92697f12f219cad27635fb4
- wasm-bindgen / web-sys 生成机制：https://rustwasm.github.io/docs/wasm-bindgen/contributing/web-sys/overview.html
- 本仓同类移植先例（Rust→OHOS，含 port/ 隔离与设备怪癖清单）：/workspace/horizon-ohos/port/docs/PORTING.md、/workspace/horizon-ohos/HANDOFF.md

---

## 附录 C：我们“自己编译的仓颉”能否使用官方互操作？

**能互操作；但要区分两种“互操作”。**

### C.1 底层互操作（NAPI / C ABI）—— 自编译完全支持，且已真机验证
- “ArkTS 调用仓颉”本质是 **Node-API（NAPI）**：只要 .so 加载时向 NAPI 注册模块（napi_module_register），ArkTS 就能 import “libX.so”。
- 用 cjv 自编译的 .so 已满足（两条路都验证过）：(a) @C 导出 + 薄 C++ NAPI shim（generate.sh 生成，signed HAP 真机运行，hilog 打印 hello-from-cjcore/add=9）；(b) 或在仓颉里 foreign 绑定 napi.h 自行注册（更自包含）。
- 结论：**能否互操作取决于“是否按 NAPI 规范注册模块”，与“用不用 DevEco 编译”无关。**

### C.2 官方便利库 ohos.ark_interop / @Interop 宏 —— 不在 cjv 交叉工具链里
- 实测（sts-1.2.0-linux-x64-ohos）：import ohos.ark_interop.* 报 “can not find package 'ohos.ark_interop'”；工具链 modules 仅含 std；cjv component list 也只有 docs/stdx/stdx-docs。
- 它随 **DevEco 的仓颉 SDK（DEVECO_CANGJIE_PATH）** 发布；但其源码是**开源**的：openharmony/arkcompiler_cangjie_ark_interop（“仓颉互操作库”）。

### C.3 想在“自编译”里用官方互操作，两条路
1. **接预编译包**：从 DevEco 仓颉 SDK 取 ohos.ark_interop（.cjo + aarch64-ohos 原生库），用 --import-path 指 .cjo、link-option 链其 .so（版本需与工具链 1.2.0 匹配）。
2. **自己构建**：按 openharmony/arkcompiler_cangjie_ark_interop 源码，用我们的交叉工具链编出该包。
   - 注意：@Interop[ArkTS] 的 Index.d.ts 生成在官方是 DevEco 的 IDE 动作；不接 IDE 时**手写 Index.d.ts**即可（generate.sh 已是这个做法）。

### C.4 建议
- **v1 不必依赖 ark_interop**：直接用 §3–§6 的“@C + NAPI shim + generate.sh”，自编译即可、已验证、零鸿蒙工程入库。
- 若更看重官方“@Interop 自动出 d.ts”的 DX，再把开源 ark_interop 包接进自编译工具链；这是“接线 + 版本对齐”的工作量，不是可行性问题。

> 一句话：**自编译仓颉走底层 NAPI 互操作没问题（已验证）；要官方 @Interop/ark_interop 那套便利层，把开源/预编译的 ark_interop 包接进自编译工具链即可，并非必须用 DevEco GUI 编译。**

---

## 附录 D：参考链接（补充）

- 仓颉互操作库源码（开源）：https://github.com/openharmony/arkcompiler_cangjie_ark_interop

---

## 附录 E：ohos-sys + “生成的 ArkTS 剥壳直接启动仓颉” —— 结论与验证

### E.1 结论
- **可以做自己的 ohos-sys**：把 OHOS 的 C/NDK 接口按“原始绑定（-sys）+ 安全封装”两层做成 `packages/ohos_*`，就是从零复刻 wasm-bindgen/web-sys 的“生成式独立绑定”。用 cjc 的 foreign func 表达 C ABI 即可，可脚本按头文件生成。
- **可以做“生成的 ArkTS 剥壳直接启动仓颉”**：但不能只靠一次裸调用——加载进来的仓颉 .so 需要先初始化运行时。正确启动序列（已本机实测）：宿主先调用 `InitCJRuntime(...)`，再 `LoadCJLibraryWithInit("lib<engine>.so")`，然后调用仓颉导出的 `@C` 入口（如 `cj_app_main()`），之后整个引擎在仓颉侧运行。
- **OHOS 侧的系统约束**：系统只能通过 UIAbility + 页面启动应用，不能直接拉起裸可执行文件。所以“剥壳”= 生成一个极薄的 ArkTS UIAbility + 一个 XComponent 页面 + module.json5（约 3 个文件，全由脚本产出、无业务逻辑），在页面 onLoad / 模块初始化时经 NAPI 触发上面的启动序列，把 surface/输入/生命周期交给仓颉。

### E.2 验证证据（本机 linux-x86_64 同构验证）
- 失败对照：dlopen 仓颉 .so 后**直接**调用 `@C` 函数 → 崩溃 `Check failed: runtime != nullptr`（运行时未初始化）。
- 成功序列：`InitCJRuntime(argbuf)` → `LoadCJLibraryWithInit("./libcjapp.so")`（rc=0）→ `cj_app_main()`：

```text
Cangjie runtime started.
LoadCJLibraryWithInit rc=0
cj_app_main: runtime alive, sum=0,20
cj_app_main -> 42
```

- 设备一致性：OHOS 的 `runtime/lib/linux_ohos_aarch64_cjnative/libcangjie-runtime.so` 同样导出 `InitCJRuntime / LoadCJLibraryWithInit / CJ_MRT_CjRuntimeInit / MRT_LibraryOnLoad`，故该序列在真机同样适用。

### E.3 ohos-sys 包规划（建议）
| 包 | 职责 | 备注 |
|---|---|---|
| ohos_cj_runtime（-sys） | InitCJRuntime / LoadCJLibraryWithInit / MRT_LibraryOnLoad 绑定 + 启动胶水 | 启动必需；NAPI shim 里调一次 |
| ohos_napi_sys | napi.h（module/function/value/tsfn） | 桥接根 |
| ohos_native_window_sys / ohos_egl_sys / ohos_gles_sys | NativeWindow、EGL、GLESv3（sysroot 有 libEGL/libGLESv3.so） | 渲染上屏 |
| ohos_input_sys / ohos_ime_sys / ohos_vsync_sys | 输入、输入法、vsync | 交互/帧同步 |
| ohos_media_sys | AVCodec/AVPlayer/AudioRenderer | 替代 libVLC/cpal |
| ohos_image_sys | ImageSource / Pixelmap / AVIF | 替代 vips 的首选 |
| ohos_hilog_sys | OH_LOG_* | 日志 |
| ohos_arkui_sys（可选） | ArkUI NDK node API / kit.ArkUI | 仅“原生 ArkUI UI”路线 |

结构对应 Rust 生态：`ohos_*_sys` = 原始绑定（≈ `windows-sys/libc`），`ohos_*` = 安全封装（≈ `windows/nix`）；生成器 ≈ wasm-bindgen。

### E.4 启动时序（生成的 ArkTS 剥壳）
```text
系统 → EntryAbility.onCreate → loadContent(Index.ets)
Index.ets: XComponent.onLoad (或 aboutToAppear)
   → NAPI shim 首次初始化: dlopen + InitCJRuntime + LoadCJLibraryWithInit(lib<engine>.so)
   → cj_app_main(nativeWindow, w, h)    // 仓颉：起引擎线程、建 EGL/SDL、跑主循环
输入/生命周期: ArkTS 事件 → cj_on_touch/key/resize/foreground/background (@C)
```

### E.5 注意
- 只支持 aarch64（arm64-v8a）；无 JIT。
- 仓颉运行时 .so（libcangjie-runtime / std-* / libboundscheck）必须随 HAP 打进 libs/arm64-v8a（或 --static 静态化）；NAPI shim 里对 libcangjie-runtime.so 的初始化不能省。
- UI 线程仅属 ArkUI；引擎必须跑独立线程，事件经 NAPI/uv_async 转投，surface 生命周期回调驱动。
- 该启动序列正是官方 ohos.ark_interop 在内部自动完成的事；我们自编译方案把它显式写在生成的 NAPI shim 里即可。

---

## 附录 F：ohos-sys 有时需要调用 ArkTS API —— 反向互操作

### F.1 结论
**能。** 互操作是双向的：
- 下向（ArkTS → 仓颉）：NAPI 模块导出，前面已讲。
- **上向（仓颉 → ArkTS）：NAPI 反向回调**。native 持有 `napi_env` + 一个对 JS 函数/对象的引用 `napi_ref`，需要时用 `napi_call_function / napi_get_property / napi_new_instance` 调 ArkTS。

### F.2 机制与实证
- 最小验证（本机 Node N-API，同款接口）：native 通过 `napi_call_function` 调起 JS 回调 `x=>x*2` 并拿到 42 → 证明“native 调 JS”路径成立。
- 在仓颉侧两种写法：
  1. 不接 ark_interop：在 `ohos_napi_sys` 里绑定 `napi_call_function / napi_create_reference / napi_threadsafe_function` 等（就是上面 demo 用的这些）。
  2. 接 ark_interop：直接用 `JSFunction.call()` / `JSObject` 属性 / `SharedObject` 持有 ArkTS 对象，更省事。

### F.3 线程（关键）
- JS/NAPI 调用必须在创建 `napi_env` 的 **JS/ArkUI 线程**执行。仓颉引擎跑独立线程 → 必须用 **`napi_threadsafe_function`（tsfn）** 把调用转投 JS 线程后再执行；或事件泵/uv_async。
- 先例：horizon-ohos 的全屏/IME/光标推送就是 tsfn（并踩过 `napi_call_function(env, recv, func, ...)` 参数顺序写反、回调从未执行的坑）。
- 需要返回值时：同一线程同步返回；跨线程用 future/信号等待，但**绝不能在 JS 线程上阻塞等待引擎**（会死锁/ANR）。

### F.4 设计模式：能力注入（Host）
为了避免 `ohos_*_sys` 硬绑 ArkTS，采用“能力注入”：
- ArkTS 剥壳初始化时把一个 **Host 对象**传给仓颉：`cj_set_host({ requestPermission, pickFile, openLink, getContext, toast, ... })`；仓颉存为 `napi_ref`。
- `ohos_*_sys` 只依赖抽象的 `Host` 接口：**有 NDK/C API 的直接调 C；只有 ArkTS 才能做的走 Host 回调**。
- 这样 ArkTS 依旧是“薄壳/能力提供者”（无业务），仓颉可随处发起 ArkTS 调用。

### F.5 判定：哪些必须回调 ArkTS
| 场景 | 走哪条 |
|---|---|
| 权限申请 requestPermissionsFromUser、文件/图片选择器、context.startAbility/openLink、want 拉起、部分 Kit（Account/IAP/Push/通知/部分系统UI） | **ArkTS-only → Host 回调** |
| 窗口、输入、vsync、AVCodec/AVPlayer、ImageSource/Pixelmap、部分 ability_runtime/access control | **优先找 NDK C API 直接绑** |
原则：先查 OHOS NDK 是否有 C 接口；没有的才设计成 Host 能力，经 NAPI(+tsfn) 回调。

### F.6 注意
- `napi_ref` 生命周期：ability 销毁后 env 失效，需在 onDestroy 清理；不要在失效 env 上调用。
- 异常跨语言：两侧都 try/catch（ark_interop 会把异常转成调用侧可捕获异常）。
- 性能：跨语言调用昂贵，批量/合并；高频路径尽量下沉到 C。
- 多引擎/JSContext 隔离：不要跨 JSContext 混用 JS 对象（ark_interop 规范）。

---

## 附录 G：CJProbe 真机验证（端到端跑通）

**结论：在真实 2in1 设备上跑通**「生成的 ArkTS 剥壳 → NAPI shim → InitCJRuntime + LoadCJLibraryWithInit → 真实交叉编译的仓颉 .so 的 cj_app_main → 返回值回显 UI」。

- 设备：HUAWEI MateBook Pro S（MOR-W52，2in1，HarmonyOS 7.0.0.111 / OpenHarmony-7.0.0.109，API 26）。构建用 CLT 26.0.0.821（API 26 / 平台 7.0，已拷贝到本地 .research-ohos/tools/clt-7.0）。
- 注：初期曾用 `devecocli create --api-level 23` 建工程（HAP 的 target/compatible 被钉成 6.1.0(23)），后已改为 API 26 复验；CLT 本身一直是 API 26。
- 真机 UI 文本：`boot=0 sum(40,2)=42 count=10`；hilog：`A00000/com.example.cjprobe/CJPROBE: RESULT boot=0 sum(40,2)=42 count=10`。
- 其中 `sum/count` 均由**仓颉引擎 .so** 计算后经 NAPI 回传给 ArkTS（不是 ArkTS 本地算的）。

### 工程结构（CJProbe）
```text
cjprobe/
├── engine/                       # 真实仓颉引擎（cjpm 交叉编译 aarch64-linux-ohos）
│   ├── cjpm.toml                 # [target.aarch64-linux-ohos] --sysroot + -L
│   └── src/main.cj               # @C: cj_app_main / cj_probe_sum / cj_probe_count
└── hap/                          # devecocli create 生成的鸿蒙工程（可丢弃/再生成）
    ├── AppScope/app.json5        # bundleName=com.example.cjprobe
    ├── build-profile.json5       # 签名配置（signature generate 写入）
    └── entry/
        ├── build-profile.json5   # externalNativeOptions + nativeLib.collectAllLibs
        ├── oh-package.json5      # 依赖 libcjprobe_shim.so
        ├── libs/arm64-v8a/       # 打包：libcjprobe.so + 仓颉运行时(54 个 .so) + libc++.so
        └── src/main/
            ├── cpp/
            │   ├── napi_init.cpp # 启动胶水：dlopen runtime+engine, InitCJRuntime, LoadCJLibraryWithInit, 注册 JS 函数
            │   ├── CMakeLists.txt
            │   └── types/libcjprobe_shim/{Index.d.ts, oh-package.json5}
            └── ets/pages/Index.ets  # 剥壳页：import 'libcjprobe_shim.so'，调用并显示
```

引擎侧最小代码：
```cangjie
package cjprobe
import std.collection.ArrayList
@C public func cj_probe_sum(a: Int64, b: Int64): Int64 { a + b }
@C public func cj_probe_count(): Int64 {
    let xs = ArrayList<Int64>()
    for (i in 0..10) { xs.add(i) }
    return xs.size
}
@C public func cj_app_main(): Int64 { println("cj_app_main: Cangjie runtime booted"); return 0 }
```

### 踩到的两个真实坑（已在 PoC 修好）
1. **不要把引擎作为 CMake 的 IMPORTED target 去 link**：否则 shim 的 `DT_NEEDED` 会写进**主机绝对路径** `libs/arm64-v8a/libcjprobe.so`，真机加载报 `Error loading shared library .../libcjprobe.so (needed by libcjprobe_shim.so)`，模块整体失败（页面显示 `ERR {}`）。修法：运行时用 `dlopen`（用 `dladdr` 取自身目录拼绝对路径，或 soname）+ `dlsym`。
2. **libc++ ABI 版本对齐**：`cjv` 预置的 OHOS 运行时是按**旧 libc++ ABI `std::__h`** 构建的；而 CLT/SDK 自带（含 NDK 与设备 `libc++_shared.so`）是 `std::__n1`；设备另有 `/system/lib64/libc++.so` 提供 `std::__h`。不处理会报 `Error relocating libcangjie-runtime.so: _ZNSt3__h15recursive_mutex4lockEv: symbol not found`。修法：把设备 `/system/lib64/libc++.so`（正是 `std::__h`）作为 `libc++.so` 打进 `libs/arm64-v8a`。
   - 根本建议：让 Cangjie SDK/libc++ 与目标 HarmonyOS 版本**对齐**（用配套的 libc++.so），或改用与设备 ABI 匹配的 Cangjie OHOS SDK。

### 复用
把上面 `libs/arm64-v8a` 的补齐（运行时 .so + 匹配的 libc++.so）与 `napi_init.cpp` 的启动胶水固化进 `generate.sh` 的 shim 模板，即成为可复用的“仓颉 OHOS 剥壳启动器”。
