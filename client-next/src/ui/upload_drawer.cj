package lanlu_client_next.ui

import cui.*
import lanlu_client_next.app.*
import std.collection.ArrayList

private let UPLOAD_DRAWER_WIDTH: Float32 = 560.0

public func uploadDrawer(window: SdlWindow, model: AppModel): Unit {
    Drawer(model.uploadDrawerOpen, edge: DrawerEdge.Right, width: UPLOAD_DRAWER_WIDTH,
        onDismiss: {=> model.closeUploadDrawer()}) {
        VStack {
            uploadHeader(model)
            Divider()
            VStack {
                SegmentedControl(["上传档案", "在线下载"], model.uploadTabIndex, key: "upload:tabs").fillWidth()
                if (model.uploadTabIndex.value == 0) {
                    uploadTabContent(window, model)
                } else {
                    downloadTabContent(model)
                }
            }.spacing(14.vp).crossAxisAlignment(CrossAxisAlignment.Start).padding(20.vp).fillHeight()
        }.spacing(0.vp).fillHeight()
    }
}

private func uploadTabContent(window: SdlWindow, model: AppModel): Unit {
    uploadCategoryPicker(model)
    ArchiveDropZone(model, {=> openArchivePicker(window, model)}).height(150.vp).fillWidth()
    uploadListHeader(model)
    ScrollView(key: "archive-upload-list") {
        VStack {
            uploadListContent(model)
        }.spacing(10.vp).crossAxisAlignment(CrossAxisAlignment.Start).hug().fillWidth()
    }.flex()
    Label("支持 ZIP、RAR、7Z、TAR、PDF、EPUB、CBZ/CBR 及分卷档案").fontSize(10.5.fp).muted()
}

private func uploadListContent(model: AppModel): Unit {
    if (model.uploadFiles.value.size == 0) {
        VStack {
            Icon(IconName.NewDocument, size: 30.vp, color: Some(if (model.isLight()) {
                LANLU_L_MUTED
            } else {
                LANLU_MUTED
            }))
            Label("尚未添加档案").fontSize(13.fp).muted()
        }.spacing(8.vp).crossAxisAlignment(CrossAxisAlignment.Center).padding(28.vp).fillWidth()
    } else {
        for (item in orderedUploads(model.uploadFiles.value)) {
            uploadFileCard(model, item)
        }
    }
}

private func downloadTabContent(model: AppModel): Unit {
    uploadCategoryPicker(model)
    VStack {
        Label("下载链接 · 每行一个").fontSize(12.fp)
        TextArea(model.downloadUrlsText, key: "download:urls").height(110.vp).fillWidth()
    }.spacing(7.vp).crossAxisAlignment(CrossAxisAlignment.Start).hug().fillWidth()
    Button("添加下载任务", {=> model.addDownloadTasks()}).role(ButtonRole.Primary).fillWidth()
    downloadListHeader(model)
    ScrollView(key: "download-task-list") {
        VStack {
            downloadListContent(model)
        }.spacing(10.vp).crossAxisAlignment(CrossAxisAlignment.Start).hug().fillWidth()
    }.flex()
    Label("链接将由服务器下载并入库到所选分类").fontSize(10.5.fp).muted()
}

private func downloadListContent(model: AppModel): Unit {
    if (model.downloadTasks.value.size == 0) {
        VStack {
            Icon(IconName.Download, size: 30.vp, color: Some(if (model.isLight()) {
                LANLU_L_MUTED
            } else {
                LANLU_MUTED
            }))
            Label("尚未添加下载任务").fontSize(13.fp).muted()
        }.spacing(8.vp).crossAxisAlignment(CrossAxisAlignment.Center).padding(28.vp).fillWidth()
    } else {
        for (item in orderedDownloads(model.downloadTasks.value)) {
            downloadTaskCard(model, item)
        }
    }
}

private func uploadHeader(model: AppModel): Unit {
    HStack {
        Icon(IconName.Upload, size: 20.vp)
        VStack {
            Label("上传档案").fontSize(17.fp)
            Label("分片上传到 Lanlu 书库").fontSize(10.5.fp).muted()
        }.spacing(2.vp).crossAxisAlignment(CrossAxisAlignment.Start).hug()
        Spacer()
        IconButton(IconName.Close, style: Some(ghostStyleOf(model)), onClick: {=> model.closeUploadDrawer()}).key(
            "upload:close")
    }.spacing(10.vp).crossAxisAlignment(CrossAxisAlignment.Center).hug().padding(18.vp, 20.vp).fillWidth()
}

