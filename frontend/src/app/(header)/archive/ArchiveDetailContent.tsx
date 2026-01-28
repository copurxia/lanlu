'use client';

import { useSearchParams, useRouter } from 'next/navigation';
import { useState, useEffect, useCallback, useMemo } from 'react';
import Link from 'next/link';
import Image from 'next/image';
import { ArchiveService } from '@/lib/services/archive-service';
import { PluginService, type Plugin } from '@/lib/services/plugin-service';
import { FavoriteService } from '@/lib/services/favorite-service';
import { TagService } from '@/lib/services/tag-service';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { Progress } from '@/components/ui/progress';
import { Input } from '@/components/ui/input';
import { Textarea } from '@/components/ui/textarea';
import { TagInput } from '@/components/ui/tag-input';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Dialog, DialogBody, DialogContent, DialogFooter, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { useLanguage } from '@/contexts/LanguageContext';
import { useAuth } from '@/contexts/AuthContext';
import { useToast } from '@/hooks/use-toast';
import { useConfirmContext } from '@/contexts/ConfirmProvider';
import { logger } from '@/lib/utils/logger';
import { useMounted } from '@/hooks/common-hooks';
import { useArchiveMetadata } from './hooks/useArchiveMetadata';
import { useArchivePreview } from './hooks/useArchivePreview';
import { stripNamespace } from '@/lib/utils/tag-utils';
import { ArchivePreviewCard } from './components/ArchivePreviewCard';
import { ArchiveBasicInfoCard } from './components/ArchiveBasicInfoCard';
import { ArchiveMobileActions } from './components/ArchiveMobileActions';
import { ArchiveCollectionsCard } from './components/ArchiveCollectionsCard';
import { useArchiveTankoubons } from './hooks/useArchiveTankoubons';
import { BookOpen, Download, Edit, Heart, RotateCcw, CheckCircle, Trash2, Play } from 'lucide-react';

