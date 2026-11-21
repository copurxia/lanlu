import AsyncStorage from '@react-native-async-storage/async-storage';
import {createMMKV} from 'react-native-mmkv';

const storage = createMMKV({id: 'lanlu.client.storage.v1'});

export function getStoredStringSync(key: string): string | null {
  return storage.getString(key) ?? null;
}

export async function getStoredString(key: string): Promise<string | null> {
  const value = getStoredStringSync(key);
  if (value !== null) {
    return value;
  }

  const legacyValue = await AsyncStorage.getItem(key);
  if (legacyValue !== null) {
    storage.set(key, legacyValue);
    AsyncStorage.removeItem(key).catch(() => undefined);
  }
  return legacyValue;
}

export function setStoredStringSync(key: string, value: string): void {
  storage.set(key, value);
  AsyncStorage.removeItem(key).catch(() => undefined);
}

export async function setStoredString(key: string, value: string): Promise<void> {
  setStoredStringSync(key, value);
}

export function removeStoredValueSync(key: string): void {
  storage.remove(key);
  AsyncStorage.removeItem(key).catch(() => undefined);
}

export async function removeStoredValue(key: string): Promise<void> {
  removeStoredValueSync(key);
}

export async function getStoredStrings(keys: string[]): Promise<Array<[string, string | null]>> {
  return Promise.all(keys.map(async key => [key, await getStoredString(key)]));
}

export async function setStoredStrings(entries: Array<[string, string]>): Promise<void> {
  entries.forEach(([key, value]) => storage.set(key, value));
  AsyncStorage.multiRemove(entries.map(([key]) => key)).catch(() => undefined);
}
