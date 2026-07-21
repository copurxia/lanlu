package lanlu_client_next.ui

import cui.*
import lanlu_client_next.app.*

// 登录页（多服务器版，设计事实来源：仓库根 login-redesign.html）：
// 左栏服务器列表（图标方块卡片 + 增/删/改/选），右栏阴影卡片登录表单（密码 / TOTP 双态）。
// 按服务器各存会话：选中带 token 的服务器时 model.selectServer 静默恢复。
// 与原型的偏差：卡片编辑/删除按钮常驻显示（原型 hover 浮现），常驻更可发现。
public func loginView(model: AppModel): Unit {
    HStack {
        serverListPanel(model)
        loginFormPanel(model)
    }.spacing(0.0)
    // Modal 不占布局空间（measure 返回零），作为兄弟节点挂在页面根部即可。
    serverEditModal(model)
}

// ---- 主题色助手（构建期拿不到 ctx.theme，明暗二选一走 palette 常量）----

private func accentOf(model: AppModel): Color {
    if (model.isLight()) { LANLU_L_ACCENT } else { LANLU_ACCENT }
}

private func accentSoftOf(model: AppModel): Color {
    if (model.isLight()) { LANLU_L_ACCENT_SOFT } else { LANLU_ACCENT_SOFT }
}

private func panelOf(model: AppModel): Color {
    if (model.isLight()) { LANLU_L_PANEL } else { LANLU_PANEL }
}

private func raisedOf(model: AppModel): Color {
    if (model.isLight()) { LANLU_L_PANEL_RAISED } else { LANLU_PANEL_RAISED }
}

private func cardBgOf(model: AppModel): Color {
    // --bg-card：暗 #131316（=LANLU_FIELD），亮 #FFFFFF。
    if (model.isLight()) { LANLU_L_PANEL } else { LANLU_FIELD }
}

private func mutedOf(model: AppModel): Color {
    if (model.isLight()) { LANLU_L_MUTED } else { LANLU_MUTED }
}

private func probeColorOf(model: AppModel, id: String): Color {
    match (model.probeState(id).value) {
        case "online" => LANLU_SUCCESS
        case "offline" => LANLU_DANGER
        case _ => mutedOf(model)
    }
}


private func shadowOf(model: AppModel): Color {
    // 原型：暗 0 18px 50px rgba(0,0,0,.45)，亮 rgba(0,0,0,.12)——双层光晕叠加后视觉偏重，
    // 亮色再压低到 ~.08（暗色维持 .45 不变）。
    if (model.isLight()) { Color.rgba(0, 0, 0, 20) } else { Color.rgba(0, 0, 0, 115) }
}

// ---- 左栏：服务器列表 ----

func serverListPanel(model: AppModel): Unit {
    let _ = model.serversVersion.value // 订阅列表变更（增删后重绘）
    // flexible(false)：外层 HStack 的 flex 会等分宽度，不加会把 300vp 拉成 1:1（原型约 1:4）。
    // （body 以 if/else 结尾的 VStack 直接链式调用会把接收者解析成 Widget 接口——先落局部变量再链。）
    let listPanel = VStack {
        HStack {
            Label("服务器").fontSize(15.fp)
            Spacer()
            // 原型是金色软底小方块＋（30×30），cui Button 最小宽 72vp，ClickArea+Label 拼。
            ClickArea(onClick: {=> model.openServerModal("") }) {
                Label("＋").fontSize(14.fp).foregroundColor(accentOf(model))
                    .padding(9.vp, 4.vp).background(accentSoftOf(model), 8.vp)
            }
        }.hug().padding(14.vp, 12.vp)
        if (model.settings.servers.size == 0) {
            // 空列表引导（原型为虚线盒，无虚线支持，退化为描边盒 + 大图标）。
            ZStack {
                SurfaceCard(Color.rgba(0, 0, 0, 0), edgeOf(model), radius: 12.0,
                    shadow: Color.rgba(0, 0, 0, 0))
                VStack {
                    Icon(IconName.Server, size: 26.vp).foregroundColor(mutedOf(model))
                    Label("还没有服务器").fontSize(13.fp).tight()
                    Label("添加一个 Lanlu 服务器开始使用；支持保存多个服务器，随时切换")
                        .fontSize(11.fp).muted().tight()
                    Button("＋ 添加服务器", {=> model.openServerModal("") }).role(ButtonRole.Primary)
                }.spacing(10.vp).crossAxisAlignment(CrossAxisAlignment.Center).padding(24.vp, 20.vp)
            }.padding(12.vp, 0.vp)
        } else {
            ScrollView {
                VStack {
                    for (p in model.settings.servers) {
                        serverCard(model, p)
                    }
                }.spacing(8.vp).padding(12.vp, 0.vp)
            }
        }
    }
    listPanel.flexible(false).width(320.vp).background(cardBgOf(model))
}

