'use client';

import { useSearchParams, useRouter } from 'next/navigation';
import { useState, useEffect, useCallback, Suspense, useRef, memo } from 'react';
import Image from 'next/image';
import { ArchiveService, PageInfo } from '@/lib/archive-service';
import { FavoriteService } from '@/lib/favorite-service';
import { Button } from '@/components/ui/button';
import { Spinner } from '@/components/ui/spinner';
import { Slider } from '@/components/ui/slider';
import { ThemeButton } from '@/components/theme/theme-toggle';
import { LanguageButton } from '@/components/language/LanguageButton';
import { HtmlRenderer } from '@/components/ui/html-renderer';
import { useLanguage } from '@/contexts/LanguageContext';
import { Popover, PopoverTrigger, PopoverContent } from '@/components/ui/popover';
import { logger } from '@/lib/logger';
import {
  useReadingMode,
  useDoublePageMode,
  useAutoPlayMode,
  useAutoPlayInterval,
  useSplitCoverMode,
  useFullscreenMode,
  useDoubleTapZoom,
  useAutoHideEnabled,
} from '@/hooks/use-reader-settings';
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
  Minimize,
  ZoomIn,
  Eye
} from 'lucide-react';
import Link from 'next/link';

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

// Memo化的视频组件
const MemoizedVideo = memo(function MemoizedVideo({
  src,
  className,
  style,
  onLoadedData,
  onError,
}: {
  src: string;
  className?: string;
  style?: React.CSSProperties;
  onLoadedData?: () => void;
  onError?: () => void;
}) {
  return (
    <video
      src={src}
      controls
      playsInline
      preload="metadata"
      className={className}
      style={style}
      onLoadedData={onLoadedData}
      onError={onError}
    />
  );
});

MemoizedVideo.displayName = 'MemoizedVideo';

