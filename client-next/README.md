# lanlu-client-next

兰鹿桌面客户端 - 基于仓颉语言与 CangjieGUI 的 lanlu 漫画归档服务器桌面客户端

## 简介

lanlu-client-next 是 lanlu 服务器的原生桌面客户端，使用仓颉语言编写，UI 基于
[CangjieGUI](../packages/cangjie-gui)（cui，本地路径依赖）。覆盖 v1 范围：登录、书库浏览
（搜索/排序/分类/过滤/分页）、档案详情、内置图片阅读器、设置页（服务器信息、缓存清理、登出）。

## 功能特性

- **登录与会话恢复** - 地址/账号/密码登录，token 持久化，启动自动恢复会话
- **书库浏览** - 封面网格、搜索、排序、分类、仅收藏/仅未读/仅无标签过滤、分页
- **档案详情** - 元数据展示、收藏/已读切换
- **内置阅读器** - 翻页导航、阅读进度回传、前后页预取
- **图片管线** - 磁盘缓存（按服务器分目录、2GB LRU 清理）、4 线程并发上限、纹理缓存
- **设置页** - 服务器信息展示、缓存用量查看与一键清理、退出登录

## 环境要求

| 依赖 | 说明 |
|------|------|
| 仓颉工具链 (cjc) | 1.1+（本机验证 1.1.3，含 cjpm） |
| libvips | 图片转码（`vips_ffi` 本地包依赖，链接 `-lvips -lgio-2.0 -lgobject-2.0 -lglib-2.0`） |
| SDL3 动态库 | 位于 `../packages/cangjie-gui/sdl/.sdl3/`，运行时必须加入 `LD_LIBRARY_PATH` |
| stdx | 以二进制依赖引入（`CANGJIE_STDX_PATH`，与根项目同款配置） |

## 构建

```bash
cd client-next
cjpm build
```

## 运行

```bash
cd client-next
LD_LIBRARY_PATH=../packages/cangjie-gui/sdl/.sdl3:$LD_LIBRARY_PATH ./target/release/bin/main
```

> 注意：`LD_LIBRARY_PATH` 需要同时包含 SDL3 动态库目录与仓颉运行时库目录
> （cjv 安装的工具链通常已在环境变量中带上运行时路径，因此上面采用 prepend 写法）。

### Wayland 会话

在 Wayland 桌面环境下，部分系统上的 SDL3 初始化路径会与 `libglycin/libdecor`
冲突并在 `SDL_CreateWindowAndRenderer` 阶段崩溃。`main.cj` 已自动检测
`XDG_SESSION_TYPE=wayland` 并强制使用 X11/XWayland 后端；如果你想使用原生 Wayland，
可显式设置：

```bash
SDL_VIDEODRIVER=wayland LD_LIBRARY_PATH=../packages/cangjie-gui/sdl/.sdl3:$LD_LIBRARY_PATH \
    ./target/release/bin/main
```

## 测试

```bash
cd client-next
cjpm test
```

## 界面快照（无头环境冒烟）

内置 `--snapshot` 参数（CangjieGUI DesktopApp 提供）：渲染若干帧后写出 BMP 并退出，
配合 `SDL_VIDEODRIVER=dummy` 可在无显示环境验证界面：

```bash
cd client-next
SDL_VIDEODRIVER=dummy LD_LIBRARY_PATH=../packages/cangjie-gui/sdl/.sdl3:$LD_LIBRARY_PATH \
    ./target/release/bin/main --snapshot /tmp/client-next.bmp
```

## 配置与数据

| 内容 | 位置 |
|------|------|
| 配置文件（服务器地址、token、用户名） | `~/.config/lanlu-client-next/config.json` |
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
- 仅图片型（`archivetype == "image"`）档案可内置阅读
