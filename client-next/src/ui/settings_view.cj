package lanlu_client_next.ui

import cui.*
import lanlu_client_next.app.*
import lanlu_client_next.net.{SearchItem, TrendPoint, PasskeyItem, SessionItem, TokenItem}
import std.collection.ArrayList

// 设置页（原型 settings-redesign.html）：左 224vp 分类导航 + 右侧内容页。
// 板块索引：0 概览 / 1 账户安全 / 2 外观 / 3 语言 / 4 缓存 / 5 诊断 / 6 分类 /
// 7 标签 / 8 智能分类 / 9 用户 / 10 系统 / 11 任务记录 / 12 定时任务 / 13 插件 /
// 14 统计 / 15 关于；6-14 为管理员区（导航按 isAdmin 门控）。
// 应用字体无 emoji 字形，导航/设置行图标用手绘矢量 GhostGlyph（GlyphIcon）替代原型 emoji。

// 侧栏宽（原型 #set-nav 224px，与书库侧栏同规格）。
private let SET_NAV_W: Float32 = 224.0
// 内容列定宽（原型 .set-page{max-width:640px}）：卡片跨轴拉伸通栏，不随内容收缩。
private let SET_CONTENT_W: Float32 = 640.0

public func settingsView(model: AppModel): Unit {
    // 进场加载一次：rememberState 随页面卸载清除（StateStore 未访问条目即删），
    // 故每次进入设置页都会重新拉取；不能用 serverInfo.isNone() 当触发条件——
    // info 失败时 toast 引发重建会反复重投，形成错误循环。
    let loaded = rememberState<Bool>("settings.loaded", {=> false})
    if (!loaded.value) {
        loaded.value = true
        model.loadServerInfo()
        model.refreshCacheInfo()
    }
    // 当前板块索引（见文件头索引约定），页面级状态随卸载重置。
    let section = rememberState<Int64>("settings.section", {=> 0})
    // 退出登录确认弹窗开关。
    let logoutOpen = rememberState<Bool>("settings.logoutOpen", {=> false})
    // 非管理员落在管理员板块时退回概览（隐藏分组后旧索引仍可能残留）。
    if (!model.isAdmin.value && section.value >= 6 && section.value <= 14) {
        section.value = 0
    }
    // 根 HStack 默认 8vp 间距会在导航/边线/内容区之间留死区，必须清零（同书库）。
    HStack {
        settingsNav(model, section)
        Divider(axis: Axis.Vertical)
        ScrollView(key: "settings-main") {
            let content = VStack {
                match (section.value) {
                    case 0 => overviewPage(model, logoutOpen)
                    case 1 => authPage(model)
                    case 2 => appearancePage(model)
                    case 4 => cachePage(model)
                    case 6 => categoriesPage(model)
                    case 7 => tagsPage(model)
                    case 8 => filtersPage(model)
                    case 9 => usersPage(model)
                    case 10 => systemPage(model)
                    case 11 => tasksPage(model)
                    case 12 => cronPage(model)
                    case 13 => pluginsPage(model)
                    case 14 => statsPage(model)
                    case 15 => aboutPage(model)
                    // 3 语言 / 5 诊断：客户端暂无对应能力，占位页。
                    case _ => placeholderPage(model, sectionName(section.value))
                }
            }.spacing(16.vp).crossAxisAlignment(CrossAxisAlignment.Start)
            let contentMaxW: Float32 = if (isWideSection(section.value)) { 100000.0 } else { SET_CONTENT_W }
            content.fillWidth().maxWidth(contentMaxW).padding(22.vp, 26.vp, 22.vp, 48.vp)
        }
    }.spacing(0.0)
    // Modal 不占布局空间（measure 返回零），作为兄弟节点挂在页面根部（同 login_view）。
    logoutConfirmModal(model, logoutOpen)
}

private func sectionName(i: Int64): String {
    match (i) {
        case 3 => "语言"
        case 5 => "诊断"
        case _ => ""
    }
}

// ---- 左侧分类导航（原型 #set-nav：与书库侧栏同语言，仅右边线分隔）----

