import React, {useCallback, useEffect, useMemo, useState} from 'react';
import {
  ActivityIndicator,
  Alert,
  RefreshControl,
  ScrollView,
  StyleSheet,
  Text,
  TextInput,
  TouchableOpacity,
  View,
} from 'react-native';
import FastImage, {type Source as FastImageSource} from '@d11/react-native-fast-image';
import type {NativeStackScreenProps} from '@react-navigation/native-stack';
import {ArrowLeft, LayoutGrid, List, Search} from 'lucide-react-native';
import {useSafeAreaInsets} from 'react-native-safe-area-context';

import {
  archiveCoverAsset,
  deleteTankoubon,
  fetchTankoubonMetadata,
  fetchTankoubonRelated,
  readAssetId,
  searchArchives,
  setTankoubonFavorite,
} from '../api/lanlu';
import {buildAuthorizedAssetImageSource, extractApiError, isNetworkError} from '../api/client';
import {ArchiveCard} from '../components/ArchiveCard';
import {ScreenState} from '../components/ScreenState';
import {useI18n} from '../i18n';
import {getStoredStringSync, setStoredStringSync} from '../storage/mmkv';
import {useTheme} from '../theme/ThemeContext';
import {useAuth} from '../auth/AuthContext';
import {useOfflineTankoubonStore} from '../stores/offlineTankoubonStore';
import {spacing} from '../theme/colors';
import type {Archive, Tankoubon, TankoubonMetadata} from '../types/api';
import type {RootStackParamList} from '../navigation/types';
import {TankoubonDetailHero} from './tankoubon-detail/TankoubonDetailHero';
import {TankoubonDetailActions} from './tankoubon-detail/TankoubonDetailActions';
import {AddArchiveDialog} from './tankoubon-detail/AddArchiveDialog';
import {TankoubonRelated} from './tankoubon-detail/TankoubonRelated';
import {ArchiveDescription} from './archive-detail/ArchiveDescription';
import {ArchiveTags} from './archive-detail/ArchiveTags';
import {TankoubonEditDialog} from './tankoubon-detail/TankoubonEditDialog';

type ViewMode = 'grid' | 'list';
const TANKOUHON_VIEW_MODE_KEY = 'tankoubon_view_mode';

function loadViewMode(): ViewMode {
  const stored = getStoredStringSync(TANKOUHON_VIEW_MODE_KEY);
  return stored === 'grid' || stored === 'list' ? stored : 'list';
}

type Props = NativeStackScreenProps<RootStackParamList, 'TankoubonDetail'>;

