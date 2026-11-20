package cui.system

import lbase.CuiException

@Test
func dateAndClockFormatsMapSdlValues(): Unit {
    // P5 移除 SDL 运行时后不再有 SDL_DATE_FORMAT_*/SDL_TIME_FORMAT_* 常量；
    // 直接按协议数值断言（YYYYMMDD=0 / DDMMYYYY=1 / MMDDYYYY=2；24HR=0 / 12HR=1）。
    expectYearMonthDay(dateFormatFromCode(0))
    expectDayMonthYear(dateFormatFromCode(1))
    expectMonthDayYear(dateFormatFromCode(2))
    expectUnknownDateFormat(dateFormatFromCode(99), 99)

    expectTwentyFourHour(clockFormatFromCode(0))
    expectTwelveHour(clockFormatFromCode(1))
    expectUnknownClockFormat(clockFormatFromCode(99), 99)
}

@Test
func weekdayMappingsPreserveSdlValues(): Unit {
    expectSunday(weekdayFromCode(0))
    expectMonday(weekdayFromCode(1))
    expectSaturday(weekdayFromCode(6))
    expectNoWeekday(weekdayFromCode(99))
    let noDay: ?Weekday = None
    @Expect(weekdayCode(Some(Weekday.Friday)), 5)
    @Expect(weekdayCode(noDay), 0)
}

@Test
func calendarDateHelpersReturnKnownValues(): Unit {
    @Expect(Time.daysInMonth(2024, 2), 29)
    @Expect(Time.daysInMonth(2023, 2), 28)
    // 2024 是闰年：12-31 是第 366 天；平年（2023）才是 365。
    @Expect(Time.dayOfYear(2024, 12, 31), 366)
    @Expect(Time.dayOfYear(2023, 12, 31), 365)
    expectMonday(Some(Time.dayOfWeek(2024, 1, 1)))
    @Expect(daysInMonthFails(2024, 13))
}

@Test
func dateTimeConvertsUnixEpoch(): Unit {
    let parts = Time.toDateTime(0, local: false)

    @Expect(parts.year, 1970)
    @Expect(parts.month, 1)
    @Expect(parts.day, 1)
    @Expect(parts.hour, 0)
    @Expect(parts.minute, 0)
    @Expect(parts.second, 0)
    expectThursday(parts.dayOfWeek)
    // toNanoseconds 按本地时区解释日历字段（mktime），local=false 的 UTC 分解只用于
    // 上面的字段断言；往返必须用 local=true 的同一口径（否则非 UTC 机器上差时差）。
    @Expect(Time.toNanoseconds(Time.toDateTime(0, local: true)), Int64(0))
}

@Test
func windowsFileTimeRoundTrips(): Unit {
    let fileTime = Time.toWindowsFileTime(Int64(0))

    @Expect(Time.fromWindowsFileTime(fileTime), Int64(0))
}

@Test
func currentTimeAndLocalePreferencesAreAvailable(): Unit {
    @Expect(Time.currentNanoseconds() > Int64(0))
    let _ = Time.currentDateTime()
    let preferences = Time.localePreferences()

    expectKnownDateFormat(preferences.dateFormat)
    expectKnownClockFormat(preferences.clockFormat)
}

@Test
func performanceClockReportsUsefulValues(): Unit {
    let start = PerformanceClock.counter()
    PerformanceClock.delayNanoseconds(UInt64(1))
    let end = PerformanceClock.counter()

    @Expect(PerformanceClock.frequency() > UInt64(0))
    @Expect(end >= start)
    @Expect(PerformanceClock.ticksNanoseconds() >= PerformanceClock.millisecondsToNanoseconds(
        PerformanceClock.ticksMilliseconds()))
}

private func daysInMonthFails(year: Int32, month: Int32): Bool {
    try {
        let _ = Time.daysInMonth(year, month)
        false
    } catch (e: CuiException) {
        true
    }
}

private func expectYearMonthDay(format: DateFormat): Unit {
    match (format) {
        case DateFormat.YearMonthDay => @Expect(true)
        case _ => @Fail("Date format should be YearMonthDay.")
    }
}

private func expectDayMonthYear(format: DateFormat): Unit {
    match (format) {
        case DateFormat.DayMonthYear => @Expect(true)
        case _ => @Fail("Date format should be DayMonthYear.")
    }
}

private func expectMonthDayYear(format: DateFormat): Unit {
    match (format) {
        case DateFormat.MonthDayYear => @Expect(true)
        case _ => @Fail("Date format should be MonthDayYear.")
    }
}

private func expectUnknownDateFormat(format: DateFormat, code: Int32): Unit {
    match (format) {
        case DateFormat.UnknownDateFormat(value) => @Expect(value, code)
        case _ => @Fail("Date format should preserve unknown codes.")
    }
}

private func expectTwentyFourHour(format: ClockFormat): Unit {
    match (format) {
        case ClockFormat.TwentyFourHour => @Expect(true)
        case _ => @Fail("Clock format should be TwentyFourHour.")
    }
}

private func expectTwelveHour(format: ClockFormat): Unit {
    match (format) {
        case ClockFormat.TwelveHour => @Expect(true)
        case _ => @Fail("Clock format should be TwelveHour.")
    }
}

private func expectUnknownClockFormat(format: ClockFormat, code: Int32): Unit {
    match (format) {
        case ClockFormat.UnknownClockFormat(value) => @Expect(value, code)
        case _ => @Fail("Clock format should preserve unknown codes.")
    }
}

private func expectKnownDateFormat(format: DateFormat): Unit {
    match (format) {
        case DateFormat.UnknownDateFormat(_) => @Fail("Locale date format should be known.")
        case _ => @Expect(true)
    }
}

private func expectKnownClockFormat(format: ClockFormat): Unit {
    match (format) {
        case ClockFormat.UnknownClockFormat(_) => @Fail("Locale clock format should be known.")
        case _ => @Expect(true)
    }
}

private func expectSunday(day: ?Weekday): Unit {
    match (day) {
        case Some(Weekday.Sunday) => @Expect(true)
        case _ => @Fail("Weekday should be Sunday.")
    }
}

private func expectMonday(day: ?Weekday): Unit {
    match (day) {
        case Some(Weekday.Monday) => @Expect(true)
        case _ => @Fail("Weekday should be Monday.")
    }
}

private func expectThursday(day: ?Weekday): Unit {
    match (day) {
        case Some(Weekday.Thursday) => @Expect(true)
        case _ => @Fail("Weekday should be Thursday.")
    }
}

private func expectSaturday(day: ?Weekday): Unit {
    match (day) {
        case Some(Weekday.Saturday) => @Expect(true)
        case _ => @Fail("Weekday should be Saturday.")
    }
}

private func expectNoWeekday(day: ?Weekday): Unit {
    match (day) {
        case None => @Expect(true)
        case Some(_) => @Fail("Weekday should be absent.")
    }
}
