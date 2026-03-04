'use client';

import { useState, useCallback, useRef } from 'react';
import { useToast } from './use-toast';

/**
 * 通用数据获取选项
 */
export interface DataFetchOptions<T> {
  onSuccess?: (data: T) => void;
  onError?: (error: string) => void;
  showSuccessMessage?: string;
  showErrorMessage?: string;
  silent?: boolean;
  debounceMs?: number;
  transform?: (data: any) => T;
}

/**
 * 提取错误信息的工具函数
 */
function extractErrorMessage(err: unknown, defaultMessage: string = '操作失败'): string {
  if (err instanceof Error) return err.message;
  if (typeof err === 'string') return err;
  if (err && typeof err === 'object') {
    const e = err as any;
    return e.message || e.response?.data?.message || defaultMessage;
  }
  return defaultMessage;
}

/**
 * 通用数据获取 Hook - 基础版本
 * 统一处理加载状态、错误处理和成功回调
 */
export function useDataFetch<T = any>(options: DataFetchOptions<T> = {}) {
  const [data, setData] = useState<T | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const { success: showSuccess, error: showError } = useToast();
  const timeoutRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  const execute = useCallback(async (
    apiCall: () => Promise<T>,
    fetchOptions?: Partial<DataFetchOptions<T>>
  ): Promise<T | null> => {
    const finalOptions = { ...options, ...fetchOptions };
    const { onSuccess, onError, showSuccessMessage, showErrorMessage, silent, debounceMs, transform } = finalOptions;

    // 清除之前的防抖定时器
    if (timeoutRef.current) {
      clearTimeout(timeoutRef.current);
    }

    const run = async (): Promise<T | null> => {
      try {
        if (!silent) setLoading(true);
        setError(null);

        const result = await apiCall();
        const transformedData = transform ? transform(result) : result;
        setData(transformedData);

        if (showSuccessMessage) {
          showSuccess(showSuccessMessage);
        } else if (onSuccess) {
          onSuccess(transformedData);
        }

        return transformedData;
      } catch (err) {
        const errorMessage = extractErrorMessage(err);
        setError(errorMessage);

        if (showErrorMessage) {
          showError(showErrorMessage);
        } else if (onError) {
          onError(errorMessage);
        } else {
          showError(errorMessage);
        }

        return null;
      } finally {
        if (!silent) setLoading(false);
      }
    };

    if (debounceMs && debounceMs > 0) {
      return new Promise((resolve) => {
        timeoutRef.current = setTimeout(async () => {
          resolve(await run());
        }, debounceMs);
      });
    }

    return run();
  }, [options, showSuccess, showError]);

  const reset = useCallback(() => {
    setData(null);
    setLoading(false);
    setError(null);
  }, []);

  return { data, loading, error, execute, reset, setData };
}

/**
 * 列表数据获取 Hook
 * 专门用于获取数组类型的数据
 */
export function useListDataFetch<T = any>(options: DataFetchOptions<T[]> = {}) {
  const { data, loading, error, execute, reset, setData } = useDataFetch<T[]>({
    ...options,
    transform: (result) => {
      const transformed = options.transform ? options.transform(result) : result;
      return Array.isArray(transformed) ? transformed : [];
    }
  });

  return {
    items: data ?? [],
    loading,
    error,
    execute,
    refresh: execute,
    reset,
    setItems: setData,
  };
}

/**
 * 单个数据获取 Hook
 * 专门用于获取单个对象的数据
 */
export function useDetailDataFetch<T = any>(options: DataFetchOptions<T> = {}) {
  const { data, loading, error, execute, reset, setData } = useDataFetch<T>(options);

  return {
    item: data,
    loading,
    error,
    execute,
    reset,
    setItem: setData,
  };
}

// 兼容旧 API 的别名导出
export { useDataFetch as useApiState };
export { useListDataFetch as useListState };
export { useDetailDataFetch as useDetailState };
