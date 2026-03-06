'use client';

import { useSearchParams, useRouter } from 'next/navigation';
import { useState, useEffect, useCallback, useMemo, useRef } from 'react';
import Link from 'next/link';
import Image from 'next/image';
import { ArchiveService } from '@/lib/services/archive-service';
import { TaskPoolService } from '@/lib/services/taskpool-service';
import { PluginService, type Plugin } from '@/lib/services/plugin-service';
import { FavoriteService } from '@/lib/services/favorite-service';
import { TagService } from '@/lib/services/tag-service';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { Progress } from '@/components/ui/progress';
import { useLanguage } from '@/contexts/LanguageContext';
import { useAuth } from '@/contexts/AuthContext';
import { useToast } from '@/hooks/use-toast';
import { useConfirmContext } from '@/contexts/ConfirmProvider';
import { logger } from '@/lib/utils/logger';
import { useMounted } from '@/hooks/common-hooks';
import { getArchiveAssetId } from '@/lib/utils/archive-assets';
import { useArchiveMetadata } from './hooks/useArchiveMetadata';
import { useArchivePreview } from './hooks/useArchivePreview';
import { buildExactTagSearchQuery } from '@/lib/utils/tag-utils';
import { ArchivePreviewCard } from './components/ArchivePreviewCard';
import { ArchiveBasicInfoCard } from './components/ArchiveBasicInfoCard';
import { ArchiveMobileActions } from './components/ArchiveMobileActions';
import { ArchiveCollectionsCard } from './components/ArchiveCollectionsCard';
import { useArchiveTankoubons } from './hooks/useArchiveTankoubons';
import { AddToTankoubonDialog } from '@/components/tankoubon/AddToTankoubonDialog';
import { ArchiveSearchTagBadge } from '@/components/archive/ArchiveSearchTagBadge';
import { ArchiveMetadataEditDialog, type RpcSelectRequest } from '@/components/archive/ArchiveMetadataEditDialog';
import { BookOpen, Download, Edit, Heart, RotateCcw, CheckCircle, Trash2, FolderPlus } from 'lucide-react';

