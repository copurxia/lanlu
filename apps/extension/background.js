// MV3 service worker: SSE-based task sync + badge updates
//
// This background script handles:
// 1. SSE subscriptions for active download tasks (runs continuously)
// 2. Badge updates based on queue state

const QUEUE_KEY = "lanlu_download_queue";
const SETTINGS_KEY = "lanlu_settings";
const STATUS_CACHE_KEY = "lanlu_tab_status_cache";
const REMOTE_CHECK_MIN_INTERVAL_MS = 60 * 1000;
const SSE_RETRY_DELAY_MS = 2000;

const STATUS = {
  NOT_FOUND: "not_found",
  DOWNLOADING: "downloading",
  DONE: "done",
  ERROR: "error",
};

const BADGE = {
  [STATUS.NOT_FOUND]: { text: "?", color: "#6b7280" },
  [STATUS.DOWNLOADING]: { text: "↓", color: "#2563eb" },
  [STATUS.DONE]: { text: "✓", color: "#16a34a" },
  [STATUS.ERROR]: { text: "!", color: "#dc2626" },
};

let queueMutationChain = Promise.resolve();

// --- Storage helpers ---

function chromeGet(area, key) {
  return new Promise((resolve) => {
    try {
      chrome.storage[area].get(key, (items) => resolve(items || {}));
    } catch {
      resolve({});
    }
  });
}

