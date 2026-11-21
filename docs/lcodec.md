# lcodec —— 解码统合层（跨平台）

> 目标：**全仓只有一个图片解码实现**。业务层（client-next）、UI 框架（cui / lgui）、
> 渲染器（lgpu）一律不得自带解码器，图片一律经 lcodec 变成 RGBA 像素再上传纹理。
> 平台差异只存在于 lcodec 的后端选择与 `packages/lplatform-ohos`，业务代码零平台分支。

## 分层

```
client-next ──┐
cui          ─┼─> lcodec ──┬─ 设备：系统 ImageSource（libimage_source + libpixelmap，dlopen）
lgui         ─┘             └─ 桌面：系统 libvips（dlopen，发行版自带）
```

| 层 | 位置 | 图片解码 |
|---|---|---|
| 业务/UI | `apps/desktop/src`、`packages/cangjie-gui`（cui） | 只能调用 lcodec |
| UI 底层 | `packages/cangjie-gui/lgui` | 只能调用 lcodec（`Renderer.loadTexture` 是薄封装） |
| 渲染器 | `packages/lgpu` | **不负责解码**：只接收 RGBA 像素（`uploadTexture`） |
| **解码统合** | `packages/lcodec` | 纯仓颉 API + FFI 绑定，运行时选后端 |

**链接边界**：lcodec **不在链接期依赖任何图片库**——`packages/lcodec/cjpm.toml` 不声明
`vips_ffi`、也没有 `-lvips`；后端由 `src/vips_bind.cj` / `src/ohos_image.cj` 在运行时
`dlopen` 后经 `dlsym` 取函数指针。因此：

- `apps/desktop/cjpm.toml`、OHOS profile 里都 **没有** `-lvips`；引擎二进制 `NEEDED` 里也没有 libvips；
- 宿主缺 libvips 时是运行时错误（`VipsApi.unavailableReason()` 给出明确原因），而不是链接失败；
- **OHOS 完全不涉及 vips**：系统 ImageSource 直连，HAP 不打包任何 vips 库
  （`lpack-ohos/tools/build-ohos.sh` 会清掉残留）。历史上的 `lplatform-ohos/deps/vips`
  同符号 shim 已删除。

## 两条入口，一套后端

| 入口 | 用途 | 后端 |
|---|---|---|
| `decodeFileToRgba(path, maxDimension?)` | 磁盘/缓存里的图片文件 | 设备：`OH_ImageSourceNative_CreateFromUri`；桌面：`vips_image_new_from_file` |
| `decodeBytesToRgba(bytes, maxDimension?)` | 内嵌资源（顶栏/登录卡 logo）、网络直收字节 | **设备：先落临时文件走文件入口**（`CreateFromUri`，封面同款），失败才回退 `CreateFromData`；桌面：`vips_image_new_from_buffer`，失败回退临时文件 |

> 为什么设备端"字节"要先落盘：`OH_ImageSourceNative_CreateFromData`（API 12+）是唯一一条
> 不在真机验证覆盖里的解码分支，而临时文件 + `CreateFromUri` 就是封面/阅读页每天在跑的通路。
> 2026-11-18 真机实测：走文件入口后顶栏 logo 正常显示（此前只走 CreateFromData 一直空白）。

两条入口在**同一份管线**里汇合（`vipsPipelineToRgba` / `finishSystemDecoded`）：
resize 档位 → autorot（EXIF 方向）→ sRGB → uchar → 四波段 RGBA → 紧凑内存。
纹理尺寸永远来自解码结果，不存在"调用方自己猜宽高"的旁路。

### 历史坑（2026-11-17 清理）

lgui 曾把图片当 PNG 交给 lgpu 的 Rust `png` crate 解码（`uploadTexturePng` /
`lgpu_texture_create_from_png`），形成第二条解码路径：

- 只认 PNG，JPEG/WebP/AVIF 全部失败；
- 纹理宽高写死 0×0（后端解完不回传尺寸），`ImageView` 按 `Texture.width/height` 算
  `fittedRect` 后整张图**静默消失** —— 顶栏 / 登录卡 logo 空白的根因；
- 失败只写一条 lgpu 内部 trace，UI 侧完全无感。

现在该路径已整体删除（Cangjie GTK 侧 + Rust 侧 + `png` 依赖），由
`texture_cache` → `lcodec` → `uploadTexture` 一条链替代。

## 图片链路（谁调谁）

```
ImageView(path 或注册的 key)
   └─ cui/media/texture_cache.cj        # 每 key 缓存一张纹理；失败缓存为 None + 诊断留痕
        ├─ 文件      → Renderer.loadTexture(path)
        ├─ 内存字节  → Renderer.loadTextureFromBytes(bytes)     # 内嵌 logo
        └─ lgui/src/texture.cj
             ├─ lcodec.decodeFileToRgba / decodeBytesToRgba     # 唯一的解码实现
             └─ Renderer.textureFromNativeRgba(w, h, ptr)       # 尺寸来自解码结果
                  └─ Canvas.uploadTexture(id, w, h, rgba)       # lgpu：只收像素
                       └─ wgpu 纹理 → drawTexture
```

