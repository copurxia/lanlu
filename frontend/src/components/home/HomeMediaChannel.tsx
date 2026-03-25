'use client';

import type { MouseEvent } from 'react';
import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import Link from 'next/link';
import { useRouter } from 'next/navigation';
import { Check, Eye, Heart, Square } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Spinner } from '@/components/ui/spinner';
import { MemoizedImage } from '@/components/reader/components/MemoizedMedia';
import { useLanguage } from '@/contexts/LanguageContext';
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
  src: string;
};

type ChannelPreviewRow = {
  height: number;
  items: Array<ChannelPreviewItem & { aspectRatio: number; width: number }>;
};

type ChannelPreviewLayout =
  | {
      kind: 'single';
      hero: ChannelPreviewItem & { aspectRatio: number };
      heroHeight: number;
    }
  | {
      kind: 'rows';
      rows: ChannelPreviewRow[];
    }
  | {
      kind: 'hero-top';
      hero: ChannelPreviewItem & { aspectRatio: number };
      heroHeight: number;
      rows: ChannelPreviewRow[];
    }
  | {
      kind: 'hero-side';
      hero: ChannelPreviewItem & { aspectRatio: number };
      heroWidth: number;
      totalHeight: number;
      rows: ChannelPreviewRow[];
    };

const DEFAULT_CHANNEL_ASPECT_RATIO = 1.2;
const SINGLE_PREVIEW_HEIGHT = 360;
const CHANNEL_ROW_GAP_PX = 1;
const CHANNEL_MAX_COLLAGE_HEIGHT = 460;
const CHANNEL_TOP_HERO_TARGET_HEIGHT = 220;
const CHANNEL_SIDE_HERO_MIN_COUNT = 4;

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

function getPagePreviewSrc(page: PageInfo): string {
  if (page.metadata?.thumb?.trim()) return page.metadata.thumb.trim();
  if (page.type === 'image' && page.url.trim()) return page.url.trim();
  return '';
}

