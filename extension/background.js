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
const TASK_POLL_ALARM = "lanlu_task_poll_alarm";
const TASK_POLL_INTERVAL_MINUTES = 3;
const TASK_POLL_MIN_INTERVAL_MS = 30 * 1000;

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

async function readSettingsRaw() {
  const local = await chromeGet("local", SETTINGS_KEY);
  const localValue = local[SETTINGS_KEY];
  if (localValue && typeof localValue === "object") return localValue;

  // Backward compatibility: older versions stored settings in sync storage.
  const legacy = await chromeGet("sync", SETTINGS_KEY);
  const legacyValue = legacy[SETTINGS_KEY];
  if (legacyValue && typeof legacyValue === "object") return legacyValue;

  return null;
}

async function getAuthConfigured() {
  const v = await readSettingsRaw();
  if (!v) return false;
  const serverUrl = normalizeServerUrl(v.serverUrl);
  const token = typeof v.token === "string" ? v.token.trim() : "";
  return !!(serverUrl && token);
}

async function getAuth() {
  const v = await readSettingsRaw();
  if (!v) return null;
  const serverUrl = normalizeServerUrl(v.serverUrl);
  const token = typeof v.token === "string" ? v.token.trim() : "";
  if (!serverUrl || !token) return null;
  return { serverUrl, token };
}

async function getAutoCloseEnabled() {
  const v = await readSettingsRaw();
  if (!v) return false;
  return !!v.autoCloseTabOnComplete;
}

async function readQueueEntries() {
  const items = await chromeGet("local", QUEUE_KEY);
  const raw = items[QUEUE_KEY];
  const parsed = typeof raw === "string" ? safeJsonParse(raw) : raw;
  const entries = parsed && parsed.state && Array.isArray(parsed.state.entries) ? parsed.state.entries : [];
  return entries;
}

async function readQueueState() {
  const items = await chromeGet("local", QUEUE_KEY);
  const raw = items[QUEUE_KEY];
  const parsed = typeof raw === "string" ? safeJsonParse(raw) : raw;
  if (parsed && typeof parsed === "object" && parsed.state && typeof parsed.state === "object") return parsed;
  return { state: { entries: [] }, version: 1 };
}