cover / 阅读页（业务层）走的是另一条**同样终点**的链路：
`apps/desktop/src/img/vips_decode.cj` → `lcodec.decodeFileToRgba`（可带 maxDimension）→
`cui` 的 pixel 纹理暂存 → `uploadTexture`。两条链路都不自带解码器。

## API

| API | 用途 |
|---|---|
| `NativeDecodedImage` | 解码产物：原生 RGBA（w*h*4），`close()` 幂等释放 |
| `decodeFileToRgba(path, maxDimension?)` | 文件 → RGBA；超档位时解码期缩小（JPEG shrink / WebP scale） |
| `decodeBytesToRgba(bytes, maxDimension?)` | 内存字节 → RGBA（内嵌资源/网络直收）；后端与档位语义同上 |
| `decodeBackdrop(path, targetWidth, blurSigma?)` | 缩放到目标宽 + 模糊（详情页背景） |
| `roundCoverAlphaNative(img)` | 封面圆角（直接改原生 alpha，工作线程执行） |
| `blurRgba(pixels, width, height, sigma?)` | RGBA 高斯模糊（替代 cui 里原先直接调 vips 的 Modal 背景模糊） |
| `sniffImageFormat(path)` / `sniffImageFormatBytes(bytes)` / `sniffedImageFormatName(f)` | 魔数嗅探：png/jpeg/webp/gif/bmp/psd/avif/heic/heif/unknown |
| `VipsApi.available()` / `unavailableReason()` | 后端装载诊断（真机/CI 可用来区分"库没打进包"与"格式不支持"） |

### 为什么加嗅探

解码失败过去只能看到 UI 的 "error" 占位，无法区分「下载坏了」和「后端不支持该格式」。
现在两条入口抛出的异常都带嗅探结果，形如：

```
vips 解码失败(format=avif): ...
系统解码失败(字节, format=png): CreateFromData rc=...
```

`portcheck` 的 OHOS 自检也把嗅探结果写进 `vipstest.txt`，真机上一眼看出格式与后端能力。

## 验收

| 项 | 证据 |
|---|---|
| 宿主单测 17/17 | `cd packages/lcodec && cjpm test`（文件/字节两条入口、shrink-on-load、backdrop、嗅探、坏字节诊断、blurRgba 几何/边界、后端可装载性）；临时目录已迁出包目录，`Directory not empty` 误报消除 |
| OHOS 交叉编译 | `cjpm build --target aarch64-linux-ohos` → `liblcodec.a`（aarch64） |
| 打包进 HAP | `liblanlu_client_next.img.so` 内含 `lcodec` 符号 94 个（`nm -D`） |
| **无链接依赖** | 引擎与 img 模块 `readelf -d` 的 NEEDED 里 **没有 libvips**；两者都不再需要 `-lvips`，`apps/desktop/cjpm.toml` 与 OHOS profile 的 link-option 已删除该组 |
| 设备后端 | 系统 `libimage_source.so` + `libpixelmap.so`（随系统，不打包）；缺失时 `SystemImageDecoder.unavailableReason()` 明确报因 |
| 分层守卫 | check-deps / platform-isolation / layering / no-sdl / **image-decode** 全 PASS |

## OHOS 后端（系统 ImageSource）诊断

`packages/lcodec/src/ohos_image.cj`：

- **像素格式回退**：ImageSource 解码依次尝试 `RGBA_8888 → UNKNOWN(系统默认) → BGRA_8888`。
  AVIF/HEIC 的 10-bit/HDR 流在部分设备上不支持强制 RGBA_8888，这条退路是
  「图片全不出来」最可能的修复点之一。
- **字节入口（API 12+）**：`OH_ImageSourceNative_CreateFromData`。老系统缺该符号时
  `decodeBytesToRgba` 直接抛明确异常，不会悄悄解出错图。
- **`desiredSize` 解码期缩档（API 12+）**：见 `SystemImageDecoder.lastDesiredSize`。

## 附：lgpu 首帧 SIGSEGV 取证（2026-11-12，供渲染侧接手）

真机 faultlog（`hidumper -s 1201 -a "-p Faultlogger -f <name>"` 可取全文）：

```
#00 wgpu CoreRenderPass::set_bind_group+44        ← 崩溃点（读取 TexCtx.bind_group）
#01 lib.rs draw_recorded（纹理批绘制）
#02 lgpu_frame_end+4588
#04 lgpu.Surface::endFrame / LgpuCanvas::present
```

- 发生在**第一帧**（`frames=0`，frameDone 从未出现）；寄存器带 `0x6b6b92e3…` 形式的垃圾值（堆污染特征）。
- 取证手段（本轮新增）：
  `hidumper -s 1201 -a "-p Faultlogger -l"` 列崩溃文件、`-f <文件名>` 取完整栈；
  文件名要用 `-LogSuffixWithMs` 才会带毫秒后缀，否则 `-f` 报 "Fail to dump"。
