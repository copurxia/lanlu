# lcodec —— 解码统合层（跨平台）

> 目标：**业务层不感知解码器的平台差异**。client-next 只调用 lcodec 的图片解码 API；
> 桌面用真 libvips，OHOS 用同符号 `libvips.so` shim（stb_image + OH ImageSource 回退），
> 差异只存在于 FFI 与 `packages/lplatform-ohos`，业务代码零平台分支。

## 分层

```
client-next ──┐
cui           ─┴─> lcodec ──[运行时 dlopen/dlsym]──> libvips.so
                                            ├─ 桌面：系统 libvips（AVIF/WebP/JPEG/PNG 全量）
                                            └─ OHOS：lplatform-ohos/deps/vips/vips_shim.c
                                                      （stb_image；AVIF/HEIC 走 OH ImageSource）
```

| 层 | 位置 | 平台差异 |
|---|---|---|
| 业务/UI | `client-next/src`、`packages/cangjie-gui` | 无（`tools/check-layering.sh` 把关） |
| **解码统合** | `packages/lcodec` | 无（纯仓颉 API + FFI 绑定） |
| 解码实现 | 系统 libvips / `lplatform-ohos/deps/vips` | 全部收敛于此 |

**链接边界**：lcodec **不在链接期依赖 libvips**——`packages/lcodec/cjpm.toml` 不声明
`vips_ffi`、也没有 `-lvips`；后端由 `src/vips_bind.cj` 在运行时 `dlopen` 后经 `dlsym`
取函数指针（实现在 `VipsApi`，API 与 vips_ffi 同名，便于迁移）。因此：

- `client-next/cjpm.toml`、OHOS profile 里都 **没有** `-lvips`；引擎二进制 `NEEDED` 里也没有 libvips；
- 宿主缺 libvips 时是运行时错误（`VipsApi.unavailableReason()` 给出明确原因），而不是链接失败；
- OHOS 上 `libvips.so` 仍随 HAP 打包（`OHOS_EXTRA_LIBS`），由 loader 在运行时装载。

## API

| API | 用途 |
|---|---|
| `NativeDecodedImage` | 解码产物：原生 RGBA（w*h*4），`close()` 幂等释放 |
| `decodeFileToRgba(path, maxDimension?)` | 任意格式 → RGBA；超档位时解码期缩小（JPEG shrink / WebP scale） |
| `decodeBackdrop(path, targetWidth, blurSigma?)` | 缩放到目标宽 + 模糊（详情页背景） |
| `roundCoverAlphaNative(img)` | 封面圆角（直接改原生 alpha，工作线程执行） |
| `blurRgba(pixels, width, height, sigma?)` | RGBA 高斯模糊（替代 cui 里原先直接调 vips 的 Modal 背景模糊） |
| `sniffImageFormat(path)` / `sniffedImageFormatName(f)` | 魔数嗅探：png/jpeg/webp/gif/bmp/psd/avif/heic/heif/unknown |
| `VipsApi.available()` / `unavailableReason()` | 后端装载诊断（真机/CI 可用来区分"库没打进包"与"格式不支持"） |

### 为什么加嗅探

OHOS 的 vips shim 里 `vips_error_buffer()` 恒返回空串，历史上解码失败只能看到 UI 的
"error" 占位、无法区分「下载坏了」和「后端不支持该格式」。现在
`decodeFileToRgba` 抛出的异常形如：

```
vips 解码失败(format=avif): ...
```

`portcheck` 的 OHOS 自检也把嗅探结果写进 `vipstest.txt`，真机上一眼看出格式与后端能力。

## 验收

| 项 | 证据 |
|---|---|
| 宿主单测 13/13 | `cd packages/lcodec && cjpm test`（PNG/JPEG/WebP 解码、shrink-on-load、backdrop、嗅探、坏字节诊断、blurRgba 几何/边界、后端可装载性） |
| OHOS 交叉编译 | `cjpm build --target aarch64-linux-ohos` → `liblcodec.a`（aarch64） |
| 打包进 HAP | `liblanlu_client_next.img.so` 内含 `lcodec` 符号 94 个（`nm -D`） |
| **无链接依赖** | 引擎与 img 模块 `readelf -d` 的 NEEDED 里 **没有 libvips**；两者都不再需要 `-lvips`，`client-next/cjpm.toml` 与 OHOS profile 的 link-option 已删除该组 |
| 运行时仍有后端 | HAP 内仍打包 `libvips.so`（113,920 B，OHOS shim），由 `lcodec` 在运行时 `dlopen`；缺失时 `VipsApi.unavailableReason()` 明确报因 |
| 分层守卫 | check-deps / platform-isolation / layering / no-sdl 全 PASS |

## OHOS 后端（vips shim）本轮加固

`packages/lplatform-ohos/deps/vips/vips_shim.c`：

- **像素格式回退**：ImageSource 解码依次尝试 `RGBA_8888 → UNKNOWN(系统默认) → BGRA_8888`。
  AVIF/HEIC 的 10-bit/HDR 流在部分设备上不支持强制 RGBA_8888，这条退路是
  「图片全不出来」最可能的修复点之一。
- **`LANLU_VIPS_TRACE=1` 诊断**：把 `decode_oh` 的每个失败阶段（缺符号 / CreateFromUri /
  CreatePixelmap(格式) / 读像素 / 尺寸非法）追加到 `$HOME/vips_trace.txt`，真机排查不用猜。
  启动方式：`aa start ... --ps lanlu.env.LANLU_VIPS_TRACE 1`（env 注入前缀是 `lanlu.env.`，
  见 EntryAbility.ets）。

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

- OHOS `libvips.so` 是 shim：`vips_image_write_to_file` / `vips_text` 恒返回 -1；
  loader 选项 `[shrink=N]` 不被识别（会退化为全尺寸解码后缩放，功能对但慢）。
- ~~AVIF 在 OHOS 只经系统 ImageSource（API 26 起、依赖设备）~~ → **已实测真机可解**（540×960，
  `format=avif`）。仍建议保留 `LANLU_VIPS_TRACE` 作为设备差异的排查口；如需摆脱系统解码器，
  再考虑给 `lplatform-ohos/deps/` 增加 libavif + dav1d（与 vips/libvlc 同模式）。

## 真机状态（2026-11-12，运行时装载后）

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

- 应用 UI 仍会在启动约 4s 后 SIGSEGV（工作区未提交的 lgpu WIP；`2026-11-11` 的 bisect
  已证明删掉全部 lcodec 改动后同样崩溃）。**自检在崩溃前完成**，因此解码链路验证不受阻塞。
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
