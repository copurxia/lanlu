import {useSyncExternalStore} from 'react';

/**
 * Per-page reader state, kept outside React so a progress tick or a size
 * measurement on one page does not re-render the whole virtualized list.
 * Mirrors the page status flow each WebtoonPageHolder subscribes to in Mihon.
 *
 * Two independent notification channels:
 * - load slice (phase/progress/error): only the subscribing cell re-renders;
 * - size version: a monotone counter the screen subscribes to so scroll
 *   geometry (getItemLayout offsets) refreshes without touching cells.
 */
export type ReaderPagePhase = 'queued' | 'loading' | 'downloading' | 'ready' | 'error';

export type ReaderPageLoadState = {
  phase: ReaderPagePhase;
  progress: number;
  error?: string;
  /** Decoded pixel size; drives webtoon item heights and aspect ratios. */
  width?: number;
  height?: number;
};

const INITIAL: ReaderPageLoadState = {phase: 'queued', progress: 0};

const states = new Map<number, ReaderPageLoadState>();
const listeners = new Map<number, Set<() => void>>();
const sizeVersionListeners = new Set<() => void>();

let sizeVersion = 0;

function snapshot(pageNumber: number): ReaderPageLoadState {
  return states.get(pageNumber) || INITIAL;
}

function publish(pageNumber: number): void {
  listeners.get(pageNumber)?.forEach(listener => listener());
}

function publishSizeVersion(): void {
  sizeVersion += 1;
  sizeVersionListeners.forEach(listener => listener());
}

export function setReaderPageLoadState(
  pageNumber: number,
  patch: {phase?: ReaderPagePhase; progress?: number; error?: string | undefined},
): void {
  const previous = snapshot(pageNumber);
  let changed = false;
  const next: ReaderPageLoadState = {...previous};
  for (const key of Object.keys(patch) as Array<keyof typeof patch>) {
    const value = patch[key];
    // An explicit undefined clears the optional key (e.g. clearing an error).
    if (value === undefined) {
      if (key in next && next[key] !== undefined) {
        delete next[key as 'error'];
        changed = true;
      }
      continue;
    }
    if (previous[key] !== value) {
      Object.assign(next, {[key]: value});
      changed = true;
    }
  }
  if (!changed) return;
  states.set(pageNumber, next);
  publish(pageNumber);
}

/** Stores the decoded pixel size of a page and bumps the geometry version. */
export function setReaderPageSize(
  pageNumber: number,
  width: number,
  height: number,
): void {
  if (!Number.isFinite(width) || !Number.isFinite(height) || width <= 0 || height <= 0) {
    return;
  }
  const previous = snapshot(pageNumber);
  if (previous.width === width && previous.height === height) return;
  states.set(pageNumber, {...previous, width, height});
  publishSizeVersion();
  publish(pageNumber);
}

/** Clears one page back to the pristine queued state (retry / source switch). */
export function resetReaderPageLoadState(pageNumber: number): void {
  if (!states.has(pageNumber)) return;
  states.set(pageNumber, {...INITIAL});
  publishSizeVersion();
  publish(pageNumber);
}

export function resetReaderPageLoadStates(): void {
  const affected = Array.from(states.keys());
  states.clear();
  affected.forEach(publish);
  publishSizeVersion();
}

/** Clears only decoded sizes, keeping load phases (viewport width change). */
export function resetReaderPageSizes(): void {
  let changed = false;
  for (const [pageNumber, state] of states) {
    if (state.width !== undefined || state.height !== undefined) {
      states.set(pageNumber, {phase: state.phase, progress: state.progress, error: state.error});
      changed = true;
    }
  }
  if (changed) {
    publishSizeVersion();
    Array.from(states.keys()).forEach(publish);
  }
}

export function getReaderPageLoadState(pageNumber: number): ReaderPageLoadState {
  return snapshot(pageNumber);
}

export function getReaderPageSize(pageNumber: number): {width?: number; height?: number} {
  const state = snapshot(pageNumber);
  return {width: state.width, height: state.height};
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

/**
 * Subscribes the caller to geometry changes (any page size write). The reader
 * screen uses this to refresh getItemLayout offsets; memoized cells do not,
 * which keeps a size measurement from re-rendering the whole list.
 */
export function useReaderPageSizeVersion(): number {
  return useSyncExternalStore(
    onStoreChange => {
      sizeVersionListeners.add(onStoreChange);
      return () => {
        sizeVersionListeners.delete(onStoreChange);
      };
    },
    () => sizeVersion,
    () => sizeVersion,
  );
}

/**
 * Tracks which page is active for media playback gating. Cells subscribe
 * individually; a page change only notifies the pages whose active status
 * actually flipped, not the whole virtualized list.
 */
let activeReaderPage = 0;
const activeListeners = new Map<number, Set<() => void>>();

function publishActiveRange(center: number, radius: number): void {
  for (let page = center - radius; page <= center + radius; page += 1) {
    activeListeners.get(page)?.forEach(listener => listener());
  }
}

export function setActiveReaderPage(pageNumber: number): void {
  const previous = activeReaderPage;
  if (previous === pageNumber) return;
  activeReaderPage = pageNumber;
  publishActiveRange(previous, 2);
  publishActiveRange(pageNumber, 2);
}

export function isReaderPageActive(pageNumber: number, radius = 1): boolean {
  return Math.abs(pageNumber - activeReaderPage) <= radius;
}

export function useIsReaderPageActive(pageNumber: number, radius = 1): boolean {
  return useSyncExternalStore(
    onStoreChange => {
      let set = activeListeners.get(pageNumber);
      if (!set) {
        set = new Set();
        activeListeners.set(pageNumber, set);
      }
      set.add(onStoreChange);
      return () => {
        set?.delete(onStoreChange);
        if (set && set.size === 0) activeListeners.delete(pageNumber);
      };
    },
    () => isReaderPageActive(pageNumber, radius),
    () => isReaderPageActive(pageNumber, radius),
  );
}
