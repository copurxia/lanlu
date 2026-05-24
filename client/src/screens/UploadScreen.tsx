import React, {useCallback, useEffect, useMemo, useState} from 'react';
import {
  ActivityIndicator,
  Alert,
  FlatList,
  Modal,
  Pressable,
  ScrollView,
  StyleSheet,
  Text,
  TextInput,
  TouchableOpacity,
  View,
} from 'react-native';
import {pick, types, isErrorWithCode, errorCodes} from '@react-native-documents/picker';
import EventSource from 'react-native-sse';
import notifee, {AndroidImportance} from 'react-native-notify-kit';
import {ArrowUpToLine, Check, CheckCircle, ChevronDown, Download, FileArchive, FolderOpen, X, XCircle} from 'lucide-react-native';
import {useSafeAreaInsets} from 'react-native-safe-area-context';

import {useI18n} from '../i18n';
import {useTheme} from '../theme/ThemeContext';
import {FluentCard, FluentTitle} from '../components/fluent';
import {apiClient, buildApiUrl, extractApiError} from '../api/client';
import {fetchCategories} from '../api/lanlu';
import {getActiveServer} from '../storage/servers';
import {getStoredToken} from '../storage/token';
import {useUploadStore, type DownloadTask, type UploadFile} from '../stores/uploadStore';
import type {Category} from '../types/api';
import {uploadLocalFileChunk} from '../native/LanluMediaProxy';

type TabKey = 'upload' | 'download';

let fileIdCounter = 0;
function nextFileId() { fileIdCounter += 1; return `file_${fileIdCounter}_${Date.now()}`; }
let dlIdCounter = 0;
function nextDlId() { dlIdCounter += 1; return `dl_${dlIdCounter}_${Date.now()}`; }

const sseRegistry = new Map<string, {es: EventSource; close: () => void; retryTimer?: ReturnType<typeof setTimeout>}>();

const UPLOAD_CHANNEL_ID = 'lanlu-upload';
const DOWNLOAD_CHANNEL_ID = 'lanlu-download';
const ARCHIVE_CHUNK_SIZE = 10 * 1024 * 1024;
const SUPPORTED_ARCHIVE_EXTENSIONS = new Set(['zip', 'rar', '7z', 'tar', 'gz', 'pdf', 'epub', 'mobi', 'cbz', 'cbr', 'cb7', 'cbt']);

type TaskDetail = {
  id: number;
  status: string;
  message?: string;
  result?: string;
  progress?: number;
};

async function fetchTaskDetail(taskId: number): Promise<TaskDetail> {
  const response = await apiClient.get<TaskDetail>(`/api/admin/taskpool/${taskId}`);
  return response.data;
}

function isTerminalTaskStatus(status: string | undefined): boolean {
  return status === 'completed' || status === 'failed' || status === 'stopped';
}

function parseFollowUpTaskId(task: TaskDetail, key: string): number {
  if (!task.result) return 0;
  try {
    const payload = JSON.parse(task.result) as Record<string, unknown>;
    return Math.trunc(Number(payload[key] || 0));
  } catch {
    return 0;
  }
}

function parseTaskResult(task: TaskDetail): Record<string, unknown> | null {
  if (!task.result) return null;
  try {
    const parsed = JSON.parse(task.result);
    return parsed && typeof parsed === 'object' ? parsed as Record<string, unknown> : null;
  } catch {
    return null;
  }
}

function isSuccessValue(value: unknown): boolean {
  if (value === true) return true;
  if (typeof value === 'number') return value !== 0;
  if (typeof value === 'string') {
    const normalized = value.trim().toLowerCase();
    return normalized === '1' || normalized === 'true' || normalized === 'ok' || normalized === 'success';
  }
  return false;
}

function getDownloadTaskError(task: TaskDetail): string {
  const result = parseTaskResult(task);
  const resultError = result?.error ?? result?.message;
  if (resultError != null && String(resultError).trim()) {
    return String(resultError);
  }
  return task.message || task.result || 'Download failed';
}

function isDownloadTaskSuccessful(task: TaskDetail): boolean {
  if (task.status !== 'completed') return false;
  const result = parseTaskResult(task);
  if (result && 'success' in result) {
    return isSuccessValue(result.success);
  }
  return true;
}

function appendDownloadLog(dlId: string, delta: string) {
  if (!delta.trim()) return;
  const current = useUploadStore.getState().downloadTasks.find(d => d.id === dlId)?.log || '';
  useUploadStore.getState().updateDownloadTask(dlId, {log: current ? `${current}\n${delta}` : delta});
}

