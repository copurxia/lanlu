# client-next 的 HarmonyOS（OpenHarmony）移植

状态：**功能移植完成并逐项真机验证**；剩余为设备侧体验确认与签名配额导致的部署阻塞（见"已知问题"）。

## 分层

- **系统层全部在 `packages/ohos`**（见 .research-ohos/packages/ohos）：
  - ArkTS 壳：窗口/焦点/生命周期（`templates_sdl3/entry/src/main/ets/pages/Index.ets`）
  - 原生输入：窗口级鼠标过滤器 `input_filter.cpp`（display 坐标 → 组件局部坐标 + 连续原点校准、滚轮 ÷45）
  - NAPI：`shell_napi.cpp`（`lanlushell.startFilter(winId, ox, oy)`）
  - HAP 生成器 hapgen（模板 + 资源 + 签名流程）
- **业务层保持跨平台**：client-next / cui 不含任何 OHOS 特有代码；平台差异只经 packages/* shim 与 ohos_entry 注入。

## 构建

```bash
bash client-next/ohos/build-ohos.sh            # 产物: build/ohos/.../entry-default-signed.hap
# 调试种子（联调用预置会话）:
CN_OHOS_SEED_FILE=/workspace/tmp/lanlu_kv_seed.bin bash client-next/ohos/build-ohos.sh
```

## 端到端联调（mock 后端）

```bash
python3 .research-ohos/mock-backend.py 8080        # /api/info|me|search|categories|assets + /__stats
python3 .research-ohos/mock-gen-seed.py seed.bin   # 生成含 profile+token 的 KV 种子
bash .research-ohos/verify-cn.sh                   # 构建→安装→启动→校验进程/请求/渲染
```

真机已观测：`/api/info`、`/api/auth/me`（令牌鉴权会话恢复）、`/api/search?row=resume`、`/api/categories`、三行书库、`/api/assets/1`（封面）。

## 已验证能力（真机）

| 能力 | 证据 |
|---|---|
| 渲染/交互 | 像素差 3.26M；键盘 3×ArrowDown → 176,845 px |
| KV（列族 + 持久） | cfid 隔离、重启保留；settings JSON v3 |
| 图片 PNG/JPEG/WebP | 解码 RGBA；WebP 走 OH ImageSource 回退 |
| HTTP/HTTPS/TLS | net/net2 = 200（含自签 TrustAll 校验） |
| 字体枚举 | 260 个系统字体 |
| 字幕 | 探测（ffmpeg，3 流 it=ass）+ libass 渲染（500×129） |
| 视频+音频+seek | frames=1099 640×360；audio frames_written=200610；seekTo=2.833s |
| HTML 阅读（Blitz） | 800×600 RGBA 出帧；fontconfig 最小配置指向 /system/fonts |
| 后端联调 | 见上（mock 请求日志） |

## 回归测试（主机侧，无需设备）

```bash
bash packages/vips_ffi/native-ohos/run-host-test.sh <image>
# ASAN: decodeFileToRgba 的 handle/unref 序列 + resize/extract/gaussblur 链
```

## 已知问题

1. **DevEco 调试签名配额耗尽**（`Provision number exceeds limit`）：无法产出新的 signed HAP。
   - 已确认：配额按账号/团队而非应用（换 bundleName 无效）；`--type release` 可生成材料但不含 p7b（需 AGC 发布 profile）。
   - 旧材料 p12 的 keyPassword 无法恢复（自动生成且每次重建）。
   - 影响：本轮的 vips double-free 修复尚未在真机复验（已由 ASAN 双向证明）。
2. **真实鼠标位置**待用户实测（过滤器已注册 rc=0，坐标映射带连续校准）。
3. 真实后端联调需要可运行的服务端环境（本机缺 libpq/rocksdb 等原生依赖）。
