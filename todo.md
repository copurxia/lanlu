# client-next 多字幕渲染实施计划

> 初版：2026-08-09
> 评审补全：2026-08-12
> 状态：主体实现、Linux 构建/自动化测试完成；真实大文件首扫、渲染、缓存命中及定位样式专项已通过，Windows 验收待执行

### 2026-08-12 执行记录

- 已完成产品主链路：安全 FFmpeg/libass FFI、一次扫描、协作取消、版本化原子缓存、不可变
  media proxy route、独立字幕 worker、PlaybackModel 多选状态、VLC 字幕强制关闭、reader dock
  与视频同矩形 RGBA 合成。
- 已完成 Linux 本机验收：`libavformat_ffi` 7/7、`libass_ffi` 5/5、`client-next` 196/196，
  无临时 include/library 环境变量的 `cjpm clean && cjpm build -V` 成功；通过 Linux Computer Use
  在终端执行 `cjpm run`，启动日志进入 main loop，真实窗口可交互。
- 真实大文件 E2E 使用“复仇公主斯嘉丽”第 6 页（档案详情显示 6 页、15.2 GB）执行：字幕扫描
  已改为携带 Bearer 的 libavformat 直连，不再经本地 media proxy 二次转发；上游在约 4.2 GB 后
  提前断流时，FFmpeg 通过 Range 自动重连并继续扫描。首扫约 83 秒完成，产出 4 轨 × 1287 个
  ASS 事件，缓存文件 366,031 字节；进程观测峰值 RSS 约 1.52 GB（非托管堆专项值）。
- Linux Computer Use 实测字幕菜单枚举 `chs/cht × SDR/HDR` 共 4 条内嵌轨，简体 SDR、繁体 SDR
  可同时勾选，20:39 画面已由 libass 渲染字幕且没有原始 ASS 标签泄漏。退出阅读页后第二次打开，
  约 4 秒内直接得到 4 轨且不再出现 `Extracting subtitles…`，缓存 mtime/大小保持不变，确认命中缓存。
  再通过进度条和 `+5s` 控件跳到真实事件：104:09 的 `\an7` 日/中双行字幕稳定落在左上角，
  104:24 的 `\an8` 日文落在顶部居中，同时保留中央标题、底部中文等独立样式层；颜色、描边、
  换行和定位正确，未显示原始 ASS 标签。P8 本地 E2E 条目据此完成。
- CI 已接入 Linux/Windows 原生依赖、构建和 DLL 收集，但本轮没有 Windows runner，因此相关
  条目仍保持未完成。
- 尚需专项迭代/验收：播放帧时间与纹理上传计数、Windows CI 实跑、
  位图字幕二进制夹具、媒体验证器与字幕缓存 LRU、视频 SAR、完整字幕状态 UI 快照矩阵。

## 1. 结论与一期边界

**视频字幕不再交给 VLC 加载或渲染，统一由 libavformat/libavcodec 抽取，
libass 渲染，reader stage 合成。**

- 内嵌文本字幕支持多选并同时显示，不限制选择数量。
- 外挂 ASS/SRT/VTT 与内嵌字幕进入同一套 libass 渲染管线。
- 视频播放仍由 libVLC 负责；视频 lane 始终强制 `libvlc_video_set_spu(-1)`，
  避免 VLC 与 libass 重复渲染。
- 运行时不依赖 `ffprobe`/`ffmpeg` 外部二进制。
- 一期支持 ASS/SSA、SubRip、WebVTT、mov_text 文本字幕；PGS、DVB、DVD 等位图字幕
  只枚举并标记“不支持”，不渲染、不 OCR。
- 一期使用系统字体提供器（Linux fontconfig、Windows DirectWrite/自动探测）兜底。
  MKV 内嵌字体附件抽取属于二期，因此一期验收口径是“标签、定位、颜色和基础样式正确，
  缺失字体允许回退”，不承诺与 VLC 像素级一致。
- 一期只覆盖仓库当前发布平台 Linux x86_64 和 Windows x86_64；不新增 macOS 目标。

## 2. 已验证事实与待验证假设

### 2.1 已验证

1. libVLC 3.0.23 的 `libvlc_video_set_spu` 只能选一条主字幕轨；VLC 4 的副字幕 API
   在本机 libVLC 3 头文件中不存在，无法靠 VLC 3 实现内嵌字幕多轨同屏。
2. 15.2GB MKV（4 条内嵌 ASS）已用 ffprobe/ffmpeg 子进程验证过枚举和双轨抽取可行；
   子进程只用于前期验证，不进入产品实现。
