import React, {useEffect, useMemo, useState} from 'react';
import {Alert, Modal, ScrollView, Share, StyleSheet, Text, TouchableOpacity, View} from 'react-native';
import {BarChart3, BookOpen, ChevronRight, Clock, Database, FileText, Filter, FolderOpen, Heart, Languages, ListTodo, LogOut, Moon, Package, Repeat, Server, Shield, Sun, Tag, Trash2, TrendingUp, User, Users} from 'lucide-react-native';
import {useSafeAreaInsets} from 'react-native-safe-area-context';
import {useNavigation} from '@react-navigation/native';
import type {NativeStackNavigationProp} from '@react-navigation/native-stack';
import Animated, {runOnJS, useAnimatedStyle, useSharedValue, withTiming} from 'react-native-reanimated';
import FastImage, {type Source as FastImageSource} from '@d11/react-native-fast-image';
import {useAuth} from '../auth/AuthContext';
import {ModalBackdrop, ScreenRoot, screenSafeAreaPadding} from '../components/SafeAreaSurface';
import {FluentCard, FluentCaption, FluentTitle} from '../components/fluent';
import {useI18n} from '../i18n';
import type {RootStackParamList} from '../navigation/types';
import {buildAuthorizedAssetImageSource, isNetworkError} from '../api/client';
import {fetchUserStats, fetchReadingTrend, type UserStats, type ReadingTrendItem} from '../api/lanlu';
import {DashboardStats} from '../components/DashboardStats';
import {ReadingTrendChart} from '../components/ReadingTrendChart';
import {clearDiagnosticLog, getDiagnosticLog} from '../storage/diagnostics';
import {useOfflineSettingsStore} from '../stores/offlineSettingsStore';
import {shareLocalTextFile} from '../native/LanluMediaProxy';
import {spacing, radius, type ThemeColors} from '../theme/colors';
import {useTheme} from '../theme/ThemeContext';

type SettingsItem = {
  icon: React.ReactNode;
  label: string;
  onPress: () => void;
  danger?: boolean;
};

function SettingsGroup({title, items}: {title?: string; items: SettingsItem[]}) {
  const {colors} = useTheme();
  const styles = useMemo(() => createStyles(colors), [colors]);
  return (
    <FluentCard style={styles.section}>
      {title ? <Text style={styles.groupTitle}>{title}</Text> : null}
      <View style={styles.actionList}>
        {items.map((item, index) => (
          <TouchableOpacity
            key={index}
            activeOpacity={0.78}
            accessibilityLabel={item.label}
            accessibilityRole="button"
            onPress={item.onPress}
            style={[
              styles.actionRow,
              index === items.length - 1 && styles.actionRowLast,
            ]}>
            <View style={styles.iconWrap}>{item.icon}</View>
            <Text
              style={[styles.actionLabel, item.danger && styles.actionLabelDanger]}
              numberOfLines={1}>
              {item.label}
            </Text>
            <ChevronRight color={item.danger ? colors.danger : colors.textMuted} size={18} />
          </TouchableOpacity>
        ))}
      </View>
    </FluentCard>
  );
}

