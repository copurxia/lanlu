import React, {useCallback, useEffect, useMemo, useState} from 'react';
import {
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

import {buildAuthorizedImageSource, extractApiError} from '../api/client';
import {
  archiveCoverAsset,
  assetPath,
  fetchArchiveMetadata,
  setArchiveFavorite,
} from '../api/lanlu';
import {ScreenState} from '../components/ScreenState';
import {useI18n} from '../i18n';
import {colors} from '../theme/colors';
import type {ArchiveMetadata} from '../types/api';
import type {RootStackParamList} from '../navigation/types';

type Props = NativeStackScreenProps<RootStackParamList, 'ArchiveDetail'>;

export function ArchiveDetailScreen({route, navigation}: Props) {
  const {t} = useI18n();
  const insets = useSafeAreaInsets();
  const {archiveId, archive} = route.params;
  const [metadata, setMetadata] = useState<ArchiveMetadata | null>(null);
  const [cover, setCover] = useState<FastImageSource | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [favorite, setFavorite] = useState(Boolean(archive?.isfavorite));

  const load = useCallback(async () => {
    setLoading(true);
    setError('');
    try {
      const result = await fetchArchiveMetadata(archiveId);
      setMetadata(result);
      setFavorite(Boolean(result.isfavorite));
      const sourcePath = assetPath(archiveCoverAsset(result) || archiveCoverAsset(archive));
      setCover(sourcePath ? await buildAuthorizedImageSource(sourcePath) : null);
    } catch (err) {
      setError(extractApiError(err));
    } finally {
      setLoading(false);
    }
  }, [archive, archiveId]);

  useEffect(() => {
    load().catch(err => console.warn('Failed to load archive:', err));
  }, [load]);

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

  const progress = Number(merged.progress || 0);
  const pagecount = Number(merged.pagecount || 0);
  const resumePage = progress > 0 ? Math.min(progress, pagecount || progress) : 1;

  return (
    <ScrollView
      style={styles.screen}
      contentContainerStyle={[styles.content, {paddingTop: insets.top + 12}]}>
      <TouchableOpacity
        accessibilityRole="button"
        onPress={() => navigation.goBack()}
        style={styles.backButton}>
        <ArrowLeft color={colors.text} size={22} />
      </TouchableOpacity>

      <View style={styles.hero}>
        <View style={styles.coverFrame}>
          {cover ? (
            <FastImage
              source={{
                ...cover,
                cache: FastImage.cacheControl.web,
                priority: FastImage.priority.high,
              }}
              resizeMode={FastImage.resizeMode.cover}
              style={styles.cover}
              onError={event =>
                console.warn('Archive detail cover failed:', archiveId, event.nativeEvent.error)
              }
            />
          ) : (
            <View style={styles.coverPlaceholder}>
              <Text style={styles.coverPlaceholderText}>{t('common.noCover')}</Text>
            </View>
          )}
        </View>
        <View style={styles.heroBody}>
          <Text style={styles.title}>
            {merged.title || merged.filename || archiveId}
          </Text>
          <Text style={styles.meta}>
            {pagecount ? t('common.pages', {count: pagecount}) : t('archive.unknownPages')}
          </Text>
          {progress > 0 ? (
            <Text style={styles.meta}>
              {t('archive.progress', {page: resumePage, total: pagecount})}
            </Text>
          ) : null}
        </View>
      </View>

      {error ? <Text style={styles.error}>{error}</Text> : null}

      <View style={styles.actionRow}>
        <TouchableOpacity
          style={styles.primaryButton}
          onPress={() =>
            navigation.navigate('Reader', {
              archiveId,
              initialPage: resumePage,
            })
          }>
          <Text style={styles.primaryButtonText}>
            {progress > 0 ? t('archive.continue') : t('archive.start')}
          </Text>
        </TouchableOpacity>
        <TouchableOpacity
          accessibilityRole="button"
          accessibilityLabel={favorite ? t('common.favorited') : t('common.favorite')}
          style={[styles.favoriteIconButton, favorite && styles.favoriteIconButtonActive]}
          onPress={toggleFavorite}>
          <Heart
            color={favorite ? colors.white : colors.primary}
            fill={favorite ? colors.white : 'transparent'}
            size={22}
          />
        </TouchableOpacity>
      </View>

      <View style={styles.section}>
        <Text style={styles.sectionTitle}>{t('archive.description')}</Text>
        <Text style={styles.description}>
          {merged.description?.trim() || t('archive.noDescription')}
        </Text>
      </View>

      {merged.tags?.length ? (
        <View style={styles.section}>
          <Text style={styles.sectionTitle}>{t('archive.tags')}</Text>
          <View style={styles.tags}>
            {merged.tags.map(tag => (
              <View key={tag} style={styles.tag}>
                <Text style={styles.tagText}>{tag}</Text>
              </View>
            ))}
          </View>
        </View>
      ) : null}
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
  hero: {
    flexDirection: 'row',
    gap: 16,
  },
  coverFrame: {
    aspectRatio: 0.72,
    backgroundColor: colors.surfaceMuted,
    borderRadius: 8,
    overflow: 'hidden',
    width: 128,
  },
  cover: {
    height: '100%',
    width: '100%',
  },
  coverPlaceholder: {
    alignItems: 'center',
    flex: 1,
    justifyContent: 'center',
  },
  coverPlaceholderText: {
    color: colors.textMuted,
  },
  heroBody: {
    flex: 1,
    gap: 8,
    justifyContent: 'center',
  },
  title: {
    color: colors.text,
    fontSize: 22,
    fontWeight: '800',
    lineHeight: 28,
  },
  meta: {
    color: colors.textMuted,
    fontSize: 14,
  },
  error: {
    color: colors.danger,
    marginTop: 14,
  },
  actionRow: {
    alignItems: 'center',
    flexDirection: 'row',
    gap: 10,
    marginTop: 20,
  },
  primaryButton: {
    alignItems: 'center',
    backgroundColor: colors.primary,
    borderRadius: 8,
    flex: 1,
    paddingVertical: 13,
  },
  primaryButtonText: {
    color: colors.white,
    fontSize: 16,
    fontWeight: '800',
  },
  favoriteIconButton: {
    alignItems: 'center',
    backgroundColor: colors.surface,
    borderColor: colors.border,
    borderRadius: 8,
    borderWidth: StyleSheet.hairlineWidth,
    height: 48,
    justifyContent: 'center',
    width: 52,
  },
  favoriteIconButtonActive: {
    backgroundColor: colors.primary,
    borderColor: colors.primary,
  },
  section: {
    marginTop: 24,
  },
  sectionTitle: {
    color: colors.text,
    fontSize: 16,
    fontWeight: '800',
    marginBottom: 8,
  },
  description: {
    color: colors.text,
    fontSize: 15,
    lineHeight: 22,
  },
  tags: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: 8,
  },
  tag: {
    backgroundColor: colors.primaryMuted,
    borderRadius: 6,
    paddingHorizontal: 10,
    paddingVertical: 6,
  },
  tagText: {
    color: colors.primary,
    fontSize: 13,
    fontWeight: '700',
  },
});
