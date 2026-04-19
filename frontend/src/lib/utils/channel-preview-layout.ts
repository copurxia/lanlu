export const DEFAULT_CHANNEL_ASPECT_RATIO = 1.2;
export const CHANNEL_ROW_GAP_PX = 1;
export const CHANNEL_MAX_COLLAGE_HEIGHT = 460;
export const CHANNEL_TOP_HERO_TARGET_HEIGHT = 220;
export const CHANNEL_SIDE_HERO_MIN_COUNT = 4;

const MIN_ASPECT_RATIO = 0.45;
const MAX_ASPECT_RATIO = 2.4;
const MIN_ROW_HEIGHT = 92;
const MIN_SINGLE_TILE_WIDTH = 96;
const MIN_TOP_HERO_HEIGHT = 120;
const MAX_TOP_HERO_HEIGHT = 260;
const MIN_SIDE_RIGHT_WIDTH = 120;
const BINARY_SEARCH_STEPS = 18;
const HEIGHT_TOLERANCE_PX = 0.25;

export type ChannelPreviewLayoutItem = {
  aspectRatio: number;
  id: string;
};

export type ChannelPreviewRow<T extends ChannelPreviewLayoutItem> = {
  height: number;
  items: Array<T & { width: number }>;
};

export type ChannelPreviewLayout<T extends ChannelPreviewLayoutItem> =
  | {
      kind: 'single';
      hero: T;
      heroHeight: number;
    }
  | {
      kind: 'rows';
      rows: ChannelPreviewRow<T>[];
    }
  | {
      kind: 'hero-top';
      hero: T;
      heroHeight: number;
      rows: ChannelPreviewRow<T>[];
    }
  | {
      kind: 'hero-side';
      hero: T;
      heroWidth: number;
      totalHeight: number;
      rows: ChannelPreviewRow<T>[];
    };

type RowSelection<T extends ChannelPreviewLayoutItem> = {
  rowCount: number;
  rows: ChannelPreviewRow<T>[];
  totalHeight: number;
};

function clampAspectRatio(aspectRatio: number): number {
  if (!Number.isFinite(aspectRatio) || aspectRatio <= 0) {
    return DEFAULT_CHANNEL_ASPECT_RATIO;
  }
  return Math.max(MIN_ASPECT_RATIO, Math.min(aspectRatio, MAX_ASPECT_RATIO));
}

function normalizeRowItems<T extends ChannelPreviewLayoutItem>(
  row: T[],
  rowWidth: number,
  height: number
): Array<T & { width: number }> {
  const availableWidth = Math.max(0, rowWidth - CHANNEL_ROW_GAP_PX * Math.max(0, row.length - 1));
  const rawWidths = row.map((item) => height * item.aspectRatio);
  const residual = availableWidth - rawWidths.reduce((sum, width) => sum + width, 0);
  const adjustedWidths = rawWidths.map((width, index) => (
    index === rawWidths.length - 1 ? width + residual : width
  ));

  return row.map((item, index) => ({
    ...item,
    width: adjustedWidths[index],
  }));
}

