"use client";

/**
 * TaskPoller组件 - 已简化
 *
 * SSE 订阅现在在 background.js 中运行，持续监控任务状态。
 * popup 只需要从 storage 读取数据，zustand 会自动同步。
 */

export default function TaskPoller() {
  // SSE 订阅在 background.js 中运行
  // popup 中的 zustand store 会自动从 chrome.storage 同步数据
  return null;
}
