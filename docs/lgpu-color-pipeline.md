# lgpu 颜色管线：sRGB 与过曝（2026-11-11）

真机反馈「浅色模式整体过曝、界面糊成一片」。本文记录定位过程、实测数据与结论。

## 1. 现象与首次误判

- 现象：浅色模式下大面积发白，卡片与背景几乎无层次；深色模式「看起来还行」。
- 首次误判：以为是调色板对比度不足，把 `LANLU_L_BG` 从 `F8F8FA` 调到 `EFF1F5`。
  **方向错误**，已回滚（调色板恢复设计原值）。

## 2. 实测（hdc 截图 + 窗口矩形采样）

用 `hidumper -s WindowManagerService -a '-a'` 取窗口矩形 `[x y w h]`，
用 `uitest screenCap` 截图后按该矩形内的点做 1×1 采样（**采样前必须确认窗口在最前**，
否则会采到遮挡窗口的像素 —— 本轮踩过，得到过 (245,245,245) 的错误结论）。

| 采样点 | 修复前 | 修复后 | 设计值 |
|---|---|---|---|
| 深色页面底 | **(61,61,66)** | **(11,11,13)** | `0B0B0D` |
| 深色面板 | — | **(22,22,26)** | `16161A` |
| 浅色页面底 | (255,255,255) | **(248,248,250)** | `F8F8FA` |
| 浅色面板 | (255,255,255) | **(255,255,255)** | `FFFFFF` |

深色底 11 → 61 是 **+454%**，符合"sRGB 被两次编码"的理论值（`sRGB(sRGB(0.043))≈0.228→58`）。

## 3. 根因

| 环节 | 格式 | 行为 |
|---|---|---|
| swapchain | sRGB（`is_srgb()` 优先） | 写入时硬件做 linear→sRGB **编码** |
| 图片纹理 | `Rgba8UnormSrgb` | 采样时 sRGB→linear **解码** ✅ |
| 调色板纯色 | 原先 `v/255` 直接当线性 | **没有解码** ❌ |

图片正确、纯色被提亮，正好解释"封面图看着正常、界面底色发白"。

## 4. 两种修法与取舍

**方案 A（采用）**：保留 sRGB 目标，CPU 侧把调色板预解码成线性
（`canvas.cj::channel` 用 256 项查表）。硬件编码后还原为原值。
- 优点：改动 1 个文件；实测字节级正确。
- 缺点：**alpha 混合发生在双线性空间**，半透明阴影/遮罩比设计亮（"过曝感"残留）。

**方案 B（horizon 的做法，OHOS 不可用）**：
`horizon/crates/horizon-client/src/gfx.rs::surface_format` 明确选**非 sRGB** 目标，
注释写着"内容在 gamma 空间混合，选 sRGB 会让合成器把 gamma 值当线性光读，颜色洗白"。
- 实测：OHOS 上配非 sRGB（Rgba8Unorm / Bgra8Unorm 各试一次）→ 应用启动后
  `reason=Cpp Crash` 原生崩溃，`lgpu main surfaceId=…` 之后立刻死。
- 结论：这条路在本机 Vulkan WSI 上走不通。

**方案 C（待做）**：渲染到**离屏 Unorm 纹理**（gamma 空间混合）→ blit 到 sRGB 交换链，
blit shader 里做 sRGB→linear。等价于 B，且不要求交换链非 sRGB。

## 4.1 方案 C 的实现（本轮）

- 新增离屏目标 `SCREEN_FORMAT = Rgba8Unorm`（`ensure_offscreen`，尺寸变化时重建）；
  **所有 UI 画进它**（gamma 空间混合，与设计稿一致），包含阴影/遮罩/文字抗锯齿。
- 新增 blit 管线（全屏三角形 + WGSL `srgb_to_linear`）：把离屏 gamma 值转成线性写进
  sRGB 交换链，硬件再编码 → 输出等于原值，且**不产生二次编码**。
- 图像纹理改为 `Rgba8Unorm`（不再 sRGB 解码），字节原样进管线。
- 离屏抓帧（弹窗模糊用）同样用 Unorm，回读即 gamma 值。
- `canvas.cj::channel` 回到 `v/255`（直传）—— 预解码与 blit 只能留一个，同时存在会变暗。

