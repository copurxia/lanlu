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
  // readingMode 不参与 fetchPages 依赖（见下），但 fetchPages 内仍需读取最新值，
  // 用 ref 转发避免把 mode 变成重拉触发器。
  const readingModeRef = useRef(readingMode);
  useEffect(() => {
    readingModeRef.current = readingMode;
  }, [readingMode]);

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
        const effectiveArchiveId = sourceArchiveId;

        // Unified path: ArchiveService.getFiles handles both Source and local formats
        const data = await ArchiveService.getFiles(effectiveArchiveId);
        const { mapPageDtosToReaderPageItems } = await import('@/features/reader/domain/mappers/page-dto-mapper');
        const initialPages = mapPageDtosToReaderPageItems(data.pages, effectiveArchiveId);

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
        if (readingModeRef.current === 'webtoon') {
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
  // readingMode 也排除在依赖外：页面列表与阅读方向无关，切模式重拉会导致
  // 整个阅读器 loading=true 全屏黑屏、图片加载状态清零，弱网下还易触发
  // 连点竞态的加载失败（webtoon 的初始滚动设置改由下方独立 effect 处理）。
  }, [
    appliedVirtualFromUrlForIdRef,
    appendedArchiveIdsRef,
    handledUrlPositionRef,
    pendingUrlPageIndexRef,
    pendingUrlPageRawRef,
    pendingWebtoonScrollToEdgeRef,
    pendingWebtoonScrollToIndexRef,
    seamlessAppendInFlightRef,
    seamlessAppendTriggeredRef,
    sourceArchiveId,
    virtualEndEnteredAtRef,
    wasCollectionEndPageRef,
    webtoonVirtualPageSeenRef,
  ]);

  // 首次进入时已在 webtoon 模式：设置初始滚动目标（从 fetchPages 中拆出，
  // 避免 readingMode 变成页面列表重拉的依赖）
  useEffect(() => {
    if (readingMode !== 'webtoon') return;
    if (pages.length === 0) return;
    if (pendingWebtoonScrollToIndexRef.current != null) return;
    if (pendingWebtoonScrollToEdgeRef.current) return;
    // 仅在因切模式进入 webtoon 且无既定滚动目标时兜底到当前页
    pendingWebtoonScrollToIndexRef.current = null;
  }, [readingMode, pages.length]);

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
