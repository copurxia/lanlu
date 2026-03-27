'use client';

import type { MouseEvent } from 'react';
import { memo, useCallback, useEffect, useMemo, useRef, useState } from 'react';
import Link from 'next/link';
import { Check, Eye, Film, Heart, Square } from 'lucide-react';
import { HomeMediaItemMenu } from '@/components/home/HomeMediaItemMenu';
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
const channelPreviewCache = new Map<string, PageInfo[]>();
const channelPreviewAspectRatioCache = new Map<string, number>();
const CHANNEL_PREVIEW_FILE_PARAMS = {
  limit: CHANNEL_PREVIEW_SOURCE_SCAN_LIMIT,
  offset: 0,
  media_types: 'image,video',
  include_metadata: true,
} as const;

function getChannelPreviewCacheKey(archiveId: string): string {
  return `${archiveId}|${CHANNEL_PREVIEW_FILE_PARAMS.limit}|${CHANNEL_PREVIEW_FILE_PARAMS.offset}|${CHANNEL_PREVIEW_FILE_PARAMS.media_types}|${CHANNEL_PREVIEW_FILE_PARAMS.include_metadata ? 'meta' : 'bare'}`;
}

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
  measurementKey: string;
  posterSrc?: string;
  src: string;
  type: PageInfo['type'];
};

