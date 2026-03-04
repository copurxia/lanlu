/**
 * 事件系统 - 用于解耦状态更新与UI渲染
 */

export type TaskEventType =
  | 'task-update'
  | 'task-complete'
  | 'task-error'
  | 'task-progress'
  | 'task-discovered';

export type TaskEventData = {
  id: string;
  type: TaskEventType;
  payload?: {
    status?: string;
    progress?: number;
    message?: string;
    error?: string;
    archiveId?: string;
    downloadTaskId?: number;
    scanTaskId?: number;
    downloadProgress?: number;
    downloadMessage?: string;
    scanProgress?: number;
    scanMessage?: string;
  };
};

type EventCallback = (data: TaskEventData) => void;

class EventBus {
  private listeners = new Map<TaskEventType, Set<EventCallback>>();

  /**
   * 订阅事件
   */
  on(type: TaskEventType, callback: EventCallback): () => void {
    if (!this.listeners.has(type)) {
      this.listeners.set(type, new Set());
    }

    const callbacks = this.listeners.get(type)!;
    callbacks.add(callback);

    // 返回取消订阅函数
    return () => {
      callbacks.delete(callback);
      if (callbacks.size === 0) {
        this.listeners.delete(type);
      }
    };
  }

  /**
   * 发布事件
   */
  emit(type: TaskEventType, data: Omit<TaskEventData, 'type'>): void {
    const callbacks = this.listeners.get(type);
    if (!callbacks) return;

    const eventData: TaskEventData = {
      ...data,
      type,
    };

    callbacks.forEach(callback => {
      try {
        callback(eventData);
      } catch (error) {
        console.error(`[EventBus] Error in event callback for ${type}:`, error);
      }
    });
  }

  /**
   * 取消特定事件的所有订阅
   */
  off(type: TaskEventType): void {
    this.listeners.delete(type);
  }

  /**
   * 清空所有事件订阅
   */
  clear(): void {
    this.listeners.clear();
  }

  /**
   * 获取事件订阅数量
   */
  getListenerCount(type?: TaskEventType): number {
    if (type) {
      return this.listeners.get(type)?.size || 0;
    }
    return Array.from(this.listeners.values()).reduce((sum, callbacks) => sum + callbacks.size, 0);
  }
}

// 导出单例实例
export const eventBus = new EventBus();

// 便捷方法
export const TaskEvents = {
  update: (id: string, payload: TaskEventData['payload']) =>
    eventBus.emit('task-update', { id, payload }),

  complete: (id: string, archiveId: string) =>
    eventBus.emit('task-complete', { id, payload: { archiveId } }),

  error: (id: string, error: string) =>
    eventBus.emit('task-error', { id, payload: { error } }),

  progress: (id: string, progress: number, message?: string) =>
    eventBus.emit('task-progress', { id, payload: { progress, message } }),

  discovered: (id: string, downloadTaskId?: number, scanTaskId?: number) =>
    eventBus.emit('task-discovered', { id, payload: { downloadTaskId, scanTaskId } }),
} as const;
