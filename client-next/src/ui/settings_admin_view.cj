package lanlu_client_next.ui

import cui.*
import lanlu_client_next.app.*
import lanlu_client_next.net.{SysSetting, TaskRecord, PluginItem, AdminUserItem, CronTask, CloudTag}
import std.collection.ArrayList

// 设置区·系统管理板块（用户/系统/任务记录/定时任务/插件/统计信息）。
// 各页面先占位，由对应 Task 就地充实。

func usersPage(model: AppModel): Unit {
    // 进场加载一次：rememberState 随页面卸载清除，每次进入重拉（同统计页约定）。
    let loaded = rememberState<Bool>("users.loaded", {=> false})
    if (!loaded.value) {
        loaded.value = true
        model.loadAdminUsers()
    }
    pageHeader("用户管理", "管理系统用户、角色和权限")

    // ---- 创建用户（原型卡片 1） ----
    let newName = rememberState<String>("users.newName", {=> ""})
    let newAdmin = rememberState<Bool>("users.newAdmin", {=> false})
    detailCard(model, "创建用户") {
        HStack {
            // formField 限宽约 320vp，右侧「设为管理员」开关保留在行内可见。
            VStack { formField("用户名", newName, "请输入用户名") }.width(320.vp)
            VStack {
                Label("设为管理员").fontSize(11.fp).muted()
                Switch("", newAdmin.project(get: {v => v}, set: {_, v => v }))
            }.spacing(5.vp).crossAxisAlignment(CrossAxisAlignment.Start)
            Spacer()
        }.spacing(16.vp).crossAxisAlignment(CrossAxisAlignment.End).hug()
        HStack {
            Button("创建用户", {=>
                if (newName.value.trimAscii().size > 0) {
                    model.actCreateUser(newName.value.trimAscii(), newAdmin.value)
                    newName.value = ""
                }
            }).role(ButtonRole.Primary)
        }.hug().padding(0.vp, 12.vp, 0.vp, 0.vp)
    }

    // ---- 用户列表（原型卡片 2；当前登录用户操作禁用） ----
    let delId = rememberState<Int64>("users.delId", {=> -1})
    let delOpen = rememberState<Bool>("users.delOpen", {=> false})
    let resetId = rememberState<Int64>("users.resetId", {=> -1})
    let resetOpen = rememberState<Bool>("users.resetOpen", {=> false})
    let resetPw = rememberState<String>("users.resetPw", {=> ""})
    detailCard(model, "用户列表") {
        let users = model.adminUsers.value
        if (users.size == 0) {
            pageLoading(model, "暂无用户或加载中…")
        }
        ForEach(users.toArray(), key: { u: AdminUserItem => "${u.id}" }) { u =>
            let self = u.username == model.settings.username
            HStack {
                VStack {
                    HStack {
                        Label(u.username).fontSize(13.fp)
                        if (u.isAdmin) { pill(model, "管理员", PillTone.Accent) }
                        else { pill(model, "普通用户", PillTone.Gray) }
                        if (self) { pill(model, "当前用户", PillTone.Blue) }
                    }.spacing(8.vp).crossAxisAlignment(CrossAxisAlignment.Center)
                    Label("创建时间: ${u.createdAt}").fontSize(10.fp).muted()
                }.spacing(3.vp).crossAxisAlignment(CrossAxisAlignment.Start).flex()
                Button("重置密码", {=>
                    resetId.value = u.id
                    resetPw.value = ""
                    resetOpen.value = true
                }).enabled(!self)
                // 角色开关：cui Bindable 仅 State.project 一种产出途径，按 brief 备选方案——
                // 本地 rememberState 初值取 u.isAdmin，set 里直接提交服务端（同外观页主题分段写法），
                // 失败由 handleError 提示，列表随 act.* 内部 reload 刷新。
                Switch("管理员",
                    rememberState<Bool>("users.role.${u.id}", {=> u.isAdmin })
                        .project(get: {v => v}, set: {_, v =>
                            model.actSetUserRole(u.id, v)
                            return v
                        }))
                    .enabled(!self)
                Button("删除", {=>
                    delId.value = u.id
                    delOpen.value = true
                }).role(ButtonRole.Danger).enabled(!self)
            }.spacing(10.vp).crossAxisAlignment(CrossAxisAlignment.Center).flexible(false).fillWidth().padding(0.vp, 6.vp)
        }
    }
    confirmModal(delOpen, "确认删除用户", "您确定要删除此用户吗？此操作无法撤销。", "删除", {=>
        model.actDeleteUser(delId.value)
    })
    // 重置密码弹窗（原型 dialog：新密码 + 确认动作）。
    Modal(resetOpen, body: {=>
        VStack {
            Label("重置密码").fontSize(15.fp)
            formField("新密码", resetPw, "请输入新密码（至少6位）", masked: true)
            HStack {
                Spacer()
                Button("取消", {=> resetOpen.value = false })
                Button("重置密码", {=>
                    if (resetPw.value.size >= 6) {
                        resetOpen.value = false
                        model.actResetUserPassword(resetId.value, resetPw.value)
                    }
                }).role(ButtonRole.Primary)
            }.spacing(8.vp)
        }.spacing(12.vp).crossAxisAlignment(CrossAxisAlignment.Start).width(360.vp)
    })
}

