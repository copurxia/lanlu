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
  useWindowDimensions,
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
  removeArchiveFromTankoubon,
  searchArchives,
  setTankoubonFavorite,
} from '../api/lanlu';
import {buildAuthorizedAssetImageSource, extractApiError} from '../api/client';
import {ScreenState} from '../components/ScreenState';
import {useI18n} from '../i18n';
import {useTheme} from '../theme/ThemeContext';
import type {Archive, Tankoubon, TankoubonMetadata} from '../types/api';
import type {RootStackParamList} from '../navigation/types';
import {TankoubonDetailHero} from './tankoubon-detail/TankoubonDetailHero';
import {TankoubonDetailActions} from './tankoubon-detail/TankoubonDetailActions';
import {TankoubonArchiveGridCard} from './tankoubon-detail/TankoubonArchiveGridCard';
import {TankoubonArchiveListItem} from './tankoubon-detail/TankoubonArchiveListItem';
import {AddArchiveDialog} from './tankoubon-detail/AddArchiveDialog';
import {TankoubonRelated} from './tankoubon-detail/TankoubonRelated';
import {ArchiveDescription} from './archive-detail/ArchiveDescription';
import {ArchiveTags} from './archive-detail/ArchiveTags';

type ViewMode = 'grid' | 'list';

type Props = NativeStackScreenProps<RootStackParamList, 'TankoubonDetail'>;

