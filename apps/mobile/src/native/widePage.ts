import {NativeModules, Platform} from 'react-native';

export type WidePageMode = 'off' | 'split' | 'rotate';

export type WidePageResult = {
  wide: boolean;
  mode: WidePageMode;
  urls: string[];
  width: number;
  height: number;
  sourceWidth: number;
  sourceHeight: number;
};

type NativeWidePageModule = {
  createWidePageImages?: (
    uri: string,
    headers: Record<string, string> | undefined,
    mode: WidePageMode,
    invert: boolean,
  ) => Promise<WidePageResult>;
};

const nativeModule = NativeModules.LanluMediaProxy as NativeWidePageModule | undefined;
const cache = new Map<string, Promise<WidePageResult | null>>();

export function isWidePage(width: number, height: number): boolean {
  return width > height;
}

/** True when the right half should be shown on the left. */
export function shouldReverseWideHalves(isRtl: boolean, invert: boolean): boolean {
  return isRtl !== invert;
}

export function orderWideHalves<T>(halves: readonly T[], reversed: boolean): T[] {
  const ordered = [...halves];
  return reversed ? ordered.reverse() : ordered;
}

/**
 * Asks the native layer to split or rotate a wide page. Results are cached per
 * source/mode so scrolling back and forth does not repeat the work.
 */
export function getWidePageImages(
  uri: string,
  headers: Record<string, string> | undefined,
  mode: WidePageMode,
  invert: boolean,
): Promise<WidePageResult | null> {
  if (Platform.OS !== 'android' || mode === 'off' || !nativeModule?.createWidePageImages) {
    return Promise.resolve(null);
  }
  const key = `${mode}|${invert}|${uri}|${JSON.stringify(headers || {})}`;
  const existing = cache.get(key);
  if (existing) return existing;

  const request = nativeModule
    .createWidePageImages(uri, headers, mode, invert)
    .then(result => {
      if (!result || !result.wide) {
        // Keep a non-wide probe cached as well, it is cheap and avoids re-downloading.
        return result;
      }
      return result;
    })
    .catch(error => {
      cache.delete(key);
      throw error;
    });
  cache.set(key, request);
  return request;
}

export function clearWidePageCache(): void {
  cache.clear();
}
