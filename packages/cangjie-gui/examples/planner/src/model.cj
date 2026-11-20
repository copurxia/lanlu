/*
 * 专注规划台的共享状态：页面切换、专注进度与偏好设置。
 * 进度百分比文本由 completed 派生，视图直接读取。
 */
package cui_planner

import cui.State

class PlannerModel {
    let page = State<Int64>(0)
    let completed = State<Float32>(0.68)
    let sessionMinutes = State<Int64>(45)
    let notifications = State<Bool>(true)
    let ambientSound = State<Bool>(false)
    let priority = State<Int64>(1)
    let density = State<Int64>(1)
    /** 默认工作城市：可从建议里选，也可自行键入其他城市（组合框绑定的自由文本）。 */
    let location = State<String>("北京")
}
