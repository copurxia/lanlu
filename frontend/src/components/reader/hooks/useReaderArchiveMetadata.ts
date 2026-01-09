'use client';

import { useCallback, useEffect, useMemo, useState } from 'react';
import type React from 'react';
import type { ArchiveMetadata } from '@/types/archive';
import { ArchiveService } from '@/lib/archive-service';
import { FavoriteService } from '@/lib/favorite-service';
import { logger } from '@/lib/logger';

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
        setIsFavorited(metadata.isfavorite);
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

  const archiveTags = archiveMetadata?.tags ?? '';
  const metadataTags = useMemo(() => {
    if (!archiveTags) return [];
    return archiveTags
      .split(',')
      .map((tag) => tag.trim())
      .filter(Boolean);
  }, [archiveTags]);

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
