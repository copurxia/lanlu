/**
 * useTaskPoller Hook - 已简化
 *
 * SSE 订阅现在在 background.js 中运行。
 * 这个 hook 只保留空实现以保持向后兼容。
 */

import { useCallback, useRef } from 'react';
import { useSettingsStore } from '~/store/settings';
import { normalizeUrl } from '~/lib/url';

interface UseTaskPollerOptions {
  enabled?: boolean;
  config?: { maxConcurrentTasks?: number };
}

interface UseTaskPollerReturn {
  start: () => void;
  stop: () => void;
  isRunning: boolean;
}

/**
 * 使用任务同步 Hook（SSE 在 background.js 中运行）
 */
export function useTaskPoller(options: UseTaskPollerOptions = {}): UseTaskPollerReturn {
  const { enabled = true } = options;
  const { settings, hydrated } = useSettingsStore();
  const isRunningRef = useRef(false);

  const start = useCallback(() => {
    if (!enabled || !hydrated) return;

    const serverUrl = normalizeUrl(settings.serverUrl);
    const token = settings.token.trim();
    if (!serverUrl || !token) return;

    // SSE 订阅在 background.js 中自动运行
    isRunningRef.current = true;
    console.log('[useTaskPoller] SSE sync runs in background.js');
  }, [enabled, hydrated, settings.serverUrl, settings.token]);

  const stop = useCallback(() => {
    isRunningRef.current = false;
  }, []);

  return {
    start,
    stop,
    isRunning: isRunningRef.current,
  };
}

/**
 * 订阅任务事件的Hook（保留用于兼容）
 */
import { useEffect, useState } from 'react';
import type { TaskEventData } from '~/lib/events';
import { eventBus } from '~/lib/events';

interface UseTaskEventsOptions {
  taskId?: string;
}

interface UseTaskEventsReturn {
  events: TaskEventData[];
  clear: () => void;
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

  return { events, clear };
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
