'use client';

import { useSearchParams } from 'next/navigation';
import { useState, useEffect, useCallback, Suspense } from 'react';
import { ArchiveService } from '@/lib/archive-service';
import { Button } from '@/components/ui/button';
import { Card } from '@/components/ui/card';
import { Spinner } from '@/components/ui/spinner';
import { ArrowLeft, ChevronLeft, ChevronRight, Maximize2, Minimize2 } from 'lucide-react';
import Link from 'next/link';

function ReaderContent() {
  const searchParams = useSearchParams();
  const id = searchParams.get('id');
  
  const [pages, setPages] = useState<string[]>([]);
  const [currentPage, setCurrentPage] = useState(0);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [isFullscreen, setIsFullscreen] = useState(false);
  const [fitMode, setFitMode] = useState<'contain' | 'width' | 'height'>('contain');
  const [touchStart, setTouchStart] = useState<number | null>(null);
  const [touchEnd, setTouchEnd] = useState<number | null>(null);
  const [imageLoading, setImageLoading] = useState(true);

  useEffect(() => {
    async function fetchPages() {
      if (!id) {
        setError('缺少归档ID参数');
        setLoading(false);
        return;
      }

      try {
        const data = await ArchiveService.getFiles(id);
        setPages(data);
      } catch (err) {
        console.error('Failed to fetch archive pages:', err);
        setError('获取归档页面失败');
      } finally {
        setLoading(false);
      }
    }

    fetchPages();
  }, [id]);


  const handlePrevPage = useCallback(() => {
    if (currentPage > 0) {
      setCurrentPage(currentPage - 1);
      setImageLoading(true);
    }
  }, [currentPage]);

  const handleNextPage = useCallback(() => {
    if (currentPage < pages.length - 1) {
      setCurrentPage(currentPage + 1);
      setImageLoading(true);
    }
  }, [currentPage, pages.length]);

  const handleImageLoad = useCallback(() => {
    setImageLoading(false);
  }, []);

  const handleImageError = useCallback(() => {
    setImageLoading(false);
  }, []);

  const handleKeyDown = useCallback((e: KeyboardEvent) => {
    switch (e.key) {
      case 'ArrowLeft':
        handlePrevPage();
        break;
      case 'ArrowRight':
        handleNextPage();
        break;
      case 'f':
        toggleFullscreen();
        break;
    }
  }, [handlePrevPage, handleNextPage]);

  useEffect(() => {
    window.addEventListener('keydown', handleKeyDown);
    return () => {
      window.removeEventListener('keydown', handleKeyDown);
    };
  }, [handleKeyDown]);

  // 触摸事件处理
  const handleTouchStart = useCallback((e: React.TouchEvent) => {
    setTouchEnd(null);
    setTouchStart(e.targetTouches[0].clientX);
  }, []);

  const handleTouchMove = useCallback((e: React.TouchEvent) => {
    setTouchEnd(e.targetTouches[0].clientX);
  }, []);

  const handleTouchEnd = useCallback(() => {
    if (!touchStart || !touchEnd) return;
    
    const distance = touchStart - touchEnd;
    const isLeftSwipe = distance > 50;
    const isRightSwipe = distance < -50;
    
    if (isLeftSwipe) {
      handleNextPage();
    }
    if (isRightSwipe) {
      handlePrevPage();
    }
  }, [touchStart, touchEnd, handleNextPage, handlePrevPage]);

  // 防止图片拖拽
  const handleImageDragStart = useCallback((e: React.DragEvent) => {
    e.preventDefault();
  }, []);

  const toggleFullscreen = () => {
    if (!document.fullscreenElement) {
      document.documentElement.requestFullscreen();
      setIsFullscreen(true);
    } else {
      document.exitFullscreen();
      setIsFullscreen(false);
    }
  };

  const toggleFitMode = () => {
    setFitMode(prev => {
      if (prev === 'contain') return 'width';
      if (prev === 'width') return 'height';
      return 'contain';
    });
  };

  if (loading) {
    return (
      <div className="min-h-screen bg-black text-white flex items-center justify-center">
        <div className="text-center">
          <p className="text-lg">加载中...</p>
        </div>
      </div>
    );
  }

  if (error || pages.length === 0) {
    return (
      <div className="min-h-screen bg-black text-white flex items-center justify-center">
        <div className="text-center">
          <p className="text-red-500 mb-4">{error || '没有可显示的页面'}</p>
          <Link href={`/archive?id=${id}`}>
            <Button variant="outline" className="text-white border-white bg-transparent hover:bg-white hover:text-black">
              <ArrowLeft className="w-4 h-4 mr-2" />
              返回详情页
            </Button>
          </Link>
        </div>
      </div>
    );
  }

  const currentImageUrl = pages[currentPage];

  return (
    <div className="h-screen bg-black text-white flex flex-col overflow-hidden">
      {/* 顶部工具栏 */}
      <div className="bg-gray-900 p-4 flex items-center justify-between">
        <div className="flex items-center space-x-4">
          <Link href={`/archive?id=${id}`}>
            <Button variant="outline" size="sm" className="text-white border-white bg-transparent hover:bg-white hover:text-black">
              <ArrowLeft className="w-4 h-4 mr-2" />
              返回
            </Button>
          </Link>
          <div className="text-sm">
            页面 {currentPage + 1} / {pages.length}
          </div>
        </div>
        
        <div className="flex items-center space-x-2">
          <Button 
            variant="outline" 
            size="sm" 
            onClick={toggleFitMode}
            className="text-white border-white bg-transparent hover:bg-white hover:text-black"
          >
            {fitMode === 'contain' ? (
              <Minimize2 className="w-4 h-4 mr-2" />
            ) : fitMode === 'width' ? (
              <Maximize2 className="w-4 h-4 mr-2" />
            ) : (
              <Maximize2 className="w-4 h-4 mr-2 rotate-90" />
            )}
            {fitMode === 'contain' ? '适应屏幕' : fitMode === 'width' ? '适应宽度' : '适应高度'}
          </Button>
          <Button 
            variant="outline" 
            size="sm" 
            onClick={toggleFullscreen}
            className="text-white border-white bg-transparent hover:bg-white hover:text-black"
          >
            {isFullscreen ? '退出全屏' : '全屏'}
          </Button>
        </div>
      </div>

      {/* 主要阅读区域 */}
      <div className="flex-1 flex items-center justify-center p-4 relative overflow-hidden">
        {/* 上一页按钮 */}
        <Button
          variant="outline"
          size="lg"
          onClick={handlePrevPage}
          disabled={currentPage === 0}
          className="absolute left-4 top-1/2 transform -translate-y-1/2 bg-black/50 text-white border-white hover:bg-white hover:text-black"
        >
          <ChevronLeft className="w-6 h-6" />
        </Button>

        {/* 图片显示区域 */}
        <div
          className="flex items-center justify-center w-full h-full touch-pan-y relative"
          onTouchStart={handleTouchStart}
          onTouchMove={handleTouchMove}
          onTouchEnd={handleTouchEnd}
        >
          {imageLoading && (
            <div className="absolute inset-0 flex items-center justify-center bg-black/50">
              <Spinner size="lg" />
            </div>
          )}
          <img
            src={currentImageUrl}
            alt={`页面 ${currentPage + 1}`}
            className={`
              object-contain select-none touch-none
              ${fitMode === 'width' ? 'w-full h-auto max-h-full' : ''}
              ${fitMode === 'height' ? 'h-full w-auto max-w-full' : ''}
              ${fitMode === 'contain' ? 'max-w-full max-h-full' : ''}
              ${imageLoading ? 'opacity-0' : 'opacity-100'}
            `}
            onLoad={handleImageLoad}
            onError={handleImageError}
            onDoubleClick={toggleFullscreen}
            onDragStart={handleImageDragStart}
            draggable={false}
          />
        </div>

        {/* 下一页按钮 */}
        <Button
          variant="outline"
          size="lg"
          onClick={handleNextPage}
          disabled={currentPage === pages.length - 1}
          className="absolute right-4 top-1/2 transform -translate-y-1/2 bg-black/50 text-white border-white hover:bg-white hover:text-black"
        >
          <ChevronRight className="w-6 h-6" />
        </Button>
      </div>

      {/* 底部导航 */}
      <div className="bg-gray-900 p-4">
        <div className="flex items-center justify-center space-x-4">
          <Button
            variant="outline"
            size="sm"
            onClick={handlePrevPage}
            disabled={currentPage === 0}
            className="text-white border-white bg-transparent hover:bg-white hover:text-black"
          >
            <ChevronLeft className="w-4 h-4 mr-2" />
            上一页
          </Button>
          
          <div className="flex items-center space-x-2">
            <input
              type="range"
              min="0"
              max={pages.length - 1}
              value={currentPage}
              onChange={(e) => setCurrentPage(parseInt(e.target.value))}
              className="w-48"
            />
            <span className="text-sm">{currentPage + 1}/{pages.length}</span>
          </div>

          <Button
            variant="outline"
            size="sm"
            onClick={handleNextPage}
            disabled={currentPage === pages.length - 1}
            className="text-white border-white bg-transparent hover:bg-white hover:text-black"
          >
            下一页
            <ChevronRight className="w-4 h-4 ml-2" />
          </Button>
        </div>
      </div>
    </div>
  );
}

export default function ReaderPage() {
  return (
    <Suspense fallback={
      <div className="min-h-screen bg-black text-white flex items-center justify-center">
        <div className="text-center">
          <p className="text-lg">加载中...</p>
        </div>
      </div>
    }>
      <ReaderContent />
    </Suspense>
  );
}