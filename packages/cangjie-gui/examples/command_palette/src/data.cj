/*
 * 命令目录与筛选。
 *
 * 每条命令带一组小写英文别名 keywords，因此英文输入也能命中中文标题的命令；
 * 匹配是大小写不敏感的子串匹配（对中文标题按原样、对英文别名按小写）。
 */
package cui_command_palette

import std.collection.ArrayList

struct Command {
    let title: String
    let hint: String
    let keywords: String

    init(title: String, hint: String, keywords: String) {
        this.title = title
        this.hint = hint
        this.keywords = keywords
    }
}

func commandCatalog(): Array<Command> {
    [
        Command("新建文档", "创建一个空白文档", "new file document"),
        Command("打开文件", "从磁盘打开已有文件", "open file"),
        Command("保存", "保存当前更改", "save"),
        Command("另存为", "保存到新的位置", "save as export"),
        Command("撤销上一步", "回退最近一次编辑", "undo revert"),
        Command("重做", "恢复被撤销的编辑", "redo"),
        Command("查找并替换", "在文档中查找并替换", "find replace search"),
        Command("切换侧栏", "显示或隐藏导航侧栏", "toggle sidebar panel"),
        Command("放大界面", "增大界面缩放", "zoom in bigger scale"),
        Command("缩小界面", "减小界面缩放", "zoom out smaller scale"),
        Command("切换深色主题", "在浅色与深色之间切换", "dark light theme mode"),
        Command("命令面板设置", "配置命令面板的行为", "settings preferences config"),
        Command("清空执行记录", "清除下方的历史列表", "clear history log"),
        Command("关于 CUI", "查看框架版本与信息", "about info version")
    ]
}

/** 标题或英文别名包含 `query` 的全部命令；匹配不区分大小写。 */
func filterCommands(catalog: Array<Command>, query: String): Array<Command> {
    let needle = query.toAsciiLower()
    if (needle.size == 0) {
        return catalog
    }
    let matches = ArrayList<Command>()
    for (command in catalog) {
        if (command.title.toAsciiLower().contains(needle) || command.keywords.contains(needle)) {
            matches.add(command)
        }
    }
    matches.toArray()
}
