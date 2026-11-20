package cui_notes

/*
 * 主从绑定必须始终读写“当前选中”的那条笔记，且新增/删除后选中索引要保持在有效范围内——
 * 这是主从模型中最容易出错的细节。
 */
@Test
func projectBindingReadsAndWritesTheSelectedNote(): Unit {
    let model = NotesModel()

    @Expect(model.body.value.contains("购物清单"))

    model.selected.value = 1
    @Expect(model.body.value.contains("会议纪要"))

    model.body.value = "改写后的内容"
    @Expect(model.notes.value[1].body, "改写后的内容")
    @Expect(model.titles()[1], "改写后的内容") // 侧栏标题实时跟随正文首行
}

@Test
func addAndDeleteKeepSelectionInRange(): Unit {
    let model = NotesModel()
    let before = model.notes.value.size

    model.addNote()
    @Expect(model.notes.value.size, before + 1)
    @Expect(model.selected.value, before) // 新建的笔记成为选中项
    @Expect(model.body.value, "") // 且初始正文为空
    @Expect(model.titles()[before], "无标题") // 空正文的侧栏标题回退为占位文本，且取标题不越界

    model.deleteSelected()
    @Expect(model.notes.value.size, before)
    @Expect(model.selected.value <= before - 1) // 被钳回有效范围
}

// 仅右键菜单提供的“复制笔记”会在源笔记之后插入副本并选中它。
@Test
func duplicateInsertsCopyAfterSourceAndSelectsIt(): Unit {
    let model = NotesModel()
    model.selected.value = 0
    let sourceBody = model.body.value
    let before = model.notes.value.size

    model.duplicateSelected()
    @Expect(model.notes.value.size, before + 1)
    @Expect(model.selected.value, Int64(1)) // 副本位于索引 1 并成为选中项
    @Expect(model.notes.value[1].body, sourceBody) // 内容相同……
    @Expect(model.notes.value[1].id != model.notes.value[0].id) // ……但 id 不同，身份独立
}
