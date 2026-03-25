'use client';

import type { MouseEvent } from 'react';
import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import Link from 'next/link';
import { useRouter } from 'next/navigation';
import { Check, Eye, Film, Heart, Square } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Spinner } from '@/components/ui/spinner';
import { MemoizedImage } from '@/components/reader/components/MemoizedMedia';
import { useLanguage } from '@/contexts/LanguageContext';
import { useMounted } from '@/hooks/common-hooks';
import { ArchiveService, type PageInfo } from '@/lib/services/archive-service';
import { FavoriteService } from '@/lib/services/favorite-service';
import { buildExactTagSearchQuery, parseTags, stripNamespace } from '@/lib/utils/tag-utils';
import { cn } from '@/lib/utils/utils';
import type { Archive } from '@/types/archive';
import type { Tankoubon } from '@/types/tankoubon';

const CHANNEL_PREVIEW_LIMIT = 9;
const CHANNEL_PREVIEW_SOURCE_SCAN_LIMIT = 24;
const channelPreviewCache = new Map<string, PageInfo[]>();

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
  id: string;
  posterSrc?: string;
  src: string;
  type: PageInfo['type'];
};

const DEFAULT_CHANNEL_ASPECT_RATIO = 1.2;
const CHANNEL_MASONRY_ITEM_HEIGHT_CLASS = 'h-[132px] sm:h-[148px] xl:h-[160px]';

type HomeMediaChannelCardProps = {
  itemId: string;
  title: string;
  description: string;
  author: string;
  detailPath: string;
  readerPath: string;
  previewArchiveId?: string;
  contentMeta: string;
  tags: ChannelTag[];
  selectionMode: boolean;
  selected: boolean;
  isFavorite: boolean;
  onToggleSelected: (selected: boolean) => void;
  onToggleFavorite: () => Promise<void>;
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

function ChannelPreviewTile({
  item,
  onMeasure,
  onVideoReady,
  videoReady,
  className,
  style,
}: {
  item: ChannelPreviewItem;
  onMeasure: (id: string, aspectRatio: number) => void;
  onVideoReady: (id: string) => void;
  videoReady: boolean;
  className?: string;
  style?: React.CSSProperties;
}) {
  return (
    <div className={cn('relative flex shrink-0 items-center justify-center overflow-hidden bg-muted', className)} style={style}>
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
            className="block h-full w-auto max-w-none flex-grow"
            muted
            loop
            playsInline
            preload={item.posterSrc ? 'metadata' : 'auto'}
            onLoadedMetadata={(event) => {
              const video = event.currentTarget;
              const naturalWidth = video.videoWidth;
              const naturalHeight = video.videoHeight;
              if (!naturalWidth || !naturalHeight) return;
              onMeasure(item.id, naturalWidth / naturalHeight);
            }}
            onLoadedData={(event) => {
              const video = event.currentTarget;
              onVideoReady(item.id);
              if (item.posterSrc || video.dataset.previewBootstrapped === '1') return;
              video.dataset.previewBootstrapped = '1';
              void video.play()
                .then(() => {
                  window.setTimeout(() => {
                    video.pause();
                  }, 80);
                })
                .catch(() => {});
            }}
          />
        </>
      ) : (
        <MemoizedImage
          src={item.src}
          alt={item.alt}
          className="block h-full w-auto max-w-none flex-grow"
          decoding="async"
          loading="lazy"
          draggable={false}
          onLoad={(event) => {
            const image = event.currentTarget;
            const naturalWidth = image.naturalWidth || image.width;
            const naturalHeight = image.naturalHeight || image.height;
            if (!naturalWidth || !naturalHeight) return;
            onMeasure(item.id, naturalWidth / naturalHeight);
          }}
        />
      )}
    </div>
  );
}

