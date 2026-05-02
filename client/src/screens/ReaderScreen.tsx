import React, {useCallback, useEffect, useMemo, useRef, useState} from 'react';
import {
  Dimensions,
  FlatList,
  Image,
  ImageSourcePropType,
  LayoutAnimation,
  ListRenderItemInfo,
  Modal,
  Platform,
  ScrollView,
  StyleSheet,
  StyleProp,
  StatusBar,
  Text,
  TouchableOpacity,
  UIManager,
  useWindowDimensions,
  View,
  ViewStyle,
  ViewToken,
} from 'react-native';
import type {NativeStackScreenProps} from '@react-navigation/native-stack';
import {Gesture, GestureDetector} from 'react-native-gesture-handler';
import {
  FlashList,
  type FlashListRef,
  type ListRenderItemInfo as FlashListRenderItemInfo,
} from '@shopify/flash-list';
import {useSafeAreaInsets} from 'react-native-safe-area-context';
import Animated, {
  cancelAnimation,
  Easing,
  runOnJS,
  useAnimatedStyle,
  useSharedValue,
  withRepeat,
  withTiming,
} from 'react-native-reanimated';
import {
  BookOpen,
  Captions,
  ChevronLeft,
  FastForward,
  Heart,
  Layers,
  List,
  Pause,
  Play,
  Rewind,
  Settings as SettingsIcon,
  Music,
  Volume2,
  VolumeX,
} from 'lucide-react-native';
import Svg, {Defs, LinearGradient, Rect, Stop} from 'react-native-svg';
import {VLCPlayer} from 'react-native-vlc-media-player';
import {WebView} from 'react-native-webview';

import {
  buildAuthorizedImageSource as buildAuthorizedImageSource_,
  apiClient,
  buildAuthorizedUri,
  extractApiError,
} from '../api/client';
import {
  assetPath,
  fetchArchiveMetadata,
  fetchArchiveFiles,
  fetchArchiveRelated,
  fetchTankoubonsForArchive,
  getPageDefaultSource,
  pagePath,
  probeMediaPage,
  setArchiveFavorite,
  updateArchiveProgress,
} from '../api/lanlu';
import {ModalBackdrop} from '../components/SafeAreaSurface';
import {ReaderSidebar} from './reader/ReaderSidebar';
import {OptionSelectSheet, type SelectOption} from './reader/OptionSelectSheet';
import {ScreenState} from '../components/ScreenState';
import {
  DEFAULT_READER_SETTINGS,
  loadReaderSettings,
  ReaderSettings,
  saveReaderSettings,
} from '../storage/preferences';
import {appendDiagnosticLog} from '../storage/diagnostics';
import {
  createLocalSubtitleFile,
  createProxiedMediaUrl,
  createProxiedPageUrl,
  setSystemBarsHidden,
} from '../native/LanluMediaProxy';
import {useI18n} from '../i18n';
import {colors, spacing} from '../theme/colors';
import type {RootStackParamList} from '../navigation/types';
import type {MetadataPageAttachment, PageInfo, PageSourceInfo} from '../types/api';

type Props = NativeStackScreenProps<RootStackParamList, 'Reader'>;

type ReaderPage = PageInfo & {
  pageNumber: number;
  sourceArchiveId: string;
  activeSource?: PageSourceInfo | null;
  backendUri?: string;
  imageSource?: ImageSourcePropType;
  thumbnailSource?: ImageSourcePropType;
  uri?: string;
  vlcUri?: string;
  headers?: Record<string, string>;
  token?: string;
  resolvedPath?: string;
  effectiveType: 'image' | 'video' | 'audio' | 'html';
};

const EPUB_HTML_INJECTION = `
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover" />
<style>
  html, body {
    display: block !important;
    visibility: visible !important;
    opacity: 1 !important;
    min-height: 100%;
    margin: 0;
    padding: 0;
    background: #fff;
    color: #111;
    overflow-wrap: anywhere;
    -webkit-text-size-adjust: 100%;
  }
  body {
    box-sizing: border-box;
    padding: 16px;
    writing-mode: horizontal-tb !important;
  }
  img, svg, video, canvas {
    display: block;
    margin-left: auto;
    margin-right: auto;
    max-width: 100%;
    height: auto;
  }
  body, body * {
    visibility: visible !important;
    opacity: 1 !important;
  }
  p, div, h1, h2, h3, h4, h5, h6, li {
    color: #111;
  }
  pre {
    white-space: pre-wrap;
  }
</style>`;

function prepareEpubHtml(html: string) {
  if (/<head\b[^>]*>/i.test(html)) {
    return html.replace(/<head\b[^>]*>/i, match => `${match}${EPUB_HTML_INJECTION}`);
  }
  return `<!doctype html><html><head>${EPUB_HTML_INJECTION}</head><body>${html}</body></html>`;
}

type ReaderItem = {
  key: string;
  pages: ReaderPage[];
  progressPage: number;
  kind?: 'pages' | 'collection-end';
};

type ReaderWebtoonItem =
  | ReaderPage
  | {
      kind: 'collection-end';
      key: string;
      pageNumber: number;
    };

type NextArchiveCandidate = {
  id: string;
  title: string;
  source: 'tankoubon' | 'archive_related';
};

type VlcPlayerRef = {
  seek: (position: number) => void;
};

type VlcTextTrack = {
  id: number;
  name: string;
};

type VlcSource = {
  uri: string;
  isNetwork: boolean;
  initType: number;
  initOptions: string[];
  mediaOptions: string[];
};

type PendingMediaSeek = {
  fromTime: number;
  targetTime: number;
  createdAt: number;
  reason: string;
};

type RecentMediaSeek = {
  fromTime: number;
  targetTime: number;
  until: number;
  reason: string;
};

type StableVlcPlayerProps = {
  playerKey: string;
  playerRef: (ref: VlcPlayerRef | null) => void;
  paused: boolean;
  muted: boolean;
  textTrack: number;
  subtitleUri?: string;
  volume: number;
  source: VlcSource;
  style: StyleProp<ViewStyle>;
  onBuffering: (event: any) => void;
  onEnd: () => void;
  onError: (event: any) => void;
  onLoad: (event: any) => void;
  onPaused: () => void;
  onPlaying: (event: any) => void;
  onProgress: (event: VlcPlaybackEvent) => void;
};

type MediaPlaybackState = {
  currentTime: number;
  duration: number;
  position: number;
  paused: boolean;
  muted: boolean;
  volume: number;
  buffered: number;
};

type ReaderLane =
  | {id: 'book'; kind: 'book'; label: string}
  | {id: string; kind: 'video' | 'audio'; label: string; page: ReaderPage};

type VlcPlaybackEvent = {
  currentTime?: number;
  duration?: number;
  position?: number;
  target?: number;
};

type SubtitleCue = {
  start: number;
  end: number;
  text: string;
};

type TimedLyricLine = {
  time: number;
  text: string;
  key: string;
};

type AudioLyricTouchTrace = {
  phase: 'pressIn' | 'pressOut' | 'press' | 'pressSuppressed';
  lineIndex: number;
  lineTime: number;
  activeLyricIndex: number;
  textPreview: string;
  now: number;
  suppressUntil: number;
  userScrolling: boolean;
  seekTime?: number;
  nextLineTime?: number;
  nativeTimestamp?: number;
};

type AudioLyricDebugWindow = {
  until: number;
  lastProgressLogAt: number;
  lineIndex?: number;
  lineTime?: number;
  targetTime: number;
  textPreview?: string;
};

type AudioLyricSnapshot = {
  activeLyricIndex: number;
  activeLineTime?: number;
  activeTextPreview?: string;
  playbackTime: number;
  timedLyricsCount: number;
  updatedAt: number;
};

const SUBTITLE_OFF_VALUE = -1;
const EMBEDDED_SUBTITLE_VALUE_OFFSET = 100000;

const READING_MODES: ReaderSettings['readingMode'][] = [
  'single-ltr',
  'single-rtl',
  'single-ttb',
  'webtoon',
];

function modeLabelKey(mode: ReaderSettings['readingMode']) {
  switch (mode) {
    case 'single-ltr':
      return 'reader.modeLtr';
    case 'single-rtl':
      return 'reader.modeRtl';
    case 'single-ttb':
      return 'reader.modeTtb';
    case 'webtoon':
      return 'reader.modeWebtoon';
  }
}

function normalizeVlcSeconds(value: number) {
  if (!Number.isFinite(value) || value <= 0) return 0;
  return value / 1000;
}

function normalizeVlcProgress(event: VlcPlaybackEvent) {
  const duration = normalizeVlcSeconds(Number(event.duration || 0));
  const currentTime = normalizeVlcSeconds(Number(event.currentTime || 0));
  const fallbackPosition = Number.isFinite(event.position || 0) ? Number(event.position || 0) : 0;
  const position = duration > 0 ? currentTime / duration : fallbackPosition;
  return {
    currentTime,
    duration,
    position: Math.max(0, Math.min(1, position)),
  };
}

function normalizeVlcBufferRate(event: unknown) {
  if (!event || typeof event !== 'object') return 0;
  const payload = event as Record<string, unknown>;
  const raw =
    typeof payload.bufferRate === 'number'
      ? payload.bufferRate / 100
      : typeof payload.rate === 'number'
        ? payload.rate
        : typeof payload.buffered === 'number'
          ? payload.buffered
          : 0;
  return Math.max(0, Math.min(1, raw));
}

function formatMediaTime(seconds: number) {
  const safe = Math.max(0, Math.floor(seconds));
  const minutes = Math.floor(safe / 60);
  const rest = safe % 60;
  return `${minutes}:${String(rest).padStart(2, '0')}`;
}

function getSubtitleAttachments(metadata?: PageInfo['metadata'] | null): MetadataPageAttachment[] {
  const attachments = Array.isArray(metadata?.attachments) ? metadata.attachments : [];
  return attachments
    .filter(attachment => String(attachment.slot || '').trim().toLowerCase() === 'subtitle')
    .sort((a, b) => {
      const orderA = typeof a.order_index === 'number' ? a.order_index : 0;
      const orderB = typeof b.order_index === 'number' ? b.order_index : 0;
      if (orderA !== orderB) return orderA - orderB;
      return String(a.name || '').localeCompare(String(b.name || ''));
    });
}

function getPageAttachmentsBySlot(metadata: PageInfo['metadata'] | undefined | null, slot: string): MetadataPageAttachment[] {
  const normalizedSlot = slot.trim().toLowerCase();
  const attachments = Array.isArray(metadata?.attachments) ? metadata.attachments : [];
  return attachments
    .filter(attachment => String(attachment.slot || '').trim().toLowerCase() === normalizedSlot)
    .sort((a, b) => {
      const orderA = typeof a.order_index === 'number' ? a.order_index : 0;
      const orderB = typeof b.order_index === 'number' ? b.order_index : 0;
      if (orderA !== orderB) return orderA - orderB;
      return String(a.name || '').localeCompare(String(b.name || ''));
    });
}

function getPageSubtitleAttachments(page?: ReaderPage | null) {
  return getSubtitleAttachments(page?.activeSource?.metadata || page?.metadata);
}

function getPageLyricsAttachments(page?: ReaderPage | null) {
  return getPageAttachmentsBySlot(page?.activeSource?.metadata || page?.metadata, 'lyrics');
}

function buildSubtitleOptionLabel(attachment: MetadataPageAttachment, subtitleIndex: number) {
  const language = String(attachment.language || '').trim();
  const kind = String(attachment.kind || '').trim().toLowerCase();
  const name = String(attachment.name || '').trim();
  if (language && kind) return `${language} · ${kind}`;
  if (language) return language;
  if (name && kind && !name.toLowerCase().endsWith(`.${kind}`)) return `${name} · ${kind}`;
  if (name) return name;
  if (kind) return kind;
  return `Subtitle ${subtitleIndex + 1}`;
}

function buildLyricsOptionLabel(attachment: MetadataPageAttachment, lyricsIndex: number) {
  const language = String(attachment.language || '').trim();
  const kind = String(attachment.kind || '').trim().toLowerCase();
  const name = String(attachment.name || '').trim();
  if (language && kind) return `${language} · ${kind}`;
  if (language) return language;
  if (name && kind && !name.toLowerCase().endsWith(`.${kind}`)) return `${name} · ${kind}`;
  if (name) return name;
  if (kind) return kind;
  return `Lyrics ${lyricsIndex + 1}`;
}

function isAssSubtitleAttachment(attachment?: MetadataPageAttachment | null) {
  const kind = String(attachment?.kind || '').trim().toLowerCase();
  const name = String(attachment?.name || '').trim().toLowerCase();
  return kind.includes('ass') || kind.includes('ssa') || name.endsWith('.ass') || name.endsWith('.ssa');
}

function subtitleFileExtension(attachment?: MetadataPageAttachment | null) {
  const kind = String(attachment?.kind || '').trim().toLowerCase();
  const name = String(attachment?.name || '').trim().toLowerCase();
  if (kind.includes('ssa') || name.endsWith('.ssa')) return 'ssa';
  if (kind.includes('vtt') || name.endsWith('.vtt')) return 'vtt';
  if (kind.includes('srt') || name.endsWith('.srt')) return 'srt';
  return 'ass';
}

function encodeEmbeddedSubtitleValue(trackId: number) {
  return -(EMBEDDED_SUBTITLE_VALUE_OFFSET + trackId);
}

function decodeEmbeddedSubtitleValue(value: number) {
  if (value > -EMBEDDED_SUBTITLE_VALUE_OFFSET) return null;
  return Math.abs(value) - EMBEDDED_SUBTITLE_VALUE_OFFSET;
}

function parseTimestamp(raw: string): number {
  const parts = raw.trim().replace(',', '.').split(':').map(part => Number(part));
  if (parts.some(part => !Number.isFinite(part))) return 0;
  if (parts.length === 3) return parts[0] * 3600 + parts[1] * 60 + parts[2];
  if (parts.length === 2) return parts[0] * 60 + parts[1];
  return parts[0] || 0;
}

function stripAssFormatting(text: string) {
  return text
    .replace(/\{[^}]*\}/g, '')
    .replace(/\\N/gi, '\n')
    .replace(/\\n/g, '\n')
    .replace(/\\h/g, ' ')
    .trim();
}

function parseSrt(text: string): SubtitleCue[] {
  return text
    .split(/\r?\n\r?\n/)
    .map(block => block.trim())
    .filter(Boolean)
    .map(block => {
      const lines = block.split(/\r?\n/).map(line => line.trim());
      const timeLine = lines.find(line => line.includes('-->')) || '';
      const [startRaw, endRaw] = timeLine.split('-->').map(value => value.trim());
      if (!startRaw || !endRaw) return null;
      const body = lines.filter(line => line && line !== timeLine && !/^\d+$/.test(line)).join('\n').trim();
      if (!body) return null;
      return {start: parseTimestamp(startRaw), end: parseTimestamp(endRaw), text: body};
    })
    .filter((cue): cue is SubtitleCue => Boolean(cue));
}

function parseVtt(text: string): SubtitleCue[] {
  return text
    .replace(/^WEBVTT[\s\r\n]*/i, '')
    .split(/\r?\n\r?\n/)
    .map(block => block.trim())
    .filter(Boolean)
    .map(block => {
      const lines = block.split(/\r?\n/).map(line => line.trim()).filter(Boolean);
      const timeLine = lines.find(line => line.includes('-->')) || '';
      const [startRaw, endRaw] = timeLine.split('-->').map(value => value.trim().split(/\s+/)[0]);
      if (!startRaw || !endRaw) return null;
      const body = lines.filter(line => line && line !== timeLine).join('\n').trim();
      if (!body) return null;
      return {start: parseTimestamp(startRaw), end: parseTimestamp(endRaw), text: body};
    })
    .filter((cue): cue is SubtitleCue => Boolean(cue));
}

function parseAss(text: string): SubtitleCue[] {
  let eventSection = false;
  let formatFields: string[] = [];
  const cues: SubtitleCue[] = [];
  for (const line of text.split(/\r?\n/)) {
    const trimmed = line.trim();
    if (/^\[events\]$/i.test(trimmed)) {
      eventSection = true;
      continue;
    }
    if (/^\[.+\]$/.test(trimmed)) {
      eventSection = false;
      continue;
    }
    if (!eventSection) continue;
    if (/^Format:/i.test(trimmed)) {
      formatFields = trimmed
        .slice(trimmed.indexOf(':') + 1)
        .split(',')
        .map(field => field.trim().toLowerCase());
      continue;
    }
    if (!/^Dialogue:/i.test(trimmed)) continue;

    const payload = trimmed.slice(trimmed.indexOf(':') + 1).trim();
    const fieldCount = Math.max(formatFields.length, 10);
    const parts = payload.split(',');
    if (parts.length < fieldCount) continue;

    const startIndex = formatFields.indexOf('start');
    const endIndex = formatFields.indexOf('end');
    const textIndex = formatFields.indexOf('text');
    const resolvedStartIndex = startIndex >= 0 ? startIndex : 1;
    const resolvedEndIndex = endIndex >= 0 ? endIndex : 2;
    const resolvedTextIndex = textIndex >= 0 ? textIndex : 9;

    const head = parts.slice(0, resolvedTextIndex);
    const bodyParts = parts.slice(resolvedTextIndex);
    if (head.length <= Math.max(resolvedStartIndex, resolvedEndIndex) || bodyParts.length === 0) continue;
    const body = stripAssFormatting(bodyParts.join(','));
    if (body) {
      cues.push({
        start: parseTimestamp(head[resolvedStartIndex] || ''),
        end: parseTimestamp(head[resolvedEndIndex] || ''),
        text: body,
      });
    }
  }
  return cues;
}

function parseSubtitleText(text: string, kind?: string): SubtitleCue[] {
  const normalized = text.replace(/^\uFEFF/, '').trim();
  const lowerKind = String(kind || '').toLowerCase();
  if (lowerKind.includes('ass') || lowerKind.includes('ssa') || /^\[Script Info\]/i.test(normalized)) {
    return parseAss(normalized);
  }
  if (lowerKind.includes('vtt') || /^WEBVTT/i.test(normalized)) {
    return parseVtt(normalized);
  }
  return parseSrt(normalized);
}

function getActiveSubtitleCues(
  attachments: MetadataPageAttachment[],
  textsByAssetId: Record<number, string>,
  currentTime: number,
) {
  return attachments
    .map(attachment => {
      const text = textsByAssetId[attachment.asset_id];
      if (!text) return null;
      return parseSubtitleText(text, attachment.kind).find(cue => currentTime >= cue.start && currentTime <= cue.end) || null;
    })
    .filter((cue): cue is SubtitleCue => Boolean(cue));
}

const LRC_TIME_TAG = /\[(\d{1,2}):(\d{2})(?:\.(\d{1,3}))?\]/g;

function parseTimedLyrics(rawLyrics: string): TimedLyricLine[] {
  const parsed: TimedLyricLine[] = [];
  let lineIndex = 0;
  for (const rawLine of rawLyrics.split(/\r?\n/)) {
    const tags = [...rawLine.matchAll(LRC_TIME_TAG)];
    if (!tags.length) {
      lineIndex += 1;
      continue;
    }
    const text = rawLine.replace(LRC_TIME_TAG, '').trim();
    tags.forEach((tag, tagIndex) => {
      const minutes = Number(tag[1] || 0);
      const seconds = Number(tag[2] || 0);
      const fraction = Number(`${tag[3] || '0'}00`.slice(0, 3));
      if (!Number.isFinite(minutes) || !Number.isFinite(seconds) || !Number.isFinite(fraction)) return;
      const time = minutes * 60 + seconds + fraction / 1000;
      parsed.push({time, text, key: `${lineIndex}-${tagIndex}-${time.toFixed(3)}`});
    });
    lineIndex += 1;
  }
  return parsed.sort((a, b) => a.time - b.time);
}

function getActiveTimedLyricIndex(lines: TimedLyricLine[], currentTime: number) {
  if (!lines.length || currentTime < lines[0].time) return -1;
  let low = 0;
  let high = lines.length - 1;
  while (low <= high) {
    const mid = Math.floor((low + high) / 2);
    if (lines[mid].time <= currentTime) low = mid + 1;
    else high = mid - 1;
  }
  return high;
}

function getPlainLyricLines(rawLyrics: string) {
  return rawLyrics
    .split(/\r?\n/)
    .map(line => line.replace(LRC_TIME_TAG, '').trim())
    .filter(Boolean);
}

function nextReadingMode(mode: ReaderSettings['readingMode']) {
  const index = READING_MODES.indexOf(mode);
  return READING_MODES[(index + 1) % READING_MODES.length];
}

