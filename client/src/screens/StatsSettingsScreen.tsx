import React, {useCallback, useEffect, useMemo, useState} from 'react';
import {Alert, RefreshControl, ScrollView, StyleSheet, Text, TouchableOpacity, View} from 'react-native';
import {ArrowLeft} from 'lucide-react-native';
import {useSafeAreaInsets} from 'react-native-safe-area-context';
import {useNavigation} from '@react-navigation/native';
import {ScreenRoot, screenSafeAreaPadding} from '../components/SafeAreaSurface';
import {FluentButton, FluentCard, FluentCaption, FluentTitle} from '../components/fluent';
import {useI18n} from '../i18n';
import {extractApiError} from '../api/client';
import {spacing, radius, type ThemeColors} from '../theme/colors';
import {useTheme} from '../theme/ThemeContext';
import {getTagCloud} from '../api/admin';
import type {TagCloudItem} from '../api/admin';
import {useAuth} from '../auth/AuthContext';

export function StatsSettingsScreen() {
  const {t} = useI18n();
  const {colors} = useTheme();
  const insets = useSafeAreaInsets();
  const navigation = useNavigation();
  const {activeServer} = useAuth();
  const styles = useMemo(() => createStyles(colors), [colors]);

  const [tagCloud, setTagCloud] = useState<TagCloudItem[]>([]);
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);

  async function loadData() {
    try {
      const res = await getTagCloud();
      setTagCloud(res.data?.items || []);
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
    Alert.alert('Tag Info', `Tag: ${item.display || item.tag}\nCount: ${item.count}`);
  }, []);

  const maxTagCount = useMemo(() => Math.max(...tagCloud.map(t => t.count), 1), [tagCloud]);

  const minTagSize = 12;
  const maxTagSize = 36;

  return (
    <ScreenRoot padded={false}>
      <ScrollView
        contentContainerStyle={[styles.content, screenSafeAreaPadding(insets)]}
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
          <FluentTitle>Server Info</FluentTitle>
          <View style={styles.infoRow}>
            <Text style={styles.infoLabel}>Server Name</Text>
            <Text style={styles.infoValue}>{activeServer?.name || '-'}</Text>
          </View>
          <View style={styles.infoRow}>
            <Text style={styles.infoLabel}>Base URL</Text>
            <Text style={styles.infoValue}>{activeServer?.baseUrl || '-'}</Text>
          </View>
          {(activeServer as any)?.version ? (
            <View style={styles.infoRow}>
              <Text style={styles.infoLabel}>Version</Text>
              <Text style={styles.infoValue}>{(activeServer as any).version}</Text>
            </View>
          ) : null}
          {(activeServer as any)?.archiveCount != null ? (
            <View style={styles.infoRow}>
              <Text style={styles.infoLabel}>Archives</Text>
              <Text style={styles.infoValue}>{(activeServer as any).archiveCount}</Text>
            </View>
          ) : null}
          {(activeServer as any)?.pageCount != null ? (
            <View style={styles.infoRow}>
              <Text style={styles.infoLabel}>Pages</Text>
              <Text style={styles.infoValue}>{(activeServer as any).pageCount}</Text>
            </View>
          ) : null}
        </FluentCard>

        <FluentCard style={styles.section}>
          <FluentTitle>Database Extensions</FluentTitle>
          <View style={styles.badgeRow}>
            <View style={[styles.extBadge, {backgroundColor: colors.primaryMuted}]}>
              <Text style={[styles.extBadgeText, {color: colors.primary}]}>pg_trgm</Text>
            </View>
            <View style={[styles.extBadge, {backgroundColor: colors.surfaceMuted}]}>
              <Text style={[styles.extBadgeText, {color: colors.textMuted}]}>vector</Text>
            </View>
            <View style={[styles.extBadge, {backgroundColor: colors.surfaceMuted}]}>
              <Text style={[styles.extBadgeText, {color: colors.textMuted}]}>uuid-ossp</Text>
            </View>
          </View>
        </FluentCard>

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
