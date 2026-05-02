import React, {useCallback, useState} from 'react';
import {Alert, Linking, StyleSheet, Text, TouchableOpacity, View} from 'react-native';
import {Download, Heart} from 'lucide-react-native';

import {colors} from '../../theme/colors';
import type {TFunction} from '../../i18n';
import type {ArchiveMetadata} from '../../types/api';

type Props = {
  metadata: ArchiveMetadata;
  favorite: boolean;
  favoriteLoading: boolean;
  onToggleFavorite: () => void;
  onStartReading: () => void;
  onDownload: () => void;
  onMarkAsRead?: () => void;
  onMarkAsNew?: () => void;
  onEdit?: () => void;
  onDelete?: () => void;
  onAddToTankoubon?: () => void;
  t: TFunction;
};

export function ArchiveDetailActions({
  metadata,
  favorite,
  favoriteLoading,
  onToggleFavorite,
  onStartReading,
  onDownload,
  onMarkAsRead,
  onMarkAsNew,
  onEdit,
  onDelete,
  onAddToTankoubon,
  t,
}: Props) {
  const progress = Number(metadata.progress || 0);

  return (
    <View style={styles.container}>
      <View style={styles.row}>
        <TouchableOpacity style={styles.primaryButton} onPress={onStartReading}>
          <Text style={styles.primaryButtonText}>
            {progress > 0 ? t('archive.continue') : t('archive.startReading')}
          </Text>
        </TouchableOpacity>

        <TouchableOpacity
          accessibilityRole="button"
          accessibilityLabel={favorite ? t('common.favorited') : t('common.favorite')}
          style={[styles.iconButton, favorite && styles.iconButtonActive]}
          onPress={onToggleFavorite}
          disabled={favoriteLoading}>
          <Heart
            color={favorite ? colors.white : colors.primary}
            fill={favorite ? colors.white : 'transparent'}
            size={20}
          />
        </TouchableOpacity>

        <TouchableOpacity
          accessibilityRole="button"
          accessibilityLabel={t('archive.download')}
          style={styles.iconButton}
          onPress={onDownload}>
          <Download color={colors.text} size={20} />
        </TouchableOpacity>
      </View>

      <View style={styles.secondaryRow}>
        {onMarkAsRead ? (
          <TouchableOpacity style={styles.secondaryButton} onPress={onMarkAsRead}>
            <Text style={styles.secondaryButtonText}>{t('archive.markAsRead')}</Text>
          </TouchableOpacity>
        ) : null}
        {onMarkAsNew ? (
          <TouchableOpacity style={styles.secondaryButton} onPress={onMarkAsNew}>
            <Text style={styles.secondaryButtonText}>{t('archive.markAsNew')}</Text>
          </TouchableOpacity>
        ) : null}
        {onAddToTankoubon ? (
          <TouchableOpacity style={styles.secondaryButton} onPress={onAddToTankoubon}>
            <Text style={styles.secondaryButtonText}>{t('tankoubon.addArchive')}</Text>
          </TouchableOpacity>
        ) : null}
        {onEdit ? (
          <TouchableOpacity style={styles.secondaryButton} onPress={onEdit}>
            <Text style={styles.secondaryButtonText}>{t('common.edit')}</Text>
          </TouchableOpacity>
        ) : null}
        {onDelete ? (
          <TouchableOpacity style={styles.secondaryButtonDanger} onPress={onDelete}>
            <Text style={styles.secondaryButtonDangerText}>{t('common.delete')}</Text>
          </TouchableOpacity>
        ) : null}
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    gap: 8,
    marginTop: 16,
  },
  row: {
    alignItems: 'center',
    flexDirection: 'row',
    gap: 10,
  },
  primaryButton: {
    alignItems: 'center',
    backgroundColor: colors.primary,
    borderRadius: 8,
    flex: 1,
    paddingVertical: 12,
  },
  primaryButtonText: {
    color: colors.white,
    fontSize: 15,
    fontWeight: '800',
  },
  iconButton: {
    alignItems: 'center',
    backgroundColor: colors.surface,
    borderColor: colors.border,
    borderRadius: 8,
    borderWidth: StyleSheet.hairlineWidth,
    height: 44,
    justifyContent: 'center',
    width: 44,
  },
  iconButtonActive: {
    backgroundColor: colors.primary,
    borderColor: colors.primary,
  },
  secondaryRow: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: 8,
  },
  secondaryButton: {
    alignItems: 'center',
    backgroundColor: colors.surface,
    borderColor: colors.border,
    borderRadius: 6,
    borderWidth: StyleSheet.hairlineWidth,
    paddingHorizontal: 12,
    paddingVertical: 7,
  },
  secondaryButtonText: {
    color: colors.text,
    fontSize: 13,
    fontWeight: '600',
  },
  secondaryButtonDanger: {
    alignItems: 'center',
    borderColor: colors.danger,
    borderRadius: 6,
    borderWidth: 1,
    paddingHorizontal: 12,
    paddingVertical: 7,
  },
  secondaryButtonDangerText: {
    color: colors.danger,
    fontSize: 13,
    fontWeight: '600',
  },
});
