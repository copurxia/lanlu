import React, {useCallback, useEffect, useMemo, useRef, useState} from 'react';
import {
  FlatList,
  Image,
  ImageSourcePropType,
  ListRenderItemInfo,
  Modal,
  ScrollView,
  StyleSheet,
  Text,
  TouchableOpacity,
  useWindowDimensions,
  View,
  ViewToken,
} from 'react-native';
import type {NativeStackScreenProps} from '@react-navigation/native-stack';
import {useSafeAreaInsets} from 'react-native-safe-area-context';
import {ChevronLeft, Settings as SettingsIcon} from 'lucide-react-native';
import Video from 'react-native-video';
import {WebView} from 'react-native-webview';

import {buildAuthorizedImageSource, buildAuthorizedUri, extractApiError} from '../api/client';
import {
  fetchArchiveFiles,
  getPageDefaultSource,
  pagePath,
  updateArchiveProgress,
} from '../api/lanlu';
import {ScreenState} from '../components/ScreenState';
import {
  DEFAULT_READER_SETTINGS,
  loadReaderSettings,
  ReaderSettings,
  saveReaderSettings,
} from '../storage/preferences';
import {colors, spacing} from '../theme/colors';
import type {RootStackParamList} from '../navigation/types';
import type {PageInfo, PageSourceInfo} from '../types/api';

type Props = NativeStackScreenProps<RootStackParamList, 'Reader'>;

type ReaderPage = PageInfo & {
  pageNumber: number;
  activeSource?: PageSourceInfo | null;
  imageSource?: ImageSourcePropType;
  uri?: string;
  headers?: Record<string, string>;
  resolvedPath?: string;
  effectiveType: 'image' | 'video' | 'audio' | 'html';
};

type ReaderItem = {
  key: string;
  pages: ReaderPage[];
  progressPage: number;
};

const READING_MODES: ReaderSettings['readingMode'][] = [
  'single-ltr',
  'single-rtl',
  'single-ttb',
  'webtoon',
];

function modeLabel(mode: ReaderSettings['readingMode']) {
  switch (mode) {
    case 'single-ltr':
      return 'LTR';
    case 'single-rtl':
      return 'RTL';
    case 'single-ttb':
      return 'Top';
    case 'webtoon':
      return 'Webtoon';
  }
}

function nextReadingMode(mode: ReaderSettings['readingMode']) {
  const index = READING_MODES.indexOf(mode);
  return READING_MODES[(index + 1) % READING_MODES.length];
}

