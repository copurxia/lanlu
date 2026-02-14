'use client';

import { useSearchParams, useRouter } from 'next/navigation';
import { useState, useEffect, useCallback, useMemo, Suspense, useRef } from 'react';
import type React from 'react';
import { ArchiveService, PageInfo } from '@/lib/services/archive-service';
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
import { getHtmlSpreadMetrics, getHtmlSpreadSlotOffset } from '@/components/reader/utils/html-spread';
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
  MousePointerClick
} from 'lucide-react';
import Link from 'next/link';
import { TankoubonService } from '@/lib/services/tankoubon-service';
import type { Tankoubon } from '@/types/tankoubon';
import { toast } from 'sonner';
import { getStoredPath } from '@/lib/utils/navigation';

function ReaderContent() {
  const router = useRouter();
  const searchParams = useSearchParams();
  const id = searchParams?.get('id') ?? null;
  const pageParam = searchParams?.get('page');
  const { t, language } = useLanguage();
  
  const [pages, setPages] = useState<PageInfo[]>([]);
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
  const urlSyncTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const pendingWebtoonScrollToIndexRef = useRef<number | null>(null);
  const pendingWebtoonScrollToEdgeRef = useRef<'top' | 'bottom' | null>(null);

  const [settingsOpen, setSettingsOpen] = useState(false);
  const [tankoubonContext, setTankoubonContext] = useState<Tankoubon | null>(null);
  const [prevArchiveId, setPrevArchiveId] = useState<string | null>(null);
  const [nextArchive, setNextArchive] = useState<{ id: string; title: string; coverAssetId?: number } | null>(null);
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

    if (id) {
      router.push(`/archive?id=${id}`);
      return;
    }

    router.push('/');
  }, [id, router]);

  const handleNavigateToArchiveFromSettings = useCallback(() => {
    if (!id) return;
    setSettingsOpen(false);
    router.push(`/archive?id=${id}`);
  }, [id, router]);

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
    if (!nextArchive?.id) return;
    pushReader(nextArchive.id, 1);
  }, [nextArchive?.id, pushReader]);

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
  const videoRefs = useRef<(HTMLVideoElement | null)[]>([]);
  const htmlContainerRefs = useRef<(HTMLDivElement | null)[]>([]);
  const imageRequestUrls = useRef<(string | null)[]>([]);
  const [mediaInfoTick, setMediaInfoTick] = useState(0);
  const archive = useReaderArchiveMetadata({ id, language });
  const { htmlContents, loadHtmlPage } = useReaderHtmlPages({ id, pages, onError: setError });

  // 用于跟踪拆分封面模式的变化，避免无限循环
  const splitCoverModeRef = useRef(splitCoverMode);

  const toolbar = useReaderToolbarAutoHide({ autoHideEnabled, delayMs: 3000 });

  const collectionEndPageEnabled = useMemo(() => {
    return Boolean(tankoubonContext);
  }, [tankoubonContext]);

  const currentPageType = pages[currentPage]?.type ?? null;
  const isCurrentHtmlPage = currentPageType === 'html';
  const isCurrentOrTailHtmlPage =
    isCurrentHtmlPage ||
    (currentPage >= pages.length && pages.length > 0 && pages[pages.length - 1]?.type === 'html');
  const isHtmlSpreadView = readingMode !== 'webtoon' && doublePageMode && isCurrentHtmlPage;

  const totalPages = useMemo(() => {
    if (readingMode === 'webtoon') return pages.length + (collectionEndPageEnabled ? 1 : 0);
    return pages.length + (collectionEndPageEnabled ? 1 : 0);
  }, [collectionEndPageEnabled, pages.length, readingMode]);

  const isCollectionEndPage = useMemo(() => {
    return collectionEndPageEnabled && currentPage === pages.length;
  }, [collectionEndPageEnabled, currentPage, pages.length]);

  const webtoonVirtualization = useReaderWebtoonVirtualization({
    readingMode,
    pages,
    currentPage,
    setCurrentPage,
    virtualLength: readingMode === 'webtoon' ? totalPages : pages.length,
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

  // Stable reference: avoid re-running effects on every render (can cause update loops).
  const priorityIndices = useMemo(() => {
    if (
      readingMode !== 'webtoon' &&
      doublePageMode &&
      !isCurrentHtmlPage &&
      !(splitCoverMode && currentPage === 0) &&
      currentPage + 1 < pages.length
    ) {
      return [currentPage, currentPage + 1];
    }
    return [currentPage];
  }, [currentPage, doublePageMode, isCurrentHtmlPage, pages.length, readingMode, splitCoverMode]);

  const imageLoading = useReaderImageLoading({
    pages,
    readingMode,
    currentPage,
    priorityIndices,
    visibleRange: webtoonVirtualization.visibleRange,
    imageRefs,
  });
  const { setImagesLoading } = imageLoading;

  useEffect(() => {
    async function fetchPages() {
      if (!id) {
        setError('Missing archive ID');
        setLoading(false);
        return;
      }

      setLoading(true);
      setError(null);
      appliedVirtualFromUrlForIdRef.current = null;

      try {
        const data = await ArchiveService.getFiles(id);

        // 计算初始页码
        let initialPage: number;

        // URL的page参数优先级最高（1-based，包含后续虚拟页；此处先按“真实页面”初始化，虚拟页在合集信息就绪后再补齐）
        const pageParamSnapshot = searchParams?.get('page');
        if (pageParamSnapshot) {
          const urlPage = parseInt(pageParamSnapshot, 10);
          if (!isNaN(urlPage) && urlPage > 0) {
            pendingUrlPageRawRef.current = urlPage;
            pendingUrlPageIndexRef.current = urlPage - 1;
            if (urlPage - 1 >= 0 && urlPage - 1 < data.pages.length) {
              initialPage = urlPage - 1;
            } else {
              initialPage = Math.max(0, data.pages.length - 1);
              // For webtoon, an out-of-range page is treated as "jump to end".
              pendingWebtoonScrollToEdgeRef.current = 'bottom';
            }
          } else {
            pendingUrlPageRawRef.current = null;
            pendingUrlPageIndexRef.current = null;
            initialPage = 0;
          }
        } else if (data.progress > 0 && data.progress < data.pages.length) {
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
        const initialPageIsHtml = data.pages[initialPage]?.type === 'html';
          
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
        setPages(data.pages);
        setCurrentPage(initialPage);
        if (readingMode === 'webtoon') {
          pendingWebtoonScrollToIndexRef.current = initialPage;
          if (!pendingWebtoonScrollToEdgeRef.current && initialPage <= 0) {
            pendingWebtoonScrollToEdgeRef.current = 'top';
          }
        }

        // 如果有进度且需要预加载图片，添加到加载队列（跳过 HTML 页，HTML 由 useReaderHtmlPages 加载）
        if (initialPage > 0 && data.pages[initialPage]?.type !== 'html') {
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
  }, [id, setImagesLoading]);

  useEffect(() => {
    currentPageRef.current = currentPage;
  }, [currentPage]);

  // When an archive belongs to a tankoubon, compute prev/next archives for "chapter" navigation.
  useEffect(() => {
    if (!id) {
      setTankoubonContext(null);
      setPrevArchiveId(null);
      setNextArchive(null);
      return;
    }

    let cancelled = false;
    (async () => {
      try {
        const tanks = await TankoubonService.getTankoubonsForArchive(id);
        if (cancelled) return;

        if (!tanks || tanks.length === 0) {
          setTankoubonContext(null);
          setPrevArchiveId(null);
          setNextArchive(null);
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

        const idx = chosen.archives?.indexOf(id) ?? -1;
        const prevId = idx > 0 ? chosen.archives?.[idx - 1] : undefined;
        setPrevArchiveId(prevId ?? null);
        const nextId = idx >= 0 ? chosen.archives?.[idx + 1] : undefined;
        if (!nextId) {
          setNextArchive(null);
          return;
        }

        try {
          const meta = await ArchiveService.getMetadata(nextId, language);
          if (cancelled) return;
          const nextTitle = (meta.title && meta.title.trim()) ? meta.title : meta.filename || nextId;
          setNextArchive({ id: nextId, title: nextTitle, coverAssetId: meta.cover_asset_id });
        } catch (metaErr) {
          logger.apiError('fetch next archive metadata', metaErr);
          if (cancelled) return;
          setNextArchive({ id: nextId, title: nextId });
        }
      } catch (err) {
        logger.apiError('fetch tankoubons for archive', err);
        if (cancelled) return;
        setTankoubonContext(null);
        setPrevArchiveId(null);
        setNextArchive(null);
      }
    })();

    return () => {
      cancelled = true;
    };
  }, [id, language]);

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
    ]
  );

  useEffect(() => {
    if (!mediaInfoEnabled) return;
    const interval = window.setInterval(() => setMediaInfoTick((prev) => prev + 1), 250);
    return () => window.clearInterval(interval);
  }, [mediaInfoEnabled]);

  useReaderProgressTracking({
    id,
    currentPage,
    pagesLength: pages.length,
    doublePageMode,
    splitCoverMode,
    isCurrentHtmlPage: isCurrentOrTailHtmlPage,
  });

  // Apply URL `page` -> state. This runs for all modes (including webtoon and the synthetic "end" page).
  // IMPORTANT: Do NOT refetch pages when only `page` changes; otherwise every flip causes flicker.
  useEffect(() => {
    if (!id) return;
    if (!pageParam) return;
    if (totalPages <= 0) return;
    const urlPage = parseInt(pageParam, 10);
    if (isNaN(urlPage) || urlPage <= 0) return;

    const desiredIndex = Math.max(0, Math.min(urlPage - 1, totalPages - 1));
    if (desiredIndex === currentPageRef.current) return;

    setCurrentPage(desiredIndex);
    setScale(1);
    setTranslateX(0);
    setTranslateY(0);

    if (readingMode === 'webtoon') {
      pendingWebtoonScrollToIndexRef.current = desiredIndex;
      pendingWebtoonScrollToEdgeRef.current =
        desiredIndex <= 0 ? 'top' : desiredIndex >= totalPages - 1 ? 'bottom' : null;
    }
  }, [id, pageParam, readingMode, totalPages]);

  // Sync state -> URL `page` for all modes (including virtual page). Debounced to avoid rapid-flip flicker.
  useEffect(() => {
    if (!id) return;
    if (totalPages <= 0) return;
    if (currentPage < 0 || currentPage >= totalPages) return;

    if (urlSyncTimerRef.current) clearTimeout(urlSyncTimerRef.current);
    urlSyncTimerRef.current = setTimeout(() => {
      const desiredPage = String(currentPage + 1);
      const currentUrlPage = searchParams?.get('page') ?? null;
      const currentUrlId = searchParams?.get('id') ?? null;
      if (currentUrlId === id && currentUrlPage === desiredPage) return;

      const params = new URLSearchParams(searchParams?.toString() || '');
      params.set('id', id);
      params.set('page', desiredPage);
      router.replace(`/reader?${params.toString()}`, { scroll: false });
    }, 120);

    return () => {
      if (urlSyncTimerRef.current) clearTimeout(urlSyncTimerRef.current);
    };
  }, [currentPage, id, router, searchParams, totalPages]);

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
    if (!id || pages.length === 0) return;

    if (readingMode === 'webtoon') {
      for (let i = webtoonVirtualization.visibleRange.start; i <= webtoonVirtualization.visibleRange.end; i += 1) {
        if (pages[i]?.type === 'html') {
          void loadHtmlPage(i);
        }
      }
      return;
    }

    if (currentPage >= 0 && currentPage < pages.length && pages[currentPage]?.type === 'html') {
      void loadHtmlPage(currentPage);
    }
  }, [id, pages, currentPage, readingMode, webtoonVirtualization.visibleRange, loadHtmlPage]);

  // 重置变换
  const resetTransform = useCallback(() => {
    setScale(1);
    setTranslateX(0);
    setTranslateY(0);
  }, []);

  const sidebar = useReaderSidebar({
    pages,
    currentPage,
    loadedImages: imageLoading.loadedImages,
    imagesLoading: imageLoading.imagesLoading,
    onSelectPage: (pageIndex) => setCurrentPage(pageIndex),
    resetTransform,
  });

  const mediaInfoOverlayLines = useMediaInfoOverlayLines({
    enabled: mediaInfoEnabled,
    tick: mediaInfoTick,
    pages,
    currentPage,
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
    visibleRange: webtoonVirtualization.visibleRange,
    imageRefs,
    videoRefs,
    htmlContainerRefs,
    imageRequestUrls,
  });

  const handleSliderChangePage = useCallback(
    (newPage: number) => {
      setCurrentPage(newPage);
      resetTransform();

      if (readingMode === 'webtoon' && webtoonContainerRef.current) {
        let accumulatedHeight = 0;
        for (let i = 0; i < newPage; i++) {
          const imageHeight =
            webtoonVirtualization.imageHeights[i] ||
            webtoonVirtualization.containerHeight ||
            window.innerHeight * 0.7;
          accumulatedHeight += imageHeight;
        }
        webtoonContainerRef.current.scrollTop = accumulatedHeight;
      }
    },
    [resetTransform, readingMode, webtoonVirtualization.containerHeight, webtoonVirtualization.imageHeights]
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
      // 放大到2倍
      setScale(2);
      
      // 在双页模式下，使用整个容器来计算位置
      let rect: DOMRect;
      if (doublePageMode) {
        // 获取包含两张图片的容器
        const containerElement = (e.currentTarget as HTMLImageElement).closest('.flex.items-center.justify-center') as HTMLElement;
        rect = containerElement.getBoundingClientRect();
      } else {
        // 单页模式，使用图片元素
        const imgElement = e.currentTarget as HTMLImageElement;
        rect = imgElement.getBoundingClientRect();
      }
      
      // 计算点击位置相对于元素中心的偏移
      const x = e.clientX - rect.left - rect.width / 2;
      const y = e.clientY - rect.top - rect.height / 2;
      
      // 计算放大后的位移，并添加边界检查
      const scaledWidth = rect.width * 2;
      const scaledHeight = rect.height * 2;
      const viewportWidth = window.innerWidth;
      const viewportHeight = window.innerHeight;
      
      // 计算最大允许的位移，确保放大后的内容不会完全超出屏幕
      const maxTranslateX = Math.max(0, (scaledWidth - viewportWidth) / 2);
      const maxTranslateY = Math.max(0, (scaledHeight - viewportHeight) / 2);
      
      // 限制位移范围
      const limitedTranslateX = Math.max(-maxTranslateX, Math.min(maxTranslateX, -x * 2));
      const limitedTranslateY = Math.max(-maxTranslateY, Math.min(maxTranslateY, -y * 2));
      
      setTranslateX(limitedTranslateX);
      setTranslateY(limitedTranslateY);
    } else {
      // 重置缩放
      resetTransform();
    }
  }, [doubleTapZoom, tapTurnPageEnabled, scale, resetTransform, doublePageMode]);

  // 处理图片拖拽开始
  const handleImageDragStart = useCallback((e: React.DragEvent) => {
    e.preventDefault();
  }, []);

  const tryTurnHtmlSpread = useCallback(
    (direction: 'prev' | 'next') => {
      if (!isHtmlSpreadView) return false;

      const container = htmlContainerRefs.current[currentPage];
      if (!container) return false;

      const metrics = getHtmlSpreadMetrics(container);
      if (metrics.maxScrollLeft <= 1) return false;

      if (direction === 'next') {
        if (metrics.currentSlot >= metrics.maxSlot) return false;
        const targetSlot = Math.min(metrics.maxSlot, metrics.currentSlot + 1);
        const target = getHtmlSpreadSlotOffset(metrics.maxScrollLeft, metrics.step, targetSlot);
        container.scrollTo({ left: target, behavior: 'auto' });
        return true;
      }

      if (metrics.currentSlot <= 0) return false;
      const targetSlot = Math.max(0, metrics.currentSlot - 1);
      const target = getHtmlSpreadSlotOffset(metrics.maxScrollLeft, metrics.step, targetSlot);
      container.scrollTo({ left: target, behavior: 'auto' });
      return true;
    },
    [currentPage, htmlContainerRefs, isHtmlSpreadView]
  );

  const handlePrevPage = useCallback(() => {
    if (isCollectionEndPage) {
      // From the synthetic "end" page, go back to the last real page.
      if (pages.length <= 0) return;

      let target = pages.length - 1;
      if (doublePageMode && pages[pages.length - 1]?.type !== 'html') {
        if (splitCoverMode) {
          // split-cover spreads start at 1: (1,2), (3,4)...
          // When pages.length is odd, the last page is part of a spread starting at pages.length - 2.
          if (pages.length % 2 === 1 && pages.length >= 2) target = pages.length - 2;
        } else {
          // Normal spreads start at 0: (0,1), (2,3)...
          // When pages.length is even, the last page is part of a spread starting at pages.length - 2.
          if (pages.length % 2 === 0 && pages.length >= 2) target = pages.length - 2;
        }
      }

      setCurrentPage(Math.max(0, target));
      resetTransform();
      return;
    }

    if (tryTurnHtmlSpread('prev')) return;

    // Collection: from the first page, flipping "prev" goes to previous chapter end (like HTML chapter navigation).
    if (currentPage <= 0 && collectionEndPageEnabled && prevArchiveId) {
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
    collectionEndPageEnabled,
    currentPage,
    isCollectionEndPage,
    requestChapterJump,
    navigateToPrevArchiveEnd,
    pages.length,
    prevArchiveId,
    resetTransform,
    doublePageMode,
    isHtmlSpreadView,
    splitCoverMode,
    tryTurnHtmlSpread,
  ]);

  const handleNextPage = useCallback(() => {
    if (isCollectionEndPage) {
      // Continue flipping from the synthetic "end" page to the next archive.
      requestChapterJump('next', navigateToNextArchiveStart);
      return;
    }

    if (tryTurnHtmlSpread('next')) return;

    // When in a collection (tankoubon), append a synthetic end page after the last real page.
    if (collectionEndPageEnabled && pages.length > 0) {
      const viewShowsTwoPages =
        !isHtmlSpreadView &&
        doublePageMode &&
        !(splitCoverMode && currentPage === 0) &&
        currentPage + 1 < pages.length;
      const viewIncludesLastPage =
        currentPage === pages.length - 1 ||
        (viewShowsTwoPages && currentPage + 1 === pages.length - 1);

      if (viewIncludesLastPage) {
        setCurrentPage(pages.length);
        resetTransform();
        return;
      }
    }

    if (currentPage < pages.length - 1) {
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
          setCurrentPage(Math.min(nextPage, pages.length - 1));
        }
      } else if (doublePageMode) {
        // 普通双页模式
        if (currentPage + 2 < pages.length) {
          setCurrentPage(currentPage + 2);
        } else {
          setCurrentPage(pages.length - 1);
        }
      } else {
        // 单页模式，一次翻一页
        setCurrentPage(currentPage + 1);
      }
      resetTransform();
    }
  }, [
    collectionEndPageEnabled,
    currentPage,
    isCollectionEndPage,
    pages.length,
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
    onWebtoonStartPrev: collectionEndPageEnabled ? () => requestChapterJump('prev', navigateToPrevArchiveEnd) : undefined,
    onWebtoonEndNext: collectionEndPageEnabled ? () => requestChapterJump('next', navigateToNextArchiveStart) : undefined,
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
    isCollectionEndPage,
    onWebtoonStartPrev: collectionEndPageEnabled ? () => requestChapterJump('prev', navigateToPrevArchiveEnd) : undefined,
    onWebtoonEndNext: collectionEndPageEnabled ? () => requestChapterJump('next', navigateToNextArchiveStart) : undefined,
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
          <Link href={`/archive?id=${id}`}>
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
	        archiveTitle={archive.archiveTitle}
	        onBack={handleBack}
	        onToggleSidebar={() => sidebar.setSidebarOpen((prev) => !prev)}
	        onToggleReadingMode={toggleReadingMode}
	        readingModeIcon={getReadingModeIcon()}
	        readingModeText={getReadingModeText()}
	        t={t}
	      />

	      <ReaderFloatingControls
	        showToolbar={toolbar.showToolbar}
	        currentPage={currentPage}
	        totalPages={totalPages}
	        onChangePage={handleSliderChangePage}
	        settingsOpen={settingsOpen}
	        onSettingsOpenChange={setSettingsOpen}
	        archiveTitle={archive.archiveTitle}
	        archiveMetadata={archive.archiveMetadata}
	        metadataTags={archive.metadataTags}
	        id={id}
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
          sidebarScrollRef={sidebar.sidebarScrollRef}
          sidebarLoading={sidebar.sidebarLoading}
          isEpub={sidebar.isEpub}
          sidebarDisplayPages={sidebar.sidebarDisplayPages}
          currentPage={currentPage}
          sidebarImagesLoading={sidebar.sidebarImagesLoading}
          pagesLength={pages.length}
          canLoadMore={sidebar.sidebarLoadedCount < pages.length}
          onSelectPage={sidebar.handleSidebarPageSelect}
          onLoadMore={sidebar.handleLoadMoreSidebarPages}
          onThumbLoaded={sidebar.handleSidebarThumbLoaded}
          onThumbError={sidebar.handleSidebarThumbError}
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
            finishedId={id}
            finishedTitle={archive.archiveTitle}
            finishedCoverAssetId={archive.archiveMetadata?.cover_asset_id}
            nextId={nextArchive?.id ?? null}
            nextTitle={nextArchive?.title ?? null}
            nextCoverAssetId={nextArchive?.coverAssetId}
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
	          onScroll={webtoonVirtualization.handleWebtoonScroll}
	          pages={pages}
	          virtualLength={totalPages}
	          collectionEndPageEnabled={collectionEndPageEnabled}
	          finishedId={id}
	          finishedTitle={archive.archiveTitle}
	          finishedCoverAssetId={archive.archiveMetadata?.cover_asset_id}
	          nextId={nextArchive?.id ?? null}
	          nextTitle={nextArchive?.title ?? null}
	          nextCoverAssetId={nextArchive?.coverAssetId}
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