func serverCard(model: AppModel, p: ServerProfile): Unit {
    let selected = model.selectedServerId.value == p.id
    let confirming = model.deleteConfirmId.value == p.id
    let fill = if (selected) { accentSoftOf(model) } else { panelOf(model) }
    // 原型选中态有 1px 金色描边（rgba(232,176,75,.35)），.background 画不了描边，
    // 用 SurfaceCard（阴影给全透明，只取填充+描边）。
    let edge = if (selected) {
        if (model.isLight()) { Color.rgba(199, 138, 30, 89) } else { Color.rgba(232, 176, 75, 89) }
    } else {
        Color.rgba(0, 0, 0, 0)
    }
    ClickArea(onClick: {=> model.selectServer(p.id) }) {
        ZStack {
            SurfaceCard(fill, edge, radius: 11.0, shadow: Color.rgba(0, 0, 0, 0))
            HStack {
                // 图标方块：36vp 圆角抬升底 + 服务器矢量图标（原型为 emoji 图标块）。
                // HStack 不加 crossAxis Center 时子件被纵轴拉伸，图标底会拉成竖条。
                Icon(IconName.Server, size: 16.vp)
                    .foregroundColor(if (selected) { accentOf(model) } else { mutedOf(model) })
                    .padding(10.vp).background(raisedOf(model), 10.vp)
                VStack {
                    Label(displayName(p)).fontSize(13.fp).maxLines(1).tight()
                    Label(p.baseUrl).fontSize(11.fp).foregroundColor(accentOf(model)).maxLines(1).tight()
                    Label(lastUsedLabel(p)).fontSize(10.fp).muted().maxLines(1).tight()
                }.spacing(2.vp)
                Spacer()
                // 在线状态点（probeServers 探测）：绿=在线 红=离线 灰=未知/在途。
                Label("●").fontSize(7.fp).foregroundColor(probeColorOf(model, p.id))
                cardActions(model, p, confirming)
            }.spacing(9.vp).crossAxisAlignment(CrossAxisAlignment.Center).padding(11.vp, 9.vp)
        }.alignment(Alignment.TopLeading)
    }
}

// 卡片操作区：单独函数返回 Unit——if/else 两分支分别是 Button 与 ClickArea 的 ZStack，
// 直接写在 builder 里会因分支类型不一致编译失败（cjc 把 if 当表达式求类型）。
func cardActions(model: AppModel, p: ServerProfile, confirming: Bool): Unit {
    if (confirming) {
        Button("确认删除", {=> model.requestDeleteServer(p.id) }).role(ButtonRole.Danger)
    } else {
        // 原型是无底小图标按钮（hover 才显底）：裸 Icon + ClickArea，不用 IconButton 的整块面。
        ClickArea(onClick: {=> model.openServerModal(p.id) }) {
            Icon(IconName.Pencil, size: 14.vp).padding(6.vp)
        }
        ClickArea(onClick: {=> model.requestDeleteServer(p.id) }) {
            Icon(IconName.Trash, size: 14.vp).padding(6.vp)
        }
    }
}

func displayName(p: ServerProfile): String {
    if (p.name.size > 0) { p.name } else { p.baseUrl }
}

func lastUsedLabel(p: ServerProfile): String {
    if (p.lastUsedAt.size > 0) { "上次使用 ${p.lastUsedAt}" } else { "从未使用" }
}

// ---- 右栏：登录表单（阴影卡片）----

