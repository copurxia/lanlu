'use client';

import { useMemo, useState, useCallback, useRef, useEffect } from 'react';
import { Film, FileText, Music } from 'lucide-react';
import { MemoizedImage } from '@/components/reader/components/MemoizedMedia';
import type { PageInfo } from '@/lib/services/archive-service';
import type React from 'react';

const GRID_GAP_PX = 8;
const OVERSCAN_PX = 480;
const DEFAULT_ASPECT_RATIO = 3 / 4;
const THUMB_IMAGE_CLASS = 'block h-auto w-full transition-opacity duration-200';
const CONTENT_PADDING_CLASS = 'px-3 pb-2 pt-2';
const THUMB_CAPTION_HEIGHT_PX = 34;

type ThumbnailLayoutItem = {
  page: PageInfo;
  index: number;
  top: number;
  left: number;
  mediaHeight: number;
  cardHeight: number;
};

type MasonryThumbnailGridProps = {
  pages: PageInfo[];
  currentPage?: number;
  onSelectPage?: (pageIndex: number) => void;
  isLink?: boolean;
  archiveId?: string;
  t: (key: string) => string;
  className?: string;
};

function getPageCustomTitle(page: PageInfo): string {
  const metaTitle = page.metadata?.title?.trim();
  if (metaTitle) return metaTitle;
  const pageTitle = page.title?.trim();
  if (pageTitle) return pageTitle;
  return '';
}

function getPageDisplayTitle(page: PageInfo, pageIndex: number, t: (key: string) => string): string {
  const customTitle = getPageCustomTitle(page);
  if (customTitle) return customTitle;
  return t('reader.pageAlt').replace('{page}', String(pageIndex + 1));
}

function getPageDisplayThumb(page: PageInfo): string {
  return page.metadata?.thumb?.trim() || '';
}