export function SettingsScreen() {
  const {t} = useI18n();
  const {activeServer, user, showServerList, signOut, isOffline} = useAuth();
  const serverId = activeServer?.id || '';
  const cacheDashboard = useOfflineSettingsStore(s => s.cacheDashboard);
  const getCachedDashboard = useOfflineSettingsStore(s => s.getCachedDashboard);
  const {colors, themePreference, setThemePreference} = useTheme();
  const navigation = useNavigation<NativeStackNavigationProp<RootStackParamList>>();
  const insets = useSafeAreaInsets();
  const [diagnosticLog, setDiagnosticLog] = useState('');
  const [diagnosticsOpen, setDiagnosticsOpen] = useState(false);
  const [avatarSource, setAvatarSource] = useState<FastImageSource | null>(null);
  const [stats, setStats] = useState<UserStats | null>(null);
  const [trend, setTrend] = useState<ReadingTrendItem[]>([]);
  const [dashboardLoading, setDashboardLoading] = useState(true);
  const diagnosticsProgress = useSharedValue(0);
  const backdropStyle = useAnimatedStyle(() => ({
    opacity: diagnosticsProgress.value,
  }));
  const sheetStyle = useAnimatedStyle(() => ({
    transform: [{translateY: (1 - diagnosticsProgress.value) * 28}],
  }));
  const styles = useMemo(() => createStyles(colors), [colors]);

  useEffect(() => {
    if (user?.avatarAssetId) {
      buildAuthorizedAssetImageSource(user.avatarAssetId).then(setAvatarSource);
    } else {
      setAvatarSource(null);
    }
  }, [user?.avatarAssetId]);

  useEffect(() => {
    let cancelled = false;
    async function loadDashboard() {
      setDashboardLoading(true);

      if (isOffline && serverId) {
        const cached = getCachedDashboard(serverId);
        if (cached) {
          setStats(cached.stats);
          setTrend(cached.trend);
          setDashboardLoading(false);
          return;
        }
      }

      try {
        const [statsData, trendData] = await Promise.all([
          fetchUserStats(),
          fetchReadingTrend(30),
        ]);
        if (!cancelled) {
          const cached = serverId ? getCachedDashboard(serverId) : null;
          const useStats = cached && statsData.favoriteCount === 0 && statsData.totalArchives === 0 ? cached.stats : statsData;
          const useTrend = cached && trendData.length === 0 ? cached.trend : trendData;
          setStats(useStats);
          setTrend(useTrend);
          if (serverId && (useStats.favoriteCount > 0 || useStats.totalArchives > 0 || useTrend.length > 0)) {
            cacheDashboard(serverId, {stats: useStats, trend: useTrend});
          }
          setDashboardLoading(false);
        }
      } catch (err) {
        if (!cancelled && serverId) {
          const cached = getCachedDashboard(serverId);
          if (cached) {
            setStats(cached.stats);
            setTrend(cached.trend);
          }
          setDashboardLoading(false);
        }
      }
    }
    loadDashboard();
    return () => {cancelled = true;};
  }, [isOffline, serverId, cacheDashboard, getCachedDashboard]);

  function confirmSignOut() {
    Alert.alert(t('settings.signOutTitle'), t('settings.signOutMessage'), [
      {text: t('common.cancel'), style: 'cancel'},
      {
        text: t('settings.signOut'),
        style: 'destructive',
        onPress: () => {
          signOut().catch(error => console.warn('Failed to sign out:', error));
        },
      },
    ]);
  }

  const themeIcon = themePreference === 'dark'
    ? <Moon color={colors.textMuted} size={20} />
    : themePreference === 'light'
    ? <Sun color={colors.textMuted} size={20} />
    : <Languages color={colors.textMuted} size={20} />;

  async function openDiagnostics() {
    const log = await getDiagnosticLog();
    setDiagnosticLog(log || t('settings.diagnosticsEmpty'));
    setDiagnosticsOpen(true);
    diagnosticsProgress.value = withTiming(1, {duration: 160});
  }

  function closeDiagnostics() {
    diagnosticsProgress.value = withTiming(0, {duration: 130}, finished => {
      if (finished) {
        runOnJS(setDiagnosticsOpen)(false);
      }
    });
  }

  async function shareDiagnostics() {
    const log = await getDiagnosticLog();
    const text = log || t('settings.diagnosticsEmpty');
    try {
      const sharedUri = await shareLocalTextFile(
        text,
        'log',
        'lanlu-diagnostics',
        t('settings.diagnostics'),
      );
      if (sharedUri) return;
    } catch {
      // fallback
    }
    await Share.share({
      title: t('settings.diagnostics'),
      message: text,
    });
  }

  async function clearDiagnostics() {
    await clearDiagnosticLog();
    setDiagnosticLog(t('settings.diagnosticsEmpty'));
  }

  const clientSettings: SettingsItem[] = [
    {
      icon: themeIcon,
      label: t('settings.theme'),
      onPress: () => navigation.navigate('ThemeSettings'),
    },
    {
      icon: <Languages color={colors.textMuted} size={20} />,
      label: t('settings.language'),
      onPress: () => navigation.navigate('LanguageSettings'),
    },
    {
      icon: <FileText color={colors.textMuted} size={20} />,
      label: t('settings.diagnostics'),
      onPress: () => navigation.navigate('DiagnosticsSettings'),
    },
    {
      icon: <Database color={colors.textMuted} size={20} />,
      label: t('settings.cache'),
      onPress: () => navigation.navigate('CacheSettings'),
    },
  ];

  const serverSettings: SettingsItem[] = [
    {
      icon: <Shield color={colors.textMuted} size={20} />,
      label: t('settings.auth'),
      onPress: () => navigation.navigate('AccountSecurity'),
    },
  ];

  if (user?.isAdmin === true) {
    serverSettings.push(
      {
        icon: <FolderOpen color={colors.textMuted} size={20} />,
        label: t('settings.categories'),
        onPress: () => navigation.navigate('CategorySettings'),
      },
      {
        icon: <Tag color={colors.textMuted} size={20} />,
        label: t('settings.tags'),
        onPress: () => navigation.navigate('TagSettings'),
      },
      {
        icon: <Filter color={colors.textMuted} size={20} />,
        label: t('settings.smartFilters'),
        onPress: () => navigation.navigate('SmartFilterSettings'),
      },
      {
        icon: <Users color={colors.textMuted} size={20} />,
        label: t('settings.users'),
        onPress: () => navigation.navigate('UserSettings'),
      },
      {
        icon: <Server color={colors.textMuted} size={20} />,
        label: t('settings.system.title'),
        onPress: () => navigation.navigate('SystemSettings'),
      },
      {
        icon: <ListTodo color={colors.textMuted} size={20} />,
        label: t('settings.tasks'),
        onPress: () => navigation.navigate('TaskSettings'),
      },
      {
        icon: <Clock color={colors.textMuted} size={20} />,
        label: t('settings.cron'),
        onPress: () => navigation.navigate('CronSettings'),
      },
      {
        icon: <Package color={colors.textMuted} size={20} />,
        label: t('settings.plugins'),
        onPress: () => navigation.navigate('PluginSettings'),
      },
      {
        icon: <BarChart3 color={colors.textMuted} size={20} />,
        label: t('settings.stats'),
        onPress: () => navigation.navigate('StatsSettings'),
      },
    );
  }

  return (
    <ScreenRoot padded={false}>
      <ScrollView
        contentContainerStyle={[styles.content, screenSafeAreaPadding(insets, !isOffline)]}
        showsVerticalScrollIndicator={false}>
        {/* 概览 */}
        <View style={styles.overviewRow}>
          <View style={styles.avatarWrap}>
            {avatarSource ? (
              <FastImage source={avatarSource} style={styles.avatar} />
            ) : (
              <User color={colors.textMuted} size={24} />
            )}
          </View>
          <View style={styles.overviewInfo}>
            <Text style={styles.overviewUsername} numberOfLines={1}>
              {user?.username || t('common.unknown')}
            </Text>
            <Text style={styles.overviewServer} numberOfLines={1}>
              {activeServer?.name || 'Lanlu'}
              {activeServer?.baseUrl ? ` · ${activeServer.baseUrl}` : ''}
            </Text>
          </View>
          <View style={styles.overviewActions}>
            <TouchableOpacity
              accessibilityLabel={t('auth.switchServer')}
              accessibilityRole="button"
              onPress={() => {
                showServerList().catch(error =>
                  console.warn('Failed to switch server:', error),
                );
              }}
              style={styles.iconButton}>
              <Repeat color={colors.textMuted} size={20} />
            </TouchableOpacity>
            <TouchableOpacity
              accessibilityLabel={t('settings.signOut')}
              accessibilityRole="button"
              onPress={confirmSignOut}
              style={styles.iconButton}>
              <LogOut color={colors.danger} size={20} />
            </TouchableOpacity>
          </View>
        </View>

        {/* 统计概览 */}
        <FluentCard style={styles.section}>
          <DashboardStats stats={stats} loading={dashboardLoading} />
          <ReadingTrendChart data={trend} loading={dashboardLoading} />
        </FluentCard>

        {/* 客户端设置 */}
        <SettingsGroup title={t('settings.clientSettings')} items={clientSettings} />

        {/* 服务端设置 */}
        <SettingsGroup title={t('settings.serverSettings')} items={serverSettings} />
      </ScrollView>

      {/* Diagnostics Modal */}
      <Modal
        animationType="fade"
        onRequestClose={closeDiagnostics}
        statusBarTranslucent
        transparent
        visible={diagnosticsOpen}>
        <ModalBackdrop animatedStyle={backdropStyle} style={styles.logBackdrop}>
          <Animated.View style={[styles.logSheet, {paddingBottom: Math.max(insets.bottom, spacing.lg)}, sheetStyle]}>
            <FluentTitle>{t('settings.diagnostics')}</FluentTitle>
            <ScrollView style={styles.logBox}>
              <Text selectable style={styles.logText}>{diagnosticLog}</Text>
            </ScrollView>
            <View style={styles.sheetActions}>
              <TouchableOpacity
                accessibilityLabel={t('settings.clearLogs')}
                accessibilityRole="button"
                onPress={clearDiagnostics}
                style={[styles.iconAction, styles.deleteAction]}>
                <Trash2 color={colors.danger} size={18} />
              </TouchableOpacity>
              <TouchableOpacity
                accessibilityLabel={t('settings.shareLogs')}
                accessibilityRole="button"
                onPress={shareDiagnostics}
                style={styles.iconAction}>
                <FileText color={colors.textMuted} size={18} />
              </TouchableOpacity>
              <TouchableOpacity
                accessibilityRole="button"
                onPress={closeDiagnostics}
                style={styles.closePill}>
                <Text style={styles.closePillText}>{t('common.close')}</Text>
              </TouchableOpacity>
            </View>
          </Animated.View>
        </ModalBackdrop>
      </Modal>
    </ScreenRoot>
  );
}