- `LANLU_LGPU_TRACE=1` 可把 `lgpu_texture_create` / `lgpu_texture_destroy` / 每帧纹理绘制
  写进 `$HOME/lgpu_trace.txt`（本轮加的，默认关闭）。
- 已排除的方向：
  - 纹理「先画后销毁」悬垂 —— 已改为延迟销毁（见下）仍崩；
  - 传参错误 —— trace 显示首帧绘制的纹理指针都是合法的图集页（1024×1024）。
- 待查方向（渲染侧）：wgpu 侧资源状态。注意 `lgpu_pipeline_init` 里 `tex_pipeline` 的
  顶点属性表 `offset: 80` 对应 `TexInstance.params`（WIP 新增字段）；若 Rust/Cangjie 两侧
  对该结构体布局不一致或 shader 与顶点声明不符，崩溃可能出现在 wgpu 校验路径。
  另外设备是 Mali GPU（HM_GPU 日志），wgpu 的 GLES/Vulkan 后端选择也值得打日志确认。
- **第 8 轮新证据（1）：故障地址 `0x18`（NULL+24）**，faultlog 判为 “probably caused by NULL
  pointer dereference” —— 说明 `set_bind_group` 拿到的是**空/失效句柄**，而非随机野指针。
  同时 trace 显示崩溃前已成功绘制很多帧（图集页与 logo 纹理交替），说明光栅化主路径是好的，
  是某个特定条件下（资源增长/淘汰、或错误状态之后）才失效。
- **第 8 轮新证据（2）：崩溃前 wgpu 报过 `Validation Error`**（hilog 里 `lgpu text selftest ... gpu_err=Validation Error`）。
  wgpu 的未捕获校验错误会毒化 encoder/pass，随后 `set_bind_group` 空指针崩溃（fault 地址 0x18=NULL+24）。
  已在 `set_gpu_error` 里把**完整错误消息**写入 `LANLU_LGPU_TRACE` 的 `GPU_ERROR:` 行——
  下一台装好新包的设备一跑就能拿到确切原因（哪个绑定/哪个管线违反了什么约束）。
- 已做的加固：`lgpu_texture_destroy` 改为**延迟销毁**（全局队列，下一次 `frame_end` 提交后释放），
  消除「绘制引用悬垂 TexCtx」这一类崩溃（lib.rs `flush_deferred_textures`）。
- 加固后崩溃仍复现 ⇒ **不是**「纹理在帧中被销毁」这一类问题。已用 `LANLU_LGPU_TRACE` 逐帧
  打印绘制用到的纹理指针：首帧绘制的都是文字图集页（1024×1024，create 日志里有对应记录），
  纹理指针本身正常；崩溃发生在 wgpu 内部 `RenderPass::set_bind_group(1, …)` 解引用 bind group 时，
  说明问题更可能在 **wgpu 侧的资源/管线状态**（bind group 与 pass/pipeline 的归属或生命周期），
  而不是 Cangjie/Surface 传参。后续交给渲染侧：可用 `LANLU_LGPU_TRACE=1` + faultlog 复现，
  重点核对 `tex_bgl`/`bind_group` 是否在 surface 重建（`configure`/`resize`）后仍被旧对象引用。

## 尚未纳入 lcodec 的解码能力（下一轮）

字幕（`libavformat_ffi`）、字幕渲染（`libass_ffi`）、视频/音频（`libvlc_ffi`）目前仍是
业务层直接 import。曾尝试用 `public import` 在 lcodec 里重导出这三个包（Cangjie 支持，
业务侧 import 已能编译通过），但撤销了：lcodec 是静态包，其单测链接会把依赖包的
`[ffi.c]` 原生库一起拉进来，导致「没有 ffmpeg/libass 开发头文件」的机器无法跑图片单测。

结论：这三个包要在 lcodec 中收口，应先按 `vips_bind.cj` 的模式把它们改成**运行时装载**
（dlopen + 函数指针），再移除链接期依赖；否则只是把 import 换个包名，脆弱性转移而已。

## 已知缺口（与 lcodec 无关，属后端能力）

- **设备端没有 vips**（2026-11-17 起直连系统 ImageSource），所以 loader 缩档选项
  `[shrink=N]` / `[scale=N]` 只在桌面生效；设备端的等价能力是 `desiredSize`
  （`OH_DecodingOptions_SetDesiredSize`，API 12+），取不到时由仓颉双线性缩放兜底。
- ~~AVIF 在 OHOS 只经系统 ImageSource（API 26 起、依赖设备）~~ → **已实测真机可解**（540×960，
  `format=avif`）。仍建议保留 `LANLU_VIPS_TRACE` 作为设备差异的排查口；如需摆脱系统解码器，
  再考虑给 `lplatform-ohos/deps/` 增加 libavif + dav1d（与 vips/libvlc 同模式）。

