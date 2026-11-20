type ChromeLastError = { message?: string } | undefined;

function lastErrorMessage(): string | null {
  const err = (typeof chrome !== "undefined" ? (chrome.runtime?.lastError as ChromeLastError) : undefined) as
    | ChromeLastError
    | undefined;
  const msg = err?.message;
  return msg && msg.trim() ? msg : null;
}

export function chromeCall<T>(invoke: (cb: (value: T) => void) => void): Promise<T> {
  return new Promise<T>((resolve, reject) => {
    try {
      invoke((value) => {
        const msg = lastErrorMessage();
        if (msg) reject(new Error(msg));
        else resolve(value);
      });
    } catch (e) {
      reject(e);
    }
  });
}

export function chromeCallVoid(invoke: (cb: () => void) => void): Promise<void> {
  return new Promise<void>((resolve, reject) => {
    try {
      invoke(() => {
        const msg = lastErrorMessage();
        if (msg) reject(new Error(msg));
        else resolve();
      });
    } catch (e) {
      reject(e);
    }
  });
}

