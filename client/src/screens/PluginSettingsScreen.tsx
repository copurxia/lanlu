import React, {useCallback, useEffect, useMemo, useState} from 'react';
import {Alert, Modal, RefreshControl, ScrollView, StyleSheet, Text, TouchableOpacity, View} from 'react-native';
import {ArrowLeft, Trash2} from 'lucide-react-native';
import {useSafeAreaInsets} from 'react-native-safe-area-context';
import {useNavigation} from '@react-navigation/native';
import {ScreenRoot, ModalBackdrop, screenSafeAreaPadding} from '../components/SafeAreaSurface';
import {
  FluentButton,
  FluentCard,
  FluentCaption,
  FluentSwitch,
  FluentSwitchRow,
  FluentTextField,
  FluentTitle,
  FluentSpinner,
} from '../components/fluent';
import {useI18n} from '../i18n';
import {extractApiError} from '../api/client';
import {spacing, radius, type ThemeColors} from '../theme/colors';
import {useTheme} from '../theme/ThemeContext';
import {
  adminListPlugins,
  adminTogglePlugin,
  adminDeletePlugin,
  adminInstallPlugin,
  adminUpdatePlugin,
  adminCheckPluginUpdate,
  adminGetPluginConfig,
  adminUpdatePluginConfig,
} from '../api/admin';
import type {Plugin, PluginParameter} from '../api/admin';

const PLUGIN_TYPE_LABELS: Record<string, string> = {
  metadata: 'common.pluginTypeMetadata',
  download: 'common.pluginTypeDownload',
  login: 'common.pluginTypeLogin',
  script: 'common.pluginTypeScript',
};

const PLUGIN_TYPE_COLORS: Record<string, string> = {
  metadata: 'primary',
  download: 'success',
  login: 'muted',
  script: 'warning',
};

const BADGE_BG: Record<string, string> = {
  primary: 'primary',
  success: 'success',
  muted: 'textMuted',
  warning: 'warning',
};