function ChannelPreviewTile({
  item,
  onMeasure,
  className,
  style,
}: {
  item: ChannelPreviewItem;
  onMeasure: (id: string, aspectRatio: number) => void;
  className?: string;
  style?: React.CSSProperties;
}) {
  return (
    <div className={cn('flex h-full items-center justify-center overflow-hidden bg-muted', className)} style={style}>
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
          onMeasure(item.id, naturalWidth / naturalHeight);
        }}
      />
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
  const containerRef = useRef<HTMLDivElement | null>(null);
  const [containerWidth, setContainerWidth] = useState(0);

  useEffect(() => {
    const element = containerRef.current;
    if (!element) return;

    const updateWidth = () => {
      setContainerWidth(element.clientWidth);
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

  const normalizedItems = useMemo(() => items.map((item) => ({
    ...item,
    aspectRatio: Math.max(0.45, Math.min(aspectRatios[item.id] || DEFAULT_CHANNEL_ASPECT_RATIO, 2.4)),
  })), [aspectRatios, items]);

  const effectiveWidth = Math.max(containerWidth, 320);

  const buildJustifiedRows = useCallback((
    sourceItems: Array<ChannelPreviewItem & { aspectRatio: number }>,
    rowWidth: number,
    rowCountOverride?: number,
    maxHeightOverride?: number
  ): ChannelPreviewRow[] => {
    if (sourceItems.length === 0) return [];
    if (sourceItems.length === 1) {
      const width = Math.max(96, rowWidth);
      const height = width / Math.max(sourceItems[0].aspectRatio, 0.1);
      return [
        {
          height: Math.round(height),
          items: [{ ...sourceItems[0], width }],
        },
      ];
    }

    const rowCount = rowCountOverride || (sourceItems.length <= 2 ? 1 : sourceItems.length <= 4 ? 2 : 3);
    const desiredTotalHeight = maxHeightOverride || Math.min(
      CHANNEL_MAX_COLLAGE_HEIGHT,
      rowCount === 1 ? 260 : rowCount === 2 ? 336 : 420
    );
    const targetRowHeight = Math.max(92, (desiredTotalHeight - CHANNEL_ROW_GAP_PX * Math.max(0, rowCount - 1)) / rowCount);
    const targetRatio = rowWidth / targetRowHeight;
    let bestCuts: number[] | null = null;
    let bestScore = Number.POSITIVE_INFINITY;

    const search = (startIndex: number, rowsLeft: number, cuts: number[]) => {
      if (rowsLeft === 1) {
        if (startIndex >= sourceItems.length) return;
        const nextCuts = [...cuts, sourceItems.length];
        const rowSlices = [];
        let sliceStart = 0;
        for (const cut of nextCuts) {
          rowSlices.push(sourceItems.slice(sliceStart, cut));
          sliceStart = cut;
        }
        const score = rowSlices.reduce((sum, row, index) => {
          const ratioSum = row.reduce((rowSum, item) => rowSum + item.aspectRatio, 0);
          const deviation = Math.abs(ratioSum - targetRatio);
          const countPenalty = row.length === 0 ? 1000 : row.length > 4 ? (row.length - 4) * 12 : 0;
          const tailPenalty = index === rowSlices.length - 1 && row.length === 1 ? 6 : 0;
          return sum + deviation * deviation + countPenalty + tailPenalty;
        }, 0);
        if (score < bestScore) {
          bestScore = score;
          bestCuts = nextCuts;
        }
        return;
      }

      const maxCut = sourceItems.length - rowsLeft + 1;
      for (let cut = startIndex + 1; cut <= maxCut; cut += 1) {
        search(cut, rowsLeft - 1, [...cuts, cut]);
      }
    };

    search(0, rowCount, []);

    const cuts = bestCuts || [sourceItems.length];
    const rows: Array<Array<ChannelPreviewItem & { aspectRatio: number }>> = [];
    let start = 0;
    for (const cut of cuts) {
      rows.push(sourceItems.slice(start, cut));
      start = cut;
    }

    const rowRatioSums = rows.map((row) => row.reduce((sum, item) => sum + item.aspectRatio, 0));

    return rows.map((row, index) => {
      const ratioSum = Math.max(rowRatioSums[index], 0.1);
      const rowGapWidth = CHANNEL_ROW_GAP_PX * Math.max(0, row.length - 1);
      const exactHeight = (rowWidth - rowGapWidth) / ratioSum;
      const widths = row.map((item) => exactHeight * item.aspectRatio);
      return {
        height: exactHeight,
        items: row.map((item, itemIndex) => ({
          ...item,
          width: widths[itemIndex],
        })),
      };
    });
  }, []);

  const chooseHeroIndex = useCallback((sourceItems: Array<ChannelPreviewItem & { aspectRatio: number }>) => {
    let topHeroIndex = 0;
    let topHeroScore = Number.NEGATIVE_INFINITY;
    let sideHeroIndex = 0;
    let sideHeroScore = Number.NEGATIVE_INFINITY;

    sourceItems.forEach((item, index) => {
      const orderBonus = Math.max(0, 0.12 - index * 0.02);
      const topScore = (2.2 - Math.abs(item.aspectRatio - 1.55)) + (item.aspectRatio >= 1.08 ? 0.8 : 0) + orderBonus;
      const sideScore = (2.1 - Math.abs(item.aspectRatio - 0.78)) + (item.aspectRatio <= 0.95 ? 1.05 : 0) + orderBonus;
      if (topScore > topHeroScore) {
        topHeroScore = topScore;
        topHeroIndex = index;
      }
      if (sideScore > sideHeroScore) {
        sideHeroScore = sideScore;
        sideHeroIndex = index;
      }
    });

    const preferSide =
      sourceItems.length >= CHANNEL_SIDE_HERO_MIN_COUNT &&
      sourceItems[sideHeroIndex].aspectRatio < 1 &&
      sideHeroScore > topHeroScore + 0.18;

    return {
      heroIndex: preferSide ? sideHeroIndex : topHeroIndex,
      placement: preferSide ? 'side' as const : 'top' as const,
    };
  }, []);

  const layout = useMemo<ChannelPreviewLayout>(() => {
    if (normalizedItems.length === 0) {
      return {
        kind: 'rows',
        rows: [],
      };
    }

    if (normalizedItems.length === 1) {
      const heroHeight = Math.min(SINGLE_PREVIEW_HEIGHT, effectiveWidth / Math.max(normalizedItems[0].aspectRatio, 0.1));
      return {
        kind: 'single',
        hero: normalizedItems[0],
        heroHeight,
      };
    }

    if (normalizedItems.length === 2) {
      return {
        kind: 'rows',
        rows: buildJustifiedRows(normalizedItems, effectiveWidth, 1, 260),
      };
    }

    const { heroIndex, placement } = chooseHeroIndex(normalizedItems);
    const hero = normalizedItems[heroIndex];
    const restItems = normalizedItems.filter((_, index) => index !== heroIndex);

    if (placement === 'side') {
      let low = Math.max(120, effectiveWidth * 0.28);
      let high = Math.max(low + 20, effectiveWidth * 0.7);
      let best: { heroWidth: number; rows: ChannelPreviewRow[]; totalHeight: number } | null = null;

      for (let i = 0; i < 18; i += 1) {
        const candidateHeroWidth = (low + high) / 2;
        const rightWidth = Math.max(120, effectiveWidth - candidateHeroWidth - CHANNEL_ROW_GAP_PX);
        const candidateRows = buildJustifiedRows(restItems, rightWidth, restItems.length <= 3 ? 2 : 3, 420);
        const totalHeight = candidateRows.reduce((sum, row) => sum + row.height, 0) + CHANNEL_ROW_GAP_PX * Math.max(0, candidateRows.length - 1);
        const solvedHeroWidth = totalHeight * hero.aspectRatio;

        best = {
          heroWidth: solvedHeroWidth,
          rows: candidateRows,
          totalHeight,
        };

        if (solvedHeroWidth > candidateHeroWidth) {
          low = candidateHeroWidth;
        } else {
          high = candidateHeroWidth;
        }
      }

      if (best && best.heroWidth > 96 && best.heroWidth + CHANNEL_ROW_GAP_PX < effectiveWidth) {
        return {
          kind: 'hero-side',
          hero,
          heroWidth: best.heroWidth,
          totalHeight: best.totalHeight,
          rows: best.rows,
        };
      }
    }

    const heroHeight = effectiveWidth / Math.max(hero.aspectRatio, 0.1);
    return {
      kind: 'hero-top',
      hero,
      heroHeight: Math.min(260, Math.max(150, heroHeight || CHANNEL_TOP_HERO_TARGET_HEIGHT)),
      rows: buildJustifiedRows(restItems, effectiveWidth),
    };
  }, [buildJustifiedRows, chooseHeroIndex, effectiveWidth, normalizedItems]);

  if (normalizedItems.length === 0) {
    return (
      <div ref={containerRef} className="flex aspect-[16/10] items-center justify-center bg-muted px-4 text-center text-sm text-muted-foreground">
        {loading ? <Spinner size="sm" /> : emptyLabel}
      </div>
    );
  }

  if (layout.kind === 'single') {
    return (
      <div
        ref={containerRef}
        className="flex items-center justify-center overflow-hidden bg-muted"
        style={{
          height: `${layout.heroHeight}px`,
          width: '100%',
        }}
      >
        <MemoizedImage
          src={layout.hero.src}
          alt={layout.hero.alt}
          className="block h-full w-auto max-w-none"
          decoding="async"
          loading="lazy"
          draggable={false}
        />
      </div>
    );
  }

  if (layout.kind === 'rows') {
    return (
      <div ref={containerRef} className="flex max-h-[460px] flex-col gap-px overflow-hidden bg-border">
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
                style={{ width: `${item.width}px` }}
              />
            ))}
          </div>
        ))}
      </div>
    );
  }

  if (layout.kind === 'hero-side') {
    return (
      <div
        ref={containerRef}
        className="grid max-h-[460px] gap-px overflow-hidden bg-border"
        style={{
          gridTemplateColumns: `${layout.heroWidth}px ${Math.max(0, effectiveWidth - layout.heroWidth - CHANNEL_ROW_GAP_PX)}px`,
          height: `${layout.totalHeight}px`,
        }}
      >
        <ChannelPreviewTile
          item={layout.hero}
          onMeasure={onMeasure}
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
                  style={{ width: `${item.width}px` }}
                />
              ))}
            </div>
          ))}
        </div>
      </div>
    );
  }

  return (
    <div ref={containerRef} className="flex max-h-[460px] flex-col gap-px overflow-hidden bg-border">
      <div
        className="flex"
        style={{
          height: `${layout.heroHeight}px`,
        }}
      >
        <ChannelPreviewTile
          item={layout.hero}
          onMeasure={onMeasure}
          style={{ width: '100%' }}
        />
      </div>
      {layout.rows.map((row: ChannelPreviewRow, rowIndex: number) => (
        <div
          key={`row-${rowIndex}`}
          className="flex gap-px"
          style={{
            height: `${row.height}px`,
          }}
        >
          {row.items.map((item: ChannelPreviewItem & { aspectRatio: number; width: number }) => (
            <ChannelPreviewTile
              key={item.id}
              item={item}
              className="shrink-0"
              onMeasure={onMeasure}
              style={{ width: `${item.width}px` }}
            />
          ))}
        </div>
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
      .map((page, index) => {
        const src = getPagePreviewSrc(page);
        if (!src) return null;
        return {
          alt: page.title || `${title || author} ${index + 1}`,
          id: `${itemId}-${page.path || index}`,
          src,
        };
      })
      .filter((item): item is ChannelPreviewItem => item !== null)
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