function chromeSet(area, data) {
  return new Promise((resolve, reject) => {
    try {
      chrome.storage[area].set(data, () => {
        if (chrome.runtime.lastError) {
          reject(chrome.runtime.lastError);
        } else {
          resolve();
        }
      });
    } catch (e) {
      reject(e);
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

async function readQueueEntries() {
  const items = await chromeGet("local", QUEUE_KEY);
  const raw = items[QUEUE_KEY];
  const parsed = typeof raw === "string" ? safeJsonParse(raw) : raw;
  const entries = parsed && parsed.state && Array.isArray(parsed.state.entries) ? parsed.state.entries : [];
  return entries;
}

function enqueueQueueMutation(work) {
  const queued = queueMutationChain.catch(() => {}).then(work);
  queueMutationChain = queued.then(
    () => undefined,
    () => undefined
  );
  return queued;
}

async function writeQueueEntry(entryId, patch) {
  await enqueueQueueMutation(async () => {
    const items = await chromeGet("local", QUEUE_KEY);
    const raw = items[QUEUE_KEY];
    const parsed = typeof raw === "string" ? safeJsonParse(raw) : raw;
    if (!parsed || !parsed.state || !Array.isArray(parsed.state.entries)) return;

    let changed = false;
    const now = Date.now();
    const entries = parsed.state.entries.map((e) => {
      if (e.id === entryId) {
        const next = { ...e };
        for (const [key, value] of Object.entries(patch)) {
          if (next[key] !== value) {
            next[key] = value;
            changed = true;
          }
        }
        return changed ? { ...next, updatedAt: now } : e;
      }
      return e;
    });

    if (!changed) return;
    parsed.state.entries = entries;
    await chromeSet("local", { [QUEUE_KEY]: JSON.stringify(parsed) });
  });
}

async function readQueueEntryById(entryId) {
  const entries = await readQueueEntries();
  for (const entry of entries) {
    if (entry && entry.id === entryId) {
      return entry;
    }
  }
  return null;
}

async function readStatusCache() {
  const items = await chromeGet("local", STATUS_CACHE_KEY);
  const cache = items[STATUS_CACHE_KEY];
  return cache && typeof cache === "object" ? cache : {};
}

function pickLatestEntryByUrl(entries, url) {
  const hits = entries.filter((e) => e && typeof e.url === "string" && e.url === url);
  if (hits.length === 0) return null;
  hits.sort((a, b) => (b.updatedAt || b.createdAt || 0) - (a.updatedAt || b.createdAt || 0));
  return hits[0] || null;
}

function statusFromEntry(entry) {
  if (!entry || typeof entry.status !== "string") return null;
  switch (entry.status) {
    case "queued":
    case "running":
    case "waiting":
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

function sleepMs(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function isRecord(value) {
  return typeof value === "object" && value !== null;
}

function clampProgress(value) {
  const n = typeof value === "number" ? value : 0;
  return Math.max(0, Math.min(100, n));
}

function normalizeStatus(raw) {
  switch (raw) {
    case "pending":
      return "queued";
    case "running":
      return "running";
    case "waiting":
      return "waiting";
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

function isEntryActiveStatus(status) {
  return status === "queued" || status === "running" || status === "waiting";
}

function parseScanTaskIdFromDownloadResult(raw) {
  if (!raw) return null;
  try {
    const obj = JSON.parse(raw);
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

function parseCallbackTaskIdFromDownloadResult(raw) {
  if (!raw) return null;
  try {
    const obj = JSON.parse(raw);
    const rawId = obj.callback_task_id;
    if (typeof rawId === "number" && Number.isFinite(rawId)) return rawId;
    if (typeof rawId === "string") {
      const trimmed = rawId.trim();
      if (!trimmed) return null;
      const parsed = Number.parseInt(trimmed, 10);
      return Number.isFinite(parsed) ? parsed : null;
    }
    return null;
  } catch {
    return null;
  }
}

function parseScanTaskIdFromCallbackResult(raw) {
  if (!raw) return null;
  try {
    const obj = JSON.parse(raw);
    const rawId = obj.scan_task_id;
    if (typeof rawId === "number" && Number.isFinite(rawId)) return rawId;
    if (typeof rawId === "string") {
      const trimmed = rawId.trim();
      if (!trimmed) return null;
      const parsed = Number.parseInt(trimmed, 10);
      return Number.isFinite(parsed) ? parsed : null;
    }
    return null;
  } catch {
    return null;
  }
}

function parseArchiveIdFromScanResult(raw) {
  if (!raw) return null;
  try {
    const obj = JSON.parse(raw);
    return typeof obj.archive_id === "string" && obj.archive_id.trim() ? obj.archive_id : null;
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

function getTaskResultString(task) {
  if (!isRecord(task)) return "";
  return typeof task.result === "string" ? task.result : "";
}

function getTaskMessage(task) {
  if (!isRecord(task)) return "";
  return typeof task.message === "string" ? task.message : "";
}

function getTaskPhase(task) {
  if (!isRecord(task)) return "";
  return typeof task.phase === "string" ? task.phase : "";
}

function getTaskWaitingReason(task) {
  if (!isRecord(task)) return "";
  if (typeof task.waiting_reason === "string") return task.waiting_reason;
  if (typeof task.waitingReason === "string") return task.waitingReason;
  return "";
}

function getTaskProgress(task) {
  if (!isRecord(task)) return 0;
  return clampProgress(task.progress);
}

function latestLogLine(text) {
  if (typeof text !== "string" || !text) return "";
  const lines = text.split(/\r?\n/);
  for (let i = lines.length - 1; i >= 0; i -= 1) {
    const line = lines[i].trim();
    if (/^fetching\b/i.test(line)) continue;
    if (line) return line.length > 120 ? `${line.slice(0, 120)}...` : line;
  }
  return "";
}

function taskDisplayMessage(task, logTail, logDelta) {
  return getTaskMessage(task) || latestLogLine(logTail) || latestLogLine(logDelta);
}

async function readTaskDetail(taskId) {
  const auth = await getAuth();
  if (!auth) return null;
  try {
    const data = await requestJson(auth, `/api/admin/taskpool/${taskId}`);
    return isRecord(data) ? data : null;
  } catch (e) {
    console.warn(`[SSE] Failed to read task detail: ${taskId}`, e);
    return null;
  }
}

async function resolveScanTaskIdFromTask(task) {
  const direct = parseScanTaskIdFromDownloadResult(getTaskResultString(task));
  if (direct) return direct;
  if (typeof task.id !== "number") return null;

  for (const delayMs of [200, 700]) {
    await sleepMs(delayMs);
    const detail = await readTaskDetail(task.id);
    if (!detail) continue;
    const parsed = parseScanTaskIdFromDownloadResult(getTaskResultString(detail));
    if (parsed) return parsed;
  }
  return null;
}

async function resolveCallbackTaskIdFromTask(task) {
  const direct = parseCallbackTaskIdFromDownloadResult(getTaskResultString(task));
  if (direct) return direct;
  if (typeof task.id !== "number") return null;

  for (const delayMs of [200, 700]) {
    await sleepMs(delayMs);
    const detail = await readTaskDetail(task.id);
    if (!detail) continue;
    const parsed = parseCallbackTaskIdFromDownloadResult(getTaskResultString(detail));
    if (parsed) return parsed;
  }
  return null;
}

async function resolveScanTaskIdFromCallbackTask(task) {
  const direct = parseScanTaskIdFromCallbackResult(getTaskResultString(task));
  if (direct) return direct;
  if (typeof task.id !== "number") return null;

  for (const delayMs of [200, 700]) {
    await sleepMs(delayMs);
    const detail = await readTaskDetail(task.id);
    if (!detail) continue;
    const parsed = parseScanTaskIdFromCallbackResult(getTaskResultString(detail));
    if (parsed) return parsed;
  }
  return null;
}

async function resolveArchiveIdFromTask(task) {
  const direct = parseArchiveIdFromScanResult(getTaskResultString(task));
  if (direct) return direct;
  if (typeof task.id !== "number") return null;

  for (const delayMs of [200, 700]) {
    await sleepMs(delayMs);
    const detail = await readTaskDetail(task.id);
    if (!detail) continue;
    const parsed = parseArchiveIdFromScanResult(getTaskResultString(detail));
    if (parsed) return parsed;
  }
  return null;
}

async function writeStatusCache(url, entry) {
  return new Promise((resolve) => {
    chrome.storage.local.get(STATUS_CACHE_KEY, (items) => {
      const prev = items && typeof items[STATUS_CACHE_KEY] === "object" ? items[STATUS_CACHE_KEY] : {};
      const next = { ...prev, [url]: entry };

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

// --- Badge helpers ---

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

// --- SSE Task Sync (runs in background service worker) ---

const sseConnections = new Map(); // key: `${entryId}:${kind}:${taskId}` -> { close: () => void }
const sseRetryTimers = new Map(); // key: `${entryId}:${kind}:${taskId}` -> timeout id
const autoCloseHandledEntries = new Set();

function isMissingTabErrorMessage(message) {
  if (typeof message !== "string") return false;
  return message.includes("No tab with id") || message.includes("Tabs cannot be edited right now");
}

function closeTabById(tabId) {
  return new Promise((resolve, reject) => {
    try {
      chrome.tabs.remove(tabId, () => {
        const err = chrome.runtime.lastError;
        if (!err) {
          resolve();
          return;
        }
        if (isMissingTabErrorMessage(err.message || "")) {
          resolve();
          return;
        }
        reject(new Error(err.message || "Failed to close tab"));
      });
    } catch (e) {
      reject(e);
    }
  });
}

async function maybeAutoCloseTabForEntry(entryId) {
  if (autoCloseHandledEntries.has(entryId)) return;

  const settings = await readSettingsRaw();
  if (!settings || !settings.autoCloseTabOnComplete) return;

  const entry = await readQueueEntryById(entryId);
  if (!entry) return;
  autoCloseHandledEntries.add(entryId);

  if (typeof entry.tabId !== "number") return;

  try {
    await closeTabById(entry.tabId);
    console.log(`[AutoClose] Closed tab ${entry.tabId} for entry ${entryId}`);
  } catch (e) {
    console.warn(`[AutoClose] Failed to close tab for entry ${entryId}`, e);
  }
}

function buildStreamKey(entryId, kind, taskId) {
  return `${entryId}:${kind}:${taskId}`;
}

function clearSseRetryTimer(key) {
  const timer = sseRetryTimers.get(key);
  if (timer == null) return;
  clearTimeout(timer);
  sseRetryTimers.delete(key);
}

function scheduleSseRetry(key) {
  if (sseRetryTimers.has(key)) return;
  const timer = setTimeout(() => {
    sseRetryTimers.delete(key);
    void syncSseSubscriptions();
  }, SSE_RETRY_DELAY_MS);
  sseRetryTimers.set(key, timer);
}

function closeAllSseConnections() {
  for (const [key, connection] of sseConnections) {
    try {
      connection.close();
    } catch {}
  }
  sseConnections.clear();
  for (const [key, timer] of sseRetryTimers) {
    clearTimeout(timer);
    sseRetryTimers.delete(key);
  }
  console.log("[SSE] Closed all connections");
}

function createSseConnection(auth, entryId, taskId, kind) {
  const key = buildStreamKey(entryId, kind, taskId);
  clearSseRetryTimer(key);
  let doneReceived = false;
  let closed = false;
  const controller = new AbortController();

  // Close existing connection if any
  const existing = sseConnections.get(key);
  if (existing) {
    try {
      existing.close();
    } catch {}
    sseConnections.delete(key);
  }

  const close = () => {
    closed = true;
    controller.abort();
  };

  // Use fetch so the extension can authenticate with the same Authorization header
  // accepted by the main server middleware.
  const url = `${auth.serverUrl}/api/admin/taskpool/${taskId}/stream`;
  const connection = { close };
  sseConnections.set(key, connection);

  void (async () => {
    try {
      const resp = await fetch(url, {
        method: "GET",
        headers: {
          Accept: "text/event-stream",
          Authorization: `Bearer ${auth.token}`,
        },
        signal: controller.signal,
      });
      if (!resp.ok) throw new Error(`HTTP ${resp.status}`);
      if (!resp.body) throw new Error("SSE response body is empty");
      clearSseRetryTimer(key);
      console.log(`[SSE] Connected: ${key}`);

      await readSseStream(resp.body, async (sseEvent) => {
        if (closed) return;
        if (sseEvent.event === "ping") return;
        if (sseEvent.event === "snapshot" || sseEvent.event === "task") {
          await handleSseEvent(entryId, kind, sseEvent);
          return;
        }
        if (sseEvent.event === "done") {
          doneReceived = true;
          try {
            await handleSseEvent(entryId, kind, sseEvent);
          } finally {
            close();
            sseConnections.delete(key);
            clearSseRetryTimer(key);
            console.log(`[SSE] Done, closed: ${key}`);
            await syncSseSubscriptions();
          }
        }
      });
    } catch (err) {
      if (closed || controller.signal.aborted) return;
      if (doneReceived) {
        sseConnections.delete(key);
        clearSseRetryTimer(key);
        console.log(`[SSE] Ignored error after done: ${key}`);
        return;
      }
      console.warn(`[SSE] Error: ${key}`, err);
      sseConnections.delete(key);
      scheduleSseRetry(key);
    }
  })();

  console.log(`[SSE] Created: ${key}`);
  return connection;
}

async function readSseStream(body, onEvent) {
  const reader = body.getReader();
  const decoder = new TextDecoder();
  let buffer = "";

  const parseEvent = (raw) => {
    const lines = raw.split(/\r?\n/);
    let event = "message";
    const data = [];
    for (const line of lines) {
      if (!line || line.startsWith(":")) continue;
      const sep = line.indexOf(":");
      const field = sep >= 0 ? line.slice(0, sep) : line;
      const value = sep >= 0 ? line.slice(sep + 1).replace(/^ /, "") : "";
      if (field === "event") event = value || "message";
      if (field === "data") data.push(value);
    }
    if (data.length === 0) return null;
    return { event, data: data.join("\n") };
  };

  while (true) {
    const { value, done } = await reader.read();
    if (done) break;
    buffer += decoder.decode(value, { stream: true });
    let boundary = buffer.search(/\r?\n\r?\n/);
    while (boundary >= 0) {
      const raw = buffer.slice(0, boundary);
      const match = buffer.slice(boundary).match(/^\r?\n\r?\n/);
      buffer = buffer.slice(boundary + (match ? match[0].length : 2));
      const event = parseEvent(raw);
      if (event) await onEvent(event);
      boundary = buffer.search(/\r?\n\r?\n/);
    }
  }

  buffer += decoder.decode();
  if (buffer.trim()) {
    const event = parseEvent(buffer);
    if (event) await onEvent(event);
  }
}

async function handleSseEvent(entryId, kind, event) {
  const rawData = event.data;
  if (!rawData) return;

  let parsed;
  try {
    parsed = JSON.parse(rawData);
  } catch {
    console.warn(`[SSE] Failed to parse: ${rawData}`);
    return;
  }

  if (!isRecord(parsed)) return;
  const stream = isRecord(parsed.stream) ? parsed.stream : null;
  const task = isRecord(parsed.task) ? parsed.task : parsed;
  if (typeof task.id !== "number" || typeof task.status !== "string") return;
  const logDelta = stream && typeof stream.log_delta === "string" ? stream.log_delta : null;
  const logTail = stream && typeof stream.log_tail === "string" ? stream.log_tail : null;

  const status = normalizeStatus(task.status);
  const phase = getTaskPhase(task);
  const waitingReason = getTaskWaitingReason(task);

  if (kind === "download") {
    const downloadProgress = clampProgress(task.progress);
    const downloadMessage = taskDisplayMessage(task, logTail, logDelta);
    const patch = {
      status,
      phase,
      waitingReason,
      downloadCompleted: task.status === "completed",
      downloadProgress,
      downloadMessage,
      error: status === "failed" ? downloadMessage || "任务失败" : undefined,
    };

    if (!patch.callbackTaskId && (task.status === "waiting" || task.status === "completed")) {
      const callbackTaskId = await resolveCallbackTaskIdFromTask(task);
      if (callbackTaskId) {
        patch.callbackTaskId = callbackTaskId;
      }
    }

    if (task.status === "completed") {
      patch.status = "completed";
      patch.downloadCompleted = true;
      patch.downloadProgress = 100;
      patch.downloadMessage = downloadMessage || "下载完成";
      const scanTaskId = await resolveScanTaskIdFromTask(task);
      if (scanTaskId) {
        patch.scanTaskId = scanTaskId;
      } else {
        console.warn(`[SSE] Download completed but no scanTaskId found: ${task.id}`);
      }
    }
    await writeQueueEntry(entryId, patch);
    if (task.status === "completed") {
      await maybeAutoCloseTabForEntry(entryId);
    }
  } else if (kind === "callback") {
    const callbackProgress = clampProgress(task.progress);
    const callbackMessage = taskDisplayMessage(task, logTail, logDelta);
    const patch = {
      status: status === "failed" ? "failed" : "completed",
      phase,
      waitingReason,
      callbackProgress,
      callbackMessage,
      error: status === "failed" ? callbackMessage || "后处理失败" : undefined,
    };

    if (task.status === "completed") {
      const scanTaskId = await resolveScanTaskIdFromCallbackTask(task);
      if (scanTaskId) {
        patch.scanTaskId = scanTaskId;
        patch.status = "completed";
      } else {
        patch.callbackMessage = callbackMessage || "后处理完成，等待扫描任务";
      }
    }
    await writeQueueEntry(entryId, patch);
  } else if (kind === "scan") {
    const scanProgress = clampProgress(task.progress);
    const scanMessage = taskDisplayMessage(task, logTail, logDelta);
    const archiveId = task.status === "completed" ? await resolveArchiveIdFromTask(task) : null;

    const patch = {
      phase,
      waitingReason,
      scanProgress,
      scanMessage,
      status: status === "failed" ? "failed" : "completed",
      error: status === "failed" ? scanMessage || "扫描失败" : undefined,
    };
    if (archiveId) {
      patch.archiveId = archiveId;
    }

    await writeQueueEntry(entryId, patch);

    if (task.status === "completed") {
      await maybeAutoCloseTabForEntry(entryId);
    }
  }
}

async function hydrateEntryFromTaskDetails(entry) {
  if (!entry || !entry.id) return entry;
  let next = entry;

  if (typeof next.downloadTaskId === "number" && next.downloadTaskId > 0) {
    const detail = await readTaskDetail(next.downloadTaskId);
    if (detail) {
      const status = normalizeStatus(detail.status);
      const patch = {
        status,
        phase: getTaskPhase(detail),
        waitingReason: getTaskWaitingReason(detail),
        downloadCompleted: detail.status === "completed",
        downloadProgress: getTaskProgress(detail),
        downloadMessage: taskDisplayMessage(detail, "", ""),
        error: status === "failed" ? getTaskMessage(detail) || "任务失败" : undefined,
      };

      if (!next.scanTaskId && detail.status === "completed") {
        const scanTaskId = await resolveScanTaskIdFromTask(detail);
        if (scanTaskId) {
          patch.scanTaskId = scanTaskId;
        } else {
          patch.downloadMessage = patch.downloadMessage || "下载完成，等待后续任务";
        }
      }
      if (!next.callbackTaskId && (detail.status === "waiting" || detail.status === "completed")) {
        const callbackTaskId = await resolveCallbackTaskIdFromTask(detail);
        if (callbackTaskId) {
          patch.callbackTaskId = callbackTaskId;
        }
      }

      await writeQueueEntry(next.id, patch);
      next = { ...next, ...patch };
    }
  }

  if (next.downloadCompleted && !next.scanTaskId && typeof next.callbackTaskId === "number" && next.callbackTaskId > 0) {
    const detail = await readTaskDetail(next.callbackTaskId);
    if (detail) {
      const status = normalizeStatus(detail.status);
      const patch = {
        status: status === "failed" ? "failed" : "completed",
        phase: getTaskPhase(detail),
        waitingReason: getTaskWaitingReason(detail),
        callbackProgress: getTaskProgress(detail),
        callbackMessage: taskDisplayMessage(detail, "", ""),
        error: status === "failed" ? getTaskMessage(detail) || "后处理失败" : undefined,
      };

      if (detail.status === "completed") {
        const scanTaskId = await resolveScanTaskIdFromCallbackTask(detail);
        if (scanTaskId) {
          patch.scanTaskId = scanTaskId;
          patch.status = "completed";
        } else {
          patch.callbackMessage = patch.callbackMessage || "后处理完成，等待扫描任务";
        }
      }

      await writeQueueEntry(next.id, patch);
      next = { ...next, ...patch };
    }
  }

  if (typeof next.scanTaskId === "number" && next.scanTaskId > 0) {
    const detail = await readTaskDetail(next.scanTaskId);
    if (detail) {
      const status = normalizeStatus(detail.status);
      const archiveId = detail.status === "completed" ? await resolveArchiveIdFromTask(detail) : null;
      const patch = {
        status: status === "failed" ? "failed" : "completed",
        phase: getTaskPhase(detail),
        waitingReason: getTaskWaitingReason(detail),
        scanProgress: getTaskProgress(detail),
        scanMessage: taskDisplayMessage(detail, "", ""),
        error: status === "failed" ? getTaskMessage(detail) || "扫描失败" : undefined,
      };
      if (archiveId) {
        patch.archiveId = archiveId;
      }
      await writeQueueEntry(next.id, patch);
      next = { ...next, ...patch };
      if (detail.status === "completed") {
        await maybeAutoCloseTabForEntry(next.id);
      }
    }
  }

  return next;
}

async function syncSseSubscriptions() {
  const auth = await getAuth();
  if (!auth) {
    closeAllSseConnections();
    return;
  }

  const entries = await readQueueEntries();
  const expectedKeys = new Set();

  // Determine which SSE connections we need
  for (const rawEntry of entries) {
    const entry = isEntryActiveStatus(rawEntry && rawEntry.status)
      ? await hydrateEntryFromTaskDetails(rawEntry)
      : rawEntry;
    const statusActive = isEntryActiveStatus(entry.status);
    const hasDownloadTask = typeof entry.downloadTaskId === "number" && entry.downloadTaskId > 0;
    const hasScanTask = typeof entry.scanTaskId === "number" && entry.scanTaskId > 0;
    // Once scan task exists, download has already finished; don't keep re-subscribing download SSE.
    const needsDownloadStream =
      hasDownloadTask && statusActive && !hasScanTask;

    if (needsDownloadStream && hasDownloadTask) {
      const key = buildStreamKey(entry.id, "download", entry.downloadTaskId);
      expectedKeys.add(key);

      if (!sseConnections.has(key)) {
        createSseConnection(auth, entry.id, entry.downloadTaskId, "download");
      }
    }

    const needsScanStream = hasScanTask && statusActive;
    if (needsScanStream && hasScanTask) {
      const key = buildStreamKey(entry.id, "scan", entry.scanTaskId);
      expectedKeys.add(key);

      if (!sseConnections.has(key)) {
        createSseConnection(auth, entry.id, entry.scanTaskId, "scan");
      }
    }
  }

  // Close connections that are no longer needed
  for (const [key, connection] of sseConnections) {
    if (!expectedKeys.has(key)) {
      connection.close();
      sseConnections.delete(key);
      clearSseRetryTimer(key);
      console.log(`[SSE] Closed (no longer needed): ${key}`);
    }
  }

  console.log(`[SSE] Synced: ${sseConnections.size} active connections`);
}

// --- Event wiring ---

chrome.runtime.onInstalled.addListener(() => {
  updateBadgeForActiveTab();
  syncSseSubscriptions();
});

chrome.runtime.onStartup?.addListener(() => {
  updateBadgeForActiveTab();
  syncSseSubscriptions();
});

// Periodic wake-up to re-sync SSE (in case service worker was terminated)
chrome.alarms?.onAlarm?.addListener((alarm) => {
  if (alarm.name === "sse-sync") {
    syncSseSubscriptions();
  }
});

// Create periodic alarm to keep service worker alive
chrome.alarms?.create?.("sse-sync", { periodInMinutes: 0.5 });

chrome.tabs.onActivated.addListener(async (activeInfo) => {
  const tabId = activeInfo && typeof activeInfo.tabId === "number" ? activeInfo.tabId : null;
  if (tabId == null) return;
  const tab = await getTabById(tabId);
  await updateBadgeForTab(tabId, tab && typeof tab.url === "string" ? tab.url : "");
});

chrome.tabs.onUpdated.addListener(async (tabId, changeInfo, tab) => {
  if (changeInfo.url || changeInfo.status === "complete") {
    const url = typeof changeInfo.url === "string" ? changeInfo.url : typeof tab?.url === "string" ? tab.url : "";
    await updateBadgeForTab(tabId, url);
  }
});

chrome.runtime.onMessage?.addListener((message, _sender, sendResponse) => {
  if (!isRecord(message) || message.type !== "lanlu_poll_now") {
    return false;
  }

  void syncSseSubscriptions();
  void updateBadgeForActiveTab();
  sendResponse?.({ ok: 1 });
  return false;
});

chrome.storage.onChanged.addListener((changes, areaName) => {
  const isRelevant =
    (areaName === "local" && (changes[QUEUE_KEY] || changes[STATUS_CACHE_KEY])) ||
    ((areaName === "local" || areaName === "sync") && changes[SETTINGS_KEY]);

  if (isRelevant) {
    updateBadgeForActiveTab();

    // Re-sync SSE subscriptions when queue changes
    if (changes[QUEUE_KEY] || changes[SETTINGS_KEY]) {
      syncSseSubscriptions();
    }
  }
});

// Initial sync
syncSseSubscriptions();