func loginFormPanel(model: AppModel): Unit {
    let p = model.selectedProfile()
    VStack {
        ZStack {
            // 阴影参数按原型 0 18px 50px：spread 显式给宽（默认经验式最大 13，太收敛）。
            SurfaceCard(cardBgOf(model), edgeOf(model), radius: 14.0, shadow: shadowOf(model),
                spread: 24.0, offsetY: 12.0)
            VStack {
                cardHeader(model, p)
                // 登录失败内联错误条（原型 .login-error 红底红边），替代 toast。
                if (model.loginError.value.size > 0) {
                    tintBar(model.loginError.value, LANLU_DANGER,
                        Color.rgba(224, 93, 93, 26), Color.rgba(224, 93, 93, 89))
                }
                if (model.totpChallengeId.value.size > 0) {
                    totpFormPanel(model)
                } else if (let Some(prof) <- p) {
                    passwordFormPanel(model, prof)
                }
                HStack {
                    Label("还没有服务器？").fontSize(11.fp).muted().tight()
                    Label("了解自建 Lanlu 服务").fontSize(11.fp).foregroundColor(accentOf(model)).tight()
                }.spacing(4.vp).mainAxisAlignment(MainAxisAlignment.Center)
            }.spacing(16.vp).crossAxisAlignment(CrossAxisAlignment.Start).padding(32.vp, 28.vp)
        }
    }.crossAxisAlignment(CrossAxisAlignment.Center).mainAxisAlignment(MainAxisAlignment.Center)
}

// 幽灵按钮样式（原型 .btn-ghost）：透明底 + 1px 描边，融入卡片背景；
// cui Button Normal 默认带 buttonSurface 填充色，在弹窗里显得突兀。

// tinted 提示条（错误红/TOTP 金/测试绿）：SurfaceCard 填充+描边，阴影给全透明。宽度与输入框对齐。
func tintBar(text: String, fg: Color, bg: Color, border: Color): Unit {
    ZStack {
        SurfaceCard(bg, border, radius: 9.0, shadow: Color.rgba(0, 0, 0, 0))
        Label(text).fontSize(12.fp).foregroundColor(fg).tight().padding(10.vp, 8.vp)
    }.alignment(Alignment.TopLeading).width(320.vp)
}

// 主按钮的「连接中」态（原型按钮内置 spinner + 文案 + 禁用感）：
// Spinner + 文案铺在 accent 底上；在途任务由 worker 去重，天然防连点。
func busyPrimaryButton(model: AppModel, title: String, onClick: () -> Unit): Unit {
    if (model.loading.value) {
        HStack {
            Spinner(14.0, accentTextOf(model))
            Label("正在连接…").fontSize(13.fp).foregroundColor(accentTextOf(model)).tight()
        }.spacing(8.vp).mainAxisAlignment(MainAxisAlignment.Center)
         .width(320.vp).padding(0.vp, 9.vp).background(accentOf(model), 10.vp)
    } else {
        Button(title, onClick).role(ButtonRole.Primary).width(320.vp)
    }
}

private func accentTextOf(model: AppModel): Color {
    if (model.isLight()) { LANLU_L_ACCENT_TEXT } else { LANLU_ACCENT_TEXT }
}

// 卡片头部：品牌 logo（brandLogo，widgets.cj）+ 服务器名 / 金色地址。
func cardHeader(model: AppModel, p: ?ServerProfile): Unit {
    HStack {
        brandLogo(model, 44.vp)
        match (p) {
            case Some(prof) =>
                VStack {
                    Label(displayName(prof)).fontSize(16.fp).maxLines(1).tight()
                    Label(prof.baseUrl).fontSize(12.fp).foregroundColor(accentOf(model)).maxLines(1).tight()
                }.spacing(2.vp)
            case None =>
                VStack {
                    Label("Lanlu").fontSize(16.fp).tight()
                    Label("先在左侧添加一个服务器").fontSize(12.fp).muted().tight()
                }.spacing(2.vp)
        }
    }.spacing(12.vp)
}

func passwordFormPanel(model: AppModel, p: ServerProfile): Unit {
    // key 带服务器 id：切换服务器时重建字段，带出该服务器上次账号。
    let user = rememberState<String>("login.user.${p.id}", {=> p.username })
    let pass = rememberState<String>("login.pass.${p.id}", {=> "" })
    let showPass = rememberState<Bool>("login.pass.show.${p.id}", {=> false })
    // 原型节奏：label 紧贴自己的输入框（6px），组与组之间 16px，按钮上沿再留 6px。
    VStack {
        Label("用户名").fontSize(12.fp).muted().tight()
        TextField(user, key: "login-user-${p.id}", leadingIcon: IconName.User).width(320.vp)
    }.spacing(6.vp)
    VStack {
        Label("密码").fontSize(12.fp).muted().tight()
        // 显示/隐藏切换：trailing 眼睛图标，点击翻转明文态（masked 是构造参，State 翻转触发重建，
        // 同 key 的 rememberState 保留已输入内容）。
        TextField(pass, key: "login-pass-${p.id}", masked: !showPass.value, leadingIcon: IconName.Lock,
            trailingIcon: Some(if (showPass.value) { IconName.EyeOff } else { IconName.Eye }),
            onTrailingClick: {=> showPass.value = !showPass.value }).width(320.vp)
    }.spacing(6.vp)
    VStack {
        busyPrimaryButton(model, "登 录", {=> model.loginSelected(user.value.trimAscii(), pass.value) })
    }.padding(0.vp, 6.vp, 0.vp, 0.vp)
}

