'use client';

import { useSearchParams, useRouter } from 'next/navigation';
import { useState, useEffect, useCallback, useMemo, Suspense } from 'react';
import Image from 'next/image';
import { ArchiveService } from '@/lib/archive-service';
import { ArchiveMetadata } from '@/types/archive';
import { PluginService, type Plugin } from '@/lib/plugin-service';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { Input } from '@/components/ui/input';
import { Textarea } from '@/components/ui/textarea';
import { TagInput } from '@/components/ui/tag-input';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Header } from '@/components/layout/Header';
import { BookOpen, Download, Info, X, Eye, Edit, CheckCircle, RotateCcw, Play, Heart } from 'lucide-react';
import Link from 'next/link';
import { useLanguage } from '@/contexts/LanguageContext';
import { useAuth } from '@/contexts/AuthContext';
import { TagService } from '@/lib/tag-service';
import { FavoriteService } from '@/lib/favorite-service';
import { AddToTankoubonDialog } from '@/components/tankoubon/AddToTankoubonDialog';
import { useToast } from '@/hooks/use-toast';
import { useConfirmContext } from '@/contexts/ConfirmProvider';
import { logger } from '@/lib/logger';

function ArchiveDetailContent() {
  const router = useRouter();
  const searchParams = useSearchParams();
  const id = searchParams?.get('id') ?? null;
  const { t, language } = useLanguage();
  const { isAuthenticated, user } = useAuth();
  const isAdmin = user?.isAdmin === true;
  const { success, error: showError } = useToast();
  const { confirm } = useConfirmContext();

  // 添加 mounted 状态以避免水合错误
  const [mounted, setMounted] = useState(false);

  // 档案专属的 tag i18n map
  const [tagI18nMap, setTagI18nMap] = useState<Record<string, string>>({});

  const displayTag = useCallback((tag: string) => {
    const key = String(tag || '').trim();
    if (!key) return '';
    const translated = tagI18nMap[key];
    if (translated && String(translated).trim()) return String(translated);
    // 如果没有翻译，去掉 namespace 前缀
    const idx = key.indexOf(':');
    return idx > 0 ? key.slice(idx + 1) : key;
  }, [tagI18nMap]);

  // 提取 fetchMetadata 函数到顶层
  const fetchMetadata = useCallback(async (): Promise<ArchiveMetadata | null> => {
    if (!id) return null;

    try {
      const data = await ArchiveService.getMetadata(id);
      setMetadata(data);
      // 从元数据中获取收藏状态
      setIsFavorite(data.isfavorite || false);
      return data;
    } catch (error) {
      logger.apiError('fetch metadata', error);
      return null;
    }
  }, [id]);

  const [metadata, setMetadata] = useState<ArchiveMetadata | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  // 设置 mounted 状态
  useEffect(() => {
    setMounted(true);
  }, []);
  const [imageModalOpen, setImageModalOpen] = useState(false);
  const [previewLoading, setPreviewLoading] = useState(false);
  const [isNewStatusLoading, setIsNewStatusLoading] = useState(false);
  const [previewError, setPreviewError] = useState<string | null>(null);
  const [showPreview, setShowPreview] = useState(false);
  const [archivePages, setArchivePages] = useState<string[]>([]);
  const [displayPages, setDisplayPages] = useState<string[]>([]);
  const [currentPage, setCurrentPage] = useState(0);
  const [loadingImages, setLoadingImages] = useState<Set<number>>(new Set());
  const [isFavorite, setIsFavorite] = useState(false);
  const [favoriteLoading, setFavoriteLoading] = useState(false);

  // 每页显示的图片数量
  const pageSize = 10;

  useEffect(() => {
    async function loadMetadata() {
      if (!id) {
        setError(t('archive.missingId'));
        setLoading(false);
        return;
      }

      try {
        await fetchMetadata();
      } catch (err) {
        logger.apiError('fetch archive metadata', err);
        setError(t('archive.fetchError'));
      } finally {
        setLoading(false);
      }
    }

    loadMetadata();
  }, [id, t, fetchMetadata]);

  // 处理收藏点击
  const handleFavoriteClick = async () => {
    if (!id || favoriteLoading) return;

    setFavoriteLoading(true);
    try {
      const success = await FavoriteService.toggleFavorite(id, isFavorite);
      if (success) {
        setIsFavorite(!isFavorite);
      }
    } catch (error) {
      logger.operationFailed('toggle favorite', error);
    } finally {
      setFavoriteLoading(false);
    }
  };

  // 获取档案专属的 tag i18n
  useEffect(() => {
    if (!id) return;
    let cancelled = false;

    (async () => {
      try {
        const map = await TagService.getTranslations(language, id);
        if (!cancelled) {
          setTagI18nMap(map || {});
        }
      } catch (e) {
        logger.apiError('fetch tag i18n', e);
        if (!cancelled) {
          setTagI18nMap({});
        }
      }
    })();

    return () => {
      cancelled = true;
    };
  }, [id, language]);

  // 获取存档页面列表
  useEffect(() => {
    async function fetchPages() {
      if (!id || !showPreview) return;
      
      setPreviewLoading(true);
      setPreviewError(null);
      
      try {
        const data = await ArchiveService.getFiles(id);
        setArchivePages(data.pages);
        // 初始显示前10页
        const initialPages = data.pages.slice(0, pageSize);
        setDisplayPages(initialPages);
        setCurrentPage(0);
      } catch (err) {
        logger.apiError('fetch archive pages', err);
        setPreviewError(t('archive.loadPreviewError'));
      } finally {
        setPreviewLoading(false);
      }
    }

    fetchPages();
  }, [id, showPreview, t]);

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
  }, [currentPage, archivePages]);

  // 处理图片加载状态
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

  // 处理图片加载失败（隐藏图片，显示占位符）
  const handleImageLoadError = useCallback((title: string) => {
    const imgElement = document.querySelector(`img[alt="${title}"]`) as HTMLElement;
    if (imgElement) {
      imgElement.style.display = 'none';
      const placeholder = imgElement.closest('.relative')?.nextElementSibling;
      if (placeholder) {
        placeholder.classList.remove('hidden');
      }
    }
  }, []);

  const tags = useMemo(() => {
    const raw = metadata?.tags ?? '';
    if (!raw) return [];
    return raw.split(',').map(tag => tag.trim()).filter(tag => tag);
  }, [metadata?.tags]);

  const [isEditing, setIsEditing] = useState(false);
  const [isSaving, setIsSaving] = useState(false);
  const [formData, setFormData] = useState({
    title: '',
    summary: '',
    tags: [] as string[],
  });

  const [metadataPlugins, setMetadataPlugins] = useState<Plugin[]>([]);
  const [selectedMetadataPlugin, setSelectedMetadataPlugin] = useState<string>('');
  const [metadataPluginParam, setMetadataPluginParam] = useState<string>('');
  const [isMetadataPluginRunning, setIsMetadataPluginRunning] = useState(false);
  const [metadataPluginProgress, setMetadataPluginProgress] = useState<number | null>(null);
  const [metadataPluginMessage, setMetadataPluginMessage] = useState<string>('');

  useEffect(() => {
    if (!isEditing || !isAuthenticated) return;
    let cancelled = false;

    (async () => {
      try {
        const plugins = await PluginService.getAllPlugins();
        const metas = plugins.filter((p) => String(p.plugin_type || '').toLowerCase() === 'metadata');
        if (cancelled) return;
        setMetadataPlugins(metas);
        if (!selectedMetadataPlugin && metas.length > 0) {
          setSelectedMetadataPlugin(metas[0].namespace);
        }
      } catch (e) {
        logger.apiError('load metadata plugins', e);
      }
    })();

    return () => {
      cancelled = true;
    };
  }, [isEditing, isAuthenticated, selectedMetadataPlugin]);

  useEffect(() => {
    if (!metadata) return;
    if (isEditing) return;
    setFormData({
      title: metadata.title || '',
      summary: metadata.summary || '',
      tags,
    });
  }, [isEditing, metadata, tags]);

  const startEdit = () => {
    if (!metadata) return;
    if (!isAuthenticated) return;
    setFormData({
      title: metadata.title || '',
      summary: metadata.summary || '',
      tags,
    });
    setIsEditing(true);
  };

  const cancelEdit = () => {
    setIsEditing(false);
    if (!metadata) return;
    setFormData({
      title: metadata.title || '',
      summary: metadata.summary || '',
      tags,
    });
  };

  const saveEdit = async () => {
    if (!metadata) return;
    setIsSaving(true);
    try {
      await ArchiveService.updateMetadata(metadata.arcid, {
        title: formData.title,
        summary: formData.summary,
        tags: formData.tags.join(', '),
      });
      setIsEditing(false);
      await fetchMetadata();
      // 重新获取 tag i18n 映射，确保新标签的翻译能够及时显示
      try {
        const map = await TagService.getTranslations(language, metadata.arcid);
        setTagI18nMap(map || {});
      } catch (e) {
        logger.apiError('fetch tag i18n', e);
        setTagI18nMap({});
      }
    } catch (error) {
      logger.operationFailed('update metadata', error);
      showError(t('archive.updateFailed'));
    } finally {
      setIsSaving(false);
    }
  };

  const runMetadataPlugin = async () => {
    if (!metadata) return;
    if (!isAuthenticated) return;
    if (!selectedMetadataPlugin) {
      showError(t('archive.metadataPluginSelectRequired'));
      return;
    }

    setIsMetadataPluginRunning(true);
    setMetadataPluginProgress(0);
    setMetadataPluginMessage(t('archive.metadataPluginEnqueued'));

    try {
      const finalTask = await ArchiveService.runMetadataPlugin(
        metadata.arcid,
        selectedMetadataPlugin,
        metadataPluginParam,
        {
          onUpdate: (task) => {
            setMetadataPluginProgress(typeof task.progress === 'number' ? task.progress : 0);
            setMetadataPluginMessage(task.message || '');
          },
        }
      );

      if (finalTask.status !== 'completed') {
        const err = finalTask.result || finalTask.message || t('archive.metadataPluginFailed');
        showError(err);
        return;
      }

      const updated = await fetchMetadata();
      if (updated) {
        setFormData({
          title: updated.title || '',
          summary: updated.summary || '',
          tags: updated.tags ? updated.tags.split(',').map(tag => tag.trim()).filter(tag => tag) : [],
        });
      }
      // 重新获取 tag i18n 映射，确保插件更新后的标签翻译能够及时显示
      try {
        const map = await TagService.getTranslations(language, metadata.arcid);
        setTagI18nMap(map || {});
      } catch (e) {
        logger.apiError('fetch tag i18n', e);
        setTagI18nMap({});
      }
      setMetadataPluginMessage(t('archive.metadataPluginCompleted'));
      setMetadataPluginProgress(100);
    } catch (e: any) {
      logger.operationFailed('run metadata plugin', e);
      showError(e?.message || t('archive.metadataPluginFailed'));
    } finally {
      setIsMetadataPluginRunning(false);
    }
  };

  // 处理设置为已读
  const handleMarkAsRead = async () => {
    if (!metadata) return;
    setIsNewStatusLoading(true);
    try {
      await ArchiveService.clearIsNew(metadata.arcid);
      await fetchMetadata(); // 重新获取元数据以更新UI
    } catch (error) {
      logger.operationFailed('mark as read', error);
      showError(t('archive.markAsReadFailed'));
    } finally {
      setIsNewStatusLoading(false);
    }
  };

  // 处理设置为新
  const handleMarkAsNew = async () => {
    if (!metadata) return;
    setIsNewStatusLoading(true);
    try {
      await ArchiveService.setIsNew(metadata.arcid);
      await fetchMetadata(); // 重新获取元数据以更新UI
    } catch (error) {
      logger.operationFailed('mark as new', error);
      showError(t('archive.markAsNewFailed'));
    } finally {
      setIsNewStatusLoading(false);
    }
  };

  // 处理删除档案
  const [deleteLoading, setDeleteLoading] = useState(false);
  const handleDeleteArchive = async () => {
    if (!metadata) return;
    if (!isAdmin) {
      showError('只有管理员才能删除档案');
      return;
    }

    const confirmed = await confirm({
      title: '确认删除',
      description: `确定要删除档案 "${metadata.title}" 吗？\n\n此操作不可恢复，将删除：\n- 档案数据库记录\n- 用户收藏记录\n- 阅读状态记录\n- 标签关联`,
      confirmText: '删除',
      cancelText: '取消',
      variant: 'destructive',
    });

    if (!confirmed) return;

    setDeleteLoading(true);
    try {
      await ArchiveService.deleteArchive(metadata.arcid);
      success('档案删除成功');
      // 删除成功后跳转到首页
      router.push('/');
    } catch (error: any) {
      logger.operationFailed('delete archive', error);
      const errorMessage = error.response?.data?.error || error.message || '删除失败';
      showError(`删除失败: ${errorMessage}`);
    } finally {
      setDeleteLoading(false);
    }
  };

  // 在组件挂载之前显示加载状态，避免水合错误
  if (!mounted || loading) {
    return (
      <div className="min-h-screen">
        <div className="container mx-auto px-4 py-8">
          <div className="text-center py-12">
            <p className="text-muted-foreground">{t('common.loading')}</p>
          </div>
        </div>
      </div>
    );
  }

  if (error || !metadata) {
    return (
      <div className="min-h-screen">
        <div className="container mx-auto px-4 py-8">
          <div className="text-center py-12">
            <p className="text-red-500 mb-4">{error || t('archive.notFound')}</p>
            <Link href="/">
              <Button variant="outline">
                {t('archive.backToHome')}
              </Button>
            </Link>
          </div>
        </div>
      </div>
    );
  }

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
          {/* 主布局：封面图与信息左右布局 */}
          <div className="space-y-6">
            {/* 顶部：封面在左，标题/标签/操作在右 */}
            <div className="grid grid-cols-1 lg:grid-cols-12 gap-6 lg:gap-8">
              <div className="lg:col-span-5 xl:col-span-4">
                <Card>
                  <CardContent className="p-4 lg:p-6">
                    {/* 缩略图 - 响应式尺寸 */}
                    <div className="aspect-[3/4] bg-muted relative max-w-[280px] sm:max-w-[360px] lg:max-w-none mx-auto lg:mx-0 group">
                      <div className="relative w-full h-full">
                        <Image
                          src={ArchiveService.getThumbnailUrl(metadata.arcid)}
                          alt={metadata.title}
                          fill
                          className="object-cover rounded-md cursor-pointer transition-all duration-300 hover:scale-105 hover:shadow-xl active:scale-95"
                          onClick={() => setImageModalOpen(true)}
                          onError={() => handleImageLoadError(metadata.title)}
                        />
                      </div>
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
                          <Image
                            src={ArchiveService.getThumbnailUrl(metadata.arcid)}
                            alt={metadata.title}
                            width={800}
                            height={1066}
                            className="max-w-full max-h-[90vh] w-auto h-auto object-contain rounded-lg"
                            onError={() => handleImageLoadError(metadata.title)}
                            unoptimized
                          />
                          <button
                            className="absolute top-2 right-2 bg-white bg-opacity-20 hover:bg-opacity-30 text-white rounded-full p-2"
                            onClick={() => setImageModalOpen(false)}
                          >
                            <X className="w-6 h-6" />
                          </button>
                        </div>
                      </div>
                    )}
                  </CardContent>
                </Card>
              </div>

	              <div className="lg:col-span-7 xl:col-span-8 h-full">
	                <Card className="h-full flex flex-col">
	                  <CardHeader className="pb-3">
	                    {isEditing ? (
	                      <div className="space-y-3">
	                        <Input
	                          value={formData.title}
	                          onChange={(e) => setFormData(prev => ({ ...prev, title: e.target.value }))}
	                          disabled={isSaving}
	                        />
	                        <Textarea
	                          value={formData.summary}
	                          onChange={(e) => setFormData(prev => ({ ...prev, summary: e.target.value }))}
	                          disabled={isSaving}
	                          placeholder={t('archive.summaryPlaceholder')}
	                          className="min-h-[84px]"
	                        />
                          <div className="pt-1">
                            <div className="flex flex-col sm:flex-row gap-2">
                              <div className="sm:w-[220px]">
                                <Select value={selectedMetadataPlugin} onValueChange={setSelectedMetadataPlugin}>
                                  <SelectTrigger disabled={isSaving || isMetadataPluginRunning || metadataPlugins.length === 0}>
                                    <SelectValue placeholder={t('archive.metadataPluginSelectPlaceholder')} />
                                  </SelectTrigger>
                                  <SelectContent>
                                    {metadataPlugins.map((p) => (
                                      <SelectItem key={p.namespace} value={p.namespace}>
                                        {p.name} ({p.namespace})
                                      </SelectItem>
                                    ))}
                                  </SelectContent>
                                </Select>
                              </div>
                              <Input
                                value={metadataPluginParam}
                                onChange={(e) => setMetadataPluginParam(e.target.value)}
                                disabled={isSaving || isMetadataPluginRunning}
                                placeholder={t('archive.metadataPluginParamPlaceholder')}
                              />
                              <Button
                                type="button"
                                onClick={runMetadataPlugin}
                                disabled={isSaving || isMetadataPluginRunning || metadataPlugins.length === 0 || !selectedMetadataPlugin}
                              >
                                <Play className="w-4 h-4 mr-2" />
                                {isMetadataPluginRunning ? t('archive.metadataPluginRunning') : t('archive.metadataPluginRun')}
                              </Button>
                            </div>
                            {(metadataPluginProgress !== null || metadataPluginMessage) && (
                              <div className="mt-2 text-xs text-muted-foreground flex items-center justify-between gap-2">
                                <span className="truncate" title={metadataPluginMessage}>
                                  {metadataPluginMessage || ''}
                                </span>
                                {metadataPluginProgress !== null && (
                                  <span className="tabular-nums">{Math.max(0, Math.min(100, metadataPluginProgress))}%</span>
                                )}
                              </div>
                            )}
                            {metadataPlugins.length === 0 && (
                              <div className="mt-2 text-xs text-muted-foreground">
                                {t('archive.metadataPluginNoPlugins')}
                              </div>
                            )}
                          </div>
	                      </div>
	                    ) : (
	                      <>
	                        <div className="flex items-start justify-between gap-3">
	                          <CardTitle className="text-lg lg:text-2xl leading-tight">{metadata.title}</CardTitle>
	                        </div>
	                        <p className={`mt-2 text-sm leading-relaxed ${metadata.summary ? 'text-muted-foreground' : 'text-muted-foreground italic'}`}>
	                          {metadata.summary || t('archive.noSummary')}
	                        </p>
	                      </>
	                    )}
	                  </CardHeader>
	                  <CardContent className="pt-0 flex flex-col gap-3 flex-1 min-h-0">
	                    {/* 摘要信息：独立成块 */}
	                    {!isEditing && (
	                      <div className="rounded-md border border-border p-3">
	                        <div className="grid grid-cols-2 gap-x-6 gap-y-2 text-sm">
	                          <div className="flex items-center justify-between gap-3">
	                            <span className="text-muted-foreground">{t('archive.pageCount')}</span>
	                            <span>{metadata.pagecount}</span>
	                          </div>
	                          <div className="flex items-center justify-between gap-3">
	                            <span className="text-muted-foreground">{t('archive.progress')}</span>
	                            <span>{metadata.progress}/{metadata.pagecount}</span>
	                          </div>
	                          <div className="flex items-center justify-between gap-3">
	                            <span className="text-muted-foreground">{t('archive.fileSize')}</span>
	                            <span>{formatFileSize(metadata.file_size)}</span>
	                          </div>
	                          <div className="flex items-center justify-between gap-3">
	                            <span className="text-muted-foreground">{t('archive.fileType')}</span>
	                            <span>{metadata.extension.toUpperCase()}</span>
	                          </div>
	                          <div className="flex items-center justify-between gap-3">
	                            <span className="text-muted-foreground">{t('archive.status')}</span>
	                            <span>{metadata.isnew ? t('archive.statusNew') : t('archive.statusRead')}</span>
	                          </div>
	                          <div className="flex items-center justify-between gap-3">
	                            <span className="text-muted-foreground">{t('archive.updatedAt')}</span>
	                            <span className="truncate">{formatDate(metadata.updated_at)}</span>
	                          </div>
	                        </div>
	                      </div>
	                    )}

	                    {/* 标签编辑器：输出仍为逗号分隔字符串 */}
                    <div className="rounded-md border border-border p-3 flex-1 min-h-0 overflow-auto">
                      {isEditing ? (
                        <TagInput
                          value={formData.tags}
                          onChange={(newTags) => setFormData(prev => ({ ...prev, tags: newTags }))}
                          disabled={isSaving}
                          placeholder={t('archive.tagsPlaceholder')}
                          className="h-full min-h-0 border-0 bg-transparent px-0 py-0 ring-0 focus-within:ring-0 focus-within:ring-offset-0 rounded-none items-start content-start"
                        />
                      ) : tags.length > 0 ? (
                        <div className="flex flex-wrap gap-2">
                          {tags.map((fullTag) => {
	                            const label = displayTag(fullTag);
	                            return (
	                              <Link key={fullTag} href={`/?q=${encodeURIComponent(fullTag)}`}>
	                                <Badge
	                                  variant="secondary"
	                                  className="px-2.5 py-1 text-sm cursor-pointer select-none transition-colors hover:bg-secondary/80"
	                                  title={fullTag}
	                                >
	                                  {label}
	                                </Badge>
	                              </Link>
	                            );
	                          })}
	                        </div>
	                      ) : (
	                        <div className="h-full flex items-center justify-center text-muted-foreground text-sm italic">
	                          {t('archive.noTags')}
	                        </div>
	                      )}
	                    </div>
	
	                    {/* 操作按钮：同一行 */}
	                    <div className="grid grid-cols-1 sm:grid-cols-2 gap-2">
	                      {isEditing ? (
	                        <>
	                          <Button className="w-full" onClick={saveEdit} disabled={isSaving}>
	                            {isSaving ? t('common.saving') : t('common.save')}
	                          </Button>
	                          <Button variant="outline" className="w-full" onClick={cancelEdit} disabled={isSaving}>
	                            {t('common.cancel')}
	                          </Button>
	                        </>
	                      ) : (
	                        <>
	                          <Link href={`/reader?id=${metadata.arcid}`} className="w-full">
	                            <Button className="w-full">
	                              <BookOpen className="w-4 h-4 mr-2" />
	                              {t('archive.startReading')}
	                            </Button>
	                          </Link>
	                          <Button
	                            variant="outline"
	                            className="w-full"
	                            onClick={() => {
	                              const downloadUrl = ArchiveService.getDownloadUrl(metadata.arcid);
	                              window.open(downloadUrl, '_blank');
	                            }}
	                          >
	                            <Download className="w-4 h-4 mr-2" />
	                            {t('archive.download')}
	                          </Button>
	                          {/* 收藏按钮 */}
	                          <Button
	                            variant="outline"
	                            className={`w-full ${isFavorite ? 'text-red-500 border-red-500' : ''}`}
	                            onClick={handleFavoriteClick}
	                            disabled={favoriteLoading}
	                          >
	                            <Heart className={`w-4 h-4 mr-2 ${isFavorite ? 'fill-current' : ''}`} />
	                            {favoriteLoading ? t('common.loading') : (isFavorite ? t('common.unfavorite') : t('common.favorite'))}
	                          </Button>
	                          {/* 已读/取消已读按钮 */}
	                          {metadata.isnew ? (
	                            <Button
	                              variant="outline"
	                              className="w-full"
	                              onClick={handleMarkAsRead}
	                              disabled={isNewStatusLoading}
	                            >
	                              <CheckCircle className="w-4 h-4 mr-2" />
	                              {isNewStatusLoading ? t('common.loading') : t('archive.markAsRead')}
	                            </Button>
	                          ) : (
	                            <Button
	                              variant="outline"
	                              className="w-full"
	                              onClick={handleMarkAsNew}
	                              disabled={isNewStatusLoading}
	                            >
	                              <RotateCcw className="w-4 h-4 mr-2" />
	                              {isNewStatusLoading ? t('common.loading') : t('archive.markAsNew')}
	                            </Button>
	                          )}
	                          {/* 添加到合集按钮 */}
	                          <AddToTankoubonDialog
	                            archiveId={metadata.arcid}
	                            fullWidth
	                            onAdded={() => {}}
	                          />
	                          {isAuthenticated ? (
	                            <Button variant="outline" className="w-full" onClick={startEdit}>
	                              <Edit className="w-4 h-4 mr-2" />
	                              {t('common.edit')}
	                            </Button>
	                          ) : (
	                            <Button variant="outline" className="w-full" disabled title="需要登录才能编辑">
	                              <Edit className="w-4 h-4 mr-2" />
	                              {t('common.edit')}
	                            </Button>
	                          )}
	                          {/* 删除按钮：仅管理员可见 */}
	                          {isAdmin && (
	                            <Button
	                              variant="destructive"
	                              className="w-full"
	                              onClick={handleDeleteArchive}
	                              disabled={deleteLoading}
	                            >
	                              <X className="w-4 h-4 mr-2" />
	                              {deleteLoading ? t('common.loading') : t('common.delete')}
	                            </Button>
	                          )}
	                        </>
	                      )}
	                    </div>
	                  </CardContent>
	                </Card>
	              </div>
            </div>

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
                              <div className="relative w-full h-full">
                                <Image
                                  src={ArchiveService.getPageUrl(metadata.arcid, page)}
                                  alt={t('archive.previewPage').replace('{current}', String(actualPageIndex + 1)).replace('{total}', String(archivePages.length))}
                                  fill
                                  className={`object-contain transition-opacity duration-200 ${isLoading ? 'opacity-0' : 'opacity-100'}`}
                                  onLoadingComplete={() => handleImageLoadEnd(actualPageIndex)}
                                  onError={() => handleImageError(actualPageIndex)}
                                  draggable={false}
                                />
                              </div>
                              
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

            {/* 基本信息 */}
            <Card>
              <CardHeader className="pb-2">
                <CardTitle className="flex items-center text-base lg:text-lg">
                  <Info className="w-4 h-4 mr-2" />
                  {t('archive.basicInfo')}
                </CardTitle>
              </CardHeader>
              <CardContent className="pt-0">
                <div className="grid grid-cols-1 sm:grid-cols-2 gap-x-6 gap-y-2 text-sm">
                  <div className="sm:col-span-2 flex items-center justify-between gap-3">
                    <span className="text-muted-foreground">{t('archive.fileName')}</span>
                    <span className="truncate max-w-[22rem]" title={metadata.filename}>{metadata.filename}</span>
                  </div>

                  <div className="flex items-center justify-between gap-3">
                    <span className="text-muted-foreground">{t('archive.pageCount')}</span>
                    <span>{metadata.pagecount}</span>
                  </div>
                  <div className="flex items-center justify-between gap-3">
                    <span className="text-muted-foreground">{t('archive.progress')}</span>
                    <span>{metadata.progress}/{metadata.pagecount}</span>
                  </div>

                  <div className="flex items-center justify-between gap-3">
                    <span className="text-muted-foreground">{t('archive.lastRead')}</span>
                    <span className="truncate">
                      {metadata.lastreadtime ? new Date(metadata.lastreadtime * 1000).toLocaleDateString() : t('archive.neverRead')}
                    </span>
                  </div>
                  <div className="flex items-center justify-between gap-3">
                    <span className="text-muted-foreground">{t('archive.status')}</span>
                    <span>{metadata.isnew ? t('archive.statusNew') : t('archive.statusRead')}</span>
                  </div>

                  <div className="flex items-center justify-between gap-3">
                    <span className="text-muted-foreground">{t('archive.fileSize')}</span>
                    <span>{formatFileSize(metadata.file_size)}</span>
                  </div>
                  <div className="flex items-center justify-between gap-3">
                    <span className="text-muted-foreground">{t('archive.fileType')}</span>
                    <span>{metadata.extension.toUpperCase()}</span>
                  </div>

                  <div className="flex items-center justify-between gap-3">
                    <span className="text-muted-foreground">{t('archive.createdAt')}</span>
                    <span className="truncate">{formatDate(metadata.created_at)}</span>
                  </div>
                  <div className="flex items-center justify-between gap-3">
                    <span className="text-muted-foreground">{t('archive.updatedAt')}</span>
                    <span className="truncate">{formatDate(metadata.updated_at)}</span>
                  </div>
                </div>
              </CardContent>
            </Card>
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
