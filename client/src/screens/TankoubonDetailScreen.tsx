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
import {ArrowLeft} from 'lucide-react-native';
import {useSafeAreaInsets} from 'react-native-safe-area-context';

import {buildAuthorizedImageSource, extractApiError} from '../api/client';
import {
  archiveCoverAsset,
  assetPath,
  fetchTankoubonMetadata,
} from '../api/lanlu';
import {ScreenState} from '../components/ScreenState';
import {useI18n} from '../i18n';
import {colors} from '../theme/colors';
import type {TankoubonMetadata} from '../types/api';
import type {RootStackParamList} from '../navigation/types';

type Props = NativeStackScreenProps<RootStackParamList, 'TankoubonDetail'>;

export function TankoubonDetailScreen({route, navigation}: Props) {
  const {language, t} = useI18n();
  const insets = useSafeAreaInsets();
  const {tankoubonId, tankoubon} = route.params;
  const [metadata, setMetadata] = useState<TankoubonMetadata | null>(null);
  const [cover, setCover] = useState<FastImageSource | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');

  const load = useCallback(async () => {
    setLoading(true);
    setError('');
    try {
      const result = await fetchTankoubonMetadata(tankoubonId, language);
      setMetadata(result);
      const sourcePath = assetPath(archiveCoverAsset(result) || archiveCoverAsset(tankoubon));
      setCover(sourcePath ? await buildAuthorizedImageSource(sourcePath) : null);
    } catch (err) {
      setError(extractApiError(err));
    } finally {
      setLoading(false);
    }
  }, [language, tankoubon, tankoubonId]);

  useEffect(() => {
    load().catch(err => console.warn('Failed to load tankoubon:', err));
  }, [load]);

  const merged = useMemo<TankoubonMetadata>(() => ({
    tankoubon_id: tankoubonId,
    title: tankoubon?.title,
    description: tankoubon?.description,
    assets: tankoubon?.assets,
    children: tankoubon?.children,
    pagecount: tankoubon?.pagecount,
    progress: tankoubon?.progress,
    isfavorite: tankoubon?.isfavorite,
    ...metadata,
  }), [metadata, tankoubon, tankoubonId]);

  const children = merged.children || [];
  const firstArchive = children[0];
  const pagecount = Number(merged.pagecount || 0);
  const archiveCount = Number(merged.archive_count || children.length || 0);

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
          load().catch(err => console.warn('Failed to load tankoubon:', err));
        }}
      />
    );
  }

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
                console.warn('Tankoubon detail cover failed:', tankoubonId, event.nativeEvent.error)
              }
            />
          ) : (
            <View style={styles.coverPlaceholder}>
              <Text style={styles.coverPlaceholderText}>{t('common.noCover')}</Text>
            </View>
          )}
        </View>
        <View style={styles.heroBody}>
          <Text style={styles.title}>{merged.title || tankoubonId}</Text>
          <Text style={styles.meta}>{t('tankoubon.archives')}: {archiveCount}</Text>
          {pagecount ? (
            <Text style={styles.meta}>{t('common.pages', {count: pagecount})}</Text>
          ) : null}
        </View>
      </View>

      {error ? <Text style={styles.error}>{error}</Text> : null}

      <TouchableOpacity
        disabled={!firstArchive}
        style={[styles.primaryButton, !firstArchive && styles.primaryButtonDisabled]}
        onPress={() => {
          if (!firstArchive) return;
          navigation.navigate('Reader', {
            archiveId: firstArchive,
            initialPage: 1,
            tankoubonId,
            children,
            childIndex: 0,
          });
        }}>
        <Text style={styles.primaryButtonText}>{t('tankoubon.start')}</Text>
      </TouchableOpacity>

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
  primaryButton: {
    alignItems: 'center',
    backgroundColor: colors.primary,
    borderRadius: 8,
    marginTop: 20,
    paddingVertical: 13,
  },
  primaryButtonDisabled: {
    opacity: 0.45,
  },
  primaryButtonText: {
    color: colors.white,
    fontSize: 16,
    fontWeight: '800',
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
