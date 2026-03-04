package cjcron

import std.time.*
import cjcron.parser.*

public class CronExpression {
    private let parsed: ParsedExpression

    private init(parsed!: ParsedExpression) {
        this.parsed = parsed
    }

    public static func parse(expr: String): CronExpression {
        let p = ExpressionParser.parse(expr)
        return CronExpression(parsed: p)
    }

    public func toString(): String {
        return parsed.raw
    }

    /**
     * Return the next execution time strictly after `after`, using the DateTime's timezone.
     * If no match is found within 5 years, returns None.
     */
    public func next(after: DateTime): Option<DateTime> {
        var candidate = normalizeStart(after)
        let limit = after + (Duration.day * (366 * 5))

        let step = if (parsed.hasSeconds) { Duration.second } else { Duration.minute }

        while (candidate <= limit) {
            if (matches(candidate)) {
                return Some(candidate)
            }
            candidate = candidate + step
        }
        return None
    }

    private func normalizeStart(after: DateTime): DateTime {
        // Ensure we are strictly after `after`.
        if (parsed.hasSeconds) {
            return after + Duration.second
        }
        // For 5-field cron: second/nano are treated as 0; step is minutes.
        // Start from the next minute boundary.
        let zone = after.zone
        let base = DateTime.of(
            year: after.year,
            month: after.month,
            dayOfMonth: after.dayOfMonth,
            hour: after.hour,
            minute: after.minute,
            second: 0,
            nanosecond: 0,
            timeZone: zone
        )
        if (base <= after) {
            return base + Duration.minute
        }
        return base
    }

    private func matches(dt: DateTime): Bool {
        if (!parsed.hasSeconds) {
            if (dt.second != 0 || dt.nanosecond != 0) {
                return false
            }
        }

        let sec = dt.second
        let min = dt.minute
        let hour = dt.hour
        let dom = dt.dayOfMonth
        let mon = dt.month.toInteger()
        let dow = dt.dayOfWeek.toInteger()

        if (!parsed.seconds[sec]) {
            return false
        }
        if (!parsed.minutes[min]) {
            return false
        }
        if (!parsed.hours[hour]) {
            return false
        }
        if (!parsed.dayOfMonth[dom - 1]) {
            return false
        }
        if (!parsed.month[mon - 1]) {
            return false
        }
        if (!parsed.dayOfWeek[dow]) {
            return false
        }

        return true
    }
}
