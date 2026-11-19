import { createMMKV } from 'react-native-mmkv';

import { useOfflineArchiveStore } from './offlineArchiveStore';
import { useOfflineFeedStore } from './offlineFeedStore';
import { useOfflineGeneralStore } from './offlineGeneralStore';
import { useOfflineSettingsStore } from './offlineSettingsStore';
import { useOfflineTankoubonStore } from './offlineTankoubonStore';
import { useUploadStore } from './uploadStore';

const item = (id: number) => ({ id, title: `item-${id}` } as any);

const mmkv = createMMKV({ id: 'lanlu.client.storage.v1' });

const START = 1_700_000_000_000;
let clock = START;

function tick() {
  clock += 1000;
  jest.setSystemTime(clock);
}

function resetStores() {
  useOfflineGeneralStore.setState({ favorites: {}, lastServerId: null });
  useOfflineSettingsStore.setState({ dashboard: {}, lastServerId: null });
  useOfflineFeedStore.setState({ feedCache: {}, lastServerId: null });
  useOfflineTankoubonStore.setState({ tankoubons: {}, lastServerId: null });
  useOfflineArchiveStore.setState({ archives: {}, lastServerId: null });
  useUploadStore.setState({ uploadFiles: [], downloadTasks: [] });
}

describe('offline general cache', () => {
  beforeEach(() => {
    clock = START;
    jest.useFakeTimers();
    jest.setSystemTime(clock);
    resetStores();
  });

  afterEach(() => {
    jest.useRealTimers();
  });

  it('merges partial updates without dropping the untouched list', () => {
    const store = useOfflineGeneralStore.getState();
    store.cacheFavorites('s1', { favorites: [item(1)], history: [item(2)] });
    tick();
    useOfflineGeneralStore
      .getState()
      .cacheFavorites('s1', { history: [item(3)] });

    const cached = useOfflineGeneralStore.getState().getCachedFavorites('s1');
    expect(cached?.favorites.map((entry: any) => entry.id)).toEqual([1]);
    expect(cached?.history.map((entry: any) => entry.id)).toEqual([3]);
    expect(cached?.timestamp).toBe(clock);
    expect(useOfflineGeneralStore.getState().lastServerId).toBe('s1');
  });

  it('isolates accounts and clears only the selected server', () => {
    const store = useOfflineGeneralStore.getState();
    store.cacheFavorites('s1', { favorites: [item(1)] });
    store.cacheFavorites('s2', { favorites: [item(2)] });

    useOfflineGeneralStore.getState().clearGeneralCache('s1');

    expect(useOfflineGeneralStore.getState().getCachedFavorites('s1')).toBeNull();
    expect(
      useOfflineGeneralStore.getState().getCachedFavorites('s2')?.favorites,
    ).toHaveLength(1);
  });

  it('clears every server when no server id is passed', () => {
    const store = useOfflineGeneralStore.getState();
    store.cacheFavorites('s1', { favorites: [item(1)] });
    store.cacheFavorites('s2', { favorites: [item(2)] });

    useOfflineGeneralStore.getState().clearGeneralCache();

    expect(useOfflineGeneralStore.getState().getCachedFavorites('s1')).toBeNull();
    expect(useOfflineGeneralStore.getState().getCachedFavorites('s2')).toBeNull();
  });

  it('persists and rehydrates the cached lists', async () => {
    useOfflineGeneralStore
      .getState()
      .cacheFavorites('s1', { favorites: [item(7)] });

    const key = 'offline-general:offline-general';
    const raw = mmkv.getString(key);
    expect(raw).toBeTruthy();
    expect(JSON.parse(raw as string).state.favorites.s1.favorites).toHaveLength(1);

    useOfflineGeneralStore.setState({ favorites: {}, lastServerId: null });
    mmkv.set(key, raw as string);
    await useOfflineGeneralStore.persist.rehydrate();

    const cached = useOfflineGeneralStore.getState().getCachedFavorites('s1');
    expect(cached?.favorites.map((entry: any) => entry.id)).toEqual([7]);
    expect(useOfflineGeneralStore.getState().lastServerId).toBe('s1');
  });
});

