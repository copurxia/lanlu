'use client';

import { useEffect, useState } from 'react';
import { ArchiveService, type PageInfo } from '@/lib/services/archive-service';
import { logger } from '@/lib/utils/logger';

type UseArchivePreviewParams = {
  id: string | null;
  showPreview: boolean;
  t: (key: string) => string;
};

export function useArchivePreview({ id, showPreview, t }: UseArchivePreviewParams) {
  const [previewLoading, setPreviewLoading] = useState(false);
  const [previewError, setPreviewError] = useState<string | null>(null);
  const [archivePages, setArchivePages] = useState<PageInfo[]>([]);

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
  }, [id, showPreview, t]);

  useEffect(() => {
    if (!showPreview) {
      setArchivePages([]);
      setPreviewError(null);
    }
  }, [showPreview]);

  return {
    previewLoading,
    previewError,
    archivePages,
    displayPages: archivePages,
  };
}

