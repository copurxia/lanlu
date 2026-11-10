export type ColorScheme = 'light' | 'dark';

export interface ThemeColors {
  background: string;
  surface: string;
  surfaceMuted: string;
  text: string;
  textMuted: string;
  border: string;
  borderStrong: string;
  primary: string;
  primaryPressed: string;
  primaryMuted: string;
  danger: string;
  success: string;
  black: string;
  white: string;
}

export const lightColors: ThemeColors = {
  background: '#f7f7f7',
  surface: '#ffffff',
  surfaceMuted: '#f3f2f1',
  text: '#201f1e',
  textMuted: '#605e5c',
  border: '#edebe9',
  borderStrong: '#c8c6c4',
  primary: '#0078d4',
  primaryPressed: '#106ebe',
  primaryMuted: '#deecf9',
  danger: '#d92d20',
  success: '#0b7a45',
  black: '#000000',
  white: '#ffffff',
};

export const darkColors: ThemeColors = {
  background: '#0d0d0d',
  surface: '#1a1a1a',
  surfaceMuted: '#252525',
  text: '#e8e6e3',
  textMuted: '#a09e9c',
  border: '#2d2d2d',
  borderStrong: '#404040',
  primary: '#4da3e0',
  primaryPressed: '#3a8fd4',
  primaryMuted: '#1a2a3a',
  danger: '#e84d3d',
  success: '#2ea86a',
  black: '#000000',
  white: '#ffffff',
};

export function getColorsByScheme(scheme: ColorScheme): ThemeColors {
  return scheme === 'dark' ? darkColors : lightColors;
}

export const spacing = {
  xs: 4,
  sm: 8,
  md: 12,
  lg: 16,
  xl: 24,
};

export const radius = {
  sm: 4,
  md: 8,
};
