"use client";

import Link from "next/link";
import { useCallback, useEffect, useMemo, useState } from "react";
import { enqueueDownloadUrl, searchArchives } from "@/lib/lanlu-api";
import { getCurrentTab, getTabsForScope, openInNewTab, type TabScope } from "@/lib/tabs";
import { getSourceSearchCandidates, normalizeUrl } from "@/lib/url";
import { useDownloadQueueStore } from "@/store/download-queue";
import { useSettingsStore } from "@/store/settings";

type CurrentTabCheck =
  | { status: "idle" }
  | { status: "checking" }
  | { status: "saved"; arcid: string; title?: string }
  | { status: "not_saved" }
  | { status: "error"; error: string };

function getErrorMessage(error: unknown, fallback: string) {
  if (error instanceof Error) return error.message || fallback;
  if (typeof error === "string") return error || fallback;
  return fallback;
}

const STATUS_CACHE_KEY = "lanlu_tab_status_cache";

type TabStatusCacheEntry = { status: "saved" | "not_saved" | "error"; updatedAt: number; arcid?: string; error?: string };

export default function AddPage() {
  const { settings, categories, hydrated, loadingCategories, saving, setCategoryId, refreshCategories } =
    useSettingsStore();
  const addEntry = useDownloadQueueStore((s) => s.add);
  const entries = useDownloadQueueStore((s) => s.entries);

  // 使用useMemo缓存recent任务，避免每次渲染都重新计算slice
  const recent = useMemo(() => {
    return entries.slice(0, 5);
  }, [entries]);

  const [busy, setBusy] = useState<null | TabScope>(null);
  const [error, setError] = useState<string | null>(null);
  const [currentTab, setCurrentTab] = useState<chrome.tabs.Tab | null>(null);
  const [check, setCheck] = useState<CurrentTabCheck>({ status: "idle" });

  const auth = useMemo(() => {
    const serverUrl = normalizeUrl(settings.serverUrl);
    const token = settings.token.trim();
    return serverUrl && token ? { serverUrl, token } : null;
  }, [settings.serverUrl, settings.token]);

  const selectedCategory = useMemo(() => {
    if (!settings.categoryId) return null;
    return categories.find((c) => c.catid === settings.categoryId) ?? null;
  }, [categories, settings.categoryId]);

  const canSubmit = !!auth && !!selectedCategory && !busy;

  const runCurrentCheck = useCallback(async () => {
    if (!auth) return;
    if (!currentTab?.url || !/^https?:\/\//.test(currentTab.url)) return;

    setCheck({ status: "checking" });
    try {
      const candidates = getSourceSearchCandidates(currentTab.url);
      for (const candidate of candidates) {
        const resp = await searchArchives(auth, { filter: `source:${candidate}$`, start: 0, count: 1 });
        const hit = resp.data?.[0];
        if (hit) {
          setCheck({ status: "saved", arcid: hit.arcid, title: hit.title });
          return;
        }
      }
      setCheck({ status: "not_saved" });
    } catch (e: unknown) {
      setCheck({ status: "error", error: getErrorMessage(e, "检查失败") });
    }
  }, [auth, currentTab?.url]);

  useEffect(() => {
    if (!hydrated) return;
    void (async () => {
      try {
        const tab = await getCurrentTab();
        setCurrentTab(tab);
      } catch {
        setCurrentTab(null);
      }
    })();
  }, [hydrated]);

  useEffect(() => {
    if (!auth || !currentTab?.url) return;
    void runCurrentCheck();
  }, [auth, currentTab?.url, runCurrentCheck]);

  // Persist the last known "saved/not_saved/error" result for this URL so the
  // background service worker can show a badge even when the popup is closed.
  useEffect(() => {
    const url = currentTab?.url;
    if (!url || !/^https?:\/\//.test(url)) return;
    if (typeof chrome === "undefined" || !chrome.storage?.local) return;

    const nextStatus =
      check.status === "saved"
        ? "saved"
        : check.status === "not_saved"
          ? "not_saved"
          : check.status === "error"
            ? "error"
            : null;
    if (!nextStatus) return;

    const now = Date.now();
    chrome.storage.local.get(STATUS_CACHE_KEY, (items) => {
      const prev = (items?.[STATUS_CACHE_KEY] ?? {}) as Record<string, TabStatusCacheEntry>;
      const next: Record<string, TabStatusCacheEntry> = {
        ...prev,
        [url]: { status: nextStatus as TabStatusCacheEntry["status"], updatedAt: now },
      };
      if (check.status === "saved") next[url].arcid = check.arcid;
      if (check.status === "error") next[url].error = check.error;

      // Keep the cache bounded to avoid unbounded growth.
      const keys = Object.keys(next);
      if (keys.length > 200) {
        keys
          .sort((a, b) => (next[a]?.updatedAt ?? 0) - (next[b]?.updatedAt ?? 0))
          .slice(0, keys.length - 200)
          .forEach((k) => {
            delete next[k];
          });
      }

      chrome.storage.local.set({ [STATUS_CACHE_KEY]: next });
    });
  }, [check, currentTab?.url]);

  const submit = useCallback(async (scope: TabScope) => {
    if (!canSubmit || !auth || !selectedCategory) return;
    setBusy(scope);
    setError(null);
    try {
      const tabs = await getTabsForScope(scope);
      const httpTabs = tabs.filter((t) => typeof t.url === "string" && /^https?:\/\//.test(t.url));
      const unique = new Map<string, typeof httpTabs[number]>();
      for (const tab of httpTabs) {
        if (tab.url) unique.set(tab.url, tab);
      }
      const toSubmit = [...unique.values()];
      if (toSubmit.length === 0) {
        setError("没有可添加的网页标签页（仅支持 http/https）");
        return;
      }

      for (const tab of toSubmit) {
        const tabUrl = tab.url!;
        const tabTitle = tab.title || undefined;

        // 进入页面即可判断是否存在；这里仍做一次检查，避免重复入队。
        let existing: { arcid: string; title?: string } | null = null;
        try {
          const candidates = getSourceSearchCandidates(tabUrl);
          for (const candidate of candidates) {
            const resp = await searchArchives(auth, { filter: `source:${candidate}$`, start: 0, count: 1 });
            const hit = resp.data?.[0];
            if (hit) {
              existing = { arcid: hit.arcid, title: hit.title };
              break;
            }
          }
        } catch {
          // ignore search errors; fallback to enqueue
        }

        if (existing) {
          addEntry({
            url: tabUrl,
            title: tabTitle,
            status: "exists",
            archiveId: existing.arcid,
          });
          continue;
        }

        try {
          const jobId = await enqueueDownloadUrl(
            { ...auth, categoryId: selectedCategory.id },
            { url: tabUrl, title: tabTitle }
          );
          addEntry({
            url: tabUrl,
            title: tabTitle,
            status: "queued",
            downloadTaskId: jobId,
            downloadProgress: 0,
          });
        } catch (e: unknown) {
          addEntry({
            url: tabUrl,
            title: tabTitle,
            status: "failed",
            error: getErrorMessage(e, "添加失败"),
          });
        }
      }
    } finally {
      setBusy(null);
    }
  }, [canSubmit, auth, selectedCategory, addEntry]);

  return (
    <div className="p-4 space-y-3">
      <div className="flex items-center justify-between">
        <div className="text-base font-semibold tracking-tight">兰鹿 · 标签页</div>
        <Link className="text-xs text-muted-foreground hover:text-foreground" href="/settings">
          设置
        </Link>
      </div>

      <div className="rounded-lg border bg-card text-card-foreground p-3 space-y-2">
        <div className="flex items-center justify-between gap-2">
          <div className="text-xs font-medium">当前标签页</div>
          <button
            type="button"
            className="text-xs underline underline-offset-2 text-muted-foreground hover:text-foreground disabled:opacity-50"
            onClick={() => void runCurrentCheck()}
            disabled={!auth || check.status === "checking"}
          >
            {check.status === "checking" ? "检查中…" : "Recheck"}
          </button>
        </div>

        <div className="text-xs">
          {check.status === "saved" ? (
            <div className="space-y-1">
              <div className="text-green-700">已保存到服务器</div>
              <div className="text-muted-foreground truncate">
                id:{" "}
                <button
                  type="button"
                  className="underline underline-offset-2"
                  onClick={() => void openInNewTab(`${auth!.serverUrl}/archive?id=${check.arcid}`)}
                >
                  {check.arcid}
                </button>
              </div>
              {check.title ? <div className="text-muted-foreground truncate">{check.title}</div> : null}
            </div>
          ) : check.status === "not_saved" ? (
            <div className="text-muted-foreground">未发现已保存记录</div>
          ) : check.status === "error" ? (
            <div className="text-red-600">错误：{check.error}</div>
          ) : !auth ? (
            <div className="text-muted-foreground">先到“设置”填写服务器与 Token</div>
          ) : currentTab?.url ? (
            <div className="text-muted-foreground truncate">{currentTab.url}</div>
          ) : (
            <div className="text-muted-foreground">无法获取当前标签页</div>
          )}
        </div>
      </div>

      <div className="rounded-lg border bg-card text-card-foreground p-3 space-y-2">
        <div className="text-xs font-medium">一键添加</div>
        <div className="space-y-2">
          <div className="flex items-center justify-between gap-2">
            <label className="text-[11px] text-muted-foreground">分类</label>
            <button
              type="button"
              className="text-[11px] underline underline-offset-2 text-muted-foreground hover:text-foreground disabled:opacity-50"
              onClick={() => void refreshCategories()}
              disabled={!auth || loadingCategories || saving}
            >
              {loadingCategories ? "刷新中…" : "刷新"}
            </button>
          </div>
          <select
            className="w-full h-9 rounded-md border bg-background px-3 text-sm outline-none focus:ring-2 focus:ring-ring disabled:opacity-50"
            value={settings.categoryId}
            onChange={(e) => void setCategoryId(e.target.value)}
            disabled={!auth || loadingCategories || saving || !!busy}
          >
            {loadingCategories ? (
              <option value="">加载中...</option>
            ) : categories.length === 0 ? (
              <option value="">暂无可用分类</option>
            ) : (
              <>
                <option value="" disabled>
                  请选择分类
                </option>
                {categories.map((c) => (
                  <option key={c.catid} value={c.catid}>
                    {c.name}
                  </option>
                ))}
              </>
            )}
          </select>
          <div className="text-[11px] text-muted-foreground">
            {auth ? (selectedCategory ? `当前：${selectedCategory.name}` : "请选择分类") : "需要配置服务器与 Token"}
          </div>
        </div>

        <div className="grid grid-cols-3 gap-2 pt-1">
          <button
            type="button"
            className="h-9 rounded-md bg-primary text-primary-foreground text-sm font-medium disabled:opacity-50"
            onClick={() => void submit("current")}
            disabled={!canSubmit}
          >
            {busy === "current" ? "添加中…" : "当前"}
          </button>
          <button
            type="button"
            className="h-9 rounded-md bg-primary text-primary-foreground text-sm font-medium disabled:opacity-50"
            onClick={() => void submit("left")}
            disabled={!canSubmit}
          >
            {busy === "left" ? "添加中…" : "左侧"}
          </button>
          <button
            type="button"
            className="h-9 rounded-md bg-primary text-primary-foreground text-sm font-medium disabled:opacity-50"
            onClick={() => void submit("right")}
            disabled={!canSubmit}
          >
            {busy === "right" ? "添加中…" : "右侧"}
          </button>
        </div>

        {error ? <div className="text-xs text-red-600">错误：{error}</div> : null}
      </div>

      <div className="rounded-lg border bg-card text-card-foreground">
        <div className="px-3 py-2 border-b text-xs font-medium flex items-center justify-between">
          <div>最近任务</div>
          <Link className="text-xs text-muted-foreground hover:text-foreground" href="/tasks">
            全部
          </Link>
        </div>
        {recent.length === 0 ? (
          <div className="px-3 py-3 text-xs text-muted-foreground">暂无任务</div>
        ) : (
          <div className="max-h-[220px] overflow-y-auto">
            {recent.map((e) => (
              <div key={e.id} className="px-3 py-2 border-b last:border-b-0">
                <div className="text-xs font-medium truncate">{e.title || e.url}</div>
                <div className="mt-1 flex items-center justify-between gap-2">
                  <div className="text-[11px] text-muted-foreground truncate">{e.url}</div>
                  {e.status === "exists" ? (
                    <div className="text-[11px] text-amber-600">已存在</div>
                  ) : e.status === "failed" ? (
                    <div className="text-[11px] text-red-600">{e.error || "失败"}</div>
                  ) : e.status === "completed" ? (
                    <div className="text-[11px] text-green-700">完成</div>
                  ) : (
                    <div className="text-[11px] text-muted-foreground">
                      {typeof e.scanProgress === "number"
                        ? `扫描 ${e.scanProgress}%`
                        : typeof e.downloadProgress === "number"
                          ? `${e.downloadProgress}%`
                          : "排队中"}
                    </div>
                  )}
                </div>
              </div>
            ))}
          </div>
        )}
      </div>
    </div>
  );
}
