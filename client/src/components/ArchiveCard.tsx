import React, {useEffect, useState} from 'react';
import {
  Modal,
  Pressable,
  ScrollView,
  StyleSheet,
  Text,
  TouchableOpacity,
  useWindowDimensions,
  View,
} from 'react-native';
import FastImage, {type Source as FastImageSource} from '@d11/react-native-fast-image';

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

export function ArchiveCard({archive, onPress, variant = 'grid', onChanged, onTagPress}: Props) {
  const {t} = useI18n();
  const {width} = useWindowDimensions();
  const [imageSource, setImageSource] = useState<FastImageSource | null>(null);
  const [imageError, setImageError] = useState('');
  const [favorite, setFavorite] = useState(Boolean(archive.isfavorite));
  const [tagsOpen, setTagsOpen] = useState(false);
  const itemWidth =
    variant === 'row'
      ? 136
      : variant === 'grid'
        ? Math.floor((width - spacing.lg * 2 - spacing.md) / 2)
        : width - spacing.lg * 2;
  const title = mediaItemTitle(archive);
  const isCollection = isTankoubon(archive);
  const allTags = parseTags((archive as Archive).tags);

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

  return (
    <>
      <TouchableOpacity
        style={[
          styles.card,
          {width: itemWidth},
          variant !== 'grid' && variant !== 'row' && styles.fullWidthCard,
          variant === 'list' && styles.listCard,
          variant === 'tweet' && styles.tweetCard,
          variant === 'channel' && styles.channelCard,
        ]}
        onPress={onPress}
        onLongPress={() => {
          if (allTags.length > 0) {
            setTagsOpen(true);
          }
        }}
        delayLongPress={650}
        activeOpacity={0.82}>
        <View
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
        </View>
        <View style={styles.body}>
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
        </View>
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
      </TouchableOpacity>

      <Modal
        animationType="fade"
        onRequestClose={() => setTagsOpen(false)}
        transparent
        visible={tagsOpen}>
        <Pressable style={styles.modalBackdrop} onPress={() => setTagsOpen(false)}>
          <Pressable style={styles.tagSheet}>
            <View style={styles.tagSheetHeader}>
              <View style={styles.tagSheetTitleWrap}>
                <Text style={styles.tagSheetTitle}>{t('archive.tags')}</Text>
                <Text numberOfLines={1} style={styles.tagSheetSubtitle}>{title}</Text>
              </View>
              <TouchableOpacity
                accessibilityLabel={t('common.close')}
                accessibilityRole="button"
                onPress={() => setTagsOpen(false)}
                style={styles.closeButton}>
                <Text style={styles.closeButtonText}>x</Text>
              </TouchableOpacity>
            </View>
            <ScrollView contentContainerStyle={styles.tagList}>
              {allTags.map(tag => (
                <TouchableOpacity
                  accessibilityRole="button"
                  key={tag}
                  onPress={() => {
                    setTagsOpen(false);
                    onTagPress?.(tag);
                  }}
                  style={styles.tagChip}>
                  <Text numberOfLines={1} style={styles.tagText}>{stripNamespace(tag)}</Text>
                  {tag.includes(':') ? (
                    <Text numberOfLines={1} style={styles.tagNamespace}>
                      {tag.slice(0, tag.indexOf(':'))}
                    </Text>
                  ) : null}
                </TouchableOpacity>
              ))}
            </ScrollView>
          </Pressable>
        </Pressable>
      </Modal>
    </>
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
  modalBackdrop: {
    backgroundColor: 'rgba(0, 0, 0, 0.28)',
    flex: 1,
    justifyContent: 'flex-end',
  },
  tagSheet: {
    backgroundColor: colors.surface,
    borderTopLeftRadius: 12,
    borderTopRightRadius: 12,
    maxHeight: '62%',
    padding: spacing.lg,
  },
  tagSheetHeader: {
    alignItems: 'center',
    flexDirection: 'row',
    gap: spacing.md,
    marginBottom: spacing.md,
  },
  tagSheetTitleWrap: {
    flex: 1,
    gap: 2,
    minWidth: 0,
  },
  tagSheetTitle: {
    color: colors.text,
    fontSize: 16,
    fontWeight: '800',
  },
  tagSheetSubtitle: {
    color: colors.textMuted,
    fontSize: 12,
  },
  closeButton: {
    alignItems: 'center',
    backgroundColor: colors.surfaceMuted,
    borderColor: colors.border,
    borderRadius: 16,
    borderWidth: StyleSheet.hairlineWidth,
    height: 32,
    justifyContent: 'center',
    width: 32,
  },
  closeButtonText: {
    color: colors.text,
    fontSize: 18,
    fontWeight: '700',
    lineHeight: 20,
  },
  tagList: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: spacing.sm,
    paddingBottom: spacing.sm,
  },
  tagChip: {
    backgroundColor: colors.surfaceMuted,
    borderColor: colors.border,
    borderRadius: 8,
    borderWidth: StyleSheet.hairlineWidth,
    maxWidth: '100%',
    paddingHorizontal: spacing.sm,
    paddingVertical: 7,
  },
  tagText: {
    color: colors.text,
    fontSize: 13,
    fontWeight: '700',
  },
  tagNamespace: {
    color: colors.textMuted,
    fontSize: 10,
    marginTop: 1,
  },
});
