'use client';

import { useSearchParams, useRouter } from 'next/navigation';
import { useState, useEffect, useCallback, useMemo, Suspense, useRef } from 'react';
import type React from 'react';
import { ArchiveService } from '@/lib/services/archive-service';
import type { Archive } from '@/types/archive';
import { Button } from '@/components/ui/button';
import { Spinner } from '@/components/ui/spinner';
import { useLanguage } from '@/contexts/LanguageContext';
import { MediaInfoOverlay } from '@/components/reader/components/MediaInfoOverlay';
import { ReaderFloatingControls } from '@/components/reader/components/ReaderFloatingControls';
import { ReaderCollectionEndPage } from '@/components/reader/components/ReaderCollectionEndPage';
import { ReaderPreloadArea } from '@/components/reader/components/ReaderPreloadArea';
import { ReaderSidebar } from '@/components/reader/components/ReaderSidebar';
import { ReaderSingleModeView } from '@/components/reader/components/ReaderSingleModeView';
import { ReaderTopBar } from '@/components/reader/components/ReaderTopBar';
import { ReaderWebtoonModeView } from '@/components/reader/components/ReaderWebtoonModeView';
import { useReaderArchiveMetadata } from '@/components/reader/hooks/useReaderArchiveMetadata';
import { useReaderHtmlPages } from '@/components/reader/hooks/useReaderHtmlPages';
import { useReaderKeyboardNavigation } from '@/components/reader/hooks/useReaderKeyboardNavigation';
import { useMediaInfoOverlayLines } from '@/components/reader/hooks/useMediaInfoOverlayLines';
import { useReaderProgressTracking } from '@/components/reader/hooks/useReaderProgressTracking';
import { getTapTurnAction, useReaderInteractionHandlers } from '@/components/reader/hooks/useReaderInteractionHandlers';
import { useReaderAutoPlay } from '@/components/reader/hooks/useReaderAutoPlay';
import { useReaderImageLoading } from '@/components/reader/hooks/useReaderImageLoading';
import { useReaderSidebar } from '@/components/reader/hooks/useReaderSidebar';
import { useReaderToolbarAutoHide } from '@/components/reader/hooks/useReaderToolbarAutoHide';
import { useReaderWebtoonVirtualization } from '@/components/reader/hooks/useReaderWebtoonVirtualization';
import { useReaderWheelNavigation } from '@/components/reader/hooks/useReaderWheelNavigation';
import { stepHtmlSpread } from '@/components/reader/utils/html-spread';
import { logger } from '@/lib/utils/logger';
import {
  useReadingMode,
  useDoublePageMode,
  useAutoPlayMode,
  useAutoPlayInterval,
  useSplitCoverMode,
  useFullscreenMode,
  useDoubleTapZoom,
  useAutoHideEnabled,
  useTapTurnPageEnabled,
  useMediaInfoEnabled,
  useLongPageEnabled,
  useSeamlessNextEnabled,
  } from '@/hooks/use-reader-settings';
import {
  ArrowLeft,
  Book,
  ArrowRight,
  ArrowDown,
  Layout,
  Play,
  Scissors,
  Maximize,
  Minimize,
  ZoomIn,
  ScrollText,
  Eye,
  Info,
  MousePointerClick,
  Link2,
} from 'lucide-react';
import Link from 'next/link';
import { TankoubonService } from '@/lib/services/tankoubon-service';
import type { Tankoubon } from '@/types/tankoubon';
import { toast } from 'sonner';
import { getStoredPath } from '@/lib/utils/navigation';
import { getArchiveAssetId } from '@/lib/utils/archive-assets';
import type { ReaderPageItem, ReaderSegment } from '@/features/reader/domain/models/reader-item';
import { isHtmlReaderItem, isVirtualEndReaderItem } from '@/features/reader/domain/rules/reader-item-capabilities';
import { mapPageDtosToReaderPageItems } from '@/features/reader/domain/mappers/page-dto-mapper';
import { buildReaderStream } from '@/features/reader/application/use-cases/build-reader-stream';

