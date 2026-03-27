'use client';

import { memo } from 'react';
import { ArchiveCard } from '@/components/archive/ArchiveCard';
import { TankoubonCard } from '@/components/tankoubon/TankoubonCard';
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
};

function isTankoubonItem(item: Archive | Tankoubon): item is Tankoubon {
  return 'tankoubon_id' in item;
}

const HomeTankoubonMasonryCard = memo(function HomeTankoubonMasonryCard({
  index,
  onRequestEnterSelection,
  onToggleTankoubonSelect,
  selectionMode,
  selected,
  tankoubon,
}: {
  index: number;
  onRequestEnterSelection: () => void;
  onToggleTankoubonSelect: (id: string, selected: boolean) => void;
  selectionMode: boolean;
  selected: boolean;
  tankoubon: Tankoubon;
}) {
  return (
    <div className="mb-4 break-inside-avoid">
      <TankoubonCard
        tankoubon={tankoubon}
        priority={index < 4}
        selectable
        selectionMode={selectionMode}
        selected={selected}
        onRequestEnterSelection={onRequestEnterSelection}
        onToggleSelect={(nextSelected) => onToggleTankoubonSelect(tankoubon.tankoubon_id, nextSelected)}
      />
    </div>
  );
});

const HomeArchiveMasonryCard = memo(function HomeArchiveMasonryCard({
  archive,
  index,
  onRequestEnterSelection,
  onToggleArchiveSelect,
  selectionMode,
  selected,
}: {
  archive: Archive;
  index: number;
  onRequestEnterSelection: () => void;
  onToggleArchiveSelect: (id: string, selected: boolean) => void;
  selectionMode: boolean;
  selected: boolean;
}) {
  return (
    <div className="mb-4 break-inside-avoid">
      <ArchiveCard
        archive={archive}
        index={index}
        priority={index < 4}
        selectable
        selectionMode={selectionMode}
        selected={selected}
        onRequestEnterSelection={onRequestEnterSelection}
        onToggleSelect={(nextSelected) => onToggleArchiveSelect(archive.arcid, nextSelected)}
      />
    </div>
  );
});

export const HomeMediaMasonry = memo(function HomeMediaMasonry({
  items,
  selectionMode,
  selectedArchiveIds,
  selectedTankoubonIds,
  onRequestEnterSelection,
  onToggleArchiveSelect,
  onToggleTankoubonSelect,
}: HomeMediaMasonryProps) {
  return (
    <div className="columns-2 gap-4 sm:columns-3 lg:columns-4 xl:columns-5 2xl:columns-6">
      {items.map((item, index) => {
        if (isTankoubonItem(item)) {
          return (
            <HomeTankoubonMasonryCard
              key={`tankoubon:${item.tankoubon_id}`}
              index={index}
              onRequestEnterSelection={onRequestEnterSelection}
              onToggleTankoubonSelect={onToggleTankoubonSelect}
              selectionMode={selectionMode}
              selected={selectedTankoubonIds.has(item.tankoubon_id)}
              tankoubon={item}
            />
          );
        }

        return (
          <HomeArchiveMasonryCard
            key={`archive:${item.arcid}`}
            archive={item}
            index={index}
            onRequestEnterSelection={onRequestEnterSelection}
            onToggleArchiveSelect={onToggleArchiveSelect}
            selectionMode={selectionMode}
            selected={selectedArchiveIds.has(item.arcid)}
          />
        );
      })}
    </div>
  );
});
