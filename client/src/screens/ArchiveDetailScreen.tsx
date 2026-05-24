import React, {useCallback, useEffect, useMemo, useRef, useState} from 'react';
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
import {useFocusEffect} from '@react-navigation/native';
import {ArrowLeft} from 'lucide-react-native';
import {useSafeAreaInsets} from 'react-native-safe-area-context';

import {buildAuthorizedAssetImageSource, buildAuthorizedImageSource, extractApiError, isNetworkError} from '../api/client';
import {createProxiedMediaUrl} from '../native/LanluMediaProxy';
import {
  archiveCoverAsset,
  deleteArchive,
  assetPath,
  fetchArchiveDownloadParts,
  fetchArchiveFiles,
  fetchArchiveMetadata,
  fetchArchiveRelated,
  fetchTankoubonsForArchive,
  getPageDefaultSource,
  markArchiveAsNew,
  markArchiveAsRead,
  readAssetId,
  setArchiveFavorite,
} from '../api/lanlu';
import {useAuth} from '../auth/AuthContext';
import {ScreenState} from '../components/ScreenState';
import {useI18n} from '../i18n';
import {useTheme} from '../theme/ThemeContext';
import {useOfflineArchiveStore} from '../stores/offlineArchiveStore';
import type {Archive, ArchiveMetadata, Tankoubon} from '../types/api';
import type {RootStackParamList} from '../navigation/types';
import {ArchiveDetailActions} from './archive-detail/ArchiveDetailActions';
import {ArchiveDetailHero} from './archive-detail/ArchiveDetailHero';
import {ArchiveDescription} from './archive-detail/ArchiveDescription';
import {ArchiveTags} from './archive-detail/ArchiveTags';
import {ArchiveBasicInfo} from './archive-detail/ArchiveBasicInfo';
import {ReaderSidebar, type SbPage} from './reader/ReaderSidebar';
import {ArchiveCard} from '../components/ArchiveCard';
import {ArchiveRelated} from './archive-detail/ArchiveRelated';
import {ArchiveEditDialog} from './archive-detail/ArchiveEditDialog';

type Props = NativeStackScreenProps<RootStackParamList, 'ArchiveDetail'>;

