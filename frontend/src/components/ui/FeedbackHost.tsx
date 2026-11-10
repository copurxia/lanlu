'use client';

import * as React from 'react';
import { Toaster } from 'sonner';
import { useConfirm } from '@/hooks/use-confirm';
import { setConfirmHandler } from '@/lib/ui/feedback-runtime';

export function FeedbackHost({
  onReady,
}: {
  onReady?: () => void;
}) {
  const { confirm, ConfirmComponent } = useConfirm();

  React.useEffect(() => {
    setConfirmHandler(confirm);
    return () => {
      setConfirmHandler(null);
    };
  }, [confirm]);

  React.useEffect(() => {
    onReady?.();
  }, [onReady]);

  return (
    <>
      <ConfirmComponent />
      <Toaster position="top-center" richColors />
    </>
  );
}