func totpFormPanel(model: AppModel): Unit {
    let code = rememberState<String>("login.totp", {=> "" })
    let recovery = rememberState<String>("login.recovery", {=> "" })
    // TOTP 提示条（原型 .totp-hint 金底金边）。
    tintBar("该账号已开启两步验证，请输入身份验证器中的验证码", accentOf(model), accentSoftOf(model),
        if (model.isLight()) { Color.rgba(199, 138, 30, 76) } else { Color.rgba(232, 176, 75, 76) })
    VStack {
        Label("验证码").fontSize(12.fp).muted().tight()
        TextField(code, key: "login-totp", leadingIcon: IconName.Lock).width(320.vp)
    }.spacing(6.vp)
    VStack {
        Label("恢复码（可选，二选一）").fontSize(12.fp).muted().tight()
        TextField(recovery, key: "login-recovery", leadingIcon: IconName.Pencil).width(320.vp)
    }.spacing(6.vp)
    VStack {
        busyPrimaryButton(model, "验 证", {=> model.verifyTotp(code.value.trimAscii(), recovery.value.trimAscii()) })
    }.padding(0.vp, 6.vp, 0.vp, 0.vp)
    ClickArea(onClick: {=> model.dismissTotp() }) {
        Label("← 返回密码登录").fontSize(12.fp).foregroundColor(accentOf(model))
    }
}

// ---- 添加/编辑服务器弹窗 ----

func serverEditModal(model: AppModel): Unit {
    let eid = model.editingServerId
    let editing: ?ServerProfile = if (eid.size > 0) { model.settings.profileById(eid) } else { None }
    // rememberState key 带编辑目标 id：新增/编辑不同服务器时字段初值各自独立。
    let name = rememberState<String>("srv.name.${eid}", {=>
        match (editing) {
            case Some(p) => p.name
            case None => ""
        }
    })
    let url = rememberState<String>("srv.url.${eid}", {=>
        match (editing) {
            case Some(p) => p.baseUrl
            case None => ""
        }
    })
    Modal(model.serverModalOpen, blurBackdrop: true, body: {=>
        VStack {
            Label(if (eid.size > 0) { "编辑服务器" } else { "添加服务器" }).fontSize(15.fp)
            Label("名称（可选，留空用地址代替）").fontSize(12.fp).muted()
            TextField(name, key: "srv-name", leadingIcon: IconName.Pencil).width(320.vp)
            Label("服务器地址").fontSize(12.fp).muted()
            TextField(url, key: "srv-url", leadingIcon: IconName.Server).width(320.vp)
            HStack {
                Button("测试连接", {=> model.testConnection(url.value) }).style(ghostStyleOf(model))
                Spacer()
                Button("取消", {=> model.serverModalOpen.value = false }).style(ghostStyleOf(model))
                Button("保 存", {=> model.saveServer(name.value.trimAscii(), url.value) })
                    .role(ButtonRole.Primary)
            }.spacing(8.vp)
            testResultLabel(model)
        }.spacing(10.vp).hug()
    })
}

func testResultLabel(model: AppModel): Unit {
    let r = model.testConnResult.value
    if (r == "testing") {
        Label("正在测试…").fontSize(12.fp).muted().tight()
    } else if (r == "ok") {
        tintBar("✓ 连接成功", LANLU_SUCCESS, Color.rgba(76, 175, 125, 26), Color.rgba(76, 175, 125, 89))
    } else if (r.size > 0) {
        tintBar("✕ ${r}", LANLU_DANGER, Color.rgba(224, 93, 93, 26), Color.rgba(224, 93, 93, 89))
    }
}
