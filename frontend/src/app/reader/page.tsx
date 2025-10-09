'use client';

import { useSearchParams } from 'next/navigation';
import { useState, useEffect, useCallback, Suspense, useRef } from 'react';
import { ArchiveService } from '@/lib/archive-service';
import { Button } from '@/components/ui/button';
import { Spinner } from '@/components/ui/spinner';
import { Slider } from '@/components/ui/slider';
import { ThemeButton } from '@/components/theme/theme-toggle';
import { ReaderLanguageToggle } from '@/components/language/ReaderLanguageToggle';
import { ReaderLanguageProvider, useReaderLanguage } from '@/contexts/ReaderLanguageContext';
import {
  ArrowLeft,
  Book,
  ArrowRight,
  ArrowDown
} from 'lucide-react';
import Link from 'next/link';

type ReadingMode = 'single-ltr' | 'single-rtl' | 'single-ttb' | 'webtoon';

function ReaderContent() {
  const searchParams = useSearchParams();
  const id = searchParams.get('id');
  const { t } = useReaderLanguage();
  
  const [pages, setPages] = useState<string[]>([]);
  const [currentPage, setCurrentPage] = useState(0);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [readingMode, setReadingMode] = useState<ReadingMode>(() => {
    // 从localStorage读取保存的阅读模式
    if (typeof window !== 'undefined') {
      const savedMode = localStorage.getItem('reader-reading-mode');
      if (savedMode && ['single-ltr', 'single-rtl', 'single-ttb', 'webtoon'].includes(savedMode)) {
        return savedMode as ReadingMode;
      }
    }
    return 'single-ltr';
  });
  const [touchStart, setTouchStart] = useState<{ x: number; y: number } | null>(null);
  const [touchEnd, setTouchEnd] = useState<{ x: number; y: number } | null>(null);
  const [imagesLoading, setImagesLoading] = useState<Set<number>>(new Set());
  const [loadedImages, setLoadedImages] = useState<Set<number>>(new Set()); // 跟踪已加载的图片
  const [showToolbar, setShowToolbar] = useState(true);
  const [toolbarTimer, setToolbarTimer] = useState<NodeJS.Timeout | null>(null);
  const [scale, setScale] = useState(1);
  const [translateX, setTranslateX] = useState(0);
  const [translateY, setTranslateY] = useState(0);
  const [lastTouchDistance, setLastTouchDistance] = useState(0);
  const webtoonContainerRef = useRef<HTMLDivElement>(null);
  const imageRefs = useRef<(HTMLImageElement | null)[]>([]);
  const observerRef = useRef<IntersectionObserver | null>(null);
  const [visibleRange, setVisibleRange] = useState({ start: 0, end: 2 }); // 可见范围
  const [imageHeights, setImageHeights] = useState<number[]>([]); // 存储每张图片的高度
  const [containerHeight, setContainerHeight] = useState(0); // 容器高度

  useEffect(() => {
    async function fetchPages() {
      if (!id) {
        setError('Missing archive ID');
        setLoading(false);
        return;
      }

      try {
        const data = await ArchiveService.getFiles(id);
        setPages(data);
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

  // 自动隐藏工具栏
  const resetAutoHideTimer = useCallback(() => {
    if (toolbarTimer) {
      clearTimeout(toolbarTimer);
    }
    
    const timer = setTimeout(() => {
      setShowToolbar(false);
    }, 3000);
    
    setToolbarTimer(timer);
  }, [toolbarTimer]);

  useEffect(() => {
    if (showToolbar) {
      resetAutoHideTimer();
    }
    
    return () => {
      if (toolbarTimer) {
        clearTimeout(toolbarTimer);
      }
    };
  }, [showToolbar, resetAutoHideTimer]);

  const handlePrevPage = useCallback(() => {
    if (currentPage > 0) {
      setCurrentPage(currentPage - 1);
      resetTransform();
    }
  }, [currentPage]);

  const handleNextPage = useCallback(() => {
    if (currentPage < pages.length - 1) {
      setCurrentPage(currentPage + 1);
      resetTransform();
    }
  }, [currentPage, pages.length]);

  const handleImageLoad = useCallback((pageIndex: number, imgElement?: HTMLImageElement) => {
    setImagesLoading(prev => {
      const newSet = new Set(prev);
      newSet.delete(pageIndex);
      return newSet;
    });
    // 标记图片为已加载
    setLoadedImages(prev => {
      const newSet = new Set(prev);
      newSet.add(pageIndex);
      return newSet;
    });
    
    // 如果是条漫模式且提供了图片元素，记录图片高度
    if (readingMode === 'webtoon' && imgElement) {
      const containerWidth = webtoonContainerRef.current?.clientWidth || window.innerWidth;
      const aspectRatio = imgElement.naturalHeight / imgElement.naturalWidth;
      const imageHeight = containerWidth * aspectRatio;
      
      setImageHeights(prev => {
        const newHeights = [...prev];
        newHeights[pageIndex] = imageHeight;
        return newHeights;
      });
    }
  }, [readingMode]);

  const handleImageError = useCallback((pageIndex: number) => {
    setImagesLoading(prev => {
      const newSet = new Set(prev);
      newSet.delete(pageIndex);
      return newSet;
    });
  }, []);

  // 计算可见范围的函数
  const calculateVisibleRange = useCallback((scrollTop: number, containerHeight: number) => {
    if (pages.length === 0 || imageHeights.length === 0) {
      return { start: 0, end: 2 };
    }

    let accumulatedHeight = 0;
    let startIndex = 0;
    let endIndex = 0;
    const bufferHeight = containerHeight * 3; // 增加缓冲区到3倍屏幕高度，提高快速滑动体验

    // 找到开始索引
    for (let i = 0; i < imageHeights.length; i++) {
      const imageHeight = imageHeights[i] || containerHeight; // 使用容器高度作为默认值
      if (accumulatedHeight + imageHeight > scrollTop - bufferHeight / 2) {
        startIndex = Math.max(0, i - 2); // 前置两个页面
        break;
      }
      accumulatedHeight += imageHeight; // 移除页面间距
    }

    // 找到结束索引
    accumulatedHeight = 0;
    for (let i = 0; i < imageHeights.length; i++) {
      const imageHeight = imageHeights[i] || containerHeight;
      accumulatedHeight += imageHeight; // 移除页面间距
      if (accumulatedHeight > scrollTop + containerHeight + bufferHeight / 2) {
        endIndex = Math.min(imageHeights.length - 1, i + 2); // 后置两个页面
        break;
      }
    }

    // 如果没有找到结束索引，说明到了底部
    if (endIndex === 0) {
      endIndex = Math.min(imageHeights.length - 1, startIndex + 5); // 增加默认范围
    }

    return { start: startIndex, end: endIndex };
  }, [pages.length, imageHeights.length]); // 只依赖长度，不依赖整个数组

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

  // 重置变换
  const resetTransform = useCallback(() => {
    setScale(1);
    setTranslateX(0);
    setTranslateY(0);
  }, []);

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
      // 使用默认高度初始化数组
      const defaultHeight = window.innerHeight * 1.5; // 默认高度为1.5倍屏幕高度
      setImageHeights(new Array(pages.length).fill(defaultHeight));
      
      // 设置初始容器高度
      const viewportHeight = window.innerHeight - 140; // 减去工具栏等高度
      setContainerHeight(viewportHeight);
      
      // 设置初始可见范围
      setVisibleRange({ start: 0, end: 2 });
    }
  }, [pages.length, imageHeights.length]);

  // 保存阅读模式到localStorage
  useEffect(() => {
    if (typeof window !== 'undefined') {
      localStorage.setItem('reader-reading-mode', readingMode);
    }
  }, [readingMode]);

  // 条漫模式初始化 - 只在页面数据加载完成后执行一次
  useEffect(() => {
    if (pages.length > 0) {
      if (readingMode === 'webtoon') {
        // 只标记可见范围内的页面为加载中
        const initialLoad = new Set<number>();
        for (let i = visibleRange.start; i <= visibleRange.end; i++) {
          if (i >= 0 && i < pages.length && !loadedImages.has(i)) {
            initialLoad.add(i);
          }
        }
        setImagesLoading(initialLoad);
      } else {
        // 非条漫模式，只加载当前页（如果还未加载）
        if (!loadedImages.has(currentPage)) {
          setImagesLoading(new Set([currentPage]));
        } else {
          setImagesLoading(new Set()); // 如果已加载，清空加载列表
        }
      }
    }
  }, [pages.length, visibleRange.start, visibleRange.end, readingMode, currentPage, loadedImages]); // 添加所有依赖项
  
  // 阅读模式切换时的处理 - 保持已加载的图片状态
  useEffect(() => {
    if (pages.length > 0) {
      if (readingMode === 'webtoon') {
        // 切换到条漫模式：确保可见范围内的页面在加载列表中（如果还未加载）
        setImagesLoading(prev => {
          const updated = new Set(prev);
          for (let i = visibleRange.start; i <= visibleRange.end; i++) {
            if (i >= 0 && i < pages.length && !loadedImages.has(i)) {
              updated.add(i);
            }
          }
          return updated;
        });
      } else {
        // 切换到单页模式：确保当前页在加载列表中（如果还未加载）
        if (!loadedImages.has(currentPage)) {
          setImagesLoading(prev => {
            const updated = new Set(prev);
            updated.add(currentPage);
            return updated;
          });
        } else {
          // 如果当前页已加载，清空加载列表
          setImagesLoading(new Set());
        }
      }
    }
  }, [readingMode, pages.length, visibleRange.start, visibleRange.end, loadedImages, currentPage]); // 添加所有依赖项
  
  // 当前页面变化时的加载处理
  useEffect(() => {
    if (pages.length > 0) {
      if (readingMode === 'webtoon') {
        // 条漫模式：预加载当前页面前后的几页（如果还未加载）
        const preloadRange = 2;
        setImagesLoading(prev => {
          const updated = new Set(prev);
          for (let i = Math.max(0, currentPage - preloadRange); i <= Math.min(pages.length - 1, currentPage + preloadRange); i++) {
            if (!loadedImages.has(i)) {
              updated.add(i);
            }
          }
          return updated;
        });
      } else {
        // 单页模式：确保当前页在加载列表中（如果还未加载）
        if (!loadedImages.has(currentPage)) {
          setImagesLoading(prev => {
            const updated = new Set(prev);
            updated.add(currentPage);
            return updated;
          });
        } else {
          // 如果当前页已加载，清空加载列表
          setImagesLoading(new Set());
        }
      }
    }
  }, [currentPage, readingMode, pages.length, loadedImages]); // 依赖项已经正确

  // 设置Intersection Observer用于懒加载
  useEffect(() => {
    if (readingMode === 'webtoon') {
      observerRef.current = new IntersectionObserver(
        (entries) => {
          entries.forEach(entry => {
            if (entry.isIntersecting) {
              const imgElement = entry.target as HTMLImageElement;
              const index = parseInt(imgElement.dataset.index || '0');
              
              // 如果图片进入视窗，开始加载
              setImagesLoading(prev => {
                const updated = new Set(prev);
                updated.add(index);
                return updated;
              });
              
              // 加载后停止观察该元素
              observerRef.current?.unobserve(imgElement);
            }
          });
        },
        {
          rootMargin: '500px' // 提前500px开始加载，提高快速滑动体验
        }
      );

      // 只观察可见范围内的图片元素
      imageRefs.current.forEach((img, index) => {
        if (img && !imagesLoading.has(index) && index >= visibleRange.start && index <= visibleRange.end) {
          img.dataset.index = index.toString();
          observerRef.current?.observe(img);
        }
      });
    }

    return () => {
      observerRef.current?.disconnect();
    };
  }, [readingMode, imagesLoading, visibleRange]);

  // 处理已经加载完成的图片
  useEffect(() => {
    if (readingMode === 'webtoon') {
      imageRefs.current.forEach((img, index) => {
        if (img && img.complete && img.naturalHeight > 0 && !imageHeights[index]) {
          // 如果图片已经加载完成但还没有记录高度，计算高度
          const containerWidth = webtoonContainerRef.current?.clientWidth || window.innerWidth;
          const aspectRatio = img.naturalHeight / img.naturalWidth;
          const imageHeight = containerWidth * aspectRatio;
          
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
          resetAutoHideTimer();
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

      {/* 悬浮进度条 - 只在非条漫模式显示 */}
      {readingMode !== 'webtoon' && (
        <div className={`absolute bottom-8 left-1/2 transform -translate-x-1/2 bg-background/95 backdrop-blur-sm border border-border rounded-full px-6 py-3 transition-opacity duration-300 z-50 shadow-lg ${showToolbar ? 'opacity-100' : 'opacity-0'}`}>
          <div className="flex items-center space-x-4">
            <div className="flex items-center space-x-2">
              <Slider
                value={[currentPage]}
                onValueChange={(value) => {
                  setCurrentPage(value[0]);
                  resetTransform();
                }}
                max={pages.length - 1}
                min={0}
                step={1}
                className="w-40 sm:w-64 h-2"
              />
              <span className="text-sm whitespace-nowrap font-medium text-foreground">{currentPage + 1}/{pages.length}</span>
            </div>
          </div>
        </div>
      )}

      {/* 主要阅读区域 */}
      <div 
        className="flex-1 relative overflow-hidden"
        onTouchStart={handleTouchStart}
        onTouchMove={handleTouchMove}
        onTouchEnd={handleTouchEnd}
      >
        {/* 单页模式 */}
        {readingMode !== 'webtoon' && (
          <div className="flex items-center justify-center w-full h-full p-4 relative">
            {/* 图片显示区域 */}
            <div className="flex items-center justify-center w-full h-full relative max-w-7xl mx-auto" style={{ maxHeight: 'calc(100vh - 140px)' }}>
              {imagesLoading.has(currentPage) && !loadedImages.has(currentPage) && (
                <div className="absolute inset-0 flex items-center justify-center bg-black/50 z-20">
                  <Spinner size="lg" />
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
                <img
                  key={`page-${currentPage}`}
                  ref={el => { imageRefs.current[0] = el; }}
                  src={pages[currentPage]}
                  alt={t('reader.pageAlt').replace('{page}', String(currentPage + 1))}
                  className={`
                    object-contain select-none touch-none
                    max-w-full max-h-full w-full h-full
                    ${imagesLoading.has(currentPage) && !loadedImages.has(currentPage) ? 'opacity-0' : 'opacity-100'}
                  `}
                  style={{
                    maxHeight: '100%',
                    height: '100%'
                  }}
                  onLoad={() => handleImageLoad(currentPage)}
                  onError={() => handleImageError(currentPage)}
                  onDoubleClick={(e) => handleDoubleClick(e, 0)}
                  onDragStart={handleImageDragStart}
                  draggable={false}
                />
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
              const scrollPercentage = container.scrollTop / (container.scrollHeight - container.clientHeight);
              const pageIndex = Math.floor(scrollPercentage * pages.length);
              if (pageIndex !== currentPage && pageIndex >= 0 && pageIndex < pages.length) {
                setCurrentPage(pageIndex);
              }
              
              // 更新可见范围
              const newVisibleRange = calculateVisibleRange(container.scrollTop, container.clientHeight);
              setVisibleRange(newVisibleRange);
              
              // 更新容器高度
              setContainerHeight(container.clientHeight);
            }}
          >
            <div
              className="flex flex-col items-center max-w-none mx-auto relative"
              style={{
                // 设置总高度，确保滚动条正常工作
                minHeight: `${imageHeights.length > 0 ? imageHeights.reduce((sum, height) => sum + (height || containerHeight || window.innerHeight), 0) : pages.length * (containerHeight || window.innerHeight) * 1.5}px`
              }}
            >
              {/* 上方占位符 */}
              {visibleRange.start > 0 && (
                <div
                  style={{
                    height: `${Array.from({length: visibleRange.start}, (_, i) => imageHeights[i] || containerHeight || window.innerHeight).reduce((sum, height) => sum + height, 0)}px`
                  }}
                  className="w-full"
                />
              )}
              
              {/* 渲染可见范围内的图片 */}
              {pages.slice(visibleRange.start, visibleRange.end + 1).map((page, index) => {
                const actualIndex = visibleRange.start + index;
                const imageHeight = imageHeights[actualIndex] || containerHeight || window.innerHeight;
                
                return (
                  <div key={actualIndex} className="relative w-full">
                    {imagesLoading.has(actualIndex) && !loadedImages.has(actualIndex) && (
                      <div
                        className="absolute inset-0 flex items-center justify-center bg-black/50 z-20"
                        style={{ height: `${imageHeight}px` }}
                      >
                        <Spinner size="lg" />
                      </div>
                    )}
                    
                    <div
                      className="relative flex justify-center"
                      style={{
                        cursor: scale > 1 ? 'grab' : 'default',
                        height: imageHeights[actualIndex] ? `${imageHeight}px` : 'auto'
                      }}
                    >
                      <img
                        key={`page-${actualIndex}`}
                        ref={el => {
                          imageRefs.current[actualIndex] = el;
                        }}
                        src={imagesLoading.has(actualIndex) || loadedImages.has(actualIndex) ? page : undefined}
                        alt={t('reader.pageAlt').replace('{page}', String(actualIndex + 1))}
                        className={`
                          object-contain select-none w-full
                          max-w-full h-auto
                          ${imagesLoading.has(actualIndex) && !loadedImages.has(actualIndex) ? 'opacity-0' : 'opacity-100'}
                        `}
                        style={{
                          // 保存图片的变换状态，避免模式切换时重置
                          transform: `scale(${scale}) translate(${translateX}px, ${translateY}px)`,
                          transition: 'transform 0.1s ease-out',
                          // 设置初始最大高度，避免布局跳动
                          maxHeight: imageHeight ? `${imageHeight}px` : `${containerHeight || window.innerHeight}px`
                        }}
                        onLoad={(e) => handleImageLoad(actualIndex, e.currentTarget)}
                        onError={() => handleImageError(actualIndex)}
                        onDoubleClick={(e) => handleDoubleClick(e, actualIndex)}
                        onDragStart={handleImageDragStart}
                        draggable={false}
                      />
                    </div>
                  </div>
                );
              })}
              
              {/* 下方占位符 */}
              {visibleRange.end < pages.length - 1 && (
                <div
                  style={{
                    height: `${Array.from({length: pages.length - visibleRange.end - 1}, (_, i) => {
                      const index = visibleRange.end + 1 + i;
                      return imageHeights[index] || containerHeight || window.innerHeight;
                    }).reduce((sum, height) => sum + height, 0)}px`
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