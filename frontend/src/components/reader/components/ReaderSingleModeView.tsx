/* eslint-disable react-hooks/immutability */
import { HtmlRenderer } from '@/components/ui/html-renderer';
import { Spinner } from '@/components/ui/spinner';
import { MemoizedImage, MemoizedVideo } from '@/components/reader/components/MemoizedMedia';
import type { PageInfo } from '@/lib/archive-service';
import type React from 'react';

export function ReaderSingleModeView({
  enabled,
  sidebarOpen,
  pages,
  cachedPages,
  currentPage,
  doublePageMode,
  splitCoverMode,
  imagesLoading,
  loadedImages,
  scale,
  translateX,
  translateY,
  htmlContents,
  imageRefs,
  videoRefs,
  htmlContainerRefs,
  imageRequestUrls,
  onImageLoaded,
  onImageError,
  onCacheImage,
  onDoubleClick,
  onImageDragStart,
  t,
}: {
  enabled: boolean;
  sidebarOpen: boolean;
  pages: PageInfo[];
  cachedPages: string[];
  currentPage: number;
  doublePageMode: boolean;
  splitCoverMode: boolean;
  imagesLoading: Set<number>;
  loadedImages: Set<number>;
  scale: number;
  translateX: number;
  translateY: number;
  htmlContents: Record<number, string>;
  imageRefs: React.MutableRefObject<(HTMLImageElement | null)[]>;
  videoRefs: React.MutableRefObject<(HTMLVideoElement | null)[]>;
  htmlContainerRefs: React.MutableRefObject<(HTMLDivElement | null)[]>;
  imageRequestUrls: React.MutableRefObject<(string | null)[]>;
  onImageLoaded: (pageIndex: number) => void;
  onImageError: (pageIndex: number) => void;
  onCacheImage: (url: string, pageIndex: number) => void;
  onDoubleClick: (e: React.MouseEvent) => void;
  onImageDragStart: (e: React.DragEvent) => void;
  t: (key: string) => string;
}) {
  if (!enabled) return null;

  return (
    <div
      className={`w-full h-full transition-all duration-300 ${
        sidebarOpen ? 'pl-[280px] sm:pl-[320px]' : 'pl-0'
      }`}
    >
      <div className="flex items-center justify-center w-full h-full relative">
        {doublePageMode &&
          ((imagesLoading.has(currentPage) && !loadedImages.has(currentPage)) ||
            (currentPage + 1 < pages.length &&
              imagesLoading.has(currentPage + 1) &&
              !loadedImages.has(currentPage + 1))) &&
          !loadedImages.has(currentPage) && (
            <div className="absolute inset-0 flex items-center justify-center z-20 pointer-events-none">
              <div className="bg-background/80 backdrop-blur-sm rounded-full p-3 shadow-lg">
                <Spinner size="lg" />
              </div>
            </div>
          )}

        <div
          className="relative flex items-center justify-center w-full h-full"
          style={{
            maxHeight: '100%',
            height: '100%',
            transform: doublePageMode ? `scale(${scale}) translate(${translateX}px, ${translateY}px)` : 'none',
            transition: 'all 300ms ease-in-out',
            cursor: doublePageMode && scale > 1 ? 'grab' : 'default',
          }}
        >
          <div className="relative w-full h-full flex">
            <div
              className={`relative ${
                doublePageMode && !(splitCoverMode && currentPage === 0) ? 'flex-1' : 'w-full'
              } h-full min-w-0`}
            >
              {pages[currentPage]?.type === 'video' ? (
                <MemoizedVideo
                  key={`page-${currentPage}`}
                  src={pages[currentPage].url}
                  ref={(el) => {
                    videoRefs.current[currentPage] = el;
                  }}
                  className={`
                    ${
                      doublePageMode && !(splitCoverMode && currentPage === 0) ? 'object-cover' : 'object-contain'
                    } select-none touch-none
                    w-full h-full
                    transition-opacity duration-300 ease-in-out
                    ${doublePageMode ? 'max-h-full' : ''}
                  `}
                  style={{
                    maxHeight: '100%',
                    height: '100%',
                    opacity: loadedImages.has(currentPage) ? 1 : 0.3,
                    transform: doublePageMode ? 'none' : `scale(${scale}) translate(${translateX}px, ${translateY}px)`,
                    transition: doublePageMode ? 'none' : 'transform 0.1s ease-out',
                  }}
                  onLoadedData={() => onImageLoaded(currentPage)}
                  onError={() => onImageError(currentPage)}
                />
              ) : pages[currentPage]?.type === 'html' ? (
                <div
                  ref={(el) => {
                    htmlContainerRefs.current[currentPage] = el;
                  }}
                  className="w-full h-full overflow-auto bg-white"
                >
                  <HtmlRenderer html={htmlContents[currentPage] || ''} className="max-w-4xl mx-auto p-4" />
                </div>
              ) : (
                <MemoizedImage
                  key={`page-${currentPage}`}
                  src={cachedPages[currentPage] || pages[currentPage]?.url}
                  alt={t('reader.pageAlt').replace('{page}', String(currentPage + 1))}
                  fill
                  className={`
                    ${
                      doublePageMode && !(splitCoverMode && currentPage === 0) ? 'object-cover' : 'object-contain'
                    } select-none touch-none
                    w-full h-full
                    transition-opacity duration-300 ease-in-out
                    ${doublePageMode ? 'max-h-full' : ''}
                  `}
                  style={{
                    maxHeight: '100%',
                    height: '100%',
                    opacity: loadedImages.has(currentPage) ? 1 : 0.3,
                    transform: doublePageMode ? 'none' : `scale(${scale}) translate(${translateX}px, ${translateY}px)`,
                    transition: doublePageMode ? 'none' : 'transform 0.1s ease-out',
                    cursor: doublePageMode ? 'pointer' : scale > 1 ? 'grab' : 'default',
                  }}
                  onLoadingComplete={(img) => {
                    imageRefs.current[currentPage] = img;
                    imageRequestUrls.current[currentPage] = img.currentSrc || img.src;
                    onImageLoaded(currentPage);
                    if (!cachedPages[currentPage] && pages[currentPage]) {
                      onCacheImage(pages[currentPage].url, currentPage);
                    }
                  }}
                  onError={() => onImageError(currentPage)}
                  onDoubleClick={onDoubleClick}
                  onDragStart={onImageDragStart}
                  draggable={false}
                />
              )}
            </div>

            {doublePageMode && !(splitCoverMode && currentPage === 0) && currentPage + 1 < pages.length && (
              <div className="relative flex-1 h-full min-w-0">
                {pages[currentPage + 1]?.type === 'video' ? (
                  <MemoizedVideo
                    key={`page-${currentPage + 1}`}
                    src={pages[currentPage + 1].url}
                    ref={(el) => {
                      videoRefs.current[currentPage + 1] = el;
                    }}
                    className={`
                      object-cover select-none touch-none
                      w-full h-full
                      transition-opacity duration-300 ease-in-out
                      max-h-full
                    `}
                    style={{
                      maxHeight: '100%',
                      height: '100%',
                      opacity: loadedImages.has(currentPage + 1) ? 1 : 0.3,
                    }}
                    onLoadedData={() => onImageLoaded(currentPage + 1)}
                    onError={() => onImageError(currentPage + 1)}
                  />
                ) : pages[currentPage + 1]?.type === 'html' ? (
                  <div
                    ref={(el) => {
                      htmlContainerRefs.current[currentPage + 1] = el;
                    }}
                    className="w-full h-full overflow-auto bg-white"
                  >
                    <HtmlRenderer html={htmlContents[currentPage + 1] || ''} className="max-w-4xl mx-auto p-4" />
                  </div>
                ) : (
                  <MemoizedImage
                    key={`page-${currentPage + 1}`}
                    src={cachedPages[currentPage + 1] || pages[currentPage + 1]?.url}
                    alt={t('reader.pageAlt').replace('{page}', String(currentPage + 2))}
                    fill
                    className={`
                      object-cover select-none touch-none
                      w-full h-full
                      transition-opacity duration-300 ease-in-out
                      max-h-full
                    `}
                    style={{
                      maxHeight: '100%',
                      height: '100%',
                      opacity: loadedImages.has(currentPage + 1) ? 1 : 0.3,
                      transform: 'none',
                      transition: 'none',
                      cursor: 'pointer',
                    }}
                    onLoadingComplete={(img) => {
                      imageRefs.current[currentPage + 1] = img;
                      imageRequestUrls.current[currentPage + 1] = img.currentSrc || img.src;
                      onImageLoaded(currentPage + 1);
                      if (!cachedPages[currentPage + 1] && pages[currentPage + 1]) {
                        onCacheImage(pages[currentPage + 1].url, currentPage + 1);
                      }
                    }}
                    onError={() => onImageError(currentPage + 1)}
                    onDoubleClick={onDoubleClick}
                    onDragStart={onImageDragStart}
                    draggable={false}
                  />
                )}
              </div>
            )}
          </div>
        </div>
      </div>
    </div>
  );
}
