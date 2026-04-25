package lanlu.infrastructure.kv

import std.io.{ByteBuffer, readToEnd}
import std.time.*
import stdx.encoding.json.stream.*

public class KvTtlRecord {
    public var value: String = ""
    public var createdAt: Int64 = 0
    public var ttlSeconds: Int64 = 0

    public init() {}

    public init(value: String, ttlSeconds: Int64) {
        this.value = value
        this.createdAt = KvTtlRecordClock.nowSeconds()
        this.ttlSeconds = ttlSeconds
    }
}

public class KvTtlRecordCodec {
    public static func encode(record: KvTtlRecord): String {
        let out = ByteBuffer()
        let w = JsonWriter(out)
        w.startObject()
        w.writeName("value").writeValue(record.value)
        w.writeName("created_at").writeValue(record.createdAt)
        w.writeName("ttl_seconds").writeValue(record.ttlSeconds)
        w.endObject()
        w.flush()
        return String.fromUtf8(readToEnd(out))
    }

    public static func decode(payload: String): Option<KvTtlRecord> {
        let trimmed = payload.trimAscii()
        if (trimmed.size == 0) {
            return None
        }

        try {
            var buf = ByteBuffer()
            unsafe { buf.write(trimmed.rawData()) }
            let reader = JsonReader(buf)
            if (reader.peek() != Some(BeginObject)) {
                return None
            }

            let record = KvTtlRecord()
            reader.startObject()
            while (reader.peek() != EndObject) {
                let name = reader.readName()
                match (name) {
                    case "value" => record.value = reader.readValue<String>()
                    case "created_at" => record.createdAt = reader.readValue<Int64>()
                    case "ttl_seconds" => record.ttlSeconds = reader.readValue<Int64>()
                    case _ => reader.skip()
                }
            }
            reader.endObject()
            return Some(record)
        } catch (_: Exception) {
            return None
        }
    }
}

public class KvTtlRecords {
    public static func encode(value: String, ttlSeconds: Int64): String {
        return KvTtlRecordCodec.encode(KvTtlRecord(value, ttlSeconds))
    }

    public static func isExpired(record: KvTtlRecord): Bool {
        return record.ttlSeconds > 0 && (KvTtlRecordClock.nowSeconds() - record.createdAt) > record.ttlSeconds
    }
}

private class KvTtlRecordClock {
    public static func nowSeconds(): Int64 {
        return DateTime.now().toUnixTimeStamp().toSeconds()
    }
}
