'use client';

import { memo, useMemo } from 'react';
import { ArchiveCard } from '@/components/archive/ArchiveCard';
import { TankoubonCard } from '@/components/tankoubon/TankoubonCard';
import { useScrollableCardCoverHeight } from '@/hooks/use-scrollable-card-cover-height';
import { Archive } from '@/types/archive';
import type { RecommendationItemType } from '@/types/recommendation';
import { Tankoubon } from '@/types/tankoubon';

export function isTankoubonItem(item: Archive | Tankoubon): item is Tankoubon {
  return 'tankoubon_id' in item;
}

const HomeScrollableTankoubonCard = memo(function HomeScrollableTankoubonCard({
  itemKey,
  index,
  coverHeight,
  selectionMode,
  selected,
  enterSelectionMode,
  toggleTankoubonSelect,
  tankoubon,
  reportAspectRatio,
  onRecommendationOpenReader,
  onRecommendationFavorite,
}: {
  itemKey: string;
  index: number;
  coverHeight?: number;
  selectionMode: boolean;
  selected: boolean;
  enterSelectionMode: () => void;
  toggleTankoubonSelect: (id: string, selected: boolean) => void;
  tankoubon: Tankoubon;
  reportAspectRatio: (key: string, aspectRatio: number) => void;
  onRecommendationOpenReader?: (itemType: RecommendationItemType, itemId: string) => void;
  onRecommendationFavorite?: (itemType: RecommendationItemType, itemId: string) => void;
}) {
  return (
    <div className="w-32 sm:w-36 md:w-40 lg:w-44 xl:w-48 shrink-0">
      <TankoubonCard
        tankoubon={tankoubon}
        priority={index < 2}
        disableContentVisibility
        coverHeight={coverHeight}
        selectable
        selectionMode={selectionMode}
        selected={selected}
        onRequestEnterSelection={enterSelectionMode}
        onToggleSelect={(nextSelected) => toggleTankoubonSelect(tankoubon.tankoubon_id, nextSelected)}
        onCoverAspectRatioChange={(aspectRatio) => reportAspectRatio(itemKey, aspectRatio)}
        recommendationContext={{ scene: 'discover' }}
        onRecommendationOpenReader={onRecommendationOpenReader}
        onRecommendationFavorite={onRecommendationFavorite}
      />
    </div>
  );
});

const HomeScrollableArchiveCard = memo(function HomeScrollableArchiveCard({
  archive,
  itemKey,
  index,
  coverHeight,
  selectionMode,
  selected,
  enterSelectionMode,
  toggleArchiveSelect,
  reportAspectRatio,
  onRecommendationOpenReader,
  onRecommendationFavorite,
}: {
  archive: Archive;
  itemKey: string;
  index: number;
  coverHeight?: number;
  selectionMode: boolean;
  selected: boolean;
  enterSelectionMode: () => void;
  toggleArchiveSelect: (id: string, selected: boolean) => void;
  reportAspectRatio: (key: string, aspectRatio: number) => void;
  onRecommendationOpenReader?: (itemType: RecommendationItemType, itemId: string) => void;
  onRecommendationFavorite?: (itemType: RecommendationItemType, itemId: string) => void;
}) {
  return (
    <div className="w-32 sm:w-36 md:w-40 lg:w-44 xl:w-48 shrink-0">
      <ArchiveCard
        archive={archive}
        index={index}
        priority={index < 2}
        disableContentVisibility
        coverHeight={coverHeight}
        selectable
        selectionMode={selectionMode}
        selected={selected}
        onRequestEnterSelection={enterSelectionMode}
        onToggleSelect={(nextSelected) => toggleArchiveSelect(archive.arcid, nextSelected)}
        onCoverAspectRatioChange={(aspectRatio) => reportAspectRatio(itemKey, aspectRatio)}
        recommendationContext={{ scene: 'discover' }}
        onRecommendationOpenReader={onRecommendationOpenReader}
        onRecommendationFavorite={onRecommendationFavorite}
      />
    </div>
  );
});

export const HomeScrollableCardRow = memo(function HomeScrollableCardRow({
  items,
  selectionMode,
  selectedArchiveIds,
  selectedTankoubonIds,
  enterSelectionMode: enterSelectionModeProp,
  toggleArchiveSelect: toggleArchiveSelectProp,
  toggleTankoubonSelect: toggleTankoubonSelectProp,
  onRequestEnterSelection,
  onToggleArchiveSelect,
  onToggleTankoubonSelect,
  onRecommendationOpenReader,
  onRecommendationFavorite,
}: {
  items: (Archive | Tankoubon)[];
  selectionMode: boolean;
  selectedArchiveIds: Set<string>;
  selectedTankoubonIds: Set<string>;
  enterSelectionMode?: () => void;
  toggleArchiveSelect?: (id: string, selected: boolean) => void;
  toggleTankoubonSelect?: (id: string, selected: boolean) => void;
  onRequestEnterSelection?: () => void;
  onToggleArchiveSelect?: (id: string, selected: boolean) => void;
  onToggleTankoubonSelect?: (id: string, selected: boolean) => void;
  onRecommendationOpenReader?: (itemType: RecommendationItemType, itemId: string) => void;
  onRecommendationFavorite?: (itemType: RecommendationItemType, itemId: string) => void;
}) {
  const enterSelectionMode = enterSelectionModeProp ?? onRequestEnterSelection ?? (() => {});
  const toggleArchiveSelect = toggleArchiveSelectProp ?? onToggleArchiveSelect ?? (() => {});
  const toggleTankoubonSelect = toggleTankoubonSelectProp ?? onToggleTankoubonSelect ?? (() => {});
  const itemKeys = useMemo(() => items.map((item) => (
    isTankoubonItem(item) ? `tankoubon:${item.tankoubon_id}` : `archive:${item.arcid}`
  )), [items]);
  const { reportAspectRatio, sharedCoverHeight } = useScrollableCardCoverHeight(itemKeys);

  return (
    <div className="flex items-start gap-4 overflow-x-auto pb-2 pr-2">
      {items.map((item, index) => {
        const itemKey = isTankoubonItem(item) ? `tankoubon:${item.tankoubon_id}` : `archive:${item.arcid}`;
        return (
          isTankoubonItem(item) ? (
            <HomeScrollableTankoubonCard
              key={itemKey}
              itemKey={itemKey}
              index={index}
              coverHeight={sharedCoverHeight}
              selectionMode={selectionMode}
              selected={selectedTankoubonIds.has(item.tankoubon_id)}
              enterSelectionMode={enterSelectionMode}
              toggleTankoubonSelect={toggleTankoubonSelect}
              tankoubon={item}
              reportAspectRatio={reportAspectRatio}
              onRecommendationOpenReader={onRecommendationOpenReader}
              onRecommendationFavorite={onRecommendationFavorite}
            />
          ) : (
            <HomeScrollableArchiveCard
              key={itemKey}
              archive={item}
              itemKey={itemKey}
              index={index}
              coverHeight={sharedCoverHeight}
              selectionMode={selectionMode}
              selected={selectedArchiveIds.has(item.arcid)}
              enterSelectionMode={enterSelectionMode}
              toggleArchiveSelect={toggleArchiveSelect}
              reportAspectRatio={reportAspectRatio}
              onRecommendationOpenReader={onRecommendationOpenReader}
              onRecommendationFavorite={onRecommendationFavorite}
            />
          )
        );
      })}
    </div>
  );
});
