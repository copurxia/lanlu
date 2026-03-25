'use client';

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

export function HomeMediaMasonry({
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
            <div key={`tankoubon:${item.tankoubon_id}`} className="mb-4 break-inside-avoid">
              <TankoubonCard
                tankoubon={item}
                priority={index < 4}
                selectable
                selectionMode={selectionMode}
                selected={selectedTankoubonIds.has(item.tankoubon_id)}
                onRequestEnterSelection={onRequestEnterSelection}
                onToggleSelect={(selected) => onToggleTankoubonSelect(item.tankoubon_id, selected)}
              />
            </div>
          );
        }

        return (
          <div key={`archive:${item.arcid}`} className="mb-4 break-inside-avoid">
            <ArchiveCard
              archive={item}
              index={index}
              priority={index < 4}
              selectable
              selectionMode={selectionMode}
              selected={selectedArchiveIds.has(item.arcid)}
              onRequestEnterSelection={onRequestEnterSelection}
              onToggleSelect={(selected) => onToggleArchiveSelect(item.arcid, selected)}
            />
          </div>
        );
      })}
    </div>
  );
}
