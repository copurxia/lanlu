# lcodec —— Lanlu 解码统合层

> 目标一句话：**业务层（client-next）与 UI 框架（cui）不再直接 import 任何解码 FFI 包**；
> 图片解码/缩放/圆角/模糊全部经 lcodec 的跨平台 API。平台差异（桌面 libvips 后端 vs
> OHOS stb+ImageSource shim 的同名 libvips.so）只存在于 FFI 层与 packages/lplatform-ohos，
> 业务层零感知。

## 分层位置（对标 lwindow）

```
client-next ──┐
cui           ─┴─> lcodec ──> vips_ffi ──> [libvips.so (桌面) | vips_shim.c (OHOS, lplatform-ohos)]
```

- lcodec 只含跨平台代码（`tools/check-layering.sh` / `check-platform-isolation.py` 把关）。
- 解码器实现不进 lcodec：桌面用系统 libvips；OHOS 由
  `packages/lplatform-ohos/deps/vips/vips_shim.c`（stb_image + OH ImageSource 回退）以
  同符号 `libvips.so` 顶替，构建时由 lpack-ohos 打进 HAP。

## API（保持与原 client-next/src/img/vips_decode.cj 完全同名同语义）

| API | 用途 |
|---|---|
| `NativeDecodedImage` | 解码产物（原生 RGBA 内存，RAII 语义，close 幂等） |
| `decodeFileToRgba(path, maxDimension?)` | 任意格式图片文件 → RGBA；超过档位时解码期缩小 |
| `decodeBackdrop(path, targetWidth, blurSigma?)` | 缩到目标宽 + 模糊（详情页背景） |
| `decodeCachedOrEvict(cache, key, path, maxDimension?)` | 解码失败剔除坏缓存后原样抛出（与 ImageCache 协作） |
| `roundCoverAlphaNative(img)` | 封面圆角（alpha 直写） |
| `sniffImageFormat(path)` | 魔数嗅探（诊断：报告实际容器格式而非"解码失败"） |

`sniffImageFormat` 是这次统合新增的诊断口：OHOS 真机上 vips shim 对不支持的格式
（如 AVIF）只报空错误串（`vips_error_buffer()` 恒空），以前 UI 只能看到"error"占位；
现在异常信息会带 `format=avif` 与文件大小，直接指出该格式落在哪条后端链路。

## 宿主单测

```bash
export LCODEC_STUB_LIB_DIR=...   # 有 libvips 可不设
(cd packages/lcodec && cjpm test)
```
