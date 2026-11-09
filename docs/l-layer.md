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

## 待办

- [ ] P2 收尾：圆形/描边圆（SDF 已支持矩形，圆用 radius=half 近似即可）、水平/垂直渐变、SSAA（`DEFAULT_SUPERSAMPLE=2`）
- [ ] P3 文本：`rustybuzz`（已在离线 registry 缓存）做 shaping + 自建字形图集（SDF 或 grayscale）
- [ ] P4 `cui` → `lgpu` 的 Renderer 适配层；开关 `CN_UI_BACKEND=sdl|lgpu`
- [ ] P5 删除 `packages/cangjie-gui/sdl`、去掉 `libSDL3*.so`、窗口钩子改直连
- [ ] P1 `lwindow`：自有事件队列（替换 `SDL_WaitEventTimeout`）、键位表迁移

## 工具链事实（容器内）

- Rust 只在 `/workspace/horizon-ohos/.tooling/rust190`（已装 `aarch64-unknown-linux-ohos` std）
- crates.io 不可达，但 `/workspace/.cargo/registry`（1.1G）有离线缓存：`wgpu-30.0.1`、`rustybuzz-0.20.1`、`pollster`、`bytemuck`、`raw-window-handle`
- 构建：`bash packages/lgpu/native-ohos/build-ohos.sh`（自动 staging 到 `native/target/release/liblgpu_native.a`）
- wgpu-hal 补丁同步：`bash tools/sync-wgpu-hal.sh`
