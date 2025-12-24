'use client';

import React, { createContext, useContext, useState, useEffect, ReactNode } from 'react';
import type { AuthUser } from '@/types/auth';
import { AuthService } from '@/lib/auth-service';

interface AuthContextType {
  token: string | null;
  user: AuthUser | null;
  isAuthenticated: boolean;
  login: (token: string, user?: AuthUser | null) => void;
  logout: () => void;
  refreshMe: () => Promise<void>;
}

const AuthContext = createContext<AuthContextType | undefined>(undefined);

export function AuthProvider({ children }: { children: ReactNode }) {
  // 添加mounted状态以避免水合错误
  const [mounted, setMounted] = useState(false);
  // 使用函数初始化状态，避免在 effect 中调用 setState
  const [token, setToken] = useState<string | null>(null);
  const [user, setUser] = useState<AuthUser | null>(null);

  useEffect(() => {
    setMounted(true);
  }, []);

  // 只在挂载后从localStorage读取token
  useEffect(() => {
    if (!mounted) return;

    if (typeof window !== 'undefined') {
      const savedToken = localStorage.getItem('auth_token');
      setToken(savedToken);
    }
  }, [mounted]);

  // 当token变化时，更新用户状态
  useEffect(() => {
    if (!mounted) return;

    if (!token) {
      // token不存在时，用户状态应为null
      // 使用微任务来避免同步调用setState
      Promise.resolve().then(() => setUser(null));
      return;
    }

    // 只有在 token 存在时才拉取用户信息，但不在这里验证 token 有效性
    // token 有效性由具体的 API 请求失败时处理
    void (async () => {
      try {
        const me = await AuthService.me();
        setUser(me.data.user);
      } catch (e: any) {
        // 只有在 /api/auth/me 明确返回 401 时才认为 token 无效
        // 其他错误可能是网络问题，不应该清空 token
        if (e?.response?.status === 401 || e?.status === 401) {
          setToken(null);
          if (typeof window !== 'undefined') {
            localStorage.removeItem('auth_token');
          }
        }
      }
    })();
  }, [token, mounted]);

  // 监听 API 401 错误事件
  useEffect(() => {
    if (!mounted || typeof window === 'undefined') {
      return;
    }

    const handleUnauthorized = () => {
      setToken(null);
      setUser(null);
      // 重定向到登录页，保留当前路径用于登录后跳转
      const currentPath = window.location.pathname;
      const redirectParam = currentPath === '/' ? '' : `?redirect=${encodeURIComponent(currentPath)}`;
      window.location.href = `/login${redirectParam}`;
    };

    window.addEventListener('auth:unauthorized', handleUnauthorized);
    return () => {
      window.removeEventListener('auth:unauthorized', handleUnauthorized);
    };
  }, [mounted]);

  const login = (newToken: string, newUser?: AuthUser | null) => {
    if (!mounted) return;
    setToken(newToken);
    if (newUser) {
      setUser(newUser);
    }
    if (typeof window !== 'undefined') {
      localStorage.setItem('auth_token', newToken);
      // 不再自动刷新页面，由路由跳转处理
    }
  };

  const logout = () => {
    if (!mounted) return;
    setToken(null);
    setUser(null);
    if (typeof window !== 'undefined') {
      localStorage.removeItem('auth_token');
      // 退出登录后跳转到登录页
      window.location.href = '/login';
    }
  };

  const refreshMe = async () => {
    if (!mounted) return;
    if (!token) {
      setUser(null);
      return;
    }
    const me = await AuthService.me();
    setUser(me.data.user);
  };

  const value = {
    token,
    user,
    isAuthenticated: !!token,
    login,
    logout,
    refreshMe,
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
      login: () => {},
      logout: () => {},
      refreshMe: async () => {}
    };
  }

  if (context === undefined) {
    throw new Error('useAuth must be used within an AuthProvider');
  }
  return context;
}