export function TankoubonDetailScreen({route, navigation}: Props) {
  const {language, t} = useI18n();
  const {colors} = useTheme();
  const insets = useSafeAreaInsets();
  const {width: screenWidth} = useWindowDimensions();
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
  const [viewMode, setViewMode] = useState<ViewMode>('list');
  const gridColumns = screenWidth > 500 ? 3 : 2;

  // Selection
  const [selectionMode, setSelectionMode] = useState(false);
  const [selectedArcids, setSelectedArcids] = useState<Set<string>>(new Set());

  // Cover cache
  const [coverCache, setCoverCache] = useState<Record<string, FastImageSource | null>>({});

  // Dialogs
  const [removeDialogOpen, setRemoveDialogOpen] = useState(false);
  const [removeTarget, setRemoveTarget] = useState<Archive | null>(null);
  const [removingArcids, setRemovingArcids] = useState<Set<string>>(new Set());
  const [addDialogOpen, setAddDialogOpen] = useState(false);

  // Related
  const [related, setRelated] = useState<Tankoubon[]>([]);
  const [relatedLoading, setRelatedLoading] = useState(false);
  const [refreshing, setRefreshing] = useState(false);

  // Batch operations
  const [batchActionRunning, setBatchActionRunning] = useState(false);

  const loadMetadata = useCallback(async (showLoading = true) => {
    if (showLoading) setLoading(true);
    setError('');
    try {
      const result = await fetchTankoubonMetadata(tankoubonId, language);
      setMetadata(result);
      setFavorite(Boolean(result.isfavorite));

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
      setError(extractApiError(err));
    } finally {
      if (showLoading) setLoading(false);
    }
  }, [language, tankoubon, tankoubonId]);

  const loadArchives = useCallback(async () => {
    if (!tankoubonId) return;
    setArchivesLoading(true);
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
      setArchivesLoading(false);

      // Load covers
      const cache: Record<string, FastImageSource | null> = {};
      await Promise.all(
        items.map(async item => {
          const ca = archiveCoverAsset(item);
          cache[item.arcid] = await buildAuthorizedAssetImageSource(ca);
        }),
      );
      setCoverCache(cache);
    } catch {
      setArchives([]);
    } finally {
      setArchivesLoading(false);
    }
  }, [language, tankoubonId]);

  const loadRelated = useCallback(async () => {
    if (!tankoubonId) return;
    setRelatedLoading(true);
    try {
      const items = await fetchTankoubonRelated(tankoubonId, 8);
      setRelated(items);
    } catch {
      setRelated([]);
    } finally {
      setRelatedLoading(false);
    }
  }, [tankoubonId]);

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

  const handleRemoveArchive = useCallback(
    async (arcid: string) => {
      setRemovingArcids(prev => new Set(prev).add(arcid));
      try {
        await removeArchiveFromTankoubon(tankoubonId, arcid);
        setArchives(prev => prev.filter(a => a.arcid !== arcid));
      } catch {
        // ignore
      } finally {
        setRemovingArcids(prev => {
          const next = new Set(prev);
          next.delete(arcid);
          return next;
        });
      }
    },
    [tankoubonId],
  );

  const confirmRemove = useCallback(() => {
    if (!removeTarget) return;
    handleRemoveArchive(removeTarget.arcid).catch(() => {});
    setRemoveDialogOpen(false);
    setRemoveTarget(null);
  }, [removeTarget, handleRemoveArchive]);

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
      if (selectionMode) {
        setSelectedArcids(prev => {
          const next = new Set(prev);
          if (next.has(item.arcid)) next.delete(item.arcid);
          else next.add(item.arcid);
          return next;
        });
      } else {
        navigation.push('ArchiveDetail', {
          archiveId: item.arcid,
          archive: item,
          tankoubonId,
          children: readerChildren,
          childIndex: readerChildren.indexOf(item.arcid),
        });
      }
    },
    [selectionMode, navigation, readerChildren, tankoubonId],
  );

  const handleArchiveLongPress = useCallback(
    (arcid: string) => {
      if (!selectionMode) {
        setSelectionMode(true);
        setSelectedArcids(new Set([arcid]));
      }
    },
    [selectionMode],
  );

  const exitSelectionMode = useCallback(() => {
    setSelectionMode(false);
    setSelectedArcids(new Set());
  }, []);

  const handleBatchRemove = useCallback(async () => {
    if (selectedArcids.size === 0) return;
    setBatchActionRunning(true);
    try {
      await Promise.all(
        Array.from(selectedArcids).map(arcid =>
          removeArchiveFromTankoubon(tankoubonId, arcid),
        ),
      );
      setArchives(prev => prev.filter(a => !selectedArcids.has(a.arcid)));
      exitSelectionMode();
    } catch {
      Alert.alert('', t('common.error'));
    } finally {
      setBatchActionRunning(false);
    }
  }, [selectedArcids, tankoubonId, exitSelectionMode, t]);

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
          paddingVertical: 10,
        },
        selectionBar: {
          alignItems: 'center',
          backgroundColor: colors.primaryMuted,
          borderRadius: 8,
          flexDirection: 'row',
          gap: 10,
          marginBottom: 10,
          padding: 10,
        },
        selectionText: {
          color: colors.primary,
          flex: 1,
          fontSize: 13,
          fontWeight: '700',
        },
        selectionActionButton: {
          backgroundColor: colors.danger,
          borderRadius: 6,
          paddingHorizontal: 12,
          paddingVertical: 6,
        },
        selectionActionText: {
          color: colors.white,
          fontSize: 12,
          fontWeight: '700',
        },
        selectionCancelText: {
          color: colors.textMuted,
          fontSize: 13,
          fontWeight: '600',
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
          margin: -4,
        },
        listContainer: {
          gap: 8,
        },
        dialogOverlay: {
          ...StyleSheet.absoluteFill,
          alignItems: 'center',
          backgroundColor: 'rgba(0,0,0,0.5)',
          justifyContent: 'center',
          zIndex: 100,
        },
        dialog: {
          backgroundColor: colors.surface,
          borderRadius: 14,
          marginHorizontal: 32,
          padding: 20,
          width: '80%',
        },
        dialogTitle: {
          color: colors.text,
          fontSize: 17,
          fontWeight: '800',
          marginBottom: 8,
        },
        dialogMessage: {
          color: colors.textMuted,
          fontSize: 14,
          lineHeight: 20,
          marginBottom: 16,
        },
        dialogButtons: {
          flexDirection: 'row',
          gap: 10,
          justifyContent: 'flex-end',
        },
        dialogButton: {
          borderRadius: 8,
          paddingHorizontal: 16,
          paddingVertical: 10,
        },
        dialogButtonText: {
          color: colors.text,
          fontSize: 14,
          fontWeight: '600',
        },
        dialogButtonDanger: {
          backgroundColor: colors.danger,
        },
        dialogButtonDangerText: {
          color: colors.white,
          fontSize: 14,
          fontWeight: '700',
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
        contentContainerStyle={[styles.content, {paddingTop: insets.top + 12}]}
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
          favorite={favorite}
          favoriteLoading={false}
          onToggleFavorite={handleFavoriteToggle}
          onEdit={() => Alert.alert(t('common.edit'), t('common.comingSoon'))}
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
                onPress={() => setViewMode(viewMode === 'grid' ? 'list' : 'grid')}>
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

          {selectionMode ? (
            <View style={styles.selectionBar}>
              <Text style={styles.selectionText}>
                {t('common.selected')} ({selectedArcids.size})
              </Text>
              <TouchableOpacity
                style={styles.selectionActionButton}
                onPress={() => {
                  Alert.alert(
                    t('tankoubon.removeSelectedConfirmTitle'),
                    t('tankoubon.removeSelectedConfirmMessage', {
                      count: selectedArcids.size,
                    }),
                    [
                      {text: t('common.cancel'), style: 'cancel'},
                      {
                        text: t('common.remove'),
                        style: 'destructive',
                        onPress: () => handleBatchRemove(),
                      },
                    ],
                  );
                }}
                disabled={batchActionRunning}>
                <Text style={styles.selectionActionText}>
                  {batchActionRunning ? t('common.loading') : t('tankoubon.removeSelected')}
                </Text>
              </TouchableOpacity>
              <TouchableOpacity onPress={exitSelectionMode}>
                <Text style={styles.selectionCancelText}>{t('common.cancel')}</Text>
              </TouchableOpacity>
            </View>
          ) : null}

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
              {filteredArchives.map(item => {
                const isRemoving = removingArcids.has(item.arcid);
                const isSelected = selectedArcids.has(item.arcid);
                return (
                  <View key={item.arcid} style={{width: `${100 / gridColumns}%` as any, padding: 4}}>
                    <TankoubonArchiveGridCard
                      archive={item}
                      cover={coverCache[item.arcid] ?? null}
                      selected={isSelected}
                      selectionMode={selectionMode}
                      onPress={() => handleArchivePress(item)}
                      onLongPress={() => handleArchiveLongPress(item.arcid)}
                      onRemove={() => {
                        setRemoveTarget(item);
                        setRemoveDialogOpen(true);
                      }}
                      removing={isRemoving}
                      t={t}
                    />
                  </View>
                );
              })}
            </View>
          ) : (
            <View style={styles.listContainer}>
              {filteredArchives.map(item => {
                const isRemoving = removingArcids.has(item.arcid);
                const isSelected = selectedArcids.has(item.arcid);
                return (
                  <TankoubonArchiveListItem
                    key={item.arcid}
                    archive={item}
                    cover={coverCache[item.arcid] ?? null}
                    selected={isSelected}
                    selectionMode={selectionMode}
                    onPress={() => handleArchivePress(item)}
                    onRemove={
                      !selectionMode
                        ? () => {
                            setRemoveTarget(item);
                            setRemoveDialogOpen(true);
                          }
                        : undefined
                    }
                    removing={isRemoving}
                    t={t}
                  />
                );
              })}
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

      {removeDialogOpen && removeTarget ? (
        <View style={styles.dialogOverlay}>
          <View style={styles.dialog}>
            <Text style={styles.dialogTitle}>
              {t('tankoubon.removeConfirmTitle')}
            </Text>
            <Text style={styles.dialogMessage}>
              {t('tankoubon.removeConfirmMessage', {
                title: removeTarget.title || removeTarget.filename || removeTarget.arcid,
              })}
            </Text>
            <View style={styles.dialogButtons}>
              <TouchableOpacity
                style={styles.dialogButton}
                onPress={() => {
                  setRemoveDialogOpen(false);
                  setRemoveTarget(null);
                }}>
                <Text style={styles.dialogButtonText}>{t('common.cancel')}</Text>
              </TouchableOpacity>
              <TouchableOpacity
                style={[styles.dialogButton, styles.dialogButtonDanger]}
                onPress={confirmRemove}>
                <Text style={styles.dialogButtonDangerText}>
                  {t('common.remove')}
                </Text>
              </TouchableOpacity>
            </View>
          </View>
        </View>
      ) : null}
    </View>
  );
}

