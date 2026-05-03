import {
  getStoredString,
  getStoredStrings,
  getStoredStringSync,
  setStoredString,
  setStoredStrings,
} from './mmkv';

export type ThemePreference = 'light' | 'dark' | 'system';
export type HomeViewMode = 'category-rows' | 'masonry' | 'list' | 'tweet' | 'channel';
export type ReadingMode = 'single-ltr' | 'single-rtl' | 'single-ttb' | 'webtoon';

export const THEME_STORAGE_KEY = 'app-theme';
export const HOME_VIEW_MODE_STORAGE_KEY = 'home_view_mode';
export const DEFAULT_HOME_VIEW_MODE: HomeViewMode = 'category-rows';

export const READER_KEYS = {
  readingMode: 'reader-reading-mode',
  doublePage: 'reader-double-page-mode',
  autoPlay: 'reader-auto-play-mode',
  autoPlayInterval: 'reader-auto-play-interval',
  splitCover: 'reader-split-cover-mode',
  doubleTapZoom: 'reader-double-tap-zoom',
  autoHide: 'reader-auto-hide-enabled',
  tapTurnPage: 'reader-tap-turn-page-enabled',
  mediaInfo: 'reader-media-info-enabled',
  longPage: 'reader-long-page-enabled',
  seamlessNext: 'reader-seamless-next-enabled',
} as const;

export type ReaderSettings = {
  readingMode: ReadingMode;
  doublePage: boolean;
  autoPlay: boolean;
  autoPlayInterval: number;
  splitCover: boolean;
  doubleTapZoom: boolean;
  autoHide: boolean;
  tapTurnPage: boolean;
  mediaInfo: boolean;
  longPage: boolean;
  seamlessNext: boolean;
};

export const DEFAULT_READER_SETTINGS: ReaderSettings = {
  readingMode: 'single-ltr',
  doublePage: false,
  autoPlay: false,
  autoPlayInterval: 3,
  splitCover: false,
  doubleTapZoom: false,
  autoHide: false,
  tapTurnPage: false,
  mediaInfo: false,
  longPage: true,
  seamlessNext: false,
};

export function normalizeHomeViewMode(value?: string | null): HomeViewMode {
  return value === 'category-rows' ||
    value === 'masonry' ||
    value === 'list' ||
    value === 'tweet' ||
    value === 'channel'
    ? value
    : DEFAULT_HOME_VIEW_MODE;
}

export function normalizeReadingMode(value?: string | null): ReadingMode {
  return value === 'single-ltr' ||
    value === 'single-rtl' ||
    value === 'single-ttb' ||
    value === 'webtoon'
    ? value
    : DEFAULT_READER_SETTINGS.readingMode;
}

export async function loadHomeViewMode(): Promise<HomeViewMode> {
  return normalizeHomeViewMode(await getStoredString(HOME_VIEW_MODE_STORAGE_KEY));
}

export function loadHomeViewModeSync(): HomeViewMode {
  return normalizeHomeViewMode(getStoredStringSync(HOME_VIEW_MODE_STORAGE_KEY));
}

export async function saveHomeViewMode(mode: HomeViewMode): Promise<void> {
  await setStoredString(HOME_VIEW_MODE_STORAGE_KEY, mode);
}

function readerSettingsFromMap(map: Record<string, string | null>): ReaderSettings {
  return {
    readingMode: normalizeReadingMode(map[READER_KEYS.readingMode]),
    doublePage: map[READER_KEYS.doublePage] === 'true',
    autoPlay: map[READER_KEYS.autoPlay] === 'true',
    autoPlayInterval: Math.max(
      1,
      Math.min(10, Number(map[READER_KEYS.autoPlayInterval] || 3)),
    ),
    splitCover: map[READER_KEYS.splitCover] === 'true',
    doubleTapZoom: map[READER_KEYS.doubleTapZoom] === 'true',
    autoHide: map[READER_KEYS.autoHide] === 'true',
    tapTurnPage: map[READER_KEYS.tapTurnPage] === 'true',
    mediaInfo: map[READER_KEYS.mediaInfo] === 'true',
    longPage: map[READER_KEYS.longPage] !== 'false',
    seamlessNext: map[READER_KEYS.seamlessNext] === 'true',
  };
}

export async function loadReaderSettings(): Promise<ReaderSettings> {
  const entries = await getStoredStrings(Object.values(READER_KEYS));
  return readerSettingsFromMap(Object.fromEntries(entries));
}

export function loadReaderSettingsSync(): ReaderSettings {
  const map = Object.fromEntries(
    Object.values(READER_KEYS).map(key => [key, getStoredStringSync(key)]),
  );
  return readerSettingsFromMap(map);
}

export async function saveReaderSettings(settings: ReaderSettings): Promise<void> {
  await setStoredStrings([
    [READER_KEYS.readingMode, settings.readingMode],
    [READER_KEYS.doublePage, String(settings.doublePage)],
    [READER_KEYS.autoPlay, String(settings.autoPlay)],
    [READER_KEYS.autoPlayInterval, String(settings.autoPlayInterval)],
    [READER_KEYS.splitCover, String(settings.splitCover)],
    [READER_KEYS.doubleTapZoom, String(settings.doubleTapZoom)],
    [READER_KEYS.autoHide, String(settings.autoHide)],
    [READER_KEYS.tapTurnPage, String(settings.tapTurnPage)],
    [READER_KEYS.mediaInfo, String(settings.mediaInfo)],
    [READER_KEYS.longPage, String(settings.longPage)],
    [READER_KEYS.seamlessNext, String(settings.seamlessNext)],
  ]);
}

function normalizeThemePreference(value?: string | null): ThemePreference {
  if (value === 'light' || value === 'dark') return value;
  return 'system';
}

export function loadThemePreferenceSync(): ThemePreference {
  return normalizeThemePreference(getStoredStringSync(THEME_STORAGE_KEY));
}

export async function saveThemePreference(preference: ThemePreference): Promise<void> {
  await setStoredString(THEME_STORAGE_KEY, preference);
}
