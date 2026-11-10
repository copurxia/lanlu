'use client';

import { useEffect } from 'react';

export function useReaderAutoPlay({
  autoPlayMode,
  autoPlayInterval,
  readingMode,
  webtoonContainerRef,
  imageHeights,
  currentPage,
  pagesLength,
  doublePageMode,
  splitCoverMode,
  onNextPage,
  setAutoPlayMode,
}: {
  autoPlayMode: boolean;
  autoPlayInterval: number;
  readingMode: 'single-ltr' | 'single-rtl' | 'single-ttb' | 'webtoon';
  webtoonContainerRef: React.RefObject<HTMLDivElement | null>;
  imageHeights: number[];
  currentPage: number;
  pagesLength: number;
  doublePageMode: boolean;
  splitCoverMode: boolean;
  onNextPage: () => void;
  setAutoPlayMode: (value: boolean) => void;
}) {
  useEffect(() => {
    let intervalId: NodeJS.Timeout | null = null;

    if (autoPlayMode && pagesLength > 0) {
      intervalId = setInterval(() => {
        if (readingMode === 'webtoon') {
          const container = webtoonContainerRef.current;
          if (!container) return;

          const currentScrollTop = container.scrollTop;
          const containerHeight = container.clientHeight;
          const scrollHeight = container.scrollHeight;

          if (currentScrollTop + containerHeight >= scrollHeight - 10) {
            setAutoPlayMode(false);
            return;
          }

          let accumulatedHeight = 0;
          let nextImagePosition = 0;

          for (let i = 0; i < imageHeights.length; i++) {
            const imageHeight = imageHeights[i] || containerHeight;
            accumulatedHeight += imageHeight;
            if (accumulatedHeight > currentScrollTop + containerHeight * 0.3) {
              nextImagePosition = accumulatedHeight - imageHeight;
              break;
            }
          }

          container.scrollTo({
            top: nextImagePosition + containerHeight * 0.7,
            behavior: 'smooth',
          });

          return;
        }

        if (doublePageMode) {
          if (currentPage >= pagesLength - (splitCoverMode && currentPage === 0 ? 1 : 2)) {
            setAutoPlayMode(false);
            return;
          }
        } else if (currentPage >= pagesLength - 1) {
          setAutoPlayMode(false);
          return;
        }

        onNextPage();
      }, autoPlayInterval * 1000);
    }

    return () => {
      if (intervalId) clearInterval(intervalId);
    };
  }, [
    autoPlayMode,
    autoPlayInterval,
    currentPage,
    pagesLength,
    doublePageMode,
    splitCoverMode,
    onNextPage,
    readingMode,
    imageHeights,
    setAutoPlayMode,
    webtoonContainerRef,
  ]);
}