function ReaderContent() {
  type EndPageNextArchive = {
    id: string;
    title: string;
    coverAssetId?: number;
    source: 'tankoubon' | 'random';
  };

  const router = useRouter();
  const searchParams = useSearchParams();
  const queryArchiveId = searchParams?.get('id') ?? null;
  const pageParam = searchParams?.get('page');
  const { t, language } = useLanguage();
  
  const [sourceArchiveId, setSourceArchiveId] = useState<string | null>(queryArchiveId);
  const [pages, setPages] = useState<ReaderPageItem[]>([]);
  const [segments, setSegments] = useState<ReaderSegment[]>([]);
  const [currentPage, setCurrentPage] = useState(0);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [scale, setScale] = useState(1);
  const [translateX, setTranslateX] = useState(0);
  const [translateY, setTranslateY] = useState(0);
  const readerAreaRef = useRef<HTMLDivElement | null>(null);
  const webtoonContainerRef = useRef<HTMLDivElement>(null);
  const webtoonPageElementRefs = useRef<(HTMLDivElement | null)[]>([]);
  const imageRefs = useRef<(HTMLImageElement | null)[]>([]);
  const currentPageRef = useRef(0);
  const pendingUrlPageIndexRef = useRef<number | null>(null);
  const pendingUrlPageRawRef = useRef<number | null>(null);
  const appliedVirtualFromUrlForIdRef = useRef<string | null>(null);
  const handledUrlPositionRef = useRef<string | null>(null);
  const urlSyncTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const queryIdSuppressTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const pendingWebtoonScrollToIndexRef = useRef<number | null>(null);
  const pendingWebtoonScrollToEdgeRef = useRef<'top' | 'bottom' | null>(null);
  const suppressNextQueryIdSyncRef = useRef<string | null>(null);
  const pagesLengthRef = useRef(0);
  const seamlessAppendInFlightRef = useRef(false);
  const seamlessAppendTriggeredRef = useRef(false);
  const virtualEndEnteredAtRef = useRef(0);
  const wasCollectionEndPageRef = useRef(false);
  const webtoonVirtualPageSeenRef = useRef(false);
  const appendedArchiveIdsRef = useRef<Set<string>>(new Set());
  const currentArchiveIdRef = useRef<string | null>(queryArchiveId);
  const nextArchiveCandidateCacheRef = useRef<Map<string, EndPageNextArchive>>(new Map());
  const nextArchiveCandidateRequestRef = useRef<Map<string, Promise<EndPageNextArchive | null>>>(new Map());

  const [settingsOpen, setSettingsOpen] = useState(false);
  const [tankoubonContext, setTankoubonContext] = useState<Tankoubon | null>(null);
  const [prevArchiveId, setPrevArchiveId] = useState<string | null>(null);
  const [nextArchiveByArchiveId, setNextArchiveByArchiveId] = useState<Record<string, EndPageNextArchive | null>>({});
  const archiveNavLockRef = useRef(0);
  const chapterJumpCountdownRef = useRef<{
    seconds: number;
    timerId: ReturnType<typeof setInterval> | null;
    toastId: string | number | null;
  }>({ seconds: 0, timerId: null, toastId: null });

  // 提取设备检测和宽度计算的通用函数
  const getDeviceInfo = useCallback(() => {
    const containerWidth = window.innerWidth >= 1024
      ? Math.min(800, window.innerWidth * 0.8)
      : Math.min(window.innerWidth * 0.95, window.innerWidth);
    return { containerWidth };
  }, []);

  const getImageHeight = useCallback((naturalWidth: number, naturalHeight: number) => {
    const { containerWidth } = getDeviceInfo();
    const aspectRatio = naturalHeight / naturalWidth;
    return containerWidth * aspectRatio;
  }, [getDeviceInfo]);

  const handleBack = useCallback(() => {
    const lastPath = getStoredPath('last');
    if (lastPath && !lastPath.startsWith('/reader')) {
      router.push(lastPath);
      return;
    }

    const currentPath = getStoredPath('current');
    if (currentPath && !currentPath.startsWith('/reader')) {
      router.push(currentPath);
      return;
    }

    const targetArchiveId = currentArchiveIdRef.current;
    if (targetArchiveId) {
      router.push(`/archive?id=${targetArchiveId}`);
      return;
    }

    router.push('/');
  }, [router]);

  const handleNavigateToArchiveFromSettings = useCallback(() => {
    const targetArchiveId = currentArchiveIdRef.current;
    if (!targetArchiveId) return;
    setSettingsOpen(false);
    router.push(`/archive?id=${targetArchiveId}`);
  }, [router]);

  const pushReader = useCallback(
    (targetId: string, page: number) => {
      const now = Date.now();
      // Prevent rapid repeat triggers (wheel/tap/keyboard) from causing push loops/flicker.
      if (now - archiveNavLockRef.current < 250) return;
      archiveNavLockRef.current = now;
      router.push(`/reader?id=${targetId}&page=${page}`);
    },
    [router]
  );

  const clearChapterJumpCountdown = useCallback(() => {
    const state = chapterJumpCountdownRef.current;
    if (state.timerId) {
      clearInterval(state.timerId);
      state.timerId = null;
    }
    if (state.toastId != null) {
      toast.dismiss(state.toastId);
      state.toastId = null;
    }
    state.seconds = 0;
  }, []);

  useEffect(() => {
    return () => {
      clearChapterJumpCountdown();
      if (urlSyncTimerRef.current) clearTimeout(urlSyncTimerRef.current);
      if (queryIdSuppressTimerRef.current) clearTimeout(queryIdSuppressTimerRef.current);
    };
  }, [clearChapterJumpCountdown]);

  const requestChapterJump = useCallback(
    (direction: 'prev' | 'next', jump: () => void) => {
      const state = chapterJumpCountdownRef.current;
      if (state.timerId) return; // already counting down

      const COUNTDOWN_SECONDS = 3;
      state.seconds = COUNTDOWN_SECONDS;

      const label = direction === 'next' ? '下一话' : '上一话';
      const renderText = (s: number) => `即将跳转到${label}（${s}秒后）`;

      state.toastId = toast.loading(renderText(COUNTDOWN_SECONDS), {
        duration: COUNTDOWN_SECONDS * 1000,
        action: { label: '取消', onClick: () => clearChapterJumpCountdown() },
      });

      state.timerId = setInterval(() => {
        state.seconds -= 1;
        if (state.seconds <= 0) {
          clearChapterJumpCountdown();
          jump();
          return;
        }
        if (state.toastId != null) {
          toast.loading(renderText(state.seconds), {
            id: state.toastId,
            duration: state.seconds * 1000,
            action: { label: '取消', onClick: () => clearChapterJumpCountdown() },
          });
        }
      }, 1000);
    },
    [clearChapterJumpCountdown]
  );

  const navigateToNextArchiveStart = useCallback(() => {
    const activeId = currentArchiveIdRef.current;
    if (!activeId) return;
    const target = nextArchiveByArchiveId[activeId];
    if (!target?.id) return;
    pushReader(target.id, 1);
  }, [nextArchiveByArchiveId, pushReader]);

  const navigateToPrevArchiveEnd = useCallback(() => {
    if (!prevArchiveId) return;
    // Use a huge page index; reader will clamp to the last real page and then sync URL to the clamped page.
    pushReader(prevArchiveId, 999999);
  }, [prevArchiveId, pushReader]);

  // 使用新的阅读设置hooks，统一管理所有localStorage逻辑
  const [readingMode, toggleReadingMode] = useReadingMode();
  const [doublePageMode, setDoublePageMode] = useDoublePageMode();
  const [autoPlayMode, setAutoPlayMode] = useAutoPlayMode();
  const [autoPlayInterval, setAutoPlayInterval] = useAutoPlayInterval();
  const [splitCoverMode, setSplitCoverMode] = useSplitCoverMode();
  const [isFullscreen, setIsFullscreen] = useFullscreenMode();
  const [doubleTapZoom, setDoubleTapZoom] = useDoubleTapZoom();
  const [autoHideEnabled, setAutoHideEnabled] = useAutoHideEnabled();
  const [tapTurnPageEnabled, setTapTurnPageEnabled] = useTapTurnPageEnabled();
  const [mediaInfoEnabled, setMediaInfoEnabled] = useMediaInfoEnabled();
  const [longPageEnabled, setLongPageEnabled] = useLongPageEnabled();
  const [seamlessNextEnabled, setSeamlessNextEnabled] = useSeamlessNextEnabled();
  const videoRefs = useRef<(HTMLVideoElement | null)[]>([]);
  const htmlContainerRefs = useRef<(HTMLDivElement | null)[]>([]);
  const imageRequestUrls = useRef<(string | null)[]>([]);
  const [mediaInfoTick, setMediaInfoTick] = useState(0);
  const seamlessEnabled = seamlessNextEnabled;
  const seamlessWebtoonEnabled = readingMode === 'webtoon' && seamlessEnabled;

  useEffect(() => {
    if (!queryArchiveId) {
      setSourceArchiveId(null);
      return;
    }

    if (suppressNextQueryIdSyncRef.current === queryArchiveId) {
      suppressNextQueryIdSyncRef.current = null;
      return;
    }

    // In seamless mode, URL id is updated while reading through appended segments.
    // Keep the original source id stable unless user navigates to an unrelated archive id.
    if (seamlessEnabled && sourceArchiveId && queryArchiveId !== sourceArchiveId) {
      const isKnownSegment = segments.some((segment) => segment.archiveId === queryArchiveId);
      if (isKnownSegment) return;
    }

    if (sourceArchiveId === queryArchiveId) return;
    setSourceArchiveId(queryArchiveId);
  }, [queryArchiveId, seamlessEnabled, segments, sourceArchiveId]);

  useEffect(() => {
    nextArchiveCandidateCacheRef.current.clear();
    nextArchiveCandidateRequestRef.current.clear();
    setNextArchiveByArchiveId({});
  }, [language, sourceArchiveId]);

  const hasInterChapterVirtualPages = seamlessWebtoonEnabled;
  const readerStream = useMemo(
    () =>
      buildReaderStream({
        sourceArchiveId,
        pages,
        segments,
        includeInterChapterVirtualPages: hasInterChapterVirtualPages,
      }),
    [hasInterChapterVirtualPages, pages, segments, sourceArchiveId]
  );
  const effectiveSegments = readerStream.effectiveSegments;
  const streamPages = readerStream.items;
  const streamIndexByRealPage = readerStream.streamIndexByRealPage;
  const streamVirtualIndexBySegment = readerStream.streamVirtualIndexBySegment;
  const virtualPageIndex = readerStream.virtualPageIndex;

  const currentStreamItem = streamPages[currentPage] ?? null;
  const activeSegment = useMemo(() => {
    if (effectiveSegments.length <= 0) return null;
    const segmentIndex = currentStreamItem?.streamSegmentIndex;
    if (
      typeof segmentIndex === 'number' &&
      segmentIndex >= 0 &&
      segmentIndex < effectiveSegments.length
    ) {
      return effectiveSegments[segmentIndex];
    }
    return effectiveSegments[effectiveSegments.length - 1] ?? null;
  }, [currentStreamItem, effectiveSegments]);

  const activeArchiveId = currentStreamItem?.archiveId ?? activeSegment?.archiveId ?? sourceArchiveId;
  useEffect(() => {
    currentArchiveIdRef.current = activeArchiveId ?? sourceArchiveId;
  }, [activeArchiveId, sourceArchiveId]);

  const setResolvedNextArchive = useCallback((archiveId: string, next: EndPageNextArchive | null) => {
    setNextArchiveByArchiveId((prev) => {
      const existing = prev[archiveId];
      if (
        existing?.id === next?.id &&
        existing?.title === next?.title &&
        existing?.coverAssetId === next?.coverAssetId &&
        existing?.source === next?.source
      ) {
        return prev;
      }
      if (existing == null && next == null && !Object.prototype.hasOwnProperty.call(prev, archiveId)) {
        return prev;
      }
      return { ...prev, [archiveId]: next };
    });
  }, []);

  const activeLocalPage = useMemo(() => {
    if (!activeSegment) return Math.max(0, currentPage);
    if (currentStreamItem && currentStreamItem.type !== 'virtual-end') {
      return currentStreamItem.streamLocalPage;
    }
    return Math.max(0, activeSegment.count - 1);
  }, [activeSegment, currentPage, currentStreamItem]);

  const currentRealPage = useMemo(() => {
    if (currentStreamItem && currentStreamItem.type !== 'virtual-end') {
      return currentStreamItem.streamRealPage;
    }
    if (activeSegment) {
      return Math.max(0, activeSegment.start + activeSegment.count - 1);
    }
    return Math.max(0, Math.min(currentPage, Math.max(0, pages.length - 1)));
  }, [activeSegment, currentPage, currentStreamItem, pages.length]);

  const archive = useReaderArchiveMetadata({ id: activeArchiveId, language });
  const { htmlContents, loadHtmlPage } = useReaderHtmlPages({ id: sourceArchiveId, pages, onError: setError });

  // 用于跟踪拆分封面模式的变化，避免无限循环
  const splitCoverModeRef = useRef(splitCoverMode);

  const toolbar = useReaderToolbarAutoHide({ autoHideEnabled, delayMs: 3000 });

  const hasTankoubonContext = Boolean(tankoubonContext);
  const nextArchiveLookupId = activeSegment?.archiveId ?? activeArchiveId ?? sourceArchiveId;
  const nextArchive = nextArchiveLookupId ? (nextArchiveByArchiveId[nextArchiveLookupId] ?? null) : null;
  const endPageIsRandomNext = nextArchive?.source === 'random';

  const currentPageType = currentStreamItem?.type ?? null;
  const isCurrentHtmlPage = isHtmlReaderItem(currentStreamItem);
  const isCollectionEndPage = isVirtualEndReaderItem(currentStreamItem);
  const isTailCollectionEndPage = isCollectionEndPage && currentPage === virtualPageIndex;
  const activeSegmentLastRealPage =
    activeSegment && activeSegment.count > 0 ? activeSegment.start + activeSegment.count - 1 : -1;
  const isCurrentOrTailHtmlPage =
    isCurrentHtmlPage ||
    (isCollectionEndPage && activeSegmentLastRealPage >= 0 && pages[activeSegmentLastRealPage]?.type === 'html');
  const isHtmlSpreadView = readingMode !== 'webtoon' && doublePageMode && isCurrentHtmlPage;

  const totalPages = streamPages.length;

  const sliderCurrentPage = seamlessEnabled ? activeLocalPage : currentPage;
  const sliderTotalPages =
    seamlessEnabled && activeSegment ? activeSegment.count : totalPages;

  useEffect(() => {
    if (isCollectionEndPage && !wasCollectionEndPageRef.current) {
      virtualEndEnteredAtRef.current = Date.now();
    }
    wasCollectionEndPageRef.current = isCollectionEndPage;
  }, [isCollectionEndPage]);

  const webtoonVirtualization = useReaderWebtoonVirtualization({
    readingMode,
    pages: streamPages,
    currentPage,
    setCurrentPage,
    resetKey: sourceArchiveId,
    getDeviceInfo,
    getImageHeight,
    webtoonPageElementRefs,
    imageRefs,
    htmlContents,
  });

  const handleMeasureWebtoonImageHeight = useCallback(
    (pageIndex: number, naturalWidth: number, naturalHeight: number) => {
      const measuredHeight = getImageHeight(naturalWidth, naturalHeight);
      webtoonVirtualization.setImageHeights((prev) => {
        const current = prev[pageIndex];
        if (current && Math.abs(current - measuredHeight) <= 2) return prev;
        const next = [...prev];
        next[pageIndex] = measuredHeight;
        return next;
      });
    },
    [getImageHeight, webtoonVirtualization]
  );

  const webtoonVisibleRealRange = useMemo(() => {
    if (readingMode !== 'webtoon') return webtoonVirtualization.visibleRange;

    let start = Number.POSITIVE_INFINITY;
    let end = -1;
    for (
      let i = webtoonVirtualization.visibleRange.start;
      i <= webtoonVirtualization.visibleRange.end;
      i += 1
    ) {
      const item = streamPages[i];
      if (!item || item.type === 'virtual-end') continue;
      start = Math.min(start, item.streamRealPage);
      end = Math.max(end, item.streamRealPage);
    }

    if (end < 0) {
      return { start: currentRealPage, end: currentRealPage };
    }
    return { start, end };
  }, [currentRealPage, readingMode, streamPages, webtoonVirtualization.visibleRange]);

  // Stable reference: avoid re-running effects on every render (can cause update loops).
  const priorityIndices = useMemo(() => {
    if (readingMode === 'webtoon') {
      return [currentRealPage];
    }

    if (
      doublePageMode &&
      !isCurrentHtmlPage &&
      !(splitCoverMode && currentPage === 0) &&
      currentPage + 1 < pages.length
    ) {
      return [currentPage, currentPage + 1];
    }
    return [currentPage];
  }, [currentPage, currentRealPage, doublePageMode, isCurrentHtmlPage, pages.length, readingMode, splitCoverMode]);

  const imageLoading = useReaderImageLoading({
    pages,
    readingMode,
    currentPage: readingMode === 'webtoon' ? currentRealPage : currentPage,
    priorityIndices,
    visibleRange: webtoonVisibleRealRange,
    resetKey: sourceArchiveId,
    imageRefs,
  });
  const { setImagesLoading } = imageLoading;

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
        const data = await ArchiveService.getFiles(sourceArchiveId);
        const initialPages = mapPageDtosToReaderPageItems(data.pages, sourceArchiveId);
        appendedArchiveIdsRef.current = new Set([sourceArchiveId]);
        setSegments([
          {
            archiveId: sourceArchiveId,
            start: 0,
            count: initialPages.length,
            title: sourceArchiveId,
          },
        ]);

        // 计算初始页码
        let initialPage: number;

        // URL的page参数优先级最高（1-based，包含后续虚拟页；此处先按“真实页面”初始化，虚拟页在合集信息就绪后再补齐）
        const pageParamSnapshot = searchParams?.get('page');
        if (pageParamSnapshot) {
          const urlPage = parseInt(pageParamSnapshot, 10);
          if (!isNaN(urlPage) && urlPage > 0) {
            pendingUrlPageRawRef.current = urlPage;
            pendingUrlPageIndexRef.current = urlPage - 1;
            if (urlPage - 1 >= 0 && urlPage - 1 < initialPages.length) {
              initialPage = urlPage - 1;
            } else {
              initialPage = Math.max(0, initialPages.length - 1);
              // For webtoon, an out-of-range page is treated as "jump to end".
              pendingWebtoonScrollToEdgeRef.current = 'bottom';
            }
          } else {
            pendingUrlPageRawRef.current = null;
            pendingUrlPageIndexRef.current = null;
            initialPage = 0;
          }
        } else if (data.progress > 0 && data.progress < initialPages.length) {
          // 没有URL参数时，使用保存的阅读进度
          initialPage = data.progress - 1; // API使用1-based页码，转换为0-based
        } else {
          initialPage = 0;
        }
        
        // 检查是否启用了拆分封面模式
        const doublePageModeFromStorage = typeof window !== 'undefined' 
          ? localStorage.getItem('doublePageMode') === 'true' 
          : false;
        const splitCoverModeFromStorage = typeof window !== 'undefined' 
          ? localStorage.getItem('splitCoverMode') === 'true' 
          : false;
        const initialPageIsHtml = initialPages[initialPage]?.type === 'html';
          
        // 在拆分封面模式下，需要调整恢复的页码（HTML 分页不使用 split-cover 规则）
        if (doublePageModeFromStorage && splitCoverModeFromStorage && !initialPageIsHtml) {
          if (initialPage === 0) {
            // 第1页，在拆分封面模式下显示为封面
            initialPage = 0;
          } else if (initialPage === 1) {
            // 第2页，在拆分封面模式下显示为第2页（与第3页一起）
            initialPage = 1;
          } else if (initialPage === 2) {
            // 第3页，在拆分封面模式下显示为第2页（与第2页一起）
            initialPage = 1;
          } else if (initialPage % 2 === 1) {
            // 奇数页（第5、7、9...页），在拆分封面模式下显示为第(currentPage-1)页（与前一页一起）
            initialPage = initialPage - 2;
          } else {
            // 偶数页（第4、6、8...页），在拆分封面模式下显示为第(currentPage-2)页（与后一页一起）
            initialPage = initialPage - 2;
          }
        }

        // 原子性地设置状态，避免多次渲染
        setPages(initialPages);
        setCurrentPage(initialPage);
        if (readingMode === 'webtoon') {
          pendingWebtoonScrollToIndexRef.current = initialPage;
          if (!pendingWebtoonScrollToEdgeRef.current && initialPage <= 0) {
            pendingWebtoonScrollToEdgeRef.current = 'top';
          }
        }

        // 如果有进度且需要预加载图片，添加到加载队列（跳过 HTML 页，HTML 由 useReaderHtmlPages 加载）
        if (initialPage > 0 && initialPages[initialPage]?.type !== 'html') {
          setImagesLoading(new Set([initialPage]));
        }
      } catch (err) {
        logger.apiError('fetch archive pages', err);
        setError('Failed to fetch archive pages');
      } finally {
        setLoading(false);
      }
    }

    fetchPages();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [sourceArchiveId, setImagesLoading]);

  useEffect(() => {
    currentPageRef.current = currentPage;
  }, [currentPage]);

  useEffect(() => {
    pagesLengthRef.current = pages.length;
  }, [pages.length]);

  useEffect(() => {
    appendedArchiveIdsRef.current = new Set(segments.map((segment) => segment.archiveId));
  }, [segments]);

  const resolveNextArchiveCandidate = useCallback(
    async (archiveId: string, excludedIds?: Set<string>): Promise<EndPageNextArchive | null> => {
      const isExcluded = (candidateId: string) =>
        candidateId === archiveId || Boolean(excludedIds?.has(candidateId));

      try {
        const tanks = await TankoubonService.getTankoubonsForArchive(archiveId);
        if (tanks && tanks.length > 0) {
          const chosen = [...tanks].sort((a, b) => {
            const fav = Number(Boolean(b.isfavorite)) - Number(Boolean(a.isfavorite));
            if (fav !== 0) return fav;
            const aCount = a.archives?.length ?? 0;
            const bCount = b.archives?.length ?? 0;
            return bCount - aCount;
          })[0];

          const idx = chosen.archives?.indexOf(archiveId) ?? -1;
          const nextId = idx >= 0 ? chosen.archives?.[idx + 1] : undefined;
          if (nextId && !isExcluded(nextId)) {
            try {
              const meta = await ArchiveService.getMetadata(nextId, language);
              const nextTitle = (meta.title && meta.title.trim()) ? meta.title : meta.filename || nextId;
              return {
                id: nextId,
                title: nextTitle,
                coverAssetId: getArchiveAssetId(meta, 'cover'),
                source: 'tankoubon',
              };
            } catch (metaErr) {
              logger.apiError('fetch next archive metadata', metaErr);
              return { id: nextId, title: nextId, source: 'tankoubon' };
            }
          }
        }
      } catch (err) {
        logger.apiError('fetch tankoubons for archive', err);
      }

      let randomCandidate: Archive | null = null;
      for (let attempt = 0; attempt < 5 && !randomCandidate; attempt += 1) {
        try {
          const randomItems = await ArchiveService.getRandom({
            count: 8,
            groupby_tanks: false,
            lang: language,
          });
          randomCandidate = randomItems.find(
            (item): item is Archive => 'arcid' in item && !isExcluded(item.arcid)
          ) || null;
        } catch (randomErr) {
          logger.apiError('fetch random archive for reader', randomErr);
        }
      }

      if (!randomCandidate) return null;
      const randomTitle = (randomCandidate.title && randomCandidate.title.trim())
        ? randomCandidate.title
        : randomCandidate.filename || randomCandidate.arcid;
      return {
        id: randomCandidate.arcid,
        title: randomTitle,
        coverAssetId: getArchiveAssetId(randomCandidate, 'cover'),
        source: 'random',
      };
    },
    [language]
  );

  const resolveNextArchiveCandidateCached = useCallback(
    async (archiveId: string, excludedIds?: Set<string>): Promise<EndPageNextArchive | null> => {
      const isCandidateExcluded = (candidate: EndPageNextArchive | null) =>
        !candidate?.id ||
        candidate.id === archiveId ||
        Boolean(excludedIds?.has(candidate.id));

      const cached = nextArchiveCandidateCacheRef.current.get(archiveId);
      if (cached && !isCandidateExcluded(cached)) {
        return cached;
      }

      const pending = nextArchiveCandidateRequestRef.current.get(archiveId);
      if (pending) {
        const pendingResult = await pending;
        if (pendingResult && !isCandidateExcluded(pendingResult)) {
          return pendingResult;
        }
      }

      const request = resolveNextArchiveCandidate(archiveId, excludedIds)
        .then((result) => {
          if (result?.id && result.id !== archiveId) {
            nextArchiveCandidateCacheRef.current.set(archiveId, result);
          }
          return result;
        })
        .finally(() => {
          nextArchiveCandidateRequestRef.current.delete(archiveId);
        });

      nextArchiveCandidateRequestRef.current.set(archiveId, request);

      const resolved = await request;
      if (isCandidateExcluded(resolved)) return null;
      return resolved;
    },
    [resolveNextArchiveCandidate]
  );

  // Resolve end-page navigation targets:
  // - In a tankoubon, use previous/next chapter.
  // - For a standalone archive, show a random next manga.
  useEffect(() => {
    if (!sourceArchiveId) {
      setTankoubonContext(null);
      setPrevArchiveId(null);
      setNextArchiveByArchiveId({});
      return;
    }

    let cancelled = false;
    (async () => {
      try {
        const tanks = await TankoubonService.getTankoubonsForArchive(sourceArchiveId);
        if (cancelled) return;

        if (!tanks || tanks.length === 0) {
          setTankoubonContext(null);
          setPrevArchiveId(null);

          const randomNext = await resolveNextArchiveCandidateCached(
            sourceArchiveId,
            new Set([sourceArchiveId])
          );
          if (cancelled) return;
          setResolvedNextArchive(
            sourceArchiveId,
            randomNext && randomNext.source === 'random' ? randomNext : null
          );
          return;
        }

        // If an archive is in multiple tankoubons, prefer the favorited one (then the larger one).
        const chosen = [...tanks].sort((a, b) => {
          const fav = Number(Boolean(b.isfavorite)) - Number(Boolean(a.isfavorite));
          if (fav !== 0) return fav;
          const aCount = a.archives?.length ?? 0;
          const bCount = b.archives?.length ?? 0;
          return bCount - aCount;
        })[0];

        setTankoubonContext(chosen);

        const idx = chosen.archives?.indexOf(sourceArchiveId) ?? -1;
        const prevId = idx > 0 ? chosen.archives?.[idx - 1] : undefined;
        setPrevArchiveId(prevId ?? null);
        const nextId = idx >= 0 ? chosen.archives?.[idx + 1] : undefined;
        if (!nextId) {
          setResolvedNextArchive(sourceArchiveId, null);
          return;
        }

        try {
          const meta = await ArchiveService.getMetadata(nextId, language);
          if (cancelled) return;
          const nextTitle = (meta.title && meta.title.trim()) ? meta.title : meta.filename || nextId;
          setResolvedNextArchive(sourceArchiveId, {
            id: nextId,
            title: nextTitle,
            coverAssetId: getArchiveAssetId(meta, 'cover'),
            source: 'tankoubon',
          });
        } catch (metaErr) {
          logger.apiError('fetch next archive metadata', metaErr);
          if (cancelled) return;
          setResolvedNextArchive(sourceArchiveId, { id: nextId, title: nextId, source: 'tankoubon' });
        }
      } catch (err) {
        logger.apiError('fetch tankoubons for archive', err);
        if (cancelled) return;
        setTankoubonContext(null);
        setPrevArchiveId(null);
        setResolvedNextArchive(sourceArchiveId, null);
      }
    })();

    return () => {
      cancelled = true;
    };
  }, [sourceArchiveId, language, resolveNextArchiveCandidateCached, setResolvedNextArchive]);

  useEffect(() => {
    if (!activeArchiveId || !archive.archiveTitle) return;
    setSegments((prev) => {
      const index = prev.findIndex((segment) => segment.archiveId === activeArchiveId);
      if (index < 0) return prev;
      if (prev[index].title === archive.archiveTitle) return prev;
      const next = [...prev];
      next[index] = { ...next[index], title: archive.archiveTitle };
      return next;
    });
  }, [activeArchiveId, archive.archiveTitle]);

  useEffect(() => {
    if (!seamlessEnabled) return;
    if (segments.length <= 0) return;

    const tailSegment = segments[segments.length - 1];
    if (!tailSegment?.archiveId) return;
    if (nextArchiveByArchiveId[tailSegment.archiveId] !== undefined) return;

    let cancelled = false;
    const excluded = new Set(appendedArchiveIdsRef.current);
    excluded.add(tailSegment.archiveId);

    void resolveNextArchiveCandidateCached(tailSegment.archiveId, excluded).then((candidate) => {
      if (cancelled) return;
      setResolvedNextArchive(tailSegment.archiveId, candidate);
    });

    return () => {
      cancelled = true;
    };
  }, [
    nextArchiveByArchiveId,
    resolveNextArchiveCandidateCached,
    seamlessEnabled,
    segments,
    setResolvedNextArchive,
  ]);

  const appendNextArchiveToStream = useCallback(async () => {
    if (!seamlessEnabled) return false;
    if (segments.length === 0) return false;
    if (seamlessAppendInFlightRef.current) return false;

    const tailSegment = segments[segments.length - 1];
    if (!tailSegment) return false;

    const excluded = new Set(appendedArchiveIdsRef.current);
    excluded.add(tailSegment.archiveId);

    seamlessAppendInFlightRef.current = true;
    try {
      const target = await resolveNextArchiveCandidateCached(tailSegment.archiveId, excluded);
      setResolvedNextArchive(tailSegment.archiveId, target);
      if (!target?.id) return false;
      if (appendedArchiveIdsRef.current.has(target.id)) return false;

      const data = await ArchiveService.getFiles(target.id);
      if (!data.pages || data.pages.length === 0) return false;

      const start = pagesLengthRef.current;
      const appendedPages = mapPageDtosToReaderPageItems(data.pages, target.id);
      setPages((prev) => [...prev, ...appendedPages]);
      setSegments((prev) => [
        ...prev,
        {
          archiveId: target.id,
          start,
          count: appendedPages.length,
          title: target.title || target.id,
          coverAssetId: target.coverAssetId,
        },
      ]);
      appendedArchiveIdsRef.current.add(target.id);
      return true;
    } catch (err) {
      logger.apiError('append seamless archive pages', err);
      return false;
    } finally {
      seamlessAppendInFlightRef.current = false;
    }
  }, [resolveNextArchiveCandidateCached, seamlessEnabled, segments, setResolvedNextArchive]);

  const handleWebtoonScroll = useCallback(
    (e: React.UIEvent<HTMLDivElement>) => {
      webtoonVirtualization.handleWebtoonScroll(e);
      if (!seamlessWebtoonEnabled || virtualPageIndex < 0) return;
      const container = e.currentTarget;
      const thresholdOffset = container.scrollTop + container.clientHeight * 0.3;
      const scrollDrivenPageIndex = webtoonVirtualization.getIndexAtOffset(thresholdOffset);
      const onVirtualPage = scrollDrivenPageIndex >= virtualPageIndex;

      if (!onVirtualPage) {
        webtoonVirtualPageSeenRef.current = false;
        seamlessAppendTriggeredRef.current = false;
        return;
      }

      if (!webtoonVirtualPageSeenRef.current) {
        webtoonVirtualPageSeenRef.current = true;
        virtualEndEnteredAtRef.current = Date.now();
      }

      const distanceToBottom = container.scrollHeight - (container.scrollTop + container.clientHeight);
      const atBottom = distanceToBottom <= 24;

      if (!atBottom) {
        seamlessAppendTriggeredRef.current = false;
        return;
      }

      if (virtualEndEnteredAtRef.current > 0 && Date.now() - virtualEndEnteredAtRef.current < 280) {
        return;
      }

      if (seamlessAppendTriggeredRef.current || seamlessAppendInFlightRef.current) return;
      seamlessAppendTriggeredRef.current = true;
      void appendNextArchiveToStream().then((ok) => {
        if (!ok) {
          seamlessAppendTriggeredRef.current = false;
        }
      });
    },
    [appendNextArchiveToStream, seamlessWebtoonEnabled, virtualPageIndex, webtoonVirtualization]
  );

  // 单独处理错误消息的翻译
  useEffect(() => {
    if (error === 'Missing archive ID') {
      setError(t('reader.missingId'));
    } else if (error === 'Failed to fetch archive pages') {
      setError(t('reader.fetchError'));
    }
  }, [error, t]);

  // 切换全屏模式
  const toggleFullscreen = useCallback(async () => {
    if (!document.fullscreenElement) {
      try {
        // On some mobile browsers, entering fullscreen may auto-rotate to landscape.
        // If supported, lock the orientation to whatever the user currently has.
        const currentOrientation =
          typeof window !== 'undefined' ? window.screen?.orientation?.type : undefined;

        await document.documentElement.requestFullscreen();
        setIsFullscreen(true);
        if (typeof window !== 'undefined') {
          localStorage.setItem('reader-fullscreen-mode', 'true');
        }

        if (typeof window !== 'undefined') {
          // TS/lib.dom types vary; treat Screen Orientation API as optional/best-effort.
          const orientation: any = (window.screen as any)?.orientation;
          const canLock = typeof orientation?.lock === 'function';
          // Only try on touch/coarse-pointer devices to avoid noisy errors on desktop.
          const isCoarsePointer =
            typeof window.matchMedia === 'function' && window.matchMedia('(pointer: coarse)').matches;
          if (canLock && isCoarsePointer) {
            const lockTarget =
              currentOrientation?.startsWith('landscape') ? 'landscape' : 'portrait';
            try {
              await orientation.lock(lockTarget);
            } catch {
              // Ignore: orientation lock is best-effort and may be blocked by the browser/OS.
            }
          }
        }
      } catch (err) {
        logger.operationFailed('enter fullscreen', err);
      }
    } else {
      try {
        await document.exitFullscreen();
        setIsFullscreen(false);
        if (typeof window !== 'undefined') {
          localStorage.setItem('reader-fullscreen-mode', 'false');
        }

        if (typeof window !== 'undefined') {
          try {
            const orientation: any = (window.screen as any)?.orientation;
            orientation?.unlock?.();
          } catch {
            // Ignore: unlock may be unsupported.
          }
        }
      } catch (err) {
        logger.operationFailed('exit fullscreen', err);
      }
    }
  }, [setIsFullscreen]);

  // 监听全屏状态变化
  useEffect(() => {
    const handleFullscreenChange = () => {
      setIsFullscreen(!!document.fullscreenElement);
      if (typeof window !== 'undefined') {
        localStorage.setItem('reader-fullscreen-mode', document.fullscreenElement ? 'true' : 'false');
      }
    };

    document.addEventListener('fullscreenchange', handleFullscreenChange);
    return () => {
      document.removeEventListener('fullscreenchange', handleFullscreenChange);
    };
  }, [setIsFullscreen]);

  const settingButtons = useMemo(
    () => [
      {
        key: 'doublePage',
        label: t('reader.doublePage'),
        icon: Layout,
        active: doublePageMode,
        disabled: readingMode === 'webtoon',
        onClick: () => setDoublePageMode((prev) => !prev),
        tooltip: t('reader.doublePageTooltip'),
      },
      {
        key: 'splitCover',
        label: t('reader.splitCover'),
        icon: Scissors,
        active: splitCoverMode,
        disabled: !doublePageMode || isCurrentOrTailHtmlPage,
        onClick: () => setSplitCoverMode((prev) => !prev),
        tooltip: t('reader.splitCoverTooltip'),
      },
      {
        key: 'autoPlay',
        label: t('reader.autoPlay'),
        icon: Play,
        active: autoPlayMode,
        disabled: false,
        onClick: () => setAutoPlayMode((prev) => !prev),
        tooltip: t('reader.autoPlayTooltip'),
      },
      {
        key: 'fullscreen',
        label: t('reader.fullscreen'),
        icon: isFullscreen ? Minimize : Maximize,
        active: isFullscreen,
        disabled: false,
        onClick: toggleFullscreen,
        tooltip: t('reader.fullscreenTooltip'),
      },
      {
        key: 'doubleTap',
        label: t('reader.doubleTap'),
        icon: ZoomIn,
        active: doubleTapZoom,
        disabled: false,
        onClick: () => setDoubleTapZoom((prev) => !prev),
        tooltip: t('reader.doubleTapTooltip'),
      },
      {
        key: 'longPage',
        label: t('reader.longPage'),
        icon: ScrollText,
        active: longPageEnabled,
        disabled: readingMode === 'webtoon',
        onClick: () => setLongPageEnabled((prev) => !prev),
        tooltip: t('reader.longPageTooltip'),
      },
      {
        key: 'seamlessNext',
        label: t('reader.seamlessNext'),
        icon: Link2,
        active: seamlessNextEnabled,
        disabled: false,
        onClick: () => setSeamlessNextEnabled((prev) => !prev),
        tooltip: t('reader.seamlessNextTooltip'),
      },
      {
        key: 'autoHide',
        label: t('reader.autoHide'),
        icon: Eye,
        active: autoHideEnabled,
        disabled: false,
        onClick: () => setAutoHideEnabled((prev) => !prev),
        tooltip: t('reader.autoHideTooltip'),
      },
      {
        key: 'tapTurnPage',
        label: t('reader.tapTurnPage'),
        icon: MousePointerClick,
        active: tapTurnPageEnabled,
        disabled: false,
        onClick: () => setTapTurnPageEnabled((prev) => !prev),
        tooltip: t('reader.tapTurnPageTooltip'),
      },
      {
        key: 'mediaInfo',
        label: t('reader.mediaInfo'),
        icon: Info,
        active: mediaInfoEnabled,
        disabled: false,
        onClick: () => setMediaInfoEnabled((prev) => !prev),
        tooltip: t('reader.mediaInfoTooltip'),
      },
    ],
    [
      t,
      readingMode,
      doublePageMode,
      isCurrentOrTailHtmlPage,
      splitCoverMode,
      setDoublePageMode,
      setSplitCoverMode,
      setAutoPlayMode,
      autoPlayMode,
      isFullscreen,
      doubleTapZoom,
      setDoubleTapZoom,
      autoHideEnabled,
      setAutoHideEnabled,
      tapTurnPageEnabled,
      setTapTurnPageEnabled,
      mediaInfoEnabled,
      toggleFullscreen,
      setMediaInfoEnabled,
      longPageEnabled,
      setLongPageEnabled,
      seamlessNextEnabled,
      setSeamlessNextEnabled,
    ]
  );

  useEffect(() => {
    if (!mediaInfoEnabled) return;
    const interval = window.setInterval(() => setMediaInfoTick((prev) => prev + 1), 250);
    return () => window.clearInterval(interval);
  }, [mediaInfoEnabled]);

  useReaderProgressTracking({
    id: seamlessEnabled ? activeArchiveId : sourceArchiveId,
    currentPage: seamlessEnabled ? activeLocalPage : currentPage,
    pagesLength: seamlessEnabled && activeSegment ? activeSegment.count : pages.length,
    doublePageMode,
    splitCoverMode,
    currentItemType: isCurrentOrTailHtmlPage ? 'html' : currentPageType,
  });

  // Apply URL `page` -> state. This runs for all modes (including webtoon and the synthetic "end" page).
  // IMPORTANT: Do NOT refetch pages when only `page` changes; otherwise every flip causes flicker.
  useEffect(() => {
    if (!sourceArchiveId) return;
    if (!pageParam) return;
    if (totalPages <= 0 && effectiveSegments.length <= 0) return;
    const urlPage = parseInt(pageParam, 10);
    if (isNaN(urlPage) || urlPage <= 0) return;
    const urlArchiveId = queryArchiveId || sourceArchiveId;
    const urlPositionKey = `${urlArchiveId}:${urlPage}`;
    if (handledUrlPositionRef.current === urlPositionKey) return;

    let desiredIndex = Math.max(0, Math.min(urlPage - 1, totalPages - 1));
    if (seamlessEnabled && effectiveSegments.length > 0) {
      const targetSegmentIndex = Math.max(
        0,
        effectiveSegments.findIndex((segment) => segment.archiveId === urlArchiveId)
      );
      const targetSegment = effectiveSegments[targetSegmentIndex] ?? effectiveSegments[0];
      const desiredLocalIndex = Math.max(0, urlPage - 1);

      if (desiredLocalIndex >= targetSegment.count) {
        const segmentVirtualIndex = streamVirtualIndexBySegment.get(targetSegmentIndex);
        desiredIndex =
          segmentVirtualIndex ??
          (virtualPageIndex >= 0 ? virtualPageIndex : Math.max(0, pages.length - 1));
      } else {
        const localPage = Math.max(0, Math.min(desiredLocalIndex, Math.max(0, targetSegment.count - 1)));
        const realPage = targetSegment.start + localPage;
        desiredIndex = streamIndexByRealPage.get(realPage) ?? realPage;
      }
    }

    if (desiredIndex === currentPageRef.current) {
      handledUrlPositionRef.current = urlPositionKey;
      return;
    }

    setCurrentPage(desiredIndex);
    setScale(1);
    setTranslateX(0);
    setTranslateY(0);
    handledUrlPositionRef.current = urlPositionKey;

    if (readingMode === 'webtoon') {
      pendingWebtoonScrollToIndexRef.current = desiredIndex;
      pendingWebtoonScrollToEdgeRef.current =
        desiredIndex <= 0 ? 'top' : desiredIndex >= totalPages - 1 ? 'bottom' : null;
    }
  }, [
    sourceArchiveId,
    pageParam,
    totalPages,
    readingMode,
    seamlessEnabled,
    queryArchiveId,
    effectiveSegments,
    pages.length,
    streamIndexByRealPage,
    streamVirtualIndexBySegment,
    virtualPageIndex,
  ]);

  // Sync state -> URL `page` for all modes (including virtual page). Debounced to avoid rapid-flip flicker.
  useEffect(() => {
    if (!sourceArchiveId) return;
    if (totalPages <= 0) return;
    if (currentPage < 0 || currentPage >= totalPages) return;

    const targetArchiveId = seamlessEnabled ? activeArchiveId : sourceArchiveId;
    if (!targetArchiveId) return;
    const targetPage = seamlessEnabled
      ? (isCollectionEndPage && activeSegment ? activeSegment.count + 1 : activeLocalPage + 1)
      : currentPage + 1;

    if (urlSyncTimerRef.current) clearTimeout(urlSyncTimerRef.current);
    urlSyncTimerRef.current = setTimeout(() => {
      const desiredPage = String(targetPage);
      if (seamlessEnabled && typeof window !== 'undefined') {
        const params = new URLSearchParams(window.location.search || '');
        const currentUrlPage = params.get('page');
        const currentUrlId = params.get('id');
        if (currentUrlId === targetArchiveId && currentUrlPage === desiredPage) return;

        params.set('id', targetArchiveId);
        params.set('page', desiredPage);
        suppressNextQueryIdSyncRef.current = targetArchiveId;
        if (queryIdSuppressTimerRef.current) clearTimeout(queryIdSuppressTimerRef.current);
        queryIdSuppressTimerRef.current = setTimeout(() => {
          if (suppressNextQueryIdSyncRef.current === targetArchiveId) {
            suppressNextQueryIdSyncRef.current = null;
          }
          queryIdSuppressTimerRef.current = null;
        }, 200);
        window.history.replaceState(window.history.state, '', `/reader?${params.toString()}`);
        return;
      }

      const currentUrlPage = searchParams?.get('page') ?? null;
      const currentUrlId = searchParams?.get('id') ?? null;
      if (currentUrlId === targetArchiveId && currentUrlPage === desiredPage) return;

      const params = new URLSearchParams(searchParams?.toString() || '');
      params.set('id', targetArchiveId);
      params.set('page', desiredPage);
      router.replace(`/reader?${params.toString()}`, { scroll: false });
    }, 120);

    return () => {
      if (urlSyncTimerRef.current) clearTimeout(urlSyncTimerRef.current);
    };
  }, [
    activeArchiveId,
    activeSegment,
    activeLocalPage,
    currentPage,
    isCollectionEndPage,
    router,
    searchParams,
    seamlessEnabled,
    sourceArchiveId,
    totalPages,
  ]);

  // Webtoon: when the "current page" changes via URL/slider/initial load, scroll the container to match.
  // (Scroll-driven currentPage updates do NOT set the pending refs, so user scrolling won't get interrupted.)
  useEffect(() => {
    if (readingMode !== 'webtoon') return;
    const container = webtoonContainerRef.current;
    if (!container) return;

    const edge = pendingWebtoonScrollToEdgeRef.current;
    const index = pendingWebtoonScrollToIndexRef.current;
    if (!edge && index == null) return;

    pendingWebtoonScrollToEdgeRef.current = null;
    pendingWebtoonScrollToIndexRef.current = null;

    requestAnimationFrame(() => {
      if (edge === 'top') {
        container.scrollTop = 0;
        return;
      }
      if (edge === 'bottom') {
        container.scrollTop = container.scrollHeight;
        return;
      }
      if (index != null) {
        const offset = webtoonVirtualization.prefixHeights[index] || 0;
        container.scrollTop = offset;
      }
    });
  }, [readingMode, webtoonVirtualization.prefixHeights]);

  // 加载HTML页面内容（单页模式：当前页；条漫模式：可见范围内）
  useEffect(() => {
    if (!sourceArchiveId || pages.length === 0) return;

    if (readingMode === 'webtoon') {
      for (let i = webtoonVirtualization.visibleRange.start; i <= webtoonVirtualization.visibleRange.end; i += 1) {
        const item = streamPages[i];
        if (item?.type === 'html') {
          void loadHtmlPage(item.streamRealPage);
        }
      }
      return;
    }

    if (currentRealPage >= 0 && currentRealPage < pages.length && pages[currentRealPage]?.type === 'html') {
      void loadHtmlPage(currentRealPage);
    }
  }, [sourceArchiveId, pages, currentRealPage, readingMode, streamPages, webtoonVirtualization.visibleRange, loadHtmlPage]);

  // 重置变换
  const resetTransform = useCallback(() => {
    setScale(1);
    setTranslateX(0);
    setTranslateY(0);
  }, []);

  const sidebar = useReaderSidebar({
    pages,
    currentPage: readingMode === 'webtoon' ? currentRealPage : currentPage,
    resetKey: sourceArchiveId,
    loading,
    onSelectPage: (pageIndex) => {
      if (readingMode === 'webtoon') {
        setCurrentPage(streamIndexByRealPage.get(pageIndex) ?? pageIndex);
        return;
      }
      setCurrentPage(pageIndex);
    },
    resetTransform,
  });

  const mediaInfoOverlayLines = useMediaInfoOverlayLines({
    enabled: mediaInfoEnabled,
    tick: mediaInfoTick,
    pages,
    currentPage: readingMode === 'webtoon' ? currentRealPage : currentPage,
    readingMode,
    doublePageMode,
    splitCoverMode,
    isHtmlSpreadView,
    cachedPages: imageLoading.cachedPages,
    htmlContents,
    scale,
    translateX,
    translateY,
    isFullscreen,
    showToolbar: toolbar.showToolbar,
    sidebarOpen: sidebar.sidebarOpen,
    autoHideEnabled,
    tapTurnPageEnabled,
    doubleTapZoom,
    autoPlayMode,
    autoPlayInterval,
    imagesLoading: imageLoading.imagesLoading,
    loadedImages: imageLoading.loadedImages,
    visibleRange: webtoonVisibleRealRange,
    imageRefs,
    videoRefs,
    htmlContainerRefs,
    imageRequestUrls,
  });

  const handleSliderChangePage = useCallback(
    (newPage: number) => {
      const targetRealPage =
        seamlessEnabled && activeSegment
          ? activeSegment.start + Math.max(0, Math.min(activeSegment.count - 1, newPage))
          : newPage;
      const targetPage =
        readingMode === 'webtoon'
          ? (streamIndexByRealPage.get(targetRealPage) ?? targetRealPage)
          : targetRealPage;

      setCurrentPage(targetPage);
      resetTransform();

      if (readingMode === 'webtoon' && webtoonContainerRef.current) {
        let accumulatedHeight = 0;
        for (let i = 0; i < targetPage; i++) {
          const imageHeight =
            webtoonVirtualization.imageHeights[i] ||
            webtoonVirtualization.containerHeight ||
            window.innerHeight * 0.7;
          accumulatedHeight += imageHeight;
        }
        webtoonContainerRef.current.scrollTop = accumulatedHeight;
      }
    },
    [
      activeSegment,
      resetTransform,
      readingMode,
      seamlessEnabled,
      streamIndexByRealPage,
      webtoonVirtualization.containerHeight,
      webtoonVirtualization.imageHeights,
    ]
  );

  // 处理双击放大
  const handleDoubleClick = useCallback((e: React.MouseEvent) => {
    if (!doubleTapZoom) return;

    // 开启“点击翻页”时，边缘区域优先用于翻页；缩小鼠标双击放大触发区域（仅中心区域可放大）
    if (tapTurnPageEnabled) {
      const action = getTapTurnAction(readerAreaRef.current, e.clientX, e.clientY);
      if (action === 'prev' || action === 'next') return;
    }
    
    e.preventDefault();
    
    // 使用React内置的双击事件，不需要手动检测
    if (scale === 1) {
      const targetScale = 2;
      const currentTarget = e.currentTarget as HTMLElement;
      const transformTarget =
        (doublePageMode
          ? (currentTarget.closest('[data-reader-zoom-surface="true"]') as HTMLElement | null)
          : currentTarget) || currentTarget;
      const rect = transformTarget.getBoundingClientRect();

      // 计算点击位置相对于变换中心（默认中心点）的偏移
      const x = e.clientX - rect.left - rect.width / 2;
      const y = e.clientY - rect.top - rect.height / 2;

      // 锚点缩放：尽量让双击点在放大后保持原位，避免出现“点哪偏哪”的跳动。
      const nextTranslateX = (scale * (x + translateX)) / targetScale - x;
      const nextTranslateY = (scale * (y + translateY)) / targetScale - y;

      // 当前 transform 是 scale(...) translate(...)，translate 会被 scale 放大，
      // 所以边界要换算回 translate 坐标空间。
      const viewportRect = readerAreaRef.current?.getBoundingClientRect();
      const viewportWidth = Math.min(rect.width, viewportRect?.width || rect.width || window.innerWidth);
      const viewportHeight = Math.min(rect.height, viewportRect?.height || rect.height || window.innerHeight);
      const maxTranslateX = Math.max(
        0,
        (rect.width * targetScale - viewportWidth) / (2 * targetScale)
      );
      const maxTranslateY = Math.max(
        0,
        (rect.height * targetScale - viewportHeight) / (2 * targetScale)
      );

      const limitedTranslateX = Math.max(-maxTranslateX, Math.min(maxTranslateX, nextTranslateX));
      const limitedTranslateY = Math.max(-maxTranslateY, Math.min(maxTranslateY, nextTranslateY));

      setScale(targetScale);
      setTranslateX(limitedTranslateX);
      setTranslateY(limitedTranslateY);
    } else {
      // 重置缩放
      resetTransform();
    }
  }, [
    doubleTapZoom,
    tapTurnPageEnabled,
    scale,
    translateX,
    translateY,
    resetTransform,
    doublePageMode,
    readerAreaRef,
  ]);

  // 处理图片拖拽开始
  const handleImageDragStart = useCallback((e: React.DragEvent) => {
    e.preventDefault();
  }, []);

  const tryTurnHtmlSpread = useCallback(
    (direction: 'prev' | 'next') => {
      if (!isHtmlSpreadView) return false;

      const container = htmlContainerRefs.current[currentPage];
      if (!container) return false;

      return stepHtmlSpread(container, direction);
    },
    [currentPage, htmlContainerRefs, isHtmlSpreadView]
  );

  const handlePrevPage = useCallback(() => {
    if (isCollectionEndPage) {
      // From the synthetic "end" page, go back to the last real page.
      if (pages.length <= 0 || !activeSegment || activeSegment.count <= 0) return;

      let targetReal = activeSegment.start + activeSegment.count - 1;
      const activeTailPage = pages[targetReal];
      if (readingMode !== 'webtoon' && doublePageMode && activeTailPage?.type !== 'html') {
        const segmentLength = activeSegment.count;
        if (splitCoverMode) {
          // split-cover spreads start at 1: (1,2), (3,4)...
          // When segment length is odd, the last page is part of a spread starting at -2.
          if (segmentLength % 2 === 1 && segmentLength >= 2) targetReal -= 1;
        } else {
          // Normal spreads start at 0: (0,1), (2,3)...
          // When segment length is even, the last page is part of a spread starting at -2.
          if (segmentLength % 2 === 0 && segmentLength >= 2) targetReal -= 1;
        }
      }

      const target = streamIndexByRealPage.get(targetReal) ?? targetReal;
      setCurrentPage(Math.max(0, target));
      resetTransform();
      return;
    }

    if (tryTurnHtmlSpread('prev')) return;

    // Tankoubon only: from the first page, flipping "prev" goes to previous chapter end.
    if (currentPage <= 0 && hasTankoubonContext && prevArchiveId) {
      if (seamlessEnabled) return;
      requestChapterJump('prev', navigateToPrevArchiveEnd);
      return;
    }

    if (currentPage > 0) {
      if (isHtmlSpreadView) {
        // HTML 双页模式按章节顺序逐章前进/后退（章节内由水平列分页处理）。
        setCurrentPage(currentPage - 1);
      } else if (doublePageMode && splitCoverMode) {
        // 拆分封面模式：第1页单独显示，其他页面正常拼合
        if (currentPage === 1) {
          // 从第2页回到封面
          setCurrentPage(0);
        } else if (currentPage === 2) {
          // 从第3页回到第2页
          setCurrentPage(1);
        } else if (currentPage > 2) {
          // 其他情况：一次翻两页
          // 注意：currentPage=2时显示的是第2页和第3页，所以前一个应该是第1页
          // currentPage=3时显示的是第4页和第5页，所以前一个应该是第2页和第3页
          setCurrentPage(currentPage - 2);
        }
      } else if (doublePageMode) {
        // 普通双页模式，一次翻两页
        setCurrentPage(Math.max(0, currentPage - 2));
      } else {
        // 单页模式，一次翻一页
        setCurrentPage(currentPage - 1);
      }
      resetTransform();
    }
  }, [
    hasTankoubonContext,
    currentPage,
    isCollectionEndPage,
    requestChapterJump,
    navigateToPrevArchiveEnd,
    pages,
    prevArchiveId,
    activeSegment,
    seamlessEnabled,
    resetTransform,
    readingMode,
    doublePageMode,
    isHtmlSpreadView,
    splitCoverMode,
    streamIndexByRealPage,
    tryTurnHtmlSpread,
  ]);

  const handleNextPage = useCallback(() => {
    if (isCollectionEndPage) {
      if (seamlessEnabled) {
        if (isTailCollectionEndPage) {
          void appendNextArchiveToStream();
        } else if (currentPage < totalPages - 1) {
          setCurrentPage(currentPage + 1);
          resetTransform();
        }
        return;
      }

      // Continue flipping from the synthetic "end" page to the selected next archive.
      if (nextArchive?.id) {
        requestChapterJump('next', navigateToNextArchiveStart);
      }
      return;
    }

    if (tryTurnHtmlSpread('next')) return;

    if (currentPage < totalPages - 1) {
      if (isHtmlSpreadView) {
        setCurrentPage(currentPage + 1);
      } else if (doublePageMode && splitCoverMode) {
        // 拆分封面模式：第1页单独显示，其他页面正常拼合
        if (currentPage === 0) {
          // 从封面跳到第2页（显示第2页和第3页）
          setCurrentPage(1);
        } else if (currentPage === 1) {
          // 从第2页跳到第4页（显示第4页和第5页）
          setCurrentPage(3);
        } else {
          // 其他情况：一次翻两页
          // 注意：currentPage=1时显示的是第2页和第3页，所以下一个应该是第4页和第5页
          // currentPage=3时显示的是第4页和第5页，所以下一个应该是第6页和第7页
          const nextPage = currentPage + 2;
          setCurrentPage(Math.min(nextPage, totalPages - 1));
        }
      } else if (doublePageMode) {
        // 普通双页模式
        if (currentPage + 2 < totalPages) {
          setCurrentPage(currentPage + 2);
        } else {
          setCurrentPage(totalPages - 1);
        }
      } else {
        // 单页模式，一次翻一页
        setCurrentPage(currentPage + 1);
      }
      resetTransform();
    }
  }, [
    currentPage,
    totalPages,
    isCollectionEndPage,
    isTailCollectionEndPage,
    seamlessEnabled,
    appendNextArchiveToStream,
    nextArchive?.id,
    requestChapterJump,
    navigateToNextArchiveStart,
    resetTransform,
    doublePageMode,
    isHtmlSpreadView,
    splitCoverMode,
    tryTurnHtmlSpread,
  ]);

  const interactionHandlers = useReaderInteractionHandlers({
    readerAreaRef,
    readingMode,
    tapTurnPageEnabled,
    autoHideEnabled,
    showToolbar: toolbar.showToolbar,
    onToggleToolbar: toolbar.toggleToolbar,
    onHideToolbar: toolbar.hideToolbar,
    onPrevPage: handlePrevPage,
    onNextPage: handleNextPage,
    onWebtoonStartPrev:
      !seamlessEnabled && hasTankoubonContext && !!prevArchiveId
        ? () => requestChapterJump('prev', navigateToPrevArchiveEnd)
        : undefined,
    onWebtoonEndNext:
      seamlessEnabled
        ? () => {
            void appendNextArchiveToStream();
          }
        : !!nextArchive?.id
        ? () => requestChapterJump('next', navigateToNextArchiveStart)
        : undefined,
    currentPage,
    setCurrentPage: (page) => setCurrentPage(page),
    pagesLength: totalPages,
    webtoonContainerRef,
    imageHeights: webtoonVirtualization.imageHeights,
    containerHeight: webtoonVirtualization.containerHeight,
    setScale,
  });

  useReaderWheelNavigation({
    pages,
    currentPage,
    readingMode,
    autoHideEnabled,
    showToolbar: toolbar.showToolbar,
    hideToolbar: toolbar.hideToolbar,
    onPrevPage: handlePrevPage,
    onNextPage: handleNextPage,
    webtoonContainerRef,
    isCollectionEndPage: isTailCollectionEndPage,
    onWebtoonStartPrev:
      !seamlessEnabled && hasTankoubonContext && !!prevArchiveId
        ? () => requestChapterJump('prev', navigateToPrevArchiveEnd)
        : undefined,
    onWebtoonEndNext:
      seamlessEnabled
        ? () => {
            void appendNextArchiveToStream();
          }
        : !!nextArchive?.id
        ? () => requestChapterJump('next', navigateToNextArchiveStart)
        : undefined,
  });

  useReaderAutoPlay({
    autoPlayMode,
    autoPlayInterval,
    readingMode,
    webtoonContainerRef,
    imageHeights: webtoonVirtualization.imageHeights,
    currentPage,
    pagesLength: totalPages,
    doublePageMode,
    splitCoverMode,
    onNextPage: handleNextPage,
    setAutoPlayMode,
  });
  useReaderKeyboardNavigation({
    readingMode,
    onPrevPage: handlePrevPage,
    onNextPage: handleNextPage,
  });

  // wheel 翻页/HTML 边界倒计时逻辑已抽到 useReaderWheelNavigation

  const getReadingModeIcon = () => {
    switch (readingMode) {
      case 'single-ltr': return <ArrowRight className="w-4 h-4" />;
      case 'single-rtl': return <ArrowLeft className="w-4 h-4" />;
      case 'single-ttb': return <ArrowDown className="w-4 h-4" />;
      case 'webtoon': return <Book className="w-4 h-4" />;
    }
  };

  const getReadingModeText = () => {
    switch (readingMode) {
      case 'single-ltr': return t('reader.leftToRight');
      case 'single-rtl': return t('reader.rightToLeft');
      case 'single-ttb': return t('reader.topToBottom');
      case 'webtoon': return t('reader.webtoon');
    }
  };

  // 自动翻页逻辑已抽到 useReaderAutoPlay

  // 处理拆分封面模式切换时的页面调整
  useEffect(() => {
    if (isCurrentOrTailHtmlPage) return;

    if (doublePageMode && pages.length > 0) {
      // 使用ref来避免无限循环
      const prevSplitCoverMode = splitCoverModeRef.current;
      splitCoverModeRef.current = splitCoverMode;
      
      // 只有当拆分封面模式发生变化时才调整页面
      if (prevSplitCoverMode !== splitCoverMode && prevSplitCoverMode !== undefined) {
        if (splitCoverMode) {
          // 启用拆分封面模式时的页面调整
          if (currentPage === 0) {
            // 当前是封面页，保持不变
            // 无需调整
          } else if (currentPage === 1) {
            // 当前显示第1-2页，调整为显示第2-3页
            setCurrentPage(1);
          } else if (currentPage === 2) {
            // 特殊处理：当前显示第3-4页，在拆分封面模式下应显示第2-3页
            setCurrentPage(1);
          } else if (currentPage % 2 === 0) {
            // 当前是偶数页，在拆分封面模式下需要调整
            // 调整为显示前一页和当前页
            setCurrentPage(currentPage - 1);
          }
          // 奇数页情况保持不变
        } else {
          // 禁用拆分封面模式时的页面调整
          if (currentPage === 0) {
            // 当前是封面页，保持不变
            // 无需调整
          } else if (currentPage === 1) {
            // 当前显示第2-3页，在普通双页模式下应显示第1-2页
            setCurrentPage(0);
          } else {
            // 其他情况，调整为显示当前页和下一页
            if (currentPage % 2 === 1) {
              setCurrentPage(currentPage + 1);
            }
            // 偶数页情况保持不变
          }
        }
      }
    }
  }, [splitCoverMode, doublePageMode, currentPage, pages.length, isCurrentOrTailHtmlPage]);

  const displayArchiveTitle = activeSegment?.title || archive.archiveTitle;

  if (loading) {
    return (
      <div className="min-h-screen bg-black text-white flex items-center justify-center">
        <Spinner size="lg" />
      </div>
    );
  }

  if (error || pages.length === 0) {
    return (
      <div className="min-h-screen bg-black text-white flex items-center justify-center">
        <div className="text-center">
          <p className="text-red-500 mb-4">{error || t('reader.noPages')}</p>
          <Link href={`/archive?id=${activeArchiveId ?? sourceArchiveId ?? ''}`}>
            <Button variant="outline" className="text-white border-white bg-transparent hover:bg-white hover:text-black">
              <ArrowLeft className="w-4 h-4 mr-2" />
              {t('reader.backToArchive')}
            </Button>
          </Link>
        </div>
      </div>
    );
  }

  
  return (
    <div
      className="h-screen bg-background text-foreground flex flex-col overflow-hidden relative"
    >
	      <ReaderTopBar
	        showToolbar={toolbar.showToolbar}
	        archiveTitle={displayArchiveTitle}
	        onBack={handleBack}
	        onToggleSidebar={() => sidebar.setSidebarOpen((prev) => !prev)}
	        onToggleReadingMode={toggleReadingMode}
	        readingModeIcon={getReadingModeIcon()}
	        readingModeText={getReadingModeText()}
	        t={t}
	      />

	      <ReaderFloatingControls
	        showToolbar={toolbar.showToolbar}
	        currentPage={sliderCurrentPage}
	        totalPages={sliderTotalPages}
	        onChangePage={handleSliderChangePage}
	        settingsOpen={settingsOpen}
	        onSettingsOpenChange={setSettingsOpen}
	        archiveTitle={displayArchiveTitle}
	        archiveMetadata={archive.archiveMetadata}
	        metadataTags={archive.metadataTags}
	        id={activeArchiveId}
	        onNavigateToArchive={handleNavigateToArchiveFromSettings}
	        settingButtons={settingButtons}
	        autoPlayMode={autoPlayMode}
	        autoPlayInterval={autoPlayInterval}
	        onAutoPlayIntervalChange={setAutoPlayInterval}
	        isFavorited={archive.isFavorited}
	        onToggleFavorite={archive.toggleFavorite}
	        t={t}
	      />

      {/* 主要阅读区域 */}
      <div
        ref={readerAreaRef}
        className="flex-1 relative overflow-hidden"
        onTouchStart={interactionHandlers.onTouchStart}
        onTouchMove={interactionHandlers.onTouchMove}
        onTouchEnd={interactionHandlers.onTouchEnd}
        onClick={interactionHandlers.onClick}
      >
        {mediaInfoEnabled ? (
          <MediaInfoOverlay lines={mediaInfoOverlayLines} sidebarOpen={sidebar.sidebarOpen} />
        ) : null}

        {/* 侧边栏导航 */}
        <ReaderSidebar
          open={sidebar.sidebarOpen}
          allPages={pages}
          sidebarScrollRef={sidebar.sidebarScrollRef}
          sidebarLoading={sidebar.sidebarLoading}
          isEpub={sidebar.isEpub}
          sidebarDisplayPages={sidebar.sidebarDisplayPages}
          currentPage={readingMode === 'webtoon' ? currentRealPage : currentPage}
          pagesLength={pages.length}
          canLoadMore={sidebar.sidebarLoadedCount < pages.length}
          onSelectPage={sidebar.handleSidebarPageSelect}
          onLoadMore={sidebar.handleLoadMoreSidebarPages}
          onOpenChange={sidebar.setSidebarOpen}
          t={t}
        />

        {/* 单页模式 */}
 	        <ReaderSingleModeView
 	          enabled={readingMode !== 'webtoon' && !isCollectionEndPage}
 	          sidebarOpen={sidebar.sidebarOpen}
            readerAreaRef={readerAreaRef}
            tapTurnPageEnabled={tapTurnPageEnabled}
            longPageEnabled={longPageEnabled}
 	          pages={pages}
 	          cachedPages={imageLoading.cachedPages}
 	          currentPage={currentPage}
 	          doublePageMode={doublePageMode}
	          splitCoverMode={splitCoverMode}
	          imagesLoading={imageLoading.imagesLoading}
	          loadedImages={imageLoading.loadedImages}
	          scale={scale}
	          translateX={translateX}
	          translateY={translateY}
	          htmlContents={htmlContents}
          imageRefs={imageRefs}
          videoRefs={videoRefs}
	          htmlContainerRefs={htmlContainerRefs}
	          imageRequestUrls={imageRequestUrls}
	          onImageLoaded={imageLoading.handleImageLoad}
	          onImageError={imageLoading.handleImageError}
	          onCacheImage={imageLoading.cacheImage}
	          onDoubleClick={handleDoubleClick}
	          onImageDragStart={handleImageDragStart}
	          t={t}
	        />

          <ReaderCollectionEndPage
            enabled={isCollectionEndPage && readingMode !== 'webtoon'}
            finishedId={activeArchiveId}
            finishedTitle={displayArchiveTitle}
            finishedCoverAssetId={getArchiveAssetId(archive.archiveMetadata, 'cover')}
            nextId={nextArchive?.id ?? null}
            nextTitle={nextArchive?.title ?? null}
            nextCoverAssetId={nextArchive?.coverAssetId}
            nextMode={endPageIsRandomNext ? 'random' : 'chapter'}
            t={t}
          />

        {/* 隐藏的预加载区域：前1页和后5页（仅单页/双页模式） */}
	        <ReaderPreloadArea
	          enabled={readingMode !== 'webtoon' && !isCollectionEndPage}
	          imagesLoading={imageLoading.imagesLoading}
	          currentPage={currentPage}
	          doublePageMode={doublePageMode}
	          pages={pages}
	          cachedPages={imageLoading.cachedPages}
	          onLoaded={imageLoading.handleImageLoad}
	          onError={imageLoading.handleImageError}
	          onCacheImage={imageLoading.cacheImage}
	        />

        {/* 条漫模式 */}
	        <ReaderWebtoonModeView
	          enabled={readingMode === 'webtoon'}
	          webtoonContainerRef={webtoonContainerRef}
	          sidebarOpen={sidebar.sidebarOpen}
	          onScroll={handleWebtoonScroll}
	          pages={streamPages}
	          finishedId={activeArchiveId}
	          finishedTitle={displayArchiveTitle}
	          finishedCoverAssetId={getArchiveAssetId(archive.archiveMetadata, 'cover')}
	          nextId={nextArchive?.id ?? null}
	          nextTitle={nextArchive?.title ?? null}
	          nextCoverAssetId={nextArchive?.coverAssetId}
	          nextMode={endPageIsRandomNext ? 'random' : 'chapter'}
	          cachedPages={imageLoading.cachedPages}
	          visibleRange={webtoonVirtualization.visibleRange}
	          imageHeights={webtoonVirtualization.imageHeights}
	          containerHeight={webtoonVirtualization.containerHeight}
	          prefixHeights={webtoonVirtualization.prefixHeights}
	          totalHeight={webtoonVirtualization.totalHeight}
	          imagesLoading={imageLoading.imagesLoading}
	          loadedImages={imageLoading.loadedImages}
	          scale={scale}
	          translateX={translateX}
	          translateY={translateY}
	          htmlContents={htmlContents}
          webtoonPageElementRefs={webtoonPageElementRefs}
          imageRefs={imageRefs}
	          videoRefs={videoRefs}
	          htmlContainerRefs={htmlContainerRefs}
	          imageRequestUrls={imageRequestUrls}
            onMeasureImageHeight={handleMeasureWebtoonImageHeight}
	          onImageLoaded={imageLoading.handleImageLoad}
	          onImageError={imageLoading.handleImageError}
	          onCacheImage={imageLoading.cacheImage}
	          onDoubleClick={handleDoubleClick}
	          onImageDragStart={handleImageDragStart}
	          t={t}
	        />
      </div>
    </div>
  );
}

export default function ReaderPage() {
  return (
    <Suspense fallback={
      <div className="min-h-screen bg-background text-foreground flex items-center justify-center">
        <div className="text-center">
          <p className="text-lg">Loading...</p>
        </div>
      </div>
    }>
      <ReaderContent />
    </Suspense>
  );
}
