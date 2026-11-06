import React, { useEffect, useMemo, useRef, useState } from 'react';
import {
  DeviceEventEmitter,
  Platform,
  requireNativeComponent,
  StyleProp,
  UIManager,
  ViewProps,
  ViewStyle,
} from 'react-native';

import { handleLongImageEvent, type LongImageEvent } from './longImageEvents';

type NativeLongImageSource = {
  uri: string;
  headers?: Record<string, string>;
};

type NativeLongImageProps = ViewProps & {
  handle: string;
  ready: boolean;
  cropBorders?: boolean;
  grayscale?: boolean;
  invertColors?: boolean;
  brightness?: number;
  fallbackAspectRatio?: number;
  source: NativeLongImageSource;
  style?: StyleProp<ViewStyle>;
};

export type LanluLongImageProps = {
  uri: string;
  headers?: Record<string, string>;
  cropBorders?: boolean;
  grayscale?: boolean;
  invertColors?: boolean;
  brightness?: number;
  fallbackAspectRatio?: number;
  onSize?: (width: number, height: number) => void;
  onLoadStart?: () => void;
  onLoad?: () => void;
  onProgress?: (loaded: number, total: number) => void;
  onError?: (message?: string) => void;
  style?: StyleProp<ViewStyle>;
};

const EVENT_NAME = 'LanluLongImageEvent';

function resolveNativeViewAvailability(): boolean {
  if (Platform.OS !== 'android') return false;
  try {
    const manager = UIManager as typeof UIManager & {
      hasViewManagerConfig?: (name: string) => boolean;
      getViewManagerConfig?: (name: string) => unknown;
    };
    if (typeof manager.hasViewManagerConfig === 'function') {
      return manager.hasViewManagerConfig('LanluLongImage');
    }
    return Boolean(manager.getViewManagerConfig?.('LanluLongImage'));
  } catch {
    return false;
  }
}

export const isLanluLongImageAvailable = resolveNativeViewAvailability();

let NativeLongImage: React.ComponentType<NativeLongImageProps> | null = null;
if (isLanluLongImageAvailable) {
  try {
    NativeLongImage =
      requireNativeComponent<NativeLongImageProps>('LanluLongImage');
  } catch {
    NativeLongImage = null;
  }
}

let nextHandle = 1;

/**
 * Native strip/region-decoded image view for long webtoon pages. The view
 * downloads the page once, keeps it in a file cache and decodes only the
 * strips that are visible, so a several-thousand-pixel-tall page never becomes
 * a single GPU texture.
 */
export function LanluLongImage({
  uri,
  headers,
  cropBorders = false,
  grayscale = false,
  invertColors = false,
  brightness = 1,
  fallbackAspectRatio = 0.72,
  onSize,
  onLoadStart,
  onLoad,
  onProgress,
  onError,
  style,
}: LanluLongImageProps) {
  const handle = useMemo(() => `lanlu-long-${nextHandle++}`, []);
  const [ready, setReady] = useState(false);
  const callbacks = useRef({
    onSize,
    onLoadStart,
    onLoad,
    onProgress,
    onError,
  });

  useEffect(() => {
    callbacks.current = { onSize, onLoadStart, onLoad, onProgress, onError };
  }, [onError, onLoad, onLoadStart, onProgress, onSize]);

  useEffect(() => {
    const subscription = DeviceEventEmitter.addListener(
      EVENT_NAME,
      (event: LongImageEvent | undefined) => {
        handleLongImageEvent(event, handle, callbacks.current);
      },
    );
    // Only let the native view start loading after the JS listener exists.
    // A cached image can otherwise emit size/load before this effect runs.
    setReady(true);
    return () => {
      setReady(false);
      subscription.remove();
    };
  }, [handle]);

  if (!NativeLongImage) {
    return null;
  }

  const source: NativeLongImageSource =
    headers && Object.keys(headers).length ? { uri, headers } : { uri };

  return (
    <NativeLongImage
      brightness={brightness}
      cropBorders={cropBorders}
      fallbackAspectRatio={fallbackAspectRatio}
      grayscale={grayscale}
      handle={handle}
      invertColors={invertColors}
      ready={ready}
      source={source}
      style={style}
    />
  );
}
