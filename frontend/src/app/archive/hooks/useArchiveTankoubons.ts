'use client';

import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import type { Tankoubon } from '@/types/tankoubon';
import type { Archive } from '@/types/archive';
import { TankoubonService } from '@/lib/tankoubon-service';
import { ArchiveService } from '@/lib/archive-service';
import { logger } from '@/lib/logger';

type Params = {
  archiveId: string | null;
  maxPreviewArchivesPerTankoubon?: number;
};

export function useArchiveTankoubons({ archiveId, maxPreviewArchivesPerTankoubon = 6 }: Params) {
  const [tankoubons, setTankoubons] = useState<Tankoubon[]>([]);
  const [archivesById, setArchivesById] = useState<Record<string, Archive>>({});
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const seqRef = useRef(0);

  const refetch = useCallback(async () => {
    const seq = ++seqRef.current;
    if (!archiveId) {
      setTankoubons([]);
      setArchivesById({});
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

      const idsToFetch = new Set<string>();
      for (const tank of tanks) {
        const rawArcids = (tank.archives || []).filter((id) => id);
        const arcids = (() => {
          if (!archiveId) return rawArcids.slice(0, maxPreviewArchivesPerTankoubon);
          const idx = rawArcids.indexOf(archiveId);
          if (idx < 0) return rawArcids.slice(0, maxPreviewArchivesPerTankoubon);
          const reordered = [archiveId, ...rawArcids.slice(0, idx), ...rawArcids.slice(idx + 1)];
          return reordered.slice(0, maxPreviewArchivesPerTankoubon);
        })();
        for (const id of arcids) idsToFetch.add(id);
      }

      if (idsToFetch.size === 0) {
        setArchivesById({});
        return;
      }

      const results = await Promise.allSettled(
        Array.from(idsToFetch).map(async (id) => {
          const archive = (await ArchiveService.getArchive(id)) as Archive;
          return { id, archive };
        })
      );

      if (seq !== seqRef.current) return;
      const map: Record<string, Archive> = {};
      for (const r of results) {
        if (r.status === 'fulfilled' && r.value?.archive) {
          map[r.value.id] = r.value.archive;
        }
      }
      setArchivesById(map);
    } catch (e) {
      logger.apiError('fetch archive tankoubons', e);
      if (seq === seqRef.current) setError('failed');
    } finally {
      if (seq === seqRef.current) setLoading(false);
    }
  }, [archiveId, maxPreviewArchivesPerTankoubon]);

  useEffect(() => {
    refetch();
  }, [refetch]);

  const tankoubonPreviewArchives = useMemo(() => {
    const byTank: Record<string, Archive[]> = {};
    if (!archiveId) return byTank;

    for (const tank of tankoubons) {
      const rawArcids = (tank.archives || []).filter((id) => id);
      const idx = rawArcids.indexOf(archiveId);
      const arcids =
        idx < 0
          ? rawArcids.slice(0, maxPreviewArchivesPerTankoubon)
          : [archiveId, ...rawArcids.slice(0, idx), ...rawArcids.slice(idx + 1)].slice(0, maxPreviewArchivesPerTankoubon);
      byTank[tank.tankoubon_id] = arcids.map((id) => archivesById[id]).filter(Boolean);
    }
    return byTank;
  }, [archiveId, archivesById, maxPreviewArchivesPerTankoubon, tankoubons]);

  return {
    tankoubons,
    tankoubonPreviewArchives,
    loading,
    error,
    refetch,
  };
}