describe('offline settings cache', () => {
  beforeEach(() => {
    clock = START;
    jest.useFakeTimers();
    jest.setSystemTime(clock);
    resetStores();
  });

  afterEach(() => {
    jest.useRealTimers();
  });

  it('replaces the dashboard snapshot for an account', () => {
    const first = { stats: { archives: 1 }, trend: [{ date: 'a' }] } as any;
    const second = { stats: { archives: 2 }, trend: [] } as any;
    useOfflineSettingsStore.getState().cacheDashboard('s1', first);
    useOfflineSettingsStore.getState().cacheDashboard('s1', second);

    expect(useOfflineSettingsStore.getState().getCachedDashboard('s1')).toBe(second);
    expect(useOfflineSettingsStore.getState().lastServerId).toBe('s1');
  });

  it('keeps dashboards apart and clears them per server or entirely', () => {
    useOfflineSettingsStore
      .getState()
      .cacheDashboard('s1', { stats: { archives: 1 }, trend: [] } as any);
    useOfflineSettingsStore
      .getState()
      .cacheDashboard('s2', { stats: { archives: 2 }, trend: [] } as any);

    useOfflineSettingsStore.getState().clearSettingsCache('s1');
    expect(useOfflineSettingsStore.getState().getCachedDashboard('s1')).toBeNull();
    expect(
      useOfflineSettingsStore.getState().getCachedDashboard('s2')?.stats,
    ).toEqual({ archives: 2 });

    useOfflineSettingsStore.getState().clearSettingsCache();
    expect(useOfflineSettingsStore.getState().getCachedDashboard('s2')).toBeNull();
  });
});

describe('offline feed cache', () => {
  beforeEach(() => {
    clock = START;
    jest.useFakeTimers();
    jest.setSystemTime(clock);
    resetStores();
  });

  afterEach(() => {
    jest.useRealTimers();
  });

  it('applies defaults for optional feed fields', () => {
    useOfflineFeedStore.getState().cacheFeed('s1', 'home', { items: [item(1)] });

    const cached = useOfflineFeedStore.getState().getCachedFeed('s1', 'home');
    expect(cached).toMatchObject({ total: 1, page: 1, categories: [], randomItems: [] });
    expect(cached?.categoryRows).toEqual({});
    expect(cached?.timestamp).toBe(clock);
  });

  it('keeps explicit total, page and filters', () => {
    useOfflineFeedStore.getState().cacheFeed('s1', 'search', {
      items: [],
      total: 120,
      page: 3,
      smartFilters: [{ id: 1 }],
    });

    const cached = useOfflineFeedStore.getState().getCachedFeed('s1', 'search');
    expect(cached?.total).toBe(120);
    expect(cached?.page).toBe(3);
    expect(cached?.smartFilters).toEqual([{ id: 1 }]);
  });

  it('scopes the cache key by server and feed key', () => {
    useOfflineFeedStore.getState().cacheFeed('s1', 'home', { items: [item(1)] });
    useOfflineFeedStore.getState().cacheFeed('s2', 'home', { items: [item(2)] });
    useOfflineFeedStore.getState().cacheFeed('s1', 'ranking', { items: [item(3)] });

    expect(
      (useOfflineFeedStore.getState().getCachedFeed('s1', 'home')?.items[0] as any)
        ?.id,
    ).toBe(1);
    expect(
      (useOfflineFeedStore.getState().getCachedFeed('s2', 'home')?.items[0] as any)
        ?.id,
    ).toBe(2);
    expect(
      (useOfflineFeedStore.getState().getCachedFeed('s1', 'ranking')?.items[0] as any)
        ?.id,
    ).toBe(3);
  });

  it('evicts the oldest entry past the 24 entry bound', () => {
    for (let index = 0; index < 25; index += 1) {
      tick();
      useOfflineFeedStore
        .getState()
        .cacheFeed('s1', `feed-${index}`, { items: [item(index)] });
    }

    const state = useOfflineFeedStore.getState();
    expect(Object.keys(state.feedCache)).toHaveLength(24);
    expect(state.getCachedFeed('s1', 'feed-0')).toBeNull();
    expect(state.getCachedFeed('s1', 'feed-24')).not.toBeNull();
  });

  it('refreshing an entry moves it out of the eviction window', () => {
    for (let index = 0; index < 24; index += 1) {
      tick();
      useOfflineFeedStore
        .getState()
        .cacheFeed('s1', `feed-${index}`, { items: [item(index)] });
    }
    tick();
    useOfflineFeedStore.getState().cacheFeed('s1', 'feed-0', { items: [item(0)] });
    tick();
    useOfflineFeedStore.getState().cacheFeed('s1', 'feed-new', { items: [item(99)] });

    const state = useOfflineFeedStore.getState();
    expect(Object.keys(state.feedCache)).toHaveLength(24);
    expect(state.getCachedFeed('s1', 'feed-0')).not.toBeNull();
    expect(state.getCachedFeed('s1', 'feed-1')).toBeNull();
  });

  it('clears only entries belonging to the given server', () => {
    useOfflineFeedStore.getState().cacheFeed('s1', 'home', { items: [item(1)] });
    useOfflineFeedStore.getState().cacheFeed('s2', 'home', { items: [item(2)] });

    useOfflineFeedStore.getState().clearFeedCache('s1');

    expect(useOfflineFeedStore.getState().getCachedFeed('s1', 'home')).toBeNull();
    expect(useOfflineFeedStore.getState().getCachedFeed('s2', 'home')).not.toBeNull();
  });
});

