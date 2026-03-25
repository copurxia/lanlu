'use client';

import type { MouseEvent, ReactNode } from 'react';
import { useCallback, useEffect, useMemo, useState } from 'react';
import Image from 'next/image';
import Link from 'next/link';
import { useRouter } from 'next/navigation';
import { BookOpen, Check, Eye, Heart, Square } from 'lucide-react';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Spinner } from '@/components/ui/spinner';
import { useLanguage } from '@/contexts/LanguageContext';
import { FavoriteService } from '@/lib/services/favorite-service';
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
  id: string;
  title: string;
  description: string;
  tags: string[];
  coverSrc: string;
  coverAlt: string;
  detailPath: string;
  readerPath: string;
  infoText: string;
  badges?: ReactNode;
  selectable: boolean;
  selectionMode: boolean;
  selected: boolean;
  isFavorite: boolean;
  onToggleSelected: (selected: boolean) => void;
  onToggleFavorite: () => Promise<void>;
};

function isTankoubonItem(item: Archive | Tankoubon): item is Tankoubon {
  return 'tankoubon_id' in item;
}

function HomeMediaListItem({
  id,
  title,
  description,
  tags,
  coverSrc,
  coverAlt,
  detailPath,
  readerPath,
  infoText,
  badges,
  selectable,
  selectionMode,
  selected,
  isFavorite,
  onToggleSelected,
  onToggleFavorite,
}: HomeMediaListItemProps) {
  const router = useRouter();
  const { t } = useLanguage();
  const [favoriteLoading, setFavoriteLoading] = useState(false);

  const handleNavigate = useCallback(() => {
    router.push(readerPath);
  }, [readerPath, router]);

  const handleToggleFavorite = useCallback(async (e: MouseEvent<HTMLButtonElement>) => {
    e.stopPropagation();
    if (favoriteLoading) return;
    setFavoriteLoading(true);
    try {
      await onToggleFavorite();
    } finally {
      setFavoriteLoading(false);
    }
  }, [favoriteLoading, onToggleFavorite]);

  const handleToggleSelected = useCallback((e: MouseEvent<HTMLButtonElement>) => {
    e.stopPropagation();
    onToggleSelected(!selected);
  }, [onToggleSelected, selected]);

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
          onToggleSelected(!selected);
          return;
        }
        handleNavigate();
      }}
      onKeyDown={(e) => {
        if (e.key !== 'Enter' && e.key !== ' ') return;
        e.preventDefault();
        if (selectionMode && selectable) {
          onToggleSelected(!selected);
          return;
        }
        handleNavigate();
      }}
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
            <h3 className="min-w-0 flex-1 font-semibold leading-tight line-clamp-2" title={title}>
              {title}
            </h3>
            {badges ? <div className="hidden shrink-0 items-center gap-1 sm:flex">{badges}</div> : null}
          </div>

          <div className="mt-1 text-xs text-muted-foreground">{infoText}</div>

          {description ? (
            <p className="mt-2 text-sm text-muted-foreground line-clamp-2" title={description}>
              {description}
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
            onClick={handleToggleSelected}
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
          onClick={(e) => e.stopPropagation()}
        >
          <Link href={detailPath} prefetch={false}>
            <Eye className="h-4 w-4" />
          </Link>
        </Button>

        <Button
          type="button"
          variant="secondary"
          size="icon"
          className={cn('h-8 w-8', isFavorite && 'text-red-500')}
          title={isFavorite ? t('common.unfavorite') : t('common.favorite')}
          disabled={favoriteLoading}
          onClick={handleToggleFavorite}
        >
          {favoriteLoading ? <Spinner size="sm" /> : <Heart className={cn('h-4 w-4', isFavorite && 'fill-current')} />}
        </Button>
      </div>
    </div>
  );
}

