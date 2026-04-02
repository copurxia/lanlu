'use client';

import React, { createContext, useContext, useState, useEffect, ReactNode, useCallback, useRef } from 'react';
import type { AuthUser } from '@/types/auth';
import { AuthService } from '@/lib/services/auth-service';
import { setAuthTokenCookie } from '@/lib/api';

type AuthUserStatus = 'anonymous' | 'token-only' | 'loading' | 'resolved' | 'error';

interface AuthContextType {
  token: string | null;
  user: AuthUser | null;
  isAuthenticated: boolean;
  userStatus: AuthUserStatus;
  login: (token: string, user?: AuthUser | null) => void;
  logout: () => void;
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

    const savedToken = localStorage.getItem('auth_token');
    setToken(savedToken);
    setUser(null);
    setUserStatus(savedToken ? 'token-only' : 'anonymous');
    setAuthTokenCookie(savedToken);
  }, []);

  const clearAuthState = useCallback(() => {
    meRequestRef.current = null;
    setToken(null);
    setUser(null);
    setUserStatus('anonymous');
    if (typeof window !== 'undefined') {
      localStorage.removeItem('auth_token');
    }
    setAuthTokenCookie(null);
  }, []);

  const fetchMe = useCallback(async (force: boolean): Promise<AuthUser | null> => {
    if (!token) {
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
        setUser(me.data.user);
        setUserStatus('resolved');
        return me.data.user;
      } catch (e: any) {
        if (e?.response?.status === 401 || e?.status === 401) {
          clearAuthState();
          return null;
        }
        setUserStatus('error');
        throw e;
      } finally {
        meRequestRef.current = null;
      }
    })();

    meRequestRef.current = request;
    return request;
  }, [clearAuthState, token, user]);

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

  const login = (newToken: string, newUser?: AuthUser | null) => {
    meRequestRef.current = null;
    setToken(newToken);
    if (newUser) {
      setUser(newUser);
      setUserStatus('resolved');
    } else {
      setUser(null);
      setUserStatus('token-only');
    }
    if (typeof window !== 'undefined') {
      localStorage.setItem('auth_token', newToken);
      setAuthTokenCookie(newToken);
    }
  };

  const logout = () => {
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
      logout: () => {},
      refreshMe: async () => {},
      ensureMe: async () => null,
    };
  }

  if (context === undefined) {
    throw new Error('useAuth must be used within an AuthProvider');
  }
  return context;
}
