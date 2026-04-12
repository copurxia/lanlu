'use client';

import { useSearchParams, useRouter } from 'next/navigation';
import { useState, useEffect, useCallback, useMemo, Suspense, useRef } from 'react';
import type React from 'react';
import dynamic from 'next/dynamic';
import { ArchiveService } from '@/lib/services/archive-service';
import { RecommendationService } from '@/lib/services/recommendation-service';
import type { Archive } from '@/types/archive';
import { Button } from '@/components/ui/button';
import { Spinner } from '@/components/ui/spinner';
import { useLanguage } from '@/contexts/LanguageContext';
import { MediaInfoOverlay } from '@/components/reader/components/MediaInfoOverlay';
import { ReaderFloatingControls } from '@/components/reader/components/ReaderFloatingControls';
import type { ReaderProgressLane } from '@/components/reader/components/ReaderFloatingControls';
import { ReaderSingleModeView } from '@/components/reader/components/ReaderSingleModeView';
import { ReaderTopBar } from '@/components/reader/components/ReaderTopBar';
import { useReaderArchiveMetadata } from '@/components/reader/hooks/useReaderArchiveMetadata';
import { useReaderHtmlPages } from '@/components/reader/hooks/useReaderHtmlPages';
import { useReaderKeyboardNavigation } from '@/components/reader/hooks/useReaderKeyboardNavigation';
import { useMediaInfoOverlayLines } from '@/components/reader/hooks/useMediaInfoOverlayLines';
import { useReaderProgressTracking } from '@/components/reader/hooks/useReaderProgressTracking';
import { getTapTurnAction, useReaderInteractionHandlers } from '@/components/reader/hooks/useReaderInteractionHandlers';
import { useReaderAutoPlay } from '@/components/reader/hooks/useReaderAutoPlay';
import { useReaderVideoAutoNext } from '@/components/reader/hooks/useReaderVideoAutoNext';
import { useReaderImageLoading } from '@/components/reader/hooks/useReaderImageLoading';
import { useReaderSidebar } from '@/components/reader/hooks/useReaderSidebar';
import { useReaderToolbarAutoHide } from '@/components/reader/hooks/useReaderToolbarAutoHide';
import { useReaderWebtoonVirtualization } from '@/components/reader/hooks/useReaderWebtoonVirtualization';
import { useReaderWheelNavigation } from '@/components/reader/hooks/useReaderWheelNavigation';
import { stepHtmlSpread } from '@/components/reader/utils/html-spread';
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
  Film,
  Clapperboard,
  Music2,
} from 'lucide-react';
import Link from 'next/link';
import { TankoubonService } from '@/lib/services/tankoubon-service';
import type { Tankoubon } from '@/types/tankoubon';
import { toast } from '@/lib/ui/feedback';
import { getStoredPath } from '@/lib/utils/navigation';
import { getArchiveAssetId } from '@/lib/utils/archive-assets';
import { logger } from '@/lib/utils/logger';
import { buildReaderStream } from '@/features/reader/application/use-cases/build-reader-stream';
import { computeReaderAdjacentPage } from '@/features/reader/application/use-cases/compute-reader-adjacent-page';
import { deriveReaderPosition } from '@/features/reader/application/use-cases/derive-reader-position';
import { buildReaderProgressLaneSpecs } from '@/features/reader/application/use-cases/build-reader-progress-lane-specs';
import { mapPageDtosToReaderPageItems } from '@/features/reader/domain/mappers/page-dto-mapper';
import { computeCollectionEndNextAction, computeCollectionEndReturnRealPage, computePrevBoundaryAction } from '@/features/reader/application/use-cases/compute-reader-boundary-navigation';
import { useReaderSourceSession } from '@/features/reader/presentation/hooks/useReaderSourceSession';
import type { MetadataPageAttachment } from '@/types/archive';

const ReaderSidebar = dynamic(
  () => import('@/components/reader/components/ReaderSidebar').then((m) => m.ReaderSidebar)
);
const ReaderCollectionEndPage = dynamic(
  () => import('@/components/reader/components/ReaderCollectionEndPage').then((m) => m.ReaderCollectionEndPage)
);
const ReaderPreloadArea = dynamic(
  () => import('@/components/reader/components/ReaderPreloadArea').then((m) => m.ReaderPreloadArea)
);
const ReaderWebtoonModeView = dynamic(
  () => import('@/components/reader/components/ReaderWebtoonModeView').then((m) => m.ReaderWebtoonModeView)
);

function formatVideoClock(seconds: number): string {
  const safe = Number.isFinite(seconds) && seconds > 0 ? Math.floor(seconds) : 0;
  const h = Math.floor(safe / 3600);
  const m = Math.floor((safe % 3600) / 60);
  const s = safe % 60;
  if (h > 0) {
    return `${h}:${String(m).padStart(2, '0')}:${String(s).padStart(2, '0')}`;
  }
  return `${m}:${String(s).padStart(2, '0')}`;
}

function getPageHeaderTitle(page?: { title?: string; metadata?: { title?: string } } | null): string {
  if (!page) return '';
  return ArchiveService.getPageDisplayTitle(page as any);
}

function getPagePathFileName(path?: string | null): string {
  const normalized = String(path || '').trim().replace(/\\/g, '/');
  if (!normalized) return '';
  const segments = normalized.split('/');
  return segments[segments.length - 1] || normalized;
}

function computeCommonPrefixLength(values: string[]): number {
  if (values.length <= 1) return 0;
  const first = values[0] || '';
  let index = 0;
  while (index < first.length) {
    const ch = first[index];
    if (values.some((value) => index >= value.length || value[index] !== ch)) break;
    index += 1;
  }
  return index;
}

function computeCommonSuffixLength(values: string[], prefixLength: number): number {
  if (values.length <= 1) return 0;
  const first = values[0] || '';
  let offset = 0;
  while (offset < first.length - prefixLength) {
    const firstIndex = first.length - 1 - offset;
    const ch = first[firstIndex];
    if (
      values.some((value) => {
        const valueIndex = value.length - 1 - offset;
        return valueIndex < prefixLength || valueIndex < 0 || value[valueIndex] !== ch;
      })
    ) {
      break;
    }
    offset += 1;
  }
  return offset;
}

function buildSourceOptionLabels(
  page: {
    sources?: Array<{ title?: string; path: string }>;
  }
): string[] {
  const fileNames = (page.sources || []).map((source, sourceIndex) => {
    return getPagePathFileName(source.path) || String(source.title || '').trim() || `Source ${sourceIndex + 1}`;
  });
  if (fileNames.length <= 1) return fileNames;

  const prefixLength = computeCommonPrefixLength(fileNames);
  const suffixLength = computeCommonSuffixLength(fileNames, prefixLength);
  const candidateLabels = fileNames.map((fileName, sourceIndex) => {
    const endIndex = Math.max(prefixLength, fileName.length - suffixLength);
    const diff = fileName.slice(prefixLength, endIndex).trim().replace(/^[\s._-]+|[\s._-]+$/g, '');
    return diff || fileName || `Source ${sourceIndex + 1}`;
  });

  const uniqueCount = new Set(candidateLabels).size;
  const tooShort = candidateLabels.some((label) => label.length < 2);
  if (uniqueCount !== candidateLabels.length || tooShort) {
    return fileNames;
  }
  return candidateLabels;
}

