import { handleLongImageEvent } from './longImageEvents';

describe('handleLongImageEvent', () => {
  it('ignores events for another view', () => {
    const onLoad = jest.fn();
    handleLongImageEvent({ handle: 'other', type: 'load' }, 'mine', { onLoad });
    expect(onLoad).not.toHaveBeenCalled();
  });

  it('reports source dimensions', () => {
    const onSize = jest.fn();
    handleLongImageEvent(
      { handle: 'mine', type: 'size', payload: { width: 1080, height: 12000 } },
      'mine',
      { onSize },
    );
    expect(onSize).toHaveBeenCalledWith(1080, 12000);
  });

  it('reports progress and ignores non-numeric payloads', () => {
    const onProgress = jest.fn();
    handleLongImageEvent(
      { handle: 'mine', type: 'progress', payload: { loaded: 50, total: 200 } },
      'mine',
      { onProgress },
    );
    expect(onProgress).toHaveBeenCalledWith(50, 200);
    onProgress.mockClear();
    handleLongImageEvent({ handle: 'mine', type: 'progress' }, 'mine', {
      onProgress,
    });
    expect(onProgress).toHaveBeenCalledWith(0, 0);
  });

  it('maps load start, load and error', () => {
    const onLoadStart = jest.fn();
    const onLoad = jest.fn();
    const onError = jest.fn();
    const handlers = { onLoadStart, onLoad, onError };
    handleLongImageEvent(
      { handle: 'mine', type: 'loadStart' },
      'mine',
      handlers,
    );
    handleLongImageEvent({ handle: 'mine', type: 'load' }, 'mine', handlers);
    handleLongImageEvent(
      { handle: 'mine', type: 'error', payload: { message: 'decode failed' } },
      'mine',
      handlers,
    );
    expect(onLoadStart).toHaveBeenCalledTimes(1);
    expect(onLoad).toHaveBeenCalledTimes(1);
    expect(onError).toHaveBeenCalledWith('decode failed');
  });
});
