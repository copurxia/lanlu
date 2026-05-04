import React, {useCallback, useEffect, useMemo, useState} from 'react';
import {Alert, RefreshControl, ScrollView, StyleSheet, Switch, Text, TextInput, TouchableOpacity, View} from 'react-native';
import {ArrowLeft} from 'lucide-react-native';
import {useSafeAreaInsets} from 'react-native-safe-area-context';
import {useNavigation} from '@react-navigation/native';
import {ScreenRoot, screenSafeAreaPadding} from '../components/SafeAreaSurface';
import {FluentButton, FluentCard, FluentTitle} from '../components/fluent';
import {useI18n} from '../i18n';
import {extractApiError} from '../api/client';
import {adminListSystemSettings, adminUpdateSystemSettings, type SystemSetting} from '../api/admin';
import {spacing, radius, type ThemeColors} from '../theme/colors';
import {useTheme} from '../theme/ThemeContext';

const CATEGORY_LABELS: Record<string, string> = {
  storage: 'settings.system.storage',
  performance: 'settings.system.performance',
  server: 'settings.system.server',
  ssl: 'settings.system.ssl',
};

const CATEGORY_ICONS: Record<string, string> = {
  storage: '📁',
  performance: '⚡',
  server: '🖥️',
  ssl: '🔒',
};

export function SystemSettingsScreen() {
  const {t, language} = useI18n();
  const {colors} = useTheme();
  const insets = useSafeAreaInsets();
  const navigation = useNavigation();
  const styles = useMemo(() => createStyles(colors), [colors]);

  const [settings, setSettings] = useState<SystemSetting[]>([]);
  const [loading, setLoading] = useState(false);
  const [refreshing, setRefreshing] = useState(false);
  const [saving, setSaving] = useState(false);
  const [activeCategory, setActiveCategory] = useState('');

  const grouped = useMemo(() => {
    const map: Record<string, SystemSetting[]> = {};
    for (const s of settings) {
      const cat = s.category || 'general';
      if (!map[cat]) map[cat] = [];
      map[cat].push(s);
    }
    return map;
  }, [settings]);

  const categories = useMemo(() => Object.keys(grouped), [grouped]);

  useEffect(() => {
    if (!activeCategory && categories.length > 0) {
      setActiveCategory(categories[0]);
    }
  }, [categories, activeCategory]);

  const activeSettings = useMemo(() => {
    if (!activeCategory) return [];
    return grouped[activeCategory] || [];
  }, [grouped, activeCategory]);

  const localValues = useMemo(() => {
    const map: Record<string, string> = {};
    for (const s of settings) map[s.key] = s.value;
    return map;
  }, [settings]);

  const [dirtyValues, setDirtyValues] = useState<Record<string, string>>({});

  useEffect(() => {
    setDirtyValues({});
  }, [settings]);

  function getValue(key: string): string {
    return key in dirtyValues ? dirtyValues[key] : (localValues[key] ?? '');
  }

  function setValue(key: string, value: string) {
    setDirtyValues(prev => {
      const original = localValues[key];
      if (value === original) {
        const next = {...prev};
        delete next[key];
        return next;
      }
      return {...prev, [key]: value};
    });
  }

  const hasDirty = Object.keys(dirtyValues).length > 0;

  const loadSettings = useCallback(async () => {
    try {
      const resp = await adminListSystemSettings();
      setSettings(resp.data?.settings || []);
    } catch (e) {
      Alert.alert(t('common.error'), extractApiError(e));
    }
  }, [t]);

  useEffect(() => {
    setLoading(true);
    loadSettings().finally(() => setLoading(false));
  }, [loadSettings]);

  const onRefresh = useCallback(async () => {
    setRefreshing(true);
    await loadSettings();
    setRefreshing(false);
  }, [loadSettings]);

  const handleSaveCategory = useCallback(async () => {
    const catSettings = activeSettings.map(s => s.key);
    const toSave: Record<string, string> = {};
    for (const key of catSettings) {
      if (key in dirtyValues) toSave[key] = dirtyValues[key];
    }
    if (Object.keys(toSave).length === 0) return;

    setSaving(true);
    try {
      await adminUpdateSystemSettings(toSave);
      await loadSettings();
      Alert.alert('', t('common.settingsSaved'));
    } catch (e) {
      Alert.alert(t('common.error'), extractApiError(e));
    } finally {
      setSaving(false);
    }
  }, [activeSettings, dirtyValues, loadSettings, t]);

  return (
    <ScreenRoot padded={false}>
      <ScrollView
        contentContainerStyle={[styles.content, screenSafeAreaPadding(insets)]}
        showsVerticalScrollIndicator={false}
        refreshControl={<RefreshControl refreshing={refreshing} onRefresh={onRefresh} tintColor={colors.primary} />}>
        <View style={styles.header}>
          <TouchableOpacity
            accessibilityRole="button"
            onPress={() => navigation.goBack()}
            style={styles.backButton}>
            <ArrowLeft color={colors.text} size={24} />
          </TouchableOpacity>
          <FluentTitle>{t('settings.system.title')}</FluentTitle>
        </View>

        <ScrollView
          horizontal
          showsHorizontalScrollIndicator={false}
          contentContainerStyle={styles.chipsRow}>
          {categories.map(cat => (
            <TouchableOpacity
              key={cat}
              accessibilityRole="button"
              onPress={() => setActiveCategory(cat)}
              style={[
                styles.chip,
                activeCategory === cat && {backgroundColor: colors.primary, borderColor: colors.primary},
              ]}>
              <Text style={[styles.chipText, activeCategory === cat && {color: colors.white}]}>
                {CATEGORY_ICONS[cat] || '📋'} {CATEGORY_LABELS[cat] ? t(CATEGORY_LABELS[cat] as any) : cat}
              </Text>
            </TouchableOpacity>
          ))}
        </ScrollView>

        {loading && settings.length === 0 ? (
          <FluentCard style={styles.section}><Text style={styles.loadingText}>{t('common.loading')}</Text></FluentCard>
        ) : !activeCategory || activeSettings.length === 0 ? (
          <FluentCard style={styles.section}><Text style={styles.emptyText}>No settings</Text></FluentCard>
        ) : (
          <FluentCard style={styles.section}>
            <View style={styles.categoryHeader}>
              <Text style={styles.categoryTitle}>{activeCategory}</Text>
              <FluentButton
                label={saving ? t('common.saving') : t('common.save')}
                variant="primary"
                onPress={handleSaveCategory}
                disabled={saving || !hasDirty}
              />
            </View>
            <View style={styles.settingList}>
              {activeSettings.map(setting => {
                const isDirty = setting.key in dirtyValues;
                const displayValue = getValue(setting.key);
                const isBool = setting.valueType === 'boolean';
                const rawDesc = setting.description;
                let localizedLabel = setting.key;
                if (rawDesc) {
                  if (typeof rawDesc === 'object') {
                    localizedLabel = (rawDesc as Record<string, string>)[language]
                      || (rawDesc as Record<string, string>)['en']
                      || (rawDesc as Record<string, string>)[Object.keys(rawDesc)[0]]
                      || setting.key;
                  } else {
                    localizedLabel = String(rawDesc);
                  }
                }

                if (isBool) {
                  const boolVal = displayValue === 'true';
                  return (
                    <View key={setting.key} style={[styles.settingRow, isDirty && styles.settingRowDirty]}>
                      <Text style={styles.settingLabel} numberOfLines={2}>{localizedLabel}</Text>
                      <Switch
                        trackColor={{false: colors.surfaceMuted, true: colors.primaryMuted}}
                        thumbColor={boolVal ? colors.primary : colors.textMuted}
                        value={boolVal}
                        onValueChange={v => setValue(setting.key, v.toString())}
                      />
                    </View>
                  );
                }

                return (
                  <View key={setting.key} style={[styles.settingRow, isDirty && styles.settingRowDirty]}>
                    <View style={styles.settingInfo}>
                      <Text style={styles.settingLabel} numberOfLines={2}>{localizedLabel}</Text>
                    </View>
                    <TextInput
                      style={[styles.inlineInput, {color: colors.text, borderColor: colors.border, backgroundColor: colors.surfaceMuted}]}
                      value={displayValue}
                      onChangeText={v => setValue(setting.key, v)}
                      keyboardType={setting.valueType === 'integer' || setting.valueType === 'long' ? 'numeric' : 'default'}
                      placeholder={setting.valueType === 'path' ? '/path/to/dir' : undefined}
                      placeholderTextColor={colors.textMuted}
                    />
                  </View>
                );
              })}
            </View>
          </FluentCard>
        )}
      </ScrollView>
    </ScreenRoot>
  );
}

