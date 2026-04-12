'use client';

import type { MouseEvent } from 'react';
import { memo, startTransition, useCallback, useEffect, useMemo, useRef, useState } from 'react';
import Link from 'next/link';
import { Check, Eye, Film, Heart, Square } from 'lucide-react';
import { FeedPreviewPlaceholder } from '@/components/home/HomeFeedLoading';
import { HomeMediaItemMenu } from '@/components/home/HomeMediaItemMenu';
import { useArchivePreviewFeed } from '@/components/home/useArchivePreviewFeed';
import { Button } from '@/components/ui/button';
import { Spinner } from '@/components/ui/spinner';
import { MemoizedImage } from '@/components/reader/components/MemoizedMedia';
import { useLanguage } from '@/contexts/LanguageContext';
import { ArchiveService, type PageInfo } from '@/lib/services/archive-service';
import { getArchiveAssetId, getCoverAssetId } from '@/lib/utils/archive-assets';
import {
  computeChannelPreviewLayout,
  DEFAULT_CHANNEL_ASPECT_RATIO,
  type ChannelPreviewLayoutItem,
} from '@/lib/utils/channel-preview-layout';
import { buildExactTagSearchQuery, parseTags, stripNamespace } from '@/lib/utils/tag-utils';
import { cn } from '@/lib/utils/utils';
import type { Archive } from '@/types/archive';
import type { Tankoubon } from '@/types/tankoubon';

const CHANNEL_PREVIEW_LIMIT = 9;
const CHANNEL_PREVIEW_SOURCE_SCAN_LIMIT = 24;
const CHANNEL_PREVIEW_INTERSECTION_MARGIN = '0px 0px';
const CHANNEL_PREVIEW_INSERT_TIMEOUT_MS = 1200;
const channelPreviewAspectRatioCache = new Map<string, number>();
const channelPreviewMediaWarmCache = new Set<string>();
const CHANNEL_PREVIEW_FILE_PARAMS = {
  limit: CHANNEL_PREVIEW_SOURCE_SCAN_LIMIT,
  offset: 0,
  include_metadata: true,
} as const;

function getChannelPreviewAspectRatioCacheKey(archiveId: string, pageKey: string): string {
  return `${archiveId}|${pageKey}`;
}

type HomeMediaChannelProps = {
  items: Array<Archive | Tankoubon>;
  selectionMode: boolean;
  selectedArchiveIds: Set<string>;
  selectedTankoubonIds: Set<string>;
  onRequestEnterSelection: () => void;
  onToggleArchiveSelect: (id: string, selected: boolean) => void;
  onToggleTankoubonSelect: (id: string, selected: boolean) => void;
};

type ChannelTag = {
  canonical: string;
  label: string;
};

type ChannelPreviewItem = {
  alt: string;
  aspectRatio: number;
  id: string;
  mediaKind: 'image' | 'video' | 'video-poster';
  measurementKey: string;
  posterSrc?: string;
  src: string;
};

type ChannelPreviewSource = {
  id: string;
  label: string;
  mediaKind: ChannelPreviewItem['mediaKind'];
  pageKey: string;
  posterSrc?: string;
  src: string;
};

type HomeMediaChannelCardProps = {
  description: string;
  detailPath: string;
  id: string;
  isFavorite: boolean;
  isNew?: boolean;
  progress?: number;
  rawTags: string;
  readerTargetId?: string;
  previewArchiveId?: string;
  contentMeta: string;
  contentWidth: number;
  selectionMode: boolean;
  selected: boolean;
  thumbnailAssetId?: number;
  title: string;
  type: 'archive' | 'tankoubon';
  onToggleSelected: (selected: boolean) => void;
  onRequestEnterSelection: () => void;
};

function isTankoubonItem(item: Archive | Tankoubon): item is Tankoubon {
  return 'tankoubon_id' in item;
}

function extractAuthor(tags: string, fallback: string): string {
  const artistTag = parseTags(tags).find((tag) => tag.trim().toLowerCase().startsWith('artist:'));
  if (!artistTag) return fallback;
  const label = stripNamespace(artistTag).trim();
  return label || fallback;
}

