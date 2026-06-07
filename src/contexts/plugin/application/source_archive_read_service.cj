package lanlu.contexts.plugin.application

import std.collection.*
import std.io.{ByteBuffer, readToEnd}
import stdx.encoding.json.stream.*

public class SourceDetailResult {
    public var title: String = ""
    public var description: String = ""
    public var tags: Array<String> = Array<String>()
    public var pageCount: Int64 = 0
    public var coverAssetId: Int64 = 0
    public var mediaType: String = "image"
    public var children: Array<SourceChildItem> = Array<SourceChildItem>()
    public var errorMessage: String = ""
    public func hasError(): Bool { errorMessage.size > 0 }
}

public class SourceChildItem {
    public var sourceNamespace: String = ""
    public var remoteId: String = ""
    public var title: String = ""
    public var description: String = ""
    public var tags: Array<String> = Array<String>()
}

public class SourcePageItem {
    public var path: String = ""
    public var assetId: Int64 = 0
}

public class SourcePagesResult {
    public var pages: Array<SourcePageItem> = Array<SourcePageItem>()
    public var errorMessage: String = ""
    public func hasError(): Bool { errorMessage.size > 0 }
}

public class SourceArchiveReadService {

    public static func fetchDetail(compositeId: String): SourceDetailResult {
        let request = match (SourceRequestResolver.parseFromCompositeId(compositeId)) {
            case Some(r) => r
            case None =>
                let result = SourceDetailResult()
                result.errorMessage = "Invalid composite id: ${compositeId}"
                return result
        }

        let json = SourceDirectActionService.execute(request.namespace, "source_detail", request)
        if (json.trimAscii().size == 0) {
            let result = SourceDetailResult()
            result.errorMessage = "source_detail returned empty response for ${compositeId}"
            return result
        }

        try {
            return parseDetailJson(json)
        } catch (e: Exception) {
            let result = SourceDetailResult()
            result.errorMessage = "Failed to parse source_detail response: ${e.message}"
            return result
        }
    }

    public static func fetchPages(compositeId: String): SourcePagesResult {
        let request = match (SourceRequestResolver.parseFromCompositeId(compositeId)) {
            case Some(r) => r
            case None =>
                let result = SourcePagesResult()
                result.errorMessage = "Invalid composite id: ${compositeId}"
                return result
        }

        let json = SourceDirectActionService.execute(request.namespace, "source_reader", request)
        if (json.trimAscii().size == 0) {
            let result = SourcePagesResult()
            result.errorMessage = "source_reader returned empty response for ${compositeId}"
            return result
        }

        try {
            return parsePagesJson(json)
        } catch (e: Exception) {
            let result = SourcePagesResult()
            result.errorMessage = "Failed to parse source_reader response: ${e.message}"
            return result
        }
    }

    public static func resolvePageAsset(namespace: String, remoteId: String, path: String, page!: String = ""): Int64 {
        if (namespace.trimAscii().size == 0 || remoteId.trimAscii().size == 0 || path.trimAscii().size == 0) {
            return 0
        }

        let paramsOut = ByteBuffer()
        let pw = JsonWriter(paramsOut)
        pw.startObject()
        pw.writeName("remote_id").writeValue(remoteId)
        pw.writeName("path").writeValue(path)
        if (page.trimAscii().size > 0) {
            pw.writeName("page").writeValue(page)
        }
        pw.endObject()
        pw.flush()

        let request = SourceRequest(namespace, remoteId)
        request.paramsJson = String.fromUtf8(readToEnd(paramsOut))

        let json = SourceDirectActionService.execute(namespace, "source_page_asset", request)
        if (json.trimAscii().size == 0) {
            return 0
        }

        try {
            return parsePageAssetJson(json)
        } catch (_: Exception) {
            return 0
        }
    }

