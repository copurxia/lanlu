import React, {useCallback, useEffect, useMemo, useState} from 'react';
import {Alert, Modal, RefreshControl, ScrollView, StyleSheet, Text, TouchableOpacity, View} from 'react-native';
import {useSafeAreaInsets} from 'react-native-safe-area-context';
import {useNavigation} from '@react-navigation/native';
import {ScreenRoot, ModalBackdrop, screenSafeAreaPadding} from '../components/SafeAreaSurface';
import {FluentButton, FluentCard, FluentCaption, FluentSwitch, FluentTextField, FluentTitle, FluentSpinner} from '../components/fluent';
import {useI18n} from '../i18n';
import {extractApiError} from '../api/client';
import {
  adminListSmartFilters,
  adminCreateSmartFilter,
  adminUpdateSmartFilter,
  adminDeleteSmartFilter,
  adminToggleSmartFilter,
  adminReorderSmartFilters,
} from '../api/admin';
import type {SmartFilterItem} from '../api/admin';
import {spacing, radius, type ThemeColors} from '../theme/colors';
import {useTheme} from '../theme/ThemeContext';
import * as Icons from 'lucide-react-native';

const ICON_LIST = ['Filter', 'Search', 'Star', 'Heart', 'Clock', 'Calendar', 'Bookmark', 'Flag', 'Tag', 'FolderOpen', 'LayoutGrid', 'List', 'Grid3x3', 'Image', 'FileText', 'Music', 'Video', 'Globe', 'Shield', 'KeyRound'];

const SORT_BY_OPTIONS = ['date_added', 'release_at', 'updated_at', 'lastread', 'title', 'pagecount'];

