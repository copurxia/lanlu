package lanlu_client_next.ui

import cui.*
import lanlu_client_next.app.*
import lanlu_client_next.net.{PageInfo, SearchItem, percentEncode}
import std.collection.ArrayList

// metadata-edit-redesign.html：合集 → 档案 → 页的单一可下钻编辑器。弹窗保持
// 1080×700 设计比例；窗口较小时由 Modal 按 94%×92% 自动收束。
public func metadataEditOverlay(model: AppModel): Unit {
    Modal(model.metadataEditorOpen, onDismiss: {=> model.closeMetadataEditor()}, blurBackdrop: true, padding: 0.0,
        maxWidth: 1080.0, maxHeightRatio: 0.92, body: {
            => metadataDialog(model)
        })
}

private func metadataDialog(model: AppModel): Unit {
    VStack {
        metadataHeader(model)
        HStack {
            ScrollView(key: "metadata-form") {
                metadataForm(model)
            }.flex()
            if (model.metadataEditorLevel.value < 2) {
                Divider(axis: Axis.Vertical)
                metadataSide(model)
            }
        }.spacing(0.0).flex()
        Divider()
        metadataFooter(model)
    }.spacing(0.0).width(1060.vp).height(680.vp)
}

private func metadataHeader(model: AppModel): Unit {
    let level = model.metadataEditorLevel.value
    let crumbs = ArrayList<String>()
    if (model.metadataEditorTankId.size > 0) {
        crumbs.add("合集 · ${model.metadataEditorTankTitle}")
    }
    if (level >= 1) {
        crumbs.add(if (level == 1) {
            model.metadataTitle.value
        } else {
            "档案 · ${model.metadataEditorArchiveTitle}"
        })
    }
    if (level == 2) {
        let pageNo = "P.${model.metadataEditorPageIndex + 1}"
        crumbs.add(if (model.metadataTitle.value.size == 0 || model.metadataTitle.value == pageNo) {
            pageNo
        } else {
            "${pageNo} · ${model.metadataTitle.value}"
        })
    }
    HStack {
        Breadcrumb(crumbs.toArray(), onSelect: {
            i => if (model.metadataEditorTankId.size > 0 && i == 0) {
                model.metadataEditorBackTo(0)
            } else {
                model.metadataEditorBackTo(1)
            }
        }, key: "metadata-crumbs")
        Spacer()
        Badge(metadataLevelLabel(level), kind: if (level == 2) {
            BadgeKind.Info
        } else {
            BadgeKind.Accent
        })
        IconButton(IconName.Close, style: Some(ghostStyleOf(model)), onClick: {
            => model.closeMetadataEditor()
        }).key("metadata:close")
    }.spacing(10.vp).crossAxisAlignment(CrossAxisAlignment.Center).hug().fillWidth().padding(18.vp, 12.vp)
}

private func metadataLevelLabel(level: Int64): String {
    if (level == 0) {
        "合集 TANKOUBON"
    } else if (level == 1) {
        "档案 ARCHIVE"
    } else {
        "页 PAGE"
    }
}

private func metadataForm(model: AppModel): Unit {
    let level = model.metadataEditorLevel.value
    VStack {
        if (level < 2) {
            metadataAssets(model)
        }
        VStack {
            if (level == 2) {
                pagePreview(model)
            }
            editField("标题", "", model.metadataTitle, model, "metadata.title")
            VStack {
                HStack {
                    Label("简介").fontSize(11.fp).muted()
                    Label("支持多行文本，由元数据插件抓取或手动填写").fontSize(10.fp).muted()
                }.spacing(8.vp).hug()
                TextArea(dirtyText(model, model.metadataDescription), key: "metadata.description")
                    .height(86.vp)
                    .fillWidth()
            }.spacing(6.vp).crossAxisAlignment(CrossAxisAlignment.Start).hug().fillWidth()
            HStack {
                Flexible {dateField(model)}
                if (level == 1 && model.metadataEditorTankId.size > 0) {
                    Flexible {editField("卷号", "合集内排序", model.metadataVolumeNo, model, "metadata.volume")}
                }
                if (level == 2) {
                    Flexible {
                        editField("排序", "影响阅读/列表顺序", model.metadataOrderIndex, model, "metadata.order")
                    }
                }
            }.spacing(14.vp).hug().fillWidth()
            if (level == 2) {
                Switch(
                    "在文件列表中隐藏该页（阅读时仍可达）",
                    model.metadataHiddenInFiles.project(
                        get: {v => v},
                        set: {
                            _, v =>
                                model.metadataEditorDirty.value = true
                                v
                        }
                    )
                ).key("metadata.hidden")
                pageAttachments(model)
            } else {
                metadataTags(model)
            }
            metadataPlugin(model)
        }
            .spacing(16.vp)
            .crossAxisAlignment(CrossAxisAlignment.Start)
            .hug()
            .fillWidth()
            .padding(20.vp, if (level == 2) {
                16.vp
            } else {
                0.vp
            })
    }.spacing(0.0).crossAxisAlignment(CrossAxisAlignment.Start).hug().fillWidth()
}

