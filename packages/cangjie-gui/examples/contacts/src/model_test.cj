package cui_contacts

// 搜索可命中任一字段（姓名、公司、职务、邮箱），空查询时显示全部联系人。
@Test
func searchFiltersAcrossFields(): Unit {
    let model = ContactsModel()
    let total = model.contacts.value.size

    model.query.value = "星河" // 星河科技有三位联系人
    @Expect(model.visible().size, Int64(3))

    model.query.value = "future.com" // 命中邮箱字段
    @Expect(model.visible().size >= 1)

    model.query.value = ""
    @Expect(model.visible().size, total)
}

// 新增必须填写姓名（否则保存按钮禁用），保存后在列表末尾追加联系人。
@Test
func addRequiresNameThenAppends(): Unit {
    let model = ContactsModel()
    let before = model.contacts.value.size

    model.startAdd()
    @Expect(!model.canSave()) // 草稿姓名为空
    model.saveForm() // 校验未通过时为空操作
    @Expect(model.contacts.value.size, before)

    model.draftName.value = "新同学"
    model.draftCompany.value = "青柠工作室"
    @Expect(model.canSave())
    model.saveForm()
    @Expect(model.contacts.value.size, before + 1)
    @Expect(!model.formOpen.value)

    model.query.value = "新同学"
    @Expect(model.visible().size, Int64(1))
}

// 编辑选中项会原位替换该联系人（id 不变，字段更新）。
@Test
func editReplacesSelectedInPlace(): Unit {
    let model = ContactsModel()
    let before = model.contacts.value.size
    model.selected.value = 0

    model.startEdit()
    model.draftRole.value = "首席设计师"
    model.saveForm()

    @Expect(model.contacts.value.size, before) // 原位替换，而非新增
    @Expect(model.contacts.value[0].role, "首席设计师")
}

// 删除先经确认标记，随后移除选中联系人并清空选择。
@Test
func deleteRemovesSelectedContact(): Unit {
    let model = ContactsModel()
    let before = model.contacts.value.size
    model.selected.value = 0
    @Expect(model.selectedContact().getOrThrow().name, "林晚")

    model.requestDelete()
    @Expect(model.confirmDelete.value)
    model.deleteSelected()
    @Expect(model.contacts.value.size, before - 1)
    @Expect(!model.confirmDelete.value)
    @Expect(model.selected.value, Int64(-1))
}
