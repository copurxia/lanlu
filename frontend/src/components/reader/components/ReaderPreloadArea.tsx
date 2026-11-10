import { useEffect } from 'react';
import { ArchiveService, type PageInfo } from '@/lib/services/archive-service';

/**
 * 预加载图片时只取字节，不进解码器。
 *
 * 旧实现用 <img width=1 height=1> 预加载：HTML 的 width/height 只影响布局，
 * 浏览器仍按原图分辨率解码（6336x9504 的页面约 230MB/张），一次预加载 6 张
 * 就是 ~1.4GB，弱网/低内存设备上表现为部分图片加载失败、显示错乱甚至崩溃。
 * 这里改用 fetch 把响应写入 HTTP 缓存（响应带 private, max-age=3600），
 * 后续真正显示时 <img> 直接命中缓存，内存开销接近零。
 */
function PreloadImageFetch({
  src,
  onLoaded,
  onError,
}: {
  src: string;
  onLoaded: () => void;
  onError: () => void;
}) {
  useEffect(() => {
    if (!src) return;
    const controller = new AbortController();
    let cancelled = false;
    fetch(src, { credentials: 'include', signal: controller.signal })
      .then((response) => {
        if (!response.ok) {
          throw new Error(`preload failed: ${response.status}`);
        }
        // 读完 body 以便浏览器完成缓存写入；不创建 Image/Bitmap，避免解码
        return response.arrayBuffer();
      })
      .then(() => {
        if (!cancelled) onLoaded();
      })
      .catch(() => {
        if (!cancelled && !controller.signal.aborted) onError();
      });
    return () => {
      cancelled = true;
      controller.abort();
    };
    // onLoaded/onError 由调用方按 index 生成，随 src 变化即可
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [src]);

  return null;
}

export function ReaderPreloadArea({
  enabled,
  imagesLoading,
  currentPage,
  doublePageMode,
  pages,
  cachedPages,
  onLoaded,
  onError,
  onCacheImage,
}: {
  enabled: boolean;
  imagesLoading: Set<number>;
  currentPage: number;
  doublePageMode: boolean;
  pages: PageInfo[];
  cachedPages: string[];
  onLoaded: (pageIndex: number) => void;
  onError: (pageIndex: number) => void;
  onCacheImage: (url: string, pageIndex: number) => void;
}) {
  if (!enabled) return null;

  return (
    <div className="hidden">
      {Array.from(imagesLoading).map((pageIndex) => {
        if (pageIndex === currentPage) return null;
        if (doublePageMode && pageIndex === currentPage + 1) return null;
        const page = pages[pageIndex];
        if (!page) return null;
        const pageUrl = ArchiveService.getResolvedPageUrl(page);
        // HTML pages (e.g. EPUB) are fetched by useReaderHtmlPages; don't try to preload with <img>.
        if (page.type === 'html') return null;

        if (page.type === 'video') {
          return (
            <video
              key={`preload-${pageIndex}`}
              src={pageUrl}
              preload="metadata"
              onLoadedData={() => onLoaded(pageIndex)}
              onError={() => onError(pageIndex)}
            />
          );
        }

        if (page.type === 'audio') {
          return (
            <audio
              key={`preload-${pageIndex}`}
              src={pageUrl}
              preload="metadata"
              onLoadedData={() => onLoaded(pageIndex)}
              onError={() => onError(pageIndex)}
            />
          );
        }

        return (
          <PreloadImageFetch
            key={`preload-${pageIndex}`}
            src={pageUrl}
            onLoaded={() => {
              onLoaded(pageIndex);
              if (!cachedPages[pageIndex] && pageUrl) {
                onCacheImage(pageUrl, pageIndex);
              }
            }}
            onError={() => onError(pageIndex)}
          />
        );
      })}
    </div>
  );
}
