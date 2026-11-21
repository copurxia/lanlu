import React, {useCallback, useEffect, useMemo, useRef, useState} from 'react';
import {
  ActivityIndicator,
  Alert,
  Modal,
  Pressable,
  ScrollView,
  StyleSheet,
  Text,
  TextInput,
  TouchableOpacity,
  View,
} from 'react-native';
import FastImage from '@d11/react-native-fast-image';
import {launchImageLibrary} from 'react-native-image-picker';

import {
  fetchMetadataPlugins,
  parseMetadataPluginPreviewResult,
  parseRpcSelectMessage,
  respondRpcSelect,
  abortRpcSelect,
  runMetadataPlugin,
  updateTankoubonMetadata,
  uploadMetadataAsset,
  type Plugin,
  type RpcSelectRequest,
} from '../../api/lanlu';
import {useTheme} from '../../theme/ThemeContext';
import type {TFunction} from '../../i18n';
import {MetadataAssetsEditor} from '../archive-detail/MetadataAssetsEditor';

type Props = {
  visible: boolean;
  onClose: () => void;
  onSaved: () => void;
  tankoubonId: string;
  initialTitle: string;
  initialSummary: string;
  initialTags: string[];
  initialAssetCoverId: string;
  initialAssetBackdropId: string;
  initialAssetClearlogoId: string;
  t: TFunction;
};