3. 纯文本 overlay 会把 ASS 覆盖标签当字面量显示，不能满足样式和定位要求。
4. 大文件字幕抽取需要顺序扫描整个容器，经 HTTP 代理可能耗时数分钟，因此必须异步、
   可取消、可缓存，并在一次扫描中抽取全部目标轨。
5. 当前开发机有 libavformat 62、libavcodec 62、libavutil 60 的开发头文件和链接库；
   只有 `libass.so.9` 运行库，没有 libass 开发头文件、`libass.pc` 和 `libass.so` 开发链接。

### 2.2 实现前必须验证

- [x] 安装 libass 开发包后，确认 `pkg-config --modversion libass`、最小链接和最小渲染程序成功。
- [x] 用真实 MKV 验证 libavformat 读取 `codecpar->extradata`，并将 Matroska ASS 的
      CodecPrivate + packet chunk 交给 libass 后可正确还原样式。
- [x] 用大于 64MiB 的测试流验证 media proxy 连续读取不会在 32MiB 边界产生假 EOF。
- [ ] 验证 libVLC 与 libavformat 对同一上游媒体并发 Range 读取时互不污染、可独立 seek。
- [ ] 验证 Windows MSYS2 的 FFmpeg/libass 版本、import library 名称和运行时 DLL 集合。

任一验证失败时，先修正本计划中的数据契约或部署方案，再进入 PlaybackModel 集成；
不得在上层用特殊分支掩盖 FFI/代理问题。

## 3. 数据契约

### 3.1 字幕流描述

`probeSubtitleStreams` 返回稳定的容器流索引，不使用 VLC 的 ES id：

```text
SubtitleStreamInfo
  streamIndex: Int32
  codecId: Int32
  codecName: String
  title: String
  language: String
  isDefault: Bool
  isForced: Bool
  isText: Bool
  supported: Bool
  unsupportedReason: String
```

- metadata 缺失时使用空字符串，不抛异常。
- 默认预取轨：第一条 `supported && isDefault`；不存在时取第一条 `supported`。
- “默认轨”只决定后台预取，不自动选中，不改变用户的字幕选择。
- PGS/DVB 等流仍返回列表项，但 `supported=false`，UI 禁用并显示原因。

### 3.2 抽取产物

删除含义不清的 `extractSubtitleText`，改为：

```text
extractSubtitleTracks(url, requestedStreamIndexes, cancelToken)
    -> ArrayList<ExtractedSubtitleTrack>

ExtractedSubtitleTrack
  streamIndex: Int32
  codecName: String
  codecPrivate: Array<UInt8>
  events: ArrayList<SubtitleEvent>

SubtitleEvent
  startMs: Int64
  durationMs: Int64
  payloadKind: MatroskaAssChunk | AssEvent | PlainText
  payload: Array<UInt8>
```

规则：

- ASS/SSA：保留 CodecPrivate；每个 Matroska packet 保留 chunk 字节，并用 stream time base
  将 PTS/duration 换算为毫秒。渲染时依次调用 `ass_process_codec_private` 和
  `ass_process_chunk`，不能把 packet 假设成完整 `.ass` 文件。
- SRT/VTT：payload 只表示文本内容，时间来自 packet PTS/duration；转换为规范 ASS 时必须
  正确处理换行、BOM、UTF-8 校验和 ASS 特殊字符，不能丢时间轴。
- mov_text：为该 stream 创建并打开 `AVCodecContext`，调用
  `avcodec_decode_subtitle2`；读取 `AVSubtitleRect.ass/text`，每次成功后调用
  `avsubtitle_free`，EOF 时按解码器要求 flush。
- `AV_NOPTS_VALUE`、负时长、时间溢出、空 packet 和畸形 UTF-8 都要有明确的跳过或报错
  规则；单个坏事件不得造成越界或资源泄漏。
- 首次发生抽取需求时，默认在**一次 `av_read_frame` 顺序扫描中收集所有受支持文本轨**，
  而不是每条轨各扫描一次。`requestedStreamIndexes` 保留用于测试和未来受限模式。
- 产物只包含托管内存，不把 AVPacket、AVSubtitle 或其他原生指针跨线程传给 UI。

### 3.3 外挂字幕产物

