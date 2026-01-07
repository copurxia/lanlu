'use client';

import { useSearchParams, useRouter } from 'next/navigation';
import { useState, useEffect, useCallback, useMemo, Suspense, useRef } from 'react';
import type React from 'react';
import { ArchiveService, PageInfo } from '@/lib/archive-service';
import { FavoriteService } from '@/lib/favorite-service';
import { Button } from '@/components/ui/button';
import { Spinner } from '@/components/ui/spinner';
import { useLanguage } from '@/contexts/LanguageContext';
import { MediaInfoOverlay } from '@/components/reader/components/MediaInfoOverlay';
import { ReaderFloatingControls } from '@/components/reader/components/ReaderFloatingControls';
import { ReaderPreloadArea } from '@/components/reader/components/ReaderPreloadArea';
import { ReaderSidebar } from '@/components/reader/components/ReaderSidebar';
import { ReaderSingleModeView } from '@/components/reader/components/ReaderSingleModeView';
import { ReaderTopBar } from '@/components/reader/components/ReaderTopBar';
import { ReaderWebtoonModeView } from '@/components/reader/components/ReaderWebtoonModeView';
import { logger } from '@/lib/logger';
import { toast } from 'sonner';
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
  Eye,
  Info,
  MousePointerClick
} from 'lucide-react';
import Link from 'next/link';
import type { ArchiveMetadata } from '@/types/archive';

const TAP_MOVE_THRESHOLD_PX = 10;
const TAP_MAX_DURATION_MS = 350;
const IGNORE_CLICK_AFTER_TOUCH_MS = 800;

function formatSeconds(seconds: number) {
  if (!Number.isFinite(seconds) || seconds < 0) return '--:--';
  const whole = Math.floor(seconds);
  const h = Math.floor(whole / 3600);
  const m = Math.floor((whole % 3600) / 60);
  const s = whole % 60;
  if (h > 0) return `${h}:${String(m).padStart(2, '0')}:${String(s).padStart(2, '0')}`;
  return `${m}:${String(s).padStart(2, '0')}`;
}

function formatPercent(value: number) {
  if (!Number.isFinite(value)) return '--%';
  return `${Math.round(value * 100)}%`;
}

function formatMiB(bytes: number | null) {
  if (!bytes || !Number.isFinite(bytes) || bytes <= 0) return '-- MiB';
  return `${(bytes / 1024 / 1024).toFixed(2)} MiB`;
}

function getApproxResourceBytes(resourceUrl: string) {
  if (typeof window === 'undefined') return null;
  if (!resourceUrl) return null;

  if (resourceUrl.startsWith('data:')) {
    const base64Index = resourceUrl.indexOf('base64,');
    if (base64Index >= 0) {
      const base64 = resourceUrl.slice(base64Index + 'base64,'.length);
      const padding = base64.endsWith('==') ? 2 : base64.endsWith('=') ? 1 : 0;
      return Math.floor((base64.length * 3) / 4) - padding;
    }
    return null;
  }

  try {
    const entries = performance.getEntriesByName(resourceUrl) as PerformanceEntry[];
    const resourceEntries = entries.filter((entry) => entry.entryType === 'resource') as PerformanceResourceTiming[];
    const latest = resourceEntries.sort((a, b) => a.startTime - b.startTime).at(-1);
    if (!latest) return null;
    const bytes = latest.transferSize || latest.encodedBodySize || latest.decodedBodySize;
    return bytes && bytes > 0 ? bytes : null;
  } catch {
    return null;
  }
}

function getImageFormatLabel(resourceUrl: string) {
  if (!resourceUrl) return null;

  if (resourceUrl.startsWith('data:')) {
    const match = resourceUrl.match(/^data:([^;,]+)[;,]/i);
    const mime = match?.[1]?.toLowerCase() || '';
    if (mime.startsWith('image/')) return mime.slice('image/'.length);
    return null;
  }

  try {
    const parsed = new URL(resourceUrl, typeof window !== 'undefined' ? window.location.origin : 'http://localhost');
    const pathnameExt = parsed.pathname.split('/').pop()?.split('.').pop();
    if (pathnameExt && pathnameExt !== parsed.pathname) return pathnameExt.toLowerCase();

    const pathParam = parsed.searchParams.get('path');
    if (pathParam) {
      const decoded = decodeURIComponent(pathParam);
      const ext = decoded.split('/').pop()?.split('.').pop();
      if (ext) return ext.toLowerCase();
    }
  } catch {
    const ext = resourceUrl.split('?')[0]?.split('#')[0]?.split('.').pop();
    if (ext && ext !== resourceUrl) return ext.toLowerCase();
  }

  return null;
}

function getLastPathSegment(url: string) {
  try {
    const parsed = new URL(url, typeof window !== 'undefined' ? window.location.origin : 'http://localhost');
    const pathname = parsed.pathname || '';
    const last = pathname.split('/').filter(Boolean).pop();
    return last || url;
  } catch {
    const parts = url.split('?')[0]?.split('#')[0]?.split('/').filter(Boolean);
    return parts?.[parts.length - 1] || url;
  }
}