private func dateField(model: AppModel): Unit {
    VStack {
        HStack {
            Label("发布日期").fontSize(11.fp).muted()
            Label("YYYY-MM-DD").fontSize(10.fp).muted()
        }.spacing(7.vp).hug()
        TextField(dirtyText(model, model.metadataReleaseAt), trailingIcon: Some(IconName.Calendar),
            key: "metadata.release").fillWidth()
    }.spacing(6.vp).crossAxisAlignment(CrossAxisAlignment.Start).hug().fillWidth()
}

private func metadataAssets(model: AppModel): Unit {
    let coverId = metadataCoverId(model)
    let field = if (model.isLight()) {
        LANLU_L_FIELD
    } else {
        LANLU_FIELD
    }
    VStack {
        ZStack {
            VStack {
                if (coverId > 0) {
                    remoteImage(model, "asset:${coverId}", "/api/assets/${coverId}", 760.vp, 168.vp)
                } else {
                    VStack {}.fillWidth().height(168.vp).background(field)
                }
                Spacer()
            }.spacing(0.0).fillWidth().height(216.vp)
            MetadataBackdropShade()
            HStack {
                if (coverId > 0) {
                    remoteImage(model, "asset:${coverId}", "/api/assets/${coverId}", 112.vp, 168.vp, radius: 12.0)
                } else {
                    VStack {
                        Icon(IconName.Image, size: 30.vp)
                    }
                        .mainAxisAlignment(MainAxisAlignment.Center)
                        .crossAxisAlignment(CrossAxisAlignment.Center)
                        .width(112.vp)
                        .height(168.vp)
                        .background(field, 12.vp)
                }
                Spacer()
            }.spacing(0.0).padding(20.vp, 48.vp, 0.vp, 0.vp).fillWidth().height(216.vp)
            MetadataAssetsChrome(model)
        }.alignment(Alignment.TopLeading).fillWidth().height(216.vp)
        Spacer().height(16.vp)
    }.spacing(0.0).hug().fillWidth()
}

private class MetadataBackdropShade <: Widget {
    private var frame = Rect.zero()

    public init() {
        emit(this)
    }

    public func measure(_: UiContext, available: Size): Size {
        Size(available.w, 216.0)
    }

    public func layout(_: UiContext, rect: Rect): Unit {
        frame = rect
    }

    public func draw(ctx: UiContext): Unit {
        let panel = ctx.theme.panel
        let top = panel.withAlpha(0)
        ctx.renderer.fillVerticalGradient(Rect(frame.x, frame.y + 72.0, 20.0, 96.0), top, panel)
        ctx.renderer.fillVerticalGradient(Rect(frame.x + 132.0, frame.y + 72.0, frame.w - 132.0, 96.0), top, panel)
    }

    public func handle(_: UiContext, _: UiEvent): Bool {
        false
    }
}

// MetadataAssetsEditor 交互层：横幅、封面与 clearlogo 各自拥有独立 hover 热区，
// 操作按钮仅悬停时出现，避免 clearlogo 被常驻按钮卡遮住。
private class MetadataAssetsChrome <: Widget {
    private let model: AppModel
    private var frame = Rect.zero()

    public init(model: AppModel) {
        this.model = model
        emit(this)
    }

    public func measure(_: UiContext, available: Size): Size {
        Size(available.w, 216.0)
    }

