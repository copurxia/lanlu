// 简单的事件系统，用于跨组件通信
type EventCallback = (...args: any[]) => void;

class EventEmitter {
  private events: Record<string, EventCallback[]> = {};

  on(event: string, callback: EventCallback): void {
    if (!this.events[event]) {
      this.events[event] = [];
    }
    this.events[event].push(callback);
  }

  off(event: string, callback: EventCallback): void {
    if (!this.events[event]) return;

    const index = this.events[event].indexOf(callback);
    if (index > -1) {
      this.events[event].splice(index, 1);
    }
  }

  emit(event: string, ...args: any[]): void {
    if (!this.events[event]) return;

    this.events[event].forEach(callback => {
      try {
        callback(...args);
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
} as const;