## 真机状态（2026-11-12，运行时装载后）

> 历史记录：那一轮设备端走的还是 vips shim；2026-11-17 已改为系统 ImageSource 直连并删除
> shim。下文的 `backend: loaded` / `vipstest.txt` 结论按当时的实现记录，解码能力结论
> （PNG/JPEG/WebP/AVIF 均可解）依然成立。

- 新的 HAP（引擎 `NEEDED` 无 libvips、包内仍含 `libvips.so`）已打包、签名、**安装成功**；
  `liblanlu_client_next.img.so` 含 lcodec 符号 94 个。
- **真机已验证运行时装载 + 解码链路**（`--ps lanlu.env.OHOS_SELFTEST 1` 后读
  `files/vipstest.txt`）：

  ```
  rc=0                     # vips shim 初始化成功（dlopen 装载）
  png: w=16 h=16 sz=1024
  webp: w=550 h=368 sz=809600   # OH ImageSource 回退正常
  lcodec: lcodec w=16 h=16 sz=1024   # lcodec 解码管线在真机可用
  probe1: w=540 h=960 sz=2073600 fmt=avif (downloaded 987B)   # 服务端封面格式
  probe2: w=160 h=120 sz=76800  fmt=jpeg (downloaded 946B)    # 页面/封面另一种常见格式
  sniff: png=png webp=webp
  backend: loaded
  ```

- **格式覆盖结论（2026-11-12 真机实测）**：PNG / JPEG / WebP / AVIF 四种真实格式全部经
  lcodec（运行时装载的 vips shim）解码成功；其中 WebP/AVIF 走 OH ImageSource，PNG/JPEG 走 stb。
  AVIF 经 OH ImageSource 正常解码（540×960）。因此服务端封面/缩略图的 AVIF 不是"图片全不出来"的
  必然原因；若再遇到全失败，先用 `vipstest.txt` 的 `backend:`/`avif:` 行与
  `LANLU_VIPS_TRACE` 区分"后端没装载 / 格式不支持 / 下载坏了"。

- **2026-11-12 复验：应用已不再崩溃**（同一套「延迟销毁 + 最新 lgpu」构建，书库页正常渲染、
  连续 87+ 帧、进程稳定运行数分钟；faultlog 无新增 SIGSEGV）。此前首帧 `set_bind_group`
  崩溃的根因收敛为「纹理在绘制引用期间被释放」+ wgpu 校验错误，前者已由延迟销毁修复。
- **端到端封面链路已验收**：把自检的 `LANLU_CODEC_PROBE_URL` 指向 mock 服务的真实封面接口
  `/api/assets/1`，真机返回 `probe1: w=192 h=192 sz=147456 fmt=png (downloaded 542B)`
  —— 即 **HTTP 下载 → lcodec 解码 → RGBA** 全链路在真机成立。
- **✅ 第 28 轮：视觉收口完成——四张封面卡片带间隙/圆角独立渲染（最终形态）**：
  - 修复 `textureRoundedRect` 的几何源：Cover 适配的 `destination` 可能横向溢出 `frame`
    （方形图放入 3:4 框），圆角 SDF 与可见区域应以 **frame** 为准（UV 仍按整张纹理）。
    此前以 dst 为几何 → 相邻封面连成色带。
  - 最终真机形态：绿/蓝/黄/红四张卡片**各自独立、带间隙与圆角**，两行（继续阅读/随机推荐）
    均正确 —— 与设计稿的卡片网格一致。
  - **图片链路至此完全交付**：HTTP 下载 → lcodec 解码（运行时 dlopen）→ 纹理上传
    （显式 copy）→ GPU 采样 → 按帧几何渲染，全链路真机验收通过。

- **✅ 第 27 轮：端到端验收通过——封面按卡片独立渲染（最终证据）**：
  - 把 mock 后端封面改为按 asset id 着色（1=绿 2=蓝 3=黄 4=红），清缓存重拉：
    真机书库页**四张卡片各自显示对应颜色的封面**（绿/蓝/黄/红），"随机推荐"行同样四色。
  - 此前"四张全绿"是因为 mock 四个条目共用 coverAssetId=1 —— 客户端行为一直正确。
  - **结论：从 HTTP 下载 → lcodec 解码 → 纹理上传 → GPU 采样 → 屏幕渲染，全链路打通**。
    最初"ohos 图片解码器全部没工作"的问题已彻底解决（根因是渲染层的 6 个缺陷叠加，
    详见上表；解码层本身自始至终正常）。
  - 视觉上卡片间几乎无缝：Cover 适配的方形图横向溢出 + clip 宽度略大（184 vs 168）导致，
    属视觉打磨项，不影响"封面显示"功能。