    public func layout(_: UiContext, rect: Rect): Unit {
        frame = rect
    }

    public func draw(ctx: UiContext): Unit {
        let backdrop = backdropRect()
        let cover = coverRect()
        let logo = logoRect()
        let onMedia = Color.rgb(242, 242, 244)
        let tag = Rect(backdrop.x + 12.0, backdrop.y + 10.0, 96.0, 22.0)

        ctx.renderer.fillRoundedRect(tag, 6.0, Color.rgba(0, 0, 0, 142))
        ctx.renderer.textCenter("BACKDROP 横幅", tag, onMedia, pointSize: 10.5)
        ctx.renderer.strokeRoundedRect(cover.inset(1.0), 12.0, Pen(width: 2.0, color: Color.rgba(255, 255, 255, 220)))
        drawDashedLogoBorder(ctx.renderer, logo, Color.rgba(255, 255, 255, 92))
        ctx.renderer.textCenter("CLEARLOGO 标志", logo, onMedia.withAlpha(166), pointSize: 10.5)

        let slot = hoveredSlot(ctx.mouseX, ctx.mouseY)
        if (slot >= 0) {
            drawSlotOverlay(ctx, slot)
        }
    }

    public func handle(ctx: UiContext, event: UiEvent): Bool {
        match (event) {
            case UiEvent.MouseMove(x, y) =>
                let slot = hoveredSlot(x, y)
                if (slot >= 0) {
                    ctx.claimHover("metadata:asset:${slot}", CursorShape.Interactive)
                }
            case UiEvent.MouseUp(MouseButton.Left, x, y) =>
                let slot = hoveredSlot(x, y)
                if (slot >= 0) {
                    let buttons = actionRects(slot)
                    for (i in 0..buttons.size) {
                        if (buttons[i].contains(x, y)) {
                            model.todoToast(assetActionLabel(slot, i))
                            return true
                        }
                    }
                }
            case _ => ()
        }
        false
    }

    private func backdropRect(): Rect {
        Rect(frame.x, frame.y, frame.w, 168.0)
    }

    private func coverRect(): Rect {
        Rect(frame.x + 20.0, frame.y + 48.0, 112.0, 168.0)
    }

    private func logoRect(): Rect {
        Rect(frame.right() - 214.0, frame.y + 94.0, 190.0, 56.0)
    }

    private func hoveredSlot(x: Float32, y: Float32): Int64 {
        if (coverRect().contains(x, y)) {
            1
        } else if (logoRect().contains(x, y)) {
            2
        } else if (backdropRect().contains(x, y)) {
            0
        } else {
            -1
        }
    }

    private func slotRect(slot: Int64): Rect {
        if (slot == 1) {
            coverRect()
        } else if (slot == 2) {
            logoRect()
        } else {
            backdropRect()
        }
    }

    private func actionRects(slot: Int64): Array<Rect> {
        let box = slotRect(slot)
        let extent: Float32 = if (slot == 0) {
            40.0
        } else {
            34.0
        }
        let count: Int64 = if (slot == 0) {
            3
        } else {
            2
        }
        let gap: Float32 = 10.0
        let total = Float32(count) * extent + Float32(count - 1) * gap
        let left = box.centerX() - total / 2.0
        let top = box.centerY() - extent / 2.0
        let out = ArrayList<Rect>()
        for (i in 0..count) {
            out.add(Rect(left + Float32(i) * (extent + gap), top, extent, extent))
        }
        out.toArray()
    }

    private func drawSlotOverlay(ctx: UiContext, slot: Int64): Unit {
        let box = slotRect(slot)
        ctx.renderer.fillRoundedRect(box, if (slot == 0) {
            0.0
        } else {
            10.0
        }, Color.rgba(0, 0, 0, 100))
        let buttons = actionRects(slot)
        for (i in 0..buttons.size) {
            let button = buttons[i]
            let hovered = button.contains(ctx.mouseX, ctx.mouseY)
            ctx.renderer.fillRoundedRect(button, button.w / 2.0, if (hovered) {
                ctx.theme.accent
            } else {
                Color.rgba(0, 0, 0, 158)
            })
            ctx
                .renderer
                .strokeRoundedRect(button.inset(0.5), button.w / 2.0, Pen(width: 1.0, color: Color.rgba(255, 255, 255,
                    74)))
            drawIcon(ctx.renderer, assetActionIcon(slot, i), button.inset(if (slot == 0) {
                11.0
            } else {
                9.0
            }), if (hovered) {
                Color.rgb(26, 18, 6)
            } else {
                Color.rgb(242, 242, 244)
            })
        }
    }

