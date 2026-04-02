'use client';

import type { MouseEvent } from 'react';
import { memo, useState } from 'react';
import Image from 'next/image';
import Link from 'next/link';
import { Check, Eye, Heart, Square } from 'lucide-react';
import { FeedPreviewPlaceholder } from '@/components/home/HomeFeedLoading';
import { HomeMediaItemMenu } from '@/components/home/HomeMediaItemMenu';
import { useArchivePreviewFeed } from '@/components/home/useArchivePreviewFeed';
import { Button } from '@/components/ui/button';
import { Spinner } from '@/components/ui/spinner';
import { useLanguage } from '@/contexts/LanguageContext';
import { ArchiveService, type PageInfo } from '@/lib/services/archive-service';
import { getArchiveAssetId, getCoverAssetId } from '@/lib/utils/archive-assets';
import { buildExactTagSearchQuery, parseTags, stripNamespace } from '@/lib/utils/tag-utils';
import { cn } from '@/lib/utils/utils';
import type { Archive } from '@/types/archive';
import type { Tankoubon } from '@/types/tankoubon';

const TWEET_PREVIEW_LIMIT = 9;
const TWEET_PREVIEW_SOURCE_SCAN_LIMIT = 24;
const TWEET_PREVIEW_FILE_PARAMS = {
  limit: TWEET_PREVIEW_SOURCE_SCAN_LIMIT,
  offset: 0,
  include_metadata: true,
} as const;

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

type TweetPreviewSource = {
  id: string;
  label: string;
  src: string;
};

