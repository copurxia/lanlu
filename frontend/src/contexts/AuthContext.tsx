'use client';

import { createContext, useContext, useState, useEffect, ReactNode } from 'react';
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
  const [token, setToken] = useState<string | null>(null);
  const [user, setUser] = useState<AuthUser | null>(null);

  useEffect(() => {
    // 只在客户端执行
    if (typeof window !== 'undefined') {
      // 从 localStorage 读取 token
      const savedToken = localStorage.getItem('auth_token');
      if (savedToken) {
        setToken(savedToken);
      }
    }
  }, []);

  useEffect(() => {
    if (!token) {
      setUser(null);
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
          setUser(null);
          if (typeof window !== 'undefined') {
            localStorage.removeItem('auth_token');
          }
        }
      }
    })();
  }, [token]);

  // 监听 API 401 错误事件
  useEffect(() => {
    if (typeof window === 'undefined') {
      return;
    }

    const handleUnauthorized = () => {
      setToken(null);
      setUser(null);
    };

    window.addEventListener('auth:unauthorized', handleUnauthorized);
    return () => {
      window.removeEventListener('auth:unauthorized', handleUnauthorized);
    };
  }, []);

  const login = (newToken: string, newUser?: AuthUser | null) => {
    setToken(newToken);
    if (newUser) {
      setUser(newUser);
    }
    if (typeof window !== 'undefined') {
      localStorage.setItem('auth_token', newToken);
      // 登录成功后刷新页面以确保状态完全同步
      window.location.reload();
    }
  };

  const logout = () => {
    setToken(null);
    setUser(null);
    if (typeof window !== 'undefined') {
      localStorage.removeItem('auth_token');
    }
  };

  const refreshMe = async () => {
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

  const context = useContext(AuthContext);
  if (context === undefined) {
    throw new Error('useAuth must be used within an AuthProvider');
  }
  return context;
}
