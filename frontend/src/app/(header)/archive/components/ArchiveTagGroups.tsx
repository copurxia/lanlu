'use client';

import type { ReactNode } from 'react';

type ArchiveTagGroupsProps = {
  tags: string[];
  renderTag: (tag: string) => ReactNode;
};

export function ArchiveTagGroups({ tags, renderTag }: ArchiveTagGroupsProps) {
  const groups: Record<string, string[]> = {};

  for (const tag of tags) {
    const idx = tag.indexOf(':');
    const ns = idx > 0 ? tag.slice(0, idx).trim().toLowerCase() : 'tags';
    if (!groups[ns]) groups[ns] = [];
    groups[ns].push(tag);
  }

  const order = Object.keys(groups).sort((a, b) => a.localeCompare(b));

  if (order.length === 0) return null;

  return (
    <div className="grid gap-5">
      {order.map((ns) => (
        <div key={ns}>
          <h3 className="mb-2 text-xs font-medium text-foreground capitalize">
            {ns}
          </h3>
          <div className="flex flex-wrap gap-2">{groups[ns].map(renderTag)}</div>
        </div>
      ))}
    </div>
  );
}
