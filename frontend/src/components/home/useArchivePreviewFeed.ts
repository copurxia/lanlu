'use client';

import { useEffect, useRef, useState } from 'react';

type PreviewStatus = 'idle' | 'loading' | 'ready' | 'error';

type UseArchivePreviewFeedOptions<TItem> = {
  archiveId?: string;
  eager?: boolean;
  enabled?: boolean;
  loaderKey: string;
  loadItems: (archiveId: string) => Promise<TItem[]>;
  rootMargin?: string;
};

const MAX_CONCURRENT_PREVIEW_REQUESTS = 4;
const previewCache = new Map<string, unknown[]>();
const previewInflight = new Map<string, Promise<unknown[]>>();
const previewQueue: Array<() => void> = [];
let activePreviewRequests = 0;

function buildPreviewCacheKey(loaderKey: string, archiveId: string): string {
  return `${loaderKey}:${archiveId}`;
}

function dequeuePreviewRequest(): void {
  while (activePreviewRequests < MAX_CONCURRENT_PREVIEW_REQUESTS && previewQueue.length > 0) {
    const nextTask = previewQueue.shift();
    nextTask?.();
  }
}

function enqueuePreviewRequest<TItem>(cacheKey: string, loadItems: () => Promise<TItem[]>): Promise<TItem[]> {
  const cachedPromise = previewInflight.get(cacheKey) as Promise<TItem[]> | undefined;
  if (cachedPromise) return cachedPromise;

  const request = new Promise<TItem[]>((resolve, reject) => {
    const run = () => {
      activePreviewRequests += 1;
      loadItems()
        .then((items) => {
          previewCache.set(cacheKey, items);
          resolve(items);
        })
        .catch(reject)
        .finally(() => {
          activePreviewRequests = Math.max(0, activePreviewRequests - 1);
          previewInflight.delete(cacheKey);
          dequeuePreviewRequest();
        });
    };

    if (activePreviewRequests < MAX_CONCURRENT_PREVIEW_REQUESTS) {
      run();
      return;
    }

    previewQueue.push(run);
  });

  previewInflight.set(cacheKey, request as Promise<unknown[]>);
  return request;
}

export function useArchivePreviewFeed<TItem, TElement extends HTMLElement = HTMLDivElement>({
  archiveId,
  eager = false,
  enabled = true,
  loaderKey,
  loadItems,
  rootMargin = '320px 0px',
}: UseArchivePreviewFeedOptions<TItem>) {
  const targetRef = useRef<TElement | null>(null);
  const [shouldLoad, setShouldLoad] = useState(Boolean(eager));
  const [items, setItems] = useState<TItem[]>([]);
  const [status, setStatus] = useState<PreviewStatus>('idle');

  useEffect(() => {
    if (!enabled || !archiveId) {
      setItems([]);
      setStatus('idle');
      setShouldLoad(Boolean(eager));
      return;
    }

    const cacheKey = buildPreviewCacheKey(loaderKey, archiveId);
    const cachedItems = previewCache.get(cacheKey) as TItem[] | undefined;
    setItems(cachedItems ?? []);
    setStatus(cachedItems ? 'ready' : eager ? 'loading' : 'idle');
    setShouldLoad(Boolean(eager || cachedItems));
  }, [archiveId, eager, enabled, loaderKey]);

  useEffect(() => {
    if (!enabled || !archiveId || shouldLoad) return;
    const target = targetRef.current;
    if (!target) return;

    const observer = new IntersectionObserver(
      (entries) => {
        if (!entries.some((entry) => entry.isIntersecting)) return;
        setShouldLoad(true);
      },
      {
        rootMargin,
        threshold: 0.01,
      }
    );

    observer.observe(target);
    return () => observer.disconnect();
  }, [archiveId, enabled, rootMargin, shouldLoad]);

  useEffect(() => {
    if (!enabled || !archiveId || !shouldLoad) return;

    const cacheKey = buildPreviewCacheKey(loaderKey, archiveId);
    const cachedItems = previewCache.get(cacheKey) as TItem[] | undefined;
    if (cachedItems) {
      setItems(cachedItems);
      setStatus('ready');
      return;
    }

    let cancelled = false;
    setStatus('loading');

    void enqueuePreviewRequest(cacheKey, () => loadItems(archiveId))
      .then((nextItems) => {
        if (cancelled) return;
        setItems(nextItems);
        setStatus('ready');
      })
      .catch(() => {
        if (cancelled) return;
        setItems([]);
        setStatus('error');
      });

    return () => {
      cancelled = true;
    };
  }, [archiveId, enabled, loadItems, loaderKey, shouldLoad]);

  return {
    items,
    loading: status === 'loading',
    ready: status === 'ready',
    shouldLoad,
    targetRef,
  };
}
