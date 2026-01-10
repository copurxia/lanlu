'use client';

import { useCallback, useEffect, useRef, useState } from 'react';
import type React from 'react';
import type { PageInfo } from '@/lib/services/archive-service';
import type { ReadingMode } from '@/hooks/use-reader-settings';

type VisibleRange = { start: number; end: number };

export function useReaderWebtoonVirtualization({
  readingMode,
  pages,
  currentPage,
  setCurrentPage,
  getDeviceInfo,
  getImageHeight,
  webtoonPageElementRefs,
  imageRefs,
  htmlContents,
}: {
  readingMode: ReadingMode;
  pages: PageInfo[];
  currentPage: number;
  setCurrentPage: React.Dispatch<React.SetStateAction<number>>;
  getDeviceInfo: () => { containerWidth: number };
  getImageHeight: (naturalWidth: number, naturalHeight: number) => number;
  webtoonPageElementRefs: React.MutableRefObject<(HTMLDivElement | null)[]>;
  imageRefs: React.MutableRefObject<(HTMLImageElement | null)[]>;
  htmlContents: Record<number, string>;
}) {
  const [visibleRange, setVisibleRange] = useState<VisibleRange>({ start: 0, end: 2 });
  const [imageHeights, setImageHeights] = useState<number[]>([]);
  const [containerHeight, setContainerHeight] = useState(0);

  const scrollTimeoutRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  const calculateVisibleRange = useCallback(
    (scrollTop: number, containerHeightInput: number) => {
      if (pages.length === 0 || imageHeights.length === 0) {
        return { start: 0, end: Math.min(2, pages.length - 1) };
      }

      let accumulatedHeight = 0;
      let startIndex = 0;
      let endIndex = pages.length - 1;
      const bufferHeight = containerHeightInput * 3;

      for (let i = 0; i < pages.length; i++) {
        const imageHeight = imageHeights[i] || containerHeightInput || window.innerHeight * 0.7;

        if (accumulatedHeight + imageHeight > scrollTop - bufferHeight) {
          startIndex = Math.max(0, i - 4);
          break;
        }
        accumulatedHeight += imageHeight;
      }

      accumulatedHeight = 0;
      for (let i = 0; i < pages.length; i++) {
        const imageHeight = imageHeights[i] || containerHeightInput || window.innerHeight * 0.7;
        accumulatedHeight += imageHeight;
        if (accumulatedHeight > scrollTop + containerHeightInput + bufferHeight) {
          endIndex = Math.min(pages.length - 1, i + 4);
          break;
        }
      }

      startIndex = Math.max(0, startIndex);
      endIndex = Math.min(pages.length - 1, endIndex);

      if (endIndex - startIndex < 2 && pages.length > 2) {
        const center = Math.floor((startIndex + endIndex) / 2);
        startIndex = Math.max(0, center - 1);
        endIndex = Math.min(pages.length - 1, center + 1);
      }

      return { start: startIndex, end: endIndex };
    },
    [pages.length, imageHeights]
  );

  const handleWebtoonScroll = useCallback(
    (e: React.UIEvent<HTMLDivElement>) => {
      const container = e.currentTarget;

      if (scrollTimeoutRef.current) {
        clearTimeout(scrollTimeoutRef.current);
      }

      scrollTimeoutRef.current = setTimeout(() => {
        let accumulatedHeight = 0;
        let newPageIndex = 0;

        for (let i = 0; i < pages.length; i++) {
          const imageHeight = imageHeights[i] || containerHeight || window.innerHeight * 0.7;
          accumulatedHeight += imageHeight;
          if (accumulatedHeight > container.scrollTop + container.clientHeight * 0.3) {
            newPageIndex = i;
            break;
          }
        }

        if (newPageIndex !== currentPage && newPageIndex >= 0 && newPageIndex < pages.length) {
          setCurrentPage(newPageIndex);
        }

        const newVisibleRange = calculateVisibleRange(container.scrollTop, container.clientHeight);
        setVisibleRange(newVisibleRange);
        setContainerHeight(container.clientHeight);
      }, 16);
    },
    [calculateVisibleRange, containerHeight, currentPage, imageHeights, pages.length, setCurrentPage]
  );

  useEffect(() => {
    return () => {
      if (scrollTimeoutRef.current) {
        clearTimeout(scrollTimeoutRef.current);
      }
    };
  }, []);

  useEffect(() => {
    if (readingMode !== 'webtoon') return;

    requestAnimationFrame(() => {
      for (let i = visibleRange.start; i <= visibleRange.end; i += 1) {
        if (pages[i]?.type !== 'html') continue;
        const el = webtoonPageElementRefs.current[i];
        if (!el) continue;
        const measured = Math.ceil(el.getBoundingClientRect().height);
        if (!measured || measured <= 0) continue;

        setImageHeights((prev) => {
          const current = prev[i];
          if (current && Math.abs(current - measured) <= 2) return prev;
          const next = [...prev];
          next[i] = measured;
          return next;
        });
      }
    });
  }, [readingMode, visibleRange, pages, htmlContents, webtoonPageElementRefs]);

  useEffect(() => {
    if (pages.length > 0 && imageHeights.length !== pages.length) {
      const { containerWidth } = getDeviceInfo();
      const defaultHeight = Math.min(window.innerHeight * 0.7, containerWidth * 1.5);
      setImageHeights(new Array(pages.length).fill(defaultHeight));

      const viewportHeight = window.innerHeight - 100;
      setContainerHeight(viewportHeight);

      setVisibleRange({ start: 0, end: Math.min(3, pages.length - 1) });
    }
  }, [pages.length, imageHeights.length, getDeviceInfo]);

  useEffect(() => {
    if (readingMode !== 'webtoon') return;

    imageRefs.current.forEach((img, index) => {
      if (img && img.complete && img.naturalHeight > 0 && !imageHeights[index]) {
        const imageHeight = getImageHeight(img.naturalWidth, img.naturalHeight);

        setImageHeights((prev) => {
          const newHeights = [...prev];
          newHeights[index] = imageHeight;
          return newHeights;
        });
      }
    });
  }, [readingMode, imageHeights, getImageHeight, imageRefs]);

  return {
    visibleRange,
    imageHeights,
    setImageHeights,
    containerHeight,
    handleWebtoonScroll,
    setVisibleRange,
    setContainerHeight,
  } as const;
}

