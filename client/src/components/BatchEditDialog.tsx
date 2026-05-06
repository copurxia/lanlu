import React, {useCallback, useEffect, useMemo, useState} from 'react';
import {
  ActivityIndicator,
  Modal,
  Pressable,
  ScrollView,
  StyleSheet,
  Text,
  TextInput,
  TouchableOpacity,
  View,
} from 'react-native';

import {Drawer} from './Drawer';
import {fetchMetadataPlugins, type Plugin} from '../api/lanlu';
import {useTheme} from '../theme/ThemeContext';
import type {TFunction} from '../i18n';

export type SummaryMode = 'append' | 'replace' | 'clear';
export type BatchEditScope = 'all' | 'archive' | 'tankoubon';

export type BatchEditPayload = {
  scope: BatchEditScope;
  updateTitle: boolean;
  titlePrefix: string;
  titleSuffix: string;
  updateSummary: boolean;
  summaryMode: SummaryMode;
  summaryValue: string;
  updateTags: boolean;
  tagsAdd: string[];
  tagsRemove: string[];
  runMetadataPlugin: boolean;
  metadataPluginNamespace: string;
  metadataPluginParam: string;
};

type Props = {
  visible: boolean;
  onClose: () => void;
  totalSelected: number;
  selectedArchiveCount: number;
  selectedTankoubonCount: number;
  applying: boolean;
  t: TFunction;
  onApply: (payload: BatchEditPayload) => Promise<boolean>;
};

