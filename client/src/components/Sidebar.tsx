import React, {useMemo} from 'react';
import {
  Image,
  ScrollView,
  StyleSheet,
  Text,
  TouchableOpacity,
  View,
} from 'react-native';
import {useSafeAreaInsets} from 'react-native-safe-area-context';
import {Moon, Sun, Languages, Repeat, LogOut} from 'lucide-react-native';
import {Drawer} from './Drawer';
import {useTheme} from '../theme/ThemeContext';
import {useI18n} from '../i18n';
import {spacing, radius} from '../theme/colors';
import type {Category} from '../types/api';
import type {SmartFilter} from '../api/lanlu';

type SidebarProps = {
  open: boolean;
  onClose: () => void;
  categories: Category[];
  smartFilters?: SmartFilter[];
  selectedCategoryId: string | null;
  onSelectCategory: (category: Category | null) => void;
  serverName?: string;
  onSwitchServer?: () => void;
  onSignOut?: () => void;
};

export function Sidebar({
  open,
  onClose,
  categories,
  smartFilters = [],
  selectedCategoryId,
  onSelectCategory,
  serverName,
  onSwitchServer,
  onSignOut,
}: SidebarProps) {
  const {colors, effectiveScheme, setThemePreference} = useTheme();
  const {language, t, setLanguagePreference} = useI18n();
  const insets = useSafeAreaInsets();
  const enabled = categories.filter(c => c.enabled !== false);

  const styles = useMemo(
    () =>
      StyleSheet.create({
        container: {
          backgroundColor: colors.surface,
          flex: 1,
          paddingBottom: insets.bottom + 16,
          width: 260,
        },
        headerArea: {
          flexDirection: 'row',
          alignItems: 'center',
          gap: spacing.sm,
          paddingHorizontal: spacing.lg,
          paddingTop: spacing.md,
          paddingBottom: spacing.md,
        },
        headerInfo: {
          flex: 1,
        },
        logoText: {
          color: colors.text,
          fontSize: 18,
          fontWeight: '900',
        },
        serverText: {
          color: colors.textMuted,
          fontSize: 12,
          marginTop: 1,
        },
        headerAction: {
          padding: spacing.xs,
        },
        sectionTitle: {
          color: colors.textMuted,
          fontSize: 12,
          fontWeight: '800',
          paddingHorizontal: spacing.lg,
          paddingTop: spacing.md,
          paddingBottom: spacing.xs,
          textTransform: 'uppercase',
        },
        navItem: {
          paddingHorizontal: spacing.lg,
          paddingVertical: 10,
        },
        navItemActive: {
          backgroundColor: colors.primaryMuted,
        },
        navText: {
          color: colors.text,
          fontSize: 15,
          fontWeight: '700',
        },
        navTextActive: {
          color: colors.primary,
        },
        divider: {
          borderTopColor: colors.border,
          borderTopWidth: StyleSheet.hairlineWidth,
          marginHorizontal: spacing.lg,
          marginVertical: spacing.sm,
        },
        bottomRow: {
          flexDirection: 'row',
          gap: spacing.sm,
          paddingHorizontal: spacing.lg,
          paddingTop: spacing.sm,
        },
        toggleButton: {
          alignItems: 'center',
          backgroundColor: colors.surfaceMuted,
          borderRadius: radius.md,
          flex: 1,
          flexDirection: 'row',
          gap: spacing.sm,
          justifyContent: 'center',
          paddingVertical: 10,
        },
        toggleText: {
          color: colors.text,
          fontSize: 13,
          fontWeight: '700',
        },
        scrollContent: {
          flexGrow: 1,
        },
      }),
    [colors, insets],
  );

  return (
    <Drawer open={open} onClose={onClose} side="left" showHandle={false} enablePanDownToClose={false}
      backdropColor={effectiveScheme === 'dark' ? 'rgba(0,0,0,0.7)' : 'rgba(255,255,255,0.7)'}
      blurType={effectiveScheme === 'dark' ? 'dark' : 'light'}
      style={{backgroundColor: colors.surface}}>
      <View style={styles.container}>
        <View style={styles.headerArea}>
          <Image source={require('../assets/lanlu_logo.png')} style={{width: 28, height: 28, borderRadius: 6}} />
          <View style={styles.headerInfo}>
            <Text style={styles.logoText}>Lanlu</Text>
            {serverName ? <Text style={styles.serverText}>{serverName}</Text> : null}
          </View>
          {onSwitchServer ? (
            <TouchableOpacity style={styles.headerAction} onPress={() => { onSwitchServer(); onClose(); }}>
              <Repeat color={colors.textMuted} size={20} />
            </TouchableOpacity>
          ) : null}
          {onSignOut ? (
            <TouchableOpacity style={styles.headerAction} onPress={() => { onSignOut(); onClose(); }}>
              <LogOut color={colors.danger} size={20} />
            </TouchableOpacity>
          ) : null}
        </View>
        <ScrollView contentContainerStyle={styles.scrollContent}>
          <Text style={styles.sectionTitle}>{t('home.categories')}</Text>
          <TouchableOpacity
            style={[styles.navItem, selectedCategoryId === null && styles.navItemActive]}
            onPress={() => { onSelectCategory(null); onClose(); }}>
            <Text style={[styles.navText, selectedCategoryId === null && styles.navTextActive]}>
              {t('common.all')}
            </Text>
          </TouchableOpacity>
          {enabled.map(cat => (
            <TouchableOpacity
              key={cat.catid}
              style={[styles.navItem, selectedCategoryId === cat.catid && styles.navItemActive]}
              onPress={() => { onSelectCategory(cat); onClose(); }}>
              <Text style={[styles.navText, selectedCategoryId === cat.catid && styles.navTextActive]}>
                {cat.icon ? `${cat.icon} ` : ''}{cat.name}
              </Text>
            </TouchableOpacity>
          ))}
          {smartFilters.length > 0 ? (
            <>
              <Text style={styles.sectionTitle}>{t('search.smartCategory')} ({smartFilters.length})</Text>
              {smartFilters.map(f => (
                <TouchableOpacity
                  key={f.id}
                  style={styles.navItem}
                  onPress={onClose}>
                  <Text style={styles.navText}>{f.name}</Text>
                </TouchableOpacity>
              ))}
            </>
          ) : null}
        </ScrollView>
        <View style={styles.divider} />
        <View style={styles.bottomRow}>
          <TouchableOpacity
            style={styles.toggleButton}
            onPress={() => setThemePreference(effectiveScheme === 'dark' ? 'light' : 'dark')}>
            {effectiveScheme === 'dark' ? <Sun color={colors.text} size={16} /> : <Moon color={colors.text} size={16} />}
            <Text style={styles.toggleText}>{effectiveScheme === 'dark' ? t('settings.themeLight') : t('settings.themeDark')}</Text>
          </TouchableOpacity>
          <TouchableOpacity
            style={styles.toggleButton}
            onPress={() => setLanguagePreference(language === 'zh' ? 'en' : 'zh')}>
            <Languages color={colors.text} size={16} />
            <Text style={styles.toggleText}>{language === 'zh' ? '中文' : 'EN'}</Text>
          </TouchableOpacity>
        </View>
      </View>
    </Drawer>
  );
}