export function TankoubonEditDialog({
  visible,
  onClose,
  onSaved,
  tankoubonId,
  initialTitle,
  initialSummary,
  initialTags,
  initialAssetCoverId,
  initialAssetBackdropId,
  initialAssetClearlogoId,
  t,
}: Props) {
  const {colors} = useTheme();

  const [title, setTitle] = useState(initialTitle);
  const [summary, setSummary] = useState(initialSummary);
  const [tagsText, setTagsText] = useState(initialTags.join(', '));
  const [assetCoverId, setAssetCoverId] = useState(initialAssetCoverId);
  const [assetBackdropId, setAssetBackdropId] = useState(initialAssetBackdropId);
  const [assetClearlogoId, setAssetClearlogoId] = useState(initialAssetClearlogoId);
  const [saving, setSaving] = useState(false);

  const [coverUploading, setCoverUploading] = useState(false);
  const [backdropUploading, setBackdropUploading] = useState(false);
  const [clearlogoUploading, setClearlogoUploading] = useState(false);

  const [plugins, setPlugins] = useState<Plugin[]>([]);
  const [selectedPlugin, setSelectedPlugin] = useState('');
  const [pluginParam, setPluginParam] = useState('');
  const [pluginRunning, setPluginRunning] = useState(false);
  const [pluginProgress, setPluginProgress] = useState<number | null>(null);
  const [pluginMessage, setPluginMessage] = useState('');

  const [pluginPickerOpen, setPluginPickerOpen] = useState(false);
  const [rpcSelectRequest, setRpcSelectRequest] = useState<RpcSelectRequest | null>(null);
  const [rpcSelectTaskId, setRpcSelectTaskId] = useState<number | null>(null);
  const [rpcSelectSelectedIndex, setRpcSelectSelectedIndex] = useState<number | null>(null);
  const [rpcSelectRemaining, setRpcSelectRemaining] = useState<number | null>(null);
  const resolvedRpcIdsRef = useRef<Set<string>>(new Set());
  const rpcTimerRef = useRef<ReturnType<typeof setInterval> | null>(null);

  useEffect(() => {
    if (visible) {
      setTitle(initialTitle);
      setSummary(initialSummary);
      setTagsText(initialTags.join(', '));
      setAssetCoverId(initialAssetCoverId);
      setAssetBackdropId(initialAssetBackdropId);
      setAssetClearlogoId(initialAssetClearlogoId);
      setSaving(false);
      setPluginRunning(false);
      setPluginProgress(null);
      setPluginMessage('');
      setPluginParam('');
      setRpcSelectRequest(null);
      setRpcSelectTaskId(null);
      setRpcSelectSelectedIndex(null);
      setRpcSelectRemaining(null);
      resolvedRpcIdsRef.current.clear();

      fetchMetadataPlugins()
        .then(metas => {
          setPlugins(metas);
          if (!selectedPlugin && metas.length > 0) {
            setSelectedPlugin(metas[0].namespace);
          }
        })
        .catch(() => {});
    }
  }, [visible, initialTitle, initialSummary, initialTags, initialAssetCoverId, initialAssetBackdropId, initialAssetClearlogoId]);

  useEffect(() => {
    if (rpcTimerRef.current) {
      clearInterval(rpcTimerRef.current);
      rpcTimerRef.current = null;
    }
    if (rpcSelectRequest && rpcSelectRemaining != null && rpcSelectRemaining > 0) {
      rpcTimerRef.current = setInterval(() => {
        setRpcSelectRemaining(prev => {
          if (prev == null || prev <= 1) {
            if (rpcTimerRef.current) clearInterval(rpcTimerRef.current);
            setRpcSelectRequest(null);
            setRpcSelectTaskId(null);
            setRpcSelectSelectedIndex(null);
            return null;
          }
          return prev - 1;
        });
      }, 1000);
    }
    return () => {
      if (rpcTimerRef.current) clearInterval(rpcTimerRef.current);
    };
  }, [rpcSelectRequest, rpcSelectRemaining]);

  const handleUpload = useCallback(
    async (slot: 'cover' | 'backdrop' | 'clearlogo') => {
      const result = await launchImageLibrary({mediaType: 'photo', quality: 0.8});
      if (!result.assets?.[0]?.uri) return;

      const setUploading = (v: boolean) => {
        if (slot === 'cover') setCoverUploading(v);
        else if (slot === 'backdrop') setBackdropUploading(v);
        else setClearlogoUploading(v);
      };

      setUploading(true);
      try {
        const assetId = await uploadMetadataAsset(
          result.assets[0].uri,
          result.assets[0].fileName || 'asset.jpg',
          result.assets[0].type || 'image/jpeg',
        );
        const idStr = String(assetId);
        if (slot === 'cover') setAssetCoverId(idStr);
        else if (slot === 'backdrop') setAssetBackdropId(idStr);
        else setAssetClearlogoId(idStr);
      } catch (e: any) {
        Alert.alert(t('common.error'), e.message || t('archive.assetUploadFailed'));
      } finally {
        setUploading(false);
      }
    },
    [t],
  );

  const handleSave = useCallback(async () => {
    setSaving(true);
    try {
      const tags = tagsText
        .split(',')
        .map(s => s.trim())
        .filter(Boolean);
      const parseId = (raw: string): number | undefined => {
        const n = Number.parseInt(String(raw || '').trim(), 10);
        return Number.isFinite(n) && n > 0 ? n : undefined;
      };
      const coverId = parseId(assetCoverId);
      const backdropId = parseId(assetBackdropId);
      const clearlogoId = parseId(assetClearlogoId);

      const assets: Record<string, unknown> = {};
      if (coverId) assets.cover = coverId;
      if (backdropId) assets.backdrop = backdropId;
      if (clearlogoId) assets.clearlogo = clearlogoId;

      await updateTankoubonMetadata(tankoubonId, {
        title,
        type: 1,
        description: summary,
        tags,
        assets: Object.keys(assets).length > 0 ? assets : undefined,
      });
      onSaved();
      onClose();
    } catch (e: any) {
      Alert.alert(t('common.error'), e.message || t('archive.updateFailed'));
    } finally {
      setSaving(false);
    }
  }, [tankoubonId, title, summary, tagsText, assetCoverId, assetBackdropId, assetClearlogoId, onSaved, onClose, t]);

  const handleRunPlugin = useCallback(async () => {
    if (!selectedPlugin || pluginRunning) return;
    resolvedRpcIdsRef.current.clear();
    setPluginRunning(true);
    setPluginProgress(0);
    setPluginMessage(t('archive.metadataPluginEnqueued'));
    setRpcSelectRequest(null);
    setRpcSelectTaskId(null);
    setRpcSelectSelectedIndex(null);
    setRpcSelectRemaining(null);

    try {
      const tags = tagsText
        .split(',')
        .map(s => s.trim())
        .filter(Boolean);
      const parseId = (raw: string): number | undefined => {
        const n = Number.parseInt(String(raw || '').trim(), 10);
        return Number.isFinite(n) && n > 0 ? n : undefined;
      };
      const rootAssets: Record<string, unknown> = {};
      const cId = parseId(assetCoverId);
      const bId = parseId(assetBackdropId);
      const lId = parseId(assetClearlogoId);
      if (cId) rootAssets.cover = cId;
      if (bId) rootAssets.backdrop = bId;
      if (lId) rootAssets.clearlogo = lId;

      const finalTask = await runMetadataPlugin(
        'tankoubon',
        tankoubonId,
        selectedPlugin,
        pluginParam,
        {
          writeBack: false,
          metadata: {
            title,
            type: 1,
            description: summary,
            tags,
            assets: Object.keys(rootAssets).length > 0 ? rootAssets : undefined,
            children: [],
          },
        },
        task => {
          if (task.progress != null) setPluginProgress(task.progress);
          if (task.message) {
            setPluginMessage(task.message);
            const rpcReq = parseRpcSelectMessage(task.message);
            if (rpcReq && !resolvedRpcIdsRef.current.has(rpcReq.request_id)) {
              setRpcSelectTaskId(task.id);
              setRpcSelectRequest(rpcReq);
              const defaultIdx =
                typeof rpcReq.default_index === 'number' &&
                rpcReq.default_index >= 0 &&
                rpcReq.default_index < rpcReq.options.length
                  ? rpcReq.default_index
                  : 0;
              setRpcSelectSelectedIndex(defaultIdx);
              const timeout =
                typeof rpcReq.timeout_seconds === 'number' && rpcReq.timeout_seconds > 0
                  ? Math.floor(rpcReq.timeout_seconds)
                  : 90;
              setRpcSelectRemaining(timeout);
            }
          }
        },
      );

      // Parse and apply preview result
      const preview = parseMetadataPluginPreviewResult(finalTask.result);
      if (preview) {
        if (preview.title.trim()) setTitle(preview.title.trim());
        setSummary(preview.summary);
        setTagsText(preview.tags.join(', '));
        if (/^\d+$/.test(preview.cover.trim())) {
          const id = Number.parseInt(preview.cover.trim(), 10);
          if (Number.isFinite(id) && id > 0) setAssetCoverId(String(id));
        }
        if (/^\d+$/.test(preview.backdrop.trim())) {
          const id = Number.parseInt(preview.backdrop.trim(), 10);
          if (Number.isFinite(id) && id > 0) setAssetBackdropId(String(id));
        }
        if (/^\d+$/.test(preview.clearlogo.trim())) {
          const id = Number.parseInt(preview.clearlogo.trim(), 10);
          if (Number.isFinite(id) && id > 0) setAssetClearlogoId(String(id));
        }
      }

      setPluginMessage(t('archive.metadataPluginCompleted'));
      setPluginProgress(100);
    } catch (e: any) {
      setPluginMessage(e.message || t('archive.metadataPluginFailed'));
    } finally {
      setPluginRunning(false);
    }
  }, [
    tankoubonId,
    selectedPlugin,
    pluginParam,
    pluginRunning,
    title,
    summary,
    tagsText,
    assetCoverId,
    assetBackdropId,
    assetClearlogoId,
    t,
  ]);

  const handleRpcSubmit = useCallback(async () => {
    if (rpcSelectTaskId == null || !rpcSelectRequest || rpcSelectSelectedIndex == null) return;
    const requestId = rpcSelectRequest.request_id;
    resolvedRpcIdsRef.current.add(requestId);
    const ok = await respondRpcSelect(rpcSelectTaskId, requestId, rpcSelectSelectedIndex);
    setRpcSelectRequest(null);
    setRpcSelectTaskId(null);
    setRpcSelectSelectedIndex(null);
    setRpcSelectRemaining(null);
    if (!ok) {
      Alert.alert(t('common.error'), 'RPC select response failed');
    }
  }, [rpcSelectRequest, rpcSelectSelectedIndex, rpcSelectTaskId, t]);

  const handleRpcAbort = useCallback(async () => {
    if (rpcSelectTaskId == null || !rpcSelectRequest) return;
    const requestId = rpcSelectRequest.request_id;
    resolvedRpcIdsRef.current.add(requestId);
    await abortRpcSelect(rpcSelectTaskId, requestId);
    setRpcSelectRequest(null);
    setRpcSelectTaskId(null);
    setRpcSelectSelectedIndex(null);
    setRpcSelectRemaining(null);
  }, [rpcSelectRequest, rpcSelectTaskId]);

  const tags = useMemo(
    () => tagsText.split(',').map(s => s.trim()).filter(Boolean),
    [tagsText],
  );

  const styles = useMemo(
    () =>
      StyleSheet.create({
        overlay: {
          backgroundColor: 'rgba(0,0,0,0.5)',
          flex: 1,
          justifyContent: 'flex-end',
        },
        container: {
          backgroundColor: colors.background,
          borderTopLeftRadius: 16,
          borderTopRightRadius: 16,
          maxHeight: '92%',
          paddingBottom: 34,
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
        body: {
          paddingHorizontal: 16,
          paddingTop: 16,
        },
        fieldLabel: {
          color: colors.text,
          fontSize: 14,
          fontWeight: '600',
          marginBottom: 6,
        },
        input: {
          backgroundColor: colors.surface,
          borderColor: colors.border,
          borderRadius: 8,
          borderWidth: StyleSheet.hairlineWidth,
          color: colors.text,
          fontSize: 15,
          paddingHorizontal: 12,
          paddingVertical: 10,
        },
        textArea: {
          backgroundColor: colors.surface,
          borderColor: colors.border,
          borderRadius: 8,
          borderWidth: StyleSheet.hairlineWidth,
          color: colors.text,
          fontSize: 15,
          minHeight: 72,
          paddingHorizontal: 12,
          paddingTop: 10,
          textAlignVertical: 'top',
        },
        tagHint: {
          color: colors.textMuted,
          fontSize: 11,
          marginTop: 4,
        },
        pluginSection: {
          borderColor: colors.border,
          borderRadius: 8,
          borderWidth: StyleSheet.hairlineWidth,
          padding: 12,
        },
        pluginRow: {
          flexDirection: 'row',
          gap: 8,
        },
        pluginPicker: {
          backgroundColor: colors.surface,
          borderColor: colors.border,
          borderRadius: 8,
          borderWidth: StyleSheet.hairlineWidth,
          flex: 1,
          paddingHorizontal: 12,
          paddingVertical: 10,
        },
        pluginPickerText: {
          color: colors.text,
          fontSize: 14,
        },
        pluginParamInput: {
          backgroundColor: colors.surface,
          borderColor: colors.border,
          borderRadius: 8,
          borderWidth: StyleSheet.hairlineWidth,
          color: colors.text,
          flex: 1,
          fontSize: 14,
          paddingHorizontal: 12,
          paddingVertical: 10,
        },
        runButton: {
          alignItems: 'center',
          backgroundColor: colors.primary,
          borderRadius: 8,
          justifyContent: 'center',
          paddingHorizontal: 16,
          paddingVertical: 10,
        },
        runButtonText: {
          color: colors.white,
          fontSize: 14,
          fontWeight: '700',
        },
        runButtonDisabled: {
          opacity: 0.5,
        },
        pluginStatus: {
          color: colors.textMuted,
          fontSize: 12,
          marginTop: 6,
        },
        pluginProgressRow: {
          alignItems: 'center',
          flexDirection: 'row',
          gap: 8,
          marginTop: 6,
        },
        pluginProgressText: {
          color: colors.textMuted,
          fontSize: 12,
        },
        noPlugins: {
          color: colors.textMuted,
          fontSize: 12,
          marginTop: 6,
        },
        pickerSheet: {
          backgroundColor: colors.background,
          borderTopLeftRadius: 16,
          borderTopRightRadius: 16,
          maxHeight: '60%',
          paddingBottom: 34,
          paddingHorizontal: 16,
          paddingTop: 8,
        },
        pickerSheetHandle: {
          alignSelf: 'center',
          backgroundColor: colors.border,
          borderRadius: 3,
          height: 4,
          marginBottom: 12,
          width: 40,
        },
        pickerSheetTitle: {
          color: colors.text,
          fontSize: 17,
          fontWeight: '800',
          marginBottom: 12,
        },
        pickerSheetItem: {
          borderBottomColor: colors.border,
          borderBottomWidth: StyleSheet.hairlineWidth,
          paddingVertical: 14,
        },
        pickerSheetItemActive: {
          backgroundColor: colors.primaryMuted,
          marginHorizontal: -16,
          paddingHorizontal: 16,
        },
        pickerSheetItemText: {
          color: colors.text,
          fontSize: 15,
          fontWeight: '600',
        },
        pickerSheetItemTextActive: {
          color: colors.primary,
        },
        pickerSheetItemSub: {
          color: colors.textMuted,
          fontSize: 12,
          marginTop: 2,
        },
        spacer: {
          height: 16,
        },
        footer: {
          borderTopColor: colors.border,
          borderTopWidth: StyleSheet.hairlineWidth,
          flexDirection: 'row',
          gap: 10,
          marginTop: 16,
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
        saveButton: {
          alignItems: 'center',
          backgroundColor: colors.primary,
          borderRadius: 8,
          flex: 1,
          paddingVertical: 12,
        },
        saveButtonText: {
          color: colors.white,
          fontSize: 15,
          fontWeight: '700',
        },
        saveButtonDisabled: {
          opacity: 0.5,
        },
        rpcOverlay: {
          backgroundColor: 'rgba(0,0,0,0.5)',
          flex: 1,
          justifyContent: 'flex-end',
        },
        rpcContainer: {
          backgroundColor: colors.background,
          borderTopLeftRadius: 16,
          borderTopRightRadius: 16,
          maxHeight: '80%',
          paddingBottom: 34,
          paddingHorizontal: 16,
          paddingTop: 12,
        },
        rpcTitle: {
          color: colors.text,
          fontSize: 17,
          fontWeight: '800',
          marginBottom: 8,
        },
        rpcMessage: {
          color: colors.textMuted,
          fontSize: 13,
          marginBottom: 12,
        },
        rpcOption: {
          backgroundColor: colors.surface,
          borderColor: colors.border,
          borderRadius: 8,
          borderWidth: StyleSheet.hairlineWidth,
          marginBottom: 8,
          padding: 12,
        },
        rpcOptionSelected: {
          borderColor: colors.primary,
          backgroundColor: colors.primaryMuted,
        },
        rpcOptionRow: {
          alignItems: 'center',
          flexDirection: 'row',
          gap: 12,
        },
        rpcOptionCover: {
          backgroundColor: colors.surfaceMuted,
          borderRadius: 4,
          height: 80,
          width: 56,
        },
        rpcOptionBody: {
          flex: 1,
        },
        rpcOptionLabel: {
          color: colors.text,
          fontSize: 14,
          fontWeight: '600',
        },
        rpcOptionDesc: {
          color: colors.textMuted,
          fontSize: 12,
          marginTop: 2,
        },
        rpcFooter: {
          alignItems: 'center',
          flexDirection: 'row',
          gap: 8,
          justifyContent: 'flex-end',
          marginTop: 12,
        },
        rpcTimer: {
          color: colors.textMuted,
          fontSize: 12,
          flex: 1,
        },
        rpcAbortButton: {
          borderColor: colors.border,
          borderRadius: 8,
          borderWidth: StyleSheet.hairlineWidth,
          paddingHorizontal: 16,
          paddingVertical: 10,
        },
        rpcAbortText: {
          color: colors.text,
          fontSize: 14,
          fontWeight: '600',
        },
        rpcSubmitButton: {
          backgroundColor: colors.primary,
          borderRadius: 8,
          paddingHorizontal: 16,
          paddingVertical: 10,
        },
        rpcSubmitText: {
          color: colors.white,
          fontSize: 14,
          fontWeight: '700',
        },
        rpcSubmitDisabled: {
          opacity: 0.5,
        },
      }),
    [colors],
  );

  return (
    <>
      <Modal visible={visible} animationType="slide" transparent statusBarTranslucent onRequestClose={onClose}>
        <View style={[styles.overlay, {paddingTop: 0}]}>
          <View style={styles.container}>
            <View style={styles.header}>
              <Text style={styles.headerTitle}>{t('common.edit')}</Text>
              <TouchableOpacity style={styles.closeButton} onPress={onClose}>
                <Text style={{color: colors.primary, fontSize: 15, fontWeight: '600'}}>{t('common.close')}</Text>
              </TouchableOpacity>
            </View>

            <ScrollView style={styles.body} showsVerticalScrollIndicator={false}>
              <MetadataAssetsEditor
                t={t}
                title={title}
                disabled={saving || pluginRunning}
                coverAssetId={assetCoverId}
                onUploadCover={() => handleUpload('cover')}
                backdropAssetId={assetBackdropId}
                onUploadBackdrop={() => handleUpload('backdrop')}
                clearlogoAssetId={assetClearlogoId}
                onUploadClearlogo={() => handleUpload('clearlogo')}
                uploadingCover={coverUploading}
                uploadingBackdrop={backdropUploading}
                uploadingClearlogo={clearlogoUploading}
              />

              <View style={styles.spacer} />

              <Text style={styles.fieldLabel}>{t('tankoubon.name')}</Text>
              <TextInput
                style={styles.input}
                value={title}
                onChangeText={setTitle}
                editable={!saving}
              />

              <View style={styles.spacer} />

              <Text style={styles.fieldLabel}>{t('tankoubon.summary')}</Text>
              <TextInput
                style={styles.textArea}
                value={summary}
                onChangeText={setSummary}
                placeholder={t('tankoubon.summaryPlaceholder')}
                placeholderTextColor={colors.textMuted}
                multiline
                editable={!saving}
              />

              <View style={styles.spacer} />

              <View style={styles.pluginSection}>
                <Text style={styles.fieldLabel}>{t('tankoubon.metadataPluginLabel')}</Text>
                <View style={styles.pluginRow}>
                  <TouchableOpacity
                    style={styles.pluginPicker}
                    onPress={() => setPluginPickerOpen(true)}
                    disabled={saving || pluginRunning || plugins.length === 0}>
                    <Text style={styles.pluginPickerText} numberOfLines={1}>
                      {selectedPlugin
                        ? plugins.find(p => p.namespace === selectedPlugin)?.name || selectedPlugin
                        : t('archive.metadataPluginSelectPlaceholder')}
                    </Text>
                  </TouchableOpacity>
                  <TextInput
                    style={styles.pluginParamInput}
                    value={pluginParam}
                    onChangeText={setPluginParam}
                    placeholder={t('archive.metadataPluginParamPlaceholder')}
                    placeholderTextColor={colors.textMuted}
                    editable={!saving && !pluginRunning}
                  />
                  <TouchableOpacity
                    style={[styles.runButton, (saving || pluginRunning || !selectedPlugin) && styles.runButtonDisabled]}
                    onPress={handleRunPlugin}
                    disabled={saving || pluginRunning || !selectedPlugin}>
                    {pluginRunning ? (
                      <ActivityIndicator color={colors.white} size="small" />
                    ) : (
                      <Text style={styles.runButtonText}>{t('archive.metadataPluginRun')}</Text>
                    )}
                  </TouchableOpacity>
                </View>

                {(pluginProgress != null || pluginMessage) && (
                  <View style={styles.pluginProgressRow}>
                    <Text style={styles.pluginProgressText} numberOfLines={1}>
                      {pluginMessage || ''}
                    </Text>
                    {pluginProgress != null && (
                      <Text style={styles.pluginProgressText}>
                        {Math.max(0, Math.min(100, pluginProgress))}%
                      </Text>
                    )}
                  </View>
                )}

                {plugins.length === 0 && (
                  <Text style={styles.noPlugins}>{t('archive.metadataPluginNoPlugins')}</Text>
                )}
              </View>

              <Modal visible={pluginPickerOpen} transparent statusBarTranslucent onRequestClose={() => setPluginPickerOpen(false)}>
                <Pressable style={styles.overlay} onPress={() => setPluginPickerOpen(false)}>
                  <View style={styles.pickerSheet}>
                    <View style={styles.pickerSheetHandle} />
                    <Text style={styles.pickerSheetTitle}>{t('tankoubon.metadataPluginLabel')}</Text>
                    <ScrollView>
                      {plugins.map(p => (
                        <TouchableOpacity
                          key={p.namespace}
                          style={[styles.pickerSheetItem, selectedPlugin === p.namespace && styles.pickerSheetItemActive]}
                          onPress={() => {
                            setSelectedPlugin(p.namespace);
                            setPluginPickerOpen(false);
                          }}>
                          <Text style={[styles.pickerSheetItemText, selectedPlugin === p.namespace && styles.pickerSheetItemTextActive]}>
                            {p.name}
                          </Text>
                          <Text style={styles.pickerSheetItemSub}>{p.namespace}</Text>
                        </TouchableOpacity>
                      ))}
                    </ScrollView>
                  </View>
                </Pressable>
              </Modal>

              <View style={styles.spacer} />

              <Text style={styles.fieldLabel}>{t('tankoubon.tags')}</Text>
              <TextInput
                style={styles.input}
                value={tagsText}
                onChangeText={setTagsText}
                placeholder={t('tankoubon.tagsPlaceholder')}
                placeholderTextColor={colors.textMuted}
                editable={!saving}
              />
              {tags.length > 0 && (
                <Text style={styles.tagHint}>{tags.length} {t('archive.tags')}</Text>
              )}

              <View style={{height: 100}} />
            </ScrollView>

            <View style={styles.footer}>
              <TouchableOpacity style={styles.cancelButton} onPress={onClose} disabled={saving}>
                <Text style={styles.cancelButtonText}>{t('common.cancel')}</Text>
              </TouchableOpacity>
              <TouchableOpacity
                style={[styles.saveButton, (saving || pluginRunning) && styles.saveButtonDisabled]}
                onPress={handleSave}
                disabled={saving || pluginRunning}>
                {saving ? (
                  <ActivityIndicator color={colors.white} size="small" />
                ) : (
                  <Text style={styles.saveButtonText}>{t('common.save')}</Text>
                )}
              </TouchableOpacity>
            </View>
          </View>
        </View>
      </Modal>

      <Modal visible={!!rpcSelectRequest} animationType="slide" transparent statusBarTranslucent>
        <View style={styles.rpcOverlay}>
          <View style={styles.rpcContainer}>
            <Text style={styles.rpcTitle}>{rpcSelectRequest?.title || ''}</Text>
            {rpcSelectRequest?.message ? (
              <Text style={styles.rpcMessage}>{rpcSelectRequest.message}</Text>
            ) : null}

            <ScrollView>
              {(rpcSelectRequest?.options || []).map(opt => (
                <TouchableOpacity
                  key={`${rpcSelectRequest?.request_id}-${opt.index}`}
                  style={[styles.rpcOption, rpcSelectSelectedIndex === opt.index && styles.rpcOptionSelected]}
                  onPress={() => setRpcSelectSelectedIndex(opt.index)}>
                  <View style={styles.rpcOptionRow}>
                    {opt.cover ? (
                      <View style={styles.rpcOptionCover}>
                        <FastImage
                          source={{uri: opt.cover}}
                          style={{flex: 1}}
                          resizeMode={FastImage.resizeMode.cover}
                        />
                      </View>
                    ) : (
                      <View style={styles.rpcOptionCover} />
                    )}
                    <View style={styles.rpcOptionBody}>
                      <Text style={styles.rpcOptionLabel}>{opt.label || `Option ${opt.index + 1}`}</Text>
                      {opt.description ? (
                        <Text style={styles.rpcOptionDesc}>{opt.description}</Text>
                      ) : null}
                    </View>
                  </View>
                </TouchableOpacity>
              ))}
            </ScrollView>

            <Text style={styles.rpcTimer}>
              {rpcSelectRemaining != null
                ? `Remaining ${Math.max(0, rpcSelectRemaining)}s`
                : ''}
            </Text>

            <View style={styles.rpcFooter}>
              <TouchableOpacity style={styles.rpcAbortButton} onPress={handleRpcAbort}>
                <Text style={styles.rpcAbortText}>{t('common.cancel')}</Text>
              </TouchableOpacity>
              <TouchableOpacity
                style={[
                  styles.rpcSubmitButton,
                  (rpcSelectSelectedIndex == null || (rpcSelectRemaining ?? 1) <= 0) && styles.rpcSubmitDisabled,
                ]}
                onPress={handleRpcSubmit}
                disabled={rpcSelectSelectedIndex == null || (rpcSelectRemaining ?? 1) <= 0}>
                <Text style={styles.rpcSubmitText}>{t('common.confirm')}</Text>
              </TouchableOpacity>
            </View>
          </View>
        </View>
      </Modal>
    </>
  );
}
