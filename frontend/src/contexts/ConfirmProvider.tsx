'use client';

import * as React from 'react';
import { confirm } from '@/lib/ui/feedback';
export type { ConfirmOptions } from '@/lib/ui/feedback-runtime';

export function ConfirmProvider({ children }: { children: React.ReactNode }) {
  return <>{children}</>;
}

export function useConfirmContext() {
  return React.useMemo(() => ({ confirm }), []);
}
