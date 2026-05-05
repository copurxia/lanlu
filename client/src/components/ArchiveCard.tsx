import React, {useEffect, useMemo, useRef, useState} from 'react';
import {
  StyleSheet,
  Text,
  TouchableOpacity,
  useWindowDimensions,
  View,
} from 'react-native';
import FastImage, {type Source as FastImageSource} from '@d11/react-native-fast-image';
import Svg, {Defs, LinearGradient, Rect, Stop} from 'react-native-svg';
import Animated, {
  useAnimatedStyle,
  useSharedValue,
  withTiming,
} from 'react-native-reanimated';
import {Check, Eye, Heart, Square} from 'lucide-react-native';

import {
  isTankoubon,
  mediaItemCoverAsset,
  mediaItemId,
  mediaItemTitle,
  setArchiveFavorite,
  setTankoubonFavorite,
} from '../api/lanlu';
import {buildAuthorizedAssetImageSource, extractApiError} from '../api/client';
import {useI18n} from '../i18n';
import {radius, spacing} from '../theme/colors';
import {useTheme} from '../theme/ThemeContext';
import type {Archive, MediaItem} from '../types/api';

type Props = {
  archive: MediaItem;
  onPress?: () => void;
  onOpenDetail?: () => void;
  onOpenReader?: () => void;
  variant?: 'grid' | 'list' | 'tweet' | 'channel' | 'row' | 'related';
  onChanged?: () => void;
  onTagPress?: (tag: string) => void;
  selectable?: boolean;
  selectionMode?: boolean;
  selected?: boolean;
  onToggleSelect?: () => void;
  onLongPress?: () => void;
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
  selectable = false,
  selectionMode = false,
  selected = false,
  onToggleSelect,
  onLongPress,
}: Props) {
  const {colors} = useTheme();
  const {t} = useI18n();
  const {width} = useWindowDimensions();
  const [imageSource, setImageSource] = useState<FastImageSource | null>(null);
  const [imageError, setImageError] = useState('');
  const [favoriteState, setFavoriteState] = useState(Boolean(archive.isfavorite));
  const [tagsOpen, setTagsOpen] = useState(false);
  const [coverTouching, setCoverTouching] = useState(false);
  const pressed = useSharedValue(0);
  const tagProgress = useSharedValue(0);
  const coverLongPressTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const selectionLongPressTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const itemWidth =
    variant === 'row'
      ? 136
      : variant === 'grid'
        ? Math.floor((width - spacing.lg * 2 - spacing.md) / 2)
        : variant === 'related'
          ? 120
          : width - spacing.lg * 2;
  const title = mediaItemTitle(archive);
  const isCollection = isTankoubon(archive);
  const itemId = mediaItemId(archive);
  const gradientId = `archive-card-preview-${itemId.replace(/[^a-zA-Z0-9_-]/g, '-')}`;
  const allTags = parseTags((archive as Archive).tags);
  const maxPreviewTags = archive.description ? 5 : 8;
  const visibleTags = allTags.filter(tag => {
    const lowered = tag.toLowerCase();
    return !lowered.includes('source') && !stripNamespace(lowered).includes('source');
  });
  const previewTags = visibleTags.slice(0, maxPreviewTags);
  const showActions = tagsOpen;

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
      const source = await buildAuthorizedAssetImageSource(mediaItemCoverAsset(archive));
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

  useEffect(() => {
    return () => {
      clearCoverLongPressTimers();
    };
  }, []);

  const pagecount = Number(archive.pagecount || 0);
  const progress = Number(archive.progress || 0);
  const progressPercent =
    pagecount > 0 && progress > 0
      ? Math.round((Math.min(progress, pagecount) / pagecount) * 100)
      : 0;
  const progressLabel = isCollection
    ? progressPercent > 0
      ? `${t('common.archives', {count: archive.children?.length || 0})}  •  ${progressPercent}%`
      : t('common.archives', {count: archive.children?.length || 0})
    : pagecount > 0 && progress > 0
      ? `${t('common.pages', {count: pagecount})}  •  ${progressPercent}%`
      : t('common.pages', {count: pagecount || 0});

  async function toggleFavorite() {
    const next = !favoriteState;
    setFavoriteState(next);
    try {
      if (isCollection) {
        await setTankoubonFavorite(archive.tankoubon_id, next);
      } else {
        await setArchiveFavorite(archive as Archive, next);
      }
      onChanged?.();
    } catch (error) {
      setFavoriteState(!next);
      console.warn(extractApiError(error));
    }
  }

  function handleBodyPress() {
    if (tagsOpen) {
      setTagsOpen(false);
      return;
    }
    if (selectionMode && selectable) {
      onToggleSelect?.();
      return;
    }
    const handler = onOpenDetail || onPress;
    if (handler) handler();
  }

  function showTags() {
    setTagsOpen(true);
  }

  function clearCoverLongPressTimers() {
    if (coverLongPressTimerRef.current) {
      clearTimeout(coverLongPressTimerRef.current);
      coverLongPressTimerRef.current = null;
    }
    if (selectionLongPressTimerRef.current) {
      clearTimeout(selectionLongPressTimerRef.current);
      selectionLongPressTimerRef.current = null;
    }
  }

  function handleCoverPressIn() {
    if (selectionMode) return;
    setCoverTouching(true);
    pressed.value = 1;
    clearCoverLongPressTimers();
    coverLongPressTimerRef.current = setTimeout(() => {
      coverLongPressTimerRef.current = null;
      showTags();
    }, 450);
    if (selectable) {
      selectionLongPressTimerRef.current = setTimeout(() => {
        selectionLongPressTimerRef.current = null;
        setTagsOpen(false);
        onLongPress?.();
      }, 1500);
    }
  }

  function handleCoverPressOut() {
    setCoverTouching(false);
    pressed.value = 0;
    clearCoverLongPressTimers();
  }

  function handleCoverPress() {
    if (tagsOpen) {
      setTagsOpen(false);
      return;
    }
    if (selectionMode && selectable) {
      onToggleSelect?.();
      return;
    }
    const handler = onOpenReader || onPress;
    if (handler) handler();
  }

  const styles = useMemo(
    () =>
      StyleSheet.create({
        card: {
          borderRadius: radius.md,
          marginBottom: spacing.md,
          overflow: 'hidden',
        },
        cardSelected: {
          borderColor: colors.primary,
          borderWidth: 2,
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
          borderRadius: radius.md,
          overflow: 'hidden',
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
          flex: 1,
          minHeight: 72,
          padding: spacing.sm,
        },
        bodyList: {
          justifyContent: 'center',
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
        actionButtons: {
          bottom: 8,
          flexDirection: 'row',
          gap: 8,
          left: 8,
          position: 'absolute',
        },
        actionButton: {
          alignItems: 'center',
          backgroundColor: 'rgba(255,255,255,0.15)',
          borderRadius: 18,
          height: 32,
          justifyContent: 'center',
          width: 32,
        },
        actionButtonActive: {
          backgroundColor: 'rgba(255,255,255,0.25)',
        },
        tagOverlay: {
          bottom: 0,
          left: 0,
          position: 'absolute',
          right: 0,
          top: 0,
        },
        gradientOverlay: {
          bottom: 0,
          left: 0,
          position: 'absolute',
          right: 0,
          top: 0,
        },
        tagOverlayContent: {
          bottom: 0,
          gap: 7,
          left: 0,
          paddingBottom: 48,
          paddingHorizontal: 12,
          paddingTop: 18,
          position: 'absolute',
          right: 0,
        },
        tagList: {
          alignItems: 'center',
          flexDirection: 'row',
          flexWrap: 'wrap',
          gap: 5,
          overflow: 'hidden',
        },
        tagListTall: {
          maxHeight: 74,
        },
        tagListWithDescription: {
          maxHeight: 50,
        },
        tagChip: {
          backgroundColor: 'rgba(255, 255, 255, 0.16)',
          borderRadius: 3,
          maxWidth: 140,
          paddingHorizontal: 7,
          paddingVertical: 2,
        },
        tagText: {
          color: colors.white,
          fontSize: 11,
          lineHeight: 15,
        },
        previewDescription: {
          color: 'rgba(255, 255, 255, 0.9)',
          fontSize: 11,
          lineHeight: 15,
        },
        relatedCard: {
          marginBottom: 0,
        },
        selectionOverlay: {
          backgroundColor: 'rgba(0,0,0,0.45)',
          borderRadius: radius.md,
          bottom: 0,
          left: 0,
          position: 'absolute',
          right: 0,
          top: 0,
          zIndex: 20,
        },
        checkbox: {
          alignItems: 'center',
          backgroundColor: 'rgba(255,255,255,0.15)',
          borderRadius: 14,
          height: 28,
          justifyContent: 'center',
          left: 8,
          position: 'absolute',
          top: 8,
          width: 28,
          zIndex: 30,
        },
        checkboxSelected: {
          backgroundColor: colors.primary,
        },
      }),
    [colors],
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
        variant === 'related' && styles.relatedCard,
        selected && styles.cardSelected,
        cardAnimatedStyle,
      ]}
    >
      <TouchableOpacity
        activeOpacity={1}
        onPress={handleCoverPress}
        onPressIn={handleCoverPressIn}
        onPressOut={handleCoverPressOut}
        style={[
          styles.coverWrap,
          variant === 'list' && styles.listCover,
          variant === 'tweet' && styles.tweetCover,
          variant === 'channel' && styles.channelCover,
        ]}>
        {imageSource ? (
          <FastImage
            source={imageSource}
            style={styles.cover}
            resizeMode={FastImage.resizeMode.cover}
            onError={event => {
              const message = event.nativeEvent.error || 'Image failed to load';
              setImageError(message);
              console.warn('Cover failed to load:', itemId, message);
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

        {selectable ? (
          <TouchableOpacity
            style={[styles.checkbox, selected && styles.checkboxSelected]}
            onPress={() => {
              if (!selected && !selectionMode) {
                onLongPress?.();
              }
              onToggleSelect?.();
            }}>
            {selected ? (
              <Check color={colors.white} size={16} />
            ) : (
              <Square color={colors.white} size={14} />
            )}
          </TouchableOpacity>
        ) : null}

        {selectionMode && !selected && selectable ? <View style={styles.selectionOverlay} /> : null}

        {visibleTags.length > 0 || archive.description ? (
          <Animated.View
            pointerEvents={coverTouching ? 'none' : tagsOpen ? 'auto' : 'none'}
            style={[styles.tagOverlay, tagOverlayStyle]}>
            <Svg height="100%" pointerEvents="none" style={styles.gradientOverlay} width="100%">
              <Defs>
                <LinearGradient id={gradientId} x1="0" x2="0" y1="0" y2="1">
                  <Stop offset="0" stopColor="#000000" stopOpacity="0" />
                  <Stop offset="0.38" stopColor="#000000" stopOpacity="0.18" />
                  <Stop offset="0.68" stopColor="#000000" stopOpacity="0.52" />
                  <Stop offset="1" stopColor="#000000" stopOpacity="0.78" />
                </LinearGradient>
              </Defs>
              <Rect fill={`url(#${gradientId})`} height="100%" width="100%" x="0" y="0" />
            </Svg>
            <View style={styles.tagOverlayContent}>
              {previewTags.length > 0 ? (
                <View style={[styles.tagList, archive.description ? styles.tagListWithDescription : styles.tagListTall]}>
                  {previewTags.map(tag => (
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
                  {visibleTags.length > previewTags.length ? (
                    <View style={styles.tagChip}>
                      <Text numberOfLines={1} style={styles.tagText}>
                        +{visibleTags.length - previewTags.length}
                      </Text>
                    </View>
                  ) : null}
                </View>
              ) : null}
              {archive.description ? (
                <Text numberOfLines={3} style={styles.previewDescription}>
                  {archive.description}
                </Text>
              ) : null}
            </View>
          </Animated.View>
        ) : null}

        {showActions ? (
          <View style={styles.actionButtons}>
            {onOpenDetail ? (
              <TouchableOpacity
                accessibilityRole="button"
                onPress={handleBodyPress}
                style={styles.actionButton}>
                <Eye color={colors.white} size={16} />
              </TouchableOpacity>
            ) : null}
            <TouchableOpacity
              accessibilityRole="button"
              accessibilityLabel={favoriteState ? 'Remove favorite' : 'Add favorite'}
              onPress={toggleFavorite}
              style={[styles.actionButton, favoriteState && styles.actionButtonActive]}>
              <Heart
                color={favoriteState ? '#f87171' : colors.white}
                fill={favoriteState ? '#f87171' : 'transparent'}
                size={16}
              />
            </TouchableOpacity>
          </View>
        ) : null}
      </TouchableOpacity>
      <TouchableOpacity activeOpacity={0.78} onPress={handleBodyPress} style={[styles.body, variant === 'list' && styles.bodyList]}>
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
    </Animated.View>
  );
}