private func uploadCategoryPicker(model: AppModel): Unit {
    VStack {
        HStack {
            Label("目标分类").fontSize(12.fp)
            Label("必选").fontSize(10.fp).foregroundColor(if (model.isLight()) {
                LANLU_L_ACCENT
            } else {
                LANLU_ACCENT
            })
        }.spacing(6.vp).hug()
        if (model.categories.value.size > 0) {
            Dropdown(uploadCategoryLabels(model), model.uploadCategoryIndex, key: "upload:category").fillWidth()
        } else {
            HStack {
                Spinner(14.0, if (model.isLight()) {
                    LANLU_L_ACCENT
                } else {
                    LANLU_ACCENT
                })
                Label("正在加载可用分类…").fontSize(11.fp).muted()
            }.spacing(8.vp).hug().padding(10.vp, 12.vp).fillWidth().background(if (model.isLight()) {
                LANLU_L_FIELD
            } else {
                LANLU_FIELD
            }, 10.vp)
        }
        Label("新档案将在服务器端处理完成后出现在所选分类中").fontSize(10.5.fp).muted()
    }.spacing(7.vp).crossAxisAlignment(CrossAxisAlignment.Start).hug().fillWidth()
}

private func uploadCategoryLabels(model: AppModel): Array<String> {
    let labels = ArrayList<String>()
    for (category in model.categories.value) {
        labels.add("${category.name}  ·  ${category.archiveCount} 项")
    }
    labels.toArray()
}

private func openArchivePicker(window: SdlWindow, model: AppModel): Unit {
    if (model.categories.value.size == 0) {
        model.showError("暂无可用分类")
        return
    }
    let request = FileDialogs.openFile(
        options: FileDialogOptions(
            filters: [
                FileDialogFilter("档案文件", "zip;rar;7z;tar;gz;pdf;epub;mobi;cbz;cbr;cb7;cbt;001;z01;r00"),
                FileDialogFilter("所有文件", "*")
            ],
            allowMany: true
        ),
        window: Some(window)
    )
    model.beginUploadFileSelection(request)
}

private func uploadListHeader(model: AppModel): Unit {
    let (success, failed, total) = uploadCounts(model.uploadFiles.value)
    HStack {
        Label("文件列表").fontSize(13.fp)
        Label("成功 ${success} / 失败 ${failed} / 共 ${total}").fontSize(10.5.fp).muted()
        Spacer()
        if (success > 0) {
            Button("清除已完成", {=> model.clearCompletedUploads()}).style(ghostStyleOf(model))
        }
        if (total > 0) {
            Button("清除全部", {=> model.clearUploads()}).style(ghostStyleOf(model))
        }
    }.spacing(8.vp).crossAxisAlignment(CrossAxisAlignment.Center).hug().fillWidth()
}

private func uploadCounts(files: ArrayList<UploadFileItem>): (Int64, Int64, Int64) {
    var success: Int64 = 0
    var failed: Int64 = 0
    for (item in files) {
        if (item.status == "success") {
            success += 1
        } else if (item.status == "error" || item.status == "fileExists") {
            failed += 1
        }
    }
    (success, failed, files.size)
}

private func orderedUploads(files: ArrayList<UploadFileItem>): ArrayList<UploadFileItem> {
    let result = ArrayList<UploadFileItem>()
    for (item in files) {
        if (item.status == "fileExists") {
            result.add(item)
        }
    }
    for (item in files) {
        if (item.status == "queued" || item.status == "uploading" || item.status == "processing") {
            result.add(item)
        }
    }
    for (item in files) {
        if (item.status == "success" || item.status == "error") {
            result.add(item)
        }
    }
    result
}

private func downloadListHeader(model: AppModel): Unit {
    let (success, failed, total) = downloadCounts(model.downloadTasks.value)
    HStack {
        Label("下载任务").fontSize(13.fp)
        Label("成功 ${success} / 失败 ${failed} / 共 ${total}").fontSize(10.5.fp).muted()
        Spacer()
        if (success > 0) {
            Button("清除已完成", {=> model.clearCompletedDownloads()}).style(ghostStyleOf(model))
        }
        if (total > 0) {
            Button("清除全部", {=> model.clearDownloads()}).style(ghostStyleOf(model))
        }
    }.spacing(8.vp).crossAxisAlignment(CrossAxisAlignment.Center).hug().fillWidth()
}

private func downloadCounts(tasks: ArrayList<DownloadTaskItem>): (Int64, Int64, Int64) {
    var success: Int64 = 0
    var failed: Int64 = 0
    for (item in tasks) {
        if (item.status == "success") {
            success += 1
        } else if (item.status == "error") {
            failed += 1
        }
    }
    (success, failed, tasks.size)
}

