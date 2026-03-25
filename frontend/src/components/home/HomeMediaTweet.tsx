'use client';

import type { MouseEvent } from 'react';
import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import Image from 'next/image';
import Link from 'next/link';
import { useRouter } from 'next/navigation';
import { Check, Eye, Heart, Square } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Spinner } from '@/components/ui/spinner';
import { useLanguage } from '@/contexts/LanguageContext';
import { ArchiveService, type PageInfo } from '@/lib/services/archive-service';
import { FavoriteService } from '@/lib/services/favorite-service';
import { buildExactTagSearchQuery, parseTags, stripNamespace } from '@/lib/utils/tag-utils';
import { cn } from '@/lib/utils/utils';
import type { Archive } from '@/types/archive';
import type { Tankoubon } from '@/types/tankoubon';

const TWEET_PREVIEW_LIMIT = 9;
const TWEET_PREVIEW_SOURCE_SCAN_LIMIT = 24;
const tweetPreviewCache = new Map<string, PageInfo[]>();

type HomeMediaTweetProps = {
  items: Array<Archive | Tankoubon>;
  selectionMode: boolean;
  selectedArchiveIds: Set<string>;
  selectedTankoubonIds: Set<string>;
  onRequestEnterSelection: () => void;
  onToggleArchiveSelect: (id: string, selected: boolean) => void;
  onToggleTankoubonSelect: (id: string, selected: boolean) => void;
};

type TweetTag = {
  canonical: string;
  label: string;
};

type TweetPreviewItem = {
  alt: string;
  id: string;
  src: string;
};

