import React, {useCallback, useEffect, useMemo, useState} from 'react';
import {
  FlatList,
  RefreshControl,
  ScrollView,
  StyleSheet,
  Text,
  TextInput,
  TouchableOpacity,
  View,
} from 'react-native';
import type {NativeStackNavigationProp} from '@react-navigation/native-stack';
import {useNavigation} from '@react-navigation/native';
import {
  ChevronRight,
  Grid2X2,
  List,
  MessageCircle,
  MessageSquareText,
  Rows3,
} from 'lucide-react-native';

import {extractApiError} from '../api/client';
import {
  fetchCategories,
  fetchDiscover,
  isTankoubon,
  mediaItemId,
  searchArchives,
} from '../api/lanlu';
import {ArchiveCard} from '../components/ArchiveCard';
import {ScreenState} from '../components/ScreenState';
import {useI18n} from '../i18n';
import {
  DEFAULT_HOME_VIEW_MODE,
  HomeViewMode,
  loadHomeViewMode,
  saveHomeViewMode,
} from '../storage/preferences';
import {colors, spacing} from '../theme/colors';
import type {Category, MediaItem} from '../types/api';
import type {RootStackParamList} from '../navigation/types';

const PAGE_SIZE = 20;
const ROW_SIZE = 10;
const VIEW_MODES: HomeViewMode[] = [
  'category-rows',
  'masonry',
  'list',
  'tweet',
  'channel',
];

type Nav = NativeStackNavigationProp<RootStackParamList>;
type HomeRow = {
  key: string;
  title: string;
  icon?: string;
  category?: Category;
  items: MediaItem[];
};

function viewModeLabel(mode: HomeViewMode, t: ReturnType<typeof useI18n>['t']) {
  switch (mode) {
    case 'category-rows':
      return t('home.rows');
    case 'masonry':
      return t('home.grid');
    case 'list':
      return t('home.list');
    case 'tweet':
      return t('home.feed');
    case 'channel':
      return t('home.channel');
  }
}

function ViewModeIcon({mode}: {mode: HomeViewMode}) {
  const props = {color: colors.text, size: 18};
  if (mode === 'masonry') return <Grid2X2 {...props} />;
  if (mode === 'list') return <List {...props} />;
  if (mode === 'tweet') return <MessageSquareText {...props} />;
  if (mode === 'channel') return <MessageCircle {...props} />;
  return <Rows3 {...props} />;
}