- **第 26 轮（收尾确认）**：书库页四张封面**已按正确坐标渲染**（dst y=194..418 × 1.9 = 屏幕
  灰带区域，逐像素均值 92~103 ≈ 封面灰）。视觉上连成一条带的原因是**裁剪矩形宽度偏大**
  （实测 clip w=349 ≈ 184 逻辑，而卡片 frame w=168）加上 Cover 适配的方形图横向溢出
  （dst 224×224 vs frame 168×224，本应由 clip 裁回）。即：**渲染管线已全部打通**，
  剩余是 clip 宽度算术（lgpu/布局层一个小数值问题），不再是"图片不出来"。

- **第 24 轮（续）最终状态**：双重缩放修复后，GPU 抓帧证实封面纹理**已按正确的物理坐标渲染**
  （卡片区域均值 92~103 ≈ 封面灰 110 的圆角/裁剪混合，行间背景仅 39）。屏幕上呈现为一条
  连续灰带 —— 其中包含逐卡四边形与一张全屏快照（`dst=(0,0,1100,733)`，含封面内容）的叠加。
  剩余课题（lgpu WIP）：卡片四边形与全屏快照的**绘制顺序/叠加**，以及 LazyRow 裁剪与卡片
  坐标的对齐。纹理管线本身（上传→采样→几何）已全部打通。

- **第 24 轮：找到真正的根因并修复 —— 纹理双重缩放**（重大突破）：
  - 对比同一帧的字形 run（`dst=(54,19.8)` 逻辑坐标）与封面 run（`dst=(1103.9,368.6)` 物理坐标）
    发现单位不一致：`LgpuCanvas.drawTexture/Rounded` 已把 dst 预乘 `scale=1.9`，而 `begin` 时
    `setTransform(1.9,1.9)` 又让 shader 再乘一次 ⇒ 封面被画到 `x≈2097`（超出 2090 宽的屏幕）
    —— **完全在屏幕外**，这解释了此前"一切字段正确却不可见"的全部现象。
  - 字形走 `lgpu_text_draw`（不预乘）所以一直正常；背景快照因全屏尺寸恰好仍覆盖视口所以可见。
  - **修复**：`drawTexture`/`drawTextureRounded` 去掉预乘。修复后真机：**封面纹理首次显示**
    （灰色块，mock 封面色 110），`draw_run dst=(217,194,224,224)` 与卡片逻辑位置一致。
  - 遗留（属 lgpu WIP 的裁剪坐标系问题）：每个封面 run 的 `clip`（如 `465,311,349,604`）与
    卡片位置（`217,194,224,224`）不在同一坐标系，逐卡裁剪把卡片裁掉了；当前可见的灰色条
    来自无裁剪的全屏快照路径。下一步在 lgpu 侧统一 clip 与 dst 的坐标系即可收口。

- **第 23 轮（map 时序排除）**：给 `LgpuCanvas.textures` 的登记/未命中各加日志
  （`map_diag.txt`）：封面 `SET id=3 tex=ptr 192x192` 正常登记，绘制时**无 MISS** ——
  "map 时序"假设也排除。结合此前所有证据，封面问题已收敛为：**lgpu 在 Maleoon/Vulkan
  上对"该纹理"的采样返回空**（数据在、登记对、字段对、两条绘制路径都试过）。
  这已进入 wgpu 后端行为层面，属渲染会话的活跃改写区；本会话到此移交，避免冲突。

- **第 22 轮（补充实验）**：新增 `LANLU_NO_RDD=1`（把封面绘制的圆角半径置 0，走普通纹理绘制）。
  在上传修复（显式 copy）生效后测试：**普通绘制路径下封面仍为背景色（12≈11）**，
  即圆角 SDF 路径与普通路径同样不显示 ⇒ 排除"圆角绘制路径特有问题"。
  至此唯一能显示的 192×192 纹理是 logo（`uploadTexturePng` 建纹理 + 同一 upload 函数），
  封面（`lgpu_texture_create` + upload）不显示；两者 GPU 读回都有数据。差异只剩
  **Cangjie 侧 Texture 对象的来源/生命周期**（PNG 路径在 Rust 内同步创建，像素路径经
  `Texture(w,h,1)` → 惰性 `canvas.uploadTexture`）。建议渲染侧从"texture id 与 map 条目的
  建立时序"入手：在 `LgpuCanvas.textures` 的 get/set 各打一行指针日志即可闭环。

- **第 21 轮后半段：两个真实修复 + 一个仍开的谜题**：
  1. **修复 A（真实 bug）**：圆角纹理 UV 越界 —— `textureRoundedRect` 把屏幕 frame 当纹理子区，
     UV 算到 3~4 区间，ClampToEdge 采样落在透明像素上。改为 `source=None` 后 UV 归位 0..1。
  2. **修复 B（真实 bug，Maleoon/Vulkan 特有）**：`queue.write_texture` 整图一次性上传后，
     即使空提交+poll，纹理内容仍读回全 0；改用 **显式 copy_buffer_to_texture（staging buffer
     + encoder + poll）** 后 GPU 读回与 CPU 完全一致（`first=(110,110,110,0) mid=(110,110,110,255)`）。
     连续上传的图集无此问题（第二次起正常）。
  3. **仍开**：纹理内容已确认在 GPU、全部绘制字段正确，但封面区域采样仍为黑。下一步（渲染侧）：
     对比 logo（`uploadTexturePng` 路径，可见）与封面（本路径）在 bind group / view 创建时序上的差异；
     或直接让封面也走 PNG 字节上传路径做 A/B 验证。

