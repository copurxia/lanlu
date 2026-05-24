import {getStoredString, getStoredStringSync, removeStoredValue, setStoredString} from './mmkv';

const DIAGNOSTIC_LOG_KEY = 'lanlu.diagnosticLog.v1';
const DIAGNOSTIC_DEBUG_KEY = 'lanlu.diagnosticDebug';
const MAX_LOG_LINES = 220;

type DiagnosticDetails = Record<string, unknown>;
type DiagnosticLevel = 'info' | 'warn' | 'error';

let debugEnabledCache: boolean | null = null;

export function isDiagnosticDebugEnabled(): boolean {
  if (debugEnabledCache !== null) return debugEnabledCache;
  try {
    debugEnabledCache = getStoredStringSync(DIAGNOSTIC_DEBUG_KEY) === '1';
  } catch {
    debugEnabledCache = false;
  }
  return debugEnabledCache;
}

export function setDiagnosticDebugEnabled(enabled: boolean) {
  debugEnabledCache = enabled;
  setStoredString(DIAGNOSTIC_DEBUG_KEY, enabled ? '1' : '0');
}

function resolveDiagnosticLevel(event: string, level: DiagnosticLevel): DiagnosticLevel {
  if (level !== 'info') return level;
  if (/(^|[.:_-])error($|[.:_-])/i.test(event)) return 'error';
  if (/(^|[.:_-])warn(?:ing)?($|[.:_-])/i.test(event)) return 'warn';
  return level;
}

function sanitizeValue(value: unknown): unknown {
  if (typeof value === 'string') {
    return value
      .replace(/Bearer\s+[A-Za-z0-9._~+/=-]+/gi, 'Bearer [redacted]')
      .replace(/([?&;]auth_token=)[^&;\s]+/gi, '$1[redacted]')
      .replace(/auth_token=[^;\s]+/gi, 'auth_token=[redacted]');
  }
  if (Array.isArray(value)) {
    return value.map(sanitizeValue);
  }
  if (value && typeof value === 'object') {
    const out: Record<string, unknown> = {};
    for (const [key, nested] of Object.entries(value)) {
      if (/token|authorization|cookie/i.test(key)) {
        out[key] = nested ? '[redacted]' : nested;
      } else {
        out[key] = sanitizeValue(nested);
      }
    }
    return out;
  }
  return value;
}

export async function appendDiagnosticLog(event: string, details?: DiagnosticDetails, level: DiagnosticLevel = 'info') {
  const effectiveLevel = resolveDiagnosticLevel(event, level);
  if (effectiveLevel === 'info' && !isDiagnosticDebugEnabled()) return;
  const timestamp = new Date().toISOString();
  const payload = details ? ` ${JSON.stringify(sanitizeValue(details))}` : '';
  const line = `[${timestamp}] ${event}${payload}`;
  const existing = await getDiagnosticLog();
  const next = [...existing.split('\n').filter(Boolean), line]
    .slice(-MAX_LOG_LINES)
    .join('\n');
  await setStoredString(DIAGNOSTIC_LOG_KEY, next);
}

export async function getDiagnosticLog(): Promise<string> {
  return (await getStoredString(DIAGNOSTIC_LOG_KEY)) || '';
}

export async function clearDiagnosticLog() {
  await removeStoredValue(DIAGNOSTIC_LOG_KEY);
}
