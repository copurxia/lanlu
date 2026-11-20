package cui.system

import lbase.CuiException

// P5：时间相关改用 libc（clock_gettime / localtime_r / gmtime_r / mktime）+ 纯计算，
// 不再依赖 SDL 的时间模块（OHOS 上这些系统调用都可用）。

@C
struct Tm {
    var tm_sec: Int32 = 0
    var tm_min: Int32 = 0
    var tm_hour: Int32 = 0
    var tm_mday: Int32 = 1
    var tm_mon: Int32 = 0
    var tm_year: Int32 = 70
    var tm_wday: Int32 = 0
    var tm_yday: Int32 = 0
    var tm_isdst: Int32 = 0
}

@C
struct Timespec {
    var tv_sec: Int64 = 0
    var tv_nsec: Int64 = 0
}

foreign {
    func clock_gettime(clk_id: Int32, tp: CPointer<Timespec>): Int32
    func localtime_r(t: CPointer<Int64>, out: CPointer<Tm>): CPointer<Tm>
    func gmtime_r(t: CPointer<Int64>, out: CPointer<Tm>): CPointer<Tm>
    func mktime(tm: CPointer<Tm>): Int64
}

private const CLOCK_REALTIME: Int32 = 0

public enum DateFormat {
    | YearMonthDay
    | DayMonthYear
    | MonthDayYear
    | UnknownDateFormat(Int32)
}

public enum ClockFormat {
    | TwentyFourHour
    | TwelveHour
    | UnknownClockFormat(Int32)
}

public enum Weekday {
    | Sunday
    | Monday
    | Tuesday
    | Wednesday
    | Thursday
    | Friday
    | Saturday
}

public struct DateTimeLocalePreferences {
    public let dateFormat: DateFormat
    public let clockFormat: ClockFormat

    public init(dateFormat: DateFormat, clockFormat: ClockFormat) {
        this.dateFormat = dateFormat
        this.clockFormat = clockFormat
    }
}

public struct WindowsFileTime {
    public let low: UInt32
    public let high: UInt32

    public init(low: UInt32, high: UInt32) {
        this.low = low
        this.high = high
    }
}

public struct DateTimeParts {
    public var year: Int32 = 1970
    public var month: Int32 = 1
    public var day: Int32 = 1
    public var hour: Int32 = 0
    public var minute: Int32 = 0
    public var second: Int32 = 0
    public var nanosecond: Int32 = 0
    public var dayOfWeek: ?Weekday = None
    public var utcOffsetSeconds: Int32 = 0
}

public class Time {
    /**
     * Throws `CuiException` when SDL cannot query the system realtime clock.
     */

    public static func currentNanoseconds(): Int64 {
        var ts = Timespec()
        unsafe { clock_gettime(CLOCK_REALTIME, inout ts) }
        ts.tv_sec * 1000000000 + ts.tv_nsec
    }

    /**
     * Throws `CuiException` when SDL cannot query or convert the system realtime clock.
     */
    public static func currentDateTime(local!: Bool = true): DateTimeParts {
        toDateTime(currentNanoseconds(), local: local)
    }

    /**
     * Throws `CuiException` when SDL cannot convert nanoseconds to calendar fields.
     */

    public static func toDateTime(nanoseconds: Int64, local!: Bool = true): DateTimeParts {
        let seconds = nanoseconds / 1000000000
        var secs = seconds
        var raw = Tm()
        unsafe {
            if (local) {
                localtime_r(inout secs, inout raw)
            } else {
                gmtime_r(inout secs, inout raw)
            }
        }
        var parts = DateTimeParts()
        parts.year = raw.tm_year + 1900
        parts.month = raw.tm_mon + 1
        parts.day = raw.tm_mday
        parts.hour = raw.tm_hour
        parts.minute = raw.tm_min
        parts.second = raw.tm_sec
        parts.nanosecond = Int32(nanoseconds % 1000000000)
        parts.dayOfWeek = weekdayFromCode(raw.tm_wday)
        parts.utcOffsetSeconds = if (local) { localOffsetSeconds(seconds) } else { 0 }
        parts
    }

    /**
     * Throws `CuiException` when SDL cannot convert calendar fields to nanoseconds.
     */

