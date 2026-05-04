import React, {useCallback, useEffect, useMemo, useState} from 'react';
import {Alert, Modal, RefreshControl, ScrollView, StyleSheet, Text, TouchableOpacity, View} from 'react-native';
import {ArrowLeft, RefreshCw} from 'lucide-react-native';
import {useSafeAreaInsets} from 'react-native-safe-area-context';
import {useNavigation} from '@react-navigation/native';
import {ScreenRoot, ModalBackdrop, screenSafeAreaPadding} from '../components/SafeAreaSurface';
import {FluentButton, FluentCard, FluentCaption, FluentTextField, FluentTitle} from '../components/fluent';
import {useI18n} from '../i18n';
import {extractApiError} from '../api/client';
import {
  adminListTasks,
  adminCancelTask,
  adminRetryTask,
  type TaskPoolTask,
} from '../api/admin';
import {spacing, radius, type ThemeColors} from '../theme/colors';
import {useTheme} from '../theme/ThemeContext';

const STATUS_LABELS: Record<string, string> = {
  All: 'common.all',
  Pending: 'common.statusPending',
  Running: 'common.statusRunning',
  Waiting: 'common.statusWaiting',
  Completed: 'common.statusCompleted',
  Failed: 'common.statusFailed',
};

const STATUSES = ['All', 'Pending', 'Running', 'Waiting', 'Completed', 'Failed'] as const;

