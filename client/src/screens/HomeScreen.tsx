import React, {useCallback, useEffect, useState} from 'react';
import {
  FlatList,
  RefreshControl,
  StyleSheet,
  Text,
  TextInput,
  TouchableOpacity,
  View,
} from 'react-native';
import type {NativeStackNavigationProp} from '@react-navigation/native-stack';
import {useNavigation} from '@react-navigation/native';

import {extractApiError} from '../api/client';
import {searchArchives} from '../api/lanlu';
import {ArchiveCard} from '../components/ArchiveCard';
import {ScreenState} from '../components/ScreenState';
import {colors} from '../theme/colors';
import {spacing} from '../theme/colors';
import type {Archive} from '../types/api';
import type {RootStackParamList} from '../navigation/types';

const PAGE_SIZE = 24;

type Nav = NativeStackNavigationProp<RootStackParamList>;

export function HomeScreen() {
  const navigation = useNavigation<Nav>();
  const [items, setItems] = useState<Archive[]>([]);
  const [filter, setFilter] = useState('');
  const [submittedFilter, setSubmittedFilter] = useState('');
  const [page, setPage] = useState(1);
  const [total, setTotal] = useState(0);
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [loadingMore, setLoadingMore] = useState(false);
  const [error, setError] = useState('');

  const load = useCallback(
    async (nextPage: number, mode: 'replace' | 'append') => {
      if (mode === 'append') {
        setLoadingMore(true);
      } else if (!refreshing) {
        setLoading(true);
      }
      setError('');
      try {
        const result = await searchArchives({
          filter: submittedFilter,
          page: nextPage,
          pageSize: PAGE_SIZE,
        });
        setTotal(result.recordsFiltered || result.recordsTotal || 0);
        setPage(nextPage);
        setItems(current =>
          mode === 'append' ? [...current, ...result.data] : result.data,
        );
      } catch (err) {
        setError(extractApiError(err));
      } finally {
        setLoading(false);
        setRefreshing(false);
        setLoadingMore(false);
      }
    },
    [refreshing, submittedFilter],
  );

  useEffect(() => {
    load(1, 'replace').catch(err => console.warn('Failed to load library:', err));
  }, [load]);

  const refresh = useCallback(() => {
    setRefreshing(true);
    load(1, 'replace').catch(err => console.warn('Failed to refresh:', err));
  }, [load]);

  function submitSearch() {
    setSubmittedFilter(filter.trim());
  }

  function loadMore() {
    if (loading || loadingMore || items.length >= total) {
      return;
    }
    load(page + 1, 'append').catch(err =>
      console.warn('Failed to load more:', err),
    );
  }

  if (loading && items.length === 0) {
    return <ScreenState loading title="Loading library" />;
  }

  if (error && items.length === 0) {
    return (
      <ScreenState
        title="Could not load library"
        message={error}
        actionLabel="Retry"
        onAction={() => {
          load(1, 'replace').catch(err =>
            console.warn('Failed to load library:', err),
          );
        }}
      />
    );
  }

  return (
    <View style={styles.screen}>
      <View style={styles.searchRow}>
        <TextInput
          autoCapitalize="none"
          autoCorrect={false}
          onChangeText={setFilter}
          onSubmitEditing={submitSearch}
          placeholder="Search archives"
          returnKeyType="search"
          style={styles.searchInput}
          value={filter}
        />
        <TouchableOpacity onPress={submitSearch} style={styles.searchButton}>
          <Text style={styles.searchButtonText}>Search</Text>
        </TouchableOpacity>
      </View>

      {error ? <Text style={styles.inlineError}>{error}</Text> : null}

      <FlatList
        columnWrapperStyle={styles.column}
        contentContainerStyle={[
          styles.listContent,
          items.length === 0 && styles.emptyList,
        ]}
        data={items}
        keyExtractor={item => item.arcid}
        numColumns={2}
        onEndReached={loadMore}
        onEndReachedThreshold={0.5}
        refreshControl={
          <RefreshControl refreshing={refreshing} onRefresh={refresh} />
        }
        renderItem={({item}) => (
          <ArchiveCard
            archive={item}
            onChanged={refresh}
            onPress={() =>
              navigation.navigate('ArchiveDetail', {
                archiveId: item.arcid,
                archive: item,
              })
            }
          />
        )}
        ListEmptyComponent={
          <ScreenState title="No archives" message="Try another search." />
        }
        ListFooterComponent={
          loadingMore ? <Text style={styles.footerText}>Loading more...</Text> : null
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
  searchRow: {
    flexDirection: 'row',
    gap: spacing.sm,
    padding: spacing.lg,
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
    backgroundColor: colors.primary,
    borderRadius: 8,
    justifyContent: 'center',
    paddingHorizontal: 14,
  },
  searchButtonText: {
    color: colors.white,
    fontWeight: '800',
  },
  inlineError: {
    color: colors.danger,
    fontSize: 13,
    paddingHorizontal: 12,
    paddingBottom: 8,
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
