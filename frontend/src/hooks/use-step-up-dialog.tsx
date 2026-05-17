'use client';

import { useCallback, useMemo, useRef, useState } from 'react';
import { StepUpDialog } from '@/components/auth/StepUpDialog';

export function useStepUpDialog() {
  const [open, setOpen] = useState(false);
  const [purpose, setPurpose] = useState<string>('');
  const resolverRef = useRef<((verified: boolean) => void) | null>(null);

  const closeWithResult = useCallback((verified: boolean) => {
    setOpen(false);
    const resolver = resolverRef.current;
    resolverRef.current = null;
    resolver?.(verified);
  }, []);

  const requestStepUp = useCallback((purposeText?: string) => {
    // If a pending step-up exists, resolve it as cancelled before starting a new one
    const staleResolver = resolverRef.current;
    if (staleResolver) {
      resolverRef.current = null;
      staleResolver(false);
    }
    if (purposeText) {
      setPurpose(purposeText);
    }
    return new Promise<boolean>((resolve) => {
      resolverRef.current = resolve;
      setOpen(true);
    });
  }, []);

  const dialog = useMemo(() => (
    <StepUpDialog
      open={open}
      purpose={purpose}
      onOpenChange={(nextOpen) => {
        if (!nextOpen) {
          closeWithResult(false);
          return;
        }
        setOpen(true);
      }}
      onVerified={() => closeWithResult(true)}
    />
  ), [closeWithResult, open, purpose]);

  return {
    requestStepUp,
    stepUpDialog: dialog,
  };
}
