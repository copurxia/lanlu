"use client";

import { useEffect } from "react";
import { useTaskPoller, useTaskEvents } from "~/hooks/useTaskPoller";
import { useDownloadQueueStore } from "~/store/download-queue";
import { ErrorBoundary } from "~/lib/error-boundary";

interface TaskPollerProps {
  enabled?: boolean;
  onError?: (error: Error) => void;
}

/**
 * TaskPoller组件 - 使用事件驱动架构的任务轮询器
 *
 * 这个组件现在是一个轻量级的wrapper，专注于：
 * 1. 订阅任务事件
 * 2. 更新Zustand状态
 * 3. 提供错误处理
 *
 * 实际的轮询逻辑在TaskPollerService中处理，与React组件解耦
 */
export default function TaskPoller({ enabled = true, onError }: TaskPollerProps) {
  const update = useDownloadQueueStore((s) => s.update);

  // 启用任务轮询
  useTaskPoller({
    enabled,
    config: {
      pollInterval: 5000, // 5秒轮询间隔
      maxConcurrentTasks: 5, // 最大并发5个任务
    },
  });

  // 订阅所有任务事件
  const { events, clear } = useTaskEvents();

  // 处理任务事件
  useEffect(() => {
    for (const event of events) {
      const { id, type, payload } = event;

      try {
        switch (type) {
          case 'task-update':
            if (payload) {
              update(id, {
                status: payload.status as "exists" | "queued" | "running" | "completed" | "failed" | "stopped",
                downloadProgress: payload.downloadProgress,
                downloadMessage: payload.downloadMessage,
                scanProgress: payload.scanProgress,
                scanMessage: payload.scanMessage,
                error: payload.error,
                archiveId: payload.archiveId,
                scanTaskId: payload.scanTaskId,
              });
            }
            break;

          case 'task-complete':
            update(id, {
              status: 'completed',
              archiveId: payload?.archiveId,
            });
            break;

          case 'task-error':
            update(id, {
              status: 'failed',
              error: payload?.error,
            });
            break;

          case 'task-progress':
            if (payload) {
              update(id, {
                downloadProgress: payload.downloadProgress,
                downloadMessage: payload.downloadMessage,
                scanProgress: payload.scanProgress,
                scanMessage: payload.scanMessage,
              });
            }
            break;

          default:
            console.warn(`[TaskPoller] Unknown event type: ${type}`);
        }
      } catch (error) {
        console.error(`[TaskPoller] Error processing event:`, error);
        onError?.(error instanceof Error ? error : new Error('Unknown error'));
      }
    }

    // 清空已处理的事件
    if (events.length > 0) {
      clear();
    }
  }, [events, update, clear, onError]);

  return null;
}

/**
 * TaskPoller包装器组件 - 包含错误边界
 */
interface TaskPollerWrapperProps extends TaskPollerProps {
  showStatus?: boolean;
}

/**
 * 带状态显示的TaskPoller组件
 */
export function TaskPollerWithStatus(props: TaskPollerWrapperProps) {
  const { showStatus = false, ...taskPollerProps } = props;
  const { isRunning } = useTaskPoller({ enabled: props.enabled });

  return (
    <ErrorBoundary
      fallback={
        <div className="p-2 text-xs text-red-600 bg-red-50 rounded">
          任务轮询器已停止
        </div>
      }
    >
      <TaskPoller {...taskPollerProps} />

      {showStatus && (
        <div className="fixed bottom-2 right-2 text-xs text-muted-foreground bg-background/80 backdrop-blur px-2 py-1 rounded">
          轮询: {isRunning ? '运行中' : '已停止'}
        </div>
      )}
    </ErrorBoundary>
  );
}