> 注意：`canvas.cj` 的直传与 `lib.rs` 的离屏 blit 是**一个原子改动**，必须一起合入；
> 只合一半会出现"整体过曝"或"整体发暗"。

### 4.2 数值验证（离线，不依赖设备）

| 检查 | 结果 |
|---|---|
| 方案 C 往返：`gamma → blit 转线性 → 硬件编码` | 256 个 8bit 值 **0 个不一致** |
| 半透明黑 55% 盖白底：gamma 混合 vs 线性混合 | **115 vs 179**（差 64 级，正是"发白"的量） |
| 同上 35% / 14% | 166 vs 211 / 219 vs 239 |

也就是说：阴影、遮罩这类半透明层在线性空间混合后**普遍亮 20~64 级**，
这正是"不透明色已经准了、但整体仍然发白"的原因。

## 4.3 设备二分：崩溃归属（两次实验，第二次有效）

**第一次（无效）**：用 `LANLU_LGPU_NOBLIT=1` 对照，两种模式都崩。
但 ArkTS 侧 `--ps lanlu.env.*` 设置的环境变量**未必对 Rust 可见** —— 事后在 step log 里
找不到 `noblit=` 打点，说明该开关很可能根本没生效，所以"两模式都崩"不能作为结论。**已撤回。**

**第二次（有效）**：把 `lib.rs` 换回并发会话的版本、`canvas.cj` 换回其版本
（即**完全不含**本方案的任何改动），重新构建装机：

| 变体 | 结果 |
|---|---|
| 仅并发会话的重构（无本方案代码） | `reason=Cpp Crash`，同样崩溃 |
| 本方案合并到该重构上 | 同样崩溃 |

**结论**：崩溃出在那个**未提交的帧渲染重构**里，与本色彩方案无关。

## 4.4 崩溃定位（已缩到很窄）

在 native 侧加了帧路径打点（写 `$HOME/lgpu_steps.txt`，`LANLU_PROBE_LGPU=1` 时启用）
与 panic hook（写 `$HOME/lgpu_panic.txt`）：

```
28 frame_end:pass-begin      ← 每帧都到这一行
27 frame_end:pre-submit
27 frame_end:presented       ← 第 28 帧没有走到这里
```

- 崩溃发生在 **第 28 帧**、`begin_render_pass` 之后、`draw_recorded` 执行期间；
- `lgpu_panic.txt` **没有生成** → 不是 Rust panic，而是原生段错误/abort
  （最可能是 `draw_recorded` 里解引用的 `TexCtx` 指针已失效，或 wgpu 内部断言）；
- 主 pass 的管线目标格式已改为与离屏目标一致（`SCREEN_FORMAT`），排除格式不匹配。

### 两次排除实验（都做了，都是负结果）

| 实验 | 做法 | 结果 | 说明 |
|---|---|---|---|
| 悬空指针假设 | 加文件开关 `$HOME/lgpu_no_destroy`：淘汰页只 `texture.destroy()`、**不释放 Box** | **仍然崩溃** | 排除"`pending_destroy` 释放后仍被 `tex_instances` 引用" |
| 旧渲染路径 + 新色彩管线 | 用 16e4b2df 的内联绘制 + 方案 C，并给新符号（`snapshot_texture`/`layer_mark`/`discard_recorded`）打最小桩 | **更早崩溃**（onCreate 阶段） | 说明新引擎代码已依赖新渲染语义，不能简单退回旧路径 |

> 结论：崩溃根因仍在并发会话的帧渲染重构内部（第 28 帧、`draw_recorded` 期间、原生段错误），
> 需要该会话自己修或回滚后再谈合并与验证。

下一步（需在并发会话停下后做）：在 `draw_recorded` 每次 draw 前校验 `tex_ptr` 是否仍在
存活表里；或用 ASan/`addr2line` 解 `cppcrash` 栈（faultlog 目录当前无权限读取）。

## 5. 现状## 5. 现状

- 已修：不透明颜色逐字节正确（见上表）。
- 未修：半透明混合仍在双线性空间 → 阴影/遮罩偏亮。需方案 C。
- 附带发现：`packages/lpack-ohos/app-profiles/lanlu/cjpm.toml.ohos` 曾写死
  `/workspace/lanlu/lanlu/packages/...`，使 worktree/CI 检出无法链接；已改为
  `@REPO_ROOT@` 占位（同批提交）。
