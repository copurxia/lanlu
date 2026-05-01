import React, {useCallback, useEffect, useMemo, useState} from 'react';
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
import {BookOpen, Heart} from 'lucide-react-native';

import {extractApiError} from '../api/client';
import {
  fetchFavoriteTankoubons,
  isTankoubon,
  mediaItemId,
  mediaItemTitle,
  searchArchives,
} from '../api/lanlu';
import {ArchiveCard} from '../components/ArchiveCard';
import {ScreenState} from '../components/ScreenState';
import {useI18n} from '../i18n';
import {colors, spacing} from '../theme/colors';
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
  const [tab, setTab] = useState<Tab>('favorites');
  const [favoriteItems, setFavoriteItems] = useState<MediaItem[]>([]);
  const [historyItems, setHistoryItems] = useState<MediaItem[]>([]);
  const [query, setQuery] = useState('');
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [error, setError] = useState('');

  const openItem = useCallback(
    (item: MediaItem) => {
      if (isTankoubon(item)) {
        const firstArchive = item.children?.[0];
        if (firstArchive) navigation.navigate('Reader', {archiveId: firstArchive, initialPage: 1});
        return;
      }
      navigation.navigate('ArchiveDetail', {archiveId: item.arcid, archive: item});
    },
    [navigation],
  );

  const loadFavorites = useCallback(async () => {
    const [archivesResult, tankoubonsResult] = await Promise.allSettled([
      searchArchives({
        favoriteonly: true,
        groupby_tanks: false,
        sortby: 'created_at',
        order: 'desc',
        page: 1,
        pageSize: 1000,
      }),
      fetchFavoriteTankoubons(),
    ]);
    const archives =
      archivesResult.status === 'fulfilled' ? archivesResult.value.data : [];
    const tankoubons =
      tankoubonsResult.status === 'fulfilled' ? tankoubonsResult.value : [];
    setFavoriteItems(
      [...archives, ...tankoubons].sort(
        (a, b) => timeValue(b, 'favorites') - timeValue(a, 'favorites'),
      ),
    );
    if (archivesResult.status === 'rejected') throw archivesResult.reason;
  }, []);

  const loadHistory = useCallback(async () => {
    const result = await searchArchives({
      sortby: 'lastread',
      order: 'desc',
      page: 1,
      pageSize: 1000,
    });
    setHistoryItems(result.data);
  }, []);

  const load = useCallback(async () => {
    setError('');
    if (!refreshing) setLoading(true);
    try {
      if (tab === 'favorites') await loadFavorites();
      else await loadHistory();
    } catch (err) {
      setError(extractApiError(err));
    } finally {
      setLoading(false);
      setRefreshing(false);
    }
  }, [loadFavorites, loadHistory, refreshing, tab]);

  useEffect(() => {
    load().catch(err => console.warn('Failed to load library:', err));
  }, [load]);

  const refresh = useCallback(() => {
    setRefreshing(true);
    load().catch(err => console.warn('Failed to refresh library:', err));
  }, [load]);

  const filteredItems = useMemo(() => {
    const items = tab === 'favorites' ? favoriteItems : historyItems;
    const normalized = query.trim().toLowerCase();
    if (!normalized) return items;
    return items.filter(item => mediaItemTitle(item).toLowerCase().includes(normalized));
  }, [favoriteItems, historyItems, query, tab]);

  const sections = useMemo(() => groupByTime(filteredItems, tab, t), [filteredItems, t, tab]);

  if (loading && !refreshing && filteredItems.length === 0) {
    return <ScreenState loading title={t('favorites.loading')} />;
  }

  return (
    <View style={styles.screen}>
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
              <ArchiveCard archive={item} onChanged={refresh} onPress={() => openItem(item)} />
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

const styles = StyleSheet.create({
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
    paddingHorizontal: 12,
    paddingVertical: 10,
  },
  inlineError: {
    color: colors.danger,
    paddingHorizontal: spacing.lg,
    paddingBottom: spacing.sm,
  },
  content: {
    paddingHorizontal: spacing.lg,
    paddingBottom: spacing.lg,
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
});