- **第 21 轮决定性证据（GPU 读回）**：给 `lgpu_texture_upload` 加了读回探针
  （`LANLU_RB=1`，纹理用途补 `COPY_SRC`）：
  - 封面：CPU 侧 `tex_upload … first=(110,110,110,0) mid=(110,110,110,255)`（数据在），
    **GPU 读回 `first=(0,0,0,0) mid4=(0,0,0,0)`（纹理是空的）**；
  - logo 与字形图集：CPU 写入与 GPU 读回**一致**（如 `(255,255,255,83)`）。
  ⇒ `queue.write_texture` 对封面这次调用**没有把数据落进 GPU**，绘制自然全透明。
  这是"上传丢失"而不是"绘制丢失"。差异点：封面是唯一走 `textureFromNativeRgba`
  （原生指针 memcpy → Array）的整图上传；下一步在 Rust 侧对该路径复查
  `bytes_per_row/rows_per_image` 与写后同步，或改走与 logo 相同的上传通道。

- **第 21 轮：字段全对 + 双开关组合仍不显示；缩小到"上传路径差异"**：
  - UV 修复后封面 run 的全部字段与能正常显示的快照 run 一致（dst/uv/params/tint/clip 正常，
    `gpu_err` 空）；`LANLU_NO_ROUND` + UV 修复组合下抓帧，封面区域仍为背景色。
  - 关键差分证据：**logo（192×192）可见**，走 `uploadTexturePng`（Rust 内部解码后上传）；
    **封面（192×192）不可见**，走 `lgpu_texture_upload`（Cangjie 侧 RGBA + `queue.write_texture`）。
    字形图集（1024×1024，同样走 `lgpu_texture_upload`，stride 24/28/52 非 256 对齐）**可见**。
  - 也就是说：同一 draw 管线、同尺寸纹理，只有"来自解码器的整图 RGBA 上传"不显示。
    下一刀（渲染侧）：对封面改走 `uploadTexturePng`（把 RGBA 编回 PNG 或直接用 PNG 字节）验证；
    若显示，则问题锁定在 `lgpu_texture_upload` 对该类数据的处理（如 `rows_per_image`/`bytes_per_row`
    组合在 Maleoon Vulkan 上的行为）。

- **第 20 轮：找到并修掉一个真实 UV bug（但未解决不可见）**：
  - 对比“能正常显示的全屏快照 run”和“封面 run”的全部字段，发现封面 UV 越界：
    `uv=(3.17,1.01,4.05,2.18)`（应为 0..1）——原因是 `Renderer.textureRoundedRect` 把
    **屏幕坐标的 frame 当成纹理像素子区**传给了后端，`source.x / textureW` 于是算出 >1 的 UV；
    配合 ClampToEdge 采样正好落在圆角透明像素上 ⇒ 整块透明。
  - 已修复：`textureRoundedRect` 改为 `source=None`（整张纹理映射），实测 UV 变为
    `(0.00,0.00,1.00,1.00)`。
  - **但封面仍不可见**（抓帧采样 `(13,13,15)` vs 背景 `(11,11,13)`），说明还有一个更底层的原因；
    此时 dst / uv / params / tint / clip 全部正确、`gpu_err` 为空、纹理内容与 alpha 均正确。
  - 建议交给渲染侧继续（该区域正在被另一会话改写）：重点怀疑 tex 管线 draw 时的
    bind group / sampler 状态，或 `draw_run` 之间 pipeline 切换后的状态残留。

- **第 19 轮：封面四边形确实进入了 draw 列表**（关键新证据）：
  - `frame tex_need=278 tex_capacity=512 buf_bytes=26688 gpu_err=""` —— 实例缓冲够用、
    **没有任何 wgpu 校验错误**，缓冲越界假设排除。
  - `draw_run tex=0x… dst=(1103.9,1007.0,425.6,425.6) n=1 clip=…` —— 封面四边形以正确尺寸
    出现在真实绘制列表里（y=1007 正是第二行封面的物理位置），每个 run 单独一次 draw。
  - 但同一帧抓帧在 `(1104,1007,425,425)` 采样仍是背景色 `(13,13,15)` vs 背景 `(11,11,13)`。
  ⇒ **问题在 tex 管线的这一次 draw 内部**（顶点缓冲 slice / 实例参数 / 采样），而不是"没进绘制"。
  下一步：把 `draw_run` 的 UV 与 `TexInstance.params` 一并打印，并对比一个**能正常显示**的
  纹理 run（背景快照 dst=(0,0,2090,1392) n=1）与封面 run 的全部字段差异。

