import React, {useEffect, useState} from 'react';
import {
  Image,
  ImageSourcePropType,
  StyleSheet,
  Text,
  TouchableOpacity,
  useWindowDimensions,
  View,
} from 'react-native';

import {assetPath, setArchiveFavorite} from '../api/lanlu';
import {buildAuthorizedImageSource, extractApiError} from '../api/client';
import {colors, radius, spacing} from '../theme/colors';
import type {Archive} from '../types/api';

type Props = {
  archive: Archive;
  onPress: () => void;
  onChanged?: () => void;
};

export function ArchiveCard({archive, onPress, onChanged}: Props) {
  const {width} = useWindowDimensions();
  const [imageSource, setImageSource] = useState<ImageSourcePropType | null>(null);
  const [favorite, setFavorite] = useState(Boolean(archive.isfavorite));
  const itemWidth = Math.floor((width - spacing.lg * 2 - spacing.md) / 2);

  useEffect(() => {
    let cancelled = false;
    async function loadCover() {
      const path = assetPath(archive.assets?.cover);
      if (!path) {
        setImageSource(null);
        return;
      }
      const source = await buildAuthorizedImageSource(path);
      if (!cancelled) {
        setImageSource(source);
      }
    }
    loadCover().catch(error => console.warn('Failed to load cover:', error));
    return () => {
      cancelled = true;
    };
  }, [archive.assets?.cover]);

  const progressLabel =
    archive.pagecount > 0 && archive.progress > 0
      ? `${Math.min(archive.progress, archive.pagecount)} / ${archive.pagecount}`
      : `${archive.pagecount || 0} pages`;

  async function toggleFavorite() {
    const next = !favorite;
    setFavorite(next);
    try {
      await setArchiveFavorite(archive, next);
      onChanged?.();
    } catch (error) {
      setFavorite(!next);
      console.warn(extractApiError(error));
    }
  }

  return (
    <TouchableOpacity
      style={[styles.card, {width: itemWidth}]}
      onPress={onPress}
      activeOpacity={0.82}>
      <View style={styles.coverWrap}>
        {imageSource ? (
          <Image source={imageSource} style={styles.cover} resizeMode="cover" />
        ) : (
          <View style={styles.placeholder}>
            <Text style={styles.placeholderText}>No Cover</Text>
          </View>
        )}
        {archive.isnew ? (
          <View style={styles.badge}>
            <Text style={styles.badgeText}>NEW</Text>
          </View>
        ) : null}
      </View>
      <View style={styles.body}>
        <Text numberOfLines={2} style={styles.title}>
          {archive.title || archive.filename || archive.arcid}
        </Text>
        <Text numberOfLines={1} style={styles.meta}>
          {progressLabel}
        </Text>
      </View>
      <TouchableOpacity
        accessibilityRole="button"
        accessibilityLabel={favorite ? 'Remove favorite' : 'Add favorite'}
        onPress={toggleFavorite}
        style={styles.favoriteButton}>
        <Text style={[styles.favoriteText, favorite && styles.favoriteActive]}>
          {favorite ? '★' : '☆'}
        </Text>
      </TouchableOpacity>
    </TouchableOpacity>
  );
}

const styles = StyleSheet.create({
  card: {
    backgroundColor: colors.surface,
    borderColor: colors.border,
    borderRadius: radius.md,
    borderWidth: StyleSheet.hairlineWidth,
    marginBottom: spacing.md,
    overflow: 'hidden',
  },
  coverWrap: {
    aspectRatio: 0.72,
    backgroundColor: colors.surfaceMuted,
  },
  cover: {
    height: '100%',
    width: '100%',
  },
  placeholder: {
    alignItems: 'center',
    flex: 1,
    justifyContent: 'center',
  },
  placeholderText: {
    color: colors.textMuted,
    fontSize: 12,
  },
  badge: {
    backgroundColor: colors.primary,
    borderRadius: 4,
    left: 8,
    paddingHorizontal: 6,
    paddingVertical: 3,
    position: 'absolute',
    top: 8,
  },
  badgeText: {
    color: colors.white,
    fontSize: 10,
    fontWeight: '800',
  },
  body: {
    gap: 4,
    minHeight: 72,
    padding: spacing.sm,
  },
  title: {
    color: colors.text,
    fontSize: 14,
    fontWeight: '700',
    lineHeight: 18,
  },
  meta: {
    color: colors.textMuted,
    fontSize: 12,
  },
  favoriteButton: {
    bottom: 8,
    position: 'absolute',
    right: 8,
  },
  favoriteText: {
    color: colors.textMuted,
    fontSize: 24,
    textShadowColor: colors.white,
    textShadowRadius: 2,
  },
  favoriteActive: {
    color: '#f2a900',
  },
});
