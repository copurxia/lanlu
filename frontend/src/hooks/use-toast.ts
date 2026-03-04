import { toast } from 'sonner';

export const useToast = () => {
  const success = (message: string, options?: any) => {
    toast.success(message, options);
  };

  const error = (message: string, options?: any) => {
    toast.error(message, options);
  };

  const info = (message: string, options?: any) => {
    toast.info(message, options);
  };

  const warning = (message: string, options?: any) => {
    toast.warning(message, options);
  };

  const loading = (message: string, options?: any) => {
    return toast.loading(message, options);
  };

  const dismiss = (toastId?: string | number) => {
    toast.dismiss(toastId);
  };

  const promise = (promise: Promise<any>, messages: {
    loading: string;
    success: string | ((data: any) => string);
    error: string | ((error: any) => string);
  }) => {
    toast.promise(promise, messages);
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
