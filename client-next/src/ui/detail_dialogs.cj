package lanlu_client_next.ui

import cui.*
import lanlu_client_next.app.*
import lanlu_client_next.net.{SearchItem, SearchQuery, TankoubonInfo}
import std.collection.{ArrayList, HashSet}
import std.sync.Mutex

// 详情页对话框（第二波交互）：
// - addToTankDialog：档案详情「加入合集」——异步列出合集选择加入，或输入名称新建合集并加入。
// - tankAddArchivesDialog：合集详情「添加档案」——搜索框 + 结果多选（排除已是成员的 id），
//   确认后批量加入。
//
// 异步取数：model.cj 不可改，任务名走 model 不识别的 "dlg." 前缀（dispatch 静默忽略），
// 结果由 job 直接写入 DialogCell（工作线程加锁写、UI 线程构建期读）；异常在 job 内捕获
// 写格，不触发全局错误 toast。框架按需渲染（无 State 写入不重绘），结果格不是 State，
// 故挂 LoadPoll 零尺寸传感器在数据未到时每 120ms 请求一帧把结果刷上屏。

// 对话框异步结果格：worker 线程 store/storeError（加锁），UI 线程 fetch/error 读；
// started/begin/reset 仅 UI 线程触碰（提交与复位都在构建/事件回调里）。
class DialogCell<T> {
    private let mtx = Mutex()
    private var result: ?T = None
    private var err: String = ""
    var started = false

    func store(v: T): Unit {
        synchronized(mtx) {
            result = Some(v)
        }
    }

    func storeError(e: String): Unit {
        synchronized(mtx) {
            err = e
        }
    }

    func fetch(): ?T {
        synchronized(mtx) {
            return result
        }
    }

    func error(): String {
        synchronized(mtx) {
            return err
        }
    }

    // 发起一轮加载：清上轮结果并标记已开始（UI 线程，提交 worker 前调用）。
    func begin(): Unit {
        synchronized(mtx) {
            result = None
            err = ""
        }
        started = true
    }

    // 对话框关闭后复位：下次打开重新拉取（列表可能已变）。
    func reset(): Unit {
        synchronized(mtx) {
            result = None
            err = ""
        }
        started = false
    }
}

// 加载轮询器：done 返回 false 时每 120ms 请求一帧（框架按需渲染，结果格不是 State，
// 需要定时帧源把异步到货的内容刷上屏）。
class LoadPoll <: Widget {
    private let done: () -> Bool

    public init(done: () -> Bool) {
        this.done = done
        emit(this)
    }

    public func measure(_: UiContext, _: Size): Size {
        Size.zero()
    }

    public func layout(_: UiContext, _: Rect): Unit {
        ()
    }

    public func draw(ctx: UiContext): Unit {
        if (!done()) {
            ctx.requestFrameAfter(120)
        }
    }

    public func handle(_: UiContext, _: UiEvent): Bool {
        false
    }
}

private func arcidListOf(arcid: String): ArrayList<String> {
    let ids = ArrayList<String>()
    ids.add(arcid)
    ids
}

// ---- 档案详情「加入合集」----

