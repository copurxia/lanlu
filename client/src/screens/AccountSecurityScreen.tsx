import React, {useCallback, useEffect, useMemo, useRef, useState} from 'react';
import {
  Alert,
  Dimensions,
  Modal,
  PanResponder,
  Platform,
  ScrollView,
  Share,
  StyleSheet,
  Text,
  TextInput,
  TouchableOpacity,
  View,
} from 'react-native';
import {
  ArrowLeft,
  Check,
  Copy,
  Download,
  KeyRound,
  LogOut,
  Plus,
  QrCode,
  RefreshCw,
  ShieldCheck,
  Trash2,
  User,
  X,
} from 'lucide-react-native';
import {useSafeAreaInsets} from 'react-native-safe-area-context';
import {useNavigation} from '@react-navigation/native';
import QRCode from 'react-native-qrcode-svg';

import * as LanluApi from '../api/lanlu';
import {useAuth} from '../auth/AuthContext';
import {
  ModalBackdrop,
  ScreenRoot,
  screenSafeAreaPadding,
} from '../components/SafeAreaSurface';
import {FluentButton, FluentCaption, FluentCard, FluentTextField, FluentTitle} from '../components/fluent';
import {useI18n} from '../i18n';
import {PasskeyModule} from '../native/PasskeyModule';
import {shareLocalTextFile} from '../native/LanluMediaProxy';
import {apiClient, buildAuthorizedAssetImageSource, extractApiError} from '../api/client';
import FastImage, {type Source as FastImageSource} from '@d11/react-native-fast-image';
import {launchImageLibrary} from 'react-native-image-picker';
import {spacing, radius, type ThemeColors} from '../theme/colors';
import {useTheme} from '../theme/ThemeContext';
import type {
  ApiEnvelope,
  AuthSession,
  AuthToken,
  AuthTokenFull,
  PasskeyCredential,
  TotpEnrollmentPayload,
  TotpStatus,
} from '../types/api';

type TaskDetail = {
  id: number;
  status: string;
  message?: string;
  result?: string;
  progress?: number;
};

const AVATAR_UPLOAD_CHUNK_SIZE = 10 * 1024 * 1024;
const TASK_POLL_INTERVAL_MS = 1000;
const TASK_POLL_TIMEOUT_MS = 30 * 60 * 1000;

function delay(ms: number) {
  return new Promise<void>(resolve => setTimeout(resolve, ms));
}

function formatDateTime(value?: string, fallback = '-'): string {
  if (!value) return fallback;
  try {
    const d = new Date(value);
    if (isNaN(d.getTime())) return fallback;
    return d.toLocaleString();
  } catch {
    return fallback;
  }
}

async function fetchTaskDetail(taskId: number): Promise<TaskDetail> {
  const response = await apiClient.get<TaskDetail>(`/api/admin/taskpool/${taskId}`);
  return response.data;
}

async function waitForTaskStatus(
  taskId: number,
  predicate: (task: TaskDetail) => boolean,
  timeoutMs = TASK_POLL_TIMEOUT_MS,
): Promise<TaskDetail> {
  const startedAt = Date.now();
  while (Date.now() - startedAt < timeoutMs) {
    const task = await fetchTaskDetail(taskId);
    if (predicate(task)) {
      return task;
    }
    if (task.status === 'failed' || task.status === 'stopped') {
      throw new Error(task.message || `Task ${taskId} failed`);
    }
    await delay(TASK_POLL_INTERVAL_MS);
  }
  throw new Error(`Task ${taskId} timed out`);
}

function parseFollowUpTaskId(task: TaskDetail, key: 'process_task_id' | 'consume_task_id'): number {
  if (!task.result) return 0;
  try {
    const payload = JSON.parse(task.result) as Record<string, unknown>;
    return Math.trunc(Number(payload[key] || 0));
  } catch {
    return 0;
  }
}

async function waitForTaskChain(taskId: number): Promise<void> {
  const initTask = await waitForTaskStatus(
    taskId,
    task => task.status === 'completed',
  );
  let nextTaskId = parseFollowUpTaskId(initTask, 'process_task_id');
  if (nextTaskId <= 0) {
    return;
  }

  const processTask = await waitForTaskStatus(
    nextTaskId,
    task => task.status === 'completed',
  );
  nextTaskId = parseFollowUpTaskId(processTask, 'consume_task_id');
  if (nextTaskId <= 0) {
    return;
  }

  await waitForTaskStatus(
    nextTaskId,
    task => task.status === 'completed',
  );
}