describe('offline archive cache', () => {
  beforeEach(() => {
    clock = START;
    jest.useFakeTimers();
    jest.setSystemTime(clock);
    resetStores();
  });

  afterEach(() => {
    jest.useRealTimers();
  });

  it('merges missing sections into the existing archive entry', () => {
    useOfflineArchiveStore.getState().cacheArchive('s1', 'a1', {
      metadata: { title: 'Archive' } as any,
      pages: [{ page: 1 } as any],
    });
    tick();
    useOfflineArchiveStore
      .getState()
      .cacheArchive('s1', 'a1', { related: [{ id: 9 } as any] });

    const cached = useOfflineArchiveStore.getState().getCachedArchive('s1', 'a1');
    expect(cached?.metadata).toEqual({ title: 'Archive' });
    expect(cached?.pages).toHaveLength(1);
    expect(cached?.related).toEqual([{ id: 9 }]);
    expect(cached?.timestamp).toBe(clock);
  });

  it('evicts the oldest archive past the 40 entry bound', () => {
    for (let index = 0; index < 41; index += 1) {
      tick();
      useOfflineArchiveStore
        .getState()
        .cacheArchive('s1', `a-${index}`, { pages: [{ page: index } as any] });
    }

    const state = useOfflineArchiveStore.getState();
    expect(Object.keys(state.archives)).toHaveLength(40);
    expect(state.getCachedArchive('s1', 'a-0')).toBeNull();
    expect(state.getCachedArchive('s1', 'a-40')).not.toBeNull();
  });

  it('clears per server without touching other accounts', () => {
    useOfflineArchiveStore
      .getState()
      .cacheArchive('s1', 'a1', { pages: [{ page: 1 } as any] });
    useOfflineArchiveStore
      .getState()
      .cacheArchive('s2', 'a1', { pages: [{ page: 2 } as any] });

    useOfflineArchiveStore.getState().clearArchiveCache('s1');

    expect(useOfflineArchiveStore.getState().getCachedArchive('s1', 'a1')).toBeNull();
    expect(useOfflineArchiveStore.getState().getCachedArchive('s2', 'a1')).not.toBeNull();
  });
});

describe('offline tankoubon cache', () => {
  beforeEach(() => {
    clock = START;
    jest.useFakeTimers();
    jest.setSystemTime(clock);
    resetStores();
  });

  afterEach(() => {
    jest.useRealTimers();
  });

  it('merges sections and isolates accounts by composite key', () => {
    useOfflineTankoubonStore.getState().cacheTankoubon('s1', 't1', {
      metadata: { title: 'Tankoubon' } as any,
      archives: [{ id: 1 } as any],
    });
    tick();
    useOfflineTankoubonStore
      .getState()
      .cacheTankoubon('s1', 't1', { related: [{ id: 2 } as any] });
    useOfflineTankoubonStore
      .getState()
      .cacheTankoubon('s2', 't1', { related: [{ id: 3 } as any] });

    const cached = useOfflineTankoubonStore.getState().getCachedTankoubon('s1', 't1');
    expect(cached?.metadata).toEqual({ title: 'Tankoubon' });
    expect(cached?.archives).toHaveLength(1);
    expect(cached?.related).toEqual([{ id: 2 }]);
    expect(
      useOfflineTankoubonStore.getState().getCachedTankoubon('s2', 't1')?.related,
    ).toEqual([{ id: 3 }]);
  });

  it('evicts the oldest tankoubon past the 40 entry bound', () => {
    for (let index = 0; index < 41; index += 1) {
      tick();
      useOfflineTankoubonStore
        .getState()
        .cacheTankoubon('s1', `t-${index}`, { metadata: { title: `t-${index}` } as any });
    }

    const state = useOfflineTankoubonStore.getState();
    expect(Object.keys(state.tankoubons)).toHaveLength(40);
    expect(state.getCachedTankoubon('s1', 't-0')).toBeNull();
    expect(state.getCachedTankoubon('s1', 't-40')).not.toBeNull();
  });
});

describe('upload store persistence', () => {
  beforeEach(resetStores);

  it('persists download tasks but not in-flight upload files', () => {
    const partialize = useUploadStore.persist.getOptions().partialize as any;
    const partial = partialize({
      uploadFiles: [{ id: 'u1' }],
      downloadTasks: [{ id: 'd1' }],
    });

    expect(partial).toEqual({ uploadFiles: [], downloadTasks: [{ id: 'd1' }] });
  });
});