func addToTankDialog(model: AppModel, open: State<Bool>, arcid: String): Unit {
    let cell = rememberState<DialogCell<ArrayList<TankoubonInfo>>>("dlg.addtank.cell:${arcid}",
        {=> DialogCell<ArrayList<TankoubonInfo>>()}).value
    let newName = rememberState<String>("dlg.addtank.name:${arcid}", {=> ""})
    // 关闭后复位（下次打开重新拉取）。
    if (!open.value && cell.started) {
        cell.reset()
        newName.value = ""
    }
    // 打开即异步拉取合集列表（仅触发一次）。
    if (open.value && !cell.started) {
        submitAddToTankList(model, cell, arcid)
    }
    Modal(open, body: {
        => ZStack {
            VStack {
                Label(model.t("dialog.addToCollection")).fontSize(15.fp)
                if (cell.error().size > 0) {
                    HStack {
                        Label(model.t("dialog.loadFailed", params: [("error", cell.error())]))
                            .fontSize(12.fp)
                            .muted()
                            .maxLines(3)
                            .flex()
                        Button(model.t("dialog.retry"), {=> submitAddToTankList(model, cell, arcid)}).style(
                            ghostStyleOf(model))
                    }.spacing(10.vp).crossAxisAlignment(CrossAxisAlignment.Center).hug().fillWidth()
                } else {
                    match (cell.fetch()) {
                        case Some(tanks) =>
                            if (tanks.size == 0) {
                                Label(model.t("dialog.noCollectionsCreate")).fontSize(12.fp).muted()
                            } else {
                                ScrollView(key: "dlg.addtank.list:${arcid}") {
                                    VStack {
                                        for (t in tanks) {
                                            ClickArea(
                                                onClick: {
                                                    =>
                                                        open.value = false
                                                        model.addArchivesToTank(t.id, arcidListOf(arcid))
                                                }
                                            ) {
                                                ZStack {
                                                    HoverSensor("dlg.tankrow:${t.id}")
                                                    HoverFill("dlg.tankrow:${t.id}", 8.0)
                                                    HStack {
                                                        Label(t.name).fontSize(13.fp).maxLines(1).flex()
                                                        Label(
                                                            model.t("dialog.archiveCount",
                                                                params: [("count", "${t.archiveCount}")]))
                                                            .fontSize(11.fp)
                                                            .muted()
                                                    }
                                                        .spacing(8.vp)
                                                        .crossAxisAlignment(CrossAxisAlignment.Center)
                                                        .hug()
                                                        .fillWidth()
                                                        .padding(8.vp, 6.vp)
                                                }.alignment(Alignment.TopLeading)
                                            }
                                        }
                                    }.spacing(0.0).crossAxisAlignment(CrossAxisAlignment.Start).hug().fillWidth()
                                }.height(240.vp)
                            }
                        case None => Label(model.t("common.loading")).fontSize(12.fp).muted()
                    }
                }
                Label(model.t("dialog.newCollection")).fontSize(11.fp).muted()
                HStack {
                    TextField(newName, key: "dlg.addtank.field:${arcid}").flex()
                    Button(
                        model.t("dialog.createAndAdd"),
                        {
                            =>
                                let name = newName.value.trimAscii()
                                if (name.size > 0) {
                                    open.value = false
                                    model.createTankAndAdd(name, arcidListOf(arcid))
                                }
                        }
                    ).role(ButtonRole.Primary)
                }.spacing(8.vp).crossAxisAlignment(CrossAxisAlignment.Center).hug().fillWidth()
                HStack {
                    Spacer()
                    Button(model.t("common.cancel"), {=> open.value = false}).style(ghostStyleOf(model))
                }.hug().fillWidth()
            }.spacing(12.vp).crossAxisAlignment(CrossAxisAlignment.Start).hug().width(360.vp)
            LoadPoll({=> !open.value || cell.fetch().isSome() || cell.error().size > 0})
        }.alignment(Alignment.TopLeading)
    })
}

private func submitAddToTankList(model: AppModel, cell: DialogCell<ArrayList<TankoubonInfo>>, arcid: String): Unit {
    cell.begin()
    match (model.api) {
        case Some(a) =>
            // State 只在 UI 线程读取；跨线程共享结果通过 DialogCell 的 Mutex 保护。
            let lang = model.language.value
            let _ = model.worker.submit(
                "dlg.addtank:${arcid}",
                {
                    =>
                        try {
                            cell.store(a.listTankoubons(lang: lang))
                        } catch (e: Exception) {
                            cell.storeError(e.message)
                        }
                        return true
                }
            )
        case None => cell.storeError(model.t("dialog.notLoggedIn"))
    }
}

// ---- 合集详情「添加档案」----

