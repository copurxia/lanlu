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
  const clearArchiveCache = useOfflineArchiveStore(state => state.clearArchiveCache);
  const clearFeedCache = useOfflineFeedStore(state => state.clearFeedCache);

  const tankoubonCount = useOfflineTankoubonStore(state => Object.keys(state.tankoubons).length);
  const generalCount = useOfflineGeneralStore(state => Object.keys(state.favorites).length);
  const settingsCount = useOfflineSettingsStore(state => Object.keys(state.dashboard).length);
  const clearTankoubonCache = useOfflineTankoubonStore(state => state.clearTankoubonCache);
  const clearGeneralCache = useOfflineGeneralStore(state => state.clearGeneralCache);
  const clearSettingsCache = useOfflineSettingsStore(state => state.clearSettingsCache);

  const clearAll = useCallback(() => {
    Alert.alert(t('settings.clearAllCache'), t('settings.clearAllCacheConfirm'), [
      {text: t('common.cancel'), style: 'cancel'},
      {
        text: t('common.delete'),
        style: 'destructive',
        onPress: async () => {
          try {
            clearArchiveCache();
            clearFeedCache();
            clearTankoubonCache();
            clearGeneralCache();
            clearSettingsCache();
            await FastImage.clearDiskCache();
            await FastImage.clearMemoryCache();
            Alert.alert(t('common.success'), t('settings.cacheCleared'));
          } catch {
            Alert.alert(t('common.error'), t('common.unknown'));
          }
        },
      },
    ]);
  }, [t, clearArchiveCache, clearFeedCache, clearTankoubonCache, clearGeneralCache, clearSettingsCache]);

  const clearArchive = useCallback(() => {
    Alert.alert(t('settings.clearArchiveCache'), t('settings.clearArchiveCacheConfirm'), [
      {text: t('common.cancel'), style: 'cancel'},
      {
        text: t('common.delete'),
        style: 'destructive',
        onPress: () => {
          clearArchiveCache();
          Alert.alert(t('common.success'), t('settings.cacheCleared'));
        },
      },
    ]);
  }, [t, clearArchiveCache]);

  const clearFeed = useCallback(() => {
    Alert.alert(t('settings.clearFeedCache'), t('settings.clearFeedCacheConfirm'), [
      {text: t('common.cancel'), style: 'cancel'},
      {
        text: t('common.delete'),
        style: 'destructive',
        onPress: () => {
          clearFeedCache();
          Alert.alert(t('common.success'), t('settings.cacheCleared'));
        },
      },
    ]);
  }, [t, clearFeedCache]);

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
            <Text style={styles.statLabel}>{t('settings.cacheArchive')}</Text>
            <Text style={styles.statValue}>
              {t('settings.cacheArchiveDescription', {count: archiveCount})}
            </Text>
          </View>

          <View style={styles.statRow}>
            <Database color={colors.textMuted} size={18} />
            <Text style={styles.statLabel}>{t('settings.cacheFeed')}</Text>
            <Text style={styles.statValue}>
              {t('settings.cacheFeedDescription', {count: feedCount})}
            </Text>
          </View>

          <View style={styles.statRow}>
            <Database color={colors.textMuted} size={18} />
            <Text style={styles.statLabel}>{t('settings.cacheTankoubon')}</Text>
            <Text style={styles.statValue}>
              {t('settings.cacheCount', {count: tankoubonCount})}
            </Text>
          </View>

          <View style={styles.statRow}>
            <Database color={colors.textMuted} size={18} />
            <Text style={styles.statLabel}>{t('settings.cacheGeneral')}</Text>
            <Text style={styles.statValue}>
              {t('settings.cacheCount', {count: generalCount})}
            </Text>
          </View>

          <View style={styles.statRow}>
            <Database color={colors.textMuted} size={18} />
            <Text style={styles.statLabel}>{t('settings.cacheDashboard')}</Text>
            <Text style={styles.statValue}>
              {t('settings.cacheCount', {count: settingsCount})}
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
              accessibilityLabel={t('settings.clearArchiveCache')}
              accessibilityRole="button"
              onPress={clearArchive}
              disabled={archiveCount === 0}
              style={[
                styles.actionRow,
                archiveCount === 0 && styles.actionRowDisabled,
              ]}>
              <Text
                style={[
                  styles.actionLabel,
                  archiveCount === 0 && styles.actionLabelDisabled,
                ]}>
                {t('settings.clearArchiveCache')}
              </Text>
              <Trash2
                color={archiveCount === 0 ? colors.textMuted : colors.danger}
                size={18}
              />
            </TouchableOpacity>

            <TouchableOpacity
              activeOpacity={0.78}
              accessibilityLabel={t('settings.clearFeedCache')}
              accessibilityRole="button"
              onPress={clearFeed}
              disabled={feedCount === 0}
              style={[
                styles.actionRow,
                feedCount === 0 && styles.actionRowDisabled,
              ]}>
              <Text
                style={[
                  styles.actionLabel,
                  feedCount === 0 && styles.actionLabelDisabled,
                ]}>
                {t('settings.clearFeedCache')}
              </Text>
              <Trash2
                color={feedCount === 0 ? colors.textMuted : colors.danger}
                size={18}
              />
            </TouchableOpacity>

            <TouchableOpacity
              activeOpacity={0.78}
              accessibilityLabel={t('settings.clearTankoubonCache')}
              accessibilityRole="button"
              onPress={() => {
                Alert.alert(t('settings.clearTankoubonCache'), t('settings.clearTankoubonCacheConfirm'), [
                  {text: t('common.cancel'), style: 'cancel'},
                  {
                    text: t('common.delete'),
                    style: 'destructive',
                    onPress: () => {
                      clearTankoubonCache();
                      Alert.alert(t('common.success'), t('settings.cacheCleared'));
                    },
                  },
                ]);
              }}
              disabled={tankoubonCount === 0}
              style={[
                styles.actionRow,
                tankoubonCount === 0 && styles.actionRowDisabled,
              ]}>
              <Text
                style={[
                  styles.actionLabel,
                  tankoubonCount === 0 && styles.actionLabelDisabled,
                ]}>
                {t('settings.clearTankoubonCache')}
              </Text>
              <Trash2
                color={tankoubonCount === 0 ? colors.textMuted : colors.danger}
                size={18}
              />
            </TouchableOpacity>

            <TouchableOpacity
              activeOpacity={0.78}
              accessibilityLabel={t('settings.clearGeneralCache')}
              accessibilityRole="button"
              onPress={() => {
                Alert.alert(t('settings.clearGeneralCache'), t('settings.clearGeneralCacheConfirm'), [
                  {text: t('common.cancel'), style: 'cancel'},
                  {
                    text: t('common.delete'),
                    style: 'destructive',
                    onPress: () => {
                      clearGeneralCache();
                      Alert.alert(t('common.success'), t('settings.cacheCleared'));
                    },
                  },
                ]);
              }}
              disabled={generalCount === 0}
              style={[
                styles.actionRow,
                generalCount === 0 && styles.actionRowDisabled,
              ]}>
              <Text
                style={[
                  styles.actionLabel,
                  generalCount === 0 && styles.actionLabelDisabled,
                ]}>
                {t('settings.clearGeneralCache')}
              </Text>
              <Trash2
                color={generalCount === 0 ? colors.textMuted : colors.danger}
                size={18}
              />
            </TouchableOpacity>

            <TouchableOpacity
              activeOpacity={0.78}
              accessibilityLabel={t('settings.clearDashboardCache')}
              accessibilityRole="button"
              onPress={() => {
                Alert.alert(t('settings.clearDashboardCache'), t('settings.clearDashboardCacheConfirm'), [
                  {text: t('common.cancel'), style: 'cancel'},
                  {
                    text: t('common.delete'),
                    style: 'destructive',
                    onPress: () => {
                      clearSettingsCache();
                      Alert.alert(t('common.success'), t('settings.cacheCleared'));
                    },
                  },
                ]);
              }}
              disabled={settingsCount === 0}
              style={[
                styles.actionRow,
                settingsCount === 0 && styles.actionRowDisabled,
              ]}>
              <Text
                style={[
                  styles.actionLabel,
                  settingsCount === 0 && styles.actionLabelDisabled,
                ]}>
                {t('settings.clearDashboardCache')}
              </Text>
              <Trash2
                color={settingsCount === 0 ? colors.textMuted : colors.danger}
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

          <TouchableOpacity
            activeOpacity={0.78}
            accessibilityLabel={t('settings.clearAllCache')}
            accessibilityRole="button"
            onPress={clearAll}
            style={[styles.clearAllButton]}>
            <Trash2 color={colors.danger} size={18} />
            <Text style={[styles.clearAllText]}>
              {t('settings.clearAllCache')}
            </Text>
          </TouchableOpacity>
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
    clearAllButton: {
      alignItems: 'center',
      backgroundColor: colors.surface,
      borderColor: colors.danger,
      borderRadius: 8,
      borderWidth: 1,
      flexDirection: 'row',
      gap: spacing.sm,
      justifyContent: 'center',
      minHeight: 48,
      paddingHorizontal: spacing.md,
    },
    clearAllText: {
      color: colors.danger,
      fontSize: 15,
      fontWeight: '800',
    },
  });
}
