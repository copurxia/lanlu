'use client';

import { useCallback, useEffect, useState } from 'react';
import { ArchiveService } from '@/lib/archive-service';
import { logger } from '@/lib/logger';
import type { ArchiveMetadata } from '@/types/archive';

type UseArchiveMetadataParams = {
  id: string | null;
  language: string;
  t: (key: string) => string;
};

export function useArchiveMetadata({ id, language, t }: UseArchiveMetadataParams) {
  const [metadata, setMetadata] = useState<ArchiveMetadata | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [isFavorite, setIsFavorite] = useState(false);

  const fetchMetadata = useCallback(async (): Promise<ArchiveMetadata | null> => {
    if (!id) return null;

    try {
      const data = await ArchiveService.getMetadata(id, language);
      setMetadata(data);
      setIsFavorite(data.isfavorite || false);

      return data;
    } catch (err) {
      logger.apiError('fetch metadata', err);
      return null;
    }
  }, [id, language]);

  useEffect(() => {
    let cancelled = false;

    async function load() {
      if (!id) {
        setError(t('archive.missingId'));
        setLoading(false);
        return;
      }

      setError(null);
      setLoading(true);
      try {
        await fetchMetadata();
      } catch (err) {
        logger.apiError('fetch archive metadata', err);
        if (!cancelled) setError(t('archive.fetchError'));
      } finally {
        if (!cancelled) setLoading(false);
      }
    }

    load();
    return () => {
      cancelled = true;
    };
  }, [id, t, fetchMetadata]);

  return {
    metadata,
    setMetadata,
    loading,
    error,
    isFavorite,
    setIsFavorite,
    refetch: fetchMetadata,
  };
}
