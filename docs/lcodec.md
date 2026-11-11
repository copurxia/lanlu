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
- AVIF 在 OHOS 只经系统 ImageSource（API 26 起、依赖设备）；若要摆脱系统依赖，
  可给 `lplatform-ohos/deps/` 增加 libavif + dav1d 的实现（与 vips/libvlc 同模式）。

## 真机状态（2026-11-12，运行时装载后）

- 新的 HAP（引擎 `NEEDED` 无 libvips、包内仍含 `libvips.so`）已打包、签名、**安装成功**；
  `liblanlu_client_next.img.so` 含 lcodec 符号 94 个。
- 启动仍因工作区未提交的 lgpu WIP 崩溃（前一节 `2026-11-11` 的 bisect 结论仍成立：
  删掉全部 lcodec 改动后同样 SIGSEGV），因此真机运行时装载的端到端验证待 lgpu 修复后进行。

## 真机状态（2026-11-11）

- HAP（含 lcodec）已打包、签名、安装成功；`liblanlu_client_next.img.so` 内 `lcodec` 符号 55 个。
- 当前真机启动峒 SIGSEGV（首帧渲染前），**与 lcodec 无关**：用反向勾选构建的
  无 lcodec 产物（`nm -D` 中 lcodec 符号数 0）同样 SIGSEGV；崩溃在窗口创建后约 0.6s，
  疑与当前工作区未提交的 lgpu WIP（`packages/lgpu` 1212 行）相关。
  lcodec 本身解码路径定位在图片增量解码工作线程，不参与启动路径。
- 下一步：先解决 lgpu WIP 崩溃，再用 `OHOS_SELFTEST=1` 跑 `vipstest.txt`（已扩展为
  同时验证 PNG/WebP 嗅探 + lcodec 解码路径）。
