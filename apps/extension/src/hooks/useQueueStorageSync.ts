/**
 * useQueueStorageSync Hook - 同步后台存储中的下载队列
 */

import { useEffect } from "react";
import { useDownloadQueueStore } from "~/store/download-queue";

const QUEUE_KEY = "lanlu_download_queue";

function safeJsonParse(raw: string): unknown {
  try {
    return JSON.parse(raw);
  } catch {
    return null;
  }
}

type PersistedQueueState = {
  state?: {
    entries?: unknown;
  };
};

function parseQueueEntries(raw: unknown) {
  const parsed = typeof raw === "string" ? safeJsonParse(raw) : raw;
  const container = parsed && typeof parsed === "object" ? (parsed as PersistedQueueState) : null;
  const entries = container?.state?.entries;
  return Array.isArray(entries) ? entries : null;
}

function isSameEntries(
  current: Array<{ id?: string; updatedAt?: number }>,
  next: Array<{ id?: string; updatedAt?: number }>
) {
  if (current.length !== next.length) return false;
  for (let i = 0; i < current.length; i += 1) {
    const a = current[i];
    const b = next[i];
    if (!a || !b) return false;
    if (a.id !== b.id || a.updatedAt !== b.updatedAt) return false;
  }
  return true;
}

/**
 * 监听 chrome.storage.local 队列变化并同步到 zustand
 */
export function useQueueStorageSync(): void {
  useEffect(() => {
    if (typeof chrome === "undefined" || !chrome.storage?.local) return;

    const onChanged = (changes: { [key: string]: chrome.storage.StorageChange }, areaName: string) => {
      if (areaName !== "local") return;
      const change = changes[QUEUE_KEY];
      if (!change) return;
      const nextEntries = parseQueueEntries(change.newValue);
      if (!nextEntries) return;
      const current = useDownloadQueueStore.getState().entries;
      if (isSameEntries(current, nextEntries)) return;
      useDownloadQueueStore.getState().setEntries(nextEntries);
    };

    chrome.storage.onChanged.addListener(onChanged);
    return () => {
      chrome.storage.onChanged.removeListener(onChanged);
    };
  }, []);
}
