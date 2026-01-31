/* eslint-disable react-hooks/immutability */
import { HtmlRenderer } from '@/components/ui/html-renderer';
import { Spinner } from '@/components/ui/spinner';
import { MemoizedImage, MemoizedVideo } from '@/components/reader/components/MemoizedMedia';
import { getTapTurnAction } from '@/components/reader/hooks/useReaderInteractionHandlers';
import type { PageInfo } from '@/lib/services/archive-service';
import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import type React from 'react';

const LONG_PAGE_ASPECT_RATIO = 2.2;
const DRAG_SCROLL_THRESHOLD_PX = 6;

export function ReaderSingleModeView({
  enabled,
  sidebarOpen,
  readerAreaRef,
  tapTurnPageEnabled,
  longPageEnabled,
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
  readerAreaRef: React.RefObject<HTMLDivElement | null>;
  tapTurnPageEnabled: boolean;
  longPageEnabled: boolean;
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
  const [imageMeta, setImageMeta] = useState<Record<number, { w: number; h: number; isLong: boolean }>>({});
  const spreadViewportRef = useRef<HTMLDivElement | null>(null);
  const [spreadViewportSize, setSpreadViewportSize] = useState({ w: 0, h: 0 });

  const registerImageMeta = useCallback((pageIndex: number, img: HTMLImageElement) => {
    const w = img.naturalWidth || img.width;
    const h = img.naturalHeight || img.height;
    if (!w || !h) return;

    const isLong = h / w >= LONG_PAGE_ASPECT_RATIO;
    setImageMeta((prev) => {
      const existing = prev[pageIndex];
      if (existing && existing.w === w && existing.h === h && existing.isLong === isLong) return prev;
      return { ...prev, [pageIndex]: { w, h, isLong } };
    });
  }, []);

  const isSingleImageLayout = !doublePageMode || (doublePageMode && splitCoverMode && currentPage === 0);
  const currentMeta = imageMeta[currentPage];
  const useLongPageScroll = Boolean(longPageEnabled && isSingleImageLayout && currentMeta?.isLong);
  const shouldTransform = scale !== 1 || translateX !== 0 || translateY !== 0;
  const isDoubleSpread =
    doublePageMode && !(splitCoverMode && currentPage === 0) && currentPage + 1 < pages.length;

  useEffect(() => {
    const el = spreadViewportRef.current;
    if (!el) return;

    const update = () => {
      // Use content box size; transforms are applied on a different wrapper.
      setSpreadViewportSize({ w: el.clientWidth, h: el.clientHeight });
    };

    update();

    if (typeof ResizeObserver === 'undefined') {
      window.addEventListener('resize', update);
      return () => {
        window.removeEventListener('resize', update);
      };
    }

    const ro = new ResizeObserver(update);
    ro.observe(el);
    window.addEventListener('resize', update);
    return () => {
      ro.disconnect();
      window.removeEventListener('resize', update);
    };
  }, [sidebarOpen]);

  const spreadLayout = useMemo(() => {
    if (!isDoubleSpread) return null;
    if (pages[currentPage]?.type !== 'image' || pages[currentPage + 1]?.type !== 'image') return null;
    const left = imageMeta[currentPage];
    const right = imageMeta[currentPage + 1];
    if (!left || !right) return null;
    if (spreadViewportSize.w <= 0 || spreadViewportSize.h <= 0) return null;

    // Fit both pages into the available viewport. Prefer fitting by height to create side margins.
    const scaleByHeight = Math.min(spreadViewportSize.h / left.h, spreadViewportSize.h / right.h);
    const scaleByWidth = spreadViewportSize.w / (left.w + right.w);
    const s = Math.min(scaleByHeight, scaleByWidth);

    const leftW = Math.max(1, Math.floor(left.w * s));
    const leftH = Math.max(1, Math.floor(left.h * s));
    const rightW = Math.max(1, Math.floor(right.w * s));
    const rightH = Math.max(1, Math.floor(right.h * s));
    const groupH = Math.max(leftH, rightH);

    return {
      leftW,
      rightW,
      groupH,
      // Keep the wrapper width exact so there is no seam between pages.
      groupW: leftW + rightW,
    };
  }, [imageMeta, isDoubleSpread, pages, currentPage, spreadViewportSize.h, spreadViewportSize.w]);

  const dragStateRef = useRef<{
    active: boolean;
    dragging: boolean;
    pointerId: number | null;
    startX: number;
    startY: number;
    startScrollTop: number;
    startScrollLeft: number;
    suppressClick: boolean;
  }>({
    active: false,
    dragging: false,
    pointerId: null,
    startX: 0,
    startY: 0,
    startScrollTop: 0,
    startScrollLeft: 0,
    suppressClick: false,
  });

  if (!enabled) return null;

  const handleLongPagePointerDown = (e: React.PointerEvent<HTMLDivElement>) => {
    if (!useLongPageScroll) return;
    if (e.pointerType === 'touch') return; // touch uses native scrolling; don't fight it
    if (e.button !== 0) return;

    if (tapTurnPageEnabled) {
      const action = getTapTurnAction(readerAreaRef.current, e.clientX, e.clientY);
      if (action === 'prev' || action === 'next') return; // edges are reserved for page turning
    }

    const el = e.currentTarget;
    dragStateRef.current.active = true;
    dragStateRef.current.dragging = false;
    dragStateRef.current.pointerId = e.pointerId;
    dragStateRef.current.startX = e.clientX;
    dragStateRef.current.startY = e.clientY;
    dragStateRef.current.startScrollTop = el.scrollTop;
    dragStateRef.current.startScrollLeft = el.scrollLeft;
    dragStateRef.current.suppressClick = false;

    // Capture so we keep getting move/up even if pointer leaves the container.
    el.setPointerCapture(e.pointerId);
  };

  const handleLongPagePointerMove = (e: React.PointerEvent<HTMLDivElement>) => {
    if (!useLongPageScroll) return;
    const state = dragStateRef.current;
    if (!state.active || state.pointerId !== e.pointerId) return;

    const dx = e.clientX - state.startX;
    const dy = e.clientY - state.startY;

    if (!state.dragging) {
      if (Math.abs(dx) < DRAG_SCROLL_THRESHOLD_PX && Math.abs(dy) < DRAG_SCROLL_THRESHOLD_PX) return;
      state.dragging = true;
      state.suppressClick = true;
    }

    e.preventDefault();
    e.stopPropagation();

    const el = e.currentTarget;
    el.scrollTop = state.startScrollTop - dy;
    el.scrollLeft = state.startScrollLeft - dx;
  };

  const finishLongPageDrag = (e: React.PointerEvent<HTMLDivElement>) => {
    if (!useLongPageScroll) return;
    const state = dragStateRef.current;
    if (!state.active || state.pointerId !== e.pointerId) return;

    if (state.dragging) {
      // Prevent the drag from becoming a click that toggles UI / turns page.
      e.preventDefault();
      e.stopPropagation();
    }

    state.active = false;
    state.dragging = false;
    state.pointerId = null;
  };

  const handleLongPageClickCapture = (e: React.MouseEvent<HTMLDivElement>) => {
    if (!useLongPageScroll) return;
    if (!dragStateRef.current.suppressClick) return;
    dragStateRef.current.suppressClick = false;
    e.preventDefault();
    e.stopPropagation();
  };

  return (
    <div
      className={`w-full h-full transition-all duration-300 ${
        sidebarOpen ? 'pl-[280px] sm:pl-[320px]' : 'pl-0'
      }`}
    >
      <div ref={spreadViewportRef} className="flex items-center justify-center w-full h-full relative">
        {doublePageMode &&
          ((imagesLoading.has(currentPage) && !loadedImages.has(currentPage)) ||
            (currentPage + 1 < pages.length &&
              imagesLoading.has(currentPage + 1) &&
              !loadedImages.has(currentPage + 1))) &&
          !loadedImages.has(currentPage) && (
            <div className="absolute inset-0 flex items-center justify-center z-20 pointer-events-none">
              <Spinner size="lg" className="drop-shadow-md" />
            </div>
          )}

        <div
          className="relative flex items-center justify-center w-full h-full"
          style={{
            maxHeight: '100%',
            height: '100%',
            transform:
              doublePageMode && !useLongPageScroll && shouldTransform
                ? `scale(${scale}) translate(${translateX}px, ${translateY}px)`
                : 'none',
            transition: doublePageMode && !useLongPageScroll && shouldTransform ? 'transform 300ms ease-in-out' : 'none',
            cursor: doublePageMode && !useLongPageScroll && scale > 1 ? 'grab' : 'default',
          }}
        >
          {spreadLayout ? (
            <div
              className="flex items-center justify-center h-full w-full"
              style={{ maxHeight: '100%' }}
            >
              <div
                className="flex items-stretch justify-center"
                style={{ width: spreadLayout.groupW, height: spreadLayout.groupH }}
              >
                <div className="relative" style={{ width: spreadLayout.leftW, height: spreadLayout.groupH }}>
                  <MemoizedImage
                    key={`page-${currentPage}`}
                    src={cachedPages[currentPage] || pages[currentPage]?.url}
                    alt={t('reader.pageAlt').replace('{page}', String(currentPage + 1))}
                    fill
                    priority
                    sizes="(max-width: 1024px) 95vw, 800px"
                    decoding="async"
                    className="block object-contain select-none touch-none w-full h-full transition-opacity duration-300 ease-in-out"
                    style={{
                      opacity: loadedImages.has(currentPage) ? 1 : 0.3,
                      cursor: 'pointer',
                    }}
                    onLoadingComplete={(img) => {
                      imageRefs.current[currentPage] = img;
                      imageRequestUrls.current[currentPage] = img.currentSrc || img.src;
                      registerImageMeta(currentPage, img);
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
                </div>

                <div className="relative" style={{ width: spreadLayout.rightW, height: spreadLayout.groupH }}>
                  <MemoizedImage
                    key={`page-${currentPage + 1}`}
                    src={cachedPages[currentPage + 1] || pages[currentPage + 1]?.url}
                    alt={t('reader.pageAlt').replace('{page}', String(currentPage + 2))}
                    fill
                    sizes="(max-width: 1024px) 95vw, 800px"
                    decoding="async"
                    className="block object-contain select-none touch-none w-full h-full transition-opacity duration-300 ease-in-out"
                    style={{
                      opacity: loadedImages.has(currentPage + 1) ? 1 : 0.3,
                      cursor: 'pointer',
                    }}
                    onLoadingComplete={(img) => {
                      imageRefs.current[currentPage + 1] = img;
                      imageRequestUrls.current[currentPage + 1] = img.currentSrc || img.src;
                      registerImageMeta(currentPage + 1, img);
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
                </div>
              </div>
            </div>
          ) : (
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
                      transform: !doublePageMode && shouldTransform ? `scale(${scale}) translate(${translateX}px, ${translateY}px)` : undefined,
                      transition: !doublePageMode && shouldTransform ? 'transform 0.1s ease-out' : undefined,
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
                  <div
                    className={
                      useLongPageScroll
                        ? 'long-page-scroll-container w-full h-full overflow-y-auto overflow-x-hidden flex justify-center cursor-grab active:cursor-grabbing'
                        : 'w-full h-full'
                    }
                    onPointerDown={handleLongPagePointerDown}
                    onPointerMove={handleLongPagePointerMove}
                    onPointerUp={finishLongPageDrag}
                    onPointerCancel={finishLongPageDrag}
                    onPointerLeave={finishLongPageDrag}
                    onClickCapture={handleLongPageClickCapture}
                  >
                    <div className={useLongPageScroll ? 'w-full lg:max-w-[800px] lg:px-4' : 'w-full h-full'}>
                      <MemoizedImage
                        key={`page-${currentPage}`}
                        src={cachedPages[currentPage] || pages[currentPage]?.url}
                        alt={t('reader.pageAlt').replace('{page}', String(currentPage + 1))}
                        {...(useLongPageScroll && currentMeta
                          ? { width: currentMeta.w, height: currentMeta.h }
                          : { fill: true })}
                        priority
                        sizes="(max-width: 1024px) 95vw, 800px"
                        decoding="async"
                        className={`
                          ${
                            useLongPageScroll
                              ? 'w-full h-auto'
                              : doublePageMode && !(splitCoverMode && currentPage === 0)
                                ? 'object-cover'
                                : 'object-contain'
                          }
                          select-none ${useLongPageScroll ? 'touch-pan-y' : 'touch-none'}
                          transition-opacity duration-300 ease-in-out
                          ${useLongPageScroll ? '' : 'w-full h-full'}
                          ${doublePageMode && !useLongPageScroll ? 'max-h-full' : ''}
                        `}
                        style={{
                          maxHeight: useLongPageScroll ? undefined : '100%',
                          height: useLongPageScroll ? 'auto' : '100%',
                          opacity: loadedImages.has(currentPage) ? 1 : 0.3,
                          // For long pages, scrolling is the primary navigation; keep transforms minimal.
                          transform: useLongPageScroll
                            ? shouldTransform
                              ? `scale(${scale})`
                              : undefined
                            : !doublePageMode && shouldTransform
                              ? `scale(${scale}) translate(${translateX}px, ${translateY}px)`
                              : undefined,
                          transformOrigin: useLongPageScroll ? 'top center' : undefined,
                          transition: !doublePageMode && shouldTransform ? 'transform 0.1s ease-out' : undefined,
                          cursor: doublePageMode ? 'pointer' : scale > 1 ? 'grab' : 'default',
                        }}
                        onLoadingComplete={(img) => {
                          imageRefs.current[currentPage] = img;
                          imageRequestUrls.current[currentPage] = img.currentSrc || img.src;
                          registerImageMeta(currentPage, img);
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
                    </div>
                  </div>
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
                      sizes="(max-width: 1024px) 95vw, 800px"
                      decoding="async"
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
                        registerImageMeta(currentPage + 1, img);
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
          )}
        </div>
      </div>
    </div>
  );
}