type HomeMediaTweetCardProps = {
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
  selectionMode: boolean;
  selected: boolean;
  thumbnailAssetId?: number;
  title: string;
  type: 'archive' | 'tankoubon';
  previewPriority?: boolean;
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

async function loadTweetPreviewSources(archiveId: string): Promise<TweetPreviewSource[]> {
  const result = await ArchiveService.getFiles(archiveId, TWEET_PREVIEW_FILE_PARAMS);
  return result.pages
    .map((page, index) => {
      const src = getPagePreviewSrc(page);
      if (!src) return null;
      return {
        id: `${archiveId}:${page.path || index}`,
        label: page.title || '',
        src,
      };
    })
    .filter((item): item is TweetPreviewSource => item !== null)
    .slice(0, TWEET_PREVIEW_LIMIT);
}

const TweetPreviewTile = memo(function TweetPreviewTile({
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
});

const TweetPreviewMedia = memo(function TweetPreviewMedia({
  emptyLabel,
  items,
  loading,
  ready,
}: {
  emptyLabel: string;
  items: TweetPreviewItem[];
  loading: boolean;
  ready: boolean;
}) {
  if (!ready && loading) {
    return <FeedPreviewPlaceholder className="aspect-16/10 w-full rounded-none" label={emptyLabel} />;
  }

  if (items.length === 0) {
    return (
      <div className="flex aspect-16/10 items-center justify-center bg-muted px-4 text-center text-sm text-muted-foreground">
        {loading ? <Spinner size="sm" /> : emptyLabel}
      </div>
    );
  }

  if (items.length === 1) {
    return (
      <div className="feed-media-fade aspect-16/10 bg-border">
        <TweetPreviewTile item={items[0]} />
      </div>
    );
  }

  if (items.length === 2) {
    return (
      <div className="feed-media-fade grid aspect-16/10 grid-cols-2 gap-px bg-border">
        {items.map((item) => (
          <TweetPreviewTile key={item.id} item={item} />
        ))}
      </div>
    );
  }

  if (items.length === 3) {
    return (
      <div className="feed-media-fade grid aspect-16/10 grid-cols-2 grid-rows-2 gap-px bg-border">
        <TweetPreviewTile item={items[0]} className="row-span-2" />
        <TweetPreviewTile item={items[1]} />
        <TweetPreviewTile item={items[2]} />
      </div>
    );
  }

  return (
    items.length === 4 ? (
      <div className="feed-media-fade grid aspect-16/10 grid-cols-2 grid-rows-2 gap-px bg-border">
        {items.map((item) => (
          <TweetPreviewTile key={item.id} item={item} />
        ))}
      </div>
    ) : items.length <= 6 ? (
      <div className="feed-media-fade grid aspect-3/2 grid-cols-3 grid-rows-2 gap-px bg-border">
        {items.map((item) => (
          <TweetPreviewTile key={item.id} item={item} />
        ))}
      </div>
    ) : (
      <div className="feed-media-fade grid aspect-square grid-cols-3 grid-rows-3 gap-px bg-border">
        {items.slice(0, TWEET_PREVIEW_LIMIT).map((item) => (
          <TweetPreviewTile key={item.id} item={item} />
        ))}
      </div>
    )
  );
});

function HomeMediaTweetCard({
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
  selectionMode,
  selected,
  thumbnailAssetId,
  title,
  type,
  previewPriority = false,
  onToggleSelected,
  onRequestEnterSelection,
}: HomeMediaTweetCardProps) {
  const { t } = useLanguage();
  const [contentExpanded, setContentExpanded] = useState(false);
  const {
    items: previewSources,
    loading: previewLoading,
    ready: previewReady,
    targetRef: previewRef,
  } = useArchivePreviewFeed<TweetPreviewSource, HTMLButtonElement>({
    archiveId: previewArchiveId,
    eager: previewPriority,
    enabled: Boolean(previewArchiveId),
    loaderKey: 'tweet-preview',
    loadItems: loadTweetPreviewSources,
  });

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
        const tags = buildTweetTags(displayTags);
        const contentText = [displayTitle.trim(), displayDescription.trim()].filter(Boolean).join('\n\n');
        const canToggleContent = contentText.length > 180 || contentText.includes('\n');
        const previewItems: TweetPreviewItem[] = previewSources.map((item, index) => ({
          alt: item.label || `${displayTitle || author} ${index + 1}`,
          id: item.id,
          src: item.src,
        }));

        return (
          <article
            className={cn(
              'feed-card-enter rounded-2xl border bg-card px-4 py-4 shadow-xs transition-colors hover:bg-card/95 sm:px-5',
              selected && 'border-primary ring-1 ring-primary/30'
            )}
            style={{
              contentVisibility: 'auto',
              containIntrinsicSize: '340px 620px',
            }}
            onContextMenuCapture={handleContextMenuCapture}
            onContextMenu={handleContextMenu}
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

                {contentText ? (
                  <div className="mt-3">
                    <div
                      className={cn(
                        'whitespace-pre-wrap wrap-break-word text-[15px] leading-6 text-foreground',
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

                <button
                  type="button"
                  ref={previewRef}
                  className="mt-4 block w-full overflow-hidden rounded-2xl border bg-muted/40 text-left transition hover:border-sky-300 hover:bg-muted/55"
                  onClick={() => {
                    if (selectionMode) {
                      toggleSelected(!selected);
                      return;
                    }
                    navigateToReader();
                  }}
                >
                  <TweetPreviewMedia
                    items={previewItems}
                    loading={previewLoading}
                    ready={previewReady}
                    emptyLabel={displayTitle || author}
                  />
                  <div className="flex items-center justify-between gap-3 px-4 py-3">
                    <div className="min-w-0">
                      <div className="truncate text-sm font-medium text-foreground">{displayTitle || author}</div>
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
      }}
    </HomeMediaItemMenu>
  );
}

const HomeArchiveTweetRow = memo(function HomeArchiveTweetRow({
  archive,
  selectionMode,
  selected,
  onRequestEnterSelection,
  onToggleArchiveSelect,
  previewPriority,
}: {
  archive: Archive;
  selectionMode: boolean;
  selected: boolean;
  onRequestEnterSelection: () => void;
  onToggleArchiveSelect: (id: string, selected: boolean) => void;
  previewPriority: boolean;
}) {
  const { t } = useLanguage();
  const contentMeta = `${t('archive.pages').replace('{count}', String(archive.pagecount))}${archive.progress > 0 && archive.pagecount > 0 ? ` · ${Math.round((archive.progress / archive.pagecount) * 100)}% ${t('common.read')}` : ''}`;
  const coverAssetId = getArchiveAssetId(archive, 'cover');

  return (
    <HomeMediaTweetCard
      id={archive.arcid}
      type="archive"
      title={archive.title}
      description={archive.description}
      rawTags={archive.tags}
      detailPath={`/archive?id=${archive.arcid}`}
      readerTargetId={archive.arcid}
      previewArchiveId={archive.arcid}
      contentMeta={contentMeta}
      selectionMode={selectionMode}
      selected={selected}
      isFavorite={Boolean(archive.isfavorite)}
      isNew={archive.isnew}
      progress={archive.progress}
      thumbnailAssetId={coverAssetId}
      previewPriority={previewPriority}
      onToggleSelected={(nextSelected) => onToggleArchiveSelect(archive.arcid, nextSelected)}
      onRequestEnterSelection={onRequestEnterSelection}
    />
  );
});

const HomeTankoubonTweetRow = memo(function HomeTankoubonTweetRow({
  tankoubon,
  selectionMode,
  selected,
  onRequestEnterSelection,
  onToggleTankoubonSelect,
  previewPriority,
}: {
  tankoubon: Tankoubon;
  selectionMode: boolean;
  selected: boolean;
  onRequestEnterSelection: () => void;
  onToggleTankoubonSelect: (id: string, selected: boolean) => void;
  previewPriority: boolean;
}) {
  const { t } = useLanguage();
  const firstArchiveId = typeof tankoubon.children?.[0] === 'string' ? tankoubon.children[0] : '';
  const pageCount = typeof tankoubon.pagecount === 'number' ? tankoubon.pagecount : 0;
  const archiveCount = typeof tankoubon.archive_count === 'number' ? tankoubon.archive_count : 0;
  const coverAssetId = getCoverAssetId(tankoubon);
  return (
    <HomeMediaTweetCard
      id={tankoubon.tankoubon_id}
      type="tankoubon"
      title={tankoubon.title}
      description={tankoubon.description}
      rawTags={tankoubon.tags}
      detailPath={`/tankoubon?id=${tankoubon.tankoubon_id}`}
      readerTargetId={firstArchiveId || undefined}
      previewArchiveId={firstArchiveId || undefined}
      contentMeta={`${archiveCount} ${t('tankoubon.archives')} · ${t('tankoubon.totalPages').replace('{count}', String(pageCount))}`}
      selectionMode={selectionMode}
      selected={selected}
      isFavorite={Boolean(tankoubon.isfavorite)}
      isNew={Boolean(tankoubon.isnew)}
      thumbnailAssetId={coverAssetId}
      previewPriority={previewPriority}
      onToggleSelected={(nextSelected) => onToggleTankoubonSelect(tankoubon.tankoubon_id, nextSelected)}
      onRequestEnterSelection={onRequestEnterSelection}
    />
  );
});

export const HomeMediaTweet = memo(function HomeMediaTweet({
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
      {items.map((item, index) => {
        if (isTankoubonItem(item)) {
          return (
            <HomeTankoubonTweetRow
              key={`tankoubon:${item.tankoubon_id}`}
              tankoubon={item}
              previewPriority={index < 2}
              selectionMode={selectionMode}
              selected={selectedTankoubonIds.has(item.tankoubon_id)}
              onRequestEnterSelection={onRequestEnterSelection}
              onToggleTankoubonSelect={onToggleTankoubonSelect}
            />
          );
        }

        return (
            <HomeArchiveTweetRow
              key={`archive:${item.arcid}`}
              archive={item}
              previewPriority={index < 2}
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
