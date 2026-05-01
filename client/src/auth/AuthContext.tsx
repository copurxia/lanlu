import React, {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useState,
} from 'react';

import {extractApiError, setUnauthorizedHandler} from '../api/client';
import * as LanluApi from '../api/lanlu';
import {
  deleteServer as deleteStoredServer,
  getActiveServer,
  getServers,
  LanluServer,
  setActiveServerId,
  touchServer,
  upsertServer,
} from '../storage/servers';
import {clearStoredToken, getStoredToken, setStoredToken} from '../storage/token';
import type {AuthUser} from '../types/api';

type AuthStatus = 'booting' | 'serverList' | 'login' | 'authenticated';

type AuthContextValue = {
  status: AuthStatus;
  servers: LanluServer[];
  activeServer: LanluServer | null;
  token: string | null;
  user: AuthUser | null;
  reloadServers: () => Promise<void>;
  saveServer: (params: {id?: string; name: string; baseUrl: string}) => Promise<LanluServer>;
  deleteServer: (serverId: string) => Promise<void>;
  selectServer: (server: LanluServer) => Promise<void>;
  showServerList: () => Promise<void>;
  signIn: (params: {username: string; password: string}) => Promise<void>;
  signOut: () => Promise<void>;
  refreshMe: () => Promise<void>;
};

const AuthContext = createContext<AuthContextValue | null>(null);

export function AuthProvider({children}: {children: React.ReactNode}) {
  const [status, setStatus] = useState<AuthStatus>('booting');
  const [servers, setServers] = useState<LanluServer[]>([]);
  const [activeServer, setActiveServer] = useState<LanluServer | null>(null);
  const [token, setToken] = useState<string | null>(null);
  const [user, setUser] = useState<AuthUser | null>(null);

  const reloadServers = useCallback(async () => {
    setServers(await getServers());
  }, []);

  const clearSessionState = useCallback(() => {
    setToken(null);
    setUser(null);
  }, []);

  const showServerList = useCallback(async () => {
    await setActiveServerId(null);
    setActiveServer(null);
    clearSessionState();
    await reloadServers();
    setStatus('serverList');
  }, [clearSessionState, reloadServers]);

  const refreshMe = useCallback(async () => {
    const currentUser = await LanluApi.fetchMe();
    setUser(currentUser);
    setStatus('authenticated');
  }, []);

  const selectServer = useCallback(
    async (server: LanluServer) => {
      await setActiveServerId(server.id);
      await touchServer(server.id);
      setActiveServer(server);
      await reloadServers();
      const storedToken = await getStoredToken(server.id);
      setToken(storedToken);
      if (!storedToken) {
        setUser(null);
        setStatus('login');
        return;
      }
      try {
        const currentUser = await LanluApi.fetchMe();
        setUser(currentUser);
        setStatus('authenticated');
      } catch (error) {
        console.warn('Failed to restore server session:', extractApiError(error));
        await clearStoredToken(server.id);
        clearSessionState();
        setStatus('login');
      }
    },
    [clearSessionState, reloadServers],
  );

  useEffect(() => {
    setUnauthorizedHandler(() => {
      const serverId = activeServer?.id;
      clearStoredToken(serverId).catch(error =>
        console.warn('Failed to clear auth:', error),
      );
      clearSessionState();
      setStatus(activeServer ? 'login' : 'serverList');
    });
    return () => setUnauthorizedHandler(null);
  }, [activeServer, clearSessionState]);

  useEffect(() => {
    let cancelled = false;
    async function boot() {
      const [storedServers, storedActiveServer] = await Promise.all([
        getServers(),
        getActiveServer(),
      ]);
      if (cancelled) {
        return;
      }
      setServers(storedServers);
      if (!storedActiveServer) {
        setStatus('serverList');
        return;
      }
      await selectServer(storedActiveServer);
    }

    boot().catch(error => {
      console.warn('Failed to boot auth state:', error);
      setStatus('serverList');
    });
    return () => {
      cancelled = true;
    };
  }, [selectServer]);

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
      await deleteStoredServer(serverId);
      if (activeServer?.id === serverId) {
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
      const nextToken = response.data?.token?.token;
      if (response.code === 202 || response.data?.challengeId) {
        throw new Error('This mobile client does not support TOTP login yet.');
      }
      if (!nextToken) {
        throw new Error(response.message || 'Login did not return a token.');
      }
      await setStoredToken(nextToken, activeServer.id);
      await touchServer(activeServer.id);
      await reloadServers();
      setToken(nextToken);
      setUser(response.data?.user || null);
      setStatus('authenticated');
      if (!response.data?.user) {
        await refreshMe();
      }
    },
    [activeServer, refreshMe, reloadServers],
  );

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
    clearSessionState();
    setStatus(activeServer ? 'login' : 'serverList');
  }, [activeServer, clearSessionState]);

  const value = useMemo<AuthContextValue>(
    () => ({
      status,
      servers,
      activeServer,
      token,
      user,
      reloadServers,
      saveServer,
      deleteServer,
      selectServer,
      showServerList,
      signIn,
      signOut,
      refreshMe,
    }),
    [
      activeServer,
      deleteServer,
      refreshMe,
      reloadServers,
      saveServer,
      selectServer,
      servers,
      showServerList,
      signIn,
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