export function BatchEditDialog({
  visible,
  onClose,
  totalSelected,
  selectedArchiveCount,
  selectedTankoubonCount,
  applying,
  t,
  onApply,
}: Props) {
  const {colors} = useTheme();

  const [scope, setScope] = useState<BatchEditScope>('all');
  const [updateTitle, setUpdateTitle] = useState(false);
  const [titlePrefix, setTitlePrefix] = useState('');
  const [titleSuffix, setTitleSuffix] = useState('');
  const [updateSummary, setUpdateSummary] = useState(false);
  const [summaryMode, setSummaryMode] = useState<SummaryMode>('append');
  const [summaryValue, setSummaryValue] = useState('');
  const [updateTags, setUpdateTags] = useState(false);
  const [tagsAddRaw, setTagsAddRaw] = useState('');
  const [tagsRemoveRaw, setTagsRemoveRaw] = useState('');
  const [runMetadataPlugin, setRunMetadataPlugin] = useState(false);
  const [metadataPluginNamespace, setMetadataPluginNamespace] = useState('');
  const [metadataPluginParam, setMetadataPluginParam] = useState('');
  const [metadataPluginPickerOpen, setMetadataPluginPickerOpen] = useState(false);

  const [plugins, setPlugins] = useState<Plugin[]>([]);

  useEffect(() => {
    if (visible) {
      setScope('all');
      setUpdateTitle(false);
      setTitlePrefix('');
      setTitleSuffix('');
      setUpdateSummary(false);
      setSummaryMode('append');
      setSummaryValue('');
      setUpdateTags(false);
      setTagsAddRaw('');
      setTagsRemoveRaw('');
      setRunMetadataPlugin(false);
      setMetadataPluginNamespace('');
      setMetadataPluginParam('');
      setMetadataPluginPickerOpen(false);

      fetchMetadataPlugins()
        .then(setPlugins)
        .catch(() => setPlugins([]));
    }
  }, [visible]);

  const tagsAdd = useMemo(
    () =>
      tagsAddRaw
        .split(',')
        .map(s => s.trim())
        .filter(Boolean),
    [tagsAddRaw],
  );

  const tagsRemove = useMemo(
    () =>
      tagsRemoveRaw
        .split(',')
        .map(s => s.trim())
        .filter(Boolean),
    [tagsRemoveRaw],
  );

  const hasAnyFieldEnabled =
    updateTitle || updateSummary || updateTags || runMetadataPlugin;
  const pluginReady =
    !runMetadataPlugin || metadataPluginNamespace.trim().length > 0;
  const effectiveArchiveCount = scope === 'tankoubon' ? 0 : selectedArchiveCount;
  const effectiveTankoubonCount = scope === 'archive' ? 0 : selectedTankoubonCount;
  const effectiveTotalCount = effectiveArchiveCount + effectiveTankoubonCount;

  const summaryLines = useMemo(() => {
    const lines: string[] = [];
    const scopeLabel =
      scope === 'all'
        ? t('home.batchScopeAll')
        : scope === 'archive'
          ? t('home.batchScopeArchive')
          : t('home.batchScopeTankoubon');
    lines.push(`${t('home.batchScopeLabel')}: ${scopeLabel}`);
    if (updateTitle && (titlePrefix.trim() || titleSuffix.trim())) {
      lines.push(`Title: +${titlePrefix.trim() || "''"} / +${titleSuffix.trim() || "''"}`);
    }
    if (updateSummary) {
      const modeLabel =
        summaryMode === 'append'
          ? 'Append'
          : summaryMode === 'replace'
            ? 'Replace'
            : 'Clear';
      lines.push(`Summary: ${modeLabel}`);
    }
    if (updateTags) {
      lines.push(`Tags: +${tagsAdd.length} / -${tagsRemove.length}`);
    }
    if (runMetadataPlugin) {
      lines.push(
        `Plugin: ${metadataPluginNamespace || '(not selected)'}`,
      );
    }
    return lines;
  }, [
    metadataPluginNamespace,
    scope,
    runMetadataPlugin,
    t,
    summaryMode,
    tagsAdd.length,
    tagsRemove.length,
    titlePrefix,
    titleSuffix,
    updateSummary,
    updateTags,
    updateTitle,
  ]);

  const handleApply = useCallback(async () => {
    const ok = await onApply({
      scope,
      updateTitle,
      titlePrefix,
      titleSuffix,
      updateSummary,
      summaryMode,
      summaryValue,
      updateTags,
      tagsAdd,
      tagsRemove,
      runMetadataPlugin,
      metadataPluginNamespace,
      metadataPluginParam,
    });
    if (ok) onClose();
  }, [
    onApply,
    onClose,
    scope,
    updateTitle,
    titlePrefix,
    titleSuffix,
    updateSummary,
    summaryMode,
    summaryValue,
    updateTags,
    tagsAdd,
    tagsRemove,
    runMetadataPlugin,
    metadataPluginNamespace,
    metadataPluginParam,
  ]);

  const styles = useMemo(
    () =>
      StyleSheet.create({
        sheetContent: {
          backgroundColor: colors.background,
          flex: 1,
        },
        header: {
          alignItems: 'center',
          borderBottomColor: colors.border,
          borderBottomWidth: StyleSheet.hairlineWidth,
          flexDirection: 'row',
          justifyContent: 'space-between',
          paddingHorizontal: 16,
          paddingVertical: 14,
        },
        headerTitle: {
          color: colors.text,
          fontSize: 17,
          fontWeight: '800',
        },
        closeButton: {
          padding: 4,
        },
        closeButtonText: {
          color: colors.primary,
          fontSize: 15,
          fontWeight: '600',
        },
        body: {
          flex: 1,
          paddingHorizontal: 16,
          paddingTop: 16,
        },
        bodyContent: {
          flexGrow: 1,
          paddingBottom: 20,
        },
        infoBox: {
          backgroundColor: colors.surface,
          borderColor: colors.border,
          borderRadius: 8,
          borderWidth: StyleSheet.hairlineWidth,
          marginBottom: 16,
          padding: 12,
        },
        infoLabel: {
          color: colors.text,
          fontSize: 14,
          fontWeight: '600',
        },
        infoSub: {
          color: colors.textMuted,
          fontSize: 12,
          marginTop: 2,
        },
        scopeRow: {
          flexDirection: 'row',
          gap: 8,
          marginBottom: 16,
        },
        scopeButton: {
          alignItems: 'center',
          borderColor: colors.borderStrong,
          borderRadius: 8,
          borderWidth: StyleSheet.hairlineWidth,
          flex: 1,
          paddingHorizontal: 10,
          paddingVertical: 10,
        },
        scopeButtonActive: {
          backgroundColor: colors.primary,
          borderColor: colors.primary,
        },
        scopeButtonText: {
          color: colors.text,
          fontSize: 13,
          fontWeight: '700',
        },
        scopeButtonTextActive: {
          color: colors.white,
        },
        section: {
          borderColor: colors.border,
          borderRadius: 8,
          borderWidth: StyleSheet.hairlineWidth,
          marginBottom: 12,
          padding: 12,
        },
        sectionHeader: {
          alignItems: 'center',
          flexDirection: 'row',
          gap: 8,
        },
        sectionCheckbox: {
          alignItems: 'center',
          borderColor: colors.borderStrong,
          borderRadius: 4,
          borderWidth: 2,
          height: 20,
          justifyContent: 'center',
          width: 20,
        },
        sectionCheckboxActive: {
          backgroundColor: colors.primary,
          borderColor: colors.primary,
        },
        checkmark: {
          color: colors.white,
          fontSize: 12,
          fontWeight: '800',
        },
        sectionLabel: {
          color: colors.text,
          fontSize: 14,
          fontWeight: '600',
        },
        sectionBody: {
          marginTop: 10,
        },
        inputRow: {
          flexDirection: 'row',
          gap: 8,
        },
        input: {
          backgroundColor: colors.surface,
          borderColor: colors.border,
          borderRadius: 8,
          borderWidth: StyleSheet.hairlineWidth,
          color: colors.text,
          flex: 1,
          fontSize: 14,
          paddingHorizontal: 10,
          paddingVertical: 8,
        },
        picker: {
          backgroundColor: colors.surface,
          borderColor: colors.border,
          borderRadius: 8,
          borderWidth: StyleSheet.hairlineWidth,
          flex: 1,
          paddingHorizontal: 12,
          paddingVertical: 10,
        },
        pickerOverlay: {
          backgroundColor: 'rgba(0,0,0,0.45)',
          flex: 1,
          justifyContent: 'flex-end',
        },
        pickerSheet: {
          backgroundColor: colors.background,
          borderTopLeftRadius: 18,
          borderTopRightRadius: 18,
          maxHeight: '70%',
          paddingBottom: 24,
          paddingHorizontal: 16,
          paddingTop: 10,
        },
        pickerSheetHandle: {
          alignSelf: 'center',
          backgroundColor: colors.borderStrong,
          borderRadius: 999,
          height: 4,
          marginBottom: 12,
          width: 42,
        },
        pickerSheetTitle: {
          color: colors.text,
          fontSize: 16,
          fontWeight: '800',
          marginBottom: 12,
        },
        pickerSheetItem: {
          borderColor: colors.border,
          borderRadius: 12,
          borderWidth: StyleSheet.hairlineWidth,
          marginBottom: 10,
          paddingHorizontal: 12,
          paddingVertical: 12,
        },
        pickerSheetItemActive: {
          backgroundColor: colors.primaryMuted,
          borderColor: colors.primary,
        },
        pickerSheetItemText: {
          color: colors.text,
          fontSize: 14,
          fontWeight: '700',
        },
        pickerSheetItemTextActive: {
          color: colors.primary,
        },
        pickerSheetItemSub: {
          color: colors.textMuted,
          fontSize: 12,
          marginTop: 2,
        },
        pickerSheetEmpty: {
          color: colors.textMuted,
          fontSize: 13,
          paddingVertical: 10,
        },
        pickerText: {
          color: colors.text,
          fontSize: 14,
        },
        tagHint: {
          color: colors.textMuted,
          fontSize: 11,
          marginTop: 4,
        },
        previewBox: {
          backgroundColor: colors.surface,
          borderColor: colors.border,
          borderRadius: 8,
          borderWidth: StyleSheet.hairlineWidth,
          marginBottom: 16,
          padding: 12,
        },
        previewTitle: {
          color: colors.text,
          fontSize: 13,
          fontWeight: '600',
          marginBottom: 4,
        },
        previewLine: {
          color: colors.textMuted,
          fontSize: 12,
          marginTop: 2,
        },
        previewEmpty: {
          color: colors.textMuted,
          fontSize: 12,
        },
        footer: {
          borderTopColor: colors.border,
          borderTopWidth: StyleSheet.hairlineWidth,
          flexDirection: 'row',
          gap: 10,
          paddingHorizontal: 16,
          paddingTop: 14,
        },
        cancelButton: {
          alignItems: 'center',
          borderColor: colors.border,
          borderRadius: 8,
          borderWidth: StyleSheet.hairlineWidth,
          flex: 1,
          paddingVertical: 12,
        },
        cancelButtonText: {
          color: colors.text,
          fontSize: 15,
          fontWeight: '700',
        },
        applyButton: {
          alignItems: 'center',
          backgroundColor: colors.primary,
          borderRadius: 8,
          flex: 1,
          paddingVertical: 12,
        },
        applyButtonDisabled: {
          opacity: 0.5,
        },
        applyButtonText: {
          color: colors.white,
          fontSize: 15,
          fontWeight: '700',
        },
      }),
    [colors],
  );

  return (
    <Drawer open={visible} onClose={onClose} maxHeight="92%" showHandle={false} style={{backgroundColor: colors.background}}>
      <View style={styles.sheetContent}>
          <View style={styles.header}>
            <Text style={styles.headerTitle}>{t('home.batchEditTitle')}</Text>
            <TouchableOpacity style={styles.closeButton} onPress={onClose}>
              <Text style={styles.closeButtonText}>{t('common.close')}</Text>
            </TouchableOpacity>
          </View>

          <ScrollView
            contentContainerStyle={styles.bodyContent}
            showsVerticalScrollIndicator={false}
            style={styles.body}>
          <View style={styles.infoBox}>
            <Text style={styles.infoLabel}>
                {t('common.selected')}: {totalSelected}
            </Text>
            <Text style={styles.infoSub}>
              Archive: {effectiveArchiveCount} / Tankoubon: {effectiveTankoubonCount}
            </Text>
          </View>

          <View style={styles.scopeRow}>
            {[
              {value: 'all', label: t('home.batchScopeAll')},
              {value: 'archive', label: t('home.batchScopeArchive')},
              {value: 'tankoubon', label: t('home.batchScopeTankoubon')},
            ].map(option => {
              const active = scope === option.value;
              return (
                <TouchableOpacity
                  key={option.value}
                  style={[styles.scopeButton, active && styles.scopeButtonActive]}
                  onPress={() => setScope(option.value as BatchEditScope)}>
                  <Text style={[styles.scopeButtonText, active && styles.scopeButtonTextActive]}>
                    {option.label}
                  </Text>
                </TouchableOpacity>
              );
            })}
          </View>

            {/* Title */}
            <View style={styles.section}>
              <TouchableOpacity
                style={styles.sectionHeader}
                onPress={() => setUpdateTitle(v => !v)}>
                <View style={[styles.sectionCheckbox, updateTitle && styles.sectionCheckboxActive]}>
                  {updateTitle ? <Text style={styles.checkmark}>✓</Text> : null}
                </View>
                <Text style={styles.sectionLabel}>{t('home.batchEditTitleField')}</Text>
              </TouchableOpacity>
              {updateTitle && (
                <View style={styles.sectionBody}>
                  <View style={styles.inputRow}>
                    <TextInput
                      style={styles.input}
                      value={titlePrefix}
                      onChangeText={setTitlePrefix}
                      placeholder={t('home.batchTitlePrefixPlaceholder')}
                      placeholderTextColor={colors.textMuted}
                    />
                    <TextInput
                      style={styles.input}
                      value={titleSuffix}
                      onChangeText={setTitleSuffix}
                      placeholder={t('home.batchTitleSuffixPlaceholder')}
                      placeholderTextColor={colors.textMuted}
                    />
                  </View>
                </View>
              )}
            </View>

            {/* Summary */}
            <View style={styles.section}>
              <TouchableOpacity
                style={styles.sectionHeader}
                onPress={() => setUpdateSummary(v => !v)}>
                <View style={[styles.sectionCheckbox, updateSummary && styles.sectionCheckboxActive]}>
                  {updateSummary ? <Text style={styles.checkmark}>✓</Text> : null}
                </View>
                <Text style={styles.sectionLabel}>{t('archive.summary')}</Text>
              </TouchableOpacity>
              {updateSummary && (
                <View style={styles.sectionBody}>
                  <View style={styles.inputRow}>
                    {(['append', 'replace', 'clear'] as SummaryMode[]).map(mode => {
                      const label =
                        mode === 'append'
                          ? t('home.batchSummaryAppend')
                          : mode === 'replace'
                            ? t('home.batchSummaryReplace')
                            : t('home.batchSummaryClear');
                      const isActive = summaryMode === mode;
                      return (
                        <TouchableOpacity
                          key={mode}
                          onPress={() => setSummaryMode(mode)}
                          style={[
                            styles.picker,
                            isActive && {borderColor: colors.primary, backgroundColor: colors.primaryMuted},
                          ]}>
                          <Text
                            style={[
                              styles.pickerText,
                              isActive && {color: colors.primary, fontWeight: '700'},
                            ]}>
                            {label}
                          </Text>
                        </TouchableOpacity>
                      );
                    })}
                  </View>
                  {summaryMode !== 'clear' && (
                    <TextInput
                      style={[styles.input, {marginTop: 8, minHeight: 60, textAlignVertical: 'top'}]}
                      value={summaryValue}
                      onChangeText={setSummaryValue}
                      placeholder={t('home.batchSummaryPlaceholder')}
                      placeholderTextColor={colors.textMuted}
                      multiline
                    />
                  )}
                </View>
              )}
            </View>

            {/* Tags */}
            <View style={styles.section}>
              <TouchableOpacity
                style={styles.sectionHeader}
                onPress={() => setUpdateTags(v => !v)}>
                <View style={[styles.sectionCheckbox, updateTags && styles.sectionCheckboxActive]}>
                  {updateTags ? <Text style={styles.checkmark}>✓</Text> : null}
                </View>
                <Text style={styles.sectionLabel}>{t('archive.tags')}</Text>
              </TouchableOpacity>
              {updateTags && (
                <View style={styles.sectionBody}>
                  <View style={styles.inputRow}>
                    <TextInput
                      style={styles.input}
                      value={tagsAddRaw}
                      onChangeText={setTagsAddRaw}
                      placeholder={t('home.batchTagsAddPlaceholder')}
                      placeholderTextColor={colors.textMuted}
                    />
                    <TextInput
                      style={styles.input}
                      value={tagsRemoveRaw}
                      onChangeText={setTagsRemoveRaw}
                      placeholder={t('home.batchTagsRemovePlaceholder')}
                      placeholderTextColor={colors.textMuted}
                    />
                  </View>
                  <Text style={styles.tagHint}>
                    +{tagsAdd.length} / -{tagsRemove.length}
                  </Text>
                </View>
              )}
            </View>

            {/* Metadata Plugin */}
            <View style={styles.section}>
              <TouchableOpacity
                style={styles.sectionHeader}
                onPress={() => setRunMetadataPlugin(v => !v)}>
                <View style={[styles.sectionCheckbox, runMetadataPlugin && styles.sectionCheckboxActive]}>
                  {runMetadataPlugin ? <Text style={styles.checkmark}>✓</Text> : null}
                </View>
                <Text style={styles.sectionLabel}>{t('archive.metadataPluginLabel')}</Text>
              </TouchableOpacity>
              {runMetadataPlugin && (
                <View style={styles.sectionBody}>
                  <View style={styles.inputRow}>
                    <TouchableOpacity
                      style={styles.picker}
                      onPress={() => {
                        if (plugins.length === 0) return;
                        setMetadataPluginPickerOpen(true);
                      }}
                      disabled={plugins.length === 0}>
                      <Text style={styles.pickerText} numberOfLines={1}>
                        {metadataPluginNamespace
                          ? plugins.find(p => p.namespace === metadataPluginNamespace)?.name ||
                            metadataPluginNamespace
                          : t('archive.metadataPluginSelectPlaceholder')}
                      </Text>
                    </TouchableOpacity>
                    <TextInput
                      style={styles.input}
                      value={metadataPluginParam}
                      onChangeText={setMetadataPluginParam}
                      placeholder={t('archive.metadataPluginParamPlaceholder')}
                      placeholderTextColor={colors.textMuted}
                    />
                  </View>
                  {plugins.length === 0 && (
                    <Text style={styles.tagHint}>{t('archive.metadataPluginNoPlugins')}</Text>
                  )}
                </View>
              )}
            </View>

            {/* Preview */}
            <View style={styles.previewBox}>
              <Text style={styles.previewTitle}>
                {t('home.batchPreviewTarget').replace('{count}', String(effectiveTotalCount))}
              </Text>
              {summaryLines.length > 0 ? (
                summaryLines.map((line, i) => (
                  <Text key={i} style={styles.previewLine}>
                    • {line}
                  </Text>
                ))
              ) : (
                <Text style={styles.previewEmpty}>
                  {t('home.batchEditNoFieldSelected')}
                </Text>
              )}
            </View>

            <View style={{height: 20}} />
          </ScrollView>

          <View style={styles.footer}>
            <TouchableOpacity
              style={styles.cancelButton}
              onPress={onClose}
              disabled={applying}>
              <Text style={styles.cancelButtonText}>{t('common.cancel')}</Text>
            </TouchableOpacity>
            <TouchableOpacity
              style={[
                styles.applyButton,
                (!hasAnyFieldEnabled || !pluginReady || applying || effectiveTotalCount === 0) &&
                  styles.applyButtonDisabled,
              ]}
              onPress={handleApply}
              disabled={!hasAnyFieldEnabled || !pluginReady || applying || effectiveTotalCount === 0}>
              {applying ? (
                <ActivityIndicator color={colors.white} size="small" />
              ) : (
                <Text style={styles.applyButtonText}>
                  {t('home.batchApplyToCount').replace(
                    '{count}',
                    String(effectiveTotalCount),
                  )}
                </Text>
              )}
            </TouchableOpacity>
          </View>

        <Modal
          visible={metadataPluginPickerOpen}
          transparent
          statusBarTranslucent
          onRequestClose={() => setMetadataPluginPickerOpen(false)}>
          <Pressable style={styles.pickerOverlay} onPress={() => setMetadataPluginPickerOpen(false)}>
            <View style={styles.pickerSheet}>
              <View style={styles.pickerSheetHandle} />
              <Text style={styles.pickerSheetTitle}>{t('archive.metadataPluginLabel')}</Text>
              <ScrollView showsVerticalScrollIndicator={false}>
                {plugins.map(plugin => {
                  const active = metadataPluginNamespace === plugin.namespace;
                  return (
                    <TouchableOpacity
                      key={plugin.namespace}
                      style={[styles.pickerSheetItem, active && styles.pickerSheetItemActive]}
                      onPress={() => {
                        setMetadataPluginNamespace(plugin.namespace);
                        setMetadataPluginPickerOpen(false);
                      }}>
                      <Text style={[styles.pickerSheetItemText, active && styles.pickerSheetItemTextActive]}>
                        {plugin.name}
                      </Text>
                      <Text style={styles.pickerSheetItemSub} numberOfLines={1}>
                        {plugin.namespace}
                      </Text>
                    </TouchableOpacity>
                  );
                })}
                {plugins.length === 0 ? (
                  <Text style={styles.pickerSheetEmpty}>{t('archive.metadataPluginNoPlugins')}</Text>
                ) : null}
              </ScrollView>
            </View>
          </Pressable>
        </Modal>
      </View>
    </Drawer>
  );
}
