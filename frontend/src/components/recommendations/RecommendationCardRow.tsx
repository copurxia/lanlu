'use client';

import { memo, useMemo } from 'react';
import { ArchiveCard } from '@/components/archive/ArchiveCard';
import { TankoubonCard } from '@/components/tankoubon/TankoubonCard';
import { useScrollableCardCoverHeight } from '@/hooks/use-scrollable-card-cover-height';
import type { Archive } from '@/types/archive';
import type { RecommendationItem, RecommendationItemType, RecommendationScene } from '@/types/recommendation';
import type { Tankoubon } from '@/types/tankoubon';

function isTankoubonItem(item: RecommendationItem): item is Tankoubon {
  return 'tankoubon_id' in item;
}

type RecommendationCardRowProps = {
  items: RecommendationItem[];
  scene: RecommendationScene;
  seedEntityType?: RecommendationItemType;
  seedEntityId?: string;
  cardSurfaceClassName?: string;
  onOpenReader?: (itemType: RecommendationItemType, itemId: string) => void;
  onOpenDetails?: (itemType: RecommendationItemType, itemId: string) => void;
  onFavorite?: (itemType: RecommendationItemType, itemId: string) => void;
};

const ArchiveRecommendationCard = memo(function ArchiveRecommendationCard({
  archive,
  index,
  scene,
  seedEntityType,
  seedEntityId,
  cardSurfaceClassName,
  onOpenReader,
  onOpenDetails,
  onFavorite,
  coverHeight,
  reportAspectRatio,
}: {
  archive: Archive;
  index: number;
  scene: RecommendationScene;
  seedEntityType?: RecommendationItemType;
  seedEntityId?: string;
  cardSurfaceClassName?: string;
  onOpenReader?: (itemType: RecommendationItemType, itemId: string) => void;
  onOpenDetails?: (itemType: RecommendationItemType, itemId: string) => void;
  onFavorite?: (itemType: RecommendationItemType, itemId: string) => void;
  coverHeight?: number;
  reportAspectRatio: (key: string, aspectRatio: number) => void;
}) {
  return (
    <div className="w-32 sm:w-36 md:w-40 lg:w-44 xl:w-48 shrink-0">
      <ArchiveCard
        archive={archive}
        index={index}
        priority={index < 2}
        disableContentVisibility
        coverHeight={coverHeight}
        surfaceClassName={cardSurfaceClassName}
        onCoverAspectRatioChange={(aspectRatio) => reportAspectRatio(`archive:${archive.arcid}`, aspectRatio)}
        recommendationContext={{
          scene,
          seedEntityType,
          seedEntityId,
        }}
        onRecommendationOpenReader={onOpenReader}
        onRecommendationOpenDetails={onOpenDetails}
        onRecommendationFavorite={onFavorite}
      />
    </div>
  );
});

const TankoubonRecommendationCard = memo(function TankoubonRecommendationCard({
  tankoubon,
  index,
  scene,
  seedEntityType,
  seedEntityId,
  cardSurfaceClassName,
  onOpenReader,
  onOpenDetails,
  onFavorite,
  coverHeight,
  reportAspectRatio,
}: {
  tankoubon: Tankoubon;
  index: number;
  scene: RecommendationScene;
  seedEntityType?: RecommendationItemType;
  seedEntityId?: string;
  cardSurfaceClassName?: string;
  onOpenReader?: (itemType: RecommendationItemType, itemId: string) => void;
  onOpenDetails?: (itemType: RecommendationItemType, itemId: string) => void;
  onFavorite?: (itemType: RecommendationItemType, itemId: string) => void;
  coverHeight?: number;
  reportAspectRatio: (key: string, aspectRatio: number) => void;
}) {
  return (
    <div className="w-32 sm:w-36 md:w-40 lg:w-44 xl:w-48 shrink-0">
      <TankoubonCard
        tankoubon={tankoubon}
        priority={index < 2}
        disableContentVisibility
        coverHeight={coverHeight}
        surfaceClassName={cardSurfaceClassName}
        onCoverAspectRatioChange={(aspectRatio) => reportAspectRatio(`tankoubon:${tankoubon.tankoubon_id}`, aspectRatio)}
        recommendationContext={{
          scene,
          seedEntityType,
          seedEntityId,
        }}
        onRecommendationOpenReader={onOpenReader}
        onRecommendationOpenDetails={onOpenDetails}
        onRecommendationFavorite={onFavorite}
      />
    </div>
  );
});

export const RecommendationCardRow = memo(function RecommendationCardRow({
  items,
  scene,
  seedEntityType,
  seedEntityId,
  cardSurfaceClassName,
  onOpenReader,
  onOpenDetails,
  onFavorite,
}: RecommendationCardRowProps) {
  const itemKeys = useMemo(() => items.map((item) => (
    isTankoubonItem(item) ? `tankoubon:${item.tankoubon_id}` : `archive:${item.arcid}`
  )), [items]);
  const { reportAspectRatio, sharedCoverHeight } = useScrollableCardCoverHeight(itemKeys);

  return (
    <div className="flex items-start gap-4 overflow-x-auto pb-2 pr-2">
      {items.map((item, index) =>
        isTankoubonItem(item) ? (
          <TankoubonRecommendationCard
            key={`tankoubon:${item.tankoubon_id}`}
            index={index}
            tankoubon={item}
            coverHeight={sharedCoverHeight}
            reportAspectRatio={reportAspectRatio}
            scene={scene}
            seedEntityType={seedEntityType}
            seedEntityId={seedEntityId}
            cardSurfaceClassName={cardSurfaceClassName}
            onOpenReader={onOpenReader}
            onOpenDetails={onOpenDetails}
            onFavorite={onFavorite}
          />
        ) : (
          <ArchiveRecommendationCard
            key={`archive:${item.arcid}`}
            archive={item}
            index={index}
            coverHeight={sharedCoverHeight}
            reportAspectRatio={reportAspectRatio}
            scene={scene}
            seedEntityType={seedEntityType}
            seedEntityId={seedEntityId}
            cardSurfaceClassName={cardSurfaceClassName}
            onOpenReader={onOpenReader}
            onOpenDetails={onOpenDetails}
            onFavorite={onFavorite}
          />
        )
      )}
    </div>
  );
});
