import {create} from 'zustand';
import {persist, createJSONStorage} from 'zustand/middleware';
import {createMmkvStorage} from '../storage/zustandMmkvStorage';
import type {Archive, Tankoubon, TankoubonMetadata} from '../types/api';

type CachedTankoubon = {
  metadata: TankoubonMetadata;
  archives: Archive[];
  related: Tankoubon[];
  timestamp: number;
};

const MAX_TANKOUBON_CACHE_ENTRIES = 40;

type OfflineTankoubonState = {
  tankoubons: Record<string, CachedTankoubon>;
  lastServerId: string | null;

  cacheTankoubon: (serverId: string, tankoubonId: string, data: {
    metadata?: TankoubonMetadata;
    archives?: Archive[];
    related?: Tankoubon[];
  }) => void;

  getCachedTankoubon: (serverId: string, tankoubonId: string) => CachedTankoubon | null;

  clearTankoubonCache: (serverId?: string) => void;
};

export const useOfflineTankoubonStore = create<OfflineTankoubonState>()(
  persist(
    (set, get) => ({
      tankoubons: {},
      lastServerId: null,

      cacheTankoubon(serverId, tankoubonId, data) {
        set(state => {
          const key = `${serverId}:${tankoubonId}`;
          const existing = state.tankoubons[key] || {
            metadata: {} as TankoubonMetadata,
            archives: [],
            related: [],
            timestamp: Date.now(),
          };
          const tankoubons = {
            ...state.tankoubons,
            [key]: {
              metadata: data.metadata || existing.metadata,
              archives: data.archives || existing.archives,
              related: data.related || existing.related,
              timestamp: Date.now(),
            },
          };
          // Bound the persisted JSON: every zustand write serializes the whole map.
          const entries = Object.entries(tankoubons);
          if (entries.length > MAX_TANKOUBON_CACHE_ENTRIES) {
            entries
              .sort((a, b) => a[1].timestamp - b[1].timestamp)
              .slice(0, entries.length - MAX_TANKOUBON_CACHE_ENTRIES)
              .forEach(([entryKey]) => delete tankoubons[entryKey]);
          }
          return {
            tankoubons,
            lastServerId: serverId,
          };
        });
      },

      getCachedTankoubon(serverId, tankoubonId) {
        return get().tankoubons[`${serverId}:${tankoubonId}`] || null;
      },

      clearTankoubonCache(serverId) {
        if (serverId) {
          set(state => {
            const next = Object.fromEntries(
              Object.entries(state.tankoubons).filter(([k]) => !k.startsWith(`${serverId}:`)),
            );
            return {tankoubons: next};
          });
        } else {
          set({tankoubons: {}});
        }
      },
    }),
    {
      name: 'offline-tankoubon',
      storage: createJSONStorage(() => createMmkvStorage('offline-tankoubon')),
      partialize: state => ({
        tankoubons: state.tankoubons,
        lastServerId: state.lastServerId,
      }),
    },
  ),
);
