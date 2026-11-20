/*
 * 看板的数据模型：卡片是唯一数据源，列头计数、筛选结果全部由它派生，
 * 展示数字不可能再与卡片数量脱节。
 */
package cui_data_board

import std.collection.ArrayList

/** 一张任务卡。id 稳定唯一，作为 ForEach 的身份键。 */
struct Task {
    let id: Int64
    let title: String
    let owner: String
    let tags: Array<String>
    let due: String
    let mine: Bool
    let urgent: Bool

    init(
        id: Int64,
        title: String,
        owner: String,
        tags: Array<String>,
        due: String,
        mine!: Bool = false,
        urgent!: Bool = false
    ) {
        this.id = id
        this.title = title
        this.owner = owner
        this.tags = tags
        this.due = due
        this.mine = mine
        this.urgent = urgent
    }
}

/** 筛选选项与 Picker 的下标一一对应。 */
let FILTER_LABELS = ["全部任务", "只看我的", "高优先级"]

func matchesFilter(task: Task, filter: Int64): Bool {
    match (filter) {
        case 1 => task.mine
        case 2 => task.urgent
        case _ => true
    }
}

func filterTasks(tasks: Array<Task>, filter: Int64): Array<Task> {
    let visible = ArrayList<Task>()
    for (task in tasks) {
        if (matchesFilter(task, filter)) {
            visible.add(task)
        }
    }
    visible.toArray()
}

func seedPlanned(): Array<Task> {
    [
        Task(1, "梳理首次启动路径", "体验", ["研究", "桌面"], "周一", mine: true),
        Task(2, "补全空状态插图", "设计", ["视觉"], "周二"),
        Task(3, "整理遥测字段字典", "数据", ["规范"], "周三", urgent: true)
    ]
}

func seedDoing(): Array<Task> {
    [
        Task(4, "重构搜索结果页", "前端", ["高优先级", "联调"], "今天", mine: true, urgent: true),
        Task(5, "验证离线同步冲突", "客户端", ["测试", "边界"], "今天")
    ]
}

func seedDone(): Array<Task> {
    [
        Task(6, "冻结第三季度路线图", "产品", ["里程碑"], "昨天"),
        Task(7, "发布无障碍检查清单", "体验", ["文档", "质量"], "昨天", mine: true),
        Task(8, "优化字体缓存策略", "基础设施", ["性能"], "上周")
    ]
}