- 外挂 ASS：保留完整原始字节，经 UTF-8/BOM 校验后用 `ass_read_memory` 创建轨。
- 外挂 SRT/VTT：本地解析为带 start/end 的 cue，再生成具有固定默认样式的完整 ASS 文档；
  一期保留换行及基础 `<b>/<i>/<u>`，其他 HTML 标签按纯文本安全转义。
- 外挂字幕继续限制单文件大小，但超限、编码错误和解析失败必须成为可见的轨级错误，
  不能静默变成空字幕。
- 删除视频路径对 `activeSubtitleTexts`/`drawSubtitleOverlay` 的依赖；歌词/音频 overlay 不变。

## 4. 生命周期、线程与错误模型

### 4.1 原生资源

- libavformat/libavcodec 与 libass 的所有句柄使用实现 `Resource` 的确定性包装；
  不依赖 `~init` 释放系统资源。
- 释放顺序：
  - FFmpeg：`AVSubtitle` -> `AVPacket` -> `AVCodecContext` -> `AVFormatContext`；
  - libass：全部 `ASS_Track` -> `ASS_Renderer` -> `ASS_Library`。
- 初始化中途失败、读取异常、取消和正常 EOF 必须走同一套 `finally`/try-with-resources 清理。
- `unsafe` 只放在 FFI 封装内部；公共 API 不暴露可写原生指针。
- `avformat_open_input`/`avformat_find_stream_info`/`av_read_frame` 是可能长时间阻塞的调用，
  不标记 `@FastNative`，也不在 UI 线程执行。

### 4.2 线程归属

- libavformat 扫描只在独立字幕扫描 worker 中执行。
- libass 的 library、renderer、track 只在 UI/渲染线程创建、访问和释放，不跨线程共享。
- worker 只回传不可变的 `SubtitleStreamInfo`/`ExtractedSubtitleTrack` 托管对象。
- 每项结果携带 `mediaGeneration` 和稳定媒体标识；切页后的迟到结果可写入其合法缓存，
  但不得更新当前 PlaybackModel 或当前 UI。
- 取消采用协作式 token。C bridge 为 `AVFormatContext.interrupt_callback` 提供只读原子标志，
  使阻塞 I/O 能尽快退出；切页、关闭客户端和清理媒体时都发出取消。

### 4.3 错误分类

至少区分并保留上下文：`OpenFailed`、`ProbeFailed`、`UnsupportedCodec`、`DecodeFailed`、
`Cancelled`、`ProxyReadFailed`、`CacheCorrupt`、`RenderInitFailed`。日志只记录媒体缓存键、
stream index、codec 和错误码，不记录 Authorization token 或完整带密钥 URL。

## 5. 分阶段任务

### P0：基线清理与测试夹具

- [x] 删除 `probeMediaDuration` 和 `std.process.executeWithOutput` 导入。
- [x] `model.cj` 的 playback worker 载荷由 `(key, path, dur, lyrics)` 改为
      `(key, path, lyrics)`；音视频时长保持 `0=未知`，开播后统一由
      `refreshVlcState`/`takeVideoFrame` 回填。
- [x] 修正 PlaybackModel 中仍声称“下载后由 ffprobe 回填”的过期注释。
- [ ] 增加不依赖外部 ffmpeg 二进制的最小媒体夹具：ASS/SSA、SRT、VTT、mov_text、
      unsupported bitmap 标识各一；记录生成方式、来源和许可。
- [ ] 保存真实 15.2GB MKV 只作为本地 E2E 夹具，不提交仓库、不进入普通 CI。

验收：`rg "ffprobe|probeMediaDuration" client-next` 无产品代码命中；现有
`client-next` 单测全绿。

### P1：原生依赖与构建接线

- [x] 新增 `packages/libavformat_ffi` 静态包及 `native/` C bridge。
- [x] 新增 `packages/libass_ffi` 静态包；句柄保持 opaque，仅为稳定公开结构
      `ASS_Image` 定义只读前缀布局。
- [x] `client-next/cjpm.toml` 加入两个 path dependency 和 Linux/Windows 链接参数。
- [x] Linux CI 安装 `libavformat-dev libavcodec-dev libavutil-dev libass-dev`；原生库验证
      增加 FFmpeg/libass。
- [x] Windows CI 安装 `mingw-w64-x86_64-ffmpeg`、`mingw-w64-x86_64-libass`，并将依赖 DLL
      一并打包和启动冒烟验证。
- [x] `.github/workflows/client-next.yml` 的 paths、required files、cache key 纳入两个新包。
- [x] deb 使用 `dpkg-shlibdeps`/`${shlibs:Depends}` 推导运行时依赖，或显式加入发行版实际
      soname 包；不能只在构建机链接成功。
