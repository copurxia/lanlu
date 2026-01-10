'use client';

import { useSearchParams, useRouter } from 'next/navigation';
import { useState, useEffect, useCallback, useMemo } from 'react';
import Link from 'next/link';
import { ArchiveService } from '@/lib/services/archive-service';
import { PluginService, type Plugin } from '@/lib/services/plugin-service';
import { FavoriteService } from '@/lib/services/favorite-service';
import { Button } from '@/components/ui/button';
import { useLanguage } from '@/contexts/LanguageContext';
import { useAuth } from '@/contexts/AuthContext';
import { useToast } from '@/hooks/use-toast';
import { useConfirmContext } from '@/contexts/ConfirmProvider';
import { logger } from '@/lib/utils/logger';
import { useMounted } from './hooks/useMounted';
import { useArchiveMetadata } from './hooks/useArchiveMetadata';
import { useArchivePreview } from './hooks/useArchivePreview';
import { displayTag } from './utils/tag';
import { ArchiveCoverCard } from './components/ArchiveCoverCard';
import { ArchiveMainCard } from './components/ArchiveMainCard';
import { ArchivePreviewCard } from './components/ArchivePreviewCard';
import { ArchiveBasicInfoCard } from './components/ArchiveBasicInfoCard';
import { ArchiveMobileActions } from './components/ArchiveMobileActions';
import { ArchiveCollectionsCard } from './components/ArchiveCollectionsCard';
import { useArchiveTankoubons } from './hooks/useArchiveTankoubons';

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

  const handleTagClick = useCallback(
    (fullTag: string) => {
      router.push(`/?q=${encodeURIComponent(displayTag(fullTag))}`);
    },
    [router]
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

  const startEdit = useCallback(() => {
    if (!metadata) return;
    if (!isAuthenticated) return;
    setFormData({
      title: metadata.title || '',
      summary: metadata.summary || '',
      tags,
    });
    setIsEditing(true);
  }, [isAuthenticated, metadata, tags]);

  const cancelEdit = useCallback(() => {
    setIsEditing(false);
    if (!metadata) return;
    setFormData({
      title: metadata.title || '',
      summary: metadata.summary || '',
      tags,
    });
  }, [metadata, tags]);

  const saveEdit = useCallback(async () => {
    if (!metadata) return;
    setIsSaving(true);
    try {
      await ArchiveService.updateMetadata(
        metadata.arcid,
        { title: formData.title, summary: formData.summary, tags: formData.tags.join(', ') },
        language
      );
      setIsEditing(false);
      await refetch();
    } catch (err) {
      logger.operationFailed('update metadata', err);
      showError(t('archive.updateFailed'));
    } finally {
      setIsSaving(false);
    }
  }, [formData.summary, formData.tags, formData.title, language, metadata, refetch, showError, t]);

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
      const finalTask = await ArchiveService.runMetadataPlugin(metadata.arcid, selectedMetadataPlugin, metadataPluginParam, {
        onUpdate: (task) => {
          setMetadataPluginProgress(typeof task.progress === 'number' ? task.progress : 0);
          setMetadataPluginMessage(task.message || '');
        },
      });

      if (finalTask.status !== 'completed') {
        const err = finalTask.result || finalTask.message || t('archive.metadataPluginFailed');
        showError(err);
        return;
      }

      const updated = await refetch();
      if (updated) {
        setFormData({
          title: updated.title || '',
          summary: updated.summary || '',
          tags: updated.tags ? updated.tags.split(',').map((tag) => tag.trim()).filter((tag) => tag) : [],
        });
      }
      setMetadataPluginMessage(t('archive.metadataPluginCompleted'));
      setMetadataPluginProgress(100);
    } catch (e: any) {
      logger.operationFailed('run metadata plugin', e);
      showError(e?.message || t('archive.metadataPluginFailed'));
    } finally {
      setIsMetadataPluginRunning(false);
    }
  }, [isAuthenticated, metadata, metadataPluginParam, refetch, selectedMetadataPlugin, showError, t]);

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
    <div className="min-h-screen">
      <main className="container mx-auto px-4 pt-6 pb-24 sm:pb-6 max-w-7xl">
        <div className="space-y-6">
          <div className="grid grid-cols-1 lg:grid-cols-12 gap-6 lg:gap-8">
            <div className="lg:col-span-5 xl:col-span-4">
              <ArchiveCoverCard arcid={metadata.arcid} title={metadata.title} noCoverLabel={t('archive.noCover')} />
            </div>

            <div className="lg:col-span-7 xl:col-span-8 h-full">
              <ArchiveMainCard
                metadata={metadata}
                t={t}
                tags={tags}
                isEditing={isEditing}
                isSaving={isSaving}
                formData={formData}
                setFormData={setFormData}
                isAuthenticated={isAuthenticated}
                isAdmin={isAdmin}
                isFavorite={isFavorite}
                favoriteLoading={favoriteLoading}
                isNewStatusLoading={isNewStatusLoading}
                deleteLoading={deleteLoading}
                onStartEdit={startEdit}
                onCancelEdit={cancelEdit}
                onSaveEdit={saveEdit}
                onFavoriteClick={handleFavoriteClick}
                onMarkAsRead={handleMarkAsRead}
                onMarkAsNew={handleMarkAsNew}
                onDeleteArchive={handleDeleteArchive}
                onTagClick={handleTagClick}
                metadataPlugins={metadataPlugins}
                selectedMetadataPlugin={selectedMetadataPlugin}
                setSelectedMetadataPlugin={setSelectedMetadataPlugin}
                metadataPluginParam={metadataPluginParam}
                setMetadataPluginParam={setMetadataPluginParam}
                isMetadataPluginRunning={isMetadataPluginRunning}
                metadataPluginProgress={metadataPluginProgress}
                metadataPluginMessage={metadataPluginMessage}
                onRunMetadataPlugin={runMetadataPlugin}
              />
            </div>
          </div>

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
        isEditing={isEditing}
        isAuthenticated={isAuthenticated}
        isAdmin={isAdmin}
        isFavorite={isFavorite}
        favoriteLoading={favoriteLoading}
        isNewStatusLoading={isNewStatusLoading}
        deleteLoading={deleteLoading}
        onFavoriteClick={handleFavoriteClick}
        onMarkAsRead={handleMarkAsRead}
        onMarkAsNew={handleMarkAsNew}
        onStartEdit={startEdit}
        onDeleteArchive={handleDeleteArchive}
      />
    </div>
  );
}