function buildChannelTags(rawTags: string): ChannelTag[] {
  return parseTags(rawTags)
    .filter((tag) => {
      const namespace = tag.split(':', 1)[0]?.trim().toLowerCase() || '';
      return namespace !== 'artist';
    })
    .slice(0, 10)
    .map((tag) => ({
      canonical: tag,
      label: `#${stripNamespace(tag).replace(/\s+/g, '')}`,
    }));
}

function getAuthorInitial(author: string): string {
  const trimmed = author.trim();
  if (!trimmed) return '?';
  return Array.from(trimmed)[0]?.toUpperCase() || '?';
}

function getPagePreviewMedia(page: PageInfo): { mediaKind: ChannelPreviewItem['mediaKind']; posterSrc?: string; src: string } | null {
  const pageMetadata = ArchiveService.getPageDisplayMetadata(page);
  const pageUrl = ArchiveService.getResolvedPageUrl(page);
  const posterSrc = pageMetadata?.thumb?.trim() || '';
  if (page.type === 'video') {
    if (posterSrc) {
      return {
        mediaKind: 'video-poster',
        posterSrc,
        src: posterSrc,
      };
    }
    if (!pageUrl.trim()) return null;
    return {
      mediaKind: 'video',
      src: pageUrl.trim(),
    };
  }
  if (page.type === 'image' && pageUrl.trim()) {
    return {
      mediaKind: 'image',
      posterSrc: posterSrc || undefined,
      src: posterSrc || pageUrl.trim(),
    };
  }
  if (posterSrc) {
    return {
      mediaKind: 'image',
      posterSrc,
      src: posterSrc,
    };
  }
  return null;
}

async function loadChannelPreviewSources(archiveId: string): Promise<ChannelPreviewSource[]> {
  const result = await ArchiveService.getFiles(archiveId, CHANNEL_PREVIEW_FILE_PARAMS);
  return result.pages
    .flatMap((page, index) => {
      const media = getPagePreviewMedia(page);
      if (!media) return [];
      const pageKey = ArchiveService.getPagePrimaryKey(page) || String(index);
      return [{
        id: `${archiveId}:${pageKey}`,
        label: page.title || '',
        mediaKind: media.mediaKind,
        pageKey,
        posterSrc: media.posterSrc,
        src: media.src,
      }];
    })
    .slice(0, CHANNEL_PREVIEW_LIMIT);
}

function preloadChannelPreviewImage(src: string): Promise<void> {
  if (!src) return Promise.resolve();
  if (channelPreviewMediaWarmCache.has(src)) return Promise.resolve();

  return new Promise((resolve) => {
    const image = new Image();
    let settled = false;

    const finish = () => {
      if (settled) return;
      settled = true;
      image.onload = null;
      image.onerror = null;
      resolve();
    };

    const markLoaded = () => {
      channelPreviewMediaWarmCache.add(src);
      finish();
    };

    image.onload = () => {
      if (typeof image.decode !== 'function') {
        markLoaded();
        return;
      }
      void image.decode().then(markLoaded).catch(markLoaded);
    };
    image.onerror = finish;
    image.src = src;

    if (image.complete) {
      if (typeof image.decode !== 'function') {
        markLoaded();
        return;
      }
      void image.decode().then(markLoaded).catch(markLoaded);
    }
  });
}

