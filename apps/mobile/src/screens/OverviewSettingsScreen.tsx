import React, {useMemo} from 'react';
import {ScrollView, StyleSheet, Text, TouchableOpacity, View} from 'react-native';
import {ArrowLeft} from 'lucide-react-native';
import {useSafeAreaInsets} from 'react-native-safe-area-context';
import {useNavigation} from '@react-navigation/native';
import {ScreenRoot, screenSafeAreaPadding} from '../components/SafeAreaSurface';
import {FluentCard, FluentCaption, FluentTitle} from '../components/fluent';
import {useI18n} from '../i18n';
import {spacing, type ThemeColors} from '../theme/colors';
import {useTheme} from '../theme/ThemeContext';
import {useAuth} from '../auth/AuthContext';

function formatDate(value?: string, fallback = '-'): string {
  if (!value) return fallback;
  try {
    const d = new Date(value);
    if (isNaN(d.getTime())) return fallback;
    return d.toLocaleString();
  } catch {
    return fallback;
  }
}

export function OverviewSettingsScreen() {
  const {t} = useI18n();
  const {colors} = useTheme();
  const insets = useSafeAreaInsets();
  const navigation = useNavigation();
  const styles = useMemo(() => createStyles(colors), [colors]);
  const {user, activeServer, isOffline} = useAuth();

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
          <FluentTitle>{t('settings.overview')}</FluentTitle>
        </View>

        <FluentCard style={styles.section}>
          <FluentCaption>{'User info'}</FluentCaption>
          <View style={styles.infoRow}>
            <Text style={styles.infoLabel}>{'Username'}</Text>
            <Text style={styles.infoValue}>{user?.username ?? '-'}</Text>
          </View>
          <View style={styles.infoRow}>
            <Text style={styles.infoLabel}>{'User ID'}</Text>
            <Text style={styles.infoValue}>{user?.id?.toString() ?? '-'}</Text>
          </View>
          <View style={styles.infoRow}>
            <Text style={styles.infoLabel}>{'Admin'}</Text>
            <Text style={styles.infoValue}>{user?.isAdmin ? 'Yes' : 'No'}</Text>
          </View>
          {user?.createdAt ? (
            <View style={styles.infoRow}>
              <Text style={styles.infoLabel}>{'Created at'}</Text>
              <Text style={styles.infoValue}>{formatDate(user.createdAt)}</Text>
            </View>
          ) : null}
        </FluentCard>

        {activeServer ? (
          <FluentCard style={styles.section}>
            <FluentCaption>{'Server info'}</FluentCaption>
            <View style={styles.infoRow}>
              <Text style={styles.infoLabel}>{'Server name'}</Text>
              <Text style={styles.infoValue}>{activeServer.name}</Text>
            </View>
            <View style={styles.infoRow}>
              <Text style={styles.infoLabel}>{'Server URL'}</Text>
              <Text style={styles.infoValue}>{activeServer.baseUrl}</Text>
            </View>
          </FluentCard>
        ) : null}
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
    infoRow: {
      alignItems: 'center',
      flexDirection: 'row',
      minHeight: 44,
      paddingVertical: spacing.xs,
    },
    infoLabel: {
      color: colors.textMuted,
      flex: 1,
      fontSize: 15,
    },
    infoValue: {
      color: colors.text,
      flex: 2,
      fontSize: 15,
      fontWeight: '600',
      textAlign: 'right',
    },
  });
}