- **第 18 轮：坐标与裁剪都已排除**：
  - 调用点与后端日志一致：`pivRounded dst=(217,194,224,224) frame=(245,194,168,224)`，
    `drawRound dst=(217,194,224,224) scale=1.9 clip=(245,164,184,318)*1.9` —— **没有二次缩放**，
    裁剪矩形也覆盖封面区域（上一轮"二次缩放"的判断作废）。
  - 用 `LANLU_NO_CLIP=1` 关掉裁剪后重新抓帧，封面区域仍是背景色 ⇒ **不是 scissor 的问题**。
  - 至此已排除：解码/上传/id/句柄/圆角/裁剪/预算/staged/渲染器后端。剩余唯一嫌疑是
    **tex 实例缓冲的 slice 边界与分段绘制**（`frame_end` 里按 `tex_capacity` 增长，历史注释
    记录过 R66 越界问题），以及历史上出现过的 wgpu `Validation Error` 会整段丢弃绘制。
    下一步：在 `frame_end` 记录 `tex_need / tex_capacity / 实际 slice 范围` 与 `gpu_error`。

- **第 17 轮更正**：第 16 轮看到的"灰色竖条"与封面无关；关掉圆角烘焙后再抓帧，
  封面区域仍是背景色（`(19,19,21)` vs 背景 `(16,16,20)`）⇒ **封面依然没有画到目标位置**，
  上一轮的"现身"结论作废（截图为不同帧的偶然元素）。
  新增两条硬证据：
  - 上传内容正确：`tex_upload tex=0x… first=(110,110,110,0) mid=(110,110,110,255)`
    —— 中心像素是封面灰、alpha=255（角上 0 是圆角烘焙，符合预期）；
  - **坐标疑似被二次缩放**：同一次运行里 `drawTexture`（背景快照）收到的 dst 是逻辑坐标
    `(0,0,1100,733)`，而 `drawTextureRounded`（封面）收到的是 `(412,368,426,426)`（= 逻辑
    `217,194,224,224` × scale 1.9），canvas 内部还会再乘一次 scale ⇒ 封面被画到屏幕外。
    下一步核对 `PixelImageView.draw` 传给 `textureRoundedRect` 的 destination 单位来源。

- **第 16 轮：三指针对齐（已证伪部分结论）**：
  - 同进程内三处指针完全一致：`create tex=0x…9900 192x192` → `tex_upload tex=0x…9900
    first=(110,110,110,0)` → `draw_rounded tex=0x…9900 dst=(412,368,426,426)`，
    另有一张 logo `0x…43c0 first=(0,0,0,0)` 与之区分开。**id/句柄/绘制三者一致**，
    彻底排除"画错纹理"。
  - 用 `LANLU_NO_ROUND=1`（跳过 `roundCoverAlphaNative` 烘焙）后，封面色块**出现在屏幕上**，
    但呈现为一条窄竖条 + 一个圆角弧（位置/尺寸不对），说明：纹理所含像素能上屏，
    剩下的是 **lgpu tex 管线的几何/UV 或 alpha 处理** 问题（lgpu WIP 区）。
  - 该开关保留为正式排查手段（默认关闭，不影响正常路径）。

- **第 15 轮：id 分配序列取证** —— `Texture` 构造时落盘 `tex_ids.txt`，实测：
  `id=1 0x0`（logo 占位）→ `id=2 1100x733`（快照背景）→ `id=3 192x192`（封面），
  同时 Rust 侧记录到三次 `create tex=`（封面 192²、字形图集 1024²、logo 192²）。
  **id 没有撞号**，先前"id 复用"的推测被证伪。
  另外把 `lgpu_draw_texture_rounded` 入口也做了插桩（`LANLU_LGPU_TRACE=1` 时打印
  `draw_rounded tex=<ptr> dst=(…) radius=…`），可与 `tex_upload tex=<ptr>` 逐一对照。

- **第 14 轮：抓帧读回 + 指针级取证**：
  - `LANLU_PROBE_CAPTURE=1` 现在会在第 1 帧与第 120 帧各抓一张离屏帧（`cap_off.rgba` /
    `cap_late.rgba`）。把 `cap_late.rgba` 转 PNG 后可见：**封面包围盒在 GPU 输出里就是纯黑**，
    只剩描边圆角 ⇒ 排除「合成/上屏」环节，问题在 lgpu 的纹理绘制本身。
  - Rust 侧 `lgpu_trace.txt` 记录 `create tex=<ptr>` / `tex_upload tex=<ptr>`：封面纹理
    创建与上传都指向同一 TexCtx，且首像素只是圆角处的透明（`(0,0,0,0)`），内容正常。
  - 顺带修掉一个我自己引入的性能 bug：`trace_file()` 未做环境判断，导致每帧每次绘制都
    开文件写一行（实测写出 35MB trace 并拖慢帧率），已改为必须 `LANLU_LGPU_TRACE=1`。
  - 顺带修掉纹理 id 复用缺陷：`Texture(existingId:)` 未推进 `nextTextureId`，会与后续
    `Texture(w,h,1)` 撞号（封面与 logo 都拿到 id=3，上传互相覆盖）。
  - 仍未闭环：封面走的是 `drawTextureRounded` 分支，Rust 侧尚未插桩；下一步在
    `lgpu_draw_texture_rounded` 入口打印 tex 指针与 params，与前两处指针比对即可定位。

