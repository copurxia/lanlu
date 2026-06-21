'use client';

import { useState } from 'react';
import { ChevronDown, ChevronUp } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { cn } from '@/lib/utils/utils';
import type { ReactNode } from 'react';

type CollapsibleTagRowProps = {
  items: ReactNode[];
  /** Number of tags to show before collapsing. Default 12 */
  limit?: number;
  className?: string;
};

export function CollapsibleTagRow({
  items,
  limit = 12,
  className,
}: CollapsibleTagRowProps) {
  const [expanded, setExpanded] = useState(false);

  if (items.length === 0) return null;

  const needsCollapse = items.length > limit;
  const visible = expanded || !needsCollapse ? items : items.slice(0, limit);
  const hiddenCount = items.length - limit;

  return (
    <div className={cn('flex flex-wrap items-center gap-2', className)}>
      {visible}
      {needsCollapse ? (
        <Button
          type="button"
          variant="ghost"
          size="sm"
          className="h-6 px-2 text-xs text-muted-foreground"
          onClick={() => setExpanded((v) => !v)}
          aria-expanded={expanded}
          title={expanded ? '收起' : `展开 ${hiddenCount} 个`}
        >
          {expanded ? (
            <ChevronUp className="h-3.5 w-3.5" />
          ) : (
            <>
              ...
              <ChevronDown className="h-3.5 w-3.5" />
            </>
          )}
        </Button>
      ) : null}
    </div>
  );
}
