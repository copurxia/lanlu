"use client";

import { create } from "zustand";
import { getCategories, type LanluCategory } from "@/lib/lanlu-api";
import { loadSettings, saveSettings, type ExtensionSettings } from "@/lib/storage";
import { normalizeUrl } from "@/lib/url";

type SettingsState = {
  settings: ExtensionSettings;
  hydrated: boolean;
  saving: boolean;
  categories: LanluCategory[];
  loadingCategories: boolean;
  error: string | null;

  hydrate: () => Promise<void>;
  setSettings: (next: ExtensionSettings) => void;
  setCategoryId: (categoryId: string) => Promise<void>;
  setAutoCloseTabOnComplete: (enabled: boolean) => Promise<void>;
  save: () => Promise<void>;
  refreshCategories: () => Promise<void>;
  clearError: () => void;
};

export const useSettingsStore = create<SettingsState>((set, get) => ({
  settings: { serverUrl: "", token: "", categoryId: "", autoCloseTabOnComplete: false },
  hydrated: false,
  saving: false,
  categories: [],
  loadingCategories: false,
  error: null,

  hydrate: async () => {
    const stored = await loadSettings();
    set({ settings: stored, hydrated: true });
    const { serverUrl, token } = stored;
    if (serverUrl.trim() && token.trim()) {
      void get().refreshCategories();
    }
  },

  setSettings: (next) => set({ settings: next }),

  setCategoryId: async (categoryId) => {
    const { settings } = get();
    const next = { ...settings, categoryId };
    set({ settings: next, saving: true, error: null });
    try {
      await saveSettings(next);
    } catch (e: unknown) {
      const message = e instanceof Error ? e.message : "保存失败";
      set({ error: message });
    } finally {
      set({ saving: false });
    }
  },

  setAutoCloseTabOnComplete: async (enabled) => {
    const { settings } = get();
    const next = { ...settings, autoCloseTabOnComplete: enabled };
    set({ settings: next, saving: true, error: null });
    try {
      await saveSettings(next);
    } catch (e: unknown) {
      const message = e instanceof Error ? e.message : "保存失败";
      set({ error: message });
    } finally {
      set({ saving: false });
    }
  },

  save: async () => {
    const { settings } = get();
    set({ saving: true, error: null });
    try {
      const next = {
        ...settings,
        serverUrl: normalizeUrl(settings.serverUrl),
        token: settings.token.trim(),
      };
      set({ settings: next });
      await saveSettings(next);
      await get().refreshCategories();
    } catch (e: unknown) {
      const message = e instanceof Error ? e.message : "保存失败";
      set({ error: message });
    } finally {
      set({ saving: false });
    }
  },

  refreshCategories: async () => {
    const { settings } = get();
    if (!settings.serverUrl.trim() || !settings.token.trim()) return;

    set({ loadingCategories: true, error: null });
    try {
      const cats = await getCategories({
        serverUrl: normalizeUrl(settings.serverUrl),
        token: settings.token.trim(),
      });
      const enabled = cats.filter((c) => c.enabled);
      let nextSettings = settings;

      // If categoryId is empty OR no longer valid after a refresh (server changed,
      // permissions changed, category disabled, etc.), pick a safe default.
      const currentValid = !!settings.categoryId && enabled.some((c) => c.catid === settings.categoryId);
      if ((!settings.categoryId || !currentValid) && enabled.length > 0) {
        nextSettings = { ...settings, categoryId: enabled[0].catid };
        set({ settings: nextSettings });
        await saveSettings(nextSettings);
      } else if (!enabled.length && settings.categoryId) {
        // No available categories -> clear selection to avoid stale/invalid ids.
        nextSettings = { ...settings, categoryId: "" };
        set({ settings: nextSettings });
        await saveSettings(nextSettings);
      }

      set({ categories: enabled });
    } catch (e: unknown) {
      const message = e instanceof Error ? e.message : "加载分类失败";
      set({ categories: [], error: message });
    } finally {
      set({ loadingCategories: false });
    }
  },

  clearError: () => set({ error: null }),
}));
