import React, {useCallback, useEffect, useMemo, useState} from 'react';
import {
  Alert,
  RefreshControl,
  ScrollView,
  StyleSheet,
  Text,
  TouchableOpacity,
  View,
} from 'react-native';
import FastImage, {type Source as FastImageSource} from '@d11/react-native-fast-image';
import type {NativeStackScreenProps} from '@react-navigation/native-stack';
import {ArrowLeft, Heart} from 'lucide-react-native';
import {useSafeAreaInsets} from 'react-native-safe-area-context';

import {buildAuthorizedAssetImageSource, extractApiError} from '../api/client';
import {
  archiveCoverAsset,
  deleteArchive,
  fetchArchiveMetadata,
  fetchArchiveRelated,
  fetchTankoubonsForArchive,
  getArchiveDownloadUrl,
  markArchiveAsNew,
  markArchiveAsRead,
  setArchiveFavorite,
} from '../api/lanlu';
import {useAuth} from '../auth/AuthContext';
import {ScreenState} from '../components/ScreenState';
import {useI18n} from '../i18n';
import {colors} from '../theme/colors';
import type {Archive, ArchiveMetadata, Tankoubon} from '../types/api';
import type {RootStackParamList} from '../navigation/types';
import {ArchiveDetailActions} from './archive-detail/ArchiveDetailActions';
import {ArchiveDetailHero} from './archive-detail/ArchiveDetailHero';
import {ArchiveDescription} from './archive-detail/ArchiveDescription';
import {ArchiveTags} from './archive-detail/ArchiveTags';
import {ArchiveRelated} from './archive-detail/ArchiveRelated';
import {RelatedArchiveCard} from './archive-detail/RelatedArchiveCard';

type Props = NativeStackScreenProps<RootStackParamList, 'ArchiveDetail'>;

