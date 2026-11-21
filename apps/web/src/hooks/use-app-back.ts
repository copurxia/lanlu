'use client';

import { useCallback, useEffect, useState } from 'react';
import { usePathname, useRouter } from 'next/navigation';
import { getStoredPath } from '@/lib/utils/navigation';

export function useAppBack() {
  const router = useRouter();
  const pathname = usePathname();
  const [currentPath, setCurrentPath] = useState(pathname || '/');

  useEffect(() => {
    if (!pathname) return;
    const search = typeof window !== 'undefined' ? window.location.search : '';
    setCurrentPath(search ? `${pathname}${search}` : pathname);
  }, [pathname]);

  return useCallback(
    (fallback: string) => {
      const lastPath = getStoredPath('last');
      if (lastPath && lastPath !== currentPath) {
        router.push(lastPath);
        return;
      }
      router.push(fallback);
    },
    [currentPath, router]
  );
}