function buildSubtitleOptionLabel(attachment: MetadataPageAttachment, subtitleIndex: number): string {
  const language = String(attachment.language || '').trim();
  const kind = String(attachment.kind || '').trim().toLowerCase();
  const name = String(attachment.name || '').trim();
  if (language && kind) return `${language} · ${kind}`;
  if (language) return language;
  if (name && kind && !name.toLowerCase().endsWith(`.${kind}`)) return `${name} · ${kind}`;
  if (name) return name;
  if (kind) return kind;
  return `Subtitle ${subtitleIndex + 1}`;
}

function buildSubtitleSourceKey(pageIndex: number, sourceIndex: number): string {
  return `${pageIndex}:${sourceIndex}`;
}

function resolvePageWithSource<
  T extends {
    type: 'image' | 'video' | 'audio' | 'html';
    title?: string;
    metadata?: {
      title?: string;
      description?: string;
      thumb_asset_id?: number;
      thumb?: string;
      attachments?: MetadataPageAttachment[];
      release_at?: string;
    };
    defaultSource?: {
      id: string;
      path: string;
      url: string;
      type: 'image' | 'video' | 'audio' | 'html';
      title?: string;
      metadata?: {
        title?: string;
        description?: string;
        thumb_asset_id?: number;
        thumb?: string;
        attachments?: MetadataPageAttachment[];
        release_at?: string;
      };
    };
    sources?: Array<{
      id: string;
      path: string;
      url: string;
      type: 'image' | 'video' | 'audio' | 'html';
      title?: string;
      metadata?: {
        title?: string;
        description?: string;
        thumb_asset_id?: number;
        thumb?: string;
        attachments?: MetadataPageAttachment[];
        release_at?: string;
      };
    }>;
  }
>(page: T, sourceIndex?: number): T & {
  path: string;
  url: string;
  effectiveType: 'image' | 'video' | 'audio' | 'html';
  effectiveTitle?: string;
  effectiveMetadata?: T['metadata'];
} {
  const source = ArchiveService.getPageSource(page as any, sourceIndex);
  return {
    ...page,
    path: source?.path || '',
    url: source?.url || '',
    effectiveType: source?.type || page.type,
    effectiveTitle: source?.title || page.title,
    effectiveMetadata: source?.metadata || page.metadata,
  };
}

function measureElementContentWidth(el: HTMLElement | null): number {
  if (!el) return 0;
  const styles = window.getComputedStyle(el);
  const paddingLeft = Number.parseFloat(styles.paddingLeft || '0');
  const paddingRight = Number.parseFloat(styles.paddingRight || '0');
  return Math.max(0, Math.round(el.clientWidth - paddingLeft - paddingRight));
}

type WebtoonZoomState = {
  pageIndex: number;
  scale: number;
  originX: number;
  originY: number;
};

const WEBTOON_DOUBLE_TAP_SCALE = 1.8;

