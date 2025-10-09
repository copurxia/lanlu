'use client';

import { useSearchParams } from 'next/navigation';
import { useState, useEffect, useCallback, Suspense } from 'react';
import { ArchiveService } from '@/lib/archive-service';
import { ArchiveMetadata } from '@/types/archive';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { Header } from '@/components/layout/Header';
import { Sidebar } from '@/components/layout/Sidebar';
import { ArrowLeft, BookOpen, Download, Tag, Calendar, FileText, Clock, HardDrive, Folder, Info, X, ChevronLeft, ChevronRight, Eye } from 'lucide-react';
import Link from 'next/link';
import { useLanguage } from '@/contexts/LanguageContext';

function ArchiveDetailContent() {
  const searchParams = useSearchParams();
  const id = searchParams.get('id');
  const { t } = useLanguage();
  
  const [metadata, setMetadata] = useState<ArchiveMetadata | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [imageModalOpen, setImageModalOpen] = useState(false);
  const [pages, setPages] = useState<string[]>([]);
  const [previewPage, setPreviewPage] = useState(0);
  const [previewLoading, setPreviewLoading] = useState(false);
  const [previewError, setPreviewError] = useState<string | null>(null);
  const [showPreview, setShowPreview] = useState(false);
  const [archivePages, setArchivePages] = useState<string[]>([]);
  const [displayPages, setDisplayPages] = useState<string[]>([]);
  const [pageSize, setPageSize] = useState(10);
  const [currentPage, setCurrentPage] = useState(0);
  const [loadingImages, setLoadingImages] = useState<Set<number>>(new Set());

  useEffect(() => {
    async function fetchMetadata() {
      if (!id) {
        setError(t('archive.missingId'));
        setLoading(false);
        return;
      }

      try {
        const data = await ArchiveService.getMetadata(id);
        setMetadata(data);
      } catch (err) {
        console.error('Failed to fetch archive metadata:', err);
        setError(t('archive.fetchError'));
      } finally {
        setLoading(false);
      }
    }

    fetchMetadata();
  }, [id, t]);

  // 获取存档页面列表
  useEffect(() => {
    async function fetchPages() {
      if (!id || !showPreview) return;
      
      setPreviewLoading(true);
      setPreviewError(null);
      
      try {
        const data = await ArchiveService.getFiles(id);
        setArchivePages(data);
        // 初始显示前10页
        const initialPages = data.slice(0, pageSize);
        setDisplayPages(initialPages);
        setCurrentPage(0);
      } catch (err) {
        console.error('Failed to fetch archive pages:', err);
        setPreviewError(t('archive.loadPreviewError'));
      } finally {
        setPreviewLoading(false);
      }
    }

    fetchPages();
  }, [id, showPreview, t, pageSize]);

  // 重置预览状态
  useEffect(() => {
    if (!showPreview) {
      setArchivePages([]);
      setDisplayPages([]);
      setCurrentPage(0);
      setPreviewError(null);
      setLoadingImages(new Set());
    }
  }, [showPreview]);

  // 加载更多页面
  const loadMorePages = useCallback(() => {
    const nextPage = currentPage + 1;
    const startIndex = nextPage * pageSize;
    const endIndex = Math.min(startIndex + pageSize, archivePages.length);
    
    if (startIndex < archivePages.length) {
      const newPages = archivePages.slice(startIndex, endIndex);
      setDisplayPages(prev => [...prev, ...newPages]);
      setCurrentPage(nextPage);
    }
  }, [currentPage, pageSize, archivePages.length]);

  // 处理图片加载状态
  const handleImageLoadStart = useCallback((pageIndex: number) => {
    setLoadingImages(prev => new Set(prev).add(pageIndex));
  }, []);

  const handleImageLoadEnd = useCallback((pageIndex: number) => {
    setLoadingImages(prev => {
      const newSet = new Set(prev);
      newSet.delete(pageIndex);
      return newSet;
    });
  }, []);

  // 处理图片加载错误
  const handleImageError = useCallback((pageIndex: number) => {
    setLoadingImages(prev => {
      const newSet = new Set(prev);
      newSet.delete(pageIndex);
      return newSet;
    });
  }, []);

  if (loading) {
    return (
      <div className="flex min-h-screen">
        {/* 侧边栏 - 在大屏幕显示 */}
        <div className="hidden lg:block lg:flex-shrink-0">
          <Sidebar />
        </div>
        
        {/* 主内容区域 */}
        <div className="flex-1 min-w-0">
          <div className="container mx-auto px-4 py-8">
            <div className="text-center py-12">
              <p className="text-muted-foreground">{t('common.loading')}</p>
            </div>
          </div>
        </div>
      </div>
    );
  }

  if (error || !metadata) {
    return (
      <div className="flex min-h-screen">
        {/* 侧边栏 - 在大屏幕显示 */}
        <div className="hidden lg:block lg:flex-shrink-0">
          <Sidebar />
        </div>
        
        {/* 主内容区域 */}
        <div className="flex-1 min-w-0">
          <div className="container mx-auto px-4 py-8">
            <div className="text-center py-12">
              <p className="text-red-500 mb-4">{error || t('archive.notFound')}</p>
              <Link href="/">
                <Button variant="outline">
                  <ArrowLeft className="w-4 h-4 mr-2" />
                  {t('archive.backToHome')}
                </Button>
              </Link>
            </div>
          </div>
        </div>
      </div>
    );
  }

  const tags = metadata.tags ? metadata.tags.split(',').map(tag => tag.trim()).filter(tag => tag) : [];

  // 格式化文件大小
  const formatFileSize = (bytes: number): string => {
    if (bytes === 0) return '0 B';
    const k = 1024;
    const sizes = ['B', 'KB', 'MB', 'GB'];
    const i = Math.floor(Math.log(bytes) / Math.log(k));
    return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + ' ' + sizes[i];
  };

  // 格式化日期
  const formatDate = (dateString: string): string => {
    if (!dateString) return t('archive.unknown');
    try {
      return new Date(dateString).toLocaleString();
    } catch {
      return dateString;
    }
  };

  return (
    <div className="min-h-screen">        
      <main className="container mx-auto px-4 py-6 max-w-7xl">
          {/* 返回按钮 */}
          <div className="mb-4 flex items-center justify-between">
            <Link href="/">
              <Button variant="outline" size="sm">
                <ArrowLeft className="w-4 h-4 mr-2" />
                {t('archive.backToHome')}
              </Button>
            </Link>
            
            {/* 为将来的编辑功能预留空间 */}
            <div className="flex items-center gap-2">
              {/* 将来可以添加编辑按钮，例如：
              <Button variant="outline" size="sm">
                <Edit className="w-4 h-4 mr-2" />
                编辑
              </Button>
              */}
            </div>
          </div>

          {/* 主要内容区域 - 响应式布局 */}
          <div className="grid grid-cols-1 lg:grid-cols-3 gap-6 lg:gap-8">
        {/* 左侧：缩略图和操作按钮 - 在大屏幕占1列，移动端占满宽 */}
        <div className="lg:col-span-1">
          <Card className="lg:sticky lg:top-6">
            <CardContent className="p-4 lg:p-6">
              {/* 缩略图 - 响应式尺寸 */}
              <div className="aspect-[3/4] bg-muted relative mb-4 lg:mb-6 max-w-xs mx-auto lg:max-w-none group">
                <img
                  src={ArchiveService.getThumbnailUrl(metadata.arcid)}
                  alt={metadata.title}
                  className="w-full h-full object-cover rounded-md cursor-pointer transition-all duration-300 hover:scale-105 hover:shadow-xl active:scale-95"
                  onClick={() => setImageModalOpen(true)}
                  onError={(e) => {
                    const target = e.target as HTMLImageElement;
                    target.style.display = 'none';
                    target.nextElementSibling?.classList.remove('hidden');
                  }}
                />
                {/* 无封面占位符 */}
                <div className="hidden absolute inset-0 bg-muted rounded-md flex items-center justify-center">
                  <div className="text-center text-muted-foreground">
                    <div className="text-3xl mb-2">📚</div>
                    <div className="text-sm">{t('archive.noCover')}</div>
                  </div>
                </div>
                {/* PC端悬停提示 */}
                <div className="absolute inset-0 bg-black bg-opacity-0 group-hover:bg-opacity-10 transition-all duration-300 rounded-md flex items-center justify-center pointer-events-none">
                  <div className="opacity-0 group-hover:opacity-100 transition-opacity duration-300 bg-white bg-opacity-90 text-gray-800 px-3 py-1 rounded-full text-sm font-medium">
                    点击查看大图
                  </div>
                </div>
              </div>
              
              {/* 图片模态框 */}
              {imageModalOpen && (
                <div
                  className="fixed inset-0 bg-black bg-opacity-75 z-[9999] flex items-center justify-center p-4"
                  onClick={() => setImageModalOpen(false)}
                >
                  <div className="relative max-w-4xl max-h-full">
                    <img
                      src={ArchiveService.getThumbnailUrl(metadata.arcid)}
                      alt={metadata.title}
                      className="max-w-full max-h-full object-contain rounded-lg"
                      onError={(e) => {
                        const target = e.target as HTMLImageElement;
                        target.style.display = 'none';
                        target.nextElementSibling?.classList.remove('hidden');
                      }}
                    />
                    {/* 模态框无封面占位符 */}
                    <div className="hidden flex items-center justify-center bg-muted rounded-lg" style={{width: '400px', height: '533px'}}>
                      <div className="text-center text-muted-foreground">
                        <div className="text-6xl mb-4">📚</div>
                        <div className="text-lg">{t('archive.noCover')}</div>
                      </div>
                    </div>
                    <button
                      className="absolute top-2 right-2 bg-white bg-opacity-20 hover:bg-opacity-30 text-white rounded-full p-2"
                      onClick={() => setImageModalOpen(false)}
                    >
                      <X className="w-6 h-6" />
                    </button>
                  </div>
                </div>
              )}
              
              {/* 操作按钮 - 响应式布局 */}
              <div className="space-y-2 lg:space-y-3">
                <Link href={`/reader?id=${metadata.arcid}`}>
                  <Button className="w-full h-12 lg:h-auto text-base lg:text-sm font-medium transition-all duration-200 hover:scale-[1.02] active:scale-[0.98]">
                    <BookOpen className="w-5 h-5 lg:w-4 lg:h-4 mr-2" />
                    <span className="hidden sm:inline">{t('archive.startReading')}</span>
                    <span className="sm:hidden">{t('common.read')}</span>
                  </Button>
                </Link>
                <Button
                  variant="outline"
                  className="w-full h-12 lg:h-auto text-base lg:text-sm font-medium transition-all duration-200 hover:scale-[1.02] active:scale-[0.98]"
                  onClick={() => {
                    if (metadata) {
                      const downloadUrl = ArchiveService.getDownloadUrl(metadata.arcid);
                      window.open(downloadUrl, '_blank');
                    }
                  }}
                >
                  <Download className="w-5 h-5 lg:w-4 lg:h-4 mr-2" />
                  <span className="hidden sm:inline">{t('archive.download')}</span>
                  <span className="sm:hidden">{t('common.download')}</span>
                </Button>
              </div>
            </CardContent>
          </Card>
        </div>

        {/* 右侧：详细信息 - 在大屏幕占2列，移动端占满宽 */}
        <div className="lg:col-span-2 space-y-4 lg:space-y-6">
          {/* 标题 */}
          <Card>
            <CardHeader className="pb-4">
              <CardTitle className="text-xl lg:text-3xl leading-tight">{metadata.title}</CardTitle>
              {metadata.summary && (
                <p className="text-muted-foreground mt-2 text-sm lg:text-base leading-relaxed">{metadata.summary}</p>
              )}
            </CardHeader>
          </Card>

          {/* 基本信息 */}
          <Card>
            <CardHeader className="pb-4">
              <CardTitle className="flex items-center text-lg lg:text-xl">
                <Info className="w-5 h-5 mr-2" />
                {t('archive.basicInfo')}
              </CardTitle>
            </CardHeader>
            <CardContent className="space-y-6">
              {/* 阅读信息 */}
              <div className="space-y-2">
                <h4 className="font-medium text-sm text-muted-foreground">{t('archive.readingInfo')}</h4>
                <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
                  <div className="flex items-center space-x-2">
                    <Clock className="w-4 h-4 text-muted-foreground flex-shrink-0" />
                    <span className="text-sm">{t('archive.lastRead')}:</span>
                    <span className="text-sm truncate">{metadata.lastreadtime ? new Date(metadata.lastreadtime * 1000).toLocaleDateString() : t('archive.neverRead')}</span>
                  </div>
                  <div className="flex items-center space-x-2">
                    <BookOpen className="w-4 h-4 text-muted-foreground flex-shrink-0" />
                    <span className="text-sm">{t('archive.pageCount')}:</span>
                    <span className="text-sm">{metadata.pagecount}</span>
                  </div>
                  <div className="flex items-center space-x-2">
                    <BookOpen className="w-4 h-4 text-muted-foreground flex-shrink-0" />
                    <span className="text-sm">{t('archive.progress')}:</span>
                    <span className="text-sm">{metadata.progress}/{metadata.pagecount}</span>
                  </div>
                  <div className="flex items-center space-x-2">
                    <Tag className="w-4 h-4 text-muted-foreground flex-shrink-0" />
                    <span className="text-sm">{t('archive.status')}:</span>
                    <span className="text-sm">{metadata.isnew === 'true' ? t('archive.statusNew') : t('archive.statusRead')}</span>
                  </div>
                </div>
              </div>

              {/* 文件信息 */}
              <div className="space-y-2">
                <h4 className="font-medium text-sm text-muted-foreground">{t('archive.fileInfo')}</h4>
                <div className="space-y-2">
                  <div className="flex items-start space-x-2">
                    <FileText className="w-4 h-4 text-muted-foreground mt-0.5 flex-shrink-0" />
                    <div className="flex-1 min-w-0">
                      <span className="text-sm text-muted-foreground">{t('archive.fileName')}:</span>
                      <div className="text-sm break-all leading-tight" title={metadata.filename}>{metadata.filename}</div>
                    </div>
                  </div>
                  <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
                    <div className="flex items-center space-x-2">
                      <HardDrive className="w-4 h-4 text-muted-foreground flex-shrink-0" />
                      <span className="text-sm">{t('archive.fileSize')}:</span>
                      <span className="text-sm">{formatFileSize(metadata.file_size)}</span>
                    </div>
                    <div className="flex items-center space-x-2">
                      <FileText className="w-4 h-4 text-muted-foreground flex-shrink-0" />
                      <span className="text-sm">{t('archive.fileType')}:</span>
                      <span className="text-sm">{metadata.extension.toUpperCase()}</span>
                    </div>
                  </div>
                </div>
              </div>

              {/* 时间信息 */}
              <div className="space-y-2">
                <h4 className="font-medium text-sm text-muted-foreground">{t('archive.timeInfo')}</h4>
                <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
                  <div className="flex items-center space-x-2">
                    <Calendar className="w-4 h-4 text-muted-foreground flex-shrink-0" />
                    <span className="text-sm">{t('archive.createdAt')}:</span>
                    <span className="text-sm truncate">{formatDate(metadata.created_at)}</span>
                  </div>
                  <div className="flex items-center space-x-2">
                    <Calendar className="w-4 h-4 text-muted-foreground flex-shrink-0" />
                    <span className="text-sm">{t('archive.updatedAt')}:</span>
                    <span className="text-sm truncate">{formatDate(metadata.updated_at)}</span>
                  </div>
                </div>
              </div>
            </CardContent>
          </Card>

          {/* 标签 */}
          {tags.length > 0 && (
            <Card>
              <CardHeader className="pb-4">
                <CardTitle className="flex items-center text-lg lg:text-xl">
                  <Tag className="w-5 h-5 mr-2" />
                  {t('archive.tags')}
                </CardTitle>
              </CardHeader>
              <CardContent>
                <div className="flex flex-wrap gap-1.5 lg:gap-2">
                  {tags.map((tag, index) => (
                    <Badge key={index} variant="secondary" className="px-2 lg:px-3 py-1 text-xs lg:text-sm">
                      {tag}
                    </Badge>
                  ))}
                </div>
              </CardContent>
            </Card>
          )}

          {/* 内容预览区域 */}
          <Card>
            <CardHeader className="pb-4">
              <div className="flex items-center justify-between">
                <CardTitle className="flex items-center text-lg lg:text-xl">
                  <Eye className="w-5 h-5 mr-2" />
                  {t('archive.pageThumbnails')}
                </CardTitle>
                {!showPreview ? (
                  <Button
                    variant="outline"
                    size="sm"
                    onClick={() => setShowPreview(true)}
                    className="text-sm"
                  >
                    <Eye className="w-4 h-4 mr-2" />
                    {t('archive.preview')}
                  </Button>
                ) : (
                  <Button
                    variant="outline"
                    size="sm"
                    onClick={() => setShowPreview(false)}
                    className="text-sm"
                  >
                    <X className="w-4 h-4 mr-2" />
                    {t('common.close')}
                  </Button>
                )}
              </div>
            </CardHeader>
            {showPreview && (
              <CardContent className="space-y-4">
                {previewLoading ? (
                  <div className="flex items-center justify-center py-12">
                    <p className="text-muted-foreground">{t('common.loading')}</p>
                  </div>
                ) : previewError ? (
                  <div className="flex items-center justify-center py-12">
                    <p className="text-red-500">{previewError}</p>
                  </div>
                ) : archivePages.length === 0 ? (
                  <div className="flex items-center justify-center py-12">
                    <p className="text-muted-foreground">{t('archive.noPreviewPages')}</p>
                  </div>
                ) : (
                  <div className="space-y-4">
                    {/* 页面信息 */}
                    <div className="flex items-center justify-between text-sm text-muted-foreground">
                      <span>{t('archive.progressRead').replace('{progress}', String(displayPages.length)).replace('{total}', String(archivePages.length))}</span>
                      <Link href={`/reader?id=${metadata.arcid}`}>
                        <Button variant="outline" size="sm">
                          <BookOpen className="w-4 h-4 mr-2" />
                          {t('archive.startReading')}
                        </Button>
                      </Link>
                    </div>

                    {/* 页面缩略图网格 */}
                    <div className="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-5 gap-3">
                      {displayPages.map((page, index) => {
                        const actualPageIndex = index;
                        const isLoading = loadingImages.has(actualPageIndex);
                        
                        return (
                          <Link
                            key={actualPageIndex}
                            href={`/reader?id=${metadata.arcid}&page=${actualPageIndex + 1}`}
                            className="group relative aspect-[3/4] bg-muted rounded-lg overflow-hidden hover:ring-2 hover:ring-primary transition-all duration-200"
                          >
                            {/* 加载状态 */}
                            {isLoading && (
                              <div className="absolute inset-0 flex items-center justify-center bg-muted/50 z-10">
                                <div className="animate-spin rounded-full h-6 w-6 border-b-2 border-primary"></div>
                              </div>
                            )}
                            
                            {/* 页面图片 */}
                            <img
                              src={ArchiveService.getPageUrl(metadata.arcid, page)}
                              alt={t('archive.previewPage').replace('{current}', String(actualPageIndex + 1)).replace('{total}', String(archivePages.length))}
                              className={`w-full h-full object-contain transition-opacity duration-200 ${isLoading ? 'opacity-0' : 'opacity-100'}`}
                              onLoadStart={() => handleImageLoadStart(actualPageIndex)}
                              onLoad={() => handleImageLoadEnd(actualPageIndex)}
                              onError={() => handleImageError(actualPageIndex)}
                              draggable={false}
                            />
                            
                            {/* 页码标签 */}
                            <div className="absolute bottom-0 left-0 right-0 bg-black/50 text-white text-xs py-1 text-center">
                              {actualPageIndex + 1}
                            </div>
                            
                            {/* 悬停提示 */}
                            <div className="absolute inset-0 bg-black bg-opacity-0 group-hover:bg-opacity-20 transition-all duration-200 flex items-center justify-center">
                              <div className="opacity-0 group-hover:opacity-100 transition-opacity duration-200 bg-white bg-opacity-90 text-gray-800 px-2 py-1 rounded text-xs font-medium">
                                {t('archive.clickToRead')}
                              </div>
                            </div>
                          </Link>
                        );
                      })}
                    </div>

                    {/* 加载更多按钮 */}
                    {displayPages.length < archivePages.length && (
                      <div className="flex justify-center pt-4">
                        <Button
                          variant="outline"
                          onClick={loadMorePages}
                          disabled={previewLoading}
                          className="text-sm"
                        >
                          {t('archive.loadMore')} ({archivePages.length - displayPages.length} {t('common.next')})
                        </Button>
                      </div>
                    )}
                  </div>
                )}
              </CardContent>
            )}
          </Card>
        </div>
      </div>
      </main>
    </div>
  );
}

export default function ArchiveDetailPage() {
  const { t } = useLanguage();
  
  return (
    <div className="min-h-screen">
      <Header />
      
      <Suspense fallback={
        <div className="container mx-auto px-4 py-8">
          <div className="text-center py-12">
            <p className="text-muted-foreground">{t('common.loading')}</p>
          </div>
        </div>
      }>
        <ArchiveDetailContent />
      </Suspense>
    </div>
  );
}