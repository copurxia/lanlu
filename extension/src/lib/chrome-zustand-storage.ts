import type { StateStorage } from "zustand/middleware";
import { chromeCall, chromeCallVoid } from "~/lib/chrome-api";

function hasChromeStorage(area: "local" | "sync"): boolean {
  return typeof chrome !== "undefined" && !!chrome.storage?.[area];
}

export function createChromeStorage(area: "local" | "sync"): StateStorage {
  return {
    getItem: async (name: string) => {
      if (hasChromeStorage(area)) {
        const stored = await chromeCall<Record<string, unknown>>((cb) => chrome.storage[area].get(name, cb));
        const raw = stored?.[name] as unknown;
        if (typeof raw === "string") return raw;
        if (raw == null) return null;
        try {
          return JSON.stringify(raw);
        } catch {
          return null;
        }
      }
      if (typeof localStorage === "undefined") return null;
      return localStorage.getItem(name);
    },
    setItem: async (name: string, value: string) => {
      if (hasChromeStorage(area)) {
        await chromeCallVoid((cb) => chrome.storage[area].set({ [name]: value }, cb));
        return;
      }
      if (typeof localStorage === "undefined") return;
      localStorage.setItem(name, value);
    },
    removeItem: async (name: string) => {
      if (hasChromeStorage(area)) {
        await chromeCallVoid((cb) => chrome.storage[area].remove(name, cb));
        return;
      }
      if (typeof localStorage === "undefined") return;
      localStorage.removeItem(name);
    },
  };
}
