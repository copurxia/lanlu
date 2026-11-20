/*
 * 看板状态：三列卡片、筛选、密度与在制上限。
 * 列头计数是 DerivedState —— 卡片或筛选一变，数字随之刷新，无需手工同步。
 */
package cui_data_board

import cui.{DerivedState, State, derive}

class BoardModel {
    let compact = State<Bool>(false)
    let wipLimit = State<Int64>(4)
    let filter = State<Int64>(0)
    let planned: State<Array<Task>>
    let doing: State<Array<Task>>
    let done: State<Array<Task>>
    let plannedCount: DerivedState<String>
    let doingCount: DerivedState<String>
    let doneCount: DerivedState<String>
    /** 进行中的可见数量超过在制上限时为 true，列头以警示色提醒。 */
    let wipExceeded: DerivedState<Bool>
    private var nextId: Int64 = 100

    init() {
        this.planned = State<Array<Task>>(seedPlanned())
        this.doing = State<Array<Task>>(seedDoing())
        this.done = State<Array<Task>>(seedDone())
        let filter = this.filter
        this.plannedCount = derive(this.planned, filter, {tasks, f => "${filterTasks(tasks, f).size} 项"})
        this.doingCount = derive(this.doing, filter, this.wipLimit,
            {tasks, f, limit => "${filterTasks(tasks, f).size} / ${limit}"})
        this.doneCount = derive(this.done, filter, {tasks, f => "${filterTasks(tasks, f).size} 项"})
        this.wipExceeded = derive(this.doing, filter, this.wipLimit,
            {tasks, f, limit => filterTasks(tasks, f).size > limit})
    }

    func visiblePlanned(): Array<Task> {
        filterTasks(planned.value, filter.value)
    }

    func visibleDoing(): Array<Task> {
        filterTasks(doing.value, filter.value)
    }

    func visibleDone(): Array<Task> {
        filterTasks(done.value, filter.value)
    }

    /** 向指定列追加一张新卡；整列替换以触发状态通知。新卡负责人统一为“待分派”。 */
    func addTask(column: State<Array<Task>>): Unit {
        let id = nextId
        nextId += 1
        let task = Task(id, "新任务 #${id}", "待分派", ["待细化"], "待排期", mine: true)
        let current = column.value
        let appended = Array<Task>(current.size + 1, {
            index => if (index < current.size) {
                current[index]
            } else {
                task
            }
        })
        column.value = appended
    }
}