    private func assetActionIcon(slot: Int64, index: Int64): IconName {
        if (slot == 0 && index == 1) {
            IconName.Image
        } else if (index == (if (slot == 0) {
            2
        } else {
            1
        })) {
            IconName.Trash
        } else {
            IconName.Upload
        }
    }

    private func assetActionLabel(slot: Int64, index: Int64): String {
        if (index == (if (slot == 0) {
            2
        } else {
            1
        })) {
            "清除资产"
        } else if (slot == 0 && index == 1) {
            "从页面选择横幅"
        } else {
            "上传资产"
        }
    }

    private func drawDashedLogoBorder(renderer: Renderer, rect: Rect, color: Color): Unit {
        let pen = Pen(width: 1.0, color: color)
        let dash: Float32 = 5.0
        let step: Float32 = 9.0
        var x = rect.x + 8.0
        while (x < rect.right() - 8.0) {
            let x2 = min(x + dash, rect.right() - 8.0)
            renderer.strokeLine(x, rect.y, x2, rect.y, pen)
            renderer.strokeLine(x, rect.bottom(), x2, rect.bottom(), pen)
            x += step
        }
        var y = rect.y + 8.0
        while (y < rect.bottom() - 8.0) {
            let y2 = min(y + dash, rect.bottom() - 8.0)
            renderer.strokeLine(rect.x, y, rect.x, y2, pen)
            renderer.strokeLine(rect.right(), y, rect.right(), y2, pen)
            y += step
        }
    }
}

private func metadataCoverId(model: AppModel): Int64 {
    if (model.metadataEditorLevel.value == 0) {
        match (model.tank.value) {
            case Some(t) => t.coverAssetId
            case None => 0
        }
    } else {
        match (model.metadataEditorArchiveMeta.value) {
            case Some(m) => m.coverAssetId
            case None => 0
        }
    }
}

private func pagePreview(model: AppModel): Unit {
    let pages = model.metadataEditorPages.value
    if (model.metadataEditorPageIndex < 0 || model.metadataEditorPageIndex >= pages.size) {
        return
    }
    let page = pages[model.metadataEditorPageIndex]
    let title = pageDisplayTitle(page, model.metadataEditorPageIndex)
    HStack {
        ZStack {
            remoteImage(model, pageThumbnailKey(model, page), pageThumbnailUrl(model, page), 220.vp, 138.vp,
                radius: 10.0)
            Badge("P.${model.metadataEditorPageIndex + 1}", kind: BadgeKind.Info).padding(8.vp)
        }.alignment(Alignment.TopLeading).width(220.vp).height(138.vp)
        VStack {
            Label(title).fontSize(14.fp).maxLines(1)
            if (page.description.trimAscii().size > 0) {
                Label(page.description).fontSize(11.fp).muted().wrap().maxLines(2)
            } else {
                Label("暂无页面简介").fontSize(11.fp).muted()
            }
            if (page.releaseAt.trimAscii().size > 0) {
                Label("发布日期：${page.releaseAt.trimAscii()}").fontSize(10.fp).muted().maxLines(1)
            }
            Label(if (page.thumbAssetId > 0) {
                "已使用自定义缩略图"
            } else {
                "使用页面自动缩略图"
            }).fontSize(11.fp).foregroundColor(if (page.thumbAssetId > 0) {
                Color.rgb(34, 158, 92)
            } else {
                if (model.isLight()) {
                    LANLU_L_MUTED
                } else {
                    LANLU_MUTED
                }
            })
            Label("条目路径：${page.sourcePath}").fontSize(10.fp).muted().maxLines(1)
            Button("替换缩略图", {=> model.todoToast("缩略图上传")}).style(ghostStyleOf(model))
        }.spacing(8.vp).crossAxisAlignment(CrossAxisAlignment.Start).flex()
    }.spacing(14.vp).crossAxisAlignment(CrossAxisAlignment.Center).hug().fillWidth()
}

