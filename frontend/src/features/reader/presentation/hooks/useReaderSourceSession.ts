'use client';

import { useEffect, useRef, useState } from 'react';
import type React from 'react';
import { ArchiveService } from '@/lib/services/archive-service';
import { logger } from '@/lib/utils/logger';
import type { ReaderPageItem, ReaderSegment } from '@/features/reader/domain/models/reader-item';
import { resolveReaderInitialPage } from '@/features/reader/application/use-cases/resolve-reader-initial-page';

type MutableRef<T> = React.MutableRefObject<T>;

export function useReaderSourceSession({
  queryArchiveId,
  seamlessEnabled,
  readingMode,
  pageParam,
  tankoubonParam,
  suppressNextQueryIdSyncRef,
  appliedVirtualFromUrlForIdRef,
  handledUrlPositionRef,
  seamlessAppendTriggeredRef,
  seamlessAppendInFlightRef,
  virtualEndEnteredAtRef,
  wasCollectionEndPageRef,
  webtoonVirtualPageSeenRef,
  pendingUrlPageRawRef,
  pendingUrlPageIndexRef,
  pendingWebtoonScrollToIndexRef,
  pendingWebtoonScrollToEdgeRef,
  appendedArchiveIdsRef,
}: {
  queryArchiveId: string | null;
  seamlessEnabled: boolean;
  readingMode: 'single-ltr' | 'single-rtl' | 'single-ttb' | 'webtoon';
  pageParam: string | null;
  tankoubonParam: string | null;
  suppressNextQueryIdSyncRef: MutableRef<string | null>;
  appliedVirtualFromUrlForIdRef: MutableRef<string | null>;
  handledUrlPositionRef: MutableRef<string | null>;
  seamlessAppendTriggeredRef: MutableRef<boolean>;
  seamlessAppendInFlightRef: MutableRef<boolean>;
  virtualEndEnteredAtRef: MutableRef<number>;
  wasCollectionEndPageRef: MutableRef<boolean>;
  webtoonVirtualPageSeenRef: MutableRef<boolean>;
  pendingUrlPageRawRef: MutableRef<number | null>;
  pendingUrlPageIndexRef: MutableRef<number | null>;
  pendingWebtoonScrollToIndexRef: MutableRef<number | null>;
  pendingWebtoonScrollToEdgeRef: MutableRef<'top' | 'bottom' | null>;
  appendedArchiveIdsRef: MutableRef<Set<string>>;
}) {
  const [sourceArchiveId, setSourceArchiveId] = useState<string | null>(queryArchiveId);
  const [pages, setPages] = useState<ReaderPageItem[]>([]);
  const [segments, setSegments] = useState<ReaderSegment[]>([]);
  const [currentPage, setCurrentPage] = useState(0);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [initialPreloadPage, setInitialPreloadPage] = useState<number | null>(null);
  const latestPageParamRef = useRef<string | null>(pageParam);

  useEffect(() => {
    latestPageParamRef.current = pageParam;
  }, [pageParam]);

  useEffect(() => {
    if (!queryArchiveId) {
      setSourceArchiveId(null);
      return;
    }

    if (suppressNextQueryIdSyncRef.current === queryArchiveId) {
      suppressNextQueryIdSyncRef.current = null;
      return;
    }

    if (seamlessEnabled && sourceArchiveId && queryArchiveId !== sourceArchiveId) {
      const isKnownSegment = segments.some((segment) => segment.archiveId === queryArchiveId);
      if (isKnownSegment) return;
    }

    if (sourceArchiveId === queryArchiveId) return;
    setSourceArchiveId(queryArchiveId);
  }, [queryArchiveId, seamlessEnabled, segments, sourceArchiveId, suppressNextQueryIdSyncRef]);

  useEffect(() => {
    async function fetchPages() {
      if (!sourceArchiveId) {
        setError('Missing archive ID');
        setLoading(false);
        return;
      }

      setLoading(true);
      setError(null);
      appliedVirtualFromUrlForIdRef.current = null;
      handledUrlPositionRef.current = null;
      seamlessAppendTriggeredRef.current = false;
      seamlessAppendInFlightRef.current = false;
      virtualEndEnteredAtRef.current = 0;
      wasCollectionEndPageRef.current = false;
      webtoonVirtualPageSeenRef.current = false;

      try {
        let effectiveArchiveId = sourceArchiveId;

        if (tankoubonParam) {
          try {
            const { TankoubonService } = await import('@/lib/services/tankoubon-service');
            const tankMeta = await TankoubonService.getMetadata(tankoubonParam);
            const childIds = (tankMeta.children || []).map(c => c.entity_id).filter(Boolean) as string[];
            if (childIds.length > 0) {
              const childMetas = await Promise.all(
                childIds.map(id => ArchiveService.getMetadata(id).catch(() => null)),
              );
              let resumeIdx = 0;
              let resumePage = 0;
              for (let i = childMetas.length - 1; i >= 0; i--) {
                const m = childMetas[i];
                if (m && typeof m.progress === 'number' && m.progress > 0) {
                  resumeIdx = i;
                  resumePage = Math.min(m.progress, m.pagecount || m.progress);
                  break;
                }
              }
              effectiveArchiveId = childIds[resumeIdx];
              if (resumePage > 0) {
                latestPageParamRef.current = String(resumePage);
              }
            }
          } catch {
            // fallback to original sourceArchiveId
          }
        }

        // Unified path: ArchiveService.getFiles handles both Source and local formats
        const data = await ArchiveService.getFiles(effectiveArchiveId);
        const { mapPageDtosToReaderPageItems } = await import('@/features/reader/domain/mappers/page-dto-mapper');
        const initialPages = mapPageDtosToReaderPageItems(data.pages, sourceArchiveId);

        appendedArchiveIdsRef.current = new Set([effectiveArchiveId]);
        setSegments([
          {
            archiveId: effectiveArchiveId,
            start: 0,
            count: initialPages.length,
            title: '',
          },
        ]);

        const doublePageModeFromStorage = typeof window !== 'undefined'
          ? localStorage.getItem('doublePageMode') === 'true'
          : false;
        const splitCoverModeFromStorage = typeof window !== 'undefined'
          ? localStorage.getItem('splitCoverMode') === 'true'
          : false;

        const initialPageParam = latestPageParamRef.current;
        const initialPageResolution = resolveReaderInitialPage({
          pageParam: initialPageParam,
          pagesLength: initialPages.length,
          doublePageMode: doublePageModeFromStorage,
          splitCoverMode: splitCoverModeFromStorage,
          initialPageType: initialPages[Math.max(0, Math.min(initialPages.length - 1, 0))]?.type,
        });

        const initialPage = initialPageResolution.initialPage;
        pendingUrlPageRawRef.current = initialPageResolution.pendingUrlPageRaw;
        pendingUrlPageIndexRef.current = initialPageResolution.pendingUrlPageIndex;
        pendingWebtoonScrollToEdgeRef.current = initialPageResolution.pendingWebtoonScrollEdge;

        setPages(initialPages);
        setCurrentPage(initialPage);
        if (readingMode === 'webtoon') {
          pendingWebtoonScrollToIndexRef.current = initialPage;
          if (!pendingWebtoonScrollToEdgeRef.current && initialPage <= 0) {
            pendingWebtoonScrollToEdgeRef.current = 'top';
          }
        }

        if (initialPage > 0 && initialPages[initialPage]?.type !== 'html') {
          setInitialPreloadPage(initialPage);
        } else {
          setInitialPreloadPage(null);
        }
      } catch (err) {
        logger.apiError('fetch reader pages', err);
        setError('Failed to fetch reader pages');
      } finally {
        setLoading(false);
      }
    }

    void fetchPages();
  // pageParam intentionally excluded from deps - it should only affect initial page selection,
  // not trigger re-fetching on every page turn (which causes full page refresh)
  }, [
    appliedVirtualFromUrlForIdRef,
    appendedArchiveIdsRef,
    handledUrlPositionRef,
    pendingUrlPageIndexRef,
    pendingUrlPageRawRef,
    pendingWebtoonScrollToEdgeRef,
    pendingWebtoonScrollToIndexRef,
    readingMode,
    seamlessAppendInFlightRef,
    seamlessAppendTriggeredRef,
    sourceArchiveId,
    virtualEndEnteredAtRef,
    wasCollectionEndPageRef,
    webtoonVirtualPageSeenRef,
  ]);

  return {
    sourceArchiveId,
    setSourceArchiveId,
    pages,
    setPages,
    segments,
    setSegments,
    currentPage,
    setCurrentPage,
    loading,
    setLoading,
    error,
    setError,
    initialPreloadPage,
  } as const;
}
