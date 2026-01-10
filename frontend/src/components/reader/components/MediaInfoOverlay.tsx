import type React from 'react';

type KV = { key: string; value: string };

function splitTokens(line: string) {
  return line
    .trim()
    .split(/\s{2,}/g)
    .map((s) => s.trim())
    .filter(Boolean);
}

function pairTokens(tokens: string[]): KV[] {
  const pairs: KV[] = [];
  for (let i = 0; i < tokens.length; i += 2) {
    const key = tokens[i];
    const value = tokens[i + 1];
    if (!key || !value) continue;
    pairs.push({ key, value });
  }
  return pairs;
}

function StatusBadge({ value }: { value: string }) {
  const v = value.toLowerCase();
  const isOn = v === 'on' || v === 'true' || v === 'enabled';
  const isOff = v === 'off' || v === 'false' || v === 'disabled';
  const color = isOn
    ? 'bg-emerald-500/15 border-emerald-500/25 text-emerald-700 dark:text-emerald-200'
    : isOff
      ? 'bg-muted/40 border-border/50 text-muted-foreground'
      : 'bg-sky-500/15 border-sky-500/25 text-sky-700 dark:text-sky-200';
  return (
    <span className={`inline-flex items-center rounded-md border px-1.5 py-0.5 text-[10px] ${color}`}>
      {value}
    </span>
  );
}

function Pill({
  children,
  tone = 'neutral',
}: {
  children: React.ReactNode;
  tone?: 'neutral' | 'strong';
}) {
  const cls =
    tone === 'strong'
      ? 'border-border/70 bg-background/60 text-foreground'
      : 'border-border/60 bg-muted/30 text-muted-foreground';
  return (
    <span className={`inline-flex items-center rounded-md border px-1.5 py-0.5 text-[10px] font-mono ${cls}`}>
      {children}
    </span>
  );
}

function KVGrid({ items }: { items: KV[] }) {
  return (
    <div className="grid grid-cols-[auto,1fr] gap-x-2 gap-y-1 text-[11px] leading-snug">
      {items.map((kv, idx) => (
        <div key={`${kv.key}-${idx}`} className="contents">
          <div className="text-muted-foreground">{kv.key}</div>
          <div className="text-foreground break-all">{kv.value}</div>
        </div>
      ))}
    </div>
  );
}

function CompactKVRow({ items }: { items: KV[] }) {
  return (
    <div className="flex flex-wrap gap-1.5">
      {items.map((kv, idx) => (
        <div
          key={`${kv.key}-${idx}`}
          className="inline-flex items-center gap-1 rounded-md border border-border/60 bg-muted/30 px-1.5 py-0.5 text-[10px]"
        >
          <span className="text-muted-foreground">{kv.key}</span>
          <span className="text-foreground font-mono">{kv.value}</span>
        </div>
      ))}
    </div>
  );
}

type MediaBlock = {
  prefix: string;
  title: { type: string; name: string; flags: string[] } | null;
  rows: KV[][];
  rawLines: string[];
};