const ChannelPreviewTile = memo(function ChannelPreviewTile({
  item,
  onMeasure,
  onVideoReady,
  videoReady,
  className,
  style,
}: {
  item: ChannelPreviewItem;
  onMeasure: (cacheKey: string, aspectRatio: number) => void;
  onVideoReady: (id: string) => void;
  videoReady: boolean;
  className?: string;
  style?: React.CSSProperties;
}) {
  return (
    <div
      className={cn('channel-layout-tile relative flex h-full items-center justify-center overflow-hidden bg-muted', className)}
      data-ready={item.mediaKind === 'video' ? String(videoReady || Boolean(item.posterSrc)) : 'true'}
      style={style}
    >
      {item.mediaKind === 'video' ? (
        <>
          {!videoReady && !item.posterSrc ? (
            <div className="pointer-events-none absolute inset-0 z-10 flex items-center justify-center bg-muted/85 text-muted-foreground">
              <Film className="h-8 w-8" />
            </div>
          ) : null}
          <video
            src={item.src}
            poster={item.posterSrc || undefined}
            className="block h-full w-auto max-w-none"
            muted
            loop
            playsInline
            preload="metadata"
            onLoadedMetadata={(event) => {
              const video = event.currentTarget;
              const naturalWidth = video.videoWidth;
              const naturalHeight = video.videoHeight;
              if (!naturalWidth || !naturalHeight) return;
              onMeasure(item.measurementKey, naturalWidth / naturalHeight);
            }}
            onLoadedData={() => {
              onVideoReady(item.id);
            }}
          />
        </>
      ) : (
        <>
          <MemoizedImage
            src={item.src}
            alt={item.alt}
            className="block h-full w-auto max-w-none"
            decoding="async"
            fetchPriority="low"
            loading="lazy"
            draggable={false}
            onLoad={(event) => {
              const image = event.currentTarget;
              const naturalWidth = image.naturalWidth || image.width;
              const naturalHeight = image.naturalHeight || image.height;
              if (!naturalWidth || !naturalHeight) return;
              onMeasure(item.measurementKey, naturalWidth / naturalHeight);
            }}
          />
          {item.mediaKind === 'video-poster' ? (
            <div className="pointer-events-none absolute right-3 top-3 rounded-full bg-black/55 p-2 text-white shadow-xs backdrop-blur-xs">
              <Film className="h-4 w-4" />
            </div>
          ) : null}
        </>
      )}
    </div>
  );
});