    private static func parseDetailJson(json: String): SourceDetailResult {
        var buf = ByteBuffer()
        unsafe { buf.write(json.rawData()) }
        let r = JsonReader(buf)

        if (r.peek() != Some(BeginObject)) {
            return SourceDetailResult()
        }

        var dataRaw: Option<String> = None
        var success = true
        var errorMessage = ""

        r.startObject()
        while (r.peek() != EndObject) {
            let name = r.readName()
            if (name == "success") {
                success = r.readValue<Bool>()
            } else if (name == "error") {
                errorMessage = r.readValue<String>()
            } else if (name == "data") {
                let bytes = r.readValueBytes()
                dataRaw = Some(String.fromUtf8(bytes))
            } else {
                r.skip()
            }
        }
        r.endObject()

        if (!success) {
            let result = SourceDetailResult()
            result.errorMessage = if (errorMessage.trimAscii().size > 0) {
                errorMessage
            } else {
                "source_detail returned success=false"
            }
            return result
        }

        match (dataRaw) {
            case Some(dataJson) =>
                let result = SourceDetailResult()
                parseDetailDataFields(dataJson, result)
                return result
            case None =>
                let result = SourceDetailResult()
                result.errorMessage = "source_detail response missing data"
                return result
        }
    }

    private static func parseDetailDataFields(dataJson: String, result: SourceDetailResult): Unit {
        var buf = ByteBuffer()
        unsafe { buf.write(dataJson.rawData()) }
        let r = JsonReader(buf)

        if (r.peek() != Some(BeginObject)) {
            return
        }

        r.startObject()
        while (r.peek() != EndObject) {
            let name = r.readName()
            if (name == "title") {
                result.title = r.readValue<String>()
            } else if (name == "description") {
                result.description = r.readValue<String>()
            } else if (name == "tags") {
                result.tags = parseStringArray(r)
            } else if (name == "page_count") {
                result.pageCount = parsePageCountValue(r)
            } else if (name == "cover_asset_id") {
                result.coverAssetId = readPositiveInt64(r)
            } else if (name == "reader") {
                parseReaderMediaType(r, result)
            } else if (name == "children") {
                result.children = parseChildrenArray(r)
            } else {
                r.skip()
            }
        }
        r.endObject()
    }

    private static func parsePageCountValue(r: JsonReader): Int64 {
        try {
            return r.readValue<Int64>()
        } catch (_: Exception) {
            try {
                let pf = r.readValue<Float64>()
                let intVal = Int64(pf)
                return if (intVal > 0) { intVal } else { 0 }
            } catch (_: Exception) {
                r.skip()
                return 0
            }
        }
    }

    private static func parseReaderMediaType(r: JsonReader, result: SourceDetailResult): Unit {
        if (r.peek() != Some(BeginObject)) {
            r.skip()
            return
        }
        r.startObject()
        while (r.peek() != EndObject) {
            let name = r.readName()
            if (name == "media_type") {
                let mt = r.readValue<String>().trimAscii()
                if (mt.size > 0) {
                    result.mediaType = mt
                }
            } else {
                r.skip()
            }
        }
        r.endObject()
    }

    private static func parseChildrenArray(r: JsonReader): Array<SourceChildItem> {
        if (r.peek() != Some(BeginArray)) {
            r.skip()
            return Array<SourceChildItem>()
        }
        let children = ArrayList<SourceChildItem>()
        r.startArray()
        while (r.peek() != EndArray) {
            if (r.peek() != Some(BeginObject)) {
                r.skip()
                continue
            }
            let child = parseSingleChild(r)
            children.add(child)
        }
        r.endArray()
        return children.toArray()
    }

    private static func parseSingleChild(r: JsonReader): SourceChildItem {
        let child = SourceChildItem()
        r.startObject()
        while (r.peek() != EndObject) {
            let name = r.readName()
            if (name == "source_namespace") {
                child.sourceNamespace = r.readValue<String>()
            } else if (name == "remote_id") {
                child.remoteId = r.readValue<String>()
            } else if (name == "title") {
                child.title = r.readValue<String>()
            } else if (name == "description") {
                child.description = r.readValue<String>()
            } else if (name == "tags") {
                child.tags = parseStringArray(r)
            } else {
                r.skip()
            }
        }
        r.endObject()
        return child
    }

    private static func parseStringArray(r: JsonReader): Array<String> {
        if (r.peek() != Some(BeginArray)) {
            r.skip()
            return Array<String>()
        }
        let items = ArrayList<String>()
        r.startArray()
        while (r.peek() != EndArray) {
            match (r.peek()) {
                case Some(_) =>
                    let val = r.readValue<String>().trimAscii()
                    if (val.size > 0) {
                        items.add(val)
                    }
                case None => break
            }
        }
        r.endArray()
        return items.toArray()
    }

