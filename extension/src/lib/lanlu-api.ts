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
  status: "pending" | "running" | "completed" | "failed" | "stopped" | string;
  progress: number;
  message: string;
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

export async function getTasksByGroup(auth: LanluAuth, groupId: string): Promise<TaskPoolTask[]> {
  const data = await requestJson<unknown>(auth, `/api/admin/taskpool/group/${encodeURIComponent(groupId)}`, {
    method: "GET",
  });
  if (!Array.isArray(data)) return [];
  return data.filter(isTaskPoolTask);
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
