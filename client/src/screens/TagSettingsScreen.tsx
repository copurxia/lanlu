import React, {useCallback, useEffect, useMemo, useState} from 'react';
import {Alert, Modal, RefreshControl, ScrollView, StyleSheet, Text, TextInput, TouchableOpacity, View} from 'react-native';
import {ArrowLeft, Edit3, Plus, Trash2} from 'lucide-react-native';
import {useSafeAreaInsets} from 'react-native-safe-area-context';
import {useNavigation} from '@react-navigation/native';
import {ScreenRoot, ModalBackdrop, screenSafeAreaPadding} from '../components/SafeAreaSurface';
import {FluentButton, FluentCard, FluentCaption, FluentTextField, FluentTitle, FluentSpinner} from '../components/fluent';
import {useI18n} from '../i18n';
import {extractApiError} from '../api/client';
import {adminListTags, adminCreateTag, adminUpdateTag, adminDeleteTag, listTagNamespaces} from '../api/admin';
import type {AdminTag} from '../api/admin';
import {spacing, radius, type ThemeColors} from '../theme/colors';
import {useTheme} from '../theme/ThemeContext';

const PAGE_SIZE = 20;

export function TagSettingsScreen() {
  const {t} = useI18n();
  const {colors} = useTheme();
  const insets = useSafeAreaInsets();
  const navigation = useNavigation();
  const styles = useMemo(() => createStyles(colors), [colors]);

  const [tags, setTags] = useState<AdminTag[]>([]);
  const [namespaces, setNamespaces] = useState<string[]>([]);
  const [selectedNamespace, setSelectedNamespace] = useState<string | undefined>(undefined);
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [modalOpen, setModalOpen] = useState(false);
  const [editingTag, setEditingTag] = useState<AdminTag | null>(null);
  const [formNamespace, setFormNamespace] = useState('');
  const [formName, setFormName] = useState('');
  const [saving, setSaving] = useState(false);

  const [searchQuery, setSearchQuery] = useState('');
  const [page, setPage] = useState(1);
  const [totalPages, setTotalPages] = useState(1);
  const [activeLangTab, setActiveLangTab] = useState<'zh' | 'en'>('zh');
  const [formZhText, setFormZhText] = useState('');
  const [formZhIntro, setFormZhIntro] = useState('');
  const [formEnText, setFormEnText] = useState('');
  const [formEnIntro, setFormEnIntro] = useState('');

  const load = useCallback(async () => {
    try {
      const offset = (page - 1) * PAGE_SIZE;
      const [tagRes, nsRes] = await Promise.all([
        adminListTags({q: searchQuery || undefined, limit: PAGE_SIZE, offset, namespace: selectedNamespace}),
        listTagNamespaces(),
      ]);
      setTags(tagRes.data?.items ?? []);
      const total = tagRes.data?.total ?? 0;
      setTotalPages(Math.max(1, Math.ceil(total / PAGE_SIZE)));
      setNamespaces(nsRes.data?.namespaces ?? []);
    } catch (error) {
      Alert.alert(t('common.error'), extractApiError(error));
    }
  }, [selectedNamespace, searchQuery, page, t]);

  useEffect(() => {
    (async () => {
      setLoading(true);
      await load();
      setLoading(false);
    })();
  }, [load]);

  const onRefresh = useCallback(async () => {
    setRefreshing(true);
    setPage(1);
    await load();
    setRefreshing(false);
  }, [load]);

  function resetPagination() {
    setPage(1);
  }

  function openCreateModal() {
    setEditingTag(null);
    setFormNamespace(selectedNamespace ?? '');
    setFormName('');
    setFormZhText('');
    setFormZhIntro('');
    setFormEnText('');
    setFormEnIntro('');
    setActiveLangTab('zh');
    setModalOpen(true);
  }

  function openEditModal(tag: AdminTag) {
    setEditingTag(tag);
    setFormNamespace(tag.namespace);
    setFormName(tag.name);
    setFormZhText(tag.translations?.zh?.text ?? '');
    setFormZhIntro(tag.translations?.zh?.intro ?? '');
    setFormEnText(tag.translations?.en?.text ?? '');
    setFormEnIntro(tag.translations?.en?.intro ?? '');
    setActiveLangTab('zh');
    setModalOpen(true);
  }

  function closeModal() {
    setModalOpen(false);
    setEditingTag(null);
  }

  async function handleSave() {
    if (!formName.trim()) {
      Alert.alert(t('common.error'), 'Tag name is required');
      return;
    }
    setSaving(true);
    try {
      const translations: Record<string, {text?: string; intro?: string}> = {};
      if (formZhText.trim() || formZhIntro.trim()) {
        translations.zh = {text: formZhText.trim() || undefined, intro: formZhIntro.trim() || undefined};
      }
      if (formEnText.trim() || formEnIntro.trim()) {
        translations.en = {text: formEnText.trim() || undefined, intro: formEnIntro.trim() || undefined};
      }
      const params: Parameters<typeof adminCreateTag>[0] & Partial<Parameters<typeof adminUpdateTag>[1]> = {
        namespace: formNamespace.trim() || undefined,
        name: formName.trim(),
        translations: Object.keys(translations).length > 0 ? translations : undefined,
      };
      if (editingTag) {
        await adminUpdateTag(editingTag.id, params);
      } else {
        await adminCreateTag(params);
      }
      closeModal();
      await load();
    } catch (error) {
      Alert.alert(t('common.error'), extractApiError(error));
    } finally {
      setSaving(false);
    }
  }

  async function handleDelete(tag: AdminTag) {
    Alert.alert(
      t('common.delete'),
      `Delete tag "${tag.name}"?`,
      [
        {text: t('common.cancel'), style: 'cancel'},
        {
          text: t('common.delete'),
          style: 'destructive',
          onPress: async () => {
            try {
              await adminDeleteTag(tag.id);
              await load();
            } catch (error) {
              Alert.alert(t('common.error'), extractApiError(error));
            }
          },
        },
      ],
    );
  }

  function handleSearchChange(text: string) {
    setSearchQuery(text);
    setPage(1);
  }

  function handleNamespaceChange(ns: string | undefined) {
    setSelectedNamespace(ns);
    setPage(1);
  }

  const translationsText = useCallback((tag: AdminTag) => {
    const zh = tag.translations?.zh?.text;
    const en = tag.translations?.en?.text;
    if (zh && en) return `${zh} / ${en}`;
    return zh || en || '';
  }, []);

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
        keyboardShouldPersistTaps="handled"
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
          <FluentTitle style={styles.headerTitle}>{t('settings.tags')}</FluentTitle>
          <TouchableOpacity
            accessibilityRole="button"
            onPress={openCreateModal}
            style={styles.headerAction}>
            <Plus color={colors.primary} size={24} />
          </TouchableOpacity>
        </View>

        <TextInput
          style={styles.searchInput}
          placeholder={t('common.searchPlaceholder')}
          placeholderTextColor={colors.textMuted}
          value={searchQuery}
          onChangeText={handleSearchChange}
          autoCapitalize="none"
          autoCorrect={false}
        />

        <ScrollView
          horizontal
          showsHorizontalScrollIndicator={false}
          style={styles.chipScroll}
          contentContainerStyle={styles.chipContainer}>
          <TouchableOpacity
            accessibilityRole="button"
            onPress={() => handleNamespaceChange(undefined)}
            style={[styles.chip, selectedNamespace === undefined && styles.chipActive]}>
            <Text style={[styles.chipText, selectedNamespace === undefined && styles.chipTextActive]}>
              {t('common.all')}
            </Text>
          </TouchableOpacity>
          {namespaces.map(ns => (
            <TouchableOpacity
              key={ns}
              accessibilityRole="button"
              onPress={() => handleNamespaceChange(ns)}
              style={[styles.chip, selectedNamespace === ns && styles.chipActive]}>
              <Text style={[styles.chipText, selectedNamespace === ns && styles.chipTextActive]}>
                {ns}
              </Text>
            </TouchableOpacity>
          ))}
        </ScrollView>

        {tags.map(tag => (
          <FluentCard key={tag.id} style={styles.card}>
            <TouchableOpacity
              activeOpacity={0.78}
              onPress={() => openEditModal(tag)}
              style={styles.cardContent}>
              <View style={styles.cardHeader}>
                {tag.namespace ? (
                  <View style={styles.namespaceBadge}>
                    <Text style={styles.namespaceBadgeText}>{tag.namespace}</Text>
                  </View>
                ) : null}
                <Text style={styles.cardTitle}>{tag.name}</Text>
              </View>
              {translationsText(tag) ? (
                <Text style={styles.translationText} numberOfLines={1}>
                  {translationsText(tag)}
                </Text>
              ) : null}
              {tag.created_at ? (
                <FluentCaption>{tag.created_at}</FluentCaption>
              ) : null}
            </TouchableOpacity>
            <View style={styles.cardActions}>
              <TouchableOpacity
                accessibilityRole="button"
                onPress={() => openEditModal(tag)}
                style={styles.actionButton}>
                <Edit3 color={colors.primary} size={18} />
              </TouchableOpacity>
              <TouchableOpacity
                accessibilityRole="button"
                onPress={() => handleDelete(tag)}
                style={styles.actionButton}>
                <Trash2 color={colors.danger} size={18} />
              </TouchableOpacity>
            </View>
          </FluentCard>
        ))}

        <View style={styles.pagination}>
          <TouchableOpacity
            accessibilityRole="button"
            disabled={page <= 1}
            onPress={() => setPage(p => Math.max(1, p - 1))}
            style={[styles.pageButton, page <= 1 && styles.pageButtonDisabled]}>
            <Text style={[styles.pageButtonText, page <= 1 && styles.pageButtonTextDisabled]}>
              Previous
            </Text>
          </TouchableOpacity>
          <Text style={styles.pageInfo}>
            Page {page} of {totalPages}
          </Text>
          <TouchableOpacity
            accessibilityRole="button"
            disabled={page >= totalPages}
            onPress={() => setPage(p => Math.min(totalPages, p + 1))}
            style={[styles.pageButton, page >= totalPages && styles.pageButtonDisabled]}>
            <Text style={[styles.pageButtonText, page >= totalPages && styles.pageButtonTextDisabled]}>
              Next
            </Text>
          </TouchableOpacity>
        </View>
      </ScrollView>

      <Modal
        animationType="fade"
        onRequestClose={closeModal}
        statusBarTranslucent
        transparent
        visible={modalOpen}>
        <ModalBackdrop style={styles.modalBackdrop}>
          <View style={[styles.modalSheet, {paddingBottom: Math.max(insets.bottom, spacing.lg)}]}>
            <FluentTitle>
              {editingTag ? t('common.edit') : t('common.add')}
            </FluentTitle>
            <FluentTextField
              label={t('settings.tags')}
              onChangeText={setFormNamespace}
              value={formNamespace}
            />
            <FluentTextField
              label={t('common.name')}
              onChangeText={setFormName}
              value={formName}
            />

            <View style={styles.langTabs}>
              <TouchableOpacity
                accessibilityRole="button"
                onPress={() => setActiveLangTab('zh')}
                style={[styles.langTab, activeLangTab === 'zh' && styles.langTabActive]}>
                <Text style={[styles.langTabText, activeLangTab === 'zh' && styles.langTabTextActive]}>
                  中文
                </Text>
              </TouchableOpacity>
              <TouchableOpacity
                accessibilityRole="button"
                onPress={() => setActiveLangTab('en')}
                style={[styles.langTab, activeLangTab === 'en' && styles.langTabActive]}>
                <Text style={[styles.langTabText, activeLangTab === 'en' && styles.langTabTextActive]}>
                  English
                </Text>
              </TouchableOpacity>
            </View>

            {activeLangTab === 'zh' ? (
              <>
                <FluentTextField
                  label={t('common.displayName') + ' (中文)'}
                  multiline
                />
                <FluentTextField
                  label={t('common.introduction') + ' (中文)'}
                  onChangeText={setFormZhIntro}
                  value={formZhIntro}
                  multiline
                  numberOfLines={3}
                  style={styles.textArea}
                />
              </>
            ) : (
              <>
                <FluentTextField
                  label={t('common.displayName') + ' (English)'}
                  multiline
                />
                <FluentTextField
                  label={t('common.introduction') + ' (English)'}
                  onChangeText={setFormEnIntro}
                  value={formEnIntro}
                  multiline
                  numberOfLines={3}
                  style={styles.textArea}
                />
              </>
            )}

            <View style={styles.modalActions}>
              <FluentButton
                label={t('common.cancel')}
                onPress={closeModal}
                variant="secondary"
                style={styles.modalActionButton}
              />
              <FluentButton
                disabled={saving}
                label={editingTag ? t('common.save') : t('common.create')}
                onPress={handleSave}
                variant="primary"
                style={styles.modalActionButton}
              />
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
    headerTitle: {flex: 1},
    backButton: {padding: spacing.xs},
    headerAction: {padding: spacing.xs},
    searchInput: {
      backgroundColor: colors.surfaceMuted,
      borderColor: colors.borderStrong,
      borderRadius: radius.md,
      borderWidth: StyleSheet.hairlineWidth,
      color: colors.text,
      fontSize: 15,
      paddingHorizontal: spacing.md,
      paddingVertical: spacing.sm,
    },
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
    card: {padding: spacing.md, gap: spacing.sm},
    cardContent: {gap: spacing.xs},
    cardHeader: {
      flexDirection: 'row',
      alignItems: 'center',
      gap: spacing.xs,
    },
    namespaceBadge: {
      backgroundColor: colors.primaryMuted,
      borderRadius: radius.sm,
      paddingHorizontal: spacing.sm,
      paddingVertical: 1,
    },
    namespaceBadgeText: {
      color: colors.primary,
      fontSize: 11,
      fontWeight: '700',
    },
    cardTitle: {
      color: colors.text,
      flex: 1,
      fontSize: 17,
      fontWeight: '800',
    },
    translationText: {
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
    pagination: {
      flexDirection: 'row',
      alignItems: 'center',
      justifyContent: 'center',
      gap: spacing.md,
      paddingVertical: spacing.md,
    },
    pageButton: {
      borderColor: colors.borderStrong,
      borderRadius: radius.md,
      borderWidth: StyleSheet.hairlineWidth,
      paddingHorizontal: spacing.md,
      paddingVertical: spacing.sm,
    },
    pageButtonDisabled: {
      opacity: 0.4,
    },
    pageButtonText: {
      color: colors.text,
      fontSize: 14,
      fontWeight: '600',
    },
    pageButtonTextDisabled: {
      color: colors.textMuted,
    },
    pageInfo: {
      color: colors.textMuted,
      fontSize: 13,
    },
    langTabs: {
      flexDirection: 'row',
      gap: spacing.sm,
    },
    langTab: {
      borderColor: colors.borderStrong,
      borderRadius: radius.md,
      borderWidth: StyleSheet.hairlineWidth,
      paddingHorizontal: spacing.md,
      paddingVertical: spacing.sm,
    },
    langTabActive: {
      backgroundColor: colors.primary,
      borderColor: colors.primary,
    },
    langTabText: {
      color: colors.text,
      fontSize: 13,
      fontWeight: '600',
    },
    langTabTextActive: {
      color: colors.white,
    },
    textArea: {
      minHeight: 72,
      textAlignVertical: 'top',
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
      justifyContent: 'flex-end',
    },
    modalActionButton: {
      flex: 1,
    },
  });
}
