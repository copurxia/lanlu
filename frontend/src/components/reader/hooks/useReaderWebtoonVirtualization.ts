'use client';

import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import type React from 'react';
import type { PageInfo } from '@/lib/services/archive-service';
import type { ReadingMode } from '@/hooks/use-reader-settings';

type VisibleRange = { start: number; end: number };

export function useReaderWebtoonVirtualization({
  readingMode,
  pages,
  currentPage,
  setCurrentPage,
  virtualLength,
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
  virtualLength?: number;
  getDeviceInfo: () => { containerWidth: number };
  getImageHeight: (naturalWidth: number, naturalHeight: number) => number;
  webtoonPageElementRefs: React.MutableRefObject<(HTMLDivElement | null)[]>;
  imageRefs: React.MutableRefObject<(HTMLImageElement | null)[]>;
  htmlContents: Record<number, string>;
}) {
  const [visibleRange, setVisibleRange] = useState<VisibleRange>({ start: 0, end: 2 });
  const [imageHeights, setImageHeights] = useState<number[]>([]);
  const [containerHeight, setContainerHeight] = useState(0);

  const realLength = pages.length;
  const effectiveLength = Math.max(0, virtualLength ?? realLength);

  const rafRef = useRef<number | null>(null);
  const lastVisibleRangeRef = useRef<VisibleRange>(visibleRange);
  const currentPageRef = useRef(currentPage);
  const containerHeightRef = useRef(containerHeight);

  useEffect(() => {
    lastVisibleRangeRef.current = visibleRange;
  }, [visibleRange]);

  useEffect(() => {
    currentPageRef.current = currentPage;
  }, [currentPage]);

  useEffect(() => {
    containerHeightRef.current = containerHeight;
  }, [containerHeight]);

  const prefixHeights = useMemo(() => {
    const out = new Array(imageHeights.length + 1);
    out[0] = 0;
    for (let i = 0; i < imageHeights.length; i += 1) {
      out[i + 1] = out[i] + (imageHeights[i] || 0);
    }
    return out;
  }, [imageHeights]);

  const totalHeight = prefixHeights[prefixHeights.length - 1] || 0;

  const findIndexAtOffset = useCallback(
    (offset: number) => {
      const n = effectiveLength;
      if (n <= 0) return 0;
      if (offset <= 0) return 0;
      if (offset >= totalHeight) return n - 1;

      // Binary search for the greatest i such that prefixHeights[i] <= offset.
      let lo = 0;
      let hi = n;
      while (lo < hi) {
        const mid = (lo + hi) >> 1;
        if (prefixHeights[mid] <= offset) lo = mid + 1;
        else hi = mid;
      }
      return Math.max(0, Math.min(n - 1, lo - 1));
    },
    [effectiveLength, prefixHeights, totalHeight]
  );

  const calculateVisibleRange = useCallback(
    (scrollTop: number, containerHeightInput: number) => {
      if (effectiveLength === 0 || imageHeights.length === 0) {
        return { start: 0, end: Math.min(2, effectiveLength - 1) };
      }

      const bufferHeight = containerHeightInput * 3;
      const startIndex = Math.max(0, findIndexAtOffset(scrollTop - bufferHeight) - 4);
      const endIndex = Math.min(effectiveLength - 1, findIndexAtOffset(scrollTop + containerHeightInput + bufferHeight) + 4);

      if (endIndex - startIndex < 2 && effectiveLength > 2) {
        const center = Math.floor((startIndex + endIndex) / 2);
        return {
          start: Math.max(0, center - 1),
          end: Math.min(effectiveLength - 1, center + 1),
        };
      }

      return { start: Math.max(0, startIndex), end: Math.min(effectiveLength - 1, endIndex) };
    },
    [effectiveLength, findIndexAtOffset, imageHeights.length]
  );

  const handleWebtoonScroll = useCallback(
    (e: React.UIEvent<HTMLDivElement>) => {
      const container = e.currentTarget;
      if (rafRef.current != null) cancelAnimationFrame(rafRef.current);
      rafRef.current = requestAnimationFrame(() => {
        rafRef.current = null;

        const scrollTop = container.scrollTop;
        const clientHeight = container.clientHeight;
        const threshold = scrollTop + clientHeight * 0.3;
        const newPageIndex = findIndexAtOffset(threshold);

        if (newPageIndex !== currentPageRef.current && newPageIndex >= 0 && newPageIndex < effectiveLength) {
          setCurrentPage(newPageIndex);
        }

        const newVisibleRange = calculateVisibleRange(scrollTop, clientHeight);
        const prevRange = lastVisibleRangeRef.current;
        if (newVisibleRange.start !== prevRange.start || newVisibleRange.end !== prevRange.end) {
          setVisibleRange(newVisibleRange);
        }

        if (Math.abs(clientHeight - containerHeightRef.current) > 1) {
          setContainerHeight(clientHeight);
        }
      });
    },
    [calculateVisibleRange, effectiveLength, findIndexAtOffset, setCurrentPage]
  );

  useEffect(() => {
    return () => {
      if (rafRef.current != null) cancelAnimationFrame(rafRef.current);
    };
  }, []);

  useEffect(() => {
    if (readingMode !== 'webtoon') return;

    requestAnimationFrame(() => {
      for (let i = visibleRange.start; i <= visibleRange.end; i += 1) {
        const el = webtoonPageElementRefs.current[i];
        if (!el) continue;
        const measured = Math.ceil(el.getBoundingClientRect().height);
        if (!measured || measured <= 0) continue;

        // Measure HTML pages and synthetic trailing pages (which don't have a PageInfo).
        if (i < realLength && pages[i]?.type !== 'html') continue;

        setImageHeights((prev) => {
          const current = prev[i];
          if (current && Math.abs(current - measured) <= 2) return prev;
          const next = [...prev];
          next[i] = measured;
          return next;
        });
      }
    });
  }, [readingMode, visibleRange, pages, realLength, htmlContents, webtoonPageElementRefs]);

  useEffect(() => {
    if (effectiveLength > 0 && imageHeights.length !== effectiveLength) {
      const { containerWidth } = getDeviceInfo();
      const defaultHeight = Math.min(window.innerHeight * 0.7, containerWidth * 1.5);
      setImageHeights(new Array(effectiveLength).fill(defaultHeight));

      const viewportHeight = window.innerHeight - 100;
      setContainerHeight(viewportHeight);

      setVisibleRange({ start: 0, end: Math.min(3, effectiveLength - 1) });
    }
  }, [effectiveLength, imageHeights.length, getDeviceInfo]);

  useEffect(() => {
    if (readingMode !== 'webtoon') return;

    imageRefs.current.forEach((img, index) => {
      if (index >= realLength) return;
      if (!img || !img.complete || img.naturalHeight <= 0) return;

      const measuredHeight = getImageHeight(img.naturalWidth, img.naturalHeight);
      setImageHeights((prev) => {
        const current = prev[index];
        // Avoid noisy re-renders; only update when it actually changes.
        if (current && Math.abs(current - measuredHeight) <= 2) return prev;
        const next = [...prev];
        next[index] = measuredHeight;
        return next;
      });
    });
  }, [readingMode, imageHeights, getImageHeight, imageRefs, realLength]);

  return {
    visibleRange,
    imageHeights,
    setImageHeights,
    containerHeight,
    prefixHeights,
    totalHeight,
    handleWebtoonScroll,
    setVisibleRange,
    setContainerHeight,
  } as const;
}
