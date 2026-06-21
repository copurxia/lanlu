'use client';

import { cn } from '@/lib/utils/utils';
import type { ReactNode } from 'react';

type DetailSectionCardProps = {
  title: ReactNode;
  subtitle?: ReactNode;
  children: ReactNode;
  variant?: 'transparent' | 'glass';
  className?: string;
  headerClassName?: string;
  titleClassName?: string;
};

export function DetailSectionCard({
  title,
  subtitle,
  children,
  variant = 'transparent',
  className,
  headerClassName,
  titleClassName,
}: DetailSectionCardProps) {
  const isGlass = variant === 'glass';

  return (
    <article
      className={cn(
        isGlass
          ? 'glass-card'
          : 'border-none bg-transparent shadow-none dark:bg-transparent',
        className
      )}
    >
      <header
        className={cn(
          'flex items-start justify-between gap-3',
          isGlass ? 'mx-4 mt-4 pb-3' : 'pb-3',
          'border-b border-border/50',
          headerClassName
        )}
      >
        <div className="min-w-0">
          <h2
            className={cn(
              'text-base font-semibold tracking-tight lg:text-lg',
              titleClassName
            )}
          >
            {title}
          </h2>
          {subtitle ? (
            <p className="mt-1 text-sm text-muted-foreground">{subtitle}</p>
          ) : null}
        </div>
      </header>
      <div className={cn('pt-4', isGlass && 'px-4 pb-4')}>{children}</div>
    </article>
  );
}