export function TaskSettingsScreen() {
  const {t} = useI18n();
  const {colors} = useTheme();
  const insets = useSafeAreaInsets();
  const navigation = useNavigation();
  const styles = useMemo(() => createStyles(colors), [colors]);

  const [tasks, setTasks] = useState<TaskPoolTask[]>([]);
  const [total, setTotal] = useState(0);
  const [page, setPage] = useState(1);
  const [totalPages, setTotalPages] = useState(1);
  const [loading, setLoading] = useState(false);
  const [refreshing, setRefreshing] = useState(false);
  const [statusFilter, setStatusFilter] = useState<string>('All');
  const [expandedLogs, setExpandedLogs] = useState<Record<number, boolean>>({});
  const [resultModalVisible, setResultModalVisible] = useState(false);
  const [resultData, setResultData] = useState('');

  const pageSize = 20;

  const loadTasks = useCallback(async (p: number, status: string) => {
    try {
      const data = await adminListTasks({
        page: p,
        pageSize,
        status: status === 'All' ? undefined : status.toLowerCase(),
      });
      setTasks(data.tasks || []);
      setTotal(data.total || 0);
      setTotalPages(data.totalPages || 1);
    } catch (e) {
      Alert.alert(t('common.error'), extractApiError(e));
    }
  }, [t]);

  useEffect(() => {
    setLoading(true);
    loadTasks(page, statusFilter).finally(() => setLoading(false));
  }, [page, statusFilter, loadTasks]);

  const onRefresh = useCallback(async () => {
    setRefreshing(true);
    await loadTasks(page, statusFilter);
    setRefreshing(false);
  }, [page, statusFilter, loadTasks]);

  const handleCancel = useCallback(async (taskId: number) => {
    try {
      await adminCancelTask(taskId);
      await loadTasks(page, statusFilter);
    } catch (e) {
      Alert.alert(t('common.error'), extractApiError(e));
    }
  }, [page, statusFilter, loadTasks, t]);

  const handleRetry = useCallback(async (taskId: number) => {
    try {
      await adminRetryTask(taskId);
      await loadTasks(page, statusFilter);
    } catch (e) {
      Alert.alert(t('common.error'), extractApiError(e));
    }
  }, [page, statusFilter, loadTasks, t]);

  const statusBadgeStyle = useCallback((status: string) => {
    switch (status.toLowerCase()) {
      case 'running':
        return {backgroundColor: colors.primaryMuted, color: colors.primary};
      case 'completed':
        return {backgroundColor: colors.primaryMuted, color: colors.success};
      case 'failed':
        return {backgroundColor: colors.primaryMuted, color: colors.danger};
      default:
        return {backgroundColor: colors.surfaceMuted, color: colors.textMuted};
    }
  }, [colors]);

  const statusCounts = useMemo(() => {
    const counts: Record<string, number> = {};
    for (const task of tasks) {
      const s = task.status.toLowerCase();
      counts[s] = (counts[s] || 0) + 1;
    }
    return counts;
  }, [tasks]);

  const toggleLog = useCallback((taskId: number) => {
    setExpandedLogs(prev => ({...prev, [taskId]: !prev[taskId]}));
  }, []);

  const openResult = useCallback((task: TaskPoolTask) => {
    const result = (task as any).result;
    if (result != null) {
      try {
        setResultData(typeof result === 'string' ? result : JSON.stringify(result, null, 2));
      } catch {
        setResultData(String(result));
      }
    } else {
      setResultData(task.message || t('common.noResult'));
    }
    setResultModalVisible(true);
  }, []);

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
          <FluentTitle style={{flex: 1}}>{t('settings.tasks')}</FluentTitle>
          <TouchableOpacity
            accessibilityRole="button"
            onPress={onRefresh}
            style={styles.addButton}>
            <RefreshCw color={colors.primary} size={22} />
          </TouchableOpacity>
        </View>

        <ScrollView
          horizontal
          showsHorizontalScrollIndicator={false}
          contentContainerStyle={styles.chipsRow}>
          {STATUSES.map(s => {
            const count = s === 'All' ? undefined : (statusCounts[s.toLowerCase()] ?? 0);
            return (
              <TouchableOpacity
                key={s}
                accessibilityRole="button"
                onPress={() => {
                  setPage(1);
                  setStatusFilter(s);
                }}
                style={[
                  styles.chip,
                  statusFilter === s && {backgroundColor: colors.primary, borderColor: colors.primary},
                ]}>
                <Text style={[styles.chipText, statusFilter === s && {color: colors.white}]}>
                  {t(STATUS_LABELS[s] as any)}
                  {count !== undefined && count > 0 ? ` (${count})` : ''}
                </Text>
              </TouchableOpacity>
            );
          })}
        </ScrollView>

        {loading && tasks.length === 0 ? (
          <FluentCaption>{t('common.loading')}</FluentCaption>
        ) : tasks.length === 0 ? (
          <FluentCard style={styles.section}>
            <FluentCaption>{t('common.noResult')}</FluentCaption>
          </FluentCard>
        ) : (
          tasks.map(task => {
            const badge = statusBadgeStyle(task.status);
            const isLogExpanded = expandedLogs[task.id] ?? false;
            const longMessage = task.message && task.message.length > 100;
            const lastLine = longMessage ? task.message!.trim().split('\n').pop() || '' : '';
            const taskResult = (task as any).result;
            const hasResult = ['completed', 'failed'].includes(task.status.toLowerCase()) && taskResult != null;
            return (
              <FluentCard key={task.id} style={styles.section}>
                <View style={styles.taskHeader}>
                  <Text style={styles.taskName}>{task.name || `${t('common.task')} #${task.id}`}</Text>
                  <View style={[styles.statusBadge, {backgroundColor: badge.backgroundColor}]}>
                    <Text style={[styles.statusBadgeText, {color: badge.color}]}>
                      {t(STATUS_LABELS[task.status] as any) || task.status}
                    </Text>
                  </View>
                </View>

                <Text style={styles.taskIdText}>{t('common.id')}: {task.id}</Text>

                {(task.taskType || task.phase) ? (
                  <View style={styles.badgeRow}>
                    {task.taskType ? (
                      <View style={[styles.infoBadge, {backgroundColor: colors.primaryMuted}]}>
                        <Text style={[styles.infoBadgeText, {color: colors.primary}]}>{task.taskType}</Text>
                      </View>
                    ) : null}
                    {task.phase ? (
                      <View style={[styles.infoBadge, {backgroundColor: colors.surfaceMuted}]}>
                        <Text style={[styles.infoBadgeText, {color: colors.textMuted}]}>{task.phase}</Text>
                      </View>
                    ) : null}
                  </View>
                ) : null}

                {task.progress !== undefined && task.progress !== null ? (
                  <View style={styles.progressRow}>
                    <View style={[styles.progressBar, {backgroundColor: colors.surfaceMuted}]}>
                      <View style={[styles.progressFill, {width: `${Math.min(task.progress, 100)}%`, backgroundColor: colors.primary}]} />
                    </View>
                    <Text style={styles.progressText}>{Math.round(task.progress)}%</Text>
                  </View>
                ) : null}

                {task.createdAt ? (
                  <Text style={styles.timestamp}>{t('common.created')}: {task.createdAt}</Text>
                ) : null}
                {task.startedAt ? (
                  <Text style={styles.timestamp}>{t('common.started')}: {task.startedAt}</Text>
                ) : null}
                {task.completedAt ? (
                  <Text style={styles.timestamp}>Completed: {task.completedAt}</Text>
                ) : null}

                {longMessage ? (
                  <View style={styles.logSection}>
                    {isLogExpanded ? (
                      <ScrollView style={styles.logBox} nestedScrollEnabled>
                        <Text style={styles.logText}>{task.message}</Text>
                      </ScrollView>
                    ) : (
                      <Text style={styles.logPreview} numberOfLines={1}>{lastLine}</Text>
                    )}
                    <TouchableOpacity
                      accessibilityRole="button"
                      onPress={() => toggleLog(task.id)}>
                      <Text style={styles.logToggle}>
                        {isLogExpanded ? t('common.hideLog') : t('common.showLog')}
                      </Text>
                    </TouchableOpacity>
                  </View>
                ) : null}

                {hasResult ? (
                  <View style={styles.resultRow}>
                    <FluentButton
                      label={t("common.viewResult")}
                      variant="ghost"
                      onPress={() => openResult(task)}
                    />
                  </View>
                ) : null}

                <View style={styles.taskActions}>
                  {['running', 'pending'].includes(task.status.toLowerCase()) ? (
                    <FluentButton
                      label={t("common.cancel")}
                      variant="danger"
                      onPress={() => handleCancel(task.id)}
                    />
                  ) : null}
                  {task.status.toLowerCase() === 'failed' ? (
                    <FluentButton
                      label={t("common.retry")}
                      variant="primary"
                      onPress={() => handleRetry(task.id)}
                    />
                  ) : null}
                </View>
              </FluentCard>
            );
          })
        )}

        {totalPages > 1 ? (
          <View style={styles.pagination}>
            <FluentButton
              label={t('common.previous')}
              variant="secondary"
              onPress={() => setPage(p => Math.max(1, p - 1))}
              disabled={page <= 1 || loading}
            />
            <Text style={styles.pageInfo}>{page} / {totalPages}</Text>
            <FluentButton
              label={t('common.next')}
              variant="secondary"
              onPress={() => setPage(p => Math.min(totalPages, p + 1))}
              disabled={page >= totalPages || loading}
            />
          </View>
        ) : null}
      </ScrollView>

      <Modal
        animationType="fade"
        onRequestClose={() => setResultModalVisible(false)}
        statusBarTranslucent
        transparent
        visible={resultModalVisible}>
        <ModalBackdrop style={styles.backdrop}>
          <View style={[styles.sheet, {paddingBottom: Math.max(insets.bottom, spacing.lg)}]}>
            <FluentTitle>Result</FluentTitle>
            <ScrollView style={styles.resultBox} nestedScrollEnabled>
              <Text style={styles.resultText}>{resultData}</Text>
            </ScrollView>
            <FluentButton
              label={t("common.close")}
              variant="primary"
              onPress={() => setResultModalVisible(false)}
            />
          </View>
        </ModalBackdrop>
      </Modal>
    </ScreenRoot>
  );
}