// 左侧分类导航（原型 #set-nav：个人区 / 客户端 / 服务器(管理员) / 其他）。
private func settingsNav(model: AppModel, section: State<Int64>): Unit {
    let bg = if (model.isLight()) {
        LANLU_L_BG
    } else {
        LANLU_BG
    }
    // 导航必须定宽非弹性：ScrollView.isFlexible 恒 true 且 .width() 修饰不改变弹性，
    // 直接挂进根 HStack 会与内容 ScrollView 按权重平分窗口宽（导航一侧 224 内容贴右）。
    VStack {
        ScrollView(key: "settings-nav") {
            VStack {
                Label("设置").fontSize(15.fp).padding(16.vp, 12.vp, 16.vp, 10.vp)
                // 导航前置图标对齐原型 #set-nav .side-item .ico（书库侧栏无图标，仅设置导航有）。
                VStack {
                    NavItem("概览", active: section.value == 0, glyph: GhostGlyph.Named(IconName.User)) {
                        => section.value = 0
                    }
                    NavItem("账户安全", active: section.value == 1, glyph: GhostGlyph.Named(IconName.Lock)) {
                        => section.value = 1
                    }
                    navHeader("客户端")
                    NavItem("外观", active: section.value == 2, glyph: GhostGlyph.Theme) {=> section.value = 2}
                    NavItem("语言", active: section.value == 3, glyph: GhostGlyph.Globe) {=> section.value = 3}
                    NavItem("缓存", active: section.value == 4, glyph: GhostGlyph.Disk) {=> section.value = 4}
                    NavItem("诊断", active: section.value == 5, glyph: GhostGlyph.Named(IconName.NewDocument)) {
                        => section.value = 5
                    }
                    if (model.isAdmin.value) {
                        navHeader("服务器")
                        NavItem("分类管理", active: section.value == 6, glyph: GhostGlyph.Named(IconName.OpenFolder)) {
                            => section.value = 6
                        }
                        NavItem("标签管理", active: section.value == 7, glyph: GhostGlyph.Tag) {
                            => section.value = 7
                        }
                        NavItem("智能分类", active: section.value == 8, glyph: GhostGlyph.Sparkle) {
                            => section.value = 8
                        }
                        navHeader("系统管理")
                        NavItem("用户管理", active: section.value == 9, glyph: GhostGlyph.Named(IconName.User)) {
                            => section.value = 9
                        }
                        NavItem("系统设置", active: section.value == 10, glyph: GhostGlyph.Monitor) {
                            => section.value = 10
                        }
                        NavItem("任务记录", active: section.value == 11, glyph: GhostGlyph.Menu) {
                            => section.value = 11
                        }
                        NavItem("定时任务", active: section.value == 12, glyph: GhostGlyph.Named(IconName.Clock)) {
                            => section.value = 12
                        }
                        NavItem("插件管理", active: section.value == 13, glyph: GhostGlyph.Box) {
                            => section.value = 13
                        }
                        NavItem("统计信息", active: section.value == 14, glyph: GhostGlyph.Chart) {
                            => section.value = 14
                        }
                    }
                    navHeader("其他")
                    NavItem("关于", active: section.value == 15, glyph: GhostGlyph.Info) {=> section.value = 15}
                }.spacing(2.vp).crossAxisAlignment(CrossAxisAlignment.Start).hug().padding(10.vp, 0.vp)
                Divider()
                // 返回入口在顶栏返回钮（同详情页），菜单内不再放「返回书库」。
                Label("v0.1.0 · CangjieGUI").fontSize(11.fp).muted().padding(14.vp, 0.vp, 14.vp, 10.vp)
            }.hug()
        }
    }.flexible(false).width(SET_NAV_W).background(bg)
}

// 分组小标题（原型 .side-sec）。
func navHeader(text: String): Unit {
    Label(text).fontSize(11.fp).muted().padding(12.vp, 10.vp, 12.vp, 4.vp)
}

// ---- 页面公共件 ----

// 页头（原型 .set-page h1 + .page-sub）。
func pageHeader(title: String, sub: String): Unit {
    VStack {
        Label(title).fontSize(18.fp)
        if (sub.size > 0) {
            Label(sub).fontSize(12.fp).muted()
        }
    }.spacing(4.vp).crossAxisAlignment(CrossAxisAlignment.Start).hug()
}

// 设置行（原型 .s-row 去图标盒）：标题/描述 + 右侧控件（开关/分段/箭头）。
func settingRow(model: AppModel, label: String, desc: String, trailing: () -> Unit): Unit {
    settingRowBody(model, label, desc, Option<GhostGlyph>.None, trailing)
}

// 带图标盒设置行（原型 .s-row .row-ico：30vp 圆角盒 + 14vp 矢量图形，替代原型 emoji）。
// 单独函数而非可选参数：仓颉尾随 lambda 糖要求末参为函数类型，可选 icon 放末尾会破坏全部旧调用点。
func settingRowIcon(model: AppModel, label: String, desc: String, icon: GhostGlyph, trailing: () -> Unit): Unit {
    settingRowBody(model, label, desc, Some(icon), trailing)
}