func systemPage(model: AppModel): Unit {
    // 进场加载一次全量设置（rememberState 随页面卸载清除，每次进入重拉）。
    let loaded = rememberState<Bool>("sys.loaded", {=> false})
    if (!loaded.value) {
        loaded.value = true
        model.loadSysSettings()
    }
    pageHeader("系统设置", "管理系统的核心配置参数（保存经服务端批量接口）")

    // 四个 Tab 对应设置项的 category 分组。
    let tab = rememberState<Int64>("sys.tab", {=> 0})
    SegmentedControl(["存储设置", "性能设置", "服务器设置", "SSL 设置"],
        tab.project(get: {v => v}, set: {_, v => v }))
    let category = match (tab.value) {
        case 0 => "storage"
        case 1 => "performance"
        case 2 => "server"
        case _ => "ssl"
    }
    if (tab.value == 1) {
        noticeRow(model, "性能设置中包含 TaskPool 和 RocksDB 本地 KV 的调优项；ROCKSDB_ 前缀的设置需重启后生效")
    } else if (tab.value == 3) {
        noticeRow(model, "启用 SSL/TLS 后经 ALPN 自动支持 HTTP/2；SSL 设置保存后需重启服务生效")
    }
    detailCard(model, match (tab.value) {
        case 0 => "存储设置"
        case 1 => "性能设置"
        case 2 => "服务器设置"
        case _ => "SSL 设置"
    }) {
        let all = model.sysSettings.value
        if (all.size == 0) {
            pageLoading(model, "设置加载中…")
        }
        // 构建期收集各行草稿 State，保存回调只读已收集的 State（避免回调内调用 rememberState）。
        let drafts = ArrayList<(String, State<String>)>()
        for (s in all) {
            if (s.category != category) { continue }
            drafts.add((s.key, sysSettingRow(model, s)))
        }
        HStack {
            Spacer()
            Button("保存", {=>
                let entries = ArrayList<(String, String)>()
                for ((k, st) in drafts) { entries.add((k, st.value)) }
                model.actSaveSysSettings(entries)
            }).role(ButtonRole.Primary).enabled(drafts.size > 0)
        }.flexible(false).fillWidth().padding(0.vp, 12.vp, 0.vp, 0.vp)
    }
}

