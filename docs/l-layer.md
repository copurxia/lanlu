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
- 构建：`bash packages/lgpu/native-ohos/build-ohos.sh`（自动 staging 到 `native/target/release/liblgpu_native.a`）
- wgpu-hal 补丁同步：`bash tools/sync-wgpu-hal.sh`
