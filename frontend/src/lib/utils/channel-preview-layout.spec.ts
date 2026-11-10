import assert from 'node:assert/strict';
import test from 'node:test';

import type { ChannelPreviewLayoutItem, ChannelPreviewRow } from './channel-preview-layout';

const layoutModule = await import(`./channel-preview-layout${'.ts'}`);
const {
  CHANNEL_MAX_COLLAGE_HEIGHT,
  CHANNEL_ROW_GAP_PX,
  computeChannelPreviewLayout,
  getChannelPreviewLayoutHeight,
} = layoutModule;

function makeItems(aspectRatios: number[]): ChannelPreviewLayoutItem[] {
  return aspectRatios.map((aspectRatio, index) => ({
    aspectRatio,
    id: `item-${index}`,
  }));
}

function assertRowWidths(
  rows: Array<ChannelPreviewRow<ChannelPreviewLayoutItem>>,
  expectedWidth: number
) {
  for (const row of rows) {
    const totalWidth =
      row.items.reduce((sum, item) => sum + item.width, 0) +
      CHANNEL_ROW_GAP_PX * Math.max(0, row.items.length - 1);
    assert.ok(
      Math.abs(totalWidth - expectedWidth) <= 0.01,
      `row width ${totalWidth} should match expected ${expectedWidth}`
    );
  }
}

test('single preview keeps its measured height without exceeding the hero cap', () => {
  const layout = computeChannelPreviewLayout(makeItems([0.8]), 672);

  assert.equal(layout.kind, 'single');
  assert.ok(layout.heroHeight <= 360);
  assert.ok(layout.heroHeight > 0);
});

test('two-item rows fill the container width exactly', () => {
  const containerWidth = 672;
  const layout = computeChannelPreviewLayout(makeItems([1.9, 1.4]), containerWidth);

  assert.equal(layout.kind, 'rows');
  assertRowWidths(layout.rows, containerWidth);
});

test('hero-side layout stays within the max height and closes the right column width', () => {
  const containerWidth = 672;
  const layout = computeChannelPreviewLayout(
    makeItems([0.7, 1.4, 1.3, 1.2, 1.1]),
    containerWidth
  );

  assert.equal(layout.kind, 'hero-side');
  assert.ok(layout.totalHeight <= CHANNEL_MAX_COLLAGE_HEIGHT + 0.5);
  assertRowWidths(layout.rows, containerWidth - layout.heroWidth - CHANNEL_ROW_GAP_PX);
});

test('portrait-hero regression sample no longer exceeds the preview height cap', () => {
  const containerWidth = 672;
  const layout = computeChannelPreviewLayout(
    makeItems([0.55, 1.9, 1.8, 1.7, 1.6, 1.5]),
    containerWidth
  );

  assert.ok(getChannelPreviewLayoutHeight(layout) <= CHANNEL_MAX_COLLAGE_HEIGHT + 0.5);

  if (layout.kind === 'hero-side') {
    assertRowWidths(layout.rows, containerWidth - layout.heroWidth - CHANNEL_ROW_GAP_PX);
    return;
  }

  if (layout.kind === 'hero-top') {
    assertRowWidths(layout.rows, containerWidth);
    return;
  }

  assert.fail(`unexpected layout kind for regression sample: ${layout.kind}`);
});
