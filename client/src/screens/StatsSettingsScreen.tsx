import React, {useCallback, useEffect, useMemo, useState} from 'react';
import {Alert, RefreshControl, ScrollView, StyleSheet, Text, TouchableOpacity, View} from 'react-native';
import {ArrowLeft} from 'lucide-react-native';
import {useSafeAreaInsets} from 'react-native-safe-area-context';
import {useNavigation} from '@react-navigation/native';
import {ScreenRoot, screenSafeAreaPadding} from '../components/SafeAreaSurface';
import {FluentButton, FluentCard, FluentCaption, FluentTitle} from '../components/fluent';
import {useI18n} from '../i18n';
import {useAuth} from '../auth/AuthContext';
import {extractApiError} from '../api/client';
import {spacing, radius, type ThemeColors} from '../theme/colors';
import {useTheme} from '../theme/ThemeContext';
import {getTagCloud} from '../api/admin';
import {fetchServerInfo, type ServerInfo} from '../api/lanlu';
import type {TagCloudItem} from '../api/admin';

export function StatsSettingsScreen() {
  const {t} = useI18n();
  const {colors} = useTheme();
  const insets = useSafeAreaInsets();
  const navigation = useNavigation();
  const {activeServer, isOffline} = useAuth();
  const styles = useMemo(() => createStyles(colors), [colors]);

  const [tagCloud, setTagCloud] = useState<TagCloudItem[]>([]);
  const [serverInfo, setServerInfo] = useState<ServerInfo | null>(null);
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);

  async function loadData() {
    try {
      const [tagRes, infoRes] = await Promise.all([
        getTagCloud(),
        fetchServerInfo().catch(() => null),
      ]);
      setTagCloud(tagRes.data?.items || []);
      setServerInfo(infoRes);
    } catch (e) {
      Alert.alert(t('common.error'), extractApiError(e));
    } finally {
      setLoading(false);
      setRefreshing(false);
    }
  }

  useEffect(() => {loadData()}, []);

  const onRefresh = useCallback(() => {
    setRefreshing(true);
    loadData();
  }, []);

  const handleTagPress = useCallback((item: TagCloudItem) => {
    (navigation as any).navigate('Main', {
      screen: 'Home',
      params: {q: item.tag},
    });
  }, [navigation]);

  const maxTagCount = useMemo(() => Math.max(...tagCloud.map(t => t.count), 1), [tagCloud]);

  const minTagSize = 12;
  const maxTagSize = 36;

  return (
    <ScreenRoot padded={false}>
      <ScrollView
        contentContainerStyle={[styles.content, screenSafeAreaPadding(insets, !isOffline)]}
        showsVerticalScrollIndicator={false}
        refreshControl={<RefreshControl refreshing={refreshing} onRefresh={onRefresh} />}>
        <View style={styles.header}>
          <TouchableOpacity
            accessibilityRole="button"
            onPress={() => navigation.goBack()}
            style={styles.backButton}>
            <ArrowLeft color={colors.text} size={24} />
          </TouchableOpacity>
          <FluentTitle style={styles.flexTitle}>{t('settings.stats')}</FluentTitle>
          <FluentButton label={t("common.refresh")} variant="secondary" onPress={onRefresh} />
        </View>

        <FluentCard style={styles.section}>
          <FluentTitle>{t('settings.serverInfo')}</FluentTitle>
          <View style={styles.infoRow}>
            <Text style={styles.infoLabel}>{t('settings.serverName')}</Text>
            <Text style={styles.infoValue}>{serverInfo?.name || activeServer?.name || '-'}</Text>
          </View>
          <View style={styles.infoRow}>
            <Text style={styles.infoLabel}>{t('settings.baseUrl')}</Text>
            <Text style={styles.infoValue}>{activeServer?.baseUrl || '-'}</Text>
          </View>
          {serverInfo?.version_desc ? (
            <View style={styles.infoRow}>
              <Text style={styles.infoLabel}>{t('settings.version')}</Text>
              <Text style={styles.infoValue}>{serverInfo.version_desc}</Text>
            </View>
          ) : null}
          {serverInfo?.total_archives != null ? (
            <View style={styles.infoRow}>
              <Text style={styles.infoLabel}>{t('settings.totalArchives')}</Text>
              <Text style={styles.infoValue}>{String(serverInfo.total_archives)}</Text>
            </View>
          ) : null}
          {serverInfo?.total_pages_read != null ? (
            <View style={styles.infoRow}>
              <Text style={styles.infoLabel}>{t('settings.totalPagesRead')}</Text>
              <Text style={styles.infoValue}>{String(serverInfo.total_pages_read)}</Text>
            </View>
          ) : null}
        </FluentCard>

        {serverInfo?.db_extensions && serverInfo.db_extensions.length > 0 ? (
        <FluentCard style={styles.section}>
          <FluentTitle>{t('settings.dbExtensions')}</FluentTitle>
          <View style={styles.badgeRow}>
            {serverInfo.db_extensions.map(ext => (
              <View key={ext.name} style={[styles.extBadge, {backgroundColor: ext.enabled ? colors.primaryMuted : colors.surfaceMuted}]}>
                <Text style={[styles.extBadgeText, {color: ext.enabled ? colors.primary : colors.textMuted}]}>
                  {ext.name}{ext.version ? ` ${ext.version}` : ''}
                </Text>
              </View>
            ))}
          </View>
        </FluentCard>
        ) : null}

        <FluentCard style={styles.section}>
          <FluentTitle>Tag Cloud</FluentTitle>
          {loading ? (
            <FluentCaption>{t('common.loading')}</FluentCaption>
          ) : tagCloud.length === 0 ? (
            <FluentCaption>No tags</FluentCaption>
          ) : (
            <View style={styles.tagCloud}>
              {tagCloud.map((item, index) => {
                const ratio = item.count / maxTagCount;
                const fontSize = minTagSize + ratio * (maxTagSize - minTagSize);
                return (
                  <TouchableOpacity
                    key={index}
                    accessibilityRole="button"
                    onPress={() => handleTagPress(item)}
                    style={styles.tagCloudItem}>
                    <Text style={[styles.tagCloudText, {fontSize, color: colors.primary}]}>
                      {item.display || item.tag}
                    </Text>
                    <Text style={styles.tagCountText}>{item.count}</Text>
                  </TouchableOpacity>
                );
              })}
            </View>
          )}
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
    flexTitle: {flex: 1},
    backButton: {padding: spacing.xs},
    infoRow: {
      flexDirection: 'row',
      justifyContent: 'space-between',
    },
    infoLabel: {
      color: colors.textMuted,
      fontSize: 13,
    },
    infoValue: {
      color: colors.text,
      fontSize: 13,
      fontWeight: '700',
      flexShrink: 1,
      textAlign: 'right',
    },
    badgeRow: {
      flexDirection: 'row',
      flexWrap: 'wrap',
      gap: spacing.sm,
    },
    extBadge: {
      borderRadius: radius.sm,
      paddingHorizontal: spacing.sm,
      paddingVertical: spacing.xs,
    },
    extBadgeText: {
      fontSize: 12,
      fontWeight: '700',
    },
    tagCloud: {
      flexDirection: 'row',
      flexWrap: 'wrap',
      gap: spacing.sm,
      justifyContent: 'center',
      paddingVertical: spacing.sm,
    },
    tagCloudItem: {
      alignItems: 'center',
      paddingHorizontal: spacing.xs,
      paddingVertical: 2,
    },
    tagCloudText: {
      fontWeight: '700',
    },
    tagCountText: {
      color: colors.textMuted,
      fontSize: 10,
      fontWeight: '700',
    },
  });
}
