import {create} from 'zustand';
import {persist, createJSONStorage} from 'zustand/middleware';
import {createMmkvStorage} from '../storage/zustandMmkvStorage';
import type {MediaItem} from '../types/api';

type CachedFavorites = {
  favorites: MediaItem[];
  history: MediaItem[];
  timestamp: number;
};

type OfflineGeneralState = {
  favorites: Record<string, CachedFavorites>;
  lastServerId: string | null;

  cacheFavorites: (serverId: string, data: {
    favorites?: MediaItem[];
    history?: MediaItem[];
  }) => void;

  getCachedFavorites: (serverId: string) => CachedFavorites | null;

  clearGeneralCache: (serverId?: string) => void;
};

export const useOfflineGeneralStore = create<OfflineGeneralState>()(
  persist(
    (set, get) => ({
      favorites: {},
      lastServerId: null,

      cacheFavorites(serverId, data) {
        set(state => {
          const existing = state.favorites[serverId] || {
            favorites: [],
            history: [],
            timestamp: Date.now(),
          };
          return {
            favorites: {
              ...state.favorites,
              [serverId]: {
                favorites: data.favorites || existing.favorites,
                history: data.history || existing.history,
                timestamp: Date.now(),
              },
            },
            lastServerId: serverId,
          };
        });
      },

      getCachedFavorites(serverId) {
        return get().favorites[serverId] || null;
      },

      clearGeneralCache(serverId) {
        if (serverId) {
          set(state => {
            const next = {...state.favorites};
            delete next[serverId];
            return {favorites: next};
          });
        } else {
          set({favorites: {}});
        }
      },
    }),
    {
      name: 'offline-general',
      storage: createJSONStorage(() => createMmkvStorage('offline-general')),
      partialize: state => ({
        favorites: state.favorites,
        lastServerId: state.lastServerId,
      }),
    },
  ),
);
