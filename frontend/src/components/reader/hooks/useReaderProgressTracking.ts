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
        updateReadingProgress(currentPage);
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
        updateReadingProgress(currentPageRef.current);
      }
    };
  }, [pagesLength, updateReadingProgress]);
}