function createStyles(colors: ThemeColors) {
  return StyleSheet.create({
    content: {gap: spacing.md, paddingBottom: spacing.xl},
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
    chipsRow: {
      flexDirection: 'row',
      gap: spacing.sm,
      paddingVertical: spacing.xs,
    },
    chip: {
      borderRadius: radius.md,
      borderWidth: StyleSheet.hairlineWidth,
      borderColor: colors.border,
      paddingHorizontal: spacing.md,
      paddingVertical: spacing.sm,
    },
    chipText: {
      color: colors.text,
      fontSize: 13,
      fontWeight: '700',
    },
    taskHeader: {
      flexDirection: 'row',
      alignItems: 'center',
      gap: spacing.sm,
    },
    taskName: {
      color: colors.text,
      flex: 1,
      fontSize: 15,
      fontWeight: '800',
    },
    statusBadge: {
      borderRadius: radius.sm,
      paddingHorizontal: spacing.sm,
      paddingVertical: 2,
    },
    statusBadgeText: {
      fontSize: 11,
      fontWeight: '700',
    },
    taskIdText: {
      color: colors.textMuted,
      fontSize: 11,
    },
    badgeRow: {
      flexDirection: 'row',
      gap: spacing.sm,
    },
    infoBadge: {
      borderRadius: radius.sm,
      paddingHorizontal: spacing.sm,
      paddingVertical: 2,
    },
    infoBadgeText: {
      fontSize: 11,
      fontWeight: '700',
    },
    progressRow: {
      flexDirection: 'row',
      alignItems: 'center',
      gap: spacing.sm,
    },
    progressBar: {
      borderRadius: 4,
      flex: 1,
      height: 6,
      overflow: 'hidden',
    },
    progressFill: {
      borderRadius: 4,
      height: '100%',
    },
    progressText: {
      color: colors.textMuted,
      fontSize: 11,
      fontWeight: '700',
      width: 36,
    },
    timestamp: {
      color: colors.textMuted,
      fontSize: 12,
    },
    logSection: {
      gap: spacing.xs,
    },
    logPreview: {
      color: colors.textMuted,
      fontSize: 12,
    },
    logBox: {
      backgroundColor: colors.surfaceMuted,
      borderRadius: radius.sm,
      maxHeight: 200,
      padding: spacing.sm,
    },
    logText: {
      color: colors.text,
      fontFamily: 'monospace',
      fontSize: 11,
    },
    logToggle: {
      color: colors.primary,
      fontSize: 12,
      fontWeight: '700',
    },
    resultRow: {
      flexDirection: 'row',
    },
    taskActions: {
      flexDirection: 'row',
      gap: spacing.sm,
    },
    pagination: {
      alignItems: 'center',
      flexDirection: 'row',
      justifyContent: 'center',
      gap: spacing.md,
      paddingVertical: spacing.md,
    },
    pageInfo: {
      color: colors.text,
      fontSize: 14,
      fontWeight: '700',
    },
    backdrop: {justifyContent: 'flex-end'},
    sheet: {
      backgroundColor: colors.surface,
      borderTopLeftRadius: 14,
      borderTopRightRadius: 14,
      gap: spacing.md,
      padding: spacing.lg,
      width: '100%',
      maxHeight: '70%',
    },
    resultBox: {
      maxHeight: 300,
    },
    resultText: {
      color: colors.text,
      fontFamily: 'monospace',
      fontSize: 12,
    },
  });
}
