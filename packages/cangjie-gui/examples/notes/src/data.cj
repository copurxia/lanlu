/*
 * 笔记数据与纯函数辅助。
 *
 * 笔记是不可变值，更新通过整表替换触发状态通知（与看板示例一致）。标题从正文首行派生，
 * 因此编辑正文时侧栏标题会实时跟随。
 */
package cui_notes

struct Note {
    let id: Int64
    let body: String

    init(id: Int64, body: String) {
        this.id = id
        this.body = body
    }
}

func seedNotes(): Array<Note> {
    [
        Note(1, "购物清单\n- 牛奶\n- 鸡蛋\n- 面包"),
        Note(2, "会议纪要\n讨论了下季度路线图与优先级，确认先做命令面板与主从编辑。"),
        Note(3, "灵感\n把提示浮层扩展成下拉与上下文菜单。"),
        Note(4, "空笔记\n")
    ]
}

func clampNoteIndex(index: Int64, count: Int64): Int64 {
    if (count <= 0) {
        0
    } else if (index < 0) {
        0
    } else if (index >= count) {
        count - 1
    } else {
        index
    }
}

/** 选中笔记的正文，没有笔记时为空串——供编辑器绑定使用。 */
func noteBodyAt(notes: Array<Note>, index: Int64): String {
    if (notes.isEmpty()) {
        ""
    } else {
        notes[clampNoteIndex(index, notes.size)].body
    }
}

/** 返回将第 `index` 条笔记正文替换后的新笔记表。 */
func withBodyAt(notes: Array<Note>, index: Int64, body: String): Array<Note> {
    if (notes.isEmpty()) {
        return notes
    }
    let target = clampNoteIndex(index, notes.size)
    Array<Note>(notes.size, {i => if (i == target) {
        Note(notes[i].id, body)
    } else {
        notes[i]
    }})
}

/** 笔记的侧栏标题：取正文首行，为空时显示占位文本。 */
func noteTitle(body: String): String {
    // 空串在仓颉中 split 得到空数组，故先判空再取首行，避免越界。
    let lines = body.split("\n")
    if (lines.isEmpty() || lines[0].isEmpty()) {
        "无标题"
    } else {
        lines[0]
    }
}
