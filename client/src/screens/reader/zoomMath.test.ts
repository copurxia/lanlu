import {
  clampScale,
  clampTranslation,
  translationForPinch,
  translationForZoomAt,
  translationLimit,
} from './zoomMath';

describe('zoomMath', () => {
  it('clamps scale to the allowed range', () => {
    expect(clampScale(0.2, 1, 5)).toBe(1);
    expect(clampScale(2.5, 1, 5)).toBe(2.5);
    expect(clampScale(9, 1, 5)).toBe(5);
    expect(clampScale(Number.NaN, 1, 5)).toBe(1);
  });

  it('locks translation at 1x', () => {
    const t = clampTranslation(400, -300, 1, 1080, 1920);
    expect(t).toEqual({ x: 0, y: 0 });
  });

  it('limits translation to the scaled overflow', () => {
    expect(translationLimit(2, 1000, 2000)).toEqual({ x: 500, y: 1000 });
    expect(clampTranslation(900, -900, 2, 1000, 2000)).toEqual({
      x: 500,
      y: -900,
    });
  });

  it('keeps a tapped point fixed when zooming in', () => {
    const width = 1000;
    const height = 2000;
    const focusX = 250;
    const focusY = 500;
    const scale = 2;
    const t = translationForZoomAt(scale, focusX, focusY, width, height);

    // The content point under the tap stays under the tap after the transform.
    const contentX = (focusX - width / 2 - t.x) / scale;
    const contentY = (focusY - height / 2 - t.y) / scale;
    const screenX = width / 2 + t.x + contentX * scale;
    const screenY = height / 2 + t.y + contentY * scale;
    expect(screenX).toBeCloseTo(focusX, 5);
    expect(screenY).toBeCloseTo(focusY, 5);
  });

  it('keeps the focal point fixed during a pinch', () => {
    const width = 1080;
    const height = 1920;
    const focusX = 300;
    const focusY = 700;
    const previousScale = 1;
    const nextScale = 2.4;
    const previousX = 0;
    const previousY = 0;
    const t = translationForPinch(
      previousScale,
      nextScale,
      previousX,
      previousY,
      focusX,
      focusY,
      width,
      height,
    );

    const contentX = (focusX - width / 2 - previousX) / previousScale;
    const contentY = (focusY - height / 2 - previousY) / previousScale;
    const screenX = width / 2 + t.x + contentX * nextScale;
    const screenY = height / 2 + t.y + contentY * nextScale;
    expect(screenX).toBeCloseTo(focusX, 5);
    expect(screenY).toBeCloseTo(focusY, 5);
  });

  it('returns to the previous translation when the pinch scale is unchanged', () => {
    expect(translationForPinch(2, 2, 120, -80, 100, 200, 1000, 2000)).toEqual({
      x: 120,
      y: -80,
    });
  });
});
