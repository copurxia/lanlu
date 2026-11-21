import {create} from 'zustand';
import {persist, createJSONStorage} from 'zustand/middleware';
import {createMmkvStorage} from '../storage/zustandMmkvStorage';
import type {UserStats, ReadingTrendItem} from '../api/lanlu';

type CachedDashboard = {
  stats: UserStats;
  trend: ReadingTrendItem[];
};

type OfflineSettingsState = {
  dashboard: Record<string, CachedDashboard>;
  lastServerId: string | null;

  cacheDashboard: (serverId: string, data: CachedDashboard) => void;

  getCachedDashboard: (serverId: string) => CachedDashboard | null;

  clearSettingsCache: (serverId?: string) => void;
};

export const useOfflineSettingsStore = create<OfflineSettingsState>()(
  persist(
    (set, get) => ({
      dashboard: {},
      lastServerId: null,

      cacheDashboard(serverId, data) {
        set(state => ({
          dashboard: {
            ...state.dashboard,
            [serverId]: data,
          },
          lastServerId: serverId,
        }));
      },

      getCachedDashboard(serverId) {
        return get().dashboard[serverId] || null;
      },

      clearSettingsCache(serverId) {
        if (serverId) {
          set(state => {
            const next = {...state.dashboard};
            delete next[serverId];
            return {dashboard: next};
          });
        } else {
          set({dashboard: {}});
        }
      },
    }),
    {
      name: 'offline-settings',
      storage: createJSONStorage(() => createMmkvStorage('offline-settings')),
      partialize: state => ({
        dashboard: state.dashboard,
        lastServerId: state.lastServerId,
      }),
    },
  ),
);