private func settingRowBody(model: AppModel, label: String, desc: String, icon: ?GhostGlyph, trailing: () -> Unit): Unit {
    HStack {
        match (icon) {
            case Some(g) =>
                let raised = if (model.isLight()) {
                    LANLU_L_PANEL_RAISED
                } else {
                    LANLU_PANEL_RAISED
                }
                let muted = if (model.isLight()) {
                    LANLU_L_MUTED
                } else {
                    LANLU_MUTED
                }
                VStack {
                    GlyphIcon(g, size: 14.0, color: muted)
                }
                    .mainAxisAlignment(MainAxisAlignment.Center)
                    .crossAxisAlignment(CrossAxisAlignment.Center)
                    .flexible(false)
                    .width(30.vp)
                    .height(30.vp)
                    .background(raised, 8.vp)
            case None => ()
        }
        VStack {
            Label(label).fontSize(13.fp)
            if (desc.size > 0) {
                Label(desc).fontSize(11.fp).muted().maxLines(1)
            }
        }.spacing(2.vp).crossAxisAlignment(CrossAxisAlignment.Start).flex()
        trailing()
    }.spacing(12.vp).crossAxisAlignment(CrossAxisAlignment.Center).hug().padding(0.vp, 4.vp)
}

// 占位页（语言/诊断：客户端无对应能力，导航保留入口）。
func placeholderPage(model: AppModel, name: String): Unit {
    pageHeader(name, "")
    VStack {
        Label("${name}设置暂未实现").fontSize(14.fp)
        Label("将在后续版本提供").fontSize(12.fp).muted()
    }
        .spacing(8.vp)
        .mainAxisAlignment(MainAxisAlignment.Center)
        .crossAxisAlignment(CrossAxisAlignment.Center)
        .fillWidth()
        .height(240.vp)
}

// ---- 各内容页 ----

private func overviewPage(model: AppModel, logoutOpen: State<Bool>): Unit {
    // 进场加载 dashboard 数据（rememberState 随页面卸载清除，每次进入重拉）。
    let loaded = rememberState<Bool>("overview.loaded", {=> false})
    if (!loaded.value) {
        loaded.value = true
        model.loadOverviewExtras()
    }
    pageHeader("概览", "当前账号、服务器连接与阅读统计")

    // ---- 账号卡（原型 .acct-card，沿用旧实现） ----
    detailCard(model, "账号") {
        HStack {
            // 头像为正圆（半径=边长一半），与顶栏用户芯片一致。
            VStack {
                Label(avatarHead(model.settings.username)).fontSize(20.fp).foregroundColor(Color.rgb(255, 255, 255))
            }
                .mainAxisAlignment(MainAxisAlignment.Center)
                .crossAxisAlignment(CrossAxisAlignment.Center)
                .flexible(false)
                .width(48.vp)
                .height(48.vp)
                .background(Color.rgb(0x3B, 0x55, 0x7D), 24.vp)
            VStack {
                Label(model.settings.username).fontSize(15.fp)
                Label(model.settings.serverUrl).fontSize(11.fp).muted().maxLines(1)
            }.spacing(2.vp).crossAxisAlignment(CrossAxisAlignment.Start).flex()
            Button("切换服务器", {=> model.page.value = Page.Login})
            Button("退出登录", {=> logoutOpen.value = true}).role(ButtonRole.Danger)
        }.spacing(12.vp).crossAxisAlignment(CrossAxisAlignment.Center).hug()
    }

    // ---- 统计卡片（原型 .stat-grid：4 等宽） ----
    match (model.userStats.value) {
        case Some(s) => HStack {
            statCard(model, GhostGlyph.Heart, "${s.favoriteCount}", "收藏数量")
            statCard(model, GhostGlyph.Book, "${s.readCount}", "已读档案")
            statCard(model, GhostGlyph.Pages, "${s.totalPagesRead}", "总阅读页数")
            statCard(model, GhostGlyph.Disk, "${s.totalArchives}", "档案总数")
        }.spacing(12.vp).flexible(false).fillWidth() // 卡内数字列是 flex 子项，hug 会压窄截断（T20 目检发现）；fillWidth 撑满内容列。

        // flexible(false) 关键：HStack 默认弹性，fillWidth 不改变弹性，若保持弹性会被页列
        // 的 flex 分配按「剩余/权重」均分高度（与其他弹性行互相削平/裁切，真机实测卡片底行被切）。
        case None => pageLoading(model, "统计数据加载中…")
    }

    // ---- 阅读趋势（原型 ReadingTrendChart：30 天柱状图，纯布局实现） ----
    detailCard(model, "阅读趋势") {
        trendBars(model, model.userTrend.value)
    }

    // ---- 最近活动（原型 RecentActivity：左右两卡 1:1；fillWidth 卡片须包 flex 单元格才能均分） ----
    HStack {
        VStack {
            detailCard(model, "最近阅读") {
                recentList(model, model.recentRead.value, "暂无阅读记录")
            }
        }.flex()
        VStack {
            detailCard(model, "最近收藏") {
                recentList(model, model.recentFav.value, "暂无收藏记录")
            }
        }.flex()
    }.spacing(14.vp).crossAxisAlignment(CrossAxisAlignment.Start).flexible(false).fillWidth()

    // ---- 服务器信息卡（沿用旧实现） ----
    detailCard(model, "服务器") {
        match (model.serverInfo.value) {
            case Some(info) => infoList(
                model,
                [
                    ("状态", "已连接"),
                    ("名称", info.name),
                    ("版本", "${info.versionName} ${info.version}"),
                    ("档案数", "${info.totalArchives} 个档案"),
                    ("地址", model.settings.serverUrl)
                ]
            )
            case None => Label("服务器信息加载中…").fontSize(12.fp).muted()
        }
    }
}