export function HomeScreen() {
  const {t} = useI18n();
  const navigation = useNavigation<Nav>();
  const [viewMode, setViewMode] = useState<HomeViewMode>(DEFAULT_HOME_VIEW_MODE);
  const [items, setItems] = useState<MediaItem[]>([]);
  const [randomItems, setRandomItems] = useState<MediaItem[]>([]);
  const [categories, setCategories] = useState<Category[]>([]);
  const [categoryRows, setCategoryRows] = useState<Record<string, MediaItem[]>>({});
  const [filter, setFilter] = useState('');
  const [submittedFilter, setSubmittedFilter] = useState('');
  const [selectedCategory, setSelectedCategory] = useState<Category | null>(null);
  const [sortby, setSortby] = useState('created_at');
  const [page, setPage] = useState(1);
  const [total, setTotal] = useState(0);
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [loadingMore, setLoadingMore] = useState(false);
  const [error, setError] = useState('');

  const showRows = viewMode === 'category-rows' && !submittedFilter && !selectedCategory;

  const openItem = useCallback(
    (item: MediaItem) => {
      if (isTankoubon(item)) {
        const firstArchive = item.children?.[0];
        if (firstArchive) {
          navigation.navigate('Reader', {archiveId: firstArchive, initialPage: 1});
        }
        return;
      }
      navigation.navigate('ArchiveDetail', {archiveId: item.arcid, archive: item});
    },
    [navigation],
  );

  const loadFeed = useCallback(
    async (nextPage: number, mode: 'replace' | 'append') => {
      if (mode === 'append') setLoadingMore(true);
      else if (!refreshing) setLoading(true);
      setError('');
      try {
        const result = await searchArchives({
          filter: submittedFilter,
          page: nextPage,
          pageSize: PAGE_SIZE,
          sortby,
          order: 'desc',
          groupby_tanks: true,
          category_id: selectedCategory?.catid,
        });
        setTotal(result.recordsFiltered || result.recordsTotal || 0);
        setPage(nextPage);
        setItems(current => (mode === 'append' ? [...current, ...result.data] : result.data));
      } catch (err) {
        setError(extractApiError(err));
      } finally {
        setLoading(false);
        setRefreshing(false);
        setLoadingMore(false);
      }
    },
    [refreshing, selectedCategory, sortby, submittedFilter],
  );

  const loadRows = useCallback(async () => {
    setLoading(true);
    setError('');
    try {
      const [cats, discover] = await Promise.all([
        fetchCategories(),
        fetchDiscover(ROW_SIZE).catch(() => []),
      ]);
      const enabled = cats.filter(category => category.enabled !== false);
      setCategories(enabled);
      setRandomItems(discover);

      if (enabled.length) {
        const rows: Record<string, MediaItem[]> = {};
        for (const category of enabled) {
          rows[String(category.id)] = [];
          rows[category.catid] = [];
        }

        const categoryIds = enabled
          .map(category => String(category.id || '').trim())
          .filter(Boolean);
        if (categoryIds.length) {
          const result = await searchArchives({
            page: 1,
            pageSize: ROW_SIZE,
            sortby,
            order: 'desc',
            groupby_tanks: true,
            category_ids: categoryIds.join(','),
            aggregate_by: 'category',
          });
          for (const group of result.groups || []) {
            if (!group.category_id) continue;
            rows[group.category_id] = group.data || [];
          }
        }

        const missing = enabled.filter(category => {
          const idItems = rows[String(category.id)] || [];
          const catidItems = rows[category.catid] || [];
          return idItems.length === 0 && catidItems.length === 0;
        });
        if (missing.length) {
          const fallbackResults = await Promise.allSettled(
            missing.map(async category => {
              const result = await searchArchives({
                page: 1,
                pageSize: ROW_SIZE,
                sortby,
                order: 'desc',
                groupby_tanks: true,
                category_id: category.catid,
              });
              return {category, items: result.data};
            }),
          );
          for (const result of fallbackResults) {
            if (result.status !== 'fulfilled') continue;
            const {category, items: rowItems} = result.value;
            rows[String(category.id)] = rowItems;
            rows[category.catid] = rowItems;
          }
        }
        setCategoryRows(rows);
      } else {
        setCategoryRows({});
      }
    } catch (err) {
      setError(extractApiError(err));
    } finally {
      setLoading(false);
      setRefreshing(false);
    }
  }, [sortby]);

  const load = useCallback(
    async (nextPage = 1, mode: 'replace' | 'append' = 'replace') => {
      if (showRows) await loadRows();
      else await loadFeed(nextPage, mode);
    },
    [loadFeed, loadRows, showRows],
  );

  useEffect(() => {
    loadHomeViewMode()
      .then(setViewMode)
      .catch(() => setViewMode(DEFAULT_HOME_VIEW_MODE));
  }, []);

  useEffect(() => {
    load(1, 'replace').catch(err => console.warn('Failed to load home:', err));
  }, [load]);

  const refresh = useCallback(() => {
    setRefreshing(true);
    load(1, 'replace').catch(err => console.warn('Failed to refresh home:', err));
  }, [load]);

  function submitSearch() {
    setSubmittedFilter(filter.trim());
    setSelectedCategory(null);
  }

  function cycleViewMode() {
    const currentIndex = VIEW_MODES.indexOf(viewMode);
    const next = VIEW_MODES[(currentIndex + 1) % VIEW_MODES.length];
    setViewMode(next);
    saveHomeViewMode(next).catch(err => console.warn('Failed to save view mode:', err));
    setItems([]);
    setPage(1);
  }

  function openCategory(category: Category) {
    const nextMode: HomeViewMode = 'masonry';
    setSelectedCategory(category);
    setSubmittedFilter('');
    setFilter('');
    setViewMode(nextMode);
    saveHomeViewMode(nextMode).catch(err => console.warn('Failed to save view mode:', err));
    setItems([]);
    setPage(1);
  }

  function clearCategory() {
    setSelectedCategory(null);
    setItems([]);
    setPage(1);
  }

  function loadMore() {
    if (showRows || loading || loadingMore || items.length >= total) return;
    loadFeed(page + 1, 'append').catch(err => console.warn('Failed to load more:', err));
  }

  const itemVariant = useMemo(() => {
    if (viewMode === 'list') return 'list';
    if (viewMode === 'tweet') return 'tweet';
    if (viewMode === 'channel') return 'channel';
    return 'grid';
  }, [viewMode]);

  const homeRows = useMemo<HomeRow[]>(() => {
    const rows: HomeRow[] = [];
    if (randomItems.length) {
      rows.push({key: 'discover', title: t('home.random'), items: randomItems});
    }
    for (const category of categories) {
      const itemsForCategory =
        categoryRows[String(category.id)] ||
        categoryRows[category.catid] ||
        [];
      rows.push({
        key: `category:${category.catid || category.id}`,
        title: category.name,
        icon: category.icon,
        category,
        items: itemsForCategory,
      });
    }
    return rows;
  }, [categories, categoryRows, randomItems, t]);

  if (loading && !refreshing && !items.length && !showRows) {
    return <ScreenState loading title={t('home.loading')} />;
  }

  if (error && !items.length && !showRows) {
    return (
      <ScreenState
        title={t('home.loadFailed')}
        message={error}
        actionLabel={t('common.retry')}
        onAction={() => load(1, 'replace').catch(() => undefined)}
      />
    );
  }

  const renderRow = (row: HomeRow) => {
    return (
      <View key={row.key} style={styles.rowSection}>
        <View style={styles.rowHeader}>
          {row.icon ? <Text style={styles.sectionIcon}>{row.icon}</Text> : null}
          <Text numberOfLines={1} style={styles.sectionTitle}>{row.title}</Text>
          {row.category ? (
            <TouchableOpacity
              accessibilityRole="button"
              onPress={() => openCategory(row.category as Category)}
              style={styles.viewMoreButton}>
              <Text style={styles.viewMoreText}>{t('common.more')}</Text>
              <ChevronRight color={colors.textMuted} size={16} />
            </TouchableOpacity>
          ) : null}
        </View>
        {row.items.length ? (
        <ScrollView
          horizontal
          contentContainerStyle={styles.rowScroller}
          showsHorizontalScrollIndicator={false}>
          {row.items.map(item => (
            <ArchiveCard
              archive={item}
              key={mediaItemId(item)}
              variant="row"
              onPress={() => openItem(item)}
            />
          ))}
        </ScrollView>
        ) : loading ? (
          <View style={styles.rowSkeleton}>
            {Array.from({length: 4}).map((_, index) => (
              <View key={index} style={styles.skeletonCard}>
                <View style={styles.skeletonCover} />
                <View style={styles.skeletonLine} />
                <View style={[styles.skeletonLine, styles.skeletonLineShort]} />
              </View>
            ))}
          </View>
        ) : (
          <Text style={styles.emptyRowText}>{t('home.noArchives')}</Text>
        )}
      </View>
    );
  };

  return (
    <View style={styles.screen}>
      <View style={styles.toolbar}>
        <TextInput
          autoCapitalize="none"
          autoCorrect={false}
          onChangeText={setFilter}
          onSubmitEditing={submitSearch}
          placeholder={t('common.search')}
          returnKeyType="search"
          style={styles.searchInput}
          value={filter}
        />
        <TouchableOpacity onPress={cycleViewMode} style={styles.modeButton}>
          <ViewModeIcon mode={viewMode} />
          <Text style={styles.modeButtonText}>{viewModeLabel(viewMode, t)}</Text>
        </TouchableOpacity>
      </View>

      <View style={styles.sortRow}>
        {selectedCategory ? (
          <TouchableOpacity onPress={clearCategory} style={styles.categoryChip}>
            <Text numberOfLines={1} style={styles.categoryChipText}>
              {selectedCategory.icon ? `${selectedCategory.icon} ` : ''}{selectedCategory.name}
            </Text>
            <Text style={styles.categoryChipClear}>x</Text>
          </TouchableOpacity>
        ) : null}
        {['created_at', 'lastread', 'release_at', 'updated_at'].map(option => (
          <TouchableOpacity
            key={option}
            onPress={() => setSortby(option)}
            style={[styles.sortChip, sortby === option && styles.sortChipActive]}>
            <Text style={[styles.sortChipText, sortby === option && styles.sortChipTextActive]}>
              {option === 'created_at'
                ? t('home.created')
                : option === 'lastread'
                  ? t('home.lastRead')
                  : option === 'release_at'
                    ? t('home.release')
                    : t('home.updated')}
            </Text>
          </TouchableOpacity>
        ))}
      </View>

      {error ? <Text style={styles.inlineError}>{error}</Text> : null}

      {showRows ? (
        <ScrollView
          refreshControl={<RefreshControl refreshing={refreshing} onRefresh={refresh} />}
          contentContainerStyle={styles.rowsContent}>
          {loading && !randomItems.length ? (
            <ScreenState loading title={t('home.loadingRecommendations')} />
          ) : null}
          {homeRows.map(renderRow)}
          {!loading && homeRows.length === 0 ? (
            <ScreenState title={t('home.noCategories')} message={t('home.useAnotherView')} />
          ) : null}
        </ScrollView>
      ) : (
        <FlatList
          contentContainerStyle={[
            styles.listContent,
            items.length === 0 && styles.emptyList,
          ]}
          data={items}
          key={`${viewMode}:${itemVariant}`}
          keyExtractor={item => mediaItemId(item)}
          numColumns={itemVariant === 'grid' ? 2 : 1}
          columnWrapperStyle={itemVariant === 'grid' ? styles.column : undefined}
          onEndReached={loadMore}
          onEndReachedThreshold={0.5}
          refreshControl={<RefreshControl refreshing={refreshing} onRefresh={refresh} />}
          renderItem={({item}) => (
            <ArchiveCard archive={item} variant={itemVariant} onPress={() => openItem(item)} />
          )}
          ListEmptyComponent={<ScreenState title={t('home.noArchives')} message={t('home.tryAnotherSearch')} />}
          ListFooterComponent={
            loadingMore ? <Text style={styles.footerText}>{t('common.loading')}</Text> : null
          }
        />
      )}
    </View>
  );
}

