'use client';

import { useSearchParams, useRouter } from 'next/navigation';
import { useState, useEffect, useCallback, useMemo } from 'react';
import dynamic from 'next/dynamic';
import Link from 'next/link';
import Image from 'next/image';
import { ArchiveService } from '@/lib/services/archive-service';
import { parseSourceId } from '@/lib/utils/source-id-utils';
import { FavoriteService } from '@/lib/services/favorite-service';
import { RecommendationService } from '@/lib/services/recommendation-service';
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
import { extractApiError } from '@/lib/utils/api-utils';

import { getTvMetaSummary, isTvArchiveMetadata } from '@/lib/utils/tv-media';
import { useArchiveMetadata } from './hooks/useArchiveMetadata';
import { useArchivePreview } from './hooks/useArchivePreview';
import { buildExactTagSearchQuery } from '@/lib/utils/tag-utils';
import { ArchiveMobileActions } from './components/ArchiveMobileActions';
import { useArchiveTankoubons } from './hooks/useArchiveTankoubons';
import { BaseMediaCardEditController } from '@/components/ui/base-media-card-edit-controller';
import { ArchiveSearchTagBadge } from '@/components/archive/ArchiveSearchTagBadge';
import { RecommendationCardRow } from '@/components/recommendations/RecommendationCardRow';
import { DetailHeroLayout } from '@/components/detail/DetailHeroLayout';
import { DetailContentGrid } from '@/components/detail/DetailContentGrid';
import { DetailSectionCard } from '@/components/detail/DetailSectionCard';
import { DetailActionPanel } from '@/components/detail/DetailActionPanel';
import { CollapsibleTagRow } from '@/components/detail/CollapsibleTagRow';
import { ArchiveBasicInfoCard } from './components/ArchiveBasicInfoCard';
import { ArchiveTagGroups } from './components/ArchiveTagGroups';
import type { Archive } from '@/types/archive';
import type { RecommendationItemType } from '@/types/recommendation';
import {
  BookOpen,
  Download,
  Edit,
  Heart,
  RotateCcw,
  CheckCircle,
  Trash2,
  FolderPlus,
} from 'lucide-react';

const AddToTankoubonDialog = dynamic(
  () => import('@/components/tankoubon/AddToTankoubonDialog').then((m) => m.AddToTankoubonDialog)
);
const ArchivePreviewCard = dynamic(
  () => import('./components/ArchivePreviewCard').then((m) => m.ArchivePreviewCard)
);
const ArchiveCollectionsCard = dynamic(
  () => import('./components/ArchiveCollectionsCard').then((m) => m.ArchiveCollectionsCard)
);