// 统计卡（原型 .stat-card）：矢量图标 + 大数字 + 小标题。
private func statCard(model: AppModel, ico: GhostGlyph, num: String, label: String): Unit {
    let cardBg = if (model.isLight()) {
        LANLU_L_PANEL
    } else {
        LANLU_FIELD
    }
    let panel = if (model.isLight()) {
        LANLU_L_PANEL_RAISED
    } else {
        LANLU_PANEL_RAISED
    }
    let accent = if (model.isLight()) {
        LANLU_L_ACCENT
    } else {
        LANLU_ACCENT
    }
    HStack {
        VStack {
            GlyphIcon(ico, size: 15.0, color: accent)
            // flexible(false) 关键：图标盒默认弹性，在卡内会与文本列按权重瓜分宽度，
            // 背景按分配到的宽帧绘制（真机实测图标盒被拉成宽条）。
        }
            .mainAxisAlignment(MainAxisAlignment.Center)
            .crossAxisAlignment(CrossAxisAlignment.Center)
            .flexible(false)
            .width(34.vp)
            .height(34.vp)
            .background(panel, 9.vp)
        VStack {
            Label(num).fontSize(18.fp)
            Label(label).fontSize(10.fp).muted()
        }.spacing(2.vp).crossAxisAlignment(CrossAxisAlignment.Start)
    // 卡片底色（原型 .stat-card 有 --bg-card 白卡）：缺背景时内容像浮在页面上。
    }.spacing(10.vp).crossAxisAlignment(CrossAxisAlignment.Center).flex().padding(12.vp, 14.vp).background(cardBg, 14.vp)
}

// 趋势柱状图（原型折线图简化为柱图：框架无折线绘制件，柱图用纯布局可达）。
private func trendBars(model: AppModel, data: ArrayList<TrendPoint>): Unit {
    if (data.size == 0) {
        Label("暂无趋势数据").fontSize(12.fp).muted()
        return
    }
    var maxV = 1
    for (p in data) {
        if (p.count > maxV) {
            maxV = p.count
        }
    }
    var total = 0
    for (p in data) {
        total += p.count
    }
    // 不可变副本：可变变量无法被 HStack 构建 lambda 捕获。
    let maxBar = maxV
    let accent = if (model.isLight()) {
        LANLU_L_ACCENT
    } else {
        LANLU_ACCENT
    }
    Label("最近 30 天 · 总阅读: ${total}").fontSize(11.fp).muted()
    HStack {
        ForEachIndexed(data.toArray()) {
            _, p =>
                // 柱高 4..96vp，保底 4vp 让 0 值可见（.vp 后缀仅 Int64/Float64 有，故用 Float64）。
                let h = 4.0 + 92.0 * Float64(p.count) / Float64(maxBar)
                VStack {}.width(0.vp).height(h.vp).flex().background(if (p.count > 0) {
                    accent
                } else {
                    Color.rgba(128, 128, 128, 40)
                }, 2.vp)
        }
    // 容器必须显式占宽：柱条是 width(0)+flex 的弹性子项，hug/自适应都会把整排
    // 收成 0 宽不可见（T20 目检发现）；fillWidth 撑满卡片内容区。
    }.spacing(2.vp).crossAxisAlignment(CrossAxisAlignment.End).fillWidth().height(100.vp)
}

// 最近活动列表（原型 .s-row：封面 + 标题 + 页数进度）。
// 异步列表必须 ForEach(key) 而非裸 for：无 key 的子节点在数据到达后的重建中
// 会按位置错位，出现行跑出卡片、按钮错位的假象（真机实测确认）。
private func recentList(model: AppModel, items: ArrayList<SearchItem>, emptyText: String): Unit {
    if (items.size == 0) {
        Label(emptyText).fontSize(12.fp).muted()
        return
    }
    ForEach(items.toArray(), key: {it: SearchItem => it.arcid}) {
        it => HStack {
            if (it.coverAssetId > 0) {
                remoteImage(model, "asset:${it.coverAssetId}", "/api/assets/${it.coverAssetId}", 36.vp, 48.vp)
            } else {
                VStack {
                    Label("无\n封面").fontSize(9.fp).muted()
                }
                    .mainAxisAlignment(MainAxisAlignment.Center)
                    .crossAxisAlignment(CrossAxisAlignment.Center)
                    .width(36.vp)
                    .height(48.vp)
                    .background(if (model.isLight()) {
                        LANLU_L_PANEL_RAISED
                    } else {
                        LANLU_PANEL_RAISED
                    }, 6.vp)
            }
            VStack {
                Label(it.title).fontSize(12.fp).maxLines(1)
                Label("${it.pagecount} 页 · 已读 ${it.progress} 页").fontSize(10.fp).muted()
            }.spacing(3.vp).crossAxisAlignment(CrossAxisAlignment.Start).flex()
        }.spacing(10.vp).crossAxisAlignment(CrossAxisAlignment.Center).hug()
    }
}

