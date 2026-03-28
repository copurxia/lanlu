'use client';

import { memo, type MouseEvent, type ReactNode } from 'react';
import Image from 'next/image';
import Link from 'next/link';
import { BookOpen, Check, Eye, Heart, Square } from 'lucide-react';
import { HomeMediaItemMenu } from '@/components/home/HomeMediaItemMenu';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Spinner } from '@/components/ui/spinner';
import { useLanguage } from '@/contexts/LanguageContext';
import { getArchiveAssetId, getCoverAssetId } from '@/lib/utils/archive-assets';
import { cn } from '@/lib/utils/utils';
import { parseTags, stripNamespace } from '@/lib/utils/tag-utils';
import type { Archive } from '@/types/archive';
import type { Tankoubon } from '@/types/tankoubon';

type HomeMediaListProps = {
  items: Array<Archive | Tankoubon>;
  selectionMode: boolean;
  selectedArchiveIds: Set<string>;
  selectedTankoubonIds: Set<string>;
  onRequestEnterSelection: () => void;
  onToggleArchiveSelect: (id: string, selected: boolean) => void;
  onToggleTankoubonSelect: (id: string, selected: boolean) => void;
};

type HomeMediaListItemProps = {
  description: string;
  detailPath: string;
  id: string;
  coverSrc: string;
  coverAlt: string;
  infoText: string;
  rawTags: string;
  title: string;
  thumbnailAssetId?: number;
  type: 'archive' | 'tankoubon';
  isFavorite: boolean;
  isNew?: boolean;
  progress?: number;
  renderBadges?: (state: { isNew: boolean }) => ReactNode;
  readerTargetId?: string;
  selectable: boolean;
  selectionMode: boolean;
  selected: boolean;
  onToggleSelected: (selected: boolean) => void;
  onRequestEnterSelection: () => void;
};

function isTankoubonItem(item: Archive | Tankoubon): item is Tankoubon {
  return 'tankoubon_id' in item;
}

