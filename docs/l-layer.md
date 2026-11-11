# L 层渲染器（lgpu）现状与计划

> 目标：**彻底去掉 SDL**，自建窗口/输入（`lwindow`）+ 渲染（`lgpu`），OS 差异全部收敛在 L 层。
> 依据用户方向：Rust 实现、导出 **C ABI**（与 `webview_native`/`fontkit_native` 同款），只对接 OHOS。

## 已完成（真机验证）

| 能力 | 证据 |
|---|---|
| Rust → aarch64-linux-ohos staticlib → HAP → Cangjie FFI | `lgpu.txt`: `self_check=0` |
| wgpu 30.0.1 + vendored patched wgpu-hal（`VK_OHOS_surface`） | `adapters: Maleoon 935\|Vulkan\|IntegratedGpu` |
| OHOS surface：`OH_NativeWindow_CreateNativeWindowFromSurfaceId` → swapchain | 屏幕出现 `#FF00FF`（44,137 px） |
| 实例化 SDF 图元（矩形/圆角/描边，解析抗锯齿） | 蓝底 15,656px / 白圆角 13,599px / 金描边 13,624px |
| 纹理路径（create/upload 子区/采样/tint/UV） | 64×64 红绿棋盘正确采样（红/绿各 2500px） |
| 全局变换 `lgpu_set_transform` | 自检 PASS（偏移后精确落位） |
| 逐批裁剪 `lgpu_set_clip`（Vulkan scissor，按 clip 分组批次） | 自检 `bbox=(20,40)-(79,59)`，与期望完全一致 |
| 实例化合批（一次 draw 画一组） | 自检 `second_green=255`（同组两实例都出图） |
| 离屏渲染 + 读回自检框架 | `lgpu_selftest()`：确定性，多次启动结果一致 |
| Cangjie 绑定包 `packages/lgpu` | `Surface`/`Texture` RAII、异常化错误、`setClip`/`setTransform` |

## 关键坑（都已修，记下来避免重犯）

1. **四边形第二个三角形退化**：顶点表里 vi=3 与 vi=5 重合，导致每个矩形只画出**半个**（真机表现为"高度只有一半"）。
   正确顶点表：三角形1 `(-1,-1)(1,-1)(-1,1)`，三角形2 `(-1,1)(1,-1)(1,1)`。
   之前所有"多实例不出图""裁剪把内容裁没"的假象都是它引起的。
2. **离屏 target 格式必须等于管线 color target 格式**（否则整个 pass 被丢弃）。
3. **读回要等自己那次提交**：`device.poll(PollType::Wait { submission_index: Some(idx) })`，不能只等"最近一次"。
4. **hilog 会丢我们 native tag 的行**：诊断信息走返回值/文件，别依赖日志。
5. **自检别用固定采样点猜坐标**：报内容包围盒（bbox）才有诊断价值。

## 后端抽象（P4 起步）

- packages/cangjie-gui/sdl/src/canvas.cj：`public interface Canvas` —— 视图只需要它，不用知道底层是 SDL 还是 wgpu。
  已收口 14 个高频图元（fill / fillRoundedRect / fillRoundedRectSoft / strokeRect / strokeRoundedRect / strokeLine / line / fillCircle / strokeCircle / text / textWidth / textHeight / textCenter）。
- sdl.Renderer 已实现 Canvas（行为零变化）。
- lgpu.LgpuCanvas 已实现 Canvas（映射到 SDF/纹理管线，含旋转矩形实现的线段）。
  迁移期注意：文本度量来自 ab_glyph，与 fontkit 在极端字号下可能差 1px；fillRoundedRectSoft 的 feather 暂按普通圆角处理（SDF 自带抗锯齿）。
- 待 P5 删 sdl 时，把 Canvas 与 Color/Pen/Rect 一起搬到中立包。

## 输入桥的坑（本轮实测）

尝试过的方案与结果：
1. Cangjie 线程直接拿原生 surface 指针绘制 → **SIGSEGV**（窗口/surface 有线程亲和性，跨边界传指针不可行）。
2. ArkTS onTouch → napi pushInput → C++ `std::deque`+`std::mutex` 环形缓冲 → Cangjie `lanlu_poll_input` 轮询 → **SIGSEGV/SIGABRT**（即使不轮询也会崩，怀疑 libmain 里新增的 C++ 静态对象/中途 #include 与引擎加载时序冲突）。