// 取字符串首字符（UTF-8 安全）：按首字节判断字符长度 1-4 字节，
// 避免多字节字符（中文等）被按字节截断成非法 UTF-8 序列（真机崩溃实证）。
func firstChar(s: String): String {
    if (s.size == 0) {
        return "?"
    }
    let b = s[0]
    let len = if (b < 0x80) {
        1
    } else if ((b & 0xE0) == 0xC0) {
        2
    } else if ((b & 0xF0) == 0xE0) {
        3
    } else {
        4
    }
    return s[0..min(len, s.size)]
}

// 头像首字符（空串回落 ?）。
private func avatarHead(username: String): String {
    firstChar(username)
}

private func appearancePage(model: AppModel): Unit {
    pageHeader("外观", "界面主题，切换后立即生效并持久化")
    detailCard(model, "主题") {
        settingRowIcon(model, "主题", "暗色为默认；切换经 setTheme 落盘并即时应用", GhostGlyph.Theme) {
            // 分段初值取自持久化设置；set 里写回 model.setTheme（落盘 + 回调应用主题）。
            SegmentedControl(
                ["暗色", "亮色"],
                rememberState<Int64>("settings.themeIdx", {=> themeToIndex(model.settings.theme)}).project(
                    get: {v => v},
                    set: {
                        _, v =>
                            model.setTheme(indexToTheme(v))
                            return v
                    }
                )
            )
        }
    }
}

private func cachePage(model: AppModel): Unit {
    pageHeader("缓存", "封面与页面图片的本地缓存，按服务器隔离存放")
    detailCard(model, "图片缓存") {
        Label(model.cacheInfo.value).fontSize(12.fp).muted()
        HStack {
            // 清理成功由 model.clearCache 内部 toast（磁盘 + 两级纹理缓存一并复位）。
            Button("清理图片缓存", {=> model.clearCache()}).role(ButtonRole.Danger)
            Label("仅清除当前服务器的缓存").fontSize(11.fp).muted()
        }.spacing(10.vp).crossAxisAlignment(CrossAxisAlignment.Center).hug()
    }
}

private func aboutPage(model: AppModel): Unit {
    pageHeader("关于", "版本信息与项目链接")
    detailCard(model, "Lanlu 桌面客户端") {
        Label("v0.1.0 · CangjieGUI").fontSize(12.fp).muted()
        // 链接类入口暂无对应能力，点击走统一「暂未实现」toast（同书库惯例）。
        ClickArea(onClick: {=> model.todoToast("项目主页")}) {
            settingRowIcon(model, "项目主页", "", GhostGlyph.Home) {
                Label("›").fontSize(13.fp).muted()
            }
        }
        ClickArea(onClick: {=> model.todoToast("开源许可")}) {
            settingRowIcon(model, "开源许可", "", GhostGlyph.Pages) {
                Label("›").fontSize(13.fp).muted()
            }
        }
        ClickArea(onClick: {=> model.todoToast("检查更新")}) {
            settingRowIcon(model, "检查更新", "当前已是最新版本", GhostGlyph.Named(IconName.Refresh)) {
                Label("›").fontSize(13.fp).muted()
            }
        }
    }
}

// ---- 退出登录确认（原型 #confirm-mask）----

private func logoutConfirmModal(model: AppModel, logoutOpen: State<Bool>): Unit {
    Modal(logoutOpen, body: {
        => VStack {
            Label("退出登录？").fontSize(15.fp)
            Label("将清除该服务器在本机保存的会话，服务器与缓存目录会保留。").fontSize(12.fp).muted()
            HStack {
                Spacer()
                Button("取消", {=> logoutOpen.value = false})
                Button(
                    "退出登录",
                    {
                        =>
                            logoutOpen.value = false
                            model.logout()
                    }
                ).role(ButtonRole.Danger)
            }.spacing(8.vp)
        }.spacing(12.vp).crossAxisAlignment(CrossAxisAlignment.Start).width(320.vp)
    })
}