export function ArchiveDetailContent() {
  const router = useRouter();
  const searchParams = useSearchParams();
  const id = searchParams?.get('id') ?? null;
  const { t, language } = useLanguage();
  const { isAuthenticated, user } = useAuth();
  const isAdmin = user?.isAdmin === true;
  const { success, error: showError } = useToast();
  const { confirm } = useConfirmContext();
  const mounted = useMounted();

  const { metadata, loading, error, isFavorite, setIsFavorite, refetch } = useArchiveMetadata({
    id,
    language,
    t,
  });

  const [showPreview, setShowPreview] = useState(false);
  const pageSize = 10;
  const { previewLoading, previewError, archivePages, displayPages, loadingImages, loadMorePages, handleImageLoadEnd, handleImageError } =
    useArchivePreview({ id, showPreview, pageSize, t });

  const { tankoubons, tankoubonPreviewArchives, loading: tankoubonsLoading } = useArchiveTankoubons({
    archiveId: id,
  });

  const tags = useMemo(() => {
    const raw = metadata?.tags ?? '';
    if (!raw) return [];
    return raw
      .split(',')
      .map((tag) => tag.trim())
      .filter((tag) => tag);
  }, [metadata?.tags]);

  // metadata.tags can be translated by backend (via ?lang=).
  // Build a reverse map so hover/click can still target the canonical tag stored in DB.
  const [tagTranslationMap, setTagTranslationMap] = useState<Record<string, string>>({});
  useEffect(() => {
    if (!id) return;
    let cancelled = false;
    void TagService.getTranslations(language, id)
      .then((map) => {
        if (!cancelled) setTagTranslationMap(map || {});
      })
      .catch(() => {
        if (!cancelled) setTagTranslationMap({});
      });
    return () => {
      cancelled = true;
    };
  }, [id, language]);

  const tagReverseMap = useMemo(() => {
    const rev: Record<string, string> = {};
    for (const [canonical, translated] of Object.entries(tagTranslationMap || {})) {
      const t2 = (translated || '').trim();
      if (!t2) continue;
      const idx = canonical.indexOf(':');
      if (idx > 0) {
        const ns = canonical.slice(0, idx);
        rev[`${ns}:${t2}`] = canonical;
      } else {
        rev[t2] = canonical;
      }
    }
    return rev;
  }, [tagTranslationMap]);

  const toCanonicalTag = useCallback(
    (displayFullTag: string) => {
      return tagReverseMap[displayFullTag] || displayFullTag;
    },
    [tagReverseMap]
  );

  const handleTagClick = useCallback(
    (fullTag: string) => {
      const canonical = toCanonicalTag(fullTag);
      // Preserve namespace for precise matching (e.g. "artist:kyockcho").
      const q = canonical.includes(':') ? canonical : stripNamespace(canonical);
      router.push(`/?q=${encodeURIComponent(q)}`);
    },
    [router, toCanonicalTag]
  );

  const [favoriteLoading, setFavoriteLoading] = useState(false);
  const handleFavoriteClick = useCallback(async () => {
    if (!id || favoriteLoading) return;

    setFavoriteLoading(true);
    try {
      const ok = await FavoriteService.toggleFavorite(id, isFavorite);
      if (ok) setIsFavorite(!isFavorite);
    } catch (err) {
      logger.operationFailed('toggle favorite', err);
    } finally {
      setFavoriteLoading(false);
    }
  }, [favoriteLoading, id, isFavorite, setIsFavorite]);

  const [editDialogOpen, setEditDialogOpen] = useState(false);
  const [isSaving, setIsSaving] = useState(false);
  const [editTitle, setEditTitle] = useState('');
  const [editSummary, setEditSummary] = useState('');
  const [editTags, setEditTags] = useState<string[]>([]);

  const [metadataPlugins, setMetadataPlugins] = useState<Plugin[]>([]);
  const [selectedMetadataPlugin, setSelectedMetadataPlugin] = useState<string>('');
  const [metadataPluginParam, setMetadataPluginParam] = useState<string>('');
  const [isMetadataPluginRunning, setIsMetadataPluginRunning] = useState(false);
  const [metadataPluginProgress, setMetadataPluginProgress] = useState<number | null>(null);
  const [metadataPluginMessage, setMetadataPluginMessage] = useState<string>('');

  useEffect(() => {
    if (!editDialogOpen || !isAuthenticated) return;
    let cancelled = false;

    (async () => {
      try {
        const metas = await PluginService.getMetadataPlugins();
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
  }, [editDialogOpen, isAuthenticated, selectedMetadataPlugin]);

  useEffect(() => {
    if (!metadata) return;
    setEditTitle(metadata.title || '');
    setEditSummary(metadata.summary || '');
    setEditTags(tags.map(toCanonicalTag));
  }, [metadata, tags, toCanonicalTag]);

  const openEditDialog = useCallback(() => {
    if (!isAuthenticated) return;
    setEditDialogOpen(true);
  }, [isAuthenticated]);

  const saveEdit = useCallback(async () => {
    if (!metadata) return;
    setIsSaving(true);
    try {
      const canonicalTags = editTags.map((t) => toCanonicalTag(t));
      await ArchiveService.updateMetadata(
        metadata.arcid,
        { title: editTitle, summary: editSummary, tags: canonicalTags.join(', ') },
        language
      );
      setEditDialogOpen(false);
      await refetch();
    } catch (err) {
      logger.operationFailed('update metadata', err);
      showError(t('archive.updateFailed'));
    } finally {
      setIsSaving(false);
    }
  }, [editSummary, editTags, editTitle, language, metadata, refetch, showError, t, toCanonicalTag]);

  const runMetadataPlugin = useCallback(async () => {
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
      const finalTask = await ArchiveService.runMetadataPluginForTarget(
        'archive',
        metadata.arcid,
        selectedMetadataPlugin,
        metadataPluginParam,
        {
          onUpdate: (task) => {
            setMetadataPluginProgress(typeof task.progress === 'number' ? task.progress : 0);
            setMetadataPluginMessage(task.message || '');
          },
        },
        // Preview by default: fill edit form, don't persist automatically.
        { writeBack: false }
      );

      if (finalTask.status !== 'completed') {
        const err = finalTask.result || finalTask.message || t('archive.metadataPluginFailed');
        showError(err);
        return;
      }

      // Preview mode: parse plugin output and fill the edit form (no DB write-back).
      try {
        const out = finalTask.result ? JSON.parse(finalTask.result) : null;
        const ok = out?.success === true || out?.success === 1 || out?.success === '1' || out?.success === 'true';
        if (!ok) {
          const err = out?.error || finalTask.result || finalTask.message || t('archive.metadataPluginFailed');
          showError(err);
          return;
        }

        const data = out?.data || {};
        const nextTitle = typeof data.title === 'string' ? data.title : '';
        const nextSummary = typeof data.summary === 'string' ? data.summary : '';
        const nextTags = typeof data.tags === 'string' ? data.tags : '';

        if (nextTitle.trim()) setEditTitle(nextTitle.trim());
        if (nextSummary.trim()) setEditSummary(nextSummary.trim());
        if (nextTags.trim()) {
          setEditTags(
            nextTags
              .split(',')
              .map((tag: string) => tag.trim())
              .filter((tag: string) => tag)
              .map((tag: string) => toCanonicalTag(tag))
          );
        }
        setEditDialogOpen(true);
      } catch {
        // If output isn't JSON, still mark as completed and let user view logs/result.
      }
      setMetadataPluginMessage(t('archive.metadataPluginCompleted'));
      setMetadataPluginProgress(100);
    } catch (e: any) {
      logger.operationFailed('run metadata plugin', e);
      showError(e?.message || t('archive.metadataPluginFailed'));
    } finally {
      setIsMetadataPluginRunning(false);
    }
  }, [isAuthenticated, metadata, metadataPluginParam, selectedMetadataPlugin, showError, t, toCanonicalTag]);

  const [isNewStatusLoading, setIsNewStatusLoading] = useState(false);
  const handleMarkAsRead = useCallback(async () => {
    if (!metadata) return;
    setIsNewStatusLoading(true);
    try {
      await ArchiveService.clearIsNew(metadata.arcid);
      await refetch();
    } catch (err) {
      logger.operationFailed('mark as read', err);
      showError(t('archive.markAsReadFailed'));
    } finally {
      setIsNewStatusLoading(false);
    }
  }, [metadata, refetch, showError, t]);

  const handleMarkAsNew = useCallback(async () => {
    if (!metadata) return;
    setIsNewStatusLoading(true);
    try {
      await ArchiveService.setIsNew(metadata.arcid);
      await refetch();
    } catch (err) {
      logger.operationFailed('mark as new', err);
      showError(t('archive.markAsNewFailed'));
    } finally {
      setIsNewStatusLoading(false);
    }
  }, [metadata, refetch, showError, t]);

  const [deleteLoading, setDeleteLoading] = useState(false);
  const handleDeleteArchive = useCallback(async () => {
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
      router.push('/');
    } catch (err: any) {
      logger.operationFailed('delete archive', err);
      const errorMessage = err.response?.data?.error || err.message || '删除失败';
      showError(`删除失败: ${errorMessage}`);
    } finally {
      setDeleteLoading(false);
    }
  }, [confirm, isAdmin, metadata, router, showError, success]);

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
              <Button variant="outline">{t('archive.backToHome')}</Button>
            </Link>
          </div>
        </div>
      </div>
    );
  }

  return (
    <div className="min-h-screen bg-background pb-20 lg:pb-0">
      <main className="container mx-auto px-4 pt-6 pb-24 sm:pb-6 max-w-7xl">
        <div className="space-y-6">
          {/* Header / hero (unified with Tankoubon page) */}
          <div className="relative">
            <div className="relative rounded-2xl border bg-card/70 backdrop-blur">
              <div className="p-4 md:p-5">
                <div className="flex flex-col gap-6 md:flex-row md:items-start md:justify-between">
                  <div className="flex min-w-0 gap-4">
                    <div className="relative h-40 w-28 shrink-0 overflow-hidden rounded-xl border bg-muted md:h-52 md:w-36">
                      <Image
                        src={`/api/archives/${metadata.arcid}/thumbnail`}
                        alt={metadata.title || ''}
                        fill
                        className="object-cover"
                        sizes="(max-width: 768px) 112px, 144px"
                        unoptimized
                      />
                    </div>

                    <div className="min-w-0">
                      <div className="flex flex-wrap items-center gap-3">
                        <Badge className="bg-primary">
                          <BookOpen className="w-3 h-3 mr-1" />
                          {t('archive.archiveLabel')}
                        </Badge>
                        <h1 className="text-xl md:text-2xl font-bold tracking-tight break-words">
                          {metadata.title}
                        </h1>
                      </div>

                      {metadata.summary ? (
                        <p className="mt-2 text-sm text-muted-foreground max-w-3xl line-clamp-3">
                          {metadata.summary}
                        </p>
                      ) : (
                        <p className="mt-2 text-sm text-muted-foreground italic">{t('archive.noSummary')}</p>
                      )}

                      {tags.length > 0 ? (
                        <div className="mt-3 flex flex-wrap gap-2">
                          {tags.map((fullTag) => (
                            <Badge
                              key={fullTag}
                              variant="secondary"
                              className="cursor-pointer max-w-full"
                              title={fullTag}
                              onClick={() => handleTagClick(fullTag)}
                            >
                              <span className="truncate">{stripNamespace(fullTag)}</span>
                            </Badge>
                          ))}
                        </div>
                      ) : null}
                    </div>
                  </div>

                  <div className="flex shrink-0 flex-wrap items-center gap-2">
                    <Button
                      size="sm"
                      variant="outline"
                      className={`h-9 w-9 p-0 ${isFavorite ? 'text-red-500 border-red-500' : ''}`}
                      title={isFavorite ? t('common.unfavorite') : t('common.favorite')}
                      disabled={!isAuthenticated || favoriteLoading}
                      onClick={handleFavoriteClick}
                    >
                      <Heart className={`w-4 h-4 ${isFavorite ? 'fill-current' : ''}`} />
                    </Button>

                    <Button
                      size="sm"
                      variant="outline"
                      className="h-9 w-9 p-0"
                      title={t('archive.download')}
                      onClick={() => {
                        const downloadUrl = ArchiveService.getDownloadUrl(metadata.arcid);
                        window.open(downloadUrl, '_blank');
                      }}
                    >
                      <Download className="w-4 h-4" />
                    </Button>

                    {metadata.isnew ? (
                      <Button
                        size="sm"
                        variant="outline"
                        className="h-9 w-9 p-0"
                        title={t('archive.markAsRead')}
                        disabled={!isAuthenticated || isNewStatusLoading}
                        onClick={handleMarkAsRead}
                      >
                        <CheckCircle className="w-4 h-4" />
                      </Button>
                    ) : (
                      <Button
                        size="sm"
                        variant="outline"
                        className="h-9 w-9 p-0"
                        title={t('archive.markAsNew')}
                        disabled={!isAuthenticated || isNewStatusLoading}
                        onClick={handleMarkAsNew}
                      >
                        <RotateCcw className="w-4 h-4" />
                      </Button>
                    )}

                    <Button
                      variant="outline"
                      size="sm"
                      className="h-9 w-9 p-0"
                      title={t('common.edit')}
                      disabled={!isAuthenticated}
                      onClick={openEditDialog}
                    >
                      <Edit className="w-4 h-4" />
                    </Button>

                    {isAdmin ? (
                      <Button
                        variant="outline"
                        size="sm"
                        className="h-9 w-9 p-0 text-destructive"
                        title={t('common.delete')}
                        disabled={deleteLoading}
                        onClick={handleDeleteArchive}
                      >
                        <Trash2 className="w-4 h-4" />
                      </Button>
                    ) : null}
                  </div>
                </div>

                <div className="mt-4 grid gap-2 sm:grid-cols-3">
                  <div className="rounded-xl border bg-background/60 p-3">
                    <p className="text-xs text-muted-foreground">{t('archive.pageCount')}</p>
                    <p className="mt-0.5 text-xl font-semibold tabular-nums">{metadata.pagecount}</p>
                  </div>
                  <div className="rounded-xl border bg-background/60 p-3">
                    <p className="text-xs text-muted-foreground">{t('archive.updatedAt')}</p>
                    <p className="mt-0.5 text-sm font-medium tabular-nums truncate" title={metadata.updated_at}>
                      {metadata.updated_at || t('archive.unknown')}
                    </p>
                  </div>
                  <div className="rounded-xl border bg-background/60 p-3">
                    <div className="flex items-center justify-between">
                      <p className="text-xs text-muted-foreground">{t('archive.progress')}</p>
                      <p className="text-xs text-muted-foreground tabular-nums">
                        {Math.max(0, Math.min(100, Math.round(metadata.progress ?? 0)))}%
                      </p>
                    </div>
                    <Progress className="mt-1.5" value={Math.max(0, Math.min(100, Math.round(metadata.progress ?? 0)))} />
                  </div>
                </div>

                <div className="mt-4 hidden sm:block">
                  <Link href={`/reader?id=${metadata.arcid}`}>
                    <Button>
                      <BookOpen className="w-4 h-4 mr-2" />
                      {t('archive.startReading')}
                    </Button>
                  </Link>
                </div>
              </div>
            </div>
          </div>

          {/* Edit metadata dialog (aligned with Tankoubon page) */}
          <Dialog open={editDialogOpen} onOpenChange={setEditDialogOpen}>
            <DialogContent>
              <DialogHeader>
                <DialogTitle>{t('archive.editMetadata')}</DialogTitle>
              </DialogHeader>
              <DialogBody className="pt-0">
                <div className="space-y-4">
                  <div>
                    <label className="text-sm font-medium">{t('archive.titleField')}</label>
                    <Input value={editTitle} onChange={(e) => setEditTitle(e.target.value)} disabled={isSaving} />
                  </div>
                  <div>
                    <label className="text-sm font-medium">{t('archive.summary')}</label>
                    <Textarea
                      value={editSummary}
                      onChange={(e) => setEditSummary(e.target.value)}
                      placeholder={t('archive.summaryPlaceholder')}
                      rows={3}
                      disabled={isSaving}
                    />
                  </div>
                  <div>
                    <label className="text-sm font-medium">{t('tankoubon.metadataPluginLabel')}</label>
                    <div className="mt-2 flex flex-col gap-2">
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
                        <div className="text-xs text-muted-foreground flex items-center justify-between gap-2">
                          <span className="truncate" title={metadataPluginMessage}>
                            {metadataPluginMessage || ''}
                          </span>
                          {metadataPluginProgress !== null && (
                            <span className="tabular-nums">{Math.max(0, Math.min(100, metadataPluginProgress))}%</span>
                          )}
                        </div>
                      )}
                      {metadataPlugins.length === 0 && (
                        <div className="text-xs text-muted-foreground">{t('archive.metadataPluginNoPlugins')}</div>
                      )}
                    </div>
                  </div>
                  <div>
                    <label className="text-sm font-medium">{t('archive.tags')}</label>
                    <TagInput
                      value={editTags}
                      onChange={setEditTags}
                      placeholder={t('archive.tagsPlaceholder')}
                      disabled={isSaving}
                    />
                  </div>
                </div>
              </DialogBody>
              <DialogFooter>
                <Button variant="outline" onClick={() => setEditDialogOpen(false)} disabled={isSaving}>
                  {t('common.cancel')}
                </Button>
                <Button onClick={saveEdit} disabled={isSaving || !editTitle.trim()}>
                  {t('common.save')}
                </Button>
              </DialogFooter>
            </DialogContent>
          </Dialog>

          <ArchivePreviewCard
            metadata={metadata}
            t={t}
            showPreview={showPreview}
            setShowPreview={setShowPreview}
            previewLoading={previewLoading}
            previewError={previewError}
            archivePages={archivePages}
            displayPages={displayPages}
            loadingImages={loadingImages}
            loadMorePages={loadMorePages}
            handleImageLoadEnd={handleImageLoadEnd}
            handleImageError={handleImageError}
          />

          {tankoubonsLoading || tankoubons.length > 0 ? (
            <ArchiveCollectionsCard
              t={t}
              currentArchiveId={metadata.arcid}
              tankoubons={tankoubons}
              previewArchivesByTankoubonId={tankoubonPreviewArchives}
              loading={tankoubonsLoading}
            />
          ) : null}

          <ArchiveBasicInfoCard metadata={metadata} t={t} />
        </div>
      </main>

      <ArchiveMobileActions
        metadata={metadata}
        t={t}
        isEditing={false}
        isAuthenticated={isAuthenticated}
        isAdmin={isAdmin}
        isFavorite={isFavorite}
        favoriteLoading={favoriteLoading}
        isNewStatusLoading={isNewStatusLoading}
        deleteLoading={deleteLoading}
        onFavoriteClick={handleFavoriteClick}
        onMarkAsRead={handleMarkAsRead}
        onMarkAsNew={handleMarkAsNew}
        onStartEdit={openEditDialog}
        onDeleteArchive={handleDeleteArchive}
      />
    </div>
  );
}
