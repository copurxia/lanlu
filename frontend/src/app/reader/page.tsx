'use client';

import { useSearchParams, useRouter } from 'next/navigation';
import { useState, useEffect, useCallback, useMemo, Suspense, useRef } from 'react';
import type React from 'react';
import { ArchiveService, PageInfo } from '@/lib/services/archive-service';
import { Button } from '@/components/ui/button';
import { useLanguage } from '@/contexts/LanguageContext';
import { MediaInfoOverlay } from '@/components/reader/components/MediaInfoOverlay';
import { ReaderFloatingControls } from '@/components/reader/components/ReaderFloatingControls';
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

  const [settingsOpen, setSettingsOpen] = useState(false);

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

  const webtoonVirtualization = useReaderWebtoonVirtualization({
    readingMode,
    pages,
    currentPage,
    setCurrentPage,
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

  const imageLoading = useReaderImageLoading({
    pages,
    readingMode,
    currentPage,
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
  }, [id, pageParam, setImagesLoading]);

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
  });

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
    currentPage,
    setCurrentPage: (page) => setCurrentPage(page),
    pagesLength: pages.length,
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
  });

  useReaderAutoPlay({
    autoPlayMode,
    autoPlayInterval,
    readingMode,
    webtoonContainerRef,
    imageHeights: webtoonVirtualization.imageHeights,
    currentPage,
    pagesLength: pages.length,
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
	        totalPages={pages.length}
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
 	          enabled={readingMode !== 'webtoon'}
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

        {/* 隐藏的预加载区域：前1页和后5页（仅单页/双页模式） */}
	        <ReaderPreloadArea
	          enabled={readingMode !== 'webtoon'}
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
	          cachedPages={imageLoading.cachedPages}
	          visibleRange={webtoonVirtualization.visibleRange}
	          imageHeights={webtoonVirtualization.imageHeights}
	          containerHeight={webtoonVirtualization.containerHeight}
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