// ==================== 设置区共享件（原型徽章/表单/确认框） ====================

// 宽板块判定（原型 .set-page.wide）。
func isWideSection(s: Int64): Bool {
    match (s) {
        case 0 | 1 | 6 | 7 | 9 | 11 | 12 | 13 | 14 => true
        case _ => false
    }
}

public enum PillTone {
    Accent | Blue | Green | Red | Orange | Gray | Outline
}

// 徽章（原型 .badge）：10fp 圆角色块文字；透明底色的rgba与原型 CSS 一致。
func pill(model: AppModel, text: String, tone: PillTone): Unit {
    let (bg, fg) = pillColors(model, tone)
    Label(text).fontSize(10.fp).foregroundColor(fg).padding(8.vp, 1.vp).background(bg, 999.vp)
}

private func pillColors(model: AppModel, tone: PillTone): (Color, Color) {
    let accent = if (model.isLight()) {
        LANLU_L_ACCENT
    } else {
        LANLU_ACCENT
    }
    let accentSoft = if (model.isLight()) {
        LANLU_L_ACCENT_SOFT
    } else {
        LANLU_ACCENT_SOFT
    }
    let muted = if (model.isLight()) {
        LANLU_L_MUTED
    } else {
        LANLU_MUTED
    }
    match (tone) {
        case PillTone.Accent => (accentSoft, accent)
        case PillTone.Blue => (Color.rgba(80, 140, 220, 40), Color.rgb(0x6E, 0xA8, 0xE8))
        case PillTone.Green => (Color.rgba(76, 175, 125, 40), Color.rgb(0x4C, 0xAF, 0x7D))
        case PillTone.Red => (Color.rgba(224, 93, 93, 40), Color.rgb(0xE0, 0x5D, 0x5D))
        case PillTone.Orange => (Color.rgba(224, 152, 60, 40), Color.rgb(0xE0, 0x98, 0x3C))
        case PillTone.Gray => (Color.rgba(128, 128, 128, 36), muted)
        case PillTone.Outline => (Color.rgba(0, 0, 0, 0), muted)
    }
}

// 表单字段（原型 .form-item）：标签 + 输入框。
// cui TextField 无 placeholder 具名参数：ZStack 上叠一层不消费事件的 muted Label 实现
// （Label.handle 返回 false，点击穿透到 TextField；文本与框内同位：左 8vp、38vp 高内垂直居中）。
func formField(label: String, text: State<String>, placeholder: String, masked!: Bool = false): Unit {
    VStack {
        Label(label).fontSize(11.fp).muted()
        ZStack {
            TextField(text, masked: masked)
            if (text.value.size == 0 && placeholder.size > 0) {
                Label(placeholder).fontSize(13.fp).muted().padding(8.vp, 10.vp, 0.vp, 0.vp)
            }
        }.alignment(Alignment.TopLeading)
    }.spacing(5.vp).crossAxisAlignment(CrossAxisAlignment.Start).hug()
}

// 通用确认弹窗（原型 #confirm-mask）：destructive 动作二次确认。
func confirmModal(open: State<Bool>, title: String, desc: String, confirmText: String, onConfirm: () -> Unit): Unit {
    Modal(open, body: {
        => VStack {
            Label(title).fontSize(15.fp)
            Label(desc).fontSize(12.fp).muted()
            HStack {
                Spacer()
                Button("取消", {=> open.value = false})
                Button(
                    confirmText,
                    {
                        =>
                            open.value = false
                            onConfirm()
                    }
                ).role(ButtonRole.Danger)
            }.spacing(8.vp)
        }.spacing(12.vp).crossAxisAlignment(CrossAxisAlignment.Start).width(340.vp)
    })
}

// 列表加载占位（数据未到时的一行提示）。
func pageLoading(model: AppModel, text: String): Unit {
    VStack {
        Label(text).fontSize(12.fp).muted()
    }
        .mainAxisAlignment(MainAxisAlignment.Center)
        .crossAxisAlignment(CrossAxisAlignment.Center)
        .fillWidth()
        .height(120.vp)
}

// Bool 初值 + 提交回调的开关绑定件（绑定语义同外观页主题分段）。
// 注意：rememberState key 必须按调用点唯一化（由调用方拼 id，见下方注释），
// 简单起见本实现每次重建生成独立 key——列表行场景用 `switchBindKeyed`。
func switchBindKeyed(key: String, v0: Bool, onSet: (Bool) -> Unit): Bindable<Bool> {
    rememberState<Bool>("swbind.${key}", {=> v0}).project(
        get: {v => v},
        set: {
            _, v =>
            onSet(v);
            return v
        }
    )
}

