import React, {useCallback, useEffect, useMemo, useState} from 'react';
import {Alert, Modal, RefreshControl, ScrollView, StyleSheet, Text, TextInput, TouchableOpacity, View} from 'react-native';
import {ArrowLeft, Edit3, Plus, RefreshCw, Scan, Search, Trash2} from 'lucide-react-native';
import {useSafeAreaInsets} from 'react-native-safe-area-context';
import {useNavigation} from '@react-navigation/native';
import {ScreenRoot, ModalBackdrop, screenSafeAreaPadding} from '../components/SafeAreaSurface';
import {FluentButton, FluentCard, FluentCaption, FluentSwitch, FluentTextField, FluentTitle, FluentSpinner} from '../components/fluent';
import {useI18n} from '../i18n';
import {buildAuthorizedAssetImageSource, extractApiError} from '../api/client';
import {createCategory, deleteCategory, scanCategory, scanMediaLibrary, updateCategory, adminListPlugins} from '../api/admin';
import type {Plugin} from '../api/admin';
import {fetchCategories} from '../api/lanlu';
import type {Category} from '../types/api';
import {spacing, radius, type ThemeColors} from '../theme/colors';
import {useTheme} from '../theme/ThemeContext';
import FastImage, {type Source as FastImageSource} from '@d11/react-native-fast-image';

const ICON_NAMES = ['Folder', 'Image', 'Book', 'Star', 'Heart', 'Clock', 'Music', 'Video', 'Globe', 'Tag'];

function getInitial(name: string): string {
  return name.trim().charAt(0).toUpperCase() || '?';
}