export function ReaderScreen({route, navigation}: Props) {
  const {archiveId, initialPage = 1} = route.params;
  const {width, height} = useWindowDimensions();
  const insets = useSafeAreaInsets();
  const listRef = useRef<FlatList<ReaderItem>>(null);
  const webtoonRef = useRef<ScrollView>(null);
  const lastSavedPage = useRef(0);
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
      const authorized = path || source?.url ? await buildAuthorizedUri(url) : {uri: '', headers: undefined};
      return {
        ...page,
        pageNumber: index + 1,
        activeSource: source,
        resolvedPath: path,
        effectiveType,
        uri: authorized.uri,
        headers: authorized.headers,
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
      const hydrated = await Promise.all(files.map(hydratePage));
      setPages(hydrated);
      const startIndex = Math.max(0, Math.min(initialPage - 1, hydrated.length - 1));
      setCurrentPage(startIndex + 1);
      requestAnimationFrame(() => {
        listRef.current?.scrollToIndex({index: startIndex, animated: false});
      });
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

  const viewabilityConfig = useMemo(() => ({itemVisiblePercentThreshold: 60}), []);
  const onViewableItemsChanged = useRef(
    ({viewableItems}: {viewableItems: ViewToken<ReaderItem>[]}) => {
      const first = viewableItems[0]?.item;
      if (first?.progressPage) setCurrentPage(first.progressPage);
    },
  );

  const goToPage = useCallback(
    (page: number) => {
      if (!pages.length) return;
      const next = Math.max(1, Math.min(page, pages.length));
      setCurrentPage(next);
      if (settings.readingMode === 'webtoon') {
        webtoonRef.current?.scrollTo({y: (next - 1) * height * 0.86, animated: true});
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

  useEffect(() => {
    if (!pages.length) return;
    Promise.all(pages.map((page, index) => hydratePage(page, index)))
      .then(setPages)
      .catch(err => console.warn('Failed to switch reader source:', err));
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [sourceIndexByPage]);

  if (loading) return <ScreenState loading title="Loading reader" />;

  if (error) {
    return (
      <ScreenState
        title="Could not load reader"
        message={error}
        actionLabel="Retry"
        onAction={() => load().catch(err => console.warn('Failed to load reader:', err))}
      />
    );
  }

  if (!pages.length) {
    return (
      <ScreenState
        title="No readable pages"
        message="This archive has no pages available for the mobile reader."
        actionLabel="Back"
        onAction={() => navigation.goBack()}
      />
    );
  }

  const renderMedia = (page: ReaderPage, pageWidth: number, pageHeight?: number, webtoon = false) => {
    const commonError = failedPages[page.pageNumber];
    const frameStyle = webtoon
      ? [styles.webtoonPage, {width}]
      : [styles.mediaPage, {width: pageWidth, height: pageHeight || height}];
    if (page.effectiveType === 'video' || page.effectiveType === 'audio') {
      return (
        <View style={frameStyle}>
          <Video
            controls
            paused={false}
            resizeMode="contain"
            source={{uri: page.uri || '', headers: page.headers}}
            style={page.effectiveType === 'audio' ? styles.audioStage : styles.pageImage}
            onError={err => {
              setFailedPages(current => ({
                ...current,
                [page.pageNumber]: JSON.stringify(err),
              }));
            }}
          />
          {page.effectiveType === 'audio' ? (
            <Text style={styles.audioTitle}>{page.title || page.resolvedPath || `Audio ${page.pageNumber}`}</Text>
          ) : null}
          {commonError ? <ErrorOverlay title="Media failed to load" message={commonError} /> : null}
        </View>
      );
    }

    if (page.effectiveType === 'html') {
      return (
        <View style={frameStyle}>
          <WebView
            source={{uri: page.uri || '', headers: page.headers}}
            style={styles.webView}
            onError={event => {
              setFailedPages(current => ({
                ...current,
                [page.pageNumber]: event.nativeEvent.description,
              }));
            }}
          />
          {commonError ? <ErrorOverlay title="HTML failed to load" message={commonError} /> : null}
        </View>
      );
    }

    return (
      <View style={frameStyle}>
        {page.imageSource ? (
          <>
            {!loadedPages[page.pageNumber] && !commonError ? (
              <Text style={styles.loadingText}>Loading page {page.pageNumber}...</Text>
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
              ]}
            />
            {commonError ? (
              <ErrorOverlay title="Page failed to load" message={`${commonError}\n${page.resolvedPath || page.uri || ''}`} />
            ) : null}
          </>
        ) : (
          <ErrorOverlay title="No readable image source" message={page.id} />
        )}
      </View>
    );
  };

  const current = pages[Math.max(0, currentPage - 1)];
  const horizontal = settings.readingMode === 'single-ltr' || settings.readingMode === 'single-rtl';
  const pageFrameHeight = height;

  const renderItem = ({item}: ListRenderItemInfo<ReaderItem>) => {
    const spreadPageWidth = item.pages.length > 1 ? width / 2 : width;
    return (
      <TouchableOpacity
        activeOpacity={1}
        onPress={() => setChromeVisible(visible => !visible)}
        style={[styles.page, {width, height: pageFrameHeight}]}>
        <View style={styles.spread}>
          {item.pages.map(page => (
            <View key={`${item.key}:${page.pageNumber}`} style={{width: spreadPageWidth, height: pageFrameHeight}}>
              {renderMedia(page, spreadPageWidth, pageFrameHeight)}
            </View>
          ))}
        </View>
      </TouchableOpacity>
    );
  };

  return (
    <View style={styles.screen}>
      {settings.readingMode === 'webtoon' ? (
        <ScrollView
          ref={webtoonRef}
          onScroll={event => {
            const approx = Math.floor(event.nativeEvent.contentOffset.y / Math.max(1, height * 0.86)) + 1;
            setCurrentPage(Math.max(1, Math.min(approx, pages.length)));
          }}
          scrollEventThrottle={100}
          contentContainerStyle={styles.webtoonContent}>
          {pages.map(page => (
            <TouchableOpacity
              activeOpacity={1}
              key={`${page.pageNumber}:${page.uri}`}
              onPress={() => setChromeVisible(visible => !visible)}>
              {renderMedia(page, width, undefined, true)}
            </TouchableOpacity>
          ))}
        </ScrollView>
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
          initialScrollIndex={currentItemIndex}
          inverted={settings.readingMode === 'single-rtl'}
          key={`${settings.readingMode}:${settings.doublePage}:${settings.splitCover}`}
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

      {chromeVisible ? (
        <>
          <View style={[styles.topBar, {paddingTop: insets.top + 8}]}>
            <TouchableOpacity onPress={() => navigation.goBack()} style={styles.iconButton}>
              <ChevronLeft color={colors.white} size={24} />
            </TouchableOpacity>
            <TouchableOpacity onPress={cycleMode} style={styles.modeButton}>
              <Text style={styles.modeText}>{modeLabel(settings.readingMode)}</Text>
              <Text style={styles.progress}>{currentPage} / {pages.length}</Text>
            </TouchableOpacity>
            <TouchableOpacity onPress={() => setSettingsOpen(true)} style={styles.iconButton}>
              <SettingsIcon color={colors.white} size={21} />
            </TouchableOpacity>
          </View>
          <View style={[styles.bottomBar, {paddingBottom: insets.bottom + 10}]}>
            <TouchableOpacity
              activeOpacity={0.9}
              onPress={event => {
                const laneWidth = Math.max(1, width - 28);
                const x = event.nativeEvent.locationX;
                const next = Math.round((x / laneWidth) * Math.max(1, pages.length - 1)) + 1;
                goToPage(next);
              }}
              style={styles.progressLane}>
              <View style={styles.progressTrack}>
                <View
                  style={[
                    styles.progressFill,
                    {width: `${Math.max(2, (currentPage / Math.max(1, pages.length)) * 100)}%`},
                  ]}
                />
              </View>
              {current?.sources && current.sources.length > 1 ? (
                <TouchableOpacity
                  onPress={() => changeSource(current, 1)}
                  style={styles.sourceButton}>
                  <Text style={styles.sourceButtonText}>
                    Source {(sourceIndexByPage[current.pageNumber - 1] ?? current.defaultSourceIndex ?? 0) + 1}/{current.sources.length}
                  </Text>
                </TouchableOpacity>
              ) : (
                <Text style={styles.progressCaption}>{currentPage} / {pages.length}</Text>
              )}
            </TouchableOpacity>
          </View>
        </>
      ) : null}

      <ReaderSettingsModal
        open={settingsOpen}
        settings={settings}
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

function ReaderSettingsModal({
  open,
  settings,
  onClose,
  onPatch,
}: {
  open: boolean;
  settings: ReaderSettings;
  onClose: () => void;
  onPatch: (patch: Partial<ReaderSettings>) => void;
}) {
  return (
    <Modal animationType="slide" onRequestClose={onClose} transparent visible={open}>
      <View style={styles.modalBackdrop}>
        <View style={styles.sheet}>
          <View style={styles.sheetHandle} />
          <Text style={styles.sheetTitle}>Reader settings</Text>
          <View style={styles.modeGrid}>
            {READING_MODES.map(mode => (
              <TouchableOpacity
                key={mode}
                onPress={() => onPatch({readingMode: mode})}
                style={[styles.modeChoice, settings.readingMode === mode && styles.modeChoiceActive]}>
                <Text style={[styles.modeChoiceText, settings.readingMode === mode && styles.modeChoiceTextActive]}>
                  {modeLabel(mode)}
                </Text>
              </TouchableOpacity>
            ))}
          </View>
          <ScrollView style={styles.settingList}>
            <ReaderSettingToggle
              label="Double page"
              active={settings.doublePage}
              disabled={settings.readingMode === 'webtoon'}
              onPress={() => onPatch({doublePage: !settings.doublePage})}
            />
            <ReaderSettingToggle
              label="Split cover"
              active={settings.splitCover}
              disabled={!settings.doublePage || settings.readingMode === 'webtoon'}
              onPress={() => onPatch({splitCover: !settings.splitCover})}
            />
            <ReaderSettingToggle
              label="Auto play"
              active={settings.autoPlay}
              onPress={() => onPatch({autoPlay: !settings.autoPlay})}
            />
            <TouchableOpacity
              onPress={() =>
                onPatch({autoPlayInterval: settings.autoPlayInterval >= 10 ? 1 : settings.autoPlayInterval + 1})
              }
              style={styles.settingRow}>
              <Text style={styles.settingLabel}>Page interval</Text>
              <Text style={styles.settingState}>{settings.autoPlayInterval}s</Text>
            </TouchableOpacity>
            <ReaderSettingToggle
              label="Tap turn page"
              active={settings.tapTurnPage}
              onPress={() => onPatch({tapTurnPage: !settings.tapTurnPage})}
            />
            <ReaderSettingToggle
              label="Auto hide controls"
              active={settings.autoHide}
              onPress={() => onPatch({autoHide: !settings.autoHide})}
            />
            <ReaderSettingToggle
              label="Media info"
              active={settings.mediaInfo}
              onPress={() => onPatch({mediaInfo: !settings.mediaInfo})}
            />
            <ReaderSettingToggle
              label="Long page"
              active={settings.longPage}
              onPress={() => onPatch({longPage: !settings.longPage})}
            />
            <ReaderSettingToggle
              label="Double tap zoom"
              active={settings.doubleTapZoom}
              onPress={() => onPatch({doubleTapZoom: !settings.doubleTapZoom})}
            />
            <ReaderSettingToggle
              label="Seamless next"
              active={settings.seamlessNext}
              onPress={() => onPatch({seamlessNext: !settings.seamlessNext})}
            />
          </ScrollView>
          <TouchableOpacity onPress={onClose} style={styles.closeButton}>
            <Text style={styles.closeButtonText}>Close</Text>
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
  onPress,
}: {
  label: string;
  active: boolean;
  disabled?: boolean;
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
        {active ? 'On' : 'Off'}
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
  webtoonContent: {
    alignItems: 'center',
    backgroundColor: colors.black,
    paddingBottom: 24,
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
  bottomBar: {
    alignItems: 'center',
    bottom: 0,
    left: 0,
    paddingHorizontal: 14,
    paddingTop: 8,
    position: 'absolute',
    right: 0,
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
