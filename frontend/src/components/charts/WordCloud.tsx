'use client';

import { useEffect, useMemo, useRef, useState } from 'react';
import { cn } from '@/lib/utils';

export type WordCloudItem = {
  id: string;
  text: string;
  weight: number;
  meta?: unknown;
};

type LayoutWord = {
  text: string;
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

function createFontScale(weights: number[]) {
  const filtered = weights.filter((w) => Number.isFinite(w) && w > 0);
  const min = Math.min(...filtered, 1);
  const max = Math.max(...filtered, 1);
  const minPx = 14;
  const maxPx = 86;
  if (min === max) return () => 24;
  return (w: number) => {
    const v = Math.max(min, Math.min(max, w));
    // log scale for better separation
    const t = (Math.log(v) - Math.log(min)) / (Math.log(max) - Math.log(min));
    return Math.round(minPx + t * (maxPx - minPx));
  };
}

export function WordCloud({ items, onWordClick, className, ariaLabel, maxWords = 200 }: Props) {
  const containerRef = useRef<HTMLDivElement | null>(null);
  const [size, setSize] = useState(420);
  const [words, setWords] = useState<LayoutWord[]>([]);

  const prepared = useMemo(() => {
    return items
      .filter((i) => i && i.text && Number.isFinite(i.weight) && i.weight > 0)
      .slice(0, maxWords);
  }, [items, maxWords]);

  useEffect(() => {
    const el = containerRef.current;
    if (!el) return;

    const observer = new ResizeObserver((entries) => {
      const rect = entries[0]?.contentRect;
      if (!rect) return;
      const next = Math.max(260, Math.floor(rect.width));
      setSize(next);
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

      const scale = createFontScale(prepared.map((w) => w.weight));
      const cloudFactory = mod.default as unknown as <T extends object>() => any;

      const nextLayout = cloudFactory<LayoutWord>()
        .size([size, size])
        .words(
          prepared.map((w) => ({
            text: w.text,
            size: scale(w.weight),
            x: 0,
            y: 0,
            rotate: 0,
            meta: w.meta ?? w.id,
          }))
        )
        .padding(2)
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
  }, [prepared, size]);

  return (
    <div ref={containerRef} className={cn('w-full', className)} aria-label={ariaLabel}>
      <svg
        width="100%"
        height={size}
        viewBox={`${-size / 2} ${-size / 2} ${size} ${size}`}
        role="img"
        aria-label={ariaLabel}
      >
        <rect x={-size / 2} y={-size / 2} width={size} height={size} rx={12} className="fill-muted/40" />
        <g>
          {words.map((w) => (
            <text
              key={`${w.text}:${w.x}:${w.y}`}
              transform={`translate(${w.x},${w.y}) rotate(${w.rotate})`}
              textAnchor="middle"
              dominantBaseline="central"
              style={{
                fontFamily: 'system-ui',
                fontSize: w.size,
                fontWeight: 700,
                fill: getColor(w.text),
                cursor: onWordClick ? 'pointer' : 'default',
                userSelect: 'none',
              }}
              onClick={() => onWordClick?.(w.meta)}
            >
              {w.text}
            </text>
          ))}
        </g>
      </svg>
    </div>
  );
}