export function ArchiveDetailContent() {
  const router = useRouter();
  const searchParams = useSearchParams();
  const rawId = searchParams?.get('id') ?? null;
  const id = rawId;
  const sourceParsed = id ? parseSourceId(id) : null;
  const isSourceMode = sourceParsed !== null;
  const sourceNamespace = sourceParsed?.namespace ?? null;
  const remoteId = sourceParsed?.remoteId ?? null;
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

  const showPreview = true;
  const [relatedArchives, setRelatedArchives] = useState<Archive[]>([]);
  const [relatedLoading, setRelatedLoading] = useState(false);
  const [previewRefreshToken, setPreviewRefreshToken] = useState(0);
  const { previewLoading, previewError, displayPages } = useArchivePreview({
    id,
    showPreview,
    t,
    refreshToken: previewRefreshToken,
  });

  const pages = displayPages;

  const { tankoubons, tankoubonPreviewArchives, loading: tankoubonsLoading } = useArchiveTankoubons({
    archiveId: isSourceMode ? null : id,
  });

  const metadataTags = metadata?.tags;
  const metadataPageCount = typeof metadata?.pagecount === 'number' ? metadata.pagecount : 0;
  const metadataProgress = typeof metadata?.progress === 'number' ? metadata.progress : 0;
  const metadataArcid = metadata?.arcid;

  const tags = useMemo(() => {
    return Array.isArray(metadataTags)
      ? metadataTags.map((tag) => String(tag || '').trim()).filter(Boolean)
      : [];
  }, [metadataTags]);

  const progressPercent = useMemo(() => {
    if (!metadataPageCount || !metadataProgress) return 0;
    return Math.max(0, Math.min(100, Math.round((metadataProgress / metadataPageCount) * 100)));
  }, [metadataPageCount, metadataProgress]);
  const isTvArchive = useMemo(() => isTvArchiveMetadata(metadata), [metadata]);
  const tvMetaSummary = useMemo(() => getTvMetaSummary(metadataTags), [metadataTags]);

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
      const ok = await FavoriteService.setFavorite('archive', id, !isFavorite);
      if (ok) setIsFavorite(!isFavorite);
    } catch (err) {
      logger.operationFailed('toggle favorite', err);
    } finally {
      setFavoriteLoading(false);
    }
  }, [favoriteLoading, id, isFavorite, setIsFavorite]);

  useEffect(() => {
    if (!metadataArcid) {
      setRelatedArchives([]);
      setRelatedLoading(false);
      return;
    }

    let cancelled = false;
    setRelatedLoading(true);

    void RecommendationService.getArchiveRelated(metadataArcid, { count: 12, lang: language })
      .then((items) => {
        if (!cancelled) {
          setRelatedArchives(items);
        }
      })
      .catch((err) => {
        logger.apiError('fetch archive related recommendations', err);
        if (!cancelled) {
          setRelatedArchives([]);
        }
      })
      .finally(() => {
        if (!cancelled) {
          setRelatedLoading(false);
        }
      });

    return () => {
      cancelled = true;
    };
  }, [language, metadataArcid]);

  const trackRelatedInteraction = useCallback(
    async (
      interactionType: 'click' | 'open_reader' | 'favorite',
      itemType: RecommendationItemType,
      itemId: string
    ) => {
      if (!metadataArcid) return;

      try {
        await RecommendationService.recordInteraction({
          scene: 'archive_related',
          seed_entity_type: 'archive',
          seed_entity_id: metadataArcid,
          item_type: itemType,
          item_id: itemId,
          interaction_type: interactionType,
        });
      } catch (err) {
        logger.apiError(`track archive related ${interactionType}`, err);
      }
    },
    [metadataArcid]
  );

  const [editDialogOpen, setEditDialogOpen] = useState(false);

  const openEditDialog = useCallback(() => {
    if (!isAuthenticated) return;
    setEditDialogOpen(true);
  }, [isAuthenticated]);

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
    } catch (err) {
      logger.operationFailed('delete archive', err);
      const errorMessage = extractApiError(err, '删除失败');
      showError(`删除失败: ${errorMessage}`);
    } finally {
      setDeleteLoading(false);
    }
  }, [confirm, isAdmin, metadata, router, showError, success]);

  if (!mounted || loading) {
    return (
      <div className="min-h-dvh">
        <div className="mx-auto w-full max-w-[1400px] px-4 py-8">
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
        <div className="mx-auto w-full max-w-[1400px] px-4 py-8">
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
  const backdropAssetId = getArchiveAssetId(metadata, 'backdrop');
  const backdropUrl = backdropAssetId ? `/api/assets/${backdropAssetId}` : '';
  const clearlogoAssetId = getArchiveAssetId(metadata, 'clearlogo');
  const clearlogoUrl = clearlogoAssetId ? `/api/assets/${clearlogoAssetId}` : '';
  const readerHref =
    isSourceMode && sourceNamespace && remoteId
      ? `/reader?source=${encodeURIComponent(sourceNamespace)}&remote_id=${encodeURIComponent(remoteId)}`
      : `/reader?id=${encodeURIComponent(rawId ?? metadata.arcid)}`;

  const badges = (
    <>
      <Badge className="bg-primary text-primary-foreground hover:bg-primary/90">
        <BookOpen className="w-3 h-3 mr-1" />
        {t('archive.archiveLabel')}
      </Badge>
      {isTvArchive && tvMetaSummary.season ? (
        <Badge variant="secondary">S{tvMetaSummary.season.padStart(2, '0')}</Badge>
      ) : null}
      {isTvArchive && tvMetaSummary.status ? (
        <Badge variant="outline" className="capitalize">
          {tvMetaSummary.status}
        </Badge>
      ) : null}
      {isTvArchive && tvMetaSummary.year ? (
        <Badge variant="outline">{tvMetaSummary.year}</Badge>
      ) : null}
    </>
  );

  const metaRow = (
    <div className="flex flex-wrap items-center gap-x-3 gap-y-1 text-xs text-muted-foreground">
      <span className="tabular-nums">
        {isTvArchive ? t('archive.episodeCount') : t('archive.pageCount')} {metadata.pagecount}
      </span>
      <span className="text-muted-foreground/60">•</span>
      <span className="tabular-nums truncate" title={metadata.release_at}>
        {t('archive.releaseAt')} {metadata.release_at || t('archive.unknown')}
      </span>
      <span className="text-muted-foreground/60">•</span>
      <span className="tabular-nums truncate" title={metadata.updated_at}>
        {t('archive.updatedAt')} {metadata.updated_at || t('archive.unknown')}
      </span>
      <span className="text-muted-foreground/60">•</span>
      <span className="tabular-nums">{t('archive.progress')} {progressPercent}%</span>
      {progressPercent > 0 ? (
        <div className="w-full">
          <Progress className="mt-2 h-1.5" value={progressPercent} />
        </div>
      ) : null}
    </div>
  );

  const iconActions = [
    !isSourceMode
      ? {
          id: 'add-to-tankoubon',
          icon: <FolderPlus className="w-4 h-4" />,
          title: t('tankoubon.addToCollection'),
          dialog: (
            <AddToTankoubonDialog
              archiveId={metadata.arcid}
              trigger={
                <Button
                  type="button"
                  variant="outline"
                  size="icon"
                  className="h-10 w-full rounded-xl"
                  title={t('tankoubon.addToCollection')}
                >
                  <FolderPlus className="w-4 h-4" />
                </Button>
              }
            />
          ),
        }
      : null,
    {
      id: 'favorite',
      icon: <Heart className={`w-4 h-4 ${isFavorite ? 'fill-current' : ''}`} />,
      title: isFavorite ? t('common.unfavorite') : t('common.favorite'),
      onClick: handleFavoriteClick,
      disabled: !isAuthenticated || favoriteLoading || isSourceMode,
      className: isFavorite ? 'text-red-500 border-red-500' : '',
    },
    {
      id: 'download',
      icon: <Download className="w-4 h-4" />,
      title: t('archive.download'),
      onClick: async () => {
        if (isSourceMode && sourceNamespace && remoteId) {
          try {
            const sourceId = `source:${sourceNamespace}:${remoteId}`;
            await ArchiveService.downloadArchive(sourceId);
            success('下载任务已创建');
            router.push('/settings/tasks');
          } catch {
            showError('创建下载任务失败');
          }
          return;
        }
        void ArchiveService.downloadArchive(metadata.arcid);
      },
    },
    !isSourceMode
      ? {
          id: 'read-status',
          icon: metadata.isnew ? (
            <CheckCircle className="w-4 h-4" />
          ) : (
            <RotateCcw className="w-4 h-4" />
          ),
          title: metadata.isnew ? t('archive.markAsRead') : t('archive.markAsNew'),
          onClick: metadata.isnew ? handleMarkAsRead : handleMarkAsNew,
          disabled: !isAuthenticated || isNewStatusLoading,
        }
      : null,
    !isSourceMode
      ? {
          id: 'edit',
          icon: <Edit className="w-4 h-4" />,
          title: t('common.edit'),
          onClick: openEditDialog,
          disabled: !isAuthenticated,
        }
      : null,
    !isSourceMode && isAdmin
      ? {
          id: 'delete',
          icon: <Trash2 className="w-4 h-4" />,
          title: t('common.delete'),
          onClick: handleDeleteArchive,
          disabled: deleteLoading,
          destructive: true,
        }
      : null,
  ].filter(Boolean) as {
    id: string;
    icon: React.ReactNode;
    title: string;
    dialog?: React.ReactNode;
    onClick?: () => void;
    disabled?: boolean;
    destructive?: boolean;
    className?: string;
  }[];

  return (
    <div className="relative min-h-dvh bg-background overflow-hidden pb-[calc(env(safe-area-inset-bottom)+4rem)] lg:pb-0">
      {/* Top-only backdrop, fading into the page background (mirrors the prototype).
          Falls back to the cover image when no backdrop is available. */}
      {backdropUrl || coverAssetId ? (
        <div className="detail-backdrop" aria-hidden="true">
          <Image
            src={backdropUrl || `/api/assets/${coverAssetId}`}
            alt=""
            fill
            className="object-cover saturate-110"
            style={{ filter: 'blur(1px)' }}
            sizes="100vw"
            unoptimized
          />
          <div className="detail-backdrop-overlay" />
        </div>
      ) : null}

      <main className="relative z-10 mx-auto w-full max-w-[1400px] px-4 pt-6 pb-2 sm:pb-6">
        <div className="space-y-8">
          <DetailHeroLayout
            cover={
              coverAssetId ? (
                <Image
                  src={`/api/assets/${coverAssetId}`}
                  alt={metadata.title || ''}
                  fill
                  className="object-cover"
                  sizes="(max-width: 640px) 112px, (max-width: 1024px) 164px, 232px"
                  unoptimized
                />
              ) : (
                <div className="absolute inset-0 flex items-center justify-center text-xs text-muted-foreground">
                  {t('archive.noCover')}
                </div>
              )
            }
            badges={badges}
            title={metadata.title}
            meta={metaRow}
            description={metadata.description || undefined}
            tags={tags.length > 0 ? <CollapsibleTagRow items={tags.map(renderTagBadge)} /> : undefined}
            clearlogoUrl={clearlogoUrl || undefined}
            clearlogoAlt={metadata.title || ''}
            actions={
              <DetailActionPanel
                primary={{
                  label: t('archive.startReading'),
                  icon: <BookOpen className="w-4 h-4" />,
                  href: readerHref,
                }}
                actions={iconActions}
              />
            }
          />

          {editDialogOpen && metadata ? (
            <BaseMediaCardEditController
              id={metadata.arcid}
              type="archive"
              initialTitle={metadata.title || ''}
              initialSummary={metadata.description || ''}
              initialTags={
                Array.isArray(metadata.tags) ? metadata.tags.join(', ') : (metadata.tags || '')
              }
              thumbnailAssetId={metadata.assets?.cover}
              onOpenChange={setEditDialogOpen}
              onSaved={() => {
                setEditDialogOpen(false);
                refetch();
              }}
            />
          ) : null}

          <DetailContentGrid
            main={
              <>
                <ArchivePreviewCard
                  metadata={metadata}
                  t={t}
                  previewLoading={previewLoading}
                  previewError={previewError}
                  pages={pages}
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

                {relatedLoading || relatedArchives.length > 0 ? (
                  <section className="rounded-2xl border-none bg-transparent p-0 shadow-none dark:bg-transparent">
                    <div className="mb-4">
                      <h2 className="text-lg font-semibold">{t('archive.relatedTitle')}</h2>
                      <p className="text-sm text-muted-foreground">{t('archive.relatedDescription')}</p>
                    </div>

                    {relatedLoading ? (
                      <div className="flex min-h-32 items-center justify-center">
                        <p className="text-sm text-muted-foreground">{t('common.loading')}</p>
                      </div>
                    ) : relatedArchives.length > 0 ? (
                      <RecommendationCardRow
                        items={relatedArchives}
                        scene="archive_related"
                        seedEntityType="archive"
                        seedEntityId={metadata.arcid}
                        cardSurfaceClassName="border-none shadow-none bg-transparent"
                        onOpenReader={(itemType, itemId) => {
                          void trackRelatedInteraction('open_reader', itemType, itemId);
                        }}
                        onOpenDetails={(itemType, itemId) => {
                          void trackRelatedInteraction('click', itemType, itemId);
                        }}
                        onFavorite={(itemType, itemId) => {
                          void trackRelatedInteraction('favorite', itemType, itemId);
                        }}
                      />
                    ) : (
                      <p className="text-sm text-muted-foreground">{t('archive.noRelated')}</p>
                    )}
                  </section>
                ) : null}
              </>
            }
            side={
              <>
                {tags.length > 0 ? (
                  <DetailSectionCard title={t('archive.tagsAndMetadata') || '标签与元数据'} variant="glass">
                    <ArchiveTagGroups tags={tags} renderTag={renderTagBadge} />
                  </DetailSectionCard>
                ) : null}
                <ArchiveBasicInfoCard metadata={metadata} t={t} />
              </>
            }
          />
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
        isSourceMode={isSourceMode}
        sourceNamespace={sourceNamespace}
        remoteId={remoteId}
        onFavoriteClick={handleFavoriteClick}
        onMarkAsRead={handleMarkAsRead}
        onMarkAsNew={handleMarkAsNew}
        onStartEdit={openEditDialog}
        onDeleteArchive={handleDeleteArchive}
      />
    </div>
  );
}
