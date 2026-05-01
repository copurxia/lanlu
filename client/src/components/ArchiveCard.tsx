import React, {useEffect, useState} from 'react';
import {
  ScrollView,
  StyleSheet,
  Text,
  TouchableOpacity,
  useWindowDimensions,
  View,
} from 'react-native';
import FastImage, {type Source as FastImageSource} from '@d11/react-native-fast-image';
import {Gesture, GestureDetector} from 'react-native-gesture-handler';
import Animated, {
  runOnJS,
  useAnimatedStyle,
  useSharedValue,
  withTiming,
} from 'react-native-reanimated';

import {
  assetPath,
  isTankoubon,
  mediaItemCoverAsset,
  mediaItemId,
  mediaItemTitle,
  setArchiveFavorite,
} from '../api/lanlu';
import {buildAuthorizedImageSource, extractApiError} from '../api/client';
import {useI18n} from '../i18n';
import {colors, radius, spacing} from '../theme/colors';
import type {Archive, MediaItem} from '../types/api';

type Props = {
  archive: MediaItem;
  onPress: () => void;
  onOpenDetail?: () => void;
  onOpenReader?: () => void;
  variant?: 'grid' | 'list' | 'tweet' | 'channel' | 'row';
  onChanged?: () => void;
  onTagPress?: (tag: string) => void;
};

function parseTags(rawTags: unknown): string[] {
  if (Array.isArray(rawTags)) {
    return rawTags.map(tag => String(tag).trim()).filter(Boolean);
  }
  if (!rawTags) return [];
  return String(rawTags)
    .split(',')
    .map(tag => tag.trim())
    .filter(Boolean);
}

function stripNamespace(tag: string) {
  const index = tag.indexOf(':');
  return index > 0 ? tag.slice(index + 1) : tag;
}

