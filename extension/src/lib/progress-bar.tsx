"use client";

import React from "react";

interface ProgressBarProps {
  progress: number | null | undefined;
  label?: string;
  className?: string;
}

/**
 * 安全的进度条组件
 * 防止 DOM 访问错误和空值问题
 */
export function ProgressBar({ progress, label, className = "" }: ProgressBarProps) {
  // 防御性检查
  if (progress == null || typeof progress !== "number" || isNaN(progress)) {
    return null;
  }

  // 确保进度值在有效范围内
  const safeProgress = Math.max(0, Math.min(100, progress));

  // 防御性检查：确保在客户端环境中
  if (typeof window === "undefined") {
    return null;
  }

  try {
    return (
      <div className={`space-y-1 ${className}`}>
        <div className="h-2 w-full rounded bg-muted overflow-hidden">
          <div
            className="h-2 rounded bg-primary transition-all duration-300 ease-out"
            style={{
              width: `${safeProgress}%`,
              // 添加内联样式作为后备
              minWidth: safeProgress > 0 ? "2px" : "0",
            }}
          />
        </div>
        {label && (
          <div className="text-[11px] text-muted-foreground">
            {label}
          </div>
        )}
      </div>
    );
  } catch (error) {
    // 如果发生错误，渲染最简版本并记录
    console.error("[ProgressBar] Render error:", error);
    return (
      <div className="h-2 w-full rounded bg-muted">
        <div className="h-2 rounded bg-primary" style={{ width: `${safeProgress}%` }} />
      </div>
    );
  }
}

export default ProgressBar;
