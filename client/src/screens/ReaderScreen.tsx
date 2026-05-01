import React, {useCallback, useEffect, useMemo, useRef, useState} from 'react';
import {
  FlatList,
  Image,
  ImageSourcePropType,
  ListRenderItemInfo,
  Modal,
  Pressable,
  ScrollView,
  StyleSheet,
  StyleProp,
  StatusBar,
  Text,
  TouchableOpacity,
  useWindowDimensions,
  View,
  ViewStyle,
  ViewToken,
} from 'react-native';
import type {NativeStackScreenProps} from '@react-navigation/native-stack';
import {
  FlashList,
  type FlashListRef,
  type ListRenderItemInfo as FlashListRenderItemInfo,
} from '@shopify/flash-list';
import {useSafeAreaInsets} from 'react-native-safe-area-context';
import Animated, {
  useAnimatedStyle,
  useSharedValue,
  withTiming,
} from 'react-native-reanimated';
import {
  BookOpen,
  ChevronLeft,
  FastForward,
  Pause,
  Play,
  Rewind,
  Settings as SettingsIcon,
  Volume2,
  VolumeX,
} from 'lucide-react-native';
import {VLCPlayer} from 'react-native-vlc-media-player';
import {WebView} from 'react-native-webview';

import {buildAuthorizedImageSource, buildAuthorizedUri, extractApiError} from '../api/client';
import {
  fetchArchiveFiles,
  getPageDefaultSource,
  pagePath,
  probeMediaPage,
  updateArchiveProgress,
} from '../api/lanlu';
import {ScreenState} from '../components/ScreenState';
import {
  DEFAULT_READER_SETTINGS,
  loadReaderSettings,
  ReaderSettings,
  saveReaderSettings,
} from '../storage/preferences';
import {appendDiagnosticLog} from '../storage/diagnostics';
import {createProxiedMediaUrl} from '../native/LanluMediaProxy';
import {useI18n} from '../i18n';
import {colors, spacing} from '../theme/colors';
import type {RootStackParamList} from '../navigation/types';
import type {PageInfo, PageSourceInfo} from '../types/api';

type Props = NativeStackScreenProps<RootStackParamList, 'Reader'>;

type ReaderPage = PageInfo & {
  pageNumber: number;
  activeSource?: PageSourceInfo | null;
  imageSource?: ImageSourcePropType;
  uri?: string;
  vlcUri?: string;
  headers?: Record<string, string>;
  token?: string;
  resolvedPath?: string;
  effectiveType: 'image' | 'video' | 'audio' | 'html';
};

type ReaderItem = {
  key: string;
  pages: ReaderPage[];
  progressPage: number;
};

type VlcPlayerRef = {
  seek: (position: number) => void;
};

