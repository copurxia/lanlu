import React, {useMemo} from 'react';
import {ActivityIndicator, StyleSheet, Text, View} from 'react-native';
import {Heart, BookOpen, FileText, Database} from 'lucide-react-native';
import {useTheme} from '../theme/ThemeContext';
import {useI18n} from '../i18n';
import {spacing, radius, type ThemeColors} from '../theme/colors';

export type UserStats = {
  favoriteCount: number;
  readCount: number;
  totalPagesRead: number;
  totalArchives: number;
};

type CardConfig = {
  key: keyof UserStats;
  icon: React.ReactNode;
  labelKey: string;
};

export function DashboardStats({stats, loading}: {stats: UserStats | null; loading: boolean}) {
  const {colors} = useTheme();
  const {t} = useI18n();
  const styles = useMemo(() => createStyles(colors), [colors]);

  const cards: CardConfig[] = useMemo(() => [
    {key: 'favoriteCount', icon: <Heart color={colors.textMuted} size={20} />, labelKey: 'dashboard.favorites'},
    {key: 'readCount', icon: <BookOpen color={colors.textMuted} size={20} />, labelKey: 'dashboard.readArchives'},
    {key: 'totalPagesRead', icon: <FileText color={colors.textMuted} size={20} />, labelKey: 'dashboard.totalPagesRead'},
    {key: 'totalArchives', icon: <Database color={colors.textMuted} size={20} />, labelKey: 'dashboard.totalArchives'},
  ], [colors.textMuted]);

  if (loading) {
    return (
      <View style={styles.grid}>
        {cards.map(card => (
          <View key={card.key} style={styles.card}>
            <ActivityIndicator color={colors.textMuted} size="small" />
          </View>
        ))}
      </View>
    );
  }

  return (
    <View style={styles.grid}>
      {cards.map(card => (
        <View key={card.key} style={styles.card}>
          <View style={styles.cardHeader}>
            {card.icon}
            <Text style={styles.value}>
              {stats ? (stats[card.key] ?? 0).toLocaleString() : '0'}
            </Text>
          </View>
          <Text style={styles.label}>{t(card.labelKey as any)}</Text>
        </View>
      ))}
    </View>
  );
}

function createStyles(colors: ThemeColors) {
  return StyleSheet.create({
    grid: {
      flexDirection: 'row',
      flexWrap: 'wrap',
      gap: spacing.sm,
    },
    card: {
      backgroundColor: colors.surface,
      borderColor: colors.border,
      borderRadius: radius.md,
      borderWidth: 1,
      flex: 1,
      gap: spacing.xs,
      minWidth: '45%',
      padding: spacing.md,
    },
    cardHeader: {
      alignItems: 'center',
      flexDirection: 'row',
      justifyContent: 'space-between',
    },
    value: {
      color: colors.text,
      fontSize: 22,
      fontWeight: '800',
    },
    label: {
      color: colors.textMuted,
      fontSize: 12,
    },
  });
}