export function ArchiveDetailScreen({route, navigation}: Props) {
  const {language, t} = useI18n();
  const {colors} = useTheme();
  const insets = useSafeAreaInsets();
  const {user, status: authStatus, activeServer, isOffline} = useAuth();
  const {archiveId, archive, tankoubonId, children, childIndex} = route.params;
  const serverId = activeServer?.id || '';
  const cacheArchive = useOfflineArchiveStore(s => s.cacheArchive);
  const getCachedArchive = useOfflineArchiveStore(s => s.getCachedArchive);
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

  // Edit dialog state
  const [editDialogOpen, setEditDialogOpen] = useState(false);

  // Sidebar state
  const [sidebarPages, setSidebarPages] = useState<SbPage[]>([]);
  const sidebarCurrentPage = useRef(1);

  // Auto-load pages for inline sidebar
  useEffect(() => {
    let cancelled = false;
    fetchArchiveFiles(archiveId)
      .then(async pages => {
        const sbPages: SbPage[] = [];
        for (let idx = 0; idx < pages.length; idx++) {
          const page = pages[idx];
          const source = getPageDefaultSource(page);
          const path = source?.path || page.path || "";
          const effectiveType = source?.type || page.type || "image";
          const displayMetadata = source?.metadata || page.metadata;
          const thumbPath = displayMetadata?.thumb?.trim()
            || assetPath(displayMetadata?.thumb_asset_id)
            || (effectiveType === "image" ? (source?.url || `/api/archives/${encodeURIComponent(archiveId)}/page/${encodeURIComponent(page.id || String(idx+1))}`) : "");
          let thumbnailSource = null;
          if (thumbPath) {
            try {
              const authThumb = await buildAuthorizedImageSource(thumbPath);
              if (authThumb?.uri) {
                const proxyUri = await createProxiedMediaUrl(authThumb.uri, authThumb.headers as Record<string, string> | undefined, true);
                thumbnailSource = {
                  uri: proxyUri || authThumb.uri,
                  ...(!proxyUri && authThumb.headers ? {headers: authThumb.headers} : {}),
                  cache: "immutable",
                } as any;
              }
            } catch {}
          }
          sbPages.push({
            pageNumber: idx + 1,
            effectiveType,
            imageSource: thumbnailSource,
            thumbnailSource,
            uri: undefined,
            vlcUri: undefined,
            headers: undefined,
            resolvedPath: path,
            title: page.title || source?.title,
            metadata: page.metadata,
            activeSource: source,
          });
        }
        if (!cancelled) setSidebarPages(sbPages);
      })
      .catch(() => {});
    return () => { cancelled = true; };
  }, [archiveId]);

  const isAuthenticated = authStatus === 'authenticated';
  const isAdmin = user?.isAdmin === true;

  const load = useCallback(async (showLoading = true) => {
    if (showLoading) setLoading(true);
    setError('');

    if (isOffline && serverId) {
      const cached = getCachedArchive(serverId, archiveId);
      if (cached && cached.metadata.arcid) {
        setMetadata(cached.metadata);
        setFavorite(Boolean(cached.metadata.isfavorite));
        setIsNew(Boolean(cached.metadata.isnew));
        const coverAsset = archiveCoverAsset(cached.metadata) || archiveCoverAsset(archive);
        buildAuthorizedAssetImageSource(coverAsset, {priority: FastImage.priority.high})
          .then(src => { if (src) setCover(src); });
        buildAuthorizedAssetImageSource(cached.metadata.assets?.backdrop, {priority: FastImage.priority.low})
          .then(src => { if (src) setBackdrop(src); });
        if (showLoading) setLoading(false);
        return;
      }
    }

    try {
      const result = await fetchArchiveMetadata(archiveId, language);
      setMetadata(result);
      setFavorite(Boolean(result.isfavorite));
      setIsNew(Boolean(result.isnew));
      if (serverId) {
        cacheArchive(serverId, archiveId, {metadata: result});
      }
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
      if (serverId && isNetworkError(err)) {
        const cached = getCachedArchive(serverId, archiveId);
        if (cached && cached.metadata.arcid) {
          setMetadata(cached.metadata);
          setFavorite(Boolean(cached.metadata.isfavorite));
          setIsNew(Boolean(cached.metadata.isnew));
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
  }, [archive, archiveId, isOffline, language, serverId, cacheArchive, getCachedArchive]);

  const loadRelatedArchives = useCallback(async () => {
    if (!archiveId) return;
    setRelatedLoading(true);

    if (isOffline && serverId) {
      const cached = getCachedArchive(serverId, archiveId);
      if (cached?.related.length) {
        setRelatedArchives(cached.related);
        setRelatedLoading(false);
        return;
      }
    }

    try {
      const items = await fetchArchiveRelated(archiveId, 8);
      setRelatedArchives(items);
      if (serverId) {
        cacheArchive(serverId, archiveId, {related: items});
      }
    } catch (err) {
      if (serverId && isNetworkError(err)) {
        const cached = getCachedArchive(serverId, archiveId);
        if (cached?.related.length) {
          setRelatedArchives(cached.related);
        } else {
          setRelatedArchives([]);
        }
      } else {
        setRelatedArchives([]);
      }
    } finally {
      setRelatedLoading(false);
    }
  }, [archiveId, isOffline, serverId, cacheArchive, getCachedArchive]);

  const loadTankoubons = useCallback(async () => {
    if (!archiveId) return;

    if (isOffline && serverId) {
      const cached = getCachedArchive(serverId, archiveId);
      if (cached?.tankoubons.length) {
        setTankoubons(cached.tankoubons);
        return;
      }
    }

    try {
      const items = await fetchTankoubonsForArchive(archiveId);
      setTankoubons(items);
      if (serverId) {
        cacheArchive(serverId, archiveId, {tankoubons: items});
      }
    } catch (err) {
      if (serverId && isNetworkError(err)) {
        const cached = getCachedArchive(serverId, archiveId);
        if (cached?.tankoubons.length) {
          setTankoubons(cached.tankoubons);
        } else {
          setTankoubons([]);
        }
      } else {
        setTankoubons([]);
      }
    }
  }, [archiveId, isOffline, serverId, cacheArchive, getCachedArchive]);

  useEffect(() => {
    loadRelatedArchives().catch(err => console.warn('Failed to load related archives:', err));
  }, [loadRelatedArchives]);

  useEffect(() => {
    loadTankoubons().catch(err => console.warn('Failed to load archive collections:', err));
  }, [loadTankoubons]);

  useEffect(() => {
    load().catch(err => console.warn('Failed to load archive:', err));
  }, [load]);

  const detailHasLoaded = useRef(false);
  useFocusEffect(
    useCallback(() => {
      if (detailHasLoaded.current) {
        load(false).catch(err => console.warn('Failed to reload archive:', err));
      } else {
        detailHasLoaded.current = true;
      }
    }, [load]),
  );

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

  const handleDownload = useCallback(async () => {
    try {
      const parts = await fetchArchiveDownloadParts(merged.arcid);
      const message = parts
        .map(part => parts.length > 1 && part.name ? `${part.name}\n${part.url}` : part.url)
        .join('\n\n');
      Alert.alert(t('archive.download'), message);
    } catch (err) {
      setError(extractApiError(err));
    }
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

        previewButtonText: {
          fontSize: 14,
          fontWeight: "700",
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
      }),
    [colors],
  );

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
      contentContainerStyle={[styles.content, {paddingTop: 12 + (isOffline ? 0 : insets.top)}]}
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
            tankoubonId,
            children,
            childIndex,
          })
        }
        onDownload={handleDownload}
        onMarkAsRead={isNew ? handleMarkAsRead : undefined}
        onMarkAsNew={!isNew && isNew !== undefined ? handleMarkAsNew : undefined}
        onEdit={isAuthenticated ? () => setEditDialogOpen(true) : undefined}
        onDelete={isAdmin ? handleDeleteArchive : undefined}
        t={t}
      />
      <ArchiveDescription description={merged.description} t={t} />
      <ArchiveTags tags={tags} onTagPress={handleTagPress} t={t} />


      {sidebarPages.length > 0 ? (
          <ReaderSidebar
            inline
            title={`${t("archive.pagePreview")} (${sidebarPages.length})`}
            tabIcons
            pages={sidebarPages}
            currentPage={sidebarCurrentPage.current}
            onSelectPage={(pageIndex) => {
              navigation.navigate('Reader', {archiveId, initialPage: pageIndex + 1, tankoubonId, children, childIndex});
            }}
            t={t as any}
          />
      ) : null}


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
          <ArchiveCard archive={item} variant="related" onOpenReader={() => handleRelatedPress(item)} onOpenDetail={() => handleRelatedPress(item)} />
        )}
      />

      <ArchiveBasicInfo metadata={merged} archive={archive} t={t} />

      <ArchiveEditDialog
        visible={editDialogOpen}
        onClose={() => setEditDialogOpen(false)}
        onSaved={() => {
          load().catch(err => console.warn('Failed to reload archive:', err));
        }}
        archiveId={archiveId}
        initialTitle={merged.title || ''}
        initialSummary={merged.description || ''}
        initialTags={tags}
        initialAssetCoverId={String(readAssetId(merged.assets, 'cover') || '')}
        initialAssetBackdropId={String(readAssetId(merged.assets, 'backdrop') || '')}
        initialAssetClearlogoId={String(readAssetId(merged.assets, 'clearlogo') || '')}
        t={t}
      />
    </ScrollView>
  );
}
