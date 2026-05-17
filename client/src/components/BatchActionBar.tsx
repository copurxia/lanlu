import React, {useMemo} from 'react';
import {ActivityIndicator, StyleSheet, Text, TouchableOpacity, View} from 'react-native';
import {BlurView} from '@sbaiahmed1/react-native-blur';
import {Check, Download, Edit, Heart, RotateCcw, Trash2, X} from 'lucide-react-native';

import {useTheme} from '../theme/ThemeContext';
import type {TFunction} from '../i18n';

export type BatchAction = {
  id: string;
  label: string;
  icon: React.ReactNode;
  destructive?: boolean;
  disabled?: boolean;
  loading?: boolean;
  onPress: () => void;
};

type Props = {
  visible: boolean;
  selectedCount: number;
  actions?: BatchAction[];
  onExit: () => void;
  t: TFunction;
};

export function BatchActionBar({visible, selectedCount, actions, onExit, t}: Props) {
  const {colors, effectiveScheme} = useTheme();

  const defaultActions: BatchAction[] = useMemo(
    () => [
      {
        id: 'edit',
        label: t('common.edit'),
        icon: <Edit color={colors.text} size={16} />,
        onPress: () => {},
      },
      {
        id: 'favorite',
        label: t('common.favorite'),
        icon: <Heart color={colors.text} size={16} />,
        onPress: () => {},
      },
      {
        id: 'download',
        label: t('archive.download'),
        icon: <Download color={colors.text} size={16} />,
        onPress: () => {},
      },
      {
        id: 'mark-read',
        label: t('archive.markAsRead'),
        icon: <Check color={colors.text} size={16} />,
        onPress: () => {},
      },
      {
        id: 'delete',
        label: t('common.delete'),
        icon: <Trash2 color={colors.danger} size={16} />,
        destructive: true,
        onPress: () => {},
      },
    ],
    [colors, t],
  );

  const resolvedActions = actions ?? defaultActions;

  if (!visible) return null;

  const tintColor = colors.background + '80';

  return (
    <View style={[styles.container, {paddingBottom: 24}]} pointerEvents="box-none">
      <View style={styles.bar}>
        <View style={styles.barBlur}>
          <BlurView
            blurType={effectiveScheme === 'dark' ? 'dark' : 'light'}
            blurAmount={20}
            style={StyleSheet.absoluteFill}
          />
          <View style={[StyleSheet.absoluteFill, {backgroundColor: tintColor}]} />
        </View>
        <View style={[styles.countBadge, {backgroundColor: 'transparent', borderColor: colors.border}]}>
          <Text style={[styles.countText, {color: colors.text}]}>
            {t('common.selected')}: {selectedCount}
          </Text>
        </View>

        <View style={[styles.actionsRow, {backgroundColor: 'transparent', borderColor: colors.border}]}>
          {resolvedActions.map(action => (
            <TouchableOpacity
              key={action.id}
              style={[styles.actionButton, action.destructive && styles.destructiveButton]}
              onPress={action.onPress}
              disabled={action.disabled || action.loading}>
              {action.loading ? (
                <ActivityIndicator color={action.destructive ? colors.danger : colors.primary} size="small" />
              ) : (
                action.icon
              )}
            </TouchableOpacity>
          ))}
        </View>

        <TouchableOpacity
          style={[styles.exitButton, {backgroundColor: 'transparent', borderColor: colors.border}]}
          onPress={onExit}>
          <X color={colors.text} size={18} />
        </TouchableOpacity>
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    alignItems: 'center',
    bottom: 0,
    justifyContent: 'center',
    left: 0,
    position: 'absolute',
    right: 0,
    zIndex: 100,
  },
  bar: {
    alignItems: 'center',
    flexDirection: 'row',
    gap: 8,
    padding: 4,
  },
  barBlur: {
    bottom: 0,
    left: 0,
    position: 'absolute',
    right: 0,
    top: 0,
    borderRadius: 24,
    overflow: 'hidden',
  },
  countBadge: {
    borderRadius: 20,
    borderWidth: StyleSheet.hairlineWidth,
    paddingHorizontal: 14,
    paddingVertical: 8,
  },
  countText: {
    fontSize: 13,
    fontWeight: '700',
  },
  actionsRow: {
    alignItems: 'center',
    borderRadius: 24,
    borderWidth: StyleSheet.hairlineWidth,
    flexDirection: 'row',
    gap: 2,
    padding: 4,
    shadowColor: '#000',
    shadowOffset: {width: 0, height: 2},
    shadowOpacity: 0.1,
    shadowRadius: 8,
    elevation: 4,
  },
  actionButton: {
    alignItems: 'center',
    borderRadius: 20,
    height: 36,
    justifyContent: 'center',
    width: 36,
  },
  destructiveButton: {},
  exitButton: {
    alignItems: 'center',
    borderRadius: 20,
    borderWidth: StyleSheet.hairlineWidth,
    height: 40,
    justifyContent: 'center',
    width: 40,
    shadowColor: '#000',
    shadowOffset: {width: 0, height: 2},
    shadowOpacity: 0.1,
    shadowRadius: 8,
    elevation: 4,
  },
});
