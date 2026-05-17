import React, {useCallback, useMemo} from 'react';
import {Alert, ScrollView, StyleSheet, Text, TouchableOpacity, View} from 'react-native';
import {ArrowLeft, Database, Image, Trash2} from 'lucide-react-native';
import {useSafeAreaInsets} from 'react-native-safe-area-context';
import {useNavigation} from '@react-navigation/native';
import FastImage from '@d11/react-native-fast-image';

import {ScreenRoot, screenSafeAreaPadding} from '../components/SafeAreaSurface';
import {FluentCard, FluentCaption, FluentTitle} from '../components/fluent';
import {useI18n} from '../i18n';
import {useAuth} from '../auth/AuthContext';
import {spacing, type ThemeColors} from '../theme/colors';
import {useTheme} from '../theme/ThemeContext';
import {useOfflineArchiveStore} from '../stores/offlineArchiveStore';
import {useOfflineFeedStore} from '../stores/offlineFeedStore';
import {useOfflineTankoubonStore} from '../stores/offlineTankoubonStore';
import {useOfflineGeneralStore} from '../stores/offlineGeneralStore';
import {useOfflineSettingsStore} from '../stores/offlineSettingsStore';

export function CacheSettingsScreen() {
  const {t} = useI18n();
  const {colors} = useTheme();
  const insets = useSafeAreaInsets();
  const {isOffline} = useAuth();
  const navigation = useNavigation();
  const styles = useMemo(() => createStyles(colors), [colors]);

  const archiveCount = useOfflineArchiveStore(state => Object.keys(state.archives).length);
  const feedCount = useOfflineFeedStore(state => Object.keys(state.feedCache).length);
  const tankoubonCount = useOfflineTankoubonStore(state => Object.keys(state.tankoubons).length);
  const generalCount = useOfflineGeneralStore(state => Object.keys(state.favorites).length);
  const settingsCount = useOfflineSettingsStore(state => Object.keys(state.dashboard).length);
  const systemCount = archiveCount + feedCount + tankoubonCount + generalCount + settingsCount;

  const clearAll = useCallback(() => {
    Alert.alert(t('settings.clearAllCache'), t('settings.clearAllCacheConfirm'), [
      {text: t('common.cancel'), style: 'cancel'},
      {
        text: t('common.delete'),
        style: 'destructive',
        onPress: async () => {
          try {
            useOfflineArchiveStore.getState().clearArchiveCache();
            useOfflineFeedStore.getState().clearFeedCache();
            useOfflineTankoubonStore.getState().clearTankoubonCache();
            useOfflineGeneralStore.getState().clearGeneralCache();
            useOfflineSettingsStore.getState().clearSettingsCache();
            await FastImage.clearDiskCache();
            await FastImage.clearMemoryCache();
            Alert.alert(t('common.success'), t('settings.cacheCleared'));
          } catch {
            Alert.alert(t('common.error'), t('common.unknown'));
          }
        },
      },
    ]);
  }, [t]);

  const clearImage = useCallback(() => {
    Alert.alert(t('settings.clearImageCache'), t('settings.clearImageCacheConfirm'), [
      {text: t('common.cancel'), style: 'cancel'},
      {
        text: t('common.delete'),
        style: 'destructive',
        onPress: async () => {
          try {
            await FastImage.clearDiskCache();
            await FastImage.clearMemoryCache();
            Alert.alert(t('common.success'), t('settings.imageCacheCleared'));
          } catch {
            Alert.alert(t('common.error'), t('common.unknown'));
          }
        },
      },
    ]);
  }, [t]);

  return (
    <ScreenRoot padded={false}>
      <ScrollView
        contentContainerStyle={[styles.content, screenSafeAreaPadding(insets, !isOffline)]}
        showsVerticalScrollIndicator={false}>
        <View style={styles.header}>
          <TouchableOpacity
            accessibilityRole="button"
            onPress={() => navigation.goBack()}
            style={styles.backButton}>
            <ArrowLeft color={colors.text} size={24} />
          </TouchableOpacity>
          <FluentTitle>{t('settings.cache')}</FluentTitle>
        </View>

        <FluentCard style={styles.section}>
          <FluentCaption>{t('settings.cacheDescription')}</FluentCaption>

          <View style={styles.statRow}>
            <Database color={colors.textMuted} size={18} />
            <Text style={styles.statLabel}>{t('settings.cacheSystem')}</Text>
            <Text style={styles.statValue}>
              {t('settings.cacheCount', {count: systemCount})}
            </Text>
          </View>

          <View style={styles.statRow}>
            <Image color={colors.textMuted} size={18} />
            <Text style={styles.statLabel}>{t('settings.cacheImage')}</Text>
          </View>
        </FluentCard>

        <FluentCard style={styles.section}>
          <View style={styles.actionList}>
            <TouchableOpacity
              activeOpacity={0.78}
              accessibilityLabel={t('settings.clearSystemCache')}
              accessibilityRole="button"
              onPress={clearAll}
              disabled={systemCount === 0}
              style={[
                styles.actionRow,
                systemCount === 0 && styles.actionRowDisabled,
              ]}>
              <Text
                style={[
                  styles.actionLabel,
                  systemCount === 0 && styles.actionLabelDisabled,
                ]}>
                {t('settings.clearSystemCache')}
              </Text>
              <Trash2
                color={systemCount === 0 ? colors.textMuted : colors.danger}
                size={18}
              />
            </TouchableOpacity>

            <TouchableOpacity
              activeOpacity={0.78}
              accessibilityLabel={t('settings.clearImageCache')}
              accessibilityRole="button"
              onPress={clearImage}
              style={[styles.actionRow, styles.actionRowLast]}>
              <Text style={styles.actionLabel}>
                {t('settings.clearImageCache')}
              </Text>
              <Trash2 color={colors.danger} size={18} />
            </TouchableOpacity>
          </View>
        </FluentCard>
      </ScrollView>
    </ScreenRoot>
  );
}

function createStyles(colors: ThemeColors) {
  return StyleSheet.create({
    content: {gap: spacing.md},
    section: {gap: spacing.md},
    header: {
      flexDirection: 'row',
      alignItems: 'center',
      gap: spacing.md,
    },
    backButton: {padding: spacing.xs},
    statRow: {
      alignItems: 'center',
      flexDirection: 'row',
      gap: spacing.sm,
      paddingVertical: spacing.xs,
    },
    statLabel: {
      color: colors.text,
      fontSize: 14,
      fontWeight: '600',
    },
    statValue: {
      color: colors.textMuted,
      fontSize: 13,
      marginLeft: 'auto',
    },
    actionList: {
      borderColor: colors.border,
      borderRadius: 8,
      borderWidth: StyleSheet.hairlineWidth,
      overflow: 'hidden',
    },
    actionRow: {
      alignItems: 'center',
      backgroundColor: colors.surface,
      borderBottomColor: colors.border,
      borderBottomWidth: StyleSheet.hairlineWidth,
      flexDirection: 'row',
      gap: spacing.md,
      minHeight: 48,
      paddingHorizontal: spacing.md,
    },
    actionRowLast: {borderBottomWidth: 0},
    actionRowDisabled: {opacity: 0.4},
    actionLabel: {
      color: colors.text,
      flex: 1,
      fontSize: 15,
      fontWeight: '800',
    },
    actionLabelDisabled: {color: colors.textMuted},
  });
}
