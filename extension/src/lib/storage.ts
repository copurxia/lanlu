export type ExtensionSettings = {
  serverUrl: string;
  token: string;
  categoryId: string;
  autoCloseTabOnComplete: boolean;
};

const STORAGE_KEY = "lanlu_settings";

const DEFAULT_SETTINGS: ExtensionSettings = {
  serverUrl: "",
  token: "",
  categoryId: "",
  autoCloseTabOnComplete: false,
};

function hasChromeStorage(): boolean {
  return typeof chrome !== "undefined" && !!chrome.storage?.sync;
}

export async function loadSettings(): Promise<ExtensionSettings> {
  if (!hasChromeStorage()) return DEFAULT_SETTINGS;
  const stored = await new Promise<Record<string, unknown>>((resolve, reject) => {
    try {
      chrome.storage.sync.get(STORAGE_KEY, (items) => {
        const err = chrome.runtime?.lastError;
        if (err?.message) reject(new Error(err.message));
        else resolve(items as Record<string, unknown>);
      });
    } catch (e) {
      reject(e);
    }
  });
  const raw = stored?.[STORAGE_KEY] as Partial<ExtensionSettings> | undefined;
  return {
    serverUrl: raw?.serverUrl || "",
    token: raw?.token || "",
    categoryId: raw?.categoryId || "",
    autoCloseTabOnComplete: !!raw?.autoCloseTabOnComplete,
  };
}

export async function saveSettings(settings: ExtensionSettings): Promise<void> {
  if (!hasChromeStorage()) return;
  await new Promise<void>((resolve, reject) => {
    try {
      chrome.storage.sync.set({ [STORAGE_KEY]: settings }, () => {
        const err = chrome.runtime?.lastError;
        if (err?.message) reject(new Error(err.message));
        else resolve();
      });
    } catch (e) {
      reject(e);
    }
  });
}
