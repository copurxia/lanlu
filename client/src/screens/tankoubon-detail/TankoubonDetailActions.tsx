import React, {useMemo} from 'react';
import {StyleSheet, Text, TouchableOpacity, View} from 'react-native';
import {Heart} from 'lucide-react-native';

import {useTheme} from '../../theme/ThemeContext';
import type {TFunction} from '../../i18n';

type Props = {
  favorite: boolean;
  favoriteLoading: boolean;
  onToggleFavorite: () => void;
  onEdit?: () => void;
  onDelete?: () => void;
  onAddArchive?: () => void;
  t: TFunction;
};

export function TankoubonDetailActions({
  favorite,
  favoriteLoading,
  onToggleFavorite,
  onEdit,
  onDelete,
  onAddArchive,
  t,
}: Props) {
  const {colors} = useTheme();

  const styles = useMemo(
    () =>
      StyleSheet.create({
        container: {
          marginTop: 16,
        },
        row: {
          alignItems: 'center',
          flexDirection: 'row',
          flexWrap: 'wrap',
          gap: 10,
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
        primaryButton: {
          alignItems: 'center',
          backgroundColor: colors.primary,
          borderRadius: 8,
          paddingHorizontal: 16,
          paddingVertical: 10,
        },
        primaryButtonText: {
          color: colors.white,
          fontSize: 14,
          fontWeight: '800',
        },
        secondaryButton: {
          alignItems: 'center',
          backgroundColor: colors.surface,
          borderColor: colors.border,
          borderRadius: 6,
          borderWidth: StyleSheet.hairlineWidth,
          paddingHorizontal: 14,
          paddingVertical: 8,
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
          paddingHorizontal: 14,
          paddingVertical: 8,
        },
        secondaryButtonDangerText: {
          color: colors.danger,
          fontSize: 13,
          fontWeight: '600',
        },
      }),
    [colors],
  );

  return (
    <View style={styles.container}>
      <View style={styles.row}>
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
        {onAddArchive ? (
          <TouchableOpacity style={styles.primaryButton} onPress={onAddArchive}>
            <Text style={styles.primaryButtonText}>{t('tankoubon.addArchive')}</Text>
          </TouchableOpacity>
        ) : null}
      </View>
    </View>
  );
}

