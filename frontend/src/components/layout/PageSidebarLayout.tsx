'use client';

import type { ReactNode } from 'react';
import { MobileBottomNav } from '@/components/layout/MobileBottomNav';
import { cn } from '@/lib/utils/utils';

interface PageSidebarLayoutProps {
  sidebar: ReactNode;
  children: ReactNode;
  sidebarClassName?: string;
  mainClassName?: string;
  contentClassName?: string;
}

export function PageSidebarLayout({
  sidebar,
  children,
  sidebarClassName,
  mainClassName,
  contentClassName,
}: PageSidebarLayoutProps) {
  return (
    <div className="bg-background h-[calc(100dvh-var(--app-header-height,4rem))] overflow-hidden">
      <div className="flex h-full min-h-0">
        <aside
          className={cn(
            'hidden lg:block flex-shrink-0 border-r border-border w-72 min-h-0 pt-4',
            sidebarClassName
          )}
        >
          {sidebar}
        </aside>

        <main
          className={cn(
            'flex-1 min-w-0 min-h-0 overflow-y-auto pb-[calc(env(safe-area-inset-bottom)+3.75rem)] lg:pb-2',
            mainClassName
          )}
        >
          <div className={cn('px-4 pt-4 pb-2', contentClassName)}>{children}</div>
        </main>
      </div>

      <MobileBottomNav />
    </div>
  );
}
