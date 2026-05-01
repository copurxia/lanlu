import AsyncStorage from '@react-native-async-storage/async-storage';

const DIAGNOSTIC_LOG_KEY = 'lanlu.diagnosticLog.v1';
const MAX_LOG_LINES = 220;

type DiagnosticDetails = Record<string, unknown>;

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

export async function appendDiagnosticLog(event: string, details?: DiagnosticDetails) {
  const timestamp = new Date().toISOString();
  const payload = details ? ` ${JSON.stringify(sanitizeValue(details))}` : '';
  const line = `[${timestamp}] ${event}${payload}`;
  const existing = await getDiagnosticLog();
  const next = [...existing.split('\n').filter(Boolean), line]
    .slice(-MAX_LOG_LINES)
    .join('\n');
  await AsyncStorage.setItem(DIAGNOSTIC_LOG_KEY, next);
}

export async function getDiagnosticLog(): Promise<string> {
  return (await AsyncStorage.getItem(DIAGNOSTIC_LOG_KEY)) || '';
}

export async function clearDiagnosticLog() {
  await AsyncStorage.removeItem(DIAGNOSTIC_LOG_KEY);
}