    public static func toNanoseconds(parts: DateTimeParts): Int64 {
        var raw = Tm()
        raw.tm_sec = parts.second
        raw.tm_min = parts.minute
        raw.tm_hour = parts.hour
        raw.tm_mday = parts.day
        raw.tm_mon = parts.month - 1
        raw.tm_year = parts.year - 1900
        raw.tm_isdst = -1
        let secs = unsafe { mktime(inout raw) }
        secs * 1000000000 + Int64(parts.nanosecond)
    }


    public static func toWindowsFileTime(nanoseconds: Int64): WindowsFileTime {
        // Windows FILETIME：自 1601-01-01 起的 100ns 计数
        const EPOCH_DIFF_100NS: Int64 = 116444736000000000
        let ticks = nanoseconds / 100 + EPOCH_DIFF_100NS
        WindowsFileTime(UInt32(ticks & 0xFFFFFFFF), UInt32((ticks >> 32) & 0xFFFFFFFF))
    }


    public static func fromWindowsFileTime(fileTime: WindowsFileTime): Int64 {
        const EPOCH_DIFF_100NS: Int64 = 116444736000000000
        let ticks = (Int64(fileTime.high) << 32) | Int64(fileTime.low)
        (ticks - EPOCH_DIFF_100NS) * 100
    }

    /**
     * Throws `CuiException` when the requested year/month is invalid.
     */

    public static func daysInMonth(year: Int32, month: Int32): Int32 {
        if (month < 1 || month > 12 || year < 1) {
            throw CuiException("无效的年月: ${year}-${month}")
        }
        match (month) {
            case 1 | 3 | 5 | 7 | 8 | 10 | 12 => 31
            case 4 | 6 | 9 | 11 => 30
            case 2 => if (isLeapYear(year)) { 29 } else { 28 }
            case _ => 0
        }
    }

    /**
     * Throws `CuiException` when the requested date is invalid.
     */

    public static func dayOfYear(year: Int32, month: Int32, day: Int32): Int32 {
        if (month < 1 || month > 12 || day < 1 || day > daysInMonth(year, month)) {
            throw CuiException("无效日期: ${year}-${month}-${day}")
        }
        var total = day
        for (m in 1..month) {
            total += daysInMonth(year, m)
        }
        total
    }

    /**
     * Throws `CuiException` when the requested date is invalid.
     */

    public static func dayOfWeek(year: Int32, month: Int32, day: Int32): Weekday {
        // Sakamoto 算法（0=Sunday）
        if (month < 1 || month > 12 || day < 1) {
            throw CuiException("无效日期: ${year}-${month}-${day}")
        }
        let offsets: Array<Int64> = [0, 3, 2, 5, 0, 3, 5, 1, 4, 6, 2, 4]
        let y: Int64 = if (month < 3) { Int64(year - 1) } else { Int64(year) }
        var index: Int64 = (y + y / 4 - y / 100 + y / 400 + offsets[Int64(month - 1)] + Int64(day)) % 7
        if (index < 0) {
            index += 7
        }
        match (Int32(index)) {
            case 0 => Weekday.Sunday
            case 1 => Weekday.Monday
            case 2 => Weekday.Tuesday
            case 3 => Weekday.Wednesday
            case 4 => Weekday.Thursday
            case 5 => Weekday.Friday
            case _ => Weekday.Saturday
        }
    }

    /**
     * Throws `CuiException` when SDL cannot query locale date/time preferences.
     */

    public static func localePreferences(): DateTimeLocalePreferences {
        // P5：不做平台查询，返回 ISO + 24 小时制（与 OHOS 简体中文默认一致）
        DateTimeLocalePreferences(DateFormat.YearMonthDay, ClockFormat.TwentyFourHour)
    }
}

private func isLeapYear(year: Int32): Bool {
    (year % 4 == 0 && year % 100 != 0) || (year % 400 == 0)
}

/// 本地时区偏移（秒）：同一时刻的本地分解与 UTC 分解各自 mktime 后相减。
private func localOffsetSeconds(epochSeconds: Int64): Int32 {
    var secs = epochSeconds
    var localTm = Tm()
    var gmTm = Tm()
    unsafe {
        localtime_r(inout secs, inout localTm)
        gmtime_r(inout secs, inout gmTm)
    }
    localTm.tm_isdst = -1
    gmTm.tm_isdst = -1
    let localEpoch = unsafe { mktime(inout localTm) }
    let gmEpoch = unsafe { mktime(inout gmTm) }
    Int32(localEpoch - gmEpoch)
}
