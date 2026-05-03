import React, {createContext, useCallback, useContext, useEffect, useMemo, useState} from 'react';
import {Appearance, useColorScheme} from 'react-native';

import {getStoredStringSync, setStoredStringSync} from '../storage/mmkv';
import {getColorsByScheme, type ColorScheme, type ThemeColors} from './colors';

export type ThemePreference = 'light' | 'dark' | 'system';

const THEME_STORAGE_KEY = 'app-theme';

interface ThemeContextValue {
  themePreference: ThemePreference;
  setThemePreference: (preference: ThemePreference) => void;
  effectiveScheme: ColorScheme;
  colors: ThemeColors;
}

const ThemeContext = createContext<ThemeContextValue | null>(null);

function normalizeThemePreference(value?: string | null): ThemePreference {
  if (value === 'light' || value === 'dark') return value;
  return 'system';
}

export function ThemeProvider({children}: {children: React.ReactNode}) {
  const systemScheme = useColorScheme();
  const [themePreference, setThemePreferenceState] = useState<ThemePreference>(
    () => normalizeThemePreference(getStoredStringSync(THEME_STORAGE_KEY)),
  );

  const effectiveScheme: ColorScheme =
    themePreference === 'system'
      ? (systemScheme === 'dark' ? 'dark' : 'light')
      : themePreference;

  const colors = useMemo(() => getColorsByScheme(effectiveScheme), [effectiveScheme]);

  useEffect(() => {
    const subscription = Appearance.addChangeListener(() => {
      // Force re-render when system appearance changes while in 'system' mode.
      // useColorScheme already reactively updates via Appearance, so this is a nudge.
      if (themePreference === 'system') {
        setThemePreferenceState('system');
      }
    });
    return () => subscription.remove();
  }, [themePreference]);

  const setThemePreference = useCallback((preference: ThemePreference) => {
    setThemePreferenceState(preference);
    setStoredStringSync(THEME_STORAGE_KEY, preference);
  }, []);

  const value = useMemo<ThemeContextValue>(
    () => ({
      themePreference,
      setThemePreference,
      effectiveScheme,
      colors,
    }),
    [themePreference, setThemePreference, effectiveScheme, colors],
  );

  return <ThemeContext.Provider value={value}>{children}</ThemeContext.Provider>;
}

export function useTheme(): ThemeContextValue {
  const value = useContext(ThemeContext);
  if (!value) {
    throw new Error('useTheme must be used inside ThemeProvider');
  }
  return value;
}