function HomeArchiveListRow({
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

  const tags = useMemo(() => parseTags(archive.tags).map(stripNamespace), [archive.tags]);
  const progressText = archive.progress > 0 && archive.pagecount > 0
    ? ` • ${Math.round((archive.progress / archive.pagecount) * 100)}% ${t('common.read')}`
    : '';
  const infoText = `${t('archive.pages').replace('{count}', String(archive.pagecount))}${progressText}`;

  const handleToggleSelected = useCallback((nextSelected: boolean) => {
    if (nextSelected && !selectionMode) onRequestEnterSelection();
    onToggleSelect(nextSelected);
  }, [onRequestEnterSelection, onToggleSelect, selectionMode]);

  const handleToggleFavorite = useCallback(async () => {
    const success = await FavoriteService.toggleFavorite(archive.arcid, isFavorite);
    if (success) setIsFavorite((current) => !current);
  }, [archive.arcid, isFavorite]);

  const coverAssetId = getArchiveAssetId(archive, 'cover');
  const coverSrc = coverAssetId ? `/api/assets/${coverAssetId}` : '';

  return (
    <HomeMediaListItem
      id={`archive:${archive.arcid}`}
      title={archive.title}
      description={archive.description}
      tags={tags}
      coverSrc={coverSrc}
      coverAlt={archive.title}
      detailPath={`/archive?id=${archive.arcid}`}
      readerPath={`/reader?id=${archive.arcid}`}
      infoText={infoText}
      badges={archive.isnew ? <Badge className="bg-red-500">{t('archive.new')}</Badge> : undefined}
      selectable
      selectionMode={selectionMode}
      selected={selected}
      isFavorite={isFavorite}
      onToggleSelected={handleToggleSelected}
      onToggleFavorite={handleToggleFavorite}
    />
  );
}

function HomeTankoubonListRow({
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

  const tags = useMemo(() => parseTags(tankoubon.tags).map(stripNamespace), [tankoubon.tags]);
  const archiveCount = typeof tankoubon.archive_count === 'number' ? tankoubon.archive_count : 0;
  const pageCount = typeof tankoubon.pagecount === 'number' ? tankoubon.pagecount : 0;
  const infoParts = [
    `${archiveCount} ${t('tankoubon.archives')}`,
    t('tankoubon.totalPages').replace('{count}', String(pageCount)),
  ];
  const coverAssetId = getCoverAssetId(tankoubon);
  const firstArchiveId = typeof tankoubon.children?.[0] === 'string' ? tankoubon.children[0] : '';
  const readerPath = firstArchiveId ? `/reader?id=${firstArchiveId}` : `/tankoubon?id=${tankoubon.tankoubon_id}`;

  const handleToggleSelected = useCallback((nextSelected: boolean) => {
    if (nextSelected && !selectionMode) onRequestEnterSelection();
    onToggleSelect(nextSelected);
  }, [onRequestEnterSelection, onToggleSelect, selectionMode]);

  const handleToggleFavorite = useCallback(async () => {
    const success = await FavoriteService.toggleTankoubonFavorite(tankoubon.tankoubon_id, isFavorite);
    if (success) setIsFavorite((current) => !current);
  }, [isFavorite, tankoubon.tankoubon_id]);

  return (
    <HomeMediaListItem
      id={`tankoubon:${tankoubon.tankoubon_id}`}
      title={tankoubon.title}
      description={tankoubon.description}
      tags={tags}
      coverSrc={coverAssetId ? `/api/assets/${coverAssetId}` : ''}
      coverAlt={tankoubon.title}
      detailPath={`/tankoubon?id=${tankoubon.tankoubon_id}`}
      readerPath={readerPath}
      infoText={infoParts.join(' • ')}
      badges={(
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
      isFavorite={isFavorite}
      onToggleSelected={handleToggleSelected}
      onToggleFavorite={handleToggleFavorite}
    />
  );
}

export function HomeMediaList({
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
              onToggleSelect={(selected) => onToggleTankoubonSelect(item.tankoubon_id, selected)}
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
            onToggleSelect={(selected) => onToggleArchiveSelect(item.arcid, selected)}
          />
        );
      })}
    </div>
  );
}
