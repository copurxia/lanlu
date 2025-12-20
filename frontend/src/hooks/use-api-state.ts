'use client';

import { useState, useCallback, useRef } from 'react';
import { useToast } from './use-toast';

interface ApiState<T> {
  data: T | null;
  loading: boolean;
  error: string | null;
}

interface UseApiStateOptions {
  onError?: (error: string) => void;
  onSuccess?: (data: any) => void;
  debounceMs?: number;
  transform?: (data: any) => any;
}

export function useApiState<T = any>({
  onError,
  onSuccess,
  debounceMs = 0,
  transform
}: UseApiStateOptions = {}) {
  const [state, setState] = useState<ApiState<T>>({
    data: null,
    loading: false,
    error: null
  });

  const { error: showError, success: showSuccess } = useToast();
  const timeoutRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  const execute = useCallback(async <R>(
    apiCall: () => Promise<R>,
    options?: {
      showSuccessMessage?: string;
      showErrorMessage?: string;
      transform?: (data: R) => T;
    }
  ): Promise<R | null> => {
    // 清除之前的定时器
    if (timeoutRef.current) {
      clearTimeout(timeoutRef.current);
    }

    return new Promise((resolve) => {
      // 防抖延迟
      const run = async () => {
        try {
          setState(prev => ({ ...prev, loading: true, error: null }));
          const result = await apiCall();
          const transformedData = options?.transform
            ? options.transform(result)
            : transform
            ? transform(result)
            : (result as unknown as T);

          setState({
            data: transformedData,
            loading: false,
            error: null
          });

          if (options?.showSuccessMessage) {
            showSuccess(options.showSuccessMessage);
          } else if (onSuccess) {
            onSuccess(result);
          }

          resolve(result);
        } catch (err: any) {
          const errorMessage = err?.message || err?.response?.data?.message || '操作失败';

          setState(prev => ({
            ...prev,
            loading: false,
            error: errorMessage
          }));

          if (options?.showErrorMessage) {
            showError(options.showErrorMessage);
          } else if (onError) {
            onError(errorMessage);
          } else {
            showError(errorMessage);
          }

          resolve(null);
        }
      };

      if (debounceMs > 0) {
        timeoutRef.current = setTimeout(run, debounceMs);
      } else {
        run();
      }
    });
  }, [showError, showSuccess, onError, onSuccess, debounceMs]);

  const reset = useCallback(() => {
    setState({
      data: null,
      loading: false,
      error: null
    });
  }, []);

  return {
    ...state,
    execute,
    reset
  };
}

// 专用Hook：用于列表数据加载
export function useListState<T = any>(options?: UseApiStateOptions) {
  const [items, setItems] = useState<T[]>([]);
  const apiState = useApiState<T[]>({
    ...options,
    transform: (data) => {
      if (Array.isArray(data)) {
        setItems(data);
      }
      return data;
    }
  });

  const refresh = useCallback(async <R>(
    apiCall: () => Promise<R>,
    options?: {
      showSuccessMessage?: string;
      showErrorMessage?: string;
    }
  ) => {
    return apiState.execute(apiCall, options);
  }, [apiState]);

  return {
    ...apiState,
    items,
    setItems,
    refresh
  };
}

// 专用Hook：用于单个数据加载
export function useDetailState<T = any>(options?: UseApiStateOptions) {
  const [item, setItem] = useState<T | null>(null);
  const apiState = useApiState<T>({
    ...options,
    transform: (data) => {
      setItem(data);
      return data;
    }
  });

  const load = useCallback(async <R>(
    apiCall: () => Promise<R>,
    options?: {
      showSuccessMessage?: string;
      showErrorMessage?: string;
    }
  ) => {
    return apiState.execute(apiCall, options);
  }, [apiState]);

  return {
    ...apiState,
    item,
    setItem,
    load
  };
}