function buildJustifiedRows<T extends ChannelPreviewLayoutItem>(
  sourceItems: T[],
  rowWidth: number,
  rowCount: number,
  maxTotalHeight: number
): ChannelPreviewRow<T>[] {
  if (sourceItems.length === 0) return [];

  if (sourceItems.length === 1) {
    const width = Math.max(MIN_SINGLE_TILE_WIDTH, rowWidth);
    const height = width / Math.max(sourceItems[0].aspectRatio, 0.1);
    return [
      {
        height,
        items: [{ ...sourceItems[0], width }],
      },
    ];
  }

  const normalizedRowCount = Math.max(1, Math.min(rowCount, sourceItems.length));
  const targetRowHeight = Math.max(
    MIN_ROW_HEIGHT,
    (maxTotalHeight - CHANNEL_ROW_GAP_PX * Math.max(0, normalizedRowCount - 1)) / normalizedRowCount
  );
  const targetRatio = rowWidth / targetRowHeight;
  let bestCuts: number[] | null = null;
  let bestScore = Number.POSITIVE_INFINITY;

  const search = (startIndex: number, rowsLeft: number, cuts: number[]) => {
    if (rowsLeft === 1) {
      if (startIndex >= sourceItems.length) return;
      const nextCuts = [...cuts, sourceItems.length];
      const rowSlices: T[][] = [];
      let sliceStart = 0;
      for (const cut of nextCuts) {
        rowSlices.push(sourceItems.slice(sliceStart, cut));
        sliceStart = cut;
      }
      const score = rowSlices.reduce((sum, row, index) => {
        const ratioSum = row.reduce((rowSum, item) => rowSum + item.aspectRatio, 0);
        const deviation = Math.abs(ratioSum - targetRatio);
        const countPenalty = row.length > 4 ? (row.length - 4) * 12 : 0;
        const tailPenalty = index === rowSlices.length - 1 && row.length === 1 ? 6 : 0;
        return sum + deviation * deviation + countPenalty + tailPenalty;
      }, 0);
      if (score < bestScore) {
        bestScore = score;
        bestCuts = nextCuts;
      }
      return;
    }

    const maxCut = sourceItems.length - rowsLeft + 1;
    for (let cut = startIndex + 1; cut <= maxCut; cut += 1) {
      search(cut, rowsLeft - 1, [...cuts, cut]);
    }
  };

  search(0, normalizedRowCount, []);

  const cuts = bestCuts || [sourceItems.length];
  const rows: T[][] = [];
  let start = 0;
  for (const cut of cuts) {
    rows.push(sourceItems.slice(start, cut));
    start = cut;
  }

  return rows.map((row) => {
    const ratioSum = Math.max(row.reduce((sum, item) => sum + item.aspectRatio, 0), 0.1);
    const rowGapWidth = CHANNEL_ROW_GAP_PX * Math.max(0, row.length - 1);
    const height = (rowWidth - rowGapWidth) / ratioSum;

    return {
      height,
      items: normalizeRowItems(row, rowWidth, height),
    };
  });
}

function measureRowsHeight<T extends ChannelPreviewLayoutItem>(rows: ChannelPreviewRow<T>[]): number {
  return rows.reduce((sum, row) => sum + row.height, 0) + CHANNEL_ROW_GAP_PX * Math.max(0, rows.length - 1);
}

function selectRows<T extends ChannelPreviewLayoutItem>(
  sourceItems: T[],
  rowWidth: number,
  preferredRowCount: number,
  maxTotalHeight: number
): RowSelection<T> | null {
  if (sourceItems.length === 0) {
    return {
      rowCount: 0,
      rows: [],
      totalHeight: 0,
    };
  }

  const maxRowCount = Math.max(1, Math.min(preferredRowCount, sourceItems.length));
  let best: RowSelection<T> | null = null;
  let bestScore = Number.POSITIVE_INFINITY;

  for (let rowCount = 1; rowCount <= maxRowCount; rowCount += 1) {
    const rows = buildJustifiedRows(sourceItems, rowWidth, rowCount, maxTotalHeight);
    const totalHeight = measureRowsHeight(rows);
    if (totalHeight > maxTotalHeight + HEIGHT_TOLERANCE_PX) continue;

    const rowPenalty = Math.abs(preferredRowCount - rowCount) * 48;
    const fillPenalty = Math.abs(maxTotalHeight - totalHeight);
    const score = rowPenalty + fillPenalty;
    if (score < bestScore) {
      bestScore = score;
      best = {
        rowCount,
        rows,
        totalHeight,
      };
    }
  }

  return best;
}

