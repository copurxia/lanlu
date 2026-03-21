'use client';

import { useCallback, useEffect, useMemo, useState } from 'react';
import type React from 'react';
import type { ArchiveMetadata } from '@/types/archive';
import { ArchiveService } from '@/lib/services/archive-service';
import { FavoriteService } from '@/lib/services/favorite-service';
import { logger } from '@/lib/utils/logger';

export function useReaderArchiveMetadata({
  id,
  language,
}: {
  id: string | null;
  language: string;
}) {
  const [archiveTitle, setArchiveTitle] = useState<string>('');
  const [archiveMetadata, setArchiveMetadata] = useState<ArchiveMetadata | null>(null);
  const [isFavorited, setIsFavorited] = useState(false);

  useEffect(() => {
    if (!id) {
      setArchiveMetadata(null);
      setIsFavorited(false);
      setArchiveTitle('');
      return;
    }

    let cancelled = false;
    setArchiveMetadata(null);

    (async () => {
      try {
        const metadata = await ArchiveService.getMetadata(id, language);
        if (cancelled) return;
        setArchiveMetadata(metadata);
        setIsFavorited(Boolean(metadata.isfavorite));
        if (metadata.title && metadata.title.trim()) {
          setArchiveTitle(metadata.title);
        }
      } catch (metaErr) {
        logger.apiError('fetch archive metadata', metaErr);
        if (cancelled) return;
        setArchiveMetadata(null);
      }
    })();

    return () => {
      cancelled = true;
    };
  }, [id, language]);

  const metadataTags = useMemo(() => {
    return Array.isArray(archiveMetadata?.tags)
      ? archiveMetadata.tags.map((tag) => String(tag || '').trim()).filter(Boolean)
      : [];
  }, [archiveMetadata]);

  const toggleFavorite = useCallback(
    async (e?: React.MouseEvent) => {
      if (!id) return;

      e?.preventDefault();
      e?.stopPropagation();

      try {
        if (isFavorited) {
          await FavoriteService.removeFavorite(id);
          setIsFavorited(false);
        } else {
          await FavoriteService.addFavorite(id);
          setIsFavorited(true);
        }
      } catch (err) {
        logger.operationFailed('toggle favorite', err);
      }
    },
    [id, isFavorited]
  );

  return {
    archiveTitle,
    setArchiveTitle,
    archiveMetadata,
    metadataTags,
    isFavorited,
    toggleFavorite,
  } as const;
}