function vlcSubtitlePath(subtitleUri?: string) {
  if (!subtitleUri) return undefined;
  if (!subtitleUri.startsWith('file://')) return subtitleUri;
  try {
    return decodeURIComponent(subtitleUri.replace(/^file:\/\//, ''));
  } catch {
    return subtitleUri.replace(/^file:\/\//, '');
  }
}

function isExternalVlcTextTrack(track: VlcTextTrack, subtitleUri?: string) {
  const subtitlePath = vlcSubtitlePath(subtitleUri);
  if (!subtitlePath) return false;
  const trackName = track.name.toLowerCase();
  const subtitleName = subtitlePath.split('/').pop()?.toLowerCase() || '';
  return (
    Boolean(subtitleName && trackName.includes(subtitleName)) ||
    trackName.includes('lanlu_subtitles') ||
    trackName.includes('subtitle-')
  );
}

function buildVlcMediaOptions(page: ReaderPage, subtitleUri?: string) {
  const subtitlePath = vlcSubtitlePath(subtitleUri);
  if (page.vlcUri) {
    return [
      ':http-reconnect',
      ...(subtitlePath ? [`:sub-file=${subtitlePath}`] : []),
      '',
    ];
  }
  return [
    ...(page.headers?.Authorization
      ? [`:http-header=Authorization: ${page.headers.Authorization}`]
      : []),
    ...(page.token ? [`:http-header=Cookie: auth_token=${page.token}`] : []),
    ':http-reconnect',
    ...(subtitlePath ? [`:sub-file=${subtitlePath}`] : []),
    '',
  ];
}

const StableVlcPlayer = React.memo(
  function StableVlcPlayer({
    playerKey,
    playerRef,
    paused,
    muted,
    textTrack,
    subtitleUri,
    volume,
    source,
    style,
    onBuffering,
    onEnd,
    onError,
    onLoad,
    onPaused,
    onPlaying,
    onProgress,
  }: StableVlcPlayerProps) {
    return (
      <VLCPlayer
        key={playerKey}
        ref={ref => playerRef(ref as VlcPlayerRef | null)}
        autoplay
        acceptInvalidCertificates
        paused={paused}
        muted={muted}
        textTrack={textTrack}
        subtitleUri={subtitleUri}
        volume={volume}
        resizeMode="contain"
        source={source as never}
        style={style}
        onBuffering={onBuffering}
        onEnd={onEnd}
        onError={onError}
        onLoad={onLoad}
        onPaused={onPaused}
        onPlaying={onPlaying}
        onProgress={onProgress}
      />
    );
  },
  (previous, next) =>
    previous.playerKey === next.playerKey &&
    previous.paused === next.paused &&
    previous.muted === next.muted &&
    previous.textTrack === next.textTrack &&
    previous.subtitleUri === next.subtitleUri &&
    previous.volume === next.volume &&
    previous.source === next.source &&
    previous.style === next.style,
);

export function ReaderScreen({route, navigation}: Props) {
  const {t} = useI18n();
  const {archiveId, initialPage = 1, children, childIndex, tankoubonId} = route.params;
  const windowDimensions = useWindowDimensions();
  const [screenDimensions, setScreenDimensions] = useState(() => Dimensions.get('screen'));
  const viewportDimensions =
    Platform.OS === 'android'
      ? {
          width: Math.max(windowDimensions.width, screenDimensions.width),
          height: Math.max(windowDimensions.height, screenDimensions.height),
        }
      : windowDimensions;
  const [stableViewport, setStableViewport] = useState({
    width: viewportDimensions.width,
    height: viewportDimensions.height,
  });
  const {width, height} = stableViewport;
  const rawInsets = useSafeAreaInsets();
  const [stableInsets, setStableInsets] = useState({
    top: rawInsets.top,
    right: rawInsets.right,
    bottom: rawInsets.bottom,
    left: rawInsets.left,
  });
  const listRef = useRef<FlatList<ReaderItem>>(null);
  const webtoonRef = useRef<FlashListRef<ReaderWebtoonItem>>(null);
  const vlcRefs = useRef<Record<number, VlcPlayerRef | null>>({});
  const vlcSessions = useRef<Record<number, {target?: number; playable: boolean; ignoredProgress: number}>>({});
  const vlcSourceKeys = useRef<Record<number, string>>({});
  const vlcSourceCache = useRef<Record<number, {key: string; source: VlcSource} | undefined>>({});
  const vlcSubtitleKeys = useRef<Record<number, string | undefined>>({});
  const vlcResumeAfterReload = useRef<Record<number, number | undefined>>({});
  const vlcResumeTimers = useRef<Record<number, ReturnType<typeof setTimeout> | undefined>>({});
  const embeddedVlcSubtitleTrackBaseline = useRef<Record<number, VlcTextTrack[] | undefined>>({});
  const externalVlcSubtitleTrackIds = useRef<Record<number, number[] | undefined>>({});
  const vlcBufferLogBuckets = useRef<Record<number, number>>({});
  const mediaLastSeekAt = useRef<Record<number, number>>({});
  const mediaPendingSeekByPage = useRef<Record<number, PendingMediaSeek | undefined>>({});
  const mediaRecentSeekByPage = useRef<Record<number, RecentMediaSeek | undefined>>({});
  const mediaLastProgressUiAt = useRef<Record<number, number>>({});
  const mediaLastBufferUiAt = useRef<Record<number, number>>({});
  const audioLyricDebugWindows = useRef<Record<number, AudioLyricDebugWindow | undefined>>({});
  const audioLyricSnapshots = useRef<Record<number, AudioLyricSnapshot | undefined>>({});
  const mediaProxyKeys = useRef<Set<string>>(new Set());
  const mediaProbeKeys = useRef<Set<string>>(new Set());
  const pendingLocalSubtitleByAssetId = useRef<Record<number, Promise<string | undefined> | undefined>>({});
  const htmlLoadingKeys = useRef<Set<string>>(new Set());
  const appendedArchiveIds = useRef<Set<string>>(new Set());
  const nextArchiveCache = useRef<Record<string, NextArchiveCandidate | null>>({});
  const lastSavedProgressKey = useRef('');
  const progressSeekLockedRef = useRef(false);
  const settingsHydratedRef = useRef(false);
  const autoHideTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const autoPreferredLaneItemKey = useRef('');

  useEffect(() => {
    const subscription = Dimensions.addEventListener('change', ({screen}) => {
      setScreenDimensions(screen);
    });
    return () => subscription.remove();
  }, []);

  useEffect(() => {
    setStableViewport(current => {
      const currentLandscape = current.width > current.height;
      const nextLandscape = viewportDimensions.width > viewportDimensions.height;
      const widthDelta = Math.abs(viewportDimensions.width - current.width);
      const heightDelta = Math.abs(viewportDimensions.height - current.height);
      if (currentLandscape !== nextLandscape || widthDelta > 120 || heightDelta > 12) {
        return {
          width: viewportDimensions.width,
          height: viewportDimensions.height,
        };
      }
      return current;
    });
  }, [viewportDimensions.height, viewportDimensions.width]);

  useEffect(() => {
    setStableInsets(current => {
      if (
        current.top === rawInsets.top &&
        current.right === rawInsets.right &&
        current.bottom === rawInsets.bottom &&
        current.left === rawInsets.left
      ) {
        return current;
      }
      return {
        top: rawInsets.top,
        right: rawInsets.right,
        bottom: rawInsets.bottom,
        left: rawInsets.left,
      };
    });
  }, [rawInsets.bottom, rawInsets.left, rawInsets.right, rawInsets.top]);
  const [settings, setSettings] = useState<ReaderSettings>(DEFAULT_READER_SETTINGS);
  const [settingsOpen, setSettingsOpen] = useState(false);
  const [sourceIndexByPage, setSourceIndexByPage] = useState<Record<number, number>>({});
  const [pages, setPages] = useState<ReaderPage[]>([]);
  const [failedPages, setFailedPages] = useState<Record<number, string>>({});
  const [loadedPages, setLoadedPages] = useState<Record<number, boolean>>({});
  const [htmlContents, setHtmlContents] = useState<Record<number, string>>({});
  const [htmlHeights, setHtmlHeights] = useState<Record<number, number>>({});
  const [currentPage, setCurrentPage] = useState(Math.max(1, initialPage));
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [chromeVisible, setChromeVisible] = useState(true);
  const [activeLaneId, setActiveLaneId] = useState<string>('book');
  const [mediaStateByPage, setMediaStateByPage] = useState<Record<number, MediaPlaybackState>>({});
  const [zoomedPages, setZoomedPages] = useState<Record<number, boolean>>({});
  const [progressSeekLocked, setProgressSeekLocked] = useState(false);
  const [nextArchiveById, setNextArchiveById] = useState<Record<string, NextArchiveCandidate | null>>({});
  const [sidebarOpen, setSidebarOpen] = useState(false);
  const [sourceSheetOpen, setSourceSheetOpen] = useState(false);
  const [subtitleSheetOpen, setSubtitleSheetOpen] = useState(false);
  const [volumeSheetPageId, setVolumeSheetPageId] = useState<number | null>(null);
  const [sourceSheetPageId, setSourceSheetPageId] = useState<number | null>(null);
  const [activeSubtitleIndexesByPage, setActiveSubtitleIndexesByPage] = useState<Record<number, number[]>>({});
  const [activeLyricsIndexByPage, setActiveLyricsIndexByPage] = useState<Record<number, number>>({});
  const [activeEmbeddedSubtitleTrackByPage, setActiveEmbeddedSubtitleTrackByPage] = useState<Record<number, number | undefined>>({});
  const [embeddedSubtitleTracksByPage, setEmbeddedSubtitleTracksByPage] = useState<Record<number, VlcTextTrack[]>>({});
  const [externalVlcSubtitleUriByPage, setExternalVlcSubtitleUriByPage] = useState<Record<number, string | undefined>>({});
  const [localSubtitleUriByAssetId, setLocalSubtitleUriByAssetId] = useState<Record<number, string>>({});
  const [subtitleTextsByAssetId, setSubtitleTextsByAssetId] = useState<Record<number, string>>({});
  const [isFavorited, setIsFavorited] = useState(false);
  const [sidebarPages, setSidebarPages] = useState<any[]>([]);
  const [appendingNext, setAppendingNext] = useState(false);
  const chromeProgress = useSharedValue(chromeVisible ? 1 : 0);
  useEffect(() => {
    chromeProgress.value = withTiming(chromeVisible ? 1 : 0, {duration: 160});
  }, [chromeProgress, chromeVisible]);

  useEffect(() => {
    if (Platform.OS === 'android' && UIManager.setLayoutAnimationEnabledExperimental) {
      UIManager.setLayoutAnimationEnabledExperimental(true);
    }
  }, []);

  useEffect(() => {
    progressSeekLockedRef.current = progressSeekLocked;
  }, [progressSeekLocked]);

  useEffect(() => {
    setSidebarPages(pages);
  }, [pages]);

  const topBarAnimatedStyle = useAnimatedStyle(() => ({
    opacity: chromeProgress.value,
    transform: [{translateY: (chromeProgress.value - 1) * 16}],
  }));

  const bottomBarAnimatedStyle = useAnimatedStyle(() => ({
    opacity: chromeProgress.value,
    transform: [{translateY: (1 - chromeProgress.value) * 18}],
  }));

  const hydratePage = useCallback(
    async (page: PageInfo, index: number, pageArchiveId = archiveId): Promise<ReaderPage> => {
      const sourceIndex = sourceIndexByPage[index] ?? page.defaultSourceIndex ?? 0;
      const sources = Array.isArray(page.sources) ? page.sources : [];
      const source =
        sources.length > 0
          ? sources[Math.max(0, Math.min(sources.length - 1, sourceIndex))]
          : getPageDefaultSource(page);
      const effectiveType = source?.type || page.type || 'image';
      const path = source?.path || page.path || '';
      const url = source?.url?.startsWith('/api/') ? source.url : pagePath(pageArchiveId, {...page, defaultSource: source || undefined});
      const authorized = path || source?.url ? await buildAuthorizedUri(url) : {uri: '', headers: undefined, token: undefined};
      const proxiedPageUri =
        effectiveType === 'html' && path && authorized.uri
          ? await createProxiedPageUrl(authorized.uri, path, authorized.headers)
          : undefined;
      const displayMetadata = source?.metadata || page.metadata;
      const thumbnailPath =
        displayMetadata?.thumb?.trim() ||
        assetPath(displayMetadata?.thumb_asset_id) ||
        (effectiveType === 'image' ? url : '');
      const imageSource = effectiveType === 'image' && authorized.uri ? await buildAuthorizedImageSource_(url) : undefined;
      const thumbnailSource = thumbnailPath ? await buildAuthorizedImageSource_(thumbnailPath) : imageSource;
      return {
        ...page,
        pageNumber: index + 1,
        sourceArchiveId: pageArchiveId,
        activeSource: source,
        backendUri: authorized.uri,
        resolvedPath: path,
        effectiveType,
        uri: proxiedPageUri || authorized.uri,
        headers: authorized.headers,
        token: authorized.token,
        imageSource,
        thumbnailSource,
      };
    },
    [archiveId, sourceIndexByPage],
  );

  const load = useCallback(async () => {
    setLoading(true);
    setError('');
    mediaProxyKeys.current.clear();
    htmlLoadingKeys.current.clear();
    vlcSourceKeys.current = {};
    vlcSourceCache.current = {};
    vlcSubtitleKeys.current = {};
    vlcSessions.current = {};
    mediaLastProgressUiAt.current = {};
    mediaPendingSeekByPage.current = {};
    mediaRecentSeekByPage.current = {};
    mediaLastBufferUiAt.current = {};
    audioLyricDebugWindows.current = {};
    audioLyricSnapshots.current = {};
    appendedArchiveIds.current = new Set([archiveId]);
    nextArchiveCache.current = {};
    lastSavedProgressKey.current = '';
    setNextArchiveById({});
    setHtmlContents({});
    setHtmlHeights({});
    try {
      const [storedSettings, files] = await Promise.all([
        loadReaderSettings(),
        fetchArchiveFiles(archiveId),
      ]);
      setSettings(storedSettings);
      settingsHydratedRef.current = true;
      const hydrated = await Promise.all(files.map((page, index) => hydratePage(page, index, archiveId)));
      setPages(hydrated);
      setSidebarPages(hydrated);
      const startIndex = Math.max(0, Math.min(initialPage - 1, hydrated.length - 1));
      setCurrentPage(startIndex + 1);
    } catch (err) {
      setError(extractApiError(err));
    } finally {
      setLoading(false);
    }
  }, [archiveId, hydratePage, initialPage]);

  const ensureMediaProxy = useCallback(
    (page: ReaderPage) => {
      if (!page.uri || page.vlcUri || (page.effectiveType !== 'video' && page.effectiveType !== 'audio')) return;
      const key = `${archiveId}:${page.pageNumber}:${page.uri}:${page.headers?.Authorization || ''}`;
      if (mediaProxyKeys.current.has(key)) return;
      mediaProxyKeys.current.add(key);
      createProxiedMediaUrl(page.uri, page.headers)
        .then(vlcUri => {
          if (!vlcUri) return;
          setPages(current =>
            current.map(item =>
              item.pageNumber === page.pageNumber && item.uri === page.uri
                ? {...item, vlcUri}
                : item,
            ),
          );
          appendDiagnosticLog('media.proxy.ready', {
            archiveId,
            page: page.pageNumber,
            type: page.effectiveType,
            uri: page.uri,
            vlcUri,
          }).catch(reason => console.warn('Failed to write diagnostic log:', reason));
        })
        .catch(err => {
          appendDiagnosticLog('media.proxy.error', {
            archiveId,
            page: page.pageNumber,
            type: page.effectiveType,
            uri: page.uri,
            message: extractApiError(err),
          }).catch(reason => console.warn('Failed to write diagnostic log:', reason));
        });
    },
    [archiveId],
  );

  const ensureHtmlContent = useCallback(
    async (page: ReaderPage) => {
      if (page.effectiveType !== 'html') return;
      const htmlUri = page.backendUri || (!page.uri?.startsWith('http://127.0.0.1') ? page.uri : '');
      if (!htmlUri) {
        setFailedPages(current => ({
          ...current,
          [page.pageNumber]: t('reader.noImageSource'),
        }));
        return;
      }
      const key = `${page.sourceArchiveId || archiveId}:${page.pageNumber}:${htmlUri}:${page.headers?.Authorization || ''}`;
      if (htmlContents[page.pageNumber] || htmlLoadingKeys.current.has(key)) return;
      htmlLoadingKeys.current.add(key);
      try {
        const response = await apiClient.get<string>(htmlUri, {
          headers: page.headers,
          responseType: 'text',
          transformResponse: data => data,
          timeout: 15000,
        });
        const rawHtml = typeof response.data === 'string' ? response.data : String(response.data || '');
        const html = prepareEpubHtml(rawHtml);
        setHtmlContents(current => ({...current, [page.pageNumber]: html}));
        setLoadedPages(current => ({...current, [page.pageNumber]: true}));
        setFailedPages(current => {
          if (!current[page.pageNumber]) return current;
          const next = {...current};
          delete next[page.pageNumber];
          return next;
        });
        appendDiagnosticLog('html.content.load', {
          archiveId: page.sourceArchiveId || archiveId,
          page: page.pageNumber,
          uri: htmlUri,
          baseUrl: page.uri,
          path: page.resolvedPath,
          bytes: rawHtml.length,
        }).catch(reason => console.warn('Failed to write diagnostic log:', reason));
      } catch (err) {
        const message = extractApiError(err, 'Failed to load HTML content');
        setFailedPages(current => ({...current, [page.pageNumber]: message}));
        appendDiagnosticLog('html.content.error', {
          archiveId: page.sourceArchiveId || archiveId,
          page: page.pageNumber,
          uri: htmlUri,
          baseUrl: page.uri,
          path: page.resolvedPath,
          message,
        }).catch(reason => console.warn('Failed to write diagnostic log:', reason));
      } finally {
        htmlLoadingKeys.current.delete(key);
      }
    },
    [archiveId, htmlContents, t],
  );

  useEffect(() => {
    load().catch(err => console.warn('Failed to load reader:', err));
  }, [load]);

  useEffect(() => {
    if (!settingsHydratedRef.current) return;
    saveReaderSettings(settings).catch(err =>
      console.warn('Failed to save reader settings:', err),
    );
  }, [settings]);

  const resolveProgressTarget = useCallback(
    (page: number) => {
      if (!pages.length) return null;
      const pageIndex = Math.max(0, Math.min(page - 1, pages.length - 1));
      const targetPage = pages[pageIndex];
      if (!targetPage) return null;
      const targetArchiveId = targetPage.sourceArchiveId || archiveId;
      const localPage = pages
        .slice(0, pageIndex + 1)
        .filter(item => (item.sourceArchiveId || archiveId) === targetArchiveId).length;
      return {
        archiveId: targetArchiveId,
        page: Math.max(1, localPage),
        globalPage: pageIndex + 1,
      };
    },
    [archiveId, pages],
  );

  const persistReadingProgress = useCallback(
    async (page: number, reason: string) => {
      const target = resolveProgressTarget(page);
      if (!target) return;
      const key = `${target.archiveId}:${target.page}`;
      if (lastSavedProgressKey.current === key) return;
      try {
        await updateArchiveProgress(target.archiveId, target.page);
        lastSavedProgressKey.current = key;
        await appendDiagnosticLog('reader.progress.saved', {
          reason,
          archiveId: target.archiveId,
          page: target.page,
          globalPage: target.globalPage,
        });
      } catch (err) {
        await appendDiagnosticLog('reader.progress.error', {
          reason,
          archiveId: target.archiveId,
          page: target.page,
          globalPage: target.globalPage,
          message: extractApiError(err),
        });
        console.warn(extractApiError(err, 'Failed to save progress'));
      }
    },
    [resolveProgressTarget],
  );

  useEffect(() => {
    if (!pages.length || currentPage <= 0 || currentPage > pages.length) return;
    const timer = setTimeout(() => {
      persistReadingProgress(currentPage, 'settled').catch(err => {
        console.warn(extractApiError(err, 'Failed to save progress'));
      });
    }, 900);
    return () => clearTimeout(timer);
  }, [currentPage, pages.length, persistReadingProgress]);

  useEffect(() => {
    appendDiagnosticLog('reader.collectionContext', {
      archiveId,
      childIndex,
      childrenCount: Array.isArray(children) ? children.length : 0,
      children,
      tankoubonId,
    }).catch(reason => console.warn('Failed to write diagnostic log:', reason));
  }, [archiveId, childIndex, children, tankoubonId]);

  const archiveChildren = useMemo(
    () => (Array.isArray(children) ? children.filter(Boolean) : []),
    [children],
  );
  const tailArchiveId = pages[pages.length - 1]?.sourceArchiveId || archiveId;
  const nextArchive = nextArchiveById[tailArchiveId] ?? null;
  const nextArchiveId = nextArchive?.id;
  const hasNextArchive = Boolean(nextArchiveId);
  const shouldShowCollectionEnd = Boolean(settings.seamlessNext && pages.length);

  useEffect(() => {
    appendDiagnosticLog('reader.collectionEnd', {
      archiveId,
      hasNextArchive,
      nextArchiveId,
      pages: pages.length,
      seamlessNext: settings.seamlessNext,
      shouldShowCollectionEnd,
      tailArchiveId,
    }).catch(reason => console.warn('Failed to write diagnostic log:', reason));
  }, [archiveId, hasNextArchive, nextArchiveId, pages.length, settings.seamlessNext, shouldShowCollectionEnd, tailArchiveId]);

  const readerItems = useMemo<ReaderItem[]>(() => {
    const appendCollectionEnd = (items: ReaderItem[]) => {
      if (!shouldShowCollectionEnd || settings.readingMode === 'webtoon') return items;
      return [
        ...items,
        {
          key: 'collection-end',
          kind: 'collection-end' as const,
          pages: [],
          progressPage: pages.length + 1,
        },
      ];
    };
    if (!settings.doublePage || settings.readingMode === 'webtoon') {
      return appendCollectionEnd(pages.map(page => ({
        kind: 'pages' as const,
        key: String(page.pageNumber),
        pages: [page],
        progressPage: page.pageNumber,
      })));
    }
    const out: ReaderItem[] = [];
    let index = 0;
    if (settings.splitCover && pages[0]) {
      out.push({key: 'cover', kind: 'pages', pages: [pages[0]], progressPage: 1});
      index = 1;
    }
    while (index < pages.length) {
      const pair = pages.slice(index, index + 2);
      out.push({
        key: pair.map(page => page.pageNumber).join('-'),
        kind: 'pages',
        pages: settings.readingMode === 'single-rtl' ? [...pair].reverse() : pair,
        progressPage: pair[0].pageNumber,
      });
      index += 2;
    }
    return appendCollectionEnd(out);
  }, [pages, settings.doublePage, settings.readingMode, settings.splitCover, shouldShowCollectionEnd]);
  const webtoonItems = useMemo<ReaderWebtoonItem[]>(
    () =>
      shouldShowCollectionEnd
        ? [
            ...pages,
            {
              kind: 'collection-end' as const,
              key: 'collection-end',
              pageNumber: pages.length + 1,
            },
          ]
        : pages,
    [pages, shouldShowCollectionEnd],
  );

  const currentItemIndex = useMemo(() => {
    const index = readerItems.findIndex(item =>
      item.progressPage === currentPage || item.pages.some(page => page.pageNumber === currentPage),
    );
    if (index >= 0) return index;
    return currentPage > pages.length ? Math.max(0, readerItems.length - 1) : 0;
  }, [currentPage, pages.length, readerItems]);

  const activeReaderItem = readerItems[currentItemIndex];
  const activeMediaPages = useMemo(
    () =>
      (activeReaderItem?.pages || []).filter(
        page => page.uri && (page.effectiveType === 'video' || page.effectiveType === 'audio'),
      ),
    [activeReaderItem],
  );
  const lanes = useMemo<ReaderLane[]>(
    () => [
      ...(activeReaderItem?.pages || [])
        .filter(page => page.effectiveType === 'video' || page.effectiveType === 'audio')
        .map((page, index) => ({
          id: `${page.effectiveType}-${page.pageNumber}`,
          kind: page.effectiveType as 'video' | 'audio',
          label:
            page.effectiveType === 'audio'
              ? `${t('reader.audio')}${activeReaderItem.pages.length > 1 ? ` ${index + 1}` : ''}`
              : `${t('reader.video')}${activeReaderItem.pages.length > 1 ? ` ${index + 1}` : ''}`,
          page,
        })),
      {id: 'book', kind: 'book', label: t('reader.book')},
    ],
    [activeReaderItem, t],
  );
  const activeLane = useMemo(
    () => lanes.find(lane => lane.id === activeLaneId) || lanes[0],
    [activeLaneId, lanes],
  );

  useEffect(() => {
    if (!lanes.length) return;
    const activeReaderItemKey = activeReaderItem?.key || '';
    const preferredLane = lanes.find(lane => lane.kind !== 'book') || lanes.find(lane => lane.id === 'book') || lanes[0];
    const activeLaneExists = lanes.some(lane => lane.id === activeLaneId);

    if (!activeLaneExists) {
      autoPreferredLaneItemKey.current = activeReaderItemKey;
      setActiveLaneId(preferredLane.id);
      return;
    }

    if (autoPreferredLaneItemKey.current === activeReaderItemKey) return;
    autoPreferredLaneItemKey.current = activeReaderItemKey;

    if (activeLaneId === 'book' && preferredLane.id !== 'book') {
      setActiveLaneId(preferredLane.id);
    }
  }, [activeLaneId, activeReaderItem, lanes]);

  const activeSubtitleIndexes = useMemo(
    () => (activeLane.kind !== 'book' ? activeSubtitleIndexesByPage[activeLane.page.pageNumber] || [] : []),
    [activeLane, activeSubtitleIndexesByPage],
  );
  const activeEmbeddedSubtitleTrack =
    activeLane.kind !== 'book' ? activeEmbeddedSubtitleTrackByPage[activeLane.page.pageNumber] : undefined;
  const activeSubtitleAttachments = useMemo(
    () =>
      activeLane.kind !== 'book'
        ? getPageSubtitleAttachments(activeLane.page).filter((_, index) => activeSubtitleIndexes.includes(index))
        : [],
    [activeLane, activeSubtitleIndexes],
  );
  const activeExternalVlcSubtitleAttachment = useMemo(
    () =>
      activeSubtitleAttachments.length === 1 && isAssSubtitleAttachment(activeSubtitleAttachments[0])
        ? activeSubtitleAttachments[0]
        : null,
    [activeSubtitleAttachments],
  );
  const activeSubtitleAssetKey = activeSubtitleAttachments
    .map(attachment => attachment.asset_id)
    .filter(id => id > 0)
    .join('|');
  const activeLyricsAttachments = useMemo(
    () =>
      activeMediaPages
        .filter(page => page.effectiveType === 'audio')
        .map(page => {
          const selectedIndex = activeLyricsIndexByPage[page.pageNumber] ?? 0;
          if (selectedIndex === SUBTITLE_OFF_VALUE) return undefined;
          return getPageLyricsAttachments(page)[selectedIndex];
        })
        .filter((attachment): attachment is MetadataPageAttachment => Boolean(attachment?.asset_id)),
    [activeLyricsIndexByPage, activeMediaPages],
  );
  const activeLyricsAssetKey = activeLyricsAttachments
    .map(attachment => attachment.asset_id)
    .filter(id => id > 0)
    .join('|');
  const activeAudioPanelSubtitleAttachments = useMemo(
    () =>
      activeMediaPages
        .filter(page => page.effectiveType === 'audio')
        .map(page => getPageSubtitleAttachments(page)[0])
        .filter((attachment): attachment is MetadataPageAttachment => Boolean(attachment?.asset_id)),
    [activeMediaPages],
  );
  const activeAudioPanelSubtitleAssetKey = activeAudioPanelSubtitleAttachments
    .map(attachment => attachment.asset_id)
    .filter(id => id > 0)
    .join('|');
  const nearbyMediaPages = useMemo(
    () =>
      pages.filter(
        page =>
          page.uri &&
          !page.vlcUri &&
          Math.abs(page.pageNumber - currentPage) <= 1 &&
          (page.effectiveType === 'video' || page.effectiveType === 'audio'),
      ),
    [currentPage, pages],
  );
  const nearbyHtmlPages = useMemo(
    () =>
      pages.filter(
        page =>
          page.effectiveType === 'html' &&
          Boolean(page.backendUri || page.uri) &&
          Math.abs(page.pageNumber - currentPage) <= 1,
      ),
    [currentPage, pages],
  );
  useEffect(() => {
    let cancelled = false;
    const loadSubtitles = async () => {
      const attachments = [...activeSubtitleAttachments, ...activeLyricsAttachments, ...activeAudioPanelSubtitleAttachments].filter(
        (attachment, index, all) =>
          attachment.asset_id > 0 && all.findIndex(item => item.asset_id === attachment.asset_id) === index,
      );
      await Promise.all(
        attachments.map(async attachment => {
          if (subtitleTextsByAssetId[attachment.asset_id] != null) return;
          const path = assetPath(attachment.asset_id);
          if (!path) return;
          try {
            const response = await apiClient.get<string>(path, {
              responseType: 'text',
              transformResponse: [value => value],
            });
            if (cancelled) return;
            const text = typeof response.data === 'string' ? response.data : String(response.data || '');
            setSubtitleTextsByAssetId(current =>
              current[attachment.asset_id] != null
                ? current
                : {...current, [attachment.asset_id]: text.replace(/^\uFEFF/, '').trim()},
            );
          } catch (err) {
            appendDiagnosticLog('subtitle.load.error', {
              archiveId,
              page: activeLane.kind !== 'book' ? activeLane.page.pageNumber : undefined,
              assetId: attachment.asset_id,
              message: extractApiError(err),
            }).catch(reason => console.warn('Failed to write diagnostic log:', reason));
          }
        }),
      );
    };

    loadSubtitles().catch(err => console.warn('Failed to load subtitles:', err));
    return () => {
      cancelled = true;
    };
  }, [
    activeLane,
    activeAudioPanelSubtitleAssetKey,
    activeAudioPanelSubtitleAttachments,
    activeLyricsAssetKey,
    activeLyricsAttachments,
    activeSubtitleAssetKey,
    activeSubtitleAttachments,
    archiveId,
    subtitleTextsByAssetId,
  ]);

  useEffect(() => {
    if (activeLane.kind === 'book') return;
    const pageNumber = activeLane.page.pageNumber;
    let cancelled = false;

    if (!activeExternalVlcSubtitleAttachment?.asset_id) {
      setExternalVlcSubtitleUriByPage(current =>
        current[pageNumber] == null ? current : {...current, [pageNumber]: undefined},
      );
      return;
    }

    const resolveSubtitleUri = async () => {
      const assetId = activeExternalVlcSubtitleAttachment.asset_id;
      const cachedSubtitleUri = localSubtitleUriByAssetId[assetId];
      if (cachedSubtitleUri) {
        setExternalVlcSubtitleUriByPage(current =>
          current[pageNumber] === cachedSubtitleUri ? current : {...current, [pageNumber]: cachedSubtitleUri},
        );
        return;
      }

      const text = subtitleTextsByAssetId[assetId];
      if (!text?.trim()) return;
      const pendingSubtitle =
        pendingLocalSubtitleByAssetId.current[assetId] ||
        createLocalSubtitleFile(text, subtitleFileExtension(activeExternalVlcSubtitleAttachment));
      pendingLocalSubtitleByAssetId.current[assetId] = pendingSubtitle;
      const subtitleUri = await pendingSubtitle.finally(() => {
        if (pendingLocalSubtitleByAssetId.current[assetId] === pendingSubtitle) {
          pendingLocalSubtitleByAssetId.current[assetId] = undefined;
        }
      });
      if (cancelled) return;
      if (!subtitleUri) return;
      appendDiagnosticLog('subtitle.localFile.ready', {
        archiveId,
        page: pageNumber,
        assetId,
        subtitleUri,
      }).catch(reason => console.warn('Failed to write diagnostic log:', reason));
      setLocalSubtitleUriByAssetId(current =>
        current[assetId] === subtitleUri ? current : {...current, [assetId]: subtitleUri},
      );
      setExternalVlcSubtitleUriByPage(current =>
        current[pageNumber] === subtitleUri ? current : {...current, [pageNumber]: subtitleUri},
      );
    };

    resolveSubtitleUri().catch(err => {
      appendDiagnosticLog('subtitle.vlcUri.error', {
        archiveId,
        page: pageNumber,
        assetId: activeExternalVlcSubtitleAttachment.asset_id,
        message: extractApiError(err),
      }).catch(reason => console.warn('Failed to write diagnostic log:', reason));
    });

    return () => {
      cancelled = true;
    };
  }, [activeExternalVlcSubtitleAttachment, activeLane, archiveId, localSubtitleUriByAssetId, subtitleTextsByAssetId]);

  const viewabilityConfig = useMemo(() => ({itemVisiblePercentThreshold: 60}), []);
  const onViewableItemsChanged = useRef(
    ({viewableItems}: {viewableItems: ViewToken<ReaderItem>[]}) => {
      if (progressSeekLockedRef.current) return;
      const first = viewableItems[0]?.item;
      if (first?.progressPage) setCurrentPage(first.progressPage);
    },
  );

  const activePage = pages[currentPage - 1];
  const isOnCollectionEnd = activeReaderItem?.kind === 'collection-end' || currentPage > pages.length;

  const resolveNextArchiveCandidate = useCallback(
    async (targetArchiveId: string, excludedIds: Set<string>): Promise<NextArchiveCandidate | null> => {
      const cached = nextArchiveCache.current[targetArchiveId];
      if (cached !== undefined && (!cached?.id || !excludedIds.has(cached.id))) return cached;

      const routeIndex = archiveChildren.indexOf(targetArchiveId);
      const routeNextId = routeIndex >= 0 ? archiveChildren[routeIndex + 1] : undefined;
      if (routeNextId && routeNextId !== targetArchiveId && !excludedIds.has(routeNextId)) {
        try {
          const meta = await fetchArchiveMetadata(routeNextId);
          const candidate = {
            id: routeNextId,
            title: meta.title?.trim() || meta.filename || routeNextId,
            source: 'tankoubon' as const,
          };
          nextArchiveCache.current[targetArchiveId] = candidate;
          return candidate;
        } catch {
          const candidate = {id: routeNextId, title: routeNextId, source: 'tankoubon' as const};
          nextArchiveCache.current[targetArchiveId] = candidate;
          return candidate;
        }
      }

      try {
        const tanks = await fetchTankoubonsForArchive(targetArchiveId);
        const chosen = [...tanks].sort((a, b) => {
          const favorite = Number(Boolean(b.isfavorite)) - Number(Boolean(a.isfavorite));
          if (favorite !== 0) return favorite;
          return (b.children?.length || 0) - (a.children?.length || 0);
        })[0];
        const index = chosen?.children?.indexOf(targetArchiveId) ?? -1;
        const nextId = index >= 0 ? chosen?.children?.[index + 1] : undefined;
        if (nextId && nextId !== targetArchiveId && !excludedIds.has(nextId)) {
          try {
            const meta = await fetchArchiveMetadata(nextId);
            const candidate = {
              id: nextId,
              title: meta.title?.trim() || meta.filename || nextId,
              source: 'tankoubon' as const,
            };
            nextArchiveCache.current[targetArchiveId] = candidate;
            return candidate;
          } catch {
            const candidate = {id: nextId, title: nextId, source: 'tankoubon' as const};
            nextArchiveCache.current[targetArchiveId] = candidate;
            return candidate;
          }
        }
      } catch (err) {
        appendDiagnosticLog('reader.next.tankoubon.error', {
          archiveId: targetArchiveId,
          message: extractApiError(err),
        }).catch(reason => console.warn('Failed to write diagnostic log:', reason));
      }

      for (let attempt = 0; attempt < 3; attempt += 1) {
        try {
          const related = await fetchArchiveRelated(targetArchiveId, 8);
          const item = related.find(candidate => candidate.arcid !== targetArchiveId && !excludedIds.has(candidate.arcid));
          if (item) {
            const candidate = {
              id: item.arcid,
              title: item.title?.trim() || item.filename || item.arcid,
              source: 'archive_related' as const,
            };
            nextArchiveCache.current[targetArchiveId] = candidate;
            return candidate;
          }
        } catch (err) {
          appendDiagnosticLog('reader.next.related.error', {
            archiveId: targetArchiveId,
            attempt,
            message: extractApiError(err),
          }).catch(reason => console.warn('Failed to write diagnostic log:', reason));
        }
      }

      nextArchiveCache.current[targetArchiveId] = null;
      return null;
    },
    [archiveChildren],
  );

  const appendNextArchiveToStream = useCallback(async () => {
    if (!settings.seamlessNext || appendingNext || !tailArchiveId) return false;
    const excluded = new Set(appendedArchiveIds.current);
    excluded.add(tailArchiveId);
    setAppendingNext(true);
    try {
      const candidate = await resolveNextArchiveCandidate(tailArchiveId, excluded);
      setNextArchiveById(current => ({...current, [tailArchiveId]: candidate}));
      if (!candidate?.id || appendedArchiveIds.current.has(candidate.id)) return false;
      const files = await fetchArchiveFiles(candidate.id);
      if (!files.length) return false;
      const start = pages.length;
      const hydrated = await Promise.all(files.map((page, index) => hydratePage(page, start + index, candidate.id)));
      appendedArchiveIds.current.add(candidate.id);
      setPages(current => [...current, ...hydrated]);
      setCurrentPage(start + 1);
      return true;
    } catch (err) {
      appendDiagnosticLog('reader.next.append.error', {
        archiveId: tailArchiveId,
        message: extractApiError(err),
      }).catch(reason => console.warn('Failed to write diagnostic log:', reason));
      return false;
    } finally {
      setAppendingNext(false);
    }
  }, [appendingNext, hydratePage, pages.length, resolveNextArchiveCandidate, settings.seamlessNext, tailArchiveId]);

  useEffect(() => {
    if (!settings.seamlessNext || !tailArchiveId || nextArchiveById[tailArchiveId] !== undefined) return;
    const excluded = new Set(appendedArchiveIds.current);
    excluded.add(tailArchiveId);
    let cancelled = false;
    resolveNextArchiveCandidate(tailArchiveId, excluded)
      .then(candidate => {
        if (cancelled) return;
        setNextArchiveById(current => ({...current, [tailArchiveId]: candidate}));
      })
      .catch(err => {
        appendDiagnosticLog('reader.next.resolve.error', {
          archiveId: tailArchiveId,
          message: extractApiError(err),
        }).catch(reason => console.warn('Failed to write diagnostic log:', reason));
      });
    return () => {
      cancelled = true;
    };
  }, [nextArchiveById, resolveNextArchiveCandidate, settings.seamlessNext, tailArchiveId]);

  const scrollToReaderItem = useCallback(
    (itemIndex: number, animated = true) => {
      const index = Math.max(0, itemIndex);
      const dimension = settings.readingMode === 'single-ltr' || settings.readingMode === 'single-rtl' ? width : height;
      listRef.current?.scrollToOffset({
        animated,
        offset: dimension * index,
      });
    },
    [height, settings.readingMode, width],
  );

  const goToPage = useCallback(
    (page: number) => {
      if (!pages.length) return;
      const lastReaderPage =
        shouldShowCollectionEnd && settings.readingMode === 'webtoon'
          ? pages.length + 1
          : readerItems[readerItems.length - 1]?.progressPage || pages.length;
      if (page > lastReaderPage && isOnCollectionEnd) {
        appendNextArchiveToStream().catch(err => console.warn('Failed to append next archive:', err));
        return;
      }
      const next = Math.max(1, Math.min(page, lastReaderPage));
      setCurrentPage(next);
      if (settings.readingMode === 'webtoon') {
        webtoonRef.current?.scrollToOffset({
          animated: true,
          offset: (next > pages.length ? pages.length : next - 1) * height,
        });
        return;
      }
      const itemIndex = readerItems.findIndex(item =>
        item.progressPage === next || item.pages.some(readerPage => readerPage.pageNumber === next),
      );
      if (itemIndex < 0) return;
      scrollToReaderItem(itemIndex);
    },
    [appendNextArchiveToStream, height, isOnCollectionEnd, pages.length, readerItems, scrollToReaderItem, settings.readingMode, shouldShowCollectionEnd],
  );

  const goToNextPage = useCallback(() => {
    if (isOnCollectionEnd) {
      appendNextArchiveToStream().catch(err => console.warn('Failed to append next archive:', err));
      return;
    }
    goToPage(currentPage + 1);
  }, [appendNextArchiveToStream, currentPage, goToPage, isOnCollectionEnd]);

  const jumpToPageFromProgress = useCallback(
    (page: number) => {
      if (progressSeekLockedRef.current || !pages.length) return;
      const lastReaderPage =
        shouldShowCollectionEnd && settings.readingMode === 'webtoon'
          ? pages.length + 1
          : readerItems[readerItems.length - 1]?.progressPage || pages.length;
      const next = Math.max(1, Math.min(page, lastReaderPage));
      const targetIndex = Math.min(next, pages.length) - 1;
      appendDiagnosticLog('reader.progress.jump.start', {
        requestedPage: page,
        targetPage: next,
        targetIndex,
        readingMode: settings.readingMode,
      }).catch(reason => console.warn('Failed to write diagnostic log:', reason));
      progressSeekLockedRef.current = true;
      setProgressSeekLocked(true);

      if (settings.readingMode === 'webtoon') {
        webtoonRef.current?.scrollToIndex({
          animated: false,
          index: Math.max(0, targetIndex),
        });
      } else {
        const itemIndex = readerItems.findIndex(item =>
          item.progressPage === next || item.pages.some(readerPage => readerPage.pageNumber === next),
        );
        if (itemIndex >= 0) scrollToReaderItem(itemIndex, false);
      }

      setTimeout(() => {
        setCurrentPage(next);
        if (next <= pages.length) {
          persistReadingProgress(next, 'progress-jump').catch(err => {
            console.warn(extractApiError(err, 'Failed to save progress'));
          });
        }
      }, 80);

      setTimeout(() => {
        progressSeekLockedRef.current = false;
        setProgressSeekLocked(false);
        appendDiagnosticLog('reader.progress.jump.done', {
          targetPage: next,
          readingMode: settings.readingMode,
        }).catch(reason => console.warn('Failed to write diagnostic log:', reason));
      }, 450);
    },
    [pages.length, persistReadingProgress, readerItems, scrollToReaderItem, settings.readingMode, shouldShowCollectionEnd],
  );

  useEffect(() => {
    if (!settings.autoPlay || settings.readingMode === 'webtoon') return;
    const timer = setInterval(goToNextPage, settings.autoPlayInterval * 1000);
    return () => clearInterval(timer);
  }, [goToNextPage, settings.autoPlay, settings.autoPlayInterval, settings.readingMode]);

  useEffect(() => {
    if (autoHideTimerRef.current) clearTimeout(autoHideTimerRef.current);
    if (!settings.autoHide || !chromeVisible || settingsOpen) return;
    autoHideTimerRef.current = setTimeout(() => setChromeVisible(false), 3000);
    return () => {
      if (autoHideTimerRef.current) clearTimeout(autoHideTimerRef.current);
    };
  }, [chromeVisible, currentPage, settings.autoHide, settingsOpen]);

  useEffect(() => {
    const landscape = width > height;
    setSystemBarsHidden(landscape && settings.autoHide && !chromeVisible, true);
  }, [chromeVisible, height, settings.autoHide, width]);

  useEffect(() => {
    setSystemBarsHidden(false, true);
    return () => {
      Object.values(vlcResumeTimers.current).forEach(timer => {
        if (timer) clearTimeout(timer);
      });
      vlcResumeTimers.current = {};
      setSystemBarsHidden(false, false);
    };
  }, []);

  useEffect(() => {
    if (settings.autoHide) return;
    setChromeVisible(true);
  }, [settings.autoHide]);

  function patchSettings(patch: Partial<ReaderSettings>) {
    setSettings(current => {
      const next = {...current, ...patch};
      if (next.readingMode === 'webtoon') next.doublePage = false;
      return next;
    });
  }

  function cycleMode() {
    patchSettings({readingMode: nextReadingMode(settings.readingMode)});
  }

  function handleOpenSourceSheet(page: ReaderPage) {
    setSourceSheetPageId(page.pageNumber);
    setSourceSheetOpen(true);
  }

  function handleSelectSource(value: number) {
    if (sourceSheetPageId == null) return;
    setSourceIndexByPage(prev => ({...prev, [sourceSheetPageId - 1]: value}));
    setSourceSheetOpen(false);
    setSourceSheetPageId(null);
  }

  function handleSetActiveLane(laneId: string) {
    LayoutAnimation.configureNext({
      duration: 220,
      create: {type: LayoutAnimation.Types.easeInEaseOut, property: LayoutAnimation.Properties.opacity},
      update: {type: LayoutAnimation.Types.easeInEaseOut},
      delete: {type: LayoutAnimation.Types.easeInEaseOut, property: LayoutAnimation.Properties.opacity},
    });
    setActiveLaneId(laneId);
  }

  function handleToggleFavorite() {
    const next = !isFavorited;
    setIsFavorited(next);
    fetchArchiveMetadata(archiveId)
      .then(meta => setArchiveFavorite(meta, next))
      .catch(err => {
        console.warn('Failed to toggle favorite:', err);
        setIsFavorited(!next);
      });
  }

  const handleSidebarSelectPage = useCallback(
    (pageIndex: number) => {
      jumpToPageFromProgress(pageIndex + 1);
    },
    [jumpToPageFromProgress],
  );

  function handleSelectSubtitle(value: number) {
    if (activeLane.kind === 'book') return;
    const pageNumber = activeLane.page.pageNumber;
    const embeddedTrackId = decodeEmbeddedSubtitleValue(value);
    if (value === SUBTITLE_OFF_VALUE) {
      setActiveSubtitleIndexesByPage(prev => ({...prev, [pageNumber]: []}));
      setActiveEmbeddedSubtitleTrackByPage(prev => ({...prev, [pageNumber]: undefined}));
      return;
    }
    if (embeddedTrackId != null) {
      setActiveEmbeddedSubtitleTrackByPage(prev => ({
        ...prev,
        [pageNumber]: prev[pageNumber] === embeddedTrackId ? undefined : embeddedTrackId,
      }));
      return;
    }
    setActiveSubtitleIndexesByPage(prev => {
      const set = new Set(prev[pageNumber] || []);
      if (set.has(value)) set.delete(value);
      else set.add(value);
      return {...prev, [pageNumber]: Array.from(set).sort((a, b) => a - b)};
    });
  }

  function handleSelectLyrics(value: number) {
    if (activeLane.kind !== 'audio') return;
    const pageNumber = activeLane.page.pageNumber;
    setActiveLyricsIndexByPage(prev => ({...prev, [pageNumber]: value}));
    setSubtitleSheetOpen(false);
  }

  function handleVolumeChange(pageNumber: number, value: number) {
    setMediaState(pageNumber, {muted: false, volume: Math.max(0, Math.min(1, value))});
  }

  const getMediaState = useCallback(
    (pageNumber: number): MediaPlaybackState =>
      mediaStateByPage[pageNumber] || {
        currentTime: 0,
        duration: 0,
        position: 0,
        paused: false,
        muted: false,
        volume: 1,
        buffered: 0,
      },
    [mediaStateByPage],
  );

  const setMediaState = useCallback(
    (pageNumber: number, patch: Partial<MediaPlaybackState>) => {
      setMediaStateByPage(current => {
        const previous =
          current[pageNumber] || {
            currentTime: 0,
            duration: 0,
            position: 0,
            paused: false,
            muted: false,
            volume: 1,
          };
        return {
          ...current,
          [pageNumber]: {
            ...previous,
            ...patch,
          },
        };
      });
    },
    [],
  );

  function seekMedia(page: ReaderPage, seconds: number, reason = 'manual') {
    const state = getMediaState(page.pageNumber);
    const session = vlcSessions.current[page.pageNumber];
    const duration = state.duration;
    const now = Date.now();
    if (!session?.playable || duration <= 0 || !vlcRefs.current[page.pageNumber]) {
      appendDiagnosticLog('media.seek.skipped', {
        archiveId,
        page: page.pageNumber,
        type: page.effectiveType,
        reason,
        seconds,
        currentTime: state.currentTime,
        duration,
        sessionPlayable: Boolean(session?.playable),
        hasPlayerRef: Boolean(vlcRefs.current[page.pageNumber]),
        target: session?.target,
        skipReason: !session?.playable ? 'not-playable' : duration <= 0 ? 'no-duration' : 'missing-player-ref',
      }).catch(err => console.warn('Failed to write diagnostic log:', err));
      return;
    }
    const lastSeekAt = mediaLastSeekAt.current[page.pageNumber] || 0;
    if (now - lastSeekAt < 350) {
      appendDiagnosticLog('media.seek.skipped', {
        archiveId,
        page: page.pageNumber,
        type: page.effectiveType,
        reason,
        seconds,
        currentTime: state.currentTime,
        duration,
        target: session.target,
        skipReason: 'throttled',
        elapsedSinceLastSeek: now - lastSeekAt,
      }).catch(err => console.warn('Failed to write diagnostic log:', err));
      return;
    }
    mediaLastSeekAt.current[page.pageNumber] = now;
    const nextTime = Math.max(0, Math.min(duration, seconds));
    const position = Math.max(0, Math.min(1, nextTime / duration));
    mediaPendingSeekByPage.current[page.pageNumber] = {
      fromTime: state.currentTime,
      targetTime: nextTime,
      createdAt: now,
      reason,
    };
    mediaRecentSeekByPage.current[page.pageNumber] = {
      fromTime: state.currentTime,
      targetTime: nextTime,
      until: now + 3000,
      reason,
    };
    vlcRefs.current[page.pageNumber]?.seek(position);
    setMediaState(page.pageNumber, {currentTime: nextTime, position});
    appendDiagnosticLog('media.seek', {
      archiveId,
      page: page.pageNumber,
      type: page.effectiveType,
      reason,
      seconds,
      nextTime,
      duration,
      position,
      target: session.target,
    }).catch(err => console.warn('Failed to write diagnostic log:', err));
  }

  function toggleChrome() {
    if (!settings.autoHide) {
      setChromeVisible(true);
      return;
    }
    setChromeVisible(visible => !visible);
  }

  function handleReaderTap(x: number, y: number) {
    if (!settings.tapTurnPage) {
      toggleChrome();
      return;
    }

    setChromeVisible(true);
    const horizontalEdge = width * 0.32;
    const verticalEdge = height * 0.28;
    if (settings.readingMode === 'single-rtl') {
      if (x < horizontalEdge) {
        goToNextPage();
        return;
      }
      if (x > width - horizontalEdge) {
        goToPage(currentPage - 1);
        return;
      }
    } else if (settings.readingMode === 'single-ttb' || settings.readingMode === 'webtoon') {
      if (y < verticalEdge) {
        goToPage(currentPage - 1);
        return;
      }
      if (y > height - verticalEdge) {
        goToNextPage();
        return;
      }
    } else {
      if (x < horizontalEdge) {
        goToPage(currentPage - 1);
        return;
      }
      if (x > width - horizontalEdge) {
        goToNextPage();
        return;
      }
    }

    toggleChrome();
  }

  function handleReaderDoubleTap(pageNumber: number) {
    if (!settings.doubleTapZoom) return;
    setZoomedPages(current => ({...current, [pageNumber]: !current[pageNumber]}));
  }

  useEffect(() => {
    if (!pages.length) return;
    mediaProxyKeys.current.clear();
    htmlLoadingKeys.current.clear();
    setHtmlContents({});
    setHtmlHeights({});
    Promise.all(pages.map((page, index) => hydratePage(page, index)))
      .then(setPages)
      .catch(err => console.warn('Failed to switch reader source:', err));
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [sourceIndexByPage]);

  useEffect(() => {
    nearbyMediaPages.forEach(ensureMediaProxy);
  }, [ensureMediaProxy, nearbyMediaPages]);

  useEffect(() => {
    nearbyHtmlPages.forEach(page => {
      ensureHtmlContent(page).catch(err => console.warn('Failed to load HTML content:', err));
    });
  }, [ensureHtmlContent, nearbyHtmlPages]);

  useEffect(() => {
    if (!sidebarOpen) return;
    pages
      .filter(page => page.uri && !page.vlcUri && (page.effectiveType === 'video' || page.effectiveType === 'audio'))
      .forEach(ensureMediaProxy);
  }, [ensureMediaProxy, pages, sidebarOpen]);

  useEffect(() => {
    activeMediaPages.forEach(page => {
      const mediaOptions = buildVlcMediaOptions(page);
      appendDiagnosticLog('media.active', {
        archiveId,
        page: page.pageNumber,
        type: page.effectiveType,
        uri: page.uri,
        vlcUri: page.vlcUri,
        path: page.resolvedPath,
        currentPage,
        hasAuthorization: Boolean(page.headers?.Authorization),
        hasCookieToken: Boolean(page.token),
        mediaOptions,
      }).catch(reason => console.warn('Failed to write diagnostic log:', reason));

      const probeKey = `${page.pageNumber}:${page.uri}`;
      if (mediaProbeKeys.current.has(probeKey)) return;
      mediaProbeKeys.current.add(probeKey);
      appendDiagnosticLog('media.probe.start', {
        archiveId,
        page: page.pageNumber,
        type: page.effectiveType,
        uri: page.uri,
        path: page.resolvedPath,
        range: 'bytes=0-0',
        hasAuthorization: Boolean(page.headers?.Authorization),
      }).catch(reason => console.warn('Failed to write diagnostic log:', reason));
      probeMediaPage(page.uri || '')
        .then(async result => {
          await appendDiagnosticLog('media.probe', {
            archiveId,
            page: page.pageNumber,
            type: page.effectiveType,
            uri: page.uri,
            vlcUri: page.vlcUri,
            path: page.resolvedPath,
            ...result,
          });
          if (result.status >= 500) {
            const fallbackRange = 'bytes=0-1023';
            await appendDiagnosticLog('media.probe.start', {
              archiveId,
              page: page.pageNumber,
              type: page.effectiveType,
              uri: page.uri,
              vlcUri: page.vlcUri,
              path: page.resolvedPath,
              range: fallbackRange,
              hasAuthorization: Boolean(page.headers?.Authorization),
            });
            const fallbackResult = await probeMediaPage(page.uri || '', fallbackRange);
            await appendDiagnosticLog('media.probe', {
              archiveId,
              page: page.pageNumber,
              type: page.effectiveType,
              uri: page.uri,
              path: page.resolvedPath,
              ...fallbackResult,
            });
          }
        })
        .catch(err => {
          const response = (err as {response?: {status?: number; headers?: unknown}}).response;
          return appendDiagnosticLog('media.probe.error', {
            archiveId,
            page: page.pageNumber,
            type: page.effectiveType,
            uri: page.uri,
            vlcUri: page.vlcUri,
            path: page.resolvedPath,
            message: extractApiError(err),
            status: response?.status,
            headers: response?.headers,
          });
        })
        .catch(reason => console.warn('Failed to write diagnostic log:', reason));
    });
  }, [activeMediaPages, archiveId, currentPage]);

  if (loading) return <ScreenState loading title={t('reader.loading')} />;

  if (error) {
    return (
      <ScreenState
        title={t('reader.loadFailed')}
        message={error}
        actionLabel={t('common.retry')}
        onAction={() => load().catch(err => console.warn('Failed to load reader:', err))}
      />
    );
  }

  if (!pages.length) {
    return (
      <ScreenState
        title={t('reader.noPages')}
        message={t('reader.noPagesMessage')}
        actionLabel={t('reader.back')}
        onAction={() => navigation.goBack()}
      />
    );
  }

  const renderMedia = (
    page: ReaderPage,
    pageWidth: number,
    pageHeight?: number,
    webtoon = false,
    mediaActive = true,
  ) => {
    const commonError = failedPages[page.pageNumber];
    const frameStyle = webtoon
      ? [styles.webtoonPage, {width}]
      : [styles.mediaPage, {width: pageWidth, height: pageHeight || height}];
    const mediaFrameStyle =
      page.effectiveType === 'audio'
        ? [
            styles.audioMediaPage,
            {
              width: pageWidth,
              height: pageHeight || height,
              minHeight: pageHeight || height,
            },
          ]
        : frameStyle;
    if (page.effectiveType === 'video' || page.effectiveType === 'audio') {
      const mediaState = getMediaState(page.pageNumber);
      const mediaUri = page.vlcUri || page.uri || '';
      const waitingForProxy = Boolean(page.headers?.Authorization && !page.vlcUri);
      const pageEmbeddedSubtitleTrack = activeEmbeddedSubtitleTrackByPage[page.pageNumber];
      const pageSubtitleIndexes = activeSubtitleIndexesByPage[page.pageNumber] || [];
      const pageSubtitleAttachments = getPageSubtitleAttachments(page).filter((_, index) =>
        pageSubtitleIndexes.includes(index),
      );
      const externalVlcSubtitleUri = externalVlcSubtitleUriByPage[page.pageNumber];
      const mediaOptions = buildVlcMediaOptions(page, externalVlcSubtitleUri);
      const vlcSourceCacheKey = `${mediaUri}|${mediaOptions.join('\u0001')}`;
      let vlcSource = vlcSourceCache.current[page.pageNumber];
      if (vlcSource?.key !== vlcSourceCacheKey) {
        vlcSource = {
          key: vlcSourceCacheKey,
          source: {
            uri: mediaUri,
            isNetwork: Boolean(mediaUri.startsWith('http')),
            initType: 2,
            initOptions: ['--network-caching=600', ''],
            mediaOptions,
          },
        };
        vlcSourceCache.current[page.pageNumber] = vlcSource;
      }
      const overlaySubtitleAttachments = externalVlcSubtitleUri
        ? pageSubtitleAttachments.filter(attachment => !isAssSubtitleAttachment(attachment))
        : pageSubtitleAttachments;
      const activeSubtitleCues = getActiveSubtitleCues(
        overlaySubtitleAttachments,
        subtitleTextsByAssetId,
        mediaState.currentTime,
      );
      const displayMetadata = page.activeSource?.metadata || page.metadata;
      const pageLyricsAttachments = page.effectiveType === 'audio' ? getPageLyricsAttachments(page) : [];
      const selectedLyricsIndex = activeLyricsIndexByPage[page.pageNumber] ?? 0;
      const lyricsAttachment = selectedLyricsIndex === SUBTITLE_OFF_VALUE
        ? undefined
        : pageLyricsAttachments[selectedLyricsIndex];
      const lyricsText = lyricsAttachment?.asset_id ? subtitleTextsByAssetId[lyricsAttachment.asset_id] || '' : '';
      const timedLyrics = page.effectiveType === 'audio' && lyricsText ? parseTimedLyrics(lyricsText) : [];
      const activeLyricIndex = timedLyrics.length ? getActiveTimedLyricIndex(timedLyrics, mediaState.currentTime) : -1;
      const activeLyricLine = activeLyricIndex >= 0 ? timedLyrics[activeLyricIndex] : undefined;
      const previousLyricSnapshot = audioLyricSnapshots.current[page.pageNumber];
      const lyricSnapshotChanged =
        page.effectiveType === 'audio' &&
        timedLyrics.length > 0 &&
        (!previousLyricSnapshot ||
          previousLyricSnapshot.activeLyricIndex !== activeLyricIndex ||
          Math.abs(previousLyricSnapshot.playbackTime - mediaState.currentTime) >= 1.2);
      if (lyricSnapshotChanged) {
        const snapshot: AudioLyricSnapshot = {
          activeLyricIndex,
          activeLineTime: activeLyricLine?.time,
          activeTextPreview: activeLyricLine?.text.slice(0, 80),
          playbackTime: mediaState.currentTime,
          timedLyricsCount: timedLyrics.length,
          updatedAt: Date.now(),
        };
        audioLyricSnapshots.current[page.pageNumber] = snapshot;
        const debugWindow = audioLyricDebugWindows.current[page.pageNumber];
        if (debugWindow && snapshot.updatedAt <= debugWindow.until) {
          appendDiagnosticLog('audio.lyric.active', {
            archiveId,
            page: page.pageNumber,
            sourceArchiveId: page.sourceArchiveId,
            sourcePath: page.resolvedPath,
            debugTargetTime: debugWindow.targetTime,
            clickedLineIndex: debugWindow.lineIndex,
            clickedLineTime: debugWindow.lineTime,
            clickedTextPreview: debugWindow.textPreview,
            ...snapshot,
          }).catch(err => console.warn('Failed to write diagnostic log:', err));
        }
      }
      const plainLyricLines = page.effectiveType === 'audio' && lyricsText && !timedLyrics.length
        ? getPlainLyricLines(lyricsText)
        : [];
      const audioSubtitleAttachment = page.effectiveType === 'audio'
        ? pageSubtitleAttachments[0] || getPageSubtitleAttachments(page)[0]
        : undefined;
      const audioSubtitleText = audioSubtitleAttachment?.asset_id
        ? subtitleTextsByAssetId[audioSubtitleAttachment.asset_id] || ''
        : '';
      const audioSubtitleLines = audioSubtitleText
        .split(/\r?\n/)
        .map(line => line.trim())
        .filter(Boolean);
      const audioTitle = displayMetadata?.title || page.activeSource?.title || page.title || page.resolvedPath || `${t('reader.audio')} ${page.pageNumber}`;
      const audioDescription = displayMetadata?.description?.trim();
      const resolvedPageHeight = pageHeight || height;
      const audioLandscape = pageWidth > resolvedPageHeight && pageWidth >= 620;
      const audioCompact = !audioLandscape && (pageWidth < 620 || resolvedPageHeight < 520);
      const audioCoverSize = Math.round(
        Math.max(
          audioLandscape ? 96 : 132,
          Math.min(
            audioLandscape ? 164 : audioCompact ? 196 : 276,
            pageWidth * (audioLandscape ? 0.18 : audioCompact ? 0.48 : 0.32),
            resolvedPageHeight * (audioLandscape ? 0.32 : 0.42),
          ),
        ),
      );
      const audioProgress = mediaState.duration > 0 ? mediaState.currentTime / mediaState.duration : mediaState.position;
      const audioBackdropWidth = Math.max(1, Math.round(pageWidth));
      const audioBackdropHeight = Math.max(1, Math.round(resolvedPageHeight));
      const audioBackdropKey = `${page.pageNumber}:${audioBackdropWidth}x${audioBackdropHeight}:${audioLandscape ? 'landscape' : 'portrait'}`;
      const audioGradientId = `reader-audio-mask-${page.pageNumber}-${audioBackdropWidth}-${audioBackdropHeight}-${audioLandscape ? 'l' : 'p'}`;
      const audioHero = (
        <View
          style={[
            styles.audioHero,
            audioLandscape ? styles.audioHeroLandscape : audioCompact ? styles.audioHeroCompact : styles.audioHeroWide,
          ]}>
          <AudioCoverArtwork
            paused={mediaState.paused}
            size={audioCoverSize}
            source={page.thumbnailSource}
          />
          <View
            style={[
              styles.audioTextBlock,
              audioCompact && styles.audioTextBlockCompact,
              audioLandscape && styles.audioTextBlockLandscape,
            ]}>
            <Text
              numberOfLines={audioLandscape ? 2 : 2}
              style={[
                styles.audioTitle,
                audioCompact && styles.audioTitleCompact,
                audioLandscape && styles.audioTitleLandscape,
              ]}>
              {audioTitle}
            </Text>
            {audioDescription ? (
              <Text
                numberOfLines={audioLandscape ? 2 : audioCompact ? 2 : 4}
                style={[styles.audioDescription, audioLandscape && styles.audioDescriptionLandscape]}>
                {audioDescription}
              </Text>
            ) : null}
            <Text numberOfLines={1} style={[styles.audioPathText, audioLandscape && styles.audioPathTextLandscape]}>
              {page.resolvedPath || page.id}
            </Text>
          </View>
        </View>
      );
      const audioLyricsPanel = (
        <AudioLyricsPanel
          activeLyricIndex={activeLyricIndex}
          audioLandscape={audioLandscape}
          audioSubtitleAttachment={audioSubtitleAttachment}
          audioSubtitleLines={audioSubtitleLines}
          audioSubtitleText={audioSubtitleText}
          lyricsAttachment={lyricsAttachment}
          lyricsText={lyricsText}
          plainLyricLines={plainLyricLines}
          t={t}
          timedLyrics={timedLyrics}
          onLyricTouchTrace={trace => {
            appendDiagnosticLog('audio.lyric.touch', {
              archiveId,
              page: page.pageNumber,
              sourceArchiveId: page.sourceArchiveId,
              sourcePath: page.resolvedPath,
              playbackTime: mediaState.currentTime,
              duration: mediaState.duration,
              paused: mediaState.paused,
              selectedLyricsIndex,
              lyricsAssetId: lyricsAttachment?.asset_id,
              ...trace,
            }).catch(err => console.warn('Failed to write diagnostic log:', err));
          }}
          onSeekLyric={(seconds, trace) => {
            audioLyricDebugWindows.current[page.pageNumber] = {
              until: Date.now() + 20000,
              lastProgressLogAt: 0,
              lineIndex: trace?.lineIndex,
              lineTime: trace?.lineTime,
              targetTime: seconds,
              textPreview: trace?.textPreview,
            };
            appendDiagnosticLog('audio.lyric.seek_request', {
              archiveId,
              page: page.pageNumber,
              sourceArchiveId: page.sourceArchiveId,
              sourcePath: page.resolvedPath,
              playbackTime: mediaState.currentTime,
              duration: mediaState.duration,
              paused: mediaState.paused,
              activeLyricIndex,
              selectedLyricsIndex,
              lyricsAssetId: lyricsAttachment?.asset_id,
              seconds,
              trace,
            }).catch(err => console.warn('Failed to write diagnostic log:', err));
            seekMedia(page, seconds, 'audio-lyric');
          }}
        />
      );
      const audioPlayerDock = (
        <View style={[styles.audioPlayerDock, audioLandscape && styles.audioPlayerDockLandscape]}>
          <View style={styles.audioProgressRow}>
            <Text style={styles.audioTimeText}>{formatMediaTime(mediaState.currentTime)}</Text>
            <View style={styles.audioProgressTrack}>
              <View
                style={[
                  styles.audioProgressBuffered,
                  {width: `${Math.max(0, Math.min(100, (mediaState.buffered || 0) * 100))}%`},
                ]}
              />
              <View
                style={[
                  styles.audioProgressFill,
                  {width: `${Math.max(1, Math.min(100, audioProgress * 100))}%`},
                ]}
              />
            </View>
            <Text style={styles.audioTimeText}>{formatMediaTime(mediaState.duration)}</Text>
          </View>
          <View style={[styles.audioTransportRow, audioLandscape && styles.audioTransportRowLandscape]}>
            <TouchableOpacity
              accessibilityLabel={t('reader.seekBack')}
              accessibilityRole="button"
              activeOpacity={0.82}
              onPress={() => seekMedia(page, mediaState.currentTime - 5, 'audio-back')}
              style={[styles.audioTransportSideButton, audioLandscape && styles.audioTransportSideButtonLandscape]}>
              <Rewind color={colors.white} size={22} />
            </TouchableOpacity>
            <TouchableOpacity
              accessibilityLabel={mediaState.paused ? t('reader.play') : t('reader.pause')}
              accessibilityRole="button"
              activeOpacity={0.86}
              onPress={() =>
                setMediaState(page.pageNumber, {
                  paused: !getMediaState(page.pageNumber).paused,
                })
              }
              style={[styles.audioTransportPlayButton, audioLandscape && styles.audioTransportPlayButtonLandscape]}>
              {mediaState.paused ? (
                <Play color={colors.black} size={audioLandscape ? 24 : 30} />
              ) : (
                <Pause color={colors.black} size={audioLandscape ? 24 : 30} />
              )}
            </TouchableOpacity>
            <TouchableOpacity
              accessibilityLabel={t('reader.seekForward')}
              accessibilityRole="button"
              activeOpacity={0.82}
              onPress={() => seekMedia(page, mediaState.currentTime + 5, 'audio-forward')}
              style={[styles.audioTransportSideButton, audioLandscape && styles.audioTransportSideButtonLandscape]}>
              <FastForward color={colors.white} size={22} />
            </TouchableOpacity>
          </View>
        </View>
      );
      const vlcSourceKey = mediaUri;
      const vlcSubtitleKey = externalVlcSubtitleUri || '';
      if (vlcSourceKeys.current[page.pageNumber] !== vlcSourceKey) {
        if (vlcResumeTimers.current[page.pageNumber]) {
          clearTimeout(vlcResumeTimers.current[page.pageNumber]);
          vlcResumeTimers.current[page.pageNumber] = undefined;
        }
        vlcSourceKeys.current[page.pageNumber] = vlcSourceKey;
        vlcSubtitleKeys.current[page.pageNumber] = vlcSubtitleKey;
        vlcSessions.current[page.pageNumber] = {
          playable: false,
          ignoredProgress: 0,
        };
        mediaPendingSeekByPage.current[page.pageNumber] = undefined;
        embeddedVlcSubtitleTrackBaseline.current[page.pageNumber] = undefined;
        externalVlcSubtitleTrackIds.current[page.pageNumber] = undefined;
      } else if (vlcSubtitleKeys.current[page.pageNumber] !== vlcSubtitleKey) {
        if (mediaState.currentTime > 1) {
          vlcResumeAfterReload.current[page.pageNumber] = mediaState.currentTime;
        }
        if (vlcResumeTimers.current[page.pageNumber]) {
          clearTimeout(vlcResumeTimers.current[page.pageNumber]);
          vlcResumeTimers.current[page.pageNumber] = undefined;
        }
        vlcSubtitleKeys.current[page.pageNumber] = vlcSubtitleKey;
        vlcSessions.current[page.pageNumber] = {
          playable: false,
          ignoredProgress: 0,
        };
        mediaPendingSeekByPage.current[page.pageNumber] = undefined;
      }
      if (!mediaActive) {
        return (
          <View style={frameStyle}>
            <Text style={styles.loadingText}>
              {page.effectiveType === 'audio' ? t('reader.audio') : t('reader.video')}
            </Text>
          </View>
        );
      }
      if (waitingForProxy) {
        return (
          <View style={frameStyle}>
            <Text style={styles.loadingText}>{t('reader.loadingPage', {page: page.pageNumber})}</Text>
          </View>
        );
      }
      return (
        <View style={mediaFrameStyle}>
          {page.effectiveType === 'audio' ? (
            <View
              key={audioBackdropKey}
              pointerEvents="none"
              style={[
                styles.audioBackdrop,
                {height: audioBackdropHeight, width: audioBackdropWidth},
              ]}>
              {page.thumbnailSource ? (
                <Image
                  blurRadius={22}
                  resizeMode="cover"
                  source={page.thumbnailSource}
                  style={styles.audioBackdropImage}
                />
              ) : null}
              <Svg
                height={audioBackdropHeight}
                pointerEvents="none"
                style={styles.audioBackdropGradient}
                width={audioBackdropWidth}>
                <Defs>
                  {audioLandscape ? (
                    <LinearGradient id={audioGradientId} x1="0" x2="1" y1="0" y2="0">
                        <Stop offset="0" stopColor="#000000" stopOpacity="0.14" />
                        <Stop offset="0.42" stopColor="#000000" stopOpacity="0.2" />
                        <Stop offset="0.72" stopColor="#000000" stopOpacity="0.4" />
                        <Stop offset="1" stopColor="#000000" stopOpacity="0.68" />
                    </LinearGradient>
                  ) : (
                    <LinearGradient id={audioGradientId} x1="0" x2="0" y1="0" y2="1">
                        <Stop offset="0" stopColor="#000000" stopOpacity="0.1" />
                        <Stop offset="0.38" stopColor="#000000" stopOpacity="0.18" />
                        <Stop offset="0.72" stopColor="#000000" stopOpacity="0.46" />
                        <Stop offset="1" stopColor="#000000" stopOpacity="0.7" />
                    </LinearGradient>
                  )}
                </Defs>
                <Rect
                  fill={`url(#${audioGradientId})`}
                  height={audioBackdropHeight}
                  width={audioBackdropWidth}
                  x="0"
                  y="0"
                />
              </Svg>
            </View>
          ) : null}
          <StableVlcPlayer
            playerKey={vlcSourceKey}
            playerRef={ref => {
              vlcRefs.current[page.pageNumber] = ref;
            }}
            paused={mediaState.paused}
            muted={mediaState.muted}
            textTrack={pageEmbeddedSubtitleTrack ?? -1}
            subtitleUri={vlcSubtitlePath(externalVlcSubtitleUri)}
            volume={Math.round(Math.max(0, Math.min(1, mediaState.volume)) * 100)}
            source={vlcSource.source}
            style={page.effectiveType === 'audio' ? styles.audioStage : styles.pageImage}
            onBuffering={event => {
              const buffered = normalizeVlcBufferRate(event);
              const bucket = Math.floor(buffered * 10);
              const now = Date.now();
              const lastBufferUiAt = mediaLastBufferUiAt.current[page.pageNumber] || 0;
              const previousBuffered = getMediaState(page.pageNumber).buffered;
              if (
                vlcBufferLogBuckets.current[page.pageNumber] !== bucket &&
                now - lastBufferUiAt >= 250
              ) {
                vlcBufferLogBuckets.current[page.pageNumber] = bucket;
                appendDiagnosticLog('vlc.buffering', {
                  archiveId,
                  page: page.pageNumber,
                  type: page.effectiveType,
                  buffered,
                  event,
                }).catch(reason => console.warn('Failed to write diagnostic log:', reason));
              }
              if (
                now - lastBufferUiAt >= 500 ||
                Math.abs(buffered - previousBuffered) >= 0.25 ||
                (buffered >= 1 && previousBuffered < 1)
              ) {
                mediaLastBufferUiAt.current[page.pageNumber] = now;
                setMediaState(page.pageNumber, {buffered});
              }
            }}
            onEnd={() => {
              setMediaState(page.pageNumber, {paused: true});
              appendDiagnosticLog('vlc.end', {
                archiveId,
                page: page.pageNumber,
                type: page.effectiveType,
              }).catch(reason => console.warn('Failed to write diagnostic log:', reason));
            }}
            onError={err => {
              appendDiagnosticLog('vlc.error', {
                archiveId,
                page: page.pageNumber,
                type: page.effectiveType,
                uri: page.uri,
                vlcUri: page.vlcUri,
                path: page.resolvedPath,
                hasAuthorization: Boolean(page.headers?.Authorization),
                hasCookieToken: Boolean(page.token),
                mediaOptions,
                event: err,
              }).catch(reason => console.warn('Failed to write diagnostic log:', reason));
              setFailedPages(current => ({
                ...current,
                [page.pageNumber]: JSON.stringify(err),
              }));
            }}
            onLoad={event => {
              const vlcTracks = Array.isArray((event as any).textTracks)
                ? ((event as any).textTracks as Array<{id?: number | string; name?: string}>)
                    .map(track => ({
                      id: Number(track.id),
                      name: String(track.name || '').trim(),
                    }))
                    .filter(track => Number.isFinite(track.id) && track.id >= 0)
                : [];
              const knownExternalTrackIds = new Set(externalVlcSubtitleTrackIds.current[page.pageNumber] || []);
              const knownEmbeddedTracks = embeddedSubtitleTracksByPage[page.pageNumber] || [];
              const namedExternalTrackIds = vlcTracks
                .filter(track => isExternalVlcTextTrack(track, externalVlcSubtitleUri))
                .map(track => track.id);
              const cleanVlcTracks = vlcTracks.filter(
                track => !knownExternalTrackIds.has(track.id) && !namedExternalTrackIds.includes(track.id),
              );
              let embeddedTracks = cleanVlcTracks;
              if (externalVlcSubtitleUri) {
                const baseline = embeddedVlcSubtitleTrackBaseline.current[page.pageNumber] || knownEmbeddedTracks;
                const baselineIds = new Set(baseline.map(track => track.id));
                const externalTrackIds = vlcTracks
                  .filter(track => !baselineIds.has(track.id) || namedExternalTrackIds.includes(track.id))
                  .map(track => track.id);
                externalVlcSubtitleTrackIds.current[page.pageNumber] = Array.from(
                  new Set([...(externalVlcSubtitleTrackIds.current[page.pageNumber] || []), ...externalTrackIds]),
                );
                embeddedTracks = baseline.filter(track => vlcTracks.some(vlcTrack => vlcTrack.id === track.id));
              } else {
                embeddedVlcSubtitleTrackBaseline.current[page.pageNumber] = cleanVlcTracks;
              }
              appendDiagnosticLog('vlc.load', {
                archiveId,
                page: page.pageNumber,
                type: page.effectiveType,
                uri: page.uri,
                vlcUri: page.vlcUri,
                subtitleUri: externalVlcSubtitleUri,
                mediaOptions,
                path: page.resolvedPath,
                duration: event.duration,
                textTracks: vlcTracks,
                embeddedTextTracks: embeddedTracks,
                externalTextTrackIds: externalVlcSubtitleTrackIds.current[page.pageNumber] || [],
              }).catch(reason => console.warn('Failed to write diagnostic log:', reason));
              setMediaState(page.pageNumber, {
                duration: normalizeVlcSeconds(event.duration),
              });
              setEmbeddedSubtitleTracksByPage(current => {
                const previous = current[page.pageNumber] || [];
                const same =
                  previous.length === embeddedTracks.length &&
                  previous.every((track, index) => track.id === embeddedTracks[index]?.id && track.name === embeddedTracks[index]?.name);
                if (same) return current;
                return {...current, [page.pageNumber]: embeddedTracks};
              });
            }}
            onPaused={() => setMediaState(page.pageNumber, {paused: true})}
            onPlaying={event => {
              const resumeTime = vlcResumeAfterReload.current[page.pageNumber];
              const duration = normalizeVlcSeconds(event.duration);
              vlcSessions.current[page.pageNumber] = {
                target: event.target,
                playable: true,
                ignoredProgress: vlcSessions.current[page.pageNumber]?.ignoredProgress || 0,
              };
              appendDiagnosticLog('vlc.playing', {
                archiveId,
                page: page.pageNumber,
                type: page.effectiveType,
                target: event.target,
                duration: event.duration,
                subtitleUri: externalVlcSubtitleUri,
                resumeTime,
              }).catch(reason => console.warn('Failed to write diagnostic log:', reason));
              setMediaState(page.pageNumber, {
                duration,
                paused: false,
              });
              if (resumeTime && duration > 0 && !vlcResumeTimers.current[page.pageNumber]) {
                vlcResumeTimers.current[page.pageNumber] = setTimeout(() => {
                  vlcResumeTimers.current[page.pageNumber] = undefined;
                  if (vlcResumeAfterReload.current[page.pageNumber] !== resumeTime) return;
                  vlcResumeAfterReload.current[page.pageNumber] = undefined;
                  const nextTime = Math.max(0, Math.min(duration, resumeTime));
                  const position = Math.max(0, Math.min(1, nextTime / duration));
                  vlcRefs.current[page.pageNumber]?.seek(position);
                  mediaPendingSeekByPage.current[page.pageNumber] = {
                    fromTime: getMediaState(page.pageNumber).currentTime,
                    targetTime: nextTime,
                    createdAt: Date.now(),
                    reason: 'resume-after-subtitle',
                  };
                  mediaRecentSeekByPage.current[page.pageNumber] = {
                    fromTime: getMediaState(page.pageNumber).currentTime,
                    targetTime: nextTime,
                    until: Date.now() + 3000,
                    reason: 'resume-after-subtitle',
                  };
                  setMediaState(page.pageNumber, {currentTime: nextTime, position});
                  appendDiagnosticLog('vlc.resumeAfterSubtitle', {
                    archiveId,
                    page: page.pageNumber,
                    type: page.effectiveType,
                    resumeTime,
                    position,
                    subtitleUri: externalVlcSubtitleUri,
                  }).catch(reason => console.warn('Failed to write diagnostic log:', reason));
                }, 800);
              }
            }}
            onProgress={(event: VlcPlaybackEvent) => {
              const session = vlcSessions.current[page.pageNumber];
              const staleTarget = Boolean(session?.target && event.target && session.target !== event.target);
              if (!session?.playable || staleTarget) {
                const ignoredProgress = (session?.ignoredProgress || 0) + 1;
                vlcSessions.current[page.pageNumber] = {
                  target: session?.target ?? event.target,
                  playable: Boolean(session?.playable),
                  ignoredProgress,
                };
                if (ignoredProgress <= 4) {
                  appendDiagnosticLog('vlc.progress.ignored', {
                    archiveId,
                    page: page.pageNumber,
                    type: page.effectiveType,
                    reason: staleTarget ? 'stale-target' : 'before-playing',
                    sessionTarget: session?.target,
                    target: event.target,
                    currentTime: event.currentTime,
                    duration: event.duration,
                    position: event.position,
                  }).catch(reason => console.warn('Failed to write diagnostic log:', reason));
                }
                return;
              }
              const progress = normalizeVlcProgress(event);
              if (progress.duration <= 0 || progress.currentTime > progress.duration + 1) return;
              const now = Date.now();
              const lyricDebugWindow = audioLyricDebugWindows.current[page.pageNumber];
              if (lyricDebugWindow) {
                if (now > lyricDebugWindow.until) {
                  audioLyricDebugWindows.current[page.pageNumber] = undefined;
                } else if (
                  now - lyricDebugWindow.lastProgressLogAt >= 1000 ||
                  Math.abs(progress.currentTime - lyricDebugWindow.targetTime) <= 0.35
                ) {
                  lyricDebugWindow.lastProgressLogAt = now;
                  const snapshot = audioLyricSnapshots.current[page.pageNumber];
                  appendDiagnosticLog('audio.lyric.progress', {
                    archiveId,
                    page: page.pageNumber,
                    type: page.effectiveType,
                    debugTargetTime: lyricDebugWindow.targetTime,
                    clickedLineIndex: lyricDebugWindow.lineIndex,
                    clickedLineTime: lyricDebugWindow.lineTime,
                    clickedTextPreview: lyricDebugWindow.textPreview,
                    currentTime: progress.currentTime,
                    duration: progress.duration,
                    position: progress.position,
                    rawCurrentTime: event.currentTime,
                    rawDuration: event.duration,
                    rawPosition: event.position,
                    paused: getMediaState(page.pageNumber).paused,
                    activeLyricIndex: snapshot?.activeLyricIndex,
                    activeLineTime: snapshot?.activeLineTime,
                    activeTextPreview: snapshot?.activeTextPreview,
                    snapshotPlaybackTime: snapshot?.playbackTime,
                  }).catch(reason => console.warn('Failed to write diagnostic log:', reason));
                }
              }
              const pendingSeek = mediaPendingSeekByPage.current[page.pageNumber];
              if (pendingSeek) {
                const seekAge = now - pendingSeek.createdAt;
                const seekingBackward = pendingSeek.targetTime < pendingSeek.fromTime - 0.35;
                const seekingForward = pendingSeek.targetTime > pendingSeek.fromTime + 0.35;
                const reachedSeekTarget =
                  (seekingBackward
                    ? progress.currentTime <= pendingSeek.targetTime + 0.35
                    : seekingForward
                      ? progress.currentTime >= pendingSeek.targetTime - 0.35
                      : true) ||
                  Math.abs(progress.currentTime - pendingSeek.targetTime) <= 0.35;
                if (reachedSeekTarget || seekAge > 1800) {
                  appendDiagnosticLog('media.seek.progress_resolved', {
                    archiveId,
                    page: page.pageNumber,
                    type: page.effectiveType,
                    reason: pendingSeek.reason,
                    fromTime: pendingSeek.fromTime,
                    targetTime: pendingSeek.targetTime,
                    currentTime: progress.currentTime,
                    duration: progress.duration,
                    position: progress.position,
                    seekAge,
                    reachedSeekTarget,
                    timedOut: seekAge > 1800,
                  }).catch(reason => console.warn('Failed to write diagnostic log:', reason));
                  mediaPendingSeekByPage.current[page.pageNumber] = undefined;
                } else if (
                  (seekingForward && progress.currentTime + 0.35 < pendingSeek.targetTime) ||
                  (seekingBackward && progress.currentTime - 0.35 > pendingSeek.targetTime)
                ) {
                  if (seekAge > 1000) {
                    appendDiagnosticLog('media.seek.progress_waiting', {
                      archiveId,
                      page: page.pageNumber,
                      type: page.effectiveType,
                      reason: pendingSeek.reason,
                      targetTime: pendingSeek.targetTime,
                      currentTime: progress.currentTime,
                      duration: progress.duration,
                    }).catch(reason => console.warn('Failed to write diagnostic log:', reason));
                    mediaPendingSeekByPage.current[page.pageNumber] = undefined;
                  }
                  return;
                }
              }
              const previous = getMediaState(page.pageNumber);
              const recentSeek = mediaRecentSeekByPage.current[page.pageNumber];
              if (recentSeek && now > recentSeek.until) {
                mediaRecentSeekByPage.current[page.pageNumber] = undefined;
              } else if (recentSeek) {
                const seekingForward = recentSeek.targetTime > recentSeek.fromTime + 0.35;
                const seekingBackward = recentSeek.targetTime < recentSeek.fromTime - 0.35;
                const staleAfterForwardSeek =
                  seekingForward &&
                  (progress.currentTime + 0.5 < previous.currentTime ||
                    progress.currentTime + 0.35 < recentSeek.targetTime);
                const staleAfterBackwardSeek =
                  seekingBackward &&
                  (progress.currentTime - 0.5 > previous.currentTime ||
                    progress.currentTime - 0.35 > recentSeek.targetTime);
                if (staleAfterForwardSeek || staleAfterBackwardSeek) {
                  appendDiagnosticLog('vlc.progress.stale_after_seek', {
                    archiveId,
                    page: page.pageNumber,
                    type: page.effectiveType,
                    reason: recentSeek.reason,
                    fromTime: recentSeek.fromTime,
                    targetTime: recentSeek.targetTime,
                    previousTime: previous.currentTime,
                    currentTime: progress.currentTime,
                    duration: progress.duration,
                    position: progress.position,
                    rawCurrentTime: event.currentTime,
                    rawDuration: event.duration,
                    rawPosition: event.position,
                  }).catch(reason => console.warn('Failed to write diagnostic log:', reason));
                  return;
                }
              } else if (progress.currentTime + 0.75 < previous.currentTime && !previous.paused) {
                appendDiagnosticLog('vlc.progress.regression_ignored', {
                  archiveId,
                  page: page.pageNumber,
                  type: page.effectiveType,
                  previousTime: previous.currentTime,
                  currentTime: progress.currentTime,
                  duration: progress.duration,
                  position: progress.position,
                  rawCurrentTime: event.currentTime,
                  rawDuration: event.duration,
                  rawPosition: event.position,
                }).catch(reason => console.warn('Failed to write diagnostic log:', reason));
                return;
              }
              const lastUiAt = mediaLastProgressUiAt.current[page.pageNumber] || 0;
              const currentTimeDelta = Math.abs(progress.currentTime - previous.currentTime);
              const durationDelta = Math.abs(progress.duration - previous.duration);
              const shouldUpdateUi =
                now - lastUiAt >= 250 ||
                currentTimeDelta >= 0.5 ||
                durationDelta >= 0.5 ||
                Math.abs(progress.position - previous.position) >= 0.01;
              if (!shouldUpdateUi) return;
              mediaLastProgressUiAt.current[page.pageNumber] = now;
              setMediaState(page.pageNumber, progress);
            }}
          />
          {page.effectiveType === 'audio' ? (
            <View
              pointerEvents="box-none"
              style={[
                styles.audioScene,
                {
                  paddingBottom: stableInsets.bottom + (audioLandscape ? (chromeVisible ? 46 : 10) : chromeVisible ? 72 : 18),
                  paddingTop: stableInsets.top + (audioLandscape ? (chromeVisible ? 42 : 10) : chromeVisible ? 70 : 18),
                },
              ]}>
              <View
                style={[
                  styles.audioSceneInner,
                  audioLandscape
                    ? styles.audioSceneInnerLandscape
                    : audioCompact
                      ? styles.audioSceneInnerCompact
                      : styles.audioSceneInnerWide,
                ]}>
                {audioLandscape ? (
                  <>
                    <View style={styles.audioLandscapeLeftPane}>
                      {audioHero}
                      {audioPlayerDock}
                    </View>
                    {audioLyricsPanel}
                  </>
                ) : (
                  <>
                    {audioHero}
                    {audioLyricsPanel}
                    {audioPlayerDock}
                  </>
                )}
              </View>
            </View>
          ) : null}
          {page.effectiveType !== 'audio' ? (
            <View
              pointerEvents={chromeVisible ? 'box-none' : 'none'}
              style={[styles.mediaOverlayControls, !chromeVisible && styles.mediaOverlayControlsHidden]}>
              <TouchableOpacity
                accessibilityLabel={t('reader.seekBack')}
                accessibilityRole="button"
                activeOpacity={0.82}
                onPress={() => seekMedia(page, mediaState.currentTime - 5, 'overlay-back')}
                style={styles.mediaSeekButton}>
                <Rewind color={colors.white} size={22} />
              </TouchableOpacity>
              <TouchableOpacity
                accessibilityLabel={mediaState.paused ? t('reader.play') : t('reader.pause')}
                accessibilityRole="button"
                activeOpacity={0.82}
                onPress={() =>
                  setMediaState(page.pageNumber, {
                    paused: !getMediaState(page.pageNumber).paused,
                  })
                }
                style={styles.mediaCenterButton}>
                {mediaState.paused ? (
                  <Play color={colors.white} size={28} />
                ) : (
                  <Pause color={colors.white} size={28} />
                )}
              </TouchableOpacity>
              <TouchableOpacity
                accessibilityLabel={t('reader.seekForward')}
                accessibilityRole="button"
                activeOpacity={0.82}
                onPress={() => seekMedia(page, mediaState.currentTime + 5, 'overlay-forward')}
                style={styles.mediaSeekButton}>
                <FastForward color={colors.white} size={22} />
              </TouchableOpacity>
            </View>
          ) : null}
          {page.effectiveType !== 'audio' ? (
            <>
              {activeSubtitleCues.length > 0 ? (
                <View pointerEvents="none" style={styles.subtitleOverlay}>
                  {activeSubtitleCues.map((cue, index) => (
                    <Text key={`${index}-${cue.start}-${cue.end}`} style={styles.subtitleText}>
                      {cue.text}
                    </Text>
                  ))}
                </View>
              ) : null}
            </>
          ) : activeSubtitleCues.length > 0 ? (
            <View pointerEvents="none" style={styles.audioTimedSubtitleOverlay}>
              {activeSubtitleCues.map((cue, index) => (
                <Text key={`${index}-${cue.start}-${cue.end}`} style={styles.subtitleText}>
                  {cue.text}
                </Text>
              ))}
            </View>
          ) : null}
          {commonError ? <ErrorOverlay title={t('reader.mediaFailed')} message={commonError} /> : null}
        </View>
      );
    }

    if (page.effectiveType === 'html') {
      const measuredHtmlHeight = htmlHeights[page.pageNumber] || 0;
      const htmlHeight =
        webtoon && settings.longPage
          ? Math.max(height, measuredHtmlHeight || 0)
          : pageHeight || height;
      const htmlFrameStyle = frameStyle;
      const html = htmlContents[page.pageNumber];
      const htmlSource = html
        ? {
            html,
            baseUrl: page.uri?.startsWith('http://127.0.0.1') ? page.uri : undefined,
          }
        : undefined;
      return (
        <View collapsable={false} renderToHardwareTextureAndroid style={htmlFrameStyle}>
          {htmlSource ? (
            <WebView
              allowsBackForwardNavigationGestures
              androidLayerType="software"
              domStorageEnabled={false}
              injectedJavaScript={`
                (function () {
                  var style = document.createElement('style');
                  style.textContent = [
                    'html,body{display:block!important;visibility:visible!important;opacity:1!important;background:#fff!important;color:#111!important;writing-mode:horizontal-tb!important;}',
                    'body{min-height:100vh!important;margin:0!important;padding:16px!important;box-sizing:border-box!important;}',
                    'body,body *{visibility:visible!important;opacity:1!important;}',
                    'p,div,h1,h2,h3,h4,h5,h6,li,a,span{color:#111!important;}',
                    'img,svg,video,canvas{display:block!important;max-width:100%!important;height:auto!important;margin-left:auto!important;margin-right:auto!important;}'
                  ].join('\\n');
                  document.head.appendChild(style);
                  var body = document.body;
                  var html = document.documentElement;
                  var lastHeight = 0;
                  function postMetrics() {
                    body = document.body;
                    html = document.documentElement;
                    var first = body && body.firstElementChild;
                    var firstRect = first ? first.getBoundingClientRect() : null;
                    var bodyStyle = body ? window.getComputedStyle(body) : null;
                    var bodyScrollHeight = body ? body.scrollHeight : 0;
                    var documentScrollHeight = html ? html.scrollHeight : 0;
                    var measuredHeight = Math.ceil(Math.max(
                      bodyScrollHeight,
                      documentScrollHeight,
                      body ? body.offsetHeight : 0,
                      html ? html.offsetHeight : 0,
                      window.innerHeight || 0
                    ));
                    if (Math.abs(measuredHeight - lastHeight) < 2 && lastHeight > 0) return;
                    lastHeight = measuredHeight;
                    window.ReactNativeWebView.postMessage(JSON.stringify({
                      kind: 'epub-dom',
                      height: measuredHeight,
                      bodyTextLength: body ? (body.innerText || body.textContent || '').length : 0,
                      bodyChildren: body ? body.children.length : 0,
                      bodyScrollHeight: bodyScrollHeight,
                      documentScrollHeight: documentScrollHeight,
                      images: document.images ? document.images.length : 0,
                      bodyDisplay: bodyStyle ? bodyStyle.display : '',
                      bodyVisibility: bodyStyle ? bodyStyle.visibility : '',
                      bodyColor: bodyStyle ? bodyStyle.color : '',
                      firstRect: firstRect ? {x:firstRect.x,y:firstRect.y,width:firstRect.width,height:firstRect.height} : null
                    }));
                  }
                  function scheduleMetrics() {
                    setTimeout(postMetrics, 0);
                    setTimeout(postMetrics, 120);
                    setTimeout(postMetrics, 600);
                  }
                  window.addEventListener('load', scheduleMetrics);
                  window.addEventListener('resize', scheduleMetrics);
                  document.addEventListener('DOMContentLoaded', scheduleMetrics);
                  Array.prototype.forEach.call(document.images || [], function (image) {
                    image.addEventListener('load', scheduleMetrics);
                    image.addEventListener('error', scheduleMetrics);
                  });
                  scheduleMetrics();
                })();
                true;
              `}
              javaScriptEnabled
              mixedContentMode="always"
              originWhitelist={['*']}
              overScrollMode="never"
              scrollEnabled={false}
              source={htmlSource}
              textZoom={100}
              style={[styles.webView, {width: pageWidth, height: htmlHeight}]}
              containerStyle={[styles.webViewContainer, {width: pageWidth, height: htmlHeight}]}
              onLoadStart={event => {
                appendDiagnosticLog('html.webview.loadStart', {
                  archiveId: page.sourceArchiveId || archiveId,
                  page: page.pageNumber,
                  uri: event.nativeEvent.url,
                  path: page.resolvedPath,
                }).catch(reason => console.warn('Failed to write diagnostic log:', reason));
              }}
              onLoadEnd={event => {
                appendDiagnosticLog('html.webview.loadEnd', {
                  archiveId: page.sourceArchiveId || archiveId,
                  page: page.pageNumber,
                  uri: event.nativeEvent.url,
                  baseUrl: page.uri,
                  path: page.resolvedPath,
                }).catch(reason => console.warn('Failed to write diagnostic log:', reason));
              }}
              onError={event => {
                setFailedPages(current => ({
                  ...current,
                  [page.pageNumber]: event.nativeEvent.description,
                }));
                appendDiagnosticLog('html.webview.error', {
                  archiveId: page.sourceArchiveId || archiveId,
                  page: page.pageNumber,
                  uri: event.nativeEvent.url,
                  path: page.resolvedPath,
                  description: event.nativeEvent.description,
                }).catch(reason => console.warn('Failed to write diagnostic log:', reason));
              }}
              onHttpError={event => {
                appendDiagnosticLog('html.webview.httpError', {
                  archiveId: page.sourceArchiveId || archiveId,
                  page: page.pageNumber,
                  uri: event.nativeEvent.url,
                  statusCode: event.nativeEvent.statusCode,
                  description: event.nativeEvent.description,
                }).catch(reason => console.warn('Failed to write diagnostic log:', reason));
              }}
              onMessage={event => {
                try {
                  const payload = JSON.parse(event.nativeEvent.data) as {kind?: string; height?: number};
                  if (payload.kind === 'epub-dom' && typeof payload.height === 'number' && payload.height > 0) {
                    setHtmlHeights(current => {
                      const nextHeight = Math.ceil(payload.height || 0);
                      if (Math.abs((current[page.pageNumber] || 0) - nextHeight) < 2) return current;
                      return {...current, [page.pageNumber]: nextHeight};
                    });
                  }
                } catch {
                }
                appendDiagnosticLog('html.webview.message', {
                  archiveId: page.sourceArchiveId || archiveId,
                  page: page.pageNumber,
                  data: event.nativeEvent.data,
                }).catch(reason => console.warn('Failed to write diagnostic log:', reason));
              }}
            />
          ) : (
            <Text style={styles.loadingText}>{t('reader.loadingPage', {page: page.pageNumber})}</Text>
          )}
          {commonError ? <ErrorOverlay title={t('reader.htmlFailed')} message={commonError} /> : null}
        </View>
      );
    }

    return (
      <View style={frameStyle}>
        {page.imageSource ? (
          <>
            {!loadedPages[page.pageNumber] && !commonError ? (
              <Text style={styles.loadingText}>{t('reader.loadingPage', {page: page.pageNumber})}</Text>
            ) : null}
            <Image
              onError={event => {
                setFailedPages(current => ({
                  ...current,
                  [page.pageNumber]: event.nativeEvent.error || 'Image failed to load.',
                }));
              }}
              onLoad={() => setLoadedPages(current => ({...current, [page.pageNumber]: true}))}
              resizeMode="contain"
              source={page.imageSource}
              style={[
                webtoon ? styles.webtoonImage : styles.pageImage,
                webtoon && !settings.longPage && {height},
                zoomedPages[page.pageNumber] && styles.zoomedMedia,
              ]}
            />
            {commonError ? (
              <ErrorOverlay title={t('reader.pageFailed')} message={`${commonError}\n${page.resolvedPath || page.uri || ''}`} />
            ) : null}
          </>
        ) : (
          <ErrorOverlay title={t('reader.noImageSource')} message={page.id} />
        )}
      </View>
    );
  };

  const horizontal = settings.readingMode === 'single-ltr' || settings.readingMode === 'single-rtl';
  const pageFrameHeight = height;
  const sourceSheetPage = sourceSheetPageId
    ? pages.find(page => page.pageNumber === sourceSheetPageId)
    : activeLane.kind !== 'book'
      ? activeLane.page
      : null;
  const subtitleSheetPage = activeLane.kind !== 'book' ? activeLane.page : null;
  const lyricsSheetOpen = subtitleSheetPage?.effectiveType === 'audio';
  const subtitleSheetAttachments = getPageSubtitleAttachments(subtitleSheetPage);
  const lyricsSheetAttachments = lyricsSheetOpen ? getPageLyricsAttachments(subtitleSheetPage) : [];
  const embeddedSubtitleTracks = subtitleSheetPage ? embeddedSubtitleTracksByPage[subtitleSheetPage.pageNumber] || [] : [];
  const subtitleOptions: SelectOption[] = [
    {value: SUBTITLE_OFF_VALUE, label: t('reader.subtitleOff')},
    ...subtitleSheetAttachments.map((attachment, index) => ({
      value: index,
      label: t('reader.subtitleExternal', {label: buildSubtitleOptionLabel(attachment, index)}),
    })),
    ...embeddedSubtitleTracks.map((track, index) => ({
      value: encodeEmbeddedSubtitleValue(track.id),
      label: t('reader.subtitleEmbedded', {label: track.name || `Track ${index + 1}`}),
    })),
  ];
  const lyricsOptions: SelectOption[] = [
    {value: SUBTITLE_OFF_VALUE, label: t('reader.lyricsOff')},
    ...lyricsSheetAttachments.map((attachment, index) => ({
      value: index,
      label: t('reader.lyricsExternal', {label: buildLyricsOptionLabel(attachment, index)}),
    })),
  ];
  const rawLyricsSelectedValue = subtitleSheetPage
    ? activeLyricsIndexByPage[subtitleSheetPage.pageNumber] ?? 0
    : SUBTITLE_OFF_VALUE;
  const lyricsSelectedValue =
    rawLyricsSelectedValue >= 0 && rawLyricsSelectedValue < lyricsSheetAttachments.length
      ? rawLyricsSelectedValue
      : SUBTITLE_OFF_VALUE;
  const volumeSheetPage = volumeSheetPageId ? pages.find(page => page.pageNumber === volumeSheetPageId) : null;
  const volumeSheetState = volumeSheetPage ? getMediaState(volumeSheetPage.pageNumber) : null;
  const readerProgressTotal = readerItems[readerItems.length - 1]?.progressPage || pages.length;
  const displayCurrentPage = Math.min(currentPage, pages.length);

  const renderItem = ({item}: ListRenderItemInfo<ReaderItem>) => {
    if (item.kind === 'collection-end') {
      return (
        <ReaderTapSurface
          onTap={() => goToNextPage()}
          style={[styles.page, {width, height: pageFrameHeight}]}>
          <ReaderCollectionEndPage
            finishedPageCount={pages.length}
            nextArchiveId={nextArchiveId}
            nextTitle={nextArchive?.title}
            nextMode={nextArchive?.source}
            t={t}
            onOpenNext={goToNextPage}
          />
        </ReaderTapSurface>
      );
    }
    const spreadPageWidth = item.pages.length > 1 ? width / 2 : width;
    const mediaActive = item.pages.some(page => page.pageNumber === currentPage);
    return (
      <View style={[styles.page, {width, height: pageFrameHeight}]}>
        <View style={styles.spread}>
          {item.pages.map(page => (
            <View
              key={`${item.key}:${page.pageNumber}`}
              style={{width: spreadPageWidth, height: pageFrameHeight}}>
              <ReaderTapSurface
                onDoubleTap={() => handleReaderDoubleTap(page.pageNumber)}
                onTap={handleReaderTap}
                style={{width: spreadPageWidth, height: pageFrameHeight}}>
                {renderMedia(page, spreadPageWidth, pageFrameHeight, false, mediaActive)}
              </ReaderTapSurface>
            </View>
          ))}
        </View>
      </View>
    );
  };

  const renderWebtoonItem = ({item}: FlashListRenderItemInfo<ReaderWebtoonItem>) => {
    if ('kind' in item && item.kind === 'collection-end') {
      return (
        <ReaderTapSurface
          onTap={() => goToNextPage()}
          style={[styles.webtoonItem, {minHeight: height}]}>
          <ReaderCollectionEndPage
            finishedPageCount={pages.length}
            nextArchiveId={nextArchiveId}
            nextTitle={nextArchive?.title}
            nextMode={nextArchive?.source}
            t={t}
            onOpenNext={goToNextPage}
          />
        </ReaderTapSurface>
      );
    }
    const page = item as ReaderPage;
    const mediaActive = Math.abs(page.pageNumber - currentPage) <= 1;
    return (
      <ReaderTapSurface
        onDoubleTap={() => handleReaderDoubleTap(page.pageNumber)}
        onTap={handleReaderTap}
        style={styles.webtoonItem}>
        {renderMedia(page, width, settings.longPage ? undefined : height, true, mediaActive)}
      </ReaderTapSurface>
    );
  };

  return (
    <View style={styles.screen}>
      <StatusBar
        animated
        backgroundColor="transparent"
        barStyle="light-content"
        translucent
      />
      {settings.readingMode === 'webtoon' ? (
        <FlashList
          data={webtoonItems}
          drawDistance={height * 1.5}
          extraData={{
            currentPage,
            failedPages,
            htmlContents,
            htmlHeights,
            loadedPages,
            longPage: settings.longPage,
          }}
          key={`webtoon:${settings.longPage ? 'long' : 'paged'}`}
          keyExtractor={page => ('kind' in page ? page.key : `${page.pageNumber}:${page.uri || page.id}`)}
          onScroll={event => {
            if (progressSeekLockedRef.current) return;
            const approx =
              Math.floor(event.nativeEvent.contentOffset.y / Math.max(1, height * 0.86)) + 1;
            setCurrentPage(Math.max(1, Math.min(approx, readerProgressTotal)));
          }}
          ref={webtoonRef}
          renderItem={renderWebtoonItem}
          scrollEventThrottle={100}
          showsVerticalScrollIndicator={false}
          style={styles.webtoonList}
          contentContainerStyle={styles.webtoonContent}
        />
      ) : (
        <FlatList
          data={readerItems}
          decelerationRate="fast"
          extraData={{
            currentPage,
            failedPages,
            htmlContents,
            htmlHeights,
            loadedPages,
          }}
          getItemLayout={(_, index) => ({
            length: horizontal ? width : height,
            offset: (horizontal ? width : height) * index,
            index,
          })}
          horizontal={horizontal}
          inverted={settings.readingMode === 'single-rtl'}
          key={settings.readingMode}
          keyExtractor={item => item.key}
          onScrollToIndexFailed={info => setTimeout(() => goToPage(info.index + 1), 250)}
          onViewableItemsChanged={onViewableItemsChanged.current}
          pagingEnabled
          ref={listRef}
          renderItem={renderItem}
          removeClippedSubviews={false}
          showsHorizontalScrollIndicator={false}
          showsVerticalScrollIndicator={false}
          viewabilityConfig={viewabilityConfig}
        />
      )}

      {settings.mediaInfo && activePage ? (
        <MediaInfoOverlay
          activeLane={activeLane}
          activeReaderItem={activeReaderItem}
          archiveId={archiveId}
          currentPage={currentPage}
          failedPages={failedPages}
          getMediaState={getMediaState}
          loadedPages={loadedPages}
          page={activePage}
          pages={pages}
          settings={settings}
          sourceIndexByPage={sourceIndexByPage}
          t={t}
          viewport={`${Math.round(width)}x${Math.round(height)}`}
        />
      ) : null}

      <Animated.View
        pointerEvents={chromeVisible ? 'auto' : 'none'}
        style={[styles.topBar, {paddingTop: stableInsets.top + 8}, topBarAnimatedStyle]}>
          <View style={styles.topBarGroup}>
            <TouchableOpacity onPress={() => navigation.goBack()} style={styles.iconButton}>
              <ChevronLeft color={colors.white} size={24} />
            </TouchableOpacity>
            <TouchableOpacity onPress={() => setSidebarOpen(true)} style={styles.iconButton}>
              <List color={colors.white} size={21} />
            </TouchableOpacity>
          </View>
            <TouchableOpacity onPress={cycleMode} style={styles.modeButton}>
              <Text style={styles.modeText}>{t(modeLabelKey(settings.readingMode))}</Text>
              <Text style={styles.progress}>{displayCurrentPage} / {pages.length}</Text>
            </TouchableOpacity>
          <View style={styles.topBarGroup}>
            <TouchableOpacity onPress={handleToggleFavorite} style={styles.iconButton}>
              <Heart
                color={colors.white}
                fill={isFavorited ? colors.white : 'transparent'}
                size={20}
              />
            </TouchableOpacity>
            <TouchableOpacity onPress={() => setSettingsOpen(true)} style={styles.iconButton}>
              <SettingsIcon color={colors.white} size={21} />
            </TouchableOpacity>
          </View>
      </Animated.View>
      <Animated.View
        pointerEvents={chromeVisible ? 'auto' : 'none'}
        style={[styles.bottomBar, {paddingBottom: stableInsets.bottom + 10}, bottomBarAnimatedStyle]}>
            <View style={styles.laneShell}>
              <View style={styles.laneRow}>
                {lanes.map(lane => {
                  const isExpanded = activeLane.id === lane.id;
                  const LaneIcon = lane.kind === 'book' ? BookOpen : lane.kind === 'audio' ? Volume2 : Play;
                  return (
                    <View key={lane.id} style={[styles.laneUnit, isExpanded && styles.laneUnitExpanded]}>
                      <TouchableOpacity
                        accessibilityLabel={lane.label}
                        accessibilityRole="button"
                        onPress={() => handleSetActiveLane(lane.id)}
                        style={[styles.laneTabMini, isExpanded && styles.laneTabMiniActive]}>
                        <LaneIcon color={isExpanded ? colors.black : colors.white} size={14} />
                      </TouchableOpacity>
                      {isExpanded ? (
                        lane.kind === 'book' ? (
                          <TouchableOpacity
                            activeOpacity={0.9}
                            disabled={progressSeekLocked}
                            onPress={event => {
                              const laneWidth = Math.max(1, width - 92);
                              const x = event.nativeEvent.locationX;
                              const next = Math.round((x / laneWidth) * Math.max(1, readerProgressTotal - 1)) + 1;
                              jumpToPageFromProgress(next);
                            }}
                            style={[styles.laneContent, progressSeekLocked && styles.laneContentDisabled]}>
                            <View style={styles.progressInline}>
                              <View style={[styles.progressTrack, styles.progressTrackInline]}>
                                <View
                                  style={[
                                    styles.progressFill,
                                    {width: `${Math.max(2, (currentPage / Math.max(1, readerProgressTotal)) * 100)}%`},
                                  ]}
                                />
                              </View>
                              <Text style={styles.progressCaption} numberOfLines={1}>
                                {displayCurrentPage} / {pages.length}
                              </Text>
                            </View>
                          </TouchableOpacity>
                        ) : activeLane.kind !== 'book' && (
                          <MediaLaneControls
                            compact={width < 430}
                            hideTransportControls={width < 430}
                            page={activeLane.page}
                            state={getMediaState(activeLane.page.pageNumber)}
                            sourceIndex={sourceIndexByPage[activeLane.page.pageNumber - 1] ?? activeLane.page.defaultSourceIndex ?? 0}
                            textTrackKind={activeLane.kind === 'audio' ? 'lyrics' : 'subtitle'}
                            t={t}
                            onOpenSourceSheet={() => handleOpenSourceSheet(activeLane.page)}
                            onOpenSubtitleSheet={() => setSubtitleSheetOpen(true)}
                            onOpenVolumeSheet={() => setVolumeSheetPageId(activeLane.page.pageNumber)}
                            onSeek={seconds => seekMedia(activeLane.page, seconds, 'lane-timeline')}
                            onSeekRelative={seconds =>
                              seekMedia(
                                activeLane.page,
                                getMediaState(activeLane.page.pageNumber).currentTime + seconds,
                                seconds < 0 ? 'lane-back' : 'lane-forward',
                              )
                            }
                            onToggleMute={() =>
                              setMediaState(activeLane.page.pageNumber, {
                                muted: !getMediaState(activeLane.page.pageNumber).muted,
                              })
                            }
                            onTogglePlay={() =>
                              setMediaState(activeLane.page.pageNumber, {
                                paused: !getMediaState(activeLane.page.pageNumber).paused,
                              })
                            }
                            onVolumeChange={value => handleVolumeChange(activeLane.page.pageNumber, value)}
                          />
                        )
                      ) : null}
                    </View>
                  );
                })}
              </View>
            </View>
      </Animated.View>

      <ReaderSettingsModal
        open={settingsOpen}
        settings={settings}
        t={t}
        onClose={() => setSettingsOpen(false)}
        onPatch={patchSettings}
      />

      <ReaderSidebar
        open={sidebarOpen}
        pages={sidebarPages}
        currentPage={currentPage}
        onClose={() => setSidebarOpen(false)}
        onSelectPage={handleSidebarSelectPage}
        t={t as (key: string, params?: Record<string, string | number>) => string}
      />

      <OptionSelectSheet
        open={sourceSheetOpen}
        title={t('reader.sourceSelect')}
        options={sourceSheetPage?.sources?.length
          ? sourceSheetPage.sources.map((s, i) => ({
              value: i,
              label: s.title || `${t('reader.source', {current: i + 1, total: sourceSheetPage.sources!.length})}`,
            }))
          : []}
        selectedValues={[
          sourceSheetPage
            ? (sourceIndexByPage[sourceSheetPage.pageNumber - 1] ?? sourceSheetPage.defaultSourceIndex ?? 0)
            : 0,
        ]}
        onSelect={handleSelectSource}
        onClose={() => setSourceSheetOpen(false)}
        t={t as (key: string, params?: Record<string, string | number>) => string}
      />

      <OptionSelectSheet
        open={subtitleSheetOpen}
        title={lyricsSheetOpen ? t('reader.lyrics') : t('reader.subtitle')}
        options={lyricsSheetOpen ? lyricsOptions : subtitleOptions}
        selectedValues={lyricsSheetOpen
          ? [lyricsSelectedValue]
          : [
              ...activeSubtitleIndexes,
              ...(activeEmbeddedSubtitleTrack == null ? [] : [encodeEmbeddedSubtitleValue(activeEmbeddedSubtitleTrack)]),
              ...(activeSubtitleIndexes.length || activeEmbeddedSubtitleTrack != null ? [] : [SUBTITLE_OFF_VALUE]),
            ]}
        multiSelect={!lyricsSheetOpen}
        onSelect={lyricsSheetOpen ? handleSelectLyrics : handleSelectSubtitle}
        onClose={() => setSubtitleSheetOpen(false)}
        t={t as (key: string, params?: Record<string, string | number>) => string}
      />

      <Modal
        animationType="fade"
        onRequestClose={() => setVolumeSheetPageId(null)}
        statusBarTranslucent
        transparent
        visible={Boolean(volumeSheetPage && volumeSheetState)}>
        <ModalBackdrop style={[styles.modalBackdrop, styles.volumePopoverBackdrop]}>
          <TouchableOpacity activeOpacity={1} onPress={() => setVolumeSheetPageId(null)} style={StyleSheet.absoluteFill} />
            {volumeSheetPage && volumeSheetState ? (
              <VolumeStrip
              bottomOffset={stableInsets.bottom + 72}
              pageNumber={volumeSheetPage.pageNumber}
              state={volumeSheetState}
              t={t}
              onClose={() => setVolumeSheetPageId(null)}
              onToggleMute={() =>
                setMediaState(volumeSheetPage.pageNumber, {
                  muted: !volumeSheetState.muted,
                })
              }
              onVolumeChange={handleVolumeChange}
            />
          ) : null}
        </ModalBackdrop>
      </Modal>
    </View>
  );
}

function ErrorOverlay({title, message}: {title: string; message: string}) {
  return (
    <View style={styles.imageError}>
      <Text style={styles.imageErrorTitle}>{title}</Text>
      <Text style={styles.imageErrorText}>{message}</Text>
    </View>
  );
}

function ReaderCollectionEndPage({
  finishedPageCount,
  nextArchiveId,
  nextTitle,
  nextMode,
  t,
  onOpenNext,
}: {
  finishedPageCount: number;
  nextArchiveId?: string;
  nextTitle?: string;
  nextMode?: 'tankoubon' | 'archive_related';
  t: ReturnType<typeof useI18n>['t'];
  onOpenNext: () => void;
}) {
  return (
    <View style={styles.collectionEnd}>
      <Text style={styles.collectionEndTitle}>{t('reader.finishedReading')}</Text>
      <Text style={styles.collectionEndText}>
        {t('reader.finishedPageCount', {count: finishedPageCount})}
      </Text>
      <View style={styles.collectionEndDivider} />
      <Text style={styles.collectionEndLabel}>
        {nextMode === 'archive_related' ? t('reader.relatedNextLabel') : t('reader.nextChapterLabel')}
      </Text>
      <Text style={styles.collectionEndNext} numberOfLines={2}>
        {nextTitle || nextArchiveId || t('reader.noNextChapter')}
      </Text>
      {nextArchiveId ? (
        <TouchableOpacity accessibilityRole="button" onPress={onOpenNext} style={styles.collectionEndButton}>
          <Text style={styles.collectionEndButtonText}>{t('reader.openNext')}</Text>
        </TouchableOpacity>
      ) : null}
    </View>
  );
}

function MediaInfoOverlay({
  activeLane,
  activeReaderItem,
  archiveId,
  currentPage,
  failedPages,
  getMediaState,
  loadedPages,
  page,
  pages,
  settings,
  sourceIndexByPage,
  t,
  viewport,
}: {
  activeLane: ReaderLane;
  activeReaderItem?: ReaderItem;
  archiveId: string;
  currentPage: number;
  failedPages: Record<number, string>;
  getMediaState: (pageNumber: number) => MediaPlaybackState;
  loadedPages: Record<number, boolean>;
  page: ReaderPage;
  pages: ReaderPage[];
  settings: ReaderSettings;
  sourceIndexByPage: Record<number, number>;
  t: ReturnType<typeof useI18n>['t'];
  viewport: string;
}) {
  const mediaState =
    activeLane.kind === 'book' ? null : getMediaState(activeLane.page.pageNumber);
  const spreadPages = activeReaderItem?.pages?.length
    ? activeReaderItem.pages.map(item => item.pageNumber).join(',')
    : String(currentPage);
  const sourceIndex = sourceIndexByPage[page.pageNumber - 1] ?? page.defaultSourceIndex ?? 0;
  const sourceCount = page.sources?.length || 0;
  const fileName = page.resolvedPath || page.path || page.uri || page.id;
  const loadState = failedPages[page.pageNumber]
    ? 'error'
    : loadedPages[page.pageNumber]
      ? 'loaded'
      : 'loading';
  const lines = [
    `P ${Math.min(currentPage, pages.length)}/${pages.length}  spread ${spreadPages}`,
    `mode ${t(modeLabelKey(settings.readingMode))}${settings.doublePage ? '  double' : ''}${settings.splitCover ? '  splitCover' : ''}`,
    `ui toolbar=${settings.autoHide ? 'auto' : 'manual'}  vp=${viewport}`,
    `cfg tap=${settings.tapTurnPage ? 'on' : 'off'} auto=${settings.autoPlay ? `${settings.autoPlayInterval}s` : 'off'} hide=${settings.autoHide ? 'on' : 'off'} zoom=${settings.doubleTapZoom ? 'on' : 'off'}`,
    `archive ${archiveId}`,
    `page ${page.effectiveType}  state=${loadState}  source=${sourceCount ? `${sourceIndex + 1}/${sourceCount}` : '1/1'}`,
    `file ${fileName}`,
    page.vlcUri ? `proxy ${page.vlcUri}` : page.uri ? `uri ${page.uri}` : '',
    mediaState
      ? `${activeLane.label}  ${formatMediaTime(mediaState.currentTime)} / ${formatMediaTime(mediaState.duration)}  pos=${Math.round(mediaState.position * 100)}%  vol=${Math.round(mediaState.volume * 100)}  ${mediaState.paused ? t('reader.pause') : t('reader.play')}`
      : '',
    failedPages[page.pageNumber] ? `error ${failedPages[page.pageNumber]}` : '',
  ].filter(Boolean);

  return (
    <View pointerEvents="none" style={styles.mediaInfoOverlay}>
      {lines.map(line => (
        <Text key={line} numberOfLines={1} style={styles.mediaInfoText}>
          {line}
        </Text>
      ))}
    </View>
  );
}

function ReaderTapSurface({
  children,
  onDoubleTap,
  onTap,
  style,
}: {
  children: React.ReactNode;
  onDoubleTap?: () => void;
  onTap: (x: number, y: number) => void;
  style?: StyleProp<ViewStyle>;
}) {
  const singleTap = Gesture.Tap()
    .maxDuration(240)
    .onEnd(event => {
      runOnJS(onTap)(event.x, event.y);
    });
  const tapGesture = onDoubleTap
    ? Gesture.Exclusive(
        Gesture.Tap()
          .numberOfTaps(2)
          .maxDelay(260)
          .onEnd(() => {
            runOnJS(onDoubleTap)();
          }),
        singleTap,
      )
    : singleTap;

  return (
    <GestureDetector gesture={tapGesture}>
      <Animated.View style={style}>{children}</Animated.View>
    </GestureDetector>
  );
}

function MediaLaneControls({
  compact,
  hideTransportControls,
  page,
  state,
  sourceIndex,
  textTrackKind,
  t,
  onOpenSourceSheet,
  onOpenSubtitleSheet,
  onOpenVolumeSheet,
  onSeek,
  onSeekRelative,
  onToggleMute,
  onTogglePlay,
  onVolumeChange,
}: {
  compact?: boolean;
  hideTransportControls?: boolean;
  page: ReaderPage;
  state: MediaPlaybackState;
  sourceIndex: number;
  textTrackKind: 'subtitle' | 'lyrics';
  t: ReturnType<typeof useI18n>['t'];
  onOpenSourceSheet: () => void;
  onOpenSubtitleSheet: () => void;
  onOpenVolumeSheet: () => void;
  onSeek: (seconds: number) => void;
  onSeekRelative: (seconds: number) => void;
  onToggleMute: () => void;
  onTogglePlay: () => void;
  onVolumeChange: (value: number) => void;
}) {
  const sourceCount = page.sources?.length || 0;
  const duration = Math.max(0, state.duration);
  const position = duration > 0 ? state.currentTime / duration : state.position;
  const [timelineWidth, setTimelineWidth] = useState(1);
  const [volBarWidth, setVolBarWidth] = useState(1);
  const textTrackLabel = textTrackKind === 'lyrics' ? t('reader.lyrics') : t('reader.subtitle');
  return (
    <View style={[styles.mediaLane, compact && styles.mediaLaneCompact]}>
      {!hideTransportControls ? (
        <>
          <TouchableOpacity
            accessibilityLabel={t('reader.seekBack')}
            accessibilityRole="button"
            onPress={() => onSeekRelative(-5)}
            style={styles.mediaIconButton}>
            <Rewind color={colors.white} size={16} />
          </TouchableOpacity>
          <TouchableOpacity
            accessibilityLabel={state.paused ? t('reader.play') : t('reader.pause')}
            accessibilityRole="button"
            onPress={onTogglePlay}
            style={styles.mediaIconButton}>
            {state.paused ? (
              <Play color={colors.white} size={16} />
            ) : (
              <Pause color={colors.white} size={16} />
            )}
          </TouchableOpacity>
          <TouchableOpacity
            accessibilityLabel={t('reader.seekForward')}
            accessibilityRole="button"
            onPress={() => onSeekRelative(5)}
            style={styles.mediaIconButton}>
            <FastForward color={colors.white} size={16} />
          </TouchableOpacity>
        </>
      ) : null}
      <TouchableOpacity
        activeOpacity={0.9}
        onLayout={event => setTimelineWidth(Math.max(1, event.nativeEvent.layout.width))}
        onPress={event => {
          onSeek((event.nativeEvent.locationX / timelineWidth) * Math.max(1, duration));
        }}
        style={styles.mediaTimeline}>
        <View style={styles.progressInline}>
          <View style={[styles.progressTrack, styles.progressTrackInline]}>
            <View
              style={[
                styles.progressBuffered,
                {width: `${Math.max(0, Math.min(100, (state.buffered || 0) * 100))}%`},
              ]}
            />
            <View
              style={[
                styles.progressFill,
                {width: `${Math.max(2, Math.max(0, Math.min(1, position)) * 100)}%`},
              ]}
            />
          </View>
          <Text style={styles.mediaTime} numberOfLines={1}>
            {formatMediaTime(state.currentTime)}/{formatMediaTime(duration)}
          </Text>
        </View>
      </TouchableOpacity>
      <TouchableOpacity
        accessibilityLabel={state.muted ? t('reader.unmute') : t('reader.mute')}
        accessibilityRole="button"
        onPress={compact ? onOpenVolumeSheet : onToggleMute}
        style={styles.mediaIconButton}>
        {state.muted ? (
          <VolumeX color={colors.white} size={16} />
        ) : (
          <Volume2 color={colors.white} size={16} />
        )}
      </TouchableOpacity>
      {!compact ? (
        <TouchableOpacity
          activeOpacity={0.9}
          onLayout={event => setVolBarWidth(Math.max(1, event.nativeEvent.layout.width))}
          onPress={event => {
            const ratio = Math.max(0, Math.min(1, event.nativeEvent.locationX / volBarWidth));
            onVolumeChange(ratio);
          }}
          style={styles.volumeSlider}>
          <View style={styles.progressTrack}>
            <View
              style={[
                styles.progressFill,
                {width: `${state.muted ? 0 : Math.max(2, Math.round(state.volume * 100))}%`},
              ]}
            />
          </View>
        </TouchableOpacity>
      ) : null}
      {sourceCount > 1 ? (
        <TouchableOpacity
          accessibilityLabel={t('reader.source', {current: sourceIndex + 1, total: sourceCount})}
          accessibilityRole="button"
          onPress={onOpenSourceSheet}
          style={styles.mediaIconButton}>
          <Layers color={colors.white} size={16} />
        </TouchableOpacity>
      ) : null}
      <TouchableOpacity
        accessibilityLabel={textTrackLabel}
        accessibilityRole="button"
        onPress={onOpenSubtitleSheet}
        style={styles.mediaIconButton}>
        {textTrackKind === 'lyrics' ? (
          <Music color={colors.white} size={16} />
        ) : (
          <Captions color={colors.white} size={16} />
        )}
      </TouchableOpacity>
    </View>
  );
}

function AudioLyricsPanel({
  activeLyricIndex,
  audioLandscape,
  audioSubtitleAttachment,
  audioSubtitleLines,
  audioSubtitleText,
  lyricsAttachment,
  lyricsText,
  plainLyricLines,
  t,
  timedLyrics,
  onLyricTouchTrace,
  onSeekLyric,
}: {
  activeLyricIndex: number;
  audioLandscape: boolean;
  audioSubtitleAttachment?: MetadataPageAttachment;
  audioSubtitleLines: string[];
  audioSubtitleText: string;
  lyricsAttachment?: MetadataPageAttachment;
  lyricsText: string;
  plainLyricLines: string[];
  t: ReturnType<typeof useI18n>['t'];
  timedLyrics: TimedLyricLine[];
  onLyricTouchTrace?: (trace: AudioLyricTouchTrace) => void;
  onSeekLyric: (seconds: number, trace?: AudioLyricTouchTrace) => void;
}) {
  const scrollRef = useRef<ScrollView | null>(null);
  const lineYByIndex = useRef<Record<number, number>>({});
  const userScrollingRef = useRef(false);
  const suppressPressUntilRef = useRef(0);
  const releaseUserScrollTimer = useRef<ReturnType<typeof setTimeout> | null>(null);
  const [viewportHeight, setViewportHeight] = useState(1);

  const releaseUserScrollSoon = useCallback(() => {
    if (releaseUserScrollTimer.current) {
      clearTimeout(releaseUserScrollTimer.current);
    }
    releaseUserScrollTimer.current = setTimeout(() => {
      userScrollingRef.current = false;
    }, 360);
  }, []);

  useEffect(() => {
    if (userScrollingRef.current) return;
    if (activeLyricIndex < 0 || !timedLyrics.length) return;
    const y = lineYByIndex.current[activeLyricIndex];
    if (typeof y !== 'number') return;
    scrollRef.current?.scrollTo({
      animated: true,
      y: Math.max(0, y - viewportHeight * 0.42),
    });
  }, [activeLyricIndex, timedLyrics.length, viewportHeight]);

  useEffect(
    () => () => {
      if (releaseUserScrollTimer.current) {
        clearTimeout(releaseUserScrollTimer.current);
      }
    },
    [],
  );

  return (
    <View style={[styles.audioLyricsPanel, audioLandscape && styles.audioLyricsPanelLandscape]}>
      <ScrollView
        contentContainerStyle={[
          styles.audioLyricsContent,
          audioLandscape && styles.audioLyricsContentLandscape,
        ]}
        fadingEdgeLength={28}
        onMomentumScrollEnd={releaseUserScrollSoon}
        onScrollBeginDrag={() => {
          userScrollingRef.current = true;
          suppressPressUntilRef.current = Date.now() + 650;
          if (releaseUserScrollTimer.current) {
            clearTimeout(releaseUserScrollTimer.current);
            releaseUserScrollTimer.current = null;
          }
        }}
        onScrollEndDrag={releaseUserScrollSoon}
        onLayout={event => setViewportHeight(Math.max(1, event.nativeEvent.layout.height))}
        ref={scrollRef}
        showsVerticalScrollIndicator={false}
        style={styles.audioLyricsScroll}>
        {!lyricsAttachment ? (
          <Text style={styles.audioLyricsEmpty}>{t('reader.audioLyricsEmpty')}</Text>
        ) : lyricsText ? (
          timedLyrics.length ? (
            timedLyrics.map((line, index) => {
              const active = index === activeLyricIndex;
              const buildTrace = (
                phase: AudioLyricTouchTrace['phase'],
                nativeTimestamp?: number,
              ): AudioLyricTouchTrace => {
                const now = Date.now();
                const nextLineTime = timedLyrics[index + 1]?.time;
                const seekNudge = typeof nextLineTime === 'number' && nextLineTime - line.time > 0.18 ? 0.08 : 0;
                return {
                  phase,
                  lineIndex: index,
                  lineTime: line.time,
                  activeLyricIndex,
                  textPreview: line.text.slice(0, 80),
                  now,
                  suppressUntil: suppressPressUntilRef.current,
                  userScrolling: userScrollingRef.current,
                  seekTime: line.time + seekNudge,
                  nextLineTime,
                  nativeTimestamp,
                };
              };
              return (
                <TouchableOpacity
                  accessibilityLabel={line.text || formatMediaTime(line.time)}
                  accessibilityRole="button"
                  activeOpacity={0.74}
                  key={line.key}
                  onLayout={event => {
                    lineYByIndex.current[index] = event.nativeEvent.layout.y;
                  }}
                  onPress={event => {
                    const trace = buildTrace(
                      Date.now() < suppressPressUntilRef.current ? 'pressSuppressed' : 'press',
                      event.nativeEvent.timestamp,
                    );
                    onLyricTouchTrace?.(trace);
                    if (trace.phase === 'pressSuppressed') return;
                    onSeekLyric(trace.seekTime ?? line.time, trace);
                  }}
                  onPressIn={event => {
                    onLyricTouchTrace?.(buildTrace('pressIn', event.nativeEvent.timestamp));
                  }}
                  onPressOut={event => {
                    onLyricTouchTrace?.(buildTrace('pressOut', event.nativeEvent.timestamp));
                  }}
                  style={styles.audioLyricTouchable}>
                  <Text
                    style={[
                      styles.audioLyricLine,
                      audioLandscape && styles.audioLyricLineLandscape,
                      active && styles.audioLyricLineActive,
                      audioLandscape && active && styles.audioLyricLineActiveLandscape,
                    ]}>
                    {line.text || '...'}
                  </Text>
                </TouchableOpacity>
              );
            })
          ) : (
            plainLyricLines.map((line, index) => (
              <Text
                key={`${index}-${line}`}
                style={[styles.audioLyricLine, audioLandscape && styles.audioLyricLineLandscape]}>
                {line}
              </Text>
            ))
          )
        ) : (
          <Text style={styles.audioLyricsEmpty}>{t('reader.audioLyricsLoading')}</Text>
        )}
        {audioSubtitleAttachment ? (
          <View style={styles.audioSubtitleBlock}>
            {audioSubtitleText ? (
              audioSubtitleLines.length ? (
                audioSubtitleLines.map((line, index) => (
                  <Text key={`${index}-${line}`} style={styles.audioSubtitleLine}>
                    {line}
                  </Text>
                ))
              ) : (
                <Text style={styles.audioLyricsEmpty}>{t('reader.audioSubtitleEmpty')}</Text>
              )
            ) : (
              <Text style={styles.audioLyricsEmpty}>{t('reader.audioSubtitleLoading')}</Text>
            )}
          </View>
        ) : null}
      </ScrollView>
    </View>
  );
}

function VolumeStrip({
  bottomOffset,
  pageNumber,
  state,
  t,
  onClose,
  onToggleMute,
  onVolumeChange,
}: {
  bottomOffset: number;
  pageNumber: number;
  state: MediaPlaybackState;
  t: ReturnType<typeof useI18n>['t'];
  onClose: () => void;
  onToggleMute: () => void;
  onVolumeChange: (pageNumber: number, value: number) => void;
}) {
  const [barWidth, setBarWidth] = useState(1);
  const volume = state.muted ? 0 : Math.max(0, Math.min(1, state.volume));
  return (
    <View style={[styles.volumePopover, {bottom: bottomOffset}]}>
      <TouchableOpacity
        accessibilityLabel={state.muted ? t('reader.unmute') : t('reader.mute')}
        accessibilityRole="button"
        onPress={onToggleMute}
        style={styles.volumePopoverIconButton}>
        {state.muted ? (
          <VolumeX color={colors.white} size={17} />
        ) : (
          <Volume2 color={colors.white} size={17} />
        )}
      </TouchableOpacity>
      <TouchableOpacity
        activeOpacity={0.9}
        onLayout={event => setBarWidth(Math.max(1, event.nativeEvent.layout.width))}
        onPress={event => {
          onVolumeChange(pageNumber, Math.max(0, Math.min(1, event.nativeEvent.locationX / barWidth)));
        }}
        style={styles.volumePopoverSlider}>
        <View style={styles.progressTrack}>
          <View style={[styles.progressFill, {width: `${Math.max(2, Math.round(volume * 100))}%`}]} />
        </View>
      </TouchableOpacity>
      <Text style={styles.volumePopoverValue}>{Math.round(volume * 100)}%</Text>
      <TouchableOpacity
        accessibilityLabel={t('common.close')}
        accessibilityRole="button"
        onPress={onClose}
        style={styles.volumePopoverClose}>
        <Text style={styles.volumePopoverCloseText}>x</Text>
      </TouchableOpacity>
    </View>
  );
}

function ReaderSettingsModal({
  open,
  settings,
  t,
  onClose,
  onPatch,
}: {
  open: boolean;
  settings: ReaderSettings;
  t: ReturnType<typeof useI18n>['t'];
  onClose: () => void;
  onPatch: (patch: Partial<ReaderSettings>) => void;
}) {
  return (
    <Modal animationType="slide" onRequestClose={onClose} statusBarTranslucent transparent visible={open}>
      <ModalBackdrop style={styles.modalBackdrop}>
        <View style={styles.sheet}>
          <View style={styles.sheetHandle} />
          <Text style={styles.sheetTitle}>{t('reader.settings')}</Text>
          <View style={styles.modeGrid}>
            {READING_MODES.map(mode => (
              <TouchableOpacity
                key={mode}
                onPress={() => onPatch({readingMode: mode})}
                style={[styles.modeChoice, settings.readingMode === mode && styles.modeChoiceActive]}>
                <Text style={[styles.modeChoiceText, settings.readingMode === mode && styles.modeChoiceTextActive]}>
                  {t(modeLabelKey(mode))}
                </Text>
              </TouchableOpacity>
            ))}
          </View>
          <ScrollView style={styles.settingList}>
            <ReaderSettingToggle
              label={t('reader.doublePage')}
              active={settings.doublePage}
              disabled={settings.readingMode === 'webtoon'}
              t={t}
              onPress={() => onPatch({doublePage: !settings.doublePage})}
            />
            <ReaderSettingToggle
              label={t('reader.splitCover')}
              active={settings.splitCover}
              disabled={!settings.doublePage || settings.readingMode === 'webtoon'}
              t={t}
              onPress={() => onPatch({splitCover: !settings.splitCover})}
            />
            <ReaderSettingToggle
              label={t('reader.autoPlay')}
              active={settings.autoPlay}
              t={t}
              onPress={() => onPatch({autoPlay: !settings.autoPlay})}
            />
            <TouchableOpacity
              onPress={() =>
                onPatch({autoPlayInterval: settings.autoPlayInterval >= 10 ? 1 : settings.autoPlayInterval + 1})
              }
              style={styles.settingRow}>
              <Text style={styles.settingLabel}>{t('reader.pageInterval')}</Text>
              <Text style={styles.settingState}>{settings.autoPlayInterval}s</Text>
            </TouchableOpacity>
            <ReaderSettingToggle
              label={t('reader.tapTurnPage')}
              active={settings.tapTurnPage}
              t={t}
              onPress={() => onPatch({tapTurnPage: !settings.tapTurnPage})}
            />
            <ReaderSettingToggle
              label={t('reader.autoHide')}
              active={settings.autoHide}
              t={t}
              onPress={() => onPatch({autoHide: !settings.autoHide})}
            />
            <ReaderSettingToggle
              label={t('reader.mediaInfo')}
              active={settings.mediaInfo}
              t={t}
              onPress={() => onPatch({mediaInfo: !settings.mediaInfo})}
            />
            <ReaderSettingToggle
              label={t('reader.longPage')}
              active={settings.longPage}
              t={t}
              onPress={() => onPatch({longPage: !settings.longPage})}
            />
            <ReaderSettingToggle
              label={t('reader.doubleTapZoom')}
              active={settings.doubleTapZoom}
              t={t}
              onPress={() => onPatch({doubleTapZoom: !settings.doubleTapZoom})}
            />
            <ReaderSettingToggle
              label={t('reader.seamlessNext')}
              active={settings.seamlessNext}
              t={t}
              onPress={() => onPatch({seamlessNext: !settings.seamlessNext})}
            />
          </ScrollView>
          <TouchableOpacity onPress={onClose} style={styles.closeButton}>
            <Text style={styles.closeButtonText}>{t('common.close')}</Text>
          </TouchableOpacity>
        </View>
      </ModalBackdrop>
    </Modal>
  );
}

function ReaderSettingToggle({
  label,
  active,
  disabled,
  t,
  onPress,
}: {
  label: string;
  active: boolean;
  disabled?: boolean;
  t: ReturnType<typeof useI18n>['t'];
  onPress: () => void;
}) {
  return (
    <TouchableOpacity
      disabled={disabled}
      onPress={onPress}
      style={[
        styles.settingRow,
        active && styles.settingRowActive,
        disabled && styles.settingRowDisabled,
      ]}>
      <Text style={[styles.settingLabel, active && styles.settingLabelActive]}>
        {label}
      </Text>
      <Text style={[styles.settingState, active && styles.settingLabelActive]}>
        {active ? t('reader.on') : t('reader.off')}
      </Text>
    </TouchableOpacity>
  );
}

function AudioCoverArtwork({
  paused,
  size,
  source,
}: {
  paused: boolean;
  size: number;
  source?: ImageSourcePropType;
}) {
  const rotation = useSharedValue(0);

  useEffect(() => {
    if (paused) {
      cancelAnimation(rotation);
      return;
    }
    rotation.value = withRepeat(
      withTiming(360, {duration: 18000, easing: Easing.linear}),
      -1,
      false,
    );
    return () => cancelAnimation(rotation);
  }, [paused, rotation]);

  const coverAnimatedStyle = useAnimatedStyle(() => ({
    transform: [{rotate: `${rotation.value}deg`}],
  }));

  return (
    <View style={[styles.audioCoverFrame, {height: size, width: size}]}>
      <Animated.View style={[styles.audioCoverShell, coverAnimatedStyle]}>
        {source ? (
          <Image resizeMode="cover" source={source} style={styles.audioCover} />
        ) : (
          <View style={styles.audioCoverFallback}>
            <Volume2 color="rgba(255,255,255,0.72)" size={Math.max(38, Math.round(size * 0.22))} />
          </View>
        )}
        <View style={styles.audioCoverVinylShade} />
        <View style={styles.audioCoverCenterDot} />
      </Animated.View>
    </View>
  );
}

const styles = StyleSheet.create({
  screen: {
    backgroundColor: colors.black,
    flex: 1,
  },
  page: {
    alignItems: 'center',
    backgroundColor: colors.black,
    justifyContent: 'center',
  },
  spread: {
    alignItems: 'center',
    flexDirection: 'row',
    height: '100%',
    justifyContent: 'center',
    width: '100%',
  },
  mediaPage: {
    alignItems: 'center',
    backgroundColor: colors.black,
    justifyContent: 'center',
  },
  audioMediaPage: {
    backgroundColor: colors.black,
    overflow: 'hidden',
    position: 'relative',
  },
  pageImage: {
    height: '100%',
    width: '100%',
  },
  zoomedMedia: {
    transform: [{scale: 2}],
  },
  webtoonContent: {
    backgroundColor: colors.black,
    paddingBottom: 24,
  },
  webtoonList: {
    backgroundColor: colors.black,
    flex: 1,
  },
  webtoonItem: {
    alignItems: 'center',
    backgroundColor: colors.black,
    width: '100%',
  },
  webtoonPage: {
    alignItems: 'center',
    backgroundColor: colors.black,
    justifyContent: 'center',
  },
  webtoonImage: {
    aspectRatio: 0.72,
    height: undefined,
    width: '100%',
  },
  webView: {
    backgroundColor: colors.white,
    height: '100%',
    width: '100%',
  },
  webViewContainer: {
    backgroundColor: colors.white,
  },
  audioStage: {
    height: 1,
    opacity: 0,
    position: 'absolute',
    width: 1,
  },
  audioBackdrop: {
    backgroundColor: '#080a0e',
    bottom: 0,
    left: 0,
    overflow: 'hidden',
    position: 'absolute',
    right: 0,
    top: 0,
  },
  audioBackdropImage: {
    bottom: -34,
    left: -34,
    opacity: 0.92,
    position: 'absolute',
    right: -34,
    top: -34,
  },
  audioBackdropGradient: {
    bottom: 0,
    left: 0,
    position: 'absolute',
    right: 0,
    top: 0,
  },
  audioScene: {
    bottom: 0,
    left: 0,
    paddingHorizontal: spacing.lg,
    position: 'absolute',
    right: 0,
    top: 0,
    zIndex: 1,
  },
  audioSceneInner: {
    flex: 1,
    minHeight: 0,
    width: '100%',
  },
  audioSceneInnerWide: {
    alignItems: 'center',
    flexDirection: 'row',
    gap: spacing.xl,
  },
  audioSceneInnerLandscape: {
    alignItems: 'stretch',
    flexDirection: 'row',
    gap: spacing.lg,
    justifyContent: 'center',
  },
  audioSceneInnerCompact: {
    alignItems: 'center',
    justifyContent: 'space-between',
  },
  audioLandscapeLeftPane: {
    alignItems: 'center',
    flexBasis: 270,
    flexGrow: 0,
    flexShrink: 1,
    justifyContent: 'center',
    minWidth: 220,
  },
  audioHero: {
    minWidth: 0,
  },
  audioHeroWide: {
    alignItems: 'center',
    flex: 0.9,
  },
  audioHeroCompact: {
    alignItems: 'center',
    flexShrink: 0,
    width: '100%',
  },
  audioHeroLandscape: {
    alignItems: 'center',
    flexShrink: 0,
    width: '100%',
  },
  audioCoverFrame: {
    backgroundColor: 'rgba(255,255,255,0.08)',
    borderRadius: 999,
    elevation: 16,
    shadowColor: '#000',
    shadowOffset: {height: 16, width: 0},
    shadowOpacity: 0.34,
    shadowRadius: 26,
  },
  audioCoverShell: {
    backgroundColor: 'rgba(8,10,14,0.92)',
    borderColor: 'rgba(255,255,255,0.24)',
    borderRadius: 999,
    borderWidth: 1,
    height: '100%',
    overflow: 'hidden',
    padding: 7,
    width: '100%',
  },
  audioCover: {
    borderRadius: 999,
    height: '100%',
    width: '100%',
  },
  audioCoverFallback: {
    alignItems: 'center',
    backgroundColor: 'rgba(255,255,255,0.1)',
    borderRadius: 999,
    height: '100%',
    justifyContent: 'center',
    width: '100%',
  },
  audioCoverVinylShade: {
    borderColor: 'rgba(255,255,255,0.16)',
    borderRadius: 999,
    borderWidth: 18,
    bottom: 14,
    left: 14,
    opacity: 0.5,
    position: 'absolute',
    right: 14,
    top: 14,
  },
  audioCoverCenterDot: {
    backgroundColor: 'rgba(250,250,250,0.92)',
    borderColor: 'rgba(0,0,0,0.54)',
    borderRadius: 15,
    borderWidth: 6,
    height: 30,
    left: '50%',
    marginLeft: -15,
    marginTop: -15,
    position: 'absolute',
    top: '50%',
    width: 30,
  },
  audioTextBlock: {
    marginTop: spacing.lg,
    maxWidth: 420,
    minWidth: 0,
    width: '100%',
  },
  audioTextBlockCompact: {
    marginBottom: spacing.md,
    marginTop: spacing.md,
  },
  audioTextBlockLandscape: {
    marginTop: spacing.sm,
    maxWidth: 270,
  },
  audioTitle: {
    color: colors.white,
    fontSize: 24,
    fontWeight: '900',
    lineHeight: 31,
    textAlign: 'center',
  },
  audioTitleCompact: {
    fontSize: 20,
    lineHeight: 26,
  },
  audioTitleLandscape: {
    fontSize: 16,
    lineHeight: 20,
  },
  audioDescription: {
    color: 'rgba(255,255,255,0.74)',
    fontSize: 13,
    lineHeight: 20,
    marginTop: spacing.sm,
    textAlign: 'center',
  },
  audioDescriptionLandscape: {
    fontSize: 11,
    lineHeight: 15,
    marginTop: 4,
  },
  audioPathText: {
    color: 'rgba(255,255,255,0.42)',
    fontSize: 11,
    marginTop: spacing.sm,
    textAlign: 'center',
  },
  audioPathTextLandscape: {
    marginTop: 4,
  },
  audioLyricsPanel: {
    flex: 1,
    justifyContent: 'center',
    minHeight: 0,
    width: '100%',
  },
  audioLyricsPanelLandscape: {
    alignSelf: 'stretch',
    flexBasis: 0,
    flexGrow: 1,
    maxWidth: 620,
  },
  audioLyricsScroll: {
    flex: 1,
  },
  audioLyricsContent: {
    justifyContent: 'center',
    minHeight: '100%',
    paddingBottom: spacing.md,
    paddingTop: spacing.md,
  },
  audioLyricsContentLandscape: {
    alignItems: 'stretch',
    paddingHorizontal: spacing.lg,
  },
  audioLyricLine: {
    color: 'rgba(255,255,255,0.56)',
    fontSize: 16,
    fontWeight: '600',
    lineHeight: 25,
    paddingVertical: 5,
    textAlign: 'center',
  },
  audioLyricTouchable: {
    width: '100%',
  },
  audioLyricLineLandscape: {
    color: 'rgba(255,255,255,0.78)',
    fontSize: 14,
    lineHeight: 22,
    paddingVertical: 3,
    textAlign: 'left',
    textShadowColor: 'rgba(0,0,0,0.45)',
    textShadowOffset: {height: 1, width: 0},
    textShadowRadius: 3,
  },
  audioLyricLineActive: {
    color: colors.white,
    fontSize: 20,
    fontWeight: '900',
    lineHeight: 29,
  },
  audioLyricLineActiveLandscape: {
    fontSize: 17,
    lineHeight: 24,
  },
  audioLyricsEmpty: {
    color: 'rgba(255,255,255,0.58)',
    fontSize: 14,
    lineHeight: 21,
    paddingVertical: spacing.lg,
    textAlign: 'center',
  },
  audioSubtitleBlock: {
    borderColor: 'rgba(255,255,255,0.14)',
    borderTopWidth: StyleSheet.hairlineWidth,
    marginTop: spacing.lg,
    paddingTop: spacing.md,
  },
  audioSubtitleLine: {
    color: 'rgba(255,255,255,0.58)',
    fontSize: 13,
    lineHeight: 20,
    paddingVertical: 2,
    textAlign: 'center',
  },
  audioPlayerDock: {
    flexShrink: 0,
    paddingTop: spacing.sm,
    width: '100%',
  },
  audioPlayerDockLandscape: {
    maxWidth: 270,
    paddingTop: spacing.sm,
  },
  audioProgressRow: {
    alignItems: 'center',
    flexDirection: 'row',
    gap: spacing.sm,
  },
  audioTimeText: {
    color: 'rgba(255,255,255,0.62)',
    fontSize: 11,
    fontWeight: '700',
    minWidth: 38,
    textAlign: 'center',
  },
  audioProgressTrack: {
    backgroundColor: 'rgba(255,255,255,0.2)',
    borderRadius: 3,
    flex: 1,
    height: 6,
    overflow: 'hidden',
  },
  audioProgressBuffered: {
    backgroundColor: 'rgba(255,255,255,0.22)',
    bottom: 0,
    left: 0,
    position: 'absolute',
    top: 0,
  },
  audioProgressFill: {
    backgroundColor: colors.white,
    bottom: 0,
    left: 0,
    position: 'absolute',
    top: 0,
  },
  audioTransportRow: {
    alignItems: 'center',
    flexDirection: 'row',
    gap: spacing.xl,
    justifyContent: 'center',
    paddingTop: spacing.md,
  },
  audioTransportRowLandscape: {
    gap: spacing.md,
    paddingTop: spacing.sm,
  },
  audioTransportSideButton: {
    alignItems: 'center',
    backgroundColor: 'rgba(255,255,255,0.12)',
    borderColor: 'rgba(255,255,255,0.18)',
    borderRadius: 24,
    borderWidth: StyleSheet.hairlineWidth,
    height: 48,
    justifyContent: 'center',
    width: 48,
  },
  audioTransportSideButtonLandscape: {
    borderRadius: 21,
    height: 42,
    width: 42,
  },
  audioTransportPlayButton: {
    alignItems: 'center',
    backgroundColor: colors.white,
    borderRadius: 34,
    height: 68,
    justifyContent: 'center',
    width: 68,
  },
  audioTransportPlayButtonLandscape: {
    borderRadius: 28,
    height: 56,
    width: 56,
  },
  audioTimedSubtitleOverlay: {
    alignItems: 'center',
    bottom: 108,
    gap: 6,
    left: spacing.lg,
    position: 'absolute',
    right: spacing.lg,
    zIndex: 2,
  },
  mediaCenterButton: {
    alignItems: 'center',
    backgroundColor: 'rgba(0,0,0,0.46)',
    borderColor: 'rgba(255,255,255,0.18)',
    borderRadius: 32,
    borderWidth: StyleSheet.hairlineWidth,
    height: 64,
    justifyContent: 'center',
    width: 64,
    zIndex: 2,
  },
  mediaOverlayControls: {
    alignItems: 'center',
    flexDirection: 'row',
    gap: 18,
    justifyContent: 'center',
    left: 0,
    position: 'absolute',
    right: 0,
    top: '44%',
    zIndex: 2,
  },
  mediaOverlayControlsHidden: {
    opacity: 0,
  },
  mediaSeekButton: {
    alignItems: 'center',
    backgroundColor: 'rgba(0,0,0,0.42)',
    borderColor: 'rgba(255,255,255,0.16)',
    borderRadius: 24,
    borderWidth: StyleSheet.hairlineWidth,
    height: 48,
    justifyContent: 'center',
    width: 48,
  },
  subtitleOverlay: {
    alignItems: 'center',
    bottom: 28,
    gap: 6,
    left: spacing.lg,
    position: 'absolute',
    right: spacing.lg,
    zIndex: 2,
  },
  subtitleText: {
    backgroundColor: 'rgba(0,0,0,0.68)',
    borderRadius: 8,
    color: colors.white,
    fontSize: 15,
    fontWeight: '700',
    lineHeight: 22,
    overflow: 'hidden',
    paddingHorizontal: 12,
    paddingVertical: 7,
    textAlign: 'center',
  },
  loadingText: {
    color: colors.white,
    position: 'absolute',
    zIndex: 1,
  },
  imageError: {
    backgroundColor: 'rgba(0,0,0,0.72)',
    borderColor: 'rgba(255,255,255,0.24)',
    borderRadius: 8,
    borderWidth: StyleSheet.hairlineWidth,
    left: 20,
    padding: 14,
    position: 'absolute',
    right: 20,
  },
  imageErrorTitle: {
    color: colors.white,
    fontSize: 16,
    fontWeight: '800',
    marginBottom: 6,
  },
  imageErrorText: {
    color: '#d2d0ce',
    fontSize: 12,
    lineHeight: 17,
  },
  collectionEnd: {
    alignItems: 'center',
    backgroundColor: 'rgba(32,31,30,0.94)',
    borderColor: 'rgba(255,255,255,0.18)',
    borderRadius: 12,
    borderWidth: StyleSheet.hairlineWidth,
    marginHorizontal: 24,
    maxWidth: 420,
    padding: 22,
  },
  collectionEndTitle: {
    color: colors.white,
    fontSize: 20,
    fontWeight: '800',
    textAlign: 'center',
  },
  collectionEndText: {
    color: '#d2d0ce',
    fontSize: 13,
    lineHeight: 18,
    marginTop: 8,
    textAlign: 'center',
  },
  collectionEndDivider: {
    backgroundColor: 'rgba(255,255,255,0.16)',
    height: StyleSheet.hairlineWidth,
    marginVertical: 18,
    width: '100%',
  },
  collectionEndLabel: {
    color: '#c8e6ff',
    fontSize: 12,
    fontWeight: '800',
    textAlign: 'center',
  },
  collectionEndNext: {
    color: colors.white,
    fontSize: 14,
    fontWeight: '700',
    lineHeight: 19,
    marginTop: 6,
    textAlign: 'center',
  },
  collectionEndButton: {
    backgroundColor: colors.primary,
    borderRadius: 999,
    marginTop: 16,
    paddingHorizontal: 18,
    paddingVertical: 10,
  },
  collectionEndButtonText: {
    color: colors.white,
    fontSize: 13,
    fontWeight: '800',
  },
  topBar: {
    alignItems: 'center',
    flexDirection: 'row',
    justifyContent: 'space-between',
    left: 0,
    paddingBottom: 8,
    paddingHorizontal: 14,
    position: 'absolute',
    right: 0,
    top: 0,
  },
  topBarGroup: {
    flexDirection: 'row',
    gap: 8,
    minWidth: 88,
  },
  iconButton: {
    alignItems: 'center',
    backgroundColor: 'rgba(0,0,0,0.44)',
    borderRadius: 20,
    height: 40,
    justifyContent: 'center',
    width: 40,
  },
  modeButton: {
    alignItems: 'center',
    backgroundColor: 'rgba(0,0,0,0.44)',
    borderRadius: 999,
    gap: 2,
    minWidth: 96,
    paddingHorizontal: 14,
    paddingVertical: 7,
  },
  modeText: {
    color: colors.white,
    fontSize: 12,
    fontWeight: '800',
  },
  progress: {
    color: colors.white,
    fontSize: 15,
    fontWeight: '800',
  },
  mediaInfoOverlay: {
    backgroundColor: 'rgba(0,0,0,0.58)',
    borderColor: 'rgba(255,255,255,0.18)',
    borderRadius: 8,
    borderWidth: StyleSheet.hairlineWidth,
    left: 12,
    maxWidth: '88%',
    paddingHorizontal: 10,
    paddingVertical: 8,
    position: 'absolute',
    top: 72,
  },
  mediaInfoText: {
    color: colors.white,
    fontSize: 11,
    fontWeight: '700',
    lineHeight: 15,
  },
  bottomBar: {
    alignItems: 'center',
    bottom: 0,
    left: 0,
    paddingHorizontal: 14,
    paddingTop: 8,
    position: 'absolute',
    right: 0,
  },
  laneShell: {
    alignItems: 'center',
    backgroundColor: 'rgba(0,0,0,0.48)',
    borderColor: 'rgba(255,255,255,0.18)',
    borderRadius: 999,
    borderWidth: StyleSheet.hairlineWidth,
    flexDirection: 'row',
    gap: 6,
    minHeight: 40,
    padding: 6,
    width: '100%',
  },
  laneRow: {
    flex: 1,
    flexDirection: 'row',
    gap: 2,
    overflow: 'hidden',
  },
  laneUnit: {
    alignItems: 'center',
    flexDirection: 'row',
    gap: 4,
  },
  laneUnitExpanded: {
    flex: 1,
  },
  laneTabMini: {
    alignItems: 'center',
    borderColor: 'rgba(255,255,255,0.18)',
    borderRadius: 16,
    borderWidth: StyleSheet.hairlineWidth,
    height: 28,
    justifyContent: 'center',
    width: 28,
  },
  laneTabMiniActive: {
    backgroundColor: colors.white,
    borderColor: colors.white,
  },
  laneContent: {
    alignItems: 'center',
    flex: 1,
    gap: 5,
    minHeight: 36,
    justifyContent: 'center',
  },
  laneContentDisabled: {
    opacity: 0.6,
  },
  mediaLane: {
    alignItems: 'center',
    flex: 1,
    flexDirection: 'row',
    gap: 8,
    minWidth: 0,
  },
  mediaLaneCompact: {
    gap: 4,
  },
  mediaIconButton: {
    alignItems: 'center',
    borderRadius: 18,
    height: 36,
    justifyContent: 'center',
    width: 36,
  },
  mediaTimeline: {
    flex: 1,
    justifyContent: 'center',
    minWidth: 0,
  },
  mediaTime: {
    color: colors.white,
    flexShrink: 0,
    fontSize: 10,
    fontWeight: '800',
    textAlign: 'left',
  },
  volumeSlider: {
    height: 32,
    justifyContent: 'center',
    width: 64,
  },
  progressLane: {
    alignItems: 'center',
    backgroundColor: 'rgba(0,0,0,0.44)',
    borderRadius: 999,
    gap: 6,
    minHeight: 40,
    paddingHorizontal: 12,
    paddingVertical: 8,
    width: '100%',
  },
  progressTrack: {
    backgroundColor: 'rgba(255,255,255,0.25)',
    borderRadius: 999,
    height: 3,
    overflow: 'hidden',
    width: '100%',
  },
  progressInline: {
    alignItems: 'center',
    alignSelf: 'stretch',
    flexDirection: 'row',
    gap: 5,
  },
  progressTrackInline: {
    flex: 1,
    width: undefined,
  },
  progressFill: {
    backgroundColor: colors.white,
    borderRadius: 999,
    height: 3,
    position: 'absolute',
    left: 0,
    top: 0,
  },
  progressBuffered: {
    backgroundColor: 'rgba(255,255,255,0.18)',
    borderRadius: 999,
    height: 3,
    position: 'absolute',
    left: 0,
    top: 0,
  },
  progressCaption: {
    color: colors.white,
    flexShrink: 0,
    fontSize: 11,
    fontWeight: '800',
    textAlign: 'left',
  },
  modalBackdrop: {
    backgroundColor: 'rgba(0,0,0,0.38)',
    flex: 1,
    justifyContent: 'flex-end',
  },
  volumePopoverBackdrop: {
    backgroundColor: 'transparent',
  },
  sheet: {
    backgroundColor: colors.surface,
    borderTopLeftRadius: 14,
    borderTopRightRadius: 14,
    maxHeight: '82%',
    padding: spacing.lg,
  },
  sheetHandle: {
    alignSelf: 'center',
    backgroundColor: colors.borderStrong,
    borderRadius: 999,
    height: 4,
    marginBottom: spacing.md,
    width: 44,
  },
  sheetTitle: {
    color: colors.text,
    fontSize: 18,
    fontWeight: '800',
    marginBottom: spacing.md,
  },
  volumeSheet: {
    backgroundColor: colors.surface,
    borderTopLeftRadius: 14,
    borderTopRightRadius: 14,
    padding: spacing.lg,
  },
  volumeSheetHeader: {
    alignItems: 'center',
    flexDirection: 'row',
    justifyContent: 'space-between',
    marginBottom: spacing.md,
  },
  volumeSheetIconButton: {
    alignItems: 'center',
    backgroundColor: colors.primary,
    borderRadius: 20,
    height: 40,
    justifyContent: 'center',
    width: 40,
  },
  volumeSheetValue: {
    color: colors.text,
    fontSize: 22,
    fontWeight: '800',
  },
  volumePresetRow: {
    flexDirection: 'row',
    gap: spacing.sm,
  },
  volumePresetButton: {
    alignItems: 'center',
    backgroundColor: colors.surfaceMuted,
    borderColor: colors.border,
    borderRadius: 8,
    borderWidth: StyleSheet.hairlineWidth,
    flex: 1,
    paddingVertical: 12,
  },
  volumePresetText: {
    color: colors.text,
    fontSize: 13,
    fontWeight: '800',
  },
  volumePopover: {
    alignItems: 'center',
    alignSelf: 'center',
    backgroundColor: 'rgba(0,0,0,0.74)',
    borderColor: 'rgba(255,255,255,0.18)',
    borderRadius: 999,
    borderWidth: StyleSheet.hairlineWidth,
    flexDirection: 'row',
    gap: 10,
    minHeight: 42,
    paddingHorizontal: 10,
    position: 'absolute',
    width: '78%',
  },
  volumePopoverIconButton: {
    alignItems: 'center',
    borderRadius: 17,
    height: 34,
    justifyContent: 'center',
    width: 34,
  },
  volumePopoverSlider: {
    flex: 1,
    height: 34,
    justifyContent: 'center',
  },
  volumePopoverValue: {
    color: colors.white,
    fontSize: 11,
    fontWeight: '800',
    textAlign: 'right',
    width: 34,
  },
  volumePopoverClose: {
    alignItems: 'center',
    borderRadius: 15,
    height: 30,
    justifyContent: 'center',
    width: 30,
  },
  volumePopoverCloseText: {
    color: colors.white,
    fontSize: 14,
    fontWeight: '800',
  },
  modeGrid: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: spacing.sm,
    marginBottom: spacing.md,
  },
  modeChoice: {
    backgroundColor: colors.surfaceMuted,
    borderColor: colors.border,
    borderRadius: 8,
    borderWidth: StyleSheet.hairlineWidth,
    paddingHorizontal: 12,
    paddingVertical: 9,
  },
  modeChoiceActive: {
    backgroundColor: colors.primaryMuted,
    borderColor: colors.primary,
  },
  modeChoiceText: {
    color: colors.textMuted,
    fontWeight: '800',
  },
  modeChoiceTextActive: {
    color: colors.primary,
  },
  settingList: {
    maxHeight: 420,
  },
  settingRow: {
    alignItems: 'center',
    borderColor: colors.border,
    borderRadius: 8,
    borderWidth: StyleSheet.hairlineWidth,
    flexDirection: 'row',
    justifyContent: 'space-between',
    marginBottom: spacing.sm,
    paddingHorizontal: spacing.md,
    paddingVertical: 12,
  },
  settingRowActive: {
    backgroundColor: colors.primaryMuted,
    borderColor: colors.primary,
  },
  settingRowDisabled: {
    opacity: 0.45,
  },
  settingLabel: {
    color: colors.text,
    fontSize: 15,
    fontWeight: '700',
  },
  settingLabelActive: {
    color: colors.primary,
  },
  settingState: {
    color: colors.textMuted,
    fontWeight: '800',
  },
  closeButton: {
    alignItems: 'center',
    backgroundColor: colors.primary,
    borderRadius: 8,
    marginTop: spacing.md,
    paddingVertical: 12,
  },
  closeButtonText: {
    color: colors.white,
    fontSize: 15,
    fontWeight: '800',
  },
});