// ---- 账户安全（原型 settings-redesign.html 账户区：当前用户/凭据/TOTP/Passkey/会话/API Token） ----
// TOTP 注册（扫码绑定）与 Passkey 注册依赖二维码展示/平台 WebAuthn，桌面端首版不实现，
// 客户端只做状态展示与关闭/删除（YAGNI，TOTP 未启用态显示提示文案）。
private func authPage(model: AppModel): Unit {
    // 进场加载一次（rememberState 随页面卸载清除，每次进入重拉，同概览页）。
    let loaded = rememberState<Bool>("auth.loaded", {=> false})
    if (!loaded.value) {
        loaded.value = true
        model.loadAuthSecurity()
    }
    pageHeader("账户安全", "管理您的账户信息、密码和登录设备")

    // ---- 当前用户卡（原型 acct-card：头像 + 徽章 + 操作） ----
    detailCard(model, "当前用户") {
        HStack {
            VStack {
                Label(avatarHead(model.settings.username)).fontSize(20.fp).foregroundColor(Color.rgb(255, 255, 255))
            }
                .mainAxisAlignment(MainAxisAlignment.Center)
                .crossAxisAlignment(CrossAxisAlignment.Center)
                .flexible(false)
                .width(48.vp)
                .height(48.vp)
                .background(Color.rgb(0x3B, 0x55, 0x7D), 24.vp)
            VStack {
                HStack {
                    Label(model.settings.username).fontSize(15.fp)
                    if (model.isAdmin.value) {
                        pill(model, "管理员", PillTone.Accent)
                    }
                }.spacing(8.vp).crossAxisAlignment(CrossAxisAlignment.Center)
                Label(model.settings.serverUrl).fontSize(11.fp).muted().maxLines(1)
            }.spacing(2.vp).crossAxisAlignment(CrossAxisAlignment.Start).flex()
        }.spacing(12.vp).crossAxisAlignment(CrossAxisAlignment.Center).hug()
    }

    // ---- 修改凭据（原型卡片 1） ----
    let credName = rememberState<String>("auth.credName", {=> model.settings.username})
    let credPw = rememberState<String>("auth.credPw", {=> ""})
    detailCard(model, "修改凭据") {
        formField("用户名", credName, model.settings.username)
        formField("新密码", credPw, "请输入新密码（至少6位）", masked: true)
        HStack {
            Button(
                "保存",
                {
                    =>
                        // 用户名与密码均为空时不提交，避免空操作 toast。
                        if (credName.value.trimAscii().size == 0 && credPw.value.size == 0) {
                            return
                        }
                        if (credPw.value.size == 0 || credPw.value.size >= 6) {
                            model.actChangeCredentials(credName.value.trimAscii(), credPw.value)
                            credPw.value = ""
                        }
                }
            ).role(ButtonRole.Primary)
        }.hug().padding(0.vp, 12.vp, 0.vp, 0.vp)
    }

    // ---- 双重验证（原型卡片 2：状态行 + 恢复码 + 关闭） ----
    let totpOffOpen = rememberState<Bool>("auth.totpOffOpen", {=> false})
    detailCard(model, "双重验证") {
        match (model.totpStatus.value) {
            case Some(tp) =>
                if (tp.enabled) {
                    settingRow(model, "双重验证已启用",
                        "${tp.credentialName} · 创建于 ${tp.createdAt} · 未使用恢复码数量: ${tp.recoveryCodesRemaining}") {
                        Button("刷新", {=> model.loadAuthSecurity()})
                    }
                    settingRow(model, "恢复码", "重新生成后，旧恢复码将全部失效") {
                        Button("重新生成恢复码", {=> model.actTotpRegenerate()})
                    }
                    settingRow(model, "关闭双重验证", "") {
                        Button("关闭双重验证", {=> totpOffOpen.value = true}).role(ButtonRole.Danger)
                    }
                } else {
                    settingRow(model, "双重验证未启用", "TOTP 绑定需扫码，请在 Web 前端或移动端的账户安全页完成设置") {
                        Label("").fontSize(12.fp).muted()
                    }
                }
            case None => pageLoading(model, "加载中…")
        }
    }
    confirmModal(totpOffOpen, "关闭双重验证？", "关闭后账号将仅受密码保护，安全性会降低。", "关闭", {
        => model.actTotpDisable()
    })

    // ---- Passkey（原型卡片 3：列表 + 删除；注册走平台 WebAuthn，桌面端占位） ----
    detailCard(model, "Passkey 管理") {
        let list = model.passkeys.value
        if (list.size == 0) {
            Label("暂无 Passkey").fontSize(12.fp).muted()
        }
        ForEach(list.toArray(), key: {pk: PasskeyItem => "${pk.id}"}) {
            pk => HStack {
                VStack {
                    HStack {
                        Label(if (pk.name.size > 0) {
                            pk.name
                        } else {
                            "未命名 Passkey"
                        }).fontSize(13.fp)
                        if (pk.algorithm.size > 0) {
                            pill(model, pk.algorithm, PillTone.Outline)
                        }
                        if (pk.userVerified) {
                            pill(model, "已验证用户", PillTone.Gray)
                        }
                    }.spacing(8.vp).crossAxisAlignment(CrossAxisAlignment.Center)
                    Label("credentialId: ${pk.credentialId} · 最后活跃: ${pk.lastUsedAt}")
                        .fontSize(10.fp)
                        .muted()
                        .maxLines(1)
                }.spacing(3.vp).crossAxisAlignment(CrossAxisAlignment.Start).flex()
                Button("删除", {=> model.actRevokePasskey(pk.id)}).role(ButtonRole.Danger)
            }.spacing(10.vp).crossAxisAlignment(CrossAxisAlignment.Center).hug().padding(0.vp, 6.vp)
        }
    }

    // ---- 登录设备（原型卡片 4：会话列表 + 撤销） ----
    let revokeOthersOpen = rememberState<Bool>("auth.revokeOthersOpen", {=> false})
    detailCard(model, "登录设备列表") {
        HStack {
            Spacer()
            Button("退出其他设备", {=> revokeOthersOpen.value = true})
            Button("刷新", {=> model.loadAuthSecurity()})
        }.spacing(8.vp)
        let list = model.sessions.value
        if (list.size == 0) {
            Label("暂无登录设备").fontSize(12.fp).muted()
        }
        ForEach(list.toArray(), key: {s: SessionItem => "${s.id}"}) {
            s => HStack {
                VStack {
                    HStack {
                        Label(if (s.name.size > 0) {
                            s.name
                        } else {
                            "未知设备"
                        }).fontSize(13.fp)
                        if (s.prefix.size > 0) {
                            pill(model, s.prefix, PillTone.Outline)
                        }
                        if (s.current) {
                            pill(model, "当前设备", PillTone.Accent)
                        }
                    }.spacing(8.vp).crossAxisAlignment(CrossAxisAlignment.Center)
                    Label("创建时间: ${s.createdAt} · 最后活跃: ${s.lastUsedAt} · IP: ${s.lastUsedIp}")
                        .fontSize(10.fp)
                        .muted()
                        .maxLines(1)
                }.spacing(3.vp).crossAxisAlignment(CrossAxisAlignment.Start).flex()
                if (s.current) {
                    // 登出当前设备等同退出登录，首版走统一占位 toast（同书库惯例）。
                    Button("登出", {=> model.todoToast("登出当前设备")}).role(ButtonRole.Danger)
                } else {
                    Button("撤销登录", {=> model.actRevokeSession(s.id)}).role(ButtonRole.Danger)
                }
            }.spacing(10.vp).crossAxisAlignment(CrossAxisAlignment.Center).hug().padding(0.vp, 6.vp)
        }
    }
    confirmModal(revokeOthersOpen, "确认退出其他设备？", "当前设备会保持登录，其他所有登录设备会立即失效。",
        "退出其他设备", {
            => model.actRevokeOtherSessions()
        })

    // ---- API Token（原型卡片 5：创建 + 列表 + 删除） ----
    let tokenName = rememberState<String>("auth.tokenName", {=> ""})
    detailCard(model, "API Token 管理") {
        HStack {
            // cui TextField 无 placeholder 具名参数，沿用 formField 的叠层占位做法。
            HStack {
                ZStack {
                    TextField(tokenName.project(get: {v => v}, set: {_, v => v}))
                    if (tokenName.value.size == 0) {
                        Label("Token名称，例如: api, script").fontSize(13.fp).muted().padding(8.vp, 10.vp, 0.vp, 0.vp)
                    }
                }.alignment(Alignment.TopLeading)
            }.flex()
            Button("创建Token", {
                => if (tokenName.value.trimAscii().size > 0) {
                    model.actCreateToken(tokenName.value.trimAscii())
                    tokenName.value = ""
                }
            }).role(ButtonRole.Primary)
        }.spacing(10.vp).crossAxisAlignment(CrossAxisAlignment.Center)
        let list = model.apiTokens.value
        if (list.size == 0) {
            Label("暂无API Token").fontSize(12.fp).muted()
        }
        ForEach(list.toArray(), key: {t: TokenItem => "${t.id}"}) {
            t => HStack {
                Label(if (t.name.size > 0) {
                    t.name
                } else {
                    "未命名Token"
                }).fontSize(13.fp)
                if (t.prefix.size > 0) {
                    pill(model, t.prefix, PillTone.Outline)
                }
                Spacer()
                Button("删除", {=> model.actRevokeToken(t.id)}).role(ButtonRole.Danger)
            }.spacing(8.vp).crossAxisAlignment(CrossAxisAlignment.Center).hug().padding(0.vp, 6.vp)
        }
    }
}
