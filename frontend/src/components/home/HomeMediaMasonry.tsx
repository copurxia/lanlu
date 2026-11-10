'use client';

import { memo, type RefObject } from 'react';
import { MediaMasonryGrid } from '@/components/media/MediaMasonryGrid';
import type { Archive } from '@/types/archive';
import type { Tankoubon } from '@/types/tankoubon';

type HomeMediaMasonryProps = {
  items: Array<Archive | Tankoubon>;
  selectionMode: boolean;
  selectedArchiveIds: Set<string>;
  selectedTankoubonIds: Set<string>;
  onRequestEnterSelection: () => void;
  onToggleArchiveSelect: (id: string, selected: boolean) => void;
  onToggleTankoubonSelect: (id: string, selected: boolean) => void;
  scrollContainerRef?: RefObject<HTMLElement | null>;
};

export const HomeMediaMasonry = memo(function HomeMediaMasonry({
  items,
  selectionMode,
  selectedArchiveIds,
  selectedTankoubonIds,
  onRequestEnterSelection,
  onToggleArchiveSelect,
  onToggleTankoubonSelect,
  scrollContainerRef,
}: HomeMediaMasonryProps) {
  return (
    <MediaMasonryGrid
      items={items}
      selectionMode={selectionMode}
      selectedArchiveIds={selectedArchiveIds}
      selectedTankoubonIds={selectedTankoubonIds}
      onRequestEnterSelection={onRequestEnterSelection}
      onToggleArchiveSelect={onToggleArchiveSelect}
      onToggleTankoubonSelect={onToggleTankoubonSelect}
      scrollContainerRef={scrollContainerRef}
    />
  );
});