export function SmartFilterSettingsScreen() {
  const {t} = useI18n();
  const {colors} = useTheme();
  const insets = useSafeAreaInsets();
  const navigation = useNavigation();
  const styles = useMemo(() => createStyles(colors), [colors]);

  const [filters, setFilters] = useState<SmartFilterItem[]>([]);
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [modalOpen, setModalOpen] = useState(false);
  const [editingFilter, setEditingFilter] = useState<SmartFilterItem | null>(null);
  const [formName, setFormName] = useState('');
  const [formCNName, setFormCNName] = useState('');
  const [formENName, setFormENName] = useState('');
  const [formIcon, setFormIcon] = useState('');
  const [formQuery, setFormQuery] = useState('');
  const [formSortBy, setFormSortBy] = useState('');
  const [formSortOrder, setFormSortOrder] = useState('');
  const [formDateFrom, setFormDateFrom] = useState('');
  const [formDateTo, setFormDateTo] = useState('');
  const [formNewOnly, setFormNewOnly] = useState(false);
  const [formUntaggedOnly, setFormUntaggedOnly] = useState(false);
  const [formEnabled, setFormEnabled] = useState(true);
  const [saving, setSaving] = useState(false);

  const load = useCallback(async () => {
    try {
      const res = await adminListSmartFilters();
      setFilters(res.data?.items ?? []);
    } catch (error) {
      Alert.alert(t('common.error'), extractApiError(error));
    }
  }, [t]);

  useEffect(() => {
    (async () => {
      setLoading(true);
      await load();
      setLoading(false);
    })();
  }, [load]);

  const onRefresh = useCallback(async () => {
    setRefreshing(true);
    await load();
    setRefreshing(false);
  }, [load]);

  function openCreateModal() {
    setEditingFilter(null);
    setFormName('');
    setFormCNName('');
    setFormENName('');
    setFormIcon('');
    setFormQuery('');
    setFormSortBy('');
    setFormSortOrder('');
    setFormDateFrom('');
    setFormDateTo('');
    setFormNewOnly(false);
    setFormUntaggedOnly(false);
    setFormEnabled(true);
    setModalOpen(true);
  }

  function openEditModal(filter: SmartFilterItem) {
    setEditingFilter(filter);
    setFormName(filter.name ?? '');
    setFormCNName(filter.translations?.zh?.text ?? '');
    setFormENName(filter.translations?.en?.text ?? '');
    setFormIcon(filter.icon ?? '');
    setFormQuery(filter.query ?? '');
    setFormSortBy(filter.sort_by ?? '');
    setFormSortOrder(filter.sort_order ?? '');
    setFormDateFrom(filter.date_from ?? '');
    setFormDateTo(filter.date_to ?? '');
    setFormNewOnly(filter.newonly ?? false);
    setFormUntaggedOnly(filter.untaggedonly ?? false);
    setFormEnabled(filter.enabled !== false);
    setModalOpen(true);
  }

  function closeModal() {
    setModalOpen(false);
    setEditingFilter(null);
  }

  async function handleSave() {
    if (!formName.trim()) {
      Alert.alert(t('common.error'), 'Filter name is required');
      return;
    }
    setSaving(true);
    try {
      const translations: Record<string, {text?: string}> = {};
      if (formCNName.trim()) translations.zh = {text: formCNName.trim()};
      if (formENName.trim()) translations.en = {text: formENName.trim()};

      const params: Partial<SmartFilterItem> = {
        name: formName.trim(),
        icon: formIcon.trim() || undefined,
        query: formQuery.trim() || undefined,
        sort_by: formSortBy.trim() || undefined,
        sort_order: formSortOrder.trim() || undefined,
        date_from: formDateFrom.trim() || undefined,
        date_to: formDateTo.trim() || undefined,
        newonly: formNewOnly || undefined,
        untaggedonly: formUntaggedOnly || undefined,
        enabled: formEnabled,
        ...(Object.keys(translations).length > 0 ? {translations} : {}),
      };
      if (editingFilter) {
        await adminUpdateSmartFilter(editingFilter.id, params);
      } else {
        await adminCreateSmartFilter(params);
      }
      closeModal();
      await load();
    } catch (error) {
      Alert.alert(t('common.error'), extractApiError(error));
    } finally {
      setSaving(false);
    }
  }

  async function handleDelete(filter: SmartFilterItem) {
    Alert.alert(
      t('common.delete'),
      `Delete filter "${filter.name}"?`,
      [
        {text: t('common.cancel'), style: 'cancel'},
        {
          text: t('common.delete'),
          style: 'destructive',
          onPress: async () => {
            try {
              await adminDeleteSmartFilter(filter.id);
              await load();
            } catch (error) {
              Alert.alert(t('common.error'), extractApiError(error));
            }
          },
        },
      ],
    );
  }

  async function handleToggle(filter: SmartFilterItem) {
    try {
      await adminToggleSmartFilter(filter.id);
      await load();
    } catch (error) {
      Alert.alert(t('common.error'), extractApiError(error));
    }
  }

  async function handleMoveUp(filter: SmartFilterItem, index: number) {
    if (index <= 0) return;
    const sorted = [...filters].sort((a, b) => (a.sort_order_num ?? 0) - (b.sort_order_num ?? 0));
    const prev = sorted[index - 1];
    if (!prev) return;
    try {
      const aNum = filter.sort_order_num ?? index;
      const bNum = prev.sort_order_num ?? index - 1;
      await adminReorderSmartFilters([
        {id: filter.id, sort_order_num: bNum},
        {id: prev.id, sort_order_num: aNum},
      ]);
      await load();
    } catch (error) {
      Alert.alert(t('common.error'), extractApiError(error));
    }
  }

  async function handleMoveDown(filter: SmartFilterItem, index: number) {
    const sorted = [...filters].sort((a, b) => (a.sort_order_num ?? 0) - (b.sort_order_num ?? 0));
    if (index >= sorted.length - 1) return;
    const next = sorted[index + 1];
    if (!next) return;
    try {
      const aNum = filter.sort_order_num ?? index;
      const bNum = next.sort_order_num ?? index + 1;
      await adminReorderSmartFilters([
        {id: filter.id, sort_order_num: bNum},
        {id: next.id, sort_order_num: aNum},
      ]);
      await load();
    } catch (error) {
      Alert.alert(t('common.error'), extractApiError(error));
    }
  }

  function renderIcon(iconName: string | undefined, size: number, color: string) {
    if (!iconName) return null;
    const IconComp = (Icons as any)[iconName];
    if (!IconComp) return null;
    return <IconComp size={size} color={color} />;
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
            <Icons.ArrowLeft color={colors.text} size={24} />
          </TouchableOpacity>
          <FluentTitle style={styles.headerTitle}>{t('settings.smartFilters')}</FluentTitle>
          <TouchableOpacity
            accessibilityRole="button"
            onPress={openCreateModal}
            style={styles.headerAction}>
            <Icons.Plus color={colors.primary} size={24} />
          </TouchableOpacity>
        </View>

        {filters.map((filter, index) => {
          const sorted = [...filters].sort((a, b) => (a.sort_order_num ?? 0) - (b.sort_order_num ?? 0));
          const sortedIndex = sorted.findIndex(f => f.id === filter.id);
          return (
            <FluentCard key={filter.id} style={styles.card}>
              <View style={styles.cardRow}>
                <View style={styles.moveButtons}>
                  <TouchableOpacity
                    accessibilityRole="button"
                    disabled={sortedIndex <= 0}
                    onPress={() => handleMoveUp(filter, sortedIndex)}
                    style={[styles.moveButton, sortedIndex <= 0 && styles.moveButtonDisabled]}>
                    <Icons.ChevronUp color={sortedIndex <= 0 ? colors.textMuted : colors.text} size={16} />
                  </TouchableOpacity>
                  <TouchableOpacity
                    accessibilityRole="button"
                    disabled={sortedIndex >= sorted.length - 1}
                    onPress={() => handleMoveDown(filter, sortedIndex)}
                    style={[styles.moveButton, sortedIndex >= sorted.length - 1 && styles.moveButtonDisabled]}>
                    <Icons.ChevronDown color={sortedIndex >= sorted.length - 1 ? colors.textMuted : colors.text} size={16} />
                  </TouchableOpacity>
                </View>
                <TouchableOpacity
                  activeOpacity={0.78}
                  onPress={() => openEditModal(filter)}
                  style={styles.cardContent}>
                  <View style={styles.cardHeader}>
                    {renderIcon(filter.icon, 20, colors.text)}
                    <Text style={styles.cardTitle}>{filter.name}</Text>
                    <View style={[styles.badge, filter.enabled !== false ? styles.badgeEnabled : styles.badgeDisabled]}>
                      <Text style={[styles.badgeText, filter.enabled !== false ? styles.badgeTextEnabled : styles.badgeTextDisabled]}>
                        {filter.enabled !== false ? t('common.enabled') : t('common.disabled')}
                      </Text>
                    </View>
                  </View>
                  <View style={styles.inlineBadges}>
                    {filter.newonly && (
                      <View style={[styles.inlineBadge, {backgroundColor: colors.primary + '20'}]}>
                        <Text style={[styles.inlineBadgeText, {color: colors.primary}]}>newOnly</Text>
                      </View>
                    )}
                    {filter.untaggedonly && (
                      <View style={[styles.inlineBadge, {backgroundColor: colors.danger + '20'}]}>
                        <Text style={[styles.inlineBadgeText, {color: colors.danger}]}>untaggedOnly</Text>
                      </View>
                    )}
                  </View>
                  <View style={styles.metaRow}>
                    {filter.query ? <FluentCaption>Q: {filter.query}</FluentCaption> : null}
                    {filter.sort_by ? <FluentCaption>Sort: {filter.sort_by}</FluentCaption> : null}
                  </View>
                  {(filter.date_from || filter.date_to) && (
                    <FluentCaption>
                      {filter.date_from ?? '…'} ~ {filter.date_to ?? '…'}
                    </FluentCaption>
                  )}
                </TouchableOpacity>
              </View>
              <View style={styles.cardActions}>
                <TouchableOpacity
                  accessibilityRole="button"
                  onPress={() => openEditModal(filter)}
                  style={styles.actionButton}>
                  <Icons.Edit3 color={colors.textMuted} size={18} />
                </TouchableOpacity>
                <FluentSwitch
                  onValueChange={() => handleToggle(filter)}
                  value={filter.enabled !== false}
                />
                <TouchableOpacity
                  accessibilityRole="button"
                  onPress={() => handleDelete(filter)}
                  style={styles.actionButton}>
                  <Icons.Trash2 color={colors.danger} size={18} />
                </TouchableOpacity>
              </View>
            </FluentCard>
          );
        })}
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
                {editingFilter ? t('common.edit') : t('common.add')}
              </FluentTitle>
              <FluentTextField
                label={t('common.name')}
                onChangeText={setFormName}
                value={formName}
              />
              <FluentTextField
                label={t('common.displayName') + ' (CN)'}
                onChangeText={setFormCNName}
                value={formCNName}
              />
              <FluentTextField
                label={t('common.displayName') + ' (EN)'}
                onChangeText={setFormENName}
                value={formENName}
              />
              <Text style={styles.fieldLabel}>Icon</Text>
              <ScrollView horizontal showsHorizontalScrollIndicator={false} style={styles.iconPickerRow}>
                {ICON_LIST.map(iconName => {
                  const selected = formIcon === iconName;
                  const IconComp = (Icons as any)[iconName];
                  return (
                    <TouchableOpacity
                      key={iconName}
                      accessibilityRole="button"
                      onPress={() => setFormIcon(selected ? '' : iconName)}
                      style={[
                        styles.iconOption,
                        selected && {backgroundColor: colors.primary, borderColor: colors.primary},
                      ]}>
                      {IconComp ? (
                        <IconComp size={22} color={selected ? '#fff' : colors.text} />
                      ) : (
                        <Text style={{color: colors.textMuted, fontSize: 10}}>?</Text>
                      )}
                    </TouchableOpacity>
                  );
                })}
              </ScrollView>
              <FluentTextField
                label={t('common.query')}
                onChangeText={setFormQuery}
                value={formQuery}
                multiline
              />
              <Text style={styles.fieldLabel}>{t('common.sortBy')}</Text>
              <View style={styles.sortByRow}>
                {SORT_BY_OPTIONS.map(opt => (
                  <TouchableOpacity
                    key={opt}
                    accessibilityRole="button"
                    onPress={() => setFormSortBy(formSortBy === opt ? '' : opt)}
                    style={[
                      styles.sortByChip,
                      formSortBy === opt && styles.sortByChipActive,
                    ]}>
                    <Text
                      style={[
                        styles.sortByChipText,
                        formSortBy === opt && styles.sortByChipTextActive,
                      ]}>
                      {opt.replace(/_/g, ' ')}
                    </Text>
                  </TouchableOpacity>
                ))}
              </View>
              <FluentTextField
                label={t('common.sortOrder')}
                onChangeText={setFormSortOrder}
                value={formSortOrder}
              />
              <FluentTextField
                label={t('common.dateFrom')}
                onChangeText={setFormDateFrom}
                value={formDateFrom}
              />
              <FluentTextField
                label={t('common.dateTo')}
                onChangeText={setFormDateTo}
                value={formDateTo}
              />
              <View style={styles.switchRow}>
                <Text style={styles.switchLabel}>{'New only'}</Text>
              <FluentSwitch
                onValueChange={setFormNewOnly}
                value={formNewOnly}
              />
              </View>
              <View style={styles.switchRow}>
                <Text style={styles.switchLabel}>{'Untagged only'}</Text>
                <FluentSwitch
                  onValueChange={setFormUntaggedOnly}
                  value={formUntaggedOnly}
                />
              </View>
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
                  label={editingFilter ? t('common.save') : t('common.create')}
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
    card: {padding: spacing.md, gap: spacing.sm},
    cardRow: {
      flexDirection: 'row',
      gap: spacing.sm,
    },
    moveButtons: {
      gap: 2,
      justifyContent: 'center',
    },
    moveButton: {
      alignItems: 'center',
      justifyContent: 'center',
      width: 28,
      height: 24,
      borderRadius: radius.sm,
    },
    moveButtonDisabled: {
      opacity: 0.4,
    },
    cardContent: {flex: 1, gap: spacing.xs},
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
    inlineBadges: {
      flexDirection: 'row',
      gap: spacing.xs,
    },
    inlineBadge: {
      borderRadius: radius.sm,
      paddingHorizontal: spacing.sm,
      paddingVertical: 1,
    },
    inlineBadgeText: {
      fontSize: 11,
      fontWeight: '700',
    },
    metaRow: {
      flexDirection: 'row',
      gap: spacing.sm,
      flexWrap: 'wrap',
    },
    cardActions: {
      flexDirection: 'row',
      alignItems: 'center',
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
    fieldLabel: {
      color: colors.text,
      fontSize: 15,
      fontWeight: '700',
    },
    iconPickerRow: {
      maxHeight: 52,
    },
    iconOption: {
      width: 44,
      height: 44,
      borderRadius: radius.md,
      borderWidth: 2,
      borderColor: colors.borderStrong,
      alignItems: 'center',
      justifyContent: 'center',
      marginRight: spacing.sm,
    },
    sortByRow: {
      flexDirection: 'row',
      flexWrap: 'wrap',
      gap: spacing.xs,
    },
    sortByChip: {
      paddingHorizontal: spacing.sm,
      paddingVertical: spacing.xs,
      borderRadius: radius.sm,
      backgroundColor: colors.surfaceMuted,
      borderWidth: 1,
      borderColor: colors.borderStrong,
    },
    sortByChipActive: {
      backgroundColor: colors.primary,
      borderColor: colors.primary,
    },
    sortByChipText: {
      fontSize: 12,
      fontWeight: '600',
      color: colors.textMuted,
    },
    sortByChipTextActive: {
      color: '#fff',
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
      paddingTop: spacing.sm,
    },
    modalActionButton: {
      flex: 1,
    },
  });
}
