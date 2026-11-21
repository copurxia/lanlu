import React from 'react';
import TestRenderer, {act} from 'react-test-renderer';

import {
  getReaderPageLoadState,
  getReaderPageSize,
  resetReaderPageLoadStates,
  resetReaderPageSizes,
  setActiveReaderPage,
  setReaderPageLoadState,
  setReaderPageSize,
  useIsReaderPageActive,
  useReaderPageLoadState,
  useReaderPageSizeVersion,
  type ReaderPageLoadState,
} from './pageLoadState';

describe('reader page load state', () => {
  beforeEach(() => resetReaderPageLoadStates());

  it('starts every page in the queued phase', () => {
    expect(getReaderPageLoadState(1)).toEqual({phase: 'queued', progress: 0});
    expect(getReaderPageLoadState(999)).toEqual({phase: 'queued', progress: 0});
  });

  it('advances through the page load lifecycle', () => {
    setReaderPageLoadState(3, {phase: 'loading', progress: 0});
    expect(getReaderPageLoadState(3).phase).toBe('loading');

    setReaderPageLoadState(3, {phase: 'downloading', progress: 42});
    expect(getReaderPageLoadState(3)).toEqual({phase: 'downloading', progress: 42});

    setReaderPageLoadState(3, {phase: 'ready', progress: 100});
    expect(getReaderPageLoadState(3).phase).toBe('ready');
  });

  it('keeps pages isolated from one another', () => {
    setReaderPageLoadState(1, {phase: 'ready', progress: 100});
    setReaderPageLoadState(2, {phase: 'error', error: 'HTTP 500'});
    expect(getReaderPageLoadState(1).phase).toBe('ready');
    expect(getReaderPageLoadState(2)).toEqual({phase: 'error', progress: 0, error: 'HTTP 500'});
    expect(getReaderPageLoadState(3).phase).toBe('queued');
  });

  it('notifies only subscribers of the changed page', () => {
    const seen: Record<number, ReaderPageLoadState[]> = {5: [], 6: []};
    const Probe = ({page}: {page: number}) => {
      seen[page].push(useReaderPageLoadState(page));
      return null;
    };
    let renderer: TestRenderer.ReactTestRenderer;
    act(() => {
      renderer = TestRenderer.create(
        <>
          <Probe page={5} />
          <Probe page={6} />
        </>,
      );
    });

    act(() => setReaderPageLoadState(5, {phase: 'downloading', progress: 10}));
    expect(seen[5].at(-1)?.progress).toBe(10);
    expect(seen[6]).toHaveLength(1);

    // A no-op patch must not create a new snapshot or trigger a render.
    const snapshot = getReaderPageLoadState(5);
    act(() => setReaderPageLoadState(5, {phase: 'downloading', progress: 10}));
    expect(getReaderPageLoadState(5)).toBe(snapshot);
    expect(seen[5]).toHaveLength(2);

    act(() => renderer.unmount());
  });

  it('clears all accumulated state on archive switch', () => {
    setReaderPageLoadState(1, {phase: 'ready', progress: 100});
    setReaderPageLoadState(2, {phase: 'error', error: 'boom'});
    resetReaderPageLoadStates();
    expect(getReaderPageLoadState(1)).toEqual({phase: 'queued', progress: 0});
    expect(getReaderPageLoadState(2)).toEqual({phase: 'queued', progress: 0});
  });

  it('stores decoded sizes and bumps the size version', () => {
    let versionSeen = -1;
    const Probe = () => {
      versionSeen = useReaderPageSizeVersion();
      return null;
    };
    let renderer: TestRenderer.ReactTestRenderer;
    act(() => {
      renderer = TestRenderer.create(<Probe />);
    });
    const initialVersion = versionSeen;

    act(() => setReaderPageSize(7, 800, 1200));
    expect(getReaderPageSize(7)).toEqual({width: 800, height: 1200});
    expect(versionSeen).toBe(initialVersion + 1);

    // Same size again: no version bump, no re-render.
    act(() => setReaderPageSize(7, 800, 1200));
    expect(versionSeen).toBe(initialVersion + 1);

    // Invalid sizes are ignored.
    act(() => setReaderPageSize(8, 0, 1200));
    act(() => setReaderPageSize(8, 800, Number.NaN));
    expect(getReaderPageSize(8)).toEqual({});

    act(() => resetReaderPageSizes());
    expect(getReaderPageSize(7)).toEqual({});
    // Load phases survive a size-only reset.
    setReaderPageLoadState(9, {phase: 'ready', progress: 100});
    act(() => setReaderPageSize(9, 100, 200));
    act(() => resetReaderPageSizes());
    expect(getReaderPageLoadState(9).phase).toBe('ready');

    act(() => renderer.unmount());
  });

  it('flips active page notifications only for affected pages', () => {
    const Probe = ({page}: {page: number}) => {
      activeSeen[page] = useIsReaderPageActive(page, 1);
      return null;
    };
    const activeSeen: Record<number, boolean> = {};
    let renderer: TestRenderer.ReactTestRenderer;
    act(() => {
      renderer = TestRenderer.create(
        <>
          <Probe page={4} />
          <Probe page={7} />
        </>,
      );
    });
    // Active page starts at 0, so nothing in range yet.
    act(() => setActiveReaderPage(5));
    expect(activeSeen[4]).toBe(true);
    expect(activeSeen[7]).toBe(false);

    act(() => setActiveReaderPage(8));
    expect(activeSeen[4]).toBe(false);
    expect(activeSeen[7]).toBe(true);

    // Same page again: no notifications.
    const rendersBefore = Object.values(activeSeen).length;
    act(() => setActiveReaderPage(8));
    expect(Object.values(activeSeen).length).toBe(rendersBefore);

    act(() => renderer.unmount());
  });
});
