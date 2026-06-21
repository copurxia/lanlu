'use client';

import { useSearchParams, useRouter } from 'next/navigation';
import { useState, useEffect, useCallback, useMemo } from 'react';
import dynamic from 'next/dynamic';
import Link from 'next/link';
import Image from 'next/image';
import { ArchiveService, type MetadataPagePatchInput } from '@/lib/services/archive-service';
import { parseSourceId } from '@/lib/utils/source-id-utils';
import { SourcePluginService } from '@/lib/services/source-plugin-service';
import { CategoryService } from '@/lib/services/category-service';

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
import { ArchiveBasicInfoCard } from './components/ArchiveBasicInfoCard';
import { ArchiveMobileActions } from './components/ArchiveMobileActions';
import { useArchiveTankoubons } from './hooks/useArchiveTankoubons';
import { BaseMediaCardEditController } from '@/components/ui/base-media-card-edit-controller';
import { ArchiveSearchTagBadge } from '@/components/archive/ArchiveSearchTagBadge';
import { RecommendationCardRow } from '@/components/recommendations/RecommendationCardRow';
import type { Archive } from '@/types/archive';
import type { RecommendationItemType } from '@/types/recommendation';
import { BookOpen, Download, Edit, Heart, RotateCcw, CheckCircle, Trash2, FolderPlus } from 'lucide-react';

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
  const [metadataPluginPreviewPages, setMetadataPluginPreviewPages] = useState<MetadataPagePatchInput[]>([]);
  const [previewRefreshToken, setPreviewRefreshToken] = useState(0);
  const { previewLoading, previewError, displayPages } =
    useArchivePreview({ id, showPreview, t, refreshToken: previewRefreshToken });

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

  const trackRelatedInteraction = useCallback(async (
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
  }, [metadataArcid]);

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
  const backdropAssetId = getArchiveAssetId(metadata, 'backdrop');
  const backdropUrl = backdropAssetId ? `/api/assets/${backdropAssetId}` : '';

  return (
    <div className="relative min-h-dvh bg-background pb-[calc(env(safe-area-inset-bottom)+4rem)] lg:pb-0">
      {backdropUrl ? (
        <div className="pointer-events-none fixed inset-0 z-0" aria-hidden="true">
          <Image src={backdropUrl} alt="" fill className="scale-105 object-cover opacity-30 blur-[2px]" unoptimized />
          <div className="absolute inset-0 bg-linear-to-b from-background/35 via-background/55 to-background/95 dark:from-background/65 dark:via-background/80 dark:to-background" />
        </div>
      ) : null}
      {/* Reserve space for the fixed mobile action bar (includes safe-area inset). */}
      <main className="relative z-10 container mx-auto px-4 pt-6 pb-2 sm:pb-6 max-w-7xl">
        <div className="space-y-6">
          {/* Header / hero (unified with Tankoubon page) */}
          <div className="relative">
            <div className="relative rounded-2xl border-none bg-transparent shadow-none dark:bg-transparent">
              <div className="p-0">
                <div className="flex flex-col gap-6 md:flex-row md:items-start md:justify-between">
                  <div className="flex min-w-0 gap-4">
                    <div className="relative h-52 w-36 shrink-0 overflow-hidden rounded-xl border-none bg-muted sm:h-56 sm:w-40 md:h-64 md:w-44 lg:h-72 lg:w-48">
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
                        <h1 className="text-lg sm:text-xl md:text-2xl font-bold tracking-tight wrap-break-word">
                          {metadata.title}
                        </h1>
                      </div>

                      {/* Keep stats directly under title on all screen sizes (same as mobile). */}
                      <div className="mt-2">
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
                          <span className="tabular-nums">
                            {t('archive.progress')} {progressPercent}%
                          </span>
                        </div>
                        {progressPercent > 0 ? (
                          <Progress className="mt-2 h-1.5" value={progressPercent} />
                        ) : null}
                      </div>

                      {/* Desktop/tablet actions now sit above summary/tags. */}
                      <div className="hidden sm:inline-flex mt-4 w-fit shrink-0 flex-col items-start gap-3">
                        <div className="inline-flex flex-wrap items-center justify-start gap-2">
                          <Link href={`/reader?id=${encodeURIComponent(rawId ?? metadata.arcid)}`}>
                            <Button size="sm" variant="default" className="h-9">
                              <BookOpen className="w-4 h-4 mr-2" />
                              {t('archive.startReading')}
                            </Button>
                          </Link>

                          {!isSourceMode && (
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
                          )}

                          <Button
                            size="sm"
                            variant="outline"
                            className={`h-9 w-9 p-0 ${isFavorite ? 'text-red-500 border-red-500' : ''}`}
                            title={isFavorite ? t('common.unfavorite') : t('common.favorite')}
                            disabled={!isAuthenticated || favoriteLoading || isSourceMode}
                            onClick={handleFavoriteClick}
                          >
                            <Heart className={`w-4 h-4 ${isFavorite ? 'fill-current' : ''}`} />
                          </Button>

                          <Button
                            size="sm"
                            variant="outline"
                            className="h-9 w-9 p-0"
                            title={t('archive.download')}
                            onClick={async () => {
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
                            }}
                          >
                            <Download className="w-4 h-4" />
                          </Button>

                          {!isSourceMode && (
                            metadata.isnew ? (
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
                            )
                          )}

                          {!isSourceMode && (
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
                          )}

                          {!isSourceMode && isAdmin ? (
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

                      {/* Summary/tags now follow the action row. */}
                      <div className="hidden sm:block mt-4">
                        {metadata.description ? (
                          <p className="text-sm text-muted-foreground max-w-3xl line-clamp-3">
                            {metadata.description}
                          </p>
                        ) : (
                          <p className="text-sm text-muted-foreground italic">{t('archive.noSummary')}</p>
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
                    {metadata.description ? (
                      <p className="text-sm text-muted-foreground max-w-3xl line-clamp-3">
                        {metadata.description}
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

                </div>
              </div>
            </div>
          </div>

          {editDialogOpen && metadata ? (
            <BaseMediaCardEditController
              id={metadata.arcid}
              type="archive"
              initialTitle={metadata.title || ''}
              initialSummary={metadata.description || ''}
              initialTags={Array.isArray(metadata.tags) ? metadata.tags.join(', ') : (metadata.tags || '')}
              thumbnailAssetId={metadata.assets?.cover}
              onOpenChange={setEditDialogOpen}
              onSaved={() => {
                setEditDialogOpen(false);
                refetch();
              }}
            />
          ) : null}

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

          {(relatedLoading || relatedArchives.length > 0) ? (
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