// 提示条（原型 .notice）：警告色左边框说明文字。
func noticeRow(model: AppModel, text: String): Unit {
    let soft = if (model.isLight()) { LANLU_L_ACCENT_SOFT } else { LANLU_ACCENT_SOFT }
    let accent = if (model.isLight()) { LANLU_L_ACCENT } else { LANLU_ACCENT }
    Label(text).fontSize(11.fp).foregroundColor(accent)
        .padding(12.vp, 10.vp).background(soft, 10.vp)
}

// 单个设置项：按 valueType 渲染控件；草稿存 rememberState("sys.{key}")，并返回草稿 State 供保存回调读取。
private func sysSettingRow(model: AppModel, s: SysSetting): State<String> {
    let draft = rememberState<String>("sys.${s.key}", {=> s.value})
    let title = if (s.descriptionZh.size > 0) { "${s.descriptionZh}  ${s.key}" } else { s.key }
    if (s.valueType == "boolean") {
        settingRow(model, title, "") {
            // cui Switch 两参数均位置参数；"true"/"false" 字符串与布尔互转。
            Switch("", draft.project(
                get: {v => v == "true" },
                set: {_, v => if (v) { "true" } else { "false" } }))
        }
    } else if (s.key == "ROCKSDB_COMPRESSION") {
        let opts = ["none", "snappy", "zlib", "bz2", "lz4", "lz4hc", "xpress", "zstd"]
        settingRow(model, title, "") {
            Dropdown(opts, draft.project(
                get: {v => compressionIndex(opts, v) },
                set: {_, i => opts[i] }))
        }
    } else {
        settingRow(model, title, if (s.valueType == "long") { "单位：毫秒" } else { "" }) {
            HStack {
                // cui TextField 无 placeholder 参数：ZStack 叠 muted Label 实现（同 formField）。
                ZStack {
                    TextField(draft.project(get: {v => v }, set: {_, v => v }))
                    if (draft.value.size == 0 && s.value.size > 0) {
                        Label(s.value).fontSize(13.fp).muted().padding(8.vp, 10.vp, 0.vp, 0.vp)
                    }
                }.alignment(Alignment.TopLeading)
            }.width(240.vp)
        }
    }
    return draft
}

private func compressionIndex(opts: Array<String>, v: String): Int64 {
    for (i in 0..opts.size) { if (opts[i] == v) { return i } }
    return 0
}

func tasksPage(model: AppModel): Unit {
    let tab = rememberState<Int64>("tasks.tab", {=> 0})
    let loadedKey = rememberState<String>("tasks.loadedKey", {=> ""})
    let status = taskStatusOf(tab.value)
    if (loadedKey.value != status) {
        loadedKey.value = status
        model.loadTasks(status)
    }
    pageHeader("任务记录", "查看并管理后台任务（列表为进入/切换时的快照）")

    // 状态筛选（原型 .ftabs：全部/待执行/执行中/等待中/已完成/失败）。
    HStack {
        SegmentedControl(["全部", "待执行", "执行中", "等待中", "已完成", "失败"],
            tab.project(get: {v => v }, set: {_, v => v }))
        Spacer()
        Button("⟳ 刷新", {=> model.loadTasks(status) })
    }.crossAxisAlignment(CrossAxisAlignment.Center).hug()

    let cancelId = rememberState<Int64>("tasks.cancelId", {=> -1})
    let cancelOpen = rememberState<Bool>("tasks.cancelOpen", {=> false})
    match (model.taskPage.value) {
        case Some(p) =>
            if (p.tasks.size == 0) {
                Label("该状态下没有任务").fontSize(12.fp).muted()
            }
            ForEach(p.tasks.toArray(), key: { t: TaskRecord => "${t.id}" }) { t =>
                taskCard(model, t, cancelId, cancelOpen)
            }
            Label("共 ${p.total} 个任务").fontSize(11.fp).muted()
        case None => pageLoading(model, "任务快照读取中…")
    }
    confirmModal(cancelOpen, "取消任务", "确定要取消这个任务吗？", "取消任务", {=>
        model.actCancelTask(cancelId.value)
    })
}

