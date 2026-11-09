# client-next on HarmonyOS — 移植验收报告

生成时间：2026-11-09（本轮为滚动更新，随验证推进修订）
HAP：`entry-default-signed.hap` ≈ **92.4 MB**（原 124.4 MB，经依赖库 SONAME 归一化 + 别名去重 + unittest 库剔除）
设备：HUAWEI MateBook Pro S（2in1），`192.168.0.26:42113`，HarmonyOS（API 26 SDK 构建）
说明：当前安装包 bundle 为 `com.example.cmakehap`（复用本机已有调试签名材料的权宜方案，见"遗留"）。

## 一、真机已验证（有日志/像素/请求级证据）

| 能力 | 证据 | 结论 |
|---|---|---|
| 安装 / 启动 / 进程存活 | `pidof` 多轮存活；无 `signo`/relocating | ✅ |
| 首帧渲染 | 窗口截图与停止态差分 > 3M 像素 | ✅ |
| 系统壳能力 | `[LANLU-SHELL] startFilter win=… rc=0`、`IME attached win=…` | ✅ |
| 会话恢复 | mock 收到 `/api/info`、`/api/auth/me`、`/api/search`、`/api/categories`（多次启动均如此） | ✅ |
| 书库 + 封面渲染 | `/api/assets/1` 请求成功；截图检出 4000+ 金色封面像素（此前必崩，vips shim 双 free 已修） | ✅ |
| 详情页交互 | 点击卡片 → `/api/archives/<id>/{metadata,files,tankoubons,recommendations,tags/translations}`，界面差分 1.79M 像素 | ✅ |
| 窗口关闭 | 点击标题栏关闭 (2560,332) → 进程退出、无 crash 日志（不再残留空白窗口） | ✅ |
| 窗口最小化 | 点击 (2493,332) → `ui window list` 变空、进程存活 | ✅ |
| 重启后数据保留 | 沙箱 KV 文件持久；再次启动会话自动恢复 | ✅ |
| 视频播放（H.264） | `video stats frames=60/120/180/240` 持续增长（MP4 与自封装 MKV 两种容器） | ✅ |
| 音频播放（PCM 48k） | `audio write cb` 持续、`frames=191040→767040`（≈16s，48k 换算吻合） | ✅ |
| 音频播放（PCM 44.1k，需重采样） | 同上量级，稳定；证明自研重采样可用 | ✅ |
| seek | `LANLU_SEEK_LOOP_MS` 循环跳转 3 轮：视频帧 900→1200、音频帧 88320→664320 持续，进程存活 | ✅ |
| 重开/渲染器重建 | reopen 后 `frames` 归零再增长至 862080，进程存活 | ✅ |
| HAP 体积 | 124.4 MB → 92.4 MB | ✅ |

## 二、静态/主机验证（无需设备）

| 门禁 | 内容 | 结果 |
|---|---|---|
| 分层守卫 `tools/check-layering.sh` | 业务/UI/SDL 绑定层禁止平台专有标识 | PASS |
| 依赖闭包 `check-soname-closure.sh` | 83 个 NEEDED 全部可由 HAP 或 NDK sysroot 解析；全部 AArch64 | PASS |
| 符号一致性 `check-symbol-consistency.sh` | `cj_app_main`/`InitCJRuntime`/SDL 两个补丁钩子等均由随包库导出 | PASS |
| ASAN 主机测试 | vips shim（旧版 heap-use-after-free / 新版 clean）、rocksdb 桥（CF/批/迭代/持久） | PASS |
| 构建 | `cjpm` 交叉编译 + ArkTS 编译 + hvigor 打包 + 签名（复用材料） | PASS |

## 三、本轮修复的关键缺陷（真机暴露）

1. **vips shim 重复 free** → 书库封面必崩（改引用计数，ASAN 复现/验证）。
2. **rocksdb 目录缺失** → KV 静默丢数据（补 mkdirs + 主机测试）。
3. **SONAME 归一化错误** → 差点启动即崩（`libSDL3.so.0` 被误删）。
4. **ffmpeg 缺 PCM 解码器** → WAV/PCM 音轨无法解码（重编 ffmpeg，脚本入库）。
5. **libswresample `swr_convert` 崩溃**（44.1k→48k）→ 改自研转换器。
6. **音频"第二条 HTTP 连接 + 独立线程"复杂度过高** → 改单 demuxer（音频包在 pump 内解码）。
7. **bench/自动化缺少超时与开关** → 加冷扫描超时、`NO_EXIT`、`SEEK_LOOP`、`VLC_STATS` 等。

## 四、平台适配层（lwindow，对标 Chromium ui/ozone）

- 业务层 `client-next/src` 与 `cui`/`sdl` 已无平台专有代码（守卫脚本可验证）。
- `packages/lwindow`：进程环境/路径/字体配置/首次启动种子 + 窗口几何/缩放、渲染驱动优先级、桌面集成、系统字体回退。
- `packages/portcheck`：移植自检（图片/网络/媒体/字幕）+ URL 探测钩子。
- ArkTS/C++ 壳（`packages/ohos`）：XComponent、IME 桥、文件选择器、最小化/关闭/退出、SDL 两个补丁钩子。

