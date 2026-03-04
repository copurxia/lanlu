'use client';

import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import type { Tankoubon } from '@/types/tankoubon';
import type { Archive } from '@/types/archive';
import { TankoubonService } from '@/lib/services/tankoubon-service';
import { ArchiveService } from '@/lib/services/archive-service';
import { logger } from '@/lib/utils/logger';
import { useLanguage } from '@/contexts/LanguageContext';

type Params = {
  archiveId: string | null;
  maxPreviewArchivesPerTankoubon?: number;
};

export function useArchiveTankoubons({ archiveId, maxPreviewArchivesPerTankoubon = 6 }: Params) {
  const { language } = useLanguage();
  const [tankoubons, setTankoubons] = useState<Tankoubon[]>([]);
  const [previewArchivesByTankoubonId, setPreviewArchivesByTankoubonId] = useState<Record<string, Archive[]>>({});
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const seqRef = useRef(0);

  const refetch = useCallback(async () => {
    const seq = ++seqRef.current;
    if (!archiveId) {
      setTankoubons([]);
      setPreviewArchivesByTankoubonId({});
      setLoading(false);
      setError(null);
      return;
    }

    setLoading(true);
    setError(null);
    try {
      const tanks = await TankoubonService.getTankoubonsForArchive(archiveId);
      if (seq !== seqRef.current) return;
      setTankoubons(tanks);

      if (tanks.length === 0) {
        setPreviewArchivesByTankoubonId({});
        return;
      }

      const windowSize = Math.max(1, maxPreviewArchivesPerTankoubon);
      const results = await Promise.allSettled(
        tanks.map(async (tank) => {
          const arcids = (tank.archives || []).filter((id) => id);
          const idx = archiveId ? arcids.indexOf(archiveId) : -1;
          const start = idx >= 0 ? Math.max(0, idx - Math.floor(windowSize / 2)) : 0;

          const resp = await ArchiveService.search({
            tankoubon_id: tank.tankoubon_id,
            sortby: 'tank_order',
            order: 'asc',
            page: Math.floor(start / windowSize) + 1,
            pageSize: windowSize,
            groupby_tanks: false,
            lang: language,
          });

          const archives = resp.data.filter((item): item is Archive => Boolean(item) && typeof item === 'object' && 'arcid' in item);
          return { tankoubonId: tank.tankoubon_id, archives };
        })
      );

      if (seq !== seqRef.current) return;
      const preview: Record<string, Archive[]> = {};
      for (const r of results) {
        if (r.status !== 'fulfilled') continue;
        const { tankoubonId, archives } = r.value;
        const idx = archives.findIndex((a) => a.arcid === archiveId);
        const ordered = idx > 0 ? [archives[idx], ...archives.slice(0, idx), ...archives.slice(idx + 1)] : archives;
        preview[tankoubonId] = ordered.slice(0, maxPreviewArchivesPerTankoubon);
      }
      setPreviewArchivesByTankoubonId(preview);
    } catch (e) {
      logger.apiError('fetch archive tankoubons', e);
      if (seq === seqRef.current) setError('failed');
    } finally {
      if (seq === seqRef.current) setLoading(false);
    }
  }, [archiveId, language, maxPreviewArchivesPerTankoubon]);

  useEffect(() => {
    refetch();
  }, [refetch]);

  const tankoubonPreviewArchives = useMemo(() => previewArchivesByTankoubonId, [previewArchivesByTankoubonId]);

  return {
    tankoubons,
    tankoubonPreviewArchives,
    loading,
    error,
    refetch,
  };
}
