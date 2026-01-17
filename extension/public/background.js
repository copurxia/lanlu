// MV3 service worker: show per-tab status on the extension action badge.
//
// Badge mapping (requested):
// - 未找到   -> "?"
// - 下载中   -> "↓"
// - 下载完成 -> "✓"
// - 错误     -> "!"

const QUEUE_KEY = "lanlu_download_queue";
const SETTINGS_KEY = "lanlu_settings";
const STATUS_CACHE_KEY = "lanlu_tab_status_cache";

const STATUS = {
  NOT_FOUND: "not_found",
  DOWNLOADING: "downloading",
  DONE: "done",
  ERROR: "error",
};

const BADGE = {
  [STATUS.NOT_FOUND]: { text: "?", color: "#6b7280" }, // gray
  [STATUS.DOWNLOADING]: { text: "↓", color: "#2563eb" }, // blue
  [STATUS.DONE]: { text: "✓", color: "#16a34a" }, // green
  [STATUS.ERROR]: { text: "!", color: "#dc2626" }, // red
};

function chromeGet(area, key) {
  return new Promise((resolve) => {
    try {
      chrome.storage[area].get(key, (items) => resolve(items || {}));
    } catch {
      resolve({});
    }
  });
}

function safeJsonParse(raw) {
  if (typeof raw !== "string") return null;
  try {
    return JSON.parse(raw);
  } catch {
    return null;
  }
}

async function getAuthConfigured() {
  const items = await chromeGet("sync", SETTINGS_KEY);
  const v = items[SETTINGS_KEY];
  if (!v || typeof v !== "object") return false;
  const serverUrl = typeof v.serverUrl === "string" ? v.serverUrl.trim() : "";
  const token = typeof v.token === "string" ? v.token.trim() : "";
  return !!(serverUrl && token);
}

async function readQueueEntries() {
  const items = await chromeGet("local", QUEUE_KEY);
  const raw = items[QUEUE_KEY];
  const parsed = typeof raw === "string" ? safeJsonParse(raw) : raw;
  const entries = parsed && parsed.state && Array.isArray(parsed.state.entries) ? parsed.state.entries : [];
  return entries;
}

async function readStatusCache() {
  const items = await chromeGet("local", STATUS_CACHE_KEY);
  const cache = items[STATUS_CACHE_KEY];
  return cache && typeof cache === "object" ? cache : {};
}

function pickLatestEntryByUrl(entries, url) {
  const hits = entries.filter((e) => e && typeof e.url === "string" && e.url === url);
  if (hits.length === 0) return null;
  hits.sort((a, b) => (b.updatedAt || b.createdAt || 0) - (a.updatedAt || a.createdAt || 0));
  return hits[0] || null;
}

function statusFromEntry(entry) {
  if (!entry || typeof entry.status !== "string") return null;
  switch (entry.status) {
    case "queued":
    case "running":
      return STATUS.DOWNLOADING;
    case "completed":
    case "exists":
      return STATUS.DONE;
    case "failed":
    case "stopped":
      return STATUS.ERROR;
    default:
      return null;
  }
}

function statusFromCache(cache, url) {
  const v = cache && cache[url];
  if (!v || typeof v !== "object") return null;
  switch (v.status) {
    case "saved":
      return STATUS.DONE;
    case "not_saved":
      return STATUS.NOT_FOUND;
    case "error":
      return STATUS.ERROR;
    default:
      return null;
  }
}

async function setBadge(tabId, status) {
  const conf = BADGE[status];
  if (!conf) {
    try {
      await chrome.action.setBadgeText({ tabId, text: "" });
    } catch {
      // ignore
    }
    return;
  }
  try {
    await chrome.action.setBadgeText({ tabId, text: conf.text });
    await chrome.action.setBadgeBackgroundColor({ tabId, color: conf.color });
  } catch {
    // ignore
  }
}

async function getActiveTab() {
  try {
    const tabs = await new Promise((resolve) => chrome.tabs.query({ active: true, currentWindow: true }, resolve));
    const tab = Array.isArray(tabs) ? tabs[0] : null;
    return tab || null;
  } catch {
    return null;
  }
}

async function updateBadgeForActiveTab() {
  const tab = await getActiveTab();
  if (!tab || typeof tab.id !== "number") return;

  const url = typeof tab.url === "string" ? tab.url : "";
  if (!/^https?:\/\//.test(url)) {
    await setBadge(tab.id, null);
    return;
  }

  // If user hasn't configured auth yet, keep the UI clean (no misleading "未").
  const configured = await getAuthConfigured();
  if (!configured) {
    await setBadge(tab.id, null);
    return;
  }

  const [entries, cache] = await Promise.all([readQueueEntries(), readStatusCache()]);
  const entry = pickLatestEntryByUrl(entries, url);
  const fromEntry = statusFromEntry(entry);
  if (fromEntry) {
    await setBadge(tab.id, fromEntry);
    return;
  }

  const fromCache = statusFromCache(cache, url);
  if (fromCache) {
    await setBadge(tab.id, fromCache);
    return;
  }

  await setBadge(tab.id, STATUS.NOT_FOUND);
}

// --- Event wiring ---

chrome.runtime.onInstalled.addListener(() => {
  updateBadgeForActiveTab();
});

chrome.runtime.onStartup?.addListener(() => {
  updateBadgeForActiveTab();
});

chrome.tabs.onActivated.addListener(() => {
  updateBadgeForActiveTab();
});

chrome.tabs.onUpdated.addListener((_tabId, changeInfo) => {
  // Only refresh when URL changes or load finishes, otherwise this can be noisy.
  if (changeInfo.url || changeInfo.status === "complete") {
    updateBadgeForActiveTab();
  }
});

chrome.storage.onChanged.addListener((changes, areaName) => {
  const isRelevant =
    (areaName === "local" && (changes[QUEUE_KEY] || changes[STATUS_CACHE_KEY])) ||
    (areaName === "sync" && changes[SETTINGS_KEY]);
  if (isRelevant) updateBadgeForActiveTab();
});
