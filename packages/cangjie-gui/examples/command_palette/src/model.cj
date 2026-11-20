/*
 * 命令面板状态。
 *
 * 结果列表是查询的纯函数（filterCommands），因此无需缓存——每次读取都由 query 现算。
 * 高亮索引在查询变化时通过 State.observe 归零，保证键入后总是选中最匹配的首项。
 */
package cui_command_palette

import cui.{DerivedState, State, StateObservation}

class PaletteModel {
    let query = State<String>("")
    let selected = State<Int64>(0)
    let log = State<Array<String>>([])
    let catalog: Array<Command>
    /** 结果条数，用于底栏提示；随查询自动派生。 */
    let resultCount: DerivedState<Int64>
    // 随模型整个生命周期持有，保证归零观察器持续生效。
    private let queryObservation: StateObservation<String>

    init() {
        this.catalog = commandCatalog()
        let cat = this.catalog
        this.resultCount = this.query.map<Int64>({q => filterCommands(cat, q).size})
        let selection = this.selected
        this.queryObservation = this.query.observe({_, _ => selection.value = 0})
    }

    func results(): Array<Command> {
        filterCommands(catalog, query.value)
    }

    /** 供 ListView 显示的标题，每次都由当前查询重新派生。 */
    func resultTitles(): Array<String> {
        let hits = results()
        Array<String>(hits.size, {i => hits[i].title})
    }

    func moveSelection(delta: Int64): Unit {
        let count = results().size
        if (count == 0) {
            return
        }
        selected.value = clampIndex(selected.value + delta, count)
    }

    /** 高亮命令的单行描述，用于底部提示栏。 */
    func selectedHint(): String {
        let hits = results()
        if (hits.isEmpty()) {
            return "没有匹配的命令，换个关键词试试"
        }
        let command = hits[clampIndex(selected.value, hits.size)]
        "${command.title} · ${command.hint}"
    }

    /** 执行高亮命令。多数命令会写入执行记录；“清空执行记录”则清空记录。 */
    func runSelected(): Unit {
        let hits = results()
        if (hits.isEmpty()) {
            return
        }
        let command = hits[clampIndex(selected.value, hits.size)]
        if (command.title == "清空执行记录") {
            log.value = []
            return
        }
        appendLog("已执行 · ${command.title}")
    }

    private func appendLog(entry: String): Unit {
        let current = log.value
        log.value = Array<String>(current.size + 1, {i => if (i < current.size) {
            current[i]
        } else {
            entry
        }})
    }

    private func clampIndex(index: Int64, count: Int64): Int64 {
        if (index < 0) {
            0
        } else if (index >= count) {
            count - 1
        } else {
            index
        }
    }
}
