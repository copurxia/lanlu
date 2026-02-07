export const NAV_HISTORY_KEYS = {
  current: 'lanlu:navigation:current',
  last: 'lanlu:navigation:last',
};

export function getStoredPath(key: keyof typeof NAV_HISTORY_KEYS): string | null {
  if (typeof window === 'undefined') return null;
  const value = sessionStorage.getItem(NAV_HISTORY_KEYS[key]);
  if (!value || !value.startsWith('/')) return null;
  return value;
}

export function updateNavigationHistory(currentPath: string): void {
  if (typeof window === 'undefined') return;
  const prev = sessionStorage.getItem(NAV_HISTORY_KEYS.current);
  if (prev && prev !== currentPath && prev.startsWith('/')) {
    sessionStorage.setItem(NAV_HISTORY_KEYS.last, prev);
  }
  sessionStorage.setItem(NAV_HISTORY_KEYS.current, currentPath);
}
