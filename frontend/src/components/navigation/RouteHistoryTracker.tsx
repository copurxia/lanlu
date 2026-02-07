'use client';

import { useEffect } from 'react';
import { usePathname } from 'next/navigation';
import { updateNavigationHistory } from '@/lib/utils/navigation';

export function RouteHistoryTracker() {
  const pathname = usePathname();

  useEffect(() => {
    if (!pathname) return;
    const search = typeof window !== 'undefined' ? window.location.search : '';
    const currentPath = search ? `${pathname}${search}` : pathname;
    updateNavigationHistory(currentPath);
  }, [pathname]);

  return null;
}