const HomeMediaListItem = memo(function HomeMediaListItem({
  description,
  detailPath,
  id,
  coverSrc,
  coverAlt,
  infoText,
  rawTags,
  title,
  thumbnailAssetId,
  type,
  isFavorite,
  isNew = false,
  progress,
  renderBadges,
  readerTargetId,
  selectable,
  selectionMode,
  selected,
  onToggleSelected,
  onRequestEnterSelection,
}: HomeMediaListItemProps) {
  const { t } = useLanguage();
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
      selectable={selectable}
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
        isNew: nextIsNew,
        navigateToReader,
        toggleFavorite,
        toggleSelected,
      }) => {
        const tags = parseTags(displayTags).map(stripNamespace);
        const badges = renderBadges?.({ isNew: nextIsNew });

        return (
          <div
            className={cn(
              'relative rounded-lg border bg-card p-3 transition-shadow hover:shadow-sm sm:p-4',
              selectionMode && !selected && 'bg-card/70',
              selected && 'border-primary ring-1 ring-primary/30'
            )}
            role="button"
            tabIndex={0}
            onClick={() => {
              if (selectionMode && selectable) {
                toggleSelected(!selected);
                return;
              }
              navigateToReader();
            }}
            onKeyDown={(e) => {
              if (e.key !== 'Enter' && e.key !== ' ') return;
              e.preventDefault();
              if (selectionMode && selectable) {
                toggleSelected(!selected);
                return;
              }
              navigateToReader();
            }}
            onContextMenuCapture={handleContextMenuCapture}
            onContextMenu={handleContextMenu}
          >
            <div className="flex gap-3 sm:gap-4">
              <div className="relative h-24 w-16 shrink-0 overflow-hidden rounded-md bg-muted sm:h-28 sm:w-20">
                {coverSrc ? (
                  <Image
                    src={coverSrc}
                    alt={coverAlt}
                    fill
                    className="object-cover"
                    sizes="112px"
                    decoding="async"
                  />
                ) : (
                  <div className="absolute inset-0 flex items-center justify-center px-2 text-center text-[10px] text-muted-foreground">
                    {t('archive.noCover')}
                  </div>
                )}
              </div>

              <div className="min-w-0 flex-1 pr-24 sm:pr-28">
                <div className="flex items-start gap-2">
                  <h3 className="min-w-0 flex-1 font-semibold leading-tight line-clamp-2" title={displayTitle}>
                    {displayTitle}
                  </h3>
                  {badges ? <div className="hidden shrink-0 items-center gap-1 sm:flex">{badges}</div> : null}
                </div>

                <div className="mt-1 text-xs text-muted-foreground">{infoText}</div>

                {displayDescription ? (
                  <p className="mt-2 text-sm text-muted-foreground line-clamp-2" title={displayDescription}>
                    {displayDescription}
                  </p>
                ) : null}

                {tags.length > 0 ? (
                  <div className="mt-2 flex flex-wrap gap-1">
                    {tags.slice(0, 8).map((tag) => (
                      <Badge key={`${id}-${tag}`} variant="secondary" className="max-w-full text-[10px] sm:text-xs" title={tag}>
                        <span className="truncate">{tag}</span>
                      </Badge>
                    ))}
                  </div>
                ) : null}

                {badges ? <div className="mt-2 flex items-center gap-1 sm:hidden">{badges}</div> : null}
              </div>
            </div>

            <div className="absolute right-3 top-3 flex items-center gap-2">
              {selectable ? (
                <Button
                  type="button"
                  variant={selected ? 'default' : 'secondary'}
                  size="icon"
                  className="h-8 w-8"
                  aria-label={selected ? t('home.unselectItem') : t('home.selectItem')}
                  title={selected ? t('home.unselectItem') : t('home.selectItem')}
                  onClick={(event: MouseEvent<HTMLButtonElement>) => {
                    event.stopPropagation();
                    toggleSelected(!selected);
                  }}
                >
                  {selected ? <Check className="h-4 w-4" /> : <Square className="h-4 w-4" />}
                </Button>
              ) : null}

              <Button
                asChild
                variant="secondary"
                size="icon"
                className="h-8 w-8"
                title={t('archive.details')}
                onClick={(event) => event.stopPropagation()}
              >
                <Link href={detailPath} prefetch={false}>
                  <Eye className="h-4 w-4" />
                </Link>
              </Button>

              <Button
                type="button"
                variant="secondary"
                size="icon"
                className={cn('h-8 w-8', nextIsFavorite && 'text-red-500')}
                title={nextIsFavorite ? t('common.unfavorite') : t('common.favorite')}
                disabled={favoriteLoading}
                onClick={(event: MouseEvent<HTMLButtonElement>) => {
                  event.stopPropagation();
                  void toggleFavorite();
                }}
              >
                {favoriteLoading ? <Spinner size="sm" /> : <Heart className={cn('h-4 w-4', nextIsFavorite && 'fill-current')} />}
              </Button>
            </div>
          </div>
        );
      }}
    </HomeMediaItemMenu>
  );
});

const HomeArchiveListRow = memo(function HomeArchiveListRow({
  archive,
  selectionMode,
  selected,
  onRequestEnterSelection,
  onToggleArchiveSelect,
}: {
  archive: Archive;
  selectionMode: boolean;
  selected: boolean;
  onRequestEnterSelection: () => void;
  onToggleArchiveSelect: (id: string, selected: boolean) => void;
}) {
  const { t } = useLanguage();
  const progressText = archive.progress > 0 && archive.pagecount > 0
    ? ` • ${Math.round((archive.progress / archive.pagecount) * 100)}% ${t('common.read')}`
    : '';
  const infoText = `${t('archive.pages').replace('{count}', String(archive.pagecount))}${progressText}`;
  const coverAssetId = getArchiveAssetId(archive, 'cover');
  const coverSrc = coverAssetId ? `/api/assets/${coverAssetId}` : '';

  return (
    <HomeMediaListItem
      id={archive.arcid}
      type="archive"
      title={archive.title}
      description={archive.description}
      rawTags={archive.tags}
      coverSrc={coverSrc}
      coverAlt={archive.title}
      thumbnailAssetId={coverAssetId}
      detailPath={`/archive?id=${archive.arcid}`}
      readerTargetId={archive.arcid}
      infoText={infoText}
      renderBadges={({ isNew }) => (isNew ? <Badge className="bg-red-500">{t('archive.new')}</Badge> : undefined)}
      selectable
      selectionMode={selectionMode}
      selected={selected}
      isFavorite={Boolean(archive.isfavorite)}
      isNew={archive.isnew}
      progress={archive.progress}
      onToggleSelected={(nextSelected) => onToggleArchiveSelect(archive.arcid, nextSelected)}
      onRequestEnterSelection={onRequestEnterSelection}
    />
  );
});

