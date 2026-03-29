'use client';

import { memo } from 'react';
import { ArchiveCard } from '@/components/archive/ArchiveCard';
import { TankoubonCard } from '@/components/tankoubon/TankoubonCard';
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
  onOpenReader,
  onOpenDetails,
  onFavorite,
}: {
  archive: Archive;
  index: number;
  scene: RecommendationScene;
  seedEntityType?: RecommendationItemType;
  seedEntityId?: string;
  onOpenReader?: (itemType: RecommendationItemType, itemId: string) => void;
  onOpenDetails?: (itemType: RecommendationItemType, itemId: string) => void;
  onFavorite?: (itemType: RecommendationItemType, itemId: string) => void;
}) {
  return (
    <div className="w-32 sm:w-36 md:w-40 lg:w-44 xl:w-48 flex-shrink-0">
      <ArchiveCard
        archive={archive}
        index={index}
        priority={index < 2}
        disableContentVisibility
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
  onOpenReader,
  onOpenDetails,
  onFavorite,
}: {
  tankoubon: Tankoubon;
  index: number;
  scene: RecommendationScene;
  seedEntityType?: RecommendationItemType;
  seedEntityId?: string;
  onOpenReader?: (itemType: RecommendationItemType, itemId: string) => void;
  onOpenDetails?: (itemType: RecommendationItemType, itemId: string) => void;
  onFavorite?: (itemType: RecommendationItemType, itemId: string) => void;
}) {
  return (
    <div className="w-32 sm:w-36 md:w-40 lg:w-44 xl:w-48 flex-shrink-0">
      <TankoubonCard
        tankoubon={tankoubon}
        priority={index < 2}
        disableContentVisibility
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
  onOpenReader,
  onOpenDetails,
  onFavorite,
}: RecommendationCardRowProps) {
  return (
    <div className="flex items-start gap-4 overflow-x-auto pb-2 pr-2">
      {items.map((item, index) =>
        isTankoubonItem(item) ? (
          <TankoubonRecommendationCard
            key={`tankoubon:${item.tankoubon_id}`}
            index={index}
            tankoubon={item}
            scene={scene}
            seedEntityType={seedEntityType}
            seedEntityId={seedEntityId}
            onOpenReader={onOpenReader}
            onOpenDetails={onOpenDetails}
            onFavorite={onFavorite}
          />
        ) : (
          <ArchiveRecommendationCard
            key={`archive:${item.arcid}`}
            archive={item}
            index={index}
            scene={scene}
            seedEntityType={seedEntityType}
            seedEntityId={seedEntityId}
            onOpenReader={onOpenReader}
            onOpenDetails={onOpenDetails}
            onFavorite={onFavorite}
          />
        )
      )}
    </div>
  );
});
