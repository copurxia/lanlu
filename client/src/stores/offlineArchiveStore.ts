import {create} from 'zustand';
import {persist, createJSONStorage} from 'zustand/middleware';
import {createMmkvStorage} from '../storage/zustandMmkvStorage';
import type {ArchiveMetadata, PageInfo, Tankoubon, Archive} from '../types/api';

type CachedArchive = {
  metadata: ArchiveMetadata;
  pages: PageInfo[];
  related: Archive[];
  tankoubons: Tankoubon[];
  timestamp: number;
};

type OfflineArchiveState = {
  archives: Record<string, CachedArchive>;
  lastServerId: string | null;

  cacheArchive: (serverId: string, archiveId: string, data: {
    metadata?: ArchiveMetadata;
    pages?: PageInfo[];
    related?: Archive[];
    tankoubons?: Tankoubon[];
  }) => void;

  getCachedArchive: (serverId: string, archiveId: string) => CachedArchive | null;

  clearArchiveCache: (serverId?: string) => void;
};

export const useOfflineArchiveStore = create<OfflineArchiveState>()(
  persist(
    (set, get) => ({
      archives: {},
      lastServerId: null,

      cacheArchive(serverId, archiveId, data) {
        set(state => {
          const key = `${serverId}:${archiveId}`;
          const existing = state.archives[key] || {
            metadata: {} as ArchiveMetadata,
            pages: [],
            related: [],
            tankoubons: [],
            timestamp: Date.now(),
          };
          return {
            archives: {
              ...state.archives,
              [key]: {
                metadata: data.metadata || existing.metadata,
                pages: data.pages || existing.pages,
                related: data.related || existing.related,
                tankoubons: data.tankoubons || existing.tankoubons,
                timestamp: Date.now(),
              },
            },
            lastServerId: serverId,
          };
        });
      },

      getCachedArchive(serverId, archiveId) {
        return get().archives[`${serverId}:${archiveId}`] || null;
      },

      clearArchiveCache(serverId) {
        if (serverId) {
          set(state => {
            const next = Object.fromEntries(
              Object.entries(state.archives).filter(([k]) => !k.startsWith(`${serverId}:`)),
            );
            return {archives: next};
          });
        } else {
          set({archives: {}});
        }
      },
    }),
    {
      name: 'offline-archive',
      storage: createJSONStorage(() => createMmkvStorage('offline-archive')),
      partialize: state => ({
        archives: state.archives,
        lastServerId: state.lastServerId,
      }),
    },
  ),
);