private func taskStatusOf(tab: Int64): String {
    match (tab) {
        case 1 => "pending"
        case 2 => "running"
        case 3 => "waiting"
        case 4 => "completed"
        case 5 => "failed"
        case _ => "all"
    }
}

// 任务卡（原型 .task-card：名称 + 状态/编号/优先级/类型徽章 + 取消/重试 + 进度 + 日志 + 时间）。
private func taskCard(model: AppModel, t: TaskRecord, cancelId: State<Int64>, cancelOpen: State<Bool>): Unit {
    let panel = if (model.isLight()) { LANLU_L_PANEL } else { LANLU_PANEL }
    VStack {
        HStack {
            Label(t.name).fontSize(13.fp).maxLines(1)
            pill(model, taskStatusLabel(t.status), taskStatusTone(t.status))
            Spacer()
            pill(model, "Job #${t.id}", PillTone.Outline)
            pill(model, "P${t.priority}", priorityTone(t.priority))
            if (t.taskType.size > 0) { pill(model, taskTypeLabel(t.taskType), PillTone.Blue) }
            if (t.triggerSource.size > 0) { pill(model, t.triggerSource, PillTone.Outline) }
            if (t.status == "pending" || t.status == "running" || t.status == "waiting") {
                Button("⏹ 取消", {=>
                    cancelId.value = t.id
                    cancelOpen.value = true
                }).role(ButtonRole.Danger)
            } else if (t.status == "failed" || t.status == "stopped") {
                Button("▶ 重试", {=> model.actRetryTask(t.id) })
            }
        }.spacing(8.vp).crossAxisAlignment(CrossAxisAlignment.Center)
        HStack {
            Label("进度").fontSize(10.fp).muted()
            ProgressTrack(t.progress, 6.0)
            Label("${t.progress}%").fontSize(10.fp).muted()
        }.spacing(10.vp).crossAxisAlignment(CrossAxisAlignment.Center)
        if (t.message.size > 0) {
            Label(t.message).fontSize(10.fp).muted().maxLines(3)
        }
        HStack {
            taskTimeCell("创建时间", t.createdAt)
            taskTimeCell("开始时间", t.startedAt)
            taskTimeCell("完成时间", t.completedAt)
        }.spacing(12.vp)
    }.spacing(8.vp).crossAxisAlignment(CrossAxisAlignment.Start).hug()
        .padding(12.vp, 14.vp).background(panel, 14.vp).fillWidth()
}

private func taskTimeCell(k: String, v: String): Unit {
    VStack {
        Label(k).fontSize(9.fp).muted()
        Label(if (v.size > 0) { v } else { "-" }).fontSize(11.fp)
    }.spacing(2.vp).crossAxisAlignment(CrossAxisAlignment.Start).flex()
}

private func taskStatusLabel(s: String): String {
    match (s) {
        case "pending" => "待执行"
        case "running" => "执行中"
        case "waiting" => "等待中"
        case "completed" => "已完成"
        case "failed" => "失败"
        case "stopped" => "已停止"
        case _ => s
    }
}

private func taskStatusTone(s: String): PillTone {
    match (s) {
        case "running" => PillTone.Blue
        case "waiting" => PillTone.Orange
        case "completed" => PillTone.Green
        case "failed" | "stopped" => PillTone.Red
        case _ => PillTone.Accent
    }
}

private func priorityTone(p: Int64): PillTone {
    if (p <= 10) { return PillTone.Red }
    if (p <= 20) { return PillTone.Orange }
    if (p <= 40) { return PillTone.Blue }
    return PillTone.Gray
}

