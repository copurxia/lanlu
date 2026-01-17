"use client";

import { useMemo } from "react";
import Link from "next/link";
import { useSettingsStore } from "@/store/settings";

export default function SettingsPage() {
  const { settings, setSettings, setCategoryId, setAutoCloseTabOnComplete, save, saving, categories, loadingCategories, error } = useSettingsStore();

  const canConnect = useMemo(() => {
    return !!settings.serverUrl.trim() && !!settings.token.trim();
  }, [settings.serverUrl, settings.token]);

  return (
    <div className="p-4 space-y-3">
      <div className="flex items-center justify-between">
        <div className="text-base font-semibold tracking-tight">设置</div>
        <Link className="text-xs text-muted-foreground hover:text-foreground" href="/">
          返回
        </Link>
      </div>

      <div className="rounded-lg border bg-card text-card-foreground p-3 space-y-3">
        <div className="space-y-1">
          <label className="text-xs font-medium">服务器地址</label>
          <input
            className="w-full h-9 rounded-md border bg-background px-3 text-sm outline-none focus:ring-2 focus:ring-ring"
            placeholder="http://localhost:8082"
            value={settings.serverUrl}
            onChange={(e) => setSettings({ ...settings, serverUrl: e.target.value })}
            disabled={saving}
          />
        </div>

        <div className="space-y-1">
          <label className="text-xs font-medium">Token</label>
          <input
            type="password"
            className="w-full h-9 rounded-md border bg-background px-3 text-sm outline-none focus:ring-2 focus:ring-ring"
            placeholder="Bearer token（登录页可复制）"
            value={settings.token}
            onChange={(e) => setSettings({ ...settings, token: e.target.value })}
            disabled={saving}
          />
        </div>

        <div className="space-y-1">
          <label className="text-xs font-medium">默认分类</label>
          <select
            className="w-full h-9 rounded-md border bg-background px-3 text-sm outline-none focus:ring-2 focus:ring-ring"
            value={settings.categoryId}
            onChange={(e) => void setCategoryId(e.target.value)}
            disabled={!canConnect || loadingCategories || saving}
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
          <div className="flex items-center justify-between">
            <div className="text-[11px] text-muted-foreground">
              {!canConnect ? "先填写服务器与 Token" : "用于“一键添加”默认目标分类"}
            </div>
            <button
              type="button"
              className="text-xs underline underline-offset-2 text-muted-foreground hover:text-foreground"
              onClick={() => void save()}
              disabled={saving}
            >
              {saving ? "保存中..." : "保存/刷新"}
            </button>
          </div>
        </div>

        <div className="flex items-start justify-between gap-3 pt-1">
          <div className="space-y-1">
            <div className="text-xs font-medium">下载完成自动关闭标签页</div>
            <div className="text-[11px] text-muted-foreground">扫描完成并写入归档后，自动关闭发起下载的标签页</div>
          </div>
          <input
            type="checkbox"
            className="mt-1 h-4 w-4"
            checked={!!settings.autoCloseTabOnComplete}
            onChange={(e) => void setAutoCloseTabOnComplete(e.target.checked)}
            disabled={saving}
          />
        </div>
      </div>

      {error ? <div className="text-xs text-red-600">错误：{error}</div> : null}

      <div className="text-xs text-muted-foreground">
        提示：任务进度查询需要服务器开放 `/api/taskpool/*`，且 Token 具备访问权限。
      </div>
    </div>
  );
}
