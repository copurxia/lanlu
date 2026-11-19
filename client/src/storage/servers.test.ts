import { testServer } from '../api/lanlu';
import {
  getActiveServer,
  getServers,
  isSupportedServerUrl,
  normalizeServerUrl,
  requireSupportedServerUrl,
  saveServers,
  setActiveServerId,
  upsertServer,
} from './servers';

describe('server url validation', () => {
  beforeEach(async () => {
    await saveServers([]);
    await setActiveServerId(null);
  });

  it('normalizes whitespace and trailing slashes', () => {
    expect(normalizeServerUrl('  https://lanlu.example///  ')).toBe(
      'https://lanlu.example',
    );
  });

  it('accepts explicit http and https urls only', () => {
    expect(isSupportedServerUrl('https://lanlu.example')).toBe(true);
    expect(isSupportedServerUrl('http://192.168.1.5:8080/')).toBe(true);
    expect(isSupportedServerUrl('https://lanlu.example/lanlu')).toBe(true);

    expect(isSupportedServerUrl('192.168.1.5:8080')).toBe(false);
    expect(isSupportedServerUrl('lanlu.example')).toBe(false);
    expect(isSupportedServerUrl('ftp://lanlu.example')).toBe(false);
    expect(isSupportedServerUrl('https://')).toBe(false);
    expect(isSupportedServerUrl('')).toBe(false);
    expect(isSupportedServerUrl('https://lanlu example')).toBe(false);
  });

  it('throws user-facing errors from the requirement helper', () => {
    expect(requireSupportedServerUrl('  https://lanlu.example/ ')).toBe(
      'https://lanlu.example',
    );
    expect(() => requireSupportedServerUrl('')).toThrow(/required/);
    expect(() => requireSupportedServerUrl('192.168.1.5:8080')).toThrow(
      /must start with http:\/\/ or https:\/\//,
    );
  });

  it('rejects saving a scheme-less server without writing it', async () => {
    await expect(
      upsertServer({name: 'Legacy', baseUrl: '192.168.1.5:8080'}),
    ).rejects.toThrow(/must start with http:\/\/ or https:\/\//);

    expect(getServers()).toEqual([]);
  });

  it('saves valid servers with a normalized base url', async () => {
    const saved = await upsertServer({
      name: '',
      baseUrl: ' https://lanlu.example/ ',
    });

    expect(saved.baseUrl).toBe('https://lanlu.example');
    expect(getServers().map(server => server.id)).toContain(saved.id);
  });

  it('keeps legacy invalid entries visible and rejects them on the test path', async () => {
    await saveServers([
      {id: 'legacy', name: 'Legacy', baseUrl: '192.168.1.5:8080'},
    ]);
    await setActiveServerId('legacy');

    expect(getServers()).toHaveLength(1);
    const active = await getActiveServer();
    expect(active?.baseUrl).toBe('192.168.1.5:8080');
    expect(isSupportedServerUrl(active?.baseUrl || '')).toBe(false);

    await expect(testServer(active?.baseUrl || '')).rejects.toThrow(
      /must start with http:\/\/ or https:\/\//,
    );
  });
});