type HomeMediaChannelCardProps = {
  description: string;
  detailPath: string;
  id: string;
  isFavorite: boolean;
  isNew?: boolean;
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

function getPagePreviewMedia(page: PageInfo): { posterSrc?: string; src: string } | null {
  const posterSrc = page.metadata?.thumb?.trim() || '';
  if (page.type === 'video' && page.url.trim()) {
    return {
      posterSrc: posterSrc || undefined,
      src: page.url.trim(),
    };
  }
  if (page.type === 'image' && page.url.trim()) {
    return {
      posterSrc: posterSrc || undefined,
      src: posterSrc || page.url.trim(),
    };
  }
  return null;
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
    <div className={cn('flex h-full items-center justify-center overflow-hidden bg-muted', className)} style={style}>
      {item.type === 'video' ? (
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
        <MemoizedImage
          src={item.src}
          alt={item.alt}
          className="block h-full w-auto max-w-none"
          decoding="async"
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
}: {
  contentWidth: number;
  emptyLabel: string;
  items: ChannelPreviewItem[];
  loading: boolean;
  onMeasure: (cacheKey: string, aspectRatio: number) => void;
}) {
  const [videoReadyMap, setVideoReadyMap] = useState<Record<string, boolean>>({});

  useEffect(() => {
    setVideoReadyMap({});
  }, [items]);

  const normalizedItems = useMemo<Array<ChannelPreviewItem & ChannelPreviewLayoutItem>>(() => items.map((item) => ({
    ...item,
  })), [items]);
  const effectiveWidth = Math.max(contentWidth, 320);
  const layout = useMemo(() => computeChannelPreviewLayout(
    normalizedItems.map((item) => ({
      ...item,
    })),
    effectiveWidth
  ), [effectiveWidth, normalizedItems]);

  const handleVideoReady = useCallback((id: string) => {
    setVideoReadyMap((current) => {
      if (current[id]) return current;
      return {
        ...current,
        [id]: true,
      };
    });
  }, []);

  return (
    <div className="w-full">
      {items.length === 0 ? (
        <div className="flex aspect-[16/10] w-full items-center justify-center bg-muted px-4 text-center text-sm text-muted-foreground">
          {loading ? <Spinner size="sm" /> : emptyLabel}
        </div>
      ) : layout.kind === 'single' ? (
        <div
          className="flex w-full items-center justify-center overflow-hidden bg-muted"
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
        <div className="flex max-h-[460px] w-full flex-col gap-px overflow-hidden bg-border">
          {layout.rows.map((row, rowIndex) => (
            <div
              key={`row-${rowIndex}`}
              className="flex gap-px"
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
          className="grid max-h-[460px] w-full gap-px overflow-hidden bg-border"
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
          <div className="flex flex-col gap-px overflow-hidden">
            {layout.rows.map((row, rowIndex) => (
              <div
                key={`side-row-${rowIndex}`}
                className="flex gap-px"
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
        <div className="flex max-h-[460px] w-full flex-col gap-px overflow-hidden bg-border">
          <div
            className="flex"
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
              className="flex gap-px"
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
  const [shouldLoadPreview, setShouldLoadPreview] = useState(false);
  const [previewLoading, setPreviewLoading] = useState(false);
  const [previewPages, setPreviewPages] = useState<PageInfo[]>([]);
  const [, setPreviewLayoutVersion] = useState(0);
  const [contentExpanded, setContentExpanded] = useState(false);
  const previewRef = useRef<HTMLButtonElement | null>(null);

  const handleMeasurePreview = useCallback((cacheKey: string, aspectRatio: number) => {
    const normalized = Number.isFinite(aspectRatio) && aspectRatio > 0
      ? aspectRatio
      : DEFAULT_CHANNEL_ASPECT_RATIO;

    const current = channelPreviewAspectRatioCache.get(cacheKey) ?? DEFAULT_CHANNEL_ASPECT_RATIO;
    if (Math.abs(current - normalized) < 0.01) return;
    channelPreviewAspectRatioCache.set(cacheKey, normalized);
    setPreviewLayoutVersion((value) => value + 1);
  }, []);

  useEffect(() => {
    if (!previewRef.current || shouldLoadPreview) return;

    const observer = new IntersectionObserver(
      (entries) => {
        if (!entries.some((entry) => entry.isIntersecting)) return;
        setShouldLoadPreview(true);
      },
      {
        rootMargin: '240px 0px',
        threshold: 0.01,
      }
    );

    observer.observe(previewRef.current);
    return () => observer.disconnect();
  }, [shouldLoadPreview]);

  useEffect(() => {
    if (!shouldLoadPreview || !previewArchiveId) return;

    const cacheKey = getChannelPreviewCacheKey(previewArchiveId);
    const cached = channelPreviewCache.get(cacheKey);
    if (cached) {
      setPreviewPages(cached);
      return;
    }

    let cancelled = false;
    setPreviewLoading(true);

    void ArchiveService.getFiles(previewArchiveId, CHANNEL_PREVIEW_FILE_PARAMS)
      .then((result) => {
        if (cancelled) return;
        const nextPages = result.pages.slice(0, CHANNEL_PREVIEW_SOURCE_SCAN_LIMIT);
        channelPreviewCache.set(cacheKey, nextPages);
        setPreviewPages(nextPages);
      })
      .catch(() => {
        if (!cancelled) setPreviewPages([]);
      })
      .finally(() => {
        if (!cancelled) setPreviewLoading(false);
      });

    return () => {
      cancelled = true;
    };
  }, [previewArchiveId, shouldLoadPreview]);

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
        const previewItems = previewPages
          .flatMap((page, index) => {
            const media = getPagePreviewMedia(page);
            if (!media || !previewArchiveId) return [];
            const pageKey = page.path || String(index);
            const measurementKey = getChannelPreviewAspectRatioCacheKey(previewArchiveId, pageKey);
            return [{
              alt: page.title || `${displayTitle || author} ${index + 1}`,
              aspectRatio: channelPreviewAspectRatioCache.get(measurementKey) || DEFAULT_CHANNEL_ASPECT_RATIO,
              id: `${id}-${page.path || index}`,
              measurementKey,
              ...(media.posterSrc ? { posterSrc: media.posterSrc } : {}),
              src: media.src,
              type: page.type,
            }];
          })
          .slice(0, CHANNEL_PREVIEW_LIMIT);

        return (
          <article className={cn('px-1 py-2', selected && 'rounded-3xl bg-primary/5')} onContextMenuCapture={handleContextMenuCapture} onContextMenu={handleContextMenu}>
            <div className="flex items-end gap-3">
              <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-full bg-sky-100 text-sm font-semibold text-sky-700 dark:bg-sky-950/60 dark:text-sky-300">
                {getAuthorInitial(author)}
              </div>

              <div className="min-w-0 flex-1">
                <div
                  className={cn(
                    'group relative w-full overflow-hidden rounded-[1.75rem] rounded-bl-md border border-slate-200 bg-white text-slate-900 shadow-sm',
                    selected && 'ring-2 ring-primary/30'
                  )}
                >
                  <div className="pointer-events-none absolute right-3 top-3 z-10 opacity-0 transition-opacity duration-150 group-hover:opacity-100 group-focus-within:opacity-100">
                    <div className="pointer-events-auto flex items-center gap-2 rounded-full bg-white/92 px-2 py-1 shadow-sm ring-1 ring-black/5 backdrop-blur">
                      <Button
                        asChild
                        variant="ghost"
                        size="icon"
                        className="h-8 w-8 rounded-full text-muted-foreground"
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
                        className={cn('h-8 w-8 rounded-full text-muted-foreground', nextIsFavorite && 'text-red-500')}
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
                    className="block w-full overflow-hidden text-left transition hover:opacity-95"
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
                      items={previewItems}
                      loading={previewLoading}
                      emptyLabel={displayTitle || author}
                      onMeasure={handleMeasurePreview}
                    />
                  </button>

                  <div className="space-y-3 px-4 py-3 sm:px-5">
                    {contentText ? (
                      <div>
                        <div
                          className={cn(
                            'whitespace-pre-wrap break-words text-[15px] leading-6 text-slate-900',
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
                      <span className="text-xs text-slate-500">{contentMeta}</span>
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

  useEffect(() => {
    const element = containerRef.current;
    if (!element) return;

    const updateWidth = () => {
      setContentWidth(element.clientWidth);
    };

    updateWidth();

    if (typeof ResizeObserver === 'undefined') {
      window.addEventListener('resize', updateWidth);
      return () => window.removeEventListener('resize', updateWidth);
    }

    const observer = new ResizeObserver(updateWidth);
    observer.observe(element);
    return () => observer.disconnect();
  }, []);

  return (
    <div ref={containerRef} className="space-y-4">
      {items.map((item) => {
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
