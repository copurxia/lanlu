# lanlu-client-next

兰鹿桌面客户端 - 基于仓颉语言与 CangjieGUI 的 lanlu 漫画归档服务器桌面客户端

## 简介

lanlu-client-next 是 lanlu 服务器的原生桌面客户端，使用仓颉语言编写，UI 基于
[CangjieGUI](../packages/cangjie-gui)（cui，本地路径依赖）。覆盖 v1 范围：登录、书库浏览
（搜索/排序/分类/过滤/分页）、档案详情、内置图片阅读器、设置页（概览 dashboard/账户安全/外观/缓存 + 管理板块：分类/标签/智能分类/用户/系统设置/任务/定时任务/插件/统计信息）。

## 功能特性

- **登录与会话恢复** - 地址/账号/密码登录，token 持久化，启动自动恢复会话
- **书库浏览** - 封面网格、搜索、排序、分类、仅收藏/仅未读/仅无标签过滤、分页
- **档案详情** - 元数据展示、收藏/已读切换
- **内置阅读器** - 翻页导航、阅读进度回传、前后页预取
- **图片管线** - 磁盘缓存（按服务器分目录、2GB LRU 清理）、4 线程并发上限、纹理缓存
- **设置页** - 左分类导航（个人区/客户端/服务器/其他）；概览含账号卡、服务器信息与阅读统计 dashboard；账户安全（凭据/TOTP 状态/Passkey/登录设备/API Token）；外观明暗主题即切即生效；缓存查看与清理；管理板块（分类/标签/智能分类/用户/系统设置/任务记录/定时任务/插件/统计信息），非管理员自动隐藏；语言/诊断为占位板块

## 环境要求

| 依赖 | 说明 |
|------|------|
| 仓颉工具链 (cjc) | 1.1+（本机验证 1.1.3，含 cjpm） |
| libvips | 图片转码（`vips_ffi` 本地包依赖，链接 `-lvips -lgio-2.0 -lgobject-2.0 -lglib-2.0`） |
| libVLC 3+ | 应用内视频解码（`libvlc_ffi` 本地包依赖，Linux 包通常为 `libvlc-dev` + `vlc-plugin-base`） |
| SDL3 动态库 | 位于 `../packages/cangjie-gui/sdl/.sdl3/`，运行时必须加入 `LD_LIBRARY_PATH` |
| MMKV 1.2.15 / kv4cj | 按 `../ref/kv4cj/README.md` 先生成 `libcore.so` 与 `libmymmkv.so` |
| stdx | 以二进制依赖引入（`CANGJIE_STDX_PATH`，与根项目同款配置） |

## 构建

```bash
cd client-next
LD_LIBRARY_PATH=../ref/kv4cj/lib:$LD_LIBRARY_PATH cjpm build
```

## 运行

```bash
cd client-next
LD_LIBRARY_PATH=../ref/kv4cj/lib:../packages/cangjie-gui/sdl/.sdl3:$LD_LIBRARY_PATH \
    ./target/release/bin/main
```

> 注意：`LD_LIBRARY_PATH` 需要同时包含 SDL3 动态库目录与仓颉运行时库目录
> （cjv 安装的工具链通常已在环境变量中带上运行时路径，因此上面采用 prepend 写法）。

### Wayland 会话

原生 Wayland 的启动崩溃（libglycin 初始化竞态，约 1/3~1/2 概率在
`SDL_CreateWindowAndRenderer` 阶段 SIGSEGV）根因是 libdecor 的 **GTK 插件**
在窗口创建时初始化 GTK3。`main.cj` 在 Wayland 会话下会把 `LIBDECOR_PLUGIN_DIR`
指向随仓库发布的 **libdecor-cairo 插件**（`../packages/cangjie-gui/sdl/libdecor-plugins/`，
无 GTK 依赖），GTK 插件不再加载，原生 Wayland 实测 20/20 启动 0 崩溃
（详见 `.superpowers/sdd/task-e2-report.md`）。渲染驱动优先级为
**D3D/Metal > vulkan > opengl > software**：Windows/macOS 交给 SDL 自动选择
（D3D11/12、Metal 本来就在内置顺序最前）；Linux 桌面会话（wayland/x11）默认
**vulkan**（SDL3 内置顺序是 opengl 在 vulkan 之前，故需显式指定；创建失败 SDL
自动回退 opengl → software），图片纹理走 GPU 上传；如在你的环境 GPU 路径
异常可设 `LANLU_SOFTWARE_RENDER=1` 回退 software 渲染。
你可通过环境变量覆盖任一环节：

```bash
# 使用系统 libdecor GTK 插件（原生装饰，若你的环境无 glycin 竞态）
LIBDECOR_PLUGIN_DIR=/usr/lib/x86_64-linux-gnu/libdecor/plugins-1 ./target/release/bin/main
# 强制 X11/XWayland 后端
SDL_VIDEODRIVER=x11 ./target/release/bin/main
# 回退 CPU 渲染（GPU 路径异常时）
LANLU_SOFTWARE_RENDER=1 ./target/release/bin/main
```

另注：`../packages/cangjie-gui/sdl/.sdl3-nolibdecor/` 保留了一份无 libdecor 的
自编译 SDL3 3.4.2（`-DSDL_WAYLAND_LIBDECOR=OFF`，同样 20/20 通过），作为
cairo 插件方案失效时的兜底；注意该构建在 GNOME 下窗口无装饰。

## 测试

```bash
cd client-next
LD_LIBRARY_PATH=../ref/kv4cj/lib:$LD_LIBRARY_PATH cjpm test
```

## 界面快照（无头环境冒烟）

内置 `--snapshot` 参数（CangjieGUI DesktopApp 提供）：渲染若干帧后写出 BMP 并退出，
配合 `SDL_VIDEODRIVER=dummy` 可在无显示环境验证界面：

```bash
cd client-next
SDL_VIDEODRIVER=dummy \
    LD_LIBRARY_PATH=../ref/kv4cj/lib:../packages/cangjie-gui/sdl/.sdl3:$LD_LIBRARY_PATH \
    ./target/release/bin/main --snapshot /tmp/client-next.bmp
```

## 配置与数据

| 内容 | 位置 |
|------|------|
| 客户端设置（MMKV，服务器、会话、主题、阅读选项） | `~/.config/lanlu-client-next/mmkv/` |
| 图片磁盘缓存（按服务器地址哈希分目录） | `~/.cache/lanlu-client-next/` |

## 项目结构

```text
client-next/
├── src/
│   ├── main.cj            # 入口 + 根路由（按 model.page 切页）
│   ├── theme.cj           # 主题
│   ├── app/               # AppModel（状态/会话/任务泵）、设置持久化、路由
│   ├── net/               # HTTP API 封装、DTO/JSON 解析、工作线程
│   ├── img/               # 图片磁盘缓存、vips 转码
│   └── ui/                # 登录/书库/详情/阅读器/设置 五个页面 + 公共控件
├── cjpm.toml
└── README.md
```

## 已知限制（v1）

- 密码输入框为明文显示（CUI 暂无密码掩码控件）
- 仅 http 官方支持（https 未验证）
- 不支持开启了 TOTP 两步验证的账号
- HTML 等非图片/音视频页面类型仍只显示占位提示
