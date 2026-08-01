package lanlu_client_next.ui

import cui.*
import lanlu_client_next.app.*

// 与 app 包 SEARCH_SORT_FIELDS 按下标一一对应；弹窗与书库工具条共享同一组查询状态。
private func advancedSortLabels(model: AppModel): Array<String> {
    [model.t("library.sort.title"), model.t("library.sort.created"), model.t("library.sort.updated"),
        model.t("library.sort.lastRead"), model.t("library.sort.pages"), model.t("library.sort.release")]
}

// frontend 首页筛选按钮对应的高级筛选弹窗。草稿由 AppModel.openAdvancedFilter 在每次打开时
// 从已应用状态同步，取消只关弹窗，应用/重置统一由模型收束查询。
func advancedFilterDialog(model: AppModel): Unit {
    Modal(model.advancedFilterOpen, onDismiss: {=> model.advancedFilterOpen.value = false}, body: {
        => VStack {
            Label(model.t("library.advancedFilter")).fontSize(15.fp)
            Label(model.t("library.filterDetail")).fontSize(12.fp).muted()
            HStack {
                Flexible {
                    filterDateField(model.t("library.dateFrom"), model.advancedDateFrom, "filter.date-from")
                }
                Flexible {
                    filterDateField(model.t("library.dateTo"), model.advancedDateTo, "filter.date-to")
                }
            }.spacing(10.vp).hug().fillWidth()
            VStack {
                Label(model.t("library.sortBy")).fontSize(11.fp).muted()
                Dropdown(advancedSortLabels(model), model.advancedSortIndex.project(get: {v => v}, set: {_, v => v}),
                    key: "filter.sort").fillWidth()
                SegmentedControl(
                    [model.t("library.order.asc"), model.t("library.order.desc")],
                    model.advancedOrderIndex.project(get: {v => v}, set: {_, v => v})
                ).fillWidth()
            }.spacing(6.vp).crossAxisAlignment(CrossAxisAlignment.Start).hug().fillWidth()
            Divider()
            VStack {
                Switch(model.t("library.newOnly"), model.advancedNewOnly.project(get: {v => v}, set: {_, v => v})).key(
                    "filter.new-only")
                Switch(model.t("library.untaggedOnly"),
                    model.advancedUntaggedOnly.project(get: {v => v}, set: {_, v => v})).key("filter.untagged-only")
                Switch(model.t("library.favoriteOnly"), model.advancedFavOnly.project(get: {v => v}, set: {_, v => v}))
                    .key("filter.favorite-only")
                Switch(
                    model.t("library.groupByTanks"),
                    model.advancedTankGroupIndex.project(
                        get: {v => v == 0},
                        set: {
                            _, v => if (v) {
                                0
                            } else {
                                1
                            }
                        }
                    )
                ).key("filter.group-tanks")
            }.spacing(6.vp).crossAxisAlignment(CrossAxisAlignment.Start).hug().fillWidth()
            Divider()
            HStack {
                Spacer()
                Button(model.t("common.cancel"), {=> model.advancedFilterOpen.value = false}).style(ghostStyleOf(model))
                Button(model.t("common.reset"), {=> model.resetAdvancedFilter()})
                    .style(ghostStyleOf(model))
                    .enabled(!model.loading.value)
                Button(model.t("common.filter"), {=> model.applyAdvancedFilter()})
                    .role(ButtonRole.Primary)
                    .enabled(!model.loading.value)
            }.spacing(8.vp).fillWidth()
        }.spacing(12.vp).crossAxisAlignment(CrossAxisAlignment.Start).width(420.vp)
    })
}

private func filterDateField(label: String, value: State<String>, key: String): Unit {
    VStack {
        Label(label).fontSize(11.fp).muted()
        TextField(value, trailingIcon: Some(IconName.Calendar), key: key).fillWidth()
        Label("YYYY-MM-DD").fontSize(10.fp).muted()
    }.spacing(5.vp).crossAxisAlignment(CrossAxisAlignment.Start).hug().fillWidth()
}