已确认可行的：只把 **surfaceId 数字**写进进程环境，Cangjie 侧自建窗口/surface 并绘制（round 12 真机验证通过）。
下一轮输入桥建议：C++ 侧用**纯 C 结构**（固定数组 + volatile 索引，不用 std::deque/std::mutex、不中途 #include），先只提供 `lanlu_poll_input` 且 Cangjie 只在**单点**调用一次验证，再逐步加频率。

## 纹理委派验证（P4 达成，真机）

`$HOME/probe_trace.txt`（`LANLU_PROBE_LGPU=1` 时写入）真机输出：
```
backend installed=true
http status=200 url=http://192.168.0.131:8080/probe.png
png id=1 bytes=4898        ← lgpu 内解码 + 上传（64x64 渐变 PNG）
probeLoadPngBytes id=1 bytes=4898
png id=2 bytes=4268        ← 应用自身的内嵌 logo，走同一条纹理路径
```

结论：PNG 字节 → lgpu 纹理 → UI 绘制 的委派链路在真机可用；
排查经验：**应用进程读不到 /data/local/tmp**，探针资源走 HTTP（mock `/probe.png`）最省事。

## 输入坐标口径（P1）

- 触摸事件：系统给的就是**窗口局部坐标**（`OH_Input_GetTouchEventWindowX/Y`），直接用。
- 鼠标事件：只有**显示坐标**（没有 window 局部 getter），必须 `display - 窗口原点` 换算；
  窗口原点由 ArkTS 的 `windowRect.left/top` 经 `startFilter` 传给 native（`lanlu_seed_origin` + 连续自校准）。
- 这条换算就是"鼠标位置不对"最容易出错的地方，先按此口径实现，待物理鼠标复核。

## 整窗渲染（P5 渲染层，真机达成）

开启：`aa start ... --ps lanlu.env.CN_UI_BACKEND lgpu --ps lanlu.env.LANLU_MAIN_LGPU 1`

链路：ArkTS 全尺寸 XComponent(`LGPU_Main`) → `shell.setMainSurface(sid,w,h)` → 环境变量
→ Cangjie 用 `Surface.fromSurfaceId` + `configure(2090x1394)` → 整棵 UI 树经 `LgpuCanvas` 绘制。

真机结果（窗口 2090x1394 px，`uitest dumpLayout` 核对过）：
```
#3B3B40 2,787,293 px  ← 内容背景（全窗）
#53535A    71,622 px  ← 标题栏条
#4D4D53    12,547 px  ← 面板
#837757     6,662 px  ← 强调色
present err=[]        ← 首帧无错误
```

关键坑（记下来避免重犯）：
- 三个 XComponent 在同一个 **`Column`** 里！`Column` 纵向排列，不重叠 —— 
  后加的整窗 XComponent 会被排到 SDL 那个**下方**，即使 surface 画对了也永远看不见。
  解决：加 `.position({x:0,y:0})` + `.zIndex(9)`。
- 判断"是否被合成"的可靠办法：`LANLU_MAIN_PROBE_FILL=1` 强制红清屏，数窗口内红像素。
- `lgpu_text_draw` 的 `len==0`（空标签）是合法调用，不能当坏参数。

## 去掉 libSDL3 的最后障碍（R42 结论）

**壳层**已经完全不依赖 SDL（CMake/EntryAbility/ArkTS/打包配置都清了，引擎由 `libmain` 构造函数启动）。
但尝试把 `-lSDL3 -lSDL3_ttf` 从引擎 link-option 移除时，进程启动即 **Cpp Crash**：

原因是 `packages/cangjie-gui/sdl` 里仍留有 391 处 SDL 调用 / 158 个不同函数（texture/renderer/
system_info/displays/clipboard/surface…）。这些代码在 lgpu 模式下**不执行**，但**仍被编译进引擎**，
移除 `-lSDL3` 后符号无法解析 → 加载期崩溃。

所以最终移除 SDL 库的顺序是：
1. 删除或改写这 391 处调用（能删的删：dead code；必须的改 lgpu 实现）
2. 再移除 `-lSDL3 -lSDL3_ttf` 与 `OHOS_EXTRA_LIBS` 里的 SDL 前缀
3. 验证 HAP 内无 `libSDL3*.so`、`readelf -d` 无 SDL NEEDED

## 窗口几何取证（R49 真机结论）

`setWindowDecorVisible(false)` 生效，已用避让区量化确认：

