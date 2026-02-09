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

function hasChromeStorage(area: "local" | "sync"): boolean {
  return typeof chrome !== "undefined" && !!chrome.storage?.[area];
}

async function readFromArea(area: "local" | "sync"): Promise<Partial<ExtensionSettings> | null> {
  if (!hasChromeStorage(area)) return null;

  const stored = await new Promise<Record<string, unknown>>((resolve, reject) => {
    try {
      chrome.storage[area].get(STORAGE_KEY, (items) => {
        const err = chrome.runtime?.lastError;
        if (err?.message) reject(new Error(err.message));
        else resolve(items as Record<string, unknown>);
      });
    } catch (e) {
      reject(e);
    }
  });

  const raw = stored?.[STORAGE_KEY];
  return raw && typeof raw === "object" ? (raw as Partial<ExtensionSettings>) : null;
}

function normalizeSettings(raw: Partial<ExtensionSettings> | null): ExtensionSettings {
  return {
    serverUrl: raw?.serverUrl || "",
    token: raw?.token || "",
    categoryId: raw?.categoryId || "",
    autoCloseTabOnComplete: !!raw?.autoCloseTabOnComplete,
  };
}

export async function loadSettings(): Promise<ExtensionSettings> {
  const local = await readFromArea("local");
  if (local) return normalizeSettings(local);

  // Backward-compatibility migration: old versions stored settings in sync.
  const legacySync = await readFromArea("sync");
  if (!legacySync) return DEFAULT_SETTINGS;

  const migrated = normalizeSettings(legacySync);
  await saveSettings(migrated);
  return migrated;
}

export async function saveSettings(settings: ExtensionSettings): Promise<void> {
  if (!hasChromeStorage("local")) return;

  await new Promise<void>((resolve, reject) => {
    try {
      chrome.storage.local.set({ [STORAGE_KEY]: settings }, () => {
        const err = chrome.runtime?.lastError;
        if (err?.message) reject(new Error(err.message));
        else resolve();
      });
    } catch (e) {
      reject(e);
    }
  });

  // Best-effort cleanup of legacy sync storage to reduce token exposure.
  if (hasChromeStorage("sync")) {
    try {
      await new Promise<void>((resolve) => chrome.storage.sync.remove(STORAGE_KEY, () => resolve()));
    } catch {
      // ignore cleanup failure
    }
  }
}