async function applyTerminalDownloadTask(dlId: string, task: TaskDetail): Promise<boolean> {
  if (!isTerminalTaskStatus(task.status)) return false;
  if (isDownloadTaskSuccessful(task)) {
    useUploadStore.getState().updateDownloadTask(dlId, {status: 'success', progress: 100, error: undefined});
    await finishDownloadNotification(dlId, true);
  } else {
    useUploadStore.getState().updateDownloadTask(dlId, {status: 'error', error: getDownloadTaskError(task)});
    await finishDownloadNotification(dlId, false);
  }
  return true;
}

async function hydrateTerminalDownloadTask(taskId: number, dlId: string): Promise<boolean> {
  try {
    const latestTask = await fetchTaskDetail(taskId);
    return await applyTerminalDownloadTask(dlId, latestTask);
  } catch {
    return false;
  }
}

function getFileExtension(fileName: string): string {
  const idx = fileName.lastIndexOf('.');
  return idx >= 0 ? fileName.slice(idx + 1).toLowerCase() : '';
}

async function uploadArchiveChunk(
  file: UploadFile,
  fileBlob: Blob,
  taskId: number,
  chunkIndex: number,
  totalChunks: number,
  start: number,
  end: number,
) {
  const path = `/api/assets/upload/chunk?taskId=${taskId}&chunkIndex=${chunkIndex}&totalChunks=${totalChunks}`;
  const server = await getActiveServer();
  const token = await getStoredToken(server?.id);
  const headers = {
    ...(token ? {Authorization: `Bearer ${token}`} : {}),
    'Content-Type': 'application/octet-stream',
  };
  const uploadedByNative = await uploadLocalFileChunk(
    file.uri,
    await buildApiUrl(path),
    headers,
    start,
    end - start,
  );
  if (uploadedByNative) return;

  const chunkBlob = fileBlob.slice(start, end, file.type || 'application/octet-stream');
  await apiClient.put(
    path,
    chunkBlob,
    {
      headers: {'Content-Type': 'application/octet-stream'},
      timeout: 0,
    },
  );
}

function subscribeTaskSSE(taskId: number, dlId: string, retryAttempt = 0) {
  sseRegistry.get(dlId)?.close();
  sseRegistry.delete(dlId);

  const server = getActiveServer();
  server.then(async srv => {
    const tok = await getStoredToken(srv?.id);
    const baseUrl = srv?.baseUrl || '';
    const streamUrl = `${baseUrl}/api/admin/taskpool/${taskId}/stream`;

    const es = new EventSource(streamUrl, {
      headers: tok ? {Authorization: `Bearer ${tok}`} : {},
    }) as EventSource & {addEventListener(type: string, listener: (e: any) => void): void};

    let closed = false;
    let retryTimer: ReturnType<typeof setTimeout> | undefined;
    const close = () => {
      if (closed) return;
      closed = true;
      if (retryTimer) clearTimeout(retryTimer);
      es.close();
      sseRegistry.delete(dlId);
    };
    sseRegistry.set(dlId, {es, close});

    es.addEventListener('task', (event: any) => {
      if (closed) return;
      try {
        const data = JSON.parse(event.data);
        if (data?.task?.progress != null) {
          const pct = Math.round(Number(data.task.progress));
          useUploadStore.getState().updateDownloadTask(dlId, {progress: pct, error: undefined});
          updateDownloadNotification(dlId, pct);
        }
        const delta = data?.stream?.log_delta;
        if (delta && typeof delta === 'string' && delta.trim()) {
          appendDownloadLog(dlId, delta);
        }
      } catch {}
    });

    // ── done: fetch final task state + close ────────────────────────────
    es.addEventListener('done', async () => {
      if (closed) return;
      close(); // close SSE first, then fetch final state
      const hydrated = await hydrateTerminalDownloadTask(taskId, dlId);
      if (!hydrated) {
        useUploadStore.getState().updateDownloadTask(dlId, {status: 'error', error: 'Failed to load final task state'});
        await finishDownloadNotification(dlId, false);
      }
    });

    es.addEventListener('error', async () => {
      if (closed) return;
      const hydrated = await hydrateTerminalDownloadTask(taskId, dlId);
      if (hydrated || closed) {
        close();
        return;
      }
      const nextAttempt = retryAttempt + 1;
      const delay = Math.min(30000, 2000 * Math.max(1, nextAttempt));
      useUploadStore.getState().updateDownloadTask(dlId, {
        status: 'downloading',
        error: `SSE disconnected; reconnecting in ${Math.round(delay / 1000)}s`,
      });
      es.close();
      retryTimer = setTimeout(() => {
        if (closed) return;
        sseRegistry.delete(dlId);
        subscribeTaskSSE(taskId, dlId, nextAttempt);
      }, delay);
      sseRegistry.set(dlId, {es, close, retryTimer});
    });

    es.addEventListener('ping', () => {});
    es.addEventListener('snapshot', (event: any) => {
      if (closed) return;
      try {
        const data = JSON.parse(event.data);
        if (data?.task?.progress != null) {
          useUploadStore.getState().updateDownloadTask(dlId, {progress: Math.round(Number(data.task.progress)), error: undefined});
        }
        const logTail = data?.stream?.log_tail;
        if (logTail && typeof logTail === 'string') {
          useUploadStore.getState().updateDownloadTask(dlId, {log: logTail});
        }
      } catch {}
    });
  });
}

