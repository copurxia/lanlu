import React, {useMemo} from 'react';
import {StyleSheet, Text, TouchableOpacity, View} from 'react-native';
import FastImage, {type Source as FastImageSource} from '@d11/react-native-fast-image';

import {useTheme} from '../../theme/ThemeContext';
import type {TFunction} from '../../i18n';
import type {Archive} from '../../types/api';

type Props = {
  archive: Archive;
  cover: FastImageSource | null;
  selected: boolean;
  selectionMode: boolean;
  onPress: () => void;
  onToggleSelect?: () => void;
  onRemove?: () => void;
  removing?: boolean;
  t: TFunction;
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

export function TankoubonArchiveListItem({
  archive,
  cover,
  selected,
  selectionMode,
  onPress,
  onToggleSelect,
  onRemove,
  removing,
  t,
}: Props) {
  const {colors} = useTheme();
  const progress = Number(archive.progress || 0);
  const pagecount = Number(archive.pagecount || 0);
  const progressPercent = pagecount > 0 && progress > 0 ? Math.round((progress / pagecount) * 100) : 0;
  const tags = parseTags(archive.tags).slice(0, 4);

  const styles = useMemo(
    () =>
      StyleSheet.create({
        item: {
          alignItems: 'center',
          backgroundColor: colors.surface,
          borderColor: colors.border,
          borderRadius: 8,
          borderWidth: StyleSheet.hairlineWidth,
          flexDirection: 'row',
          gap: 12,
          padding: 12,
        },
        itemSelected: {
          borderColor: colors.primary,
          borderWidth: 2,
        },
        coverFrame: {
          aspectRatio: 0.72,
          backgroundColor: colors.surfaceMuted,
          borderRadius: 6,
          height: 80,
          overflow: 'hidden',
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
          fontSize: 10,
        },
        body: {
          flex: 1,
          gap: 4,
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
        tags: {
          flexDirection: 'row',
          flexWrap: 'wrap',
          gap: 4,
        },
        tag: {
          backgroundColor: colors.primaryMuted,
          borderRadius: 4,
          paddingHorizontal: 6,
          paddingVertical: 2,
        },
        tagText: {
          color: colors.primary,
          fontSize: 10,
          fontWeight: '600',
        },
        removeButton: {
          alignItems: 'center',
          height: 32,
          justifyContent: 'center',
          width: 32,
        },
        removeButtonText: {
          color: colors.danger,
          fontSize: 20,
          fontWeight: '700',
        },
      }),
    [colors],
  );

  return (
    <TouchableOpacity
      style={[styles.item, selected && styles.itemSelected]}
      onPress={onPress}
      disabled={removing}
      activeOpacity={0.7}>
      <View style={styles.coverFrame}>
        {cover ? (
          <FastImage
            source={cover}
            resizeMode={FastImage.resizeMode.cover}
            style={styles.cover}
          />
        ) : (
          <View style={styles.coverPlaceholder}>
            <Text style={styles.coverPlaceholderText}>{t('common.noCover')}</Text>
          </View>
        )}
      </View>
      <View style={styles.body}>
        <Text style={styles.title} numberOfLines={2}>
          {archive.title || archive.filename}
        </Text>
        <Text style={styles.meta}>
          {pagecount > 0 ? `${pagecount} pages` : ''}
          {progressPercent > 0 ? ` • ${progressPercent}%` : ''}
        </Text>
        {tags.length > 0 ? (
          <View style={styles.tags}>
            {tags.map(tag => (
              <View key={tag} style={styles.tag}>
                <Text style={styles.tagText}>{stripNamespace(tag)}</Text>
              </View>
            ))}
          </View>
        ) : null}
      </View>
      {onRemove ? (
        <TouchableOpacity
          style={styles.removeButton}
          onPress={onRemove}
          disabled={removing}>
          <Text style={styles.removeButtonText}>−</Text>
        </TouchableOpacity>
      ) : null}
    </TouchableOpacity>
  );
}

