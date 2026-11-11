# client-next 应用层接线清单（待 `p0-focus-visible` 合并后应用）

> 前置：合并 `p0-focus-visible` 分支（提供 `TextField(onSubmit:)`、`FocusTarget`、
> `Pagination/Breadcrumb/StepIndicator/WordCloud` 键盘化、`Modal` 初始聚焦与恢复、
> `Key.PageUp/PageDown/Menu`、`ScrollView/TextArea` 键盘滚动、`Toast` 交互、
> `Tooltip` 键盘可见、`RadioButton.groupRange`、只读字段不进焦）。

## A. 表单回车提交（缺口 #4）——预计 12 处

| 位置 | 改法 |
|---|---|
| `login_view.cj:262` 登录用户名 | `TextField(user, key: ..., leadingIcon: IconName.User, onSubmit: {=> submitLogin() })` |
| `login_view.cj:268` 登录密码 | 同上，`onSubmit` 指向同一个 `submitLogin`（提取局部闭包：`{=> model.loginSelected(user.value.trimAscii(), pass.value) }`） |
| `login_view.cj:285/289` TOTP 码 / 恢复码 | `onSubmit: {=> model.verifyTotp(code.value.trimAscii(), recovery.value.trimAscii()) }` |
| `login_view.cj:325/327` 服务器名 / 地址 | `onSubmit: {=> model.saveServer(name.value.trimAscii(), url.value) }`（地址框同时触发"测试连接"更激进，保守只保存） |
| `detail_dialogs.cj:177/263` 新建合集 / 加入合集搜索 | `onSubmit` 调用各自的确认回调（需先看函数签名，确认框同时 `autofocus()`） |
| `add_to_tank_dialog.cj:67/124` | 同上 |
| `metadata_edit_view.cj:152/486/519/568` | 字段级保存（保存按钮回调），逐个接 |
| `settings_view.cj:788/1018`、`settings_admin_view.cj:244`、`advanced_filter_dialog.cj:76`、`detail_view.cj:592/804-808`、`upload_drawer.cj:60` | 按语义接：单字段筛选类回车 = 应用筛选；编辑类回车 = 提交当前表单 |

要点：
- 同一表单的多个字段共用一个 `submit` 闭包，避免重复逻辑；
- 提交前保持既有的空值校验（如用户名空则不发请求），不要因为回车绕过校验。

## B. 弹窗初始聚焦（缺口 #3 应用侧）——预计 8 处

给每个弹窗内**首个输入框**加 `.autofocus()`（框架 Modal 已自动聚焦首个停靠点，但显式
autofocus 更稳且表达意图）：

- `login_view.cj:325` 服务器编辑弹窗的 name 框；
- `detail_dialogs.cj:177`（新建合集）、`:263`（加入合集搜索）；
- `add_to_tank_dialog.cj:67`（筛选）、`:124`（新合集名）；
- `metadata_edit_view.cj` 的标题/描述首字段；
- `settings_admin_view.cj:692` cron 参数框；
- `advanced_filter_dialog.cj:76` 值输入框。

注意：搜索/筛选类弹窗应 `autofocus().`（键盘意图，焦点环可见），纯浏览类弹窗不必。

## C. 自绘点击件接焦点环（缺口 #2 应用侧，工作量最大）

把 `widgets.cj` 的 `ClickArea` 实现换成 `FocusTarget` 薄封装（保留原构造签名，内部改为）：

```cangjie
public class ClickArea {
    public init(onClick!: () -> Unit, body!: () -> Unit) {
        FocusTarget(onClick: onClick, body: body)   // 内部自带焦点/键盘/悬停
    }
}
```

同理迁移：`GhostIconButton`（改用 `FocusTarget` 包自绘图标，或直接用框架 `IconButton`）、
`NavItem`、`TagChip`、`MiniSeg`、封面卡 `archiveCard/tankCard/memberCard`、
`CardHoverActions` 的三个浮层钮、`pvThumb/pvRow`。

注意：
- `ClickArea` 当前用 `ZStack` 叠 `ClickSensor`，换成 `FocusTarget` 后事件顺序变化——
  逐个页面回归一次点击行为（尤其卡片内嵌套按钮的区域）。
- 卡片级 `FocusTarget` 包裹时，卡内按钮仍是独立停靠点（`focusableIds` 会同时列出两者），
  键盘顺序为「卡片 → 卡内按钮」，符合预期。

## D. 阅读器/设置页键盘化（缺口 #7/#9 应用侧）

- `reader_dock.cj` 音量/进度自绘滑条：换成框架 `Slider`（已具备 Up/Down/Home/End）或
  按其 `handle` 补同样的键；
- `settings_view.cj` 的开关/表格：确认 `RadioButton` 组使用 `.groupRange(...)`；
- 列表行 hover 底色：`drawRow` 里补 `ctx.isHovered(rowKey)` 分支（仿 `pagination.cj:117`）。

## E. 长按连发（缺口 #16 剩余部分，需 L 层改动）

审计发现：`frame` 的 `UiEvent.KeyDown(Key, Bool)` 第二参数是 **repeat** 位，但应用侧
桥接硬编码为 `false`——`client-next/src/ui/lgpu_backend.cj:676`：

```cangjie
if (ev.pressed) { UiEvent.KeyDown(keyFromCode(ev.key), false) } else { ... }
```

`lwindow.LWindowEvent` 也没有 repeat 字段。因此：

- 桌面（SDL）路径：OS 会重复发 KeyDown，长按方向键/步进器**已经**连发（只是 repeat 位未用）；
- OHOS 路径：壳层若只发单次 keydown，则长按**确实不连发**——这是 L 层（`lwindow` +
  ArkTS 输入桥）的缺口，不是控件层。

修复顺序：`LWindowEvent` 加 `repeat: Bool` → ArkTS 侧把 `KeyEvent.repeat`（或按时间阈值
自行判定）写入事件 → `lwpEventToUi` 透传 → 控件按需处理（例如 Stepper/Slider 在 repeat 时
步长 ×10 加速）。控件层无需改动即可先受益于透传。

## 验收方式

1. 合并后先在 `packages/cangjie-gui-p0` 运行 `cjpm test`（当前基线：TOTAL 423，PASSED 382，
   ERROR 40 + FAILED 1 均为环境限制）；
2. client-next 侧编译通过后，逐项手工验收：回车提交、弹窗首焦点、Tab 遍历到卡片/图标钮、
   阅读器滑条方向键；
3. 真机（OHOS）重编后复验一遍焦点环与键盘路径。