private func editField(label: String, hint: String, value: State<String>, model: AppModel, key: String): Unit {
    VStack {
        HStack {
            Label(label).fontSize(11.fp).muted()
            if (hint.size > 0) {
                Label(hint).fontSize(10.fp).muted()
            }
        }.spacing(7.vp).hug()
        TextField(dirtyText(model, value), key: key).fillWidth()
    }.spacing(6.vp).crossAxisAlignment(CrossAxisAlignment.Start).hug().fillWidth()
}

private func dirtyText(model: AppModel, value: State<String>): Bindable<String> {
    value.project(
        get: {v => v},
        set: {
            _, v =>
                model.metadataEditorDirty.value = true
                v
        }
    )
}

private func metadataTags(model: AppModel): Unit {
    VStack {
        HStack {
            Label("标签").fontSize(11.fp).muted()
            Label("逗号分隔 · 保存为 namespace:name 规范形式").fontSize(10.fp).muted()
        }.spacing(8.vp).hug()
        let tags = splitTags(model.metadataTags.value)
        if (tags.size > 0) {
            FlowRow {
                for (tag in tags) {
                    Badge(tag, kind: if (tag.contains(":")) {
                        BadgeKind.Accent
                    } else {
                        BadgeKind.Neutral
                    })
                }
            }.spacing(6.vp)
        }
        TextField(dirtyText(model, model.metadataTags), key: "metadata.tags").fillWidth()
    }.spacing(7.vp).crossAxisAlignment(CrossAxisAlignment.Start).hug().fillWidth()
}

private func splitTags(raw: String): ArrayList<String> {
    let out = ArrayList<String>()
    for (part in raw.split(",")) {
        let tag = part.trimAscii()
        if (tag.size > 0) {
            out.add(tag)
        }
    }
    out
}

private func metadataPlugin(model: AppModel): Unit {
    let field = if (model.isLight()) {
        LANLU_L_FIELD
    } else {
        LANLU_FIELD
    }
    let labels = ArrayList<String>()
    let namespaces = ArrayList<String>()
    for (plugin in model.plugins.value) {
        if (plugin.pluginType == "metadata" && plugin.enabled && plugin.installed) {
            labels.add(if (plugin.name.size > 0) {
                plugin.name
            } else {
                plugin.namespace
            })
            namespaces.add(plugin.namespace)
        }
    }
    let selected = rememberState<Int64>("metadata.plugin.index", {=> 0})
    if (selected.value >= labels.size) {
        selected.value = 0
    }
    let param = rememberState<String>("metadata.plugin.param", {=> ""})
    VStack {
        HStack {
            Label("从插件获取元数据").fontSize(11.fp).muted()
            Label("任务由服务端执行并直接写回").fontSize(10.fp).muted()
        }.spacing(8.vp).hug()
        HStack {
            Dropdown(if (labels.size > 0) {
                labels.toArray()
            } else {
                ["暂无可用插件"]
            }, selected, key: "metadata.plugin").width(180.vp)
            TextField(param, key: "metadata.plugin.param").flex()
            IconButton(IconName.Play, role: ButtonRole.Primary, onClick: {
                => if (selected.value >= 0 && selected.value < namespaces.size) {
                    model.runMetadataEditorPlugin(namespaces[selected.value], param.value)
                }
            }).key("metadata:plugin-run").enabled(namespaces.size > 0 && !model.metadataPluginRunning.value)
        }.spacing(8.vp).hug().fillWidth()
        if (model.metadataPluginRunning.value) {
            HStack {
                Spinner(14.0, if (model.isLight()) {
                    LANLU_L_ACCENT
                } else {
                    LANLU_ACCENT
                })
                Label("正在创建插件任务…").fontSize(11.fp).muted()
            }.spacing(8.vp).hug()
        }
        if (model.metadataPluginPreview.value) {
            HStack {
                Icon(IconName.Sparkle, size: 14.vp).foregroundColor(if (model.isLight()) {
                    LANLU_L_ACCENT
                } else {
                    LANLU_ACCENT
                })
                Label("插件任务已提交：结果由服务端写回元数据，任务完成后重新打开详情即可查看。")
                    .fontSize(11.fp)
                    .foregroundColor(if (model.isLight()) {
                        LANLU_L_ACCENT
                    } else {
                        LANLU_ACCENT
                    })
                    .wrap()
                    .flex()
            }.spacing(8.vp).padding(12.vp, 8.vp).background(field, 9.vp).fillWidth()
        }
    }.spacing(8.vp).crossAxisAlignment(CrossAxisAlignment.Start).hug().fillWidth()
}

