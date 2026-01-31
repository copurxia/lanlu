import type { PageInfo } from '@/lib/services/archive-service';
import Image from 'next/image';

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
        // HTML pages (e.g. EPUB) are fetched via useReaderHtmlPages; don't try to preload with <img>.
        if (page.type === 'html') return null;

        if (page.type === 'video') {
          return (
            <video
              key={`preload-${pageIndex}`}
              src={page.url}
              preload="metadata"
              onLoadedData={() => onLoaded(pageIndex)}
              onError={() => onError(pageIndex)}
            />
          );
        }

        return (
          <Image
            key={`preload-${pageIndex}`}
            src={page.url}
            alt=""
            width={1}
            height={1}
            priority
            fetchPriority="high"
            onLoadingComplete={() => {
              onLoaded(pageIndex);
              if (!cachedPages[pageIndex]) {
                onCacheImage(page.url, pageIndex);
              }
            }}
            onError={() => onError(pageIndex)}
          />
        );
      })}
    </div>
  );
}
