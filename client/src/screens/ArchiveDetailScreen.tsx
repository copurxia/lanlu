import React, {useCallback, useEffect, useMemo, useState} from 'react';
import {
  Image,
  ImageSourcePropType,
  ScrollView,
  StyleSheet,
  Text,
  TouchableOpacity,
  View,
} from 'react-native';
import type {NativeStackScreenProps} from '@react-navigation/native-stack';

import {buildAuthorizedImageSource, extractApiError} from '../api/client';
import {
  assetPath,
  fetchArchiveMetadata,
  setArchiveFavorite,
} from '../api/lanlu';
import {ScreenState} from '../components/ScreenState';
import {colors} from '../theme/colors';
import type {ArchiveMetadata} from '../types/api';
import type {RootStackParamList} from '../navigation/types';

type Props = NativeStackScreenProps<RootStackParamList, 'ArchiveDetail'>;

export function ArchiveDetailScreen({route, navigation}: Props) {
  const {archiveId, archive} = route.params;
  const [metadata, setMetadata] = useState<ArchiveMetadata | null>(null);
  const [cover, setCover] = useState<ImageSourcePropType | null>(null);
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
      const sourcePath = assetPath(result.assets?.cover || archive?.assets?.cover);
      setCover(sourcePath ? await buildAuthorizedImageSource(sourcePath) : null);
      navigation.setOptions({
        title: result.title || archive?.title || 'Archive',
      });
    } catch (err) {
      setError(extractApiError(err));
    } finally {
      setLoading(false);
    }
  }, [archive?.assets?.cover, archive?.title, archiveId, navigation]);

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
    return <ScreenState loading title="Loading archive" />;
  }

  if (error && !metadata && !archive) {
    return (
      <ScreenState
        title="Could not load archive"
        message={error}
        actionLabel="Retry"
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
    <ScrollView style={styles.screen} contentContainerStyle={styles.content}>
      <View style={styles.hero}>
        <View style={styles.coverFrame}>
          {cover ? (
            <Image source={cover} resizeMode="cover" style={styles.cover} />
          ) : (
            <View style={styles.coverPlaceholder}>
              <Text style={styles.coverPlaceholderText}>No Cover</Text>
            </View>
          )}
        </View>
        <View style={styles.heroBody}>
          <Text style={styles.title}>
            {merged.title || merged.filename || archiveId}
          </Text>
          <Text style={styles.meta}>
            {pagecount ? `${pagecount} pages` : 'Unknown page count'}
          </Text>
          {progress > 0 ? (
            <Text style={styles.meta}>Progress: {resumePage} / {pagecount}</Text>
          ) : null}
        </View>
      </View>

      {error ? <Text style={styles.error}>{error}</Text> : null}

      <View style={styles.actions}>
        <TouchableOpacity
          style={styles.primaryButton}
          onPress={() =>
            navigation.navigate('Reader', {
              archiveId,
              initialPage: resumePage,
            })
          }>
          <Text style={styles.primaryButtonText}>
            {progress > 0 ? 'Continue Reading' : 'Start Reading'}
          </Text>
        </TouchableOpacity>
        <TouchableOpacity
          style={styles.secondaryButton}
          onPress={() => navigation.navigate('Reader', {archiveId, initialPage: 1})}>
          <Text style={styles.secondaryButtonText}>First Page</Text>
        </TouchableOpacity>
        <TouchableOpacity style={styles.secondaryButton} onPress={toggleFavorite}>
          <Text style={styles.secondaryButtonText}>
            {favorite ? 'Favorited' : 'Favorite'}
          </Text>
        </TouchableOpacity>
      </View>

      <View style={styles.section}>
        <Text style={styles.sectionTitle}>Description</Text>
        <Text style={styles.description}>
          {merged.description?.trim() || 'No description.'}
        </Text>
      </View>

      {merged.tags?.length ? (
        <View style={styles.section}>
          <Text style={styles.sectionTitle}>Tags</Text>
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
  actions: {
    gap: 10,
    marginTop: 20,
  },
  primaryButton: {
    alignItems: 'center',
    backgroundColor: colors.primary,
    borderRadius: 8,
    paddingVertical: 13,
  },
  primaryButtonText: {
    color: colors.white,
    fontSize: 16,
    fontWeight: '800',
  },
  secondaryButton: {
    alignItems: 'center',
    backgroundColor: colors.surface,
    borderColor: colors.border,
    borderRadius: 8,
    borderWidth: StyleSheet.hairlineWidth,
    paddingVertical: 12,
  },
  secondaryButtonText: {
    color: colors.text,
    fontSize: 15,
    fontWeight: '700',
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
