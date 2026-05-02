import {getStoredString, removeStoredValue, setStoredString} from './mmkv';

export type LanluServer = {
  id: string;
  name: string;
  baseUrl: string;
  lastUsedAt?: string;
};

const SERVERS_KEY = 'lanlu.servers.v1';
const ACTIVE_SERVER_ID_KEY = 'lanlu.activeServerId.v1';

export function normalizeServerUrl(input: string): string {
  return input.trim().replace(/\/+$/, '');
}

function createServerId() {
  return `server-${Date.now()}-${Math.random().toString(36).slice(2, 8)}`;
}

function normalizeServer(server: LanluServer): LanluServer {
  return {
    ...server,
    name: server.name.trim() || normalizeServerUrl(server.baseUrl),
    baseUrl: normalizeServerUrl(server.baseUrl),
  };
}

export async function getServers(): Promise<LanluServer[]> {
  const raw = await getStoredString(SERVERS_KEY);
  if (!raw) {
    return [];
  }
  try {
    const parsed = JSON.parse(raw) as LanluServer[];
    return Array.isArray(parsed)
      ? parsed.map(normalizeServer).filter(server => server.id && server.baseUrl)
      : [];
  } catch {
    return [];
  }
}

export async function saveServers(servers: LanluServer[]): Promise<void> {
  await setStoredString(SERVERS_KEY, JSON.stringify(servers.map(normalizeServer)));
}

export async function upsertServer(input: {
  id?: string;
  name: string;
  baseUrl: string;
}): Promise<LanluServer> {
  const servers = await getServers();
  const next: LanluServer = normalizeServer({
    id: input.id || createServerId(),
    name: input.name,
    baseUrl: input.baseUrl,
    lastUsedAt: new Date().toISOString(),
  });
  const index = servers.findIndex(server => server.id === next.id);
  const updated =
    index >= 0
      ? servers.map(server => (server.id === next.id ? {...server, ...next} : server))
      : [next, ...servers];
  await saveServers(updated);
  return next;
}

export async function deleteServer(serverId: string): Promise<void> {
  const servers = await getServers();
  await saveServers(servers.filter(server => server.id !== serverId));
  const activeId = await getActiveServerId();
  if (activeId === serverId) {
    await removeStoredValue(ACTIVE_SERVER_ID_KEY);
  }
}

export async function getActiveServerId(): Promise<string | null> {
  const value = await getStoredString(ACTIVE_SERVER_ID_KEY);
  return value || null;
}

export async function setActiveServerId(serverId: string | null): Promise<void> {
  if (!serverId) {
    await removeStoredValue(ACTIVE_SERVER_ID_KEY);
    return;
  }
  await setStoredString(ACTIVE_SERVER_ID_KEY, serverId);
}

export async function getActiveServer(): Promise<LanluServer | null> {
  const [servers, activeId] = await Promise.all([getServers(), getActiveServerId()]);
  if (!activeId) {
    return null;
  }
  return servers.find(server => server.id === activeId) || null;
}

export async function touchServer(serverId: string): Promise<void> {
  const servers = await getServers();
  await saveServers(
    servers.map(server =>
      server.id === serverId
        ? {...server, lastUsedAt: new Date().toISOString()}
        : server,
    ),
  );
}
