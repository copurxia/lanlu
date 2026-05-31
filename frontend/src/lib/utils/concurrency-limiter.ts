/**
 * 全局并发限制器，用于限制 Source 封面/页面等资产请求的并发数。
 */
export class ConcurrencyLimiter {
  private limit: number;
  private queue: Array<() => void> = [];
  private active = 0;

  constructor(limit: number) {
    this.limit = Math.max(1, limit);
  }

  async run<T>(fn: () => Promise<T>): Promise<T> {
    if (this.active < this.limit) {
      this.active++;
      try {
        return await fn();
      } finally {
        this.active--;
        this.drain();
      }
    }

    return new Promise<T>((resolve, reject) => {
      this.queue.push(async () => {
        this.active++;
        try {
          resolve(await fn());
        } catch (e) {
          reject(e);
        } finally {
          this.active--;
          this.drain();
        }
      });
    });
  }

  private drain(): void {
    while (this.active < this.limit && this.queue.length > 0) {
      const next = this.queue.shift();
      if (next) next();
    }
  }
}

/** Source 封面资产请求全局并发限制 */
export const sourceCoverAssetLimiter = new ConcurrencyLimiter(4);

/** Source 页面资产请求全局并发限制 */
export const sourcePageAssetLimiter = new ConcurrencyLimiter(3);
