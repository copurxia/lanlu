package lrr4cj.utils

import std.collection.*
import std.io.{ByteBuffer, readToEnd}
import stdx.encoding.json.stream.*
import stdx.log.*

/**
 * 将“代码中发现的插件参数schema”和“数据库中已保存的参数value”合并，避免启动/发现插件时覆盖用户配置。
 *
 * - discoveredJson: 来自插件脚本 getPluginInfo().parameters（通常没有 value）
 * - existingJson: 数据库 plugins.parameters（可能包含 value）
 */
public func mergePluginParameters(existingJson: String, discoveredJson: String): String {
    let existingTrimmed = existingJson.trimAscii()
    let discoveredTrimmed = discoveredJson.trimAscii()

    if (discoveredTrimmed.size == 0) {
        return existingJson
    }
    if (existingTrimmed.size == 0) {
        return discoveredJson
    }

    try {
        // Only merge when discovered is a JSON array (schema array).
        var discoveredBuf = ByteBuffer()
        unsafe { discoveredBuf.write(discoveredTrimmed.rawData()) }
        let discoveredReader = JsonReader(discoveredBuf)

        if (discoveredReader.peek() != Some(BeginArray)) {
            return discoveredJson
        }

        // existingValueMap: key -> raw JSON value string (not quoted unless value itself is string literal)
        var existingValueMap = HashMap<String, String>()
        // existingObjMap: key -> raw JSON object string (for appending objects not present in discovered)
        var existingObjMap = HashMap<String, String>()

        func extractKeyAndValue(rawObj: String, index: Int64): (String, Option<String>) {
            var key = "param${index.toString()}"
            var valueRaw: Option<String> = None

            var buf = ByteBuffer()
            unsafe { buf.write(rawObj.rawData()) }
            let r = JsonReader(buf)
            if (r.peek() != Some(BeginObject)) {
                return (key, valueRaw)
            }

            r.startObject()
            while (r.peek() != EndObject) {
                let n = r.readName()
                match (n) {
                    case "name" =>
                        let v = r.readValue<String>().trimAscii()
                        if (v.size > 0) { key = v }
                    case "value" =>
                        let bytes = r.readValueBytes()
                        valueRaw = Some(String.fromUtf8(bytes))
                    case _ =>
                        r.skip()
                }
            }
            r.endObject()
            return (key, valueRaw)
        }

        func extractKeyFromObject(rawObj: String, index: Int64): String {
            let (k, _) = extractKeyAndValue(rawObj, index)
            return k
        }

        func injectValueIntoObject(rawObj: String, valueRaw: String): String {
            // Re-serialize object, dropping any existing "value" field and appending/overwriting with provided valueRaw.
            var inBuf = ByteBuffer()
            unsafe { inBuf.write(rawObj.rawData()) }
            let r = JsonReader(inBuf)

            let out = ByteBuffer()
            let w = JsonWriter(out)

            if (r.peek() != Some(BeginObject)) {
                // Not an object; best-effort return original.
                return rawObj
            }

            w.startObject()
            r.startObject()
            while (r.peek() != EndObject) {
                let name = r.readName()
                if (name == "value") {
                    r.skip()
                    continue
                }
                let bytes = r.readValueBytes()
                w.writeName(name).jsonValue(String.fromUtf8(bytes))
            }
            r.endObject()

            w.writeName("value").jsonValue(valueRaw)
            w.endObject()
            w.flush()
            return String.fromUtf8(readToEnd(out))
        }

        // Parse existingJson into maps.
        try {
            var existingBuf = ByteBuffer()
            unsafe { existingBuf.write(existingTrimmed.rawData()) }
            let existingReader = JsonReader(existingBuf)

            match (existingReader.peek()) {
                case Some(BeginArray) =>
                    existingReader.startArray()
                    var idx: Int64 = 0
                    while (existingReader.peek() != EndArray) {
                        match (existingReader.peek()) {
                            case Some(BeginObject) =>
                                let rawObj = String.fromUtf8(existingReader.readValueBytes())
                                let (key, valueOpt) = extractKeyAndValue(rawObj, idx)
                                existingObjMap[key] = rawObj
                                match (valueOpt) {
                                    case Some(v) => existingValueMap[key] = v
                                    case None => ()
                                }
                                idx += 1
                            case Some(_) =>
                                existingReader.skip()
                                idx += 1
                            case None => break
                        }
                    }
                    existingReader.endArray()
                case Some(BeginObject) =>
                    // Compat: DB stored as {name:value}
                    existingReader.startObject()
                    while (existingReader.peek() != EndObject) {
                        let k = existingReader.readName()
                        let bytes = existingReader.readValueBytes()
                        existingValueMap[k] = String.fromUtf8(bytes)
                    }
                    existingReader.endObject()
                case _ => ()
            }
        } catch (_: Exception) {
            // ignore; fall back to discovered below
        }

        // Build merged schema: discovered wins, but inject existing.value.
        var seenKeys = HashSet<String>()
        var mergedRawItems = ArrayList<String>()

        discoveredReader.startArray()
        var dIdx: Int64 = 0
        while (discoveredReader.peek() != EndArray) {
            match (discoveredReader.peek()) {
                case Some(BeginObject) =>
                    let rawObj = String.fromUtf8(discoveredReader.readValueBytes())
                    let key = extractKeyFromObject(rawObj, dIdx)
                    seenKeys.add(key)

                    if (existingValueMap.contains(key)) {
                        mergedRawItems.add(injectValueIntoObject(rawObj, existingValueMap[key]))
                    } else {
                        mergedRawItems.add(rawObj)
                    }
                    dIdx += 1
                case Some(_) =>
                    // Preserve non-object items as raw values.
                    let raw = String.fromUtf8(discoveredReader.readValueBytes())
                    mergedRawItems.add(raw)
                    dIdx += 1
                case None => break
            }
        }
        discoveredReader.endArray()

        // Append existing objects that were not present in discovered schema.
        for ((k, rawObj) in existingObjMap) {
            if (!seenKeys.contains(k)) {
                mergedRawItems.add(rawObj)
            }
        }

        // Serialize merged array.
        let out = ByteBuffer()
        let w = JsonWriter(out)
        w.startArray()
        for (i in 0..mergedRawItems.size) {
            w.jsonValue(mergedRawItems[i])
        }
        w.endArray()
        w.flush()
        return String.fromUtf8(readToEnd(out))
    } catch (e: Exception) {
        getLogger("plugin_utils").warn("合并插件参数失败，使用discovered参数", ("error", e.message))
        return discoveredJson
    }
}
