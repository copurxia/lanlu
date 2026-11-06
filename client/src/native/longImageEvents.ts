export type LongImageEvent = {
  handle?: string;
  type?: string;
  payload?: {
    width?: number;
    height?: number;
    loaded?: number;
    total?: number;
    message?: string;
  };
};

export type LongImageEventHandlers = {
  onSize?: (width: number, height: number) => void;
  onLoadStart?: () => void;
  onLoad?: () => void;
  onProgress?: (loaded: number, total: number) => void;
  onError?: (message?: string) => void;
};

/**
 * Routes one native event to the handlers of the matching view. Kept pure so
 * the JS/native event contract is testable without a device.
 */
export function handleLongImageEvent(
  event: LongImageEvent | undefined,
  handle: string,
  handlers: LongImageEventHandlers,
): void {
  if (!event || event.handle !== handle) return;
  switch (event.type) {
    case 'size': {
      const width = Number(event.payload?.width);
      const height = Number(event.payload?.height);
      if (Number.isFinite(width) && Number.isFinite(height)) {
        handlers.onSize?.(width, height);
      }
      break;
    }
    case 'loadStart':
      handlers.onLoadStart?.();
      break;
    case 'load':
      handlers.onLoad?.();
      break;
    case 'progress':
      handlers.onProgress?.(
        Number(event.payload?.loaded) || 0,
        Number(event.payload?.total) || 0,
      );
      break;
    case 'error':
      handlers.onError?.(event.payload?.message);
      break;
    default:
      break;
  }
}
