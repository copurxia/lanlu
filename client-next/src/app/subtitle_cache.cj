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
                return decodeSubtitleTracks(File.readFrom(finalPath))
            } catch (_: Exception) {
                removeIfExists(finalPath, recursive: false)
            }
        }
        let tracks = extractSubtitleTracks(url, bearer: bearer, cancel: cancel)
        let encoded = encodeSubtitleTracks(tracks)
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

    private func ensureRoot(): Unit {
        if (!exists(Path(root))) {
            Directory.create(Path(root), recursive: true)
        }
    }

    private func path(stableKey: String, suffix: String): String {
        "${root}/${sanitizeKey("v1:${stableKey}")}${suffix}"
    }
}