// ── Task utils ───────────────────────────────────────────────────────────

async function waitForTaskRunning(taskId: number, maxWaitMs = 30 * 60 * 1000) {
  const startedAt = Date.now();
  while (Date.now() - startedAt < maxWaitMs) {
    try {
      const task = await fetchTaskDetail(taskId);
      if (task?.status === 'running') return;
      if (task?.status === 'failed' || task?.status === 'stopped') {
        throw new Error(task?.message || `Task ${taskId} terminal before running`);
      }
    } catch (e: any) {
      if (e.message?.includes('terminal')) throw e;
    }
    await new Promise<void>(resolve => setTimeout(resolve, 1000));
  }
  throw new Error(`Task ${taskId} timed out waiting for running state`);
}

async function waitForTaskTerminal(taskId: number, onUpdate?: (task: TaskDetail) => void, maxWaitMs = 60 * 60 * 1000): Promise<TaskDetail> {
  const startedAt = Date.now();
  while (Date.now() - startedAt < maxWaitMs) {
    const task = await fetchTaskDetail(taskId);
    onUpdate?.(task);
    if (isTerminalTaskStatus(task.status)) {
      return task;
    }
    await new Promise<void>(resolve => setTimeout(resolve, 1000));
  }
  throw new Error(`Task ${taskId} timed out`);
}

async function waitForUploadTaskChain(taskId: number, onProgress?: (progress: number) => void): Promise<TaskDetail> {
  let lastProgress = 0;
  const trackProgress = (task: TaskDetail) => {
    if (typeof task.progress !== 'number') return;
    lastProgress = Math.max(lastProgress, Math.min(100, Math.max(0, task.progress)));
    onProgress?.(lastProgress);
  };

  const uploadTask = await waitForTaskTerminal(taskId, trackProgress);
  if (uploadTask.status !== 'completed') {
    throw new Error(uploadTask.message || `Task ${taskId} ${uploadTask.status}`);
  }

  const processTaskId = parseFollowUpTaskId(uploadTask, 'process_task_id');
  if (processTaskId <= 0) return uploadTask;

  const processTask = await waitForTaskTerminal(processTaskId, trackProgress);
  if (processTask.status !== 'completed') {
    throw new Error(processTask.message || `Task ${processTaskId} ${processTask.status}`);
  }

  const consumeTaskId = parseFollowUpTaskId(processTask, 'consume_task_id');
  if (consumeTaskId <= 0) return processTask;

  const consumeTask = await waitForTaskTerminal(consumeTaskId, trackProgress);
  if (consumeTask.status !== 'completed') {
    throw new Error(consumeTask.message || `Task ${consumeTaskId} ${consumeTask.status}`);
  }
  return consumeTask;
}

// ── Notification helpers ─────────────────────────────────────────────────

const notifyIds = new Map<string, string>(); // task id -> notifee notification id

async function ensureChannels() {
  await notifee.createChannel({id: UPLOAD_CHANNEL_ID, name: 'Upload', importance: AndroidImportance.LOW});
  await notifee.createChannel({id: DOWNLOAD_CHANNEL_ID, name: 'Download', importance: AndroidImportance.LOW});
}

async function showUploadNotification(fileId: string, fileName: string) {
  const id = await notifee.displayNotification({
    title: 'Uploading',
    body: fileName,
    android: {
      channelId: UPLOAD_CHANNEL_ID,
      progress: {max: 100, current: 0, indeterminate: false},
      ongoing: true,
      onlyAlertOnce: true,
    },
  });
  notifyIds.set(fileId, id);
}

async function updateUploadNotification(fileId: string, progress: number) {
  const id = notifyIds.get(fileId);
  if (!id) return;
  await notifee.displayNotification({
    id,
    android: {
      channelId: UPLOAD_CHANNEL_ID,
      progress: {max: 100, current: progress, indeterminate: false},
      ongoing: true,
      onlyAlertOnce: true,
    },
  });
}

async function finishUploadNotification(fileId: string, success: boolean) {
  const id = notifyIds.get(fileId);
  if (!id) return;
  notifyIds.delete(fileId);
  await notifee.displayNotification({
    id,
    title: success ? 'Upload complete' : 'Upload failed',
    android: {
      channelId: UPLOAD_CHANNEL_ID,
      progress: {max: 100, current: success ? 100 : 0, indeterminate: false},
      ongoing: false,
      onlyAlertOnce: false,
    },
  });
}

