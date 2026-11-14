# client-next 性能改善计划

- 日期：2026-11-11
- 范围：`client-next/` 及其渲染/运行时依赖 `packages/cangjie-gui`（cui + lgui）、`packages/lgpu`（Rust wgpu 原生）、`packages/qwest`、`packages/libass_ffi`、`packages/libvlc_ffi`。
- 输入：两路只读代码审计（渲染帧管线 / 数据-图片-网络管线），关键结论已人工复核（见“附录 A”）；服务端侧慢接口见 [performance-fix-plan.md](./performance-fix-plan.md)、[api-performance-report.md](./api-performance-report.md)。
- 参考开源项目：Zed GPUI、glyphon / iced cryoglyph、egui、Slint、Vello、Flutter Impeller、Mihon/Tachiyomi、Neko、Coil、libvips（链接见“附录 B”）。

---

## 落地进度

只读审计 → 计划 → 分批实现。下表按批次记录已落实到代码并验证的条目。

### 第 4 批（2026-11-12）：整段排版缓存 + 空闲阻塞唤醒

| 条目 | 改动 | 验证 |
|---|---|---|
| **R5.2 整段排版缓存** | `lgpu/native/src/lib.rs`：新增 `text_runs`（键 = 字体+字号档+文本哈希，值 = **相对起笔点**的字形四边形 + 前进宽度）。命中时跳过 char→glyph 映射、图集槽查找与 Vec 重建，直接平移后追加实例；段内任一图集页被淘汰则整段失效重排；上限 4096 条整表清空 | 7 个 Rust 单测通过（新增哈希确定性与区分度用例）；`cjpm build`（lgpu）通过 |
| **R5.2 计数** | `run_hits` / `run_miss` 进入 M0 统计行，可直接看缓存命中率 | 同上 |
| **R6 空闲不再忙轮询** | `lwindow` 导出 `lwpWaitForEvents(ms)` / `lwpWakeEventWaiter()`（复用 LWP 通道已有的 `wait`/`wake`）；`lgui` 的 `waitEventTimeout` 改为**阻塞**在注入的等待原语上，未注入时回退旧的 4ms 短轮询；`pushWakeEvent` 走注入的 wake。`client-next` 在两个事件源安装点按 `lwpInputEnabled()` 条件注入 | `cjpm build`（lwindow / lgui）通过；client-next 全量源码编译通过 |
| | 兜底：注入的等待方若立即返回 false（通道未就绪），`waitEventTimeout` 至少让出 1ms，避免退化为 100% CPU 空转 | 同上 |

### 第 3 批（2026-11-12）：图集正确性 + 书架派生缓存

| 条目 | 改动 | 验证 |
|---|---|---|
| **R5.3 图集不再丢字** | `lgpu/native/src/{lib.rs,text.rs}`：图集改**多页**（满页开新页，上限 8 页≈32MB，超出 FIFO 淘汰最旧页）；淘汰页经全局延迟销毁队列在帧末释放；新增 `glyph_index` 做 O(1) 字形查找（否则多页后每字形 O(页数)）；不再上传 4MB 空白页（wgpu 新纹理本就零初始化） | 6 个 Rust 单测通过（含「满页返回 None 而非重叠分配」「字号不串位」）；`cjpm build`（lgui/lgpu/cui）通过 |
| **溢出/批次计数** | `glyph_overflow`、`atlas_page_evict`、`rect_runs` 进入 M0 统计行 | 同上 |
| **M0 上屏打点** | `client-next/src/main.cj`：每 120 帧（`LANLU_PERF`/`LANLU_PROBE_LGPU` 开时）输出 `lgpu stats …` + 文字测量命中率；`perfStatsEnabled()` 只读一次环境变量 | 全量源码编译通过 |
| **D1 书架派生缓存** | `app/model.cj` 新增 `ShelfDerived` + `shelfDerived(key, compute)` 缓存与 `invalidateShelfDerived()`（挂在收藏/历史加载与 4 处就地刷新点）；`ui/shelf_view.cj` 把「侧栏历史计数 + 可见列表 + 最近在读」三次全量扫描合并为**一次**遍历并缓存 | 全量源码编译通过；新增 `app/shelf_derived_test.cj`（3 个用例，见下方说明） |

### 第 1~2 批（2026-11-11）