export function AccountSecurityScreen() {
  const {t} = useI18n();
  const {colors} = useTheme();
  const {user, signOut, refreshMe, isOffline} = useAuth();
  const insets = useSafeAreaInsets();
  const navigation = useNavigation();
  const styles = useMemo(() => createStyles(colors), [colors]);

  const [loading, setLoading] = useState(false);

  // Change credentials
  const [newUsername, setNewUsername] = useState('');
  const [newPassword, setNewPassword] = useState('');
  const [confirmPassword, setConfirmPassword] = useState('');

  // TOTP
  const [totpStatus, setTotpStatus] = useState<TotpStatus | null>(null);
  const [totpLoading, setTotpLoading] = useState(false);
  const [enrollingTotp, setEnrollingTotp] = useState(false);
  const [confirmingTotp, setConfirmingTotp] = useState(false);
  const [disablingTotp, setDisablingTotp] = useState(false);
  const [regeneratingRecoveryCodes, setRegeneratingRecoveryCodes] = useState(false);
  const [totpEnrollment, setTotpEnrollment] = useState<TotpEnrollmentPayload | null>(null);
  const [totpName, setTotpName] = useState('');
  const [totpCode, setTotpCode] = useState('');
  const [recoveryCodes, setRecoveryCodes] = useState<string[]>([]);

  // Passkeys
  const [passkeys, setPasskeys] = useState<PasskeyCredential[]>([]);
  const [passkeysLoading, setPasskeysLoading] = useState(false);
  const [passkeySupported, setPasskeySupported] = useState(false);
  const [registeringPasskey, setRegisteringPasskey] = useState(false);
  const [newPasskeyName, setNewPasskeyName] = useState('');

  // Sessions
  const [sessions, setSessions] = useState<AuthSession[]>([]);
  const [sessionsLoading, setSessionsLoading] = useState(false);

  // Tokens
  const [tokens, setTokens] = useState<AuthToken[]>([]);
  const [tokensLoading, setTokensLoading] = useState(false);
  const [newTokenName, setNewTokenName] = useState('');
  const [newTokenValue, setNewTokenValue] = useState<string | null>(null);

  // Step-up modal
  const [stepUpOpen, setStepUpOpen] = useState(false);
  const [stepUpMethods, setStepUpMethods] = useState<string[]>([]);
  const [stepUpMethod, setStepUpMethod] = useState<'password' | 'totp' | 'passkey'>('password');
  const [stepUpPassword, setStepUpPassword] = useState('');
  const [stepUpTotpCode, setStepUpTotpCode] = useState('');
  const [stepUpRecoveryCode, setStepUpRecoveryCode] = useState('');
  const [stepUpMode, setStepUpMode] = useState<'totp' | 'recovery'>('totp');
  const [stepUpLoading, setStepUpLoading] = useState(false);
  const [stepUpError, setStepUpError] = useState<string | null>(null);
  const stepUpResolverRef = useRef<((verified: boolean) => void) | null>(null);

  // Avatar
  const [avatarSource, setAvatarSource] = useState<FastImageSource | null>(null);
  const [avatarLoading, setAvatarLoading] = useState(false);
  const [avatarDialogOpen, setAvatarDialogOpen] = useState(false);
  const [selectedImageUri, setSelectedImageUri] = useState<string | null>(null);
  const [selectedImageName, setSelectedImageName] = useState('');
  const [selectedImageType, setSelectedImageType] = useState('');
  const [avatarZoom, setAvatarZoom] = useState(1);
  const [avatarPan, setAvatarPan] = useState({x: 0, y: 0});
  const avatarPanRef = useRef({x: 0, y: 0});
  const dragStartRef = useRef({x: 0, y: 0});
  const sliderWidthRef = useRef(200);

  useEffect(() => {
    const supported = PasskeyModule.isSupported();
    setPasskeySupported(supported);
      if (!supported) {
        Alert.alert(t('auth.passkeyManagement'), t('auth.passkeyUnavailable'));
      }
  }, [t]);

  const showError = useCallback((msg: string) => {
    Alert.alert(t('common.error'), msg);
  }, [t]);

  const showSuccess = useCallback((msg: string) => {
    Alert.alert('', msg);
  }, [t]);

  const requestStepUp = useCallback(async (): Promise<boolean> => {
    try {
      const resp = await LanluApi.getStepUpOptions();
      const methods = resp.data?.methods || ['password'];
      setStepUpMethods(methods);
      if (methods.includes('passkey') && passkeySupported) {
        setStepUpMethod('passkey');
      } else if (methods.includes('totp')) {
        setStepUpMethod('totp');
      } else {
        setStepUpMethod('password');
      }
      setStepUpPassword('');
      setStepUpTotpCode('');
      setStepUpRecoveryCode('');
      setStepUpMode('totp');
      setStepUpError(null);

      return new Promise<boolean>(resolve => {
        stepUpResolverRef.current = resolve;
        setStepUpOpen(true);
      });
    } catch {
      return false;
    }
  }, [passkeySupported]);

  const closeStepUp = useCallback((verified: boolean) => {
    setStepUpOpen(false);
    stepUpResolverRef.current?.(verified);
    stepUpResolverRef.current = null;
  }, []);

  const verifyStepUp = useCallback(async () => {
    setStepUpLoading(true);
    setStepUpError(null);
    try {
      if (stepUpMethod === 'password') {
        await LanluApi.verifyStepUpPassword(stepUpPassword);
      } else if (stepUpMethod === 'totp') {
        await LanluApi.verifyStepUpTotp({
          code: stepUpMode === 'totp' ? stepUpTotpCode : undefined,
          recoveryCode: stepUpMode === 'recovery' ? stepUpRecoveryCode : undefined,
        });
      } else {
        const optionsResp = await LanluApi.getWebauthnStepUpOptions();
        const optsData = optionsResp.data!;
        const credential = await PasskeyModule.authenticate(optsData.publicKey);
        await LanluApi.verifyWebauthnStepUp({
          challengeId: optsData.challengeId,
          credential,
        });
      }
      closeStepUp(true);
    } catch (e) {
      setStepUpError(t('auth.stepUpFailed'));
    } finally {
      setStepUpLoading(false);
    }
  }, [stepUpMethod, stepUpPassword, stepUpMode, stepUpTotpCode, stepUpRecoveryCode, closeStepUp, t]);

  // ─── Data loading ──────────────────────────────────────────────

  const loadTotpStatus = useCallback(async () => {
    setTotpLoading(true);
    try {
      const resp = await LanluApi.getTotpStatus();
      setTotpStatus(resp.data ?? null);
    } catch {
      // silent
    } finally {
      setTotpLoading(false);
    }
  }, []);

  const loadPasskeys = useCallback(async () => {
    if (!passkeySupported) return;
    setPasskeysLoading(true);
    try {
      const resp = await LanluApi.listPasskeyCredentials();
      setPasskeys(resp.data?.credentials || []);
    } catch {
      // silent
    } finally {
      setPasskeysLoading(false);
    }
  }, [passkeySupported]);

  const loadSessions = useCallback(async () => {
    setSessionsLoading(true);
    try {
      const resp = await LanluApi.listSessions();
      setSessions(resp.data?.sessions || []);
    } catch {
      // ignore
    } finally {
      setSessionsLoading(false);
    }
  }, []);

  const loadTokens = useCallback(async () => {
    setTokensLoading(true);
    try {
      const resp = await LanluApi.listTokens();
      setTokens(resp.data?.tokens || []);
    } catch {
      // ignore
    } finally {
      setTokensLoading(false);
    }
  }, []);

  useEffect(() => {
    loadTotpStatus();
    loadPasskeys();
    loadSessions();
    loadTokens();
  }, [loadTotpStatus, loadPasskeys, loadSessions, loadTokens]);

  useEffect(() => {
    if (user?.avatarAssetId) {
      buildAuthorizedAssetImageSource(user.avatarAssetId).then(setAvatarSource);
    } else {
      setAvatarSource(null);
    }
  }, [user?.avatarAssetId]);

  // ─── Change credentials ────────────────────────────────────────

  const canChangeUsername = newUsername.length >= 3 && newUsername !== user?.username;
  const canChangePassword = newPassword.length >= 6 && newPassword === confirmPassword;
  const canSave = canChangeUsername || canChangePassword;

  const handleSaveCredentials = async () => {
    if (!canSave) return;
    setLoading(true);
    try {
      if (canChangeUsername) {
        await LanluApi.changeUsername(newUsername);
        setNewUsername('');
      }
      if (canChangePassword) {
        if (!(await requestStepUp())) return;
        await LanluApi.changePassword(newPassword);
        setNewPassword('');
        setConfirmPassword('');
        await signOut();
        return;
      }
      showSuccess(t('auth.credentialsUpdated'));
    } catch (e) {
      showError(extractApiError(e, t('settings.signOutTitle')));
    } finally {
      setLoading(false);
    }
  };

  // ─── TOTP ──────────────────────────────────────────────────────

  const startTotpEnrollment = async () => {
    setEnrollingTotp(true);
    try {
      if (!(await requestStepUp())) return;
      const resp = await LanluApi.startTotpEnrollment(totpName);
      if (resp.data) setTotpEnrollment(resp.data);
      setRecoveryCodes([]);
    } catch {
      showError(t('auth.totpEnrollStartFailed'));
    } finally {
      setEnrollingTotp(false);
    }
  };

  const confirmTotpEnrollment = async () => {
    if (!totpEnrollment || !totpCode.trim()) return;
    setConfirmingTotp(true);
    try {
      const resp = await LanluApi.confirmTotpEnrollment({
        challengeId: totpEnrollment.challengeId,
        code: totpCode.trim(),
        name: totpName,
      });
      setRecoveryCodes(resp.data?.recoveryCodes || []);
      setTotpEnrollment(null);
      setTotpCode('');
      await loadTotpStatus();
      showSuccess(t('auth.totpEnabled'));
    } catch {
      showError(t('auth.totpConfirmFailed'));
    } finally {
      setConfirmingTotp(false);
    }
  };

  const regenerateTotpRecoveryCodes = async () => {
    if (!totpCode.trim()) return;
    setRegeneratingRecoveryCodes(true);
    try {
      if (!(await requestStepUp())) return;
      const resp = await LanluApi.regenerateRecoveryCodes(totpCode.trim());
      setRecoveryCodes(resp.data?.recoveryCodes || []);
      setTotpCode('');
      await loadTotpStatus();
      showSuccess(t('auth.totpRecoveryCodesRegenerated'));
    } catch {
      showError(t('auth.totpRecoveryCodesRegenerateFailed'));
    } finally {
      setRegeneratingRecoveryCodes(false);
    }
  };

  const disableTotp = async () => {
    setDisablingTotp(true);
    try {
      if (!(await requestStepUp())) return;
      await LanluApi.disableTotp();
      setRecoveryCodes([]);
      setTotpEnrollment(null);
      setTotpCode('');
      await loadTotpStatus();
      showSuccess(t('auth.totpDisabled'));
    } catch {
      showError(t('auth.totpDisableFailed'));
    } finally {
      setDisablingTotp(false);
    }
  };

  const copyRecoveryCodes = async () => {
    if (recoveryCodes.length === 0) return;
    try {
      await Share.share({message: recoveryCodes.join('\n')});
    } catch {
      // ignore
    }
  };

  const downloadRecoveryCodes = async () => {
    if (recoveryCodes.length === 0) return;
    try {
      const sharedUri = await shareLocalTextFile(
        recoveryCodes.join('\n'),
        'txt',
        'lanlu-totp-recovery-codes',
        t('auth.recoveryCodes'),
      );
      if (!sharedUri) {
        await Share.share({
          title: t('auth.recoveryCodes'),
          message: recoveryCodes.join('\n'),
        });
      }
    } catch {
      // ignore
    }
  };

  // ─── Passkeys ──────────────────────────────────────────────────

  const registerPasskey = async () => {
    if (!passkeySupported) return;
    setRegisteringPasskey(true);
    try {
      if (!(await requestStepUp())) return;
      const optionsResp = await LanluApi.getWebauthnRegisterOptions();
      const regData = optionsResp.data!;
      const credential = await PasskeyModule.register(regData.publicKey);
      await LanluApi.verifyWebauthnRegistration({
        challengeId: regData.challengeId,
        name: newPasskeyName.trim(),
        credential,
      });
      setNewPasskeyName('');
      await loadPasskeys();
      showSuccess(t('auth.passkeyRegistered'));
    } catch {
      showError(t('auth.passkeyRegisterFailed'));
    } finally {
      setRegisteringPasskey(false);
    }
  };

  const revokePasskey = (id: number) => {
    Alert.alert(
      t('auth.confirmDeletePasskeyTitle'),
      t('auth.confirmDeletePasskeyDescription'),
      [
        {text: t('common.cancel'), style: 'cancel'},
        {
          text: t('common.delete'),
          style: 'destructive',
          onPress: async () => {
            setLoading(true);
            try {
              if (!(await requestStepUp())) return;
              await LanluApi.revokePasskeyCredential(id);
              await loadPasskeys();
              showSuccess(t('auth.passkeyDeleted'));
            } catch {
              showError(t('auth.passkeyDeleteFailed'));
            } finally {
              setLoading(false);
            }
          },
        },
      ],
    );
  };

  // ─── Sessions ──────────────────────────────────────────────────

  const revokeSession = (session: AuthSession) => {
    Alert.alert(
      session.current
        ? t('auth.confirmLogoutCurrentSessionTitle')
        : t('auth.confirmRevokeSessionTitle'),
      session.current
        ? t('auth.confirmLogoutCurrentSessionDescription')
        : t('auth.confirmRevokeSessionDescription'),
      [
        {text: t('common.cancel'), style: 'cancel'},
        {
          text: session.current ? t('auth.logout') : t('auth.revokeSession'),
          style: 'destructive',
          onPress: async () => {
            setLoading(true);
            try {
              await LanluApi.revokeSession(session.id);
              if (session.current) {
                await signOut();
                return;
              }
              await loadSessions();
            } catch {
              // ignore
            } finally {
              setLoading(false);
            }
          },
        },
      ],
    );
  };

  const revokeOtherSessions = () => {
    Alert.alert(
      t('auth.confirmRevokeOtherSessionsTitle'),
      t('auth.confirmRevokeOtherSessionsDescription'),
      [
        {text: t('common.cancel'), style: 'cancel'},
        {
          text: t('auth.revokeOtherSessions'),
          style: 'destructive',
          onPress: async () => {
            setLoading(true);
            try {
              await LanluApi.revokeOtherSessions();
              await loadSessions();
              showSuccess(t('auth.otherSessionsRevoked'));
            } catch {
              showError(t('auth.revokeOtherSessionsFailed'));
            } finally {
              setLoading(false);
            }
          },
        },
      ],
    );
  };

  // ─── Tokens ────────────────────────────────────────────────────

  const createToken = async () => {
    if (!newTokenName.trim()) return;
    setLoading(true);
    setNewTokenValue(null);
    try {
      const resp = await LanluApi.createToken(newTokenName.trim());
      setNewTokenValue(resp.data?.token?.token || null);
      setNewTokenName('');
      await loadTokens();
    } catch {
      showError(t('auth.confirmRevokeTokenTitle'));
    } finally {
      setLoading(false);
    }
  };

  const revokeToken = (token: AuthToken) => {
    Alert.alert(
      t('auth.confirmRevokeTokenTitle'),
      t('auth.confirmRevokeTokenDescription'),
      [
        {text: t('common.cancel'), style: 'cancel'},
        {
          text: t('auth.revokeToken'),
          style: 'destructive',
          onPress: async () => {
            setLoading(true);
            try {
              await LanluApi.revokeToken(token.id);
              await loadTokens();
            } catch {
              // ignore
            } finally {
              setLoading(false);
            }
          },
        },
      ],
    );
  };

  // ─── Confirm sign out ──────────────────────────────────────────

  const confirmSignOut = () => {
    Alert.alert(t('settings.signOutTitle'), t('settings.signOutMessage'), [
      {text: t('common.cancel'), style: 'cancel'},
      {
        text: t('settings.signOut'),
        style: 'destructive',
        onPress: () => signOut().catch(() => {}),
      },
    ]);
  };

  const handlePickAvatar = useCallback(async () => {
    const result = await launchImageLibrary({mediaType: 'photo', quality: 0.8});
    if (result.assets?.[0]?.uri) {
      setSelectedImageUri(result.assets[0].uri);
      setSelectedImageName(result.assets[0].fileName || 'avatar.jpg');
      setSelectedImageType(result.assets[0].type || 'image/jpeg');
      setAvatarZoom(1);
      setAvatarPan({x: 0, y: 0});
      avatarPanRef.current = {x: 0, y: 0};
      setAvatarDialogOpen(true);
    }
  }, []);

  const handleUploadAvatar = useCallback(async () => {
    if (!selectedImageUri) return;
    setAvatarLoading(true);
    try {
      const fileResponse = await fetch(selectedImageUri);
      if (!fileResponse.ok) {
        throw new Error('Failed to read selected image');
      }
      const fileBlob = await fileResponse.blob();
      const fileSize = Number(fileBlob.size || 0);
      if (fileSize <= 0) {
        throw new Error('Selected image is empty');
      }

      const chunkSize = AVATAR_UPLOAD_CHUNK_SIZE;
      const totalChunks = Math.max(1, Math.ceil(fileSize / chunkSize));
      const initResp = await apiClient.post<ApiEnvelope<{taskId: string}>>('/api/assets/upload/init', {
        filename: selectedImageName || 'avatar.jpg',
        filesize: fileSize,
        chunk_size: chunkSize,
        total_chunks: totalChunks,
        target_type: 'user_avatar',
        target_id: '',
        overwrite: true,
        content_type: selectedImageType || fileBlob.type || 'image/jpeg',
      });
      const taskId = Number(initResp.data?.data?.taskId || 0);
      if (!taskId) {
        throw new Error('Failed to initialize avatar upload');
      }

      await waitForTaskStatus(taskId, task => task.status === 'running');
      for (let chunkIndex = 0; chunkIndex < totalChunks; chunkIndex += 1) {
        const start = chunkIndex * chunkSize;
        const end = Math.min(start + chunkSize, fileSize);
        const chunk = fileBlob.slice(start, end, selectedImageType || fileBlob.type || 'image/jpeg');
        await apiClient.put(
          `/api/assets/upload/chunk?taskId=${taskId}&chunkIndex=${chunkIndex}&totalChunks=${totalChunks}`,
          chunk,
          {
            headers: {'Content-Type': 'application/octet-stream'},
          },
        );
      }

      await waitForTaskChain(taskId);
      setAvatarDialogOpen(false);
      setSelectedImageUri(null);
      setSelectedImageName('');
      setSelectedImageType('');
      await refreshMe();
    } catch (e) {
      showError(extractApiError(e, 'Failed to upload avatar'));
    } finally {
      setAvatarLoading(false);
    }
  }, [selectedImageName, selectedImageType, selectedImageUri, refreshMe, showError]);

  const canvasPanResponder = useMemo(() => PanResponder.create({
    onStartShouldSetPanResponder: () => true,
    onMoveShouldSetPanResponder: (_, g) => Math.abs(g.dx) > 2 || Math.abs(g.dy) > 2,
    onPanResponderGrant: () => {
      dragStartRef.current = {...avatarPanRef.current};
    },
    onPanResponderMove: (_, g) => {
      const x = dragStartRef.current.x + g.dx;
      const y = dragStartRef.current.y + g.dy;
      avatarPanRef.current = {x, y};
      setAvatarPan({x, y});
    },
    onPanResponderRelease: () => {},
  }), []);

  const sliderPanResponder = useMemo(() => PanResponder.create({
    onStartShouldSetPanResponder: () => true,
    onMoveShouldSetPanResponder: () => true,
    onPanResponderMove: (e) => {
      const width = sliderWidthRef.current || 200;
      const x = e.nativeEvent.locationX;
      const newZoom = Math.max(1, Math.min(3, 1 + (x / width) * 2));
      setAvatarZoom(newZoom);
    },
  }), []);

  // ─── Render ────────────────────────────────────────────────────

  return (
    <ScreenRoot padded={false}>
      <ScrollView
        contentContainerStyle={[styles.content, screenSafeAreaPadding(insets, !isOffline)]}
        showsVerticalScrollIndicator={false}
      >
        {/* Header */}
        <View style={styles.header}>
          <TouchableOpacity
            accessibilityRole="button"
            onPress={() => navigation.goBack()}
            style={styles.backButton}
          >
            <ArrowLeft color={colors.text} size={24} />
          </TouchableOpacity>
          <FluentTitle>{t('auth.security')}</FluentTitle>
        </View>

        {/* ─── User Profile ─────────────────────────────────────── */}
        <FluentCard style={styles.section}>
          <FluentTitle>{t('settings.account')}</FluentTitle>
          <View style={styles.profileRow}>
            <View style={styles.avatarLargeWrap}>
              {avatarSource ? (
                <FastImage source={avatarSource} style={styles.avatarLarge} />
              ) : (
                <User color={colors.textMuted} size={32} />
              )}
            </View>
            <View style={styles.profileInfo}>
              <Text style={styles.profileUsername}>{user?.username || t('common.unknown')}</Text>
              <Text style={styles.profileId}>ID: {user?.id ?? '-'}</Text>
              {user?.isAdmin ? (
                <View style={styles.adminBadgeSelf}>
                  <Text style={styles.adminBadgeText}>{t('auth.admin')}</Text>
                </View>
              ) : null}
            </View>
          </View>
          <View style={styles.profileActions}>
            <FluentButton
              label={t('auth.changeAvatar')}
              variant="secondary"
              onPress={handlePickAvatar}
              style={styles.flexButton}
            />
            <FluentButton
              label={t('auth.logout')}
              variant="danger"
              onPress={confirmSignOut}
              style={styles.flexButton}
            />
          </View>
        </FluentCard>

        {/* ─── Change Credentials ───────────────────────────────── */}
        <FluentCard style={styles.section}>
          <FluentTitle>{t('auth.changeCredentials')}</FluentTitle>
          <FluentCaption>{t('auth.changeCredentialsDescription')}</FluentCaption>
          <FluentTextField
            label={t('auth.username')}
            value={newUsername}
            onChangeText={setNewUsername}
            placeholder={user?.username || ''}
            editable={!loading}
            maxLength={64}
          />
          {newUsername.length > 0 && newUsername.length < 3 && (
            <Text style={styles.hintDanger}>{t('auth.usernameTooShort')}</Text>
          )}
          {newUsername === user?.username && newUsername.length >= 3 && (
            <Text style={styles.hintMuted}>{t('auth.usernameUnchanged')}</Text>
          )}
          <FluentTextField
            label={t('auth.newPassword')}
            value={newPassword}
            onChangeText={setNewPassword}
            placeholder={t('auth.newPasswordPlaceholder')}
            secureTextEntry
            editable={!loading}
          />
          <FluentTextField
            label={t('auth.confirmPasswordPlaceholder')}
            value={confirmPassword}
            onChangeText={setConfirmPassword}
            placeholder={t('auth.confirmPasswordPlaceholder')}
            secureTextEntry
            editable={!loading}
          />
          {newPassword.length > 0 && confirmPassword.length > 0 && newPassword !== confirmPassword && (
            <Text style={styles.hintDanger}>{t('auth.passwordMismatch')}</Text>
          )}
          {newPassword.length > 0 && newPassword.length < 6 && (
            <Text style={styles.hintDanger}>{t('auth.passwordTooShort')}</Text>
          )}
          <FluentButton
            label={loading ? t('common.saving') : t('common.save')}
            variant="primary"
            onPress={handleSaveCredentials}
            disabled={loading || !canSave}
            style={styles.fullButton}
          />
        </FluentCard>

        {/* ─── TOTP ─────────────────────────────────────────────── */}
        <FluentCard style={styles.section}>
          <FluentTitle>{t('auth.totpManagement')}</FluentTitle>
          <FluentCaption>{t('auth.totpManagementDescription')}</FluentCaption>

          <View style={styles.statusRow}>
            <View style={styles.statusIcon}>
              <ShieldCheck color={totpStatus?.enabled ? colors.success : colors.textMuted} size={18} />
            </View>
            <View style={styles.statusInfo}>
              <Text style={styles.statusLabel}>
                {totpStatus?.enabled ? t('auth.totpEnabledLabel') : t('auth.totpDisabledLabel')}
              </Text>
              {totpStatus?.enabled && (
                <Text style={styles.statusDetail}>
                  {totpStatus.credentialName || t('auth.totpDefaultCredential')}
                  {totpStatus.createdAt ? ` · ${formatDateTime(totpStatus.createdAt)}` : ''}
                </Text>
              )}
              {!totpStatus?.enabled && (
                <Text style={styles.statusDetail}>{t('auth.totpSetupHint')}</Text>
              )}
            </View>
            <TouchableOpacity
              accessibilityRole="button"
              onPress={loadTotpStatus}
              disabled={totpLoading}
              style={styles.smallIconBtn}
            >
              <RefreshCw color={colors.primary} size={18} />
            </TouchableOpacity>
          </View>

          {!totpStatus?.enabled ? (
            /* Enroll flow */
            <View style={styles.borderedSection}>
              <FluentTextField
                label={t('auth.totpAppName')}
                value={totpName}
                onChangeText={setTotpName}
                placeholder={t('auth.totpAppNamePlaceholder')}
                editable={!enrollingTotp && !confirmingTotp}
              />
              {!totpEnrollment ? (
                <FluentButton
                  label={enrollingTotp ? t('auth.totpGenerating') : t('auth.totpStartEnrollment')}
                  variant="primary"
                  onPress={startTotpEnrollment}
                  disabled={enrollingTotp}
                  style={styles.fullButton}
                />
              ) : (
                <>
                  <View style={styles.qrRow}>
                    <View style={styles.qrBox}>
                      {totpEnrollment.otpauthUri ? (
                        <QRCode value={totpEnrollment.otpauthUri} size={160} />
                      ) : (
                        <View style={[styles.qrPlaceholder, {backgroundColor: colors.surfaceMuted}]}>
                          <QrCode color={colors.textMuted} size={40} />
                        </View>
                      )}
                    </View>
                    <View style={styles.qrInfo}>
                      <Text style={styles.qrTitle}>{t('auth.scanQrCode')}</Text>
                      <Text style={styles.qrDesc}>{t('auth.scanQrCodeDescription')}</Text>
                      <Text style={styles.sectionLabel}>{t('auth.manualEntryKey')}</Text>
                      <View style={[styles.monoBox, {backgroundColor: colors.surfaceMuted}]}>
                        <Text style={[styles.monoText, {color: colors.text}]} selectable>
                          {totpEnrollment.manualEntryKey}
                        </Text>
                      </View>
                    </View>
                  </View>
                  <FluentTextField
                    label={t('auth.totpCode')}
                    value={totpCode}
                    onChangeText={setTotpCode}
                    placeholder={t('auth.totpCodePlaceholder')}
                    keyboardType="number-pad"
                    editable={!confirmingTotp}
                  />
                  <View style={styles.buttonRow}>
                    <FluentButton
                      label={confirmingTotp ? t('auth.totpConfirming') : t('auth.totpConfirmEnrollment')}
                      variant="primary"
                      onPress={confirmTotpEnrollment}
                      disabled={confirmingTotp || !totpCode.trim()}
                    />
                    <FluentButton
                      label={t('common.cancel')}
                      variant="ghost"
                      onPress={() => setTotpEnrollment(null)}
                      disabled={confirmingTotp}
                    />
                  </View>
                </>
              )}
            </View>
          ) : (
            /* TOTP enabled management */
            <View style={styles.borderedSection}>
              <Text style={styles.statusDetail}>
                {t('auth.recoveryCodesRemaining')}: {totpStatus?.recoveryCodesRemaining ?? 0}
              </Text>
              <FluentTextField
                label={t('auth.totpCode')}
                value={totpCode}
                onChangeText={setTotpCode}
                placeholder={t('auth.totpCodePlaceholder')}
                keyboardType="number-pad"
                editable={!regeneratingRecoveryCodes}
              />
              <FluentButton
                label={regeneratingRecoveryCodes ? t('auth.totpRegeneratingRecoveryCodes') : t('auth.regenerateRecoveryCodes')}
                variant="secondary"
                onPress={regenerateTotpRecoveryCodes}
                disabled={regeneratingRecoveryCodes || !totpCode.trim()}
                style={styles.fullButton}
              />
              <FluentButton
                label={disablingTotp ? t('auth.disablingTotp') : t('auth.disableTotp')}
                variant="danger"
                onPress={disableTotp}
                disabled={disablingTotp}
                style={styles.fullButton}
              />
            </View>
          )}

          {/* Recovery codes display */}
          {recoveryCodes.length > 0 ? (
            <View style={[styles.borderedSection, styles.dashedBorder]}>
              <View style={styles.recoveryHeader}>
                <View>
                  <Text style={styles.sectionLabel}>{t('auth.recoveryCodes')}</Text>
                  <Text style={styles.hintMuted}>{t('auth.recoveryCodesDescription')}</Text>
                </View>
                <View style={styles.buttonRow}>
                  <TouchableOpacity
                    accessibilityRole="button"
                    onPress={copyRecoveryCodes}
                    style={styles.smallIconBtn}
                  >
                    <Copy color={colors.primary} size={18} />
                  </TouchableOpacity>
                  <TouchableOpacity
                    accessibilityRole="button"
                    onPress={downloadRecoveryCodes}
                    style={styles.smallIconBtn}
                  >
                    <Download color={colors.primary} size={18} />
                  </TouchableOpacity>
                </View>
              </View>
              {recoveryCodes.map(code => (
                <View key={code} style={[styles.monoBox, {backgroundColor: colors.surfaceMuted}]}>
                  <Text style={[styles.monoText, {color: colors.text}]} selectable>
                    {code}
                  </Text>
                </View>
              ))}
            </View>
          ) : null}
        </FluentCard>

        {/* ─── Passkeys ─────────────────────────────────────────── */}
        <FluentCard style={styles.section}>
          <FluentTitle>{t('auth.passkeyManagement')}</FluentTitle>
          <FluentCaption>{t('auth.passkeyManagementDescription')}</FluentCaption>
          {passkeySupported ? (
            <>
              <FluentTextField
                label={t('auth.passkeyName')}
                value={newPasskeyName}
                onChangeText={setNewPasskeyName}
                placeholder={t('auth.passkeyNamePlaceholder')}
                editable={!registeringPasskey}
              />
              <FluentButton
                label={registeringPasskey ? t('auth.passkeyRegistering') : t('auth.passkeyRegister')}
                variant="primary"
                onPress={registerPasskey}
                disabled={registeringPasskey}
                style={styles.fullButton}
              />
              <View style={styles.listHeader}>
                <Text style={styles.hintMuted}>{t('auth.passkeys')}</Text>
                <TouchableOpacity
                  accessibilityRole="button"
                  onPress={loadPasskeys}
                  disabled={passkeysLoading}
                  style={styles.smallIconBtn}
                >
                  <RefreshCw color={colors.primary} size={18} />
                </TouchableOpacity>
              </View>
              {passkeysLoading ? (
                <Text style={styles.hintMuted}>{t('common.loading')}</Text>
              ) : passkeys.length === 0 ? (
                <Text style={styles.hintMuted}>{t('auth.noPasskeys')}</Text>
              ) : (
                passkeys.map(pk => (
                  <View key={pk.id} style={[styles.listItem, {borderColor: colors.border}]}>
                    <View style={styles.listItemInfo}>
                      <Text style={styles.itemTitle}>{pk.name || t('auth.unnamedPasskey')}</Text>
                      <View style={styles.badgeRow}>
                        <View style={styles.smallBadge}>
                          <Text style={styles.smallBadgeText}>{pk.algorithm}</Text>
                        </View>
                        {pk.userVerified ? (
                          <View style={[styles.smallBadge, {backgroundColor: colors.primaryMuted}]}>
                            <Text style={[styles.smallBadgeText, {color: colors.primary}]}>
                              {t('auth.passkeyUserVerified')}
                            </Text>
                          </View>
                        ) : null}
                      </View>
                      {pk.lastUsedAt ? (
                        <Text style={styles.hintMuted}>{t('auth.lastUsed')}: {formatDateTime(pk.lastUsedAt)}</Text>
                      ) : null}
                    </View>
                    <TouchableOpacity
                      accessibilityRole="button"
                      onPress={() => revokePasskey(pk.id)}
                      disabled={loading}
                      style={styles.dangerIconBtn}
                    >
                      <Trash2 color={colors.danger} size={18} />
                    </TouchableOpacity>
                  </View>
                ))
              )}
            </>
          ) : (
            <Text style={styles.hintMuted}>{t('auth.passkeyUnavailable')}</Text>
          )}
        </FluentCard>

        {/* ─── Sessions ─────────────────────────────────────────── */}
        <FluentCard style={styles.section}>
          <FluentTitle>{t('auth.sessionManagement')}</FluentTitle>
          <FluentCaption>{t('auth.sessionManagementDescription')}</FluentCaption>
          <View style={styles.listHeader}>
            <Text style={styles.hintMuted}>{t('auth.sessions')}</Text>
            <View style={styles.buttonRow}>
              <FluentButton
                label={t('auth.revokeOtherSessions')}
                variant="secondary"
                onPress={revokeOtherSessions}
                disabled={loading || sessionsLoading || sessions.length <= 1}
              />
              <TouchableOpacity
                accessibilityRole="button"
                onPress={loadSessions}
                disabled={sessionsLoading}
                style={styles.smallIconBtn}
              >
                <RefreshCw color={colors.primary} size={18} />
              </TouchableOpacity>
            </View>
          </View>
          {sessionsLoading ? (
            <Text style={styles.hintMuted}>{t('common.loading')}</Text>
          ) : sessions.length === 0 ? (
            <Text style={styles.hintMuted}>{t('auth.noSessions')}</Text>
          ) : (
            sessions.map(session => (
              <View key={session.id} style={[styles.listItem, {borderColor: colors.border}]}>
                <View style={styles.listItemInfo}>
                  <View style={styles.badgeRow}>
                    <Text style={styles.itemTitle}>{session.name || t('auth.unnamedSession')}</Text>
                    <View style={styles.smallBadge}>
                      <Text style={styles.smallBadgeText}>{session.prefix}</Text>
                    </View>
                    {session.current ? (
                      <View style={[styles.smallBadge, {backgroundColor: colors.primaryMuted}]}>
                        <Text style={[styles.smallBadgeText, {color: colors.primary}]}>
                          {t('auth.currentSession')}
                        </Text>
                      </View>
                    ) : null}
                  </View>
                  {session.createdAt ? (
                    <Text style={styles.hintMuted}>{t('auth.createdAt')}: {formatDateTime(session.createdAt)}</Text>
                  ) : null}
                  {session.lastUsedAt ? (
                    <Text style={styles.hintMuted}>{t('auth.lastUsed')}: {formatDateTime(session.lastUsedAt)}</Text>
                  ) : null}
                  {session.lastUsedIp ? (
                    <Text style={styles.hintMuted}>IP: {session.lastUsedIp}</Text>
                  ) : null}
                </View>
                <TouchableOpacity
                  accessibilityRole="button"
                  onPress={() => revokeSession(session)}
                  disabled={loading}
                  style={styles.dangerIconBtn}
                >
                  <LogOut color={colors.danger} size={18} />
                </TouchableOpacity>
              </View>
            ))
          )}
        </FluentCard>

        {/* ─── New Token Display ────────────────────────────────── */}
        {newTokenValue ? (
          <FluentCard style={[styles.section, styles.dashedBorder]}>
            <Text style={styles.sectionLabel}>{t('auth.newToken')}</Text>
            <Text style={styles.hintMuted}>{t('auth.newTokenHint')}</Text>
            <View style={[styles.monoBox, {backgroundColor: colors.surfaceMuted}]}>
              <Text style={[styles.monoText, {color: colors.text}]} selectable>
                {newTokenValue}
              </Text>
            </View>
          </FluentCard>
        ) : null}

        {/* ─── API Tokens ───────────────────────────────────────── */}
        <FluentCard style={styles.section}>
          <FluentTitle>{t('auth.tokenManagement')}</FluentTitle>
          <FluentCaption>{t('auth.tokenManagementDescription')}</FluentCaption>
          <FluentTextField
            label={t('auth.tokenName')}
            value={newTokenName}
            onChangeText={setNewTokenName}
            placeholder={t('auth.tokenNamePlaceholder')}
            editable={!loading}
          />
          <FluentButton
            label={t('auth.createToken')}
            variant="primary"
            onPress={createToken}
            disabled={loading || !newTokenName.trim()}
            style={styles.fullButton}
          />
          <View style={styles.listHeader}>
            <Text style={styles.hintMuted}>{t('auth.tokens')}</Text>
            <TouchableOpacity
              accessibilityRole="button"
              onPress={loadTokens}
              disabled={tokensLoading}
              style={styles.smallIconBtn}
            >
              <RefreshCw color={colors.primary} size={18} />
            </TouchableOpacity>
          </View>
          {tokensLoading ? (
            <Text style={styles.hintMuted}>{t('common.loading')}</Text>
          ) : tokens.length === 0 ? (
            <Text style={styles.hintMuted}>{t('auth.noTokens')}</Text>
          ) : (
            tokens.map(tk => (
              <View key={tk.id} style={[styles.listItem, {borderColor: colors.border}]}>
                <View style={styles.listItemInfo}>
                  <View style={styles.badgeRow}>
                    <Text style={styles.itemTitle}>{tk.name || t('auth.unnamedToken')}</Text>
                    <View style={styles.smallBadge}>
                      <Text style={styles.smallBadgeText}>{tk.prefix}</Text>
                    </View>
                  </View>
                </View>
                <TouchableOpacity
                  accessibilityRole="button"
                  onPress={() => revokeToken(tk)}
                  disabled={loading}
                  style={styles.dangerIconBtn}
                >
                  <Trash2 color={colors.danger} size={18} />
                </TouchableOpacity>
              </View>
            ))
          )}
        </FluentCard>
      </ScrollView>

      {/* ─── Avatar Editor Modal ────────────────────────────────── */}
      <Modal
        animationType="fade"
        onRequestClose={() => setAvatarDialogOpen(false)}
        statusBarTranslucent
        transparent
        visible={avatarDialogOpen}
      >
        <ModalBackdrop style={{justifyContent: 'center', padding: spacing.lg}}>
          <View style={styles.avatarEditorSheet}>
            <View style={styles.avatarEditorHeader}>
              <Text style={styles.avatarEditorTitle}>{t('auth.editAvatar')}</Text>
              <TouchableOpacity
                accessibilityRole="button"
                onPress={() => setAvatarDialogOpen(false)}
                style={styles.closeBtn}
              >
                <X color={colors.textMuted} size={20} />
              </TouchableOpacity>
            </View>

            {selectedImageUri ? (
              <>
                {/* Canvas */}
                <View
                  style={styles.avatarCanvas}
                  {...canvasPanResponder.panHandlers}
                >
                  <FastImage
                    source={{uri: selectedImageUri}}
                    style={[
                      styles.avatarCanvasImage,
                      {
                        transform: [
                          {translateX: avatarPan.x},
                          {translateY: avatarPan.y},
                          {scale: avatarZoom},
                        ],
                      },
                    ]}
                    resizeMode={FastImage.resizeMode.cover}
                  />
                </View>

                {/* Zoom slider */}
                <View style={styles.zoomRow}>
                  <Text style={styles.zoomLabel}>1x</Text>
                  <View
                    style={styles.sliderTrack}
                    onLayout={e => { sliderWidthRef.current = e.nativeEvent.layout.width; }}
                    {...sliderPanResponder.panHandlers}
                  >
                    <View
                      style={[
                        styles.sliderFill,
                        {width: `${((avatarZoom - 1) / 2) * 100}%`},
                      ]}
                    />
                    <View
                      style={[
                        styles.sliderThumb,
                        {left: `${((avatarZoom - 1) / 2) * 100}%`},
                      ]}
                    />
                  </View>
                  <Text style={styles.zoomLabel}>3x</Text>
                </View>

                {/* Preview circles */}
                <View style={styles.previewRow}>
                  <View style={styles.previewCol}>
                    <View style={styles.previewCircleLarge}>
                      <FastImage
                        source={{uri: selectedImageUri}}
                        style={[
                          styles.previewImage,
                          {
                            transform: [
                              {translateX: avatarPan.x},
                              {translateY: avatarPan.y},
                              {scale: avatarZoom},
                            ],
                          },
                        ]}
                        resizeMode={FastImage.resizeMode.cover}
                      />
                    </View>
                    <Text style={styles.previewLabel}>100x100</Text>
                  </View>
                  <View style={styles.previewCol}>
                    <View style={styles.previewCircleSmall}>
                      <FastImage
                        source={{uri: selectedImageUri}}
                        style={[
                          styles.previewImageSmall,
                          {
                            transform: [
                              {translateX: avatarPan.x},
                              {translateY: avatarPan.y},
                              {scale: avatarZoom},
                            ],
                          },
                        ]}
                        resizeMode={FastImage.resizeMode.cover}
                      />
                    </View>
                    <Text style={styles.previewLabel}>50x50</Text>
                  </View>
                </View>
              </>
            ) : null}

            {/* Footer */}
            <View style={styles.avatarEditorFooter}>
              <FluentButton
                label={t('common.cancel')}
                variant="secondary"
                onPress={() => setAvatarDialogOpen(false)}
                disabled={avatarLoading}
              />
              <FluentButton
                label={avatarLoading ? t('common.saving') : t('common.upload')}
                variant="primary"
                onPress={handleUploadAvatar}
                disabled={avatarLoading || !selectedImageUri}
              />
            </View>
          </View>
        </ModalBackdrop>
      </Modal>

      {/* ─── Step-Up Modal ──────────────────────────────────────── */}
      <Modal
        animationType="fade"
        onRequestClose={() => closeStepUp(false)}
        statusBarTranslucent
        transparent
        visible={stepUpOpen}
      >
        <ModalBackdrop style={{justifyContent: 'flex-end'}}>
          <View style={[styles.stepUpSheet, {paddingBottom: Math.max(insets.bottom, spacing.lg)}]}>
            <View style={styles.stepUpHeader}>
              <Text style={styles.stepUpTitle}>{t('auth.stepUpTitle')}</Text>
              <TouchableOpacity
                accessibilityRole="button"
                onPress={() => closeStepUp(false)}
                style={styles.closeBtn}
              >
                <X color={colors.textMuted} size={20} />
              </TouchableOpacity>
            </View>
            <Text style={styles.hintMuted}>{t('auth.stepUpDescription')}</Text>

            {/* Method selector */}
            <View style={styles.methodRow}>
              {stepUpMethods.includes('password') && (
                <TouchableOpacity
                  accessibilityRole="button"
                  onPress={() => setStepUpMethod('password')}
                  style={[
                    styles.methodChip,
                    stepUpMethod === 'password' && {backgroundColor: colors.primary, borderColor: colors.primary},
                  ]}
                >
                  <Text
                    style={[
                      styles.methodChipText,
                      stepUpMethod === 'password' && {color: colors.white},
                    ]}
                  >
                    {t('auth.stepUpPassword')}
                  </Text>
                </TouchableOpacity>
              )}
              {stepUpMethods.includes('totp') && (
                <TouchableOpacity
                  accessibilityRole="button"
                  onPress={() => setStepUpMethod('totp')}
                  style={[
                    styles.methodChip,
                    stepUpMethod === 'totp' && {backgroundColor: colors.primary, borderColor: colors.primary},
                  ]}
                >
                  <Text
                    style={[
                      styles.methodChipText,
                      stepUpMethod === 'totp' && {color: colors.white},
                    ]}
                  >
                    TOTP
                  </Text>
                </TouchableOpacity>
              )}
              {stepUpMethods.includes('passkey') && passkeySupported && (
                <TouchableOpacity
                  accessibilityRole="button"
                  onPress={() => setStepUpMethod('passkey')}
                  style={[
                    styles.methodChip,
                    stepUpMethod === 'passkey' && {backgroundColor: colors.primary, borderColor: colors.primary},
                  ]}
                >
                  <Text
                    style={[
                      styles.methodChipText,
                      stepUpMethod === 'passkey' && {color: colors.white},
                    ]}
                  >
                    Passkey
                  </Text>
                </TouchableOpacity>
              )}
            </View>

            {stepUpMethod === 'password' && (
              <FluentTextField
                label={t('auth.stepUpPassword')}
                value={stepUpPassword}
                onChangeText={setStepUpPassword}
                placeholder={t('auth.stepUpPassword')}
                secureTextEntry
                editable={!stepUpLoading}
              />
            )}

            {stepUpMethod === 'totp' && (
              <>
                <View style={styles.methodRow}>
                  <TouchableOpacity
                    accessibilityRole="button"
                    onPress={() => setStepUpMode('totp')}
                    style={[
                      styles.methodChip,
                      stepUpMode === 'totp' && {backgroundColor: colors.primary, borderColor: colors.primary},
                    ]}
                  >
                    <Text
                      style={[
                        styles.methodChipText,
                        stepUpMode === 'totp' && {color: colors.white},
                      ]}
                    >
                      {t('auth.stepUpTotp')}
                    </Text>
                  </TouchableOpacity>
                  <TouchableOpacity
                    accessibilityRole="button"
                    onPress={() => setStepUpMode('recovery')}
                    style={[
                      styles.methodChip,
                      stepUpMode === 'recovery' && {backgroundColor: colors.primary, borderColor: colors.primary},
                    ]}
                  >
                    <Text
                      style={[
                        styles.methodChipText,
                        stepUpMode === 'recovery' && {color: colors.white},
                      ]}
                    >
                      {t('auth.stepUpRecovery')}
                    </Text>
                  </TouchableOpacity>
                </View>
                <FluentTextField
                  label={stepUpMode === 'totp' ? t('auth.stepUpTotp') : t('auth.stepUpRecovery')}
                  value={stepUpMode === 'totp' ? stepUpTotpCode : stepUpRecoveryCode}
                  onChangeText={stepUpMode === 'totp' ? setStepUpTotpCode : setStepUpRecoveryCode}
                  placeholder={stepUpMode === 'totp' ? t('auth.totpCodePlaceholder') : ''}
                  keyboardType={stepUpMode === 'totp' ? 'number-pad' : 'default'}
                  editable={!stepUpLoading}
                />
              </>
            )}

            {stepUpMethod === 'passkey' && (
              <Text style={styles.hintMuted}>{t('auth.passkeyStepUpHint')}</Text>
            )}

            {stepUpError ? (
              <View style={styles.msgRow}>
                <Text style={styles.errorText}>{stepUpError}</Text>
              </View>
            ) : null}

            <View style={styles.buttonRow}>
              <FluentButton
                label={t('common.cancel')}
                onPress={() => closeStepUp(false)}
                disabled={stepUpLoading}
              />
              <FluentButton
                label={t('auth.stepUpVerify')}
                variant="primary"
                onPress={verifyStepUp}
                disabled={
                  stepUpLoading ||
                  (stepUpMethod === 'password' && !stepUpPassword.trim()) ||
                  (stepUpMethod === 'totp' && stepUpMode === 'totp' && !stepUpTotpCode.trim()) ||
                  (stepUpMethod === 'totp' && stepUpMode === 'recovery' && !stepUpRecoveryCode.trim())
                }
              />
            </View>
          </View>
        </ModalBackdrop>
      </Modal>
    </ScreenRoot>
  );
}

