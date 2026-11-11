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

**组合应用已实测（含 gui 补丁的全栈演练）**：在「对方 WIP 快照 + 34 个 gui 补丁」之上，
三个应用补丁按 0001→0002→0003 顺序连续 `git apply` 全部成功，改动标记全部就位。
三个补丁在干净基线上**按 0001→0002→0003 顺序连续 `git apply` 全部成功**，
且三个补丁的改动标记（onSubmit / FocusTarget / registerFocusStop）在应用后全部就位——顺序应用
没有 hunk 相互干扰。附注：补丁会把相关文件的 git mode 从 100755 规整为 100644（生成补丁时
工作树的可执行位差异），仅是无害告警。

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
**⚠️ 与对方未提交改动重叠**：`widgets.cj` 同时在对方的未提交改动集里。本补丁是在**含对方 WIP**
的文件内容上生成的，因此：对方先提交 → 直接 apply 没问题；对方**丢弃** widgets.cj 的改动 →
本补丁的上下文可能漂移，届时 `git apply --3way` 重试或重新生成 hunk。
**需视觉回归**：焦点环出现在这些区域时是否压住相邻内容、`ClickArea` 包裹后布局是否与原先一致
（`FocusTarget` 透传 measure/layout，理论上无差异，但覆盖 40+ 处调用点，建议真机扫一遍）。
**未验证**：整包编译（同 0001，本机缺 cargo/依赖条件）。

## 0003 阅读器 dock 键盘翻页 + Key 枚举清理

依赖框架 gui 补丁 `c62b524`（`registerFocusStop`）、`e5ee7f9`（公开 `drawFocusRing`）、
`37573de`（`Key.PageUp/PageDown`）。

| 位置 | 改动 |
|---|---|
| `reader_dock.cj` | dock 作为一个复合控件登记焦点停靠点 `reader:dock`；聚焦时 Left/Right 翻一页、PageUp/PageDown 翻十页、Home/End 到首末页（等效鼠标拖 Book 滑条，只是步进）；焦点态在页码滑条外圈画统一外环；`focusableId()` 返回停靠点 id |
| `reader_view.cj` | `Key.RawScancode(78/75)` → `Key.PageDown/PageUp`（框架分支已收进枚举，去掉 SDL scancode 魔数与过时注释） |

这是审计缺口 #5/#7 在阅读器的落点：此前纯键盘用户无法操作底部胶囊，只能靠鼠标拖滑条。

**已验证**：`git apply --check` 通过（2 文件 5 hunk）。
**需真机回归**：dock 焦点环画在页码滑条外圈（`bookSeekRect.inset(-4)`）是否压住相邻 lane tab；
Home/End 在虚拟结束页下的页码语义（沿用 `gotoDisplayPage` 的夹取）。
**未验证**：整包编译（同前，本机缺 cargo/依赖条件）。

## 后续（本目录尚未包含）

- #2：17 类自绘点击件迁 `FocusTarget`（改动面大，需逐个视觉回归）；
- #5/#7：阅读器 dock 换成 `Slider`（拿到焦点环与方向键）；
- #10：列表/卡片补 hover（部分已由框架侧行 hover 覆盖）；
- #11：长按连发需要 L 层 `LWindowEvent.repeat` 字段打通 ArkTS 输入桥。