type MediaPlaybackState = {
  currentTime: number;
  duration: number;
  position: number;
  paused: boolean;
  muted: boolean;
  volume: number;
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

function formatMediaTime(seconds: number) {
  const safe = Math.max(0, Math.floor(seconds));
  const minutes = Math.floor(safe / 60);
  const rest = safe % 60;
  return `${minutes}:${String(rest).padStart(2, '0')}`;
}

function nextReadingMode(mode: ReaderSettings['readingMode']) {
  const index = READING_MODES.indexOf(mode);
  return READING_MODES[(index + 1) % READING_MODES.length];
}

function buildVlcMediaOptions(page: ReaderPage) {
  if (page.vlcUri) {
    return [':http-reconnect', ''];
  }
  return [
    ...(page.headers?.Authorization
      ? [`:http-header=Authorization: ${page.headers.Authorization}`]
      : []),
    ...(page.token ? [`:http-header=Cookie: auth_token=${page.token}`] : []),
    ':http-reconnect',
    '',
  ];
}

export function ReaderScreen({route, navigation}: Props) {
  const {t} = useI18n();
  const {archiveId, initialPage = 1} = route.params;
  const {width, height} = useWindowDimensions();
  const insets = useSafeAreaInsets();
  const listRef = useRef<FlatList<ReaderItem>>(null);
  const webtoonRef = useRef<FlashListRef<ReaderPage>>(null);
  const vlcRefs = useRef<Record<number, VlcPlayerRef | null>>({});
  const vlcSessions = useRef<Record<number, {target?: number; playable: boolean; ignoredProgress: number}>>({});
  const vlcSourceKeys = useRef<Record<number, string>>({});
  const mediaProbeKeys = useRef<Set<string>>(new Set());
  const lastSavedPage = useRef(0);
  const settingsHydratedRef = useRef(false);
  const autoHideTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const [settings, setSettings] = useState<ReaderSettings>(DEFAULT_READER_SETTINGS);
  const [settingsOpen, setSettingsOpen] = useState(false);
  const [sourceIndexByPage, setSourceIndexByPage] = useState<Record<number, number>>({});
  const [pages, setPages] = useState<ReaderPage[]>([]);
  const [failedPages, setFailedPages] = useState<Record<number, string>>({});
  const [loadedPages, setLoadedPages] = useState<Record<number, boolean>>({});
  const [currentPage, setCurrentPage] = useState(Math.max(1, initialPage));
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [chromeVisible, setChromeVisible] = useState(true);
  const [activeLaneId, setActiveLaneId] = useState<string>('book');
  const [mediaStateByPage, setMediaStateByPage] = useState<Record<number, MediaPlaybackState>>({});
  const [zoomedPages, setZoomedPages] = useState<Record<number, boolean>>({});
  const chromeProgress = useSharedValue(chromeVisible ? 1 : 0);
  useEffect(() => {
    chromeProgress.value = withTiming(chromeVisible ? 1 : 0, {duration: 160});
  }, [chromeProgress, chromeVisible]);

  const topBarAnimatedStyle = useAnimatedStyle(() => ({
    opacity: chromeProgress.value,
    transform: [{translateY: (chromeProgress.value - 1) * 16}],
  }));

  const bottomBarAnimatedStyle = useAnimatedStyle(() => ({
    opacity: chromeProgress.value,
    transform: [{translateY: (1 - chromeProgress.value) * 18}],
  }));

  const hydratePage = useCallback(
    async (page: PageInfo, index: number): Promise<ReaderPage> => {
      const sourceIndex = sourceIndexByPage[index] ?? page.defaultSourceIndex ?? 0;
      const sources = Array.isArray(page.sources) ? page.sources : [];
      const source =
        sources.length > 0
          ? sources[Math.max(0, Math.min(sources.length - 1, sourceIndex))]
          : getPageDefaultSource(page);
      const effectiveType = source?.type || page.type || 'image';
      const path = source?.path || page.path || '';
      const url = source?.url?.startsWith('/api/') ? source.url : pagePath(archiveId, {...page, defaultSource: source || undefined});
      const authorized = path || source?.url ? await buildAuthorizedUri(url) : {uri: '', headers: undefined, token: undefined};
      const vlcUri =
        authorized.uri && (effectiveType === 'video' || effectiveType === 'audio')
          ? await createProxiedMediaUrl(authorized.uri, authorized.headers)
          : undefined;
      return {
        ...page,
        pageNumber: index + 1,
        activeSource: source,
        resolvedPath: path,
        effectiveType,
        uri: authorized.uri,
        vlcUri,
        headers: authorized.headers,
        token: authorized.token,
        imageSource: effectiveType === 'image' && authorized.uri ? await buildAuthorizedImageSource(url) : undefined,
      };
    },
    [archiveId, sourceIndexByPage],
  );

  const load = useCallback(async () => {
    setLoading(true);
    setError('');
    try {
      const [storedSettings, files] = await Promise.all([
        loadReaderSettings(),
        fetchArchiveFiles(archiveId),
      ]);
      setSettings(storedSettings);
      settingsHydratedRef.current = true;
      const hydrated = await Promise.all(files.map(hydratePage));
      setPages(hydrated);
      const startIndex = Math.max(0, Math.min(initialPage - 1, hydrated.length - 1));
      setCurrentPage(startIndex + 1);
    } catch (err) {
      setError(extractApiError(err));
    } finally {
      setLoading(false);
    }
  }, [archiveId, hydratePage, initialPage]);

  useEffect(() => {
    load().catch(err => console.warn('Failed to load reader:', err));
  }, [load]);

  useEffect(() => {
    if (!settingsHydratedRef.current) return;
    saveReaderSettings(settings).catch(err =>
      console.warn('Failed to save reader settings:', err),
    );
  }, [settings]);

  useEffect(() => {
    if (!pages.length || currentPage <= 0 || currentPage === lastSavedPage.current) return;
    const timer = setTimeout(() => {
      lastSavedPage.current = currentPage;
      updateArchiveProgress(archiveId, currentPage).catch(err => {
        console.warn(extractApiError(err, 'Failed to save progress'));
      });
    }, 900);
    return () => clearTimeout(timer);
  }, [archiveId, currentPage, pages.length]);

  const readerItems = useMemo<ReaderItem[]>(() => {
    if (!settings.doublePage || settings.readingMode === 'webtoon') {
      return pages.map(page => ({
        key: String(page.pageNumber),
        pages: [page],
        progressPage: page.pageNumber,
      }));
    }
    const out: ReaderItem[] = [];
    let index = 0;
    if (settings.splitCover && pages[0]) {
      out.push({key: 'cover', pages: [pages[0]], progressPage: 1});
      index = 1;
    }
    while (index < pages.length) {
      const pair = pages.slice(index, index + 2);
      out.push({
        key: pair.map(page => page.pageNumber).join('-'),
        pages: settings.readingMode === 'single-rtl' ? [...pair].reverse() : pair,
        progressPage: pair[0].pageNumber,
      });
      index += 2;
    }
    return out;
  }, [pages, settings.doublePage, settings.readingMode, settings.splitCover]);

  const currentItemIndex = useMemo(() => {
    const index = readerItems.findIndex(item =>
      item.pages.some(page => page.pageNumber === currentPage),
    );
    return Math.max(0, index);
  }, [currentPage, readerItems]);

  const activeReaderItem = readerItems[currentItemIndex];
  const activeMediaPages = useMemo(
    () =>
      (activeReaderItem?.pages || []).filter(
        page => page.uri && (page.effectiveType === 'video' || page.effectiveType === 'audio'),
      ),
    [activeReaderItem],
  );

  const viewabilityConfig = useMemo(() => ({itemVisiblePercentThreshold: 60}), []);
  const onViewableItemsChanged = useRef(
    ({viewableItems}: {viewableItems: ViewToken<ReaderItem>[]}) => {
      const first = viewableItems[0]?.item;
      if (first?.progressPage) setCurrentPage(first.progressPage);
    },
  );

  const activePage = pages[currentPage - 1];

  const goToPage = useCallback(
    (page: number) => {
      if (!pages.length) return;
      const next = Math.max(1, Math.min(page, pages.length));
      setCurrentPage(next);
      if (settings.readingMode === 'webtoon') {
        webtoonRef.current?.scrollToOffset({
          animated: true,
          offset: (next - 1) * height,
        });
        return;
      }
      const itemIndex = readerItems.findIndex(item =>
        item.pages.some(readerPage => readerPage.pageNumber === next),
      );
      listRef.current?.scrollToIndex({index: Math.max(0, itemIndex), animated: true});
    },
    [height, pages.length, readerItems, settings.readingMode],
  );

  useEffect(() => {
    if (!settings.autoPlay || settings.readingMode === 'webtoon') return;
    const timer = setInterval(() => {
      setCurrentPage(page => {
        const next = Math.min(page + 1, pages.length);
        goToPage(next);
        return next;
      });
    }, settings.autoPlayInterval * 1000);
    return () => clearInterval(timer);
  }, [goToPage, pages.length, settings.autoPlay, settings.autoPlayInterval, settings.readingMode]);

  useEffect(() => {
    if (autoHideTimerRef.current) clearTimeout(autoHideTimerRef.current);
    if (!settings.autoHide || !chromeVisible || settingsOpen) return;
    autoHideTimerRef.current = setTimeout(() => setChromeVisible(false), 3000);
    return () => {
      if (autoHideTimerRef.current) clearTimeout(autoHideTimerRef.current);
    };
  }, [chromeVisible, currentPage, settings.autoHide, settingsOpen]);

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

  function changeSource(page: ReaderPage, delta: number) {
    const count = page.sources?.length || 0;
    if (count <= 1) return;
    const index = page.pageNumber - 1;
    const current = sourceIndexByPage[index] ?? page.defaultSourceIndex ?? 0;
    const next = (current + delta + count) % count;
    setSourceIndexByPage(value => ({...value, [index]: next}));
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

  function seekMedia(page: ReaderPage, seconds: number) {
    const state = getMediaState(page.pageNumber);
    const duration = Math.max(1, state.duration);
    const nextTime = Math.max(0, Math.min(duration, seconds));
    const position = Math.max(0, Math.min(1, nextTime / duration));
    vlcRefs.current[page.pageNumber]?.seek(position);
    setMediaState(page.pageNumber, {currentTime: nextTime, position});
  }

  function toggleChrome() {
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
        goToPage(currentPage + 1);
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
        goToPage(currentPage + 1);
        return;
      }
    } else {
      if (x < horizontalEdge) {
        goToPage(currentPage - 1);
        return;
      }
      if (x > width - horizontalEdge) {
        goToPage(currentPage + 1);
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
    Promise.all(pages.map((page, index) => hydratePage(page, index)))
      .then(setPages)
      .catch(err => console.warn('Failed to switch reader source:', err));
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [sourceIndexByPage]);

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
    if (page.effectiveType === 'video' || page.effectiveType === 'audio') {
      const mediaState = getMediaState(page.pageNumber);
      const mediaOptions = buildVlcMediaOptions(page);
      const mediaUri = page.vlcUri || page.uri || '';
      if (vlcSourceKeys.current[page.pageNumber] !== mediaUri) {
        vlcSourceKeys.current[page.pageNumber] = mediaUri;
        vlcSessions.current[page.pageNumber] = {
          playable: false,
          ignoredProgress: 0,
        };
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
      return (
        <View style={frameStyle}>
          <VLCPlayer
            ref={ref => {
              vlcRefs.current[page.pageNumber] = ref as VlcPlayerRef | null;
            }}
            autoplay
            acceptInvalidCertificates
            paused={mediaState.paused}
            muted={mediaState.muted}
            volume={Math.round(Math.max(0, Math.min(1, mediaState.volume)) * 100)}
            resizeMode="contain"
            source={
              {
                uri: mediaUri,
                isNetwork: Boolean(mediaUri.startsWith('http')),
                initType: 2,
                initOptions: ['--network-caching=600', ''],
                mediaOptions,
              } as never
            }
            style={page.effectiveType === 'audio' ? styles.audioStage : styles.pageImage}
            onBuffering={event => {
              appendDiagnosticLog('vlc.buffering', {
                archiveId,
                page: page.pageNumber,
                type: page.effectiveType,
                event,
              }).catch(reason => console.warn('Failed to write diagnostic log:', reason));
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
              appendDiagnosticLog('vlc.load', {
                archiveId,
                page: page.pageNumber,
                type: page.effectiveType,
                uri: page.uri,
                vlcUri: page.vlcUri,
                path: page.resolvedPath,
                duration: event.duration,
              }).catch(reason => console.warn('Failed to write diagnostic log:', reason));
              setMediaState(page.pageNumber, {
                duration: normalizeVlcSeconds(event.duration),
              });
            }}
            onPaused={() => setMediaState(page.pageNumber, {paused: true})}
            onPlaying={event => {
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
              }).catch(reason => console.warn('Failed to write diagnostic log:', reason));
              setMediaState(page.pageNumber, {
                duration: normalizeVlcSeconds(event.duration),
                paused: false,
              });
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
              setMediaState(page.pageNumber, progress);
            }}
          />
          {page.effectiveType === 'audio' ? (
            <Text style={styles.audioTitle}>{page.title || page.resolvedPath || `${t('reader.audio')} ${page.pageNumber}`}</Text>
          ) : null}
          {commonError ? <ErrorOverlay title={t('reader.mediaFailed')} message={commonError} /> : null}
        </View>
      );
    }

    if (page.effectiveType === 'html') {
      return (
        <View style={frameStyle}>
          <WebView
            allowsBackForwardNavigationGestures
            androidLayerType="hardware"
            overScrollMode="never"
            source={{uri: page.uri || '', headers: page.headers}}
            style={styles.webView}
            containerStyle={styles.webViewContainer}
            onError={event => {
              setFailedPages(current => ({
                ...current,
                [page.pageNumber]: event.nativeEvent.description,
              }));
            }}
          />
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
  const lanes: ReaderLane[] = [
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
  ];
  const activeLane = lanes.find(lane => lane.id === activeLaneId) || lanes[0];

  const renderItem = ({item}: ListRenderItemInfo<ReaderItem>) => {
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

  const renderWebtoonItem = ({item}: FlashListRenderItemInfo<ReaderPage>) => {
    const mediaActive = Math.abs(item.pageNumber - currentPage) <= 1;
    return (
      <ReaderTapSurface
        onDoubleTap={() => handleReaderDoubleTap(item.pageNumber)}
        onTap={handleReaderTap}
        style={styles.webtoonItem}>
        {renderMedia(item, width, settings.longPage ? undefined : height, true, mediaActive)}
      </ReaderTapSurface>
    );
  };

  return (
    <View style={styles.screen}>
      <StatusBar
        backgroundColor="transparent"
        barStyle="light-content"
        translucent
      />
      {settings.readingMode === 'webtoon' ? (
        <FlashList
          data={pages}
          drawDistance={height * 1.5}
          extraData={{
            currentPage,
            failedPages,
            loadedPages,
            longPage: settings.longPage,
          }}
          key={`webtoon:${settings.longPage ? 'long' : 'paged'}`}
          keyExtractor={page => `${page.pageNumber}:${page.uri || page.id}`}
          onScroll={event => {
            const approx =
              Math.floor(event.nativeEvent.contentOffset.y / Math.max(1, height * 0.86)) + 1;
            setCurrentPage(Math.max(1, Math.min(approx, pages.length)));
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
          currentPage={currentPage}
          getMediaState={getMediaState}
          page={activePage}
          pages={pages}
          settings={settings}
          t={t}
        />
      ) : null}

      <Animated.View
        pointerEvents={chromeVisible ? 'auto' : 'none'}
        style={[styles.topBar, {paddingTop: insets.top + 8}, topBarAnimatedStyle]}>
            <TouchableOpacity onPress={() => navigation.goBack()} style={styles.iconButton}>
              <ChevronLeft color={colors.white} size={24} />
            </TouchableOpacity>
            <TouchableOpacity onPress={cycleMode} style={styles.modeButton}>
              <Text style={styles.modeText}>{t(modeLabelKey(settings.readingMode))}</Text>
              <Text style={styles.progress}>{currentPage} / {pages.length}</Text>
            </TouchableOpacity>
            <TouchableOpacity onPress={() => setSettingsOpen(true)} style={styles.iconButton}>
              <SettingsIcon color={colors.white} size={21} />
            </TouchableOpacity>
      </Animated.View>
      <Animated.View
        pointerEvents={chromeVisible ? 'auto' : 'none'}
        style={[styles.bottomBar, {paddingBottom: insets.bottom + 10}, bottomBarAnimatedStyle]}>
            <View style={styles.laneShell}>
              <View style={styles.laneTabs}>
                {lanes.map(lane => (
                  <TouchableOpacity
                    accessibilityLabel={lane.label}
                    accessibilityRole="button"
                    key={lane.id}
                    onPress={() => setActiveLaneId(lane.id)}
                    style={[styles.laneTab, activeLane.id === lane.id && styles.laneTabActive]}>
                    {lane.kind === 'book' ? (
                      <BookOpen color={activeLane.id === lane.id ? colors.black : colors.white} size={16} />
                    ) : lane.kind === 'audio' ? (
                      <Volume2 color={activeLane.id === lane.id ? colors.black : colors.white} size={16} />
                    ) : (
                      <Play color={activeLane.id === lane.id ? colors.black : colors.white} size={15} />
                    )}
                  </TouchableOpacity>
                ))}
              </View>

              {activeLane.kind === 'book' ? (
                <TouchableOpacity
                  activeOpacity={0.9}
                  onPress={event => {
                    const laneWidth = Math.max(1, width - 92);
                    const x = event.nativeEvent.locationX;
                    const next = Math.round((x / laneWidth) * Math.max(1, pages.length - 1)) + 1;
                    goToPage(next);
                  }}
                  style={styles.laneContent}>
                  <View style={styles.progressTrack}>
                    <View
                      style={[
                        styles.progressFill,
                        {width: `${Math.max(2, (currentPage / Math.max(1, pages.length)) * 100)}%`},
                      ]}
                    />
                  </View>
                  <Text style={styles.progressCaption}>{currentPage} / {pages.length}</Text>
                </TouchableOpacity>
              ) : (
                <MediaLaneControls
                  label={activeLane.label}
                  page={activeLane.page}
                  state={getMediaState(activeLane.page.pageNumber)}
                  sourceIndex={sourceIndexByPage[activeLane.page.pageNumber - 1] ?? activeLane.page.defaultSourceIndex ?? 0}
                  t={t}
                  onChangeSource={() => changeSource(activeLane.page, 1)}
                  onSeek={seconds => seekMedia(activeLane.page, seconds)}
                  onSeekRelative={seconds =>
                    seekMedia(activeLane.page, getMediaState(activeLane.page.pageNumber).currentTime + seconds)
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
                  onVolumeStep={delta =>
                    setMediaState(activeLane.page.pageNumber, {
                      muted: false,
                      volume: Math.max(0, Math.min(1, getMediaState(activeLane.page.pageNumber).volume + delta)),
                    })
                  }
                />
              )}
            </View>
      </Animated.View>

      <ReaderSettingsModal
        open={settingsOpen}
        settings={settings}
        t={t}
        onClose={() => setSettingsOpen(false)}
        onPatch={patchSettings}
      />
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

function MediaInfoOverlay({
  activeLane,
  currentPage,
  getMediaState,
  page,
  pages,
  settings,
  t,
}: {
  activeLane: ReaderLane;
  currentPage: number;
  getMediaState: (pageNumber: number) => MediaPlaybackState;
  page: ReaderPage;
  pages: ReaderPage[];
  settings: ReaderSettings;
  t: ReturnType<typeof useI18n>['t'];
}) {
  const mediaState =
    activeLane.kind === 'book' ? null : getMediaState(activeLane.page.pageNumber);
  const lines = [
    `${t('reader.pageInfo')}: ${currentPage} / ${pages.length}`,
    `${t('reader.modeInfo')}: ${t(modeLabelKey(settings.readingMode))}`,
    `${t('reader.fileInfo')}: ${page.resolvedPath || page.path || page.uri || page.id}`,
    `${t('reader.typeInfo')}: ${page.effectiveType}`,
    `${t('reader.settingsInfo')}: tap=${settings.tapTurnPage ? 'on' : 'off'} auto=${settings.autoPlay ? 'on' : 'off'} hide=${settings.autoHide ? 'on' : 'off'}`,
    mediaState
      ? `${activeLane.label}: ${formatMediaTime(mediaState.currentTime)} / ${formatMediaTime(mediaState.duration)} ${mediaState.paused ? t('reader.pause') : t('reader.play')}`
      : '',
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
  const lastTapAt = useRef(0);

  return (
    <Pressable
      onPress={event => {
        const now = Date.now();
        const isDoubleTap = onDoubleTap && now - lastTapAt.current < 260;
        lastTapAt.current = now;
        if (isDoubleTap) {
          onDoubleTap();
          return;
        }
        onTap(event.nativeEvent.locationX, event.nativeEvent.locationY);
      }}
      style={style}>
      {children}
    </Pressable>
  );
}

function MediaLaneControls({
  label,
  page,
  state,
  sourceIndex,
  t,
  onChangeSource,
  onSeek,
  onSeekRelative,
  onToggleMute,
  onTogglePlay,
  onVolumeStep,
}: {
  label: string;
  page: ReaderPage;
  state: MediaPlaybackState;
  sourceIndex: number;
  t: ReturnType<typeof useI18n>['t'];
  onChangeSource: () => void;
  onSeek: (seconds: number) => void;
  onSeekRelative: (seconds: number) => void;
  onToggleMute: () => void;
  onTogglePlay: () => void;
  onVolumeStep: (delta: number) => void;
}) {
  const sourceCount = page.sources?.length || 0;
  const duration = Math.max(0, state.duration);
  const position = duration > 0 ? state.currentTime / duration : state.position;
  const [timelineWidth, setTimelineWidth] = useState(1);
  return (
    <View style={styles.mediaLane}>
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
        accessibilityLabel={t('reader.seekBack')}
        accessibilityRole="button"
        onPress={() => onSeekRelative(-5)}
        style={styles.mediaIconButton}>
        <Rewind color={colors.white} size={16} />
      </TouchableOpacity>
      <TouchableOpacity
        accessibilityLabel={t('reader.seekForward')}
        accessibilityRole="button"
        onPress={() => onSeekRelative(5)}
        style={styles.mediaIconButton}>
        <FastForward color={colors.white} size={16} />
      </TouchableOpacity>
      <TouchableOpacity
        activeOpacity={0.9}
        onLayout={event => setTimelineWidth(Math.max(1, event.nativeEvent.layout.width))}
        onPress={event => {
          onSeek((event.nativeEvent.locationX / timelineWidth) * Math.max(1, duration));
        }}
        style={styles.mediaTimeline}>
        <View style={styles.progressTrack}>
          <View
            style={[
              styles.progressFill,
              {width: `${Math.max(2, Math.max(0, Math.min(1, position)) * 100)}%`},
            ]}
          />
        </View>
        <Text style={styles.mediaTime} numberOfLines={1}>
          {label} {formatMediaTime(state.currentTime)} / {formatMediaTime(duration)}
        </Text>
      </TouchableOpacity>
      <TouchableOpacity
        accessibilityLabel={state.muted ? t('reader.unmute') : t('reader.mute')}
        accessibilityRole="button"
        onPress={onToggleMute}
        style={styles.mediaIconButton}>
        {state.muted ? (
          <VolumeX color={colors.white} size={16} />
        ) : (
          <Volume2 color={colors.white} size={16} />
        )}
      </TouchableOpacity>
      <TouchableOpacity
        accessibilityLabel={t('reader.volume')}
        accessibilityRole="button"
        onPress={() => onVolumeStep(state.volume >= 1 ? -0.25 : 0.25)}
        style={styles.volumePill}>
        <Text style={styles.sourceButtonText}>{Math.round(state.volume * 100)}</Text>
      </TouchableOpacity>
      {sourceCount > 1 ? (
        <TouchableOpacity onPress={onChangeSource} style={styles.sourceButton}>
          <Text style={styles.sourceButtonText}>
            {t('reader.source', {current: sourceIndex + 1, total: sourceCount})}
          </Text>
        </TouchableOpacity>
      ) : null}
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
    <Modal animationType="slide" onRequestClose={onClose} transparent visible={open}>
      <View style={styles.modalBackdrop}>
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
      </View>
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
    height: 84,
    width: '92%',
  },
  audioTitle: {
    color: colors.white,
    fontSize: 16,
    fontWeight: '800',
    marginTop: spacing.md,
    paddingHorizontal: spacing.lg,
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
    gap: 8,
    minHeight: 48,
    padding: 6,
    width: '100%',
  },
  laneTabs: {
    flexDirection: 'row',
    gap: 4,
  },
  laneTab: {
    alignItems: 'center',
    borderColor: 'rgba(255,255,255,0.18)',
    borderRadius: 18,
    borderWidth: StyleSheet.hairlineWidth,
    height: 36,
    justifyContent: 'center',
    width: 36,
  },
  laneTabActive: {
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
  mediaLane: {
    alignItems: 'center',
    flex: 1,
    flexDirection: 'row',
    gap: 6,
    minWidth: 0,
  },
  mediaIconButton: {
    alignItems: 'center',
    borderRadius: 16,
    height: 32,
    justifyContent: 'center',
    width: 32,
  },
  mediaTimeline: {
    flex: 1,
    gap: 5,
    justifyContent: 'center',
    minWidth: 0,
  },
  mediaTime: {
    color: colors.white,
    fontSize: 10,
    fontWeight: '800',
  },
  volumePill: {
    alignItems: 'center',
    borderRadius: 999,
    justifyContent: 'center',
    minWidth: 28,
    paddingHorizontal: 4,
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
  progressFill: {
    backgroundColor: colors.white,
    borderRadius: 999,
    height: 3,
  },
  progressCaption: {
    color: colors.white,
    fontSize: 11,
    fontWeight: '800',
  },
  sourceButton: {
    alignItems: 'center',
    borderRadius: 999,
    justifyContent: 'center',
    minHeight: 18,
  },
  sourceButtonText: {
    color: colors.white,
    fontSize: 12,
    fontWeight: '800',
  },
  modalBackdrop: {
    backgroundColor: 'rgba(0,0,0,0.38)',
    flex: 1,
    justifyContent: 'flex-end',
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