const ChannelPreviewMedia = memo(function ChannelPreviewMedia({
  contentWidth,
  emptyLabel,
  items,
  loading,
  onMeasure,
  placeholderVisible,
}: {
  contentWidth: number;
  emptyLabel: string;
  items: ChannelPreviewItem[];
  loading: boolean;
  onMeasure: (cacheKey: string, aspectRatio: number) => void;
  placeholderVisible: boolean;
}) {
  const [videoReadyMap, setVideoReadyMap] = useState<Record<string, boolean>>({});
  const itemIdsKey = useMemo(() => items.map((item) => item.id).join('|'), [items]);

  useEffect(() => {
    setVideoReadyMap({});
  }, [itemIdsKey]);

  const effectiveWidth = Math.max(contentWidth, 320);
  const layout = useMemo<ReturnType<typeof computeChannelPreviewLayout<ChannelPreviewItem & ChannelPreviewLayoutItem>>>(() => (
    computeChannelPreviewLayout(items, effectiveWidth)
  ), [effectiveWidth, items]);

  const handleVideoReady = useCallback((id: string) => {
    setVideoReadyMap((current) => {
      if (current[id]) return current;
      return {
        ...current,
        [id]: true,
      };
    });
  }, []);

  if (placeholderVisible) {
    return <FeedPreviewPlaceholder className="aspect-16/10 w-full rounded-none" />;
  }

  return (
    <div className="channel-layout-shell feed-media-fade w-full">
      {items.length === 0 ? (
        <div className="flex aspect-16/10 w-full items-center justify-center bg-muted px-4 text-center text-sm text-muted-foreground">
          {loading ? <Spinner size="sm" /> : emptyLabel}
        </div>
      ) : layout.kind === 'single' ? (
        <div
          className="channel-layout-single flex w-full items-center justify-center overflow-hidden bg-muted"
          style={{
            height: `${layout.heroHeight}px`,
          }}
        >
          <ChannelPreviewTile
            item={layout.hero}
            onMeasure={onMeasure}
            onVideoReady={handleVideoReady}
            videoReady={Boolean(videoReadyMap[layout.hero.id])}
            style={{ width: '100%' }}
          />
        </div>
      ) : layout.kind === 'rows' ? (
        <div className="channel-layout-stack flex max-h-[460px] w-full flex-col gap-px overflow-hidden bg-border">
          {layout.rows.map((row, rowIndex) => (
            <div
              key={`row-${rowIndex}`}
              className="channel-layout-row flex gap-px"
              style={{
                height: `${row.height}px`,
              }}
            >
              {row.items.map((item) => (
                <ChannelPreviewTile
                  key={item.id}
                  item={item}
                  className="shrink-0"
                  onMeasure={onMeasure}
                  onVideoReady={handleVideoReady}
                  videoReady={Boolean(videoReadyMap[item.id])}
                  style={{ width: `${item.width}px` }}
                />
              ))}
            </div>
          ))}
        </div>
      ) : layout.kind === 'hero-side' ? (
        <div
          className="channel-layout-split grid max-h-[460px] w-full gap-px overflow-hidden bg-border"
          style={{
            gridTemplateColumns: `${layout.heroWidth}px ${Math.max(0, effectiveWidth - layout.heroWidth - 1)}px`,
            height: `${layout.totalHeight}px`,
          }}
        >
          <ChannelPreviewTile
            item={layout.hero}
            onMeasure={onMeasure}
            onVideoReady={handleVideoReady}
            videoReady={Boolean(videoReadyMap[layout.hero.id])}
            style={{ width: `${layout.heroWidth}px` }}
          />
          <div className="channel-layout-stack flex flex-col gap-px overflow-hidden">
            {layout.rows.map((row, rowIndex) => (
              <div
                key={`side-row-${rowIndex}`}
                className="channel-layout-row flex gap-px"
                style={{
                  height: `${row.height}px`,
                }}
              >
                {row.items.map((item) => (
                  <ChannelPreviewTile
                    key={item.id}
                    item={item}
                    className="shrink-0"
                    onMeasure={onMeasure}
                    onVideoReady={handleVideoReady}
                    videoReady={Boolean(videoReadyMap[item.id])}
                    style={{ width: `${item.width}px` }}
                  />
                ))}
              </div>
            ))}
          </div>
        </div>
      ) : (
        <div className="channel-layout-stack flex max-h-[460px] w-full flex-col gap-px overflow-hidden bg-border">
          <div
            className="channel-layout-single flex"
            style={{
              height: `${layout.heroHeight}px`,
            }}
          >
            <ChannelPreviewTile
              item={layout.hero}
              onMeasure={onMeasure}
              onVideoReady={handleVideoReady}
              videoReady={Boolean(videoReadyMap[layout.hero.id])}
              style={{ width: '100%' }}
            />
          </div>
          {layout.rows.map((row, rowIndex) => (
            <div
              key={`row-${rowIndex}`}
              className="channel-layout-row flex gap-px"
              style={{
                height: `${row.height}px`,
              }}
            >
              {row.items.map((item) => (
                <ChannelPreviewTile
                  key={item.id}
                  item={item}
                  className="shrink-0"
                  onMeasure={onMeasure}
                  onVideoReady={handleVideoReady}
                  videoReady={Boolean(videoReadyMap[item.id])}
                  style={{ width: `${item.width}px` }}
                />
              ))}
            </div>
          ))}
        </div>
      )}
    </div>
  );
});

