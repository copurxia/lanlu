import {NativeModules, Platform, UIManager} from 'react-native';

type GlobalErrorUtils = {
  getGlobalHandler?: () => (error: unknown, isFatal?: boolean) => void;
  setGlobalHandler: (handler: (error: unknown, isFatal?: boolean) => void) => void;
};

const ENDPOINT = 'http://192.168.0.111:8084/log';
let installed = false;

/** Report which native capabilities are actually reachable from JS.
 *  Under bridgeless, a legacy ReactPackage is invisible unless
 *  useTurboModuleInterop is enabled, so a missing method here is a real bug. */
function reportNativeCapabilities(): void {
  try {
    const proxy = NativeModules.LanluMediaProxy as
      | Record<string, unknown>
      | undefined;
    const ui = UIManager as typeof UIManager & {
      hasViewManagerConfig?: (name: string) => boolean;
    };
    const method = (name: string) => typeof proxy?.[name] === 'function';
    reportDebug('native.capabilities', {
      platform: Platform.OS,
      bridgeless: Boolean((globalThis as {__turboModuleProxy?: unknown}).__turboModuleProxy),
      proxyModule: Boolean(proxy),
      createUrl: method('createUrl'),
      createPageUrl: method('createPageUrl'),
      setSystemBarTheme: method('setSystemBarTheme'),
      setSystemBarsHidden: method('setSystemBarsHidden'),
      setKeepScreenOn: method('setKeepScreenOn'),
      prefetchImage: method('prefetchImage'),
      createWidePageImages: method('createWidePageImages'),
      hasLongImageView:
        typeof ui.hasViewManagerConfig === 'function'
          ? ui.hasViewManagerConfig('LanluLongImage')
          : null,
      hasColorFilterView:
        typeof ui.hasViewManagerConfig === 'function'
          ? ui.hasViewManagerConfig('LanluColorFilterView')
          : null,
    });
  } catch {
    // Capability probing must never affect startup.
  }
}

/** Debug-only structured log line for device verification without adb. */
export function reportDebug(message: string, data: Record<string, unknown> = {}): void {
  if (!__DEV__) return;
  try {
    fetch(ENDPOINT, {
      method: 'POST',
      headers: {'Content-Type': 'application/json'},
      body: JSON.stringify({message, at: new Date().toISOString(), ...data}),
    }).catch(() => undefined);
  } catch {
    // Diagnostics must never affect the app.
  }
}

/**
 * Debug-only bridge: forwards JS fatal/non-fatal errors to the LAN log server
 * so they can be inspected without adb. It never changes the crash behavior.
 */
export function installErrorBridge(): void {
  if (!__DEV__ || installed) return;
  const errorUtils = (globalThis as unknown as {ErrorUtils?: GlobalErrorUtils}).ErrorUtils;
  if (!errorUtils || typeof errorUtils.setGlobalHandler !== 'function') return;
  installed = true;
  reportDebug('app.js.start');
  reportNativeCapabilities();
  const previous = errorUtils.getGlobalHandler?.();
  errorUtils.setGlobalHandler((error, isFatal) => {
    try {
      const value = error as {message?: unknown; stack?: unknown};
      const payload = {
        at: new Date().toISOString(),
        fatal: Boolean(isFatal),
        platform: Platform.OS,
        message: String(value?.message ?? error),
        stack: String(value?.stack ?? ''),
      };
      fetch(ENDPOINT, {
        method: 'POST',
        headers: {'Content-Type': 'application/json'},
        body: JSON.stringify(payload),
      }).catch(() => undefined);
    } catch {
      // Reporting must never mask the original error.
    }
    previous?.(error, isFatal);
  });
}