| 条目 | 改动 | 验证 |
|---|---|---|
| **M0 度量** | `lgpu/native/src/lib.rs` 新增 `FrameStats`（draw call / rect 实例 / tex 实例 / run 数 / 上传字节 / 测量次数 / 纹理创建销毁存活 / 帧数）+ 导出 `lgpu_stats_line` / `lgpu_stats_reset`；Cangjie 侧 `lgpu.statsLine()` / `lgpu.statsReset()` | `cargo test -p lanlu-lgpu-native --release` 通过；`cjpm build`（lgpu）通过 |
| **R1 纹理/字形合批** | 抽出 `tex_run_bounds()`（相邻且 `(纹理, clip)` 相同即合并），上屏路径 `lgpu_frame_end` 改走统一录制顺序的 `draw_recorded`；抓帧/快照路径共用同一分组 | 4 个 Rust 单测（含“1000 个字形 1 次 draw”用例）通过 |
| **R3 双重上传** | `lgui/src/texture.cj`：有后端画布时只上传一次（`textureFromPixelsRgba` / `updateStreamingTextureRgba`），不再重复走 `texturePixelsSink` | `cjpm build`（lgui）通过 |
| **R4 纹理回收** | 新增 `Canvas.releaseTexture(id)` + `lgui.textureReleaseSink`；`Texture.close()` 真正销毁 lgpu 纹理并从 `LgpuCanvas.textures` 移除（幂等） | `cjpm build`（lgui / lgpu）通过 |
| **R5.1 测量缓存** | `LgpuCanvas.textWidth` 加 `(text, 字号)` 缓存（上限 8192 条）+ `measureStats()` 供打点 | `cjpm build`（lgpu）通过 |
| **R7 Spinner** | `client-next/src/ui/widgets.cj`：`requestFrame()` → `requestFrameAfter(33)`（~30fps 且动画结束自动停帧） | client-next 源码编译通过 |

说明：

- **编译验证口径**：宿主机缺 libass/rocksdb/vlc 开发包，`client-next` 的 `build.cj` 预构建（C 桥接）失败——这是环境限制，与本次改动无关。验证方式是临时跳过 `client-next/build.cj`、`packages/libass_ffi/build.cj`、`packages/rocksdb_ffi/build.cj` 三个预构建脚本，让 Cangjie 编译器完整编译 `client-next` 全部源码；结果**编译通过、只在最终链接阶段因宿主缺原生库失败**。CI（`client-next.yml`）才是全链路验证口径。
- **client-next 单测无法在宿主执行**：测试二进制要链接 `-lvlc` / `-lrocksdb` / `libass.so.9`，宿主没有这些库；且并行分支此刻正在重构 `html_page_model_test.cj` / `settings_test.cj` 等文件。因此新增的 `shelf_derived_test.cj` 目前只做了源码级校验，实际执行交给 CI。Rust 侧单测可在宿主运行（不依赖上述库）。
- 工作区在实现期间出现了另一路并行改动（`lgpu_layer_mark` / `lgpu_snapshot_texture` / `draw_recorded` 录制顺序与层断点，对应本计划的 R2 绘制顺序问题），已与其合并而非覆盖：帧末统一走 `draw_recorded`。
- 尚未开始：R5.2/R5.3（run 缓存、可淘汰多页图集）、R5.4（command buffer 合并 FFI）、R6（空闲阻塞等待）、R8（截图不落盘）、R9（子树记忆化）、R10（mipmap/分片上传）、D1~D8（书架视图、worker 优先级、压缩、图片管线、JSON 写放大、启动路径）。

---

## 0. 结论速览

client-next 的架构底子是对的：脏帧驱动循环、Lazy 虚拟化列表、实例缓冲按 2 的幂复用、图片 shrink-on-load、纹理上传预算都已具备。性能问题集中在 **lgpu 迁移（P5）后遗留的“直通”实现**和**几处 UI 线程同步 I/O**：

| # | 问题 | 位置 | 影响 |
|---|---|---|---|
| 1 | 每个纹理实例（含**每个字形**）一次 draw call | `lgpu/native/src/lib.rs:983-994` | 文字多的页面每帧数千 draw，GPU/CPU 双耗 |
| 2 | 图片/视频帧**双重 GPU 上传** | `lgui/src/texture.cj:296-303, 343-353` + `ui/lgpu_backend.cj:119,190` | 上传带宽 ×2，预算统计失真 |
| 3 | `Texture.close()` 空实现，`LgpuCanvas.textures` 永不清理 | `lgui/src/texture.cj:128-134`、`lgpu/src/canvas.cj:179-213` | **显存无界增长**，256MB LRU 形同虚设 |
| 4 | lgpu 路径文字测量无缓存，每次 FFI + 多次分配 | `lgui/src/renderer.cj:849` → `lgpu/src/canvas.cj:362` → `lib.rs:1663` | 每帧每个 Label 至少测 1~2 次 |
| 5 | 字形图集固定 1024²、无淘汰，满了就**静默丢字** | `lib.rs:1688-1800`（text.rs Atlas） | 正确性 + CJK/高 DPI 下必现 |
| 6 | 空闲 4ms 忙轮询、`pushWakeEvent` 空实现 | `lgui/src/window.cj:140-157` | 空闲 ~250 次/s 唤醒，OHOS 耗电 |
| 7 | Spinner 在 `draw` 中无条件 `requestFrame` | `ui/widgets.cj:45-46` | 只要可见即 60fps 全树重建 |
| 8 | 页面转场/主题涟漪截帧：离屏重绘 + 同步 map + **落盘再读回** | `lgui/src/renderer.cj:675-722`、`ui/page_transition.cj:63` | 每次导航 8~33MB 磁盘 I/O + GPU 同步卡顿 |
| 9 | 书架视图构建时遍历 `SearchItemView`，超出 64 槽环形窗口即 RocksDB seek+get | `ui/shelf_view.cj:29,79,269`；`net/search_store.cj:162-188` | 每次重建 UI 线程 ~2-3k 次点查 |
| 10 | API 线程仅 2 条，排在 1.3~8s 的服务端搜索之后 | `net/worker.cj:45` | 冷启动首屏与交互请求队头阻塞 |
| 11 | HTTP 无压缩（不发 `Accept-Encoding`，qwest 无解码器） | `packages/qwest` | 大 JSON 原样传输 |
| 12 | 启动期同步：`webview.warmup()` 全量字体扫描、OfflineCache 在 UI 线程 `get()` | `main.cj:169`、`model.cj:2237` | 首帧前 50~300ms+ |