function ReaderContent() {
  const router = useRouter();
  const searchParams = useSearchParams();
  const id = searchParams?.get('id') ?? null;
  const pageParam = searchParams?.get('page');
  const { t, language } = useLanguage();
  
  const [pages, setPages] = useState<PageInfo[]>([]);
  const [cachedPages, setCachedPages] = useState<string[]>([]);
  const [currentPage, setCurrentPage] = useState(0);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [touchStart, setTouchStart] = useState<{ x: number; y: number } | null>(null);
  const [touchEnd, setTouchEnd] = useState<{ x: number; y: number } | null>(null);
  const [imagesLoading, setImagesLoading] = useState<Set<number>>(new Set());
  const [loadedImages, setLoadedImages] = useState<Set<number>>(new Set()); // 跟踪已加载的图片
  const [htmlContents, setHtmlContents] = useState<Record<number, string>>({}); // HTML内容缓存（按页索引）
  const [showToolbar, setShowToolbar] = useState(true);
  const [isFavorited, setIsFavorited] = useState(false); // 收藏状态
  const [archiveTitle, setArchiveTitle] = useState<string>(''); // 归档标题
  const [archiveMetadata, setArchiveMetadata] = useState<ArchiveMetadata | null>(null);
  const [scale, setScale] = useState(1);
  const [translateX, setTranslateX] = useState(0);
  const [translateY, setTranslateY] = useState(0);
  const [lastTouchDistance, setLastTouchDistance] = useState(0);
  const tapStartRef = useRef<{ x: number; y: number; time: number } | null>(null);
  const tapMovedRef = useRef(false);
  const lastTouchAtRef = useRef(0);
  const readerAreaRef = useRef<HTMLDivElement | null>(null);
  const webtoonContainerRef = useRef<HTMLDivElement>(null);
  const webtoonPageElementRefs = useRef<(HTMLDivElement | null)[]>([]);
  const imageRefs = useRef<(HTMLImageElement | null)[]>([]);
  const observerRef = useRef<IntersectionObserver | null>(null);
  const currentPageRef = useRef<number>(0); // 用于跟踪最新的currentPage值
  const [visibleRange, setVisibleRange] = useState({ start: 0, end: 2 }); // 可见范围
  const [imageHeights, setImageHeights] = useState<number[]>([]); // 存储每张图片的高度
  const [containerHeight, setContainerHeight] = useState(0); // 容器高度
  const imageLoadTimeoutRef = useRef<NodeJS.Timeout | null>(null); // 图片加载防抖引用
  const autoHideTimeoutRef = useRef<NodeJS.Timeout | null>(null); // 自动隐藏定时器引用
  const AUTO_HIDE_DELAY = 3000; // 自动隐藏延迟时间（毫秒）

  // 侧边栏状态管理
  const [sidebarOpen, setSidebarOpen] = useState(false);
  const [sidebarDisplayPages, setSidebarDisplayPages] = useState<PageInfo[]>([]);
  const [sidebarLoadedCount, setSidebarLoadedCount] = useState(20);
  const [sidebarLoading, setSidebarLoading] = useState(false);
  const [sidebarImagesLoading, setSidebarImagesLoading] = useState<Set<number>>(new Set());
  const [settingsOpen, setSettingsOpen] = useState(false);
  const [isEpub, setIsEpub] = useState(false); // 是否为EPUB文件
  const [showAutoNextCountdown, setShowAutoNextCountdown] = useState(false); // 是否显示自动跳转倒计时
  const [countdownSeconds, setCountdownSeconds] = useState(3); // 倒计时秒数
  const countdownTimeoutRef = useRef<NodeJS.Timeout | null>(null); // 倒计时定时器引用
  const countdownToastId = useRef<string | number | null>(null); // toast ID引用
  const COUNTDOWN_DURATION = 3; // 倒计时持续时间（秒）
  const sidebarScrollRef = useRef<HTMLDivElement | null>(null); // 侧边栏滚动容器引用
  const scrollTimeoutRef = useRef<NodeJS.Timeout | null>(null);

  // 提取设备检测和宽度计算的通用函数
  const getDeviceInfo = useCallback(() => {
    const containerWidth = window.innerWidth >= 1024
      ? Math.min(800, window.innerWidth * 0.8)
      : Math.min(window.innerWidth * 0.95, window.innerWidth);
    return { containerWidth };
  }, []);

  // 清除倒计时定时器
  const clearCountdown = useCallback(() => {
    if (countdownTimeoutRef.current) {
      clearTimeout(countdownTimeoutRef.current);
      countdownTimeoutRef.current = null;
    }
    if (countdownToastId.current !== null) {
      toast.dismiss(countdownToastId.current);
      countdownToastId.current = null;
    }
    setShowAutoNextCountdown(false);
    setCountdownSeconds(COUNTDOWN_DURATION);
  }, []);

  const getImageHeight = useCallback((naturalWidth: number, naturalHeight: number) => {
    const { containerWidth } = getDeviceInfo();
    const aspectRatio = naturalHeight / naturalWidth;
    return containerWidth * aspectRatio;
  }, [getDeviceInfo]);

  // 智能返回逻辑：检查是否能安全返回站内页面
  const handleBack = useCallback(() => {
    // 检查是否有历史记录且上一页是站内页面
    const referrer = document.referrer;
    const currentOrigin = window.location.origin;

    // 如果有上一页且上一页是站内页面，则返回上一页
    if (window.history.length > 1 && referrer && referrer.startsWith(currentOrigin)) {
      window.history.back();
    } else {
      // 否则直接跳转到首页
      router.push('/');
    }
  }, [router]);

  const handleNavigateToArchiveFromSettings = useCallback(() => {
    if (!id) return;
    setSettingsOpen(false);
    router.push(`/archive?id=${id}`);
  }, [id, router]);

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
  const htmlContentsRef = useRef<Record<number, string>>({});
  const htmlLoadingRef = useRef<Set<number>>(new Set());
  const videoRefs = useRef<(HTMLVideoElement | null)[]>([]);
  const htmlContainerRefs = useRef<(HTMLDivElement | null)[]>([]);
  const imageRequestUrls = useRef<(string | null)[]>([]);
  const [mediaInfoTick, setMediaInfoTick] = useState(0);

  const isInteractiveTarget = useCallback((target: EventTarget | null) => {
    if (!(target instanceof HTMLElement)) return false;
    return Boolean(
      target.closest(
        'a,button,input,textarea,select,option,[role="button"],[role="link"],[data-no-reader-tap]'
      )
    );
  }, []);

  const isHtmlContentTarget = useCallback((target: EventTarget | null) => {
    if (!(target instanceof HTMLElement)) return false;
    return Boolean(target.closest('.html-content-container'));
  }, []);

  const getTapTurnAction = useCallback((clientX: number, clientY: number) => {
    const el = readerAreaRef.current;
    if (!el) return 'none' as const;
    const rect = el.getBoundingClientRect();
    const x = clientX - rect.left;
    const y = clientY - rect.top;
    if (x < 0 || y < 0 || x > rect.width || y > rect.height) return 'none' as const;

    const clamp = (value: number, min: number, max: number) => Math.max(min, Math.min(max, value));
    const edgeW = clamp(rect.width * 0.22, 72, 180);
    const edgeH = clamp(rect.height * 0.22, 72, 180);

    const inLeft = x <= edgeW;
    const inRight = x >= rect.width - edgeW;
    const inTop = y <= edgeH;
    const inBottom = y >= rect.height - edgeH;

    if (!(inLeft || inRight || inTop || inBottom)) return 'none' as const;

    const leftDist = x;
    const rightDist = rect.width - x;
    const topDist = y;
    const bottomDist = rect.height - y;
    const minDist = Math.min(leftDist, rightDist, topDist, bottomDist);

    if (minDist === rightDist || minDist === bottomDist) return 'next' as const;
    return 'prev' as const;
  }, []);

  useEffect(() => {
    htmlContentsRef.current = htmlContents;
  }, [htmlContents]);

  const loadHtmlPage = useCallback(async (pageIndex: number) => {
    if (!id) return;
    const page = pages[pageIndex];
    if (!page || page.type !== 'html') return;
    if (htmlContentsRef.current[pageIndex]) return;
    if (htmlLoadingRef.current.has(pageIndex)) return;

    htmlLoadingRef.current.add(pageIndex);
    try {
      const response = await fetch(page.url);
      const html = await response.text();

      // 重写相对路径为API路径，确保资源文件正确加载
      const urlObj = new URL(page.url, window.location.origin);
      const pathParam = urlObj.searchParams.get('path');
      const currentDir = pathParam ? pathParam.substring(0, pathParam.lastIndexOf('/')) : '';

      let processedHtml = html;

      processedHtml = processedHtml.replace(
        /(src|href)=["'](?!http|https|data:|mailto:|tel:)([^"']+)["']/gi,
        (match, attr, relativePath) => {
          if (!relativePath.startsWith('/') && !relativePath.startsWith('data:')) {
            const fullPath = currentDir ? `${currentDir}/${relativePath}` : relativePath;
            const encodedPath = encodeURIComponent(fullPath);
            const apiPath = ArchiveService.addTokenToUrl(`/api/archives/${id}/page?path=${encodedPath}`);
            return `${attr}="${apiPath}"`;
          }
          return match;
        }
      );

      processedHtml = processedHtml.replace(
        /url\((?!['"]?(?:http|https|data:))([^'")]+)\)/gi,
        (match, relativePath) => {
          relativePath = relativePath.replace(/['"]/g, '');
          if (!relativePath.startsWith('/') && !relativePath.startsWith('data:')) {
            const fullPath = currentDir ? `${currentDir}/${relativePath}` : relativePath;
            const encodedPath = encodeURIComponent(fullPath);
            const apiPath = ArchiveService.addTokenToUrl(`/api/archives/${id}/page?path=${encodedPath}`);
            return `url(${apiPath})`;
          }
          return match;
        }
      );

      setHtmlContents(prev => ({ ...prev, [pageIndex]: processedHtml }));
    } catch (error) {
      logger.error('Failed to load HTML page', error);
      setError('Failed to load HTML content');
    } finally {
      htmlLoadingRef.current.delete(pageIndex);
    }
  }, [id, pages]);

  const clearAutoHideTimers = useCallback(() => {
    if (autoHideTimeoutRef.current) {
      clearTimeout(autoHideTimeoutRef.current);
      autoHideTimeoutRef.current = null;
    }
  }, []);

  const scheduleAutoHide = useCallback(() => {
    if (!autoHideEnabled) return;
    if (autoHideTimeoutRef.current) {
      clearTimeout(autoHideTimeoutRef.current);
    }
    autoHideTimeoutRef.current = setTimeout(() => {
      setShowToolbar(false);
    }, AUTO_HIDE_DELAY);
  }, [autoHideEnabled]);

  const hideToolbar = useCallback(() => {
    setShowToolbar(false);
    clearAutoHideTimers();
  }, [clearAutoHideTimers]);

  const toggleToolbar = useCallback(() => {
    if (!autoHideEnabled) return;
    setShowToolbar(prev => {
      const next = !prev;
      if (next) {
        scheduleAutoHide();
      } else {
        clearAutoHideTimers();
      }
      return next;
    });
  }, [autoHideEnabled, scheduleAutoHide, clearAutoHideTimers]);

  // 用于跟踪拆分封面模式的变化，避免无限循环
  const splitCoverModeRef = useRef(splitCoverMode);

  useEffect(() => {
    async function fetchPages() {
      if (!id) {
        setError('Missing archive ID');
        setLoading(false);
        return;
      }

      try {
        const data = await ArchiveService.getFiles(id);

        // 计算初始页码
        let initialPage: number;

        // URL的page参数优先级最高
        if (pageParam) {
          const urlPage = parseInt(pageParam, 10);
          if (!isNaN(urlPage) && urlPage > 0 && urlPage <= data.pages.length) {
            initialPage = urlPage - 1; // URL使用1-based，转换为0-based
          } else {
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
          
        // 在拆分封面模式下，需要调整恢复的页码
        if (doublePageModeFromStorage && splitCoverModeFromStorage) {
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

        // 如果有进度且需要预加载图片，添加到加载队列
        if (initialPage > 0) {
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
  }, [id, pageParam]);

  // 获取 metadata（包含标题、摘要、标签、收藏状态等）
  useEffect(() => {
    if (!id) {
      setArchiveMetadata(null);
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

  const metadataTags = useMemo(() => {
    if (!archiveMetadata?.tags) return [];
    return archiveMetadata.tags
      .split(',')
      .map((tag) => tag.trim())
      .filter(Boolean);
  }, [archiveMetadata?.tags]);

  // 单独处理错误消息的翻译
  useEffect(() => {
    if (error === 'Missing archive ID') {
      setError(t('reader.missingId'));
    } else if (error === 'Failed to fetch archive pages') {
      setError(t('reader.fetchError'));
    }
  }, [error, t]);

  // 初始化侧边栏状态和EPUB检测
  useEffect(() => {
    // 从localStorage恢复侧边栏状态
    if (typeof window !== 'undefined') {
      const savedSidebarState = localStorage.getItem('reader_sidebar_open');
      if (savedSidebarState !== null) {
        setSidebarOpen(savedSidebarState === 'true');
      }
    }

    // 检测是否为EPUB文件
    if (pages.length > 0) {
      // 如果第一个页面的类型是 'html'，则认为是EPUB
      const isEpubFile = pages[0]?.type === 'html';
      setIsEpub(isEpubFile);
    }
  }, [pages]);

  // 侧边栏状态持久化
  useEffect(() => {
    if (typeof window !== 'undefined') {
      localStorage.setItem('reader_sidebar_open', sidebarOpen.toString());
    }
  }, [sidebarOpen]);

  // 侧边栏页面数据初始化
  useEffect(() => {
    if (pages.length > 0 && sidebarDisplayPages.length === 0) {
      // 只在首次加载或pages数组变化时重置，避免load more时重新渲染
      setSidebarDisplayPages(pages.slice(0, sidebarLoadedCount));
      setSidebarLoading(false);
    }
  }, [pages, sidebarLoadedCount, sidebarDisplayPages.length]);

  // 监听currentPage变化，自动扩展侧边栏加载范围
  useEffect(() => {
    // 如果当前页面超出已加载范围，且还有更多内容可以加载
    if (currentPage >= sidebarLoadedCount && sidebarLoadedCount < pages.length && !sidebarLoading) {
      // 计算需要加载的页数，确保至少加载到当前页面+10页
      const targetCount = Math.min(pages.length, currentPage + 10);
      const newPages = pages.slice(sidebarLoadedCount, targetCount);

      if (newPages.length > 0) {
        setSidebarDisplayPages(prev => [...prev, ...newPages]);
        setSidebarLoadedCount(targetCount);

        // 同时添加新页面到缩略图加载队列
        const newPageIndices: number[] = [];
        for (let i = sidebarLoadedCount; i < targetCount; i++) {
          if (!loadedImages.has(i) && !imagesLoading.has(i)) {
            newPageIndices.push(i);
          }
        }
        if (newPageIndices.length > 0) {
          setSidebarImagesLoading(prev => {
            const updated = new Set(prev);
            newPageIndices.forEach(index => updated.add(index));
            return updated;
          });
        }
      }
    }
  }, [currentPage, pages.length, sidebarLoadedCount, sidebarLoading, loadedImages, imagesLoading]);

  // 更新阅读进度
  const updateReadingProgress = useCallback(async (page: number) => {
    if (!id) return;

    try {
      // 在拆分封面模式下，需要计算实际的阅读进度
      let actualPage = page;
      if (doublePageMode && splitCoverMode) {
        // 拆分封面模式：第0页显示第1页，第1页显示第2-3页，第3页显示第4-5页，以此类推
        if (page === 0) {
          // 封面页，实际是第1页
          actualPage = 0;
        } else if (page === 1) {
          // 显示第2-3页，保存进度为第3页
          actualPage = 2;
        } else {
          // 其他情况，currentPage显示的是第(currentPage+1)和第(currentPage+2)页
          // 保存进度为第(currentPage+2)页
          actualPage = page + 1;
        }
      }
      
      // 调用新的进度更新API，自动标记为已读
      await ArchiveService.updateProgress(id, actualPage + 1); // API 使用1-based页码
    } catch (err) {
      logger.operationFailed('update reading progress', err);
      // 静默失败，不影响阅读体验
    }
  }, [id, doublePageMode, splitCoverMode]);

  // 切换收藏状态
  const toggleFavorite = useCallback(async (e?: React.MouseEvent) => {
    if (!id) return;

    // 阻止事件冒泡
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
      // 可以显示错误提示，但静默失败更符合用户体验
    }
  }, [id, isFavorited]);

  // 切换全屏模式
  const toggleFullscreen = useCallback(async () => {
    if (!document.fullscreenElement) {
      try {
        await document.documentElement.requestFullscreen();
        setIsFullscreen(true);
        if (typeof window !== 'undefined') {
          localStorage.setItem('reader-fullscreen-mode', 'true');
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
        disabled: !doublePageMode,
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
      splitCoverMode,
      autoPlayMode,
      isFullscreen,
      doubleTapZoom,
      autoHideEnabled,
      tapTurnPageEnabled,
      mediaInfoEnabled,
      toggleFullscreen,
      setMediaInfoEnabled,
    ]
  );

  useEffect(() => {
    if (!mediaInfoEnabled) return;
    const interval = window.setInterval(() => setMediaInfoTick((prev) => prev + 1), 250);
    return () => window.clearInterval(interval);
  }, [mediaInfoEnabled]);

  const mediaInfoOverlayLines = useMemo(() => {
    if (!mediaInfoEnabled) return [];
    void mediaInfoTick;
    const page = pages[currentPage];
    if (!page) return [];

    const showSecondPage =
      readingMode !== 'webtoon' &&
      doublePageMode &&
      !(splitCoverMode && currentPage === 0) &&
      currentPage + 1 < pages.length;

    const indices = showSecondPage ? [currentPage, currentPage + 1] : [currentPage];

    const readImageInfo = (index: number) => {
      const element = imageRefs.current[index];
      if (!element) return null;
      const rect = element.getBoundingClientRect();
      const resourceUrl = imageRequestUrls.current[index] || element.currentSrc || element.src;
      return {
        naturalWidth: element.naturalWidth,
        naturalHeight: element.naturalHeight,
        displayedWidth: Math.round(rect.width),
        displayedHeight: Math.round(rect.height),
        bytes: getApproxResourceBytes(resourceUrl),
        format: getImageFormatLabel(resourceUrl),
      };
    };

    const readVideoInfo = (index: number) => {
      const element = videoRefs.current[index];
      if (!element) return null;
      const buffered = element.buffered;
      const bufferedEnd = buffered && buffered.length > 0 ? buffered.end(buffered.length - 1) : 0;
      return {
        videoWidth: element.videoWidth,
        videoHeight: element.videoHeight,
        duration: element.duration,
        currentTime: element.currentTime,
        playbackRate: element.playbackRate,
        muted: element.muted,
        volume: element.volume,
        paused: element.paused,
        readyState: element.readyState,
        bufferedEnd,
      };
    };

    const readHtmlInfo = (index: number) => {
      const html = htmlContents[index] || '';
      let title: string | null = null;
      if (html) {
        try {
          const parsed = new DOMParser().parseFromString(html, 'text/html');
          title = parsed.querySelector('title')?.textContent?.trim() || null;
        } catch {
          title = null;
        }
      }
      const container = htmlContainerRefs.current[index];
      const scrollable =
        readingMode !== 'webtoon' && container && container.scrollHeight > container.clientHeight;
      return {
        title,
        length: html.length,
        scrollTop: container ? Math.round(container.scrollTop) : null,
        scrollHeight: container ? Math.round(container.scrollHeight) : null,
        clientHeight: container ? Math.round(container.clientHeight) : null,
        scrollable,
      };
    };

    const lines: string[] = [];
    const headerIndexLabel = indices.length === 2 ? `${indices[0] + 1}-${indices[1] + 1}` : `${indices[0] + 1}`;
    lines.push(`P ${headerIndexLabel}/${pages.length}  ${readingMode}${doublePageMode ? '  double' : ''}`);
    if (isFullscreen) lines.push(`fullscreen`);

    indices.forEach((index, idx) => {
      const p = pages[index];
      if (!p) return;
      const prefix = indices.length === 2 ? `#${idx + 1} ` : '';
      const src = p.type === 'image' ? (cachedPages[index] || p.url) : p.url;
      lines.push(`${prefix}${p.type}  ${getLastPathSegment(src)}`);

      if (p.type === 'video') {
        const info = readVideoInfo(index);
        if (info) {
          const time = `${formatSeconds(info.currentTime)}/${formatSeconds(info.duration)}`;
          const bufferedPct =
            info.duration > 0 ? formatPercent(Math.min(1, Math.max(0, info.bufferedEnd / info.duration))) : '--%';
          lines.push(
            `${prefix}${info.videoWidth}x${info.videoHeight}  t ${time}  buf ${bufferedPct}`
          );
          lines.push(
            `${prefix}${info.paused ? 'paused' : 'playing'}  ${info.playbackRate.toFixed(2)}x  vol ${formatPercent(
              info.muted ? 0 : info.volume
            )}  ready ${info.readyState}`
          );
        }
      } else if (p.type === 'html') {
        const info = readHtmlInfo(index);
        if (info.title) lines.push(`${prefix}title  ${info.title}`);
        if (info.scrollable && info.scrollTop !== null && info.scrollHeight !== null && info.clientHeight !== null) {
          lines.push(`${prefix}scroll  ${info.scrollTop}/${info.scrollHeight - info.clientHeight}`);
        } else if (info.length) {
          lines.push(`${prefix}len  ${info.length}`);
        }
      } else {
        const info = readImageInfo(index);
        if (info) {
          lines.push(`${prefix}${info.naturalWidth}x${info.naturalHeight}  disp ${info.displayedWidth}x${info.displayedHeight}`);
          lines.push(`${prefix}fmt  ${info.format || '--'}`);
          lines.push(`${prefix}size  ${formatMiB(info.bytes)}`);
          lines.push(`${prefix}zoom  ${scale.toFixed(2)}x`);
        } else {
          lines.push(`${prefix}zoom  ${scale.toFixed(2)}x`);
        }
      }
    });

    return lines;
  }, [
    mediaInfoEnabled,
    mediaInfoTick,
    pages,
    currentPage,
    readingMode,
    doublePageMode,
    splitCoverMode,
    cachedPages,
    htmlContents,
    scale,
    isFullscreen,
  ]);

  // 监听页码变化并更新进度
  useEffect(() => {
    if (pages.length > 0 && currentPage >= 0) {
      // 清除之前的定时器
      if (imageLoadTimeoutRef.current) {
        clearTimeout(imageLoadTimeoutRef.current);
      }

      // 防抖：延迟500ms更新，避免频繁调用
      imageLoadTimeoutRef.current = setTimeout(() => {
        updateReadingProgress(currentPage);
      }, 500);

      return () => {
        if (imageLoadTimeoutRef.current) {
          clearTimeout(imageLoadTimeoutRef.current);
        }
      };
    }
  }, [currentPage, pages.length, updateReadingProgress]);

  // 组件卸载时保存进度
  useEffect(() => {
    return () => {
      if (pages.length > 0 && currentPageRef.current >= 0) {
        updateReadingProgress(currentPageRef.current);
      }
    };
  }, [pages.length, updateReadingProgress]);

  // 跟踪currentPage的变化并更新ref
  useEffect(() => {
    currentPageRef.current = currentPage;
  }, [currentPage]);

  // 加载HTML页面内容（单页模式：当前页；条漫模式：可见范围内）
  useEffect(() => {
    if (!id || pages.length === 0) return;

    if (readingMode === 'webtoon') {
      for (let i = visibleRange.start; i <= visibleRange.end; i += 1) {
        if (pages[i]?.type === 'html') {
          void loadHtmlPage(i);
        }
      }
      return;
    }

    if (currentPage >= 0 && currentPage < pages.length && pages[currentPage]?.type === 'html') {
      void loadHtmlPage(currentPage);
    }
  }, [id, pages, currentPage, readingMode, visibleRange, loadHtmlPage]);

  // 自动隐藏工具栏逻辑
  // - 显示条件：仅点击/轻触
  // - 隐藏条件：点击（切换）、滑动（触摸移动后抬起）、或显示后一段时间
  useEffect(() => {
    clearAutoHideTimers();

    if (!autoHideEnabled) {
      setShowToolbar(true);
      return;
    }

    if (showToolbar) {
      scheduleAutoHide();
    }

    return () => {
      clearAutoHideTimers();
    };
  }, [autoHideEnabled, showToolbar, scheduleAutoHide, clearAutoHideTimers]);

  // 重置变换
  const resetTransform = useCallback(() => {
    setScale(1);
    setTranslateX(0);
    setTranslateY(0);
  }, []);

  const handleSliderChangePage = useCallback(
    (newPage: number) => {
      setCurrentPage(newPage);
      resetTransform();

      if (readingMode === 'webtoon' && webtoonContainerRef.current) {
        let accumulatedHeight = 0;
        for (let i = 0; i < newPage; i++) {
          const imageHeight = imageHeights[i] || containerHeight || window.innerHeight * 0.7;
          accumulatedHeight += imageHeight;
        }
        webtoonContainerRef.current.scrollTop = accumulatedHeight;
      }
    },
    [resetTransform, readingMode, imageHeights, containerHeight]
  );

  // 处理双击放大
  const handleDoubleClick = useCallback((e: React.MouseEvent) => {
    if (!doubleTapZoom) return;
    
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
  }, [doubleTapZoom, scale, resetTransform, doublePageMode]);

  // 处理图片拖拽开始
  const handleImageDragStart = useCallback((e: React.DragEvent) => {
    e.preventDefault();
  }, []);

  const handlePrevPage = useCallback(() => {
    if (currentPage > 0) {
      if (doublePageMode && splitCoverMode) {
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
  }, [currentPage, resetTransform, doublePageMode, splitCoverMode]);

  const handleNextPage = useCallback(() => {
    if (currentPage < pages.length - 1) {
      if (doublePageMode && splitCoverMode) {
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
  }, [currentPage, pages.length, resetTransform, doublePageMode, splitCoverMode]);

  const runTapTurnAction = useCallback((action: 'prev' | 'next') => {
    if (autoHideEnabled && showToolbar) {
      hideToolbar();
    }

    // 条漫模式下需要滚动到对应位置，仅更新 currentPage 不足以产生可见变化
    if (readingMode === 'webtoon' && webtoonContainerRef.current) {
      const nextPage =
        action === 'prev'
          ? Math.max(0, currentPage - 1)
          : Math.min(pages.length - 1, currentPage + 1);

      setCurrentPage(nextPage);

      requestAnimationFrame(() => {
        if (!webtoonContainerRef.current) return;
        let accumulatedHeight = 0;
        for (let i = 0; i < nextPage; i++) {
          accumulatedHeight += imageHeights[i] || containerHeight || window.innerHeight * 0.7;
        }
        webtoonContainerRef.current.scrollTop = accumulatedHeight;
      });

      return;
    }

    if (action === 'prev') {
      handlePrevPage();
    } else {
      handleNextPage();
    }
  }, [
    autoHideEnabled,
    showToolbar,
    hideToolbar,
    readingMode,
    currentPage,
    pages.length,
    imageHeights,
    containerHeight,
    handlePrevPage,
    handleNextPage,
  ]);

  // 侧边栏页面选择处理
  const handleSidebarPageSelect = useCallback((pageIndex: number) => {
    setCurrentPage(pageIndex);
    resetTransform();

    // 移动端选择页面后自动关闭侧边栏
    if (typeof window !== 'undefined' && window.innerWidth < 768) {
      setSidebarOpen(false);
    }
  }, [resetTransform]);

  const handleSidebarThumbLoaded = useCallback((pageIndex: number) => {
    setSidebarImagesLoading((prev) => {
      const next = new Set(prev);
      next.delete(pageIndex);
      return next;
    });
  }, []);

  const handleSidebarThumbError = useCallback((pageIndex: number) => {
    setSidebarImagesLoading((prev) => {
      const next = new Set(prev);
      next.delete(pageIndex);
      return next;
    });
  }, []);

  // 加载更多侧边栏页面
  const handleLoadMoreSidebarPages = useCallback(() => {
    // 保存当前滚动位置
    const scrollElement = sidebarScrollRef.current;
    const scrollTop = scrollElement?.scrollTop || 0;

    setSidebarLoading(true);
    const newCount = sidebarLoadedCount + 10;

    // 直接追加新页面到现有数组
    const newPages = pages.slice(sidebarLoadedCount, newCount);
    setSidebarDisplayPages(prev => [...prev, ...newPages]);

    setSidebarLoadedCount(newCount);
    setSidebarLoading(false);

    // 使用requestAnimationFrame在DOM更新后恢复滚动位置
    // 确保与静态导出环境兼容
    requestAnimationFrame(() => {
      if (scrollElement) {
        scrollElement.scrollTop = scrollTop;
      }
    });
  }, [pages, sidebarLoadedCount]);

  const handleImageError = useCallback((pageIndex: number) => {
    setImagesLoading(prev => {
      const newSet = new Set(prev);
      newSet.delete(pageIndex);
      return newSet;
    });
  }, []);

  // 缓存图片 - 简化为直接使用原始 URL
  const cacheImage = useCallback(async (url: string, index: number) => {
    // 直接使用原始 URL，浏览器会自动处理缓存
    setCachedPages(prev => {
      const newCachedPages = [...prev];
      newCachedPages[index] = url;
      return newCachedPages;
    });
  }, []);

  const handleImageLoad = useCallback((pageIndex: number, imgElement?: HTMLImageElement) => {
    // 原子性地更新两个状态，避免中间状态导致白屏
    setImagesLoading(prev => {
      const newSet = new Set(prev);
      newSet.delete(pageIndex);
      return newSet;
    });
    setLoadedImages(prev => {
      const newSet = new Set(prev);
      newSet.add(pageIndex);
      return newSet;
    });

    // 如果是条漫模式且提供了图片元素，记录图片高度
    if (readingMode === 'webtoon' && imgElement) {
      const imageHeight = getImageHeight(imgElement.naturalWidth, imgElement.naturalHeight);

      setImageHeights(prev => {
        const newHeights = [...prev];
        newHeights[pageIndex] = imageHeight;
        return newHeights;
      });

      // 预加载相邻图片 - 只添加加载队列，不直接调用缓存
      const preloadAdjacent = (index: number) => {
        // 预加载前一张和后一张图片
        [index - 1, index + 1].forEach(adjacentIndex => {
          if (adjacentIndex >= 0 && adjacentIndex < pages.length && !loadedImages.has(adjacentIndex) && !imagesLoading.has(adjacentIndex)) {
            setImagesLoading(prev => {
              const updated = new Set(prev);
              updated.add(adjacentIndex);
              return updated;
            });
            // 不在这里调用 cacheImage，避免重复缓存
            // 缓存逻辑由 useEffect 统一管理
          }
        });
      };

      // 延迟预加载，避免影响当前图片加载
      setTimeout(() => preloadAdjacent(pageIndex), 100);
    }
  }, [readingMode, loadedImages, imagesLoading, pages, getImageHeight]); // 移除 cacheImage 依赖

  // 计算可见范围的函数
  const calculateVisibleRange = useCallback((scrollTop: number, containerHeight: number) => {
    if (pages.length === 0 || imageHeights.length === 0) {
      return { start: 0, end: Math.min(2, pages.length - 1) };
    }

    let accumulatedHeight = 0;
    let startIndex = 0;
    let endIndex = pages.length - 1;
    const bufferHeight = containerHeight * 3; // 增加缓冲区到3倍屏幕高度，确保快速滚动时不漏

    // 条漫模式：所有页面都参与计算（包含HTML页）
    for (let i = 0; i < pages.length; i++) {
      const imageHeight = imageHeights[i] || containerHeight || window.innerHeight * 0.7;

      if (accumulatedHeight + imageHeight > scrollTop - bufferHeight) {
        startIndex = Math.max(0, i - 4); // 增加前置缓冲
        break;
      }
      accumulatedHeight += imageHeight;
    }

    // 找到结束索引
    accumulatedHeight = 0;
    for (let i = 0; i < pages.length; i++) {
      const imageHeight = imageHeights[i] || containerHeight || window.innerHeight * 0.7;

      accumulatedHeight += imageHeight;
      if (accumulatedHeight > scrollTop + containerHeight + bufferHeight) {
        endIndex = Math.min(pages.length - 1, i + 4); // 增加后置缓冲
        break;
      }
    }

    // 确保范围有效且合理
    startIndex = Math.max(0, startIndex);
    endIndex = Math.min(pages.length - 1, endIndex);

    // 确保至少显示3页，除非总页数不足
    if (endIndex - startIndex < 2 && pages.length > 2) {
      const center = Math.floor((startIndex + endIndex) / 2);
      startIndex = Math.max(0, center - 1);
      endIndex = Math.min(pages.length - 1, center + 1);
    }

    return { start: startIndex, end: endIndex };
  }, [pages.length, imageHeights]);

  const handleWebtoonScroll = useCallback(
    (e: React.UIEvent<HTMLDivElement>) => {
      const container = e.currentTarget;

      if (scrollTimeoutRef.current) {
        clearTimeout(scrollTimeoutRef.current);
      }

      scrollTimeoutRef.current = setTimeout(() => {
        let accumulatedHeight = 0;
        let newPageIndex = 0;

        for (let i = 0; i < pages.length; i++) {
          const imageHeight = imageHeights[i] || containerHeight || window.innerHeight * 0.7;
          accumulatedHeight += imageHeight;
          if (accumulatedHeight > container.scrollTop + container.clientHeight * 0.3) {
            newPageIndex = i;
            break;
          }
        }

        if (newPageIndex !== currentPage && newPageIndex >= 0 && newPageIndex < pages.length) {
          setCurrentPage(newPageIndex);
        }

        const newVisibleRange = calculateVisibleRange(container.scrollTop, container.clientHeight);
        setVisibleRange(newVisibleRange);
        setContainerHeight(container.clientHeight);
      }, 16);
    },
    [calculateVisibleRange, containerHeight, currentPage, imageHeights, pages.length]
  );

  // 条漫模式下测量HTML页高度，避免HTML页内部滚动/高度不准导致的滚动计算错误
  useEffect(() => {
    if (readingMode !== 'webtoon') return;

    requestAnimationFrame(() => {
      for (let i = visibleRange.start; i <= visibleRange.end; i += 1) {
        if (pages[i]?.type !== 'html') continue;
        const el = webtoonPageElementRefs.current[i];
        if (!el) continue;
        const measured = Math.ceil(el.getBoundingClientRect().height);
        if (!measured || measured <= 0) continue;

        setImageHeights(prev => {
          const current = prev[i];
          if (current && Math.abs(current - measured) <= 2) return prev;
          const next = [...prev];
          next[i] = measured;
          return next;
        });
      }
    });
  }, [readingMode, visibleRange, pages, htmlContents]);

  const handleKeyDown = useCallback((e: KeyboardEvent) => {
    if (e.target instanceof HTMLInputElement) return;
    
    switch (e.key) {
      case 'ArrowLeft':
        if (readingMode === 'single-rtl') {
          handleNextPage();
        } else if (readingMode !== 'webtoon') {
          handlePrevPage();
        }
        break;
      case 'ArrowRight':
        if (readingMode === 'single-rtl') {
          handlePrevPage();
        } else if (readingMode !== 'webtoon') {
          handleNextPage();
        }
        break;
      case 'ArrowUp':
        if (readingMode === 'single-ttb') {
          handlePrevPage();
        }
        break;
      case 'ArrowDown':
        if (readingMode === 'single-ttb') {
          handleNextPage();
        }
        break;
    }
  }, [handlePrevPage, handleNextPage, readingMode]);

  useEffect(() => {
    window.addEventListener('keydown', handleKeyDown);
    return () => {
      window.removeEventListener('keydown', handleKeyDown);
    };
  }, [handleKeyDown]);

  const handleWheel = useCallback((e: WheelEvent) => {
    if (e.target instanceof HTMLInputElement) return;

    // 隐藏条件：滑动/滚动
    if (autoHideEnabled && showToolbar) {
      hideToolbar();
    }

    // 条漫模式下仅允许自然滚动，不触发HTML边界倒计时跳转
    if (readingMode === 'webtoon') {
      if (showAutoNextCountdown) {
        clearCountdown();
      }
      return;
    }

    // 检查当前页面是否为HTML类型
    const isHtmlPage = pages[currentPage]?.type === 'html';

    // 如果是HTML页面，允许内容自然滚动，只在边界处翻页
    if (isHtmlPage) {
      const target = e.target as HTMLElement;
      // 检查事件是否来自HTML内容容器或其子元素
      const htmlContainer = target.closest('.html-content-container');

      if (htmlContainer) {
        // 获取滚动位置
        const scrollTop = htmlContainer.scrollTop;
        const scrollHeight = htmlContainer.scrollHeight;
        const clientHeight = htmlContainer.clientHeight;
        const isAtTop = scrollTop <= 5; // 允许5px的误差
        const isNearTop = scrollTop <= 150; // 接近顶部时开始倒计时
        const isNearBottom = scrollTop >= scrollHeight - clientHeight - 150; // 提前150px开始倒计时
        const isAtBottom = scrollTop >= scrollHeight - clientHeight - 5;

        const deltaY = e.deltaY;

        // 如果正在显示倒计时，阻止滚动并处理倒计时逻辑
        if (showAutoNextCountdown) {
          e.preventDefault();
          if (isAtTop && deltaY < 0) {
            // 倒计时结束后自动跳转
            // 不需要手动处理，倒计时会自动执行
          } else if (isAtBottom && deltaY > 0) {
            // 倒计时结束后自动跳转
            // 不需要手动处理，倒计时会自动执行
          } else {
            // 其他滚动行为，取消倒计时
            clearCountdown();
          }
          return;
        }

        // 在顶部向上滚动 -> 上一页（跳转到上一页底部，显示倒计时）
        // 在底部向下滚动 -> 下一页（跳转到下一页顶部，显示倒计时）
        // 其他情况允许自然滚动
        if (isNearTop && deltaY < 0) {
          // 接近顶部时，开始倒计时
          e.preventDefault();
          if (!showAutoNextCountdown) {
            setShowAutoNextCountdown(true);
            setCountdownSeconds(COUNTDOWN_DURATION);

            // 显示 toast
            countdownToastId.current = toast.loading(`即将跳转到上一页（${COUNTDOWN_DURATION}秒后）`, {
              duration: COUNTDOWN_DURATION * 1000,
              action: {
                label: '取消',
                onClick: () => clearCountdown(),
              },
            });

            // 开始倒计时
            countdownTimeoutRef.current = setInterval(() => {
              setCountdownSeconds(prev => {
                if (prev <= 1) {
                  // 倒计时结束，执行跳转
                  clearCountdown();
                  handlePrevPage();
                  setTimeout(() => {
                    const htmlContainer = document.querySelector('.html-content-container');
                    if (htmlContainer) {
                      htmlContainer.scrollTop = htmlContainer.scrollHeight;
                    }
                  }, 100);
                  return 0;
                }
                // 更新 toast 消息
                if (countdownToastId.current !== null) {
                  toast.loading(`即将跳转到上一页（${prev - 1}秒后）`, {
                    id: countdownToastId.current,
                    duration: (prev - 1) * 1000,
                    action: {
                      label: '取消',
                      onClick: () => clearCountdown(),
                    },
                  });
                }
                return prev - 1;
              });
            }, 1000);
          }
        } else if (isNearBottom && deltaY > 0) {
          // 接近底部时，开始倒计时
          e.preventDefault();
          if (!showAutoNextCountdown) {
            setShowAutoNextCountdown(true);
            setCountdownSeconds(COUNTDOWN_DURATION);

            // 显示 toast
            countdownToastId.current = toast.loading(`即将跳转到下一页（${COUNTDOWN_DURATION}秒后）`, {
              duration: COUNTDOWN_DURATION * 1000,
              action: {
                label: '取消',
                onClick: () => clearCountdown(),
              },
            });

            // 开始倒计时
            countdownTimeoutRef.current = setInterval(() => {
              setCountdownSeconds(prev => {
                if (prev <= 1) {
                  // 倒计时结束，执行跳转
                  clearCountdown();
                  handleNextPage();
                  setTimeout(() => {
                    const htmlContainer = document.querySelector('.html-content-container');
                    if (htmlContainer) {
                      htmlContainer.scrollTop = 0;
                    }
                  }, 100);
                  return 0;
                }
                // 更新 toast 消息
                if (countdownToastId.current !== null) {
                  toast.loading(`即将跳转到下一页（${prev - 1}秒后）`, {
                    id: countdownToastId.current,
                    duration: (prev - 1) * 1000,
                    action: {
                      label: '取消',
                      onClick: () => clearCountdown(),
                    },
                  });
                }
                return prev - 1;
              });
            }, 1000);
          }
        }
        // 其他情况不阻止默认行为，让HTML内容自然滚动
        return;
      }
    }

    // 非HTML页面的滚轮处理逻辑
    const deltaX = e.deltaX;
    const deltaY = e.deltaY;

    if (readingMode === 'single-rtl') {
      if (deltaX > 0 || deltaY > 0) {
        handlePrevPage();
      } else if (deltaX < 0 || deltaY < 0) {
        handleNextPage();
      }
    } else if (readingMode === 'single-ttb') {
      if (deltaY > 0) {
        handleNextPage();
      } else if (deltaY < 0) {
        handlePrevPage();
      }
    } else {
      if (deltaX > 0 || deltaY > 0) {
        handleNextPage();
      } else if (deltaX < 0 || deltaY < 0) {
        handlePrevPage();
      }
    }
  }, [
    handlePrevPage,
    handleNextPage,
    readingMode,
    pages,
    currentPage,
    showAutoNextCountdown,
    clearCountdown,
    autoHideEnabled,
    showToolbar,
    hideToolbar,
  ]);

  useEffect(() => {
    window.addEventListener('wheel', handleWheel);
    return () => {
      window.removeEventListener('wheel', handleWheel);
    };
  }, [handleWheel]);

  useEffect(() => {
    if (readingMode === 'webtoon' && showAutoNextCountdown) {
      clearCountdown();
    }
  }, [readingMode, showAutoNextCountdown, clearCountdown]);

  // 计算两点距离
  const getDistance = (touch1: Touch, touch2: Touch) => {
    const dx = touch1.clientX - touch2.clientX;
    const dy = touch1.clientY - touch2.clientY;
    return Math.sqrt(dx * dx + dy * dy);
  };

  // 触摸开始
  const handleTouchStart = useCallback((e: React.TouchEvent) => {
    lastTouchAtRef.current = Date.now();

    if (e.touches.length === 1) {
      tapStartRef.current = {
        x: e.touches[0].clientX,
        y: e.touches[0].clientY,
        time: Date.now(),
      };
      tapMovedRef.current = false;
    } else {
      tapStartRef.current = null;
      tapMovedRef.current = true;
    }

    // 条漫模式下不阻止默认行为，让页面可以自然滚动
    if (readingMode === 'webtoon') return;

    if (e.touches.length === 1) {
      setTouchEnd(null);
      setTouchStart({ x: e.touches[0].clientX, y: e.touches[0].clientY });
    } else if (e.touches.length === 2) {
      // 双指缩放
      const distance = getDistance(e.touches[0] as Touch, e.touches[1] as Touch);
      setLastTouchDistance(distance);
      setTouchStart(null);
    }
  }, [readingMode]);

  // 触摸移动
  const handleTouchMove = useCallback((e: React.TouchEvent) => {
    lastTouchAtRef.current = Date.now();

    if (e.touches.length === 1 && tapStartRef.current) {
      const dx = e.touches[0].clientX - tapStartRef.current.x;
      const dy = e.touches[0].clientY - tapStartRef.current.y;
      if (Math.abs(dx) > TAP_MOVE_THRESHOLD_PX || Math.abs(dy) > TAP_MOVE_THRESHOLD_PX) {
        tapMovedRef.current = true;
      }
    } else if (e.touches.length > 1) {
      tapMovedRef.current = true;
    }

    // 条漫模式下不阻止默认行为，让页面可以自然滚动
    if (readingMode === 'webtoon') return;

    if (e.touches.length === 1 && touchStart) {
      setTouchEnd({ x: e.touches[0].clientX, y: e.touches[0].clientY });
    } else if (e.touches.length === 2) {
      // 双指缩放
      e.preventDefault();
      const distance = getDistance(e.touches[0] as Touch, e.touches[1] as Touch);
      if (lastTouchDistance > 0) {
        const scaleChange = distance / lastTouchDistance;
        setScale(prev => Math.min(Math.max(prev * scaleChange, 0.5), 3));
      }
      setLastTouchDistance(distance);
    }
  }, [touchStart, lastTouchDistance, readingMode]);

  // 触摸结束
  const handleTouchEnd = useCallback((e: React.TouchEvent) => {
    lastTouchAtRef.current = Date.now();

    const start = tapStartRef.current;
    const now = Date.now();
    const duration = start ? now - start.time : Infinity;
    const endTouch = e.changedTouches?.[0];
    const movedByEnd =
      Boolean(start && endTouch) &&
      (Math.abs(endTouch.clientX - start!.x) > TAP_MOVE_THRESHOLD_PX ||
        Math.abs(endTouch.clientY - start!.y) > TAP_MOVE_THRESHOLD_PX);
    const moved = tapMovedRef.current || movedByEnd;
    const isTap = Boolean(start && !moved && duration <= TAP_MAX_DURATION_MS);

    if (isTap) {
      // HTML内容区域内的点击交给内容自身处理（链接、选择等）
      if (isHtmlContentTarget(e.target) || isInteractiveTarget(e.target)) {
        tapStartRef.current = null;
        tapMovedRef.current = false;
        return;
      }

      if (tapTurnPageEnabled && endTouch) {
        const action = getTapTurnAction(endTouch.clientX, endTouch.clientY);
        if (action === 'prev' || action === 'next') {
          runTapTurnAction(action);
          tapStartRef.current = null;
          tapMovedRef.current = false;
          setTouchStart(null);
          setTouchEnd(null);
          setLastTouchDistance(0);
          return;
        }
      }

      toggleToolbar();
      tapStartRef.current = null;
      tapMovedRef.current = false;
      setTouchStart(null);
      setTouchEnd(null);
      setLastTouchDistance(0);
      return;
    }

    // 滑动结束：如果工具栏当前可见，立即隐藏
    if (autoHideEnabled && showToolbar && moved) {
      hideToolbar();
    }

    tapStartRef.current = null;
    tapMovedRef.current = false;

    if (!touchStart || !touchEnd) {
      setLastTouchDistance(0);
      return;
    }
    
    // 条漫模式下不处理滑动手势，让页面自然滚动
    if (readingMode === 'webtoon') {
      setTouchStart(null);
      setTouchEnd(null);
      setLastTouchDistance(0);
      return;
    }
    
    const deltaX = touchStart.x - touchEnd.x;
    const deltaY = touchStart.y - touchEnd.y;
    const isHorizontalSwipe = Math.abs(deltaX) > Math.abs(deltaY);
    const isSwipe = Math.abs(deltaX) > 50 || Math.abs(deltaY) > 50;
    
    if (isSwipe) {
      if (isHorizontalSwipe) {
        // 水平滑动
        if (readingMode === 'single-rtl') {
          if (deltaX > 50) {
            handlePrevPage();
          } else if (deltaX < -50) {
            handleNextPage();
          }
        } else {
          if (deltaX > 50) {
            handleNextPage();
          } else if (deltaX < -50) {
            handlePrevPage();
          }
        }
      } else {
        // 垂直滑动
        if (readingMode === 'single-ttb') {
          if (deltaY > 50) {
            handleNextPage();
          } else if (deltaY < -50) {
            handlePrevPage();
          }
        }
      }
    }
    
    setTouchStart(null);
    setTouchEnd(null);
    setLastTouchDistance(0);
  }, [
    touchStart,
    touchEnd,
    handleNextPage,
    handlePrevPage,
    readingMode,
    toggleToolbar,
    autoHideEnabled,
    showToolbar,
    hideToolbar,
    isHtmlContentTarget,
    isInteractiveTarget,
    tapTurnPageEnabled,
    getTapTurnAction,
    runTapTurnAction,
  ]);

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

  // 初始化图片高度数组和容器高度
  useEffect(() => {
    if (pages.length > 0 && imageHeights.length !== pages.length) {
      // 使用更合理的默认高度初始化数组
      const { containerWidth } = getDeviceInfo();
      const defaultHeight = Math.min(window.innerHeight * 0.7, containerWidth * 1.5);
      setImageHeights(new Array(pages.length).fill(defaultHeight));
      
      // 设置初始容器高度
      const viewportHeight = window.innerHeight - 100; // 优化工具栏高度计算
      setContainerHeight(viewportHeight);
      
      // 设置初始可见范围
      setVisibleRange({ start: 0, end: Math.min(3, pages.length - 1) }); // 增加初始渲染范围
    }
  }, [pages.length, imageHeights.length, getDeviceInfo]);

  // 自动翻页定时器
  useEffect(() => {
    let intervalId: NodeJS.Timeout | null = null;
    
    if (autoPlayMode && pages.length > 0) {
      // 设置定时器
      intervalId = setInterval(() => {
        if (readingMode === 'webtoon') {
          // 条漫模式：自动滚动
          if (webtoonContainerRef.current) {
            const container = webtoonContainerRef.current;
            const currentScrollTop = container.scrollTop;
            const containerHeight = container.clientHeight;
            const scrollHeight = container.scrollHeight;
            
            // 检查是否到达底部
            if (currentScrollTop + containerHeight >= scrollHeight - 10) {
              // 到达底部，停止自动翻页
              setAutoPlayMode(false);
              return;
            }
            
            // 计算下一张图片的位置
            let accumulatedHeight = 0;
            let nextImagePosition = 0;
            
            for (let i = 0; i < imageHeights.length; i++) {
              const imageHeight = imageHeights[i] || containerHeight;
              accumulatedHeight += imageHeight;
              
              // 找到当前可见图片的下一张图片位置
              if (accumulatedHeight > currentScrollTop + containerHeight * 0.3) {
                nextImagePosition = accumulatedHeight - imageHeight;
                break;
              }
            }
            
            // 滚动到下一张图片
            container.scrollTo({
              top: nextImagePosition + containerHeight * 0.7,
              behavior: 'smooth'
            });
          }
        } else {
          // 单页/双页模式：检查是否到达最后一页
          if (doublePageMode) {
            // 双页模式：检查是否到达最后两页
            if (currentPage >= pages.length - (splitCoverMode && currentPage === 0 ? 1 : 2)) {
              // 到达最后一页，停止自动翻页
              setAutoPlayMode(false);
              return;
            }
          } else {
            // 单页模式：检查是否到达最后一页
            if (currentPage >= pages.length - 1) {
              // 到达最后一页，停止自动翻页
              setAutoPlayMode(false);
              return;
            }
          }
          
          // 执行翻页
          handleNextPage();
        }
      }, autoPlayInterval * 1000); // 转换为毫秒
    }
    
    // 清理函数
    return () => {
      if (intervalId) {
        clearInterval(intervalId);
      }
    };
  }, [autoPlayMode, autoPlayInterval, currentPage, pages.length, doublePageMode, splitCoverMode, handleNextPage, readingMode, imageHeights, setAutoPlayMode]);

  // 处理拆分封面模式切换时的页面调整
  useEffect(() => {
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
  }, [splitCoverMode, doublePageMode, currentPage, pages.length]);

  // 合并的图片加载逻辑 - 优化性能和减少重复执行
  useEffect(() => {
    if (pages.length === 0) return;

    if (readingMode === 'webtoon') {
      // 条漫模式：预加载当前页面前后的几页（如果还未加载）
      const preloadRange = 2;
      setImagesLoading(prev => {
        const updated = new Set(prev);

        // 添加当前页面及前后页面到加载队列
        for (let i = Math.max(0, currentPage - preloadRange); i <= Math.min(pages.length - 1, currentPage + preloadRange); i++) {
          if (!loadedImages.has(i)) {
            updated.add(i);
          }
        }

        // 确保可见范围内的页面在加载列表中
        for (let i = visibleRange.start; i <= visibleRange.end; i++) {
          if (i >= 0 && i < pages.length && !loadedImages.has(i)) {
            updated.add(i);
          }
        }

        return updated;
      });
    } else {
      // 单页/双页模式：预加载前1页和后5页
      setImagesLoading(prev => {
        const updated = new Set(prev);

        // 预加载范围：前1页，后5页
        const preloadBefore = 1;
        const preloadAfter = 5;

        for (let i = Math.max(0, currentPage - preloadBefore);
             i <= Math.min(pages.length - 1, currentPage + preloadAfter);
             i++) {
          if (!loadedImages.has(i)) {
            updated.add(i);
          }
        }

        return updated;
      });
    }
  }, [currentPage, readingMode, pages.length, loadedImages, visibleRange.start, visibleRange.end]);

  // 设置Intersection Observer用于懒加载
  useEffect(() => {
    if (readingMode === 'webtoon') {
      observerRef.current = new IntersectionObserver(
        (entries) => {
          entries.forEach(entry => {
            if (entry.isIntersecting) {
              const imgElement = entry.target as HTMLImageElement;
              const index = parseInt(imgElement.dataset.index || '0');

              // 观察所有图片
              if (!loadedImages.has(index) && !imagesLoading.has(index)) {
                setImagesLoading(prev => {
                  const updated = new Set(prev);
                  updated.add(index);
                  return updated;
                });

                // 预加载相邻图片
                [index - 1, index + 1].forEach(adjacentIndex => {
                  if (adjacentIndex >= 0 && adjacentIndex < pages.length && !loadedImages.has(adjacentIndex) && !imagesLoading.has(adjacentIndex)) {
                    setImagesLoading(prev => {
                      const updated = new Set(prev);
                      updated.add(adjacentIndex);
                      return updated;
                    });
                  }
                });
              }

              // 加载后停止观察该元素
              observerRef.current?.unobserve(imgElement);
            }
          });
        },
        {
          rootMargin: '2000px 0px 2000px 0px' // 增加预加载距离到2000px，优化快速滚动体验
        }
      );

      // 观察可见范围内的图片元素
      imageRefs.current.forEach((img, index) => {
        if (img && index >= visibleRange.start && index <= visibleRange.end) {
          img.dataset.index = index.toString();
          observerRef.current?.observe(img);
        }
      });
    }

    return () => {
      observerRef.current?.disconnect();
    };
  }, [readingMode, imagesLoading, visibleRange, loadedImages, pages.length]);

  // 清理防抖定时器
  useEffect(() => {
    return () => {
      if (scrollTimeoutRef.current) {
        clearTimeout(scrollTimeoutRef.current);
      }
    };
  }, []);

  // 处理已经加载完成的图片
  useEffect(() => {
    if (readingMode === 'webtoon') {
      imageRefs.current.forEach((img, index) => {
        if (img && img.complete && img.naturalHeight > 0 && !imageHeights[index]) {
          // 如果图片已经加载完成但还没有记录高度，计算高度
          const imageHeight = getImageHeight(img.naturalWidth, img.naturalHeight);
          
          setImageHeights(prev => {
            const newHeights = [...prev];
            newHeights[index] = imageHeight;
            return newHeights;
          });
        }
      });
    }
  }, [readingMode, imageHeights, getImageHeight]);

  // 组件卸载时清理倒计时定时器
  useEffect(() => {
    return () => {
      clearCountdown();
    };
  }, [clearCountdown]);

  if (loading) {
    return (
      <div className="min-h-screen bg-black text-white flex items-center justify-center">
        <div className="text-center">
          <p className="text-lg">{t('common.loading')}</p>
        </div>
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
        showToolbar={showToolbar}
        archiveTitle={archiveTitle}
        onBack={handleBack}
        onToggleSidebar={() => setSidebarOpen((prev) => !prev)}
        onToggleReadingMode={toggleReadingMode}
        readingModeIcon={getReadingModeIcon()}
        readingModeText={getReadingModeText()}
        t={t}
      />

      <ReaderFloatingControls
        showToolbar={showToolbar}
        currentPage={currentPage}
        totalPages={pages.length}
        onChangePage={handleSliderChangePage}
        settingsOpen={settingsOpen}
        onSettingsOpenChange={setSettingsOpen}
        archiveTitle={archiveTitle}
        archiveMetadata={archiveMetadata}
        metadataTags={metadataTags}
        id={id}
        onNavigateToArchive={handleNavigateToArchiveFromSettings}
        settingButtons={settingButtons}
        autoPlayMode={autoPlayMode}
        autoPlayInterval={autoPlayInterval}
        onAutoPlayIntervalChange={setAutoPlayInterval}
        isFavorited={isFavorited}
        onToggleFavorite={toggleFavorite}
        t={t}
      />

      {/* 主要阅读区域 */}
      <div
        ref={readerAreaRef}
        className="flex-1 relative overflow-hidden"
        onTouchStart={handleTouchStart}
        onTouchMove={handleTouchMove}
        onTouchEnd={handleTouchEnd}
        onClick={(e) => {
          // HTML内容/交互元素的点击交给内容自身处理
          if (isHtmlContentTarget(e.target) || isInteractiveTarget(e.target)) return;

          // 显示条件只有点击：触摸后的合成 click 一律忽略（避免滑动触发）
          if (Date.now() - lastTouchAtRef.current < IGNORE_CLICK_AFTER_TOUCH_MS) return;

          if (tapTurnPageEnabled) {
            const action = getTapTurnAction(e.clientX, e.clientY);
            if (action === 'prev' || action === 'next') {
              runTapTurnAction(action);
              return;
            }
          }

          toggleToolbar();
        }}
      >
        {mediaInfoEnabled ? (
          <MediaInfoOverlay lines={mediaInfoOverlayLines} sidebarOpen={sidebarOpen} />
        ) : null}

        {/* 侧边栏导航 */}
        <ReaderSidebar
          open={sidebarOpen}
          sidebarScrollRef={sidebarScrollRef}
          sidebarLoading={sidebarLoading}
          isEpub={isEpub}
          sidebarDisplayPages={sidebarDisplayPages}
          currentPage={currentPage}
          sidebarImagesLoading={sidebarImagesLoading}
          pagesLength={pages.length}
          canLoadMore={sidebarLoadedCount < pages.length}
          onSelectPage={handleSidebarPageSelect}
          onLoadMore={handleLoadMoreSidebarPages}
          onThumbLoaded={handleSidebarThumbLoaded}
          onThumbError={handleSidebarThumbError}
          t={t}
        />

        {/* 单页模式 */}
        <ReaderSingleModeView
          enabled={readingMode !== 'webtoon'}
          sidebarOpen={sidebarOpen}
          pages={pages}
          cachedPages={cachedPages}
          currentPage={currentPage}
          doublePageMode={doublePageMode}
          splitCoverMode={splitCoverMode}
          imagesLoading={imagesLoading}
          loadedImages={loadedImages}
          scale={scale}
          translateX={translateX}
          translateY={translateY}
          htmlContents={htmlContents}
          imageRefs={imageRefs}
          videoRefs={videoRefs}
          htmlContainerRefs={htmlContainerRefs}
          imageRequestUrls={imageRequestUrls}
          onImageLoaded={handleImageLoad}
          onImageError={handleImageError}
          onCacheImage={cacheImage}
          onDoubleClick={handleDoubleClick}
          onImageDragStart={handleImageDragStart}
          t={t}
        />

        {/* 隐藏的预加载区域：前1页和后5页（仅单页/双页模式） */}
        <ReaderPreloadArea
          enabled={readingMode !== 'webtoon'}
          imagesLoading={imagesLoading}
          currentPage={currentPage}
          doublePageMode={doublePageMode}
          pages={pages}
          cachedPages={cachedPages}
          onLoaded={handleImageLoad}
          onError={handleImageError}
          onCacheImage={cacheImage}
        />

        {/* 条漫模式 */}
        <ReaderWebtoonModeView
          enabled={readingMode === 'webtoon'}
          webtoonContainerRef={webtoonContainerRef}
          sidebarOpen={sidebarOpen}
          onScroll={handleWebtoonScroll}
          pages={pages}
          cachedPages={cachedPages}
          visibleRange={visibleRange}
          imageHeights={imageHeights}
          containerHeight={containerHeight}
          imagesLoading={imagesLoading}
          loadedImages={loadedImages}
          scale={scale}
          translateX={translateX}
          translateY={translateY}
          htmlContents={htmlContents}
          webtoonPageElementRefs={webtoonPageElementRefs}
          imageRefs={imageRefs}
          videoRefs={videoRefs}
          htmlContainerRefs={htmlContainerRefs}
          imageRequestUrls={imageRequestUrls}
          onImageLoaded={handleImageLoad}
          onImageError={handleImageError}
          onCacheImage={cacheImage}
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
