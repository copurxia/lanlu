'use client';

import { useCallback, useMemo, useRef, useState } from 'react';
import { StepUpDialog } from '@/components/auth/StepUpDialog';

export function useStepUpDialog() {
  const [open, setOpen] = useState(false);
  const resolverRef = useRef<((verified: boolean) => void) | null>(null);

  const closeWithResult = useCallback((verified: boolean) => {
    setOpen(false);
    const resolver = resolverRef.current;
    resolverRef.current = null;
    resolver?.(verified);
  }, []);

  const requestStepUp = useCallback(() => {
    return new Promise<boolean>((resolve) => {
      resolverRef.current = resolve;
      setOpen(true);
    });
  }, []);

  const dialog = useMemo(() => (
    <StepUpDialog
      open={open}
      onOpenChange={(nextOpen) => {
        if (!nextOpen) {
          closeWithResult(false);
          return;
        }
        setOpen(true);
      }}
      onVerified={() => closeWithResult(true)}
    />
  ), [closeWithResult, open]);

  return {
    requestStepUp,
    stepUpDialog: dialog,
  };
}
