export type LanluCategory = {
  id: number;
  catid: string;
  name: string;
  enabled: boolean;
};

type CategoryResponse = {
  success: number | boolean | string;
  data: LanluCategory | LanluCategory[];
};

export type LanluAuth = {
  serverUrl: string;
  token: string;
};

export type LanluDownloadRequest = {
  url: string;
  title?: string;
};

export type LanluDownloadContext = LanluAuth & {
  categoryId: number;
};

export type LanluSearchArchive = {
  type: "archive";
  arcid: string;
  title?: string;
  tags?: string;
  filename?: string;
};

export type LanluSearchResponse = {
  data?: LanluSearchArchive[];
  draw?: number;
  recordsFiltered?: number;
  recordsTotal?: number;
};

export type TaskPoolTask = {
  id: number;
  name: string;
  task_type: string;
  status: "pending" | "running" | "waiting" | "completed" | "failed" | "stopped" | string;
  progress: number;
  message: string;
  phase?: string;
  waiting_reason?: string;
  active_key?: string;
  plugin_namespace: string;
  parameters: string;
  result: string;
  priority: number;
  group_id: string;
  timeout_at: string;
  trigger_source: string;
  created_at: string;
  started_at: string;
  completed_at: string;
};

export type TaskStreamPayload = {
  task: TaskPoolTask;
  event: string;
  version?: number;
  log?: string;
  logTail?: string;
  logDelta?: string;
  logBytes?: number;
  mode?: "snapshot" | "delta" | string;
};

type TaskStreamHandlers = {
  onOpen?: () => void;
  onTask?: (payload: TaskStreamPayload) => void;
  onDone?: (payload: TaskStreamPayload) => void;
  onError?: (error: Error) => void;
  onClose?: () => void;
};

type ParsedSseEvent = {
  event: string;
  data: string;
};

function normalizeSuccess(raw: unknown): boolean {
  return raw === true || raw === 1 || raw === "1" || raw === "true";
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null;
}

