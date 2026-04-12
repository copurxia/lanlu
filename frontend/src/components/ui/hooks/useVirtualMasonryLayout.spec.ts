import { describe, expect, it } from 'vitest';
import {
  buildVirtualMasonryLayout,
  buildVisibleMasonryItems,
} from '@/components/ui/hooks/useVirtualMasonryLayout';

describe('buildVirtualMasonryLayout', () => {
  it('places items into the shortest column first', () => {
    const items = ['a', 'b', 'c', 'd'];
    const layout = buildVirtualMasonryLayout({
      items,
      containerWidth: 300,
      gap: 10,
      getColumns: () => 2,
      getItemKey: (item) => item,
      getItemHeight: (item) => {
        if (item === 'a') return 120;
        if (item === 'b') return 60;
        if (item === 'c') return 80;
        return 90;
      },
    });

    expect(layout.columns).toBe(2);
    expect(layout.layoutItems.map((item) => ({
      key: item.key,
      left: item.left,
      top: item.top,
    }))).toEqual([
      { key: 'a', left: 0, top: 0 },
      { key: 'b', left: 155, top: 0 },
      { key: 'c', left: 155, top: 70 },
      { key: 'd', left: 0, top: 130 },
    ]);
  });
});

describe('buildVisibleMasonryItems', () => {
  it('respects viewport and overscan bounds', () => {
    const layout = buildVirtualMasonryLayout({
      items: ['a', 'b', 'c'],
      containerWidth: 320,
      gap: 8,
      getColumns: () => 1,
      getItemKey: (item) => item,
      getItemHeight: () => 100,
    });

    const visible = buildVisibleMasonryItems({
      layoutItems: layout.layoutItems,
      scrollTop: 110,
      viewportHeight: 80,
      overscan: 10,
    });

    expect(visible.map((item) => item.key)).toEqual(['b']);
  });

  it('includes nearby items when overscan expands the range', () => {
    const layout = buildVirtualMasonryLayout({
      items: ['a', 'b', 'c'],
      containerWidth: 320,
      gap: 8,
      getColumns: () => 1,
      getItemKey: (item) => item,
      getItemHeight: () => 100,
    });

    const visible = buildVisibleMasonryItems({
      layoutItems: layout.layoutItems,
      scrollTop: 110,
      viewportHeight: 80,
      overscan: 140,
    });

    expect(visible.map((item) => item.key)).toEqual(['a', 'b', 'c']);
  });
});