private func pageAttachments(model: AppModel): Unit {
    VStack {
        HStack {
            Label("页面附件").fontSize(11.fp).muted()
            Label("歌词 / 字幕 / 字体等，随页分发到阅读器").fontSize(10.fp).muted()
        }.spacing(8.vp).hug()
        Panel(flexible: false) {
            HStack {
                Badge("附件", kind: BadgeKind.Info)
                VStack {
                    Label("此页附件由服务端元数据维护").fontSize(12.fp)
                    Label("可在上传组件接入后添加或替换文件").fontSize(10.fp).muted()
                }.spacing(3.vp).crossAxisAlignment(CrossAxisAlignment.Start).flex()
                IconButton(IconName.Plus, label: Some("添加附件"), style: Some(ghostStyleOf(model)), onClick: {
                    => model.todoToast("附件上传")
                })
            }.spacing(10.vp).crossAxisAlignment(CrossAxisAlignment.Center).hug().fillWidth()
        }.fillWidth()
    }.spacing(7.vp).crossAxisAlignment(CrossAxisAlignment.Start).hug().fillWidth()
}

private func metadataSide(model: AppModel): Unit {
    let level = model.metadataEditorLevel.value
    let count = if (level == 0) {
        model.tankMembers.value.size
    } else {
        model.metadataEditorPages.value.size
    }
    VStack {
        HStack {
            Label(if (level == 0) {
                "收录档案"
            } else {
                "页面"
            }).fontSize(13.fp)
            Badge("${count}")
            Spacer()
            IconButton(IconName.Plus, style: Some(ghostStyleOf(model)), onClick: {
                => model.todoToast(if (level == 0) {
                    "添加档案"
                } else {
                    "批量页编辑"
                })
            }).key("metadata:side-add")
        }.spacing(8.vp).crossAxisAlignment(CrossAxisAlignment.Center).hug().fillWidth().padding(14.vp, 10.vp)
        Divider()
        ScrollView(key: "metadata-side-list") {
            VStack {
                if (level == 0) {
                    ForEachIndexed(model.tankMembers.value) {i, item => tankMemberRow(model, item, i)}
                } else {
                    ForEachIndexed(model.metadataEditorPages.value) {i, page => metadataPageRow(model, page, i)}
                }
                if (count == 0) {
                    Label("暂无可编辑条目").fontSize(11.fp).muted().padding(12.vp)
                }
            }.spacing(3.vp).crossAxisAlignment(CrossAxisAlignment.Start).hug().fillWidth().padding(8.vp)
        }.flex()
        Divider()
        Label(if (level == 0) {
            "进入成员档案的嵌套编辑。"
        } else {
            "编辑单页标题、描述、缩略图与附件。"
        }).fontSize(10.fp).muted().wrap().padding(14.vp, 9.vp).fillWidth()
    }.spacing(0.0).hug().width(310.vp)
}

private func tankMemberRow(model: AppModel, item: SearchItem, index: Int64): Unit {
    ClickArea(onClick: {=> model.editTankMember(item, index + 1)}) {
        HStack {
            if (item.coverAssetId > 0) {
                remoteImage(model, "asset:${item.coverAssetId}", "/api/assets/${item.coverAssetId}", 34.vp, 48.vp,
                    radius: 6.0)
            } else {
                VStack {Label("${index + 1}").fontSize(10.fp).muted()}.width(34.vp).height(48.vp)
            }
            VStack {
                Label(item.title).fontSize(12.fp).maxLines(1)
                Label("${item.pagecount} 页").fontSize(10.fp).muted()
            }.spacing(3.vp).crossAxisAlignment(CrossAxisAlignment.Start).flex()
            Badge("Vol.${index + 1}", kind: BadgeKind.Accent)
            Icon(IconName.Pencil, size: 13.vp, color: Some(if (model.isLight()) {
                LANLU_L_MUTED
            } else {
                LANLU_MUTED
            }))
        }.spacing(9.vp).crossAxisAlignment(CrossAxisAlignment.Center).padding(8.vp, 6.vp).fillWidth()
    }
}

