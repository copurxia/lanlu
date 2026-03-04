'use client';

import * as React from 'react';
import { useConfirm } from '@/hooks/use-confirm';

type ConfirmOptions = {
  title: string;
  description: string;
  confirmText?: string;
  cancelText?: string;
  variant?: 'default' | 'destructive';
};

export const ConfirmContext = React.createContext<{
  confirm: (options: ConfirmOptions) => ReturnType<ReturnType<typeof useConfirm>['confirm']>;
} | null>(null);

export function ConfirmProvider({ children }: { children: React.ReactNode }) {
  const { confirm, ConfirmComponent } = useConfirm();

  return (
    <ConfirmContext.Provider value={{ confirm }}>
      {children}
      <ConfirmComponent />
    </ConfirmContext.Provider>
  );
}

export function useConfirmContext() {
  const context = React.useContext(ConfirmContext);
  if (!context) {
    throw new Error('useConfirmContext must be used within a ConfirmProvider');
  }
  return context;
}
