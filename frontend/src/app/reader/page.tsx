'use client';

import { useSearchParams } from 'next/navigation';
import { useState, useEffect, useCallback, Suspense, useRef, memo } from 'react';
import Image from 'next/image';
import { ArchiveService } from '@/lib/archive-service';
import { FavoriteService } from '@/lib/favorite-service';
import { Button } from '@/components/ui/button';
import { Spinner } from '@/components/ui/spinner';
import { Slider } from '@/components/ui/slider';
import { ThemeButton } from '@/components/theme/theme-toggle';
import { ReaderLanguageToggle } from '@/components/language/ReaderLanguageToggle';
import { ReaderLanguageProvider, useReaderLanguage } from '@/contexts/ReaderLanguageContext';
import { Popover, PopoverTrigger, PopoverContent } from '@/components/ui/popover';
import {
  ArrowLeft,
  Book,
  ArrowRight,
  ArrowDown,
  Heart,
  Settings,
  Layout,
  Play,
  Scissors,
  Maximize,
  Minimize
} from 'lucide-react';
import Link from 'next/link';

type ReadingMode = 'single-ltr' | 'single-rtl' | 'single-ttb' | 'webtoon';

// Memo化的图片组件，减少不必要的重渲染
const MemoizedImage = memo(Image, (prevProps, nextProps) => {
  return (
    prevProps.src === nextProps.src &&
    prevProps.fill === nextProps.fill &&
    prevProps.className === nextProps.className &&
    prevProps.style === nextProps.style
  );
});

MemoizedImage.displayName = 'MemoizedImage';

