import {create} from 'zustand';
import {persist, createJSONStorage} from 'zustand/middleware';
import {createMmkvStorage} from '../storage/zustandMmkvStorage';
import {updateArchiveProgress} from '../api/lanlu';

type QueuedProgress = {
  archiveId: string;
  page: number;
  queuedAt: number;
};

type OfflineProgressState = {
  queue: Record<string, QueuedProgress>;

  enqueueProgress: (serverId: string, archiveId: string, page: number) => void;
  dequeueProgress: (serverId: string, archiveId: string) => void;
  flushQueue: (serverId: string) => Promise<number>;

  getQueueForServer: (serverId: string) => QueuedProgress[];
};

export const useOfflineProgressQueue = create<OfflineProgressState>()(
  persist(
    (set, get) => ({
      queue: {},

      enqueueProgress(serverId, archiveId, page) {
        const key = `${serverId}:${archiveId}`;
        set(state => ({
          queue: {
            ...state.queue,
            [key]: {archiveId, page, queuedAt: Date.now()},
          },
        }));
      },

      dequeueProgress(serverId, archiveId) {
        const key = `${serverId}:${archiveId}`;
        set(state => {
          const next = {...state.queue};
          delete next[key];
          return {queue: next};
        });
      },

      async flushQueue(serverId) {
        const entries = get().getQueueForServer(serverId);
        if (!entries.length) return 0;

        let synced = 0;
        const results = await Promise.allSettled(
          entries.map(entry =>
            updateArchiveProgress(entry.archiveId, entry.page).then(() => entry),
          ),
        );

        for (const result of results) {
          if (result.status === 'fulfilled') {
            get().dequeueProgress(serverId, result.value.archiveId);
            synced += 1;
          }
        }
        return synced;
      },

      getQueueForServer(serverId) {
        const prefix = `${serverId}:`;
        return Object.entries(get().queue)
          .filter(([key]) => key.startsWith(prefix))
          .map(([, entry]) => entry)
          .sort((a, b) => a.queuedAt - b.queuedAt);
      },
    }),
    {
      name: 'offline-progress',
      storage: createJSONStorage(() => createMmkvStorage('offline-progress')),
      partialize: state => ({queue: state.queue}),
    },
  ),
);