export function MasonryThumbnailGrid({
  pages,
  currentPage,
  onSelectPage,
  isLink = false,
  archiveId,
  t,
  className = '',
}: MasonryThumbnailGridProps) {
  const [scrollTop, setScrollTop] = useState(0);
  const [viewportHeight, setViewportHeight] = useState(0);
  const [contentWidth, setContentWidth] = useState(0);
  const scrollRef = useRef<HTMLDivElement | null>(null);
  const containerRef = useRef<HTMLDivElement | null>(null);
  const [aspectRatios, setAspectRatios] = useState<Record<string, number>>({});

  const getLayoutKey = useCallback((page: PageInfo, index: number) => {
    const path = String(page.path || '').trim();
    if (path) return path;
    const url = String(page.url || '').trim();
    if (url) return url;
    return `page-${index}`;
  }, []);

  const handleImageLoad = useCallback((page: PageInfo, index: number, image: HTMLImageElement) => {
    const naturalWidth = image.naturalWidth || image.width;
    const naturalHeight = image.naturalHeight || image.height;
    if (!naturalWidth || !naturalHeight) return;

    const nextRatio = naturalWidth / naturalHeight;
    if (!Number.isFinite(nextRatio) || nextRatio <= 0) return;

    const key = getLayoutKey(page, index);
    setAspectRatios((prev) => {
      const prevRatio = prev[key];
      if (prevRatio && Math.abs(prevRatio - nextRatio) < 0.01) {
        return prev;
      }
      return {
        ...prev,
        [key]: nextRatio,
      };
    });
  }, [getLayoutKey]);

  const updateViewport = useCallback(() => {
    const scrollElement = scrollRef.current;
    if (!scrollElement) return;

    // 获取实际的内容宽度（减去padding）
    const computedStyle = window.getComputedStyle(scrollElement);
    const paddingLeft = parseFloat(computedStyle.paddingLeft) || 0;
    const paddingRight = parseFloat(computedStyle.paddingRight) || 0;
    const contentWidth = scrollElement.clientWidth - paddingLeft - paddingRight;

    setViewportHeight(scrollElement.clientHeight);
    setContentWidth(Math.max(0, contentWidth));
  }, []);

  // 初始化时也要更新viewport
  useEffect(() => {
    if (scrollRef.current) {
      updateViewport();
    }
  }, [updateViewport]);

  useEffect(() => {
    const scrollElement = scrollRef.current;
    if (!scrollElement) return;

    updateViewport();
    setScrollTop(scrollElement.scrollTop);

    if (typeof ResizeObserver === 'undefined') {
      window.addEventListener('resize', updateViewport);
      return () => {
        window.removeEventListener('resize', updateViewport);
      };
    }

    const observer = new ResizeObserver(updateViewport);
    observer.observe(scrollElement);
    window.addEventListener('resize', updateViewport);
    return () => {
      observer.disconnect();
      window.removeEventListener('resize', updateViewport);
    };
  }, [updateViewport]);

  const columns = useMemo(() => {
    if (contentWidth < 400) return 2;
    if (contentWidth < 600) return 3;
    if (contentWidth < 900) return 4;
    if (contentWidth < 1200) return 5;
    if (contentWidth < 1600) return 6;
    return 7;
  }, [contentWidth]);

  const itemWidth = useMemo(() => {
    if (columns <= 0) return 0;
    const totalGaps = GRID_GAP_PX * (columns - 1);
    const width = Math.floor((contentWidth - totalGaps) / columns);
    return Math.max(0, width);
  }, [columns, contentWidth]);

  const gridLayout = useMemo(() => {
    if (columns <= 0 || itemWidth <= 0) {
      return { items: [] as ThumbnailLayoutItem[], totalHeight: 0 };
    }

    const columnHeights = Array.from({ length: columns }, () => 0);
    const items: ThumbnailLayoutItem[] = [];

    pages.forEach((page, index) => {
      const key = getLayoutKey(page, index);
      const aspectRatio = aspectRatios[key] || DEFAULT_ASPECT_RATIO;
      const mediaHeight = Math.max(64, Math.round(itemWidth / Math.max(aspectRatio, 0.05)));
      const cardHeight = mediaHeight + THUMB_CAPTION_HEIGHT_PX;

      let column = 0;
      for (let i = 1; i < columnHeights.length; i += 1) {
        if (columnHeights[i] < columnHeights[column]) {
          column = i;
        }
      }

      const top = columnHeights[column];
      const left = column * (itemWidth + GRID_GAP_PX);
      columnHeights[column] += cardHeight + GRID_GAP_PX;

      items.push({
        page,
        index,
        top,
        left,
        mediaHeight,
        cardHeight,
      });
    });

    const totalHeight = Math.max(0, ...columnHeights) - (items.length > 0 ? GRID_GAP_PX : 0);
    return { items, totalHeight };
  }, [getLayoutKey, columns, pages, aspectRatios, itemWidth]);

  const canVirtualize = itemWidth > 0 && viewportHeight > 0;

  const visibleItems = useMemo(() => {
    if (!gridLayout.items.length) return [] as ThumbnailLayoutItem[];
    if (!canVirtualize) return gridLayout.items;

    const minTop = Math.max(0, scrollTop - OVERSCAN_PX);
    const maxBottom = scrollTop + viewportHeight + OVERSCAN_PX;

    return gridLayout.items.filter((item) => item.top + item.cardHeight >= minTop && item.top <= maxBottom);
  }, [canVirtualize, scrollTop, viewportHeight, gridLayout]);

  const renderThumbnailItem = (item: ThumbnailLayoutItem) => {
    const { page, index, top, left, mediaHeight, cardHeight } = item;
    const isCurrentPage = currentPage === index;
    const metadataThumb = getPageDisplayThumb(page);
    const showVideoPreview = page.type === 'video' && !metadataThumb;
    const thumbSrc = metadataThumb || (page.type === 'image' ? page.url : '');
    const showImageThumb = Boolean(thumbSrc);
    const displayTitle = getPageDisplayTitle(page, index, t);
    const hasCustomTitle = getPageCustomTitle(page).length > 0;
    const captionText = hasCustomTitle ? displayTitle : String(index + 1);

    const content = (
      <>
        {isCurrentPage ? <div className="pointer-events-none absolute inset-0 z-10 bg-primary/10" /> : null}

        <div className="pointer-events-none absolute right-2 top-2 z-20 inline-flex items-center gap-1 rounded-full bg-black/65 px-2 py-1 text-[11px] font-medium text-white shadow-sm backdrop-blur-sm">
          <span>{index + 1}</span>
          {page.type === 'video' ? <Film className="h-3 w-3" /> : null}
          {page.type === 'audio' ? <Music className="h-3 w-3" /> : null}
          {page.type === 'html' ? <FileText className="h-3 w-3" /> : null}
        </div>

        <div className="w-full overflow-hidden bg-muted/70" style={{ height: `${mediaHeight}px` }}>
          {showVideoPreview ? (
            <video
              src={page.url}
              className="block h-full w-full object-cover"
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
          ) : showImageThumb ? (
            <MemoizedImage
              src={thumbSrc}
              alt={displayTitle || t('archive.previewPage').replace('{current}', String(index + 1)).replace('{total}', String(pages.length))}
              className={THUMB_IMAGE_CLASS}
              decoding="async"
              loading="lazy"
              draggable={false}
              onLoad={(e) => handleImageLoad(page, index, e.currentTarget)}
            />
          ) : (
            <div className="flex h-full w-full items-center justify-center text-muted-foreground/80">
              {page.type === 'audio' ? <Music className="h-7 w-7" /> : <FileText className="h-7 w-7" />}
            </div>
          )}
        </div>

        <div className="flex min-h-[34px] items-center justify-center border-t border-black/5 bg-background/84 px-2 py-1 text-center backdrop-blur-sm">
          <span className={`block max-w-full text-[11px] leading-snug tracking-tight ${hasCustomTitle ? 'line-clamp-2 font-normal text-foreground/80' : 'truncate text-[10px] text-muted-foreground/80'}`}>
            {captionText}
          </span>
        </div>
      </>
    );

    const baseClassName = `group absolute overflow-hidden rounded-lg bg-muted shadow-sm hover:ring-2 hover:ring-primary transition-all duration-200 ${
      isCurrentPage ? 'ring-2 ring-primary' : ''
    }`;

    if (isLink && archiveId) {
      return (
        <a
          key={index}
          href={`/reader?id=${archiveId}&page=${index + 1}`}
          className={baseClassName}
          style={{
            top,
            left,
            width: `${itemWidth}px`,
            height: `${cardHeight}px`,
          }}
        >
          {content}
        </a>
      );
    }

    return (
      <button
        key={index}
        type="button"
        onClick={() => onSelectPage?.(index)}
        className={baseClassName}
        style={{
          top,
          left,
          width: `${itemWidth}px`,
          height: `${cardHeight}px`,
        }}
      >
        {content}
      </button>
    );
  };

  return (
    <div ref={containerRef} className={className}>
      <div
        ref={scrollRef}
        className="overflow-y-auto h-full"
        onScroll={(e) => setScrollTop(e.currentTarget.scrollTop)}
      >
        <div className={CONTENT_PADDING_CLASS}>
          <div className="relative" style={{ height: `${gridLayout.totalHeight}px` }}>
            {visibleItems.map(renderThumbnailItem)}
          </div>
        </div>
      </div>
    </div>
  );
}
