'use client';

import React, { createContext, useContext, useState, useEffect, ReactNode, useCallback, useRef } from 'react';
import type { AuthUser } from '@/types/auth';
import { AuthService } from '@/lib/services/auth-service';
import { extractApiError } from '@/lib/utils/api-utils';

type AuthUserStatus = 'anonymous' | 'loading' | 'resolved' | 'error';

interface AuthContextType {
  token: string | null;
  user: AuthUser | null;
  isAuthenticated: boolean;
  userStatus: AuthUserStatus;
  login: (token?: string | null, user?: AuthUser | null) => void;
  logout: () => Promise<void>;
  refreshMe: () => Promise<void>;
  ensureMe: () => Promise<AuthUser | null>;
}

const AuthContext = createContext<AuthContextType | undefined>(undefined);

export function AuthProvider({ children }: { children: ReactNode }) {
  const [token, setToken] = useState<string | null>(null);
  const [user, setUser] = useState<AuthUser | null>(null);
  const [userStatus, setUserStatus] = useState<AuthUserStatus>('anonymous');
  const meRequestRef = useRef<Promise<AuthUser | null> | null>(null);

  useEffect(() => {
    if (typeof window === 'undefined') {
      return;
    }
    setToken(null);
    setUser(null);
    setUserStatus('loading');
  }, []);

  const clearAuthState = useCallback(() => {
    meRequestRef.current = null;
    setToken(null);
    setUser(null);
    setUserStatus('anonymous');
  }, []);

  const fetchMe = useCallback(async (force: boolean): Promise<AuthUser | null> => {
    if (!token && userStatus !== 'loading') {
      setUser(null);
      setUserStatus('anonymous');
      return null;
    }

    if (!force && user) {
      return user;
    }

    if (meRequestRef.current) {
      return meRequestRef.current;
    }

    setUserStatus('loading');
    const request = (async () => {
      try {
        const me = await AuthService.me();
        const currentUser = me.data.user;
        setToken('cookie-session');
        setUser(currentUser);
        setUserStatus('resolved');
        return currentUser;
      } catch (e) {
        const status =
          typeof e === 'object' && e !== null && 'response' in e
            ? Number((e as { response?: { status?: unknown } }).response?.status)
            : Number((e as { status?: unknown })?.status);
        if (status === 401) {
          clearAuthState();
          return null;
        }
        setUserStatus('error');
        throw new Error(extractApiError(e, 'Failed to fetch current user'));
      } finally {
        meRequestRef.current = null;
      }
    })();

    meRequestRef.current = request;
    return request;
  }, [clearAuthState, token, user, userStatus]);

  // 监听 API 401 错误事件
  useEffect(() => {
    if (typeof window === 'undefined') {
      return;
    }

    const handleUnauthorized = () => {
      clearAuthState();
      // 重定向到登录页，保留当前路径用于登录后跳转
      const currentPath = window.location.pathname;
      const redirectParam = currentPath === '/' ? '' : `?redirect=${encodeURIComponent(currentPath)}`;
      window.location.href = `/login${redirectParam}`;
    };

    window.addEventListener('auth:unauthorized', handleUnauthorized);
    return () => {
      window.removeEventListener('auth:unauthorized', handleUnauthorized);
    };
  }, [clearAuthState]);

  const login = (newToken?: string | null, newUser?: AuthUser | null) => {
    meRequestRef.current = null;
    setToken(newToken || 'cookie-session');
    if (newUser) {
      setUser(newUser);
      setUserStatus('resolved');
    } else {
      setUser(null);
      setUserStatus('loading');
      void fetchMe(true).catch(() => {});
    }
  };

  const logout = async () => {
    try {
      await AuthService.logout();
    } catch {
      // Ignore logout API errors and clear local state anyway.
    }
    clearAuthState();
    if (typeof window !== 'undefined') {
      window.location.href = '/login';
    }
  };

  const refreshMe = useCallback(async () => {
    await fetchMe(true);
  }, [fetchMe]);

  const ensureMe = useCallback(async () => {
    return fetchMe(false);
  }, [fetchMe]);

  // 自动补全用户信息：当有 cookie 会话但 user 为空时，自动调用 ensureMe 拉取用户信息（含 isAdmin）
  useEffect(() => {
    if (!user && userStatus === 'loading') {
      void ensureMe();
    }
  }, [token, user, userStatus, ensureMe]);

  const value = {
    token,
    user,
    isAuthenticated: !!token,
    userStatus,
    login,
    logout,
    refreshMe,
    ensureMe,
  };

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>;
}

export function useAuth() {
  // 使用 useContext 必须在组件的顶层调用，不能有条件判断
  const context = useContext(AuthContext);
  
  // 只在服务端静态生成期间返回回退值，避免调用useContext
  // 客户端环境下正常使用 Context，即使是在静态导出模式下
  if (typeof window === 'undefined' && process.env.NEXT_PUBLIC_STATIC_EXPORT === 'true') {
    return {
      token: null,
      user: null,
      isAuthenticated: false,
      userStatus: 'anonymous' as const,
      login: () => {},
      logout: async () => {},
      refreshMe: async () => {},
      ensureMe: async () => null,
    };
  }

  if (context === undefined) {
    throw new Error('useAuth must be used within an AuthProvider');
  }
  return context;
}
