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
import {useFocusEffect, useNavigation} from '@react-navigation/native';
import DateTimePicker, {
  type DateTimePickerEvent,
} from '@react-native-community/datetimepicker';
import {useSafeAreaInsets} from 'react-native-safe-area-context';
import {
  CalendarDays,
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
  fetchSmartFilters,
  fetchTagAutocomplete,
  isTankoubon,
  mediaItemId,
  searchArchives,
  type SmartFilter,
  type TagSuggestion,
} from '../api/lanlu';
import {ArchiveCard} from '../components/ArchiveCard';
import {HomeFeedCard} from '../components/HomeFeedCard';
import {ScreenState} from '../components/ScreenState';
import {useI18n} from '../i18n';
import {appendDiagnosticLog} from '../storage/diagnostics';
import {
  DEFAULT_HOME_VIEW_MODE,
  HomeViewMode,
  loadHomeViewMode,
  loadHomeViewModeSync,
  saveHomeViewMode,
} from '../storage/preferences';
import {spacing} from '../theme/colors';
import {useTheme} from '../theme/ThemeContext';
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
type DatePickerTarget = 'from' | 'to';
type HomeViewSurface = 'archive-feed' | 'home-category-rows';

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
  const {colors} = useTheme();
  const props = {color: colors.text, size: 18};
  if (mode === 'masonry') return <Grid2X2 {...props} />;
  if (mode === 'list') return <List {...props} />;
  if (mode === 'tweet') return <MessageSquareText {...props} />;
  if (mode === 'channel') return <MessageCircle {...props} />;
  return <Rows3 {...props} />;
}

function resolveSmartFilterDate(value?: string): string {
  const normalized = String(value || '').trim();
  if (!normalized) return '';
  const relativeDays = Number.parseInt(normalized, 10);
  if (!Number.isNaN(relativeDays) && String(relativeDays) === normalized) {
    const date = new Date();
    date.setDate(date.getDate() + relativeDays);
    return date.toISOString().split('T')[0] || '';
  }
  return normalized;
}

function parseDateInput(value: string): Date | null {
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(value.trim());
  if (!match) return null;
  const year = Number(match[1]);
  const month = Number(match[2]);
  const day = Number(match[3]);
  const date = new Date(year, month - 1, day);
  if (
    date.getFullYear() !== year ||
    date.getMonth() !== month - 1 ||
    date.getDate() !== day
  ) {
    return null;
  }
  return date;
}

function formatDateInput(date: Date): string {
  const year = date.getFullYear();
  const month = String(date.getMonth() + 1).padStart(2, '0');
  const day = String(date.getDate()).padStart(2, '0');
  return `${year}-${month}-${day}`;
}

function smartFilterName(filter: SmartFilter, language: string): string {
  if (language !== 'zh') {
    const translated = filter.translations?.[language]?.text?.trim();
    if (translated) return translated;
  }
  return filter.name;
}

function buildExactTagSearchQuery(tag: string) {
  const query = String(tag || '').trim();
  if (!query) return '';
  return query.endsWith('$') ? query : `${query}$`;
}

function resolveHomeViewSurface(mode: HomeViewMode, isRowsLanding: boolean): HomeViewSurface {
  if (mode === 'category-rows' && isRowsLanding) return 'home-category-rows';
  return 'archive-feed';
}

