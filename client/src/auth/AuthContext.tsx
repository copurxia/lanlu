import React, {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useRef,
  useState,
} from 'react';

import {extractApiError, isNetworkError, setUnauthorizedHandler, setOfflineHandler, setOnlineHandler} from '../api/client';
import * as LanluApi from '../api/lanlu';
import {
  deleteServer as deleteStoredServer,
  getActiveServerId,
  getServers,
  LanluServer,
  setActiveServerId,
  touchServer,
  upsertServer,
} from '../storage/servers';
import {clearStoredToken, getStoredToken, setStoredToken} from '../storage/token';
import {getStoredStringSync, setStoredStringSync} from '../storage/mmkv';
import {perfMark, perfSince} from '../perf/perf';
import {clearSessionCache, primeSession} from './session';
import {useOfflineProgressQueue} from '../stores/offlineProgressQueue';
import type {AuthUser} from '../types/api';

type AuthStatus = 'booting' | 'serverList' | 'login' | 'authenticated';

type AuthContextValue = {
  status: AuthStatus;
  servers: LanluServer[];
  activeServer: LanluServer | null;
  token: string | null;
  user: AuthUser | null;
  isOffline: boolean;
  reloadServers: () => Promise<void>;
  saveServer: (params: {id?: string; name: string; baseUrl: string}) => Promise<LanluServer>;
  deleteServer: (serverId: string) => Promise<void>;
  selectServer: (server: LanluServer) => Promise<void>;
  showServerList: () => Promise<void>;
  signIn: (params: {username: string; password: string}) => Promise<void>;
  totpChallenge: {challengeId: string} | null;
  verifyTotp: (params: {code: string; recoveryCode?: string}) => Promise<void>;
  dismissTotp: () => void;
  signOut: () => Promise<void>;
  refreshMe: () => Promise<void>;
  reconnect: () => Promise<void>;
};

const USER_CACHE_KEY = 'cached_user';

function userCacheKey(serverId?: string | null) {
  return serverId ? `${USER_CACHE_KEY}:${serverId}` : USER_CACHE_KEY;
}

function loadCachedUser(serverId?: string | null): AuthUser | null {
  try {
    const raw = getStoredStringSync(userCacheKey(serverId));
    return raw ? JSON.parse(raw) : null;
  } catch { return null; }
}

/** Keychain has no synchronous API, so tokens are mirrored into MMKV on every
 *  write and the boot path reads the mirror synchronously. The Keychain value
 *  stays the source of truth for writes/clears. */
function loadStoredTokenSync(serverId?: string | null): string | null {
  try {
    return getStoredStringSync(`auth_token_mirror:${serverId || 'legacy'}`) || null;
  } catch {
    return null;
  }
}

function mirrorToken(token: string | null, serverId?: string | null) {
  try {
    setStoredStringSync(`auth_token_mirror:${serverId || 'legacy'}`, token || '');
  } catch {}
}

function saveCachedUser(user: AuthUser, serverId?: string | null) {
  try {
    const serialized = JSON.stringify(user);
    if (serverId) {
      setStoredStringSync(userCacheKey(serverId), serialized);
    }
    setStoredStringSync(USER_CACHE_KEY, serialized);
  } catch {}
}

function clearCachedUser(serverId?: string | null) {
  try {
    if (serverId) {
      setStoredStringSync(userCacheKey(serverId), '');
    } else {
      setStoredStringSync(USER_CACHE_KEY, '');
    }
  } catch {}
}

const AuthContext = createContext<AuthContextValue | null>(null);