function ReaderContent() {
  const searchParams = useSearchParams();
  const id = searchParams?.get('id') ?? null;
  const { t } = useReaderLanguage();
  
  const [pages, setPages] = useState<string[]>([]);
  const [cachedPages, setCachedPages] = useState<string[]>([]);
  const [currentPage, setCurrentPage] = useState(0);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [readingMode, setReadingMode] = useState<ReadingMode>(() => {
    // 从localStorage读取保存的阅读模式
    if (typeof window !== 'undefined') {
      try {
        const savedMode = localStorage.getItem('reader-reading-mode');
        if (savedMode && ['single-ltr', 'single-rtl', 'single-ttb', 'webtoon'].includes(savedMode)) {
          return savedMode as ReadingMode;
        }
      } catch (e) {
        // 忽略localStorage访问错误
        console.warn('Failed to read reading mode from localStorage:', e);
      }
    }
    return 'single-ltr'; // 默认阅读模式
  });
  const [touchStart, setTouchStart] = useState<{ x: number; y: number } | null>(null);
  const [touchEnd, setTouchEnd] = useState<{ x: number; y: number } | null>(null);
  const [imagesLoading, setImagesLoading] = useState<Set<number>>(new Set());
  const [loadedImages, setLoadedImages] = useState<Set<number>>(new Set()); // 跟踪已加载的图片
  const [showToolbar, setShowToolbar] = useState(true);
  const [isFavorited, setIsFavorited] = useState(false); // 收藏状态
  const [scale, setScale] = useState(1);
  const [translateX, setTranslateX] = useState(0);
  const [translateY, setTranslateY] = useState(0);
  const [lastTouchDistance, setLastTouchDistance] = useState(0);
  const webtoonContainerRef = useRef<HTMLDivElement>(null);
  const imageRefs = useRef<(HTMLImageElement | null)[]>([]);
  const observerRef = useRef<IntersectionObserver | null>(null);
  const currentPageRef = useRef<number>(0); // 用于跟踪最新的currentPage值
  const [visibleRange, setVisibleRange] = useState({ start: 0, end: 2 }); // 可见范围
  const [imageHeights, setImageHeights] = useState<number[]>([]); // 存储每张图片的高度
  const [containerHeight, setContainerHeight] = useState(0); // 容器高度
  const imageLoadTimeoutRef = useRef<NodeJS.Timeout | null>(null); // 图片加载防抖引用
  const [doublePageMode, setDoublePageMode] = useState<boolean>(() => {
    // 从localStorage读取保存的双页拼合设置
    if (typeof window !== 'undefined') {
      try {
        const saved = localStorage.getItem('reader-double-page-mode');
        return saved === 'true';
      } catch (e) {
        console.warn('Failed to read double page mode from localStorage:', e);
      }
    }
    return false; // 默认关闭
  });
  const [autoPlayMode, setAutoPlayMode] = useState<boolean>(() => {
    // 从localStorage读取保存的自动翻页设置
    if (typeof window !== 'undefined') {
      try {
        const saved = localStorage.getItem('reader-auto-play-mode');
        return saved === 'true';
      } catch (e) {
        console.warn('Failed to read auto play mode from localStorage:', e);
      }
    }
    return false; // 默认关闭
  });
  const [splitCoverMode, setSplitCoverMode] = useState<boolean>(() => {
    // 从localStorage读取保存的拆分封面设置
    if (typeof window !== 'undefined') {
      try {
        const saved = localStorage.getItem('reader-split-cover-mode');
        return saved === 'true';
      } catch (e) {
        console.warn('Failed to read split cover mode from localStorage:', e);
      }
    }
    return false; // 默认关闭
  });
  const [isFullscreen, setIsFullscreen] = useState<boolean>(() => {
    // 从localStorage读取保存的全屏设置
    if (typeof window !== 'undefined') {
      try {
        const saved = localStorage.getItem('reader-fullscreen-mode');
        return saved === 'true';
      } catch (e) {
        console.warn('Failed to read fullscreen mode from localStorage:', e);
      }
    }
    return false; // 默认关闭
  });
  
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
        let initialPage = data.progress > 0 && data.progress < data.pages.length
          ? data.progress - 1 // API使用1-based页码，转换为0-based
          : 0;
        
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

        // 获取收藏状态
        try {
          const favorites = await FavoriteService.getFavorites();
          setIsFavorited(favorites.includes(id));
        } catch (favErr) {
          console.error('Failed to fetch favorite status:', favErr);
          // 收藏状态失败不影响阅读体验，静默处理
        }
      } catch (err) {
        console.error('Failed to fetch archive pages:', err);
        setError('Failed to fetch archive pages');
      } finally {
        setLoading(false);
      }
    }

    fetchPages();
  }, [id]);

  // 单独处理错误消息的翻译
  useEffect(() => {
    if (error === 'Missing archive ID') {
      setError(t('reader.missingId'));
    } else if (error === 'Failed to fetch archive pages') {
      setError(t('reader.fetchError'));
    }
  }, [error, t]);

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
      console.error('Failed to update reading progress:', err);
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
      console.error('Failed to toggle favorite:', err);
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
        console.error('Failed to enter fullscreen:', err);
      }
    } else {
      try {
        await document.exitFullscreen();
        setIsFullscreen(false);
        if (typeof window !== 'undefined') {
          localStorage.setItem('reader-fullscreen-mode', 'false');
        }
      } catch (err) {
        console.error('Failed to exit fullscreen:', err);
      }
    }
  }, []);

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
  }, []);

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

  // 自动隐藏工具栏功能已移除

  // 重置变换
  const resetTransform = useCallback(() => {
    setScale(1);
    setTranslateX(0);
    setTranslateY(0);
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
      // 优化PC端显示：为PC端设置更合适的宽度限制
      const isPC = window.innerWidth >= 1024; // PC屏幕判断
      const maxContainerWidth = isPC
        ? Math.min(800, window.innerWidth * 0.8) // PC端最大800px，或屏幕宽度的80%
        : Math.min(window.innerWidth * 0.95, 1200); // 移动端保持原逻辑

      const aspectRatio = imgElement.naturalHeight / imgElement.naturalWidth;
      const imageHeight = maxContainerWidth * aspectRatio;

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
  }, [readingMode, loadedImages, imagesLoading, pages]); // 移除 cacheImage 依赖

  // 计算可见范围的函数
  const calculateVisibleRange = useCallback((scrollTop: number, containerHeight: number) => {
    if (pages.length === 0 || imageHeights.length === 0) {
      return { start: 0, end: Math.min(2, pages.length - 1) };
    }

    let accumulatedHeight = 0;
    let startIndex = 0;
    let endIndex = pages.length - 1;
    const bufferHeight = containerHeight * 3; // 增加缓冲区到3倍屏幕高度，确保快速滚动时不漏

    // 条漫模式：所有图片都参与计算
    for (let i = 0; i < imageHeights.length; i++) {
      const imageHeight = imageHeights[i] || containerHeight;

      if (accumulatedHeight + imageHeight > scrollTop - bufferHeight) {
        startIndex = Math.max(0, i - 4); // 增加前置缓冲
        break;
      }
      accumulatedHeight += imageHeight;
    }

    // 找到结束索引
    accumulatedHeight = 0;
    for (let i = 0; i < imageHeights.length; i++) {
      const imageHeight = imageHeights[i] || containerHeight;

      accumulatedHeight += imageHeight;
      if (accumulatedHeight > scrollTop + containerHeight + bufferHeight) {
        endIndex = Math.min(imageHeights.length - 1, i + 4); // 增加后置缓冲
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

  // 计算两点距离
  const getDistance = (touch1: Touch, touch2: Touch) => {
    const dx = touch1.clientX - touch2.clientX;
    const dy = touch1.clientY - touch2.clientY;
    return Math.sqrt(dx * dx + dy * dy);
  };

  // 触摸开始
  const handleTouchStart = useCallback((e: React.TouchEvent) => {
    // 条漫模式下不阻止默认行为，让页面可以自然滚动
    if (readingMode === 'webtoon') {
      return;
    }
    
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
    // 条漫模式下不阻止默认行为，让页面可以自然滚动
    if (readingMode === 'webtoon') {
      return;
    }
    
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
  const handleTouchEnd = useCallback(() => {
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
  }, [touchStart, touchEnd, handleNextPage, handlePrevPage, readingMode]);

  // 双击放大/缩小
  const handleDoubleClick = useCallback((e: React.MouseEvent, imageIndex?: number) => {
    e.preventDefault();
    if (scale === 1) {
      const targetImage = imageIndex !== undefined ? imageRefs.current[imageIndex] : imageRefs.current[0];
      const rect = targetImage?.getBoundingClientRect();
      if (rect) {
        const x = (e.clientX - rect.left) / rect.width;
        const y = (e.clientY - rect.top) / rect.height;
        setScale(2);
        setTranslateX(-x * rect.width * 0.5);
        setTranslateY(-y * rect.height * 0.5);
      }
    } else {
      resetTransform();
    }
  }, [scale, resetTransform]);

  // 防止图片拖拽
  const handleImageDragStart = useCallback((e: React.DragEvent) => {
    e.preventDefault();
  }, []);

  const toggleReadingMode = () => {
    setReadingMode(prev => {
      const modes: ReadingMode[] = ['single-ltr', 'single-rtl', 'single-ttb', 'webtoon'];
      const currentIndex = modes.indexOf(prev);
      return modes[(currentIndex + 1) % modes.length];
    });
    resetTransform();
  };

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
      const isPC = window.innerWidth >= 1024; // PC屏幕判断
      const containerWidth = isPC
        ? Math.min(800, window.innerWidth * 0.8) // PC端最大800px，或屏幕宽度的80%
        : Math.min(window.innerWidth * 0.95, window.innerWidth);
      const defaultHeight = Math.min(window.innerHeight * 0.7, containerWidth * 1.5); // PC端降低默认高度
      setImageHeights(new Array(pages.length).fill(defaultHeight));
      
      // 设置初始容器高度
      const viewportHeight = window.innerHeight - 100; // 优化工具栏高度计算
      setContainerHeight(viewportHeight);
      
      // 设置初始可见范围
      setVisibleRange({ start: 0, end: Math.min(3, pages.length - 1) }); // 增加初始渲染范围
    }
  }, [pages.length, imageHeights.length]);

  // 保存阅读模式到localStorage
  useEffect(() => {
    if (typeof window !== 'undefined') {
      localStorage.setItem('reader-reading-mode', readingMode);
    }
  }, [readingMode]);

  // 保存双页拼合设置到localStorage
  useEffect(() => {
    if (typeof window !== 'undefined') {
      localStorage.setItem('reader-double-page-mode', String(doublePageMode));
    }
  }, [doublePageMode]);

  // 保存自动翻页设置到localStorage
  useEffect(() => {
    if (typeof window !== 'undefined') {
      localStorage.setItem('reader-auto-play-mode', String(autoPlayMode));
    }
  }, [autoPlayMode]);

  // 保存拆分封面设置到localStorage
  useEffect(() => {
    if (typeof window !== 'undefined') {
      localStorage.setItem('reader-split-cover-mode', String(splitCoverMode));
    }
  }, [splitCoverMode]);

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
      // 单页模式：只加载当前页
      if (!loadedImages.has(currentPage)) {
        setImagesLoading(new Set([currentPage]));
      } else {
        setImagesLoading(new Set());
      }
    }
  }, [currentPage, readingMode, pages.length, loadedImages, visibleRange.start, visibleRange.end]);

  // 滚动事件防抖处理
  const scrollTimeoutRef = useRef<NodeJS.Timeout | null>(null);
  
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
          const isPC = window.innerWidth >= 1024; // PC屏幕判断
          const maxContainerWidth = isPC
            ? Math.min(800, window.innerWidth * 0.8) // PC端最大800px，或屏幕宽度的80%
            : Math.min(window.innerWidth * 0.95, 1200); // 移动端保持原逻辑
          const aspectRatio = img.naturalHeight / img.naturalWidth;
          const imageHeight = maxContainerWidth * aspectRatio;
          
          setImageHeights(prev => {
            const newHeights = [...prev];
            newHeights[index] = imageHeight;
            return newHeights;
          });
        }
      });
    }
  }, [readingMode, imageHeights]);

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
      onMouseMove={() => {
        if (!showToolbar) {
          setShowToolbar(true);
        }
      }}
    >
      {/* 简洁的工具栏 */}
      <div className={`bg-background/95 backdrop-blur-sm border-b transition-transform duration-300 ${showToolbar ? 'translate-y-0' : '-translate-y-full'}`}>
        <div className="p-3">
          <div className="flex items-center justify-between">
            {/* 左侧：返回按钮和功能按钮 */}
            <div className="flex items-center space-x-2">
              <Button
                variant="outline"
                size="sm"
                className="border-border bg-background hover:bg-accent hover:text-accent-foreground pointer-events-auto relative z-50"
                onClick={(e) => {
                  e.preventDefault();
                  e.stopPropagation();
                  window.location.href = `/archive?id=${id}`;
                }}
              >
                <ArrowLeft className="w-4 h-4 mr-2" />
                <span className="hidden sm:inline">{t('reader.back')}</span>
              </Button>

              {/* 主题切换按钮 */}
              <ThemeButton />

              {/* 语言切换按钮 */}
              <div onClick={(e) => e.stopPropagation()}>
                <ReaderLanguageToggle />
              </div>
            </div>

            {/* 右侧：阅读模式切换 */}
            <Button
              variant="outline"
              size="sm"
              onClick={toggleReadingMode}
              className="border-border bg-background hover:bg-accent hover:text-accent-foreground"
            >
              {getReadingModeIcon()}
              <span className="ml-2 hidden sm:inline">{getReadingModeText()}</span>
            </Button>
          </div>
        </div>
      </div>

      {/* 悬浮进度条和收藏按钮 - 紧挨在一起的两个独立区域 */}
      <div className={`absolute bottom-8 left-1/2 transform -translate-x-1/2 flex items-center gap-3 transition-opacity duration-300 z-50 ${showToolbar ? 'opacity-100' : 'opacity-0'}`}>
        {/* 进度条区域 */}
        <div className="bg-background/95 backdrop-blur-sm border border-border rounded-full px-4 py-3 shadow-lg">
          <div className="flex items-center space-x-2">
            <Slider
              value={[currentPage]}
              onValueChange={(value) => {
                const newPage = value[0];
                setCurrentPage(newPage);
                resetTransform();

                // 条漫模式下需要滚动到对应位置
                if (readingMode === 'webtoon' && webtoonContainerRef.current) {
                  let accumulatedHeight = 0;

                  // 按单个图片计算
                  for (let i = 0; i < newPage; i++) {
                    const imageHeight = imageHeights[i] || containerHeight || window.innerHeight * 0.7;
                    accumulatedHeight += imageHeight;
                  }

                  webtoonContainerRef.current.scrollTop = accumulatedHeight;
                }
              }}
              max={pages.length - 1}
              min={0}
              step={1}
              className="w-40 sm:w-64 h-2"
            />
            <span className="text-sm whitespace-nowrap font-medium text-foreground">{currentPage + 1}/{pages.length}</span>
          </div>
        </div>

        {/* 设置按钮区域 */}
        <div className="bg-background/95 backdrop-blur-sm border border-border rounded-full p-0 shadow-lg">
          <Popover>
            <PopoverTrigger asChild>
              <Button
                variant="ghost"
                size="sm"
                className={`
                  rounded-full p-0 h-12 w-12
                  transition-all duration-200 ease-in-out
                  hover:scale-110 active:scale-95
                  text-muted-foreground hover:text-foreground hover:bg-accent
                `}
                style={{ padding: '3px' }}
                title="设置"
              >
                <Settings className="w-4 h-4" />
              </Button>
            </PopoverTrigger>
            <PopoverContent align="center" sideOffset={12} className="w-auto p-3">
              <div className="grid grid-cols-4 gap-2">
                <Button
                  variant="ghost"
                  size="sm"
                  onClick={() => setDoublePageMode(!doublePageMode)}
                  className={`
                    flex flex-col items-center justify-center h-16 w-16
                    rounded-lg border transition-all duration-200
                    ${doublePageMode
                      ? 'border-primary bg-primary/10 text-primary hover:bg-primary/20'
                      : 'border-border bg-background text-muted-foreground hover:text-foreground hover:bg-accent'
                    }
                  `}
                  title="双页拼合"
                >
                  <Layout className="w-5 h-5 mb-1" />
                  <span className="text-xs">双页</span>
                </Button>
                <Button
                  variant="ghost"
                  size="sm"
                  onClick={() => setSplitCoverMode(!splitCoverMode)}
                  disabled={!doublePageMode}
                  className={`
                    flex flex-col items-center justify-center h-16 w-16
                    rounded-lg border transition-all duration-200
                    ${splitCoverMode
                      ? 'border-primary bg-primary/10 text-primary hover:bg-primary/20'
                      : 'border-border bg-background text-muted-foreground hover:text-foreground hover:bg-accent'
                    }
                    ${!doublePageMode ? 'opacity-50 cursor-not-allowed' : ''}
                  `}
                  title={t('reader.splitCoverDescription')}
                >
                  <Scissors className="w-5 h-5 mb-1" />
                  <span className="text-xs">{t('reader.splitCover')}</span>
                </Button>
                <Button
                  variant="ghost"
                  size="sm"
                  onClick={() => {
                    setAutoPlayMode(!autoPlayMode);
                    // 当启用自动翻页模式时，同时启用全屏模式
                    if (!autoPlayMode && !isFullscreen) {
                      toggleFullscreen();
                    }
                  }}
                  className={`
                    flex flex-col items-center justify-center h-16 w-16
                    rounded-lg border transition-all duration-200
                    ${autoPlayMode
                      ? 'border-primary bg-primary/10 text-primary hover:bg-primary/20'
                      : 'border-border bg-background text-muted-foreground hover:text-foreground hover:bg-accent'
                    }
                  `}
                  title="自动翻页"
                >
                  <Play className="w-5 h-5 mb-1" />
                  <span className="text-xs">自动</span>
                </Button>
                <Button
                  variant="ghost"
                  size="sm"
                  onClick={toggleFullscreen}
                  className={`
                    flex flex-col items-center justify-center h-16 w-16
                    rounded-lg border transition-all duration-200
                    ${isFullscreen
                      ? 'border-primary bg-primary/10 text-primary hover:bg-primary/20'
                      : 'border-border bg-background text-muted-foreground hover:text-foreground hover:bg-accent'
                    }
                  `}
                  title="全屏模式"
                >
                  {isFullscreen ? <Minimize className="w-5 h-5 mb-1" /> : <Maximize className="w-5 h-5 mb-1" />}
                  <span className="text-xs">全屏</span>
                </Button>
              </div>
            </PopoverContent>
          </Popover>
        </div>

        {/* 收藏按钮区域 - 仅在未收藏时显示 */}
        {!isFavorited && (
          <div className="bg-background/95 backdrop-blur-sm border border-border rounded-full p-0 shadow-lg">
            <Button
              variant="ghost"
              size="sm"
              onClick={toggleFavorite}
              className={`
                rounded-full p-0 h-12 w-12
                transition-all duration-200 ease-in-out
                hover:scale-110 active:scale-95
                text-muted-foreground hover:text-red-500 hover:bg-red-50 dark:hover:bg-red-950/20
              `}
              style={{ padding: '3px' }}
              title="收藏"
            >
              <Heart className="w-4 h-4" />
            </Button>
          </div>
        )}
      </div>

      {/* 主要阅读区域 */}
      <div 
        className="flex-1 relative overflow-hidden"
        onTouchStart={handleTouchStart}
        onTouchMove={handleTouchMove}
        onTouchEnd={handleTouchEnd}
      >
        {/* 单页模式 */}
        {readingMode !== 'webtoon' && (
          <div className="flex items-center justify-center w-full h-full relative">
            {/* 图片显示区域 */}
            <div className="flex items-center justify-center w-full h-full relative max-w-7xl mx-auto" style={{ maxHeight: 'calc(100vh - 140px)' }}>
              {/* 双页模式下的加载提示 */}
              {doublePageMode && (
                (imagesLoading.has(currentPage) && !loadedImages.has(currentPage)) ||
                (currentPage + 1 < pages.length && imagesLoading.has(currentPage + 1) && !loadedImages.has(currentPage + 1))
              ) && !loadedImages.has(currentPage) && (
                <div className="absolute inset-0 flex items-center justify-center z-20 pointer-events-none">
                  <div className="bg-background/80 backdrop-blur-sm rounded-full p-3 shadow-lg">
                    <Spinner size="lg" />
                  </div>
                </div>
              )}

              <div
                className="relative flex items-center justify-center w-full h-full"
                style={{
                  transform: `scale(${scale}) translate(${translateX}px, ${translateY}px)`,
                  transition: 'transform 0.1s ease-out',
                  cursor: scale > 1 ? 'grab' : 'default',
                  maxHeight: '100%'
                }}
              >
                <div className="relative w-full h-full flex">
                  {/* 当前页 */}
                  <div className={`relative ${doublePageMode && !(splitCoverMode && currentPage === 0) ? 'flex-1' : 'w-full'} h-full min-w-0`}>
                    <MemoizedImage
                      key={`page-${currentPage}`}
                      src={cachedPages[currentPage] || pages[currentPage]}
                      alt={t('reader.pageAlt').replace('{page}', String(currentPage + 1))}
                      fill
                      className={`
                        ${doublePageMode && !(splitCoverMode && currentPage === 0) ? 'object-cover' : 'object-contain'} select-none touch-none
                        w-full h-full
                        transition-opacity duration-200 ease-in-out
                        ${doublePageMode ? 'max-h-[calc(100vh-180px)]' : ''}
                      `}
                      style={{
                        maxHeight: '100%',
                        height: '100%',
                        opacity: loadedImages.has(currentPage) ? 1 : 0.3
                      }}
                      onLoadingComplete={() => {
                        handleImageLoad(currentPage);
                        // 图片加载完成后缓存它（优化：只在缓存中没有该图片时才缓存）
                        if (!cachedPages[currentPage]) {
                          cacheImage(pages[currentPage], currentPage);
                        }
                      }}
                      onError={() => handleImageError(currentPage)}
                      onDoubleClick={(e) => handleDoubleClick(e, 0)}
                      onDragStart={handleImageDragStart}
                      draggable={false}
                    />
                  </div>

                  {/* 下一页（仅在双页模式下且不是拆分封面模式的封面时显示） */}
                  {doublePageMode && !(splitCoverMode && currentPage === 0) && currentPage + 1 < pages.length && (
                    <div className="relative flex-1 h-full min-w-0">
                      <MemoizedImage
                        key={`page-${currentPage + 1}`}
                        src={cachedPages[currentPage + 1] || pages[currentPage + 1]}
                        alt={t('reader.pageAlt').replace('{page}', String(currentPage + 2))}
                        fill
                        className={`
                          object-cover select-none touch-none
                          w-full h-full
                          transition-opacity duration-200 ease-in-out
                          max-h-[calc(100vh-180px)]
                        `}
                        style={{
                          maxHeight: '100%',
                          height: '100%',
                          opacity: loadedImages.has(currentPage + 1) ? 1 : 0.3
                        }}
                        onLoadingComplete={() => {
                          handleImageLoad(currentPage + 1);
                          // 图片加载完成后缓存它
                          if (!cachedPages[currentPage + 1]) {
                            cacheImage(pages[currentPage + 1], currentPage + 1);
                          }
                        }}
                        onError={() => handleImageError(currentPage + 1)}
                        onDoubleClick={(e) => handleDoubleClick(e, 1)}
                        onDragStart={handleImageDragStart}
                        draggable={false}
                      />
                    </div>
                  )}
                </div>
              </div>
            </div>
          </div>
        )}

        {/* 条漫模式 */}
        {readingMode === 'webtoon' && (
          <div
            ref={webtoonContainerRef}
            className="h-full overflow-y-auto overflow-x-hidden"
            onScroll={(e) => {
              const container = e.currentTarget;

              // 防抖处理滚动事件
              if (scrollTimeoutRef.current) {
                clearTimeout(scrollTimeoutRef.current);
              }

              scrollTimeoutRef.current = setTimeout(() => {
                // 更精确的页面索引计算
                let accumulatedHeight = 0;
                let newPageIndex = 0;

                // 按单个图片计算滚动位置
                for (let i = 0; i < imageHeights.length; i++) {
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

                // 更新可见范围
                const newVisibleRange = calculateVisibleRange(container.scrollTop, container.clientHeight);
                setVisibleRange(newVisibleRange);

                // 更新容器高度
                setContainerHeight(container.clientHeight);
              }, 16); // 减少防抖延迟到16ms（约等于60fps的一帧时间）
            }}
          >
            <div
              className="flex flex-col items-center mx-auto relative"
              style={{
                // 精确计算总高度，确保滚动条准确
                height: `${imageHeights.length > 0
                  ? imageHeights.reduce((sum, height) => {
                      return sum + (height || containerHeight || window.innerHeight * 0.7);
                    }, 0)
                  : pages.length * (containerHeight || window.innerHeight * 0.7)
                }px`,
                // 根据设备类型动态设置最大宽度
                maxWidth: window.innerWidth >= 1024 ? '800px' : '1200px',
                width: '100%',
                padding: window.innerWidth >= 1024 ? '0 1rem' : '0' // PC端添加左右边距
              }}
            >
              {/* 上方占位符 */}
              {visibleRange.start > 0 && (
                <div
                  style={{
                    height: `${Array.from({length: visibleRange.start}, (_, i) => {
                      return imageHeights[i] || containerHeight || window.innerHeight * 0.7;
                    }).reduce((sum, height) => sum + height, 0)}px`,
                    minHeight: '1px'
                  }}
                  className="w-full"
                />
              )}
              
              {/* 渲染可见范围内的图片 */}
              {(() => {
                const elements = [];
                let i = visibleRange.start;

                while (i <= visibleRange.end) {
                  const actualIndex = i;
                  const page = pages[actualIndex];
                  const imageHeight = imageHeights[actualIndex] || containerHeight || window.innerHeight * 0.7;

                  if (page) {
                    elements.push(
                      <div key={actualIndex} className="relative w-full">
                        {imagesLoading.has(actualIndex) && !loadedImages.has(actualIndex) && (
                          <div
                            className="absolute inset-0 flex items-center justify-center z-20 pointer-events-none"
                            style={{
                              height: `${imageHeight}px`,
                              minHeight: '100px'
                            }}
                          >
                            <div className="bg-background/80 backdrop-blur-sm rounded-full p-3 shadow-lg">
                              <Spinner size="lg" />
                            </div>
                          </div>
                        )}

                        <div
                          className="relative flex justify-center w-full"
                          style={{
                            height: `${imageHeight}px`,
                            minHeight: '100px'
                          }}
                        >
                          <div className="relative w-full h-full flex justify-center">
                            <MemoizedImage
                              key={`page-${actualIndex}`}
                              src={cachedPages[actualIndex] || page}
                              alt={t('reader.pageAlt').replace('{page}', String(actualIndex + 1))}
                              fill
                              className="object-contain select-none"
                              style={{
                                maxWidth: '100%',
                                maxHeight: '100%',
                                width: 'auto',
                                height: 'auto',
                                display: 'block',
                                margin: '0 auto',
                                opacity: loadedImages.has(actualIndex) ? 1 : 0.3
                              }}
                              onLoadingComplete={() => {
                                handleImageLoad(actualIndex);
                                if (!cachedPages[actualIndex]) {
                                  cacheImage(page, actualIndex);
                                }
                              }}
                              onError={() => handleImageError(actualIndex)}
                              onDoubleClick={(e) => handleDoubleClick(e, actualIndex)}
                              onDragStart={handleImageDragStart}
                              draggable={false}
                            />
                          </div>
                        </div>
                      </div>
                    );
                  }
                  i += 1;
                }

                return elements;
              })()}
              
              {/* 下方占位符 */}
              {visibleRange.end < pages.length - 1 && (
                <div
                  style={{
                    height: `${Array.from({length: pages.length - visibleRange.end - 1}, (_, i) => {
                      const index = visibleRange.end + 1 + i;
                      return imageHeights[index] || containerHeight || window.innerHeight * 0.7;
                    }).reduce((sum, height) => sum + height, 0)}px`,
                    minHeight: '1px'
                  }}
                  className="w-full"
                />
              )}
            </div>
          </div>
        )}
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
      <ReaderLanguageProvider>
        <ReaderContent />
      </ReaderLanguageProvider>
    </Suspense>
  );
}
