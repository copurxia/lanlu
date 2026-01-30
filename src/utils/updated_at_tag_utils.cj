package lanlu.utils

import std.collection.*
import std.convert.*
import std.time.*

/**
 * Helpers for handling plugin-emitted pseudo-tags like `updated_at:<value>`.
 *
 * The backend accepts `updated_at:` in the tag list as a way for plugins to suggest
 * a specific update time. We map it to the DB field (archives.updated_at) and
 * remove it from the stored tags.
 */

/**
 * Extract `updated_at:*` pseudo-tags from a comma-separated tag string.
 * Returns (updatedAtString, cleanedTagsString).
 */
public func extractUpdatedAtFromTags(tagsString: String): (String, String) {
    if (tagsString.trimAscii().size == 0) {
        return ("", "")
    }

    var extracted = ""
    var kept: ArrayList<String> = ArrayList<String>()

    let parts = tagsString.split(",")
    for (p in parts) {
        let t = p.trimAscii()
        if (t.size == 0) { continue }

        if (t.startsWith("updated_at:")) {
            let raw = t["updated_at:".size..].trimAscii()
            if (raw.size > 0) {
                match (normalizeUpdatedAt(raw)) {
                    case Some(normalized) => extracted = normalized
                    case None => ()
                }
            }
            continue
        }

        kept.add(t)
    }

    return (extracted, String.join(kept.toArray(), delimiter: ", "))
}

/**
 * Normalize a plugin-provided updated_at value into a DateTime string suitable for DB writes.
 * Supports:
 * - unix seconds (e.g. "1700000000")
 * - DateTime parseable strings
 */
public func normalizeUpdatedAt(raw: String): Option<String> {
    let s = raw.trimAscii()
    if (s.size == 0) { return None }

    // If it's an integer unix timestamp (seconds), convert from Unix epoch.
    var allDigits = true
    var i: Int64 = 0
    while (i < s.size) {
        let ch = s[i]
        if (ch < 48u8 || ch > 57u8) {
            allDigits = false
            break
        }
        i += 1
    }
    if (allDigits) {
        try {
            let secs = Int64.parse(s)
            let dt = DateTime.fromUnixTimeStamp(Duration.second * secs)
            return Some(dt.toString())
        } catch (_: Exception) {
            return None
        }
    }

    // Otherwise, try parse as DateTime string.
    match (DateTime.tryParse(s)) {
        case Some(dt) => Some(dt.toString())
        case None => None
    }
}