export function ArchiveDetailScreen({route, navigation}: Props) {
  const {language, t} = useI18n();
  const insets = useSafeAreaInsets();
  const {user, status: authStatus} = useAuth();
  const {archiveId, archive} = route.params;
  const [metadata, setMetadata] = useState<ArchiveMetadata | null>(null);
  const [cover, setCover] = useState<FastImageSource | null>(null);
  const [backdrop, setBackdrop] = useState<FastImageSource | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [favorite, setFavorite] = useState(Boolean(archive?.isfavorite));
  const [relatedArchives, setRelatedArchives] = useState<Archive[]>([]);
  const [relatedLoading, setRelatedLoading] = useState(false);
  const [tankoubons, setTankoubons] = useState<Tankoubon[]>([]);
  const [isNew, setIsNew] = useState(Boolean(archive?.isnew));
  const [refreshing, setRefreshing] = useState(false);

  const isAuthenticated = authStatus === 'authenticated';
  const isAdmin = user?.isAdmin === true;

  const load = useCallback(async (showLoading = true) => {
    if (showLoading) setLoading(true);
    setError('');
    try {
      const result = await fetchArchiveMetadata(archiveId, language);
      setMetadata(result);
      setFavorite(Boolean(result.isfavorite));
      setIsNew(Boolean(result.isnew));
      const coverAsset = archiveCoverAsset(result) || archiveCoverAsset(archive);
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
  }, [archive, archiveId, language]);

  const loadRelatedArchives = useCallback(async () => {
    if (!archiveId) return;
    setRelatedLoading(true);
    try {
      const items = await fetchArchiveRelated(archiveId, 8);
      setRelatedArchives(items);
    } catch {
      setRelatedArchives([]);
    } finally {
      setRelatedLoading(false);
    }
  }, [archiveId]);

  const loadTankoubons = useCallback(async () => {
    if (!archiveId) return;
    try {
      const items = await fetchTankoubonsForArchive(archiveId);
      setTankoubons(items);
    } catch {
      setTankoubons([]);
    }
  }, [archiveId]);

  useEffect(() => {
    loadRelatedArchives().catch(err => console.warn('Failed to load related archives:', err));
  }, [loadRelatedArchives]);

  useEffect(() => {
    loadTankoubons().catch(err => console.warn('Failed to load archive collections:', err));
  }, [loadTankoubons]);

  useEffect(() => {
    load().catch(err => console.warn('Failed to load archive:', err));
  }, [load]);

  const refresh = useCallback(() => {
    setRefreshing(true);
    Promise.all([load(false), loadRelatedArchives(), loadTankoubons()])
      .catch(err => console.warn('Failed to refresh archive:', err))
      .finally(() => setRefreshing(false));
  }, [load, loadRelatedArchives, loadTankoubons]);

  const merged = useMemo<ArchiveMetadata>(() => {
    return {
      arcid: archiveId,
      title: archive?.title,
      filename: archive?.filename,
      description: archive?.description,
      assets: archive?.assets,
      pagecount: archive?.pagecount,
      progress: archive?.progress,
      isfavorite: archive?.isfavorite,
      archivetype: archive?.archivetype,
      size: archive?.size,
      ...metadata,
    };
  }, [archive, archiveId, metadata]);

  async function toggleFavorite() {
    const next = !favorite;
    setFavorite(next);
    try {
      await setArchiveFavorite(merged, next);
    } catch (err) {
      setFavorite(!next);
      setError(extractApiError(err));
    }
  }

  const handleDownload = useCallback(() => {
    const url = getArchiveDownloadUrl(merged.arcid);
    // Open download URL using system browser or alert
    Alert.alert(t('archive.download'), url);
  }, [merged.arcid, t]);

  const handleMarkAsRead = useCallback(async () => {
    try {
      await markArchiveAsRead(merged.arcid);
      setIsNew(false);
    } catch (err) {
      setError(extractApiError(err));
    }
  }, [merged.arcid]);

  const handleMarkAsNew = useCallback(async () => {
    try {
      await markArchiveAsNew(merged.arcid);
      setIsNew(true);
    } catch (err) {
      setError(extractApiError(err));
    }
  }, [merged.arcid]);

  const handleDeleteArchive = useCallback(() => {
    if (!isAdmin) {
      Alert.alert('', t('common.accessDenied'));
      return;
    }
    Alert.alert(
      t('archive.deleteConfirmTitle'),
      t('archive.deleteConfirmMessage', {title: merged.title || merged.filename || merged.arcid}),
      [
        {text: t('common.cancel'), style: 'cancel'},
        {
          text: t('common.delete'),
          style: 'destructive',
          onPress: async () => {
            try {
              await deleteArchive(merged.arcid);
              navigation.goBack();
            } catch (err) {
              setError(extractApiError(err));
            }
          },
        },
      ],
    );
  }, [isAdmin, merged, navigation, t]);

  const handleTagPress = useCallback(
    (tag: string) => {
      (navigation as any).navigate('Main', {
        screen: 'Home',
        params: {q: tag},
      });
    },
    [navigation],
  );

  const handleRelatedPress = useCallback(
    (item: Archive) => {
      navigation.push('ArchiveDetail', {archiveId: item.arcid, archive: item});
    },
    [navigation],
  );

  const progress = Number(merged.progress || 0);
  const pagecount = Number(merged.pagecount || 0);
  const resumePage = progress > 0 ? Math.min(progress, pagecount || progress) : 1;

  const tags = useMemo(() => {
    return Array.isArray(merged.tags)
      ? merged.tags.map(tag => String(tag || '').trim()).filter(Boolean)
      : [];
  }, [merged.tags]);

  if (loading && !metadata && !archive) {
    return <ScreenState loading title={t('archive.loading')} />;
  }

  if (error && !metadata && !archive) {
    return (
      <ScreenState
        title={t('archive.loadFailed')}
        message={error}
        actionLabel={t('common.retry')}
        onAction={() => {
          load().catch(err => console.warn('Failed to load archive:', err));
        }}
      />
    );
  }

  return (
    <ScrollView
      style={styles.screen}
      contentContainerStyle={[styles.content, {paddingTop: insets.top + 12}]}
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

      <ArchiveDetailHero metadata={merged} cover={cover} backdrop={backdrop} t={t} />

      {error ? <Text style={styles.error}>{error}</Text> : null}

      <ArchiveDetailActions
        metadata={merged}
        favorite={favorite}
        favoriteLoading={false}
        onToggleFavorite={toggleFavorite}
        onStartReading={() =>
          navigation.navigate('Reader', {
            archiveId,
            initialPage: resumePage,
          })
        }
        onDownload={handleDownload}
        onMarkAsRead={isNew ? handleMarkAsRead : undefined}
        onMarkAsNew={!isNew && isNew !== undefined ? handleMarkAsNew : undefined}
        onEdit={isAuthenticated ? () => Alert.alert(t('common.edit'), t('common.comingSoon')) : undefined}
        onDelete={isAdmin ? handleDeleteArchive : undefined}
        t={t}
      />

      <ArchiveDescription description={merged.description} t={t} />
      <ArchiveTags tags={tags} onTagPress={handleTagPress} t={t} />

      {tankoubons.length > 0 ? (
        <View style={styles.section}>
          <Text style={styles.sectionTitle}>{t('archive.collections')}</Text>
          <View style={styles.tankoubonList}>
            {tankoubons.map(tk => (
              <TouchableOpacity
                key={tk.tankoubon_id}
                style={styles.tankoubonItem}
                onPress={() =>
                  navigation.push('TankoubonDetail', {
                    tankoubonId: tk.tankoubon_id,
                    tankoubon: tk,
                  })
                }>
                <Text style={styles.tankoubonItemText}>{tk.title || tk.tankoubon_id}</Text>
              </TouchableOpacity>
            ))}
          </View>
        </View>
      ) : null}

      <ArchiveRelated
        related={relatedArchives}
        loading={relatedLoading}
        t={t}
        keyExtractor={item => item.arcid}
        renderItem={item => (
          <RelatedArchiveCard archive={item} onPress={handleRelatedPress} />
        )}
      />
    </ScrollView>
  );
}

const styles = StyleSheet.create({
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
  section: {
    marginTop: 20,
  },
  sectionTitle: {
    color: colors.text,
    fontSize: 15,
    fontWeight: '800',
    marginBottom: 8,
  },
  tankoubonList: {
    gap: 6,
  },
  tankoubonItem: {
    backgroundColor: colors.surface,
    borderColor: colors.border,
    borderRadius: 8,
    borderWidth: StyleSheet.hairlineWidth,
    paddingHorizontal: 14,
    paddingVertical: 10,
  },
  tankoubonItemText: {
    color: colors.primary,
    fontSize: 14,
    fontWeight: '600',
  },
  relatedCard: {
    width: 120,
  },
  relatedCover: {
    aspectRatio: 0.72,
    backgroundColor: colors.surfaceMuted,
    borderRadius: 6,
    width: '100%',
  },
  relatedTitle: {
    color: colors.text,
    fontSize: 12,
    marginTop: 4,
  },
});