async function showDownloadNotification(dlId: string, url: string) {
  const id = await notifee.displayNotification({
    title: 'Downloading',
    body: url,
    android: {
      channelId: DOWNLOAD_CHANNEL_ID,
      progress: {max: 100, current: 0, indeterminate: false},
      ongoing: true,
      onlyAlertOnce: true,
    },
  });
  notifyIds.set(dlId, id);
}

async function updateDownloadNotification(dlId: string, progress: number) {
  const id = notifyIds.get(dlId);
  if (!id) return;
  await notifee.displayNotification({
    id,
    android: {
      channelId: DOWNLOAD_CHANNEL_ID,
      progress: {max: 100, current: progress, indeterminate: false},
      ongoing: true,
      onlyAlertOnce: true,
    },
  });
}

async function finishDownloadNotification(dlId: string, success: boolean) {
  const id = notifyIds.get(dlId);
  if (!id) return;
  notifyIds.delete(dlId);
  await notifee.displayNotification({
    id,
    title: success ? 'Download complete' : 'Download failed',
    android: {
      channelId: DOWNLOAD_CHANNEL_ID,
      progress: {max: 100, current: success ? 100 : 0, indeterminate: false},
      ongoing: false,
      onlyAlertOnce: false,
    },
  });
}

// ── Component ────────────────────────────────────────────────────────────