private func metadataPageRow(model: AppModel, page: PageInfo, index: Int64): Unit {
    ClickArea(onClick: {=> model.editMetadataPage(index)}) {
        HStack {
            remoteImage(model, pageThumbnailKey(model, page), pageThumbnailUrl(model, page), 52.vp, 34.vp, radius: 6.0)
            VStack {
                Label(pageDisplayTitle(page, index)).fontSize(12.fp).maxLines(1)
                Label(pageDisplaySummary(page)).fontSize(10.fp).muted().maxLines(1)
            }.spacing(2.vp).crossAxisAlignment(CrossAxisAlignment.Start).flex()
            Icon(IconName.Pencil, size: 13.vp, color: Some(if (model.isLight()) {
                LANLU_L_MUTED
            } else {
                LANLU_MUTED
            }))
        }.spacing(8.vp).crossAxisAlignment(CrossAxisAlignment.Center).padding(8.vp, 7.vp).fillWidth()
    }
}

private func pageDisplayTitle(page: PageInfo, index: Int64): String {
    if (!pageHasCustomTitle(page)) {
        return "P.${index + 1}"
    }
    page.title.trimAscii()
}

private func pageHasCustomTitle(page: PageInfo): Bool {
    let title = page.title.trimAscii()
    let path = page.sourcePath.trimAscii()
    if (title.size == 0 || title == path) {
        return false
    }
    let parts = path.split("/")
    if (parts.size > 0 && title == parts[parts.size - 1]) {
        return false
    }
    true
}

private func pageDisplaySummary(page: PageInfo): String {
    let releaseAt = page.releaseAt.trimAscii()
    let description = page.description.trimAscii()
    if (releaseAt.size > 0 && description.size > 0) {
        return "${description} · ${releaseAt}"
    }
    if (description.size > 0) {
        return description
    }
    if (releaseAt.size > 0) {
        return releaseAt
    }
    if (page.thumbAssetId > 0) {
        "自定义缩略图"
    } else {
        "自动缩略图"
    }
}

private func pageThumbnailKey(model: AppModel, page: PageInfo): String {
    if (page.thumbAssetId > 0) {
        "asset:${page.thumbAssetId}"
    } else {
        // 自动缩略图走 thumb: 档（解码上限 300px，评审 #41）：编辑器侧栏只展示 52×34vp，
        // 用 page:（2000px 档）会为每张缩略图全页解码。url 不变，由 model 按 key 前缀分档。
        "thumb:${model.metadataEditorArchiveId}:${page.sourcePath}"
    }
}

private func pageThumbnailUrl(model: AppModel, page: PageInfo): String {
    if (page.thumbAssetId > 0) {
        "/api/assets/${page.thumbAssetId}"
    } else {
        "/api/archives/${model.metadataEditorArchiveId}/page?path=${percentEncode(page.sourcePath)}"
    }
}

private func metadataFooter(model: AppModel): Unit {
    HStack {
        if (model.metadataEditorDirty.value) {
            Badge("有未保存的更改", kind: BadgeKind.Accent)
        } else {
            Label("所有更改已保存").fontSize(11.fp).muted()
        }
        Label(if (model.metadataEditorLevel.value == 2) {
            "来源：手动编辑"
        } else {
            "来源：统一元数据"
        }).fontSize(10.fp).muted()
        Spacer()
        Button("取 消", {=> model.closeMetadataEditor()}).style(ghostStyleOf(model))
        Button(if (model.metadataEditorSaving.value) {
            "保存中…"
        } else {
            "保存更改"
        }, {
            => model.saveMetadataEditor()
        }).role(ButtonRole.Primary).enabled(!model.metadataEditorSaving.value)
    }.spacing(10.vp).crossAxisAlignment(CrossAxisAlignment.Center).hug().fillWidth().padding(18.vp, 12.vp)
}
