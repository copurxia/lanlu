'use client';

import type { ConfirmOptions } from '@/lib/ui/feedback-runtime';
import { getConfirmHandler } from '@/lib/ui/feedback-runtime';

type ToastId = string | number;
type ToastOptions = { id?: ToastId; [key: string]: unknown };

const FEEDBACK_HOST_ID = 'lanlu-feedback-host';

let hostReady = false;
let hostPromise: Promise<void> | null = null;
let toastIdCounter = 0;

function nextToastId(): ToastId {
  toastIdCounter += 1;
  return `lanlu-toast-${toastIdCounter}`;
}

async function ensureFeedbackHost(): Promise<void> {
  if (typeof window === 'undefined') {
    return;
  }
  if (hostReady) {
    return;
  }
  if (!hostPromise) {
    hostPromise = (async () => {
      const existing = document.getElementById(FEEDBACK_HOST_ID);
      if (existing?.dataset.ready === 'true') {
        hostReady = true;
        return;
      }

      const [React, { createRoot }, { FeedbackHost }] = await Promise.all([
        import('react'),
        import('react-dom/client'),
        import('@/components/ui/FeedbackHost'),
      ]);

      const container = existing ?? document.createElement('div');
      container.id = FEEDBACK_HOST_ID;
      if (!existing) {
        document.body.appendChild(container);
      }

      await new Promise<void>((resolve) => {
        const root = createRoot(container);
        root.render(
          React.createElement(FeedbackHost, {
            onReady: () => {
              container.dataset.ready = 'true';
              hostReady = true;
              resolve();
            },
          })
        );
      });
    })().catch((error) => {
      hostPromise = null;
      throw error;
    });
  }

  return hostPromise;
}

async function getSonnerToast() {
  await ensureFeedbackHost();
  const { toast } = await import('sonner');
  return toast;
}

function withToastId(options: ToastOptions | undefined, toastId: ToastId): ToastOptions {
  if (options?.id !== undefined) {
    return options;
  }
  return options ? { ...options, id: toastId } : { id: toastId };
}

function scheduleToastCall(
  method: 'success' | 'error' | 'info' | 'warning' | 'loading',
  message: string,
  options?: ToastOptions
): ToastId {
  const toastId = options?.id ?? nextToastId();
  void getSonnerToast().then((sonnerToast) => {
    sonnerToast[method](message, withToastId(options, toastId));
  });
  return toastId;
}

export async function confirm(options: ConfirmOptions): Promise<boolean> {
  if (typeof window === 'undefined') {
    return false;
  }

  try {
    await ensureFeedbackHost();
    const handler = getConfirmHandler();
    if (handler) {
      return handler(options);
    }
  } catch {}

  const fallbackText = [options.title.trim(), options.description.trim()]
    .filter((part) => part.length > 0)
    .join('\n\n');
  return window.confirm(fallbackText);
}

export const toast = {
  success(message: string, options?: ToastOptions) {
    return scheduleToastCall('success', message, options);
  },
  error(message: string, options?: ToastOptions) {
    return scheduleToastCall('error', message, options);
  },
  info(message: string, options?: ToastOptions) {
    return scheduleToastCall('info', message, options);
  },
  warning(message: string, options?: ToastOptions) {
    return scheduleToastCall('warning', message, options);
  },
  loading(message: string, options?: ToastOptions) {
    return scheduleToastCall('loading', message, options);
  },
  dismiss(toastId?: ToastId) {
    void getSonnerToast().then((sonnerToast) => {
      sonnerToast.dismiss(toastId);
    });
  },
  promise<T>(
    promise: Promise<T>,
    messages: {
      loading: string;
      success: string | ((data: T) => string);
      error: string | ((error: unknown) => string);
    },
    options?: ToastOptions
  ): ToastId {
    const toastId = options?.id ?? nextToastId();
    void getSonnerToast().then((sonnerToast) => {
      sonnerToast.promise(promise, messages);
    });
    return toastId;
  },
};