function UploadScreen() {
  const {t} = useI18n();
  const {colors} = useTheme();
  const insets = useSafeAreaInsets();
  const [activeTab, setActiveTab] = useState<TabKey>('upload');

  const [categories, setCategories] = useState<Category[]>([]);
  const [selectedCategoryId, setSelectedCategoryId] = useState<number | null>(null);
  const [categoryPickerOpen, setCategoryPickerOpen] = useState(false);

  const uploadFiles = useUploadStore(s => s.uploadFiles);
  const downloadTasks = useUploadStore(s => s.downloadTasks);
  const addUploadFiles = useUploadStore(s => s.addUploadFiles);
  const updateUploadFile = useUploadStore(s => s.updateUploadFile);
  const removeUploadFile = useUploadStore(s => s.removeUploadFile);
  const addDownloadTask = useUploadStore(s => s.addDownloadTask);
  const updateDownloadTask = useUploadStore(s => s.updateDownloadTask);
  const removeDownloadTask = useUploadStore(s => s.removeDownloadTask);

  const [urlInput, setUrlInput] = useState('');
  const [uploadTitle, setUploadTitle] = useState('');
  const [uploadTags, setUploadTags] = useState('');
  const styles = useMemo(() => createStyles(colors), [colors]);

  useEffect(() => {
    ensureChannels();
    fetchCategories()
      .then(cats => {
        const enabled = cats.filter(c => c.enabled !== false);
        setCategories(enabled);
        setSelectedCategoryId(prev => prev ?? (enabled[0]?.id ?? null));
      })
      .catch(() => {});
  }, []);

  useEffect(() => {
    useUploadStore.getState().downloadTasks.forEach(d => {
      if (d.status === 'downloading' && d.jobId && !sseRegistry.has(d.id)) {
        subscribeTaskSSE(d.jobId, d.id);
      }
    });
  }, []);

  useEffect(() => {
    return () => {
      sseRegistry.forEach(({close}) => close());
      sseRegistry.clear();
    };
  }, []);

  const selectedCategoryName = categories.find(c => c.id === selectedCategoryId)?.name;

  // ── Upload handlers ──────────────────────────────────────────────────────

  const startUpload = useCallback(async (file: UploadFile, overwrite = false) => {
    updateUploadFile(file.id, {status: 'uploading', error: undefined, progress: 0});
    showUploadNotification(file.id, file.name);
    try {
      const chunkSize = ARCHIVE_CHUNK_SIZE;
      const fileResp = await fetch(file.uri);
      if (!fileResp.ok) throw new Error('Failed to read selected file');
      const fileBlob = await fileResp.blob();
      const fileSize = Number(fileBlob.size || file.size || 0);
      if (fileSize <= 0) throw new Error('Selected file is empty');
      if (fileSize !== file.size) {
        updateUploadFile(file.id, {size: fileSize});
      }
      const totalChunks = Math.max(1, Math.ceil(fileSize / chunkSize));

      const initResp = await apiClient.post<{data?: {taskId?: string}}>(
        '/api/assets/upload/init',
        {
          filename: file.name,
          filesize: fileSize,
          chunk_size: chunkSize,
          total_chunks: totalChunks,
          category_id: String(selectedCategoryId ?? ''),
          title: uploadTitle.trim() || file.name.replace(/\\.[^.]+$/, ''),
          tags: uploadTags.trim(),
          target_type: 'archive',
          target_id: '',
          overwrite,
          content_type: file.type || 'application/octet-stream',
        },
      );
      const taskIdStr = initResp.data?.data?.taskId;
      if (!taskIdStr) throw new Error('Failed to init upload');
      const taskId = Number(taskIdStr);

      // Wait for TaskPool to pick up the task (status → running)
      await waitForTaskRunning(taskId);

      for (let i = 0; i < totalChunks; i++) {
        const start = i * chunkSize;
        const end = Math.min(start + chunkSize, fileSize);
        await uploadArchiveChunk(file, fileBlob, taskId, i, totalChunks, start, end);
        const pct = Math.round(Math.min(70, ((i + 1) / totalChunks) * 70));
        updateUploadFile(file.id, {progress: pct});
        updateUploadNotification(file.id, pct);
      }

      await waitForUploadTaskChain(taskId, progress => {
        updateUploadFile(file.id, {progress});
        updateUploadNotification(file.id, progress);
      });
      updateUploadFile(file.id, {status: 'success', progress: 100});
      finishUploadNotification(file.id, true);
    } catch (e: any) {
      const message = extractApiError(e, e.message || t('common.error'));
      if (e?.response?.status === 409 && message.includes('文件已存在')) {
        updateUploadFile(file.id, {status: 'fileExists', error: message, progress: 0});
      } else {
        updateUploadFile(file.id, {status: 'error', error: message});
      }
      finishUploadNotification(file.id, false);
    }
  }, [t, selectedCategoryId, updateUploadFile]);

  const handlePickFiles = useCallback(async () => {
    if (selectedCategoryId === null) {
      Alert.alert(t('common.error'), t('upload.selectCategoryFirst'));
      return;
    }
    try {
      const results = await pick({type: [types.allFiles], allowMultiSelection: true});
      if (results.length === 0) return;

      const newFiles: UploadFile[] = [];
      const unsupported: string[] = [];
      results.forEach(r => {
        const name = r.name || 'unknown';
        const extension = getFileExtension(name);
        const isVolumeSuffix = /^(\d{2,3}|[zr]\d{2})$/.test(extension);
        if (!extension || (!SUPPORTED_ARCHIVE_EXTENSIONS.has(extension) && !isVolumeSuffix)) {
          unsupported.push(extension || name);
          return;
        }
        newFiles.push({
          id: nextFileId(),
          uri: r.uri,
          name,
          size: r.size || 0,
          type: r.type || 'application/octet-stream',
          progress: 0,
          status: 'queued' as const,
        });
      });
      if (unsupported.length > 0) {
        Alert.alert(t('common.error'), t('upload.unsupportedFormat', {format: unsupported.join(', ')}));
      }
      if (newFiles.length === 0) return;
      addUploadFiles(newFiles);
      newFiles.forEach(f => startUpload(f));
    } catch (err: any) {
      if (isErrorWithCode(err) && err.code === errorCodes.OPERATION_CANCELED) return;
      Alert.alert(t('common.error'), err.message || t('common.error'));
    }
  }, [t, selectedCategoryId, addUploadFiles, startUpload]);

  // ── Download handlers ────────────────────────────────────────────────────

  const startDownload = useCallback(async (url: string) => {
    const dlId = nextDlId();
    const task: DownloadTask = {id: dlId, url, progress: 0, log: '', status: 'pending'};
    addDownloadTask(task);
    showDownloadNotification(dlId, url);

    try {
      const resp = await apiClient.post<{success?: number; job?: number; error?: string}>(
        '/api/download_url',
        {url, category_id: selectedCategoryId},
      );

      if (!resp.data?.success) {
        updateDownloadTask(dlId, {status: 'error', error: resp.data?.error || t('common.error')});
        finishDownloadNotification(dlId, false);
        return;
      }

      const taskId = resp.data.job;
      if (!taskId) {
        updateDownloadTask(dlId, {status: 'error', error: 'No task ID returned'});
        finishDownloadNotification(dlId, false);
        return;
      }

      updateDownloadTask(dlId, {status: 'downloading', jobId: taskId});
      subscribeTaskSSE(taskId, dlId);
    } catch (e: any) {
      updateDownloadTask(dlId, {status: 'error', error: e.message || t('common.error')});
      finishDownloadNotification(dlId, false);
    }
  }, [t, selectedCategoryId, addDownloadTask, updateDownloadTask]);

  const handleDownloadUrls = useCallback(() => {
    if (selectedCategoryId === null) {
      Alert.alert(t('common.error'), t('upload.selectCategoryFirst'));
      return;
    }
    const lines = urlInput.split('\n').map(u => u.trim()).filter(u => u.length > 0);
    if (lines.length === 0) return;
    lines.forEach(url => startDownload(url));
    setUrlInput('');
  }, [urlInput, startDownload, selectedCategoryId, t]);

  const handleRemoveDownloadTask = useCallback((id: string) => {
    sseRegistry.get(id)?.close();
    sseRegistry.delete(id);
    removeDownloadTask(id);
  }, [removeDownloadTask]);

  const activeUploadCount = uploadFiles.filter(f => f.status === 'queued' || f.status === 'uploading').length;
  const activeDownloadCount = downloadTasks.filter(d => d.status === 'pending' || d.status === 'downloading').length;

  const renderCategoryRow = () => (
    <TouchableOpacity style={[styles.categoryRow, {borderColor: colors.border, backgroundColor: colors.surface}]} onPress={() => setCategoryPickerOpen(true)}>
      <FolderOpen size={16} color={colors.primary} />
      <Text style={[styles.categoryRowText, {color: selectedCategoryName ? colors.text : colors.textMuted}]} numberOfLines={1}>
        {selectedCategoryName || t('upload.selectCategory')}
      </Text>
      <ChevronDown size={14} color={colors.textMuted} />
    </TouchableOpacity>
  );

  return (
    <View style={[styles.root, {paddingTop: insets.top}]}>
      <View style={styles.header}>
        <FluentTitle>{t('tabs.upload')}</FluentTitle>
      </View>

      <View style={styles.tabBar}>
        <TouchableOpacity style={[styles.tab, activeTab === 'upload' && styles.tabActive]} onPress={() => setActiveTab('upload')}>
          <ArrowUpToLine size={18} color={activeTab === 'upload' ? colors.primary : colors.textMuted} />
          <Text style={[styles.tabLabel, {color: activeTab === 'upload' ? colors.primary : colors.textMuted}]}>{t('upload.uploadTab')}</Text>
          {activeUploadCount > 0 && <View style={[styles.badge, {backgroundColor: colors.primary}]}><Text style={styles.badgeText}>{activeUploadCount}</Text></View>}
        </TouchableOpacity>
        <TouchableOpacity style={[styles.tab, activeTab === 'download' && styles.tabActive]} onPress={() => setActiveTab('download')}>
          <Download size={18} color={activeTab === 'download' ? colors.primary : colors.textMuted} />
          <Text style={[styles.tabLabel, {color: activeTab === 'download' ? colors.primary : colors.textMuted}]}>{t('upload.downloadTab')}</Text>
          {activeDownloadCount > 0 && <View style={[styles.badge, {backgroundColor: colors.primary}]}><Text style={styles.badgeText}>{activeDownloadCount}</Text></View>}
        </TouchableOpacity>
      </View>

      <ScrollView style={styles.content} contentContainerStyle={styles.contentInner} keyboardShouldPersistTaps="handled">
        {activeTab === 'upload' ? (
          <>
            <FluentCard style={styles.card}>
              {renderCategoryRow()}

              <TouchableOpacity style={styles.filePickerArea} onPress={handlePickFiles} activeOpacity={0.7}>
                <FileArchive size={40} color={colors.textMuted} />
                <Text style={styles.filePickerHint}>{t('upload.selectFileHint')}</Text>
                <Text style={styles.filePickerSubHint}>{t('upload.multiFileHint')}</Text>
              </TouchableOpacity>

              <TextInput
                style={[styles.metaInput, {color: colors.text, borderColor: colors.border, backgroundColor: colors.surface}]}
                value={uploadTitle}
                onChangeText={setUploadTitle}
                placeholder={t('upload.titlePlaceholder')}
                placeholderTextColor={colors.textMuted}
              />
              <TextInput
                style={[styles.metaInput, {color: colors.text, borderColor: colors.border, backgroundColor: colors.surface}]}
                value={uploadTags}
                onChangeText={setUploadTags}
                placeholder={t('upload.tagsPlaceholder')}
                placeholderTextColor={colors.textMuted}
              />
            </FluentCard>

            {uploadFiles.map(file => (
              <FluentCard key={file.id} style={styles.taskCard}>
                <View style={styles.taskRow}>
                  <FileArchive size={20} color={colors.primary} style={{marginTop: 2}} />
                  <View style={styles.taskInfo}>
                    <Text style={styles.taskName} numberOfLines={1}>{file.name}</Text>
                    <Text style={styles.taskSize}>{formatFileSize(file.size)}</Text>
                    {file.progress > 0 && file.progress < 100 && (
                      <View style={styles.progressRow}>
                        <View style={styles.progressTrack}><View style={[styles.progressFill, {width: `${file.progress}%`, backgroundColor: colors.primary}]} /></View>
                        <Text style={styles.progressText}>{file.progress}%</Text>
                      </View>
                    )}
                    {file.error ? <Text style={[styles.taskError, {color: colors.danger}]}>{file.error}</Text> : null}
                    {file.status === 'fileExists' && (
                      <TouchableOpacity
                        style={[styles.inlineActionBtn, {borderColor: colors.primary}]}
                        onPress={() => startUpload(file, true)}>
                        <Text style={[styles.inlineActionText, {color: colors.primary}]}>{t('upload.overwrite')}</Text>
                      </TouchableOpacity>
                    )}
                  </View>
                  <View style={styles.taskStatus}>
                    {file.status === 'uploading' ? <ActivityIndicator size="small" color={colors.primary} /> : null}
                    {file.status === 'error' ? <XCircle size={20} color={colors.danger} /> : null}
                    {file.status === 'fileExists' ? <XCircle size={20} color={colors.danger} /> : null}
                    {file.status === 'success' ? <CheckCircle size={20} color={colors.success} /> : null}
                    {(file.status === 'error' || file.status === 'fileExists' || file.status === 'success') && (
                      <TouchableOpacity onPress={() => removeUploadFile(file.id)} hitSlop={8}><X size={16} color={colors.textMuted} /></TouchableOpacity>
                    )}
                  </View>
                </View>
              </FluentCard>
            ))}
          </>
        ) : (
          <>
            <FluentCard style={styles.card}>
              {renderCategoryRow()}

              <Text style={styles.label}>{t('upload.urlLabel')}</Text>
              <TextInput
                style={[styles.textArea, {color: colors.text, borderColor: colors.border, backgroundColor: colors.surface}]}
                value={urlInput}
                onChangeText={setUrlInput}
                placeholder={t('upload.urlPlaceholderMulti')}
                placeholderTextColor={colors.textMuted}
                autoCapitalize="none" autoCorrect={false}
                multiline numberOfLines={5} textAlignVertical="top"
              />
              <TouchableOpacity
                style={[styles.actionBtn, {backgroundColor: urlInput.trim() ? colors.primary : colors.primaryMuted}]}
                onPress={handleDownloadUrls} disabled={!urlInput.trim()}>
                <Download size={18} color="#fff" />
                <Text style={styles.actionBtnText}>{t('upload.startDownload')}</Text>
              </TouchableOpacity>
            </FluentCard>

            {downloadTasks.map(task => (
              <FluentCard key={task.id} style={styles.taskCard}>
                <View style={styles.taskRow}>
                  <Download size={18} color={colors.primary} style={{marginTop: 2}} />
                  <View style={styles.taskInfo}>
                    <Text style={styles.taskUrl} numberOfLines={1}>{task.url}</Text>
                    {task.progress > 0 && (
                      <View style={styles.progressRow}>
                        <View style={styles.progressTrack}><View style={[styles.progressFill, {width: `${task.progress}%`, backgroundColor: colors.primary}]} /></View>
                        <Text style={styles.progressText}>{task.progress}%</Text>
                      </View>
                    )}
                    {task.log ? (
                      <ScrollView style={[styles.taskLog, {backgroundColor: colors.surface, borderColor: colors.border}]} nestedScrollEnabled>
                        <Text style={styles.taskLogText} selectable>{task.log}</Text>
                      </ScrollView>
                    ) : null}
                    {task.error ? <Text style={[styles.taskError, {color: colors.danger}]}>{task.error}</Text> : null}
                  </View>
                  <View style={styles.taskStatus}>
                    {task.status === 'downloading' ? <ActivityIndicator size="small" color={colors.primary} /> : null}
                    {task.status === 'error' ? <XCircle size={20} color={colors.danger} /> : null}
                    {task.status === 'success' ? <CheckCircle size={20} color={colors.success} /> : null}
                    {(task.status === 'error' || task.status === 'success') && (
                      <TouchableOpacity onPress={() => handleRemoveDownloadTask(task.id)} hitSlop={8}><X size={16} color={colors.textMuted} /></TouchableOpacity>
                    )}
                  </View>
                </View>
              </FluentCard>
            ))}
          </>
        )}
      </ScrollView>

      <Modal visible={categoryPickerOpen} transparent animationType="fade" onRequestClose={() => setCategoryPickerOpen(false)}>
        <Pressable style={styles.modalOverlay} onPress={() => setCategoryPickerOpen(false)}>
          <View style={[styles.modalContent, {backgroundColor: colors.surface}]}>
            <Text style={[styles.modalTitle, {color: colors.text}]}>{t('upload.selectCategory')}</Text>
            <FlatList
              data={categories}
              keyExtractor={item => String(item.id)}
              renderItem={({item}) => (
                <TouchableOpacity
                  style={[styles.categoryItem, item.id === selectedCategoryId && {backgroundColor: colors.primaryMuted}]}
                  onPress={() => { setSelectedCategoryId(item.id); setCategoryPickerOpen(false); }}>
                  <Text style={[styles.categoryItemName, {color: colors.text}]}>{item.name}</Text>
                  {item.id === selectedCategoryId && <Check size={18} color={colors.primary} />}
                </TouchableOpacity>
              )}
              style={styles.categoryList}
            />
          </View>
        </Pressable>
      </Modal>
    </View>
  );
}

