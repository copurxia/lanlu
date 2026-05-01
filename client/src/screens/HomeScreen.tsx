import React, {useCallback, useEffect, useMemo, useRef, useState} from 'react';
import {
  FlatList,
  Modal,
  RefreshControl,
  ScrollView,
  StyleSheet,
  Switch,
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
  Search,
  SlidersHorizontal,
  X,
} from 'lucide-react-native';

import {extractApiError} from '../api/client';
import {
  fetchCategories,
  fetchDiscover,
  fetchTagAutocomplete,
  isTankoubon,
  mediaItemId,
  searchArchives,
  type TagSuggestion,
} from '../api/lanlu';
import {ArchiveCard} from '../components/ArchiveCard';
import {ScreenState} from '../components/ScreenState';
import {useI18n} from '../i18n';
import {appendDiagnosticLog} from '../storage/diagnostics';
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
  const {language, t} = useI18n();
  const navigation = useNavigation<Nav>();
  const [viewMode, setViewMode] = useState<HomeViewMode>(DEFAULT_HOME_VIEW_MODE);
  const [items, setItems] = useState<MediaItem[]>([]);
  const [randomItems, setRandomItems] = useState<MediaItem[]>([]);
  const [categories, setCategories] = useState<Category[]>([]);
  const [categoryRows, setCategoryRows] = useState<Record<string, MediaItem[]>>({});
  const [filter, setFilter] = useState('');
  const [submittedFilter, setSubmittedFilter] = useState('');
  const [searchVersion, setSearchVersion] = useState(0);
  const [selectedCategory, setSelectedCategory] = useState<Category | null>(null);
  const [sortby, setSortby] = useState('created_at');
  const [sortOrder, setSortOrder] = useState<'asc' | 'desc'>('desc');
  const [dateFrom, setDateFrom] = useState('');
  const [dateTo, setDateTo] = useState('');
  const [newOnly, setNewOnly] = useState(false);
  const [untaggedOnly, setUntaggedOnly] = useState(false);
  const [favoriteOnly, setFavoriteOnly] = useState(false);
  const [groupByTanks, setGroupByTanks] = useState(true);
  const [filtersOpen, setFiltersOpen] = useState(false);
  const [suggestions, setSuggestions] = useState<TagSuggestion[]>([]);
  const [suggestionsLoading, setSuggestionsLoading] = useState(false);
  const [page, setPage] = useState(1);
  const [total, setTotal] = useState(0);
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [loadingMore, setLoadingMore] = useState(false);
  const [error, setError] = useState('');
  const requestIdRef = useRef(0);

  const hasAdvancedFilters = Boolean(
    dateFrom || dateTo || newOnly || untaggedOnly || favoriteOnly || !groupByTanks,
  );
  const showRows = viewMode === 'category-rows' && !submittedFilter && !selectedCategory && !hasAdvancedFilters;

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
      const requestId = requestIdRef.current + 1;
      requestIdRef.current = requestId;
      const activeFilter = submittedFilter.trim();
      const params = {
        filter: activeFilter,
        page: nextPage,
        pageSize: PAGE_SIZE,
        sortby: activeFilter && sortby === 'created_at' ? 'relevance' : sortby,
        order: sortOrder,
        groupby_tanks: groupByTanks,
        category_id: selectedCategory?.catid,
        date_from: dateFrom,
        date_to: dateTo,
        newonly: newOnly,
        untaggedonly: untaggedOnly,
        favoriteonly: favoriteOnly,
        lang: language,
      };
      if (mode === 'append') setLoadingMore(true);
      else if (!refreshing) setLoading(true);
      setError('');
      try {
        await appendDiagnosticLog('home.feed.start', {requestId, mode, params});
        const result = await searchArchives(params);
        if (requestId !== requestIdRef.current) {
          await appendDiagnosticLog('home.feed.stale', {
            requestId,
            activeRequestId: requestIdRef.current,
            dataCount: result.data.length,
          });
          return;
        }
        setTotal(result.recordsFiltered || result.recordsTotal || 0);
        setPage(nextPage);
        setItems(current => (mode === 'append' ? [...current, ...result.data] : result.data));
        await appendDiagnosticLog('home.feed.done', {
          requestId,
          mode,
          dataCount: result.data.length,
          recordsFiltered: result.recordsFiltered,
          recordsTotal: result.recordsTotal,
        });
      } catch (err) {
        if (requestId !== requestIdRef.current) return;
        await appendDiagnosticLog('home.feed.error', {
          requestId,
          message: err instanceof Error ? err.message : String(err),
        });
        setError(extractApiError(err));
      } finally {
        if (requestId !== requestIdRef.current) return;
        setLoading(false);
        setRefreshing(false);
        setLoadingMore(false);
      }
    },
    [
      dateFrom,
      dateTo,
      favoriteOnly,
      groupByTanks,
      language,
      newOnly,
      refreshing,
      selectedCategory,
      sortOrder,
      sortby,
      submittedFilter,
      untaggedOnly,
    ],
  );

  const loadRows = useCallback(async () => {
    const requestId = requestIdRef.current + 1;
    requestIdRef.current = requestId;
    setLoading(true);
    setError('');
    try {
      const [cats, discover] = await Promise.all([
        fetchCategories(),
        fetchDiscover(ROW_SIZE).catch(() => []),
      ]);
      if (requestId !== requestIdRef.current) return;
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
            order: sortOrder,
            groupby_tanks: groupByTanks,
            category_ids: categoryIds.join(','),
            aggregate_by: 'category',
            date_from: dateFrom,
            date_to: dateTo,
            newonly: newOnly,
            untaggedonly: untaggedOnly,
            favoriteonly: favoriteOnly,
            lang: language,
          });
          if (requestId !== requestIdRef.current) return;
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
                order: sortOrder,
                groupby_tanks: groupByTanks,
                category_id: category.catid,
                date_from: dateFrom,
                date_to: dateTo,
                newonly: newOnly,
                untaggedonly: untaggedOnly,
                favoriteonly: favoriteOnly,
                lang: language,
              });
              return {category, items: result.data};
            }),
          );
          if (requestId !== requestIdRef.current) return;
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
      if (requestId !== requestIdRef.current) return;
      setError(extractApiError(err));
    } finally {
      if (requestId !== requestIdRef.current) return;
      setLoading(false);
      setRefreshing(false);
    }
  }, [dateFrom, dateTo, favoriteOnly, groupByTanks, language, newOnly, sortOrder, sortby, untaggedOnly]);

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
  }, [load, searchVersion]);

  const refresh = useCallback(() => {
    setRefreshing(true);
    load(1, 'replace').catch(err => console.warn('Failed to refresh home:', err));
  }, [load]);

  useEffect(() => {
    const words = filter.trim().split(/\s+/).filter(Boolean);
    const lastWord = words[words.length - 1] || '';
    if (!lastWord) {
      setSuggestions([]);
      setSuggestionsLoading(false);
      return;
    }

    let cancelled = false;
    setSuggestionsLoading(true);
    const timer = setTimeout(() => {
      fetchTagAutocomplete(lastWord, language, 10)
        .then(result => {
          if (!cancelled) setSuggestions(result);
        })
        .catch(autocompleteError => {
          if (cancelled) return;
          setSuggestions([]);
          appendDiagnosticLog('home.search.autocomplete.error', {
            query: lastWord,
            message: autocompleteError instanceof Error ? autocompleteError.message : String(autocompleteError),
          }).catch(() => undefined);
        })
        .finally(() => {
          if (!cancelled) setSuggestionsLoading(false);
        });
    }, 220);

    return () => {
      cancelled = true;
      clearTimeout(timer);
    };
  }, [filter, language]);

  function selectSuggestion(suggestion: TagSuggestion) {
    const words = filter.trim().split(/\s+/).filter(Boolean);
    const nextWords = words.length ? words.slice(0, -1) : [];
    nextWords.push(suggestion.value);
    setFilter(`${nextWords.join(' ')} `);
    setSuggestions([]);
  }

  function submitSearch() {
    const nextFilter = filter.trim();
    requestIdRef.current += 1;
    appendDiagnosticLog('home.search.submit', {
      filter: nextFilter,
      previousFilter: submittedFilter,
      sortby,
      sortOrder,
      viewMode,
      selectedCategory: selectedCategory?.catid,
      dateFrom,
      dateTo,
      newOnly,
      untaggedOnly,
      favoriteOnly,
      groupByTanks,
      nextRequestSeed: requestIdRef.current,
    }).catch(logError => console.warn('Failed to log search submit:', logError));
    setItems([]);
    setPage(1);
    setTotal(0);
    setError('');
    setLoading(Boolean(nextFilter));
    setSubmittedFilter(nextFilter);
    setSelectedCategory(null);
    setSearchVersion(version => version + 1);
  }

  function applyFilters() {
    setFiltersOpen(false);
    setItems([]);
    setPage(1);
    setTotal(0);
    setSearchVersion(version => version + 1);
  }

  function resetFilters() {
    setSortby('created_at');
    setSortOrder('desc');
    setDateFrom('');
    setDateTo('');
    setNewOnly(false);
    setUntaggedOnly(false);
    setFavoriteOnly(false);
    setGroupByTanks(true);
    setFiltersOpen(false);
    setItems([]);
    setPage(1);
    setTotal(0);
    setSearchVersion(version => version + 1);
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

  if (loading && !refreshing && !items.length && !showRows && !submittedFilter) {
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
        <TouchableOpacity
          accessibilityLabel={t('common.search')}
          accessibilityRole="button"
          onPress={submitSearch}
          style={styles.searchButton}>
          <Search color={colors.text} size={18} />
        </TouchableOpacity>
        <TouchableOpacity
          accessibilityLabel={t('common.filter')}
          accessibilityRole="button"
          onPress={() => setFiltersOpen(true)}
          style={[styles.searchButton, hasAdvancedFilters && styles.filterButtonActive]}>
          <SlidersHorizontal color={hasAdvancedFilters ? colors.primary : colors.text} size={18} />
        </TouchableOpacity>
        <TouchableOpacity onPress={cycleViewMode} style={styles.modeButton}>
          <ViewModeIcon mode={viewMode} />
          <Text style={styles.modeButtonText}>{viewModeLabel(viewMode, t)}</Text>
        </TouchableOpacity>
      </View>

      {(suggestions.length > 0 || suggestionsLoading) && filter.trim() ? (
        <View style={styles.suggestionsPanel}>
          <Text style={styles.suggestionsTitle}>
            {suggestionsLoading ? t('common.loading') : t('search.suggestions')}
          </Text>
          {suggestions.map(suggestion => (
            <TouchableOpacity
              accessibilityRole="button"
              key={suggestion.value}
              onPress={() => selectSuggestion(suggestion)}
              style={styles.suggestionRow}>
              <Text numberOfLines={1} style={styles.suggestionLabel}>{suggestion.label}</Text>
              {suggestion.label !== suggestion.value ? (
                <Text numberOfLines={1} style={styles.suggestionValue}>{suggestion.value}</Text>
              ) : null}
            </TouchableOpacity>
          ))}
        </View>
      ) : null}

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
          ListEmptyComponent={
            loading ? (
              <ScreenState loading title={t('home.loading')} />
            ) : (
              <ScreenState title={t('home.noArchives')} message={t('home.tryAnotherSearch')} />
            )
          }
          ListFooterComponent={
            loadingMore ? <Text style={styles.footerText}>{t('common.loading')}</Text> : null
          }
        />
      )}

      <Modal
        animationType="slide"
        onRequestClose={() => setFiltersOpen(false)}
        transparent
        visible={filtersOpen}>
        <View style={styles.modalBackdrop}>
          <View style={styles.filterSheet}>
            <View style={styles.sheetHeader}>
              <Text style={styles.sheetTitle}>{t('common.filter')}</Text>
              <TouchableOpacity
                accessibilityLabel={t('common.close')}
                accessibilityRole="button"
                onPress={() => setFiltersOpen(false)}
                style={styles.sheetCloseButton}>
                <X color={colors.textMuted} size={18} />
              </TouchableOpacity>
            </View>

            <Text style={styles.fieldLabel}>{t('search.sortBy')}</Text>
            <View style={styles.optionGrid}>
              {[
                ['relevance', t('home.relevance')],
                ['lastread', t('home.lastRead')],
                ['created_at', t('home.created')],
                ['release_at', t('home.release')],
                ['updated_at', t('home.updated')],
                ['title', t('home.titleSort')],
                ['pagecount', t('home.pageCount')],
              ].map(([value, label]) => (
                <TouchableOpacity
                  accessibilityRole="button"
                  key={value}
                  onPress={() => setSortby(value)}
                  style={[styles.sheetChip, sortby === value && styles.sortChipActive]}>
                  <Text style={[styles.sortChipText, sortby === value && styles.sortChipTextActive]}>
                    {label}
                  </Text>
                </TouchableOpacity>
              ))}
            </View>

            <Text style={styles.fieldLabel}>{t('search.sortOrder')}</Text>
            <View style={styles.optionRow}>
              {[
                ['desc', t('search.desc')],
                ['asc', t('search.asc')],
              ].map(([value, label]) => (
                <TouchableOpacity
                  accessibilityRole="button"
                  key={value}
                  onPress={() => setSortOrder(value as 'asc' | 'desc')}
                  style={[styles.sheetChip, sortOrder === value && styles.sortChipActive]}>
                  <Text style={[styles.sortChipText, sortOrder === value && styles.sortChipTextActive]}>
                    {label}
                  </Text>
                </TouchableOpacity>
              ))}
            </View>

            <View style={styles.dateRow}>
              <View style={styles.dateField}>
                <Text style={styles.fieldLabel}>{t('search.dateFrom')}</Text>
                <TextInput
                  autoCapitalize="none"
                  onChangeText={setDateFrom}
                  placeholder="YYYY-MM-DD"
                  style={styles.sheetInput}
                  value={dateFrom}
                />
              </View>
              <View style={styles.dateField}>
                <Text style={styles.fieldLabel}>{t('search.dateTo')}</Text>
                <TextInput
                  autoCapitalize="none"
                  onChangeText={setDateTo}
                  placeholder="YYYY-MM-DD"
                  style={styles.sheetInput}
                  value={dateTo}
                />
              </View>
            </View>

            <View style={styles.switchList}>
              <FilterSwitch label={t('search.newOnly')} value={newOnly} onValueChange={setNewOnly} />
              <FilterSwitch label={t('search.untaggedOnly')} value={untaggedOnly} onValueChange={setUntaggedOnly} />
              <FilterSwitch label={t('search.favoriteOnly')} value={favoriteOnly} onValueChange={setFavoriteOnly} />
              <FilterSwitch label={t('search.groupByTanks')} value={groupByTanks} onValueChange={setGroupByTanks} />
            </View>

            <View style={styles.sheetActions}>
              <TouchableOpacity onPress={resetFilters} style={styles.secondaryAction}>
                <Text style={styles.secondaryActionText}>{t('common.reset')}</Text>
              </TouchableOpacity>
              <TouchableOpacity onPress={applyFilters} style={styles.primaryAction}>
                <Text style={styles.primaryActionText}>{t('common.filter')}</Text>
              </TouchableOpacity>
            </View>
          </View>
        </View>
      </Modal>
    </View>
  );
}

