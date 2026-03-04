'use client';

import { useEffect, useMemo, useRef, useState } from 'react';
import { cn } from '@/lib/utils/utils';

export type WordCloudItem = {
  id: string;
  text: string;
  weight: number;
  meta?: unknown;
};

type LayoutWord = {
  id: string;
  text: string;
  weight: number;
  size: number;
  x: number;
  y: number;
  rotate: number;
  meta?: unknown;
};

type Props = {
  items: WordCloudItem[];
  onWordClick?: (meta: unknown) => void;
  className?: string;
  ariaLabel?: string;
  maxWords?: number;
};

function stableHash(input: string): number {
  let hash = 2166136261;
  for (let i = 0; i < input.length; i++) {
    hash ^= input.charCodeAt(i);
    hash = Math.imul(hash, 16777619);
  }
  return hash >>> 0;
}

const palette = [
  '#b45309',
  '#c2410c',
  '#be123c',
  '#a21caf',
  '#7c3aed',
  '#2563eb',
  '#0ea5e9',
  '#059669',
  '#16a34a',
  '#a16207',
];

function getColor(key: string): string {
  const idx = stableHash(key) % palette.length;
  return palette[idx];
}

function clamp(value: number, min: number, max: number): number {
  return Math.max(min, Math.min(max, value));
}

function computeCloudHeight(width: number, wordCount: number): number {
  const base = width * 0.62;
  const extra = Math.log2(wordCount + 1) * 48;
  return clamp(Math.round(base + extra), 220, 680);
}

function createFontScale(weights: number[], wordCount: number, width: number, height: number) {
  const filtered = weights.filter((w) => Number.isFinite(w) && w > 0);
  const min = Math.min(...filtered, 1);
  const max = Math.max(...filtered, 1);

  const areaFactor = clamp(Math.sqrt((width * height) / (420 * 320)), 0.8, 1.2);
  const crowdFactor = wordCount > 120 ? 0.72 : wordCount > 70 ? 0.82 : wordCount > 30 ? 0.92 : 1;
  const sparseFactor = wordCount < 6 ? 1.28 : wordCount < 12 ? 1.15 : 1;

  const baseMin = wordCount > 120 ? 10 : wordCount > 70 ? 11 : 12;
  const baseMax = wordCount < 6 ? 96 : wordCount < 12 ? 76 : wordCount < 30 ? 60 : wordCount < 70 ? 48 : 40;

  const minPx = Math.max(10, Math.round(baseMin * areaFactor * crowdFactor));
  const maxPx = Math.max(minPx + 8, Math.round(baseMax * areaFactor * crowdFactor * sparseFactor));

  if (min === max) return () => Math.round((minPx + maxPx) / 2);

  return (w: number) => {
    const v = Math.max(min, Math.min(max, w));
    const t = (Math.log(v) - Math.log(min)) / (Math.log(max) - Math.log(min));
    return Math.round(minPx + t * (maxPx - minPx));
  };
}

export function WordCloud({ items, onWordClick, className, ariaLabel, maxWords = 200 }: Props) {
  const containerRef = useRef<HTMLDivElement | null>(null);
  const [width, setWidth] = useState(420);
  const [words, setWords] = useState<LayoutWord[]>([]);
  const [hoveredWordId, setHoveredWordId] = useState<string | null>(null);

  const prepared = useMemo(() => {
    return items
      .filter((i) => i && i.text && Number.isFinite(i.weight) && i.weight > 0)
      .sort((a, b) => b.weight - a.weight)
      .slice(0, maxWords);
  }, [items, maxWords]);

  const height = useMemo(() => computeCloudHeight(width, prepared.length), [prepared.length, width]);

  useEffect(() => {
    const el = containerRef.current;
    if (!el) return;

    const observer = new ResizeObserver((entries) => {
      const rect = entries[0]?.contentRect;
      if (!rect) return;
      const next = Math.max(260, Math.floor(rect.width));
      setWidth(next);
    });
    observer.observe(el);
    return () => observer.disconnect();
  }, []);

  useEffect(() => {
    if (prepared.length === 0) {
      // Avoid synchronous setState in effect (lint rule); schedule microtask instead.
      queueMicrotask(() => setWords([]));
      return;
    }

    let cancelled = false;
    let layout: { start: () => void; stop: () => void } | null = null;

    (async () => {
      const mod = await import('d3-cloud');
      if (cancelled) return;

      const scale = createFontScale(prepared.map((w) => w.weight), prepared.length, width, height);
      const cloudFactory = mod.default as unknown as () => any;
      const padding = prepared.length > 120 ? 0 : prepared.length > 70 ? 1 : 2;

      const nextLayout = cloudFactory()
        .size([width, height])
        .words(
          prepared.map((w) => ({
            id: w.id,
            text: w.text,
            weight: w.weight,
            size: scale(w.weight),
            x: 0,
            y: 0,
            rotate: 0,
            meta: w.meta ?? w.id,
          }))
        )
        .padding(padding)
        .rotate(() => 0)
        .font('system-ui')
        .fontWeight(() => 700)
        .fontSize((d: LayoutWord) => d.size)
        .spiral('archimedean')
        .on('end', (result: LayoutWord[]) => {
          if (!cancelled) setWords(result);
        });

      layout = nextLayout;
      nextLayout.start();
    })();

    return () => {
      cancelled = true;
      layout?.stop();
    };
  }, [height, prepared, width]);

  return (
    <div ref={containerRef} className={cn('w-full', className)} aria-label={ariaLabel}>
      <svg
        width="100%"
        height={height}
        viewBox={`${-width / 2} ${-height / 2} ${width} ${height}`}
        role="img"
        aria-label={ariaLabel}
      >
        <rect x={-width / 2} y={-height / 2} width={width} height={height} rx={12} className="fill-muted/40" />
        <g>
          {words.map((w) => {
            const isHovered = hoveredWordId === w.id;
            const isDimmed = hoveredWordId !== null && !isHovered;

            return (
              <text
                key={`${w.id}:${w.x}:${w.y}`}
                transform={`translate(${w.x},${w.y}) rotate(${w.rotate})`}
                textAnchor="middle"
                dominantBaseline="central"
                role={onWordClick ? 'button' : undefined}
                tabIndex={onWordClick ? 0 : -1}
                aria-label={`${w.text} (${w.weight})`}
                style={{
                  fontFamily: 'system-ui',
                  fontSize: w.size,
                  fontWeight: isHovered ? 800 : 700,
                  fill: getColor(w.id),
                  cursor: onWordClick ? 'pointer' : 'default',
                  userSelect: 'none',
                  opacity: isDimmed ? 0.4 : 1,
                  transition: 'opacity 120ms ease-out',
                }}
                onMouseEnter={() => setHoveredWordId(w.id)}
                onMouseLeave={() => setHoveredWordId((prev) => (prev === w.id ? null : prev))}
                onFocus={() => setHoveredWordId(w.id)}
                onBlur={() => setHoveredWordId((prev) => (prev === w.id ? null : prev))}
                onClick={() => onWordClick?.(w.meta)}
                onKeyDown={(e) => {
                  if (!onWordClick) return;
                  if (e.key === 'Enter' || e.key === ' ') {
                    e.preventDefault();
                    onWordClick(w.meta);
                  }
                }}
              >
                <title>{`${w.text} (${w.weight})`}</title>
                {w.text}
              </text>
            );
          })}
        </g>
      </svg>
    </div>
  );
}