func tankAddArchivesDialog(model: AppModel, open: State<Bool>, tankId: String): Unit {
    let cell = rememberState<DialogCell<ArrayList<SearchItem>>>("dlg.tankadd.cell:${tankId}",
        {=> DialogCell<ArrayList<SearchItem>>()}).value
    let query = rememberState<String>("dlg.tankadd.q:${tankId}", {=> ""})
    let picked = rememberState<HashSet<String>>("dlg.tankadd.picked:${tankId}", {=> HashSet<String>()})
    // 关闭后复位（下次打开重拉并清空已选/搜索词）。
    if (!open.value && cell.started) {
        cell.reset()
        query.value = ""
        picked.value = HashSet<String>()
    }
    // 打开即拉一轮（空筛选 = 全部档案）。
    if (open.value && !cell.started) {
        submitTankAddSearch(model, cell, tankId, "")
    }
    Modal(
        open,
        body: {
            =>
                let light = model.isLight()
                let accent = if (light) {
                    LANLU_L_ACCENT
                } else {
                    LANLU_ACCENT
                }
                let accentSoft = if (light) {
                    LANLU_L_ACCENT_SOFT
                } else {
                    LANLU_ACCENT_SOFT
                }
                // 已是成员的 id 不列出（合集不重复收录同一档案）。
                let memberIds = HashSet<String>()
                for (it in model.tankMembers.value) {
                    memberIds.add(it.arcid)
                }
                ZStack {
                    VStack {
                        Label(model.t("dialog.addArchives")).fontSize(15.fp)
                        HStack {
                            TextField(query, key: "dlg.tankadd.field:${tankId}").flex()
                            Button(model.t("dialog.search"), {
                                => submitTankAddSearch(model, cell, tankId, query.value.trimAscii())
                            }).style(ghostStyleOf(model))
                        }.spacing(8.vp).crossAxisAlignment(CrossAxisAlignment.Center).hug().fillWidth()
                        if (cell.error().size > 0) {
                            HStack {
                                Label(model.t("dialog.searchFailed", params: [("error", cell.error())]))
                                    .fontSize(12.fp)
                                    .muted()
                                    .maxLines(3)
                                    .flex()
                                Button(model.t("dialog.retry"), {
                                    => submitTankAddSearch(model, cell, tankId, query.value.trimAscii())
                                }).style(ghostStyleOf(model))
                            }.spacing(10.vp).crossAxisAlignment(CrossAxisAlignment.Center).hug().fillWidth()
                        } else {
                            match (cell.fetch()) {
                                case Some(items) =>
                                    let shown = ArrayList<SearchItem>()
                                    for (it in items) {
                                        if (it.arcid.size > 0 && !memberIds.contains(it.arcid)) {
                                            shown.add(it)
                                        }
                                    }
                                    if (shown.size == 0) {
                                        Label(model.t("dialog.noArchives")).fontSize(12.fp).muted()
                                    } else {
                                        ScrollView {
                                            VStack {
                                                for (it in shown) {
                                                    let on = picked.value.contains(it.arcid)
                                                    ClickArea(
                                                        onClick: {
                                                            =>
                                                                if (picked.value.contains(it.arcid)) {
                                                                    picked.value.remove(it.arcid)
                                                                } else {
                                                                    picked.value.add(it.arcid)
                                                                }
                                                                picked.value = picked.value
                                                        }
                                                    ) {
                                                        HStack {
                                                            VStack {
                                                                if (on) {
                                                                    Icon(IconName.Check, size: 12.vp, color: accent)
                                                                }
                                                            }
                                                                .crossAxisAlignment(CrossAxisAlignment.Center)
                                                                .hug()
                                                                .width(18.vp)
                                                            Label(it.title).fontSize(13.fp).maxLines(1).flex()
                                                            Label(
                                                                model.t("detail.pages",
                                                                    params: [("count", "${it.pagecount}")]))
                                                                .fontSize(11.fp)
                                                                .muted()
                                                        }
                                                            .spacing(8.vp)
                                                            .crossAxisAlignment(CrossAxisAlignment.Center)
                                                            .hug()
                                                            .fillWidth()
                                                            .padding(8.vp, 6.vp)
                                                            .background(if (on) {
                                                                accentSoft
                                                            } else {
                                                                Color.rgba(0, 0, 0, 0)
                                                            }, 8.vp)
                                                    }
                                                }
                                            }
                                                .spacing(2.0)
                                                .crossAxisAlignment(CrossAxisAlignment.Start)
                                                .hug()
                                                .fillWidth()
                                        }.height(300.vp)
                                    }
                                case None => Label(model.t("dialog.searching")).fontSize(12.fp).muted()
                            }
                        }
                        HStack {
                            Spacer()
                            Button(model.t("common.cancel"), {=> open.value = false}).style(ghostStyleOf(model))
                            Button(model.t("dialog.addCount", params: [("count", "${picked.value.size}")]), {
                                => if (picked.value.size > 0) {
                                    open.value = false
                                    let ids = ArrayList<String>()
                                    for (id in picked.value) {
                                        ids.add(id)
                                    }
                                    model.addArchivesToTank(tankId, ids)
                                }
                            }).role(ButtonRole.Primary)
                        }.spacing(8.vp).crossAxisAlignment(CrossAxisAlignment.Center).hug().fillWidth()
                    }.spacing(12.vp).crossAxisAlignment(CrossAxisAlignment.Start).hug().width(420.vp)
                    LoadPoll({=> !open.value || cell.fetch().isSome() || cell.error().size > 0})
                }.alignment(Alignment.TopLeading)
        }
    )
}

// 发起一轮对话框内搜索：结果直接写格（worker 去重兜底，连点搜索只跑一个在途）。
private func submitTankAddSearch(model: AppModel, cell: DialogCell<ArrayList<SearchItem>>, tankId: String,
    filter: String): Unit {
    cell.begin()
    match (model.api) {
        case Some(a) =>
            let lang = model.language.value
            let _ = model.worker.submit(
                "dlg.tankadd:${tankId}",
                {
                    =>
                        try {
                            let q = SearchQuery()
                            q.filter = filter
                            q.pageSize = 100
                            q.lang = lang
                            cell.store(a.search(q).items)
                        } catch (e: Exception) {
                            cell.storeError(e.message)
                        }
                        return true
                }
            )
        case None => cell.storeError(model.t("dialog.notLoggedIn"))
    }
}
