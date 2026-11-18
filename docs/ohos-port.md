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
bash packages/lpack-ohos/tools/build-ohos.sh   # 产物: packages/lpack-ohos/target/<app>/target/ohos/hap/.../entry-default-signed.hap
# 调试种子（联调用预置会话）:
CN_OHOS_SEED_FILE=/workspace/tmp/lanlu_kv_seed.bin bash packages/lpack-ohos/tools/build-ohos.sh
```

### 前置工具（一次性，改动后需重跑对应脚本）

| 脚本 | 作用 | 何时需要 |
|---|---|---|
| `packages/lpack-ohos/tools/build-hapgen.sh` | 构建 HAP 打包器 **hapgen** | 改了 `packages/ohos/src/main.cj` |
| `packages/lpack-ohos/tools/make-sdl3-noversion.sh` | 生成 `prefix-nov`（SONAME 改短为 `libSDL3.so`） | 重编 / 升级 SDL3 后 |
| `packages/lpack-ohos/tools/build-ffmpeg-ohos.sh` | 交叉编译 ffmpeg 7.1.1（含 PCM 解码） | 需要新编解码器时 |

> ⚠️ hapgen 必须用 **host 工具链** `/workspace/.cjv/toolchains/sts-1.2.0` 构建；
> 用交叉工具链构建出的二进制运行时会 `SIGABRT`（`itfVExtensionDataStart is nullptr`）。
> `packages/lpack-ohos/tools/build-hapgen.sh` 已封装正确做法。

> ⚠️ SDL3 只允许**一份**进 HAP。SDL3 的 SONAME 是 `libSDL3.so.0`，而 `libSDL3_ttf.so`
> 等按 `libSDL3.so` 依赖；两者同时存在会让进程加载两份 SDL3，导致窗口动作/文件对话框钩子
> 注册到错误实例、`SDL_PushEvent` 恒失败（IME 文本投递不了）。
> `packages/lpack-ohos/tools/make-sdl3-noversion.sh` + `build-ohos.sh` 的 `OHOS_SDL3_PREFIX` 已统一为一份。

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
cd packages/lcodec && cjpm test    # 文件/字节两条解码入口、嗅探、backdrop、blur
```
（vips shim 的宿主机 ASAN 回归测试已随 shim 一起删除：设备端不再使用 vips。）

## 系统层补丁（packages/ohos/patches，见 ohos 仓库）

SDL 的 OpenHarmony 后端缺两类能力，均在 SDL 源码上打补丁（重建 libSDL3.so）：

1. `sdl3-openharmony-window-actions.patch`：最小化（原先 `#if 0` 空实现）→ 钩子转给 ArkTS `window.minimize()`；
2. `sdl3-openharmony-file-dialogs.patch`：文件对话框（后端无实现，回调永不触发）→ 钩子转给 ArkTS 系统 picker（打开文件复制进沙箱；保存写入沙箱再复制到用户选的 uri）。

两者都用 `dlsym` 注册，因此**未打补丁的 SDL 也能运行**（能力退化为无操作/取消）。

## 平台补齐的其它能力（全部在 packages/ohos）

| 能力 | 说明 |
|---|---|
| 键盘 | XComponent 焦点（`focusable/defaultFocus/requestFocus`）——否则 key 回调不触发 |
| 文本输入 | IME 桥接：`insertText`→SDL 文本事件、删除/回车/方向/剪贴板→按键事件；桌面不弹软键盘、手机弹 |
| 鼠标 | 窗口级过滤器 + 原点校准（disp→local） |
| 关闭/最小化 | 引擎退出标志 → `terminateSelf`；SDL 钩子 → `window.minimize()` |
| 文件对话框 | 打开/保存（见上） |

## 已知问题

1. **DevEco 调试签名配额耗尽**（`Provision number exceeds limit`）：无法产出新的 signed HAP。
   - 已确认：配额按账号/团队而非应用（换 bundleName 无效）；`--type release` 可生成材料但不含 p7b（需 AGC 发布 profile）。
   - 旧材料 p12 的 keyPassword 无法恢复（自动生成且每次重建）。
   - 影响：本轮的 vips double-free 修复尚未在真机复验（已由 ASAN 双向证明）。
2. **真实鼠标位置**待用户实测（过滤器已注册 rc=0，坐标映射带连续校准）。
3. 真实后端联调需要可运行的服务端环境（本机缺 libpq/rocksdb 等原生依赖）。

## 播放链路（libvlc_ffi shim，OHOS 后端）

- **单 demuxer**：视频与音频共用同一个 `AVFormatContext`（一条 HTTP 连接），音频包在 `pump()` 里解码，
  避免"第二条连接 + 独立音频线程"带来的复杂度和偶发问题。
- **音频输出**：`OH_AudioRenderer` 回调从环形缓冲取数据（s16 交错 48k 立体声）；
  启动时激活音频会话（`OH_AudioSessionManager_SetScene(MEDIA)` + `ActivateAudioSession`）并注册中断回调。
- **不使用 libswresample**：真机上 `swr_convert` 在 44.1k→48k 场景直接 SIGSEGV；
  改为自带转换器（s16/s16p/s32/s32p/f32/f32p/u8/u8p + 线性重采样 + 单声道复制）。
- **seek**：flush 音视频解码器 + 清空环形缓冲；`LANLU_SEEK_LOOP_MS`/`LANLU_SEEK_TARGETS` 可周期性验证。
- **调试开关**（均为 env，生产不设即无副作用）：
  | 变量 | 作用 |
  |---|---|
  | `LANLU_VLC_STATS=1` | 打印音频回调计数/音频采样数/视频帧数/解码头信息 |
  | `LANLU_VLC_NO_AUDIO=1` | 跳过音频（二分定位音视频问题） |
  | `LANLU_VLC_LOG` | 日志文件路径 |
  | `LANLU_SEEK_LOOP_MS` / `LANLU_SEEK_TARGETS` | 周期性 seek 验证 |
  | `LANLU_BENCH_*`（业务层） | 字幕/播放基准：ARCID/PAGE/PAGE_TYPE/PLAY_MS/SEEK_MS/NO_EXIT |
- 真机已验证：H.264 视频 + PCM 音轨（48k 与 44.1k）连续播放、周期性 seek 后音视频继续、
  重开（渲染器重建）后音频恢复。

## 性能观测（真机，HUAWEI MateBook Pro S）

| 场景 | CPU（单核占比） | 说明 |
|---|---|---|
| 窗口可见但空闲 | **13.6%** | 引擎侧线程 `SDL_main` 仅 ~5%，其余是 ArkUI 对 XComponent 表面的持续合成 |
| 窗口最小化 | **2.5%** | 说明引擎空闲已正确休眠（脏帧跳过 + 长等待），大头在可见时的窗口合成 |

线程分解（空闲、可见）：
```
15.9%  tid=<主线程>  （ArkUI 合成 + 轮询）
 5.4%  tid=SDL_main （引擎事件/帧循环）
 2.5%  tid=OS_EVENT_POLL
```

引擎侧空闲策略（`desktop_app.cj`）：脏帧跳过 + `waitEventTimeout(idleWaitTimeoutMs(...))`，
无定时帧时等待上限为 `Int32.Max`（真正阻塞），因此**引擎不会空转**；可见时的合成开销属系统行为。

内存（60s 播放 soak）：RSS 稳定在 **~263–271 MB**，无增长。