- [x] README 补充 Linux/Windows 原生开发依赖和故障诊断命令。

验收：Linux 和 Windows 均能完成最小 FFI build/test；安装产物在无开发包环境中启动，
`ldd` 或 Windows DLL 检查无缺失项。

### P2：libavformat/libavcodec 安全封装

- [x] C bridge 使用编译时真实头文件访问 AVFormatContext/AVStream/AVCodecParameters/
      AVPacket 字段，仓颉侧不复制易随 FFmpeg major 变化的完整结构体布局。
- [x] bridge 在编译期/运行时校验 `libavformat`、`libavcodec` major；不匹配时返回明确错误。
- [x] 绑定打开/枚举/读取与释放调用：
      `avformat_open_input`、`avformat_find_stream_info`、`avformat_close_input`、
      `av_read_frame`、`av_packet_alloc/free/unref`、`av_dict_get/set/free`、
      `avcodec_get_name`、`avcodec_find_decoder`、`avcodec_alloc/free_context`、
      `avcodec_parameters_to_context`、`avcodec_open2`、`avcodec_decode_subtitle2`、
      `avsubtitle_free`、`av_rescale_q`、`av_strerror`。
- [x] 实现 `probeSubtitleStreams`，包含 metadata、disposition、supported reason 及默认轨规则。
- [x] 实现 `extractSubtitleTracks`，一次扫描收集全部支持轨；正确换算 time base、过滤其他
      stream、释放每个 packet、flush mov_text 解码器并响应取消。
- [x] 公共 API 文档写明线程、所有权、取消、错误和输入上限。

验收：五类最小夹具结果正确；重复执行、错误 URL、截断媒体、取消和畸形 packet 均不崩溃、
不泄漏句柄；真实 MKV 能得到 4 条独立 ASS 轨及完整 CodecPrivate。

### P3：media proxy 稳定媒体租约与顺序读取

- [x] 将当前“一个可变 route 指向当前 upstream”改为每次 open 生成不可变 route/session；
      route 在 VLC 和字幕扫描仍持有时不能被切页改指向另一媒体。
- [x] 引入 `MediaProxyLease` 或等价引用计数生命周期；PlaybackModel、VLC、字幕 worker
      明确各自持有/释放租约。
- [x] 流式转发已是 O(1) 内存后，优先移除 32MiB 开放 Range 截断；若上游限制要求保留窗口，
      必须实现对下游透明的连续读取，不能以窗口结束冒充文件 EOF。
- [x] 正确透传 GET/HEAD、206/200、Content-Range、Content-Length、ETag、Last-Modified 和错误状态。
- [x] 增加读取/连接超时、取消关闭响应体，以及日志脱敏。
- [ ] 增加同一媒体 VLC + libavformat 并发读、切页后旧任务继续收尾、多个 seek 和上游断流测试。

验收：顺序读取大于 64MiB 内容字节完全一致；跨多个原 32MiB 边界无截断；切页后旧扫描
永远不会读到新媒体；代理关闭后没有遗留 server/response 资源。

### P4：版本化字幕缓存

- [x] 缓存根目录使用 `defaultCacheRoot(activeBaseUrl())/subtitles/`，按服务器隔离。
- [ ] 缓存键至少包含 cache schema version、server hash、arcid、sourcePath/page id、媒体验证器
      （ETag/Last-Modified/长度，能取得时必须使用）、stream index 和 codec。
- [x] 定义稳定、长度前缀的二进制事件格式及 manifest；禁止直接序列化原生结构体内存。
- [x] 写入采用同目录临时文件 + flush + 原子 rename；取消或失败删除临时文件。
- [x] 读取校验 magic、schema、长度边界、事件数量上限和校验和；损坏时删除并重新抽取。
- [x] probe 完成后后台预取默认轨；因为顺序扫描成本相同，实际扫描同时缓存全部支持文本轨。
- [x] 同一稳定媒体只允许一个在途 scan；多次选择合并等待同一结果，不重复扫描。
- [ ] 接入现有“清理缓存”入口，并定义字幕缓存容量上限、LRU/mtime 淘汰和未完成文件清理。

验收：二次打开同媒体不再读取完整容器；并发请求只扫描一次；媒体验证器或 schema 改变时
不会误用旧缓存；损坏/中断写入可自愈。

### P5：libass 安全封装与 RGBA 合成