// 任务类型中文名（前端 cron 类型表子集，未知类型原样显示）。
func taskTypeLabel(v: String): String {
    match (v) {
        case "scan_all_categories" => "扫描所有分类"
        case "scan_single_category" | "scan_category" => "扫描分类"
        case "scan_archive" => "扫描档案"
        case "generate_thumbnail" => "生成缩略图"
        case "check_database" => "数据库检查"
        case "clear_cache" => "清理缓存"
        case "clear_log" => "清理日志"
        case "regenerate_cover" => "重建封面"
        case "backfill_metadata" => "回填元数据"
        case "scan_plugins" => "插件扫描"
        case "metadata_plugin" => "元数据插件"
        case "tag_import" => "标签导入"
        case "download_url" => "下载URL"
        case "asset_upload" | "upload" | "asset_upload_process" | "upload_process" => "资源上传"
        case _ => v
    }
}

func cronPage(model: AppModel): Unit {
    // 进场加载一次：任务数据 + 系统设置（启动任务设置键也在系统设置里）。
    let loaded = rememberState<Bool>("cron.loaded", {=> false})
    if (!loaded.value) {
        loaded.value = true
        model.loadCron()
        model.loadSysSettings()
    }
    pageHeader("定时任务管理", "配置定时执行的任务和启动时触发的任务")
    HStack {
        Spacer()
        Button("⟳ 刷新", {=> model.loadCron() })
        // 创建/编辑弹窗首版走 todoToast（YAGNI，计划评审已确认）。
        Button("＋ 创建定时任务", {=> model.todoToast("定时任务编辑弹窗") }).role(ButtonRole.Primary)
    }.hug()

    // 服务状态卡（原型：运行中/已停止 + 启停 + 统计）。
    detailCard(model, "服务状态") {
        match (model.cronStatus.value) {
            case Some(st) =>
                HStack {
                    if (st.running) { pill(model, "运行中", PillTone.Green) }
                    else { pill(model, "已停止", PillTone.Gray) }
                    Spacer()
                    Label("总任务数: ${st.totalTasks} · 已启用: ${st.enabledTasks}").fontSize(11.fp).muted()
                    Button(if (st.running) { "⏹ 停止服务" } else { "▶ 启动服务" },
                        {=> model.actCronServiceToggle() })
                }.spacing(10.vp).crossAxisAlignment(CrossAxisAlignment.Center)
            case None => pageLoading(model, "加载中…")
        }
    }

    let tab = rememberState<Int64>("cron.tab", {=> 0})
    SegmentedControl(["定时任务列表", "启动任务设置"], tab.project(get: {v => v }, set: {_, v => v }))
    if (tab.value == 0) {
        cronTaskList(model)
    } else {
        startupSettings(model)
    }
}

// 定时任务列表（原型：任务卡 + 立即执行/启停/编辑/删除）。
private func cronTaskList(model: AppModel): Unit {
    let delId = rememberState<Int64>("cron.delId", {=> -1})
    let delOpen = rememberState<Bool>("cron.delOpen", {=> false})
    let tasks = model.cronTasks.value
    if (tasks.size == 0) {
        Label("暂无定时任务").fontSize(12.fp).muted()
    }
    ForEach(tasks.toArray(), key: { t: CronTask => "${t.id}" }) { t =>
        let panel = if (model.isLight()) { LANLU_L_PANEL } else { LANLU_PANEL }
        VStack {
            HStack {
                Label(t.name).fontSize(13.fp)
                if (t.enabled) { pill(model, "启用", PillTone.Green) }
                else { pill(model, "禁用", PillTone.Gray) }
                pill(model, taskTypeLabel(t.taskType), PillTone.Outline)
                Spacer()
                Button("▶", {=> model.actCronTrigger(t.id) })
                // cui Switch 两参数均位置参数；绑定件按任务 id 唯一化 key（见 switchBindKeyed）。
                Switch("", switchBindKeyed("cron.${t.id}", t.enabled, {v => model.actCronToggle(t.id, v) }))
                Button("编辑", {=> model.todoToast("定时任务编辑弹窗") })
                Button("删除", {=>
                    delId.value = t.id
                    delOpen.value = true
                }).role(ButtonRole.Danger)
            }.spacing(8.vp).crossAxisAlignment(CrossAxisAlignment.Center)
            HStack {
                taskTimeCell("Cron 表达式", t.cronExpression)
                taskTimeCell("优先级", "${t.priority}")
                taskTimeCell("执行次数", "${t.runCount}")
                taskTimeCell("上次执行", if (t.hasLastRun) {
                    "${t.lastRunAt} ${if (t.lastRunSuccess) { "✓" } else { "✗" }}"
                } else { "从未执行" })
            }.spacing(12.vp)
            if (t.enabled && t.nextRunAt.size > 0) {
                Label("下次执行: ${t.nextRunAt}").fontSize(11.fp)
                    .foregroundColor(if (model.isLight()) { LANLU_L_ACCENT } else { LANLU_ACCENT })
            }
        }.spacing(8.vp).crossAxisAlignment(CrossAxisAlignment.Start).hug()
            .padding(12.vp, 14.vp).background(panel, 14.vp).fillWidth()
    }
    confirmModal(delOpen, "删除定时任务", "确定要删除此定时任务吗？此操作无法撤销。", "删除", {=>
        model.actCronDelete(delId.value)
    })
}

