/*
 * 日历数据模型与月份运算。
 *
 * 视图层只读写这里的 State；月份边界、跨年进退位和周行展开等规则集中在本文件，
 * 与渲染完全解耦，可独立测试。
 */
package cui_calendar

import std.collection.ArrayList
import cui.{DateTimeParts, DerivedState, State, Time, Weekday, derive}

let MONTH_NAMES = ["一月", "二月", "三月", "四月", "五月", "六月", "七月", "八月", "九月", "十月", "十一月", "十二月"]

class CalendarModel {
    /** “今天”的日期。跨日由 refreshToday 更新，视图每帧重建自然拿到新值。 */
    private var today: DateTimeParts
    let year: State<Int64>
    let month: State<Int64>
    let selected: State<Int64>
    let tab = State<Int64>(0)
    /** 标题由年/月派生，仅在其中之一变化时重新拼接。 */
    let title: DerivedState<String>

    init(today: DateTimeParts) {
        this.today = today
        this.year = State<Int64>(Int64(today.year))
        this.month = State<Int64>(Int64(today.month))
        this.selected = State<Int64>(Int64(today.day))
        this.title = derive(this.year, this.month, {y, m => "${y} 年 ${MONTH_NAMES[m - 1]}"})
    }

    /** 跨日时更新“今天”高亮基准；每帧调用一次，日期未变时只做比较、无副作用。 */
    func refreshToday(now: DateTimeParts): Unit {
        if (now.year != today.year || now.month != today.month || now.day != today.day) {
            today = now
        }
    }

    func isToday(day: Int64): Bool {
        year.value == Int64(today.year) && month.value == Int64(today.month) && day == Int64(today.day)
    }

    func selectedDateLine(): String {
        let weekday = Time.dayOfWeek(Int32(year.value), Int32(month.value), Int32(selected.value))
        "${year.value} 年 ${month.value} 月 ${selected.value} 日，${weekdayName(weekday)}"
    }

    /** 前进或后退 `delta` 个月，跨年自动进退位，选中日夹紧到目标月长度内。 */
    func shiftMonth(delta: Int64): Unit {
        var nextMonth = month.value + delta
        var nextYear = year.value
        while (nextMonth < 1) {
            nextMonth += 12
            nextYear -= 1
        }
        while (nextMonth > 12) {
            nextMonth -= 12
            nextYear += 1
        }
        month.value = nextMonth
        year.value = nextYear
        selected.value = min(selected.value, Int64(Time.daysInMonth(Int32(nextYear), Int32(nextMonth))))
    }
}

/*
 * 一个月的周行：每行七个日号，0 表示该格在本月之外。行数按当月实际需要生成。
 */
func monthWeeks(year: Int64, month: Int64): Array<Array<Int64>> {
    let firstIndex = weekdayIndex(Time.dayOfWeek(Int32(year), Int32(month), 1))
    let days = Int64(Time.daysInMonth(Int32(year), Int32(month)))
    let rows = (firstIndex + days + 6) / 7
    let weeks = ArrayList<Array<Int64>>()
    for (row in 0..rows) {
        weeks.add(Array<Int64>(7, {col => dayForCell(firstIndex, days, row, col)}))
    }
    weeks.toArray()
}

func dayForCell(firstIndex: Int64, days: Int64, row: Int64, col: Int64): Int64 {
    let day = row * 7 + col - firstIndex + 1
    if (day >= 1 && day <= days) {
        day
    } else {
        0
    }
}

func weekdayIndex(day: Weekday): Int64 {
    match (day) {
        case Weekday.Sunday => 0
        case Weekday.Monday => 1
        case Weekday.Tuesday => 2
        case Weekday.Wednesday => 3
        case Weekday.Thursday => 4
        case Weekday.Friday => 5
        case Weekday.Saturday => 6
    }
}

func weekdayName(day: Weekday): String {
    match (day) {
        case Weekday.Sunday => "星期日"
        case Weekday.Monday => "星期一"
        case Weekday.Tuesday => "星期二"
        case Weekday.Wednesday => "星期三"
        case Weekday.Thursday => "星期四"
        case Weekday.Friday => "星期五"
        case Weekday.Saturday => "星期六"
    }
}