function ChannelPreviewMedia({
  aspectRatios,
  emptyLabel,
  items,
  loading,
  onMeasure,
}: {
  aspectRatios: Record<string, number>;
  emptyLabel: string;
  items: ChannelPreviewItem[];
  loading: boolean;
  onMeasure: (id: string, aspectRatio: number) => void;
}) {
  const mounted = useMounted();
  const [videoReadyMap, setVideoReadyMap] = useState<Record<string, boolean>>({});

  const normalizedItems = useMemo(() => items.map((item) => ({
    ...item,
    aspectRatio: Math.max(0.45, Math.min(aspectRatios[item.id] || DEFAULT_CHANNEL_ASPECT_RATIO, 2.6)),
  })), [aspectRatios, items]);

  const masonryItems = useMemo(() => normalizedItems.map((item) => {
    const basis = Math.max(92, Math.round(148 * item.aspectRatio));
    return {
      ...item,
      basis,
      grow: Math.max(1, item.aspectRatio),
      minWidth: Math.max(92, Math.min(220, Math.round(basis * 0.72))),
    };
  }), [normalizedItems]);

  const handleVideoReady = useCallback((id: string) => {
    setVideoReadyMap((current) => {
      if (current[id]) return current;
      return {
        ...current,
        [id]: true,
      };
    });
  }, []);

  if (items.length === 0) {
    return (
      <div className="flex aspect-[16/10] items-center justify-center bg-muted px-4 text-center text-sm text-muted-foreground">
        {loading ? <Spinner size="sm" /> : emptyLabel}
      </div>
    );
  }

  if (!mounted) {
    return (
      <div className="flex max-h-[460px] flex-wrap gap-px overflow-hidden bg-border">
        {Array.from({ length: Math.max(1, Math.min(items.length, CHANNEL_PREVIEW_LIMIT)) }).map((_, index) => (
          <div
            key={`channel-preview-skeleton-${index}`}
            className={cn('shrink-0 animate-pulse bg-muted', CHANNEL_MASONRY_ITEM_HEIGHT_CLASS)}
            style={{
              flexBasis: `${index % 3 === 1 ? 212 : 148}px`,
              flexGrow: index % 3 === 1 ? 1.4 : 1,
              minWidth: `${index % 3 === 1 ? 144 : 108}px`,
            }}
          />
        ))}
      </div>
    );
  }

  return (
    <div className="flex max-h-[460px] flex-wrap gap-px overflow-hidden bg-border">
      {masonryItems.map((item) => (
        <ChannelPreviewTile
          key={item.id}
          item={item}
          className={CHANNEL_MASONRY_ITEM_HEIGHT_CLASS}
          onMeasure={onMeasure}
          onVideoReady={handleVideoReady}
          videoReady={Boolean(videoReadyMap[item.id])}
          style={{
            flexBasis: `${item.basis}px`,
            flexGrow: item.grow,
            minWidth: `${item.minWidth}px`,
          }}
        />
      ))}
    </div>
  );
}

