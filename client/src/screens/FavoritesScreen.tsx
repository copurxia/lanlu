import React, {useCallback, useEffect, useMemo, useRef, useState} from 'react';
import {
  FlatList,
  RefreshControl,
  SectionList,
  StyleSheet,
  Text,
  TextInput,
  TouchableOpacity,
  View,
} from 'react-native';
import {useNavigation} from '@react-navigation/native';
import type {NativeStackNavigationProp} from '@react-navigation/native-stack';
import {useSafeAreaInsets} from 'react-native-safe-area-context';
import {BookOpen, Heart} from 'lucide-react-native';

import {extractApiError, isNetworkError} from '../api/client';
import {
  isTankoubon,
  mediaItemId,
  mediaItemTitle,
  searchArchives,
} from '../api/lanlu';
import {ArchiveCard} from '../components/ArchiveCard';
import {ScreenState} from '../components/ScreenState';
import {useI18n} from '../i18n';
import {spacing} from '../theme/colors';
import {useTheme} from '../theme/ThemeContext';
import {useAuth} from '../auth/AuthContext';
import {useOfflineGeneralStore} from '../stores/offlineGeneralStore';
import type {Archive, MediaItem} from '../types/api';
import type {RootStackParamList} from '../navigation/types';

type Tab = 'favorites' | 'history';
type Nav = NativeStackNavigationProp<RootStackParamList>;
type Section = {title: string; data: MediaItem[]};
type TFunction = ReturnType<typeof useI18n>['t'];

function timeValue(item: MediaItem, tab: Tab): number {
  const raw = tab === 'favorites' ? item.favoritetime : (item as Archive).lastreadtime;
  if (typeof raw === 'number') return raw * 1000;
  if (typeof raw === 'string') {
    const ms = new Date(raw).getTime();
    return Number.isFinite(ms) ? ms : 0;
  }
  return 0;
}

function groupByTime(items: MediaItem[], tab: Tab, t: TFunction): Section[] {
  const groups = new Map<string, MediaItem[]>();
  const now = new Date();
  const today = now.toDateString();
  const yesterday = new Date(now.getTime() - 86400000).toDateString();
  for (const item of items) {
    const ms = timeValue(item, tab);
    const date = ms ? new Date(ms) : null;
    const label = !date
      ? t('favorites.earlier')
      : date.toDateString() === today
        ? t('favorites.today')
        : date.toDateString() === yesterday
          ? t('favorites.yesterday')
          : date.toLocaleDateString();
    const current = groups.get(label) || [];
    current.push(item);
    groups.set(label, current);
  }
  return Array.from(groups.entries()).map(([title, data]) => ({title, data}));
}

