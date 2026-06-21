'use client';

import { cn } from '@/lib/utils/utils';
import type { ReactNode } from 'react';

type DetailContentGridProps = {
  main: ReactNode;
  side: ReactNode;
  className?: string;
  mainClassName?: string;
  sideClassName?: string;
};

export function DetailContentGrid({
  main,
  side,
  className,
  mainClassName,
  sideClassName,
}: DetailContentGridProps) {
  return (
    <div className={cn('detail-content-grid', className)}>
      <div className={cn('grid gap-7', mainClassName)}>{main}</div>
      <aside
        className={cn(
          'grid gap-6 content-start',
          'lg:sticky lg:top-[calc(var(--app-header-height)+1rem)]',
          sideClassName
        )}
      >
        {side}
      </aside>
    </div>
  );
}
