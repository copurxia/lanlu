package lanlu.utils

import std.fs.*
import ahash.*
import avif_ffi.*

/**
 * Thumbhash utilities (content-based hash of decoded pixels).
 *
 * This is used for caching (ETag) and quick-change detection.
 */
public class ThumbHashUtils {
    /**
     * Calculate a deterministic hash from RGBA pixels (already decoded).
     * This lets callers avoid re-decoding the written AVIF just to compute thumbhash.
     */
    public static func calculateThumbHashFromRgbaPixels(pixels: Array<UInt8>): String {
        let builder = RandomState.new()
        let hasher = builder.buildHasher()
        hasher.write(pixels)
        let hash = hasher.finish()
        return hashToHex(hash)
    }

    /**
     * Calculate a deterministic hash from the decoded RGBA pixels of an AVIF file.
     */
    public static func calculateAvifThumbHashFromFile(imagePath: String): String {
        let filePath = Path(imagePath)
        let file = File(filePath, Read)
        let fileInfo = file.info
        let fileSize = Int64(fileInfo.size)
        let buffer = Array<Byte>(fileSize, {_ => 0})
        let bytesRead = file.read(buffer)
        file.close()

        if (bytesRead <= 0) {
            throw Exception("Failed to read file: ${imagePath}")
        }

        let imageData = buffer[0..bytesRead]
        if (let Some((_, _, pixels)) <- AvifDecoder.decodeRGBA(imageData)) {
            return calculateThumbHashFromRgbaPixels(pixels)
        }

        throw Exception("AVIF decode failed for: ${imagePath}")
    }

    private static func hashToHex(hash: UInt64): String {
        var result = ""
        var h = hash
        for (_ in 0..16) {
            let nibble = Int64((h >> 60) & 0xF)
            let c = if (nibble < 10) {
                Rune(UInt32(48 + nibble))  // '0'
            } else {
                Rune(UInt32(97 + nibble - 10))  // 'a'
            }
            result += c.toString()
            h <<= 4
        }
        return result
    }
}
