import type {StateStorage} from 'zustand/middleware';
import {getStoredStringSync, removeStoredValueSync, setStoredStringSync} from './mmkv';

export function createMmkvStorage(scope: string): StateStorage {
  return {
    getItem(key: string): string | null {
      return getStoredStringSync(`${scope}:${key}`);
    },
    setItem(key: string, value: string): void {
      setStoredStringSync(`${scope}:${key}`, value);
    },
    removeItem(key: string): void {
      removeStoredValueSync(`${scope}:${key}`);
    },
  };
}