private func orderedDownloads(tasks: ArrayList<DownloadTaskItem>): ArrayList<DownloadTaskItem> {
    let result = ArrayList<DownloadTaskItem>()
    for (item in tasks) {
        if (item.status == "queued" || item.status == "downloading" || item.status == "processing") {
            result.add(item)
        }
    }
    for (item in tasks) {
        if (item.status == "success" || item.status == "error") {
            result.add(item)
        }
    }
    result
}

private func downloadTaskCard(model: AppModel, item: DownloadTaskItem): Unit {
    let cardBg = if (model.isLight()) {
        LANLU_L_PANEL
    } else {
        LANLU_FIELD
    }
    VStack {
        HStack {
            Icon(IconName.Download, size: 18.vp).foregroundColor(uploadStatusColor(model, item.status))
            VStack {
                Label(item.url).fontSize(12.5.fp).maxLines(1).tight()
            }.spacing(2.vp).crossAxisAlignment(CrossAxisAlignment.Start).hug().flex()
            Label(uploadStatusLabel(item.status))
                .fontSize(10.5.fp)
                .foregroundColor(uploadStatusColor(model, item.status))
        }.spacing(9.vp).crossAxisAlignment(CrossAxisAlignment.Center).hug().fillWidth()

        if (item.status == "queued" || item.status == "downloading" || item.status == "processing") {
            HStack {
                ProgressTrack(item.progress, 6.0).flex()
                Label("${item.progress}%").fontSize(10.fp).muted()
            }.spacing(10.vp).crossAxisAlignment(CrossAxisAlignment.Center).hug().fillWidth()
        }
        if (item.message.size > 0) {
            Label(item.message).fontSize(10.5.fp).muted().maxLines(2).tight().fillWidth()
        }
        if (item.status == "error" || item.status == "success") {
            HStack {
                Spacer()
                Button("移除", {=> model.removeDownloadTask(item.id)}).style(ghostStyleOf(model))
            }.spacing(8.vp).hug().fillWidth()
        }
    }
        .spacing(9.vp)
        .crossAxisAlignment(CrossAxisAlignment.Start)
        .padding(12.vp, 14.vp)
        .background(cardBg, 12.vp)
        .fillWidth()
}

private func uploadFileCard(model: AppModel, item: UploadFileItem): Unit {
    let cardBg = if (model.isLight()) {
        LANLU_L_PANEL
    } else {
        LANLU_FIELD
    }
    VStack {
        HStack {
            Icon(IconName.NewDocument, size: 18.vp).foregroundColor(uploadStatusColor(model, item.status))
            VStack {
                Label(item.name).fontSize(12.5.fp).maxLines(1).tight()
                Label(formatFileSize(item.size)).fontSize(10.fp).muted()
            }.spacing(2.vp).crossAxisAlignment(CrossAxisAlignment.Start).hug().flex()
            Label(uploadStatusLabel(item.status))
                .fontSize(10.5.fp)
                .foregroundColor(uploadStatusColor(model, item.status))
        }.spacing(9.vp).crossAxisAlignment(CrossAxisAlignment.Center).hug().fillWidth()

        if (item.status == "queued" || item.status == "uploading" || item.status == "processing") {
            HStack {
                ProgressTrack(item.progress, 6.0).flex()
                Label("${item.progress}%").fontSize(10.fp).muted()
            }.spacing(10.vp).crossAxisAlignment(CrossAxisAlignment.Center).hug().fillWidth()
        }
        if (item.message.size > 0) {
            Label(item.message).fontSize(10.5.fp).muted().maxLines(2).tight().fillWidth()
        }
        if (item.status == "fileExists" || item.status == "error" || item.status == "success") {
            HStack {
                Spacer()
                if (item.status == "fileExists") {
                    Button("强制覆盖", {=> model.retryUpload(item.id, overwrite: true)}).role(ButtonRole.Primary)
                } else if (item.status == "error") {
                    Button("重试", {=> model.retryUpload(item.id)}).role(ButtonRole.Primary)
                }
                Button("移除", {=> model.removeUpload(item.id)}).style(ghostStyleOf(model))
            }.spacing(8.vp).hug().fillWidth()
        }
    }
        .spacing(9.vp)
        .crossAxisAlignment(CrossAxisAlignment.Start)
        .padding(12.vp, 14.vp)
        .background(cardBg, 12.vp)
        .fillWidth()
}

private func uploadStatusLabel(status: String): String {
    match (status) {
        case "queued" => "排队中"
        case "uploading" => "上传中"
        case "downloading" => "下载中"
        case "processing" => "处理中"
        case "success" => "已完成"
        case "fileExists" => "文件已存在"
        case "error" => "失败"
        case _ => status
    }
}