function parseRpcSelectRequest(message: string): RpcSelectRequest | null {
  const prefix = '[RPC_SELECT]';
  if (!message?.startsWith(prefix)) return null;
  try {
    const parsed = JSON.parse(message.slice(prefix.length)) as RpcSelectRequest;
    if (!parsed?.request_id || !Array.isArray(parsed?.options) || parsed.options.length === 0) {
      return null;
    }
    return parsed;
  } catch {
    return null;
  }
}

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

  const progressPercent = useMemo(() => {
    const pagecount = typeof metadata?.pagecount === 'number' ? metadata.pagecount : 0;
    const progress = typeof metadata?.progress === 'number' ? metadata.progress : 0;
    if (!pagecount || !progress) return 0;
    return Math.max(0, Math.min(100, Math.round((progress / pagecount) * 100)));
  }, [metadata?.pagecount, metadata?.progress]);

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
      const exactQuery = buildExactTagSearchQuery(canonical);
      if (!exactQuery) return;
      router.push(`/?q=${encodeURIComponent(exactQuery)}`);
    },
    [router, toCanonicalTag]
  );

  const renderTagBadge = useCallback(
    (displayFullTag: string) => {
      const canonical = toCanonicalTag(displayFullTag);

      return (
        <ArchiveSearchTagBadge
          key={displayFullTag}
          displayFullTag={displayFullTag}
          canonicalFullTag={canonical}
          onClick={() => handleTagClick(displayFullTag)}
        />
      );
    },
    [handleTagClick, toCanonicalTag]
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
  const [editCover, setEditCover] = useState('');
  const [editBackdrop, setEditBackdrop] = useState('');
  const [editClearlogo, setEditClearlogo] = useState('');
  const [editAssetCoverId, setEditAssetCoverId] = useState('');
  const [editAssetBackdropId, setEditAssetBackdropId] = useState('');
  const [editAssetClearlogoId, setEditAssetClearlogoId] = useState('');

  const [metadataPlugins, setMetadataPlugins] = useState<Plugin[]>([]);
  const [selectedMetadataPlugin, setSelectedMetadataPlugin] = useState<string>('');
  const [metadataPluginParam, setMetadataPluginParam] = useState<string>('');
  const [isMetadataPluginRunning, setIsMetadataPluginRunning] = useState(false);
  const [metadataPluginProgress, setMetadataPluginProgress] = useState<number | null>(null);
  const [metadataPluginMessage, setMetadataPluginMessage] = useState<string>('');
  const [rpcSelectTaskId, setRpcSelectTaskId] = useState<number | null>(null);
  const [rpcSelectRequest, setRpcSelectRequest] = useState<RpcSelectRequest | null>(null);
  const [rpcSelectSelectedIndex, setRpcSelectSelectedIndex] = useState<number | null>(null);
  const [rpcSelectRemainingSeconds, setRpcSelectRemainingSeconds] = useState<number | null>(null);
  const resolvedRpcSelectRequestIdsRef = useRef<Set<string>>(new Set());

  useEffect(() => {
    if (!rpcSelectRequest || rpcSelectRemainingSeconds == null) return;
    if (rpcSelectRemainingSeconds <= 0) {
      setRpcSelectRequest(null);
      setRpcSelectTaskId(null);
      setRpcSelectSelectedIndex(null);
      setRpcSelectRemainingSeconds(null);
      return;
    }

    const timer = window.setTimeout(() => {
      setRpcSelectRemainingSeconds((current) => {
        if (current == null) return null;
        return Math.max(0, current - 1);
      });
    }, 1000);

    return () => window.clearTimeout(timer);
  }, [rpcSelectRemainingSeconds, rpcSelectRequest]);


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
    setEditCover('');
    setEditBackdrop('');
    setEditClearlogo('');
    setEditAssetCoverId(String(getArchiveAssetId(metadata, 'cover') || ''));
    setEditAssetBackdropId(String(getArchiveAssetId(metadata, 'backdrop') || ''));
    setEditAssetClearlogoId(String(getArchiveAssetId(metadata, 'clearlogo') || ''));
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
      const parseAssetId = (raw: string): number | undefined => {
        const value = Number(String(raw || '').trim());
        if (!Number.isFinite(value)) return undefined;
        const id = Math.trunc(value);
        return id > 0 ? id : undefined;
      };
      const assets = {
        cover: parseAssetId(editAssetCoverId),
        backdrop: parseAssetId(editAssetBackdropId),
        clearlogo: parseAssetId(editAssetClearlogoId),
      };
      await ArchiveService.updateMetadata(
        metadata.arcid,
        {
          title: editTitle,
          summary: editSummary,
          tags: canonicalTags.join(', '),
          cover: editCover || undefined,
          backdrop: editBackdrop || undefined,
          clearlogo: editClearlogo || undefined,
          assets,
        },
        language,
        { metadataNamespace: selectedMetadataPlugin || undefined }
      );
      setEditDialogOpen(false);
      await refetch();
    } catch (err) {
      logger.operationFailed('update metadata', err);
      showError(t('archive.updateFailed'));
    } finally {
      setIsSaving(false);
    }
  }, [editAssetBackdropId, editAssetClearlogoId, editAssetCoverId, editBackdrop, editClearlogo, editCover, editSummary, editTags, editTitle, language, metadata, refetch, selectedMetadataPlugin, showError, t, toCanonicalTag]);

  const submitRpcSelect = useCallback(async () => {
    if (rpcSelectTaskId == null || !rpcSelectRequest || rpcSelectSelectedIndex == null) return;
    const requestId = rpcSelectRequest.request_id;
    const ok = await TaskPoolService.respondRpcSelect(rpcSelectTaskId, requestId, rpcSelectSelectedIndex);
    resolvedRpcSelectRequestIdsRef.current.add(requestId);
    if (!ok) {
      showError('提交选择失败，可能请求已过期');
      setRpcSelectRequest(null);
      setRpcSelectTaskId(null);
      setRpcSelectSelectedIndex(null);
      setRpcSelectRemainingSeconds(null);
      return;
    }
    setRpcSelectRequest(null);
    setRpcSelectTaskId(null);
    setRpcSelectSelectedIndex(null);
    setRpcSelectRemainingSeconds(null);
  }, [rpcSelectRequest, rpcSelectSelectedIndex, rpcSelectTaskId, showError]);

  const abortRpcSelect = useCallback(async () => {
    if (rpcSelectTaskId == null || !rpcSelectRequest) return;
    const requestId = rpcSelectRequest.request_id;
    const ok = await TaskPoolService.abortRpcSelect(rpcSelectTaskId, requestId);
    resolvedRpcSelectRequestIdsRef.current.add(requestId);
    if (!ok) {
      showError('放弃选择失败，可能请求已过期');
      setRpcSelectRequest(null);
      setRpcSelectTaskId(null);
      setRpcSelectSelectedIndex(null);
      setRpcSelectRemainingSeconds(null);
      return;
    }
    setRpcSelectRequest(null);
    setRpcSelectTaskId(null);
    setRpcSelectSelectedIndex(null);
    setRpcSelectRemainingSeconds(null);
  }, [rpcSelectRequest, rpcSelectTaskId, showError]);

  const runMetadataPlugin = useCallback(async () => {
    if (!metadata) return;
    if (!isAuthenticated) return;
    if (!selectedMetadataPlugin) {
      showError(t('archive.metadataPluginSelectRequired'));
      return;
    }

    resolvedRpcSelectRequestIdsRef.current.clear();
    setIsMetadataPluginRunning(true);
    setMetadataPluginProgress(0);
    setMetadataPluginMessage(t('archive.metadataPluginEnqueued'));
    setRpcSelectRequest(null);
    setRpcSelectTaskId(null);
    setRpcSelectSelectedIndex(null);
    setRpcSelectRemainingSeconds(null);

    try {
      const metadataTags = editTags.map((tag) => toCanonicalTag(tag)).filter(Boolean);
      const toAssetValue = (pathValue: string, assetId: string): string => {
        const path = pathValue.trim();
        if (path) return path;
        const id = assetId.trim();
        if (/^\d+$/.test(id)) return id;
        return '';
      };
      const rootAssets = [
        { key: 'cover', value: toAssetValue(editCover, editAssetCoverId) },
        { key: 'backdrop', value: toAssetValue(editBackdrop, editAssetBackdropId) },
        { key: 'clearlogo', value: toAssetValue(editClearlogo, editAssetClearlogoId) },
      ].filter((item) => item.value);
      const finalTask = await ArchiveService.runMetadataPluginForTarget(
        'archive',
        metadata.arcid,
        selectedMetadataPlugin,
        metadataPluginParam,
        {
          onUpdate: (task) => {
            setMetadataPluginProgress(typeof task.progress === 'number' ? task.progress : 0);
            setMetadataPluginMessage(task.message || '');

            const req = parseRpcSelectRequest(task.message || '');
            if (req) {
              if (resolvedRpcSelectRequestIdsRef.current.has(req.request_id)) return;
              setRpcSelectTaskId(task.id);
              setRpcSelectRequest((current) => {
                if (current?.request_id === req.request_id) return current;
                const defaultIndex = typeof req.default_index === 'number' ? req.default_index : 0;
                setRpcSelectSelectedIndex(defaultIndex >= 0 && defaultIndex < req.options.length ? defaultIndex : 0);
                const timeout = typeof req.timeout_seconds === 'number' && req.timeout_seconds > 0 ? Math.floor(req.timeout_seconds) : 90;
                setRpcSelectRemainingSeconds(timeout);
                return req;
              });
            }
          },
        },
        // Preview by default: fill edit form, don't persist automatically.
        {
          writeBack: false,
          metadata: {
            title: editTitle,
            type: 0,
            description: editSummary,
            tags: metadataTags,
            assets: rootAssets,
            archive: [],
          },
        }
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
        const readAssetValue = (assets: unknown, key: string): string => {
          if (!Array.isArray(assets)) return '';
          for (const item of assets) {
            if (!item || typeof item !== 'object') continue;
            const row = item as Record<string, unknown>;
            const itemKey = String(row.key ?? row.type ?? row.name ?? '').trim().toLowerCase();
            if (itemKey !== key) continue;
            const value = row.value;
            if (typeof value === 'string') return value.trim();
            if (typeof value === 'number' && Number.isFinite(value)) return String(Math.trunc(value));
            return '';
          }
          return '';
        };
        const nextTitle = typeof data.title === 'string' ? data.title : '';
        const nextSummary = typeof data.description === 'string' ? data.description : '';
        const nextTags = Array.isArray(data.tags)
          ? data.tags.map((tag: unknown) => String(tag || '').trim()).filter(Boolean)
          : [];
        const nextCover = readAssetValue(data.assets, 'cover');
        const nextBackdrop = readAssetValue(data.assets, 'backdrop');
        const nextClearlogo = readAssetValue(data.assets, 'clearlogo');
        const applyAssetPreview = (
          rawValue: string,
          setPathValue: (next: string) => void,
          setAssetIdValue: (next: string) => void
        ) => {
          const trimmed = rawValue.trim();
          if (!trimmed) return;
          if (/^\d+$/.test(trimmed)) {
            const id = Number.parseInt(trimmed, 10);
            if (Number.isFinite(id) && id > 0) {
              setAssetIdValue(String(id));
              setPathValue('');
              return;
            }
          }
          setPathValue(trimmed);
        };

        if (nextTitle.trim()) setEditTitle(nextTitle.trim());
        setEditSummary(nextSummary);
        setEditTags(nextTags.map((tag: string) => toCanonicalTag(tag)));
        applyAssetPreview(nextCover, setEditCover, setEditAssetCoverId);
        applyAssetPreview(nextBackdrop, setEditBackdrop, setEditAssetBackdropId);
        applyAssetPreview(nextClearlogo, setEditClearlogo, setEditAssetClearlogoId);
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
      setRpcSelectRequest(null);
      setRpcSelectTaskId(null);
      setRpcSelectSelectedIndex(null);
      setRpcSelectRemainingSeconds(null);
    }
  }, [editAssetBackdropId, editAssetClearlogoId, editAssetCoverId, editBackdrop, editClearlogo, editCover, editSummary, editTags, editTitle, isAuthenticated, metadata, metadataPluginParam, selectedMetadataPlugin, showError, t, toCanonicalTag]);

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
      <div className="min-h-dvh">
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
      <div className="min-h-dvh">
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

  const coverAssetId = getArchiveAssetId(metadata, 'cover');

  return (
    <div className="min-h-dvh bg-background pb-[calc(env(safe-area-inset-bottom)+4rem)] lg:pb-0">
      {/* Reserve space for the fixed mobile action bar (includes safe-area inset). */}
      <main className="container mx-auto px-4 pt-6 pb-2 sm:pb-6 max-w-7xl">
        <div className="space-y-6">
          {/* Header / hero (unified with Tankoubon page) */}
          <div className="relative">
            <div className="relative rounded-2xl border bg-card/70 backdrop-blur">
              <div className="p-4 md:p-5">
                <div className="flex flex-col gap-6 md:flex-row md:items-start md:justify-between">
                  <div className="flex min-w-0 gap-4">
                    <div className="relative h-52 w-36 shrink-0 overflow-hidden rounded-xl border bg-muted sm:h-56 sm:w-40 md:h-64 md:w-44 lg:h-72 lg:w-48">
                      {coverAssetId ? (
                        <Image
                          src={`/api/assets/${coverAssetId}`}
                          alt={metadata.title || ''}
                          fill
                          className="object-cover"
                          sizes="(max-width: 640px) 144px, (max-width: 768px) 160px, (max-width: 1024px) 176px, 192px"
                          unoptimized
                        />
                      ) : (
                        <div className="absolute inset-0 flex items-center justify-center text-xs text-muted-foreground">
                          {t('archive.noCover')}
                        </div>
                      )}
                    </div>

                    <div className="min-w-0 flex-1">
                      <div className="flex flex-wrap items-center gap-3">
                        <Badge className="bg-primary">
                          <BookOpen className="w-3 h-3 mr-1" />
                          {t('archive.archiveLabel')}
                        </Badge>
                        <h1 className="text-lg sm:text-xl md:text-2xl font-bold tracking-tight break-words">
                          {metadata.title}
                        </h1>
                      </div>

                      {/* Keep stats directly under title on all screen sizes (same as mobile). */}
                      <div className="mt-2">
                        <div className="flex flex-wrap items-center gap-x-3 gap-y-1 text-xs text-muted-foreground">
                          <span className="tabular-nums">
                            {t('archive.pageCount')} {metadata.pagecount}
                          </span>
                          <span className="text-muted-foreground/60">•</span>
                          <span className="tabular-nums truncate" title={metadata.updated_at}>
                            {t('archive.updatedAt')} {metadata.updated_at || t('archive.unknown')}
                          </span>
                          <span className="text-muted-foreground/60">•</span>
                          <span className="tabular-nums">
                            {t('archive.progress')} {progressPercent}%
                          </span>
                        </div>
                        {progressPercent > 0 ? (
                          <Progress className="mt-2 h-1.5" value={progressPercent} />
                        ) : null}
                      </div>

                      {/* On mobile, summary/tags span full width below (to avoid an empty left column under the cover). */}
                      <div className="hidden sm:block">
                        {metadata.summary ? (
                          <p className="mt-2 text-sm text-muted-foreground max-w-3xl line-clamp-3">
                            {metadata.summary}
                          </p>
                        ) : (
                          <p className="mt-2 text-sm text-muted-foreground italic">{t('archive.noSummary')}</p>
                        )}

                        {tags.length > 0 ? (
                          <div className="mt-3 flex flex-wrap gap-2">
                            {tags.map(renderTagBadge)}
                          </div>
                        ) : null}
                      </div>
                    </div>
                  </div>

                  {/* Mobile: show summary/tags full width (not constrained to the title column). */}
                  <div className="sm:hidden w-full">
                    {metadata.summary ? (
                      <p className="text-sm text-muted-foreground max-w-3xl line-clamp-3">
                        {metadata.summary}
                      </p>
                    ) : (
                      <p className="text-sm text-muted-foreground italic">{t('archive.noSummary')}</p>
                    )}

                    {tags.length > 0 ? (
                      <div className="mt-3 flex flex-wrap gap-2 w-full">
                        {tags.map(renderTagBadge)}
                      </div>
                    ) : null}
                  </div>

                  {/* Desktop/tablet actions; mobile uses the bottom action bar */}
                  <div className="hidden sm:flex shrink-0 flex-wrap items-center gap-2">
                    <AddToTankoubonDialog
                      archiveId={metadata.arcid}
                      trigger={
                        <Button
                          size="sm"
                          variant="outline"
                          className="h-9 w-9 p-0"
                          title={t('tankoubon.addToCollection')}
                        >
                          <FolderPlus className="w-4 h-4" />
                        </Button>
                      }
                    />

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

                    <Link href={`/reader?id=${metadata.arcid}`} className="ml-auto">
                      <Button size="sm" variant="default" className="h-9">
                        <BookOpen className="w-4 h-4 mr-2" />
                        {t('archive.startReading')}
                      </Button>
                    </Link>
                  </div>
                </div>


              </div>
            </div>
          </div>

          <ArchiveMetadataEditDialog
            open={editDialogOpen}
            onOpenChange={setEditDialogOpen}
            t={t}
            title={editTitle}
            onTitleChange={setEditTitle}
            summary={editSummary}
            onSummaryChange={setEditSummary}
            assetCoverId={editAssetCoverId}
            onAssetCoverIdChange={setEditAssetCoverId}
            assetBackdropId={editAssetBackdropId}
            onAssetBackdropIdChange={setEditAssetBackdropId}
            assetClearlogoId={editAssetClearlogoId}
            onAssetClearlogoIdChange={setEditAssetClearlogoId}
            tags={editTags}
            onTagsChange={setEditTags}
            isSaving={isSaving}
            saveDisabled={!editTitle.trim()}
            onSave={saveEdit}
            metadataPlugins={metadataPlugins}
            selectedMetadataPlugin={selectedMetadataPlugin}
            onSelectedMetadataPluginChange={setSelectedMetadataPlugin}
            metadataPluginParam={metadataPluginParam}
            onMetadataPluginParamChange={setMetadataPluginParam}
            isMetadataPluginRunning={isMetadataPluginRunning}
            metadataPluginProgress={metadataPluginProgress}
            metadataPluginMessage={metadataPluginMessage}
            onRunMetadataPlugin={runMetadataPlugin}
            rpcSelect={{
              request: rpcSelectRequest,
              selectedIndex: rpcSelectSelectedIndex,
              remainingSeconds: rpcSelectRemainingSeconds,
              onSelectIndex: setRpcSelectSelectedIndex,
              onAbort: abortRpcSelect,
              onSubmit: submitRpcSelect,
            }}
          />

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