```
rect=515,292,2090,1394  sysTop=0 sysBottom=0  cutTop=0  navBottom=0
```

- `sysTop = 0` → **没有系统标题栏**（不是沉浸式全屏，是真正去掉了窗口装饰）
- `cutTop = 0` / `navBottom = 0` → 无刘海与导航条避让
- 窗口矩形 2090×1394 与我们拿到的 XComponent surface 尺寸完全一致 → **内容区 = 窗口区**，
  所以鼠标局部坐标就是 `raw - (rect.left, rect.top)`，不存在标题栏高度偏移

取证方式：ArkTS 在 `onWindowStageCreate` 之后把 `windowRect` 与三个 `AvoidAreaType` 写进
`$HOME/window_info.txt`（`getWindowAvoidArea`）。这个探针比截图颜色判断可靠。

**三键平台化后（2026-11-11）**：`decor=false` 的结论不变——三键仍由系统绘制在窗口右上角、
悬浮不占布局（`sysTop` 仍 0）。新增协议链路 `lw_window.title_buttons_rect` 上报
**窗口局部 px**（壳从 vp 换算），引擎侧 `ui title buttons width=140vp selfDrawn=false`
打点可证；业务层标题栏据此右侧避让，不再自绘三键。详见
[lwindow-title-buttons-plan.md](lwindow-title-buttons-plan.md)。

## 鼠标坐标取证（R50 真机结论）

```
window_info:   rect=515,292,2090,1394  sysTop=0 sysBottom=0 cutTop=0 navBottom=0
filter_origin: ox=515.0 oy=292.0 calibrated=1
```

- 输入过滤器实际使用的原点 `(515,292)` **与窗口矩形原点完全一致** → 屏幕坐标减原点即得窗口局部坐标，
  没有标题栏高度偏移。
- 因此 `local = display - windowRect.origin` 是正确的换算，且装饰去掉后无需再减任何 chrome。
- `lanlu_seed_origin()` 现在直接把种子原点标记为已校准（此前只存值不置标志）。

取证入口：`startFilter(winId, rect.left, rect.top)` 会把原点写进 `$HOME/filter_origin.txt`。

## 视觉验收（R62，真机截图）

截图方法（devecocli 在 Linux 容器不可用，改用系统工具）：

```bash
hdc -t <dev> shell "snapshot_display -f /data/local/tmp/v.jpeg"
hdc -t <dev> file recv /data/local/tmp/v.jpeg /tmp/v.jpeg
magick /tmp/v.jpeg -crop 2090x1394+515+292 +repage win.png   # 裁到窗口区域
magick win.png -format %c -depth 8 histogram:info: | sort -rn | head -5
```

实测结果（窗口 2090×1394）：

```
#3C3B40  2384603 px   主背景（设计值 #3B3B40，jpeg 色偏 1）
#4E4D53   321397 px   标题栏 / 面板（设计值 #53535A 附近）
#535459    65917 px   次级表面
#847757     9852 px   强调色（设计值 #837757）
颜色总数 7511，亮像素（文字）13299，mean=0.256 std=0.052
```

→ 调色板与设计一致、文字像素存在、无大面积纯黑/纯白，说明**整窗渲染 + 纹理 + 文字都在正常工作**。

## M0-4 最小用例结论：引擎调壳导出符号（2026-11-10，host 实测）

探针：[tools/probes/ffi-call](../tools/probes/ffi-call/README.md)（`bash tools/probes/ffi-call/run.sh`）。
最小化“引擎（仓颉 dylib）调用壳（C）导出函数”，把历史两次失败（`d722178c`、`03461092`）
拆成 5 个可控变体。**全部可复现**，结果如下：

| 变体 | 壳对引擎可见的时机 | 结果 |
|---|---|---|
| `shell-first-g` | `dlopen(shell, RTLD_GLOBAL)` 在加载引擎之前 | ✅ `LoadCJLibraryWithInit rc=0`；`lwp_probe(6)=43`；外部线程回调 `cj_foreign_entry(21)=63`；`cj_app_main` 返回 43 |
| `engine-first` | 先加载引擎，之后才 `dlopen(shell, RTLD_GLOBAL)` | ⚠️ `LoadCJLibraryWithInit rc=-1`，但随后 `dlopen(engine, RTLD_LAZY)` **返回 ok**，`cj_app_main` 也有“返回值”（垃圾值 6399146），引擎 `println` 丢失，**退出码 0** |
| `shell-local` | `dlopen(shell, RTLD_LOCAL)` | ❌ 引擎始终解析不到符号：`LoadCJLibraryWithInit rc=-1`，`dlopen(engine)` 报 `undefined symbol`，退出码 1 |
| `ctor-autostart` | 在壳的**构造函数里同步**启动引擎 | ❌ `undefined symbol`。构造函数执行期间壳自身的符号尚未进入全局作用域 |
| `ctor-deferred` | 构造函数只起线程，稍后再启动（≈ 现在 `lanlu_autostart_engine`） | ✅ 能跑通，但成立前提是“壳的 dlopen 已完成”，靠线程调度碰运气 |