function parseMediaBlocks(lines: string[]) {
  const blocks: MediaBlock[] = [];
  const byPrefix = new Map<string, MediaBlock>();

  const getBlock = (prefix: string) => {
    const existing = byPrefix.get(prefix);
    if (existing) return existing;
    const created: MediaBlock = { prefix, title: null, rows: [], rawLines: [] };
    byPrefix.set(prefix, created);
    blocks.push(created);
    return created;
  };

  for (const line of lines) {
    const match = line.match(/^(#\d+)\s+(.*)$/);
    const prefix = match?.[1] ? match[1] : '';
    const content = match?.[2] ? match[2] : line;
    const block = getBlock(prefix);
    block.rawLines.push(content);

    const tokens = splitTokens(content);
    if (!tokens.length) continue;

    if (!block.title) {
      const type = tokens[0];
      const name = tokens[1] || '';
      if (type === 'image' || type === 'video' || type === 'html') {
        block.title = { type, name, flags: tokens.slice(2) };
        continue;
      }
    }

    block.rows.push(pairTokens(tokens));
  }

  return blocks;
}

export function MediaInfoOverlay({
  lines,
  sidebarOpen,
}: {
  lines: string[];
  sidebarOpen: boolean;
}) {
  if (!lines.length) return null;

  const header = lines[0] || '';
  const uiLine = lines.find((l) => l.startsWith('ui ')) || '';
  const cfgLines = lines.filter((l) => l.startsWith('cfg '));
  const envLine = lines.find((l) => l.startsWith('env ')) || '';
  const loadLine = lines.find((l) => l.startsWith('load ')) || '';

  const consumed = new Set<string>([header, uiLine, envLine, loadLine, ...cfgLines].filter(Boolean));
  const mediaLines = lines.filter((l) => !consumed.has(l));

  const uiItems = uiLine ? pairTokens(splitTokens(uiLine.replace(/^ui\s+/, ''))) : [];
  const cfgItems = cfgLines.flatMap((l) => pairTokens(splitTokens(l.replace(/^cfg\s+/, ''))));
  const envItems = envLine ? pairTokens(splitTokens(envLine.replace(/^env\s+/, ''))) : [];
  const loadItems = loadLine ? pairTokens(splitTokens(loadLine.replace(/^load\s+/, ''))) : [];

  const blocks = parseMediaBlocks(mediaLines);

  return (
    <div
      className={[
        'absolute top-3 z-30 pointer-events-none select-none',
        sidebarOpen ? 'left-[calc(280px+12px)] sm:left-[calc(320px+12px)]' : 'left-3',
      ].join(' ')}
    >
      <div className="w-[min(92vw,560px)] lg:w-[520px] overflow-hidden rounded-xl border border-border/60 bg-background/85 shadow-xl backdrop-blur-md">
        <div className="flex items-center justify-between gap-2 border-b border-border/60 px-3 py-2">
          <div className="text-[12px] font-medium text-foreground font-mono">{header}</div>
          <div className="text-[10px] text-muted-foreground">Media Info</div>
        </div>

        <div className="space-y-2 px-3 py-2">
          {(uiItems.length > 0 || cfgItems.length > 0) && (
            <div className="space-y-1.5">
              {uiItems.length > 0 && (
                <div className="flex flex-wrap gap-1.5">
                  {uiItems.map((kv, idx) => (
                    <div
                      key={`ui-${kv.key}-${idx}`}
                      className="inline-flex items-center gap-1 rounded-md border border-border/60 bg-muted/30 px-1.5 py-0.5 text-[10px]"
                    >
                      <span className="text-muted-foreground">{kv.key}</span>
                      <StatusBadge value={kv.value} />
                    </div>
                  ))}
                </div>
              )}
              {cfgItems.length > 0 && (
                <div className="flex flex-wrap gap-1.5">
                  {cfgItems.map((kv, idx) => (
                    <div
                      key={`cfg-${kv.key}-${idx}`}
                      className="inline-flex items-center gap-1 rounded-md border border-border/60 bg-muted/30 px-1.5 py-0.5 text-[10px]"
                    >
                      <span className="text-muted-foreground">{kv.key}</span>
                      <StatusBadge value={kv.value} />
                    </div>
                  ))}
                </div>
              )}
            </div>
          )}

          {(envItems.length > 0 || loadItems.length > 0) && (
            <div className="grid grid-cols-1 gap-2 sm:grid-cols-2">
              {envItems.length > 0 ? (
                <div className="rounded-lg border border-border/60 bg-muted/30 p-2">
                  <div className="mb-1 text-[10px] uppercase tracking-wide text-muted-foreground">Env</div>
                  <CompactKVRow items={envItems} />
                </div>
              ) : null}
              {loadItems.length > 0 ? (
                <div className="rounded-lg border border-border/60 bg-muted/30 p-2">
                  <div className="mb-1 text-[10px] uppercase tracking-wide text-muted-foreground">Load</div>
                  <CompactKVRow items={loadItems} />
                </div>
              ) : null}
            </div>
          )}

          {blocks.length > 0 && (
            <div className="space-y-2">
              {blocks.map((block, blockIdx) => {
                const title = block.title;
                const type = title?.type || 'media';
                const name = title?.name || '';
                const flags = title?.flags || [];

                return (
                  <div key={`${block.prefix}-${blockIdx}`} className="rounded-lg border border-border/60 bg-muted/20 p-2">
                    <div className="flex items-center justify-between gap-2">
                      <div className="flex items-center gap-2 min-w-0">
                        <Pill tone="strong">{block.prefix ? block.prefix : 'P'}</Pill>
                        <Pill tone="strong">{type}</Pill>
                        <div className="truncate text-[11px] text-foreground font-mono">{name}</div>
                      </div>
                      {flags.length > 0 ? (
                        <div className="flex gap-1">
                          {flags.slice(0, 3).map((f) => (
                            <span
                              key={f}
                              className="inline-flex items-center rounded-md border border-border/60 bg-muted/30 px-1.5 py-0.5 text-[10px] text-muted-foreground"
                            >
                              {f}
                            </span>
                          ))}
                          {flags.length > 3 ? (
                            <span className="text-[10px] text-muted-foreground">+{flags.length - 3}</span>
                          ) : null}
                        </div>
                      ) : null}
                    </div>

                    <div className="mt-2 space-y-2">
                      {block.rows.map((row, rowIdx) => (
                        <div key={rowIdx} className="rounded-md border border-border/60 bg-background/40 p-2">
                          <KVGrid items={row} />
                        </div>
                      ))}
                    </div>
                  </div>
                );
              })}
            </div>
          )}
        </div>
      </div>
    </div>
  );
}
