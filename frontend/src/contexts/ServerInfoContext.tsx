'use client';

import React, { createContext, useContext, useState, useEffect, ReactNode, useCallback } from 'react';
import { ServerInfo } from '@/types/server';
import { ArchiveService } from '@/lib/services/archive-service';

interface ServerInfoContextType {
  serverInfo: ServerInfo | null;
  serverName: string;
  loading: boolean;
  error: string | null;
  refresh: () => Promise<void>;
}

const DEFAULT_SERVER_NAME = 'Lanlu';

const ServerInfoContext = createContext<ServerInfoContextType | undefined>(undefined);

export function ServerInfoProvider({ children }: { children: ReactNode }) {
  const [serverInfo, setServerInfo] = useState<ServerInfo | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const fetchServerInfo = useCallback(async () => {
    try {
      setLoading(true);
      setError(null);
      const info = await ArchiveService.getServerInfo();
      setServerInfo(info);
    } catch (err: any) {
      setError(err.message || 'Failed to fetch server info');
      // 保持之前的 serverInfo 或使用默认值
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    fetchServerInfo();
  }, [fetchServerInfo]);

  const serverName = serverInfo?.name || DEFAULT_SERVER_NAME;

  // 动态更新网页标题
  useEffect(() => {
    if (typeof window !== 'undefined' && serverName) {
      document.title = serverName;
    }
  }, [serverName]);

  return (
    <ServerInfoContext.Provider
      value={{
        serverInfo,
        serverName,
        loading,
        error,
        refresh: fetchServerInfo,
      }}
    >
      {children}
    </ServerInfoContext.Provider>
  );
}

export function useServerInfo() {
  const context = useContext(ServerInfoContext);

  // 服务端渲染或静态导出时返回默认值
  if (typeof window === 'undefined') {
    return {
      serverInfo: null,
      serverName: DEFAULT_SERVER_NAME,
      loading: false,
      error: null,
      refresh: async () => {},
    };
  }

  if (context === undefined) {
    throw new Error('useServerInfo must be used within a ServerInfoProvider');
  }

  return context;
}
