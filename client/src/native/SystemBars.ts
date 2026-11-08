import {NativeModules, Platform} from 'react-native';

import {debugEndpoint} from '../debug/errorBridge';

type SystemBarsModule = {
  setSystemBarTheme?: (backgroundColor: string, lightIcons: boolean) => void;
};

/** Set system bar colors immediately; theme resources alone do not repaint an existing window. */
let lastReport = '';

export function setSystemBarTheme(backgroundColor: string, lightIcons: boolean) {
  if (Platform.OS !== 'android') return;
  const module = NativeModules.LanluMediaProxy as SystemBarsModule | undefined;
  const hasMethod = typeof module?.setSystemBarTheme === 'function';
  if (__DEV__) {
    const key = `${backgroundColor}:${lightIcons}:${hasMethod}`;
    if (key !== lastReport) {
      lastReport = key;
      fetch(debugEndpoint(), {
        method: 'POST',
        headers: {'Content-Type': 'application/json'},
        body: JSON.stringify({
          message: 'systembar.sync',
          backgroundColor,
          lightIcons,
          nativeMethod: hasMethod,
        }),
      }).catch(() => undefined);
    }
  }
  try {
    module?.setSystemBarTheme?.(backgroundColor, lightIcons);
  } catch {
    // Best-effort: never break theme switching.
  }
}
