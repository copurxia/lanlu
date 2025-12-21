'use client';

import { useState, useEffect, useCallback, useMemo, useRef } from 'react';

/**
 * 常用 React Hooks 的统一导出
 * 避免在多个文件中重复导入相同的 hooks
 */

// 重新导出常用的 React hooks
export { useState, useEffect, useCallback, useMemo, useRef };

/**
 * 统一管理本地存储的 Hook
 */
export function useLocalStorage<T>(key: string, initialValue: T) {
  const [storedValue, setStoredValue] = useState<T>(() => {
    try {
      const item = window.localStorage.getItem(key);
      return item ? JSON.parse(item) : initialValue;
    } catch (error) {
      console.warn(`Failed to read ${key} from localStorage:`, error);
      return initialValue;
    }
  });

  const setValue = useCallback((value: T | ((val: T) => T)) => {
    try {
      const valueToStore = value instanceof Function ? value(storedValue) : value;
      setStoredValue(valueToStore);
      window.localStorage.setItem(key, JSON.stringify(valueToStore));
    } catch (error) {
      console.warn(`Failed to save ${key} to localStorage:`, error);
    }
  }, [key, storedValue]);

  return [storedValue, setValue] as const;
}

/**
 * 防抖 Hook
 */
export function useDebounce<T>(value: T, delay: number): T {
  const [debouncedValue, setDebouncedValue] = useState<T>(value);

  useEffect(() => {
    const handler = setTimeout(() => {
      setDebouncedValue(value);
    }, delay);

    return () => {
      clearTimeout(handler);
    };
  }, [value, delay]);

  return debouncedValue;
}

/**
 * 切换状态 Hook
 */
export function useToggle(initialValue: boolean = false) {
  const [value, setValue] = useState(initialValue);
  const toggle = useCallback(() => setValue(v => !v), []);
  return [value, toggle] as const;
}

/**
 * 异步操作状态管理 Hook
 */
export function useAsync<T, E = string>(
  asyncFunction: () => Promise<T>,
  immediate: boolean = true
) {
  const [status, setStatus] = useState<'idle' | 'pending' | 'success' | 'error'>('idle');
  const [data, setData] = useState<T | null>(null);
  const [error, setError] = useState<E | null>(null);

  const execute = useCallback(async () => {
    setStatus('pending');
    setData(null);
    setError(null);

    try {
      const response = await asyncFunction();
      setData(response);
      setStatus('success');
      return response;
    } catch (error) {
      setError(error as E);
      setStatus('error');
      throw error;
    }
  }, [asyncFunction]);

  useEffect(() => {
    if (immediate) {
      const executeAsync = async () => {
        await execute();
      };
      executeAsync();
    }
  }, [execute, immediate]);

  return { execute, status, data, error };
}

/**
 * 数组操作 Hook
 */
export function useArray<T>(initialValue: T[] = []) {
  const [array, setArray] = useState<T[]>(initialValue);

  const add = useCallback((item: T) => {
    setArray(prev => [...prev, item]);
  }, []);

  const removeIndex = useCallback((index: number) => {
    setArray(prev => prev.filter((_, i) => i !== index));
  }, []);

  const remove = useCallback((item: T) => {
    setArray(prev => prev.filter(i => i !== item));
  }, []);

  const clear = useCallback(() => {
    setArray([]);
  }, []);

  const update = useCallback((index: number, item: T) => {
    setArray(prev => prev.map((i, iIndex) => (iIndex === index ? item : i)));
  }, []);

  return { array, add, remove, removeIndex, clear, update };
}

/**
 * 表单状态管理 Hook
 */
export function useForm<T extends Record<string, any>>(initialValues: T) {
  const [values, setValues] = useState<T>(initialValues);
  const [errors, setErrors] = useState<Partial<Record<keyof T, string>>>({});
  const [touched, setTouchedState] = useState<Partial<Record<keyof T, boolean>>>({});

  const setValue = useCallback((name: keyof T, value: any) => {
    setValues(prev => ({ ...prev, [name]: value }));
  }, []);

  const setError = useCallback((name: keyof T, error: string) => {
    setErrors(prev => ({ ...prev, [name]: error }));
  }, []);

  const setTouched = useCallback((name: keyof T, isTouched: boolean = true) => {
    setTouchedState(prev => ({ ...prev, [name]: isTouched }));
  }, []);

  const reset = useCallback(() => {
    setValues(initialValues);
    setErrors({});
    setTouchedState({});
  }, [initialValues]);

  const handleChange = useCallback((e: React.ChangeEvent<HTMLInputElement | HTMLTextAreaElement | HTMLSelectElement>) => {
    const { name, value } = e.target;
    setValue(name as keyof T, value);
  }, [setValue]);

  return {
    values,
    errors,
    touched,
    setValue,
    setError,
    setTouched,
    reset,
    handleChange,
  };
}

/**
 * 窗口大小 Hook
 */
export function useWindowSize() {
  const [windowSize, setWindowSize] = useState({
    width: typeof window !== 'undefined' ? window.innerWidth : 0,
    height: typeof window !== 'undefined' ? window.innerHeight : 0,
  });

  useEffect(() => {
    function handleResize() {
      setWindowSize({
        width: window.innerWidth,
        height: window.innerHeight,
      });
    }

    window.addEventListener('resize', handleResize);
    return () => window.removeEventListener('resize', handleResize);
  }, []);

  return windowSize;
}

/**
 * 响应式断点 Hook（扩展版支持3xl/4xl/5xl）
 */
export function useBreakpoint() {
  const { width } = useWindowSize();

  const breakpoint = useMemo(() => {
    if (width < 640) return 'sm';
    if (width < 768) return 'md';
    if (width < 1024) return 'lg';
    if (width < 1280) return 'xl';
    if (width < 1400) return '2xl';
    if (width < 1920) return '3xl';
    if (width < 2560) return '4xl';
    return '5xl';
  }, [width]);

  return breakpoint;
}

/**
 * 获取当前断点对应的网格列数
 * 与 ArchiveGrid 的 gridClasses 保持一致
 */
export function useGridColumnCount() {
  const { width } = useWindowSize();

  const columnCount = useMemo(() => {
    // 对应 grid-cols-2 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-5 xl:grid-cols-6 2xl:grid-cols-6 3xl:grid-cols-7 4xl:grid-cols-8 5xl:grid-cols-9
    if (width < 640) return 2;   // default (xs)
    if (width < 768) return 3;   // sm
    if (width < 1024) return 4;  // md
    if (width < 1280) return 5;  // lg
    if (width < 1400) return 6;  // xl
    if (width < 1920) return 6;  // 2xl
    if (width < 2560) return 7;  // 3xl
    if (width < 3200) return 8;  // 4xl
    return 9;                     // 5xl
  }, [width]);

  return columnCount;
}
