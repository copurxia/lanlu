import { createMMKV } from 'react-native-mmkv';

import { updateArchiveProgress } from '../api/lanlu';
import { useOfflineProgressQueue } from './offlineProgressQueue';

jest.mock('../api/lanlu', () => ({
  updateArchiveProgress: jest.fn(),
}));

const mockedUpdateProgress = updateArchiveProgress as jest.MockedFunction<
  typeof updateArchiveProgress
>;

const mmkv = createMMKV({ id: 'lanlu.client.storage.v1' });

const START = 1_700_000_000_000;
let clock = START;

function tick() {
  clock += 1000;
  jest.setSystemTime(clock);
}

describe('offline progress queue', () => {
  beforeEach(() => {
    clock = START;
    jest.useFakeTimers();
    jest.setSystemTime(clock);
    mockedUpdateProgress.mockReset();
    mockedUpdateProgress.mockResolvedValue(undefined);
    useOfflineProgressQueue.setState({ queue: {} });
  });

  afterEach(() => {
    jest.useRealTimers();
  });

  it('enqueues progress with a timestamp and overwrites the same archive', () => {
    useOfflineProgressQueue.getState().enqueueProgress('s1', 'a1', 3);
    expect(useOfflineProgressQueue.getState().getQueueForServer('s1')).toEqual([
      { archiveId: 'a1', page: 3, queuedAt: START },
    ]);

    tick();
    useOfflineProgressQueue.getState().enqueueProgress('s1', 'a1', 9);

    expect(useOfflineProgressQueue.getState().getQueueForServer('s1')).toEqual([
      { archiveId: 'a1', page: 9, queuedAt: clock },
    ]);
  });

  it('returns entries for one server sorted by queue time', () => {
    useOfflineProgressQueue.getState().enqueueProgress('s1', 'second', 2);
    tick();
    useOfflineProgressQueue.getState().enqueueProgress('s1', 'third', 3);
    tick();
    useOfflineProgressQueue.getState().enqueueProgress('s1', 'first', 1);

    expect(
      useOfflineProgressQueue
        .getState()
        .getQueueForServer('s1')
        .map(entry => entry.archiveId),
    ).toEqual(['second', 'third', 'first']);
  });

  it('keeps accounts isolated', () => {
    useOfflineProgressQueue.getState().enqueueProgress('s1', 'a1', 1);
    useOfflineProgressQueue.getState().enqueueProgress('s2', 'a2', 2);

    expect(useOfflineProgressQueue.getState().getQueueForServer('s1')).toHaveLength(1);
    expect(useOfflineProgressQueue.getState().getQueueForServer('s2')).toHaveLength(1);
    expect(useOfflineProgressQueue.getState().getQueueForServer('unknown')).toEqual([]);

    useOfflineProgressQueue.getState().dequeueProgress('s1', 'a1');

    expect(useOfflineProgressQueue.getState().getQueueForServer('s1')).toEqual([]);
    expect(useOfflineProgressQueue.getState().getQueueForServer('s2')).toHaveLength(1);
  });

  it('flushes every queued page for the given server', async () => {
    useOfflineProgressQueue.getState().enqueueProgress('s1', 'a1', 4);
    tick();
    useOfflineProgressQueue.getState().enqueueProgress('s1', 'a2', 8);

    const synced = await useOfflineProgressQueue.getState().flushQueue('s1');

    expect(synced).toBe(2);
    expect(mockedUpdateProgress.mock.calls).toEqual([
      ['a1', 4],
      ['a2', 8],
    ]);
    expect(useOfflineProgressQueue.getState().getQueueForServer('s1')).toEqual([]);
  });

  it('returns zero without calling the API when the queue is empty', async () => {
    await expect(
      useOfflineProgressQueue.getState().flushQueue('s1'),
    ).resolves.toBe(0);
    expect(mockedUpdateProgress).not.toHaveBeenCalled();
  });

  it('keeps failed entries queued and reports only synced entries', async () => {
    useOfflineProgressQueue.getState().enqueueProgress('s1', 'ok', 1);
    tick();
    useOfflineProgressQueue.getState().enqueueProgress('s1', 'broken', 2);
    mockedUpdateProgress.mockImplementation(async archiveId => {
      if (archiveId === 'broken') {
        throw new Error('offline');
      }
    });

    const synced = await useOfflineProgressQueue.getState().flushQueue('s1');

    expect(synced).toBe(1);
    expect(useOfflineProgressQueue.getState().getQueueForServer('s1')).toEqual([
      { archiveId: 'broken', page: 2, queuedAt: clock },
    ]);
  });

  it('does not retry automatically; a later flush retries the survivor', async () => {
    useOfflineProgressQueue.getState().enqueueProgress('s1', 'a1', 1);
    mockedUpdateProgress.mockRejectedValueOnce(new Error('offline'));

    expect(await useOfflineProgressQueue.getState().flushQueue('s1')).toBe(0);
    expect(mockedUpdateProgress).toHaveBeenCalledTimes(1);

    jest.advanceTimersByTime(60_000);
    await Promise.resolve();
    expect(mockedUpdateProgress).toHaveBeenCalledTimes(1);
    expect(useOfflineProgressQueue.getState().getQueueForServer('s1')).toHaveLength(1);

    expect(await useOfflineProgressQueue.getState().flushQueue('s1')).toBe(1);
    expect(mockedUpdateProgress).toHaveBeenCalledTimes(2);
    expect(useOfflineProgressQueue.getState().getQueueForServer('s1')).toEqual([]);
  });

  it('flushes only the requested server', async () => {
    useOfflineProgressQueue.getState().enqueueProgress('s1', 'a1', 1);
    useOfflineProgressQueue.getState().enqueueProgress('s2', 'a2', 2);

    expect(await useOfflineProgressQueue.getState().flushQueue('s2')).toBe(1);
    expect(mockedUpdateProgress.mock.calls).toEqual([['a2', 2]]);
    expect(useOfflineProgressQueue.getState().getQueueForServer('s1')).toHaveLength(1);
  });

  it('persists the queue and restores it on rehydrate', async () => {
    useOfflineProgressQueue.getState().enqueueProgress('s1', 'a1', 5);

    const key = 'offline-progress:offline-progress';
    const raw = mmkv.getString(key);
    expect(JSON.parse(raw as string).state.queue['s1:a1']).toMatchObject({
      archiveId: 'a1',
      page: 5,
    });

    useOfflineProgressQueue.setState({ queue: {} });
    mmkv.set(key, raw as string);
    await useOfflineProgressQueue.persist.rehydrate();

    expect(useOfflineProgressQueue.getState().getQueueForServer('s1')).toEqual([
      { archiveId: 'a1', page: 5, queuedAt: START },
    ]);
  });

  it('persists only the queue', () => {
    const partialize = useOfflineProgressQueue.persist.getOptions().partialize as any;
    expect(partialize({ queue: {}, enqueueProgress: jest.fn() })).toEqual({ queue: {} });
  });
});