// 启动任务设置（前端 StartupTaskSettings：改动即保存）。
private func startupSettings(model: AppModel): Unit {
    detailCard(model, "启动任务配置") {
        startupRow(model, "启动时扫描目录", "应用启动时自动扫描档案目录", "ENABLE_INITIAL_SCAN", false)
        startupRow(model, "启动时检查数据库", "应用启动时自动检查数据库一致性", "ENABLE_INITIAL_DB_CHECK", true)
        startupRow(model, "启动时扫描插件", "应用启动时自动扫描并加载插件", "ENABLE_INITIAL_PLUGIN_SCAN", true)
    }
}

private func startupRow(model: AppModel, label: String, desc: String, key: String, dft: Bool): Unit {
    var cur = if (dft) { "true" } else { "false" }
    for (s in model.sysSettings.value) { if (s.key == key) { cur = s.value } }
    // lambda 不能捕获可变局部变量，取不可变副本。
    let cur0 = cur
    settingRow(model, label, desc) {
        Switch("", rememberState<Bool>("cron.startup.${key}", {=> cur0 == "true" })
            .project(get: {v => v }, set: {_, v =>
                model.actSaveStartup(key, v)
                return v
            }))
    }
}

func pluginsPage(model: AppModel): Unit {
    // 进场加载一次：rememberState 随页面卸载清除，每次进入重拉（同统计页约定）。
    let loaded = rememberState<Bool>("plugins.loaded", {=> false})
    if (!loaded.value) {
        loaded.value = true
        model.loadPlugins()
    }
    pageHeader("插件管理", "管理系统插件的启用、禁用和配置")

    // 类型筛选（原型 ftabs：全部/元数据/下载/登录/脚本/在线源）。
    let tab = rememberState<Int64>("plugins.tab", {=> 0})
    HStack {
        SegmentedControl(["全部", "元数据", "下载", "登录", "脚本", "在线源"],
            tab.project(get: {v => v }, set: {_, v => v }))
        Spacer()
        // 安装插件（wasm 上传/URL）首版走 todoToast（YAGNI，计划评审已确认）。
        Button("安装插件", {=> model.todoToast("安装插件（wasm 上传/URL）") }).role(ButtonRole.Primary)
    }.crossAxisAlignment(CrossAxisAlignment.Center).hug()

    let delNs = rememberState<String>("plugins.delNs", {=> ""})
    let delOpen = rememberState<Bool>("plugins.delOpen", {=> false})
    let cfgNs = rememberState<String>("plugins.cfgNs", {=> ""})
    let cfgOpen = rememberState<Bool>("plugins.cfgOpen", {=> false})
    let want = pluginTypeOf(tab.value)
    let list = model.plugins.value
    // 先按类型过滤出目标列表，再切块渲染（过滤逻辑与原 shown 计数一致）。
    let filtered = ArrayList<PluginItem>()
    for (p in list) {
        if (want.size > 0 && p.pluginType != want) { continue }
        filtered.add(p)
    }
    // 卡片网格（原型 .grid-3：三列）。同分类页做法：LazyGrid 与页层 ScrollView 嵌套
    // 会拿到无限高，故退化为 HStack 三列等宽分行布局（见 chunkCats 注释）。
    // 异步网格同样走 ForEach(key)，防止数据到达后的重建错位。
    ForEachIndexed(chunkPlugins(filtered, 3).toArray()) { _, row =>
        HStack {
            ForEach(row.toArray(), key: { p: PluginItem => p.namespace }) { p =>
                VStack {
                    pluginCard(model, p, delNs, delOpen, cfgNs, cfgOpen)
                }.flex()
            }
            // 末行补空槽，保持三列等宽。
            for (_ in 0..(3 - row.size)) {
                VStack { }.flex()
            }
        }.spacing(12.vp).crossAxisAlignment(CrossAxisAlignment.Start).hug()
    }
    if (filtered.size == 0) {
        let _ = Label("暂无插件").fontSize(12.fp).muted()
    }
    confirmModal(delOpen, "删除插件", "确定要删除该插件吗？此操作将同时删除插件文件，不可恢复。", "删除", {=>
        model.actPluginDelete(delNs.value)
    })
    pluginConfigModal(model, cfgNs, cfgOpen)
}

