import {Platform} from 'react-native';

type GlobalErrorUtils = {
  getGlobalHandler?: () => (error: unknown, isFatal?: boolean) => void;
  setGlobalHandler: (handler: (error: unknown, isFatal?: boolean) => void) => void;
};

const ENDPOINT = 'http://192.168.0.111:8084/log';
let installed = false;

/**
 * Debug-only bridge: forwards JS fatal/non-fatal errors to the LAN log server
 * so they can be inspected without adb. It never changes the crash behavior.
 */
export function installErrorBridge(): void {
  if (!__DEV__ || installed) return;
  const errorUtils = (globalThis as unknown as {ErrorUtils?: GlobalErrorUtils}).ErrorUtils;
  if (!errorUtils || typeof errorUtils.setGlobalHandler !== 'function') return;
  installed = true;
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