### 结论（M1 传输层必须遵守）

1. **壳必须以 `RTLD_GLOBAL` 加载，且早于引擎**。`RTLD_LOCAL` 下引擎永远看不到壳符号
   （与 horizon-ohos 在 `sdl_main.c` 里记录的同一条教训一致：libSDL3 被 RTLD_LOCAL 加载后
   `dlsym(RTLD_DEFAULT)` 查不到）。
2. **不要在壳的构造函数里启动引擎**。同步启动必失败；异步启动虽然能过，但时序不确定——
   这就是引擎里到处“最多等 N 秒拿环境变量”的根源。
3. **失败是静默的**：`engine-first` 变体里 `dlopen` 返回 ok、`cj_app_main` 有返回值、进程退出码 0，
   只有引擎输出丢失。**不能用“链接成功 / 退出码”判断链路是否可用**。
4. 因此 M1 的启动顺序定为：壳 `dlopen` 完成后（ArkTS 显式调 `lshell.start()`，或壳内明确同步点）
   → `lwp_open` → 发 `core.hello` → 再 `InitCJRuntime` + `LoadCJLibraryWithInit` → 引擎回
   `core.hello_ack`。**以 hello_ack 作为链路可用的唯一判据**，并在 `lpack-ohos verify` 里加
   符号门禁（壳声明的 `lwp_*` 必须由 `liblwp.so` 导出）。
5. 外部线程（pthread）调用仓颉 `@C` 函数在 host 上工作正常（63 正确、无崩溃、无死锁），
   与运行时 `CJ_MCC_N2CStub`/`MRT_NewForeignCJThread` 的实现一致；但按计划 §2 原则 6，
   LWP 仍不依赖它（外部线程只写队列 + 唤醒）。
6. **尚未覆盖**：历史现象里的“lgpu 静态库被链两份”与设备侧 SIGSEGV（Maleoon 驱动、musl 栈）
   在 host 上无法复现，需要在 M4 真机阶段用本探针同样的最小化思路继续二分（计划 R1/R11）。

## 待办

- [ ] P2 收尾：圆形/描边圆（SDF 已支持矩形，圆用 radius=half 近似即可）、水平/垂直渐变、SSAA（`DEFAULT_SUPERSAMPLE=2`）
- [ ] P3 文本：`rustybuzz`（已在离线 registry 缓存）做 shaping + 自建字形图集（SDF 或 grayscale）
- [x] P4 抽象层：Canvas 接口 + sdl.Renderer/lgpu.LgpuCanvas 双实现（编译通过）
- [ ] P4 切换：视图参数改为 Canvas、加 CN_UI_BACKEND=sdl|lgpu 开关、真机对照
- [ ] P5 删除 `packages/cangjie-gui/sdl`、去掉 `libSDL3*.so`、窗口钩子改直连
- [x] P1 lwindow 自建窗口（surfaceId → OHNativeWindow → lgpu.Surface）真机验证
- [ ] P1 自有事件队列 + 输入桥（事件模型已就位，桥待重做）
- [ ] P1 键位表从 sdl/input/keyboard.cj 迁移

## 工具链事实（容器内）

- Rust 只在 `/workspace/horizon-ohos/.tooling/rust190`（已装 `aarch64-unknown-linux-ohos` std）
- crates.io 不可达，但 `/workspace/.cargo/registry`（1.1G）有离线缓存：`wgpu-30.0.1`、`rustybuzz-0.20.1`、`pollster`、`bytemuck`、`raw-window-handle`
- 构建：`bash packages/lplatform-ohos/deps/lgpu/build-ohos.sh`（自动 staging 到 `native/target/release/liblgpu_native.a`）
- wgpu-hal 补丁同步：`bash tools/sync-wgpu-hal.sh`
