import React, {useCallback, useMemo, useState} from 'react';
import {Alert, Linking, Modal, Pressable, StyleSheet, Text, TouchableOpacity, View} from 'react-native';
import {CheckCircle, Download, Edit, FolderOpen, Heart, MoreHorizontal, RotateCcw, Trash2} from 'lucide-react-native';

import {useTheme} from '../../theme/ThemeContext';
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
  const {colors} = useTheme();
  const progress = Number(metadata.progress || 0);
  const [menuVisible, setMenuVisible] = useState(false);

  const styles = useMemo(
    () =>
      StyleSheet.create({
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
        overlay: {
          backgroundColor: 'rgba(0,0,0,0.4)',
          flex: 1,
          justifyContent: 'flex-end',
        },
        menuSheet: {
          backgroundColor: colors.background,
          borderTopLeftRadius: 16,
          borderTopRightRadius: 16,
          paddingBottom: 24,
          paddingTop: 8,
        },
        menuHandle: {
          alignSelf: 'center',
          backgroundColor: colors.border,
          borderRadius: 3,
          height: 4,
          marginBottom: 12,
          width: 40,
        },
        menuItem: {
          alignItems: 'center',
          flexDirection: 'row',
          gap: 12,
          paddingHorizontal: 20,
          paddingVertical: 14,
        },
        menuItemText: {
          color: colors.text,
          fontSize: 15,
          fontWeight: '500',
        },
        menuItemDangerText: {
          color: colors.danger,
          fontSize: 15,
          fontWeight: '500',
        },
      }),
    [colors],
  );

  function renderMenuItem(
    label: string,
    icon: React.ReactNode,
    onPress?: () => void,
    danger = false,
  ) {
    if (!onPress) return null;
    return (
      <TouchableOpacity
        style={styles.menuItem}
        onPress={() => {
          setMenuVisible(false);
          onPress();
        }}>
        {icon}
        <Text style={danger ? styles.menuItemDangerText : styles.menuItemText}>
          {label}
        </Text>
      </TouchableOpacity>
    );
  }

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
          accessibilityLabel={t('common.more')}
          style={styles.iconButton}
          onPress={() => setMenuVisible(true)}>
          <MoreHorizontal color={colors.text} size={20} />
        </TouchableOpacity>
      </View>

      <Modal
        animationType="fade"
        onRequestClose={() => setMenuVisible(false)}
        statusBarTranslucent
        transparent
        visible={menuVisible}>
        <Pressable style={styles.overlay} onPress={() => setMenuVisible(false)}>
          <Pressable style={styles.menuSheet}>
            <View style={styles.menuHandle} />

            {renderMenuItem(
              t('archive.download'),
              <Download color={colors.text} size={20} />,
              onDownload,
            )}
            {renderMenuItem(
              t('archive.markAsRead'),
              <CheckCircle color={colors.text} size={20} />,
              onMarkAsRead,
            )}
            {renderMenuItem(
              t('archive.markAsNew'),
              <RotateCcw color={colors.text} size={20} />,
              onMarkAsNew,
            )}
            {renderMenuItem(
              t('tankoubon.addArchive'),
              <FolderOpen color={colors.text} size={20} />,
              onAddToTankoubon,
            )}
            {renderMenuItem(
              t('common.edit'),
              <Edit color={colors.text} size={20} />,
              onEdit,
            )}
            {renderMenuItem(
              t('common.delete'),
              <Trash2 color={colors.danger} size={20} />,
              onDelete,
              true,
            )}
          </Pressable>
        </Pressable>
      </Modal>
    </View>
  );
}
