'use client';

export type ConfirmOptions = {
  title: string;
  description: string;
  confirmText?: string;
  cancelText?: string;
  variant?: 'default' | 'destructive';
};

export type ConfirmHandler = (options: ConfirmOptions) => Promise<boolean>;

let confirmHandler: ConfirmHandler | null = null;

export function setConfirmHandler(handler: ConfirmHandler | null) {
  confirmHandler = handler;
}

export function getConfirmHandler() {
  return confirmHandler;
}