async function writeQueueState(nextState) {
  try {
    // Match zustand's persisted format: a JSON string.
    await new Promise((resolve) => chrome.storage.local.set({ [QUEUE_KEY]: JSON.stringify(nextState) }, resolve));
  } catch {
    // ignore
  }
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

function clampProgress(value) {
  const n = typeof value === "number" ? value : 0;
  return Math.max(0, Math.min(100, n));
}

function normalizeQueueStatus(raw) {
  switch (raw) {
    case "pending":
      return "queued";
    case "running":
      return "running";
    case "completed":
      return "completed";
    case "failed":
      return "failed";
    case "stopped":
      return "stopped";
    default:
      return "running";
  }
}

function parseArchiveIdFromScanResult(raw) {
  if (!raw || typeof raw !== "string") return null;
  try {
    const obj = JSON.parse(raw);
    return obj && typeof obj.archive_id === "string" && obj.archive_id.trim() ? obj.archive_id : null;
  } catch {
    return null;
  }
}

function parseScanTaskIdFromDownloadResult(raw) {
  if (!raw || typeof raw !== "string") return null;
  try {
    const obj = JSON.parse(raw);
    if (!obj) return null;
    if (typeof obj.task_id === "number" && Number.isFinite(obj.task_id)) return obj.task_id;
    if (typeof obj.task_id === "string") {
      const trimmed = obj.task_id.trim();
      if (!trimmed) return null;
      const parsed = Number.parseInt(trimmed, 10);
      return Number.isFinite(parsed) ? parsed : null;
    }
    return null;
  } catch {
    return null;
  }
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

async function getTaskById(auth, id) {
  return requestJson(auth, `/api/admin/taskpool/${id}`);
}

function ensureTaskPollerAlarm() {
  try {
    if (!chrome.alarms?.create) return;
    chrome.alarms.create(TASK_POLL_ALARM, { periodInMinutes: TASK_POLL_INTERVAL_MINUTES });
  } catch {
    // ignore
  }
}

let taskPollInFlight = false;
let lastTaskPollAt = 0;
async function pollTasksOnce(options = {}) {
  const force = !!options.force;
  const now = Date.now();
  if (!force && now - lastTaskPollAt < TASK_POLL_MIN_INTERVAL_MS) return;
  if (taskPollInFlight) return;

  taskPollInFlight = true;
  lastTaskPollAt = now;

  try {
    const auth = await getAuth();
    if (!auth) return;

    const autoClose = await getAutoCloseEnabled();
    const queueState = await readQueueState();
    const entries = queueState?.state?.entries;
    const list = Array.isArray(entries) ? entries : [];

    // If tasks already completed while popup was open (or before the worker got a chance
    // to poll), close them here as a catch-up pass.
    if (autoClose) {
      const completed = list.filter((e) => e && typeof e.tabId === "number" && e.status === "completed");
      if (completed.length > 0) {
        for (const e of completed) {
          try {
            await new Promise((resolve) => chrome.tabs.remove(e.tabId, () => resolve()));
          } catch {
            // ignore
          } finally {
            // Prevent repeated close attempts.
            const latest = await readQueueState();
            const latestEntries = Array.isArray(latest?.state?.entries) ? latest.state.entries : [];
            const nextEntries = latestEntries.map((row) => {
              if (!row || row.id !== e.id) return row;
              return { ...row, tabId: undefined, updatedAt: Date.now() };
            });
            await writeQueueState({ ...latest, state: { ...(latest.state || {}), entries: nextEntries } });
          }
        }
      }
    }

    const active = list.filter((entry) => {
      if (!entry || typeof entry !== "object") return false;
      if (entry.status === "queued" || entry.status === "running") return true;
      if (entry.status === "completed" && entry.downloadTaskId && !entry.scanTaskId && !entry.archiveId) return true;
      return false;
    });
    if (active.length === 0) return;

    const patchesById = new Map();
    const closeCandidates = [];
    const now = () => Date.now();

    for (const entry of active) {
      if (!entry || typeof entry.id !== "string") continue;
      const id = entry.id;
      const patch = { updatedAt: now() };
      let effectiveStatus = entry.status;
      let downloadTask = null;

      try {
        // 1) poll download task
        if (entry.downloadTaskId && (entry.status === "queued" || entry.status === "running")) {
          downloadTask = await getTaskById(auth, entry.downloadTaskId);
          const status =
            downloadTask && typeof downloadTask.status === "string" ? normalizeQueueStatus(downloadTask.status) : "running";
          patch.status = status;
          effectiveStatus = status;
          patch.downloadProgress = clampProgress(downloadTask?.progress);
          patch.downloadMessage = typeof downloadTask?.message === "string" ? downloadTask.message : "";
          if (status === "failed") patch.error = patch.downloadMessage || "任务失败";
        }

        // 2) poll scan task
        if (entry.scanTaskId && (entry.status === "queued" || entry.status === "running")) {
          const scanTask = await getTaskById(auth, entry.scanTaskId);
          const scanStatus =
            scanTask && typeof scanTask.status === "string" ? normalizeQueueStatus(scanTask.status) : "running";
          const archiveId = scanTask?.status === "completed" ? parseArchiveIdFromScanResult(scanTask.result) : null;

          patch.scanProgress = clampProgress(scanTask?.progress);
          patch.scanMessage = typeof scanTask?.message === "string" ? scanTask.message : "";
          patch.status = scanStatus;
          effectiveStatus = scanStatus;
          if (archiveId) patch.archiveId = archiveId;
          if (scanStatus === "failed") patch.error = patch.scanMessage || "扫描失败";

          if (scanStatus === "completed" && archiveId) {
            patch.status = "completed";
            effectiveStatus = "completed";
            if (autoClose && typeof entry.tabId === "number") {
              closeCandidates.push({ id, tabId: entry.tabId });
            }
          }
        }

        // If the download just completed in this tick, try discovering scan task immediately.
        if (
          entry.downloadTaskId &&
          effectiveStatus === "completed" &&
          !entry.scanTaskId &&
          !entry.archiveId
        ) {
          const scanTaskId = parseScanTaskIdFromDownloadResult(downloadTask?.result);
          if (typeof scanTaskId === "number") {
            patch.scanTaskId = scanTaskId;
            try {
              const scan = await getTaskById(auth, scanTaskId);
              patch.scanProgress = clampProgress(scan?.progress);
              patch.scanMessage = typeof scan?.message === "string" ? scan.message : "";
              const scanStatus = typeof scan?.status === "string" ? normalizeQueueStatus(scan.status) : "running";
              patch.status = scanStatus;
              effectiveStatus = scanStatus;
            } catch {
              patch.status = "queued";
              effectiveStatus = "queued";
            }
          }
        }
      } catch (e) {
        patch.status = "failed";
        patch.error = getErrorMessage(e, "任务查询失败");
      }

      patchesById.set(id, patch);
    }

    if (patchesById.size > 0) {
      const latest = await readQueueState();
      const latestEntries = Array.isArray(latest?.state?.entries) ? latest.state.entries : [];
      const nextEntries = latestEntries.map((e) => {
        if (!e || typeof e.id !== "string") return e;
        const patch = patchesById.get(e.id);
        return patch ? { ...e, ...patch } : e;
      });
      await writeQueueState({ ...latest, state: { ...(latest.state || {}), entries: nextEntries } });
    }

    if (autoClose && closeCandidates.length > 0) {
      for (const c of closeCandidates) {
        try {
          await new Promise((resolve) => chrome.tabs.remove(c.tabId, () => resolve()));
        } catch {
          // ignore
        } finally {
          // Prevent repeated close attempts.
          const latest = await readQueueState();
          const latestEntries = Array.isArray(latest?.state?.entries) ? latest.state.entries : [];
          const nextEntries = latestEntries.map((e) => {
            if (!e || e.id !== c.id) return e;
            return { ...e, tabId: undefined, updatedAt: Date.now() };
          });
          await writeQueueState({ ...latest, state: { ...(latest.state || {}), entries: nextEntries } });
        }
      }
    }
  } finally {
    taskPollInFlight = false;
  }
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
    // 1) Exact tag token match (fast-path; matches normalized tags).
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

    // 2) Fuzzy fallback: cover older/non-normalized tags like ", source:xxx" with whitespace.
    for (const candidate of candidates) {
      const resp = await searchArchives(auth, { filter: `source:${candidate}`, start: 0, count: 1 });
      const hit = resp && Array.isArray(resp.data) ? resp.data[0] : null;
      if (
        hit &&
        typeof hit.arcid === "string" &&
        typeof hit.tags === "string" &&
        hit.tags.includes(`source:${candidate}`)
      ) {
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
  ensureTaskPollerAlarm();
  updateBadgeForActiveTab();
  pollTasksOnce({ force: true });
});

chrome.runtime.onStartup?.addListener(() => {
  ensureTaskPollerAlarm();
  updateBadgeForActiveTab();
  pollTasksOnce({ force: true });
});

chrome.alarms?.onAlarm?.addListener((alarm) => {
  if (alarm && alarm.name === TASK_POLL_ALARM) {
    pollTasksOnce({ force: true });
  }
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
    ((areaName === "local" || areaName === "sync") && changes[SETTINGS_KEY]);
  if (isRelevant) updateBadgeForActiveTab();

  // Keep task progress up-to-date even when popup is closed.
  const taskRelevant = (areaName === "local" && changes[QUEUE_KEY]) || ((areaName === "local" || areaName === "sync") && changes[SETTINGS_KEY]);
  if (taskRelevant) pollTasksOnce();
});

// Ensure the alarm exists even if the worker starts from other events.
ensureTaskPollerAlarm();