async function requestJson<T>(
  auth: LanluAuth,
  path: string,
  init?: RequestInit
): Promise<T> {
  const url = `${auth.serverUrl}${path}`;
  const resp = await fetch(url, {
    ...init,
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${auth.token}`,
      ...(init?.headers || {}),
    },
  });
  const text = await resp.text();
  let data: unknown;
  try {
    data = text ? JSON.parse(text) : null;
  } catch {
    data = text;
  }
  if (!resp.ok) {
    const message =
      (isRecord(data) && (data.error || data.message)
        ? String(data.error || data.message)
        : null) || `HTTP ${resp.status}`;
    throw new Error(message);
  }
  return data as T;
}

export async function getCategories(auth: LanluAuth): Promise<LanluCategory[]> {
  const data = await requestJson<unknown>(auth, "/api/categories", { method: "GET" });
  if (!isRecord(data)) return [];
  if (!normalizeSuccess(data.success)) return [];
  const raw = data.data as CategoryResponse["data"] | undefined;
  if (!raw) return [];
  return Array.isArray(raw) ? raw : [raw];
}

function isArchiveItem(value: unknown): value is LanluSearchArchive {
  if (!isRecord(value)) return false;
  return value.type === "archive" && typeof value.arcid === "string";
}

export async function searchArchives(
  auth: LanluAuth,
  params: { filter: string; start?: number; count?: number; category?: string }
): Promise<LanluSearchResponse> {
  const searchParams = new URLSearchParams();
  searchParams.set("filter", params.filter);
  if (params.category) searchParams.set("category", params.category);
  searchParams.set("start", String(params.start ?? 0));
  searchParams.set("count", String(params.count ?? 20));

  const data = await requestJson<unknown>(auth, `/api/search?${searchParams.toString()}`, {
    method: "GET",
  });

  if (!isRecord(data)) return {};
  const rawItems = data.data;
  const items = Array.isArray(rawItems) ? rawItems.filter(isArchiveItem) : [];
  return {
    data: items,
    draw: typeof data.draw === "number" ? data.draw : undefined,
    recordsFiltered: typeof data.recordsFiltered === "number" ? data.recordsFiltered : undefined,
    recordsTotal: typeof data.recordsTotal === "number" ? data.recordsTotal : undefined,
  };
}

function isTaskPoolTask(value: unknown): value is TaskPoolTask {
  if (!isRecord(value)) return false;
  return typeof value.id === "number" && typeof value.status === "string";
}

export async function getTaskById(auth: LanluAuth, id: number): Promise<TaskPoolTask> {
  const data = await requestJson<unknown>(auth, `/api/admin/taskpool/${id}`, { method: "GET" });
  if (!isTaskPoolTask(data)) {
    throw new Error("任务数据格式错误");
  }
  return data;
}

export function subscribeTaskStream(
  auth: LanluAuth,
  id: number,
  handlers: TaskStreamHandlers = {}
): () => void {
  let closed = false;
  const controller = new AbortController();

  const url = `${auth.serverUrl}/api/admin/taskpool/${id}/stream`;

  const emitPayload = (event: ParsedSseEvent, forceDone: boolean = false): void => {
    const rawData = event.data;
    if (!rawData) return;
    let parsed: unknown;
    try {
      parsed = JSON.parse(rawData);
    } catch {
      handlers.onError?.(new Error(rawData));
      return;
    }

    if (!isRecord(parsed)) return;
    const taskCandidate = isRecord(parsed.task) ? parsed.task : parsed;
    if (!isTaskPoolTask(taskCandidate)) return;

    const payload: TaskStreamPayload = {
      task: taskCandidate,
      event: event.event,
      version: typeof parsed.v === "number" ? parsed.v : undefined,
      log: typeof parsed.log === "string" ? parsed.log : undefined,
      logTail:
        isRecord(parsed.stream) && typeof parsed.stream.log_tail === "string"
          ? parsed.stream.log_tail
          : typeof parsed.log_tail === "string"
            ? parsed.log_tail
            : undefined,
      logDelta:
        isRecord(parsed.stream) && typeof parsed.stream.log_delta === "string"
          ? parsed.stream.log_delta
          : typeof parsed.log_delta === "string"
            ? parsed.log_delta
            : undefined,
      logBytes:
        isRecord(parsed.stream) && typeof parsed.stream.log_bytes === "number"
          ? parsed.stream.log_bytes
          : typeof parsed.log_bytes === "number"
            ? parsed.log_bytes
            : undefined,
      mode:
        isRecord(parsed.stream) && typeof parsed.stream.mode === "string"
          ? parsed.stream.mode
          : typeof parsed.mode === "string"
            ? parsed.mode
            : undefined,
    };

    handlers.onTask?.(payload);
    if (forceDone || isTerminalStatus(payload.task.status)) {
      handlers.onDone?.(payload);
    }
  };

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
      if (closed) return;
      handlers.onOpen?.();

      await readSseStream(resp.body, (event) => {
        if (closed) return;
        if (event.event === "ping") return;
        if (event.event === "snapshot" || event.event === "task") {
          emitPayload(event, false);
        } else if (event.event === "done") {
          emitPayload(event, true);
          closed = true;
          controller.abort();
        }
      });
    } catch (error) {
      if (closed || controller.signal.aborted) return;
      handlers.onError?.(error instanceof Error ? error : new Error(`SSE connection error: ${id}`));
    } finally {
      handlers.onClose?.();
    }
  })();

  return () => {
    closed = true;
    controller.abort();
  };
}

function isTerminalStatus(status: string): boolean {
  return status === "completed" || status === "failed" || status === "stopped";
}

async function readSseStream(
  body: ReadableStream<Uint8Array>,
  onEvent: (event: ParsedSseEvent) => void
): Promise<void> {
  const reader = body.getReader();
  const decoder = new TextDecoder();
  let buffer = "";

  const flushEvent = (raw: string): void => {
    const lines = raw.split(/\r?\n/);
    let event = "message";
    const data: string[] = [];
    for (const line of lines) {
      if (!line || line.startsWith(":")) continue;
      const sep = line.indexOf(":");
      const field = sep >= 0 ? line.slice(0, sep) : line;
      const value = sep >= 0 ? line.slice(sep + 1).replace(/^ /, "") : "";
      if (field === "event") event = value || "message";
      if (field === "data") data.push(value);
    }
    if (data.length > 0) {
      onEvent({ event, data: data.join("\n") });
    }
  };

  while (true) {
    const { value, done } = await reader.read();
    if (done) break;
    buffer += decoder.decode(value, { stream: true });
    let boundary = buffer.search(/\r?\n\r?\n/);
    while (boundary >= 0) {
      const raw = buffer.slice(0, boundary);
      const match = buffer.slice(boundary).match(/^\r?\n\r?\n/);
      buffer = buffer.slice(boundary + (match?.[0].length ?? 2));
      flushEvent(raw);
      boundary = buffer.search(/\r?\n\r?\n/);
    }
  }
  buffer += decoder.decode();
  if (buffer.trim()) flushEvent(buffer);
}

export async function enqueueDownloadUrl(
  ctx: LanluDownloadContext,
  req: LanluDownloadRequest
): Promise<number> {
  const data = await requestJson<unknown>(ctx, "/api/download_url", {
    method: "POST",
    body: JSON.stringify({
      url: req.url,
      title: req.title,
      category_id: ctx.categoryId,
    }),
  });

  if (!isRecord(data) || !normalizeSuccess(data.success)) {
    const message =
      (isRecord(data) && (data.error || data.message)
        ? String(data.error || data.message)
        : null) || "添加失败";
    throw new Error(message);
  }
  const job = data.job;
  if (typeof job !== "number") {
    throw new Error("服务器未返回 job id");
  }
  return job;
}
