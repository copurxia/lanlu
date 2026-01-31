import { Book } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Spinner } from '@/components/ui/spinner';
import { MemoizedImage } from '@/components/reader/components/MemoizedMedia';
import type { PageInfo } from '@/lib/services/archive-service';
import type React from 'react';

export function ReaderSidebar({
  open,
  sidebarScrollRef,
  sidebarLoading,
  isEpub,
  sidebarDisplayPages,
  currentPage,
  sidebarImagesLoading,
  pagesLength,
  canLoadMore,
  onSelectPage,
  onLoadMore,
  onThumbLoaded,
  onThumbError,
  t,
}: {
  open: boolean;
  sidebarScrollRef: React.RefObject<HTMLDivElement | null>;
  sidebarLoading: boolean;
  isEpub: boolean;
  sidebarDisplayPages: PageInfo[];
  currentPage: number;
  sidebarImagesLoading: Set<number>;
  pagesLength: number;
  canLoadMore: boolean;
  onSelectPage: (pageIndex: number) => void;
  onLoadMore: () => void;
  onThumbLoaded: (pageIndex: number) => void;
  onThumbError: (pageIndex: number) => void;
  t: (key: string) => string;
}) {
  if (!open) return null;

  return (
    <div
      ref={sidebarScrollRef}
      className="absolute left-0 top-0 bottom-0 w-[280px] sm:w-[320px] bg-background/95 backdrop-blur-sm border-r border-border z-40 flex flex-col"
      onWheel={(e) => e.stopPropagation()}
    >
      <div className="flex-1 overflow-y-auto">
        <div className="p-3">
          {sidebarLoading ? (
            <div className="flex items-center justify-center py-12">
              <Spinner />
            </div>
          ) : isEpub ? (
            <div className="space-y-1">
              {sidebarDisplayPages.map((page, index) => (
                <button
                  key={index}
                  onClick={() => onSelectPage(index)}
                  className={`w-full flex items-center gap-3 p-3 rounded-lg hover:bg-muted transition-colors group text-left ${
                    currentPage === index ? 'bg-accent text-accent-foreground' : ''
                  }`}
                >
                  <span className="flex-shrink-0 w-8 h-8 rounded-full bg-primary/10 text-primary flex items-center justify-center text-sm font-medium">
                    {index + 1}
                  </span>
                  <span className="flex-1 truncate text-sm group-hover:text-primary transition-colors">
                    {page.title || `${t('archive.chapter')} ${index + 1}`}
                  </span>
                  <Book className="w-4 h-4 text-muted-foreground group-hover:text-primary transition-colors" />
                </button>
              ))}
            </div>
          ) : (
            <div className="grid grid-cols-2 md:grid-cols-3 gap-2">
              {sidebarDisplayPages.map((page, index) => {
                const actualPageIndex = index;
                const isLoading = sidebarImagesLoading.has(actualPageIndex);
                const isCurrentPage = currentPage === actualPageIndex;

                return (
                  <button
                    key={actualPageIndex}
                    onClick={() => onSelectPage(actualPageIndex)}
                    className={`group relative aspect-[3/4] bg-muted rounded-lg overflow-hidden hover:ring-2 hover:ring-primary transition-all duration-200 ${
                      isCurrentPage ? 'ring-2 ring-primary' : ''
                    }`}
                  >
                    {isCurrentPage && (
                      <div className="absolute inset-0 bg-primary/10 z-10 flex items-center justify-center">
                        <div className="bg-primary text-primary-foreground text-xs px-2 py-1 rounded-full font-medium">
                          {actualPageIndex + 1}
                        </div>
                      </div>
                    )}

                    {isLoading && (
                      <div className="absolute inset-0 flex items-center justify-center bg-muted/50 z-10">
                        <div className="animate-spin rounded-full h-6 w-6 border-b-2 border-primary" />
                      </div>
                    )}

                    <div className="relative w-full h-full">
                      {page.type === 'video' ? (
                        <video
                          src={page.url}
                          className="w-full h-full object-cover"
                          muted
                          loop
                          playsInline
                          onMouseEnter={(e) => {
                            const video = e.target as HTMLVideoElement;
                            video.play().catch(() => {});
                          }}
                          onMouseLeave={(e) => {
                            const video = e.target as HTMLVideoElement;
                            video.pause();
                            video.currentTime = 0;
                          }}
                        />
                      ) : (
                        <MemoizedImage
                          src={page.url}
                          alt={t('archive.previewPage')
                            .replace('{current}', String(actualPageIndex + 1))
                            .replace('{total}', String(pagesLength))}
                          className={`absolute inset-0 object-contain transition-opacity duration-200 ${
                            isLoading ? 'opacity-0' : 'opacity-100'
                          }`}
                          decoding="async"
                          loading="lazy"
                          onLoad={() => onThumbLoaded(actualPageIndex)}
                          onError={() => onThumbError(actualPageIndex)}
                          draggable={false}
                        />
                      )}
                    </div>

                    <div className="absolute bottom-0 left-0 right-0 bg-black/50 text-white text-xs py-1 px-1 text-center truncate">
                      {actualPageIndex + 1}
                      {page.type === 'video' ? ' 🎬' : ''}
                    </div>
                  </button>
                );
              })}
            </div>
          )}

          {!isEpub && canLoadMore && (
            <div className="mt-4 text-center">
              <Button variant="outline" onClick={onLoadMore} disabled={sidebarLoading} className="w-full">
                {sidebarLoading ? <Spinner className="mr-2" /> : null}
                {t('archive.loadMore')}
              </Button>
            </div>
          )}
        </div>
      </div>
    </div>
  );
}
