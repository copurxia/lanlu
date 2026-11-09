# HarmonyOS 移植交接说明

本文件面向"接手把最后几项做完"的人。功能实现与真机验证已完成，见
[ohos-port-acceptance.md](ohos-port-acceptance.md)（验收矩阵）与
[ohos-port.md](ohos-port.md)（构建/联调/性能）。

## 1. 一键构建 → 签名 → 安装

```bash
# 1) 构建（末尾自动跑静态门禁：分层/HAP 依赖闭包/关键符号）
CN_OHOS_SEED_FILE=/workspace/tmp/lanlu_kv_seed.bin \
  bash client-next/ohos/build-ohos.sh

# 2) 签名（复用本机已有调试材料，绕开 AGC 配额）
bash tools/sign-hap.sh

# 3) 安装启动
hdc -t 192.168.0.26:42113 install \
  client-next/build/ohos/target/ohos/hap/entry/build/default/outputs/default/entry-default-signed.hap
hdc -t 192.168.0.26:42113 shell aa start -b com.example.cmakehap -a EntryAbility
```

前置脚本（改动后需重跑）：`tools/build-hapgen.sh`（改了 `packages/ohos/src/main.cj`）、
`tools/make-sdl3-noversion.sh`（升级 SDL3 后）、`tools/build-ffmpeg-ohos.sh`（换编解码器时）。

## 2. 剩余四项及其操作步骤

### 2.1 正式包名/签名（唯一硬阻塞）
现象：`devecocli signature generate` → `Provision number exceeds limit.`（账号级配额）。

收尾步骤：
1. 在 AGC 控制台清理历史 profile（或等配额恢复）；
2. 把 `client-next/cjpm.toml` 与 `client-next/ohos/cjpm.toml.ohos` 的
   `bundle-name` 改回 `com.lanlu.clientnext`；
3. `cd client-next/build/ohos/target/ohos/hap && devecocli signature generate --product default --type debug`
   （会写入官方 signingConfigs）；
4. 重新 `build-ohos.sh`（此时**不要**再跑 `sign-hap.sh`），安装包名即为产品包。

> 备选：`~/.ohos/config` 里有一份 `com.example.clientnext` 的 debug profile（有效期到 ~2027-11），
> 但对应 p12 的密码未记录；若能找回密码，可把 `sign-hap.sh` 的材料换成那一组，
> 包名改为 `com.example.clientnext`。

### 2.2 IME 拼音实际输入（需真人键盘）
桥接已用注入路径验证到引擎（`[input] TEXT_INPUT text="..." (user event)`）。人工确认步骤：
1. 启动应用，点标题栏搜索框；
2. 用物理键盘输入拼音 → 候选词 → 上屏，确认文字进入输入框、光标位置正确；
3. 若异常，看 `hilog | grep LANLU-SHELL` 是否有 `IME attached`、
   以及 `$HOME/input_log.txt`（需 `LANLU_INPUT_LOG=1`）中的 `TEXT_INPUT` 记录。

### 2.3 AAC/Opus 真实码流
自制转换器已支持 `s16/s16p/s32/s32p/f32/f32p/u8/u8p` + 线性重采样（因为
`libswresample` 在本构建下 44.1k→48k 必崩）。验证方法：
1. 取一个带 AAC 音轨的视频（mp4/mkv）；
2. `MOCK_VIDEO=/path/to/file.mp4 python3 .research-ohos/mock-backend.py 8080`；
3. 启动并带动 `LANLU_VLC_STATS=1`，确认 `pipeline: ... audio_stream=1`、
   `audio write cb` 持续增长且进程不崩。

### 2.4 系统文件选择器
本机 picker 进程会 `service died`（系统侧），因此加了 120s 超时兜底
（超时按取消处理，引擎不会卡死）。人工验证：点"打开文件"→ 在选择器里选一个文件，
确认 `hilog | grep 'test dialog callback'` 出现带路径的回调。

## 3. 架构导航（改哪里）

| 关注点 | 位置 |
|---|---|
| 业务/UI（跨平台） | `client-next/src/`（禁止出现平台标识，`tools/check-layering.sh` 会把关） |
| 平台适配层（对标 Chromium ozone） | `packages/lwindow/`：进程环境/路径/字体/首启种子、窗口几何、渲染驱动、桌面集成 |
| 视图/控件框架 | `packages/cangjie-gui/`（cui + sdl 绑定，含事件解码、文本输入分发） |
| OHOS 系统层 | `packages/ohos/`：ArkTS 壳（XComponent/IME/窗口控制/picker）+ C++ 桥（`shell_napi.cpp`、`input_filter.cpp`、`sdl_main.c`）+ hapgen 打包器 |
| 媒体 | `packages/libvlc_ffi/native-ohos/vlc_shim.c`（单 demuxer、OH_AudioRenderer、自研重采样） |
| 自检 | `packages/portcheck/`；静态门禁 `tools/verify-ohos.sh` |

## 4. 已知问题（非阻塞）

| 问题 | 现状/原因 |
|---|---|
| 可见空闲 CPU ≈13.6%（最小化 2.5%） | 引擎已正确空闲；差额是 ArkUI 对 XComponent 的持续合成 |
| 系统 picker 进程崩溃 | 设备系统侧（`filePicker service died`）；已加超时兜底 |
| 空闲 RSS ≈263MB | 含 Cangjie 运行时 + ffmpeg + vips；60s 播放无增长 |
| `libSDL3.so` 只允许一份 | 双实例会让钩子/事件队列错位、`SDL_PushEvent` 恒失败（详见验收报告第七节） |