function ReaderContent() {
  type EndPageNextArchive = {
    id: string;
    title: string;
    coverAssetId?: number;
    source: 'tankoubon' | 'archive_related';
  };

  const router = useRouter();
  const searchParams = useSearchParams();
  const queryArchiveId = searchParams?.get('id') ?? null;
  const pageParam = searchParams?.get('page');
  const { t, language } = useLanguage();
  
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
  const pendingUrlStateApplyRef = useRef<{ archiveId: string; pageIndex: number } | null>(null);
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
  const [expandedProgressLaneId, setExpandedProgressLaneId] = useState<string | null>(null);
  const [currentSourceIndexByPageIndex, setCurrentSourceIndexByPageIndex] = useState<Record<number, number>>({});
  const [currentSubtitleIndexBySourceKey, setCurrentSubtitleIndexBySourceKey] = useState<Record<string, number[]>>({});
  const subtitlePreferenceRef = useRef<{ language: string; name: string } | null>(null);
  const [videoTimelineByPageIndex, setVideoTimelineByPageIndex] = useState<
    Record<number, { currentTime: number; duration: number; paused: boolean; muted: boolean; volume: number; buffered: number }>
  >({});
  const pendingSourceRestoreRef = useRef<Record<number, { currentTime: number; paused: boolean; muted: boolean; volume: number }>>({});
  const [tankoubonContext, setTankoubonContext] = useState<Tankoubon | null>(null);
  const [prevArchiveId, setPrevArchiveId] = useState<string | null>(null);
  const [nextArchiveByArchiveId, setNextArchiveByArchiveId] = useState<Record<string, EndPageNextArchive | null>>({});
  const [webtoonContentElement, setWebtoonContentElement] = useState<HTMLDivElement | null>(null);
  const [webtoonContentWidth, setWebtoonContentWidth] = useState(0);
  const [webtoonZoom, setWebtoonZoom] = useState<WebtoonZoomState | null>(null);
  const archiveNavLockRef = useRef(0);
  const chapterJumpCountdownRef = useRef<{
    seconds: number;
    timerId: ReturnType<typeof setInterval> | null;
    toastId: string | number | null;
  }>({ seconds: 0, timerId: null, toastId: null });

  const getImageHeight = useCallback((naturalWidth: number, naturalHeight: number) => {
    const fallbackWidth = window.innerWidth >= 1024
      ? Math.min(800, window.innerWidth * 0.8)
      : Math.min(window.innerWidth * 0.95, window.innerWidth);
    const containerWidth = webtoonContentWidth > 0 ? webtoonContentWidth : fallbackWidth;
    const aspectRatio = naturalHeight / naturalWidth;
    return containerWidth * aspectRatio;
  }, [webtoonContentWidth]);

  const handleWebtoonContentContainerRef = useCallback((el: HTMLDivElement | null) => {
    setWebtoonContentElement(el);
    setWebtoonContentWidth((prev) => {
      const next = measureElementContentWidth(el);
      return prev === next ? prev : next;
    });
  }, []);

  useEffect(() => {
    if (!webtoonContentElement) return;

    const updateWidth = () => {
      const next = measureElementContentWidth(webtoonContentElement);
      setWebtoonContentWidth((prev) => (prev === next ? prev : next));
    };

    updateWidth();

    if (typeof ResizeObserver === 'undefined') {
      window.addEventListener('resize', updateWidth);
      return () => {
        window.removeEventListener('resize', updateWidth);
      };
    }

    const observer = new ResizeObserver(updateWidth);
    observer.observe(webtoonContentElement);
    return () => {
      observer.disconnect();
    };
  }, [webtoonContentElement]);

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
  const videoRefs = useRef<(HTMLMediaElement | null)[]>([]);
  const htmlContainerRefs = useRef<(HTMLDivElement | null)[]>([]);
  const imageRequestUrls = useRef<(string | null)[]>([]);
  const [mediaInfoTick, setMediaInfoTick] = useState(0);
  const seamlessEnabled = seamlessNextEnabled;
  const seamlessWebtoonEnabled = readingMode === 'webtoon' && seamlessEnabled;

  const {
    sourceArchiveId,
    pages,
    setPages,
    segments,
    setSegments,
    currentPage,
    setCurrentPage,
    loading,
    error,
    setError,
    initialPreloadPage,
  } = useReaderSourceSession({
    queryArchiveId,
    seamlessEnabled,
    readingMode,
    pageParam,
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
  });

  useEffect(() => {
    setCurrentSourceIndexByPageIndex((prev) => {
      let changed = false;
      const next: Record<number, number> = {};
      for (let i = 0; i < pages.length; i += 1) {
        const page = pages[i];
        const sourceCount = page.sources?.length ?? 0;
        if (sourceCount <= 0) {
          if (prev[i] !== undefined) changed = true;
          continue;
        }
        const fallbackIndex = Math.max(0, Math.min(sourceCount - 1, page.defaultSourceIndex ?? 0));
        const existing = prev[i];
        const resolved =
          typeof existing === 'number' && existing >= 0 && existing < sourceCount
            ? existing
            : fallbackIndex;
        next[i] = resolved;
        if (prev[i] !== resolved) changed = true;
      }

      const prevKeys = Object.keys(prev);
      if (!changed && prevKeys.length === Object.keys(next).length) {
        return prev;
      }
      return next;
    });
  }, [pages]);

  const effectivePages = useMemo(
    () => pages.map((page, pageIndex) => resolvePageWithSource(page, currentSourceIndexByPageIndex[pageIndex])),
    [currentSourceIndexByPageIndex, pages]
  );

  const currentSubtitleIndexByPageIndex = useMemo(() => {
    const out: Record<number, number[]> = {};
    for (let i = 0; i < effectivePages.length; i += 1) {
      const sourceIndex = currentSourceIndexByPageIndex[i] ?? effectivePages[i]?.defaultSourceIndex ?? 0;
      const key = buildSubtitleSourceKey(i, sourceIndex);
      out[i] = currentSubtitleIndexBySourceKey[key] ?? [];
    }
    return out;
  }, [currentSourceIndexByPageIndex, currentSubtitleIndexBySourceKey, effectivePages]);

  useEffect(() => {
    setCurrentSubtitleIndexBySourceKey((prev) => {
      let changed = false;
      const next: Record<string, number[]> = {};
      for (let i = 0; i < effectivePages.length; i += 1) {
        const page = effectivePages[i];
        const sourceIndex = currentSourceIndexByPageIndex[i] ?? page?.defaultSourceIndex ?? 0;
        const key = buildSubtitleSourceKey(i, sourceIndex);
        const subtitleAttachments = ArchiveService.getSubtitleAttachments(page.effectiveMetadata || page.metadata);
        const subtitleCount = subtitleAttachments.length;
        const existing = prev[key];
        if (subtitleCount <= 0) {
          if (existing !== undefined) changed = true;
          continue;
        }

        // Filter existing indexes to keep only valid ones
        let resolved = (existing || []).filter((idx) => idx >= 0 && idx < subtitleCount);

        // Auto-select preferred subtitle if none selected
        if (resolved.length === 0 && subtitlePreferenceRef.current) {
          const preferredLanguage = subtitlePreferenceRef.current.language.trim().toLowerCase();
          const preferredName = subtitlePreferenceRef.current.name.trim().toLowerCase();
          const matchedIndex = subtitleAttachments.findIndex((attachment) => {
            const currentLanguage = String(attachment.language || '').trim().toLowerCase();
            const currentName = String(attachment.name || '').trim().toLowerCase();
            return currentLanguage === preferredLanguage && currentName === preferredName;
          });
          if (matchedIndex >= 0) {
            resolved = [matchedIndex];
          }
        }

        next[key] = resolved;
        if (JSON.stringify(prev[key] || []) !== JSON.stringify(resolved)) changed = true;
      }

      const prevKeys = Object.keys(prev);
      if (!changed && prevKeys.length === Object.keys(next).length) {
        return prev;
      }
      return next;
    });
  }, [currentSourceIndexByPageIndex, effectivePages]);


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
        pages: effectivePages,
        segments,
        includeInterChapterVirtualPages: hasInterChapterVirtualPages,
      }),
    [effectivePages, hasInterChapterVirtualPages, segments, sourceArchiveId]
  );
  const effectiveSegments = readerStream.effectiveSegments;
  const streamPages = readerStream.items;
  const streamIndexByRealPage = readerStream.streamIndexByRealPage;
  const streamVirtualIndexBySegment = readerStream.streamVirtualIndexBySegment;
  const virtualPageIndex = readerStream.virtualPageIndex;

  const readerPosition = useMemo(
    () =>
      deriveReaderPosition({
        currentPage,
        pages: effectivePages,
        streamPages,
        effectiveSegments,
        sourceArchiveId,
        readingMode,
        doublePageMode,
        seamlessEnabled,
      }),
    [currentPage, doublePageMode, effectiveSegments, effectivePages, readingMode, seamlessEnabled, sourceArchiveId, streamPages]
  );
  const {
    activeSegment,
    activeArchiveId,
    activeLocalPage,
    currentRealPage,
    nextArchiveLookupId,
    currentPageType,
    isCurrentHtmlPage,
    isCollectionEndPage,
    activeSegmentLastRealPage,
    isCurrentOrTailHtmlPage,
    isHtmlSpreadView,
    sliderCurrentPage,
    sliderTotalPages,
  } = readerPosition;
  const totalPages = streamPages.length;
  const isTailCollectionEndPage = isCollectionEndPage && currentPage === virtualPageIndex;

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

  const archive = useReaderArchiveMetadata({ id: activeArchiveId, language });
  const { htmlContents, loadHtmlPage } = useReaderHtmlPages({ id: sourceArchiveId, pages: effectivePages, onError: setError });

  // 用于跟踪拆分封面模式的变化，避免无限循环
  const splitCoverModeRef = useRef(splitCoverMode);

  const toolbar = useReaderToolbarAutoHide({ autoHideEnabled, delayMs: 3000 });

  const hasTankoubonContext = Boolean(tankoubonContext);
  const nextArchive = nextArchiveLookupId ? (nextArchiveByArchiveId[nextArchiveLookupId] ?? null) : null;
  const endPageIsRelatedNext = nextArchive?.source === 'archive_related';

  const handleOpenRelatedNextDetails = useCallback(() => {
    if (!sourceArchiveId || !nextArchive || nextArchive.source !== 'archive_related') return;

    void RecommendationService.recordInteraction({
      scene: 'archive_related',
      seed_entity_type: 'archive',
      seed_entity_id: sourceArchiveId,
      item_type: 'archive',
      item_id: nextArchive.id,
      interaction_type: 'click',
    }).catch((error) => {
      logger.apiError('track archive related detail click from reader', error);
    });
  }, [nextArchive, sourceArchiveId]);

  const handleOpenRelatedNextReader = useCallback(() => {
    if (!sourceArchiveId || !nextArchive || nextArchive.source !== 'archive_related') return;

    void RecommendationService.recordInteraction({
      scene: 'archive_related',
      seed_entity_type: 'archive',
      seed_entity_id: sourceArchiveId,
      item_type: 'archive',
      item_id: nextArchive.id,
      interaction_type: 'open_reader',
    }).catch((error) => {
      logger.apiError('track archive related open_reader from reader', error);
    });
  }, [nextArchive, sourceArchiveId]);

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
    contentWidth: webtoonContentWidth,
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

  useEffect(() => {
    if (readingMode !== 'webtoon') {
      setWebtoonZoom((prev) => (prev == null ? prev : null));
      return;
    }

    setWebtoonZoom((prev) => {
      if (!prev) return prev;
      const { start, end } = webtoonVirtualization.visibleRange;
      if (prev.pageIndex >= start && prev.pageIndex <= end) return prev;
      return null;
    });
  }, [readingMode, webtoonVirtualization.visibleRange]);

  // Stable reference: avoid re-running effects on every render (can cause update loops).
  const priorityIndices = useMemo(() => {
    if (readingMode === 'webtoon') {
      return [currentRealPage];
    }

    if (
      doublePageMode &&
      !isCurrentHtmlPage &&
      !(splitCoverMode && currentPage === 0) &&
      currentPage + 1 < effectivePages.length
    ) {
      return [currentPage, currentPage + 1];
    }
    return [currentPage];
  }, [currentPage, currentRealPage, doublePageMode, effectivePages.length, isCurrentHtmlPage, readingMode, splitCoverMode]);

  const imageLoading = useReaderImageLoading({
    pages: effectivePages,
    readingMode,
    currentPage: readingMode === 'webtoon' ? currentRealPage : currentPage,
    priorityIndices,
    visibleRange: webtoonVisibleRealRange,
    resetKey: sourceArchiveId,
    imageRefs,
  });
  const { setImagesLoading } = imageLoading;
  useEffect(() => {
    if (initialPreloadPage == null) return;
    setImagesLoading(new Set([initialPreloadPage]));
  }, [initialPreloadPage, setImagesLoading]);

  useEffect(() => {
    currentPageRef.current = currentPage;
  }, [currentPage]);

  useEffect(() => {
    pagesLengthRef.current = effectivePages.length;
  }, [effectivePages.length]);

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
            const aCount = a.children?.length ?? 0;
            const bCount = b.children?.length ?? 0;
            return bCount - aCount;
          })[0];

          const idx = chosen.children?.indexOf(archiveId) ?? -1;
          const nextId = idx >= 0 ? chosen.children?.[idx + 1] : undefined;
          if (nextId && !isExcluded(nextId)) {
            try {
              const meta = await ArchiveService.getMetadata(nextId, language);
              const nextTitle = (meta.title && meta.title.trim()) ? meta.title : meta.filename || '';
              return {
                id: nextId,
                title: nextTitle,
                coverAssetId: getArchiveAssetId(meta, 'cover'),
                source: 'tankoubon',
              };
            } catch (metaErr) {
              logger.apiError('fetch next archive metadata', metaErr);
              return { id: nextId, title: '', source: 'tankoubon' };
            }
          }
        }
      } catch (err) {
        logger.apiError('fetch tankoubons for archive', err);
      }

      let relatedCandidate: Archive | null = null;
      for (let attempt = 0; attempt < 3 && !relatedCandidate; attempt += 1) {
        try {
          const relatedItems = await RecommendationService.getArchiveRelated(archiveId, {
            count: 8,
            lang: language,
          });
          relatedCandidate = relatedItems.find(
            (item) => !isExcluded(item.arcid)
          ) || null;
        } catch (relatedErr) {
          logger.apiError('fetch archive related recommendation for reader', relatedErr);
        }
      }

      if (!relatedCandidate) return null;
      const relatedTitle = (relatedCandidate.title && relatedCandidate.title.trim())
        ? relatedCandidate.title
        : relatedCandidate.filename || relatedCandidate.arcid;
      return {
        id: relatedCandidate.arcid,
        title: relatedTitle,
        coverAssetId: getArchiveAssetId(relatedCandidate, 'cover'),
        source: 'archive_related',
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
  // - For a standalone archive, reuse archive-related recommendations.
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

          const relatedNext = await resolveNextArchiveCandidateCached(
            sourceArchiveId,
            new Set([sourceArchiveId])
          );
          if (cancelled) return;
          setResolvedNextArchive(
            sourceArchiveId,
            relatedNext && relatedNext.source === 'archive_related' ? relatedNext : null
          );
          return;
        }

        // If an archive is in multiple tankoubons, prefer the favorited one (then the larger one).
        const chosen = [...tanks].sort((a, b) => {
          const fav = Number(Boolean(b.isfavorite)) - Number(Boolean(a.isfavorite));
          if (fav !== 0) return fav;
          const aCount = a.children?.length ?? 0;
          const bCount = b.children?.length ?? 0;
          return bCount - aCount;
        })[0];

        setTankoubonContext(chosen);

        const idx = chosen.children?.indexOf(sourceArchiveId) ?? -1;
        const prevId = idx > 0 ? chosen.children?.[idx - 1] : undefined;
        setPrevArchiveId(prevId ?? null);
        const nextId = idx >= 0 ? chosen.children?.[idx + 1] : undefined;
        if (!nextId) {
          setResolvedNextArchive(sourceArchiveId, null);
          return;
        }

        try {
          const meta = await ArchiveService.getMetadata(nextId, language);
          if (cancelled) return;
          const nextTitle = (meta.title && meta.title.trim()) ? meta.title : meta.filename || '';
          setResolvedNextArchive(sourceArchiveId, {
            id: nextId,
            title: nextTitle,
            coverAssetId: getArchiveAssetId(meta, 'cover'),
            source: 'tankoubon',
          });
        } catch (metaErr) {
          logger.apiError('fetch next archive metadata', metaErr);
          if (cancelled) return;
          setResolvedNextArchive(sourceArchiveId, { id: nextId, title: '', source: 'tankoubon' });
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
  }, [activeArchiveId, archive.archiveTitle, setSegments]);

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
          title: '',
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
  }, [
    resolveNextArchiveCandidateCached,
    seamlessEnabled,
    segments,
    setPages,
    setResolvedNextArchive,
    setSegments,
  ]);

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
  }, [error, setError, t]);

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

    pendingUrlStateApplyRef.current = {
      archiveId: urlArchiveId,
      pageIndex: desiredIndex,
    };
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
    setCurrentPage,
    virtualPageIndex,
  ]);

  useEffect(() => {
    const pending = pendingUrlStateApplyRef.current;
    if (!pending) return;

    const currentArchiveId = (seamlessEnabled ? activeArchiveId : sourceArchiveId) ?? sourceArchiveId ?? '';
    if (currentArchiveId != pending.archiveId) return;
    if (currentPage !== pending.pageIndex) return;

    pendingUrlStateApplyRef.current = null;
  }, [activeArchiveId, currentPage, seamlessEnabled, sourceArchiveId]);

  // Sync state -> URL `page` for all modes (including virtual page). Debounced to avoid rapid-flip flicker.
  useEffect(() => {
    if (!sourceArchiveId) return;
    if (totalPages <= 0) return;
    if (currentPage < 0 || currentPage >= totalPages) return;
    if (pendingUrlStateApplyRef.current) return;

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
    if (!sourceArchiveId || effectivePages.length === 0) return;

    if (readingMode === 'webtoon') {
      for (let i = webtoonVirtualization.visibleRange.start; i <= webtoonVirtualization.visibleRange.end; i += 1) {
        const item = streamPages[i];
        if (item?.type === 'html') {
          void loadHtmlPage(item.streamRealPage);
        }
      }
      return;
    }

    if (currentRealPage >= 0 && currentRealPage < effectivePages.length && effectivePages[currentRealPage]?.effectiveType === 'html') {
      void loadHtmlPage(currentRealPage);
    }
  }, [sourceArchiveId, effectivePages, currentRealPage, readingMode, streamPages, webtoonVirtualization.visibleRange, loadHtmlPage]);

  // 重置变换
  const resetTransform = useCallback(() => {
    setScale(1);
    setTranslateX(0);
    setTranslateY(0);
  }, []);

  const handleChangePageSource = useCallback(
    (pageIndex: number, nextSourceIndex: number) => {
      const page = pages[pageIndex];
      const sourceCount = page?.sources?.length ?? 0;
      if (!page || sourceCount <= 1) return;
      const clampedIndex = Math.max(0, Math.min(sourceCount - 1, nextSourceIndex));
      if (currentSourceIndexByPageIndex[pageIndex] === clampedIndex) return;

      const mediaElement = videoRefs.current[pageIndex];
      if (mediaElement) {
        pendingSourceRestoreRef.current[pageIndex] = {
          currentTime: Number.isFinite(mediaElement.currentTime) && mediaElement.currentTime >= 0 ? mediaElement.currentTime : 0,
          paused: mediaElement.paused,
          muted: mediaElement.muted,
          volume: Number.isFinite(mediaElement.volume) ? Math.max(0, Math.min(1, mediaElement.volume)) : 1,
        };
      } else {
        const snapshot = videoTimelineByPageIndex[pageIndex];
        if (snapshot) {
          pendingSourceRestoreRef.current[pageIndex] = {
            currentTime: snapshot.currentTime,
            paused: snapshot.paused,
            muted: snapshot.muted,
            volume: snapshot.volume,
          };
        }
      }

      setCurrentSourceIndexByPageIndex((prev) => ({ ...prev, [pageIndex]: clampedIndex }));
    },
    [currentSourceIndexByPageIndex, pages, videoTimelineByPageIndex]
  );

  const handleChangePageSubtitle = useCallback(
    (pageIndex: number, subtitleIndex: number) => {
      const page = effectivePages[pageIndex];
      const subtitleAttachments = ArchiveService.getSubtitleAttachments(page?.effectiveMetadata || page?.metadata);
      const subtitleCount = subtitleAttachments.length;
      if (!page || subtitleCount <= 0) return;
      
      const sourceIndex = currentSourceIndexByPageIndex[pageIndex] ?? page?.defaultSourceIndex ?? 0;
      const key = buildSubtitleSourceKey(pageIndex, sourceIndex);
      const currentIndexes = currentSubtitleIndexBySourceKey[key] || [];
      
      // Toggle subtitle index: remove if exists, add if not exists
      let nextIndexes: number[];
      if (currentIndexes.includes(subtitleIndex)) {
        nextIndexes = currentIndexes.filter((idx) => idx !== subtitleIndex);
      } else {
        nextIndexes = [...currentIndexes, subtitleIndex].sort((a, b) => a - b);
      }
      
      // Update preference based on last selected subtitle
      if (nextIndexes.length > 0) {
        const lastIndex = nextIndexes[nextIndexes.length - 1];
        const selected = subtitleAttachments[lastIndex];
        subtitlePreferenceRef.current = {
          language: String(selected?.language || '').trim().toLowerCase(),
          name: String(selected?.name || '').trim().toLowerCase(),
        };
      } else {
        subtitlePreferenceRef.current = null;
      }

      setCurrentSubtitleIndexBySourceKey((prev) => ({ ...prev, [key]: nextIndexes }));
    },
    [currentSourceIndexByPageIndex, currentSubtitleIndexBySourceKey, effectivePages]
  );

  useEffect(() => {
    const pendingEntries = Object.entries(pendingSourceRestoreRef.current);
    if (pendingEntries.length <= 0) return;

    const cleanups: Array<() => void> = [];
    for (const [pageIndexText] of pendingEntries) {
      const pageIndex = Number.parseInt(pageIndexText, 10);
      if (!Number.isFinite(pageIndex)) continue;
      const element = videoRefs.current[pageIndex];
      if (!element) continue;

      let applied = false;
      const applyRestore = () => {
        if (applied) return;
        const currentRestore = pendingSourceRestoreRef.current[pageIndex];
        if (!currentRestore) return;
        applied = true;

        const duration = Number.isFinite(element.duration) && element.duration > 0 ? element.duration : 0;
        const targetTime = duration > 0
          ? Math.max(0, Math.min(duration, currentRestore.currentTime))
          : Math.max(0, currentRestore.currentTime);
        try {
          element.currentTime = targetTime;
        } catch {
          // ignore browsers that block seeking before metadata is fully ready
        }
        element.muted = currentRestore.muted;
        element.volume = Math.max(0, Math.min(1, currentRestore.volume));
        if (!currentRestore.paused) {
          void element.play().catch(() => {});
        } else {
          element.pause();
        }

        setVideoTimelineByPageIndex((prev) => ({
          ...prev,
          [pageIndex]: {
            currentTime: targetTime,
            duration,
            paused: element.paused,
            muted: element.muted,
            volume: Number.isFinite(element.volume) ? element.volume : currentRestore.volume,
            buffered: prev[pageIndex]?.buffered ?? 0,
          },
        }));
        delete pendingSourceRestoreRef.current[pageIndex];
      };

      if (element.readyState >= 1) {
        applyRestore();
        continue;
      }

      const handleReady = () => applyRestore();
      element.addEventListener('loadedmetadata', handleReady);
      element.addEventListener('canplay', handleReady);
      cleanups.push(() => {
        element.removeEventListener('loadedmetadata', handleReady);
        element.removeEventListener('canplay', handleReady);
      });
    }

    return () => {
      for (const cleanup of cleanups) cleanup();
    };
  }, [effectivePages, videoTimelineByPageIndex]);

  const sidebar = useReaderSidebar({
    pages: effectivePages as any,
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
    pages: effectivePages as any,
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
      setCurrentPage,
      streamIndexByRealPage,
      webtoonVirtualization.containerHeight,
      webtoonVirtualization.imageHeights,
    ]
  );

  const progressLaneSpecs = useMemo(
    () =>
      buildReaderProgressLaneSpecs({
        readingMode,
        doublePageMode,
        splitCoverMode,
        isHtmlSpreadView,
        currentPage: readingMode === 'webtoon' ? currentRealPage : currentPage,
        pagesLength: effectivePages.length,
        getPageType: (pageIndex) => effectivePages[pageIndex]?.effectiveType ?? null,
      }),
    [currentPage, currentRealPage, doublePageMode, effectivePages, isHtmlSpreadView, readingMode, splitCoverMode]
  );

  const mediaLanePageIndexes = useMemo(
    () =>
      progressLaneSpecs
        .filter((lane) => (lane.kind === 'video' || lane.kind === 'audio') && typeof lane.mediaPageIndex === 'number')
        .map((lane) => lane.mediaPageIndex as number),
    [progressLaneSpecs]
  );

  useEffect(() => {
    if (mediaLanePageIndexes.length <= 0) return;

    const cleanups: Array<() => void> = [];
    for (const pageIndex of mediaLanePageIndexes) {
      const el = videoRefs.current[pageIndex];
      if (!el) continue;

      const sync = () => {
        const nextCurrent = Number.isFinite(el.currentTime) && el.currentTime >= 0 ? el.currentTime : 0;
        const nextDuration = Number.isFinite(el.duration) && el.duration > 0 ? el.duration : 0;
        const nextPaused = el.paused;
        const nextMuted = el.muted;
        const nextVolume = Number.isFinite(el.volume) ? Math.max(0, Math.min(1, el.volume)) : 1;
        // 计算已缓冲比例：取所有缓冲范围中包含当前时间的最远 end 点
        let nextBuffered = 0;
        if (nextDuration > 0 && el.buffered.length > 0) {
          let maxEnd = 0;
          for (let i = 0; i < el.buffered.length; i++) {
            if (el.buffered.start(i) <= nextCurrent + 0.5) {
              maxEnd = Math.max(maxEnd, el.buffered.end(i));
            }
          }
          nextBuffered = Math.min(1, maxEnd / nextDuration);
        }
        setVideoTimelineByPageIndex((prev) => {
          const previous = prev[pageIndex];
          if (
            previous &&
            previous.currentTime === nextCurrent &&
            previous.duration === nextDuration &&
            previous.paused === nextPaused &&
            previous.muted === nextMuted &&
            previous.volume === nextVolume &&
            previous.buffered === nextBuffered
          ) {
            return prev;
          }
          return {
            ...prev,
            [pageIndex]: {
              currentTime: nextCurrent,
              duration: nextDuration,
              paused: nextPaused,
              muted: nextMuted,
              volume: nextVolume,
              buffered: nextBuffered,
            },
          };
        });
      };

      sync();
      el.addEventListener('timeupdate', sync);
      el.addEventListener('durationchange', sync);
      el.addEventListener('loadedmetadata', sync);
      el.addEventListener('seeked', sync);
      el.addEventListener('play', sync);
      el.addEventListener('pause', sync);
      el.addEventListener('volumechange', sync);
      el.addEventListener('progress', sync);

      cleanups.push(() => {
        el.removeEventListener('timeupdate', sync);
        el.removeEventListener('durationchange', sync);
        el.removeEventListener('loadedmetadata', sync);
        el.removeEventListener('seeked', sync);
        el.removeEventListener('play', sync);
        el.removeEventListener('pause', sync);
        el.removeEventListener('volumechange', sync);
        el.removeEventListener('progress', sync);
      });
    }

    return () => {
      for (const cleanup of cleanups) cleanup();
    };
  }, [mediaLanePageIndexes]);

  const progressLanes = useMemo<ReaderProgressLane[]>(() => {
    const hasMediaLane = progressLaneSpecs.some((lane) => lane.kind === 'video' || lane.kind === 'audio');
    if (!hasMediaLane) return [];

    return progressLaneSpecs.map((lane) => {
      if (lane.kind === 'book') {
        return {
          id: 'book',
          kind: 'book',
          icon: Book,
          label: lane.label,
          value: sliderCurrentPage,
          min: 0,
          max: Math.max(0, sliderTotalPages - 1),
          step: 1,
          valueText: `${sliderCurrentPage + 1}/${sliderTotalPages}`,
          onChange: (nextValue: number) => handleSliderChangePage(Math.round(nextValue)),
        };
      }

      const pageIndex = lane.mediaPageIndex ?? -1;
      const page = pageIndex >= 0 ? pages[pageIndex] : undefined;
      const effectivePage = pageIndex >= 0 ? effectivePages[pageIndex] : undefined;
      const videoElement = pageIndex >= 0 ? videoRefs.current[pageIndex] : null;
      const snapshot = pageIndex >= 0 ? videoTimelineByPageIndex[pageIndex] : undefined;
      const sourceLabels = page ? buildSourceOptionLabels(page) : [];
      const sourceOptions = page?.sources?.map((_, sourceIndex) => ({
        value: sourceIndex,
        label: sourceLabels[sourceIndex] || `Source ${sourceIndex + 1}`,
      }));
      const subtitleAttachments = ArchiveService.getSubtitleAttachments(effectivePage?.effectiveMetadata || effectivePage?.metadata);
      const subtitleOptions = lane.kind === 'video' || lane.kind === 'audio'
        ? subtitleAttachments.map((attachment, subtitleIndex) => ({
            value: subtitleIndex,
            label: buildSubtitleOptionLabel(attachment, subtitleIndex),
          }))
        : undefined;
      const activeSourceIndex = pageIndex >= 0 ? currentSourceIndexByPageIndex[pageIndex] ?? page?.defaultSourceIndex ?? 0 : 0;
      const activeSubtitleIndexes = pageIndex >= 0 ? currentSubtitleIndexByPageIndex[pageIndex] ?? [] : [];
      const currentTime =
        snapshot?.currentTime ??
        (videoElement && Number.isFinite(videoElement.currentTime) ? videoElement.currentTime : 0);
      const duration =
        snapshot?.duration ??
        (videoElement && Number.isFinite(videoElement.duration) && videoElement.duration > 0 ? videoElement.duration : 0);
      const isPlaying = snapshot ? !snapshot.paused : Boolean(videoElement && !videoElement.paused);
      const isMuted = snapshot?.muted ?? Boolean(videoElement?.muted);
      const volume = snapshot?.volume ?? (videoElement && Number.isFinite(videoElement.volume) ? videoElement.volume : 1);
      const buffered = snapshot?.buffered ?? 0;
      const max = duration > 0 ? duration : 1;

      return {
        id: lane.id,
        kind: lane.kind,
        icon:
          lane.kind === 'audio'
            ? Music2
            : lane.id === 'video-right'
              ? Clapperboard
              : Film,
        label: lane.label,
        value: Math.max(0, Math.min(max, currentTime)),
        min: 0,
        max,
        step: 0.1,
        valueText: `${formatVideoClock(currentTime)}/${formatVideoClock(duration)}`,
        onChange: (nextValue: number) => {
          if (!videoElement) return;
          const clamped = Math.max(0, Math.min(max, nextValue));
          videoElement.currentTime = clamped;
          setVideoTimelineByPageIndex((prev) => ({
            ...prev,
            [pageIndex]: {
              currentTime: clamped,
              duration,
              paused: videoElement.paused,
              muted: videoElement.muted,
              volume: Number.isFinite(videoElement.volume) ? videoElement.volume : 1,
              buffered,
            },
          }));
        },
        isPlaying,
        isMuted,
        volume,
        buffered,
        sourceOptions,
        activeSourceIndex,
        subtitleOptions,
        activeSubtitleIndexes,
        onSourceChange: (nextSourceIndex: number) => handleChangePageSource(pageIndex, nextSourceIndex),
        onSubtitleChange: (nextSubtitleIndex: number) => handleChangePageSubtitle(pageIndex, nextSubtitleIndex),
        onTogglePlay: () => {
          if (!videoElement) return;
          if (videoElement.paused) {
            void videoElement.play().catch(() => {});
          } else {
            videoElement.pause();
          }
        },
        onSeekRelative: (deltaSeconds: number) => {
          if (!videoElement) return;
          const current = Number.isFinite(videoElement.currentTime) ? videoElement.currentTime : 0;
          const target = Math.max(0, Math.min(max, current + deltaSeconds));
          videoElement.currentTime = target;
        },
        onToggleMute: () => {
          if (!videoElement) return;
          videoElement.muted = !videoElement.muted;
        },
        onVolumeChange: (nextVolume: number) => {
          if (!videoElement) return;
          const target = Math.max(0, Math.min(1, nextVolume));
          videoElement.volume = target;
          if (target > 0 && videoElement.muted) {
            videoElement.muted = false;
          }
        },
      };
    });
  }, [
    currentSourceIndexByPageIndex,
    currentSubtitleIndexByPageIndex,
    effectivePages,
    handleChangePageSubtitle,
    handleChangePageSource,
    handleSliderChangePage,
    pages,
    progressLaneSpecs,
    sliderCurrentPage,
    sliderTotalPages,
    videoTimelineByPageIndex,
  ]);

  useEffect(() => {
    if (progressLanes.length <= 0) {
      setExpandedProgressLaneId(null);
      return;
    }
    if (expandedProgressLaneId && progressLanes.some((lane) => lane.id === expandedProgressLaneId)) {
      return;
    }
    setExpandedProgressLaneId(progressLanes[0]?.id ?? null);
  }, [expandedProgressLaneId, progressLanes]);

  const handleToggleProgressLane = useCallback((laneId: string) => {
    setExpandedProgressLaneId((prev) => (prev === laneId ? null : laneId));
  }, []);

  // 处理双击放大
  const handleDoubleClick = useCallback((e: React.MouseEvent) => {
    if (!doubleTapZoom) return;

    // 开启“点击翻页”时，边缘区域优先用于翻页；缩小鼠标双击放大触发区域（仅中心区域可放大）
    if (tapTurnPageEnabled) {
      const action = getTapTurnAction(readerAreaRef.current, e.clientX, e.clientY);
      if (action === 'prev' || action === 'next') return;
    }
    
    e.preventDefault();

    if (readingMode === 'webtoon') {
      const currentTarget = e.currentTarget as HTMLElement;
      const rawPageIndex = currentTarget.dataset.readerPageIndex;
      const pageIndex = rawPageIndex ? Number.parseInt(rawPageIndex, 10) : Number.NaN;
      if (!Number.isFinite(pageIndex)) return;

      const rect = currentTarget.getBoundingClientRect();
      const originX = Math.max(0, Math.min(100, ((e.clientX - rect.left) / Math.max(1, rect.width)) * 100));
      const originY = Math.max(0, Math.min(100, ((e.clientY - rect.top) / Math.max(1, rect.height)) * 100));

      setWebtoonZoom((prev) => {
        if (prev?.pageIndex === pageIndex) return null;
        return {
          pageIndex,
          scale: WEBTOON_DOUBLE_TAP_SCALE,
          originX,
          originY,
        };
      });
      return;
    }
    
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
    readingMode,
    readerAreaRef,
  ]);

  // 处理图片拖拽开始
  const handleImageDragStart = useCallback((e: React.DragEvent) => {
    e.preventDefault();
  }, []);

  // 处理视频点击 - 切换工具栏显示/隐藏
  const handleVideoClick = useCallback(() => {
    toolbar.toggleToolbar();
  }, [toolbar]);

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
      const targetReal = computeCollectionEndReturnRealPage({
        activeSegment,
        readingMode,
        doublePageMode,
        splitCoverMode,
        tailPageType: activeSegmentLastRealPage >= 0 ? effectivePages[activeSegmentLastRealPage]?.effectiveType ?? null : null,
      });
      if (targetReal == null) return;

      const target = streamIndexByRealPage.get(targetReal) ?? targetReal;
      setCurrentPage(Math.max(0, target));
      resetTransform();
      return;
    }

    if (tryTurnHtmlSpread('prev')) return;

    const prevBoundaryAction = computePrevBoundaryAction({
      currentPage,
      hasTankoubonContext,
      hasPrevArchive: Boolean(prevArchiveId),
      seamlessEnabled,
    });
    if (prevBoundaryAction.type === 'jump-prev-chapter') {
      requestChapterJump('prev', navigateToPrevArchiveEnd);
      return;
    }

    const targetPage = computeReaderAdjacentPage({
      direction: 'prev',
      currentPage,
      totalPages,
      doublePageMode,
      splitCoverMode,
      isHtmlSpreadView,
    });
    if (targetPage != null) {
      setCurrentPage(targetPage);
      resetTransform();
    }
  }, [
    hasTankoubonContext,
    currentPage,
    isCollectionEndPage,
    requestChapterJump,
    navigateToPrevArchiveEnd,
    effectivePages,
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
    activeSegmentLastRealPage,
    setCurrentPage,
    totalPages,
  ]);

  const handleNextPage = useCallback(() => {
    if (isCollectionEndPage) {
      const collectionEndAction = computeCollectionEndNextAction({
        seamlessEnabled,
        isTailCollectionEndPage,
        currentPage,
        totalPages,
        hasNextArchive: Boolean(nextArchive?.id),
      });

      if (collectionEndAction.type === 'append') {
        void appendNextArchiveToStream();
        return;
      }
      if (collectionEndAction.type === 'advance') {
        setCurrentPage(collectionEndAction.page);
        resetTransform();
        return;
      }
      if (collectionEndAction.type === 'jump-next-chapter') {
        requestChapterJump('next', navigateToNextArchiveStart);
      }
      return;
    }

    if (tryTurnHtmlSpread('next')) return;

    const targetPage = computeReaderAdjacentPage({
      direction: 'next',
      currentPage,
      totalPages,
      doublePageMode,
      splitCoverMode,
      isHtmlSpreadView,
    });
    if (targetPage != null) {
      setCurrentPage(targetPage);
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
    setCurrentPage,
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
    pages: effectivePages as any,
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

  const { handleVideoEnded } = useReaderVideoAutoNext({
    currentPage,
    pagesLength: totalPages,
    doublePageMode,
    splitCoverMode,
    onNextPage: handleNextPage,
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

    if (doublePageMode && effectivePages.length > 0) {
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
  }, [splitCoverMode, doublePageMode, currentPage, effectivePages.length, isCurrentOrTailHtmlPage, setCurrentPage]);

  const displayArchiveTitle = useMemo(() => {
    if (!isCollectionEndPage) {
      const primaryIndex = currentRealPage;
      const primaryPageTitle = getPageHeaderTitle(effectivePages[primaryIndex] as any);
      if (primaryPageTitle) return primaryPageTitle;

      const hasSecondVisiblePage =
        readingMode !== 'webtoon' &&
        doublePageMode &&
        !isHtmlSpreadView &&
        !(splitCoverMode && currentPage === 0);
      if (hasSecondVisiblePage) {
        const secondaryPageTitle = getPageHeaderTitle(effectivePages[primaryIndex + 1] as any);
        if (secondaryPageTitle) return secondaryPageTitle;
      }
    }

    return archive.archiveTitle || activeSegment?.title || '';
  }, [
    activeSegment?.title,
    archive.archiveTitle,
    currentPage,
    currentRealPage,
    doublePageMode,
    isCollectionEndPage,
    isHtmlSpreadView,
    effectivePages,
    readingMode,
    splitCoverMode,
  ]);
  const shouldRenderSidebar = sidebar.sidebarOpen || sidebar.sidebarLoading;

  if (loading) {
    return (
      <div className="min-h-screen bg-black text-white flex items-center justify-center">
        <Spinner size="lg" />
      </div>
    );
  }

  if (error || effectivePages.length === 0) {
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
      className="bg-background text-foreground flex flex-col overflow-hidden relative"
      style={{ height: '100dvh', minHeight: 0 }}
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
          progressLanes={progressLanes}
          expandedLaneId={expandedProgressLaneId}
          onToggleLane={handleToggleProgressLane}
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
        className="flex-1 min-h-0 relative overflow-hidden"
        onTouchStart={interactionHandlers.onTouchStart}
        onTouchMove={interactionHandlers.onTouchMove}
        onTouchEnd={interactionHandlers.onTouchEnd}
        onClick={interactionHandlers.onClick}
      >
        {mediaInfoEnabled ? (
          <MediaInfoOverlay lines={mediaInfoOverlayLines} sidebarOpen={sidebar.sidebarOpen} />
        ) : null}

        {/* 侧边栏导航 */}
        {shouldRenderSidebar ? (
          <ReaderSidebar
            open={sidebar.sidebarOpen}
            allPages={effectivePages as any}
            sidebarScrollRef={sidebar.sidebarScrollRef}
            sidebarLoading={sidebar.sidebarLoading}
            isEpub={sidebar.isEpub}
            sidebarDisplayPages={sidebar.sidebarDisplayPages}
            currentPage={readingMode === 'webtoon' ? currentRealPage : currentPage}
            pagesLength={effectivePages.length}
            canLoadMore={sidebar.sidebarLoadedCount < effectivePages.length}
            onSelectPage={sidebar.handleSidebarPageSelect}
            onLoadMore={sidebar.handleLoadMoreSidebarPages}
            onOpenChange={sidebar.setSidebarOpen}
            t={t}
          />
        ) : null}

        {/* 单页模式 */}
 	        <ReaderSingleModeView
 	          enabled={readingMode !== 'webtoon' && !isCollectionEndPage}
 	          sidebarOpen={sidebar.sidebarOpen}
            readerAreaRef={readerAreaRef}
            tapTurnPageEnabled={tapTurnPageEnabled}
            longPageEnabled={longPageEnabled}
 	          pages={effectivePages as any}
            currentSubtitleIndexByPageIndex={currentSubtitleIndexByPageIndex}
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
	          onVideoClick={handleVideoClick}
	          onVideoEnded={handleVideoEnded}
	          showToolbar={toolbar.showToolbar}
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
            nextMode={endPageIsRelatedNext ? 'related' : 'chapter'}
            onOpenNextDetails={handleOpenRelatedNextDetails}
            onOpenNextReader={handleOpenRelatedNextReader}
            t={t}
          />

        {/* 隐藏的预加载区域：前1页和后5页（仅单页/双页模式） */}
	        <ReaderPreloadArea
	          enabled={readingMode !== 'webtoon' && !isCollectionEndPage}
	          imagesLoading={imageLoading.imagesLoading}
	          currentPage={currentPage}
	          doublePageMode={doublePageMode}
	          pages={effectivePages as any}
	          cachedPages={imageLoading.cachedPages}
	          onLoaded={imageLoading.handleImageLoad}
	          onError={imageLoading.handleImageError}
	          onCacheImage={imageLoading.cacheImage}
	        />

        {/* 条漫模式 */}
	        <ReaderWebtoonModeView
	          enabled={readingMode === 'webtoon'}
	          webtoonContainerRef={webtoonContainerRef}
            contentContainerRef={handleWebtoonContentContainerRef}
	          sidebarOpen={sidebar.sidebarOpen}
	          onScroll={handleWebtoonScroll}
	          pages={streamPages}
            currentSubtitleIndexByPageIndex={currentSubtitleIndexByPageIndex}
	          finishedId={activeArchiveId}
	          finishedTitle={displayArchiveTitle}
	          finishedCoverAssetId={getArchiveAssetId(archive.archiveMetadata, 'cover')}
	          nextId={nextArchive?.id ?? null}
	          nextTitle={nextArchive?.title ?? null}
	          nextCoverAssetId={nextArchive?.coverAssetId}
	          nextMode={endPageIsRelatedNext ? 'related' : 'chapter'}
	          onOpenNextDetails={handleOpenRelatedNextDetails}
	          onOpenNextReader={handleOpenRelatedNextReader}
	          cachedPages={imageLoading.cachedPages}
	          visibleRange={webtoonVirtualization.visibleRange}
	          imageHeights={webtoonVirtualization.imageHeights}
	          containerHeight={webtoonVirtualization.containerHeight}
	          prefixHeights={webtoonVirtualization.prefixHeights}
	          totalHeight={webtoonVirtualization.totalHeight}
	          imagesLoading={imageLoading.imagesLoading}
	          loadedImages={imageLoading.loadedImages}
            webtoonZoom={webtoonZoom}
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
	          onVideoClick={handleVideoClick}
	          onVideoEnded={handleVideoEnded}
	          showToolbar={toolbar.showToolbar}
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
