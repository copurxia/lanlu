# lpack-ohos —— 鸿蒙工程生成器与打包器（平台包）

计划：[docs/lwindow-platform-separation-plan.md](../../docs/lwindow-platform-separation-plan.md) §4.3、§9.2。

职责：**主仓不存放任何鸿蒙工程**。本包读取 app profile + 引擎产物 + `lplatform-ohos` 的壳源码，
生成完整鸿蒙工程到不入库的 `build/ohos/`，调用 hvigor 打包并签名。

上游：`git.copur.xyz/cangjie-ohos/ohos`（hapgen）。本目录是它的主仓副本，日常在此开发，定期回推。

## 目录

```
src/main.cj           hapgen：读模板 + app metadata → 生成工程 → hvigor → 签名
templates/            鸿蒙工程骨架（AppScope、entry、hvigor 配置、module.json5）
templates_sdl3/       覆盖层（当前壳形态）；壳的 cpp/ets 不在这里，见 lplatform-ohos/shell
assets/default/       AppScope / entry 的图标与背景
assets/libcxx/        OHOS 可用的 libc++.so（ABI 对齐，见 client-next-ohos-plan.md 附录 G）
```

## 用法

由 `client-next/ohos/build-ohos.sh` 调用：

```
lpack-ohos  gen --sign      # 当前入口：生成 + 构建 + 签名（在工作目录下执行）
```

hapgen 读取的环境变量：

| 变量 | 含义 |
|---|---|
| `OHOS_TEMPLATES` | 模板根；同级 `<值>_sdl3` 为覆盖层（构建脚本在 `build/ohos/.hap-templates` 里拼好） |
| `OHOS_ASSETS` | 图标资源目录 |
| `OHOS_LIBCXX` | libc++.so 路径 |
| `OHOS_UI` | 壳形态（当前 `sdl3`） |
| `OHOS_EXTRA_LIBS` / `OHOS_LGPU_LIB` / `OHOS_SDL3_PREFIX` / `OHOS_STRIP` | 链接与打包参数 |

## 构建 hapgen 本体

必须用 **host 工具链**（交叉工具链编出的二进制运行时会 `SIGABRT`，见 ohos-port.md）：

```
bash packages/lpack-ohos/tools/build-hapgen.sh
```

## 迁移状态（M0）

- [x] 从仓外 `.research-ohos/packages/ohos` 迁入主仓（源 + 模板 + 资源）
- [x] 壳源码（cpp/ets）从模板移除，改由 `lplatform-ohos/shell` 在构建时覆盖
- [x] hapgen 读 `app-profiles/<app>/app.toml`（包名/版本/API/设备/权限/querySchemes），
      缺省回退 `cjpm.toml` 元数据；模板用 `__PERMISSIONS__` / `__QUERY_SCHEMES__` 占位
- [ ] M0 收尾：`build-ohos.sh` 改为一条 `lpack-ohos build --app lanlu` 命令；工具链路径改为配置项
- [ ] M6：`templates_sdl3` 覆盖层随 SDL 一并删除，改为 `templates_lwp`

## 自检（不构建）

```bash
bash tools/build-ohos.sh --self-check     # 只校验工具链/profile/预编译材料，秒级
bash tools/build-ohos.sh                   # 完整构建
bash tools/build-ohos.sh --app <name> --build-dir <dir>   # 换 profile / 输出目录
```

与 `lpack-linux` 的 `build-deb.sh --self-test` 对齐：**先能给自检，再谈构建** ——
环境问题在秒级暴露，而不是构建到一半才炸。