const styles = StyleSheet.create({
  screen: {
    backgroundColor: colors.background,
    flex: 1,
  },
  toolbar: {
    alignItems: 'center',
    flexDirection: 'row',
    gap: spacing.sm,
    paddingHorizontal: spacing.lg,
    paddingTop: spacing.md,
    paddingBottom: spacing.sm,
  },
  searchInput: {
    backgroundColor: colors.surface,
    borderColor: colors.border,
    borderRadius: 8,
    borderWidth: StyleSheet.hairlineWidth,
    color: colors.text,
    flex: 1,
    fontSize: 15,
    paddingHorizontal: 12,
    paddingVertical: 10,
  },
  modeButton: {
    alignItems: 'center',
    backgroundColor: colors.surface,
    borderColor: colors.border,
    borderRadius: 8,
    borderWidth: StyleSheet.hairlineWidth,
    flexDirection: 'row',
    gap: 6,
    minHeight: 42,
    paddingHorizontal: 10,
  },
  modeButtonText: {
    color: colors.text,
    fontSize: 12,
    fontWeight: '800',
  },
  sortRow: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: spacing.sm,
    paddingHorizontal: spacing.lg,
    paddingBottom: spacing.sm,
  },
  categoryChip: {
    alignItems: 'center',
    backgroundColor: colors.primaryMuted,
    borderColor: colors.primary,
    borderRadius: 999,
    borderWidth: StyleSheet.hairlineWidth,
    flexDirection: 'row',
    gap: spacing.xs,
    maxWidth: '100%',
    paddingHorizontal: 10,
    paddingVertical: 6,
  },
  categoryChipText: {
    color: colors.primary,
    fontSize: 12,
    fontWeight: '800',
    maxWidth: 220,
  },
  categoryChipClear: {
    color: colors.primary,
    fontSize: 12,
    fontWeight: '900',
  },
  sortChip: {
    backgroundColor: colors.surface,
    borderColor: colors.border,
    borderRadius: 999,
    borderWidth: StyleSheet.hairlineWidth,
    paddingHorizontal: 10,
    paddingVertical: 6,
  },
  sortChipActive: {
    backgroundColor: colors.primaryMuted,
    borderColor: colors.primary,
  },
  sortChipText: {
    color: colors.textMuted,
    fontSize: 12,
    fontWeight: '700',
  },
  sortChipTextActive: {
    color: colors.primary,
  },
  inlineError: {
    color: colors.danger,
    fontSize: 13,
    paddingHorizontal: spacing.lg,
    paddingBottom: spacing.sm,
  },
  rowsContent: {
    paddingTop: spacing.sm,
    paddingBottom: spacing.xl,
  },
  rowSection: {
    marginBottom: spacing.xl,
  },
  rowHeader: {
    alignItems: 'center',
    flexDirection: 'row',
    gap: spacing.sm,
    paddingHorizontal: spacing.lg,
    marginBottom: spacing.md,
  },
  sectionIcon: {
    fontSize: 18,
  },
  sectionTitle: {
    color: colors.text,
    flex: 1,
    fontSize: 18,
    fontWeight: '800',
  },
  viewMoreButton: {
    alignItems: 'center',
    flexDirection: 'row',
    gap: 2,
    minHeight: 32,
    paddingLeft: spacing.sm,
  },
  viewMoreText: {
    color: colors.textMuted,
    fontSize: 13,
    fontWeight: '800',
  },
  rowScroller: {
    gap: spacing.md,
    paddingLeft: spacing.lg,
    paddingRight: spacing.lg,
  },
  rowSkeleton: {
    flexDirection: 'row',
    gap: spacing.md,
    paddingHorizontal: spacing.lg,
  },
  skeletonCard: {
    width: 136,
  },
  skeletonCover: {
    aspectRatio: 0.72,
    backgroundColor: colors.surfaceMuted,
    borderRadius: 8,
  },
  skeletonLine: {
    backgroundColor: colors.surfaceMuted,
    borderRadius: 999,
    height: 12,
    marginTop: spacing.sm,
  },
  skeletonLineShort: {
    width: '64%',
  },
  emptyRowText: {
    color: colors.textMuted,
    fontSize: 13,
    paddingHorizontal: spacing.lg,
  },
  emptyList: {
    flexGrow: 1,
  },
  listContent: {
    flexGrow: 1,
    paddingHorizontal: spacing.lg,
    paddingBottom: spacing.lg,
  },
  column: {
    gap: spacing.md,
  },
  footerText: {
    color: colors.textMuted,
    padding: 16,
    textAlign: 'center',
  },
});
