import { toast, type ToastId, type ToastOptions, type ToastPromiseMessages } from '@/lib/ui/feedback';

export const useToast = () => {
  const success = (message: string, options?: ToastOptions) => {
    toast.success(message, options);
  };

  const error = (message: string, options?: ToastOptions) => {
    toast.error(message, options);
  };

  const info = (message: string, options?: ToastOptions) => {
    toast.info(message, options);
  };

  const warning = (message: string, options?: ToastOptions) => {
    toast.warning(message, options);
  };

  const loading = (message: string, options?: ToastOptions): ToastId => {
    return toast.loading(message, options);
  };

  const dismiss = (toastId?: ToastId) => {
    toast.dismiss(toastId);
  };

  const promise = <T,>(
    pendingPromise: Promise<T>,
    messages: ToastPromiseMessages<T>,
    options?: ToastOptions
  ) => {
    toast.promise(pendingPromise, messages, options);
  };

  return {
    toast,
    success,
    error,
    info,
    warning,
    loading,
    dismiss,
    promise,
  };
};
