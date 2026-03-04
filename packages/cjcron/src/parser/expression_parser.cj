package cjcron.parser

import cjcron.error.*
import std.unicode.*
import std.collection.*

public class ExpressionParser {
    public static func parse(expr: String): ParsedExpression {
        let trimmed = expr.trim()
        if (trimmed.isEmpty()) {
            throw CronError("Cron expression is empty")
        }

        // Support common @aliases
        if (trimmed == "@yearly" || trimmed == "@annually") {
            return parse("0 0 1 1 *")
        }
        if (trimmed == "@monthly") {
            return parse("0 0 1 * *")
        }
        if (trimmed == "@weekly") {
            return parse("0 0 * * 0")
        }
        if (trimmed == "@daily") {
            return parse("0 0 * * *")
        }
        if (trimmed == "@hourly") {
            return parse("0 * * * *")
        }

        let fields = splitWhitespace(trimmed)
        if (fields.size != 5 && fields.size != 6) {
            throw CronError("Cron must be 5 fields (min hour dom mon dow) or 6 fields (sec min hour dom mon dow)")
        }

        let hasSeconds = fields.size == 6
        let secField = if (hasSeconds) { fields[0] } else { "0" }
        let minField = if (hasSeconds) { fields[1] } else { fields[0] }
        let hourField = if (hasSeconds) { fields[2] } else { fields[1] }
        let domField = if (hasSeconds) { fields[3] } else { fields[2] }
        let monField = if (hasSeconds) { fields[4] } else { fields[3] }
        let dowField = if (hasSeconds) { fields[5] } else { fields[4] }

        let allowedSeconds = FieldParser.parseField(normalizeDowMonNames(secField, fieldKind: "sec"), min: 0, max: 59, name: "second")
        let allowedMinutes = FieldParser.parseField(normalizeDowMonNames(minField, fieldKind: "min"), min: 0, max: 59, name: "minute")
        let allowedHours = FieldParser.parseField(normalizeDowMonNames(hourField, fieldKind: "hour"), min: 0, max: 23, name: "hour")
        let allowedDom = FieldParser.parseField(normalizeDowMonNames(domField, fieldKind: "dom"), min: 1, max: 31, name: "day-of-month")
        let allowedMon = FieldParser.parseField(normalizeDowMonNames(monField, fieldKind: "mon"), min: 1, max: 12, name: "month")
        let allowedDow = parseDayOfWeek(dowField)

        return ParsedExpression(
            raw: trimmed,
            hasSeconds: hasSeconds,
            seconds: allowedSeconds,
            minutes: allowedMinutes,
            hours: allowedHours,
            dayOfMonth: allowedDom,
            month: allowedMon,
            dayOfWeek: allowedDow
        )
    }

    private static func splitWhitespace(s: String): Array<String> {
        let normalized = s.replace("\t", " ").replace("\n", " ").replace("\r", " ")
        let rawParts = normalized.split(" ")
        var out = ArrayList<String>()
        for (p in rawParts) {
            let t = p.trim()
            if (!t.isEmpty()) {
                out.add(t)
            }
        }
        return out.toArray()
    }

    private static func normalizeDowMonNames(s: String, fieldKind!: String): String {
        // Only normalize month/dow names; other fields return as-is.
        if (fieldKind != "mon" && fieldKind != "dow") {
            return s
        }
        var upper = s.toUpper()
        // Month names
        upper = upper.replace("JAN", "1")
        upper = upper.replace("FEB", "2")
        upper = upper.replace("MAR", "3")
        upper = upper.replace("APR", "4")
        upper = upper.replace("MAY", "5")
        upper = upper.replace("JUN", "6")
        upper = upper.replace("JUL", "7")
        upper = upper.replace("AUG", "8")
        upper = upper.replace("SEP", "9")
        upper = upper.replace("OCT", "10")
        upper = upper.replace("NOV", "11")
        upper = upper.replace("DEC", "12")

        // Day-of-week names (0=SUN .. 6=SAT)
        upper = upper.replace("SUN", "0")
        upper = upper.replace("MON", "1")
        upper = upper.replace("TUE", "2")
        upper = upper.replace("WED", "3")
        upper = upper.replace("THU", "4")
        upper = upper.replace("FRI", "5")
        upper = upper.replace("SAT", "6")
        return upper
    }

    private static func parseDayOfWeek(field: String): Array<Bool> {
        let normalized = normalizeDowMonNames(field, fieldKind: "dow").trim()
        // Accept 0-6, and also 7 as Sunday (common extension)
        let base = FieldParser.parseField(normalized, min: 0, max: 7, name: "day-of-week")
        var allowed = Array<Bool>(7, { _ => false })
        for (i in 0..base.size) {
            if (base[i]) {
                if (i == 7) {
                    allowed[0] = true
                } else {
                    allowed[i] = true
                }
            }
        }
        return allowed
    }
}

public class ParsedExpression {
    public let raw: String
    public let hasSeconds: Bool
    public let seconds: Array<Bool>     // 0-59
    public let minutes: Array<Bool>     // 0-59
    public let hours: Array<Bool>       // 0-23
    public let dayOfMonth: Array<Bool>  // 1-31 (index 0 => day 1)
    public let month: Array<Bool>       // 1-12 (index 0 => month 1)
    public let dayOfWeek: Array<Bool>   // 0-6 (0 => Sunday)

    public init(
        raw!: String,
        hasSeconds!: Bool,
        seconds!: Array<Bool>,
        minutes!: Array<Bool>,
        hours!: Array<Bool>,
        dayOfMonth!: Array<Bool>,
        month!: Array<Bool>,
        dayOfWeek!: Array<Bool>
    ) {
        this.raw = raw
        this.hasSeconds = hasSeconds
        this.seconds = seconds
        this.minutes = minutes
        this.hours = hours
        this.dayOfMonth = dayOfMonth
        this.month = month
        this.dayOfWeek = dayOfWeek
    }
}