function createStyles(colors: ThemeColors) {
  return StyleSheet.create({
    content: {gap: spacing.md, paddingBottom: spacing.xl},
    section: {gap: spacing.md},
    header: {flexDirection: 'row', alignItems: 'center', gap: spacing.md},
    backButton: {padding: spacing.xs},
    chipsRow: {flexDirection: 'row', gap: spacing.sm, paddingVertical: spacing.xs},
    chip: {
      borderRadius: radius.md,
      borderWidth: StyleSheet.hairlineWidth,
      borderColor: colors.border,
      paddingHorizontal: spacing.md,
      paddingVertical: spacing.sm,
    },
    chipText: {color: colors.text, fontSize: 13, fontWeight: '700'},
    loadingText: {color: colors.textMuted, fontSize: 14, textAlign: 'center', padding: spacing.lg},
    emptyText: {color: colors.textMuted, fontSize: 14, textAlign: 'center', padding: spacing.lg},
    categoryHeader: {
      flexDirection: 'row',
      alignItems: 'center',
      justifyContent: 'space-between',
    },
    categoryTitle: {color: colors.text, fontSize: 18, fontWeight: '800'},
    settingList: {
      borderColor: colors.border,
      borderRadius: radius.md,
      borderWidth: StyleSheet.hairlineWidth,
      overflow: 'hidden',
    },
    settingRow: {
      borderBottomColor: colors.border,
      borderBottomWidth: StyleSheet.hairlineWidth,
      flexDirection: 'row',
      alignItems: 'center',
      gap: spacing.sm,
      padding: spacing.md,
    },
    settingRowDirty: {backgroundColor: colors.primaryMuted},
    settingInfo: {flex: 1},
    settingLabel: {color: colors.text, fontSize: 13, fontWeight: '700', flex: 1},
    inlineInput: {
      borderRadius: radius.sm,
      borderWidth: StyleSheet.hairlineWidth,
      fontSize: 13,
      minHeight: 36,
      paddingHorizontal: spacing.sm,
      paddingVertical: spacing.xs,
      textAlign: 'right',
      width: 160,
    },
  });
}
