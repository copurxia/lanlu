import {
  isWidePage,
  orderWideHalves,
  shouldReverseWideHalves,
} from './widePage';

describe('widePage helpers', () => {
  it('detects wide pages', () => {
    expect(isWidePage(2000, 1400)).toBe(true);
    expect(isWidePage(1400, 2000)).toBe(false);
    expect(isWidePage(1000, 1000)).toBe(false);
  });

  it('mirrors the halves for right-to-left layouts', () => {
    expect(shouldReverseWideHalves(false, false)).toBe(false);
    expect(shouldReverseWideHalves(true, false)).toBe(true);
    expect(shouldReverseWideHalves(true, true)).toBe(false);
    expect(shouldReverseWideHalves(false, true)).toBe(true);
  });

  it('orders the halves without mutating the input', () => {
    const halves = ['left', 'right'];
    expect(orderWideHalves(halves, false)).toEqual(['left', 'right']);
    expect(orderWideHalves(halves, true)).toEqual(['right', 'left']);
    expect(halves).toEqual(['left', 'right']);
  });
});
