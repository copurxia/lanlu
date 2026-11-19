import { describe, expect, it } from 'vitest';
import {
  CHANNEL_MAX_COLLAGE_HEIGHT,
  CHANNEL_ROW_GAP_PX,
  computeChannelPreviewLayout,
  getChannelPreviewLayoutHeight,
} from './channel-preview-layout';
import type { ChannelPreviewLayoutItem, ChannelPreviewRow } from './channel-preview-layout';

function makeItems(aspectRatios: number[]): ChannelPreviewLayoutItem[] {
  return aspectRatios.map((aspectRatio, index) => ({
    aspectRatio,
    id: `item-${index}`,
  }));
}

function expectRowWidths(
  rows: Array<ChannelPreviewRow<ChannelPreviewLayoutItem>>,
  expectedWidth: number
) {
  for (const row of rows) {
    const totalWidth =
      row.items.reduce((sum, item) => sum + item.width, 0) +
      CHANNEL_ROW_GAP_PX * Math.max(0, row.items.length - 1);
    expect(Math.abs(totalWidth - expectedWidth)).toBeLessThanOrEqual(0.01);
  }
}

describe('channel preview layout', () => {
  it('single preview keeps its measured height without exceeding the hero cap', () => {
    const layout = computeChannelPreviewLayout(makeItems([0.8]), 672);

    if (layout.kind !== 'single') {
      throw new Error(`expected single, got ${layout.kind}`);
    }
    expect(layout.heroHeight).toBeLessThanOrEqual(360);
    expect(layout.heroHeight).toBeGreaterThan(0);
  });

  it('two-item rows fill the container width exactly', () => {
    const containerWidth = 672;
    const layout = computeChannelPreviewLayout(makeItems([1.9, 1.4]), containerWidth);

    if (layout.kind !== 'rows') {
      throw new Error(`expected rows, got ${layout.kind}`);
    }
    expectRowWidths(layout.rows, containerWidth);
  });

  it('hero-side layout stays within the max height and closes the right column width', () => {
    const containerWidth = 672;
    const layout = computeChannelPreviewLayout(
      makeItems([0.7, 1.4, 1.3, 1.2, 1.1]),
      containerWidth
    );

    if (layout.kind !== 'hero-side') {
      throw new Error(`expected hero-side, got ${layout.kind}`);
    }
    expect(layout.totalHeight).toBeLessThanOrEqual(CHANNEL_MAX_COLLAGE_HEIGHT + 0.5);
    expectRowWidths(layout.rows, containerWidth - layout.heroWidth - CHANNEL_ROW_GAP_PX);
  });

  it('portrait-hero regression sample no longer exceeds the preview height cap', () => {
    const containerWidth = 672;
    const layout = computeChannelPreviewLayout(
      makeItems([0.55, 1.9, 1.8, 1.7, 1.6, 1.5]),
      containerWidth
    );

    expect(getChannelPreviewLayoutHeight(layout)).toBeLessThanOrEqual(
      CHANNEL_MAX_COLLAGE_HEIGHT + 0.5
    );

    if (layout.kind === 'hero-side') {
      expectRowWidths(layout.rows, containerWidth - layout.heroWidth - CHANNEL_ROW_GAP_PX);
      return;
    }

    if (layout.kind === 'hero-top') {
      expectRowWidths(layout.rows, containerWidth);
      return;
    }

    throw new Error(`unexpected layout kind for regression sample: ${layout.kind}`);
  });
});
