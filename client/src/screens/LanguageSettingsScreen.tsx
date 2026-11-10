import React, {useMemo} from 'react';
import {ScrollView, StyleSheet, Text, TouchableOpacity, View} from 'react-native';
import {Check, Languages} from 'lucide-react-native';
import {useSafeAreaInsets} from 'react-native-safe-area-context';
import {useNavigation} from '@react-navigation/native';
import {ArrowLeft} from 'lucide-react-native';

import {
  ScreenRoot,
  screenSafeAreaPadding,
} from '../components/SafeAreaSurface';
import {FluentCard, FluentCaption, FluentTitle} from '../components/fluent';
import {useI18n} from '../i18n';
import {useAuth} from '../auth/AuthContext';
import {spacing, type ThemeColors} from '../theme/colors';
import {useTheme} from '../theme/ThemeContext';

export function LanguageSettingsScreen() {
  const {t} = useI18n();
  const {colors} = useTheme();
  const {languagePreference, setLanguagePreference} = useI18n();
  const insets = useSafeAreaInsets();
  const {isOffline} = useAuth();
  const navigation = useNavigation();
  const styles = useMemo(() => createStyles(colors), [colors]);

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
          <FluentTitle>{t('settings.language')}</FluentTitle>
        </View>

        <FluentCard style={styles.section}>
          <FluentCaption>{t('settings.languageDescription')}</FluentCaption>
          <View style={styles.actionList}>
            <LanguageActionRow
              active={languagePreference === 'system'}
              colors={colors}
              label={t('settings.languageSystem')}
              onPress={() => setLanguagePreference('system')}
            />
            <LanguageActionRow
              active={languagePreference === 'zh'}
              colors={colors}
              label={t('settings.languageChinese')}
              onPress={() => setLanguagePreference('zh')}
            />
            <LanguageActionRow
              active={languagePreference === 'en'}
              colors={colors}
              label={t('settings.languageEnglish')}
              onPress={() => setLanguagePreference('en')}
            />
          </View>
        </FluentCard>
      </ScrollView>
    </ScreenRoot>
  );
}

function LanguageActionRow({
  active,
  colors,
  label,
  onPress,
}: {
  active: boolean;
  colors: ThemeColors;
  label: string;
  onPress: () => void;
}) {
  const styles = useMemo(() => createStyles(colors), [colors]);
  return (
    <TouchableOpacity
      activeOpacity={0.78}
      accessibilityLabel={label}
      accessibilityRole="button"
      onPress={onPress}
      style={styles.actionRow}>
      <View style={styles.iconWrap}>
        <Languages color={active ? colors.primary : colors.textMuted} size={18} />
      </View>
      <Text style={[styles.actionLabel, active && styles.actionLabelActive]}>{label}</Text>
      {active ? (
        <View style={styles.checkIcon}>
          <Check color={colors.white} size={15} />
        </View>
      ) : null}
    </TouchableOpacity>
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
    actionLabel: {
      color: colors.text,
      flex: 1,
      fontSize: 15,
      fontWeight: '800',
    },
    actionLabelActive: {color: colors.primary},
    iconWrap: {
      alignItems: 'center',
      height: 36,
      justifyContent: 'center',
      width: 28,
    },
    checkIcon: {
      alignItems: 'center',
      backgroundColor: colors.primary,
      borderRadius: 13,
      height: 26,
      justifyContent: 'center',
      width: 26,
    },
  });
}
