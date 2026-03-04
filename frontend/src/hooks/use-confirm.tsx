'use client';

import * as React from 'react';
import { ConfirmDialog } from '@/components/ui/confirm-dialog';

type SimpleConfirmOptions = {
  title: string;
  description: string;
  confirmText?: string;
  cancelText?: string;
  variant?: 'default' | 'destructive';
};

export const useConfirm = () => {
  const [confirmState, setConfirmState] = React.useState<{
    options: SimpleConfirmOptions | null;
    resolve: ((value: boolean) => void) | null;
  }>({
    options: null,
    resolve: null,
  });

  const confirmStateRef = React.useRef(confirmState);
  React.useEffect(() => {
    confirmStateRef.current = confirmState;
  }, [confirmState]);

  const confirm = React.useCallback((options: SimpleConfirmOptions): Promise<boolean> => {
    return new Promise((resolve) => {
      setConfirmState({ options, resolve });
    });
  }, []);

  const handleClose = React.useCallback(() => {
    setConfirmState({ options: null, resolve: null });
  }, []);

  const handleConfirm = React.useCallback(async () => {
    if (confirmStateRef.current.resolve) {
      confirmStateRef.current.resolve(true);
    }
    handleClose();
  }, [handleClose]);

  const ConfirmComponent = React.useCallback(() => {
    if (!confirmState.options) return null;

    return (
      <ConfirmDialog
        open={true}
        onOpenChange={(open) => {
          if (!open) {
            // 处理取消：resolve Promise 为 false
            if (confirmStateRef.current.resolve) {
              confirmStateRef.current.resolve(false);
            }
            handleClose();
          }
        }}
        title={confirmState.options.title}
        description={confirmState.options.description}
        confirmText={confirmState.options.confirmText}
        cancelText={confirmState.options.cancelText}
        variant={confirmState.options.variant}
        onConfirm={handleConfirm}
      />
    );
  }, [confirmState.options, handleClose, handleConfirm]);

  return {
    confirm,
    ConfirmComponent,
  };
};
