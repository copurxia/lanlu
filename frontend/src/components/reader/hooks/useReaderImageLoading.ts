'use client';

import { useCallback, useEffect, useRef, useState } from 'react';
import type React from 'react';
import type { PageInfo } from '@/lib/services/archive-service';
import type { ReadingMode } from '@/hooks/use-reader-settings';

type VisibleRange = { start: number; end: number };

const MAX_RETRIES = 5;
const BASE_RETRY_DELAY_MS = 500;
const MAX_RETRY_DELAY_MS = 15000;

function getRetryDelayMs(attempt: number) {
  const exp = Math.min(attempt - 1, 10);
  const base = Math.min(MAX_RETRY_DELAY_MS, BASE_RETRY_DELAY_MS * Math.pow(2, exp));
  const jitter = Math.random() * 0.2 + 0.9; // 0.9x ~ 1.1x
  return Math.round(base * jitter);
}

export function useReaderImageLoading({
  pages,
  readingMode,
  currentPage,
  priorityIndices,
  visibleRange,
  imageRefs,
}: {
  pages: PageInfo[];
  readingMode: ReadingMode;
  currentPage: number;
  priorityIndices?: number[];
  visibleRange: VisibleRange;
  imageRefs: React.MutableRefObject<(HTMLImageElement | null)[]>;
}) {
  const [cachedPages, setCachedPages] = useState<string[]>([]);
  const [imagesLoading, setImagesLoading] = useState<Set<number>>(new Set());
  const [loadedImages, setLoadedImages] = useState<Set<number>>(new Set());

  const observerRef = useRef<IntersectionObserver | null>(null);
  const pagesRef = useRef<PageInfo[]>(pages);
  const loadedImagesRef = useRef<Set<number>>(loadedImages);
  const imagesLoadingRef = useRef<Set<number>>(imagesLoading);
  const retryStateRef = useRef<Map<number, { attempts: number; nextRetryAt: number }>>(new Map());
  const retryTimersRef = useRef<Map<number, ReturnType<typeof setTimeout>>>(new Map());
  const mountedRef = useRef(true);
  const currentPageRef = useRef(currentPage);
  const visibleRangeRef = useRef(visibleRange);
  const readingModeRef = useRef(readingMode);
  const pagesLengthRef = useRef(pages.length);

  useEffect(() => {
    pagesRef.current = pages;
  }, [pages]);

  useEffect(() => {
    loadedImagesRef.current = loadedImages;
  }, [loadedImages]);

  useEffect(() => {
    imagesLoadingRef.current = imagesLoading;
  }, [imagesLoading]);

  useEffect(() => {
    mountedRef.current = true;
    const retryTimers = retryTimersRef.current;
    return () => {
      mountedRef.current = false;
      retryTimers.forEach((timerId) => clearTimeout(timerId));
      retryTimers.clear();
    };
  }, []);

  useEffect(() => {
    currentPageRef.current = currentPage;
  }, [currentPage]);

  useEffect(() => {
    visibleRangeRef.current = visibleRange;
  }, [visibleRange]);

  useEffect(() => {
    readingModeRef.current = readingMode;
  }, [readingMode]);

  useEffect(() => {
    pagesLengthRef.current = pages.length;
  }, [pages.length]);

  useEffect(() => {
    if (pages.length === 0) {
      retryStateRef.current.clear();
      retryTimersRef.current.forEach((timerId) => clearTimeout(timerId));
      retryTimersRef.current.clear();
      return;
    }

    // Prune retry state/timers for indexes that no longer exist.
    retryStateRef.current.forEach((_, index) => {
      if (index >= pages.length) retryStateRef.current.delete(index);
    });
    retryTimersRef.current.forEach((timerId, index) => {
      if (index >= pages.length) {
        clearTimeout(timerId);
        retryTimersRef.current.delete(index);
      }
    });
  }, [pages.length]);

  const shouldLoadIndexNow = useCallback((pageIndex: number) => {
    const now = Date.now();
    const state = retryStateRef.current.get(pageIndex);
    if (!state) return true;
    if (state.attempts >= MAX_RETRIES) return false;
    return now >= state.nextRetryAt;
  }, []);

  const isIndexDesiredNow = useCallback((pageIndex: number) => {
    const length = pagesLengthRef.current;
    if (pageIndex < 0 || pageIndex >= length) return false;
    if (loadedImagesRef.current.has(pageIndex)) return false;

    const page = pagesRef.current[pageIndex];
    // HTML pages are loaded by useReaderHtmlPages (fetch + parse); keep them out of image/video preloading.
    if (page?.type === 'html') return false;

    const mode = readingModeRef.current;
    const cp = currentPageRef.current;
    const vr = visibleRangeRef.current;

    if (mode === 'webtoon') {
      const preloadRange = 2;
      const withinCurrent = pageIndex >= Math.max(0, cp - preloadRange) && pageIndex <= Math.min(length - 1, cp + preloadRange);
      const withinVisible = pageIndex >= vr.start && pageIndex <= vr.end;
      return withinCurrent || withinVisible;
    }

    const preloadBefore = 1;
    const preloadAfter = 5;
    return pageIndex >= Math.max(0, cp - preloadBefore) && pageIndex <= Math.min(length - 1, cp + preloadAfter);
  }, []);

  const handleImageError = useCallback((pageIndex: number) => {
    setImagesLoading((prev) => {
      const newSet = new Set(prev);
      newSet.delete(pageIndex);
      return newSet;
    });

    if (loadedImagesRef.current.has(pageIndex)) return;

    const prevState = retryStateRef.current.get(pageIndex);
    const attempts = (prevState?.attempts ?? 0) + 1;
    if (attempts >= MAX_RETRIES) {
      retryStateRef.current.set(pageIndex, { attempts, nextRetryAt: Number.POSITIVE_INFINITY });
      const existingTimerId = retryTimersRef.current.get(pageIndex);
      if (existingTimerId) {
        clearTimeout(existingTimerId);
        retryTimersRef.current.delete(pageIndex);
      }
      return;
    }

    const delayMs = getRetryDelayMs(attempts);
    const nextRetryAt = Date.now() + delayMs;
    retryStateRef.current.set(pageIndex, { attempts, nextRetryAt });

    const existingTimerId = retryTimersRef.current.get(pageIndex);
    if (existingTimerId) clearTimeout(existingTimerId);
    const timerId = setTimeout(() => {
      retryTimersRef.current.delete(pageIndex);
      if (!mountedRef.current) return;
      if (!isIndexDesiredNow(pageIndex)) return;
      if (!shouldLoadIndexNow(pageIndex)) return;
      if (imagesLoadingRef.current.has(pageIndex)) return;
      setImagesLoading((prev) => {
        if (prev.has(pageIndex)) return prev;
        const updated = new Set(prev);
        updated.add(pageIndex);
        return updated;
      });
    }, delayMs);
    retryTimersRef.current.set(pageIndex, timerId);
  }, [isIndexDesiredNow, shouldLoadIndexNow]);

  const cacheImage = useCallback(async (url: string, index: number) => {
    setCachedPages((prev) => {
      const newCachedPages = [...prev];
      newCachedPages[index] = url;
      return newCachedPages;
    });
  }, []);

  const handleImageLoad = useCallback((pageIndex: number) => {
    setImagesLoading((prev) => {
      const newSet = new Set(prev);
      newSet.delete(pageIndex);
      return newSet;
    });
    setLoadedImages((prev) => {
      const newSet = new Set(prev);
      newSet.add(pageIndex);
      return newSet;
    });

    retryStateRef.current.delete(pageIndex);
    const existingTimerId = retryTimersRef.current.get(pageIndex);
    if (existingTimerId) {
      clearTimeout(existingTimerId);
      retryTimersRef.current.delete(pageIndex);
    }

    if (readingMode === 'webtoon') {
      const preloadAdjacent = (index: number) => {
        [index - 1, index + 1].forEach((adjacentIndex) => {
          if (adjacentIndex < 0 || adjacentIndex >= pages.length) return;
          if (loadedImagesRef.current.has(adjacentIndex)) return;
          if (imagesLoadingRef.current.has(adjacentIndex)) return;
          if (!shouldLoadIndexNow(adjacentIndex)) return;
          setImagesLoading((prev) => {
            const updated = new Set(prev);
            updated.add(adjacentIndex);
            return updated;
          });
        });
      };

      setTimeout(() => preloadAdjacent(pageIndex), 100);
    }
  }, [pages.length, readingMode, shouldLoadIndexNow]);

  useEffect(() => {
    if (pages.length === 0) return;

    const prioritySet = new Set(priorityIndices ?? [currentPage]);
    const isPriorityReady = () => {
      for (const idx of prioritySet) {
        if (idx < 0 || idx >= pages.length) continue;
        const page = pages[idx];
        // HTML pages are handled by useReaderHtmlPages; don't block image/video preloading on them.
        if (page?.type === 'html') continue;
        if (!loadedImages.has(idx)) return false;
      }
      return true;
    };

    if (readingMode === 'webtoon') {
      const preloadRange = 2;
      setImagesLoading((prev) => {
        const updated = new Set(prev);
        const priorityReady = isPriorityReady();

        for (let i = Math.max(0, currentPage - preloadRange); i <= Math.min(pages.length - 1, currentPage + preloadRange); i++) {
          if (!loadedImages.has(i)) {
            if (!shouldLoadIndexNow(i)) continue;
            if (pages[i]?.type !== 'html' && (priorityReady || prioritySet.has(i))) updated.add(i);
          }
        }

        for (let i = visibleRange.start; i <= visibleRange.end; i++) {
          if (i >= 0 && i < pages.length && !loadedImages.has(i)) {
            if (!shouldLoadIndexNow(i)) continue;
            if (pages[i]?.type !== 'html' && (priorityReady || prioritySet.has(i))) updated.add(i);
          }
        }

        // Prevent unbounded growth when rapidly scrolling/jumping.
        for (const idx of Array.from(updated)) {
          if (!isIndexDesiredNow(idx)) updated.delete(idx);
        }

        if (!priorityReady) {
          for (const idx of Array.from(updated)) {
            if (!prioritySet.has(idx)) updated.delete(idx);
          }
        }

        return updated;
      });
    } else {
      setImagesLoading((prev) => {
        const updated = new Set(prev);
        const preloadBefore = 1;
        const preloadAfter = 5;
        const priorityReady = isPriorityReady();

        for (
          let i = Math.max(0, currentPage - preloadBefore);
          i <= Math.min(pages.length - 1, currentPage + preloadAfter);
          i++
        ) {
          if (!loadedImages.has(i)) {
            if (!shouldLoadIndexNow(i)) continue;
            if (pages[i]?.type !== 'html' && (priorityReady || prioritySet.has(i))) updated.add(i);
          }
        }

        for (const idx of Array.from(updated)) {
          if (!isIndexDesiredNow(idx)) updated.delete(idx);
        }

        if (!priorityReady) {
          for (const idx of Array.from(updated)) {
            if (!prioritySet.has(idx)) updated.delete(idx);
          }
        }

        return updated;
      });
    }
  }, [
    currentPage,
    priorityIndices,
    readingMode,
    pages,
    loadedImages,
    visibleRange.start,
    visibleRange.end,
    shouldLoadIndexNow,
    isIndexDesiredNow,
  ]);

  useEffect(() => {
    if (readingMode !== 'webtoon') return;

    observerRef.current = new IntersectionObserver(
      (entries) => {
        entries.forEach((entry) => {
          if (!entry.isIntersecting) return;
          const imgElement = entry.target as HTMLImageElement;
          const index = parseInt(imgElement.dataset.index || '0', 10);

          if (!loadedImagesRef.current.has(index) && !imagesLoadingRef.current.has(index)) {
            if (!shouldLoadIndexNow(index)) return;
            setImagesLoading((prev) => {
              const updated = new Set(prev);
              updated.add(index);
              return updated;
            });

            [index - 1, index + 1].forEach((adjacentIndex) => {
              if (adjacentIndex < 0 || adjacentIndex >= pages.length) return;
              if (loadedImagesRef.current.has(adjacentIndex)) return;
              if (imagesLoadingRef.current.has(adjacentIndex)) return;
              if (!shouldLoadIndexNow(adjacentIndex)) return;
              setImagesLoading((prev) => {
                const updated = new Set(prev);
                updated.add(adjacentIndex);
                return updated;
              });
            });
          }

          observerRef.current?.unobserve(imgElement);
        });
      },
      { rootMargin: '2000px 0px 2000px 0px' }
    );

    imageRefs.current.forEach((img, index) => {
      if (!img) return;
      if (index < visibleRange.start || index > visibleRange.end) return;
      img.dataset.index = index.toString();
      observerRef.current?.observe(img);
    });

    return () => {
      observerRef.current?.disconnect();
    };
  }, [readingMode, pages.length, visibleRange.end, visibleRange.start, imageRefs, shouldLoadIndexNow]);

  return {
    cachedPages,
    setCachedPages,
    imagesLoading,
    setImagesLoading,
    loadedImages,
    setLoadedImages,
    handleImageLoad,
    handleImageError,
    cacheImage,
  } as const;
}