- [x] 绑定完整生命周期：`ass_library_init/done`、`ass_renderer_init/done`、
      `ass_new_track/free_track`。
- [x] 绑定配置：`ass_set_frame_size`、`ass_set_storage_size`、`ass_set_pixel_aspect`、
      `ass_set_margins`、`ass_set_use_margins`、`ass_set_fonts`。
- [x] 绑定输入：`ass_read_memory`、`ass_process_codec_private`、`ass_process_chunk`、
      `ass_process_data`、`ass_flush_events`；二期字体任务再加入 `ass_add_font`。
- [x] 绑定输出：`ass_render_frame` 和稳定 `ASS_Image` 前缀；检查空指针、负尺寸、stride、
      坐标和整数乘法溢出。
- [x] 实现 SRT/VTT -> 规范 ASS 转换器，默认 Script Info、PlayRes 和 Style 固定且有单测。
- [x] 实现每轨 `ASS_Track` 管理器。一个 `ASS_Renderer` 可依次渲染多轨，但每次调用后必须
      立即消费/拷贝该轨的 `ASS_Image` 链表，再调用下一轨，不能跨调用保存借用指针。
- [x] 实现透明 RGBA 合成：严格按 `ASS_Image` 链表顺序和用户选择顺序叠加；libass 颜色的
      alpha 为反向值，实际覆盖率由 bitmap coverage 与 `(255 - colorAlpha)` 共同计算；
      使用 source-over，并裁剪到输出边界。
- [x] 输出 `SubtitleBitmap(width, height, generation, rgba)`；复用同尺寸数组，
      `detect_change=0` 时避免无意义纹理上传，但动画/卡拉 OK 仍按播放时钟更新。

验收：固定字体、固定时钟下 golden/hash 测试稳定；定位、颜色、透明度、描边、阴影、换行、
裁剪、重叠和多轨顺序正确；空轨和恶意尺寸不会崩溃或越界。

### P6：PlaybackModel、worker 与 VLC 集成

- [x] 新增状态：`embeddedSubtitleStreams`、`activeEmbeddedStreamIndexes`、轨级 loading/error、
      当前 `mediaGeneration`、已准备的 libass 轨和字幕 bitmap generation。
- [x] 新增注入点：probe、scan/cache load、取消；测试中不得要求真实 FFmpeg/libass。
- [x] `model.cj` 接入 `subprobe:<stableMediaKey>` 和 `subscan:<stableMediaKey>`；字幕扫描使用
      独立单线程或有界执行器，不占用当前 2 个通用 API worker。
- [x] video lane 激活后立即异步 probe；命中缓存直接准备轨，未命中则后台预取默认轨。
- [x] 用户选择尚未抽取的轨时显示 loading，并等待同一媒体的批量扫描结果；取消选择不取消
      其他仍需要的扫描，切媒体才取消整项。
- [x] 删除 VLC `subtitleTracks`/`subtitleTrackId` 作为 UI 数据源以及 `setSubtitleTrack`/
      `cycleSubtitleTrack` 的用户路径。
- [x] 在 VLC start 后及每秒节流检查时调用 `set_spu(-1)`；VLC 延迟发现字幕轨也不能自行启用。
- [x] seek、stop、切 lane、切媒体和 close 时刷新/释放正确状态；旧 worker 结果按 generation 丢弃。
- [x] 所有模型状态只在 UI pump 回填，worker 不直接修改 PlaybackModel 集合。

验收：模型测试覆盖 probe、默认预取、多选、取消、切页迟到、缓存命中/失败、Off、seek 以及
VLC 自动重新选轨后的强制关闭；通用 API worker 不被大文件 scan 饥饿。

### P7：reader dock 与视频舞台迁移

- [x] `reader_dock` 改成“Off + 外挂多选 + 内嵌多选”；内嵌项使用容器 stream metadata，
      不再显示 VLC ES id。
- [x] 显示探测中、抽取中、失败、unsupported codec；unsupported 行禁用但可说明原因。
- [x] Off 同时清空外挂和内嵌选中集；多选点击保持 popup 打开；选中/loading/error 图标可区分。
- [x] `drawVideoStage` 只计算一次视频 `fittedRect`，视频纹理和字幕透明纹理绘制到同一矩形；
      字幕不能以整个 reader frame 为坐标系。
- [ ] libass frame/storage size 取当前视频像素尺寸；若 probe 提供有效 SAR，则同步修正视频显示
      宽高比并调用 `ass_set_pixel_aspect`，保证两层几何一致。