export function CategorySettingsScreen() {
  const {t} = useI18n();
  const {colors} = useTheme();
  const insets = useSafeAreaInsets();
  const navigation = useNavigation();
  const styles = useMemo(() => createStyles(colors), [colors]);

  const [categories, setCategories] = useState<Category[]>([]);
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [modalOpen, setModalOpen] = useState(false);
  const [editingCategory, setEditingCategory] = useState<Category | null>(null);
  const [formName, setFormName] = useState('');
  const [formDescription, setFormDescription] = useState('');
  const [formSortOrder, setFormSortOrder] = useState('');
  const [formEnabled, setFormEnabled] = useState(true);
  const [formScanPath, setFormScanPath] = useState('');
  const [saving, setSaving] = useState(false);

  const [searchQuery, setSearchQuery] = useState('');
  const [statusFilter, setStatusFilter] = useState<'all' | 'enabled' | 'disabled'>('all');
  const [coverSources, setCoverSources] = useState<Record<string, FastImageSource | null>>({});
  const [availablePlugins, setAvailablePlugins] = useState<Plugin[]>([]);
  const [selectedPlugins, setSelectedPlugins] = useState<string[]>([]);

  const load = useCallback(async () => {
    try {
      const data = await fetchCategories();
      setCategories(data);
    } catch (error) {
      Alert.alert(t('common.error'), extractApiError(error));
    }
  }, [t]);

  const loadPlugins = useCallback(async () => {
    try {
      const res = await adminListPlugins();
      const all = res.data?.plugins ?? [];
      setAvailablePlugins(all.filter(p => p.plugin_type === 'metadata'));
    } catch {
    }
  }, []);

  useEffect(() => {
    (async () => {
      setLoading(true);
      await Promise.all([load(), loadPlugins()]);
      setLoading(false);
    })();
  }, [load, loadPlugins]);

  useEffect(() => {
    (async () => {
      const sources: Record<string, FastImageSource | null> = {};
      for (const cat of categories) {
        if (cat.cover_asset_id) {
          sources[cat.catid] = await buildAuthorizedAssetImageSource(cat.cover_asset_id);
        }
      }
      setCoverSources(sources);
    })();
  }, [categories]);

  const filteredCategories = useMemo(() => {
    return categories.filter(cat => {
      const matchesSearch = !searchQuery || cat.name.toLowerCase().includes(searchQuery.toLowerCase());
      const matchesStatus = statusFilter === 'all'
        || (statusFilter === 'enabled' && cat.enabled !== false)
        || (statusFilter === 'disabled' && cat.enabled === false);
      return matchesSearch && matchesStatus;
    });
  }, [categories, searchQuery, statusFilter]);

  const onRefresh = useCallback(async () => {
    setRefreshing(true);
    await load();
    setRefreshing(false);
  }, [load]);

  function openCreateModal() {
    setEditingCategory(null);
    setFormName('');
    setFormDescription('');
    setFormSortOrder('');
    setFormEnabled(true);
    setFormScanPath('');
    setSelectedPlugins([]);
    setModalOpen(true);
  }

  function openEditModal(cat: Category) {
    setEditingCategory(cat);
    setFormName(cat.name);
    setFormDescription(cat.description ?? '');
    setFormSortOrder(cat.sort_order?.toString() ?? '');
    setFormEnabled(cat.enabled !== false);
    setFormScanPath('');
    setSelectedPlugins([]);
    setModalOpen(true);
  }

  function closeModal() {
    setModalOpen(false);
    setEditingCategory(null);
  }

  async function handleSave() {
    if (!formName.trim()) {
      Alert.alert(t('common.error'), 'Category name is required');
      return;
    }
    setSaving(true);
    try {
      const params: Record<string, unknown> = {
        name: formName.trim(),
        description: formDescription.trim() || undefined,
        sort_order: formSortOrder ? parseInt(formSortOrder, 10) : undefined,
        enabled: formEnabled,
        scan_path: formScanPath.trim() || undefined,
        plugins: selectedPlugins.length > 0 ? selectedPlugins : undefined,
      };
      if (editingCategory) {
        await updateCategory(editingCategory.catid, params);
      } else {
        await createCategory(params as any);
      }
      closeModal();
      await load();
    } catch (error) {
      Alert.alert(t('common.error'), extractApiError(error));
    } finally {
      setSaving(false);
    }
  }

  async function handleDelete(cat: Category) {
    Alert.alert(
      t('common.delete'),
      `Delete category "${cat.name}"?`,
      [
        {text: t('common.cancel'), style: 'cancel'},
        {
          text: t('common.delete'),
          style: 'destructive',
          onPress: async () => {
            try {
              await deleteCategory(cat.catid);
              await load();
            } catch (error) {
              Alert.alert(t('common.error'), extractApiError(error));
            }
          },
        },
      ],
    );
  }

  function togglePlugin(namespace: string) {
    setSelectedPlugins(prev =>
      prev.includes(namespace) ? prev.filter(p => p !== namespace) : [...prev, namespace],
    );
  }

  async function handleScan(cat: Category) {
    try {
      await scanCategory(cat.catid);
      Alert.alert(t('common.success'), t('common.scan'));
    } catch (error) {
      Alert.alert(t('common.error'), extractApiError(error));
    }
  }

  async function handleScanAll() {
    try {
      await scanMediaLibrary();
      Alert.alert(t('common.success'), t('common.scan'));
    } catch (error) {
      Alert.alert(t('common.error'), extractApiError(error));
    }
  }

  if (loading) {
    return (
      <ScreenRoot padded={false}>
        <FluentSpinner label={t('common.loading')} />
      </ScreenRoot>
    );
  }

  return (
    <ScreenRoot padded={false}>
      <ScrollView
        contentContainerStyle={[styles.content, screenSafeAreaPadding(insets)]}
        showsVerticalScrollIndicator={false}
        refreshControl={
          <RefreshControl
            colors={[colors.primary]}
            onRefresh={onRefresh}
            refreshing={refreshing}
            tintColor={colors.primary}
          />
        }>
        <View style={styles.header}>
          <TouchableOpacity
            accessibilityRole="button"
            onPress={() => navigation.goBack()}
            style={styles.backButton}>
            <ArrowLeft color={colors.text} size={24} />
          </TouchableOpacity>
          <FluentTitle style={styles.headerTitle}>{t('settings.categories')}</FluentTitle>
          <TouchableOpacity
            accessibilityRole="button"
            onPress={handleScanAll}
            style={styles.headerAction}>
            <RefreshCw color={colors.primary} size={20} />
          </TouchableOpacity>
          <TouchableOpacity
            accessibilityRole="button"
            onPress={openCreateModal}
            style={styles.headerAction}>
            <Plus color={colors.primary} size={24} />
          </TouchableOpacity>
        </View>

        <View style={styles.searchContainer}>
          <Search color={colors.textMuted} size={18} />
          <TextInput
            placeholder={t('common.searchPlaceholder')}
            placeholderTextColor={colors.textMuted}
            style={styles.searchInput}
            value={searchQuery}
            onChangeText={setSearchQuery}
          />
        </View>

        <View style={styles.filterRow}>
          {(['all', 'enabled', 'disabled'] as const).map(status => (
            <TouchableOpacity
              key={status}
              accessibilityRole="button"
              onPress={() => setStatusFilter(status)}
              style={[
                styles.filterChip,
                statusFilter === status && styles.filterChipActive,
              ]}>
              <Text
                style={[
                  styles.filterChipText,
                  statusFilter === status && styles.filterChipTextActive,
                ]}>
                {status === 'all' ? t('common.all') : status === 'enabled' ? t('common.enabled') : t('common.disabled')}
              </Text>
            </TouchableOpacity>
          ))}
        </View>

        {filteredCategories.map(cat => (
          <FluentCard key={cat.catid} style={styles.card}>
            <TouchableOpacity
              activeOpacity={0.78}
              onPress={() => openEditModal(cat)}
              style={styles.cardContent}>
              <View style={styles.cardRow}>
                {cat.cover_asset_id && coverSources[cat.catid] ? (
                  <FastImage
                    source={coverSources[cat.catid]!}
                    style={styles.coverImage}
                  />
                ) : (
                  <View style={styles.coverPlaceholder}>
                    <Text style={styles.coverPlaceholderText}>{getInitial(cat.name)}</Text>
                  </View>
                )}
                <View style={styles.cardInfo}>
                  <View style={styles.cardHeader}>
                    <Text style={styles.cardTitle}>{cat.name}</Text>
                    <View style={[styles.badge, cat.enabled !== false ? styles.badgeEnabled : styles.badgeDisabled]}>
                      <Text style={[styles.badgeText, cat.enabled !== false ? styles.badgeTextEnabled : styles.badgeTextDisabled]}>
                        {cat.enabled !== false ? t('common.enabled') : t('common.disabled')}
                      </Text>
                    </View>
                  </View>
                  {cat.description ? (
                    <FluentCaption>{cat.description}</FluentCaption>
                  ) : null}
                  <Text style={styles.archiveCount}>
                    {cat.archive_count != null ? t('common.archiveCount', {count: cat.archive_count}) : t('common.archiveCount', {count: 0})}
                  </Text>
                </View>
              </View>
            </TouchableOpacity>
            <View style={styles.cardActions}>
              <TouchableOpacity
                accessibilityRole="button"
                onPress={() => openEditModal(cat)}
                style={styles.actionButton}>
                <Edit3 color={colors.textMuted} size={18} />
              </TouchableOpacity>
              <TouchableOpacity
                accessibilityRole="button"
                onPress={() => handleScan(cat)}
                style={styles.actionButton}>
                <Scan color={colors.textMuted} size={18} />
              </TouchableOpacity>
              <TouchableOpacity
                accessibilityRole="button"
                onPress={() => handleDelete(cat)}
                style={styles.actionButton}>
                <Trash2 color={colors.danger} size={18} />
              </TouchableOpacity>
            </View>
          </FluentCard>
        ))}
      </ScrollView>

      <Modal
        animationType="fade"
        onRequestClose={closeModal}
        statusBarTranslucent
        transparent
        visible={modalOpen}>
        <ModalBackdrop style={styles.modalBackdrop}>
          <View style={[styles.modalSheet, {paddingBottom: Math.max(insets.bottom, spacing.lg)}]}>
            <ScrollView showsVerticalScrollIndicator={false}>
              <FluentTitle>
                {editingCategory ? t('common.edit') : t('common.add')}
              </FluentTitle>
              <FluentTextField
                label={t('common.name')}
                onChangeText={setFormName}
                value={formName}
              />
              <FluentTextField
                label={t('common.description')}
                onChangeText={setFormDescription}
                value={formDescription}
                multiline
              />
              <FluentTextField
                keyboardType="numeric"
                label={t('common.sortOrder')}
                onChangeText={setFormSortOrder}
                value={formSortOrder}
              />
              <FluentTextField
                label={t('common.scanPath')}
                onChangeText={setFormScanPath}
                value={formScanPath}
              />
              {availablePlugins.length > 0 && (
                <View style={styles.pluginsSection}>
                  <Text style={styles.pluginsTitle}>{t('common.plugins')}</Text>
                  {availablePlugins.map(plugin => (
                    <TouchableOpacity
                      key={plugin.namespace}
                      accessibilityRole="button"
                      onPress={() => togglePlugin(plugin.namespace)}
                      style={styles.pluginRow}>
                      <View
                        style={[
                          styles.checkbox,
                          selectedPlugins.includes(plugin.namespace) && styles.checkboxActive,
                        ]}>
                        {selectedPlugins.includes(plugin.namespace) && (
                          <Text style={styles.checkmark}>✓</Text>
                        )}
                      </View>
                      <Text style={styles.pluginLabel}>{plugin.name}</Text>
                    </TouchableOpacity>
                  ))}
                </View>
              )}
              <View style={styles.switchRow}>
                <Text style={styles.switchLabel}>{t('common.enabled')}</Text>
                <FluentSwitch
                  onValueChange={setFormEnabled}
                  value={formEnabled}
                />
              </View>
              <View style={styles.modalActions}>
                <FluentButton
                  label={t('common.cancel')}
                  onPress={closeModal}
                  variant="secondary"
                  style={styles.modalActionButton}
                />
                <FluentButton
                  disabled={saving}
                  label={editingCategory ? t('common.save') : t('common.create')}
                  onPress={handleSave}
                  variant="primary"
                  style={styles.modalActionButton}
                />
              </View>
            </ScrollView>
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
    headerTitle: {flex: 1},
    backButton: {padding: spacing.xs},
    headerAction: {padding: spacing.xs},
    searchContainer: {
      flexDirection: 'row',
      alignItems: 'center',
      backgroundColor: colors.surfaceMuted,
      borderRadius: radius.md,
      paddingHorizontal: spacing.md,
      height: 40,
      gap: spacing.sm,
    },
    searchInput: {
      flex: 1,
      color: colors.text,
      fontSize: 15,
      paddingVertical: 0,
    },
    filterRow: {
      flexDirection: 'row',
      gap: spacing.sm,
    },
    filterChip: {
      paddingHorizontal: spacing.md,
      paddingVertical: spacing.xs,
      borderRadius: 20,
      backgroundColor: colors.surfaceMuted,
    },
    filterChipActive: {
      backgroundColor: colors.primary,
    },
    filterChipText: {
      fontSize: 13,
      fontWeight: '600',
      color: colors.textMuted,
    },
    filterChipTextActive: {
      color: '#fff',
    },
    card: {padding: spacing.md, gap: spacing.sm},
    cardContent: {gap: spacing.xs},
    cardRow: {
      flexDirection: 'row',
      gap: spacing.md,
    },
    coverImage: {
      width: 56,
      height: 56,
      borderRadius: radius.md,
    },
    coverPlaceholder: {
      width: 56,
      height: 56,
      borderRadius: radius.md,
      backgroundColor: colors.primary + '30',
      alignItems: 'center',
      justifyContent: 'center',
    },
    coverPlaceholderText: {
      fontSize: 22,
      fontWeight: '800',
      color: colors.primary,
    },
    cardInfo: {
      flex: 1,
      gap: spacing.xs,
    },
    cardHeader: {
      flexDirection: 'row',
      alignItems: 'center',
      gap: spacing.sm,
    },
    cardTitle: {
      color: colors.text,
      flex: 1,
      fontSize: 17,
      fontWeight: '800',
    },
    badge: {
      borderRadius: radius.sm,
      paddingHorizontal: spacing.sm,
      paddingVertical: 2,
    },
    badgeEnabled: {
      backgroundColor: colors.success + '20',
    },
    badgeDisabled: {
      backgroundColor: colors.danger + '20',
    },
    badgeText: {
      fontSize: 12,
      fontWeight: '700',
    },
    badgeTextEnabled: {
      color: colors.success,
    },
    badgeTextDisabled: {
      color: colors.danger,
    },
    archiveCount: {
      color: colors.textMuted,
      fontSize: 13,
    },
    cardActions: {
      flexDirection: 'row',
      gap: spacing.sm,
      justifyContent: 'flex-end',
    },
    actionButton: {
      alignItems: 'center',
      backgroundColor: colors.surfaceMuted,
      borderRadius: 20,
      height: 36,
      justifyContent: 'center',
      width: 36,
    },
    pluginsSection: {
      gap: spacing.xs,
    },
    pluginsTitle: {
      color: colors.text,
      fontSize: 15,
      fontWeight: '700',
      marginBottom: spacing.xs,
    },
    pluginRow: {
      flexDirection: 'row',
      alignItems: 'center',
      gap: spacing.sm,
      paddingVertical: spacing.xs,
    },
    checkbox: {
      width: 22,
      height: 22,
      borderRadius: 4,
      borderWidth: 2,
      borderColor: colors.borderStrong,
      alignItems: 'center',
      justifyContent: 'center',
    },
    checkboxActive: {
      backgroundColor: colors.primary,
      borderColor: colors.primary,
    },
    checkmark: {
      color: '#fff',
      fontSize: 14,
      fontWeight: '700',
    },
    pluginLabel: {
      color: colors.text,
      fontSize: 14,
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
    switchRow: {
      alignItems: 'center',
      flexDirection: 'row',
      minHeight: 44,
    },
    switchLabel: {
      color: colors.text,
      flex: 1,
      fontSize: 15,
      fontWeight: '700',
    },
    modalActions: {
      flexDirection: 'row',
      gap: spacing.sm,
      justifyContent: 'flex-end',
    },
    modalActionButton: {
      flex: 1,
    },
  });
}
