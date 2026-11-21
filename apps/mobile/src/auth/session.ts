import type {LanluServer} from '../storage/servers';
import {getActiveServer} from '../storage/servers';
import {getStoredToken} from '../storage/token';

export type Session = {
  server: LanluServer | null;
  token: string | null;
};

const EMPTY_SESSION: Session = {server: null, token: null};

let session: Session | null = null;
let hydrating: Promise<Session> | null = null;

export function primeSession(server: LanluServer | null, token: string | null): Session {
  session = {server, token};
  hydrating = Promise.resolve(session);
  return session;
}

export function getSessionSnapshot(): Session | null {
  return session;
}

export function clearSessionCache(): void {
  session = EMPTY_SESSION;
  hydrating = Promise.resolve(EMPTY_SESSION);
}

export function invalidateSessionCache(): void {
  session = null;
  hydrating = null;
}

/**
 * Returns the active server/token from memory. The first call hydrates from
 * MMKV + Keychain; every later call is allocation-only. AuthProvider primes
 * this cache before rendering authenticated screens.
 */
export function getSession(): Promise<Session> {
  if (session) {
    return Promise.resolve(session);
  }
  if (!hydrating) {
    hydrating = (async () => {
      const server = await getActiveServer();
      const token = await getStoredToken(server?.id);
      session = {server, token};
      return session;
    })();
  }
  return hydrating;
}
