import {create} from 'zustand';
import {persist, createJSONStorage} from 'zustand/middleware';
import {createMmkvStorage} from '../storage/zustandMmkvStorage';
import type {Category, MediaItem} from '../types/api';

type CachedFeed = {
  items: MediaItem[];
  categories: Category[];
  categoryRows: Record<string, MediaItem[]>;
  randomItems: MediaItem[];
  smartFilters?: any[];
  total: number;
  page: number;
  timestamp: number;
};

type FeedCacheKey = string;

type OfflineFeedState = {
  feedCache: Record<FeedCacheKey, CachedFeed>;
  lastServerId: string | null;

  cacheFeed: (serverId: string, key: FeedCacheKey, feed: {
    items: MediaItem[];
    categories?: Category[];
    categoryRows?: Record<string, MediaItem[]>;
    randomItems?: MediaItem[];
    smartFilters?: any[];
    total?: number;
    page?: number;
  }) => void;

  getCachedFeed: (serverId: string, key: FeedCacheKey) => CachedFeed | null;

  clearFeedCache: (serverId?: string) => void;
};

export const useOfflineFeedStore = create<OfflineFeedState>()(
  persist(
    (set, get) => ({
      feedCache: {},
      lastServerId: null,

      cacheFeed(serverId, key, feed) {
        set(state => {
          const next = {...state.feedCache};
          next[`${serverId}:${key}`] = {
            items: feed.items,
            categories: feed.categories || [],
            categoryRows: feed.categoryRows || {},
            randomItems: feed.randomItems || [],
            smartFilters: feed.smartFilters,
            total: feed.total || feed.items.length,
            page: feed.page || 1,
            timestamp: Date.now(),
          };
          return {
            feedCache: next,
            lastServerId: serverId,
          };
        });
      },

      getCachedFeed(serverId, key) {
        return get().feedCache[`${serverId}:${key}`] || null;
      },

      clearFeedCache(serverId) {
        if (serverId) {
          set(state => {
            const next = Object.fromEntries(
              Object.entries(state.feedCache).filter(([k]) => !k.startsWith(`${serverId}:`)),
            );
            return {feedCache: next};
          });
        } else {
          set({feedCache: {}});
        }
      },
    }),
    {
      name: 'offline-feed',
      storage: createJSONStorage(() => createMmkvStorage('offline-feed')),
      partialize: state => ({
        feedCache: state.feedCache,
        lastServerId: state.lastServerId,
      }),
    },
  ),
);