function chooseHeroPlacement<T extends ChannelPreviewLayoutItem>(sourceItems: T[]) {
  let topHeroIndex = 0;
  let topHeroScore = Number.NEGATIVE_INFINITY;
  let sideHeroIndex = 0;
  let sideHeroScore = Number.NEGATIVE_INFINITY;

  sourceItems.forEach((item, index) => {
    const orderBonus = Math.max(0, 0.12 - index * 0.02);
    const topScore = (2.2 - Math.abs(item.aspectRatio - 1.55)) + (item.aspectRatio >= 1.08 ? 0.8 : 0) + orderBonus;
    const sideScore = (2.1 - Math.abs(item.aspectRatio - 0.78)) + (item.aspectRatio <= 0.95 ? 1.05 : 0) + orderBonus;
    if (topScore > topHeroScore) {
      topHeroScore = topScore;
      topHeroIndex = index;
    }
    if (sideScore > sideHeroScore) {
      sideHeroScore = sideScore;
      sideHeroIndex = index;
    }
  });

  const preferSide =
    sourceItems.length >= CHANNEL_SIDE_HERO_MIN_COUNT &&
    sourceItems[sideHeroIndex].aspectRatio < 1 &&
    sideHeroScore > topHeroScore + 0.18;

  return {
    heroIndex: preferSide ? sideHeroIndex : topHeroIndex,
    placement: preferSide ? 'side' as const : 'top' as const,
  };
}

function solveHeroSideLayout<T extends ChannelPreviewLayoutItem>(
  hero: T,
  restItems: T[],
  containerWidth: number
): Extract<ChannelPreviewLayout<T>, { kind: 'hero-side' }> | null {
  const desiredRowCount = restItems.length <= 3 ? 2 : 3;
  const maxRowCount = Math.max(1, Math.min(desiredRowCount, restItems.length));
  const maxHeightByWidth = Math.min(
    CHANNEL_MAX_COLLAGE_HEIGHT,
    (containerWidth - CHANNEL_ROW_GAP_PX - MIN_SIDE_RIGHT_WIDTH) / Math.max(hero.aspectRatio, 0.1)
  );

  if (!Number.isFinite(maxHeightByWidth) || maxHeightByWidth <= MIN_TOP_HERO_HEIGHT) {
    return null;
  }

  type Candidate = {
    heroWidth: number;
    rowCount: number;
    rows: ChannelPreviewRow<T>[];
    rightWidth: number;
    totalHeight: number;
  };

  let best: Candidate | null = null;
  let bestScore = Number.POSITIVE_INFINITY;

  for (let rowCount = 1; rowCount <= maxRowCount; rowCount += 1) {
    const evaluate = (candidateHeight: number) => {
      const heroWidth = candidateHeight * hero.aspectRatio;
      const rightWidth = containerWidth - heroWidth - CHANNEL_ROW_GAP_PX;
      if (heroWidth < MIN_SINGLE_TILE_WIDTH || rightWidth < MIN_SIDE_RIGHT_WIDTH) return null;

      const rows = buildJustifiedRows(restItems, rightWidth, rowCount, candidateHeight);
      return {
        heroWidth,
        rightWidth,
        rows,
        totalHeight: measureRowsHeight(rows),
      };
    };

    const upperBound = Math.min(CHANNEL_MAX_COLLAGE_HEIGHT, maxHeightByWidth);
    const maxEvaluation = evaluate(upperBound);
    if (!maxEvaluation) continue;
    if (maxEvaluation.totalHeight > upperBound + HEIGHT_TOLERANCE_PX) continue;

    let low = MIN_TOP_HERO_HEIGHT;
    let high = upperBound;
    let resolvedEvaluation = maxEvaluation;

    for (let step = 0; step < BINARY_SEARCH_STEPS; step += 1) {
      const candidateHeight = (low + high) / 2;
      const evaluation = evaluate(candidateHeight);
      if (!evaluation) {
        high = candidateHeight;
        continue;
      }

      const diff = evaluation.totalHeight - candidateHeight;
      resolvedEvaluation = evaluation;

      if (Math.abs(diff) <= HEIGHT_TOLERANCE_PX) break;
      if (diff > 0) {
        low = candidateHeight;
      } else {
        high = candidateHeight;
      }
    }

    const finalEvaluation = resolvedEvaluation;
    if (finalEvaluation.totalHeight > CHANNEL_MAX_COLLAGE_HEIGHT + HEIGHT_TOLERANCE_PX) continue;

    const score =
      Math.abs(desiredRowCount - rowCount) * 48 +
      Math.abs(CHANNEL_MAX_COLLAGE_HEIGHT - finalEvaluation.totalHeight);

    if (score < bestScore) {
      bestScore = score;
      best = {
        heroWidth: finalEvaluation.heroWidth,
        rowCount,
        rows: finalEvaluation.rows,
        rightWidth: finalEvaluation.rightWidth,
        totalHeight: finalEvaluation.totalHeight,
      };
    }
  }

  if (!best) return null;

  return {
    kind: 'hero-side',
    hero,
    heroWidth: best.heroWidth,
    totalHeight: best.totalHeight,
    rows: best.rows,
  };
}