export function HomeScreen() {
  const {colors} = useTheme();
  const {language, t} = useI18n();
  const navigation = useNavigation<Nav>();
  const insets = useSafeAreaInsets();
  const [viewMode, setViewMode] = useState<HomeViewMode>(() => loadHomeViewModeSync());
  const [items, setItems] = useState<MediaItem[]>([]);
  const [randomItems, setRandomItems] = useState<MediaItem[]>([]);
  const [categories, setCategories] = useState<Category[]>([]);
  const [smartFilters, setSmartFilters] = useState<SmartFilter[]>([]);
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
  const [draftSortby, setDraftSortby] = useState('created_at');
  const [draftSortOrder, setDraftSortOrder] = useState<'asc' | 'desc'>('desc');
  const [draftDateFrom, setDraftDateFrom] = useState('');
  const [draftDateTo, setDraftDateTo] = useState('');
  const [draftNewOnly, setDraftNewOnly] = useState(false);
  const [draftUntaggedOnly, setDraftUntaggedOnly] = useState(false);
  const [draftFavoriteOnly, setDraftFavoriteOnly] = useState(false);
  const [draftGroupByTanks, setDraftGroupByTanks] = useState(true);
  const [filtersOpen, setFiltersOpen] = useState(false);
  const [datePickerTarget, setDatePickerTarget] = useState<DatePickerTarget | null>(null);
  const [suggestions, setSuggestions] = useState<TagSuggestion[]>([]);
  const [suggestionsLoading, setSuggestionsLoading] = useState(false);
  const [activeSmartFilterId, setActiveSmartFilterId] = useState<number | null>(null);
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
  const isRowsLanding = !submittedFilter && !selectedCategory && !hasAdvancedFilters;
  const showRows = viewMode === 'category-rows' && isRowsLanding;

  const openReader = useCallback(
    (item: MediaItem) => {
      if (isTankoubon(item)) {
        const firstArchive = item.children?.[0];
        if (firstArchive) {
      navigation.navigate('Reader', {
        archiveId: firstArchive,
        tankoubonId: item.tankoubon_id,
        children: item.children,
        childIndex: 0,
        resumeCollection: true,
      });
        }
        return;
      }
      const pagecount = Number(item.pagecount || 0);
      const progress = Number(item.progress || 0);
      const initialPage = progress > 0 ? Math.min(progress, pagecount || progress) : 1;
      navigation.navigate('Reader', {archiveId: item.arcid, initialPage});
    },
    [navigation],
  );

  const openDetail = useCallback(
    (item: MediaItem) => {
      if (isTankoubon(item)) {
        navigation.navigate('TankoubonDetail', {
          tankoubonId: item.tankoubon_id,
          tankoubon: item,
        });
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
    let cancelled = false;
    Promise.all([fetchCategories(), fetchSmartFilters()])
      .then(([nextCategories, nextSmartFilters]) => {
        if (cancelled) return;
        setCategories(nextCategories.filter(category => category.enabled !== false));
        setSmartFilters(nextSmartFilters);
      })
      .catch(chipError => {
        appendDiagnosticLog('home.chips.load.error', {
          message: chipError instanceof Error ? chipError.message : String(chipError),
        }).catch(() => undefined);
      });
    return () => {
      cancelled = true;
    };
  }, []);

  useEffect(() => {
    load(1, 'replace').catch(err => console.warn('Failed to load home:', err));
  }, [load, searchVersion]);

  const homeHasLoaded = useRef(false);
  useFocusEffect(
    useCallback(() => {
      if (homeHasLoaded.current) {
        load(1, 'replace').catch(err => console.warn('Failed to reload home:', err));
      } else {
        homeHasLoaded.current = true;
      }
    }, [load]),
  );

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
    setSortby(draftSortby);
    setSortOrder(draftSortOrder);
    setDateFrom(draftDateFrom.trim());
    setDateTo(draftDateTo.trim());
    setNewOnly(draftNewOnly);
    setUntaggedOnly(draftUntaggedOnly);
    setFavoriteOnly(draftFavoriteOnly);
    setGroupByTanks(draftGroupByTanks);
    setFiltersOpen(false);
    setDatePickerTarget(null);
    setItems([]);
    setPage(1);
    setTotal(0);
    setSearchVersion(version => version + 1);
  }

  function openFilters() {
    setDraftSortby(sortby);
    setDraftSortOrder(sortOrder);
    setDraftDateFrom(dateFrom);
    setDraftDateTo(dateTo);
    setDraftNewOnly(newOnly);
    setDraftUntaggedOnly(untaggedOnly);
    setDraftFavoriteOnly(favoriteOnly);
    setDraftGroupByTanks(groupByTanks);
    setDatePickerTarget(null);
    setFiltersOpen(true);
  }

  function closeFilters() {
    setDatePickerTarget(null);
    setFiltersOpen(false);
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
    setDraftSortby('created_at');
    setDraftSortOrder('desc');
    setDraftDateFrom('');
    setDraftDateTo('');
    setDraftNewOnly(false);
    setDraftUntaggedOnly(false);
    setDraftFavoriteOnly(false);
    setDraftGroupByTanks(true);
    setFiltersOpen(false);
    setDatePickerTarget(null);
    setItems([]);
    setPage(1);
    setTotal(0);
    setSearchVersion(version => version + 1);
  }

  function onDatePickerChange(event: DateTimePickerEvent, selectedDate?: Date) {
    const target = datePickerTarget;
    setDatePickerTarget(null);
    if (event.type === 'dismissed' || !selectedDate || !target) return;
    const nextValue = formatDateInput(selectedDate);
    if (target === 'from') {
      setDraftDateFrom(nextValue);
    } else {
      setDraftDateTo(nextValue);
    }
  }

  function datePickerValue(target: DatePickerTarget): Date {
    const draftValue = target === 'from' ? draftDateFrom : draftDateTo;
    return parseDateInput(draftValue) || new Date();
  }

  function cycleViewMode() {
    const currentIndex = VIEW_MODES.indexOf(viewMode);
    const next = VIEW_MODES[(currentIndex + 1) % VIEW_MODES.length];
    const previousSurface = resolveHomeViewSurface(viewMode, isRowsLanding);
    const nextSurface = resolveHomeViewSurface(next, isRowsLanding);
    if (previousSurface !== nextSurface) {
      setItems([]);
      setTotal(0);
      setLoading(nextSurface !== 'home-category-rows');
      setSearchVersion(version => version + 1);
    }
    setViewMode(next);
    saveHomeViewMode(next).catch(err => console.warn('Failed to save view mode:', err));
    setPage(1);
  }

  function openCategory(category: Category) {
    setSelectedCategory(category);
    setActiveSmartFilterId(null);
    setSubmittedFilter('');
    setFilter('');
    setItems([]);
    setTotal(0);
    setPage(1);
    setLoading(true);
  }

  function showAll() {
    setActiveSmartFilterId(null);
    setSelectedCategory(null);
    setFilter('');
    setSubmittedFilter('');
    setSortby('created_at');
    setSortOrder('desc');
    setDateFrom('');
    setDateTo('');
    setNewOnly(false);
    setUntaggedOnly(false);
    setFavoriteOnly(false);
    setGroupByTanks(true);
    setItems([]);
    setPage(1);
    setTotal(0);
    setSearchVersion(version => version + 1);
  }

  function applySmartFilter(filterItem: SmartFilter) {
    setActiveSmartFilterId(filterItem.id);
    setSelectedCategory(null);
    const nextQuery = String(filterItem.query || '').trim();
    setFilter(nextQuery);
    setSubmittedFilter(nextQuery);
    const nextSort = String(filterItem.sort_by || '').trim();
    setSortby(nextSort && nextSort !== '_default' ? nextSort : 'created_at');
    setSortOrder(filterItem.sort_order === 'asc' ? 'asc' : 'desc');
    setDateFrom(resolveSmartFilterDate(filterItem.date_from));
    setDateTo(resolveSmartFilterDate(filterItem.date_to));
    setNewOnly(Boolean(filterItem.newonly));
    setUntaggedOnly(Boolean(filterItem.untaggedonly));
    setFavoriteOnly(false);
    setGroupByTanks(true);
    setItems([]);
    setPage(1);
    setTotal(0);
    setSearchVersion(version => version + 1);
  }

  function applyTagSearch(tag: string) {
    const nextQuery = buildExactTagSearchQuery(tag);
    if (!nextQuery) return;
    setActiveSmartFilterId(null);
    setSelectedCategory(null);
    setFilter(nextQuery);
    setSubmittedFilter(nextQuery);
    setSortby('relevance');
    setSortOrder('desc');
    setDateFrom('');
    setDateTo('');
    setNewOnly(false);
    setUntaggedOnly(false);
    setFavoriteOnly(false);
    setGroupByTanks(true);
    setItems([]);
    setPage(1);
    setTotal(0);
    setLoading(true);
    setSearchVersion(version => version + 1);
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
  const listLayoutKey = itemVariant === 'grid' ? 'columns:2' : 'columns:1';

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

  const styles = useMemo(
    () =>
      StyleSheet.create({
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
          flexGrow: 0,
          minHeight: 42,
          paddingBottom: spacing.xs,
        },
        sortRowContent: {
          alignItems: 'center',
          flexDirection: 'row',
          gap: spacing.sm,
          minHeight: 38,
          paddingHorizontal: spacing.lg,
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
          justifyContent: 'center',
          maxWidth: 180,
          minHeight: 32,
          paddingHorizontal: 10,
          paddingVertical: 7,
        },
        sortChipActive: {
          backgroundColor: colors.primaryMuted,
          borderColor: colors.primary,
        },
        sortChipText: {
          color: colors.textMuted,
          fontSize: 12,
          fontWeight: '700',
          lineHeight: 16,
          maxWidth: 160,
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
          paddingTop: spacing.xs,
          paddingBottom: spacing.lg,
        },
        rowSection: {
          marginBottom: spacing.md,
        },
        rowHeader: {
          alignItems: 'center',
          flexDirection: 'row',
          gap: spacing.sm,
          paddingHorizontal: spacing.lg,
          marginBottom: spacing.sm,
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
        dateInputRow: {
          alignItems: 'center',
          backgroundColor: colors.surfaceMuted,
          borderColor: colors.border,
          borderRadius: 8,
          borderWidth: StyleSheet.hairlineWidth,
          flexDirection: 'row',
          minHeight: 40,
          overflow: 'hidden',
        },
        dateInput: {
          color: colors.text,
          flex: 1,
          fontSize: 14,
          paddingHorizontal: 10,
          paddingVertical: 8,
        },
        datePickerButton: {
          alignItems: 'center',
          alignSelf: 'stretch',
          borderLeftColor: colors.border,
          borderLeftWidth: StyleSheet.hairlineWidth,
          justifyContent: 'center',
          width: 40,
        },
        switchList: {
          borderColor: colors.border,
          borderRadius: 8,
          borderWidth: StyleSheet.hairlineWidth,
          overflow: 'hidden',
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
      }),
    [colors],
  );

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
              onOpenDetail={() => openDetail(item)}
              onOpenReader={() => openReader(item)}
              onPress={() => openReader(item)}
              onTagPress={applyTagSearch}
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
    <View style={[styles.screen, {paddingTop: insets.top, paddingLeft: insets.left, paddingRight: insets.right}]}>
      <View style={styles.toolbar}>
        <TextInput
          autoCapitalize="none"
          autoCorrect={false}
          onChangeText={setFilter}
          onSubmitEditing={submitSearch}
          placeholder={t('common.search')}
          placeholderTextColor={colors.textMuted}
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
          onPress={openFilters}
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

      <ScrollView
        contentContainerStyle={styles.sortRowContent}
        horizontal
        showsHorizontalScrollIndicator={false}
        style={styles.sortRow}>
        <TouchableOpacity
          onPress={showAll}
          style={[
            styles.sortChip,
            !selectedCategory && activeSmartFilterId === null && !submittedFilter && !hasAdvancedFilters && styles.sortChipActive,
          ]}>
          <Text
            style={[
              styles.sortChipText,
              !selectedCategory && activeSmartFilterId === null && !submittedFilter && !hasAdvancedFilters && styles.sortChipTextActive,
            ]}>
            {t('common.all')}
          </Text>
        </TouchableOpacity>
        {smartFilters.map(filterItem => (
          <TouchableOpacity
            key={`smart:${filterItem.id}`}
            onPress={() => applySmartFilter(filterItem)}
            style={[styles.sortChip, activeSmartFilterId === filterItem.id && styles.sortChipActive]}>
            <Text
              numberOfLines={1}
              style={[styles.sortChipText, activeSmartFilterId === filterItem.id && styles.sortChipTextActive]}>
              {smartFilterName(filterItem, language)}
            </Text>
          </TouchableOpacity>
        ))}
        {categories.map(category => (
          <TouchableOpacity
            key={`category:${category.catid || category.id}`}
            onPress={() => openCategory(category)}
            style={[styles.sortChip, selectedCategory?.catid === category.catid && styles.sortChipActive]}>
            <Text
              numberOfLines={1}
              style={[styles.sortChipText, selectedCategory?.catid === category.catid && styles.sortChipTextActive]}>
              {category.icon ? `${category.icon} ` : ''}{category.name}
            </Text>
          </TouchableOpacity>
        ))}
      </ScrollView>

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
          extraData={itemVariant}
          key={listLayoutKey}
          keyExtractor={item => mediaItemId(item)}
          numColumns={itemVariant === 'grid' ? 2 : 1}
          columnWrapperStyle={itemVariant === 'grid' ? styles.column : undefined}
          onEndReached={loadMore}
          onEndReachedThreshold={0.5}
          refreshControl={<RefreshControl refreshing={refreshing} onRefresh={refresh} />}
          renderItem={({item}) => (
            itemVariant === 'tweet' || itemVariant === 'channel' ? (
              <HomeFeedCard
                item={item}
                mode={itemVariant}
                onChanged={refresh}
                onDetailPress={() => openDetail(item)}
                onPress={() => openReader(item)}
                onTagPress={applyTagSearch}
              />
            ) : (
              <ArchiveCard
                archive={item}
                variant={itemVariant}
                onOpenDetail={() => openDetail(item)}
                onOpenReader={() => openReader(item)}
                onPress={() => openReader(item)}
                onTagPress={applyTagSearch}
              />
            )
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
        onRequestClose={closeFilters}
        statusBarTranslucent
        transparent
        visible={filtersOpen}>
        <View style={styles.modalBackdrop}>
          <View style={[styles.filterSheet, {paddingBottom: Math.max(insets.bottom, spacing.lg)}]}>
            <View style={styles.sheetHeader}>
              <Text style={styles.sheetTitle}>{t('common.filter')}</Text>
              <TouchableOpacity
                accessibilityLabel={t('common.close')}
                accessibilityRole="button"
                onPress={closeFilters}
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
                  onPress={() => setDraftSortby(value)}
                  style={[styles.sheetChip, draftSortby === value && styles.sortChipActive]}>
                  <Text style={[styles.sortChipText, draftSortby === value && styles.sortChipTextActive]}>
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
                  onPress={() => setDraftSortOrder(value as 'asc' | 'desc')}
                  style={[styles.sheetChip, draftSortOrder === value && styles.sortChipActive]}>
                  <Text style={[styles.sortChipText, draftSortOrder === value && styles.sortChipTextActive]}>
                    {label}
                  </Text>
                </TouchableOpacity>
              ))}
            </View>

            <View style={styles.dateRow}>
              <View style={styles.dateField}>
                <Text style={styles.fieldLabel}>{t('search.dateFrom')}</Text>
                <View style={styles.dateInputRow}>
                  <TextInput
                    autoCapitalize="none"
                    keyboardType="numbers-and-punctuation"
                    onChangeText={setDraftDateFrom}
                    placeholder="YYYY-MM-DD"
                    placeholderTextColor={colors.textMuted}
                    style={styles.dateInput}
                    value={draftDateFrom}
                  />
                  <TouchableOpacity
                    accessibilityLabel={t('search.dateFrom')}
                    accessibilityRole="button"
                    onPress={() => setDatePickerTarget('from')}
                    style={styles.datePickerButton}>
                    <CalendarDays color={colors.textMuted} size={18} />
                  </TouchableOpacity>
                </View>
              </View>
              <View style={styles.dateField}>
                <Text style={styles.fieldLabel}>{t('search.dateTo')}</Text>
                <View style={styles.dateInputRow}>
                  <TextInput
                    autoCapitalize="none"
                    keyboardType="numbers-and-punctuation"
                    onChangeText={setDraftDateTo}
                    placeholder="YYYY-MM-DD"
                    placeholderTextColor={colors.textMuted}
                    style={styles.dateInput}
                    value={draftDateTo}
                  />
                  <TouchableOpacity
                    accessibilityLabel={t('search.dateTo')}
                    accessibilityRole="button"
                    onPress={() => setDatePickerTarget('to')}
                    style={styles.datePickerButton}>
                    <CalendarDays color={colors.textMuted} size={18} />
                  </TouchableOpacity>
                </View>
              </View>
            </View>

            <View style={styles.switchList}>
              <FilterSwitch label={t('search.newOnly')} value={draftNewOnly} onValueChange={setDraftNewOnly} />
              <FilterSwitch label={t('search.untaggedOnly')} value={draftUntaggedOnly} onValueChange={setDraftUntaggedOnly} />
              <FilterSwitch label={t('search.favoriteOnly')} value={draftFavoriteOnly} onValueChange={setDraftFavoriteOnly} />
              <FilterSwitch label={t('search.groupByTanks')} value={draftGroupByTanks} onValueChange={setDraftGroupByTanks} />
            </View>

            <View style={styles.sheetActions}>
              <TouchableOpacity onPress={resetFilters} style={styles.secondaryAction}>
                <Text style={styles.secondaryActionText}>{t('common.reset')}</Text>
              </TouchableOpacity>
              <TouchableOpacity onPress={applyFilters} style={styles.primaryAction}>
                <Text style={styles.primaryActionText}>{t('common.filter')}</Text>
              </TouchableOpacity>
            </View>
            {datePickerTarget ? (
              <DateTimePicker
                display="default"
                mode="date"
                onChange={onDatePickerChange}
                value={datePickerValue(datePickerTarget)}
              />
            ) : null}
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
  const {colors} = useTheme();
  const styles = useMemo(
    () =>
      StyleSheet.create({
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
      }),
    [colors],
  );

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
