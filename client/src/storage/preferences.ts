import {
  getStoredString,
  getStoredStrings,
  getStoredStringSync,
  setStoredString,
  setStoredStringSync,
  setStoredStrings,
} from './mmkv';

export type ThemePreference = 'light' | 'dark' | 'system';
export type HomeViewMode = 'category-rows' | 'masonry' | 'list' | 'tweet' | 'channel';
export type ReadingMode = 'single-ltr' | 'single-rtl' | 'single-ttb' | 'webtoon';
export type TapZoneMode = 'default' | 'l-shape' | 'kindlish' | 'edge' | 'disabled';
export type WidePageMode = 'off' | 'split' | 'rotate';

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
  seamlessNext: 'reader-seamless-next-enabled',
  webtoonPadding: 'reader-webtoon-padding',
  webtoonGap: 'reader-webtoon-gap',
  webtoonCropBorders: 'reader-webtoon-crop-borders',
  tapZoneMode: 'reader-tap-zone-mode',
  widePageMode: 'reader-wide-page-mode',
  widePageInvert: 'reader-wide-page-invert',
  grayscale: 'reader-grayscale',
  invertColors: 'reader-invert-colors',
  brightness: 'reader-brightness',
  keepScreenOn: 'reader-keep-screen-on',
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
  seamlessNext: boolean;
  webtoonPadding: number;
  webtoonGap: number;
  webtoonCropBorders: boolean;
  tapZoneMode: TapZoneMode;
  widePageMode: WidePageMode;
  widePageInvert: boolean;
  grayscale: boolean;
  invertColors: boolean;
  brightness: number;
  keepScreenOn: boolean;
};

export const DEFAULT_READER_SETTINGS: ReaderSettings = {
  readingMode: 'single-ltr',
  doublePage: false,
  autoPlay: false,
  autoPlayInterval: 3,
  splitCover: false,
  doubleTapZoom: true,
  autoHide: true,
  tapTurnPage: true,
  mediaInfo: false,
  seamlessNext: false,
  webtoonPadding: 0,
  webtoonGap: 0,
  webtoonCropBorders: false,
  tapZoneMode: 'default',
  widePageMode: 'off',
  widePageInvert: false,
  grayscale: false,
  invertColors: false,
  brightness: 1,
  keepScreenOn: true,
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

const ARCHIVE_READING_MODE_PREFIX = 'reader-archive-mode:';

export function normalizeTapZoneMode(value?: string | null): TapZoneMode {
  return value === 'default' ||
    value === 'l-shape' ||
    value === 'kindlish' ||
    value === 'edge' ||
    value === 'disabled'
    ? value
    : DEFAULT_READER_SETTINGS.tapZoneMode;
}

export function normalizeWidePageMode(value?: string | null): WidePageMode {
  return value === 'off' || value === 'split' || value === 'rotate'
    ? value
    : DEFAULT_READER_SETTINGS.widePageMode;
}

export function loadArchiveReadingMode(archiveId?: string | null): ReadingMode | null {
  if (!archiveId) return null;
  const value = getStoredStringSync(`${ARCHIVE_READING_MODE_PREFIX}${archiveId}`);
  if (
    value === 'single-ltr' ||
    value === 'single-rtl' ||
    value === 'single-ttb' ||
    value === 'webtoon'
  ) {
    return value;
  }
  return null;
}

export function saveArchiveReadingMode(archiveId: string | undefined, mode: ReadingMode): void {
  if (!archiveId) return;
  setStoredStringSync(`${ARCHIVE_READING_MODE_PREFIX}${archiveId}`, mode);
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
    doubleTapZoom: map[READER_KEYS.doubleTapZoom] !== 'false',
    autoHide: map[READER_KEYS.autoHide] !== 'false',
    tapTurnPage: map[READER_KEYS.tapTurnPage] !== 'false',
    mediaInfo: map[READER_KEYS.mediaInfo] === 'true',
    seamlessNext: map[READER_KEYS.seamlessNext] === 'true',
    webtoonPadding: clampReaderNumber(map[READER_KEYS.webtoonPadding], 0, 0, 64),
    webtoonGap: clampReaderNumber(map[READER_KEYS.webtoonGap], 0, 0, 32),
    webtoonCropBorders: map[READER_KEYS.webtoonCropBorders] === 'true',
    tapZoneMode: normalizeTapZoneMode(map[READER_KEYS.tapZoneMode]),
    widePageMode: normalizeWidePageMode(map[READER_KEYS.widePageMode]),
    widePageInvert: map[READER_KEYS.widePageInvert] === 'true',
    grayscale: map[READER_KEYS.grayscale] === 'true',
    invertColors: map[READER_KEYS.invertColors] === 'true',
    brightness: clampReaderNumber(map[READER_KEYS.brightness], 100, 20, 200) / 100,
    keepScreenOn: map[READER_KEYS.keepScreenOn] !== 'false',
  };
}

function clampReaderNumber(value: string | null | undefined, fallback: number, min: number, max: number) {
  const parsed = Number(value);
  if (!Number.isFinite(parsed)) return fallback;
  return Math.max(min, Math.min(max, Math.round(parsed)));
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
    [READER_KEYS.seamlessNext, String(settings.seamlessNext)],
    [READER_KEYS.webtoonPadding, String(settings.webtoonPadding)],
    [READER_KEYS.webtoonGap, String(settings.webtoonGap)],
    [READER_KEYS.webtoonCropBorders, String(settings.webtoonCropBorders)],
    [READER_KEYS.tapZoneMode, settings.tapZoneMode],
    [READER_KEYS.widePageMode, settings.widePageMode],
    [READER_KEYS.widePageInvert, String(settings.widePageInvert)],
    [READER_KEYS.grayscale, String(settings.grayscale)],
    [READER_KEYS.invertColors, String(settings.invertColors)],
    [READER_KEYS.brightness, String(Math.round(settings.brightness * 100))],
    [READER_KEYS.keepScreenOn, String(settings.keepScreenOn)],
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
