/* eslint-disable react-hooks/immutability */
import { HtmlRenderer } from '@/components/ui/html-renderer';
import { Spinner } from '@/components/ui/spinner';
import { MemoizedImage, MemoizedVideo } from '@/components/reader/components/MemoizedMedia';
import type { PageInfo } from '@/lib/services/archive-service';
import type React from 'react';

export function ReaderWebtoonModeView({
  enabled,
  webtoonContainerRef,
  sidebarOpen,
  onScroll,
  pages,
  cachedPages,
  visibleRange,
  imageHeights,
  containerHeight,
  prefixHeights,
  totalHeight,
  imagesLoading,
  loadedImages,
  scale,
  translateX,
  translateY,
  htmlContents,
  webtoonPageElementRefs,
  imageRefs,
  videoRefs,
  htmlContainerRefs,
  imageRequestUrls,
  onImageLoaded,
  onImageError,
  onCacheImage,
  onMeasureImageHeight,
  onDoubleClick,
  onImageDragStart,
  t,
}: {
  enabled: boolean;
  webtoonContainerRef: React.RefObject<HTMLDivElement | null>;
  sidebarOpen: boolean;
  onScroll: (e: React.UIEvent<HTMLDivElement>) => void;
  pages: PageInfo[];
  cachedPages: string[];
  visibleRange: { start: number; end: number };
  imageHeights: number[];
  containerHeight: number;
  prefixHeights: number[];
  totalHeight: number;
  imagesLoading: Set<number>;
  loadedImages: Set<number>;
  scale: number;
  translateX: number;
  translateY: number;
  htmlContents: Record<number, string>;
  webtoonPageElementRefs: React.MutableRefObject<(HTMLDivElement | null)[]>;
  imageRefs: React.MutableRefObject<(HTMLImageElement | null)[]>;
  videoRefs: React.MutableRefObject<(HTMLVideoElement | null)[]>;
  htmlContainerRefs: React.MutableRefObject<(HTMLDivElement | null)[]>;
  imageRequestUrls: React.MutableRefObject<(string | null)[]>;
  onImageLoaded: (pageIndex: number) => void;
  onImageError: (pageIndex: number) => void;
  onCacheImage: (url: string, pageIndex: number) => void;
  onMeasureImageHeight?: (pageIndex: number, naturalWidth: number, naturalHeight: number) => void;
  onDoubleClick: (e: React.MouseEvent) => void;
  onImageDragStart: (e: React.DragEvent) => void;
  t: (key: string) => string;
}) {
  if (!enabled) return null;

  const shouldTransform = scale !== 1 || translateX !== 0 || translateY !== 0;
  const transform = shouldTransform ? `scale(${scale}) translate(${translateX}px, ${translateY}px)` : undefined;
  const transformTransition = shouldTransform ? 'transform 0.1s ease-out' : undefined;

  const estimatedTotalHeight = totalHeight || pages.length * (containerHeight || window.innerHeight * 0.7);
  const topSpacerHeight = prefixHeights[visibleRange.start] || 0;
  const afterEndOffset = prefixHeights[visibleRange.end + 1] ?? estimatedTotalHeight;
  const bottomSpacerHeight = Math.max(0, estimatedTotalHeight - afterEndOffset);

  return (
    <div
      ref={webtoonContainerRef}
      className={`h-full overflow-y-auto overflow-x-hidden transition-all duration-250 ease-out ${
        sidebarOpen ? 'pl-[280px] sm:pl-[320px]' : 'pl-0'
      }`}
      onScroll={onScroll}
    >
      <div
        className="flex flex-col items-center mx-auto relative"
        style={{
          height: `${estimatedTotalHeight}px`,
          maxWidth: window.innerWidth >= 1024 ? '800px' : '1200px',
          width: '100%',
          padding: window.innerWidth >= 1024 ? '0 1rem' : '0',
        }}
      >
        {visibleRange.start > 0 && (
          <div
            style={{
              height: `${topSpacerHeight}px`,
              minHeight: '1px',
            }}
            className="w-full"
          />
        )}

        {(() => {
          const elements = [];
          let i = visibleRange.start;

          while (i <= visibleRange.end) {
            const actualIndex = i;
            const page = pages[actualIndex];
            const imageHeight = imageHeights[actualIndex] || containerHeight || window.innerHeight * 0.7;

            if (page) {
              elements.push(
                <div key={actualIndex} className="relative w-full">
                  {imagesLoading.has(actualIndex) && !loadedImages.has(actualIndex) && (
                    <div
                      className="absolute inset-0 flex items-center justify-center z-20 pointer-events-none"
                      style={{
                        height: `${imageHeight}px`,
                        minHeight: '100px',
                      }}
                    >
                      <Spinner size="lg" className="drop-shadow-md" />
                    </div>
                  )}

                  <div
                    className="relative flex justify-center w-full"
                    ref={(el) => {
                      webtoonPageElementRefs.current[actualIndex] = el;
                    }}
                    style={
                      page.type === 'html'
                        ? { minHeight: '100px' }
                        : {
                            height: `${imageHeight}px`,
                            minHeight: '100px',
                          }
                    }
                  >
                    <div className="relative w-full h-full flex justify-center">
                      {page.type === 'video' ? (
                        <MemoizedVideo
                          key={`page-${actualIndex}`}
                          src={page.url}
                          ref={(el) => {
                            videoRefs.current[actualIndex] = el;
                          }}
                          className="object-contain select-none"
                          style={{
                            maxWidth: '100%',
                            maxHeight: '100%',
                            width: 'auto',
                            height: 'auto',
                            display: 'block',
                            margin: '0 auto',
                            opacity: 1,
                          }}
                          onLoadedData={() => onImageLoaded(actualIndex)}
                          onError={() => onImageError(actualIndex)}
                        />
                      ) : page.type === 'html' ? (
                        <div
                          ref={(el) => {
                            htmlContainerRefs.current[actualIndex] = el;
                          }}
                          className="w-full bg-white"
                        >
                          {htmlContents[actualIndex] ? (
                            <HtmlRenderer
                              html={htmlContents[actualIndex]}
                              className="max-w-4xl mx-auto p-4"
                              scrollable={false}
                            />
                          ) : (
                            <div className="p-6 flex items-center justify-center">
                              <Spinner />
                            </div>
                          )}
                        </div>
	                      ) : (
	                        <MemoizedImage
	                          key={`page-${actualIndex}`}
	                          ref={(el) => {
	                            imageRefs.current[actualIndex] = el;
	                          }}
	                          src={cachedPages[actualIndex] || page.url}
	                          alt={t('reader.pageAlt').replace('{page}', String(actualIndex + 1))}
	                          decoding="async"
	                          loading="lazy"
	                          className="absolute inset-0 object-contain select-none w-full h-full"
	                          style={{
	                            opacity: 1,
	                            transform,
	                            transition: transformTransition,
	                            cursor: scale > 1 ? 'grab' : 'default',
	                          }}
	                          onLoad={(e) => {
	                            const img = e.currentTarget;
	                            imageRequestUrls.current[actualIndex] = img.currentSrc || img.src;
	                            if (img.naturalWidth > 0 && img.naturalHeight > 0) {
	                              onMeasureImageHeight?.(actualIndex, img.naturalWidth, img.naturalHeight);
	                            }
	                            onImageLoaded(actualIndex);
	                            if (!cachedPages[actualIndex]) {
	                              onCacheImage(page.url, actualIndex);
	                            }
	                          }}
	                          onError={() => onImageError(actualIndex)}
	                          onDoubleClick={onDoubleClick}
	                          onDragStart={onImageDragStart}
	                          draggable={false}
	                        />
	                      )}
                    </div>
                  </div>
                </div>
              );
            }
            i += 1;
          }

          return elements;
        })()}

        {visibleRange.end < pages.length - 1 && (
          <div
            style={{
              height: `${bottomSpacerHeight}px`,
              minHeight: '1px',
            }}
            className="w-full"
          />
        )}
      </div>
    </div>
  );
}
