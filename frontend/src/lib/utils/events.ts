// 简单的事件系统，用于跨组件通信
type EventCallback<TArgs extends unknown[] = unknown[]> = (...args: TArgs) => void;

class EventEmitter {
  private events: Record<string, Array<EventCallback<unknown[]>>> = {};

  on<TArgs extends unknown[]>(event: string, callback: EventCallback<TArgs>): void {
    if (!this.events[event]) {
      this.events[event] = [];
    }
    this.events[event].push(callback as EventCallback<unknown[]>);
  }

  off<TArgs extends unknown[]>(event: string, callback: EventCallback<TArgs>): void {
    if (!this.events[event]) return;

    const index = this.events[event].indexOf(callback as EventCallback<unknown[]>);
    if (index > -1) {
      this.events[event].splice(index, 1);
    }
  }

  emit<TArgs extends unknown[]>(event: string, ...args: TArgs): void {
    if (!this.events[event]) return;

    this.events[event].forEach(callback => {
      try {
        (callback as EventCallback<TArgs>)(...args);
      } catch (error) {
        console.error(`Error in event callback for ${event}:`, error);
      }
    });
  }
}

export const appEvents = new EventEmitter();

// 定义事件名称常量
export const AppEvents = {
  UPLOAD_COMPLETED: 'upload:completed',
  ARCHIVES_REFRESH: 'archives:refresh',
  SEARCH_RESET: 'search:reset',
  FILTER_OPEN: 'filter:open',
  HOME_VIEW_MODE_CHANGE: 'home:view-mode-change',
} as const;