export function AuthProvider({children}: {children: React.ReactNode}) {
  // Restore persisted state synchronously: every read below is backed by MMKV,
  // so the first paint can be the real screen (home / server list / login)
  // instead of a two-stage boot spinner.
  const [initial] = useState(() => {
    perfMark('auth.boot.start');
    const servers = getServers();
    const activeId = getActiveServerId();
    const activeServer = activeId
      ? servers.find(server => server.id === activeId) || null
      : null;
    if (!activeServer) {
      return {
        servers,
        activeServer: null,
        token: null,
        user: null,
        status: 'serverList' as AuthStatus,
      };
    }
    const token = loadStoredTokenSync(activeServer.id);
    const user = token ? loadCachedUser(activeServer.id) : null;
    const status: AuthStatus = !token ? 'login' : user ? 'authenticated' : 'booting';
    return {servers, activeServer, token, user, status};
  });
  const [status, setStatus] = useState<AuthStatus>(initial.status);
  const [servers, setServers] = useState<LanluServer[]>(initial.servers);
  const [activeServer, setActiveServer] = useState<LanluServer | null>(initial.activeServer);
  const [token, setToken] = useState<string | null>(initial.token);
  const [user, setUser] = useState<AuthUser | null>(initial.user);
  const [isOffline, setIsOffline] = useState(false);
  const [totpChallenge, setTotpChallenge] = useState<{challengeId: string} | null>(null);
  const bootPrimed = useRef(false);
  const flushQueue = useOfflineProgressQueue(s => s.flushQueue);

  const flushProgressIfNeeded = useCallback(async () => {
    if (activeServer?.id) {
      const synced = await flushQueue(activeServer.id);
      if (synced > 0) {
        console.log(`Synced ${synced} deferred progress entries`);
      }
    }
  }, [activeServer?.id, flushQueue]);

  const reloadServers = useCallback(async () => {
    setServers(await getServers());
  }, []);

  const clearSessionState = useCallback(() => {
    setToken(null);
    setUser(null);
  }, []);

  const showServerList = useCallback(async () => {
    await setActiveServerId(null);
    clearSessionCache();
    setActiveServer(null);
    clearSessionState();
    await reloadServers();
    setStatus('serverList');
  }, [clearSessionState, reloadServers]);

  const refreshMe = useCallback(async () => {
    const currentUser = await LanluApi.fetchMe();
    saveCachedUser(currentUser, activeServer?.id);
    setUser(currentUser);
    setStatus('authenticated');
  }, [activeServer?.id]);

  const selectServer = useCallback(
    async (server: LanluServer) => {
      await setActiveServerId(server.id);
      setActiveServer(server);
      const storedToken = await getStoredToken(server.id);
      // Keep the MMKV mirror in step so the next cold boot can restore the
      // session synchronously (Keychain itself has no sync read).
      mirrorToken(storedToken, server.id);
      setToken(storedToken);
      primeSession(server, storedToken);
      perfMark('auth.server_ready', {hasToken: Boolean(storedToken)});
      // lastUsedAt / server-list ordering is not part of first paint.
      touchServer(server.id)
        .then(reloadServers)
        .catch(error => console.warn('Failed to update server metadata:', error));
      if (!storedToken) {
        setUser(null);
        setStatus('login');
        return;
      }
      // Render the cached identity immediately; validate it in the background.
      const cachedUser = loadCachedUser(server.id);
      if (cachedUser) {
        setUser(cachedUser);
        setStatus('authenticated');
        perfMark('auth.cached_user');
      }
      let probeId: ReturnType<typeof setTimeout> | undefined;
      try {
        const controller = new AbortController();
        probeId = setTimeout(() => controller.abort(), 3500);
        const currentUser = await LanluApi.fetchMe({timeout: 3500, signal: controller.signal});
        clearTimeout(probeId);
        saveCachedUser(currentUser, server.id);
        setUser(currentUser);
        setStatus('authenticated');
        setIsOffline(false);
        perfSince('auth.me_ready', 'auth.server_ready');
      } catch (error) {
        if (probeId) clearTimeout(probeId);
        if (isNetworkError(error)) {
          const cached = loadCachedUser(server.id);
          setUser(cached);
          setStatus('authenticated');
          setIsOffline(true);
          perfMark('auth.offline_restore');
          return;
        }
        console.warn('Failed to restore server session:', extractApiError(error));
        await clearStoredToken(server.id);
        mirrorToken(null, server.id);
        clearSessionCache();
        clearSessionState();
        setStatus('login');
      }
    },
    [clearSessionState, reloadServers],
  );

  useEffect(() => {
    setOfflineHandler(() => {
      setIsOffline(true);
    });
    setOnlineHandler(() => {
      setIsOffline(false);
    });
    return () => {
      setOfflineHandler(null);
      setOnlineHandler(null);
    };
  }, []);

  useEffect(() => {
    if (!isOffline && activeServer?.id) {
      flushProgressIfNeeded().catch(err =>
        console.warn('Failed to flush deferred progress:', err),
      );
    }
  }, [isOffline, flushProgressIfNeeded, activeServer?.id]);

  useEffect(() => {
    setUnauthorizedHandler(() => {
      const serverId = activeServer?.id;
      clearStoredToken(serverId).catch(error =>
        console.warn('Failed to clear auth:', error),
      );
      mirrorToken(null, serverId);
      clearSessionCache();
      clearCachedUser(serverId);
      clearSessionState();
      setStatus(activeServer ? 'login' : 'serverList');
    });
    return () => setUnauthorizedHandler(null);
  }, [activeServer, clearSessionState]);

  useEffect(() => {
    if (bootPrimed.current) return;
    bootPrimed.current = true;
    perfMark('auth.boot.sync_done', {status: initial.status});
    // Nothing to validate: the synchronous restore already resolved the screen.
    if (initial.status !== 'booting' || !initial.activeServer) {
      return;
    }
    // Token exists but no cached identity: probe the server, then commit.
    let cancelled = false;
    selectServer(initial.activeServer).catch(error => {
      if (!cancelled) {
        console.warn('Failed to restore server session:', extractApiError(error));
        setStatus('login');
      }
    });
    return () => {
      cancelled = true;
    };
  }, [initial.activeServer, initial.status, selectServer]);

  const saveServer = useCallback(
    async (params: {id?: string; name: string; baseUrl: string}) => {
      const server = await upsertServer(params);
      await reloadServers();
      return server;
    },
    [reloadServers],
  );

  const deleteServer = useCallback(
    async (serverId: string) => {
      await clearStoredToken(serverId);
      mirrorToken(null, serverId);
      await deleteStoredServer(serverId);
      if (activeServer?.id === serverId) {
        clearSessionCache();
        clearCachedUser(serverId);
        setActiveServer(null);
        clearSessionState();
        setStatus('serverList');
      }
      await reloadServers();
    },
    [activeServer?.id, clearSessionState, reloadServers],
  );

  const signIn = useCallback(
    async (params: {username: string; password: string}) => {
      if (!activeServer) {
        throw new Error('Select a server before signing in.');
      }
      const response = await LanluApi.login({
        username: params.username,
        password: params.password,
      });
      if (response.code === 202 || response.data?.challengeId) {
        setTotpChallenge({challengeId: response.data?.challengeId!});
        return;
      }
      const nextToken = response.data?.token?.token;
      if (!nextToken) {
        throw new Error(response.message || 'Login did not return a token.');
      }
      await setStoredToken(nextToken, activeServer.id);
      mirrorToken(nextToken, activeServer.id);
      primeSession(activeServer, nextToken);
      touchServer(activeServer.id)
        .then(reloadServers)
        .catch(error => console.warn('Failed to update server metadata:', error));
      setToken(nextToken);
      const nextUser = response.data?.user || null;
      if (nextUser) {
        saveCachedUser(nextUser, activeServer.id);
      }
      setUser(nextUser);
      setStatus('authenticated');
      if (!nextUser) {
        await refreshMe();
      }
    },
    [activeServer, refreshMe, reloadServers],
  );

  const verifyTotp = useCallback(
    async (params: {code: string; recoveryCode?: string}) => {
      if (!totpChallenge) throw new Error('No TOTP challenge in progress');
      const response = await LanluApi.verifyTotpLogin({
        challengeId: totpChallenge.challengeId,
        code: params.code,
        recoveryCode: params.recoveryCode,
      });
      const nextToken = response.data?.token?.token;
      if (!nextToken) {
        throw new Error(response.message || 'TOTP verification failed');
      }
      setTotpChallenge(null);
      if (!activeServer) throw new Error('No active server');
      await setStoredToken(nextToken, activeServer.id);
      mirrorToken(nextToken, activeServer.id);
      primeSession(activeServer, nextToken);
      touchServer(activeServer.id)
        .then(reloadServers)
        .catch(error => console.warn('Failed to update server metadata:', error));
      setToken(nextToken);
      const nextUser = response.data?.user || null;
      if (nextUser) {
        saveCachedUser(nextUser, activeServer.id);
      }
      setUser(nextUser);
      setStatus('authenticated');
      if (!nextUser) {
        await refreshMe();
      }
    },
    [totpChallenge, activeServer, refreshMe, reloadServers],
  );

  const dismissTotp = useCallback(() => setTotpChallenge(null), []);

  const signOut = useCallback(async () => {
    const serverId = activeServer?.id;
    try {
      await LanluApi.logout();
    } catch (error) {
      const message = extractApiError(error, '');
      if (message) {
        console.warn('Logout failed:', message);
      }
    }
    await clearStoredToken(serverId);
    mirrorToken(null, serverId);
    clearSessionCache();
    clearCachedUser(serverId);
    clearSessionState();
    setIsOffline(false);
    setStatus(activeServer ? 'login' : 'serverList');
  }, [activeServer, clearSessionState]);

  const reconnect = useCallback(async () => {
    if (!activeServer) {
      return;
    }
    let probeId: ReturnType<typeof setTimeout> | undefined;
    try {
      const controller = new AbortController();
      probeId = setTimeout(() => controller.abort(), 3500);
      const currentUser = await LanluApi.fetchMe({timeout: 3500, signal: controller.signal});
      clearTimeout(probeId);
      saveCachedUser(currentUser, activeServer.id);
      setUser(currentUser);
      setIsOffline(false);
      await flushProgressIfNeeded();
      setStatus('authenticated');
    } catch (error) {
      if (probeId) clearTimeout(probeId);
      if (isNetworkError(error)) {
        return;
      }
      await clearStoredToken(activeServer.id);
      mirrorToken(null, activeServer.id);
      clearSessionCache();
      clearCachedUser(activeServer.id);
      clearSessionState();
      setStatus('login');
    }
  }, [activeServer, clearSessionState, flushProgressIfNeeded]);

  const value = useMemo<AuthContextValue>(
    () => ({
      status,
      servers,
      activeServer,
      token,
      user,
      isOffline,
      reloadServers,
      saveServer,
      deleteServer,
      selectServer,
      showServerList,
      signIn,
      totpChallenge,
      verifyTotp,
      dismissTotp,
      signOut,
      refreshMe,
      reconnect,
    }),
    [
      activeServer,
      deleteServer,
      isOffline,
      reconnect,
      refreshMe,
      reloadServers,
      saveServer,
      selectServer,
      servers,
      showServerList,
      signIn,
      totpChallenge,
      verifyTotp,
      dismissTotp,
      signOut,
      status,
      token,
      user,
    ],
  );

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>;
}

export function useAuth() {
  const context = useContext(AuthContext);
  if (!context) {
    throw new Error('useAuth must be used within AuthProvider');
  }
  return context;
}
