import { useCallback, useEffect, useMemo, useState } from "react"
import { enqueueDownloadUrl, searchArchives } from "~/lib/lanlu-api"
import { getCurrentTab, getTabsForScope, openInNewTab, type TabScope } from "~/lib/tabs"
import { getSourceSearchCandidates, normalizeUrl } from "~/lib/url"
import { useDownloadQueueStore } from "~/store/download-queue"
import { useSettingsStore } from "~/store/settings"
import type { PopupRoute } from "~/popup-pages/types"

type AddPageProps = {
  navigate: (route: PopupRoute) => void
}

type CurrentTabCheck =
  | { status: "idle" }
  | { status: "checking" }
  | { status: "saved"; arcid: string; title?: string }
  | { status: "not_saved" }
  | { status: "error"; error: string }

function getErrorMessage(error: unknown, fallback: string) {
  if (error instanceof Error) return error.message || fallback
  if (typeof error === "string") return error || fallback
  return fallback
}

const STATUS_CACHE_KEY = "lanlu_tab_status_cache"

type TabStatusCacheEntry = {
  status: "saved" | "not_saved" | "error"
  updatedAt: number
  arcid?: string
  title?: string
  error?: string
}

export default function AddPage({ navigate }: AddPageProps) {
  const { settings, categories, hydrated, loadingCategories, saving, setCategoryId, refreshCategories } =
    useSettingsStore()
  const addEntry = useDownloadQueueStore((s) => s.add)
  const entries = useDownloadQueueStore((s) => s.entries)

  const recent = useMemo(() => {
    return entries.slice(0, 5)
  }, [entries])

  const [busy, setBusy] = useState<null | TabScope>(null)
  const [error, setError] = useState<string | null>(null)
  const [currentTab, setCurrentTab] = useState<chrome.tabs.Tab | null>(null)
  const [check, setCheck] = useState<CurrentTabCheck>({ status: "idle" })

  const auth = useMemo(() => {
    const serverUrl = normalizeUrl(settings.serverUrl)
    const token = settings.token.trim()
    return serverUrl && token ? { serverUrl, token } : null
  }, [settings.serverUrl, settings.token])

  const selectedCategory = useMemo(() => {
    if (!settings.categoryId) return null
    return categories.find((c) => c.catid === settings.categoryId) ?? null
  }, [categories, settings.categoryId])

  const canSubmit = !!auth && !!selectedCategory && !busy

  const readStatusCache = useCallback(async (): Promise<Record<string, TabStatusCacheEntry>> => {
    if (typeof chrome === "undefined" || !chrome.storage?.local) return {}
    return await new Promise((resolve) => {
      chrome.storage.local.get(STATUS_CACHE_KEY, (items) => {
        const cache = items?.[STATUS_CACHE_KEY]
        resolve(cache && typeof cache === "object" ? (cache as Record<string, TabStatusCacheEntry>) : {})
      })
    })
  }, [])

  const writeStatusCache = useCallback(async (url: string, entry: TabStatusCacheEntry): Promise<void> => {
    if (typeof chrome === "undefined" || !chrome.storage?.local) return
    await new Promise((resolve) => {
      chrome.storage.local.get(STATUS_CACHE_KEY, (items) => {
        const prev = (items?.[STATUS_CACHE_KEY] ?? {}) as Record<string, TabStatusCacheEntry>
        const next: Record<string, TabStatusCacheEntry> = { ...prev, [url]: entry }

        const keys = Object.keys(next)
        if (keys.length > 200) {
          keys
            .sort((a, b) => (next[a]?.updatedAt ?? 0) - (next[b]?.updatedAt ?? 0))
            .slice(0, keys.length - 200)
            .forEach((k) => {
              delete next[k]
            })
        }

        chrome.storage.local.set({ [STATUS_CACHE_KEY]: next }, () => resolve(undefined))
      })
    })
  }, [])

  const findExistingArchive = useCallback(
    async (
      cache: Record<string, TabStatusCacheEntry>,
      url: string
    ): Promise<{ arcid: string; title?: string } | null> => {
      const cached = cache[url]
      if (cached?.status === "saved" && cached.arcid) {
        return { arcid: cached.arcid, title: cached.title }
      }

      const candidates = getSourceSearchCandidates(url)
      for (const candidate of candidates) {
        const resp = await searchArchives(auth!, { filter: `source:${candidate}$`, start: 0, count: 1 })
        const hit = resp.data?.[0]
        if (hit?.arcid) {
          return { arcid: hit.arcid, title: hit.title }
        }
      }
      for (const candidate of candidates) {
        const resp = await searchArchives(auth!, { filter: `source:${candidate}`, start: 0, count: 1 })
        const hit = resp.data?.[0]
        if (hit?.arcid && typeof hit.tags === "string" && hit.tags.includes(`source:${candidate}`)) {
          return { arcid: hit.arcid, title: hit.title }
        }
      }
      return null
    },
    [auth]
  )

  const runCurrentCheck = useCallback(async () => {
    if (!auth) return
    if (!currentTab?.url || !/^https?:\/\//.test(currentTab.url)) return

    setCheck({ status: "checking" })
    try {
      const cache = await readStatusCache()
      const cached = cache[currentTab.url]
      if (cached?.status === "saved" && cached.arcid) {
        setCheck({ status: "saved", arcid: cached.arcid, title: cached.title })
        return
      }

      const candidates = getSourceSearchCandidates(currentTab.url)
      for (const candidate of candidates) {
        const resp = await searchArchives(auth, { filter: `source:${candidate}$`, start: 0, count: 1 })
        const hit = resp.data?.[0]
        if (hit) {
          setCheck({ status: "saved", arcid: hit.arcid, title: hit.title })
          void writeStatusCache(currentTab.url, {
            status: "saved",
            updatedAt: Date.now(),
            arcid: hit.arcid,
            title: hit.title
          })
          return
        }
      }

      for (const candidate of candidates) {
        const resp = await searchArchives(auth, { filter: `source:${candidate}`, start: 0, count: 1 })
        const hit = resp.data?.[0]
        if (hit?.arcid && typeof hit.tags === "string" && hit.tags.includes(`source:${candidate}`)) {
          setCheck({ status: "saved", arcid: hit.arcid, title: hit.title })
          void writeStatusCache(currentTab.url, {
            status: "saved",
            updatedAt: Date.now(),
            arcid: hit.arcid,
            title: hit.title
          })
          return
        }
      }
      setCheck({ status: "not_saved" })
      void writeStatusCache(currentTab.url, { status: "not_saved", updatedAt: Date.now() })
    } catch (e: unknown) {
      const msg = getErrorMessage(e, "检查失败")
      setCheck({ status: "error", error: msg })
      void writeStatusCache(currentTab.url, { status: "error", updatedAt: Date.now(), error: msg })
    }
  }, [auth, currentTab?.url, readStatusCache, writeStatusCache])

  useEffect(() => {
    if (!hydrated) return
    void (async () => {
      try {
        const tab = await getCurrentTab()
        setCurrentTab(tab)
      } catch {
        setCurrentTab(null)
      }
    })()
  }, [hydrated])

  useEffect(() => {
    if (!auth || !currentTab?.url || !/^https?:\/\//.test(currentTab.url)) {
      setCheck({ status: "idle" })
      return
    }
    if (typeof chrome === "undefined" || !chrome.storage?.local) return

    const url = currentTab.url
    let cancelled = false

    const applyCache = (cache: unknown) => {
      if (cancelled) return
      const entry = (cache as Record<string, TabStatusCacheEntry> | undefined)?.[url]
      if (!entry) {
        setCheck({ status: "idle" })
        return
      }
      if (entry.status === "saved" && entry.arcid) {
        setCheck({ status: "saved", arcid: entry.arcid, title: entry.title })
      } else if (entry.status === "not_saved") {
        setCheck({ status: "not_saved" })
      } else if (entry.status === "error") {
        setCheck({ status: "error", error: entry.error || "检查失败" })
      } else {
        setCheck({ status: "checking" })
      }
    }

    chrome.storage.local.get(STATUS_CACHE_KEY, (items) => {
      applyCache(items?.[STATUS_CACHE_KEY])
    })

    const onChanged = (changes: { [key: string]: chrome.storage.StorageChange }, areaName: string) => {
      if (cancelled) return
      if (areaName !== "local") return
      if (!changes[STATUS_CACHE_KEY]) return
      applyCache(changes[STATUS_CACHE_KEY].newValue)
    }
    chrome.storage.onChanged.addListener(onChanged)

    return () => {
      cancelled = true
      chrome.storage.onChanged.removeListener(onChanged)
    }
  }, [auth, currentTab?.url])

  useEffect(() => {
    const url = currentTab?.url
    if (!url || !/^https?:\/\//.test(url)) return
    if (typeof chrome === "undefined" || !chrome.storage?.local) return

    const nextStatus =
      check.status === "saved"
        ? "saved"
        : check.status === "not_saved"
        ? "not_saved"
        : check.status === "error"
        ? "error"
        : null
    if (!nextStatus) return

    const now = Date.now()
    chrome.storage.local.get(STATUS_CACHE_KEY, (items) => {
      const prev = (items?.[STATUS_CACHE_KEY] ?? {}) as Record<string, TabStatusCacheEntry>
      const next: Record<string, TabStatusCacheEntry> = {
        ...prev,
        [url]: { status: nextStatus as TabStatusCacheEntry["status"], updatedAt: now }
      }
      if (check.status === "saved") next[url].arcid = check.arcid
      if (check.status === "saved" && check.title) next[url].title = check.title
      if (check.status === "error") next[url].error = check.error

      const keys = Object.keys(next)
      if (keys.length > 200) {
        keys
          .sort((a, b) => (next[a]?.updatedAt ?? 0) - (next[b]?.updatedAt ?? 0))
          .slice(0, keys.length - 200)
          .forEach((k) => {
            delete next[k]
          })
      }

      chrome.storage.local.set({ [STATUS_CACHE_KEY]: next })
    })
  }, [check, currentTab?.url])

  const submit = useCallback(
    async (scope: TabScope) => {
      if (!canSubmit || !auth || !selectedCategory) return
      setBusy(scope)
      setError(null)
      try {
        const tabs = await getTabsForScope(scope)
        const httpTabs = tabs.filter((t) => typeof t.url === "string" && /^https?:\/\//.test(t.url))
        const unique = new Map<string, (typeof httpTabs)[number]>()
        for (const tab of httpTabs) {
          if (tab.url) unique.set(tab.url, tab)
        }
        const toSubmit = [...unique.values()]
        if (toSubmit.length === 0) {
          setError("没有可添加的网页标签页（仅支持 http/https）")
          return
        }

        const cache = await readStatusCache()

        for (const tab of toSubmit) {
          const tabUrl = tab.url!
          const tabTitle = tab.title || undefined
          const tabId = typeof tab.id === "number" ? tab.id : undefined

          let existing: { arcid: string; title?: string } | null = null
          try {
            existing = await findExistingArchive(cache, tabUrl)
          } catch {
            // ignore
          }

          if (existing) {
            addEntry({
              url: tabUrl,
              title: tabTitle,
              tabId,
              status: "exists",
              archiveId: existing.arcid
            })
            void writeStatusCache(tabUrl, {
              status: "saved",
              updatedAt: Date.now(),
              arcid: existing.arcid,
              title: existing.title
            })
            continue
          }

          try {
            const jobId = await enqueueDownloadUrl(
              { ...auth, categoryId: selectedCategory.id },
              { url: tabUrl, title: tabTitle }
            )
            addEntry({
              url: tabUrl,
              title: tabTitle,
              tabId,
              status: "queued",
              downloadTaskId: jobId,
              downloadProgress: 0
            })
          } catch (e: unknown) {
            addEntry({
              url: tabUrl,
              title: tabTitle,
              tabId,
              status: "failed",
              error: getErrorMessage(e, "添加失败")
            })
          }
        }
      } finally {
        setBusy(null)
      }
    },
    [canSubmit, auth, selectedCategory, addEntry, readStatusCache, findExistingArchive, writeStatusCache]
  )

  return (
    <div className="p-4 space-y-3">
      <div className="flex items-center justify-between">
        <div className="text-base font-semibold tracking-tight">兰鹿 · 标签页</div>
        <button
          type="button"
          className="text-xs text-muted-foreground hover:text-foreground"
          onClick={() => navigate("settings")}
        >
          设置
        </button>
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
          <button
            type="button"
            className="text-xs text-muted-foreground hover:text-foreground"
            onClick={() => navigate("tasks")}
          >
            全部
          </button>
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
  )
}