function HomeMediaChannelCard({
  itemId,
  title,
  description,
  author,
  detailPath,
  readerPath,
  previewArchiveId,
  contentMeta,
  tags,
  selected,
  isFavorite,
  onToggleSelected,
  onToggleFavorite,
}: HomeMediaChannelCardProps) {
  const router = useRouter();
  const { t } = useLanguage();
  const [favoriteLoading, setFavoriteLoading] = useState(false);
  const [shouldLoadPreview, setShouldLoadPreview] = useState(false);
  const [previewLoading, setPreviewLoading] = useState(false);
  const [previewPages, setPreviewPages] = useState<PageInfo[]>([]);
  const [previewAspectRatios, setPreviewAspectRatios] = useState<Record<string, number>>({});
  const [contentExpanded, setContentExpanded] = useState(false);
  const previewRef = useRef<HTMLButtonElement | null>(null);

  const handleOpenReader = useCallback(() => {
    router.push(readerPath);
  }, [readerPath, router]);

  const handleToggleSelected = useCallback((event: MouseEvent<HTMLButtonElement>) => {
    event.stopPropagation();
    onToggleSelected(!selected);
  }, [onToggleSelected, selected]);

  const handleToggleFavorite = useCallback(async (event: MouseEvent<HTMLButtonElement>) => {
    event.stopPropagation();
    if (favoriteLoading) return;
    setFavoriteLoading(true);
    try {
      await onToggleFavorite();
    } finally {
      setFavoriteLoading(false);
    }
  }, [favoriteLoading, onToggleFavorite]);

  const handleMeasurePreview = useCallback((id: string, aspectRatio: number) => {
    const normalized = Number.isFinite(aspectRatio) && aspectRatio > 0
      ? aspectRatio
      : DEFAULT_CHANNEL_ASPECT_RATIO;

    setPreviewAspectRatios((current) => {
      if (Math.abs((current[id] || DEFAULT_CHANNEL_ASPECT_RATIO) - normalized) < 0.01) {
        return current;
      }
      return {
        ...current,
        [id]: normalized,
      };
    });
  }, []);

  const contentText = [title.trim(), description.trim()].filter(Boolean).join('\n\n');
  const canToggleContent = useMemo(() => {
    if (!contentText) return false;
    return contentText.length > 180 || contentText.includes('\n');
  }, [contentText]);
  const previewItems = useMemo(() => {
    return previewPages
      .flatMap((page, index) => {
        const media = getPagePreviewMedia(page);
        if (!media) return [];
        return [{
          alt: page.title || `${title || author} ${index + 1}`,
          id: `${itemId}-${page.path || index}`,
          ...(media.posterSrc ? { posterSrc: media.posterSrc } : {}),
          src: media.src,
          type: page.type,
        }];
      })
      .slice(0, CHANNEL_PREVIEW_LIMIT);
  }, [author, itemId, previewPages, title]);

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

    const cached = channelPreviewCache.get(previewArchiveId);
    if (cached) {
      setPreviewPages(cached);
      return;
    }

    let cancelled = false;
    setPreviewLoading(true);

    void ArchiveService.getFiles(previewArchiveId)
      .then((result) => {
        if (cancelled) return;
        const nextPages = result.pages.slice(0, CHANNEL_PREVIEW_SOURCE_SCAN_LIMIT);
        channelPreviewCache.set(previewArchiveId, nextPages);
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
    <article className={cn('px-1 py-2', selected && 'rounded-3xl bg-primary/5')}>
      <div className="flex items-end gap-3">
        <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-full bg-sky-100 text-sm font-semibold text-sky-700 dark:bg-sky-950/60 dark:text-sky-300">
          {getAuthorInitial(author)}
        </div>

        <div className="min-w-0 flex-1">
          <div
            className={cn(
              'group relative overflow-hidden rounded-[1.75rem] rounded-bl-md border border-slate-200 bg-white text-slate-900 shadow-sm',
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
                  className={cn('h-8 w-8 rounded-full text-muted-foreground', isFavorite && 'text-red-500')}
                  title={isFavorite ? t('common.unfavorite') : t('common.favorite')}
                  disabled={favoriteLoading}
                  onClick={handleToggleFavorite}
                >
                  {favoriteLoading ? <Spinner size="sm" /> : <Heart className={cn('h-4 w-4', isFavorite && 'fill-current')} />}
                </Button>

                <Button
                  type="button"
                  variant={selected ? 'default' : 'ghost'}
                  size="icon"
                  className="h-8 w-8 rounded-full"
                  aria-label={selected ? t('home.unselectItem') : t('home.selectItem')}
                  title={selected ? t('home.unselectItem') : t('home.selectItem')}
                  onClick={handleToggleSelected}
                >
                  {selected ? <Check className="h-4 w-4" /> : <Square className="h-4 w-4" />}
                </Button>
              </div>
            </div>

            <button
              type="button"
              ref={previewRef}
              className="block w-full overflow-hidden text-left transition hover:opacity-95"
              onClick={handleOpenReader}
            >
              <ChannelPreviewMedia
                aspectRatios={previewAspectRatios}
                items={previewItems}
                loading={previewLoading}
                emptyLabel={title || author}
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
                        key={`${itemId}-${tag.canonical}`}
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
}

function HomeArchiveChannelRow({
  archive,
  selectionMode,
  selected,
  onRequestEnterSelection,
  onToggleSelect,
}: {
  archive: Archive;
  selectionMode: boolean;
  selected: boolean;
  onRequestEnterSelection: () => void;
  onToggleSelect: (selected: boolean) => void;
}) {
  const { t } = useLanguage();
  const [isFavorite, setIsFavorite] = useState(Boolean(archive.isfavorite));

  useEffect(() => {
    setIsFavorite(Boolean(archive.isfavorite));
  }, [archive.isfavorite]);

  const handleToggleSelected = useCallback((nextSelected: boolean) => {
    if (nextSelected && !selectionMode) onRequestEnterSelection();
    onToggleSelect(nextSelected);
  }, [onRequestEnterSelection, onToggleSelect, selectionMode]);

  const handleToggleFavorite = useCallback(async () => {
    const success = await FavoriteService.toggleFavorite(archive.arcid, isFavorite);
    if (success) setIsFavorite((current) => !current);
  }, [archive.arcid, isFavorite]);

  const contentMeta = `${t('archive.pages').replace('{count}', String(archive.pagecount))}${archive.progress > 0 && archive.pagecount > 0 ? ` · ${Math.round((archive.progress / archive.pagecount) * 100)}% ${t('common.read')}` : ''}`;

  return (
    <HomeMediaChannelCard
      itemId={`archive:${archive.arcid}`}
      title={archive.title}
      description={archive.description}
      author={extractAuthor(archive.tags, t('home.unknownArtist'))}
      detailPath={`/archive?id=${archive.arcid}`}
      readerPath={`/reader?id=${archive.arcid}`}
      previewArchiveId={archive.arcid}
      contentMeta={contentMeta}
      tags={buildChannelTags(archive.tags)}
      selectionMode={selectionMode}
      selected={selected}
      isFavorite={isFavorite}
      onToggleSelected={handleToggleSelected}
      onToggleFavorite={handleToggleFavorite}
    />
  );
}

function HomeTankoubonChannelRow({
  tankoubon,
  selectionMode,
  selected,
  onRequestEnterSelection,
  onToggleSelect,
}: {
  tankoubon: Tankoubon;
  selectionMode: boolean;
  selected: boolean;
  onRequestEnterSelection: () => void;
  onToggleSelect: (selected: boolean) => void;
}) {
  const { t } = useLanguage();
  const [isFavorite, setIsFavorite] = useState(Boolean(tankoubon.isfavorite));

  useEffect(() => {
    setIsFavorite(Boolean(tankoubon.isfavorite));
  }, [tankoubon.isfavorite]);

  const handleToggleSelected = useCallback((nextSelected: boolean) => {
    if (nextSelected && !selectionMode) onRequestEnterSelection();
    onToggleSelect(nextSelected);
  }, [onRequestEnterSelection, onToggleSelect, selectionMode]);

  const handleToggleFavorite = useCallback(async () => {
    const success = await FavoriteService.toggleTankoubonFavorite(tankoubon.tankoubon_id, isFavorite);
    if (success) setIsFavorite((current) => !current);
  }, [isFavorite, tankoubon.tankoubon_id]);

  const firstArchiveId = typeof tankoubon.children?.[0] === 'string' ? tankoubon.children[0] : '';
  const pageCount = typeof tankoubon.pagecount === 'number' ? tankoubon.pagecount : 0;
  const archiveCount = typeof tankoubon.archive_count === 'number' ? tankoubon.archive_count : 0;

  return (
    <HomeMediaChannelCard
      itemId={`tankoubon:${tankoubon.tankoubon_id}`}
      title={tankoubon.title}
      description={tankoubon.description}
      author={extractAuthor(tankoubon.tags, t('tankoubon.collection'))}
      detailPath={`/tankoubon?id=${tankoubon.tankoubon_id}`}
      readerPath={firstArchiveId ? `/reader?id=${firstArchiveId}` : `/tankoubon?id=${tankoubon.tankoubon_id}`}
      previewArchiveId={firstArchiveId || undefined}
      contentMeta={`${archiveCount} ${t('tankoubon.archives')} · ${t('tankoubon.totalPages').replace('{count}', String(pageCount))}`}
      tags={buildChannelTags(tankoubon.tags)}
      selectionMode={selectionMode}
      selected={selected}
      isFavorite={isFavorite}
      onToggleSelected={handleToggleSelected}
      onToggleFavorite={handleToggleFavorite}
    />
  );
}

export function HomeMediaChannel({
  items,
  selectionMode,
  selectedArchiveIds,
  selectedTankoubonIds,
  onRequestEnterSelection,
  onToggleArchiveSelect,
  onToggleTankoubonSelect,
}: HomeMediaChannelProps) {
  return (
    <div className="space-y-4">
      {items.map((item) => {
        if (isTankoubonItem(item)) {
          return (
            <HomeTankoubonChannelRow
              key={`tankoubon:${item.tankoubon_id}`}
              tankoubon={item}
              selectionMode={selectionMode}
              selected={selectedTankoubonIds.has(item.tankoubon_id)}
              onRequestEnterSelection={onRequestEnterSelection}
              onToggleSelect={(selected) => onToggleTankoubonSelect(item.tankoubon_id, selected)}
            />
          );
        }

        return (
          <HomeArchiveChannelRow
            key={`archive:${item.arcid}`}
            archive={item}
            selectionMode={selectionMode}
            selected={selectedArchiveIds.has(item.arcid)}
            onRequestEnterSelection={onRequestEnterSelection}
            onToggleSelect={(selected) => onToggleArchiveSelect(item.arcid, selected)}
          />
        );
      })}
    </div>
  );
}