- [x] resize、DPI、视频分辨率变化时重配 renderer 并使字幕纹理失效；旧纹理及时释放。
- [x] 用 streaming texture 原地更新字幕 RGBA；无字幕画面不创建透明全屏纹理。
- [x] 删除视频 `drawSubtitleOverlay`；音频歌词 overlay 及其他页面绘制不变。

验收：16:9、4:3、竖屏、letterbox 和窗口 resize 下字幕与视频像素矩形对齐；多轨按稳定顺序
显示；切页后不残留上一媒体的字幕纹理或面板状态。

### P8：测试、质量门禁与文档

- [x] 单元测试：time base 换算、stream metadata、SRT/VTT 转 ASS、缓存编码/损坏、RGBA alpha
      合成、模型状态机和代理 session 生命周期。
- [ ] FFI 集成测试：ASS CodecPrivate/chunk、SRT、VTT、mov_text、unsupported bitmap、截断输入、
      取消、重复打开关闭和所有错误清理路径。
- [ ] media proxy 集成测试：HEAD、完整 GET、开放/闭合 Range、跨边界顺序读、seek、并发、断流。
- [ ] UI/快照测试：无字幕、单轨、多轨、loading、error、unsupported、Off 和 resize。
- [x] Linux CI：`cjpm build`、`cjfmt`、`cjlint`、`cjpm test`、headless smoke 全绿。
- [ ] Windows CI：交叉构建、测试、DLL 打包和启动 smoke 全绿。
- [x] 本地 E2E：15.2GB MKV 双轨同屏；验证 `\an7/\an8` 等定位标签、颜色/描边、换行，
      无原始标签泄漏，VLC 原生字幕始终关闭，第二次打开命中缓存。
- [ ] 性能记录：首次 probe/scan 耗时、第二次缓存命中耗时、播放帧时间、字幕纹理上传次数、
      峰值托管内存和字幕缓存体积；记录测试机器和媒体大小。
- [x] 更新 client-next README：支持格式、位图字幕限制、字体回退、缓存位置/清理、原生依赖和
      故障诊断。

## 6. 推荐实施顺序与依赖

```text
P0 基线清理
  └─ P1 构建/依赖
       ├─ P2 libavformat/libavcodec ─ P3 proxy ─ P4 缓存 ┐
       └─ P5 libass/合成 ────────────────────────────────┤
                                                           └─ P6 模型/worker
                                                                └─ P7 UI/舞台
                                                                     └─ P8 全量验收
```

- P2 与 P5 可并行，但进入 P6 前二者的安全高层 API 必须稳定。
- P3 必须在真实大文件后台扫描前完成，否则可变代理 route 会造成跨媒体误读风险。
- P4 可先使用最小缓存实现验证数据格式，再补淘汰；但原子写和损坏校验不能延期。
- 二期字体附件不阻塞一期，但一期文档和 E2E 必须如实记录字体回退差异。

## 7. 一期完成定义

以下条件全部满足才能关闭本计划：

- [x] 产品运行路径和安装包均不调用或依赖 ffprobe/ffmpeg 外部二进制。
- [x] 支持格式的内嵌/外挂字幕可任意多选、同时显示；位图字幕明确禁用。
- [x] ASS CodecPrivate、packet 时间轴、mov_text 解码及所有原生释放路径正确。
- [x] VLC 原生字幕在启动、seek、延迟发现轨和切媒体后均保持关闭。
- [x] 大文件每个媒体最多一次在途顺序扫描，缓存命中不重新扫描，切页不会串流。
- [x] 视频和字幕在 letterbox/resize 下使用同一像素矩形，没有标签字面量泄漏。
- [ ] Linux/Windows 构建、测试、打包、启动 smoke 全绿。
- [ ] 真实双轨 E2E、缓存二次打开和性能记录归档完成。

## 8. 二期候选

- [ ] 枚举 MKV attachment stream，抽取字体并按 MIME/扩展名/大小白名单校验。
- [ ] 通过 `ass_add_font` 注入当前媒体字体；切媒体时按正确顺序清理 track/renderer/font。
- [ ] 字体附件缓存、去重、容量限制和恶意字体隔离。
- [ ] PGS/DVB 位图字幕解码与合成（独立设计，不与文本字幕伪装成同一数据格式）。
- [ ] 用户级字体、字号、边距和轨道偏移配置。
- [ ] 字幕轨延迟、单轨位置偏移及多轨自动避让策略。