// ─── Styles ─────────────────────────────────────────────────────────────────

function createStyles(colors: ThemeColors) {
  return StyleSheet.create({
    content: {
      gap: spacing.md,
      paddingBottom: spacing.xl,
    },
    section: {
      gap: spacing.md,
    },
    header: {
      flexDirection: 'row',
      alignItems: 'center',
      gap: spacing.md,
    },
    backButton: {
      padding: spacing.xs,
    },
    row: {
      gap: spacing.xs,
    },
    label: {
      color: colors.textMuted,
      fontSize: 12,
      fontWeight: '700',
      textTransform: 'uppercase',
    },
    value: {
      color: colors.text,
      fontSize: 16,
      fontWeight: '800',
    },
    badgeRow: {
      flexDirection: 'row',
      flexWrap: 'wrap',
      gap: spacing.xs,
    },
    adminBadge: {
      backgroundColor: colors.primaryMuted,
      borderRadius: radius.sm,
      paddingHorizontal: spacing.sm,
      paddingVertical: 2,
    },
    adminBadgeText: {
      color: colors.primary,
      fontSize: 12,
      fontWeight: '700',
    },
    fullButton: {
      marginTop: spacing.xs,
    },
    hintDanger: {
      color: colors.danger,
      fontSize: 12,
    },
    hintMuted: {
      color: colors.textMuted,
      fontSize: 12,
    },
    msgRow: {
      paddingVertical: spacing.xs,
    },
    errorText: {
      color: colors.danger,
      fontSize: 13,
    },
    successText: {
      color: colors.success,
      fontSize: 13,
    },
    // Status row
    statusRow: {
      flexDirection: 'row',
      alignItems: 'center',
      gap: spacing.sm,
    },
    statusIcon: {
      width: 32,
      height: 32,
      alignItems: 'center',
      justifyContent: 'center',
    },
    statusInfo: {
      flex: 1,
    },
    statusLabel: {
      color: colors.text,
      fontSize: 14,
      fontWeight: '700',
    },
    statusDetail: {
      color: colors.textMuted,
      fontSize: 12,
    },
    // Bordered section
    borderedSection: {
      borderColor: colors.border,
      borderRadius: radius.md,
      borderWidth: StyleSheet.hairlineWidth,
      padding: spacing.md,
      gap: spacing.md,
    },
    dashedBorder: {
      borderStyle: 'dashed',
    },
    // QR code
    qrRow: {
      flexDirection: 'row',
      gap: spacing.md,
    },
    qrBox: {
      borderRadius: radius.md,
      borderWidth: StyleSheet.hairlineWidth,
      borderColor: colors.border,
      padding: spacing.sm,
      backgroundColor: colors.white,
    },
    qrPlaceholder: {
      width: 160,
      height: 160,
      alignItems: 'center',
      justifyContent: 'center',
      borderRadius: radius.sm,
    },
    qrInfo: {
      flex: 1,
      gap: spacing.sm,
    },
    qrTitle: {
      color: colors.text,
      fontSize: 13,
      fontWeight: '700',
    },
    qrDesc: {
      color: colors.textMuted,
      fontSize: 12,
    },
    sectionLabel: {
      color: colors.text,
      fontSize: 13,
      fontWeight: '700',
    },
    monoBox: {
      borderRadius: radius.sm,
      padding: spacing.sm,
    },
    monoText: {
      fontFamily: Platform.OS === 'ios' ? 'Menlo' : 'monospace',
      fontSize: 12,
    },
    // Recovery codes
    recoveryHeader: {
      flexDirection: 'row',
      justifyContent: 'space-between',
      alignItems: 'flex-start',
    },
    // Button row
    buttonRow: {
      flexDirection: 'row',
      gap: spacing.sm,
      alignItems: 'center',
    },
    smallIconBtn: {
      width: 36,
      height: 36,
      alignItems: 'center',
      justifyContent: 'center',
      borderRadius: 18,
    },
    dangerIconBtn: {
      width: 36,
      height: 36,
      alignItems: 'center',
      justifyContent: 'center',
    },
    closeBtn: {
      width: 32,
      height: 32,
      alignItems: 'center',
      justifyContent: 'center',
    },
    // List items
    listHeader: {
      flexDirection: 'row',
      justifyContent: 'space-between',
      alignItems: 'center',
    },
    listItem: {
      flexDirection: 'row',
      alignItems: 'center',
      borderRadius: radius.md,
      borderWidth: StyleSheet.hairlineWidth,
      padding: spacing.md,
      gap: spacing.sm,
    },
    listItemInfo: {
      flex: 1,
      gap: spacing.xs,
    },
    itemTitle: {
      color: colors.text,
      fontSize: 14,
      fontWeight: '700',
    },
    smallBadge: {
      backgroundColor: colors.surfaceMuted,
      borderRadius: radius.sm,
      paddingHorizontal: spacing.xs,
      paddingVertical: 1,
    },
    smallBadgeText: {
      color: colors.textMuted,
      fontSize: 10,
      fontWeight: '700',
    },
    // Step-up modal
    stepUpSheet: {
      backgroundColor: colors.surface,
      borderTopLeftRadius: 14,
      borderTopRightRadius: 14,
      gap: spacing.md,
      padding: spacing.lg,
      width: '100%',
    },
    stepUpHeader: {
      flexDirection: 'row',
      justifyContent: 'space-between',
      alignItems: 'center',
    },
    stepUpTitle: {
      color: colors.text,
      fontSize: 18,
      fontWeight: '800',
    },
    methodRow: {
      flexDirection: 'row',
      flexWrap: 'wrap',
      gap: spacing.xs,
    },
    methodChip: {
      borderRadius: radius.md,
      borderWidth: StyleSheet.hairlineWidth,
      borderColor: colors.border,
      paddingHorizontal: spacing.md,
      paddingVertical: spacing.sm,
    },
    methodChipText: {
      color: colors.text,
      fontSize: 13,
      fontWeight: '700',
    },
    // Avatar profile
    profileRow: {
      flexDirection: 'row',
      alignItems: 'center',
      gap: spacing.md,
    },
    avatarLargeWrap: {
      width: 64,
      height: 64,
      borderRadius: 32,
      backgroundColor: colors.surfaceMuted,
      alignItems: 'center',
      justifyContent: 'center',
      overflow: 'hidden',
    },
    avatarLarge: {
      width: 64,
      height: 64,
    },
    profileInfo: {
      flex: 1,
      gap: 2,
    },
    profileUsername: {
      color: colors.text,
      fontSize: 17,
      fontWeight: '700',
    },
    profileId: {
      color: colors.textMuted,
      fontSize: 13,
    },
    adminBadgeSelf: {
      alignSelf: 'flex-start',
      backgroundColor: colors.primaryMuted,
      borderRadius: radius.sm,
      paddingHorizontal: spacing.sm,
      paddingVertical: 2,
      marginTop: spacing.xs,
    },
    profileActions: {
      flexDirection: 'row',
      gap: spacing.sm,
      marginTop: spacing.md,
    },
    flexButton: {
      flex: 1,
    },
    // Avatar editor modal
    avatarEditorSheet: {
      backgroundColor: colors.surface,
      borderRadius: radius.md,
      gap: spacing.md,
      padding: spacing.lg,
      width: '100%',
      maxWidth: 400,
    },
    avatarEditorHeader: {
      flexDirection: 'row',
      justifyContent: 'space-between',
      alignItems: 'center',
    },
    avatarEditorTitle: {
      color: colors.text,
      fontSize: 18,
      fontWeight: '800',
    },
    avatarCanvas: {
      width: '100%',
      aspectRatio: 1,
      backgroundColor: colors.surfaceMuted,
      borderRadius: radius.md,
      overflow: 'hidden',
      alignItems: 'center',
      justifyContent: 'center',
    },
    avatarCanvasImage: {
      width: '100%',
      height: '100%',
    },
    zoomRow: {
      flexDirection: 'row',
      alignItems: 'center',
      gap: spacing.sm,
    },
    zoomLabel: {
      color: colors.textMuted,
      fontSize: 12,
      fontWeight: '700',
      width: 24,
      textAlign: 'center',
    },
    sliderTrack: {
      flex: 1,
      height: 32,
      borderRadius: 16,
      backgroundColor: colors.surfaceMuted,
      justifyContent: 'center',
      position: 'relative',
    },
    sliderFill: {
      position: 'absolute',
      left: 0,
      top: 0,
      bottom: 0,
      backgroundColor: colors.primary,
      borderRadius: 16,
    },
    sliderThumb: {
      position: 'absolute',
      width: 24,
      height: 24,
      borderRadius: 12,
      backgroundColor: colors.white,
      borderWidth: 2,
      borderColor: colors.primary,
      marginLeft: -12,
      top: 4,
      elevation: 2,
      shadowColor: colors.black,
      shadowOffset: {width: 0, height: 1},
      shadowOpacity: 0.2,
      shadowRadius: 2,
    },
    previewRow: {
      flexDirection: 'row',
      justifyContent: 'center',
      gap: spacing.xl,
    },
    previewCol: {
      alignItems: 'center',
      gap: spacing.xs,
    },
    previewCircleLarge: {
      width: 100,
      height: 100,
      borderRadius: 50,
      backgroundColor: colors.surfaceMuted,
      overflow: 'hidden',
    },
    previewImage: {
      width: 100,
      height: 100,
    },
    previewCircleSmall: {
      width: 50,
      height: 50,
      borderRadius: 25,
      backgroundColor: colors.surfaceMuted,
      overflow: 'hidden',
    },
    previewImageSmall: {
      width: 50,
      height: 50,
    },
    previewLabel: {
      color: colors.textMuted,
      fontSize: 11,
    },
    avatarEditorFooter: {
      flexDirection: 'row',
      gap: spacing.sm,
      justifyContent: 'flex-end',
    },
  });
}
