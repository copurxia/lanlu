'use client';

import { useCallback, useEffect, useRef } from 'react';
import { ArchiveService } from '@/lib/services/archive-service';
import { logger } from '@/lib/utils/logger';

export function useReaderProgressTracking({
  id,
  currentPage,
  pagesLength,
  doublePageMode,
  splitCoverMode,
}: {
  id: string | null;
  currentPage: number;
  pagesLength: number;
  doublePageMode: boolean;
  splitCoverMode: boolean;
}) {
  const imageLoadTimeoutRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const currentPageRef = useRef<number>(0);

  const updateReadingProgress = useCallback(
    async (page: number) => {
      if (!id) return;

      try {
        let actualPage = page;
        if (doublePageMode && splitCoverMode) {
          if (page === 0) {
            actualPage = 0;
          } else if (page === 1) {
            actualPage = 2;
          } else {
            actualPage = page + 1;
          }
        }

        await ArchiveService.updateProgress(id, actualPage + 1);
      } catch (err) {
        logger.operationFailed('update reading progress', err);
      }
    },
    [id, doublePageMode, splitCoverMode]
  );

  useEffect(() => {
    currentPageRef.current = currentPage;
  }, [currentPage]);

  useEffect(() => {
    if (pagesLength > 0 && currentPage >= 0) {
      if (imageLoadTimeoutRef.current) {
        clearTimeout(imageLoadTimeoutRef.current);
      }

      imageLoadTimeoutRef.current = setTimeout(() => {
        // `currentPage` may temporarily point to a synthetic page (e.g. collection "end" page).
        // Clamp to a valid page index so we never send an out-of-range progress to the API.
        const clampedPage = Math.max(0, Math.min(currentPage, pagesLength - 1));
        updateReadingProgress(clampedPage);
      }, 500);

      return () => {
        if (imageLoadTimeoutRef.current) {
          clearTimeout(imageLoadTimeoutRef.current);
        }
      };
    }
  }, [currentPage, pagesLength, updateReadingProgress]);

  useEffect(() => {
    return () => {
      if (pagesLength > 0 && currentPageRef.current >= 0) {
        const clampedPage = Math.max(0, Math.min(currentPageRef.current, pagesLength - 1));
        updateReadingProgress(clampedPage);
      }
    };
  }, [pagesLength, updateReadingProgress]);
}
