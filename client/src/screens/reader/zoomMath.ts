export type ZoomTranslation = { x: number; y: number };

export function clampScale(scale: number, min = 1, max = 5): number {
  'worklet';
  if (!Number.isFinite(scale)) return min;
  return Math.min(max, Math.max(min, scale));
}

export function translationLimit(
  scale: number,
  width: number,
  height: number,
): ZoomTranslation {
  'worklet';
  return {
    x: Math.max(0, ((scale - 1) * width) / 2),
    y: Math.max(0, ((scale - 1) * height) / 2),
  };
}

export function clampTranslation(
  x: number,
  y: number,
  scale: number,
  width: number,
  height: number,
): ZoomTranslation {
  'worklet';
  const limit = translationLimit(scale, width, height);
  return {
    x:
      limit.x === 0
        ? 0
        : Math.min(limit.x, Math.max(-limit.x, Number.isFinite(x) ? x : 0)),
    y:
      limit.y === 0
        ? 0
        : Math.min(limit.y, Math.max(-limit.y, Number.isFinite(y) ? y : 0)),
  };
}

/**
 * Translation that keeps the content point under (focusX, focusY) fixed while
 * scaling from 1x to `scale`. Coordinates are local to the zoom viewport.
 */
export function translationForZoomAt(
  scale: number,
  focusX: number,
  focusY: number,
  width: number,
  height: number,
): ZoomTranslation {
  'worklet';
  return clampTranslation(
    (width / 2 - focusX) * (scale - 1),
    (height / 2 - focusY) * (scale - 1),
    scale,
    width,
    height,
  );
}

/**
 * Translation after a pinch that changes the scale from `previousScale` to
 * `nextScale`, keeping the focal point stable.
 */
export function translationForPinch(
  previousScale: number,
  nextScale: number,
  previousX: number,
  previousY: number,
  focusX: number,
  focusY: number,
  width: number,
  height: number,
): ZoomTranslation {
  'worklet';
  const ratio = previousScale > 0 ? nextScale / previousScale : 1;
  return clampTranslation(
    ratio * previousX + (1 - ratio) * (focusX - width / 2),
    ratio * previousY + (1 - ratio) * (focusY - height / 2),
    nextScale,
    width,
    height,
  );
}