function HomeMediaChannelCard({
  description,
  detailPath,
  id,
  isFavorite,
  isNew = false,
  progress,
  rawTags,
  readerTargetId,
  previewArchiveId,
  contentMeta,
  contentWidth,
  selectionMode,
  selected,
  thumbnailAssetId,
  title,
  type,
  onToggleSelected,
  onRequestEnterSelection,
}: HomeMediaChannelCardProps) {
  const { t } = useLanguage();
  const [previewLayoutVersion, setPreviewLayoutVersion] = useState(0);
  const [contentExpanded, setContentExpanded] = useState(false);
  const [previewGateOpen, setPreviewGateOpen] = useState(false);
  const layoutFlushFrameRef = useRef<number | null>(null);
  const {
    items: previewSources,
    loading: previewLoading,
    ready: previewReady,
    targetRef: previewRef,
  } = useArchivePreviewFeed<ChannelPreviewSource, HTMLButtonElement>({
    archiveId: previewArchiveId,
    eager: false,
    enabled: Boolean(previewArchiveId),
    loaderKey: 'channel-preview',
    loadItems: loadChannelPreviewSources,
    rootMargin: CHANNEL_PREVIEW_INTERSECTION_MARGIN,
  });
  const previewSourceIdsKey = useMemo(() => previewSources.map((item) => item.id).join('|'), [previewSources]);

  const handleMeasurePreview = useCallback((cacheKey: string, aspectRatio: number) => {
    const normalized = Number.isFinite(aspectRatio) && aspectRatio > 0
      ? aspectRatio
      : DEFAULT_CHANNEL_ASPECT_RATIO;

    const current = channelPreviewAspectRatioCache.get(cacheKey) ?? DEFAULT_CHANNEL_ASPECT_RATIO;
    if (Math.abs(current - normalized) < 0.01) return;
    channelPreviewAspectRatioCache.set(cacheKey, normalized);
    if (layoutFlushFrameRef.current != null) return;
    layoutFlushFrameRef.current = window.requestAnimationFrame(() => {
      layoutFlushFrameRef.current = null;
      setPreviewLayoutVersion((value) => value + 1);
    });
  }, []);

  useEffect(() => {
    return () => {
      if (layoutFlushFrameRef.current == null) return;
      window.cancelAnimationFrame(layoutFlushFrameRef.current);
    };
  }, []);

  useEffect(() => {
    setPreviewGateOpen(false);
  }, [previewArchiveId, previewSourceIdsKey]);

  useEffect(() => {
    let cancelled = false;
    if (!previewReady) return () => {
      cancelled = true;
    };

    if (previewSources.length === 0) {
      setPreviewGateOpen(true);
      return () => {
        cancelled = true;
      };
    }

    let gateOpened = false;
    const openGate = () => {
      if (cancelled || gateOpened) return;
      gateOpened = true;
      startTransition(() => {
        setPreviewGateOpen(true);
      });
    };

    const timeoutId = window.setTimeout(openGate, CHANNEL_PREVIEW_INSERT_TIMEOUT_MS);
    const preloadTasks = previewSources
      .map((item) => {
        if (item.mediaKind === 'video') return null;
        return preloadChannelPreviewImage(item.src);
      })
      .filter((task): task is Promise<void> => task !== null);

    void Promise.all(preloadTasks)
      .then(openGate)
      .catch(openGate)
      .finally(() => {
        window.clearTimeout(timeoutId);
      });

    return () => {
      cancelled = true;
      window.clearTimeout(timeoutId);
    };
  }, [previewReady, previewSourceIdsKey, previewSources.length]);

  return (
    <HomeMediaItemMenu
      id={id}
      type={type}
      title={title}
      description={description}
      tags={rawTags}
      thumbnailAssetId={thumbnailAssetId}
      readerTargetId={readerTargetId}
      isFavorite={isFavorite}
      isNew={isNew}
      progress={progress}
      selectable
      selectionMode={selectionMode}
      selected={selected}
      onToggleSelect={onToggleSelected}
      onRequestEnterSelection={onRequestEnterSelection}
    >
      {({
        displayDescription,
        displayTags,
        displayTitle,
        favoriteLoading,
        handleContextMenu,
        handleContextMenuCapture,
        isFavorite: nextIsFavorite,
        navigateToReader,
        toggleFavorite,
        toggleSelected,
      }) => {
        const author = extractAuthor(displayTags, type === 'archive' ? t('home.unknownArtist') : t('tankoubon.collection'));
        const tags = buildChannelTags(displayTags);
        const contentText = [displayTitle.trim(), displayDescription.trim()].filter(Boolean).join('\n\n');
        const canToggleContent = contentText.length > 180 || contentText.includes('\n');
        const previewItems: ChannelPreviewItem[] = previewArchiveId
          ? previewSources.map((item, index) => {
              const measurementKey = getChannelPreviewAspectRatioCacheKey(previewArchiveId, item.pageKey);
              return {
                alt: item.label || `${displayTitle || author} ${index + 1}`,
                aspectRatio: channelPreviewAspectRatioCache.get(measurementKey) || DEFAULT_CHANNEL_ASPECT_RATIO,
                id: item.id,
                mediaKind: item.mediaKind,
                measurementKey,
                posterSrc: item.posterSrc,
                src: item.src,
              };
            })
          : [];
        const visiblePreviewItems = previewGateOpen ? previewItems : [];
        const showPreviewPlaceholder = Boolean(previewArchiveId) && (!previewReady || (previewItems.length > 0 && !previewGateOpen));

        void previewLayoutVersion;

        return (
          <article
            className={cn('feed-card-enter px-1 py-2', selected && 'rounded-3xl bg-primary/6 dark:bg-primary/10')}
            style={{
              contentVisibility: 'auto',
              containIntrinsicSize: '380px 760px',
            }}
            onContextMenuCapture={handleContextMenuCapture}
            onContextMenu={handleContextMenu}
          >
            <div className="flex items-end gap-3">
              <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-full bg-sky-100 text-sm font-semibold text-sky-700 dark:bg-sky-950/60 dark:text-sky-300">
                {getAuthorInitial(author)}
              </div>

              <div className="min-w-0 flex-1">
                <div
                  className={cn(
                    'group relative w-full overflow-hidden rounded-[1.75rem] rounded-bl-md border border-border/70 bg-card/95 text-card-foreground shadow-[0_16px_40px_hsl(var(--foreground)/0.08)] backdrop-blur-sm transition-[background-color,border-color,box-shadow] duration-200 dark:bg-card/88 dark:shadow-[0_20px_48px_hsl(220_40%_2%/0.35)]',
                    selected && 'ring-2 ring-primary/30'
                  )}
                >
                  <div className="pointer-events-none absolute right-3 top-3 z-10 opacity-0 transition-opacity duration-150 group-hover:opacity-100 group-focus-within:opacity-100">
                    <div className="pointer-events-auto flex items-center gap-2 rounded-full border border-border/60 bg-background/88 px-2 py-1 text-foreground shadow-[0_10px_28px_hsl(var(--foreground)/0.12)] backdrop-blur-md dark:bg-background/78 dark:shadow-[0_14px_30px_hsl(220_40%_2%/0.42)]">
                      <Button
                        asChild
                        variant="ghost"
                        size="icon"
                        className="h-8 w-8 rounded-full text-muted-foreground hover:bg-accent/80 hover:text-accent-foreground"
                        title={t('archive.details')}
                      >
                        <Link href={detailPath} prefetch={false} onClick={(event) => event.stopPropagation()}>
                          <Eye className="h-4 w-4" />
                        </Link>
                      </Button>

                      <Button
                        type="button"
                        variant="ghost"
                        size="icon"
                        className={cn(
                          'h-8 w-8 rounded-full text-muted-foreground hover:bg-accent/80 hover:text-accent-foreground',
                          nextIsFavorite && 'text-red-500'
                        )}
                        title={nextIsFavorite ? t('common.unfavorite') : t('common.favorite')}
                        disabled={favoriteLoading}
                        onClick={(event: MouseEvent<HTMLButtonElement>) => {
                          event.stopPropagation();
                          void toggleFavorite();
                        }}
                      >
                        {favoriteLoading ? <Spinner size="sm" /> : <Heart className={cn('h-4 w-4', nextIsFavorite && 'fill-current')} />}
                      </Button>

                      <Button
                        type="button"
                        variant={selected ? 'default' : 'ghost'}
                        size="icon"
                        className="h-8 w-8 rounded-full"
                        aria-label={selected ? t('home.unselectItem') : t('home.selectItem')}
                        title={selected ? t('home.unselectItem') : t('home.selectItem')}
                        onClick={(event: MouseEvent<HTMLButtonElement>) => {
                          event.stopPropagation();
                          toggleSelected(!selected);
                        }}
                      >
                        {selected ? <Check className="h-4 w-4" /> : <Square className="h-4 w-4" />}
                      </Button>
                    </div>
                  </div>

                  <button
                    type="button"
                    ref={previewRef}
                    className="block w-full overflow-hidden text-left transition-[opacity,filter] duration-200 hover:opacity-95"
                    onClick={() => {
                      if (selectionMode) {
                        toggleSelected(!selected);
                        return;
                      }
                      navigateToReader();
                    }}
                  >
                    <ChannelPreviewMedia
                      contentWidth={contentWidth}
                      items={visiblePreviewItems}
                      loading={previewLoading}
                      emptyLabel={displayTitle || author}
                      onMeasure={handleMeasurePreview}
                      placeholderVisible={showPreviewPlaceholder}
                    />
                  </button>

                  <div className="space-y-3 px-4 py-3 sm:px-5">
                    {contentText ? (
                      <div>
                        <div
                          className={cn(
                            'whitespace-pre-wrap wrap-break-word text-[15px] leading-6 text-card-foreground',
                            !contentExpanded && canToggleContent && 'line-clamp-5'
                          )}
                        >
                          {contentText}
                        </div>
                        {canToggleContent ? (
                          <button
                            type="button"
                            className="mt-2 text-sm font-medium text-sky-600 transition-colors hover:text-sky-500 hover:underline dark:text-sky-400 dark:hover:text-sky-300"
                            onClick={(event) => {
                              event.stopPropagation();
                              setContentExpanded((current) => !current);
                            }}
                          >
                            {contentExpanded ? t('common.collapse') : t('common.expand')}
                          </button>
                        ) : null}
                      </div>
                    ) : null}

                    {tags.length > 0 ? (
                      <div className="flex flex-wrap gap-x-3 gap-y-1 text-sm">
                        {tags.map((tag) => {
                          const exactQuery = buildExactTagSearchQuery(tag.canonical);
                          const href = exactQuery ? `/?q=${encodeURIComponent(exactQuery)}` : '/';
                          return (
                            <Link
                              key={`${id}-${tag.canonical}`}
                              href={href}
                              prefetch={false}
                              className="font-medium text-sky-600 transition-colors hover:text-sky-500 hover:underline dark:text-sky-400 dark:hover:text-sky-300"
                            >
                              {tag.label}
                            </Link>
                          );
                        })}
                      </div>
                    ) : null}

                    <div className="flex justify-end">
                      <span className="text-xs text-muted-foreground">{contentMeta}</span>
                    </div>
                  </div>
                </div>
              </div>
            </div>
          </article>
        );
      }}
    </HomeMediaItemMenu>
  );
}