function FilterSwitch({
  label,
  onValueChange,
  value,
}: {
  label: string;
  onValueChange: (value: boolean) => void;
  value: boolean;
}) {
  return (
    <View style={styles.switchRow}>
      <Text style={styles.switchLabel}>{label}</Text>
      <Switch
        onValueChange={onValueChange}
        thumbColor={value ? colors.primary : colors.white}
        trackColor={{false: colors.borderStrong, true: colors.primaryMuted}}
        value={value}
      />
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
  searchButton: {
    alignItems: 'center',
    backgroundColor: colors.surface,
    borderColor: colors.border,
    borderRadius: 8,
    borderWidth: StyleSheet.hairlineWidth,
    height: 42,
    justifyContent: 'center',
    width: 42,
  },
  filterButtonActive: {
    backgroundColor: colors.primaryMuted,
    borderColor: colors.primary,
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
  suggestionsPanel: {
    backgroundColor: colors.surface,
    borderColor: colors.border,
    borderRadius: 8,
    borderWidth: StyleSheet.hairlineWidth,
    marginHorizontal: spacing.lg,
    marginBottom: spacing.sm,
    overflow: 'hidden',
  },
  suggestionsTitle: {
    color: colors.textMuted,
    fontSize: 12,
    fontWeight: '800',
    paddingHorizontal: spacing.md,
    paddingTop: spacing.sm,
    paddingBottom: spacing.xs,
    textTransform: 'uppercase',
  },
  suggestionRow: {
    borderTopColor: colors.border,
    borderTopWidth: StyleSheet.hairlineWidth,
    gap: 2,
    paddingHorizontal: spacing.md,
    paddingVertical: spacing.sm,
  },
  suggestionLabel: {
    color: colors.text,
    fontSize: 14,
    fontWeight: '800',
  },
  suggestionValue: {
    color: colors.textMuted,
    fontSize: 12,
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
  modalBackdrop: {
    backgroundColor: 'rgba(0,0,0,0.32)',
    flex: 1,
    justifyContent: 'flex-end',
  },
  filterSheet: {
    backgroundColor: colors.surface,
    borderTopLeftRadius: 14,
    borderTopRightRadius: 14,
    gap: spacing.md,
    maxHeight: '88%',
    padding: spacing.lg,
  },
  sheetHeader: {
    alignItems: 'center',
    flexDirection: 'row',
    gap: spacing.md,
  },
  sheetTitle: {
    color: colors.text,
    flex: 1,
    fontSize: 18,
    fontWeight: '900',
  },
  sheetCloseButton: {
    alignItems: 'center',
    backgroundColor: colors.surfaceMuted,
    borderRadius: 18,
    height: 36,
    justifyContent: 'center',
    width: 36,
  },
  fieldLabel: {
    color: colors.textMuted,
    fontSize: 12,
    fontWeight: '800',
    textTransform: 'uppercase',
  },
  optionGrid: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: spacing.sm,
  },
  optionRow: {
    flexDirection: 'row',
    gap: spacing.sm,
  },
  sheetChip: {
    backgroundColor: colors.surface,
    borderColor: colors.border,
    borderRadius: 999,
    borderWidth: StyleSheet.hairlineWidth,
    paddingHorizontal: 12,
    paddingVertical: 8,
  },
  dateRow: {
    flexDirection: 'row',
    gap: spacing.sm,
  },
  dateField: {
    flex: 1,
    gap: spacing.xs,
  },
  sheetInput: {
    backgroundColor: colors.surfaceMuted,
    borderColor: colors.border,
    borderRadius: 8,
    borderWidth: StyleSheet.hairlineWidth,
    color: colors.text,
    fontSize: 14,
    paddingHorizontal: 10,
    paddingVertical: 9,
  },
  switchList: {
    borderColor: colors.border,
    borderRadius: 8,
    borderWidth: StyleSheet.hairlineWidth,
    overflow: 'hidden',
  },
  switchRow: {
    alignItems: 'center',
    backgroundColor: colors.surface,
    borderBottomColor: colors.border,
    borderBottomWidth: StyleSheet.hairlineWidth,
    flexDirection: 'row',
    minHeight: 48,
    paddingHorizontal: spacing.md,
  },
  switchLabel: {
    color: colors.text,
    flex: 1,
    fontSize: 15,
    fontWeight: '800',
  },
  sheetActions: {
    flexDirection: 'row',
    gap: spacing.sm,
    justifyContent: 'flex-end',
  },
  primaryAction: {
    alignItems: 'center',
    backgroundColor: colors.primary,
    borderRadius: 8,
    height: 40,
    justifyContent: 'center',
    paddingHorizontal: spacing.lg,
  },
  primaryActionText: {
    color: colors.white,
    fontSize: 14,
    fontWeight: '900',
  },
  secondaryAction: {
    alignItems: 'center',
    backgroundColor: colors.surface,
    borderColor: colors.borderStrong,
    borderRadius: 8,
    borderWidth: StyleSheet.hairlineWidth,
    height: 40,
    justifyContent: 'center',
    paddingHorizontal: spacing.lg,
  },
  secondaryActionText: {
    color: colors.text,
    fontSize: 14,
    fontWeight: '800',
  },
});
