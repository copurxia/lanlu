package cjcron.parser

import cjcron.error.*
import std.convert.*
import std.unicode.*

public class FieldParser {
    public static func parseField(field: String, min!: Int64, max!: Int64, name!: String = "field"): Array<Bool> {
        if (min > max) {
            throw CronError("Invalid range for ${name}: min > max")
        }

        let size = max - min + 1
        var allowed = Array<Bool>(size, { _ => false })

        let trimmed = field.trim()
        if (trimmed == "*") {
            for (i in 0..size) {
                allowed[i] = true
            }
            return allowed
        }

        // Comma-separated parts
        let parts = trimmed.split(",")
        if (parts.size == 0) {
            throw CronError("Empty ${name}")
        }
        for (part in parts) {
            allowed = applyPart(part.trim(), min: min, max: max, name: name, allowed: allowed)
        }
        return allowed
    }

    private static func applyPart(part: String, min!: Int64, max!: Int64, name!: String, allowed!: Array<Bool>): Array<Bool> {
        var out = allowed
        if (part.isEmpty()) {
            throw CronError("Empty item in ${name}")
        }

        // step: a/b or */b or a-b/b
        let stepSplit = part.split("/")
        if (stepSplit.size > 2) {
            throw CronError("Invalid step syntax in ${name}: ${part}")
        }
        let base = stepSplit[0].trim()
        let step = if (stepSplit.size == 2) {
            parseInt(stepSplit[1].trim(), name: name, context: part)
        } else { 1 }
        if (step <= 0) {
            throw CronError("Step must be > 0 in ${name}: ${part}")
        }

        if (base == "*") {
            var v = min
            while (v <= max) {
                out[v - min] = true
                v += step
            }
            return out
        }

        // range a-b or single a
        let dashSplit = base.split("-")
        if (dashSplit.size == 1) {
            let value = parseInt(dashSplit[0].trim(), name: name, context: part)
            out = markValue(value, min: min, max: max, name: name, context: part, allowed: out)
            return out
        }
        if (dashSplit.size != 2) {
            throw CronError("Invalid range syntax in ${name}: ${part}")
        }
        let start = parseInt(dashSplit[0].trim(), name: name, context: part)
        let end = parseInt(dashSplit[1].trim(), name: name, context: part)
        if (start > end) {
            throw CronError("Invalid range (start>end) in ${name}: ${part}")
        }

        var v = start
        while (v <= end) {
            out = markValue(v, min: min, max: max, name: name, context: part, allowed: out)
            v += step
        }
        return out
    }

    private static func markValue(value: Int64, min!: Int64, max!: Int64, name!: String, context!: String, allowed!: Array<Bool>): Array<Bool> {
        var out = allowed
        if (value < min || value > max) {
            throw CronError("Value out of range for ${name} (${min}-${max}): ${context}")
        }
        out[value - min] = true
        return out
    }

    private static func parseInt(s: String, name!: String, context!: String): Int64 {
        if (s.isEmpty()) {
            throw CronError("Missing number in ${name}: ${context}")
        }
        try {
            return Int64.parse(s.trim())
        } catch (e: Exception) {
            throw CronError("Invalid number in ${name}: ${context}")
        }
    }
}
