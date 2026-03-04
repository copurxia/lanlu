export type TabScope = "current" | "left" | "right";
import { chromeCall } from "~/lib/chrome-api";

function assertChromeTabs(): void {
  if (typeof chrome === "undefined" || !chrome.tabs?.query) {
    throw new Error("无法访问 chrome.tabs（请在扩展弹窗中使用）");
  }
}

async function tabsQuery(queryInfo: chrome.tabs.QueryInfo): Promise<chrome.tabs.Tab[]> {
  assertChromeTabs();
  return chromeCall<chrome.tabs.Tab[]>((cb) => chrome.tabs.query(queryInfo, cb));
}

export async function getCurrentTab(): Promise<chrome.tabs.Tab> {
  const [tab] = await tabsQuery({ active: true, currentWindow: true });
  if (!tab) throw new Error("未找到当前活动标签页");
  return tab;
}

export async function openInNewTab(url: string): Promise<void> {
  if (typeof chrome === "undefined" || !chrome.tabs?.create) {
    throw new Error("无法打开新标签页（请在扩展环境中使用）");
  }
  await chromeCall((cb) => chrome.tabs.create({ url }, cb));
}

export async function getTabsForScope(scope: TabScope): Promise<chrome.tabs.Tab[]> {
  const tabs = await tabsQuery({ currentWindow: true });
  const active = tabs.find((t) => t.active);
  if (!active || typeof active.index !== "number") {
    throw new Error("未找到当前活动标签页");
  }

  const sorted = [...tabs].sort((a, b) => (a.index ?? 0) - (b.index ?? 0));
  if (scope === "current") return active.url ? [active] : [active];
  if (scope === "left") return sorted.filter((t) => (t.index ?? 0) < active.index);
  return sorted.filter((t) => (t.index ?? 0) > active.index);
}