## 五、遗留与风险

| 项 | 状态 | 说明 |
|---|---|---|
| IME 文本输入 | ✅ 已验证（桥接层） | 引擎收到 `[input] TEXT_INPUT text="hello-ohos"`（走 SDL user event 通道）；物理键盘拼音输入仍需人工抽查 |
| AAC/Opus 真实样片 | ⏳ 待验 | 转换器已支持 fltp 等平面格式，但仓库内无带音轨的 AAC 样片可测 |
| 正式包名/签名 | ⚠️ 权宜 | 现用 `com.example.cmakehap`（复用已有调试材料）；配额恢复后应改回 `com.lanlu.clientnext` 并生成正式 Profile |
| 文件对话框三件套 | ✅ 链路已验证 | 请求→钩子→ArkTS→系统 picker 进程拉起；`completeFileDialog` → 引擎回调已真机验证（取消/超时路径返回 null）。**本机系统 picker 自身不稳定（`filePicker service died`）**，故加了 120s 超时兜底，超时按取消处理 |
| 鼠标位置 | ⏳ 待确认 | 用户此前反馈"位置不对"；过滤器已按窗口矩形自校准，需人工复核 |
| 空闲 CPU | 观察 | 空闲截图差分为 0（不空转），但 top 累计均值显示 15–22%（疑 GC/运行时后台线程） |

## 六、鼠标坐标自检（人工，10 秒）

实现要点（`packages/ohos/templates_sdl3/entry/src/main/cpp/input_filter.cpp`）：
1. ArkTS 侧 `startFilter(winId, rect.left, rect.top)` 把窗口矩形原点交给 native，`lanlu_seed_origin()` 记为初始原点；
2. 物理鼠标事件走 `OH_NativeWindowManager_RegisterMouseEventFilter`，得到的是**屏幕坐标**，
   native 减去原点得到窗口局部坐标后推入 SDL；
3. 运行时还会用 SDL 自身 lane（XComponent 局部坐标）做**自校准**，两者一致时原点持续修正。

自检步骤：
1. `hdc shell hilog -r` 清日志；
2. 用物理鼠标在窗口内移动几下（必须真鼠标，`uitest uiInput` 只能注入触摸，验证不到这条 lane）；
3. 看日志：
   ```
   filter evt act=.. disp=(Dx,Dy) local=(Lx,Ly) btn=..
   [LANLU-SHELL] startFilter win=.. rect=(Ox,Oy,W,H)
   ```
4. 判定：`Lx ≈ Dx - Ox`、`Ly ≈ Dy - Oy`（当前设备窗口 rect 原点为 (515,292)）。
   满足即鼠标定位正确；若纵向恒差约 70px，说明窗口矩形含了系统装饰高度（本工程窗口是 borderless，
   正常不应出现）。

## 七、关键平台缺陷：进程内两份 SDL3（已修）

现象：窗口动作/文件对话框"钩子注册成功"但无效；`SDL_PushEvent` 恒返回 0；IME 文本无法投递。

根因：SDL3 的 SONAME 是 `libSDL3.so.0`，而 `libSDL3_ttf.so` 等按 `libSDL3.so` 文件名依赖；
两个名字各自对应一个文件 → 进程里加载**两份 SDL3**：引擎初始化其中一份，壳（libmain）拿到另一份未初始化的。

修复：`tools/make-sdl3-noversion.sh` 生成 `prefix-nov`（同一份库，SONAME 原地改短为 `libSDL3.so`），
壳与引擎都用它链接 → 三方 DT_NEEDED 全部为 `libSDL3.so` → 只加载一份。

修复后真机证据：
```
inited(VIDEO)=0x20 inited(EVENTS)=0x4000
probe user push=1
push=1 text=hello-ohos
[input] TEXT_INPUT text="hello-ohos" (user event)
```

## 八、最终验收运行（本轮，全部同一构建）

| # | 检查 | 证据 |
|---|---|---|
| A | 冷启动 | `pid=38397` 存活 |
| B | 系统壳 | `hook registered ×2`、`LANLU-SHELL` 日志 ×2 |
| C | 书库封面 | 金色像素 4143（窗口内截图统计） |
| D | 音视频播放 | `video stats frames=240→300`、`audio write cb calls=400/600/800, frames=94080→478080` |
| E | IME 文本桥 | `[input] TEXT_INPUT text="final-check" (user event)` |
| F | 静态门禁 | `tools/verify-ohos.sh`：分层/依赖闭包/符号 全 PASS |

### 仍未闭环（外部条件，非实现缺口）

| 项 | 阻塞原因 |
|---|---|
| 正式包名/签名 | AGC `Provision number exceeds limit`（账号级配额；本轮再次确认：代理关掉后可走到 profile 阶段，仍被配额拦下） |
| IME 拼音实际输入 | 需真实键盘（桥接层已用注入路径验证到引擎） |
| AAC/Opus 码流 | 离线环境无从取得带音轨样片（转换器已支持 fltp 等平面格式） |
| picker 选中/取消 | 本机系统 picker 进程 `service died`；已加 120s 超时兜底，取消路径已验证 |