目标是先修正确性问题（显存泄漏、丢字、绘制顺序），然后在不改变“即时模式”编程模型的前提下，把每帧开销降一个数量级。

---

## 1. 验收指标与度量先行

### 1.1 指标（基线需在 M0 实测后填入）

| 指标 | 场景 | 目标 |
|---|---|---|
| 帧 CPU 时间 p50/p95 | 书库封面网格滚动、设置页（文字密集） | p95 < 8ms（120Hz 预算），文字页 draw call < 50 |
| 空闲 CPU | 静止窗口 60s | < 1%（无动画/视频时 0 次重绘、唤醒 ≤ 定时器所需） |
| 显存 | 书库连续浏览 500 本 / 阅读 300 页 | 稳定在 GPU 预算（256MB）± 10%，无单调增长 |
| 冷启动 | 启动 → 首帧 / → 首行封面 | 首帧 < 300ms；有 SWR 缓存时首行 < 500ms |
| 翻页 | 阅读器下一页（已预取） | < 16ms 出图；未预取 < 网络+解码时延 |
| 导航转场 | 书库 → 详情 | 无 > 33ms 卡顿帧 |
| 视频 1080p | 播放 | 无每帧托管分配；UI 线程上传 ≤ 1 次/帧 |

### 1.2 M0：补齐埋点（1~2 天，所有后续项共用）

参考 Zed GPUI 对帧预算的做法（每帧分阶段计时，超预算报警）以及 egui 的 `request_repaint` 可观测性：

1. **lgpu 计数器**（Rust 侧原子计数，`lgpu_stats()` 导出）：每帧 draw call 数、rect/tex 实例数、glyph miss 数、`write_texture` 字节数、当前纹理数与显存估算。
2. **测量计数**：`LgpuCanvas.textWidth` 调用次数 / 命中率（现有 `textMeasureCount` 只在已废弃的 SDL 路径上递增）。
3. **重绘原因**：DesktopApp 记录每帧触发源（input / state-gen / timer / requestFrame + 调用者标签），用来定位“谁让 UI 不空闲”。
4. `perf_log.cj` 改为启动时一次性读取环境变量，并使用常驻 buffered writer（现在是每行开关一次文件）。
5. 基准场景脚本化：复用 `packages/cangjie-gui/bench`（scenes/large_table/planner_scroll），新增 `client-next/bench/frame_bench.sh`，用 `--profile` + `--snapshot` 在 dummy 视频驱动下跑固定场景，输出 JSON，CI 只记录趋势，不设门槛。

---

## 2. 渲染管线（P0~P1）

### R1 纹理/字形合批（P0，最大收益）