// 按 cols 切成若干行（三列分行布局用；与分类页 chunkCats 同款做法）。
private func chunkPlugins(items: ArrayList<PluginItem>, cols: Int64): ArrayList<ArrayList<PluginItem>> {
    let rows = ArrayList<ArrayList<PluginItem>>()
    var i = 0
    while (i < items.size) {
        let row = ArrayList<PluginItem>()
        var c = 0
        while (c < cols && i + c < items.size) {
            row.add(items[i + c])
            c += 1
        }
        rows.add(row)
        i += cols
    }
    return rows
}

private func pluginTypeOf(tab: Int64): String {
    match (tab) {
        case 1 => "metadata"
        case 2 => "download"
        case 3 => "login"
        case 4 => "script"
        case 5 => "source"
        case _ => ""
    }
}

private func pluginTypeLabel(v: String): (String, PillTone) {
    match (v) {
        case "metadata" => ("元数据", PillTone.Blue)
        case "download" => ("下载", PillTone.Green)
        case "login" => ("登录", PillTone.Red)
        case "script" => ("脚本", PillTone.Orange)
        case "source" => ("在线源", PillTone.Accent)
        case _ => (v, PillTone.Gray)
    }
}

// 插件卡（原型 .m-card：名称/命名空间/类型徽章/开关 + 作者/版本/描述 + 操作行）。
private func pluginCard(model: AppModel, p: PluginItem, delNs: State<String>, delOpen: State<Bool>,
        cfgNs: State<String>, cfgOpen: State<Bool>): Unit {
    let panel = if (model.isLight()) { LANLU_L_PANEL } else { LANLU_PANEL }
    let (typeText, typeTone) = pluginTypeLabel(p.pluginType)
    VStack {
        HStack {
            VStack {
                Label(p.name).fontSize(14.fp)
                Label("命名空间: ${p.namespace}").fontSize(10.fp).muted()
            }.spacing(2.vp).crossAxisAlignment(CrossAxisAlignment.Start).flex()
            pill(model, typeText, typeTone)
            // cui Switch 两参数均位置参数；绑定件按插件命名空间唯一化 key（见 switchBindKeyed）。
            Switch("", switchBindKeyed("plugin.${p.namespace}", p.enabled,
                {v => model.actPluginEnabled(p.namespace, v) }))
                .enabled(p.installed)
        }.spacing(8.vp).crossAxisAlignment(CrossAxisAlignment.Center).fillWidth()
        Label("作者: ${p.author} · 版本: ${p.version}").fontSize(11.fp).muted()
        Label(p.description).fontSize(11.fp).muted().maxLines(2)
        HStack {
            Button("删除", {=>
                delNs.value = p.namespace
                delOpen.value = true
            }).role(ButtonRole.Danger)
            Spacer()
            // 应用字体无 emoji 字形，按钮用文字「配置」。
            Button("配置", {=>
                cfgNs.value = p.namespace
                cfgOpen.value = true
            }).enabled(p.installed && p.hasSchema)
        }.crossAxisAlignment(CrossAxisAlignment.Center).fillWidth()
    }.spacing(8.vp).crossAxisAlignment(CrossAxisAlignment.Start).hug()
        .padding(12.vp, 14.vp).background(panel, 14.vp).fillWidth()
}