const HomeArchiveChannelRow = memo(function HomeArchiveChannelRow({
  archive,
  contentWidth,
  selectionMode,
  selected,
  onRequestEnterSelection,
  onToggleArchiveSelect,
}: {
  archive: Archive;
  contentWidth: number;
  selectionMode: boolean;
  selected: boolean;
  onRequestEnterSelection: () => void;
  onToggleArchiveSelect: (id: string, selected: boolean) => void;
}) {
  const { t } = useLanguage();
  const contentMeta = `${t('archive.pages').replace('{count}', String(archive.pagecount))}${archive.progress > 0 && archive.pagecount > 0 ? ` · ${Math.round((archive.progress / archive.pagecount) * 100)}% ${t('common.read')}` : ''}`;
  const coverAssetId = getArchiveAssetId(archive, 'cover');

  return (
    <HomeMediaChannelCard
      id={archive.arcid}
      type="archive"
      title={archive.title}
      description={archive.description}
      rawTags={archive.tags}
      detailPath={`/archive?id=${archive.arcid}`}
      readerTargetId={archive.arcid}
      previewArchiveId={archive.arcid}
      contentMeta={contentMeta}
      contentWidth={contentWidth}
      selectionMode={selectionMode}
      selected={selected}
      isFavorite={Boolean(archive.isfavorite)}
      isNew={archive.isnew}
      progress={archive.progress}
      thumbnailAssetId={coverAssetId}
      onToggleSelected={(nextSelected) => onToggleArchiveSelect(archive.arcid, nextSelected)}
      onRequestEnterSelection={onRequestEnterSelection}
    />
  );
});

