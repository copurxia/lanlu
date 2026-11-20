package cui.media

import std.collection.HashMap
import std.env.getVariable
import std.fs.{File, Path, exists}
import cui.base.{Renderer, Texture, texturePixelsSink}

/*
 * Process-wide image texture cache, keyed by file path (or an embedded-asset key) and scoped to
 * one renderer (the single window a `DesktopApp` drives). `ImageView` declares images inline in
 * the per-frame rebuild; lookups hit this cache instead of the disk, so no hoisting or manual
 * resource management is needed. Entries live until explicitly invalidated — desktop apps use a
 * small, stable set of images, and an eviction policy would trade a bounded texture pool for disk
 * churn. A failed load is cached as `None` so a missing file is not retried every frame; call
 * `invalidateImage` after (re)writing the file to retry. UI-thread only, like the rest of the
 * framework.
 *
 * 解码口径（2026-11-17 收口）：**所有**图片解码都走 lcodec，没有第二条路径。
 *   - 文件路径  → lcodec.decodeFileToRgba（设备：系统 ImageSource；桌面：系统 libvips）
 *   - 内存字节  → lcodec.decodeBytesToRgba（内嵌资源；同一条管线的字节入口）
 * 框架层（cui / lgui / lgpu）不再自带任何图片解码器，因此纹理尺寸恒为真实像素尺寸、
 * 格式支持范围与业务层（封面 / 阅读页）完全一致。
 */
private var cacheRenderer: ?Renderer = None
private let cachedTextures = HashMap<String, ?Texture>()
// 内嵌资源注册表：key → 图片字节。命中注册表的 key 不读盘，直接从内存解码。
private let registeredBytes = HashMap<String, Array<UInt8>>()

/**
 * Registers in-memory image bytes under `key` so `ImageView` renders embedded assets through the
 * same key-addressed cache as files. Registered keys never touch the disk: the embedded bytes
 * win even if a same-named file exists. Re-registering replaces the source bytes; call
 * `invalidateImage(key)` afterwards if a texture decoded from older bytes may be cached.
 */
public func registerImageBytes(key: String, bytes: Array<UInt8>): Unit {
    registeredBytes[key] = bytes
}

// Returns the cached texture for `path`, loading and caching it (or the failure) on first use.
//
// 失败缓存有例外：**"没有可用的绘制后端"不是图片本身的错**（典型场景是第一帧比 lgpu
// canvas 安装得更早），这种失败不写进缓存，下一帧重试。否则一次时机问题就会让某个图片
// 在整个进程生命周期里永久消失（顶栏 logo 的"永远不出现"曾经可能就是这个形状）。
protected func sharedTexture(renderer: Renderer, path: String): ?Texture {
    adoptRenderer(renderer)
    match (cachedTextures.get(path)) {
        case Some(entry) => entry
        case None =>
            match (decodeTexture(renderer, path)) {
                case Some(texture) =>
                    cachedTextures[path] = Some(texture)
                    Some(texture)
                case None =>
                    if (!uploadBackendReady(renderer)) {
                        return None // 瞬时问题：不缓存，等后端就绪后重试
                    }
                    let failed: ?Texture = None
                    cachedTextures[path] = failed
                    None
            }
    }
}

// 绘制/上传后端是否已就绪（lgpu canvas 已安装，或调用方装了像素 sink）。
private func uploadBackendReady(renderer: Renderer): Bool {
    renderer.backendActive() || texturePixelsSink.isSome()
}

// Textures are only valid on the renderer that created them. When a different renderer shows
// up (a recreated window), the stale entries are dropped WITHOUT closing: SDL destroyed them
// together with their renderer, and closing again would touch freed handles.
private func adoptRenderer(renderer: Renderer): Unit {
    match (cacheRenderer) {
        case Some(existing) =>
            if (!refEq(existing, renderer)) {
                cachedTextures.clear()
                cacheRenderer = Some(renderer)
            }
        case None => cacheRenderer = Some(renderer)
    }
}

// 唯一解码入口：注册过的 key 走内存字节，其余走文件路径；两者最终都由 lcodec 解码。
private func decodeTexture(renderer: Renderer, path: String): ?Texture {
    // A missing, unsupported or corrupt image (or a headless renderer) must not throw out of
    // draw and kill the frame loop; the failure is cached so it is not retried every frame.
    // 诊断口（LANLU_IMG_DIAG=1）：失败必须留痕，否则真机上只会看到"某处空白"。
    try {
        return Some(match (registeredBytes.get(path)) {
            case Some(bytes) => renderer.loadTextureFromBytes(bytes)
            case None => renderer.loadTexture(path)
        })
    } catch (e: Exception) {
        recordDecodeFailure(path, e)
        return None
    }
}

// 解码失败诊断：写 $HOME/img_diag.txt（真机排查用），每个 key 只记第一次。
// 不再要求 LANLU_IMG_DIAG=1——"某张图静默消失"是最难查的一类问题，留痕的成本只有一行文件写。
private func recordDecodeFailure(path: String, error: Exception): Unit {
    try {
        let home = getVariable("HOME") ?? "."
        let p = Path(home + "/img_diag.txt")
        let prev = if (exists(p)) { String.fromUtf8(File.readFrom(p)) } else { "" }
        let line = "[cui] decode failed key=${path} err=${error.message}\n"
        if (!prev.contains(line)) {
            File.writeTo(p, (prev + line).toArray())
        }
    } catch (_: Exception) {}
}

/**
 * Drops the cached texture for `path` (closing it); the next draw decodes it again. Call
 * this after overwriting an image file — including one whose earlier load failed.
 */
public func invalidateImage(path: String): Unit {
    match (cachedTextures.get(path)) {
        case Some(Some(texture)) => texture.close()
        case _ => ()
    }
    let _ = cachedTextures.remove(path)
}

/** Empties the image cache, closing every cached texture; images reload on next draw. */
public func clearImageCache(): Unit {
    for ((_, entry) in cachedTextures) {
        match (entry) {
            case Some(texture) => texture.close()
            case None => ()
        }
    }
    cachedTextures.clear()
}
