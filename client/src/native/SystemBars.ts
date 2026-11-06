import {NativeModules, Platform} from 'react-native';

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
      fetch('http://192.168.0.111:8084/log', {
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