export function PluginSettingsScreen() {
  const {t} = useI18n();
  const {colors} = useTheme();
  const insets = useSafeAreaInsets();
  const navigation = useNavigation();
  const styles = useMemo(() => createStyles(colors), [colors]);

  const [plugins, setPlugins] = useState<Plugin[]>([]);
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [installModalOpen, setInstallModalOpen] = useState(false);
  const [installUrl, setInstallUrl] = useState('');
  const [typeFilter, setTypeFilter] = useState('');
  const [checkingAll, setCheckingAll] = useState(false);
  const [configModalOpen, setConfigModalOpen] = useState(false);
  const [configPlugin, setConfigPlugin] = useState<Plugin | null>(null);
  const [configParameters, setConfigParameters] = useState<PluginParameter[]>([]);
  const [configFormValues, setConfigFormValues] = useState<Record<string, unknown>>({});
  const [configLoading, setConfigLoading] = useState(false);
  const [configSaving, setConfigSaving] = useState(false);

  async function loadData() {
    try {
      const res = await adminListPlugins();
      setPlugins(res.data?.plugins || []);
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

  const pluginTypes = useMemo(() => {
    return [...new Set(plugins.map(p => p.plugin_type))];
  }, [plugins]);

  const filteredPlugins = useMemo(() => {
    if (!typeFilter) return plugins;
    return plugins.filter(p => p.plugin_type === typeFilter);
  }, [plugins, typeFilter]);

  async function handleToggle(plugin: Plugin) {
    try {
      await adminTogglePlugin(plugin.namespace, !plugin.enabled);
      await loadData();
    } catch (e) {Alert.alert(t('common.error'), extractApiError(e));}
  }

  function confirmDelete(plugin: Plugin) {
    Alert.alert(t('common.confirm'), t('settings.pluginDeleteConfirm'), [
      {text: t('common.cancel'), style: 'cancel'},
      {text: t('common.delete'), style: 'destructive', onPress: () => handleDelete(plugin.namespace)},
    ]);
  }

  async function handleDelete(namespace: string) {
    try {
      await adminDeletePlugin(namespace);
      await loadData();
    } catch (e) {Alert.alert(t('common.error'), extractApiError(e));}
  }

  async function handleInstall() {
    if (!installUrl.trim()) return;
    try {
      await adminInstallPlugin(installUrl.trim());
      setInstallModalOpen(false);
      setInstallUrl('');
      await loadData();
      Alert.alert(t('common.success'), t('settings.pluginInstallSuccess'));
    } catch (e) {Alert.alert(t('common.error'), extractApiError(e));}
  }

  async function handleCheckUpdate(plugin: Plugin) {
    try {
      await adminCheckPluginUpdate(plugin.namespace);
      Alert.alert(t('common.success'), t('common.checkUpdate'));
    } catch (e) {Alert.alert(t('common.error'), extractApiError(e));}
  }

  async function handleUpdate(plugin: Plugin, force = false) {
    try {
      await adminUpdatePlugin(plugin.namespace, force);
      await loadData();
      Alert.alert(t('common.success'), t('settings.pluginUpdateSuccess'));
    } catch (e) {
      const msg = extractApiError(e);
      if (!force && msg.toLowerCase().includes('without force')) {
        Alert.alert(
          t('settings.pluginForceUpdate'),
          t('settings.pluginForceUpdateConfirm', {name: plugin.name}),
          [
            {text: t('common.cancel'), style: 'cancel'},
            {text: t('settings.pluginForceUpdate'), style: 'destructive', onPress: () => handleUpdate(plugin, true)},
          ],
        );
      } else {
        Alert.alert(t('common.error'), msg);
      }
    }
  }

  function handleConfigure(plugin: Plugin) {
    setConfigPlugin(plugin);
    setConfigModalOpen(true);
    loadPluginConfig(plugin.namespace);
  }

  async function loadPluginConfig(namespace: string) {
    setConfigLoading(true);
    setConfigParameters([]);
    setConfigFormValues({});
    try {
      const res = await adminGetPluginConfig(namespace);
      const data = res.data;
      if (data?.has_schema && data?.parameters) {
        let parsed: PluginParameter[] = [];
        if (typeof data.parameters === 'string') {
          try {
            parsed = (JSON.parse(data.parameters) as unknown[]).filter(
              (p: unknown) => typeof p === 'object' && p !== null && 'type' in (p as Record<string, unknown>) && 'desc' in (p as Record<string, unknown>),
            ) as PluginParameter[];
          } catch (_) {}
        } else if (Array.isArray(data.parameters)) {
          parsed = data.parameters.filter(
            (p: unknown) => typeof p === 'object' && p !== null && 'type' in (p as Record<string, unknown>) && 'desc' in (p as Record<string, unknown>),
          ) as PluginParameter[];
        }
        setConfigParameters(parsed);
        const initial: Record<string, unknown> = {};
        parsed.forEach((p, i) => {
          initial[`param${i}`] = p.value ?? p.default_value ?? '';
        });
        setConfigFormValues(initial);
      }
    } catch (_) {
      setConfigParameters([]);
    } finally {
      setConfigLoading(false);
    }
  }

  async function handleSaveConfig() {
    if (!configPlugin) return;
    setConfigSaving(true);
    try {
      const updated = configParameters.map((p, i) => ({
        ...p,
        value: configFormValues[`param${i}`] ?? p.default_value ?? '',
      }));
      await adminUpdatePluginConfig(configPlugin.namespace, updated);
      setConfigModalOpen(false);
      Alert.alert(t('common.success'), t('settings.pluginConfigSaved'));
    } catch (e) {
      Alert.alert(t('common.error'), t('settings.pluginConfigSaveFailed'));
    } finally {
      setConfigSaving(false);
    }
  }

  function handleConfigFieldChange(key: string, value: unknown) {
    setConfigFormValues(prev => ({...prev, [key]: value}));
  }

  async function handleCheckAllUpdates() {
    const withUpdateUrl = plugins.filter(p => p.update_url);
    if (withUpdateUrl.length === 0) {
      Alert.alert(t('common.info'), t('common.noUpdateUrl'));
      return;
    }
    setCheckingAll(true);
    const results = await Promise.allSettled(
      withUpdateUrl.map(p => adminCheckPluginUpdate(p.namespace)),
    );
    setCheckingAll(false);
    let updates = 0;
    let latest = 0;
    let failed = 0;
    for (const r of results) {
      if (r.status === 'fulfilled') {
        const hasUpdate = Boolean((r.value as {data?: {has_update?: boolean}} | undefined)?.data?.has_update);
        if (hasUpdate) {
          updates++;
        } else {
          latest++;
        }
      } else {
        failed++;
      }
    }
    Alert.alert(
      t('common.success'),
      t('common.updateSummary', {updates: updates, latest: latest, failed: failed}),
    );
  }

  function badgeBg(type: string): string {
    const c = PLUGIN_TYPE_COLORS[type] || 'muted';
    if (c === 'primary') return colors.primary;
    if (c === 'success') return colors.success;
    if (c === 'warning') return colors.danger;
    return colors.textMuted;
  }

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
          <FluentTitle style={styles.flexTitle}>{t('settings.plugins')}</FluentTitle>
          <FluentButton
            label={checkingAll ? t('common.loading') : t('common.checkAll')}
            variant="ghost"
            disabled={checkingAll}
            onPress={handleCheckAllUpdates}
          />
          <FluentButton label={t("common.install")} variant="primary" onPress={() => setInstallModalOpen(true)} />
        </View>

        {pluginTypes.length > 0 && (
          <ScrollView
            horizontal
            showsHorizontalScrollIndicator={false}
            style={styles.chipScroll}
            contentContainerStyle={styles.chipContainer}>
            <TouchableOpacity
              accessibilityRole="button"
              onPress={() => setTypeFilter('')}
              style={[styles.chip, typeFilter === '' && styles.chipActive]}>
              <Text style={[styles.chipText, typeFilter === '' && styles.chipTextActive]}>
                {t('common.pluginTypeAll')}
              </Text>
            </TouchableOpacity>
            {pluginTypes.map(pt => (
              <TouchableOpacity
                key={pt}
                accessibilityRole="button"
                onPress={() => setTypeFilter(pt)}
                style={[styles.chip, typeFilter === pt && styles.chipActive]}>
                <Text style={[styles.chipText, typeFilter === pt && styles.chipTextActive]}>
                  {PLUGIN_TYPE_LABELS[pt] ? t(PLUGIN_TYPE_LABELS[pt] as any) : pt}
                </Text>
              </TouchableOpacity>
            ))}
          </ScrollView>
        )}

        {filteredPlugins.map(plugin => (
          <FluentCard key={plugin.id} style={styles.pluginCard}>
            <View style={styles.pluginHeader}>
              <View style={styles.pluginNameRow}>
                <Text style={styles.pluginName}>{plugin.name}</Text>
                <Text style={styles.pluginVersion}>{plugin.version}</Text>
              </View>
              <FluentSwitch
                value={plugin.enabled}
                onValueChange={() => handleToggle(plugin)}
              />
            </View>
            {plugin.description ? (
              <Text style={styles.descriptionText} numberOfLines={2}>
                {plugin.description}
              </Text>
            ) : null}
            <FluentCaption>{plugin.namespace}</FluentCaption>
            {plugin.update_url ? (
              <Text style={styles.urlText} numberOfLines={1}>{plugin.update_url}</Text>
            ) : null}
            <View style={styles.pluginMeta}>
              <View style={[styles.typeBadge, {backgroundColor: badgeBg(plugin.plugin_type)}]}>
                <Text style={styles.typeBadgeText}>{PLUGIN_TYPE_LABELS[plugin.plugin_type] ? t(PLUGIN_TYPE_LABELS[plugin.plugin_type] as any) : plugin.plugin_type}</Text>
              </View>
              <View style={[styles.badge, {backgroundColor: plugin.enabled ? colors.success : colors.textMuted}]}>
                <Text style={styles.badgeText}>{plugin.enabled ? t('common.enabled') : t('common.disabled')}</Text>
              </View>
              {plugin.author ? <Text style={styles.authorText}>{plugin.author}</Text> : null}
            </View>
            <View style={styles.pluginActions}>
              <FluentButton label={t("common.checkUpdate")} variant="ghost" onPress={() => handleCheckUpdate(plugin)} />
              <FluentButton label={t("common.update")} variant="ghost" onPress={() => handleUpdate(plugin)} />
              <FluentButton label={t("common.configure")} variant="ghost" onPress={() => handleConfigure(plugin)} />
              <TouchableOpacity
                accessibilityRole="button"
                onPress={() => confirmDelete(plugin)}
                style={styles.actionButton}>
                <Trash2 color={colors.danger} size={18} />
              </TouchableOpacity>
            </View>
          </FluentCard>
        ))}
      </ScrollView>

      <Modal animationType="fade" onRequestClose={() => setInstallModalOpen(false)} statusBarTranslucent transparent visible={installModalOpen}>
        <ModalBackdrop style={styles.modalBackdrop}>
          <View style={[styles.modalSheet, {paddingBottom: Math.max(insets.bottom, spacing.lg)}]}>
            <FluentTitle>{t('common.install')}</FluentTitle>
            <FluentTextField
              label={t("common.installUrl")}
              value={installUrl}
              onChangeText={setInstallUrl}
              autoCapitalize="none"
              autoCorrect={false}
              keyboardType="url"
            />
            <View style={styles.modalActions}>
              <FluentButton label={t('common.cancel')} variant="secondary" onPress={() => setInstallModalOpen(false)} style={styles.flexButton} />
              <FluentButton label={t("common.install")} variant="primary" onPress={handleInstall} style={styles.flexButton} />
            </View>
          </View>
        </ModalBackdrop>
      </Modal>

      <Modal animationType="fade" onRequestClose={() => setConfigModalOpen(false)} statusBarTranslucent transparent visible={configModalOpen}>
        <ModalBackdrop style={styles.modalBackdrop}>
          <View style={[styles.modalSheet, {paddingBottom: Math.max(insets.bottom, spacing.lg)}]}>
            <FluentTitle>{t('settings.pluginConfiguration')}</FluentTitle>
            {configLoading ? (
              <FluentSpinner label={t('common.loading')} />
            ) : configParameters.length > 0 ? (
              <ScrollView style={styles.configForm} showsVerticalScrollIndicator={false}>
                {configParameters.map((param, index) => {
                  const key = `param${index}`;
                  const value = configFormValues[key];
                  return (
                    <View key={key} style={styles.configField}>
                      <Text style={styles.configFieldLabel}>{param.desc}</Text>
                      {param.type === 'bool' ? (
                        <FluentSwitchRow
                          label=""
                          value={Boolean(value)}
                          onValueChange={v => handleConfigFieldChange(key, v)}
                        />
                      ) : param.type === 'int' ? (
                        <FluentTextField
                          value={String(value ?? '')}
                          onChangeText={v => handleConfigFieldChange(key, v.replace(/[^0-9-]/g, ''))}
                          keyboardType="numeric"
                        />
                      ) : param.type === 'array' ? (
                        <FluentTextField
                          value={Array.isArray(value) ? value.join(', ') : String(value ?? '')}
                          onChangeText={v => handleConfigFieldChange(key, v.split(',').map(s => s.trim()))}
                          placeholder="comma-separated values"
                        />
                      ) : (
                        <FluentTextField
                          value={String(value ?? '')}
                          onChangeText={v => handleConfigFieldChange(key, v)}
                        />
                      )}
                    </View>
                  );
                })}
              </ScrollView>
            ) : (
              <Text style={styles.configText}>{t('settings.noConfigurationRequired')}</Text>
            )}
            <View style={styles.modalActions}>
              <FluentButton label={t('common.cancel')} variant="secondary" onPress={() => setConfigModalOpen(false)} style={styles.flexButton} disabled={configSaving} />
              <FluentButton label={t('common.save')} variant="primary" onPress={handleSaveConfig} style={styles.flexButton} disabled={configSaving || configParameters.length === 0} />
            </View>
          </View>
        </ModalBackdrop>
      </Modal>
    </ScreenRoot>
  );
}

function createStyles(colors: ThemeColors) {
  return StyleSheet.create({
    content: {gap: spacing.md},
    header: {
      flexDirection: 'row',
      alignItems: 'center',
      gap: spacing.md,
    },
    flexTitle: {flex: 1},
    backButton: {padding: spacing.xs},
    chipScroll: {marginBottom: spacing.xs},
    chipContainer: {
      flexDirection: 'row',
      gap: spacing.sm,
      paddingVertical: spacing.xs,
    },
    chip: {
      borderColor: colors.borderStrong,
      borderRadius: 16,
      borderWidth: StyleSheet.hairlineWidth,
      paddingHorizontal: spacing.md,
      paddingVertical: spacing.sm,
    },
    chipActive: {
      backgroundColor: colors.primary,
      borderColor: colors.primary,
    },
    chipText: {
      color: colors.text,
      fontSize: 13,
      fontWeight: '700',
    },
    chipTextActive: {
      color: colors.white,
    },
    pluginCard: {gap: spacing.sm},
    pluginHeader: {
      flexDirection: 'row',
      alignItems: 'center',
      justifyContent: 'space-between',
    },
    pluginNameRow: {
      flexDirection: 'row',
      alignItems: 'baseline',
      gap: spacing.sm,
    },
    pluginName: {
      color: colors.text,
      fontSize: 15,
      fontWeight: '700',
    },
    pluginVersion: {
      color: colors.textMuted,
      fontSize: 12,
    },
    descriptionText: {
      color: colors.textMuted,
      fontSize: 13,
      lineHeight: 18,
    },
    urlText: {
      color: colors.textMuted,
      fontSize: 11,
    },
    pluginMeta: {
      flexDirection: 'row',
      alignItems: 'center',
      gap: spacing.sm,
      flexWrap: 'wrap',
    },
    typeBadge: {
      borderRadius: radius.sm,
      paddingHorizontal: spacing.sm,
      paddingVertical: 2,
    },
    typeBadgeText: {
      color: colors.white,
      fontSize: 11,
      fontWeight: '700',
    },
    badge: {
      borderRadius: radius.sm,
      paddingHorizontal: spacing.sm,
      paddingVertical: 2,
    },
    badgeText: {
      color: colors.white,
      fontSize: 11,
      fontWeight: '700',
    },
    authorText: {
      color: colors.textMuted,
      fontSize: 12,
    },
    pluginActions: {
      flexDirection: 'row',
      alignItems: 'center',
      gap: spacing.sm,
      flexWrap: 'wrap',
    },
    configForm: {
      maxHeight: 300,
    },
    configField: {
      gap: spacing.xs,
      marginBottom: spacing.md,
    },
    configFieldLabel: {
      color: colors.text,
      fontSize: 14,
      fontWeight: '700',
    },
    configText: {
      color: colors.textMuted,
      fontSize: 14,
      lineHeight: 20,
      textAlign: 'center',
      paddingVertical: spacing.xl,
    },
    modalBackdrop: {justifyContent: 'flex-end'},
    modalSheet: {
      backgroundColor: colors.surface,
      borderTopLeftRadius: 14,
      borderTopRightRadius: 14,
      gap: spacing.md,
      maxHeight: '82%',
      padding: spacing.lg,
      width: '100%',
    },
    modalActions: {
      flexDirection: 'row',
      gap: spacing.sm,
    },
    flexButton: {flex: 1},
    actionButton: {
      width: 36,
      height: 36,
      borderRadius: 18,
      alignItems: 'center',
      justifyContent: 'center',
    },
  });
}
