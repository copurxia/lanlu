import { resolveTapAction } from './tapZones';

const width = 1000;
const height = 2000;

describe('resolveTapAction', () => {
  it('keeps the current default layout for vertical readers', () => {
    const options = { vertical: true };
    expect(resolveTapAction('default', 500, 100, width, height, options)).toBe('backward');
    expect(resolveTapAction('default', 500, 1000, width, height, options)).toBe('menu');
    expect(resolveTapAction('default', 500, 1900, width, height, options)).toBe('forward');
  });

  it('mirrors the default layout for right-to-left paging', () => {
    expect(
      resolveTapAction('default', 100, 1000, width, height, { vertical: false }),
    ).toBe('backward');
    expect(
      resolveTapAction('default', 900, 1000, width, height, { vertical: false }),
    ).toBe('forward');
    expect(
      resolveTapAction('default', 100, 1000, width, height, { vertical: false, reversed: true }),
    ).toBe('forward');
    expect(
      resolveTapAction('default', 900, 1000, width, height, { vertical: false, reversed: true }),
    ).toBe('backward');
  });

  it('supports the L-shaped layout', () => {
    const options = { vertical: true };
    expect(resolveTapAction('l-shape', 500, 100, width, height, options)).toBe('backward');
    expect(resolveTapAction('l-shape', 500, 1900, width, height, options)).toBe('forward');
    expect(resolveTapAction('l-shape', 100, 1000, width, height, options)).toBe('backward');
    expect(resolveTapAction('l-shape', 900, 1000, width, height, options)).toBe('forward');
    expect(resolveTapAction('l-shape', 500, 1000, width, height, options)).toBe('menu');
  });

  it('supports the Kindle-like layout', () => {
    const options = { vertical: true };
    expect(resolveTapAction('kindlish', 500, 100, width, height, options)).toBe('menu');
    expect(resolveTapAction('kindlish', 100, 1500, width, height, options)).toBe('backward');
    expect(resolveTapAction('kindlish', 900, 1500, width, height, options)).toBe('forward');
  });

  it('supports the edge layout', () => {
    const options = { vertical: true };
    expect(resolveTapAction('edge', 100, 500, width, height, options)).toBe('forward');
    expect(resolveTapAction('edge', 900, 500, width, height, options)).toBe('forward');
    expect(resolveTapAction('edge', 500, 1900, width, height, options)).toBe('backward');
    expect(resolveTapAction('edge', 500, 500, width, height, options)).toBe('menu');
  });

  it('returns menu when zones are disabled or the size is invalid', () => {
    expect(resolveTapAction('disabled', 100, 100, width, height, { vertical: true })).toBe('menu');
    expect(resolveTapAction('default', 100, 100, 0, height, { vertical: true })).toBe('menu');
    expect(resolveTapAction('default', 100, 100, width, 0, { vertical: true })).toBe('menu');
  });
});