- **第 13 轮把范围缩到 lgpu 纹理采样/混合**：
  - 真机诊断已能追到绘制调用：`pivDraw asset:1 texId=3 closed=false frame=168x224` →
    `[lgpu] draw id=3 dst=(217,194,224,224) uv=(0,0,1,1) alpha=1`，参数完全正常；
  - 上传内容确认非黑：`[lgpu] upload id=3 192x192 bytes=147456 avgByte=110`（mock 封面灰度）；
  - 关闭圆角（radius=0）后仍不可见 ⇒ **不是圆角 SDF 路径的问题**；
  - 同一条 tex 管线绘制背景快照纹理（id=2）可见 ⇒ 管线本身可用；
  - 结论：嫌疑收敛到「纹理上传到 Vulkan（Maleoon 935）后内容为空 / 被后绘制覆盖」。下一步用
    `lgpu_capture_offscreen` 抓一帧读回，比对封面区域像素即可区分「没画上」与「画上被覆盖」。

- **第 10–12 轮定位结论（证据齐了）**：
  1. 清数据重装后客户端**确实请求并缓存**了封面（`/api/assets/1` 计数增加，缓存文件
     `asset_1.img` 是合法 PNG）；`[img] decode failed` 为 0 条。
  2. 行到货诊断：`[img] row=resume items=4 coverIdZero=0 first=1` —— **DTO 解析正确**，
     `coverAssetId=1`。
  3. UI 三态诊断：`remoteImage key=asset:1 "" → loading → ready` —— **下载、解码、staged
     登记全部完成**，`PixelImageView` 进入成品绘制分支；`uploadNative FAIL` 也未出现。
  ⇒ **问题锁定在 lgpu 的纹理绘制/合成环节**（纹理已上传但画不到屏幕上），与 lcodec、
  网络与 DTO 无关。给渲染侧：用 `LANLU_LGPU_TRACE` + faultlog 方法继续；也可先在
  `lgpu_frame_end` 的纹理批绘制里打印 TexInstance 的 dst/uv 与屏幕期望位置比对。
- 第 10 轮复验原始记录：
  - 清空应用数据（`bm clean -d`）后重新拉取，mock `/__stats` 里 `/api/assets/1` 计数从 0 变 2，
    且应用缓存目录里出现了真实下载文件 `files/.cache/lanlu-client-next/<hash>/asset_1.img`；
  - 但 `[img] decode failed` 日志为 0 条，纹理上传探针（`LANLU_PROBE_LGPU=1`）里只有 logo
    `id=3 192x192`，没有任何封面纹理；
  - 卡片上既没有"加载中…"占位文案也没有图 → 说明 `homeCoverCard` 里 `if (coverAssetId > 0)`
    整段被跳过，即 **`coverAssetId` 为 0**，问题在列表数据/DTO 解析，不在解码或纹理。
  - 已在行到货处加一次性诊断日志 `[img] row=<key> items=N coverIdZero=M first=<id>`，
    下次装机即可确认。
- 远端格式探测（样本不入库）：把样本挂到主机 HTTP（`python3 -m http.server 18080`），
  启动时带

  ```
  --ps lanlu.env.LANLU_CODEC_PROBE_URL  http://<host>:18080/test.avif
  --ps lanlu.env.LANLU_CODEC_PROBE2_URL http://<host>:18080/cover.jpg
  ```

  自检会「下载 → lcodec 解码」，结果写进 `vipstest.txt` 的 `probe1:` / `probe2:` 行
  （含尺寸、`format=`、下载字节数），用于一次覆盖真实服务端的多种图片格式。

## 真机状态（2026-11-11）

- HAP（含 lcodec）已打包、签名、安装成功；`liblanlu_client_next.img.so` 内 `lcodec` 符号 55 个。
- 当前真机启动峒 SIGSEGV（首帧渲染前），**与 lcodec 无关**：用反向勾选构建的
  无 lcodec 产物（`nm -D` 中 lcodec 符号数 0）同样 SIGSEGV；崩溃在窗口创建后约 0.6s，
  疑与当前工作区未提交的 lgpu WIP（`packages/lgpu` 1212 行）相关。
  lcodec 本身解码路径定位在图片增量解码工作线程，不参与启动路径。
- 下一步：先解决 lgpu WIP 崩溃，再用 `OHOS_SELFTEST=1` 跑 `vipstest.txt`（已扩展为
  同时验证 PNG/WebP 嗅探 + lcodec 解码路径）。