const HomeTankoubonListRow = memo(function HomeTankoubonListRow({
  tankoubon,
  selectionMode,
  selected,
  onRequestEnterSelection,
  onToggleTankoubonSelect,
}: {
  tankoubon: Tankoubon;
  selectionMode: boolean;
  selected: boolean;
  onRequestEnterSelection: () => void;
  onToggleTankoubonSelect: (id: string, selected: boolean) => void;
}) {
  const { t } = useLanguage();
  const archiveCount = typeof tankoubon.archive_count === 'number' ? tankoubon.archive_count : 0;
  const pageCount = typeof tankoubon.pagecount === 'number' ? tankoubon.pagecount : 0;
  const infoParts = [
    `${archiveCount} ${t('tankoubon.archives')}`,
    t('tankoubon.totalPages').replace('{count}', String(pageCount)),
  ];
  const coverAssetId = getCoverAssetId(tankoubon);
  const firstArchiveId = typeof tankoubon.children?.[0] === 'string' ? tankoubon.children[0] : '';

  return (
    <HomeMediaListItem
      id={tankoubon.tankoubon_id}
      type="tankoubon"
      title={tankoubon.title}
      description={tankoubon.description}
      rawTags={tankoubon.tags}
      coverSrc={coverAssetId ? `/api/assets/${coverAssetId}` : ''}
      coverAlt={tankoubon.title}
      thumbnailAssetId={coverAssetId}
      detailPath={`/tankoubon?id=${tankoubon.tankoubon_id}`}
      readerTargetId={firstArchiveId || undefined}
      infoText={infoParts.join(' • ')}
      renderBadges={() => (
        <>
          <Badge className="bg-primary">
            <BookOpen className="mr-1 h-3 w-3" />
            {t('tankoubon.collection')}
          </Badge>
          <Badge variant="secondary">{archiveCount}</Badge>
        </>
      )}
      selectable
      selectionMode={selectionMode}
      selected={selected}
      isFavorite={Boolean(tankoubon.isfavorite)}
      isNew={Boolean(tankoubon.isnew)}
      onToggleSelected={(nextSelected) => onToggleTankoubonSelect(tankoubon.tankoubon_id, nextSelected)}
      onRequestEnterSelection={onRequestEnterSelection}
    />
  );
});

export const HomeMediaList = memo(function HomeMediaList({
  items,
  selectionMode,
  selectedArchiveIds,
  selectedTankoubonIds,
  onRequestEnterSelection,
  onToggleArchiveSelect,
  onToggleTankoubonSelect,
}: HomeMediaListProps) {
  return (
    <div className="space-y-3">
      {items.map((item) => {
        if (isTankoubonItem(item)) {
          return (
            <HomeTankoubonListRow
              key={`tankoubon:${item.tankoubon_id}`}
              tankoubon={item}
              selectionMode={selectionMode}
              selected={selectedTankoubonIds.has(item.tankoubon_id)}
              onRequestEnterSelection={onRequestEnterSelection}
              onToggleTankoubonSelect={onToggleTankoubonSelect}
            />
          );
        }

        return (
          <HomeArchiveListRow
            key={`archive:${item.arcid}`}
            archive={item}
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
