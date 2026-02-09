import { useMemo } from "react"
import { openInNewTab } from "~/lib/tabs"
import { normalizeUrl } from "~/lib/url"
import { ErrorBoundary } from "~/lib/error-boundary"
import { ProgressBar } from "~/lib/progress-bar"
import { useDownloadQueueStore } from "~/store/download-queue"
import { useSettingsStore } from "~/store/settings"
import type { PopupRoute } from "~/popup-pages/types"

type TasksPageProps = {
  navigate: (route: PopupRoute) => void
}

function formatTime(ts: number): string {
  try {
    return new Date(ts).toLocaleString()
  } catch {
    return ""
  }
}

function statusLabel(status: string): string {
  switch (status) {
    case "exists":
      return "已存在"
    case "queued":
      return "排队中"
    case "running":
      return "进行中"
    case "completed":
      return "完成"
    case "failed":
      return "失败"
    case "stopped":
      return "已停止"
    default:
      return status
  }
}

export default function TasksPage({ navigate }: TasksPageProps) {
  const entries = useDownloadQueueStore((s) => s.entries)
  const remove = useDownloadQueueStore((s) => s.remove)
  const clearCompleted = useDownloadQueueStore((s) => s.clearCompleted)
  const clearAll = useDownloadQueueStore((s) => s.clearAll)

  const { settings } = useSettingsStore()
  const baseUrl = useMemo(() => normalizeUrl(settings.serverUrl), [settings.serverUrl])

  return (
    <div className="p-4 space-y-3">
      <div className="flex items-center justify-between">
        <div className="text-base font-semibold tracking-tight">任务</div>
        <button
          type="button"
          className="text-xs text-muted-foreground hover:text-foreground"
          onClick={() => navigate("add")}
        >
          返回
        </button>
      </div>

      <div className="flex items-center justify-between gap-2">
        <button
          type="button"
          className="h-8 px-3 rounded-md border text-xs text-muted-foreground hover:text-foreground"
          onClick={() => clearCompleted()}
          disabled={entries.length === 0}
        >
          清空已完成
        </button>
        <button
          type="button"
          className="h-8 px-3 rounded-md border text-xs text-muted-foreground hover:text-foreground"
          onClick={() => clearAll()}
          disabled={entries.length === 0}
        >
          清空全部
        </button>
      </div>

      {entries.length === 0 ? (
        <div className="rounded-lg border bg-card text-card-foreground p-3 text-xs text-muted-foreground">
          暂无任务
        </div>
      ) : (
        <div className="rounded-lg border bg-card text-card-foreground overflow-hidden">
          <div className="max-h-[480px] overflow-y-auto">
            {entries.map((e) => {
              const downloadP = typeof e.downloadProgress === "number" ? e.downloadProgress : null
              const scanP = typeof e.scanProgress === "number" ? e.scanProgress : null
              const activeP = scanP ?? downloadP

              return (
                <div key={e.id} className="px-3 py-3 border-b last:border-b-0 space-y-2">
                  <div className="flex items-start justify-between gap-2">
                    <div className="min-w-0">
                      <div className="text-xs font-medium truncate">{e.title || e.url}</div>
                      <div className="text-[11px] text-muted-foreground truncate">{e.url}</div>
                    </div>
                    <button
                      type="button"
                      className="text-[11px] text-muted-foreground hover:text-foreground"
                      onClick={() => remove(e.id)}
                    >
                      移除
                    </button>
                  </div>

                  <div className="flex items-center justify-between">
                    <div className="text-[11px] text-muted-foreground">{statusLabel(e.status)}</div>
                    <div className="text-[11px] text-muted-foreground">{formatTime(e.createdAt)}</div>
                  </div>

                  {activeP != null && (
                    <ErrorBoundary
                      fallback={
                        <div className="h-2 w-full rounded bg-muted">
                          <div className="h-2 rounded bg-primary" style={{ width: `${activeP}%` }} />
                        </div>
                      }
                    >
                      <ProgressBar
                        progress={activeP}
                        label={
                          scanP != null
                            ? `扫描 ${scanP}% ${e.scanMessage || ""}`.trim()
                            : `下载 ${downloadP ?? 0}% ${e.downloadMessage || ""}`.trim()
                        }
                      />
                    </ErrorBoundary>
                  )}

                  {e.error ? <div className="text-[11px] text-red-600">错误：{e.error}</div> : null}

                  {e.archiveId ? (
                    <div className="text-[11px] text-muted-foreground">
                      id:{" "}
                      <button
                        type="button"
                        className="underline underline-offset-2"
                        onClick={() => void openInNewTab(`${baseUrl}/archive?id=${e.archiveId}`)}
                        disabled={!baseUrl}
                      >
                        {e.archiveId}
                      </button>
                    </div>
                  ) : null}
                </div>
              )
            })}
          </div>
        </div>
      )}
    </div>
  )
}