export function FavoritesScreen() {
  const navigation = useNavigation<Nav>();
  const {t} = useI18n();
  const {colors} = useTheme();
  const insets = useSafeAreaInsets();
  const {activeServer, isOffline} = useAuth();
  const serverId = activeServer?.id || '';
  const cacheFavorites = useOfflineGeneralStore(s => s.cacheFavorites);
  const getCachedFavorites = useOfflineGeneralStore(s => s.getCachedFavorites);
  const loadIdRef = useRef(0);
  const [tab, setTab] = useState<Tab>('favorites');
  const [favoriteItems, setFavoriteItems] = useState<MediaItem[]>([]);
  const [historyItems, setHistoryItems] = useState<MediaItem[]>([]);
  const [query, setQuery] = useState('');
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [error, setError] = useState('');

  const openDetail = useCallback(
    (item: MediaItem) => {
      if (isTankoubon(item)) {
        navigation.navigate('TankoubonDetail', {tankoubonId: item.tankoubon_id, tankoubon: item});
      } else {
        navigation.navigate('ArchiveDetail', {archiveId: item.arcid, archive: item});
      }
    },
    [navigation],
  );

  const openReader = useCallback(
    (item: MediaItem) => {
      if (isTankoubon(item)) {
        const firstArchive = item.children?.[0];
        if (firstArchive) {
          navigation.navigate('Reader', {
            archiveId: firstArchive,
            initialPage: 1,
            tankoubonId: item.tankoubon_id,
            children: item.children,
            childIndex: 0,
          });
        }
      } else {
        navigation.navigate('Reader', {archiveId: item.arcid});
      }
    },
    [navigation],
  );

  const loadFavorites = useCallback(async () => {
    if (isOffline && serverId) {
      const cached = getCachedFavorites(serverId);
      if (cached?.favorites.length) {
        setFavoriteItems(cached.favorites);
        return;
      }
    }

    try {
      const result = await searchArchives({
        favoriteonly: true,
        groupby_tanks: true,
        sortby: 'created_at',
        order: 'desc',
        page: 1,
        pageSize: 1000,
      });
      setFavoriteItems(result.data);
      if (serverId && result.data.length) {
        cacheFavorites(serverId, {favorites: result.data});
      }
    } catch (err) {
      if (serverId) {
        const cached = getCachedFavorites(serverId);
        if (cached?.favorites.length) {
          setFavoriteItems(cached.favorites);
          return;
        }
      }
      throw err;
    }
  }, [isOffline, serverId, cacheFavorites, getCachedFavorites]);

  const loadHistory = useCallback(async () => {
    if (isOffline && serverId) {
      const cached = getCachedFavorites(serverId);
      if (cached?.history.length) {
        setHistoryItems(cached.history);
        return;
      }
    }

    const result = await searchArchives({
      sortby: 'lastread',
      order: 'desc',
      page: 1,
      pageSize: 1000,
    });
    setHistoryItems(result.data);
    if (serverId) {
      cacheFavorites(serverId, {history: result.data});
    }
  }, [isOffline, serverId, cacheFavorites, getCachedFavorites]);

  const load = useCallback(async () => {
    const loadId = ++loadIdRef.current;
    setError('');
    if (!refreshing) setLoading(true);
    try {
      if (tab === 'favorites') await loadFavorites();
      else await loadHistory();
    } catch (err) {
      if (loadId !== loadIdRef.current) return;
      if (serverId && isNetworkError(err)) {
        const cached = getCachedFavorites(serverId);
        if (cached) {
          if (tab === 'favorites' && cached.favorites.length) {
            setFavoriteItems(cached.favorites);
            setError('');
          } else if (tab === 'history' && cached.history.length) {
            setHistoryItems(cached.history);
            setError('');
          } else {
            setError(extractApiError(err));
          }
        } else {
          setError(extractApiError(err));
        }
      } else {
        setError(extractApiError(err));
      }
    } finally {
      if (loadId === loadIdRef.current) {
        setLoading(false);
        setRefreshing(false);
      }
    }
  }, [loadFavorites, loadHistory, refreshing, tab, serverId, getCachedFavorites]);

  useEffect(() => {
    load().catch(err => console.warn('Failed to load library:', err));
  }, [load]);

  const refresh = useCallback(() => {
    setRefreshing(true);
    load().catch(() => {});
  }, [load]);

  useEffect(() => {
    load().catch(() => {});
  }, [load]);

  const filteredItems = useMemo(() => {
    const items = tab === 'favorites' ? favoriteItems : historyItems;
    const normalized = query.trim().toLowerCase();
    if (!normalized) return items;
    return items.filter(item => mediaItemTitle(item).toLowerCase().includes(normalized));
  }, [favoriteItems, historyItems, query, tab]);

  const sections = useMemo(() => groupByTime(filteredItems, tab, t), [filteredItems, t, tab]);

  const styles = useMemo(
    () =>
      StyleSheet.create({
        screen: {
          backgroundColor: colors.background,
          flex: 1,
        },
        header: {
          gap: spacing.md,
          padding: spacing.lg,
        },
        tabs: {
          backgroundColor: colors.surfaceMuted,
          borderRadius: 8,
          flexDirection: 'row',
          padding: 3,
        },
        tab: {
          alignItems: 'center',
          borderRadius: 7,
          flex: 1,
          flexDirection: 'row',
          gap: 6,
          justifyContent: 'center',
          paddingVertical: 9,
        },
        tabActive: {
          backgroundColor: colors.surface,
        },
        tabText: {
          color: colors.textMuted,
          fontWeight: '800',
        },
        tabTextActive: {
          color: colors.primary,
        },
        searchInput: {
          backgroundColor: colors.surface,
          borderColor: colors.border,
          borderRadius: 8,
          borderWidth: StyleSheet.hairlineWidth,
          color: colors.text,
          fontSize: 15,
          includeFontPadding: false,
          minHeight: 42,
          paddingHorizontal: 12,
          paddingVertical: 0,
          textAlignVertical: 'center',
        },
        inlineError: {
          color: colors.danger,
          paddingHorizontal: spacing.lg,
          paddingBottom: spacing.sm,
        },
        content: {
          paddingHorizontal: spacing.lg,
          paddingBottom: spacing.lg + 56,
        },
        emptyContent: {
          flexGrow: 1,
        },
        sectionHeader: {
          alignItems: 'center',
          flexDirection: 'row',
          justifyContent: 'space-between',
          marginBottom: spacing.md,
          marginTop: spacing.md,
        },
        sectionTitle: {
          color: colors.text,
          fontSize: 18,
          fontWeight: '800',
        },
        sectionCount: {
          color: colors.textMuted,
          fontSize: 13,
          fontWeight: '700',
        },
        column: {
          gap: spacing.md,
        },
      }),
    [colors],
  );

  if (loading && !refreshing && filteredItems.length === 0) {
    return <ScreenState loading title={t('favorites.loading')} />;
  }

  return (
    <View
      style={[
        styles.screen,
        {
          paddingTop: isOffline ? 0 : insets.top,
          paddingLeft: insets.left,
          paddingRight: insets.right,
        },
      ]}>
      <View style={styles.header}>
        <View style={styles.tabs}>
          <TouchableOpacity
            onPress={() => setTab('favorites')}
            style={[styles.tab, tab === 'favorites' && styles.tabActive]}>
            <Heart color={tab === 'favorites' ? colors.primary : colors.textMuted} size={16} />
            <Text style={[styles.tabText, tab === 'favorites' && styles.tabTextActive]}>
              {t('favorites.favorites')}
            </Text>
          </TouchableOpacity>
          <TouchableOpacity
            onPress={() => setTab('history')}
            style={[styles.tab, tab === 'history' && styles.tabActive]}>
            <BookOpen color={tab === 'history' ? colors.primary : colors.textMuted} size={16} />
            <Text style={[styles.tabText, tab === 'history' && styles.tabTextActive]}>
              {t('favorites.history')}
            </Text>
          </TouchableOpacity>
        </View>
        <TextInput
          autoCapitalize="none"
          autoCorrect={false}
          onChangeText={setQuery}
          placeholder={t('favorites.searchPlaceholder')}
          placeholderTextColor={colors.textMuted}
          style={styles.searchInput}
          value={query}
        />
      </View>

      {error ? <Text style={styles.inlineError}>{error}</Text> : null}

      <SectionList
        contentContainerStyle={[styles.content, sections.length === 0 && styles.emptyContent]}
        keyExtractor={item => mediaItemId(item)}
        refreshControl={<RefreshControl refreshing={refreshing} onRefresh={refresh} />}
        renderItem={() => null}
        renderSectionFooter={({section}) => (
          <FlatList
            columnWrapperStyle={styles.column}
            data={section.data}
            keyExtractor={item => mediaItemId(item)}
            numColumns={2}
            renderItem={({item}) => (
              <ArchiveCard archive={item} onChanged={refresh} onOpenDetail={() => openDetail(item)} onOpenReader={() => openReader(item)} />
            )}
            scrollEnabled={false}
          />
        )}
        renderSectionHeader={({section}) => (
          <View style={styles.sectionHeader}>
            <Text style={styles.sectionTitle}>{section.title}</Text>
            <Text style={styles.sectionCount}>{section.data.length}</Text>
          </View>
        )}
        sections={sections}
        ListEmptyComponent={
          <ScreenState
            title={tab === 'favorites' ? t('favorites.noFavorites') : t('favorites.noHistory')}
            message={query ? t('favorites.tryAnotherSearch') : t('favorites.emptyHint')}
          />
        }
      />
    </View>
  );
}