export function ArchiveCard({
  archive,
  onPress,
  onOpenDetail,
  onOpenReader,
  variant = 'grid',
  onChanged,
  onTagPress,
}: Props) {
  const {t} = useI18n();
  const {width} = useWindowDimensions();
  const [imageSource, setImageSource] = useState<FastImageSource | null>(null);
  const [imageError, setImageError] = useState('');
  const [favorite, setFavorite] = useState(Boolean(archive.isfavorite));
  const [tagsOpen, setTagsOpen] = useState(false);
  const pressed = useSharedValue(0);
  const tagProgress = useSharedValue(0);
  const itemWidth =
    variant === 'row'
      ? 136
      : variant === 'grid'
        ? Math.floor((width - spacing.lg * 2 - spacing.md) / 2)
        : width - spacing.lg * 2;
  const title = mediaItemTitle(archive);
  const isCollection = isTankoubon(archive);
  const allTags = parseTags((archive as Archive).tags);
  const visibleTags = allTags.filter(tag => {
    const lowered = tag.toLowerCase();
    return !lowered.includes('source') && !stripNamespace(lowered).includes('source');
  });

  useEffect(() => {
    tagProgress.value = withTiming(tagsOpen ? 1 : 0, {duration: 160});
  }, [tagProgress, tagsOpen]);

  const cardAnimatedStyle = useAnimatedStyle(() => ({
    transform: [{scale: withTiming(pressed.value ? 0.985 : 1, {duration: 120})}],
  }));

  const tagOverlayStyle = useAnimatedStyle(() => ({
    opacity: tagProgress.value,
    transform: [{translateY: (1 - tagProgress.value) * 10}],
  }));

  useEffect(() => {
    let cancelled = false;
    async function loadCover() {
      const path = assetPath(mediaItemCoverAsset(archive));
      if (!path) {
        setImageSource(null);
        return;
      }
      const source = await buildAuthorizedImageSource(path);
      if (!cancelled) {
        setImageError('');
        setImageSource(source);
      }
    }
    loadCover().catch(error => console.warn('Failed to load cover:', error));
    return () => {
      cancelled = true;
    };
  }, [archive]);

  const pagecount = Number(archive.pagecount || 0);
  const progress = Number(archive.progress || 0);
  const progressLabel = isCollection
    ? t('common.archives', {count: archive.children?.length || 0})
    : pagecount > 0 && progress > 0
      ? `${Math.min(progress, pagecount)} / ${pagecount}`
      : t('common.pages', {count: pagecount || 0});

  async function toggleFavorite() {
    if (isCollection) {
      return;
    }
    const next = !favorite;
    setFavorite(next);
    try {
      await setArchiveFavorite(archive as Archive, next);
      onChanged?.();
    } catch (error) {
      setFavorite(!next);
      console.warn(extractApiError(error));
    }
  }

  function handleCardPress() {
    if (tagsOpen) {
      setTagsOpen(false);
      return;
    }
    (onOpenReader || onPress)();
  }

  function handleBodyPress() {
    if (tagsOpen) {
      setTagsOpen(false);
      return;
    }
    (onOpenDetail || onPress)();
  }

  function showTags() {
    if (visibleTags.length > 0) {
      setTagsOpen(true);
    }
  }

  const cardGesture = Gesture.Exclusive(
    Gesture.LongPress()
      .minDuration(650)
      .onBegin(() => {
        pressed.value = 1;
      })
      .onFinalize((_event, success) => {
        pressed.value = 0;
        if (success) {
          runOnJS(showTags)();
        }
      }),
    Gesture.Tap().onEnd(() => {
      runOnJS(handleCardPress)();
    }),
  );

  return (
    <Animated.View
      style={[
        styles.card,
        {width: itemWidth},
        variant !== 'grid' && variant !== 'row' && styles.fullWidthCard,
        variant === 'list' && styles.listCard,
        variant === 'tweet' && styles.tweetCard,
        variant === 'channel' && styles.channelCard,
        cardAnimatedStyle,
      ]}
    >
        <GestureDetector gesture={cardGesture}>
          <Animated.View
            style={[
              styles.coverWrap,
              variant === 'list' && styles.listCover,
              variant === 'tweet' && styles.tweetCover,
              variant === 'channel' && styles.channelCover,
            ]}>
            {imageSource ? (
              <FastImage
                source={{
                  ...imageSource,
                  cache: FastImage.cacheControl.web,
                  priority: FastImage.priority.normal,
                }}
                style={styles.cover}
                resizeMode={FastImage.resizeMode.cover}
                onError={event => {
                  const message = event.nativeEvent.error || 'Image failed to load';
                  setImageError(message);
                  console.warn('Cover failed to load:', mediaItemId(archive), message);
                }}
              />
            ) : (
              <View style={styles.placeholder}>
                <Text style={styles.placeholderText}>{t('common.noCover')}</Text>
              </View>
            )}
            {imageError ? (
              <View style={styles.placeholderOverlay}>
                <Text style={styles.placeholderText}>{t('common.noCover')}</Text>
              </View>
            ) : null}
            {!isCollection && archive.isnew ? (
              <View style={styles.badge}>
                <Text style={styles.badgeText}>NEW</Text>
              </View>
            ) : null}
            {isCollection ? (
              <View style={styles.collectionBadge}>
                <Text style={styles.badgeText}>{t('home.rows').toUpperCase()}</Text>
              </View>
            ) : null}
            {visibleTags.length > 0 ? (
              <Animated.View
                pointerEvents={tagsOpen ? 'auto' : 'none'}
                style={[styles.tagOverlay, tagOverlayStyle]}>
                <View style={styles.tagFadeTop} />
                <View style={styles.tagOverlayContent}>
                  <ScrollView
                    contentContainerStyle={styles.tagList}
                    horizontal
                    showsHorizontalScrollIndicator={false}>
                    {visibleTags.map(tag => (
                      <TouchableOpacity
                        accessibilityRole="button"
                        key={tag}
                        onPress={() => {
                          setTagsOpen(false);
                          onTagPress?.(tag);
                        }}
                        style={styles.tagChip}>
                        <Text numberOfLines={1} style={styles.tagText}>
                          {stripNamespace(tag)}
                        </Text>
                      </TouchableOpacity>
                    ))}
                  </ScrollView>
                </View>
              </Animated.View>
            ) : null}
          </Animated.View>
        </GestureDetector>
        <TouchableOpacity activeOpacity={0.78} onPress={handleBodyPress} style={styles.body}>
          <Text numberOfLines={2} style={styles.title}>
            {title}
          </Text>
          <Text numberOfLines={1} style={styles.meta}>
            {progressLabel}
          </Text>
          {(variant === 'tweet' || variant === 'channel') && archive.description ? (
            <Text numberOfLines={3} style={styles.description}>
              {archive.description}
            </Text>
          ) : null}
        </TouchableOpacity>
        {!isCollection ? (
          <TouchableOpacity
            accessibilityRole="button"
            accessibilityLabel={favorite ? 'Remove favorite' : 'Add favorite'}
            onPress={toggleFavorite}
            style={styles.favoriteButton}>
            <Text style={[styles.favoriteText, favorite && styles.favoriteActive]}>
              {favorite ? '★' : '☆'}
            </Text>
          </TouchableOpacity>
        ) : null}
    </Animated.View>
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
  fullWidthCard: {
    marginBottom: spacing.sm,
  },
  listCard: {
    flexDirection: 'row',
    minHeight: 112,
  },
  tweetCard: {
    borderRadius: radius.md,
  },
  channelCard: {
    borderRadius: radius.md,
  },
  coverWrap: {
    aspectRatio: 0.72,
    backgroundColor: colors.surfaceMuted,
  },
  listCover: {
    aspectRatio: 0.72,
    width: 82,
  },
  tweetCover: {
    aspectRatio: 1.35,
  },
  channelCover: {
    aspectRatio: 1.65,
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
  placeholderOverlay: {
    alignItems: 'center',
    backgroundColor: colors.surfaceMuted,
    bottom: 0,
    justifyContent: 'center',
    left: 0,
    position: 'absolute',
    right: 0,
    top: 0,
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
  collectionBadge: {
    backgroundColor: colors.text,
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
  description: {
    color: colors.textMuted,
    fontSize: 13,
    lineHeight: 18,
    marginTop: 4,
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
  tagOverlay: {
    bottom: 0,
    left: 0,
    minHeight: 92,
    overflow: 'hidden',
    position: 'absolute',
    right: 0,
  },
  tagFadeTop: {
    backgroundColor: 'rgba(0, 0, 0, 0.18)',
    flex: 1,
  },
  tagOverlayContent: {
    backgroundColor: 'rgba(0, 0, 0, 0.58)',
    paddingBottom: 36,
    paddingHorizontal: spacing.sm,
    paddingTop: spacing.sm,
  },
  tagList: {
    alignItems: 'center',
    flexDirection: 'row',
    gap: spacing.sm,
  },
  tagChip: {
    backgroundColor: 'rgba(255, 255, 255, 0.16)',
    borderColor: 'rgba(255, 255, 255, 0.22)',
    borderRadius: 4,
    borderWidth: StyleSheet.hairlineWidth,
    maxWidth: 140,
    paddingHorizontal: 6,
    paddingVertical: 3,
  },
  tagText: {
    color: colors.white,
    fontSize: 11,
    fontWeight: '700',
  },
});
