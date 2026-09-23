package lanlu_client_next.app

import lanlu_client_next.img.sanitizeKey
import libavformat_ffi.{ExtractedSubtitleTrack, SubtitleCancelToken, decodeSubtitleTracks, encodeSubtitleTracks,
    extractSubtitleTracks}
import std.collection.ArrayList
import std.fs.{Directory, File, OpenMode, Path, exists, removeIfExists, rename}

/** Versioned, server-isolated subtitle extraction cache with atomic publication. */
public class SubtitleCache {
    private let root: String

    public init(root: String) {
        this.root = "${root}/subtitles"
        ensureRoot()
    }

    public func loadOrExtract(stableKey: String, url: String, bearer!: String = "", cancel!: ?SubtitleCancelToken = None): ArrayList<ExtractedSubtitleTrack> {
        let finalPath = Path(path(stableKey, ".llsub"))
        if (exists(finalPath)) {
            try {
                SubtitlePerf.spanStart("subtitle_cache_hit")
                let tracks = decodeSubtitleTracks(File.readFrom(finalPath))
                SubtitlePerf.spanEnd("subtitle_cache_hit")
                SubtitlePerf.countAdd("subtitle_cache_hit_count", 1)
                return tracks
            } catch (_: Exception) {
                removeIfExists(finalPath, recursive: false)
            }
        }
        SubtitlePerf.spanStart("subtitle_scan")
        let tracks = extractSubtitleTracks(url, bearer: bearer, cancel: cancel)
        let encoded = encodeSubtitleTracks(tracks)
        SubtitlePerf.spanEnd("subtitle_scan")
        SubtitlePerf.gauge("subtitle_cache_bytes", Int64(encoded.size))
        SubtitlePerf.countAdd("subtitle_scan_count", 1)
        let temporary = Path(path(stableKey, ".bin"))
        try {
            let file = File(temporary, OpenMode.Write)
            try {
                file.write(encoded)
                file.flush()
                file.close()
            } catch (e: Exception) {
                try {
                    file.close()
                } catch (_: Exception) {
                    ()
                }
                throw e
            }
            rename(temporary, to: finalPath, overwrite: true)
        } catch (e: Exception) {
            removeIfExists(temporary, recursive: false)
            throw e
        }
        tracks
    }

    public func clear(): Unit {
        removeIfExists(Path(root), recursive: true)
        ensureRoot()
    }

    // 当前字幕缓存总体积（字节）；目录不存在返回 0。
    public func totalBytes(): Int64 {
        var total: Int64 = 0
        if (!exists(Path(root))) {
            return 0
        }
        for (info in Directory.readFrom(Path(root))) {
            total += info.size
        }
        total
    }

    // 缓存条目数（扁平目录一层即全部 .llsub）。
    public func fileCount(): Int64 {
        if (!exists(Path(root))) {
            return 0
        }
        Int64(Directory.readFrom(Path(root)).size)
    }

    private func ensureRoot(): Unit {
        if (!exists(Path(root))) {
            Directory.create(Path(root), recursive: true)
        }
    }

    private func path(stableKey: String, suffix: String): String {
        "${root}/${sanitizeKey("v1:${stableKey}")}${suffix}"
    }
}