// 配置弹窗：首版收敛为说明性弹窗——参数 Schema 运行时按插件动态生成，
// 完整表单（string/int/bool/array 同系统设置页 sysSettingRow 模式）留待后续迭代。
private func pluginConfigModal(model: AppModel, cfgNs: State<String>, cfgOpen: State<Bool>): Unit {
    Modal(cfgOpen, body: {=>
        VStack {
            Label("配置插件 · ${cfgNs.value}").fontSize(15.fp)
            Label("参数加载与编辑走系统设置同款表单（string/int 输入、bool 开关、array 逗号分隔）")
                .fontSize(11.fp).muted()
            HStack {
                Spacer()
                Button("取消", {=> cfgOpen.value = false })
                Button("关闭", {=> cfgOpen.value = false }).role(ButtonRole.Primary)
            }.spacing(8.vp)
        }.spacing(12.vp).crossAxisAlignment(CrossAxisAlignment.Start).width(440.vp)
    })
}

func statsPage(model: AppModel): Unit {
    // 进场加载一次：rememberState 随页面卸载清除，每次进入重拉（同设置页头部约定）。
    let loaded = rememberState<Bool>("stats.loaded", {=> false})
    if (!loaded.value) {
        loaded.value = true
        model.loadServerInfo()
        model.loadTagCloud()
    }
    pageHeader("统计信息", "查看系统信息与标签词云")

    // 系统信息（原型 kv-grid 两列定义列表 + motd）。
    detailCard(model, "系统信息") {
        match (model.serverInfo.value) {
            case Some(info) =>
                infoList(model, [
                    ("服务器名称", info.name),
                    ("版本", "${info.versionName} ${info.version}"),
                    ("档案总数", "${info.totalArchives}"),
                    ("地址", model.settings.serverUrl)
                ])
            case None => pageLoading(model, "加载中…")
        }
    }

    // 标签词云（原型 WordCloud：字号随权重；点击跳书库搜索）。
    detailCard(model, "标签词云") {
        let tags = model.tagCloud.value
        if (tags.size == 0) {
            let _ = Label("暂无标签数据").fontSize(12.fp).muted()
        } else {
            var maxC = 1
            for (t in tags) { if (t.count > maxC) { maxC = t.count } }
            // lambda 不能捕获可变局部变量，取不可变副本进 FlowRow 构建器。
            let maxCount = maxC
            let _ = FlowRow {
                ForEach(tags.toArray(), key: { t: CloudTag => t.tag }) { t =>
                    // 字号 11..22fp 随权重线性放大（原型 11+count*0.45px，上限收敛）。
                    let fs = 11.0 + 11.0 * Float64(t.count) / Float64(maxCount)
                    ClickArea(onClick: {=> model.searchFromSettings(t.tag) }) {
                        Label(t.display).fontSize(fs.fp)
                            .foregroundColor(if (model.isLight()) { LANLU_L_MUTED } else { LANLU_MUTED })
                    }
                }
            }.spacing(14.vp)
        }
    }
}