function formatFileSize(bytes: number): string {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  if (bytes < 1024 * 1024 * 1024) return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
  return `${(bytes / (1024 * 1024 * 1024)).toFixed(2)} GB`;
}

function createStyles(colors: any) {
  return StyleSheet.create({
    root: {flex: 1, backgroundColor: colors.background},
    header: {paddingHorizontal: 20, paddingTop: 8, paddingBottom: 4},
    tabBar: {flexDirection: 'row', marginHorizontal: 16, marginTop: 8, borderRadius: 10, backgroundColor: colors.surface, padding: 4},
    tab: {flex: 1, flexDirection: 'row', alignItems: 'center', justifyContent: 'center', gap: 6, paddingVertical: 10, borderRadius: 8},
    tabActive: {backgroundColor: colors.primaryMuted},
    tabLabel: {fontSize: 14, fontWeight: '600'},
    badge: {borderRadius: 10, minWidth: 20, height: 20, alignItems: 'center', justifyContent: 'center', paddingHorizontal: 5},
    badgeText: {color: '#fff', fontSize: 11, fontWeight: '700'},
    content: {flex: 1},
    contentInner: {padding: 16, paddingBottom: 100, gap: 12},
    card: {padding: 20, gap: 16},
    taskCard: {padding: 14, gap: 10},
    categoryRow: {flexDirection: 'row', alignItems: 'center', paddingHorizontal: 14, paddingVertical: 10, borderRadius: 10, borderWidth: 1, gap: 8},
    categoryRowText: {flex: 1, fontSize: 13, fontWeight: '500'},
    filePickerArea: {alignItems: 'center', justifyContent: 'center', paddingVertical: 40, borderWidth: 2, borderColor: colors.border, borderStyle: 'dashed', borderRadius: 12, gap: 10},
    filePickerHint: {fontSize: 15, color: colors.textMuted, textAlign: 'center'},
    metaInput: {borderWidth: 1, borderRadius: 10, paddingHorizontal: 14, paddingVertical: 10, fontSize: 14},
    filePickerSubHint: {fontSize: 12, color: colors.textMuted, textAlign: 'center', opacity: 0.6},
    taskRow: {flexDirection: 'row', gap: 12},
    taskInfo: {flex: 1, gap: 4},
    taskName: {fontSize: 14, fontWeight: '600', color: colors.text},
    taskUrl: {fontSize: 13, fontWeight: '500', color: colors.text},
    taskSize: {fontSize: 12, color: colors.textMuted},
    taskStatus: {alignItems: 'center', gap: 6, justifyContent: 'center'},
    progressRow: {flexDirection: 'row', alignItems: 'center', gap: 8, marginTop: 4},
    progressTrack: {flex: 1, height: 5, borderRadius: 3, backgroundColor: colors.border, overflow: 'hidden'},
    progressFill: {height: '100%', borderRadius: 3},
    progressText: {fontSize: 11, fontWeight: '600', color: colors.textMuted, minWidth: 30, textAlign: 'right'},
    taskError: {fontSize: 12, marginTop: 2},
    inlineActionBtn: {alignSelf: 'flex-start', marginTop: 8, paddingHorizontal: 10, paddingVertical: 6, borderRadius: 8, borderWidth: 1},
    inlineActionText: {fontSize: 12, fontWeight: '700'},
    taskLog: {maxHeight: 120, borderRadius: 8, borderWidth: 1, padding: 8, marginTop: 4},
    taskLogText: {fontSize: 11, fontFamily: 'monospace', lineHeight: 16, color: colors.text},
    label: {fontSize: 14, fontWeight: '600', color: colors.text, marginBottom: -8},
    textArea: {borderWidth: 1, borderRadius: 10, paddingHorizontal: 14, paddingTop: 12, paddingBottom: 12, fontSize: 14, minHeight: 100},
    actionBtn: {flexDirection: 'row', alignItems: 'center', justifyContent: 'center', gap: 8, paddingVertical: 14, borderRadius: 10},
    actionBtnText: {color: '#fff', fontSize: 15, fontWeight: '600'},
    modalOverlay: {flex: 1, backgroundColor: 'rgba(0,0,0,0.4)', justifyContent: 'flex-end'},
    modalContent: {maxHeight: '60%', borderTopLeftRadius: 16, borderTopRightRadius: 16, paddingTop: 16, paddingBottom: 40},
    modalTitle: {fontSize: 16, fontWeight: '700', paddingHorizontal: 20, marginBottom: 12},
    categoryList: {maxHeight: 400},
    categoryItem: {flexDirection: 'row', alignItems: 'center', paddingHorizontal: 20, paddingVertical: 14, gap: 12},
    categoryItemName: {flex: 1, fontSize: 15},
  });
}

export {UploadScreen};
