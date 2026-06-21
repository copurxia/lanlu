'use client';

import { cn } from '@/lib/utils/utils';
import type { ReactNode } from 'react';

export type DetailInfoItem = {
  label: ReactNode;
  value: ReactNode;
  title?: string;
};

type DetailInfoListProps = {
  items: DetailInfoItem[];
  className?: string;
};

export function DetailInfoList({ items, className }: DetailInfoListProps) {
  return (
    <dl className={cn('grid gap-3 text-sm', className)}>
      {items.map((item, index) => (
        <div
          key={index}
          className="flex items-start justify-between gap-4 pb-3 border-b border-border/50 last:border-0 last:pb-0"
          title={item.title}
        >
          <dt className="text-muted-foreground whitespace-nowrap shrink-0">{item.label}</dt>
          <dd className="text-right break-words">{item.value}</dd>
        </div>
      ))}
    </dl>
  );
}
