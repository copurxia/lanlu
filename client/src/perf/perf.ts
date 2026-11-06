import {appendPerformanceLines} from '../storage/diagnostics';

/**
 * Lightweight, always-on performance baseline. Marks are buffered and flushed
 * in one MMKV write per JS turn so instrumentation does not add synchronous IO
 * to the frame path.
 */
const origin = Date.now();
const marks = new Map<string, number>();
let pending: string[] = [];
let flushTimer: ReturnType<typeof setTimeout> | null = null;

function flush(): void {
  if (flushTimer) {
    clearTimeout(flushTimer);
    flushTimer = null;
  }
  if (!pending.length) return;
  const lines = pending;
  pending = [];
  appendPerformanceLines(lines);
}

function scheduleFlush(): void {
  if (flushTimer) return;
  flushTimer = setTimeout(() => {
    flushTimer = null;
    flush();
  }, 0);
}

export function perfNow(): number {
  return Date.now() - origin;
}

export function perfMark(name: string, details?: Record<string, unknown>): void {
  const at = Date.now();
  marks.set(name, at);
  let suffix = '';
  if (details) {
    try {
      suffix = ` ${JSON.stringify(details)}`;
    } catch {
      suffix = '';
    }
  }
  pending.push(`[perf] s=${origin.toString(36)} +${at - origin}ms ${name}${suffix}`);
  scheduleFlush();
}

export function perfSince(
  name: string,
  from: string,
  details?: Record<string, unknown>,
): void {
  const start = marks.get(from);
  if (start === undefined) return;
  perfMark(name, {...details, ms: Date.now() - start});
}

export function perfFlush(): void {
  flush();
}