private func uploadStatusColor(model: AppModel, status: String): Color {
    match (status) {
        case "success" => LANLU_SUCCESS
        case "error" => LANLU_DANGER
        case "fileExists" | "queued" | "uploading" | "downloading" | "processing" =>
            if (model.isLight()) {
                LANLU_L_ACCENT
            } else {
                LANLU_ACCENT
            }
        case _ =>
            if (model.isLight()) {
                LANLU_L_MUTED
            } else {
                LANLU_MUTED
            }
    }
}

private func formatFileSize(size: Int64): String {
    if (size < 1024) {
        return "${size} B"
    }
    if (size < 1024 * 1024) {
        return "${size / 1024} KB"
    }
    let tenths = size * 10 / (1024 * 1024)
    "${tenths / 10}.${tenths % 10} MB"
}

// 系统文件拖放目标：DropFile 自带窗口逻辑坐标，Drawer 会把事件路由到内容树；
// 这里按自身布局矩形命中，避免拖到列表卡片也被误判为添加文件。
private class ArchiveDropZone <: Widget {
    private let model: AppModel
    private let onBrowse: () -> Unit
    private let hoverId = "upload:drop-zone"
    private var frame = Rect.zero()

    public init(model: AppModel, onBrowse: () -> Unit) {
        this.model = model
        this.onBrowse = onBrowse
        emit(this)
    }

    public func measure(_: UiContext, available: Size): Size {
        Size(available.w, 150.0)
    }

    public func layout(_: UiContext, rect: Rect): Unit {
        frame = rect
    }

    public func draw(ctx: UiContext): Unit {
        let hovered = ctx.isHovered(hoverId)
        let accent = if (model.isLight()) {
            LANLU_L_ACCENT
        } else {
            LANLU_ACCENT
        }
        let edge = if (hovered) {
            accent
        } else {
            ctx.theme.panelEdge
        }
        ctx.renderer.fillRoundedRect(frame, 12.0, if (model.isLight()) {
            LANLU_L_FIELD
        } else {
            LANLU_FIELD
        })
        drawDashedBorder(ctx, edge)
        let iconRect = Rect(frame.centerX() - 12.0, frame.y + 25.0, 24.0, 24.0)
        drawIcon(ctx.renderer, IconName.Upload, iconRect, if (hovered) {
            accent
        } else {
            ctx.theme.mutedText
        })
        drawCenteredText(ctx, "拖放档案到这里，或点击选择文件", frame.y + 62.0, 13.0, if (hovered) {
            accent
        } else {
            ctx.theme.text
        })
        drawCenteredText(ctx, "支持多选 · 自动按 10 MiB 分片上传", frame.y + 87.0, 10.5, ctx.theme.mutedText)
    }

    private func drawDashedBorder(ctx: UiContext, color: Color): Unit {
        let pen = Pen(width: 1.0, color: color)
        let inset = frame.inset(0.5)
        let dash: Float32 = 8.0
        let gap: Float32 = 5.0
        var x = inset.x + 12.0
        while (x < inset.right() - 12.0) {
            ctx.renderer.strokeLine(x, inset.y, min(x + dash, inset.right() - 12.0), inset.y, pen)
            ctx.renderer.strokeLine(x, inset.bottom(), min(x + dash, inset.right() - 12.0), inset.bottom(), pen)
            x += dash + gap
        }
        var y = inset.y + 12.0
        while (y < inset.bottom() - 12.0) {
            ctx.renderer.strokeLine(inset.x, y, inset.x, min(y + dash, inset.bottom() - 12.0), pen)
            ctx.renderer.strokeLine(inset.right(), y, inset.right(), min(y + dash, inset.bottom() - 12.0), pen)
            y += dash + gap
        }
    }

    private func drawCenteredText(ctx: UiContext, text: String, y: Float32, pointSize: Float32, color: Color): Unit {
        let width = ctx.renderer.textWidth(text, pointSize: pointSize)
        ctx.renderer.text(text, frame.centerX() - width / 2.0, y, color, pointSize: pointSize)
    }

    public func handle(ctx: UiContext, event: UiEvent): Bool {
        match (event) {
            case UiEvent.MouseMove(x, y) =>
                if (frame.contains(x, y)) {
                    ctx.claimHover(hoverId, CursorShape.Interactive)
                }
            case UiEvent.MouseUp(MouseButton.Left, x, y) =>
                if (frame.contains(x, y)) {
                    onBrowse()
                    return true
                }
            case UiEvent.DropFile(path, x, y) =>
                if (frame.contains(x, y)) {
                    model.addUploadPath(path)
                    return true
                }
            case _ => ()
        }
        false
    }
}