    private static func parsePagesJson(json: String): SourcePagesResult {
        var buf = ByteBuffer()
        unsafe { buf.write(json.rawData()) }
        let r = JsonReader(buf)

        if (r.peek() != Some(BeginObject)) {
            return SourcePagesResult()
        }

        var dataRaw: Option<String> = None
        var success = true
        var errorMessage = ""

        r.startObject()
        while (r.peek() != EndObject) {
            let name = r.readName()
            if (name == "success") {
                success = r.readValue<Bool>()
            } else if (name == "error") {
                errorMessage = r.readValue<String>()
            } else if (name == "data") {
                let bytes = r.readValueBytes()
                dataRaw = Some(String.fromUtf8(bytes))
            } else {
                r.skip()
            }
        }
        r.endObject()

        if (!success) {
            let result = SourcePagesResult()
            result.errorMessage = if (errorMessage.trimAscii().size > 0) {
                errorMessage
            } else {
                "source_reader returned success=false"
            }
            return result
        }

        match (dataRaw) {
            case Some(dataJson) =>
                var buf2 = ByteBuffer()
                unsafe { buf2.write(dataJson.rawData()) }
                let r2 = JsonReader(buf2)

                if (r2.peek() != Some(BeginObject)) {
                    return SourcePagesResult()
                }

                let result = SourcePagesResult()
                r2.startObject()
                while (r2.peek() != EndObject) {
                    let name = r2.readName()
                    if (name == "pages") {
                        result.pages = parsePageItems(r2)
                    } else {
                        r2.skip()
                    }
                }
                r2.endObject()
                return result
            case None =>
                let result = SourcePagesResult()
                result.errorMessage = "source_reader response missing data"
                return result
        }
    }

    private static func parsePageItems(r: JsonReader): Array<SourcePageItem> {
        if (r.peek() != Some(BeginArray)) {
            r.skip()
            return Array<SourcePageItem>()
        }
        let items = ArrayList<SourcePageItem>()
        r.startArray()
        while (r.peek() != EndArray) {
            if (r.peek() != Some(BeginObject)) {
                r.skip()
                continue
            }
            let page = parseSinglePageItem(r)
            items.add(page)
        }
        r.endArray()
        return items.toArray()
    }

    private static func parseSinglePageItem(r: JsonReader): SourcePageItem {
        let page = SourcePageItem()
        r.startObject()
        while (r.peek() != EndObject) {
            let name = r.readName()
            if (name == "path") {
                page.path = r.readValue<String>()
            } else if (name == "asset_id") {
                page.assetId = readPositiveInt64(r)
            } else {
                r.skip()
            }
        }
        r.endObject()

        return page
    }

    private static func parsePageAssetJson(json: String): Int64 {
        var buf = ByteBuffer()
        unsafe { buf.write(json.rawData()) }
        let r = JsonReader(buf)

        if (r.peek() != Some(BeginObject)) {
            return 0
        }

        var dataRaw: Option<String> = None
        var success: Bool = false

        r.startObject()
        while (r.peek() != EndObject) {
            let name = r.readName()
            if (name == "success") {
                success = r.readValue<Bool>()
            } else if (name == "data") {
                let bytes = r.readValueBytes()
                dataRaw = Some(String.fromUtf8(bytes))
            } else {
                r.skip()
            }
        }
        r.endObject()

        if (!success) {
            return 0
        }

        match (dataRaw) {
            case Some(dataJson) =>
                var buf2 = ByteBuffer()
                unsafe { buf2.write(dataJson.rawData()) }
                let r2 = JsonReader(buf2)

                if (r2.peek() != Some(BeginObject)) {
                    return 0
                }

                var assetId: Int64 = 0
                r2.startObject()
                while (r2.peek() != EndObject) {
                    let name = r2.readName()
                    if (name == "asset_id") {
                        assetId = readPositiveInt64(r2)
                    } else {
                        r2.skip()
                    }
                }
                r2.endObject()
                return assetId
            case None => return 0
        }
    }

    private static func readPositiveInt64(r: JsonReader): Int64 {
        try {
            let parsed = r.readValue<Int64>()
            return if (parsed > 0) { parsed } else { 0 }
        } catch (_: Exception) {
            r.skip()
            return 0
        }
    }
}
