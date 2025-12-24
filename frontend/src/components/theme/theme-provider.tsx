'use client';

import { createContext, useContext, useEffect, useState } from 'react';

type Theme = 'dark' | 'light' | 'system';

type ThemeProviderProps = {
  children: React.ReactNode;
  defaultTheme?: Theme;
  storageKey?: string;
};

type ThemeProviderState = {
  theme: Theme;
  setTheme: (theme: Theme) => void;
};

const initialState: ThemeProviderState = {
  theme: 'system',
  setTheme: () => null,
};

const ThemeProviderContext = createContext<ThemeProviderState>(initialState);

export function ThemeProvider({
  children,
  defaultTheme = 'system',
  storageKey = 'lrr4cj-ui-theme',
  ...props
}: ThemeProviderProps) {
  // 添加mounted状态以避免水合错误
  const [mounted, setMounted] = useState(false);
  const [theme, setThemeState] = useState<Theme>(defaultTheme);

  useEffect(() => {
    setMounted(true);
  }, []);

  // 只有在挂载后才从localStorage读取主题
  useEffect(() => {
    if (!mounted) return;

    const savedTheme = localStorage.getItem(storageKey) as Theme;
    if (savedTheme) {
      setThemeState(savedTheme);
    }
  }, [mounted, storageKey]);

  useEffect(() => {
    if (!mounted) return;

    const root = window.document.documentElement;

    root.classList.remove('light', 'dark');

    // 声明支持 light 和 dark 两种颜色方案
    root.style.colorScheme = 'light dark';

    if (theme === 'system') {
      const systemTheme = window.matchMedia('(prefers-color-scheme: dark)').matches
        ? 'dark'
        : 'light';

      root.classList.add(systemTheme);
      return;
    }

    root.classList.add(theme);
  }, [theme, mounted]);

  const value = {
    theme: mounted ? theme : defaultTheme,
    setTheme: (theme: Theme) => {
      if (!mounted) return;
      localStorage.setItem(storageKey, theme);
      setThemeState(theme);
    },
  };

  // 避免水合不匹配：在组件未挂载前不渲染任何内容
  if (!mounted) {
    return <>{children}</>;
  }

  return (
    <ThemeProviderContext.Provider {...props} value={value}>
      {children}
    </ThemeProviderContext.Provider>
  );
}

export const useTheme = () => {
  const context = useContext(ThemeProviderContext);

  if (context === undefined)
    throw new Error('useTheme must be used within a ThemeProvider');

  return context;
};