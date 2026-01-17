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
const REMOTE_CHECK_MIN_INTERVAL_MS = 60 * 1000;

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

function normalizeServerUrl(input) {
  if (typeof input !== "string") return "";
  const trimmed = input.trim();
  if (!trimmed) return "";
  return trimmed.endsWith("/") ? trimmed.slice(0, -1) : trimmed;
}

function getSourceSearchCandidates(input) {
  try {
    const url = new URL(input);
    const base = `${url.protocol}//${url.host}${url.pathname}${url.search}`;
    const trimmed = base.endsWith("/") ? base.slice(0, -1) : base;

    const candidates = [base];
    if (trimmed !== base) candidates.push(trimmed);

    const withoutProtocol = `${url.host}${url.pathname}${url.search}`;
    const withoutProtocolTrimmed = withoutProtocol.endsWith("/") ? withoutProtocol.slice(0, -1) : withoutProtocol;
    if (!candidates.includes(withoutProtocol)) candidates.push(withoutProtocol);
    if (!candidates.includes(withoutProtocolTrimmed) && withoutProtocolTrimmed !== withoutProtocol) {
      candidates.push(withoutProtocolTrimmed);
    }
    return candidates;
  } catch {
    return [];
  }
}

async function getAuthConfigured() {
  const items = await chromeGet("sync", SETTINGS_KEY);
  const v = items[SETTINGS_KEY];
  if (!v || typeof v !== "object") return false;
  const serverUrl = normalizeServerUrl(v.serverUrl);
  const token = typeof v.token === "string" ? v.token.trim() : "";
  return !!(serverUrl && token);
}

async function getAuth() {
  const items = await chromeGet("sync", SETTINGS_KEY);
  const v = items[SETTINGS_KEY];
  if (!v || typeof v !== "object") return null;
  const serverUrl = normalizeServerUrl(v.serverUrl);
  const token = typeof v.token === "string" ? v.token.trim() : "";
  if (!serverUrl || !token) return null;
  return { serverUrl, token };
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

function getErrorMessage(error, fallback) {
  if (error instanceof Error) return error.message || fallback;
  if (typeof error === "string") return error || fallback;
  return fallback;
}

function isRecord(value) {
  return typeof value === "object" && value !== null;
}

async function requestJson(auth, path) {
  const url = `${auth.serverUrl}${path}`;
  const resp = await fetch(url, {
    method: "GET",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${auth.token}`,
    },
  });
  const text = await resp.text();
  let data;
  try {
    data = text ? JSON.parse(text) : null;
  } catch {
    data = text;
  }
  if (!resp.ok) {
    const message =
      (isRecord(data) && (data.error || data.message) ? String(data.error || data.message) : null) ||
      `HTTP ${resp.status}`;
    throw new Error(message);
  }
  return data;
}

async function searchArchives(auth, params) {
  const searchParams = new URLSearchParams();
  searchParams.set("filter", params.filter);
  searchParams.set("start", String(params.start ?? 0));
  searchParams.set("count", String(params.count ?? 20));
  const data = await requestJson(auth, `/api/search?${searchParams.toString()}`);
  if (!isRecord(data)) return {};
  return { data: Array.isArray(data.data) ? data.data : [] };
}

async function writeStatusCache(url, entry) {
  return new Promise((resolve) => {
    chrome.storage.local.get(STATUS_CACHE_KEY, (items) => {
      const prev = items && typeof items[STATUS_CACHE_KEY] === "object" ? items[STATUS_CACHE_KEY] : {};
      const next = { ...prev, [url]: entry };

      // Keep the cache bounded to avoid unbounded growth.
      const keys = Object.keys(next);
      if (keys.length > 200) {
        keys
          .sort((a, b) => ((next[a] && next[a].updatedAt) || 0) - ((next[b] && next[b].updatedAt) || 0))
          .slice(0, keys.length - 200)
          .forEach((k) => {
            delete next[k];
          });
      }

      chrome.storage.local.set({ [STATUS_CACHE_KEY]: next }, () => resolve());
    });
  });
}

async function ensureRemoteStatusForUrl(tabId, url) {
  if (typeof tabId !== "number") return;
  if (!/^https?:\/\//.test(url || "")) return;

  const auth = await getAuth();
  if (!auth) return;

  // Skip noisy repeat checks for the same URL.
  const cache = await readStatusCache();
  const prev = cache && cache[url];
  if (prev && typeof prev === "object" && typeof prev.updatedAt === "number") {
    if (Date.now() - prev.updatedAt < REMOTE_CHECK_MIN_INTERVAL_MS) return;
  }

  try {
    const candidates = getSourceSearchCandidates(url);
    for (const candidate of candidates) {
      const resp = await searchArchives(auth, { filter: `source:${candidate}$`, start: 0, count: 1 });
      const hit = resp && Array.isArray(resp.data) ? resp.data[0] : null;
      if (hit && typeof hit.arcid === "string") {
        await writeStatusCache(url, {
          status: "saved",
          updatedAt: Date.now(),
          arcid: hit.arcid,
          title: typeof hit.title === "string" ? hit.title : undefined,
        });
        return;
      }
    }
    await writeStatusCache(url, { status: "not_saved", updatedAt: Date.now() });
  } catch (e) {
    await writeStatusCache(url, {
      status: "error",
      updatedAt: Date.now(),
      error: getErrorMessage(e, "检查失败"),
    });
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

async function getTabById(tabId) {
  try {
    const tab = await new Promise((resolve) => chrome.tabs.get(tabId, resolve));
    return tab || null;
  } catch {
    return null;
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

async function updateBadgeForTab(tabId, tabUrl) {
  const tab = tabUrl ? { id: tabId, url: tabUrl } : await getTabById(tabId);
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

async function updateBadgeForActiveTab() {
  const tab = await getActiveTab();
  if (!tab || typeof tab.id !== "number") return;
  await updateBadgeForTab(tab.id, typeof tab.url === "string" ? tab.url : "");
}

// --- Event wiring ---

chrome.runtime.onInstalled.addListener(() => {
  updateBadgeForActiveTab();
});

chrome.runtime.onStartup?.addListener(() => {
  updateBadgeForActiveTab();
});

chrome.tabs.onActivated.addListener(async (activeInfo) => {
  const tabId = activeInfo && typeof activeInfo.tabId === "number" ? activeInfo.tabId : null;
  if (tabId == null) return;
  const tab = await getTabById(tabId);
  if (tab && typeof tab.url === "string") {
    await ensureRemoteStatusForUrl(tabId, tab.url);
  }
  await updateBadgeForTab(tabId, tab && typeof tab.url === "string" ? tab.url : "");
});

chrome.tabs.onUpdated.addListener(async (tabId, changeInfo, tab) => {
  // Only refresh when URL changes or load finishes, otherwise this can be noisy.
  if (changeInfo.url || changeInfo.status === "complete") {
    const url = typeof changeInfo.url === "string" ? changeInfo.url : typeof tab?.url === "string" ? tab.url : "";
    await ensureRemoteStatusForUrl(tabId, url);
    await updateBadgeForTab(tabId, url);
  }
});

chrome.storage.onChanged.addListener((changes, areaName) => {
  const isRelevant =
    (areaName === "local" && (changes[QUEUE_KEY] || changes[STATUS_CACHE_KEY])) ||
    (areaName === "sync" && changes[SETTINGS_KEY]);
  if (isRelevant) updateBadgeForActiveTab();
});
