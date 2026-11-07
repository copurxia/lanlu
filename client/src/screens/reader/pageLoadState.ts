import {useSyncExternalStore} from 'react';

/**
 * Per-page load state, kept outside React so a progress tick on one page does
 * not re-render the whole virtualized list. Mirrors the page status flow each
 * WebtoonPageHolder subscribes to in Mihon.
 */
export type ReaderPagePhase = 'queued' | 'loading' | 'downloading' | 'ready' | 'error';

export type ReaderPageLoadState = {
  phase: ReaderPagePhase;
  progress: number;
  error?: string;
};

const INITIAL: ReaderPageLoadState = {phase: 'queued', progress: 0};

const states = new Map<number, ReaderPageLoadState>();
const listeners = new Map<number, Set<() => void>>();

function snapshot(pageNumber: number): ReaderPageLoadState {
  return states.get(pageNumber) || INITIAL;
}

function publish(pageNumber: number): void {
  listeners.get(pageNumber)?.forEach(listener => listener());
}

export function setReaderPageLoadState(
  pageNumber: number,
  patch: Partial<ReaderPageLoadState>,
): void {
  const previous = snapshot(pageNumber);
  let changed = false;
  const next: ReaderPageLoadState = {...previous};
  for (const key of Object.keys(patch) as (keyof ReaderPageLoadState)[]) {
    const value = patch[key];
    if (value !== undefined && previous[key] !== value) {
      Object.assign(next, {[key]: value});
      changed = true;
    }
  }
  if (!changed) return;
  states.set(pageNumber, next);
  publish(pageNumber);
}

export function resetReaderPageLoadStates(): void {
  const affected = Array.from(states.keys());
  states.clear();
  affected.forEach(publish);
}

export function getReaderPageLoadState(pageNumber: number): ReaderPageLoadState {
  return snapshot(pageNumber);
}

export function useReaderPageLoadState(pageNumber: number): ReaderPageLoadState {
  return useSyncExternalStore(
    onStoreChange => {
      let set = listeners.get(pageNumber);
      if (!set) {
        set = new Set();
        listeners.set(pageNumber, set);
      }
      set.add(onStoreChange);
      return () => {
        set?.delete(onStoreChange);
        if (set && set.size === 0) listeners.delete(pageNumber);
      };
    },
    () => snapshot(pageNumber),
    () => INITIAL,
  );
}