function ReaderContent() {
  const router = useRouter();
  const searchParams = useSearchParams();
  const id = searchParams?.get('id') ?? null;
  const pageParam = searchParams?.get('page');
  const { t } = useLanguage();
  
  const [pages, setPages] = useState<PageInfo[]>([]);
  const [cachedPages, setCachedPages] = useState<string[]>([]);
  const [currentPage, setCurrentPage] = useState(0);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [touchStart, setTouchStart] = useState<{ x: number; y: number } | null>(null);
  const [touchEnd, setTouchEnd] = useState<{ x: number; y: number } | null>(null);
  const [imagesLoading, setImagesLoading] = useState<Set<number>>(new Set());
  const [loadedImages, setLoadedImages] = useState<Set<number>>(new Set()); // 跟踪已加载的图片
  const [htmlContent, setHtmlContent] = useState<string>(''); // HTML内容缓存
  const [showToolbar, setShowToolbar] = useState(true);
  const [isFavorited, setIsFavorited] = useState(false); // 收藏状态
  const [archiveTitle, setArchiveTitle] = useState<string>(''); // 归档标题
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
  const autoHideTimeoutRef = useRef<NodeJS.Timeout | null>(null); // 自动隐藏定时器引用
  const AUTO_HIDE_DELAY = 3000; // 自动隐藏延迟时间（毫秒）
  const mouseMoveTimeoutRef = useRef<NodeJS.Timeout | null>(null); // 鼠标移动防抖引用
  const MOUSE_MOVE_DEBOUNCE = 100; // 鼠标移动防抖延迟（毫秒）

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

  // 使用新的阅读设置hooks，统一管理所有localStorage逻辑
  const [readingMode, toggleReadingMode] = useReadingMode();
  const [doublePageMode, setDoublePageMode] = useDoublePageMode();
  const [autoPlayMode, setAutoPlayMode] = useAutoPlayMode();
  const [autoPlayInterval, setAutoPlayInterval] = useAutoPlayInterval();
  const [splitCoverMode, setSplitCoverMode] = useSplitCoverMode();
  const [isFullscreen, setIsFullscreen] = useFullscreenMode();
  const [doubleTapZoom, setDoubleTapZoom] = useDoubleTapZoom();
  const [autoHideEnabled, setAutoHideEnabled] = useAutoHideEnabled();

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

        // 获取metadata（包含收藏状态和标题）
        try {
          const metadata = await ArchiveService.getMetadata(id);
          setIsFavorited(metadata.isfavorite);
          if (metadata.title && metadata.title.trim()) {
            setArchiveTitle(metadata.title);
          }
        } catch (favErr) {
          logger.apiError('fetch favorite status', favErr);
          // 收藏状态失败不影响阅读体验，静默处理
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

  // 加载HTML页面内容
  useEffect(() => {
    if (pages.length > 0 && currentPage >= 0 && currentPage < pages.length) {
      const page = pages[currentPage];

      if (page.type === 'html') {
        // 加载HTML内容
        fetch(page.url)
          .then(response => response.text())
          .then(html => {
            // 重写相对路径为API路径，确保资源文件正确加载
            // 提取当前页面的路径部分（从page.url中的path参数）
            const urlObj = new URL(page.url, window.location.origin);
            const pathParam = urlObj.searchParams.get('path');
            const currentDir = pathParam ? pathParam.substring(0, pathParam.lastIndexOf('/')) : '';

            // 重写HTML中的相对路径
            let processedHtml = html;

            // 1. 重写HTML标签中的src和href属性
            processedHtml = processedHtml.replace(
              /(src|href)=["'](?!http|https|data:|mailto:|tel:)([^"']+)["']/gi,
              (match, attr, relativePath) => {
                // 如果是相对路径，转换为API路径
                if (!relativePath.startsWith('/') && !relativePath.startsWith('data:')) {
                  const fullPath = currentDir ? `${currentDir}/${relativePath}` : relativePath;
                  const encodedPath = encodeURIComponent(fullPath);
                  const apiPath = `/api/archives/${id}/page?path=${encodedPath}`;
                  return `${attr}="${apiPath}"`;
                }
                return match;
              }
            );

            // 2. 重写CSS中的url()引用
            processedHtml = processedHtml.replace(
              /url\((?!['"]?(?:http|https|data:))([^'")]+)\)/gi,
              (match, relativePath) => {
                // 清理路径中的引号
                relativePath = relativePath.replace(/['"]/g, '');
                // 如果是相对路径，转换为API路径
                if (!relativePath.startsWith('/') && !relativePath.startsWith('data:')) {
                  const fullPath = currentDir ? `${currentDir}/${relativePath}` : relativePath;
                  const encodedPath = encodeURIComponent(fullPath);
                  const apiPath = `/api/archives/${id}/page?path=${encodedPath}`;
                  return `url(${apiPath})`;
                }
                return match;
              }
            );

            // 3. 处理EPUB内部导航链接（<a>标签的href）
            // 创建一个临时DOM元素来解析HTML
            const tempDiv = document.createElement('div');
            tempDiv.innerHTML = processedHtml;

            // 查找所有<a>标签
            const links = tempDiv.querySelectorAll('a[href]');
            links.forEach(link => {
              const href = link.getAttribute('href');
              if (href && !href.startsWith('http') && !href.startsWith('data:') && !href.startsWith('mailto:')) {
                // 这是EPUB内部链接，转换为前端路由
                const fullPath = currentDir ? `${currentDir}/${href}` : href;
                const encodedPath = encodeURIComponent(fullPath);

                // 检查是否是HTML文件
                if (/\.(xhtml|html|htm)$/i.test(href)) {
                  // 查找对应的页面索引
                  const targetPageIndex = pages.findIndex(p => {
                    const urlObj = new URL(p.url, window.location.origin);
                    const pagePath = urlObj.searchParams.get('path');
                    return pagePath === fullPath;
                  });

                  if (targetPageIndex >= 0) {
                    // 使用javascript:void(0)阻止默认行为，然后导航到正确页面
                    link.setAttribute('href', `#page-${targetPageIndex}`);
                    link.addEventListener('click', (e) => {
                      e.preventDefault();
                      setCurrentPage(targetPageIndex);
                    });
                  }
                } else {
                  // 非HTML文件（如图片），转换为API路径
                  link.setAttribute('href', `/api/archives/${id}/page?path=${encodedPath}`);
                }
              }
            });

            // 将处理后的HTML设置回去
            processedHtml = tempDiv.innerHTML;

            setHtmlContent(processedHtml);
          })
          .catch(error => {
            logger.error('Failed to load HTML page', error);
            setError('Failed to load HTML content');
          });
      } else {
        // 非HTML页面清空HTML内容
        setHtmlContent('');
      }
    }
  }, [currentPage, pages, id]);

  // 自动隐藏工具栏逻辑（合并版）
  useEffect(() => {
    // 清除所有定时器
    if (autoHideTimeoutRef.current) {
      clearTimeout(autoHideTimeoutRef.current);
    }
    if (mouseMoveTimeoutRef.current) {
      clearTimeout(mouseMoveTimeoutRef.current);
    }

    // 如果未启用自动隐藏，不设置任何逻辑
    if (!autoHideEnabled) {
      return;
    }

    // 设置自动隐藏定时器
    const scheduleAutoHide = () => {
      if (autoHideTimeoutRef.current) {
        clearTimeout(autoHideTimeoutRef.current);
      }
      autoHideTimeoutRef.current = setTimeout(() => {
        setShowToolbar(false);
      }, AUTO_HIDE_DELAY);
    };

    // 鼠标移动处理函数（带防抖）
    const handleMouseMove = () => {
      if (mouseMoveTimeoutRef.current) {
        clearTimeout(mouseMoveTimeoutRef.current);
      }

      mouseMoveTimeoutRef.current = setTimeout(() => {
        if (!showToolbar) {
          setShowToolbar(true);
        }
        // 显示工具栏后，重新安排自动隐藏
        scheduleAutoHide();
      }, MOUSE_MOVE_DEBOUNCE);
    };

    // 触摸移动处理函数（移动端支持）
    const handleTouchMove = () => {
      if (mouseMoveTimeoutRef.current) {
        clearTimeout(mouseMoveTimeoutRef.current);
      }

      mouseMoveTimeoutRef.current = setTimeout(() => {
        if (!showToolbar) {
          setShowToolbar(true);
        }
        scheduleAutoHide();
      }, MOUSE_MOVE_DEBOUNCE);
    };

    // 如果工具栏当前可见，立即设置自动隐藏定时器
    if (showToolbar) {
      scheduleAutoHide();
    }

    // 添加事件监听
    document.addEventListener('mousemove', handleMouseMove);
    document.addEventListener('touchmove', handleTouchMove, { passive: true });

    // 清理函数
    return () => {
      if (autoHideTimeoutRef.current) {
        clearTimeout(autoHideTimeoutRef.current);
      }
      if (mouseMoveTimeoutRef.current) {
        clearTimeout(mouseMoveTimeoutRef.current);
      }
      document.removeEventListener('mousemove', handleMouseMove);
      document.removeEventListener('touchmove', handleTouchMove);
    };
  }, [showToolbar, autoHideEnabled]);

  // 重置变换
  const resetTransform = useCallback(() => {
    setScale(1);
    setTranslateX(0);
    setTranslateY(0);
  }, []);

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

  const handleWheel = useCallback((e: WheelEvent) => {
    if (e.target instanceof HTMLInputElement) return;

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
        const isAtBottom = scrollTop >= scrollHeight - clientHeight - 5;

        const deltaY = e.deltaY;

        // 在顶部向上滚动 -> 上一页（跳转到上一页底部）
        // 在底部向下滚动 -> 下一页（跳转到下一页顶部）
        // 其他情况允许自然滚动
        if ((isAtTop && deltaY < 0) || (isAtBottom && deltaY > 0)) {
          e.preventDefault();
          if (isAtTop && deltaY < 0) {
            // 跳转到上一页底部
            handlePrevPage();
            // 等待页面渲染完成后，滚动到底部
            setTimeout(() => {
              const htmlContainer = document.querySelector('.html-content-container');
              if (htmlContainer) {
                htmlContainer.scrollTop = htmlContainer.scrollHeight;
              }
            }, 100);
          } else if (isAtBottom && deltaY > 0) {
            // 跳转到下一页顶部
            handleNextPage();
            // 等待页面渲染完成后，滚动到顶部
            setTimeout(() => {
              const htmlContainer = document.querySelector('.html-content-container');
              if (htmlContainer) {
                htmlContainer.scrollTop = 0;
              }
            }, 100);
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
    } else if (readingMode !== 'webtoon') {
      if (deltaX > 0 || deltaY > 0) {
        handleNextPage();
      } else if (deltaX < 0 || deltaY < 0) {
        handlePrevPage();
      }
    }
  }, [handlePrevPage, handleNextPage, readingMode, pages, currentPage]);

  useEffect(() => {
    window.addEventListener('wheel', handleWheel);
    return () => {
      window.removeEventListener('wheel', handleWheel);
    };
  }, [handleWheel]);

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
      {/* 简洁的工具栏 */}
      <div className={`
        bg-background/95 backdrop-blur-sm border-b
        transition-all duration-250 ease-out
        will-change-transform will-change-opacity
        ${showToolbar 
          ? 'h-auto translate-y-0 opacity-100' 
          : '!h-0 -translate-y-4 opacity-0 overflow-hidden'}
      `}>
        <div className={`
          transition-all duration-250 ease-out
          ${showToolbar ? 'p-3 opacity-100' : 'p-0 opacity-0'}
        `}>
          <div className={`flex items-center justify-between transition-all duration-250 ease-out ${showToolbar ? 'opacity-100 scale-100' : 'opacity-0 scale-95'}`}>
            {/* 左侧：返回按钮和功能按钮 */}
            <div className={`flex items-center space-x-2 transition-all duration-250 ease-out delay-50 ${showToolbar ? 'opacity-100 translate-x-0' : 'opacity-0 -translate-x-4'}`}>
              <Button
                variant="outline"
                size="sm"
                className="border-border bg-background hover:bg-accent hover:text-accent-foreground pointer-events-auto relative z-50"
                onClick={handleBack}
              >
                <ArrowLeft className="w-4 h-4 mr-2" />
                <span className="hidden sm:inline">{t('reader.back')}</span>
              </Button>

              {/* 主题切换按钮 */}
              <ThemeButton />

              {/* 语言切换按钮 */}
              <LanguageButton />
            </div>

            {/* 中间：标题显示（仅PC端且有标题时显示） */}
            {archiveTitle && (
              <div className={`hidden lg:flex items-center justify-center flex-1 px-4 transition-all duration-250 ease-out delay-75 ${showToolbar ? 'opacity-100 scale-100' : 'opacity-0 scale-95'}`}>
                <h1 className="text-sm font-medium text-foreground truncate max-w-md text-center" title={archiveTitle}>
                  {archiveTitle}
                </h1>
              </div>
            )}

            {/* 右侧：阅读模式切换 */}
            <Button
              variant="outline"
              size="sm"
              onClick={toggleReadingMode}
              className={`border-border bg-background hover:bg-accent hover:text-accent-foreground transition-all duration-250 ease-out delay-50 ${showToolbar ? 'opacity-100 translate-x-0' : 'opacity-0 translate-x-4'}`}
            >
              {getReadingModeIcon()}
              <span className="ml-2 hidden sm:inline">{getReadingModeText()}</span>
            </Button>
          </div>
        </div>
      </div>

      {/* 悬浮进度条和收藏按钮 - 紧挨在一起的两个独立区域 */}
      <div className={`
        absolute bottom-8 left-1/2 transform -translate-x-1/2 flex items-center gap-3 
        transition-all duration-250 ease-out z-50
        will-change-transform will-change-opacity
        ${showToolbar 
          ? 'opacity-100 translate-y-0 pointer-events-auto' 
          : 'opacity-0 translate-y-4 pointer-events-none'}
      `}>
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
                  transition-all duration-150 ease-out
                  hover:scale-110 active:scale-95
                  text-muted-foreground hover:text-foreground hover:bg-accent
                  will-change-transform
                `}
                style={{ padding: '3px' }}
                title={t('reader.settings')}
              >
                <Settings className="w-4 h-4" />
              </Button>
            </PopoverTrigger>
            <PopoverContent align="center" sideOffset={12} className="w-auto p-4">
              <div className="grid grid-cols-3 gap-3">
                <Button
                  variant="ghost"
                  size="sm"
                  onClick={() => setDoublePageMode(!doublePageMode)}
                  disabled={readingMode === 'webtoon'}
                  className={`
                    flex flex-col items-center justify-center
                    aspect-square h-14 md:h-20
                    rounded-lg border-2 transition-all duration-150 ease-out
                    shadow-sm hover:shadow-md
                    will-change-transform will-change-opacity
                    ${doublePageMode
                      ? 'border-primary bg-primary/20 text-primary hover:bg-primary/30'
                      : 'border-border bg-background text-muted-foreground hover:text-foreground hover:bg-accent hover:border-primary/50'
                    }
                    ${readingMode === 'webtoon' ? 'opacity-50 cursor-not-allowed' : ''}
                  `}
                  title={t('reader.doublePageTooltip')}
                >
                  <Layout className="w-5 h-5 md:w-6 md:h-6 mb-1.5" />
                  <span className="text-xs md:text-sm leading-tight text-center px-1">{t('reader.doublePage')}</span>
                </Button>
                <Button
                  variant="ghost"
                  size="sm"
                  onClick={() => setSplitCoverMode(!splitCoverMode)}
                  disabled={!doublePageMode}
                  className={`
                    flex flex-col items-center justify-center
                    aspect-square h-14 md:h-20
                    rounded-lg border-2 transition-all duration-150 ease-out
                    shadow-sm hover:shadow-md
                    will-change-transform will-change-opacity
                    ${splitCoverMode
                      ? 'border-primary bg-primary/20 text-primary hover:bg-primary/30'
                      : 'border-border bg-background text-muted-foreground hover:text-foreground hover:bg-accent hover:border-primary/50'
                    }
                    ${!doublePageMode ? 'opacity-50 cursor-not-allowed' : ''}
                  `}
                  title={t('reader.splitCoverTooltip')}
                >
                  <Scissors className="w-5 h-5 md:w-6 md:h-6 mb-1.5" />
                  <span className="text-xs md:text-sm leading-tight text-center px-1">{t('reader.splitCover')}</span>
                </Button>
                <Button
                  variant="ghost"
                  size="sm"
                  onClick={() => setAutoPlayMode(!autoPlayMode)}
                  className={`
                    flex flex-col items-center justify-center
                    aspect-square h-14 md:h-20
                    rounded-lg border-2 transition-all duration-150 ease-out
                    shadow-sm hover:shadow-md
                    will-change-transform will-change-opacity
                    ${autoPlayMode
                      ? 'border-primary bg-primary/20 text-primary hover:bg-primary/30'
                      : 'border-border bg-background text-muted-foreground hover:text-foreground hover:bg-accent hover:border-primary/50'
                    }
                  `}
                  title={t('reader.autoPlayTooltip')}
                >
                  <Play className="w-5 h-5 md:w-6 md:h-6 mb-1.5" />
                  <span className="text-xs md:text-sm leading-tight text-center px-1">{t('reader.autoPlay')}</span>
                </Button>
                <Button
                  variant="ghost"
                  size="sm"
                  onClick={toggleFullscreen}
                  className={`
                    flex flex-col items-center justify-center
                    aspect-square h-14 md:h-20
                    rounded-lg border-2 transition-all duration-150 ease-out
                    shadow-sm hover:shadow-md
                    will-change-transform will-change-opacity
                    ${isFullscreen
                      ? 'border-primary bg-primary/20 text-primary hover:bg-primary/30'
                      : 'border-border bg-background text-muted-foreground hover:text-foreground hover:bg-accent hover:border-primary/50'
                    }
                  `}
                  title={t('reader.fullscreenTooltip')}
                >
                  {isFullscreen ? <Minimize className="w-5 h-5 md:w-6 md:h-6 mb-1.5" /> : <Maximize className="w-5 h-5 md:w-6 md:h-6 mb-1.5" />}
                  <span className="text-xs md:text-sm leading-tight text-center px-1">{t('reader.fullscreen')}</span>
                </Button>
                <Button
                  variant="ghost"
                  size="sm"
                  onClick={() => setDoubleTapZoom(!doubleTapZoom)}
                  className={`
                    flex flex-col items-center justify-center
                    aspect-square h-14 md:h-20
                    rounded-lg border-2 transition-all duration-150 ease-out
                    shadow-sm hover:shadow-md
                    will-change-transform will-change-opacity
                    ${doubleTapZoom
                      ? 'border-primary bg-primary/20 text-primary hover:bg-primary/30'
                      : 'border-border bg-background text-muted-foreground hover:text-foreground hover:bg-accent hover:border-primary/50'
                    }
                  `}
                  title={t('reader.doubleTapTooltip')}
                >
                  <ZoomIn className="w-5 h-5 md:w-6 md:h-6 mb-1.5" />
                  <span className="text-xs md:text-sm leading-tight text-center px-1">{t('reader.doubleTap')}</span>
                </Button>
                <Button
                  variant="ghost"
                  size="sm"
                  onClick={() => setAutoHideEnabled(!autoHideEnabled)}
                  className={`
                    flex flex-col items-center justify-center
                    aspect-square h-14 md:h-20
                    rounded-lg border-2 transition-all duration-150 ease-out
                    shadow-sm hover:shadow-md
                    will-change-transform will-change-opacity
                    ${autoHideEnabled
                      ? 'border-primary bg-primary/20 text-primary hover:bg-primary/30'
                      : 'border-border bg-background text-muted-foreground hover:text-foreground hover:bg-accent hover:border-primary/50'
                    }
                  `}
                  title={t('reader.autoHideTooltip')}
                >
                  <Eye className="w-5 h-5 md:w-6 md:h-6 mb-1.5" />
                  <span className="text-xs md:text-sm leading-tight text-center px-1">{t('reader.autoHide')}</span>
                </Button>
              </div>

              {/* 自动翻页间隔时间调整 */}
              {autoPlayMode && (
                <div className="mt-4 pt-4 border-t border-border col-span-full">
                  <div className="flex items-center justify-between mb-3">
                    <span className="text-sm font-medium">{t('reader.pageInterval')}</span>
                    <span className="text-sm text-muted-foreground">{autoPlayInterval}秒</span>
                  </div>
                  <Slider
                    value={[autoPlayInterval]}
                    onValueChange={(value) => setAutoPlayInterval(value[0])}
                    max={10}
                    min={1}
                    step={1}
                    className="w-full"
                  />
                </div>
              )}
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
                transition-all duration-150 ease-out
                hover:scale-110 active:scale-95
                text-muted-foreground hover:text-red-500 hover:bg-red-50 dark:hover:bg-red-950/20
                will-change-transform
              `}
              style={{ padding: '3px' }}
              title={t('reader.favorite')}
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
        onClick={() => {
          // 当启用自动隐藏时，点击屏幕可以切换工具栏显示/隐藏
          if (autoHideEnabled) {
            setShowToolbar(!showToolbar);
          }
        }}
      >
        {/* 单页模式 */}
        {readingMode !== 'webtoon' && (
          <div className="w-full h-full">
            {/* 图片显示区域 */}
            <div className="flex items-center justify-center w-full h-full relative">
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
                  maxHeight: '100%',
                  height: '100%',
                  transform: doublePageMode ? `scale(${scale}) translate(${translateX}px, ${translateY}px)` : 'none',
                  transition: 'all 300ms ease-in-out',
                  cursor: doublePageMode && scale > 1 ? 'grab' : 'default'
                }}
              >
                <div className="relative w-full h-full flex">
                  {/* 当前页 */}
                  <div className={`relative ${doublePageMode && !(splitCoverMode && currentPage === 0) ? 'flex-1' : 'w-full'} h-full min-w-0`}>
                    {pages[currentPage]?.type === 'video' ? (
                      <MemoizedVideo
                        key={`page-${currentPage}`}
                        src={pages[currentPage].url}
                        className={`
                          ${doublePageMode && !(splitCoverMode && currentPage === 0) ? 'object-cover' : 'object-contain'} select-none touch-none
                          w-full h-full
                          transition-opacity duration-300 ease-in-out
                          ${doublePageMode ? 'max-h-full' : ''}
                        `}
                        style={{
                          maxHeight: '100%',
                          height: '100%',
                          opacity: loadedImages.has(currentPage) ? 1 : 0.3,
                          transform: doublePageMode ? 'none' : `scale(${scale}) translate(${translateX}px, ${translateY}px)`,
                          transition: doublePageMode ? 'none' : 'transform 0.1s ease-out',
                        }}
                        onLoadedData={() => handleImageLoad(currentPage)}
                        onError={() => handleImageError(currentPage)}
                      />
                    ) : pages[currentPage]?.type === 'html' ? (
                      <div className="w-full h-full overflow-auto bg-white">
                        <HtmlRenderer
                          html={htmlContent}
                          className="max-w-4xl mx-auto p-4"
                        />
                      </div>
                    ) : (
                      <MemoizedImage
                        key={`page-${currentPage}`}
                        src={cachedPages[currentPage] || pages[currentPage]?.url}
                        alt={t('reader.pageAlt').replace('{page}', String(currentPage + 1))}
                        fill
                        className={`
                          ${doublePageMode && !(splitCoverMode && currentPage === 0) ? 'object-cover' : 'object-contain'} select-none touch-none
                          w-full h-full
                          transition-opacity duration-300 ease-in-out
                          ${doublePageMode ? 'max-h-full' : ''}
                        `}
                        style={{
                          maxHeight: '100%',
                          height: '100%',
                          opacity: loadedImages.has(currentPage) ? 1 : 0.3,
                          transform: doublePageMode ? 'none' : `scale(${scale}) translate(${translateX}px, ${translateY}px)`,
                          transition: doublePageMode ? 'none' : 'transform 0.1s ease-out',
                          cursor: doublePageMode ? 'pointer' : (scale > 1 ? 'grab' : 'default')
                        }}
                        onLoadingComplete={() => {
                          handleImageLoad(currentPage);
                          // 图片加载完成后缓存它（优化：只在缓存中没有该图片时才缓存）
                          if (!cachedPages[currentPage] && pages[currentPage]) {
                            cacheImage(pages[currentPage].url, currentPage);
                          }
                        }}
                        onError={() => handleImageError(currentPage)}
                        onDoubleClick={(e) => handleDoubleClick(e)}
                        onDragStart={handleImageDragStart}
                        draggable={false}
                      />
                    )}
                  </div>

                  {/* 下一页（仅在双页模式下且不是拆分封面模式的封面时显示） */}
                  {doublePageMode && !(splitCoverMode && currentPage === 0) && currentPage + 1 < pages.length && (
                    <div className="relative flex-1 h-full min-w-0">
                      {pages[currentPage + 1]?.type === 'video' ? (
                        <MemoizedVideo
                          key={`page-${currentPage + 1}`}
                          src={pages[currentPage + 1].url}
                          className={`
                            object-cover select-none touch-none
                            w-full h-full
                            transition-opacity duration-300 ease-in-out
                            max-h-full
                          `}
                          style={{
                            maxHeight: '100%',
                            height: '100%',
                            opacity: loadedImages.has(currentPage + 1) ? 1 : 0.3,
                          }}
                          onLoadedData={() => handleImageLoad(currentPage + 1)}
                          onError={() => handleImageError(currentPage + 1)}
                        />
                      ) : pages[currentPage + 1]?.type === 'html' ? (
                        <div className="w-full h-full overflow-auto bg-white">
                          <HtmlRenderer
                            html={htmlContent}
                            className="max-w-4xl mx-auto p-4"
                          />
                        </div>
                      ) : (
                        <MemoizedImage
                          key={`page-${currentPage + 1}`}
                          src={cachedPages[currentPage + 1] || pages[currentPage + 1]?.url}
                          alt={t('reader.pageAlt').replace('{page}', String(currentPage + 2))}
                          fill
                          className={`
                            object-cover select-none touch-none
                            w-full h-full
                            transition-opacity duration-300 ease-in-out
                            max-h-full
                          `}
                          style={{
                            maxHeight: '100%',
                            height: '100%',
                            opacity: loadedImages.has(currentPage + 1) ? 1 : 0.3,
                            transform: 'none',
                            transition: 'none',
                            cursor: 'pointer'
                          }}
                          onLoadingComplete={() => {
                            handleImageLoad(currentPage + 1);
                            // 图片加载完成后缓存它
                            if (!cachedPages[currentPage + 1] && pages[currentPage + 1]) {
                              cacheImage(pages[currentPage + 1].url, currentPage + 1);
                            }
                          }}
                          onError={() => handleImageError(currentPage + 1)}
                          onDoubleClick={(e) => handleDoubleClick(e)}
                          onDragStart={handleImageDragStart}
                          draggable={false}
                        />
                      )}
                    </div>
                  )}
                </div>
              </div>
            </div>
          </div>
        )}

        {/* 隐藏的预加载区域：前1页和后5页（仅单页/双页模式） */}
        {readingMode !== 'webtoon' && (
          <div className="hidden">
            {Array.from(imagesLoading).map(pageIndex => {
              // 跳过当前页和双页模式下的下一页（它们已经在上面渲染了）
              if (pageIndex === currentPage) return null;
              if (doublePageMode && pageIndex === currentPage + 1) return null;
              const page = pages[pageIndex];
              if (!page) return null;

              if (page.type === 'video') {
                return (
                  <video
                    key={`preload-${pageIndex}`}
                    src={page.url}
                    preload="metadata"
                    onLoadedData={() => handleImageLoad(pageIndex)}
                    onError={() => handleImageError(pageIndex)}
                  />
                );
              }

              return (
                <img
                  key={`preload-${pageIndex}`}
                  src={page.url}
                  alt=""
                  onLoad={() => {
                    handleImageLoad(pageIndex);
                    if (!cachedPages[pageIndex]) {
                      cacheImage(page.url, pageIndex);
                    }
                  }}
                  onError={() => handleImageError(pageIndex)}
                />
              );
            })}
          </div>
        )}

        {/* 条漫模式 */}
        {readingMode === 'webtoon' && (
          <div
            ref={webtoonContainerRef}
            className="h-full overflow-y-auto overflow-x-hidden transition-all duration-250 ease-out"
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
                            {page.type === 'video' ? (
                              <MemoizedVideo
                                key={`page-${actualIndex}`}
                                src={page.url}
                                className="object-contain select-none"
                                style={{
                                  maxWidth: '100%',
                                  maxHeight: '100%',
                                  width: 'auto',
                                  height: 'auto',
                                  display: 'block',
                                  margin: '0 auto',
                                  opacity: loadedImages.has(actualIndex) ? 1 : 0.3,
                                }}
                                onLoadedData={() => handleImageLoad(actualIndex)}
                                onError={() => handleImageError(actualIndex)}
                              />
                            ) : page.type === 'html' ? (
                              <div className="w-full h-full overflow-auto bg-white">
                                <HtmlRenderer
                                  html={htmlContent}
                                  className="max-w-4xl mx-auto p-4"
                                />
                              </div>
                            ) : (
                              <MemoizedImage
                                key={`page-${actualIndex}`}
                                src={cachedPages[actualIndex] || page.url}
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
                                  opacity: loadedImages.has(actualIndex) ? 1 : 0.3,
                                  transform: `scale(${scale}) translate(${translateX}px, ${translateY}px)`,
                                  transition: 'transform 0.1s ease-out',
                                  cursor: scale > 1 ? 'grab' : 'default'
                                }}
                                onLoadingComplete={() => {
                                  handleImageLoad(actualIndex);
                                  if (!cachedPages[actualIndex]) {
                                    cacheImage(page.url, actualIndex);
                                  }
                                }}
                                onError={() => handleImageError(actualIndex)}
                                onDoubleClick={(e) => handleDoubleClick(e)}
                                onDragStart={handleImageDragStart}
                                draggable={false}
                              />
                            )}
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
      <ReaderContent />
    </Suspense>
  );
}
