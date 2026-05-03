import React, {useMemo} from 'react';
import {StyleSheet, Text, TouchableOpacity, View} from 'react-native';
import FastImage, {type Source as FastImageSource} from '@d11/react-native-fast-image';

import {assetPath, archiveCoverAsset, mediaItemTitle} from '../../api/lanlu';
import {useTheme} from '../../theme/ThemeContext';
import type {TFunction} from '../../i18n';
import type {Archive} from '../../types/api';

type Props = {
  archive: Archive;
  cover: FastImageSource | null;
  selected: boolean;
  selectionMode: boolean;
  onPress: () => void;
  onLongPress?: () => void;
  onToggleSelect?: () => void;
  onRemove?: () => void;
  removing?: boolean;
  t: TFunction;
};

export function TankoubonArchiveGridCard({
  archive,
  cover,
  selected,
  selectionMode,
  onPress,
  onLongPress,
  onToggleSelect,
  onRemove,
  removing,
  t,
}: Props) {
  const {colors} = useTheme();
  const progress = Number(archive.progress || 0);
  const pagecount = Number(archive.pagecount || 0);
  const progressPercent = pagecount > 0 && progress > 0 ? Math.round((progress / pagecount) * 100) : 0;

  const styles = useMemo(
    () =>
      StyleSheet.create({
        card: {
          backgroundColor: colors.surface,
          borderColor: colors.border,
          borderRadius: 8,
          borderWidth: StyleSheet.hairlineWidth,
          overflow: 'hidden',
          paddingBottom: 8,
        },
        cardSelected: {
          borderColor: colors.primary,
          borderWidth: 2,
        },
        coverFrame: {
          aspectRatio: 0.72,
          backgroundColor: colors.surfaceMuted,
          width: '100%',
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
          fontSize: 11,
        },
        selectedOverlay: {
          ...StyleSheet.absoluteFill,
          alignItems: 'center',
          backgroundColor: 'rgba(0,120,212,0.3)',
          justifyContent: 'center',
        },
        selectedCheck: {
          color: colors.white,
          fontSize: 24,
          fontWeight: '800',
        },
        title: {
          color: colors.text,
          fontSize: 12,
          fontWeight: '600',
          lineHeight: 16,
          paddingHorizontal: 8,
          paddingTop: 6,
        },
        meta: {
          color: colors.textMuted,
          fontSize: 11,
          paddingHorizontal: 8,
          paddingTop: 2,
        },
      }),
    [colors],
  );

  return (
    <TouchableOpacity
      style={[styles.card, selected && styles.cardSelected]}
      onPress={onPress}
      onLongPress={onLongPress}
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
        {selected && selectionMode ? (
          <View style={styles.selectedOverlay}>
            <Text style={styles.selectedCheck}>✓</Text>
          </View>
        ) : null}
      </View>
      <Text style={styles.title} numberOfLines={2}>
        {archive.title || archive.filename}
      </Text>
      <Text style={styles.meta}>
        {pagecount > 0 ? `${pagecount} pages` : ''}
        {progressPercent > 0 ? ` • ${progressPercent}%` : ''}
      </Text>
    </TouchableOpacity>
  );
}

