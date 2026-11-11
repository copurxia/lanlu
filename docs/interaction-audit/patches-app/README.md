# 应用层补丁（合并 gui 分支后再应用）

> 这些补丁改的是 `client-next`（应用层），依赖 `p0-focus-visible` 分支提供的新 API
> （`TextField(onSubmit:)`、`.autofocus()`）。**必须先合并/应用 [../patches/](../patches/README.md)
> 的 gui 补丁，再应用本目录补丁**，否则编译不过。

## 0001 表单回车提交与弹窗初始聚焦

| 位置 | 改动 |
|---|---|
| `login_view.cj` 密码面板 | 账号框 `.autofocus()`（进入登录页即可直接输入）；账号/密码框 `onSubmit` → `loginSelected`（回车即登录） |
| `login_view.cj` TOTP 面板 | 验证码框 `.autofocus()`；验证码/恢复码框 `onSubmit` → `verifyTotp` |
| `login_view.cj` 服务器编辑弹窗 | 名称框 `.autofocus()`；名称/地址框 `onSubmit` → `saveServer` |
| `detail_dialogs.cj` | 新建合集输入框回车 = 「创建并加入」；合集添加搜索框回车 = 搜索 |
| `add_to_tank_dialog.cj` | 新建合集输入框回车 = 「新建并加入」 |

对应审计缺口 #3（全应用 0 处 autofocus）与 #4（表单 Enter 不提交）的高频入口。

## 应用与验证

```bash
cd /path/to/lanlu                     # 仓库根
git apply --check docs/interaction-audit/patches-app/0001-*.patch   # 先干跑
git apply docs/interaction-audit/patches-app/0001-*.patch
```

**已验证**：
- `git apply --check` 在本次提交的仓库状态上干净通过（3 个文件、7 个 hunk）。
- 补丁里所有新代码都是**复制同文件已有的调用表达式**（按钮的 onClick 体原样搬进 `onSubmit`），
  并已逐个核对被调 API 的签名（`loginSelected(String, String)`、`verifyTotp(String, String)`、
  `saveServer(String, String)`、`createTankAndAdd(String, ArrayList<String>)`、
  `submitTankAddSearch(model, cell, tankId, String)`）。

**未验证**：整包 `cjpm build`。本机缺少 `cargo`（应用 `build.cj` 的 pre-build 需要构建
fontkit 原生库），`--skip-script` 又会因依赖树里同时存在 `lcodec` 与演练副本而冲突；
请在具备完整构建环境的机器上编译确认。

## 0002 ClickArea 与自绘图标钮接入焦点环

依赖框架新增的公开 API `registerFocusStop`（gui 补丁 `c62b524`）与既有 `FocusTarget`。

| 位置 | 改动 |
|---|---|
| `widgets.cj` `ClickArea` | 实现由「ZStack + ClickSensor」改为 **`FocusTarget` 包裹**：一次改动让全部 **40+ 处**调用点（详情页 10、设置页 5、登录页 5、阅读器 4、书架/标签等）同时获得 Tab 可达、Enter/Space 激活、键盘焦点外环；点击语义不变（按下+框内抬起才触发），悬停仍认领手型 |
| `widgets.cj` `GhostIconButton` | 自绘图标钮自己就是控件：`registerFocusStop(hoverId)` 登记停靠点、`MouseDown` 聚焦、`Enter/Space` 激活、`showFocusRing` 时画外环、`layout` 上报焦点矩形（配合框架的滚入视野）。`hoverId` 本身实例唯一（`detail:addtank`/`reader.topbar.back` 等），直接复用为焦点 id |

这是审计缺口 #2（17 类自绘点击件全不在 Tab 环）**结构性解法**的落地：框架侧开放登记能力，
应用侧两处小改动覆盖绝大多数自绘件。

**已验证**：`git apply --check` 在当前仓库状态干净通过（1 文件 5 hunk）。
**需视觉回归**：焦点环出现在这些区域时是否压住相邻内容、`ClickArea` 包裹后布局是否与原先一致
（`FocusTarget` 透传 measure/layout，理论上无差异，但覆盖 40+ 处调用点，建议真机扫一遍）。
**未验证**：整包编译（同 0001，本机缺 cargo/依赖条件）。

## 后续（本目录尚未包含）

- #2：17 类自绘点击件迁 `FocusTarget`（改动面大，需逐个视觉回归）；
- #5/#7：阅读器 dock 换成 `Slider`（拿到焦点环与方向键）；
- #10：列表/卡片补 hover（部分已由框架侧行 hover 覆盖）；
- #11：长按连发需要 L 层 `LWindowEvent.repeat` 字段打通 ArkTS 输入桥。
