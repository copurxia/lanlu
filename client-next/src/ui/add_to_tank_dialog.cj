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
// 异步结果写入 Mutex 保护的 DialogCell，UI State 不跨线程修改；LoadPoll 只负责在
// 请求完成前提供定时帧，成功、失败、空列表都由弹窗本地状态明确呈现。

private func loadTankPickerList(model: AppModel, cell: DialogCell<ArrayList<TankoubonInfo>>): Unit {
    cell.begin()
    match (model.api) {
        case Some(a) =>
            let lang = model.language.value
            let _ = model.worker.submit(
                "tankpicker.list",
                {
                    =>
                        try {
                            cell.store(a.listTankoubons(lang: lang))
                        } catch (e: Exception) {
                            cell.storeError(e.message)
                        }
                        return 0
                }
            )
        case None => cell.storeError(model.t("dialog.notLoggedIn"))
    }
}

// 对话框本体。open 由批量栏「加入合集」按钮置起；arcids 为打开那一刻捕获的选中档案列
// （选择可能在对话框打开期间继续变化，批量动作按打开时的快照执行）。
public func addToTankDialog(model: AppModel, open: State<Bool>, arcids: State<ArrayList<String>>): Unit {
    let cell = rememberState<DialogCell<ArrayList<TankoubonInfo>>>("addtank.cell",
        {=> DialogCell<ArrayList<TankoubonInfo>>()}).value
    let filter = rememberState<String>("addtank.filter", {=> ""})
    let newName = rememberState<String>("addtank.newname", {=> ""})
    // 打开沿检测：false→true 时重置过滤/新建名并发起拉取（Modal body 仅在打开时构建，
    // 沿检测必须放在 Modal 之外的本函数每帧路径上）。
    let wasOpen = rememberState<Bool>("addtank.wasopen", {=> false})
    if (open.value && !wasOpen.value) {
        filter.value = ""
        newName.value = ""
        loadTankPickerList(model, cell)
    } else if (!open.value && wasOpen.value) {
        cell.reset()
    }
    wasOpen.value = open.value

    Modal(open, body: {
        => ZStack {
            VStack {
                Label(model.t("dialog.addToCollection")).fontSize(15.fp)
                Label(model.t("dialog.addSelected", params: [("count", "${arcids.value.size}")]))
                    .fontSize(12.fp)
                    .muted()
                // 名称过滤： cui TextField 无 placeholder 参数，沿用 formField 的叠层占位做法。
                ZStack {
                    TextField(filter)
                    if (filter.value.size == 0) {
                        Label(model.t("dialog.searchCollections"))
                            .fontSize(13.fp)
                            .muted()
                            .padding(8.vp, 10.vp, 0.vp, 0.vp)
                    }
                }.alignment(Alignment.TopLeading)
                if (cell.error().size > 0) {
                    HStack {
                        Label(model.t("dialog.loadFailed", params: [("error", cell.error())]))
                            .fontSize(12.fp)
                            .muted()
                            .maxLines(3)
                            .flex()
                        Button(model.t("dialog.retry"), {=> loadTankPickerList(model, cell)}).style(ghostStyleOf(model))
                    }.spacing(10.vp).crossAxisAlignment(CrossAxisAlignment.Center).hug().fillWidth()
                } else {
                    match (cell.fetch()) {
                        case Some(list) =>
                            let needle = filter.value.trimAscii().toAsciiLower()
                            let shown = ArrayList<TankoubonInfo>()
                            for (t in list) {
                                if (needle.size == 0 || t.name.toAsciiLower().contains(needle)) {
                                    shown.add(t)
                                }
                            }
                            if (shown.size == 0) {
                                Label(if (list.size == 0) {
                                    model.t("dialog.noCollectionsCreate")
                                } else {
                                    model.t("dialog.noMatchingCollections")
                                }).fontSize(12.fp).muted().padding(0.vp, 24.vp)
                            } else {
                                ScrollView(key: "addtank-list") {
                                    VStack {
                                        for (t in shown) {
                                            tankPickRow(
                                                model,
                                                t,
                                                {
                                                    =>
                                                        open.value = false
                                                        model.addArchivesToTank(t.id, copyArchiveIds(arcids.value))
                                                }
                                            )
                                        }
                                    }.spacing(2.vp).crossAxisAlignment(CrossAxisAlignment.Start).hug().fillWidth()
                                }.height(240.vp)
                            }
                        case None => Label(model.t("dialog.loadingCollections")).fontSize(12.fp).muted()
                    }
                }
                Divider()
                // 新建合集并加入（原型批量栏同款内联创建）。
                HStack {
                    ZStack {
                        TextField(newName)
                        if (newName.value.size == 0) {
                            Label(model.t("dialog.newCollectionName"))
                                .fontSize(13.fp)
                                .muted()
                                .padding(8.vp, 10.vp, 0.vp, 0.vp)
                        }
                    }.alignment(Alignment.TopLeading).flex()
                    Button(
                        model.t("dialog.createAndAdd"),
                        {
                            =>
                                let name = newName.value.trimAscii()
                                if (name.size > 0) {
                                    open.value = false
                                    model.createTankAndAdd(name, copyArchiveIds(arcids.value))
                                }
                        }
                    ).role(ButtonRole.Primary)
                }.spacing(10.vp).crossAxisAlignment(CrossAxisAlignment.Center).hug().fillWidth()
                HStack {
                    Spacer()
                    Button(model.t("common.cancel"), {=> open.value = false}).style(ghostStyleOf(model))
                }.hug().fillWidth()
            }.spacing(12.vp).crossAxisAlignment(CrossAxisAlignment.Start).hug().width(380.vp)
            LoadPoll({=> !open.value || cell.fetch().isSome() || cell.error().size > 0})
        }.alignment(Alignment.TopLeading)
    })
}

private func copyArchiveIds(source: ArrayList<String>): ArrayList<String> {
    let copy = ArrayList<String>()
    for (id in source) {
        copy.add(id)
    }
    copy
}

// 合集选择行：名称 + 档案计数，整行可点（NavItem 同款交互，hover 由 ClickArea 的
// 交互光标表达；计数 muted 右对齐）。
private func tankPickRow(model: AppModel, t: TankoubonInfo, onClick: () -> Unit): Unit {
    ClickArea(onClick: onClick) {
        HStack {
            Label(t.name).fontSize(13.fp).maxLines(1)
            Spacer()
            Label(model.t("dialog.archiveCount", params: [("count", "${t.archiveCount}")])).fontSize(11.fp).muted()
        }.spacing(10.vp).crossAxisAlignment(CrossAxisAlignment.Center).hug().fillWidth().padding(8.vp, 7.vp)
    }
}
