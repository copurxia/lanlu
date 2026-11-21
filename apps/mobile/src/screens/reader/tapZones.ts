import type { TapZoneMode } from '../../storage/preferences';

export type TapAction = 'menu' | 'forward' | 'backward';

export type TapZoneOptions = {
  /** Vertical paging / webtoon (top and bottom edges move). */
  vertical: boolean;
  /** Right-to-left paging; only the default layout mirrors left/right. */
  reversed?: boolean;
};

function clampUnit(value: number): number {
  return Math.min(0.999, Math.max(0, value));
}

/**
 * Maps a tap position to a reader action for the configured navigation
 * layout. Coordinates are in screen pixels.
 */
export function resolveTapAction(
  mode: TapZoneMode,
  x: number,
  y: number,
  width: number,
  height: number,
  options: TapZoneOptions,
): TapAction {
  if (width <= 0 || height <= 0) return 'menu';
  const nx = clampUnit(x / width);
  const ny = clampUnit(y / height);

  switch (mode) {
    case 'disabled':
      return 'menu';
    case 'l-shape': {
      if (ny < 1 / 3) return 'backward';
      if (ny > 2 / 3) return 'forward';
      if (nx < 1 / 3) return 'backward';
      if (nx > 2 / 3) return 'forward';
      return 'menu';
    }
    case 'kindlish': {
      if (ny < 1 / 3) return 'menu';
      if (nx < 1 / 3) return 'backward';
      return 'forward';
    }
    case 'edge': {
      if (nx < 1 / 3 || nx > 2 / 3) return 'forward';
      if (ny > 2 / 3) return 'backward';
      return 'menu';
    }
    default: {
      if (options.vertical) {
        if (ny < 0.28) return 'backward';
        if (ny > 0.72) return 'forward';
        return 'menu';
      }
      const leftAction: TapAction = options.reversed ? 'forward' : 'backward';
      const rightAction: TapAction = options.reversed ? 'backward' : 'forward';
      if (nx < 0.32) return leftAction;
      if (nx > 0.68) return rightAction;
      return 'menu';
    }
  }
}
