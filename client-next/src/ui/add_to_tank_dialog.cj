package lanlu_client_next.ui

import cui.*
import lanlu_client_next.app.*
import lanlu_client_next.net.TankoubonInfo
import std.collection.ArrayList

// ── 加入合集对话框（第二波；对齐 frontend 批量栏「加入合集」流程）──
//
// 打开时经 worker 异步拉取 api.listTankoubons 列出合集（可按名称过滤），选中即
// model.addArchivesToTank(tankId, arcids)；底部提供「新建合集」输入框走
// model.createTankAndAdd(name, arcids)。合集条目不可加入合集，arcids 由调用方
// （splitSelection）预先剔除 tank 条目。
//
// 异步取数说明：worker 结果统一由 model.dispatch 按任务名消费，本对话框的
// "tankpicker.list" 不在其列（不改 model.cj 的约束下），结果仅用于唤醒 UI 线程与
// 在途去重；数据由工作线程在任务体内直接写回 State——写发生在 worker 信箱入锁之前，
// UI 线程 drain 取锁后可见，无数据竞争。失败不打 worker 错误通道（避免统一 toast），
// 任务体内捕获后置 failed，由对话框内「重试」再发起。

// 拉取合集列表写入 list；loading/failed 供对话框三态展示。重复点击重试依赖
// worker 同名在途去重，不会叠请求。
public func loadTankPickerList(model: AppModel, list: State<ArrayList<TankoubonInfo>>,
    loading: State<Bool>, failed: State<Bool>): Unit {
    match (model.api) {
        case Some(a) =>
            loading.value = true
            failed.value = false
            let _ = model.worker.submit(
                "tankpicker.list",
                {
                    =>
                        try {
                            list.value = a.listTankoubons()
                        } catch (_: Exception) {
                            failed.value = true
                        }
                        loading.value = false
                        return 0
                }
            )
        case None => ()
    }
}

// 对话框本体。open 由批量栏「加入合集」按钮置起；arcids 为打开那一刻捕获的选中档案列
// （选择可能在对话框打开期间继续变化，批量动作按打开时的快照执行）。
public func addToTankDialog(model: AppModel, open: State<Bool>, arcids: State<ArrayList<String>>): Unit {
    let list = rememberState<ArrayList<TankoubonInfo>>("addtank.list", {=> ArrayList<TankoubonInfo>()})
    let loading = rememberState<Bool>("addtank.loading", {=> false})
    let failed = rememberState<Bool>("addtank.failed", {=> false})
    let filter = rememberState<String>("addtank.filter", {=> ""})
    let newName = rememberState<String>("addtank.newname", {=> ""})
    // 打开沿检测：false→true 时重置过滤/新建名并发起拉取（Modal body 仅在打开时构建，
    // 沿检测必须放在 Modal 之外的本函数每帧路径上）。
    let wasOpen = rememberState<Bool>("addtank.wasopen", {=> false})
    if (open.value && !wasOpen.value) {
        filter.value = ""
        newName.value = ""
        loadTankPickerList(model, list, loading, failed)
    }
    wasOpen.value = open.value

    Modal(open, body: {
        =>
            VStack {
                Label("加入合集").fontSize(15.fp)
                Label("将 ${arcids.value.size} 个选中档案加入合集").fontSize(12.fp).muted()
                // 名称过滤： cui TextField 无 placeholder 参数，沿用 formField 的叠层占位做法。
                ZStack {
                    TextField(filter)
                    if (filter.value.size == 0) {
                        Label("搜索合集…").fontSize(13.fp).muted().padding(8.vp, 10.vp, 0.vp, 0.vp)
                    }
                }.alignment(Alignment.TopLeading)
                if (loading.value) {
                    Label("加载合集列表…").fontSize(12.fp).muted().padding(0.vp, 40.vp)
                } else if (failed.value) {
                    HStack {
                        Label("合集列表加载失败").fontSize(12.fp).muted()
                        Button("重试", {=> loadTankPickerList(model, list, loading, failed)})
                            .style(ghostStyleOf(model))
                    }.spacing(10.vp).crossAxisAlignment(CrossAxisAlignment.Center)
                } else {
                    let needle = filter.value.trimAscii().toAsciiLower()
                    let shown = ArrayList<TankoubonInfo>()
                    for (t in list.value) {
                        if (needle.size == 0 || t.name.toAsciiLower().contains(needle)) {
                            shown.add(t)
                        }
                    }
                    ScrollView(key: "addtank-list") {
                        VStack {
                            for (t in shown) {
                                tankPickRow(t, {=>
                                    open.value = false
                                    model.addArchivesToTank(t.id, arcids.value)
                                })
                            }
                            if (shown.size == 0) {
                                Label("无匹配合集").fontSize(12.fp).muted().padding(0.vp, 24.vp)
                            }
                        }.spacing(2.vp).crossAxisAlignment(CrossAxisAlignment.Start).hug()
                    }.height(240.vp)
                }
                Divider()
                // 新建合集并加入（原型批量栏同款内联创建）。
                HStack {
                    ZStack {
                        TextField(newName)
                        if (newName.value.size == 0) {
                            Label("新合集名称…").fontSize(13.fp).muted().padding(8.vp, 10.vp, 0.vp, 0.vp)
                        }
                    }.alignment(Alignment.TopLeading).flex()
                    Button("新建并加入", {
                        =>
                            let name = newName.value.trimAscii()
                            if (name.size > 0) {
                                open.value = false
                                model.createTankAndAdd(name, arcids.value)
                            }
                    }).role(ButtonRole.Primary)
                }.spacing(10.vp).crossAxisAlignment(CrossAxisAlignment.Center)
                HStack {
                    Spacer()
                    Button("取消", {=> open.value = false}).style(ghostStyleOf(model))
                }
            }.spacing(12.vp).crossAxisAlignment(CrossAxisAlignment.Start).width(380.vp)
    })
}

// 合集选择行：名称 + 档案计数，整行可点（NavItem 同款交互，hover 由 ClickArea 的
// 交互光标表达；计数 muted 右对齐）。
private func tankPickRow(t: TankoubonInfo, onClick: () -> Unit): Unit {
    ClickArea(onClick: onClick) {
        HStack {
            Label(t.name).fontSize(13.fp).maxLines(1)
            Spacer()
            Label("${t.archiveCount} 个档案").fontSize(11.fp).muted()
        }.spacing(10.vp).crossAxisAlignment(CrossAxisAlignment.Center).hug().padding(8.vp, 7.vp)
    }
}
