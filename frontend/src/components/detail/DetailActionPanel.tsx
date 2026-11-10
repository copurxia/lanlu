'use client';

import Link from 'next/link';
import { Button } from '@/components/ui/button';
import { cn } from '@/lib/utils/utils';
import type { ReactNode } from 'react';

export type DetailAction = {
  id: string;
  icon?: ReactNode;
  title: string;
  onClick?: () => void;
  disabled?: boolean;
  destructive?: boolean;
  className?: string;
  dialog?: ReactNode;
};

type DetailActionPanelProps = {
  primary: {
    label: ReactNode;
    icon?: ReactNode;
    onClick?: () => void;
    href?: string;
    disabled?: boolean;
    className?: string;
  };
  actions: DetailAction[];
  className?: string;
};

export function DetailActionPanel({
  primary,
  actions,
  className,
}: DetailActionPanelProps) {
  const primaryButton = (
    <Button
      size="sm"
      className={cn('h-10 w-full gap-2 rounded-xl font-semibold', primary.className)}
      disabled={primary.disabled}
      onClick={primary.onClick}
    >
      {primary.icon}
      {primary.label}
    </Button>
  );

  return (
    <div
      className={cn(
        'glass-card p-3.5',
        'flex flex-col gap-2.5',
        className
      )}
    >
      {primary.href ? (
        <Link href={primary.href} className="w-full">
          {primaryButton}
        </Link>
      ) : (
        primaryButton
      )}

      <div className="grid grid-cols-4 gap-2">
        {actions.map((action) =>
          action.dialog ? (
            <div key={action.id} className="contents">
              {action.dialog}
            </div>
          ) : (
            <Button
              key={action.id}
              type="button"
              variant="outline"
              size="icon"
              className={cn(
                'h-10 w-full rounded-xl',
                action.destructive && 'text-destructive hover:text-destructive',
                action.className
              )}
              title={action.title}
              disabled={action.disabled}
              onClick={action.onClick}
            >
              {action.icon}
            </Button>
          )
        )}
      </div>
    </div>
  );
}