const HomeTankoubonChannelRow = memo(function HomeTankoubonChannelRow({
  tankoubon,
  contentWidth,
  selectionMode,
  selected,
  onRequestEnterSelection,
  onToggleTankoubonSelect,
}: {
  tankoubon: Tankoubon;
  contentWidth: number;
  selectionMode: boolean;
  selected: boolean;
  onRequestEnterSelection: () => void;
  onToggleTankoubonSelect: (id: string, selected: boolean) => void;
}) {
  const { t } = useLanguage();
  const firstArchiveId = typeof tankoubon.children?.[0] === 'string' ? tankoubon.children[0] : '';
  const pageCount = typeof tankoubon.pagecount === 'number' ? tankoubon.pagecount : 0;
  const archiveCount = typeof tankoubon.archive_count === 'number' ? tankoubon.archive_count : 0;
  const coverAssetId = getCoverAssetId(tankoubon);

  return (
    <HomeMediaChannelCard
      id={tankoubon.tankoubon_id}
      type="tankoubon"
      title={tankoubon.title}
      description={tankoubon.description}
      rawTags={tankoubon.tags}
      detailPath={`/tankoubon?id=${tankoubon.tankoubon_id}`}
      readerTargetId={firstArchiveId || undefined}
      previewArchiveId={firstArchiveId || undefined}
      contentMeta={`${archiveCount} ${t('tankoubon.archives')} · ${t('tankoubon.totalPages').replace('{count}', String(pageCount))}`}
      contentWidth={contentWidth}
      selectionMode={selectionMode}
      selected={selected}
      isFavorite={Boolean(tankoubon.isfavorite)}
      isNew={Boolean(tankoubon.isnew)}
      thumbnailAssetId={coverAssetId}
      onToggleSelected={(nextSelected) => onToggleTankoubonSelect(tankoubon.tankoubon_id, nextSelected)}
      onRequestEnterSelection={onRequestEnterSelection}
    />
  );
});

