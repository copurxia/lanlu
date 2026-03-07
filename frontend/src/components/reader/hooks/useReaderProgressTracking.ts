'use client';

import { useCallback, useEffect, useRef } from 'react';
import { ArchiveService } from '@/lib/services/archive-service';
import { logger } from '@/lib/utils/logger';
import type { ReaderItemType } from '@/features/reader/domain/models/reader-item';
import { computeProgressPage } from '@/features/reader/application/use-cases/compute-progress-page';

export function useReaderProgressTracking({
  id,
  currentPage,
  pagesLength,
  doublePageMode,
  splitCoverMode,
  currentItemType,
}: {
  id: string | null;
  currentPage: number;
  pagesLength: number;
  doublePageMode: boolean;
  splitCoverMode: boolean;
  currentItemType?: ReaderItemType | null;
}) {
  const imageLoadTimeoutRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const currentPageRef = useRef<number>(0);

  const updateReadingProgress = useCallback(
    async (page: number) => {
      if (!id) return;

      try {
        const actualPage = computeProgressPage({
          currentPage: page,
          pagesLength,
          doublePageMode,
          splitCoverMode,
          currentItemType,
        });

        await ArchiveService.updateProgress(id, actualPage + 1);
      } catch (err) {
        logger.operationFailed('update reading progress', err);
      }
    },
    [id, pagesLength, doublePageMode, splitCoverMode, currentItemType]
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