function createStyles(colors: ThemeColors) {
  return StyleSheet.create({
    content: {gap: spacing.md},
    section: {gap: spacing.md},
    groupTitle: {
      color: colors.textMuted,
      fontSize: 12,
      fontWeight: '700',
      textTransform: 'uppercase',
    },
    overviewRow: {
      alignItems: 'center',
      backgroundColor: colors.surface,
      borderRadius: radius.md,
      borderColor: colors.border,
      borderWidth: StyleSheet.hairlineWidth,
      flexDirection: 'row',
      gap: spacing.md,
      padding: spacing.lg,
    },
    avatarWrap: {
      alignItems: 'center',
      backgroundColor: colors.surfaceMuted,
      borderRadius: 24,
      height: 48,
      justifyContent: 'center',
      overflow: 'hidden',
      width: 48,
    },
    avatar: {
      height: 48,
      width: 48,
    },
    overviewInfo: {
      flex: 1,
      gap: 2,
    },
    overviewUsername: {
      color: colors.text,
      fontSize: 17,
      fontWeight: '700',
    },
    overviewServer: {
      color: colors.textMuted,
      fontSize: 13,
    },
    overviewActions: {
      flexDirection: 'row',
      gap: spacing.xs,
    },
    iconButton: {
      width: 40,
      height: 40,
      borderRadius: 20,
      alignItems: 'center',
      justifyContent: 'center',
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
    actionLabel: {
      color: colors.text,
      flex: 1,
      fontSize: 15,
      fontWeight: '800',
    },
    actionLabelDanger: {color: colors.danger},
    iconWrap: {
      alignItems: 'center',
      height: 36,
      justifyContent: 'center',
      width: 28,
    },
    iconAction: {
      alignItems: 'center',
      backgroundColor: colors.surfaceMuted,
      borderColor: colors.border,
      borderRadius: 18,
      borderWidth: StyleSheet.hairlineWidth,
      height: 36,
      justifyContent: 'center',
      width: 36,
    },
    deleteAction: {
      backgroundColor: colors.danger === '#e84d3d' ? '#2a1515' : '#fff5f5',
    },
    logBackdrop: {justifyContent: 'flex-end'},
    sheetActions: {
      alignItems: 'center',
      flexDirection: 'row',
      gap: spacing.sm,
      justifyContent: 'flex-end',
    },
    closePill: {
      alignItems: 'center',
      backgroundColor: colors.primary,
      borderRadius: 18,
      height: 36,
      justifyContent: 'center',
      paddingHorizontal: spacing.lg,
    },
    closePillText: {
      color: colors.white,
      fontSize: 14,
      fontWeight: '800',
    },
    logSheet: {
      backgroundColor: colors.surface,
      borderTopLeftRadius: 14,
      borderTopRightRadius: 14,
      gap: spacing.md,
      maxHeight: '82%',
      padding: spacing.lg,
      width: '100%',
    },
    logBox: {
      backgroundColor: colors.surfaceMuted,
      borderColor: colors.border,
      borderRadius: 8,
      borderWidth: StyleSheet.hairlineWidth,
      maxHeight: 420,
      padding: spacing.md,
    },
    logText: {
      color: colors.text,
      fontFamily: 'monospace',
      fontSize: 11,
      lineHeight: 16,
    },
  });
}
