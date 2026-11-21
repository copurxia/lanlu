'use client';

import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import type React from 'react';
import type { PageInfo } from '@/lib/services/archive-service';
import type { ReadingMode } from '@/hooks/use-reader-settings';

type VisibleRange = { start: number; end: number };

type ReaderVirtualEndPage = {
  type: 'virtual-end';
  archiveId: string;
};

type ReaderWebtoonPage = PageInfo | ReaderVirtualEndPage;

export function useReaderWebtoonVirtualization({
  readingMode,
  pages,
  currentPage,
  setCurrentPage,
  resetKey,
  contentWidth,
  getImageHeight,
  webtoonPageElementRefs,
  imageRefs,
  htmlContents,
}: {
  readingMode: ReadingMode;
  pages: ReaderWebtoonPage[];
  currentPage: number;
  setCurrentPage: React.Dispatch<React.SetStateAction<number>>;
  resetKey?: string | null;
  contentWidth: number;
  getImageHeight: (naturalWidth: number, naturalHeight: number) => number;
  webtoonPageElementRefs: React.MutableRefObject<(HTMLDivElement | null)[]>;
  imageRefs: React.MutableRefObject<(HTMLImageElement | null)[]>;
  htmlContents: Record<number, string>;
}) {
  const [visibleRange, setVisibleRange] = useState<VisibleRange>({ start: 0, end: 2 });
  const [imageHeights, setImageHeights] = useState<number[]>([]);
  const [containerHeight, setContainerHeight] = useState(0);

  const effectiveLength = Math.max(0, pages.length);

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
    setImageHeights([]);
    setVisibleRange({ start: 0, end: 2 });
    setContainerHeight(0);
  }, [resetKey]);

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

        const pageType = pages[i]?.type;
        if (pageType === 'image' || pageType === 'video') continue;

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
    if (effectiveLength <= 0) {
      setImageHeights((prev) => (prev.length === 0 ? prev : []));
      setVisibleRange({ start: 0, end: 2 });
      return;
    }

    const fallbackWidth =
      window.innerWidth >= 1024
        ? Math.min(800, window.innerWidth * 0.8)
        : Math.min(window.innerWidth * 0.95, window.innerWidth);
    const effectiveWidth = contentWidth > 0 ? contentWidth : fallbackWidth;
    const defaultHeight = Math.min(window.innerHeight * 0.7, effectiveWidth * 1.5);

    // Keep measured heights for existing pages and only append defaults for newly appended pages.
    // Full reset here would make the scroll-anchor jump backward when seamless pages are appended.
    setImageHeights((prev) => {
      const next = prev.slice(0, effectiveLength);
      while (next.length < effectiveLength) {
        next.push(defaultHeight);
      }
      if (next.length === prev.length && next.every((h, idx) => h === prev[idx])) {
        return prev;
      }
      return next;
    });

    setContainerHeight((prev) => {
      if (prev > 0) return prev;
      return window.innerHeight - 100;
    });

    setVisibleRange((prev) => {
      const maxIndex = effectiveLength - 1;
      const start = Math.max(0, Math.min(prev.start, maxIndex));
      const end = Math.max(start, Math.min(prev.end, maxIndex));
      if (prev.start === start && prev.end === end) return prev;
      return { start, end };
    });
  }, [contentWidth, effectiveLength]);

  useEffect(() => {
    if (readingMode !== 'webtoon') return;

    setImageHeights((prev) => {
      let changed = false;
      const next = [...prev];

      imageRefs.current.forEach((img, index) => {
        const page = pages[index];
        if (!page || page.type !== 'image') return;
        if (!img || !img.complete || img.naturalHeight <= 0) return;

        const measuredHeight = getImageHeight(img.naturalWidth, img.naturalHeight);
        const current = next[index];
        if (current && Math.abs(current - measuredHeight) <= 2) return;
        next[index] = measuredHeight;
        changed = true;
      });

      return changed ? next : prev;
    });
  }, [readingMode, contentWidth, getImageHeight, imageRefs, pages]);

  return {
    visibleRange,
    imageHeights,
    setImageHeights,
    containerHeight,
    prefixHeights,
    totalHeight,
    handleWebtoonScroll,
    getIndexAtOffset: findIndexAtOffset,
    setVisibleRange,
    setContainerHeight,
  } as const;
}
