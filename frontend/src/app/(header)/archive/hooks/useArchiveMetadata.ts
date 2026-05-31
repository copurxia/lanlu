'use client';

import { useCallback, useEffect, useState } from 'react';
import { ArchiveService } from '@/lib/services/archive-service';
import { SourcePluginService } from '@/lib/services/source-plugin-service';
import { logger } from '@/lib/utils/logger';
import type { ArchiveMetadata } from '@/types/archive';

type UseArchiveMetadataParams = {
  id: string | null;
  sourceNamespace?: string | null;
  remoteId?: string | null;
  language: string;
  t: (key: string) => string;
};

function sourceItemToArchiveMetadata(item: import('@/lib/services/source-plugin-service').SourceItem): ArchiveMetadata {
  return {
    arcid: `source:${item.source_namespace}:${item.remote_id}`,
    title: item.title || '',
    description: item.description || '',
    tags: item.tags || [],
    pagecount: item.page_count || item.reader?.page_count || 0,
    progress: 0,
    isnew: true,
    isfavorite: false,
    archivetype: item.reader?.media_type || 'image',
    lastreadtime: 0,
    size: 0,
    assets: undefined,
    release_at: '',
    updated_at: '',
    created_at: '',
    filename: '',
    relative_path: '',
    thumbnail_hash: '',
  };
}

export function useArchiveMetadata({ id, sourceNamespace, remoteId, language, t }: UseArchiveMetadataParams) {
  const [metadata, setMetadata] = useState<ArchiveMetadata | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [isFavorite, setIsFavorite] = useState(false);

  const fetchMetadata = useCallback(async (): Promise<ArchiveMetadata | null> => {
    if (sourceNamespace && remoteId) {
      try {
        const result = await SourcePluginService.detail(sourceNamespace, remoteId);
        if (result.success && result.data) {
          const adapted = sourceItemToArchiveMetadata(result.data);
          setMetadata(adapted);
          setIsFavorite(false);
          return adapted;
        } else {
          setError(result.error || t('archive.fetchError'));
          return null;
        }
      } catch (err) {
        logger.apiError('fetch source archive metadata', err);
        setError(t('archive.fetchError'));
        return null;
      }
    }

    if (!id) return null;

    try {
      const data = await ArchiveService.getMetadata(id, language);
      setMetadata(data);
      setIsFavorite(Boolean(data.isfavorite));
      return data;
    } catch (err) {
      logger.apiError('fetch metadata', err);
      return null;
    }
  }, [id, sourceNamespace, remoteId, language, t]);

  useEffect(() => {
    let cancelled = false;

    async function load() {
      if (!id && !(sourceNamespace && remoteId)) {
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
  }, [id, sourceNamespace, remoteId, t, fetchMetadata]);

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
