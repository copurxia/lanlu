'use client';

import { useCallback, useEffect, useState } from 'react';
import { ArchiveService, type PageInfo } from '@/lib/archive-service';
import { logger } from '@/lib/logger';

type UseArchivePreviewParams = {
  id: string | null;
  showPreview: boolean;
  pageSize: number;
  t: (key: string) => string;
};

export function useArchivePreview({ id, showPreview, pageSize, t }: UseArchivePreviewParams) {
  const [previewLoading, setPreviewLoading] = useState(false);
  const [previewError, setPreviewError] = useState<string | null>(null);
  const [archivePages, setArchivePages] = useState<PageInfo[]>([]);
  const [displayPages, setDisplayPages] = useState<PageInfo[]>([]);
  const [currentPage, setCurrentPage] = useState(0);
  const [loadingImages, setLoadingImages] = useState<Set<number>>(new Set());

  useEffect(() => {
    let cancelled = false;

    async function fetchPages() {
      if (!id || !showPreview) return;

      setPreviewLoading(true);
      setPreviewError(null);

      try {
        const data = await ArchiveService.getFiles(id);
        if (cancelled) return;
        setArchivePages(data.pages);
        setDisplayPages(data.pages.slice(0, pageSize));
        setCurrentPage(0);
      } catch (err) {
        logger.apiError('fetch archive pages', err);
        if (!cancelled) setPreviewError(t('archive.loadPreviewError'));
      } finally {
        if (!cancelled) setPreviewLoading(false);
      }
    }

    fetchPages();
    return () => {
      cancelled = true;
    };
  }, [id, showPreview, t, pageSize]);

  useEffect(() => {
    if (!showPreview) {
      setArchivePages([]);
      setDisplayPages([]);
      setCurrentPage(0);
      setPreviewError(null);
      setLoadingImages(new Set());
    }
  }, [showPreview]);

  const loadMorePages = useCallback(() => {
    const nextPage = currentPage + 1;
    const startIndex = nextPage * pageSize;
    const endIndex = Math.min(startIndex + pageSize, archivePages.length);

    if (startIndex < archivePages.length) {
      const newPages = archivePages.slice(startIndex, endIndex);
      setDisplayPages((prev) => [...prev, ...newPages]);
      setCurrentPage(nextPage);
    }
  }, [currentPage, archivePages, pageSize]);

  const handleImageLoadEnd = useCallback((pageIndex: number) => {
    setLoadingImages((prev) => {
      const next = new Set(prev);
      next.delete(pageIndex);
      return next;
    });
  }, []);

  const handleImageError = useCallback((pageIndex: number) => {
    setLoadingImages((prev) => {
      const next = new Set(prev);
      next.delete(pageIndex);
      return next;
    });
  }, []);

  return {
    previewLoading,
    previewError,
    archivePages,
    displayPages,
    loadingImages,
    loadMorePages,
    handleImageLoadEnd,
    handleImageError,
  };
}

