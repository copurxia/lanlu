import React, {useCallback, useEffect, useMemo, useState} from 'react';
import {Alert, Modal, RefreshControl, ScrollView, StyleSheet, Text, TouchableOpacity, View, Switch} from 'react-native';
import {ArrowLeft, Plus} from 'lucide-react-native';
import {useSafeAreaInsets} from 'react-native-safe-area-context';
import {useNavigation} from '@react-navigation/native';
import {ScreenRoot, ModalBackdrop, screenSafeAreaPadding} from '../components/SafeAreaSurface';
import {FluentButton, FluentCard, FluentCaption, FluentTextField, FluentTitle} from '../components/fluent';
import {useI18n} from '../i18n';
import {extractApiError} from '../api/client';
import {spacing, radius, type ThemeColors} from '../theme/colors';
import {useTheme} from '../theme/ThemeContext';
import {
  getCronStatus,
  startCron,
  stopCron,
  listCronTasks,
  createCronTask,
  updateCronTask,
  deleteCronTask,
  triggerCronTask,
  enableCronTask,
  disableCronTask,
} from '../api/admin';
import type {CronStatus, ScheduledTask} from '../api/admin';

export function CronSettingsScreen() {
  const {t} = useI18n();
  const {colors} = useTheme();
  const insets = useSafeAreaInsets();
  const navigation = useNavigation();
  const styles = useMemo(() => createStyles(colors), [colors]);

  const [status, setStatus] = useState<CronStatus | null>(null);
  const [tasks, setTasks] = useState<ScheduledTask[]>([]);
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [modalOpen, setModalOpen] = useState(false);
  const [editingTask, setEditingTask] = useState<ScheduledTask | null>(null);
  const [form, setForm] = useState({name: '', cronExpression: '', taskType: '', enabled: true, priority: '', timeoutSeconds: ''});

  async function loadData() {
    try {
      const [statusRes, tasksRes] = await Promise.all([getCronStatus(), listCronTasks({page: 1, pageSize: 100})]);
      setStatus(statusRes);
      setTasks(tasksRes.tasks || []);
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

  async function handleStart() {
    try {
      await startCron();
      await loadData();
    } catch (e) {Alert.alert(t('common.error'), extractApiError(e));}
  }

  async function handleStop() {
    try {
      await stopCron();
      await loadData();
    } catch (e) {Alert.alert(t('common.error'), extractApiError(e));}
  }

  function openCreate() {
    setEditingTask(null);
    setForm({name: '', cronExpression: '', taskType: '', enabled: true, priority: '', timeoutSeconds: ''});
    setModalOpen(true);
  }

  function openEdit(task: ScheduledTask) {
    setEditingTask(task);
    setForm({
      name: task.name,
      cronExpression: task.cronExpression,
      taskType: task.taskType,
      enabled: task.enabled,
      priority: task.priority != null ? String(task.priority) : '',
      timeoutSeconds: task.timeoutSeconds != null ? String(task.timeoutSeconds) : '',
    });
    setModalOpen(true);
  }

  async function handleSave() {
    const payload = {
      name: form.name,
      cronExpression: form.cronExpression,
      taskType: form.taskType,
      enabled: form.enabled,
      priority: form.priority ? parseInt(form.priority, 10) : undefined,
      timeoutSeconds: form.timeoutSeconds ? parseInt(form.timeoutSeconds, 10) : undefined,
    };
    try {
      if (editingTask) {
        await updateCronTask(editingTask.id, payload);
      } else {
        await createCronTask(payload);
      }
      setModalOpen(false);
      await loadData();
    } catch (e) {Alert.alert(t('common.error'), extractApiError(e));}
  }

  function confirmDelete(task: ScheduledTask) {
    Alert.alert(t('common.confirm'), t('common.delete') + ' cron task?', [
      {text: t('common.cancel'), style: 'cancel'},
      {text: t('common.delete'), style: 'destructive', onPress: () => handleDelete(task.id)},
    ]);
  }

  async function handleDelete(id: number) {
    try {
      await deleteCronTask(id);
      await loadData();
    } catch (e) {Alert.alert(t('common.error'), extractApiError(e));}
  }

  async function handleTrigger(id: number) {
    try {
      await triggerCronTask(id);
      Alert.alert(t('common.success'), t('common.taskTriggered'));
    } catch (e) {Alert.alert(t('common.error'), extractApiError(e));}
  }

  async function handleToggleEnabled(task: ScheduledTask) {
    try {
      if (task.enabled) {
        await disableCronTask(task.id);
      } else {
        await enableCronTask(task.id);
      }
      await loadData();
    } catch (e) {Alert.alert(t('common.error'), extractApiError(e));}
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
          <FluentTitle style={{flex: 1}}>{t('settings.cron')}</FluentTitle>
          <TouchableOpacity
            accessibilityRole="button"
            onPress={openCreate}
            style={styles.addButton}>
            <Plus color={colors.primary} size={24} />
          </TouchableOpacity>
        </View>

        <FluentCard style={styles.section}>
          <View style={styles.statusRow}>
            <View style={[styles.dot, {backgroundColor: status?.running ? colors.success : colors.danger}]} />
            <Text style={styles.statusText}>
              {status?.running ? t('common.running') : t('common.stopped')}
            </Text>
          </View>
          <View style={styles.statRow}>
            <Text style={styles.statLabel}>{t('common.total') || 'Total tasks'}</Text>
            <Text style={styles.statValue}>{status?.totalTasks ?? 0}</Text>
          </View>
          <View style={styles.statRow}>
            <Text style={styles.statLabel}>{t('common.enabledTasks') || 'Enabled tasks'}</Text>
            <Text style={styles.statValue}>{status?.enabledTasks ?? 0}</Text>
          </View>
          <View style={styles.buttonRow}>
            {status?.running ? (
              <FluentButton label={t("common.stop")} variant="danger" onPress={handleStop} style={styles.flexButton} />
            ) : (
              <FluentButton label={t("common.start")} variant="primary" onPress={handleStart} style={styles.flexButton} />
            )}
          </View>
        </FluentCard>

        {tasks.map(task => (
          <FluentCard key={task.id} style={styles.taskCard}>
            <TouchableOpacity accessibilityRole="button" onPress={() => openEdit(task)}>
              <View style={styles.taskHeader}>
                <Text style={styles.taskName}>{task.name}</Text>
                <View style={[styles.badge, {backgroundColor: task.enabled ? colors.success : colors.textMuted}]}>
                  <Text style={styles.badgeText}>{task.enabled ? t('common.enabled') : t('common.disabled')}</Text>
                </View>
              </View>
              <FluentCaption>{task.cronExpression}</FluentCaption>
              <View style={styles.taskMeta}>
                <Text style={styles.metaText}>Last run: {task.lastRunAt ? new Date(task.lastRunAt).toLocaleString() : '-'}</Text>
                <Text style={styles.metaText}>Next run: {task.nextRunAt ? new Date(task.nextRunAt).toLocaleString() : '-'}</Text>
              </View>
              <View style={styles.taskMeta}>
                <Text style={styles.metaText}>Run count: {task.runCount ?? 0}</Text>
                {task.lastRunAt ? (
                  <View style={[styles.dot, {backgroundColor: task.lastRunSuccess ? colors.success : colors.danger}]} />
                ) : null}
              </View>
            </TouchableOpacity>
            <View style={styles.taskActions}>
              <Switch
                value={task.enabled}
                onValueChange={() => handleToggleEnabled(task)}
                trackColor={{false: colors.borderStrong, true: colors.primaryMuted}}
                thumbColor={task.enabled ? colors.primary : colors.textMuted}
              />
              <FluentButton label={t("common.trigger")} variant="ghost" onPress={() => handleTrigger(task.id)} />
              <FluentButton label={t('common.delete')} variant="danger" onPress={() => confirmDelete(task)} />
            </View>
          </FluentCard>
        ))}
      </ScrollView>

      <Modal animationType="fade" onRequestClose={() => setModalOpen(false)} statusBarTranslucent transparent visible={modalOpen}>
        <ModalBackdrop style={styles.modalBackdrop}>
          <View style={[styles.modalSheet, {paddingBottom: Math.max(insets.bottom, spacing.lg)}]}>
            <FluentTitle>{editingTask ? t('common.edit') + ' Task' : t('common.create') + ' Task'}</FluentTitle>
            <FluentTextField label={t("common.name")} value={form.name} onChangeText={v => setForm(f => ({...f, name: v}))} />
            <FluentTextField label={t("common.cronExpression")} value={form.cronExpression} onChangeText={v => setForm(f => ({...f, cronExpression: v}))} />
            <FluentTextField label={t("common.taskType")} value={form.taskType} onChangeText={v => setForm(f => ({...f, taskType: v}))} />
            <View style={styles.switchRow}>
              <Text style={styles.switchLabel}>Enabled</Text>
              <Switch
                value={form.enabled}
                onValueChange={v => setForm(f => ({...f, enabled: v}))}
                trackColor={{false: colors.borderStrong, true: colors.primaryMuted}}
                thumbColor={form.enabled ? colors.primary : colors.textMuted}
              />
            </View>
            <FluentTextField label={t("common.priority")} value={form.priority} onChangeText={v => setForm(f => ({...f, priority: v}))} keyboardType="numeric" />
            <FluentTextField label={t("common.timeoutSeconds")} value={form.timeoutSeconds} onChangeText={v => setForm(f => ({...f, timeoutSeconds: v}))} keyboardType="numeric" />
            <View style={styles.modalActions}>
              <FluentButton label={t('common.cancel')} variant="secondary" onPress={() => setModalOpen(false)} style={styles.flexButton} />
              <FluentButton label={t('common.save')} variant="primary" onPress={handleSave} style={styles.flexButton} />
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
    section: {gap: spacing.md},
    header: {
      flexDirection: 'row',
      alignItems: 'center',
      gap: spacing.md,
    },
    backButton: {padding: spacing.xs},
    addButton: {
      width: 40,
      height: 40,
      borderRadius: 20,
      alignItems: 'center',
      justifyContent: 'center',
    },
    statusRow: {
      flexDirection: 'row',
      alignItems: 'center',
      gap: spacing.sm,
    },
    dot: {
      width: 10,
      height: 10,
      borderRadius: 5,
    },
    statusText: {
      color: colors.text,
      fontSize: 16,
      fontWeight: '700',
    },
    statRow: {
      flexDirection: 'row',
      justifyContent: 'space-between',
    },
    statLabel: {
      color: colors.textMuted,
      fontSize: 13,
    },
    statValue: {
      color: colors.text,
      fontSize: 13,
      fontWeight: '700',
    },
    buttonRow: {
      flexDirection: 'row',
      gap: spacing.sm,
    },
    flexButton: {flex: 1},
    taskCard: {gap: spacing.sm},
    taskHeader: {
      flexDirection: 'row',
      alignItems: 'center',
      justifyContent: 'space-between',
    },
    taskName: {
      color: colors.text,
      fontSize: 15,
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
    taskMeta: {
      flexDirection: 'row',
      gap: spacing.md,
      alignItems: 'center',
    },
    metaText: {
      color: colors.textMuted,
      fontSize: 12,
    },
    taskActions: {
      flexDirection: 'row',
      alignItems: 'center',
      gap: spacing.sm,
      marginTop: spacing.xs,
    },
    switchRow: {
      flexDirection: 'row',
      alignItems: 'center',
      justifyContent: 'space-between',
    },
    switchLabel: {
      color: colors.text,
      fontSize: 15,
      fontWeight: '700',
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
  });
}
