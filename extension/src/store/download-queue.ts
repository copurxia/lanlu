"use client";

import { create } from "zustand";
import { createJSONStorage, persist } from "zustand/middleware";
import { createChromeStorage } from "@/lib/chrome-zustand-storage";

function createId(): string {
  try {
    const c = globalThis.crypto as Crypto | undefined;
    if (c && typeof c.randomUUID === "function") return c.randomUUID();
  } catch {
    // ignore
  }
  return `${Date.now().toString(36)}_${Math.random().toString(36).slice(2, 10)}`;
}

export type DownloadEntry = {
  id: string;
  url: string;
  title?: string;
  tabId?: number;
  createdAt: number;
  updatedAt: number;

  status: "exists" | "queued" | "running" | "completed" | "failed" | "stopped";
  error?: string;

  downloadTaskId?: number;
  downloadProgress?: number;
  downloadMessage?: string;

  scanTaskId?: number;
  scanProgress?: number;
  scanMessage?: string;

  archiveId?: string;
};

type QueueState = {
  entries: DownloadEntry[];
  add: (entry: Omit<DownloadEntry, "id" | "createdAt" | "updatedAt"> & { id?: string }) => void;
  update: (id: string, patch: Partial<DownloadEntry>) => void;
  setEntries: (entries: DownloadEntry[]) => void;
  remove: (id: string) => void;
  clearCompleted: () => void;
  clearAll: () => void;
};

export const useDownloadQueueStore = create<QueueState>()(
  persist(
    (set, get) => ({
      entries: [],
      add: (entry) => {
        const now = Date.now();
        const id = entry.id ?? createId();
        const next: DownloadEntry = {
          id,
          createdAt: now,
          updatedAt: now,
          url: entry.url,
          title: entry.title,
          tabId: entry.tabId,
          status: entry.status,
          error: entry.error,
          downloadTaskId: entry.downloadTaskId,
          downloadProgress: entry.downloadProgress,
          downloadMessage: entry.downloadMessage,
          scanTaskId: entry.scanTaskId,
          scanProgress: entry.scanProgress,
          scanMessage: entry.scanMessage,
          archiveId: entry.archiveId,
        };
        set({ entries: [next, ...get().entries].slice(0, 100) });
      },
      update: (id, patch) => {
        const now = Date.now();
        set({
          entries: get().entries.map((e) => (e.id === id ? { ...e, ...patch, updatedAt: now } : e)),
        });
      },
      setEntries: (entries) => set({ entries }),
      remove: (id) => set({ entries: get().entries.filter((e) => e.id !== id) }),
      clearCompleted: () =>
        set({
          entries: get().entries.filter(
            (e) => !(e.status === "completed" || e.status === "failed" || e.status === "stopped" || e.status === "exists")
          ),
        }),
      clearAll: () => set({ entries: [] }),
    }),
    {
      name: "lanlu_download_queue",
      storage: createJSONStorage(() => createChromeStorage("local")),
      version: 1,
    }
  )
);
