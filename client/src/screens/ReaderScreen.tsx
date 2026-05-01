import React, {useCallback, useEffect, useMemo, useRef, useState} from 'react';
import {
  FlatList,
  Image,
  ImageSourcePropType,
  ListRenderItemInfo,
  StyleSheet,
  Text,
  TouchableOpacity,
  useWindowDimensions,
  View,
  ViewToken,
} from 'react-native';
import type {NativeStackScreenProps} from '@react-navigation/native-stack';
import {useSafeAreaInsets} from 'react-native-safe-area-context';

import {buildAuthorizedImageSource, extractApiError} from '../api/client';
import {
  fetchArchiveFiles,
  getPageDefaultSource,
  pagePath,
  updateArchiveProgress,
} from '../api/lanlu';
import {ScreenState} from '../components/ScreenState';
import {colors} from '../theme/colors';
import type {RootStackParamList} from '../navigation/types';
import type {PageInfo} from '../types/api';

type Props = NativeStackScreenProps<RootStackParamList, 'Reader'>;

type ReaderPage = PageInfo & {
  pageNumber: number;
  imageSource?: ImageSourcePropType;
  resolvedPath?: string;
  resolvedUrl?: string;
};

export function ReaderScreen({route, navigation}: Props) {
  const {archiveId, initialPage = 1} = route.params;
  const {width, height} = useWindowDimensions();
  const insets = useSafeAreaInsets();
  const listRef = useRef<FlatList<ReaderPage>>(null);
  const lastSavedPage = useRef(0);
  const [pages, setPages] = useState<ReaderPage[]>([]);
  const [failedPages, setFailedPages] = useState<Record<number, string>>({});
  const [loadedPages, setLoadedPages] = useState<Record<number, boolean>>({});
  const [currentPage, setCurrentPage] = useState(Math.max(1, initialPage));
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [chromeVisible, setChromeVisible] = useState(true);

  const load = useCallback(async () => {
    setLoading(true);
    setError('');
    try {
      const files = await fetchArchiveFiles(archiveId);
      const imagePages = files.filter(file => {
        const source = getPageDefaultSource(file);
        return (source?.type || file.type || 'image') === 'image';
      });
      const hydrated = await Promise.all(
        imagePages.map(async (page, index) => {
          const source = getPageDefaultSource(page);
          const path = source?.path || page.path || '';
          const url = pagePath(archiveId, page);
          return {
            ...page,
            pageNumber: index + 1,
            resolvedPath: path,
            resolvedUrl: url,
            imageSource: path ? await buildAuthorizedImageSource(url) : undefined,
          };
        }),
      );
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
  }, [archiveId, initialPage]);

  useEffect(() => {
    load().catch(err => console.warn('Failed to load reader:', err));
  }, [load]);

  useEffect(() => {
    if (!pages.length || currentPage <= 0 || currentPage === lastSavedPage.current) {
      return;
    }

    const timer = setTimeout(() => {
      lastSavedPage.current = currentPage;
      updateArchiveProgress(archiveId, currentPage).catch(err => {
        console.warn(extractApiError(err, 'Failed to save progress'));
      });
    }, 900);
    return () => clearTimeout(timer);
  }, [archiveId, currentPage, pages.length]);

  const viewabilityConfig = useMemo(
    () => ({itemVisiblePercentThreshold: 60}),
    [],
  );

  const onViewableItemsChanged = useRef(
    ({viewableItems}: {viewableItems: ViewToken<ReaderPage>[]}) => {
      const first = viewableItems[0]?.item;
      if (first?.pageNumber) {
        setCurrentPage(first.pageNumber);
      }
    },
  );

  function goToPage(page: number) {
    if (!pages.length) {
      return;
    }
    const next = Math.max(1, Math.min(page, pages.length));
    listRef.current?.scrollToIndex({index: next - 1, animated: true});
    setCurrentPage(next);
  }

  if (loading) {
    return <ScreenState loading title="Loading reader" />;
  }

  if (error) {
    return (
      <ScreenState
        title="Could not load reader"
        message={error}
        actionLabel="Retry"
        onAction={() => {
          load().catch(err => console.warn('Failed to load reader:', err));
        }}
      />
    );
  }

  if (!pages.length) {
    return (
      <ScreenState
        title="No image pages"
        message="This mobile MVP currently supports image archives only."
        actionLabel="Back"
        onAction={() => navigation.goBack()}
      />
    );
  }

  const renderItem = ({item}: ListRenderItemInfo<ReaderPage>) => (
    <TouchableOpacity
      activeOpacity={1}
      onPress={() => setChromeVisible(visible => !visible)}
      style={[styles.page, {width, minHeight: height}]}>
      {item.imageSource ? (
        <>
          {!loadedPages[item.pageNumber] && !failedPages[item.pageNumber] ? (
            <Text style={styles.loadingText}>Loading page {item.pageNumber}...</Text>
          ) : null}
          <Image
            onError={event => {
              setFailedPages(current => ({
                ...current,
                [item.pageNumber]:
                  event.nativeEvent.error || 'Image failed to load.',
              }));
            }}
            onLoad={() => {
              setLoadedPages(current => ({...current, [item.pageNumber]: true}));
            }}
            resizeMode="contain"
            source={item.imageSource}
            style={styles.pageImage}
          />
          {failedPages[item.pageNumber] ? (
            <View style={styles.imageError}>
              <Text style={styles.imageErrorTitle}>Page failed to load</Text>
              <Text style={styles.imageErrorText}>{failedPages[item.pageNumber]}</Text>
              <Text style={styles.imageErrorText}>{item.resolvedPath || item.resolvedUrl}</Text>
            </View>
          ) : null}
        </>
      ) : (
        <View style={styles.imageError}>
          <Text style={styles.imageErrorTitle}>No readable image source</Text>
          <Text style={styles.imageErrorText}>{item.id}</Text>
        </View>
      )}
    </TouchableOpacity>
  );

  return (
    <View style={styles.screen}>
      <FlatList
        data={pages}
        decelerationRate="fast"
        getItemLayout={(_, index) => ({
          length: width,
          offset: width * index,
          index,
        })}
        horizontal
        initialScrollIndex={Math.max(0, Math.min(initialPage - 1, pages.length - 1))}
        keyExtractor={item => `${item.pageNumber}:${item.path}`}
        onScrollToIndexFailed={info => {
          setTimeout(() => goToPage(info.index + 1), 250);
        }}
        onViewableItemsChanged={onViewableItemsChanged.current}
        pagingEnabled
        ref={listRef}
        renderItem={renderItem}
        removeClippedSubviews={false}
        showsHorizontalScrollIndicator={false}
        viewabilityConfig={viewabilityConfig}
      />

      {chromeVisible ? (
        <>
          <View style={[styles.topBar, {paddingTop: insets.top + 8}]}>
            <TouchableOpacity onPress={() => navigation.goBack()} style={styles.iconButton}>
              <Text style={styles.iconButtonText}>‹</Text>
            </TouchableOpacity>
            <Text style={styles.progress}>
              {currentPage} / {pages.length}
            </Text>
            <View style={styles.iconButtonSpacer} />
          </View>
          <View style={[styles.bottomBar, {paddingBottom: insets.bottom + 10}]}>
            <TouchableOpacity
              disabled={currentPage <= 1}
              onPress={() => goToPage(currentPage - 1)}
              style={[styles.navButton, currentPage <= 1 && styles.navButtonDisabled]}>
              <Text style={styles.navButtonText}>Previous</Text>
            </TouchableOpacity>
            <TouchableOpacity
              disabled={currentPage >= pages.length}
              onPress={() => goToPage(currentPage + 1)}
              style={[
                styles.navButton,
                currentPage >= pages.length && styles.navButtonDisabled,
              ]}>
              <Text style={styles.navButtonText}>Next</Text>
            </TouchableOpacity>
          </View>
        </>
      ) : null}
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
    flex: 1,
    justifyContent: 'center',
  },
  pageImage: {
    height: '100%',
    width: '100%',
  },
  loadingText: {
    color: colors.white,
    position: 'absolute',
    zIndex: 1,
  },
  unsupported: {
    color: colors.white,
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
    backgroundColor: 'rgba(0,0,0,0.58)',
    flexDirection: 'row',
    justifyContent: 'space-between',
    left: 0,
    paddingBottom: 10,
    paddingHorizontal: 14,
    position: 'absolute',
    right: 0,
    top: 0,
  },
  iconButton: {
    alignItems: 'center',
    borderRadius: 8,
    height: 40,
    justifyContent: 'center',
    width: 40,
  },
  iconButtonText: {
    color: colors.white,
    fontSize: 38,
    lineHeight: 38,
  },
  iconButtonSpacer: {
    height: 40,
    width: 40,
  },
  progress: {
    color: colors.white,
    fontSize: 15,
    fontWeight: '800',
  },
  bottomBar: {
    backgroundColor: 'rgba(0,0,0,0.58)',
    bottom: 0,
    flexDirection: 'row',
    gap: 12,
    left: 0,
    paddingHorizontal: 14,
    paddingTop: 10,
    position: 'absolute',
    right: 0,
  },
  navButton: {
    alignItems: 'center',
    backgroundColor: colors.white,
    borderRadius: 8,
    flex: 1,
    paddingVertical: 12,
  },
  navButtonDisabled: {
    opacity: 0.42,
  },
  navButtonText: {
    color: colors.text,
    fontWeight: '800',
  },
});