**参考**：Zed GPUI 把同类图元（quad/shadow/sprite）按类型收集成实例数组，一种图元一次 instanced draw，单色字形与多色精灵共享图集纹理（[Zed 博客](https://zed.dev/blog/videogame)）；glyphon 把所有文字写进一个图集，用一个 vertex buffer 一次绘制（[glyphon](https://github.com/BillyDM/glyphon)）。

**改动**（`lgpu/native/src/lib.rs` frame_end）：
- 把 `tex_instances` 写入**一个**连续 vertex buffer（已经是这样），再按 `(texture_ptr, clip)` 把**相邻**实例合并为 run，每个 run 只调一次 `draw(0..6, start..end)`，只有在纹理或裁剪变化时才重新 set bind group / scissor。
- `set_pipeline` 与 group 0 移出循环。
- 去掉 frame_end 里每帧额外收集的 `Vec<TexInstance>`，改为复用 ctx 上的成员。

**预期**：文字页的 draw call 从“字形数”降到“纹理切换次数”（通常 < 20）。

### R2 恢复绘制顺序（P0，正确性）

当前先画全部 rect、再画全部纹理/文字，导致后绘制的模态背景、遮罩被下层的文字和图片“穿透”。

**参考**：GPUI 使用 `order`（z/绘制序）+ 按图元类型的 batch 迭代器，在保持画家顺序的同时合批；Vello hybrid 用同一 pass 内“图层序 + 图集”的方式处理外部纹理（[vello#1552](https://github.com/linebender/vello/pull/1552)）。

**方案**：录制时给每个图元分配单调递增的 `seq`。frame_end 按 seq 把 rect 与 tex 交错切分为若干 “segment”，segment 内同类合批。这样文字页仍只有少量切换，而 Modal 等覆盖层能正确遮挡。也可以更进一步合并为一条 uber pipeline（rect 也当作“无纹理采样”的实例），彻底避免 pipeline 切换。

### R3 修掉双重上传与视频帧拷贝（P0，小改动）

- `lgui/src/texture.cj`：`textureFromPixelsRgba` / `updateStreamingTextureRgba` 在已有 `backendCanvas()` 时**不再**调用 `texturePixelsSink`（或在 `lgpu_backend.cj:119,190` 移除指向同一 `uploadTexture` 的 sink 注册）。二选一，并加单测断言“上传次数 == 1”（用 M0 计数器）。
- `textureFromNativeRgba` / `updateStreamingTextureNativeRgba`（`texture.cj:379-412`）：新增 `lgpu_upload_texture_native(ptr, len, stride)`，直接把原生指针交给 `queue.write_texture`，去掉每帧 w×h×4 的托管数组分配与 memcpy。
- 视频：`FRAME_MUTEX` 只保护“交换双缓冲指针”，上传在锁外进行（`libvlc_ffi.cj:107-175`、`reader_stage.cj:1053`），避免阻塞 VLC 解码线程。
- 1080p 视频可考虑 I420/NV12 三平面纹理 + 着色器转 RGB，上传量降为 37.5%（mpv/libplacebo 的标准做法）。放在 P2。

### R4 纹理生命周期与显存预算（P0，正确性）

- `Texture.close()` 调用 `canvas.destroyTexture(id)`，lgpu 侧 drop `TexCtx`（wgpu Texture / View / BindGroup），并从 `textures`/`textureSizes` 中移除。
- 注意帧内安全：被本帧 `tex_instances` 引用的纹理延迟到 `frame_end` 提交后再销毁（加一个 `pending_destroy` 列表）。
- `pixel_texture_cache` 的 GPU LRU 改为以 lgpu 上报的真实显存为准，淘汰时实际销毁纹理。
- 参考 Flutter Impeller 的 RenderTargetCache：按帧时钟淘汰“N 帧未使用”的资源，同时警惕其已知坑（离屏渲染推进帧时钟，导致误淘汰在屏资源，见 [flutter#194307](https://github.com/flutter/flutter/issues/194307)）。我们的离屏抓帧（R8）**不得**推进 LRU 帧计数。

### R5 文字：测量缓存 + 可淘汰图集（P0/P1）

**参考**：glyphon / iced cryoglyph 使用 etagere 分配图集，按“本帧是否使用”做 LRU 淘汰，提供 `trim()`；图集满时先淘汰、再**扩容**，而不是失败（[glyphon](https://github.com/BillyDM/glyphon)、[cryoglyph](https://github.com/iced-rs/cryoglyph/tree/update-wgpu)）。cosmic-text 缓存 shaping 结果（`Buffer`/`ShapeLine`），文本未变就不重排。

1. **测量缓存（P0）**：在 `LgpuCanvas` 加 `HashMap<(fontId, sizeQ, String), Float32>`，按容量做 LRU（如 8k 条）。命中时完全不进 FFI。宽度只取决于字体与字号，可以安全地跨帧复用。`ellipsize` 的全局缓存一并改为按 (text,size,maxW) 命中，不再先测全宽。
2. **字形 run 缓存（P1）**：Rust 侧 `lgpu_text_draw` 按 `(font, size, text_hash)` 缓存已排版好的 glyph quad 列表（相对坐标），命中时只做平移后追加到实例缓冲。每次调用只拿一次锁，不再为每次调用分配 String/Vec。
3. **图集（P1）**：
   - 改为单通道 R8 coverage 纹理（彩色 emoji 另开 RGBA 页），显存与上传量降为 1/4；
   - 多页图集：满时先淘汰本帧未使用的字形，仍不够就新开一页，**绝不丢字**；
   - glyph miss 先在 CPU 侧暂存，帧末**一次** `write_texture` 写脏矩形，而不是每个字形单独上传；
   - 创建时不再上传 4MB 空白缓冲（wgpu 新纹理默认就是零初始化）。
4. **全局 Mutex（P1）**：`lock_surface` 每个图元都要取一次。改为 Cangjie 侧把一帧的图元录进共享内存的 command buffer，帧末一次 FFI 提交（GPUI 的 Scene 也是先收集再统一上 GPU）。这一步需要 R1/R2 先落地。

### R6 空闲真正零开销（P0）

**参考**：egui/eframe 默认按需重绘，靠 `request_repaint` / `request_repaint_after` 驱动，空闲时阻塞在事件循环上（[egui Context](https://docs.rs/egui/0.36.2/egui/struct.Context.html)）。

- `lgui/src/window.cj` 的 headless `waitEventTimeout`：改为阻塞等待一个条件变量 / eventfd（LWP 事件到达、`pushWakeEvent`、定时器截止三者之一唤醒），去掉 4ms sleep 轮询。OHOS 侧由 XComponent 回调直接 signal。
- `pushWakeEvent` 实现为 signal 同一个条件变量。worker 的 `requestWake()` 现在实际依赖轮询，修好之后结果投递延迟从 ≤4ms 降到亚毫秒。
- `lgpu_backend.cj:512-541` 每个事件都 `getVariable()`，改成启动时读一次并缓存为 `let`。
- `main.cj:254-282` / `lgpu_backend.cj:61,662`：probe trace 在 release 下默认关闭（启动时决定），字符串拼接放进闭包里惰性构造。
- `main.cj:85-91` `syncTitleBarDragRegion`：先比较后分配（或用 generation 号），不要每 tick 分配数组。

### R7 消除不必要的连续重绘（P0）

- `Spinner`（`widgets.cj:45`）：改成在 `draw` 中 `requestFrameAfter(33)`（≈30fps 足够），并且只在 Spinner 实际出现在可见区时请求。更好的做法是由 M0 的“重绘原因”统计来兜底。
- 统一审计 `requestFrame` 调用点，原则是“动画结束必须停”，用 M0 的重绘原因统计做回归检查。参考 GPUI 的 reduced-motion 与帧预算处理（GPUI 的 motion 指南见附录 B）。

### R8 转场/涟漪截帧走 GPU 内部（P1）

`captureFramePixels`（`renderer.cj:675-722`）现在是：离屏重绘 → 同步 map → 写 `$HOME/.lgui_capture.rgba` → 读回 → 双重上传。

lgpu 已经有 `lgpu_capture_offscreen`（commit 76599a3b/adc5bc69），改造如下：
- 新增 `lgpu_snapshot_to_texture(id)`：把上一帧（或当前已录制的帧）直接 `copy_texture_to_texture` 到一张新的可采样纹理，**全程不读回 CPU、不落盘**。
- 更省的做法是把 swapchain 的上一帧保留成 render target（surface 设置 `COPY_SRC` usage），转场时直接拷贝。
- ThemeRipple 的两次截帧合并为一次（新主题那一帧由下一帧正常渲染，不必截图）。

### R9 即时模式下的“保留”优化（P1~P2）

全树重建本身可以接受（egui、GPUI 的 element 层都是每帧重建），关键在于让重建**便宜**：

1. **按局部 generation 跳过**（P1）：把全局 generation 计数器（`core/state.cj:214`）拆成按 State 归属的 scope。顶层页面级子树（titlebar / 侧栏 / 内容区）用 `Memo(key, deps)` 包起来，依赖没变就复用上一帧的 layout 结果与绘制命令列表（GPUI 的 `cached` view 与 Flutter `RepaintBoundary` 都是这个思路）。
2. **Label 缓存外置**（P1）：Label 的宽度/换行缓存从实例字段改为 StateStore 中按 (text, font, size, maxW) 键控的缓存，跨帧存活。配合 R5.1 基本消除重复测量。
3. **局部重绘**（P2）：参考 Slint 软件渲染器的 dirty region 部分重绘（[Slint SoftwareRenderer](https://docs.slint.dev/latest/docs/rust/slint/platform/software_renderer/struct.SoftwareRenderer.html)）。GPU 路径下收益主要在功耗（OHOS 2in1）。先用 Memo 子树的命令缓存实现“只重建脏子树”，再评估 scissor 部分重绘。

### R10 图片纹理质量与上传（P1）

- 封面缩略图生成 mipmap（`mip_level_count > 1`，上传后用 compute/blit 生成），或者让 vips 直接按显示尺寸 × DPR 解码，消除缩小显示时的锯齿与闪烁。
- 上传预算按**实际**上传字节计（R3 修完后自然正确）。单张超过预算的大图（2000px 页 ≈16~22MB）按行带分片上传，跨帧完成，避免一次卡一帧。参考 wgpu `StagingBelt` 复用 staging 缓冲（[gogpu/wgpu StagingBelt 实现](https://github.com/gogpu/wgpu/blob/v0.28.3/staging_belt.go)）。
- 阅读器超大页（长条漫）：参考 Mihon 的 subsampling-scale-image-view，按视口分块（tile）+ 按缩放比选取 subsample 级别解码，不必把整张超长图常驻显存（[mihonapp/subsampling-scale-image-view](https://github.com/mihonapp/subsampling-scale-image-view)）。Neko 在阅读器里使用 hardware bitmap，减少 CPU 侧像素副本（[Neko#2654](https://github.com/nekomangaorg/Neko/pull/2654)）；对应到我们这里，就是解码结果上传后立即释放 staged 像素（见 D4）。

---

## 3. 数据、网络与存储（P0~P2）

### D1 书架视图去除 UI 线程 RocksDB 扫描（P0）

`shelf_view.cj:29,79,269` 在每次构建时调用 `visibleShelfItems` / `historyCount` / `mostRecentHistory`，遍历整个 `SearchItemView`（pageSize=1000）。

- 计数和“最近一条”在加载/变更时算好，存进 `State<Int64>`、`State<?Item>`，视图里只读。
- 过滤结果（visibleShelfItems）在数据或过滤条件变化时计算一次，缓存成 `ArrayList` 快照；渲染只通过 Lazy 网格访问可见区。
- `toggleFavorite` 的线性扫描（`model.cj:3406,3448,3461,3488,3542`）改为维护 `id → index` 映射。
- 补一个单测：用计数型 fake store 断言“一次 shelf 视图构建的 store 读取次数 ≤ 可见项数 + 常数”（沿用服务端计划中“按 SQL 次数上限断言”的思路）。

### D2 Worker 线程与优先级（P0）

- API 线程 2 → 按用途拆成两条队列：**交互队列**（me / meta / progress / 收藏 / 翻译，2 线程）和**批量队列**（search 行 / searchAll / tankoubons，2~3 线程），交互请求不再排在慢搜索后面。
- 冷启动 `me → categories → rows` 改为并行：`me` 与 `categories` 同时发出，rows 只依赖 categories；同时把 `/api/info` 等非首屏请求延后。
- 网络层取消：qwest 支持 `cancel()`（关闭底层 socket）。离开页面、快速滚动时取消在途的封面请求，最多浪费一个 RTT。

### D3 HTTP 压缩与连接（P1）

- qwest 增加 `Accept-Encoding: gzip`（可选 br）与流式解压（zlib FFI，或复用 vips 依赖链里已有的 zlib）。服务端计划 P0-x 已经加了 gzip（performance-fix-plan.md:121），两边配合后 `/api/tags/translations` 1.4MB 预计压到 < 600KB。
- 设置 `TCP_NODELAY`；响应头解析的 16KB 行缓冲改为线程局部复用。
- 评估 HTTP/2：图片多路复用在高 RTT 下收益明显，但实现成本高，暂列为 P3，只做调研。

### D4 图片管线（P1）

**参考**：Coil / Glide 的三级缓存（内存位图 → 磁盘 → 网络）、请求随视图 detach 自动取消、按目标尺寸采样解码（[Android 图片优化指南](https://developer.android.com/develop/ui/compose/graphics/images/optimization)）；libvips 官方建议首选 `vips_thumbnail`，它会自动选择 shrink-on-load，并对 JPEG/WebP/HEIF/AVIF 都生效（[libvips developer checklist](https://www.libvips.org/API/8.17/developer-checklist.html)）。

1. **解码改用 `vips_thumbnail_buffer` / `vips_thumbnail`**（`vips_decode.cj:116-152, 407-420`）：一次打开、自动 shrink-on-load（AVIF/HEIF 走 `thumbnail` 的内嵌缩略或 subsample），对小目标用 `access=sequential`。去掉 3 次打开文件和手写的 shrink/scale 分支。
2. **持久化“显示尺寸”衍生图**：封面/缩略图在首次解码后，把目标尺寸的结果（WebP/QOI，或者直接 RGBA + 头部）写进 `<key>@w400.thumb`，下次命中跳过全尺寸解码。阅读页（2000px）仍缓存原图。
3. **磁盘 LRU 修正**（`image_cache.cj:191-220`）：命中时更新访问时间（`utimes`，或在 RocksDB 维护 `key → (size, atime)` 索引）。淘汰从索引取最旧项，不再整目录 `readFrom` + 排序；`totalBytes()` 改为增量维护。
4. **内存预算**：staged 96MB 只够约 4 张 2000px 页。纹理上传成功后**立即释放** staged 像素（GPU 持有即可），让 staged 预算只覆盖“已解码未上传”的短暂窗口；GPU 预算由 R4 真实统计。预取窗口（±2）可以随之放宽到前 3 后 1。
5. **取消与优先级**：书库封面在 Lazy 项离开可见区时 `cancelImage`。队列改为按优先级的双端结构 / 索引堆，`cancelImage` O(1) 标记 + 惰性丢弃，`finishImageTask` 不再 `remove(at:0)`。
6. 封面圆角改为着色器实现（lgpu 已有 `lgpu_draw_texture_rounded`，commit 16e4b2df），不再在 worker 上逐像素处理，同一份解码结果可以复用于不同圆角。

### D5 JSON 与写放大（P1）

- `json_codec.cj:28` `decodeRaw<String>` 对每个字符串字段重新构造 JsonReader。改成直接从当前 reader 读取 token；`rawText` / `parseEnvelope` 改为一次遍历解析 envelope 和 data，消除二次解析（dto.cj 共 132 + 30 处，可以用宏或代码生成批量替换）。
- `checkedBodyCached → storeResponse`（`lanlu_api.cj:205-210`）与 `search()` 的逐项 entity 批写（`lanlu_api.cj:380`、`search_store.cj:373`）：
  - 写 RocksDB 移到独立的低优先级“持久化线程”，不占 API 线程；
  - 同一 key 内容未变（比较 ETag 或 body hash）就跳过写入；
  - 搜索结果优先只写 entity，原始 body 可以不再重复缓存（两者二选一）。

### D6 启动路径（P1）

- `webview.warmup()`（`main.cj:169`）：改为首次打开 HTML 页面时惰性初始化，或者在首帧之后放到后台线程预热。
- OfflineCache：`tryResumeSession` 不在 UI 线程 `f.get()`（`model.cj:2237`）。恢复会话期间先用设置库里的 token 发起 `me`，离线缓存就绪后再做 SWR 填充。
- `lwpAwaitSystemInfo(300)`：先用默认值创建窗口，system info 到达后再修正 DPI/尺寸，不在启动时阻塞等待。
- `ApiWorker` 13 条线程按需惰性启动（字幕线程、上传池在首次使用时创建）。
- 目标：首帧前只保留 “设置库打开 + 窗口/渲染器创建 + 字体加载”。

### D7 设置写入与 UI 线程 I/O（P2）

- `persistSettings` 防抖的 leading 写当前同步发生在 UI 线程（`settings.cj:510-560`）。改为全部异步（只保留 trailing 写），退出时 flush。
- `SearchItemView.itemAt` 的环形窗口（64 槽）对顺序扫描无效。顺序访问时一次性批量预读一页（RocksDB iterator 连续读），或者对 ≤1000 的视图直接物化到内存。

### D8 字幕（P2）

- `libass_ffi.cj:124` 逐字节 lambda 拷贝改为 `memcpy`（`acquireArrayRawData` + 块拷贝），或直接走 R3 的原生指针上传。
- libass 的 `render()` 每帧在 UI 线程执行（`playback_model.cj:639`）。移到字幕线程，提前一帧渲染，UI 线程只做 `changed` 时的上传。

---

## 4. 里程碑与排期

| 里程碑 | 内容 | 预估 | 退出标准 |
|---|---|---|---|
| **M0 度量** | §1.2 全部 | 1~2 天 | 基准脚本可复现；基线数字写回 §1.1 |
| **M1 正确性 + 速赢** | R3、R4、R6、R7、R5.1、D1、D6（warmup 惰性化） | 1 周 | 显存稳定；空闲 0 重绘；文字测量命中率 > 95%；书架重建 store 读取 ≤ 可见项数 |
| **M2 GPU 合批** | R1、R2、R5.3（多页图集 + R8 coverage） | 1~1.5 周 | 文字页 draw < 50；Modal 遮挡正确（快照测试）；CJK 压测零丢字 |
| **M3 网络/图片** | D2、D3、D4.1~4.5、D5 | 1.5 周 | 冷启动首行指标达标；滚动时取消率可观测；JSON 解析 CPU 降 ≥ 30% |
| **M4 架构级** | R5.2、R5.4（command buffer）、R8、R9.1~9.2、R10 | 2~3 周 | 帧 p95 < 8ms；转场无 > 33ms 帧 |
| **M5 打磨** | R9.3、D7、D8、YUV 视频、HTTP/2 调研 | 按需 | — |

依赖关系：R2 依赖 R1 的 run 切分；R5.4 依赖 R1/R2；D4.4 依赖 R4；R10 的分片上传依赖 R3。

## 5. 测试与回归保护

- **单测**（`cjpm test`）：
  - 纹理上传次数 == 1（R3）；
  - `close()` 后 lgpu 纹理数减少（R4）；
  - 测量缓存命中（R5.1）；
  - shelf 构建的 store 读取上限（D1）；
  - 图片队列取消为 O(1)，且不会丢掉高优先级任务（D4.5）；
  - JSON 解析结果与旧实现逐字段一致（D5，用 `dto_test.cj` 现有样本做对拍）。
- **快照测试**：`--snapshot` + `SDL_VIDEODRIVER=dummy`，增加“Modal 覆盖文字/图片”的场景，像素比对锁住 R2 的绘制顺序。
- **基准趋势**：M0 的 frame_bench JSON 进 CI artifact，PR 描述附前后对比；`perf_bench_test.cj` 保持现状。
- **真机**：OHOS 2in1 上每个里程碑跑一次空闲功耗与滚动帧率（沿用 R62 真机视觉验收方式）。

## 6. 风险

| 风险 | 缓解 |
|---|---|
| R2 交错 segment 让 draw 数回升 | 先合并为 uber pipeline；用 M0 计数器验证 |
| 纹理延迟销毁时机错误导致 use-after-free / wgpu 校验错误（参考 adc5bc69 的抓帧崩溃根因） | `pending_destroy` 在 `queue.submit` 之后才释放；开启 wgpu validation 跑一遍快照测试 |
| Memo 子树依赖漏写导致 UI 不刷新 | 依赖默认取 scope 内读取过的 State（自动追踪），debug 构建下每 N 帧强制全量重建并比对命令列表 |
| `vips_thumbnail` 色彩/方向行为与旧实现不同 | 对 `vips_decode_test.cj` 的样本逐像素对比，autorot 行为单独验证 |
| qwest 取消打断 keep-alive 连接 | 被取消的连接直接丢弃，不回池 |

---

## 附录 A：已人工复核的关键证据

- `lgpu/native/src/lib.rs:978-994`：注释原文“纹理：每张纹理一次 draw（bind group 不同，无法合批）”，循环内每个实例都 `set_pipeline` + 两次 `set_bind_group` + `draw(0..6, 0..1)`。
- `lgui/src/texture.cj:296-303`：先 `canvas.uploadTexture`，再调 `texturePixelsSink`；`:128-134` 的 `close()` 只设置标志位。
- `lgui/src/window.cj:140-157`：`pollEvent` + `sleep(4ms)` 循环；`pushWakeEvent` 为空实现。
- `client-next/src/ui/widgets.cj:45-46`：`draw` 首行 `ctx.requestFrame()`。
- `client-next/src/net/worker.cj:45`：`API_THREADS = 2`。
- `client-next/src/ui/shelf_view.cj:29,79`：视图构建中调用 `visibleShelfItems(model)` / `historyCount(model.shelfHistory.value)`。
- `packages/lgpu/src/canvas.cj:179-213`：`textures`/`textureSizes` 只插入、不删除。

## 附录 B：参考的开源项目与资料

| 项目 | 借鉴点 | 对应条目 |
|---|---|---|
| [Zed GPUI — Leveraging Rust and the GPU to render UIs at 120 FPS](https://zed.dev/blog/videogame) | 按图元类型实例化合批、字形图集、帧预算 | R1 R2 R5 |
| [GPUI 元素树分析（buiy prior-art）](https://github.com/intendednull/buiy/blob/main/docs/prior-art/gpui/element-tree.md) | 每帧重建 element + 缓存 view | R9 |
| [GPUI 帧预算与 reduced motion](https://raw.githubusercontent.com/curiositech/port-daddy/refs/heads/main/skills/rust-gpui-motion/references/04-frame-budget-and-reduced-motion.md) | 动画结束停帧、帧预算 | R7 |
| [glyphon](https://github.com/BillyDM/glyphon) / [iced cryoglyph](https://github.com/iced-rs/cryoglyph/tree/update-wgpu) | wgpu 文字：etagere 图集、LRU trim、单 buffer 绘制 | R5 |
| [egui Context（request_repaint / request_repaint_after）](https://docs.rs/egui/0.36.2/egui/struct.Context.html) | 按需重绘、空闲阻塞 | R6 R7 |
| [Slint SoftwareRenderer（partial rendering）](https://docs.slint.dev/latest/docs/rust/slint/platform/software_renderer/struct.SoftwareRenderer.html) | 脏区域部分重绘 | R9.3 |
| [Vello hybrid 外部纹理 + 图集 PR](https://github.com/linebender/vello/pull/1552) | 混合渲染中图集与绘制序 | R2 |
| [Flutter Impeller RenderTargetCache 问题](https://github.com/flutter/flutter/issues/194307) | 帧时钟淘汰与离屏渲染陷阱 | R4 R8 |
| [gogpu/wgpu StagingBelt](https://github.com/gogpu/wgpu/blob/v0.28.3/staging_belt.go) | staging 缓冲复用、分片上传 | R10 |
| [Mihon subsampling-scale-image-view](https://github.com/mihonapp/subsampling-scale-image-view) | 超大图分块 + subsample 解码 | R10 |
| [Neko：阅读器使用 hardware bitmap](https://github.com/nekomangaorg/Neko/pull/2654) | 上传后释放 CPU 像素副本 | R10 D4.4 |
| [Android 位图优化（下采样）](https://developer.android.com/develop/ui/compose/graphics/images/optimization) / Coil、Glide | 三级缓存、按目标尺寸解码、请求随视图取消 | D4 |
| [libvips developer checklist](https://www.libvips.org/API/8.17/developer-checklist.html) | 首选 `thumbnail`、shrink-on-load、sequential | D4.1 |

## 附录 C：真机帧率实测（MOR-M1 2in1，2026-11-14）

采样方法：壳层 `lwpAttachStats()` 的 frames 计数（每 ~5s 打一行 hilog），相邻样本差 / 间隔秒 = fps。
窗口 2090×1394（scale 1.9）；build = a8f851d7（交换链取帧修复 + 离屏容量复用之后）。

| 操作 | fps | 说明 |
|---|---|---|
| 首页空闲 | 0（偶发 1 帧定时器） | 零渲染生效：无请求帧时主循环阻塞等待 |
| 首页滚动（连续 fling） | 平均 59.7（窗口 46–64） | 接近满帧；低谷来自 fling 起步的整树重建 |
| 详情页打开/返回 | 转场 50–53 | 转场结束后回 0 |
| 主题切换 | 2 帧 | 瞬时全量重绘一次（无涟漪动画时的正确行为） |
| 窗口缩放（连续边缘拖拽） | 66.8 | 见 a8f851d7：修复取帧 SIGABRT + 离屏容量复用 |

已知剩余项：滚动低谷（fling 起步全树重建）与缩放时的 swapchain 重配开销，见 R9/R6。
