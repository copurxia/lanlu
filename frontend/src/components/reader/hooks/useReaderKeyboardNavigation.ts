'use client';

import { useCallback, useEffect } from 'react';
import type { ReadingMode } from '@/hooks/use-reader-settings';

export function useReaderKeyboardNavigation({
  readingMode,
  onPrevPage,
  onNextPage,
}: {
  readingMode: ReadingMode;
  onPrevPage: () => void;
  onNextPage: () => void;
}) {
  const handleKeyDown = useCallback(
    (e: KeyboardEvent) => {
      if (e.target instanceof HTMLInputElement) return;

      switch (e.key) {
        case 'ArrowLeft':
          if (readingMode === 'single-rtl') {
            onNextPage();
          } else if (readingMode !== 'webtoon') {
            onPrevPage();
          }
          break;
        case 'ArrowRight':
          if (readingMode === 'single-rtl') {
            onPrevPage();
          } else if (readingMode !== 'webtoon') {
            onNextPage();
          }
          break;
        case 'ArrowUp':
          if (readingMode === 'single-ttb') {
            onPrevPage();
          }
          break;
        case 'ArrowDown':
          if (readingMode === 'single-ttb') {
            onNextPage();
          }
          break;
      }
    },
    [onNextPage, onPrevPage, readingMode]
  );

  useEffect(() => {
    window.addEventListener('keydown', handleKeyDown);
    return () => {
      window.removeEventListener('keydown', handleKeyDown);
    };
  }, [handleKeyDown]);
}

