package lanlu_client_next.img

/*
 * 解码已统合进 lcodec（packages/lcodec）：本文件只保留业务层兼容面。
 *
 * - decodeFileToRgba / decodeBackdrop / roundCoverAlphaNative 全部转发 lcodec 同名实现
 *   （含新增格式嗅探诊断：解码异常带 format=avif 等，OHOS 真机可直接看出后端缺口）。
 * - decodeCachedOrEvict 与 ImageCache 协作，留在业务层（lcodec 不依赖缓存实现）。
 */

import lcodec.{NativeDecodedImage, decodeBackdrop as lcDecodeBackdrop, decodeFileToRgba as lcDecodeFileToRgba,
    roundCoverAlphaNative as lcRoundCoverAlphaNative}

public func decodeFileToRgba(path: String, maxDimension!: Int32 = 0): NativeDecodedImage {
    lcDecodeFileToRgba(path, maxDimension: maxDimension)
}

public func decodeBackdrop(path: String, targetWidth: Int32, blurSigma!: Float64 = 8.0): NativeDecodedImage {
    lcDecodeBackdrop(path, targetWidth, blurSigma: blurSigma)
}

public func roundCoverAlphaNative(d: NativeDecodedImage): Unit {
    lcRoundCoverAlphaNative(d)
}

// 解码缓存定稿文件（图片管线用）：解码失败说明 .img 字节损坏（如截断的下载），
// 先剔除该 key 的缓存条目再原样抛出——坏字节留在缓存里会让每次重试都命中同一份坏数据。
// 剔除本身的 I/O 失败静默吞掉，保证抛出的始终是原始解码错误。
public func decodeCachedOrEvict(cache: ImageCache, key: String, path: String,
    maxDimension!: Int32 = 0): NativeDecodedImage {
    try {
        return lcDecodeFileToRgba(path, maxDimension: maxDimension)
    } catch (e: Exception) {
        try { cache.evict(key) } catch (_: Exception) { () }
        throw e
    }
}