function buildHeroTopLayout<T extends ChannelPreviewLayoutItem>(
  hero: T,
  restItems: T[],
  containerWidth: number
): Extract<ChannelPreviewLayout<T>, { kind: 'hero-top' }> {
  const preferredHeroHeight = Math.min(
    MAX_TOP_HERO_HEIGHT,
    Math.max(CHANNEL_TOP_HERO_TARGET_HEIGHT, containerWidth / Math.max(hero.aspectRatio, 0.1))
  );
  const singleRowSelection = selectRows(restItems, containerWidth, 1, CHANNEL_MAX_COLLAGE_HEIGHT);
  const minRowsHeight = singleRowSelection?.totalHeight || 0;
  const maxHeroHeight = Math.max(
    MIN_TOP_HERO_HEIGHT,
    CHANNEL_MAX_COLLAGE_HEIGHT - (restItems.length > 0 ? CHANNEL_ROW_GAP_PX : 0) - minRowsHeight
  );
  const heroHeight = Math.max(
    MIN_TOP_HERO_HEIGHT,
    Math.min(preferredHeroHeight, Math.max(MIN_TOP_HERO_HEIGHT, maxHeroHeight))
  );
  const remainingHeight = Math.max(
    0,
    CHANNEL_MAX_COLLAGE_HEIGHT - heroHeight - (restItems.length > 0 ? CHANNEL_ROW_GAP_PX : 0)
  );
  const preferredRowCount = restItems.length <= 2 ? 1 : restItems.length <= 4 ? 2 : 3;
  const rowSelection = selectRows(restItems, containerWidth, preferredRowCount, remainingHeight) || {
    rowCount: 0,
    rows: [],
    totalHeight: 0,
  };

  return {
    kind: 'hero-top',
    hero,
    heroHeight,
    rows: rowSelection.rows,
  };
}

export function getChannelPreviewLayoutHeight<T extends ChannelPreviewLayoutItem>(layout: ChannelPreviewLayout<T>): number {
  switch (layout.kind) {
    case 'single':
      return layout.heroHeight;
    case 'rows':
      return measureRowsHeight(layout.rows);
    case 'hero-top':
      return layout.heroHeight + (layout.rows.length > 0 ? CHANNEL_ROW_GAP_PX : 0) + measureRowsHeight(layout.rows);
    case 'hero-side':
      return layout.totalHeight;
  }
}

export function computeChannelPreviewLayout<T extends ChannelPreviewLayoutItem>(
  items: T[],
  containerWidth: number
): ChannelPreviewLayout<T> {
  const normalizedItems = items.map((item) => ({
    ...item,
    aspectRatio: clampAspectRatio(item.aspectRatio),
  }));
  const effectiveWidth = Math.max(containerWidth, 320);

  if (normalizedItems.length === 0) {
    return {
      kind: 'rows',
      rows: [],
    };
  }

  if (normalizedItems.length === 1) {
    return {
      kind: 'single',
      hero: normalizedItems[0],
      heroHeight: Math.min(360, effectiveWidth / Math.max(normalizedItems[0].aspectRatio, 0.1)),
    };
  }

  if (normalizedItems.length === 2) {
    return {
      kind: 'rows',
      rows: buildJustifiedRows(normalizedItems, effectiveWidth, 1, 260),
    };
  }

  const { heroIndex, placement } = chooseHeroPlacement(normalizedItems);
  const hero = normalizedItems[heroIndex];
  const restItems = normalizedItems.filter((_, index) => index !== heroIndex);

  if (placement === 'side') {
    const sideLayout = solveHeroSideLayout(hero, restItems, effectiveWidth);
    if (sideLayout) {
      return sideLayout;
    }
  }

  return buildHeroTopLayout(hero, restItems, effectiveWidth);
}
