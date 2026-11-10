import React, {useMemo} from 'react';
import {ActivityIndicator, StyleSheet, Text, TouchableOpacity, View} from 'react-native';
import {BlurView} from '@sbaiahmed1/react-native-blur';
import {useSafeAreaInsets} from 'react-native-safe-area-context';
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

const TAB_BAR_HEIGHT = 58;

export function BatchActionBar({visible, selectedCount, actions, onExit, t}: Props) {
  const {colors, effectiveScheme} = useTheme();
  const insets = useSafeAreaInsets();

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
  const blurType = effectiveScheme === 'dark' ? 'dark' : 'light';

  return (
    <View style={[styles.container, {bottom: insets.bottom + TAB_BAR_HEIGHT, paddingBottom: 24}]} pointerEvents="box-none">
      <View style={styles.bar}>
        <View style={[styles.countBadge, {borderColor: colors.border}]}>
          <BlurView blurType={blurType} blurAmount={20} style={StyleSheet.absoluteFill} />
          <View style={[StyleSheet.absoluteFill, {backgroundColor: tintColor}]} />
          <Text style={[styles.countText, {color: colors.text}]}>
            {t('common.selected')}: {selectedCount}
          </Text>
        </View>

        <View style={[styles.actionsRow, {borderColor: colors.border}]}>
          <BlurView blurType={blurType} blurAmount={20} style={StyleSheet.absoluteFill} />
          <View style={[StyleSheet.absoluteFill, {backgroundColor: tintColor}]} />
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

        <View style={[styles.exitButton, {borderColor: colors.border}]}>
          <BlurView blurType={blurType} blurAmount={20} style={StyleSheet.absoluteFill} />
          <View style={[StyleSheet.absoluteFill, {backgroundColor: tintColor}]} />
          <TouchableOpacity style={styles.exitButtonInner} onPress={onExit}>
            <X color={colors.text} size={18} />
          </TouchableOpacity>
        </View>
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
  countBadge: {
    borderRadius: 20,
    borderWidth: StyleSheet.hairlineWidth,
    overflow: 'hidden',
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
    overflow: 'hidden',
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
    borderRadius: 20,
    borderWidth: StyleSheet.hairlineWidth,
    height: 40,
    overflow: 'hidden',
    width: 40,
    shadowColor: '#000',
    shadowOffset: {width: 0, height: 2},
    shadowOpacity: 0.1,
    shadowRadius: 8,
    elevation: 4,
  },
  exitButtonInner: {
    alignItems: 'center',
    flex: 1,
    justifyContent: 'center',
  },
});
