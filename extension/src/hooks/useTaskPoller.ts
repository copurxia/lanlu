/**
 * useTaskPoller Hook - 管理任务轮询的React Hook
 */

import { useEffect, useRef, useCallback } from 'react';
import { useSettingsStore } from '~/store/settings';
import { useDownloadQueueStore } from '~/store/download-queue';
import { taskPollerService, type TaskPollerConfig } from '~/services/TaskPollerService';
import { eventBus } from '~/lib/events';
import { normalizeUrl } from '~/lib/url';

interface UseTaskPollerOptions {
  enabled?: boolean; // 是否启用轮询
  config?: TaskPollerConfig; // 轮询配置
}

interface UseTaskPollerReturn {
  start: () => void; // 启动轮询
  stop: () => void; // 停止轮询
  pollOnce: () => Promise<void>; // 手动触发一次轮询
  isRunning: boolean; // 是否正在运行
}

/**
 * 使用任务轮询Hook
 */
export function useTaskPoller(options: UseTaskPollerOptions = {}): UseTaskPollerReturn {
  const { enabled = true } = options;

  const { settings, hydrated } = useSettingsStore();
  const entries = useDownloadQueueStore((s) => s.entries);

  const authRef = useRef<{ serverUrl: string; token: string } | null>(null);
  const isRunningRef = useRef(false);

  // 更新认证信息
  useEffect(() => {
    const serverUrl = normalizeUrl(settings.serverUrl);
    const token = settings.token.trim();
    if (serverUrl && token) {
      authRef.current = { serverUrl, token };
      if (isRunningRef.current) {
        taskPollerService.updateAuth(authRef.current);
      }
    } else {
      authRef.current = null;
    }
  }, [settings.serverUrl, settings.token]);

  // 启动轮询
  const start = useCallback(() => {
    if (!enabled || !hydrated || !authRef.current) {
      console.log('[useTaskPoller] Cannot start - missing requirements:', {
        enabled,
        hydrated,
        hasAuth: !!authRef.current,
      });
      return;
    }

    console.log('[useTaskPoller] Starting task poller...');
    taskPollerService.start(authRef.current, entries);
    isRunningRef.current = true;
  }, [enabled, hydrated, entries]);

  // 停止轮询
  const stop = useCallback(() => {
    console.log('[useTaskPoller] Stopping task poller...');
    taskPollerService.stop();
    isRunningRef.current = false;
  }, []);

  // 手动触发一次轮询
  const pollOnce = useCallback(async () => {
    if (!authRef.current) {
      console.log('[useTaskPoller] Cannot poll - no auth');
      return;
    }
    await taskPollerService.pollOnce();
  }, []);

  // 自动启动/停止轮询
  useEffect(() => {
    if (!hydrated) return;

    if (enabled && authRef.current) {
      start();
    } else {
      stop();
    }

    return () => {
      stop();
    };
  }, [enabled, hydrated, start, stop]);

  // 更新entries
  useEffect(() => {
    if (isRunningRef.current) {
      taskPollerService.updateEntries(entries);
    }
  }, [entries]);

  // 在组件卸载时停止轮询
  useEffect(() => {
    return () => {
      if (isRunningRef.current) {
        taskPollerService.stop();
        isRunningRef.current = false;
      }
    };
  }, []);

  return {
    start,
    stop,
    pollOnce,
    isRunning: isRunningRef.current,
  };
}

/**
 * 订阅任务事件的Hook
 */
import { useState } from 'react';
import type { TaskEventData } from '~/lib/events';

interface UseTaskEventsOptions {
  taskId?: string; // 特定任务ID，为空则监听所有任务
}

interface UseTaskEventsReturn {
  events: TaskEventData[]; // 事件列表
  clear: () => void; // 清空事件列表
}

export function useTaskEvents(options: UseTaskEventsOptions = {}): UseTaskEventsReturn {
  const { taskId } = options;

  const [events, setEvents] = useState<TaskEventData[]>([]);

  useEffect(() => {
    const eventTypes = ['task-update', 'task-complete', 'task-error', 'task-progress', 'task-discovered'] as const;
    const unsubscribers = eventTypes.map((type) =>
      eventBus.on(type, (event) => {
        if (!taskId || event.id === taskId) {
          setEvents((prev) => [...prev, event]);
        }
      })
    );

    return () => {
      unsubscribers.forEach((unsubscribe) => unsubscribe());
    };
  }, [taskId]);

  const clear = useCallback(() => {
    setEvents([]);
  }, []);

  return {
    events,
    clear,
  };
}

/**
 * 检查任务状态的Hook
 */
interface UseTaskStatusOptions {
  taskId: string;
}

interface UseTaskStatusReturn {
  status?: string;
  progress?: number;
  error?: string;
  archiveId?: string;
}

export function useTaskStatus({ taskId }: UseTaskStatusOptions): UseTaskStatusReturn {
  const [status, setStatus] = useState<UseTaskStatusReturn>({});

  useEffect(() => {
    const unsubscribe = eventBus.on('task-update', (event) => {
      if (event.id === taskId && event.payload) {
        setStatus((prev) => ({
          ...prev,
          ...event.payload,
        }));
      }
    });

    const unsubscribeComplete = eventBus.on('task-complete', (event) => {
      if (event.id === taskId) {
        setStatus((prev) => ({
          ...prev,
          status: 'completed',
          archiveId: event.payload?.archiveId,
        }));
      }
    });

    const unsubscribeError = eventBus.on('task-error', (event) => {
      if (event.id === taskId) {
        setStatus((prev) => ({
          ...prev,
          status: 'failed',
          error: event.payload?.error,
        }));
      }
    });

    return () => {
      unsubscribe();
      unsubscribeComplete();
      unsubscribeError();
    };
  }, [taskId]);

  return status;
}