type HomeMediaTweetCardProps = {
  itemId: string;
  title: string;
  description: string;
  author: string;
  detailPath: string;
  readerPath: string;
  previewArchiveId?: string;
  contentMeta: string;
  tags: TweetTag[];
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

function buildTweetTags(rawTags: string): TweetTag[] {
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

function TweetPreviewTile({
  item,
  className,
}: {
  item: TweetPreviewItem;
  className?: string;
}) {
  return (
    <div className={cn('relative h-full w-full overflow-hidden bg-muted', className)}>
      <Image
        src={item.src}
        alt={item.alt}
        fill
        className="object-cover"
        sizes="(max-width: 768px) 100vw, 720px"
        decoding="async"
        unoptimized
      />
    </div>
  );
}

function TweetPreviewMedia({
  emptyLabel,
  items,
  loading,
}: {
  emptyLabel: string;
  items: TweetPreviewItem[];
  loading: boolean;
}) {
  if (items.length === 0) {
    return (
      <div className="flex aspect-[16/10] items-center justify-center bg-muted px-4 text-center text-sm text-muted-foreground">
        {loading ? <Spinner size="sm" /> : emptyLabel}
      </div>
    );
  }

  if (items.length === 1) {
    return (
      <div className="aspect-[16/10] bg-border">
        <TweetPreviewTile item={items[0]} />
      </div>
    );
  }

  if (items.length === 2) {
    return (
      <div className="grid aspect-[16/10] grid-cols-2 gap-px bg-border">
        {items.map((item) => (
          <TweetPreviewTile key={item.id} item={item} />
        ))}
      </div>
    );
  }

  if (items.length === 3) {
    return (
      <div className="grid aspect-[16/10] grid-cols-2 grid-rows-2 gap-px bg-border">
        <TweetPreviewTile item={items[0]} className="row-span-2" />
        <TweetPreviewTile item={items[1]} />
        <TweetPreviewTile item={items[2]} />
      </div>
    );
  }

  return (
    items.length === 4 ? (
      <div className="grid aspect-[16/10] grid-cols-2 grid-rows-2 gap-px bg-border">
        {items.map((item) => (
          <TweetPreviewTile key={item.id} item={item} />
        ))}
      </div>
    ) : items.length <= 6 ? (
      <div className="grid aspect-[3/2] grid-cols-3 grid-rows-2 gap-px bg-border">
        {items.map((item) => (
          <TweetPreviewTile key={item.id} item={item} />
        ))}
      </div>
    ) : (
      <div className="grid aspect-square grid-cols-3 grid-rows-3 gap-px bg-border">
        {items.slice(0, TWEET_PREVIEW_LIMIT).map((item) => (
          <TweetPreviewTile key={item.id} item={item} />
        ))}
      </div>
    )
  );
}

function HomeMediaTweetCard({
  itemId,
  title,
  description,
  author,
  detailPath,
  readerPath,
  previewArchiveId,
  contentMeta,
  tags,
  selectionMode,
  selected,
  isFavorite,
  onToggleSelected,
  onToggleFavorite,
}: HomeMediaTweetCardProps) {
  const router = useRouter();
  const { t } = useLanguage();
  const [favoriteLoading, setFavoriteLoading] = useState(false);
  const [shouldLoadPreview, setShouldLoadPreview] = useState(false);
  const [previewLoading, setPreviewLoading] = useState(false);
  const [previewPages, setPreviewPages] = useState<PageInfo[]>([]);
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
      .filter((item): item is TweetPreviewItem => item !== null)
      .slice(0, TWEET_PREVIEW_LIMIT);
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

    const cached = tweetPreviewCache.get(previewArchiveId);
    if (cached) {
      setPreviewPages(cached);
      return;
    }

    let cancelled = false;
    setPreviewLoading(true);

    void ArchiveService.getFiles(previewArchiveId)
      .then((result) => {
        if (cancelled) return;
        const nextPages = result.pages.slice(0, TWEET_PREVIEW_SOURCE_SCAN_LIMIT);
        tweetPreviewCache.set(previewArchiveId, nextPages);
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
    <article
      className={cn(
        'rounded-2xl border bg-card px-4 py-4 shadow-sm transition-colors hover:bg-card/95 sm:px-5',
        selected && 'border-primary ring-1 ring-primary/30'
      )}
    >
      <div className="flex items-start gap-3">
        <div className="flex h-11 w-11 shrink-0 items-center justify-center rounded-full bg-sky-100 text-sm font-semibold text-sky-700 dark:bg-sky-950/60 dark:text-sky-300">
          {getAuthorInitial(author)}
        </div>

        <div className="min-w-0 flex-1">
          <div className="flex items-start justify-between gap-3">
            <div className="min-w-0">
              <div className="truncate text-sm font-semibold text-foreground">{author}</div>
              <div className="text-xs text-muted-foreground">{contentMeta}</div>
            </div>

            <div className="flex items-center gap-2">
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

          {contentText ? (
            <div className="mt-3">
              <div
                className={cn(
                  'whitespace-pre-wrap break-words text-[15px] leading-6 text-foreground',
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
            <div className="mt-3 flex flex-wrap gap-x-3 gap-y-1 text-sm">
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

          <button
            type="button"
            ref={previewRef}
            className="mt-4 block w-full overflow-hidden rounded-2xl border bg-muted/40 text-left transition hover:border-sky-300 hover:bg-muted/55"
            onClick={handleOpenReader}
          >
            <TweetPreviewMedia
              items={previewItems}
              loading={previewLoading}
              emptyLabel={title || author}
            />
            <div className="flex items-center justify-between gap-3 px-4 py-3">
              <div className="min-w-0">
                <div className="truncate text-sm font-medium text-foreground">{title || author}</div>
                <div className="truncate text-xs text-muted-foreground">{contentMeta}</div>
              </div>
              <span className="shrink-0 text-sm font-medium text-sky-600 dark:text-sky-400">
                {t('archive.startReading')}
              </span>
            </div>
          </button>
        </div>
      </div>
    </article>
  );
}

function HomeArchiveTweetRow({
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
    <HomeMediaTweetCard
      itemId={`archive:${archive.arcid}`}
      title={archive.title}
      description={archive.description}
      author={extractAuthor(archive.tags, t('home.unknownArtist'))}
      detailPath={`/archive?id=${archive.arcid}`}
      readerPath={`/reader?id=${archive.arcid}`}
      previewArchiveId={archive.arcid}
      contentMeta={contentMeta}
      tags={buildTweetTags(archive.tags)}
      selectionMode={selectionMode}
      selected={selected}
      isFavorite={isFavorite}
      onToggleSelected={handleToggleSelected}
      onToggleFavorite={handleToggleFavorite}
    />
  );
}

function HomeTankoubonTweetRow({
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
    <HomeMediaTweetCard
      itemId={`tankoubon:${tankoubon.tankoubon_id}`}
      title={tankoubon.title}
      description={tankoubon.description}
      author={extractAuthor(tankoubon.tags, t('tankoubon.collection'))}
      detailPath={`/tankoubon?id=${tankoubon.tankoubon_id}`}
      readerPath={firstArchiveId ? `/reader?id=${firstArchiveId}` : `/tankoubon?id=${tankoubon.tankoubon_id}`}
      previewArchiveId={firstArchiveId || undefined}
      contentMeta={`${archiveCount} ${t('tankoubon.archives')} · ${t('tankoubon.totalPages').replace('{count}', String(pageCount))}`}
      tags={buildTweetTags(tankoubon.tags)}
      selectionMode={selectionMode}
      selected={selected}
      isFavorite={isFavorite}
      onToggleSelected={handleToggleSelected}
      onToggleFavorite={handleToggleFavorite}
    />
  );
}

export function HomeMediaTweet({
  items,
  selectionMode,
  selectedArchiveIds,
  selectedTankoubonIds,
  onRequestEnterSelection,
  onToggleArchiveSelect,
  onToggleTankoubonSelect,
}: HomeMediaTweetProps) {
  return (
    <div className="space-y-4">
      {items.map((item) => {
        if (isTankoubonItem(item)) {
          return (
            <HomeTankoubonTweetRow
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
          <HomeArchiveTweetRow
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