export const HomeMediaChannel = memo(function HomeMediaChannel({
  items,
  selectionMode,
  selectedArchiveIds,
  selectedTankoubonIds,
  onRequestEnterSelection,
  onToggleArchiveSelect,
  onToggleTankoubonSelect,
}: HomeMediaChannelProps) {
  const containerRef = useRef<HTMLDivElement | null>(null);
  const [contentWidth, setContentWidth] = useState(0);
  const resizeFrameRef = useRef<number | null>(null);

  useEffect(() => {
    const element = containerRef.current;
    if (!element) return;

    const updateWidth = () => {
      const nextWidth = element.clientWidth;
      setContentWidth((current) => (current === nextWidth ? current : nextWidth));
    };

    updateWidth();

    const scheduleWidthUpdate = () => {
      if (resizeFrameRef.current != null) return;
      resizeFrameRef.current = window.requestAnimationFrame(() => {
        resizeFrameRef.current = null;
        updateWidth();
      });
    };

    if (typeof ResizeObserver === 'undefined') {
      window.addEventListener('resize', scheduleWidthUpdate);
      return () => {
        window.removeEventListener('resize', scheduleWidthUpdate);
        if (resizeFrameRef.current != null) {
          window.cancelAnimationFrame(resizeFrameRef.current);
        }
      };
    }

    const observer = new ResizeObserver(scheduleWidthUpdate);
    observer.observe(element);
    return () => {
      observer.disconnect();
      if (resizeFrameRef.current != null) {
        window.cancelAnimationFrame(resizeFrameRef.current);
      }
    };
  }, []);

  return (
    <div ref={containerRef} className="space-y-4">
      {items.map((item, index) => {
        if (isTankoubonItem(item)) {
          return (
            <HomeTankoubonChannelRow
              key={`tankoubon:${item.tankoubon_id}`}
              tankoubon={item}
              contentWidth={contentWidth}
              selectionMode={selectionMode}
              selected={selectedTankoubonIds.has(item.tankoubon_id)}
              onRequestEnterSelection={onRequestEnterSelection}
              onToggleTankoubonSelect={onToggleTankoubonSelect}
            />
          );
        }

        return (
            <HomeArchiveChannelRow
              key={`archive:${item.arcid}`}
              archive={item}
              contentWidth={contentWidth}
              selectionMode={selectionMode}
              selected={selectedArchiveIds.has(item.arcid)}
              onRequestEnterSelection={onRequestEnterSelection}
            onToggleArchiveSelect={onToggleArchiveSelect}
          />
        );
      })}
    </div>
  );
});