export function TankoubonDetailScreen({route, navigation}: Props) {
  const {language, t} = useI18n();
  const {colors} = useTheme();
  const insets = useSafeAreaInsets();
  const {activeServer, isOffline} = useAuth();
  const serverId = activeServer?.id || '';
  const cacheTankoubon = useOfflineTankoubonStore(s => s.cacheTankoubon);
  const getCachedTankoubon = useOfflineTankoubonStore(s => s.getCachedTankoubon);
  const {tankoubonId, tankoubon} = route.params;

  const [metadata, setMetadata] = useState<TankoubonMetadata | null>(null);
  const [cover, setCover] = useState<FastImageSource | null>(null);
  const [backdrop, setBackdrop] = useState<FastImageSource | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [favorite, setFavorite] = useState(Boolean(tankoubon?.isfavorite));

  // Archive list
  const [archives, setArchives] = useState<Archive[]>([]);
  const [archivesLoading, setArchivesLoading] = useState(false);
  const [archiveFilter, setArchiveFilter] = useState('');

  // View mode
  const [viewMode, setViewMode] = useState<ViewMode>(loadViewMode);

  const [addDialogOpen, setAddDialogOpen] = useState(false);
  const [editDialogOpen, setEditDialogOpen] = useState(false);

  // Related
  const [related, setRelated] = useState<Tankoubon[]>([]);
  const [relatedLoading, setRelatedLoading] = useState(false);
  const [refreshing, setRefreshing] = useState(false);

  const loadMetadata = useCallback(async (showLoading = true) => {
    if (showLoading) setLoading(true);
    setError('');

    if (isOffline && serverId) {
      const cached = getCachedTankoubon(serverId, tankoubonId);
      if (cached && cached.metadata.tankoubon_id) {
        setMetadata(cached.metadata);
        setFavorite(Boolean(cached.metadata.isfavorite));
        const coverAsset = archiveCoverAsset(cached.metadata) || archiveCoverAsset(tankoubon);
        buildAuthorizedAssetImageSource(coverAsset, {priority: FastImage.priority.high})
          .then(src => { if (src) setCover(src); });
        buildAuthorizedAssetImageSource(cached.metadata.assets?.backdrop, {priority: FastImage.priority.low})
          .then(src => { if (src) setBackdrop(src); });
        if (showLoading) setLoading(false);
        return;
      }
    }

    try {
      const result = await fetchTankoubonMetadata(tankoubonId, language);
      setMetadata(result);
      setFavorite(Boolean(result.isfavorite));
      if (serverId) {
        cacheTankoubon(serverId, tankoubonId, {metadata: result});
      }

      const coverAsset = archiveCoverAsset(result) || archiveCoverAsset(tankoubon);
      setCover(
        await buildAuthorizedAssetImageSource(coverAsset, {
          priority: FastImage.priority.high,
        }),
      );

      setBackdrop(
        await buildAuthorizedAssetImageSource(result.assets?.backdrop, {
          priority: FastImage.priority.low,
        }),
      );
    } catch (err) {
      if (serverId && isNetworkError(err)) {
        const cached = getCachedTankoubon(serverId, tankoubonId);
        if (cached && cached.metadata.tankoubon_id) {
          setMetadata(cached.metadata);
          setFavorite(Boolean(cached.metadata.isfavorite));
          setError('');
        } else {
          setError(extractApiError(err));
        }
      } else {
        setError(extractApiError(err));
      }
    } finally {
      if (showLoading) setLoading(false);
    }
  }, [language, tankoubon, tankoubonId, isOffline, serverId, cacheTankoubon, getCachedTankoubon]);

  const loadArchives = useCallback(async () => {
    if (!tankoubonId) return;
    setArchivesLoading(true);

    if (isOffline && serverId) {
      const cached = getCachedTankoubon(serverId, tankoubonId);
      if (cached?.archives.length) {
        setArchives(cached.archives);
        setArchivesLoading(false);
        return;
      }
    }

    try {
      const result = await searchArchives({
        tankoubon_id: tankoubonId,
        sortby: 'tank_order',
        order: 'asc',
        page: 1,
        pageSize: 10000,
        lang: language,
      });
      const items = result.data
        .filter((item): item is Archive => 'arcid' in item)
        .map(item => item as Archive);
      setArchives(items);
      if (serverId) {
        cacheTankoubon(serverId, tankoubonId, {archives: items});
      }
    } catch (err) {
      if (serverId && isNetworkError(err)) {
        const cached = getCachedTankoubon(serverId, tankoubonId);
        if (cached?.archives.length) {
          setArchives(cached.archives);
        } else {
          setArchives([]);
        }
      } else {
        setArchives([]);
      }
    } finally {
      setArchivesLoading(false);
    }
  }, [language, tankoubonId, isOffline, serverId, cacheTankoubon, getCachedTankoubon]);

  const loadRelated = useCallback(async () => {
    if (!tankoubonId) return;
    setRelatedLoading(true);

    if (isOffline && serverId) {
      const cached = getCachedTankoubon(serverId, tankoubonId);
      if (cached?.related.length) {
        setRelated(cached.related);
        setRelatedLoading(false);
        return;
      }
    }

    try {
      const items = await fetchTankoubonRelated(tankoubonId, 8);
      setRelated(items);
      if (serverId) {
        cacheTankoubon(serverId, tankoubonId, {related: items});
      }
    } catch (err) {
      if (serverId && isNetworkError(err)) {
        const cached = getCachedTankoubon(serverId, tankoubonId);
        if (cached?.related.length) {
          setRelated(cached.related);
        } else {
          setRelated([]);
        }
      } else {
        setRelated([]);
      }
    } finally {
      setRelatedLoading(false);
    }
  }, [tankoubonId, isOffline, serverId, cacheTankoubon, getCachedTankoubon]);

  useEffect(() => {
    loadMetadata().catch(err => console.warn('Failed to load tankoubon:', err));
  }, [loadMetadata]);

  useEffect(() => {
    loadArchives().catch(err => console.warn('Failed to load archives:', err));
  }, [loadArchives]);

  useEffect(() => {
    loadRelated().catch(err => console.warn('Failed to load related:', err));
  }, [loadRelated]);

  const refresh = useCallback(() => {
    setRefreshing(true);
    Promise.all([loadMetadata(false), loadArchives(), loadRelated()])
      .catch(err => console.warn('Failed to refresh tankoubon:', err))
      .finally(() => setRefreshing(false));
  }, [loadArchives, loadMetadata, loadRelated]);

  const merged = useMemo<TankoubonMetadata>(
    () => ({
      tankoubon_id: tankoubonId,
      title: tankoubon?.title,
      description: tankoubon?.description,
      assets: tankoubon?.assets,
      children: tankoubon?.children,
      pagecount: tankoubon?.pagecount,
      progress: tankoubon?.progress,
      isfavorite: tankoubon?.isfavorite,
      ...metadata,
    }),
    [metadata, tankoubon, tankoubonId],
  );
  const readerChildren = useMemo(() => archives.map(item => item.arcid), [archives]);

  const handleStartReading = useCallback(() => {
    const first = archives[0];
    if (!first) return;
    navigation.push('Reader', {
      archiveId: first.arcid,
      tankoubonId,
      children: readerChildren,
      childIndex: 0,
    });
  }, [archives, navigation, tankoubonId, readerChildren]);

  const handleFavoriteToggle = useCallback(async () => {
    const next = !favorite;
    setFavorite(next);
    try {
      await setTankoubonFavorite(tankoubonId, next);
    } catch {
      setFavorite(!next);
    }
  }, [favorite, tankoubonId]);

  const handleDelete = useCallback(() => {
    Alert.alert(
      t('tankoubon.deleteConfirmTitle'),
      t('tankoubon.deleteConfirmMessage'),
      [
        {text: t('common.cancel'), style: 'cancel'},
        {
          text: t('common.delete'),
          style: 'destructive',
          onPress: async () => {
            try {
              await deleteTankoubon(tankoubonId);
              navigation.goBack();
            } catch (err) {
              setError(extractApiError(err));
            }
          },
        },
      ],
    );
  }, [tankoubonId, navigation, t]);

  const handleTagPress = useCallback(
    (tag: string) => {
      (navigation as any).navigate('Main', {
        screen: 'Home',
        params: {q: tag},
      });
    },
    [navigation],
  );

  const handleArchivePress = useCallback(
    (item: Archive) => {
      navigation.push('ArchiveDetail', {
        archiveId: item.arcid,
        archive: item,
        tankoubonId,
        children: readerChildren,
        childIndex: readerChildren.indexOf(item.arcid),
      });
    },
    [navigation, readerChildren, tankoubonId],
  );

  const filteredArchives = useMemo(() => {
    const q = archiveFilter.trim().toLowerCase();
    if (!q) return archives;
    return archives.filter(
      a =>
        String(a.title || '').toLowerCase().includes(q) ||
        String(a.filename || '').toLowerCase().includes(q),
    );
  }, [archives, archiveFilter]);
  const tags = useMemo(() => {
    return Array.isArray(merged.tags)
      ? merged.tags.map(tag => String(tag || '').trim()).filter(Boolean)
      : [];
  }, [merged.tags]);

  const existingArcids = useMemo(
    () => new Set(archives.map(a => a.arcid)),
    [archives],
  );

  const styles = useMemo(
    () =>
      StyleSheet.create({
        screen: {
          backgroundColor: colors.background,
          flex: 1,
        },
        content: {
          padding: 16,
          paddingBottom: 40,
        },
        backButton: {
          alignItems: 'center',
          backgroundColor: colors.surface,
          borderColor: colors.border,
          borderRadius: 20,
          borderWidth: StyleSheet.hairlineWidth,
          height: 40,
          justifyContent: 'center',
          marginBottom: 14,
          width: 40,
        },
        error: {
          color: colors.danger,
          marginTop: 14,
        },
        archiveSection: {
          marginTop: 24,
        },
        archiveSectionHeader: {
          alignItems: 'center',
          flexDirection: 'row',
          justifyContent: 'space-between',
          marginBottom: 10,
        },
        archiveSectionTitleRow: {
          alignItems: 'center',
          flexDirection: 'row',
          gap: 8,
        },
        archiveSectionTitle: {
          color: colors.text,
          fontSize: 16,
          fontWeight: '800',
        },
        archiveCount: {
          backgroundColor: colors.surfaceMuted,
          borderRadius: 10,
          paddingHorizontal: 8,
          paddingVertical: 2,
        },
        archiveCountText: {
          color: colors.textMuted,
          fontSize: 12,
          fontWeight: '600',
        },
        archiveControls: {
          flexDirection: 'row',
          gap: 8,
        },
        viewModeButton: {
          padding: 6,
        },
        filterRow: {
          alignItems: 'center',
          backgroundColor: colors.surface,
          borderColor: colors.border,
          borderRadius: 8,
          borderWidth: StyleSheet.hairlineWidth,
          flexDirection: 'row',
          minHeight: 42,
          marginBottom: 12,
          paddingHorizontal: 10,
        },
        filterIcon: {
          marginRight: 6,
        },
        filterInput: {
          color: colors.text,
          flex: 1,
          fontSize: 14,
          includeFontPadding: false,
          minHeight: 40,
          paddingVertical: 0,
          textAlignVertical: 'center',
        },
        loading: {
          paddingVertical: 24,
        },
        emptyState: {
          alignItems: 'center',
          paddingVertical: 24,
        },
        emptyText: {
          color: colors.textMuted,
          fontSize: 14,
          textAlign: 'center',
        },
        resetText: {
          color: colors.primary,
          fontSize: 14,
          fontWeight: '600',
          marginTop: 8,
        },
        grid: {
          flexDirection: 'row',
          flexWrap: 'wrap',
          gap: spacing.md,
        },
        listContainer: {
          gap: 8,
        },
      }),
    [colors],
  );

  if (loading && !metadata && !tankoubon) {
    return <ScreenState loading title={t('tankoubon.loading')} />;
  }

  if (error && !metadata && !tankoubon) {
    return (
      <ScreenState
        title={t('tankoubon.loadFailed')}
        message={error}
        actionLabel={t('common.retry')}
        onAction={() => {
          loadMetadata().catch(err => console.warn('Failed to load:', err));
        }}
      />
    );
  }

  return (
    <View style={styles.screen}>
      <ScrollView
        contentContainerStyle={[styles.content, {paddingTop: 12 + (isOffline ? 0 : insets.top)}]}
        showsVerticalScrollIndicator={false}
        refreshControl={
          <RefreshControl
            refreshing={refreshing}
            onRefresh={refresh}
            tintColor={colors.primary}
            colors={[colors.primary]}
          />
        }>
        <TouchableOpacity
          accessibilityRole="button"
          onPress={() => navigation.goBack()}
          style={styles.backButton}>
          <ArrowLeft color={colors.text} size={22} />
        </TouchableOpacity>

        <TankoubonDetailHero tankoubon={merged} cover={cover} backdrop={backdrop} t={t} />

        {error ? <Text style={styles.error}>{error}</Text> : null}

        <TankoubonDetailActions
          progress={merged.progress}
          favorite={favorite}
          favoriteLoading={false}
          onStartReading={handleStartReading}
          onToggleFavorite={handleFavoriteToggle}
          onEdit={() => setEditDialogOpen(true)}
          onDelete={handleDelete}
          onAddArchive={() => setAddDialogOpen(true)}
          t={t}
        />

        <ArchiveDescription description={merged.description} t={t} />
        <ArchiveTags tags={tags} onTagPress={handleTagPress} t={t} />

        {/* Archive list section */}
        <View style={styles.archiveSection}>
          <View style={styles.archiveSectionHeader}>
            <View style={styles.archiveSectionTitleRow}>
              <Text style={styles.archiveSectionTitle}>
                {t('tankoubon.archivesTitle')}
              </Text>
              <View style={styles.archiveCount}>
                <Text style={styles.archiveCountText}>
                  {archiveFilter.trim()
                    ? `${filteredArchives.length}/${archives.length}`
                    : String(archives.length)}
                </Text>
              </View>
            </View>

            <View style={styles.archiveControls}>
              <TouchableOpacity
                style={styles.viewModeButton}
                onPress={() => {
                  const next = viewMode === 'grid' ? 'list' : 'grid';
                  setViewMode(next);
                  setStoredStringSync(TANKOUHON_VIEW_MODE_KEY, next);
                }}>
                {viewMode === 'grid' ? (
                  <List color={colors.textMuted} size={18} />
                ) : (
                  <LayoutGrid color={colors.textMuted} size={18} />
                )}
              </TouchableOpacity>
            </View>
          </View>

          <View style={styles.filterRow}>
            <Search color={colors.textMuted} size={16} style={styles.filterIcon} />
            <TextInput
              style={styles.filterInput}
              value={archiveFilter}
              onChangeText={setArchiveFilter}
              placeholder={t('tankoubon.filterPlaceholder')}
              placeholderTextColor={colors.textMuted}
            />
          </View>

          {archivesLoading ? (
            <ActivityIndicator color={colors.primary} style={styles.loading} />
          ) : archives.length === 0 ? (
            <View style={styles.emptyState}>
              <Text style={styles.emptyText}>{t('tankoubon.noArchives')}</Text>
            </View>
          ) : filteredArchives.length === 0 ? (
            <View style={styles.emptyState}>
              <Text style={styles.emptyText}>{t('tankoubon.noMatchingArchives')}</Text>
              <TouchableOpacity onPress={() => setArchiveFilter('')}>
                <Text style={styles.resetText}>{t('common.reset')}</Text>
              </TouchableOpacity>
            </View>
          ) : viewMode === 'grid' ? (
            <View style={styles.grid}>
              {filteredArchives.map(item => (
                <ArchiveCard
                  key={`${item.arcid}-${viewMode}`}
                  archive={item}
                  variant="grid"
                  onPress={() => handleArchivePress(item)}
                  onChanged={() => loadArchives()}
                  onTagPress={handleTagPress}
                />
              ))}
            </View>
          ) : (
            <View style={styles.listContainer}>
              {filteredArchives.map(item => (
                <ArchiveCard
                  key={`${item.arcid}-${viewMode}`}
                  archive={item}
                  variant="list"
                  onPress={() => handleArchivePress(item)}
                  onChanged={() => loadArchives()}
                  onTagPress={handleTagPress}
                />
              ))}
            </View>
          )}
        </View>

        <TankoubonRelated
          related={related}
          loading={relatedLoading}
          t={t}
          onPress={item =>
            navigation.push('TankoubonDetail', {
              tankoubonId: item.tankoubon_id,
              tankoubon: item,
            })
          }
        />
      </ScrollView>

      <AddArchiveDialog
        visible={addDialogOpen}
        tankoubonId={tankoubonId}
        existingArcids={existingArcids}
        onClose={() => {
          setAddDialogOpen(false);
          loadArchives().catch(() => {});
        }}
        onAdded={() => {
          loadArchives().catch(() => {});
        }}
        t={t}
      />

      <TankoubonEditDialog
        visible={editDialogOpen}
        onClose={() => setEditDialogOpen(false)}
        onSaved={() => {
          loadMetadata().catch(err => console.warn('Failed to reload tankoubon:', err));
        }}
        tankoubonId={tankoubonId}
        initialTitle={merged.title || ''}
        initialSummary={merged.description || ''}
        initialTags={tags}
        initialAssetCoverId={String(readAssetId(merged.assets, 'cover') || '')}
        initialAssetBackdropId={String(readAssetId(merged.assets, 'backdrop') || '')}
        initialAssetClearlogoId={String(readAssetId(merged.assets, 'clearlogo') || '')}
        t={t}
      />
    </View>
  );
}
