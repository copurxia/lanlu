import React, {useCallback, useEffect, useMemo, useState} from 'react';
import {Alert, Modal, RefreshControl, ScrollView, StyleSheet, Text, TouchableOpacity, View} from 'react-native';
import {ArrowLeft, Plus} from 'lucide-react-native';
import {useSafeAreaInsets} from 'react-native-safe-area-context';
import {useNavigation} from '@react-navigation/native';
import {ScreenRoot, ModalBackdrop, screenSafeAreaPadding} from '../components/SafeAreaSurface';
import {FluentButton, FluentCard, FluentCaption, FluentSwitch, FluentTextField, FluentTitle} from '../components/fluent';
import {useAuth} from '../auth/AuthContext';
import {useI18n} from '../i18n';
import {extractApiError} from '../api/client';
import {
  adminListUsers,
  adminCreateUser,
  adminToggleUserRole,
  adminDeleteUser,
  adminResetUserPassword,
  type AdminUser,
} from '../api/admin';
import {spacing, radius, type ThemeColors} from '../theme/colors';
import {useTheme} from '../theme/ThemeContext';

export function UserSettingsScreen() {
  const {t} = useI18n();
  const {colors} = useTheme();
  const {user: currentUser, isOffline} = useAuth();
  const insets = useSafeAreaInsets();
  const navigation = useNavigation();
  const styles = useMemo(() => createStyles(colors), [colors]);

  const [users, setUsers] = useState<AdminUser[]>([]);
  const [loading, setLoading] = useState(false);
  const [refreshing, setRefreshing] = useState(false);

  const [createOpen, setCreateOpen] = useState(false);
  const [createUsername, setCreateUsername] = useState('');
  const [createIsAdmin, setCreateIsAdmin] = useState(false);
  const [createLoading, setCreateLoading] = useState(false);
  const [resetOpen, setResetOpen] = useState(false);
  const [resetUser, setResetUser] = useState<AdminUser | null>(null);
  const [resetPassword, setResetPassword] = useState('');
  const [resetConfirmPassword, setResetConfirmPassword] = useState('');
  const [resetPasswordError, setResetPasswordError] = useState('');
  const [resetLoading, setResetLoading] = useState(false);

  const loadUsers = useCallback(async () => {
    try {
      const resp = await adminListUsers();
      setUsers(resp.data?.users || []);
    } catch (e) {
      Alert.alert(t('common.error'), extractApiError(e));
    }
  }, [t]);

  useEffect(() => {
    setLoading(true);
    loadUsers().finally(() => setLoading(false));
  }, [loadUsers]);

  const onRefresh = useCallback(async () => {
    setRefreshing(true);
    await loadUsers();
    setRefreshing(false);
  }, [loadUsers]);

  const handleCreate = useCallback(async () => {
    if (!createUsername.trim()) return;
    setCreateLoading(true);
    try {
      const resp = await adminCreateUser({username: createUsername.trim(), isAdmin: createIsAdmin});
      const generatedPassword = resp.data?.generatedPassword;
      setCreateOpen(false);
      setCreateUsername('');
      setCreateIsAdmin(false);
      const msg = generatedPassword
        ? `Created "${createUsername.trim()}", generated password: ${generatedPassword}`
        : `Created "${createUsername.trim()}"`;
      Alert.alert(t('common.success'), msg);
      await loadUsers();
    } catch (e) {
      Alert.alert(t('common.error'), extractApiError(e));
    } finally {
      setCreateLoading(false);
    }
  }, [createUsername, createIsAdmin, loadUsers, t]);

  const handleToggleRole = useCallback(async (user: AdminUser) => {
    try {
      await adminToggleUserRole(user.id, !user.isAdmin);
      await loadUsers();
    } catch (e) {
      Alert.alert(t('common.error'), extractApiError(e));
    }
  }, [loadUsers, t]);

  const handleDelete = useCallback((user: AdminUser) => {
    Alert.alert(
      t('common.confirm'),
      `Delete user "${user.username}"?`,
      [
        {text: t('common.cancel'), style: 'cancel'},
        {
          text: t('common.delete'),
          style: 'destructive',
          onPress: async () => {
            try {
              await adminDeleteUser(user.id);
              await loadUsers();
            } catch (e) {
              Alert.alert(t('common.error'), extractApiError(e));
            }
          },
        },
      ],
    );
  }, [loadUsers, t]);

  const handleResetPassword = useCallback((user: AdminUser) => {
    setResetUser(user);
    setResetPassword('');
    setResetConfirmPassword('');
    setResetPasswordError('');
    setResetOpen(true);
  }, [t]);

  const submitResetPassword = useCallback(async () => {
    if (!resetUser) return;
    if (resetPassword.length < 6) {
      setResetPasswordError('Password must be at least 6 characters');
      return;
    }
    if (resetPassword !== resetConfirmPassword) {
      setResetPasswordError('Passwords do not match');
      return;
    }
    setResetPasswordError('');
    setResetLoading(true);
    try {
      await adminResetUserPassword(resetUser.id, resetPassword.trim());
      setResetOpen(false);
      setResetUser(null);
      setResetPassword('');
      setResetConfirmPassword('');
      Alert.alert(t('common.success'), 'Password reset successfully');
    } catch (e) {
      Alert.alert(t('common.error'), extractApiError(e));
    } finally {
      setResetLoading(false);
    }
  }, [resetPassword, resetConfirmPassword, resetUser, t]);

  return (
    <ScreenRoot padded={false}>
      <ScrollView
        contentContainerStyle={[styles.content, screenSafeAreaPadding(insets, !isOffline)]}
        showsVerticalScrollIndicator={false}
        refreshControl={<RefreshControl refreshing={refreshing} onRefresh={onRefresh} tintColor={colors.primary} />}>
        <View style={styles.header}>
          <TouchableOpacity
            accessibilityRole="button"
            onPress={() => navigation.goBack()}
            style={styles.backButton}>
            <ArrowLeft color={colors.text} size={24} />
          </TouchableOpacity>
          <FluentTitle style={{flex: 1}}>{t('settings.users')}</FluentTitle>
          <TouchableOpacity
            accessibilityRole="button"
            onPress={() => setCreateOpen(true)}
            style={styles.addButton}>
            <Plus color={colors.primary} size={24} />
          </TouchableOpacity>
        </View>

        {loading && users.length === 0 ? (
          <FluentCaption>{t('common.loading')}</FluentCaption>
        ) : users.length === 0 ? (
          <FluentCard style={styles.section}>
            <FluentCaption>{t('common.noResult')}</FluentCaption>
          </FluentCard>
        ) : (
          users.map(user => {
            const isSelf = currentUser?.id === user.id;
            return (
              <FluentCard key={user.id} style={styles.section}>
                <View style={styles.userHeader}>
                  <Text style={styles.userName}>{user.username}</Text>
                  {isSelf ? (
                    <View style={styles.selfBadge}>
                      <Text style={styles.selfBadgeText}>You</Text>
                    </View>
                  ) : null}
                  <View style={user.isAdmin ? styles.adminBadge : styles.userBadge}>
                    <Text style={user.isAdmin ? styles.adminBadgeText : styles.userBadgeText}>
                      {user.isAdmin ? t('auth.admin') : t('auth.user')}
                    </Text>
                  </View>
                </View>
                {user.createdAt ? (
                  <Text style={styles.createdAt}>{user.createdAt}</Text>
                ) : null}
                <View style={styles.toggleRow}>
                  <Text style={styles.toggleLabel}>{t('auth.admin')}</Text>
                  <FluentSwitch
                    value={user.isAdmin}
                    disabled={isSelf}
                    onValueChange={() => handleToggleRole(user)}
                  />
                </View>
                <View style={styles.userActions}>
                  <FluentButton
                    label={t('common.resetPassword')}
                    variant="secondary"
                    onPress={() => handleResetPassword(user)}
                    disabled={isSelf}
                    style={styles.actionButton}
                  />
                  <FluentButton
                    label={t('common.delete')}
                    variant="danger"
                    onPress={() => handleDelete(user)}
                    disabled={isSelf}
                    style={styles.actionButton}
                  />
                </View>
              </FluentCard>
            );
          })
        )}
      </ScrollView>

      <Modal
        animationType="fade"
        onRequestClose={() => setCreateOpen(false)}
        statusBarTranslucent
        transparent
        visible={createOpen}>
        <ModalBackdrop style={styles.backdrop}>
          <View style={[styles.sheet, {paddingBottom: Math.max(insets.bottom, spacing.lg)}]}>
            <FluentTitle>{'Create user'}</FluentTitle>
            <FluentTextField
              label={t('auth.username')}
              value={createUsername}
              onChangeText={setCreateUsername}
              placeholder={t('auth.username')}
              editable={!createLoading}
            />
            <View style={styles.toggleRow}>
              <Text style={styles.toggleLabel}>{t('auth.admin')}</Text>
              <FluentSwitch
                value={createIsAdmin}
                onValueChange={setCreateIsAdmin}
              />
            </View>
            <View style={styles.modalActions}>
              <FluentButton
                label={t('common.cancel')}
                onPress={() => setCreateOpen(false)}
                disabled={createLoading}
              />
              <FluentButton
                label={createLoading ? t('common.saving') : 'Create'}
                variant="primary"
                onPress={handleCreate}
                disabled={createLoading || !createUsername.trim()}
              />
            </View>
          </View>
        </ModalBackdrop>
      </Modal>

      <Modal
        animationType="fade"
        onRequestClose={() => setResetOpen(false)}
        statusBarTranslucent
        transparent
        visible={resetOpen}>
        <ModalBackdrop style={styles.backdrop}>
          <View style={[styles.sheet, {paddingBottom: Math.max(insets.bottom, spacing.lg)}]}>
            <FluentTitle>{t('common.resetPassword')}</FluentTitle>
            <FluentCaption>
              {resetUser ? `Reset password for "${resetUser.username}"?` : ''}
            </FluentCaption>
            <FluentTextField
              label={'New password'}
              value={resetPassword}
              onChangeText={(v) => {setResetPassword(v); setResetPasswordError('');}}
              placeholder={'New password'}
              secureTextEntry
              editable={!resetLoading}
            />
            <FluentTextField
              label={'Confirm password'}
              value={resetConfirmPassword}
              onChangeText={(v) => {setResetConfirmPassword(v); setResetPasswordError('');}}
              placeholder={'Confirm password'}
              secureTextEntry
              editable={!resetLoading}
            />
            {resetPasswordError ? (
              <Text style={styles.errorText}>{resetPasswordError}</Text>
            ) : null}
            <View style={styles.modalActions}>
              <FluentButton
                label={t('common.cancel')}
                onPress={() => setResetOpen(false)}
                disabled={resetLoading}
              />
              <FluentButton
                label={resetLoading ? t('common.saving') : t('common.confirm')}
                variant="primary"
                onPress={submitResetPassword}
                disabled={resetLoading || !resetPassword.trim() || !resetConfirmPassword.trim()}
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
    userHeader: {
      flexDirection: 'row',
      alignItems: 'center',
      gap: spacing.sm,
    },
    userName: {
      color: colors.text,
      fontSize: 16,
      fontWeight: '800',
    },
    selfBadge: {
      backgroundColor: colors.textMuted + '30',
      borderRadius: radius.sm,
      paddingHorizontal: spacing.sm,
      paddingVertical: 2,
    },
    selfBadgeText: {
      color: colors.textMuted,
      fontSize: 12,
      fontWeight: '700',
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
    userBadge: {
      backgroundColor: colors.surfaceMuted,
      borderRadius: radius.sm,
      borderColor: colors.border,
      borderWidth: 1,
      paddingHorizontal: spacing.sm,
      paddingVertical: 2,
    },
    userBadgeText: {
      color: colors.textMuted,
      fontSize: 12,
      fontWeight: '700',
    },
    createdAt: {
      color: colors.textMuted,
      fontSize: 12,
    },
    errorText: {
      color: colors.danger,
      fontSize: 13,
      fontWeight: '600',
    },
    toggleRow: {
      flexDirection: 'row',
      alignItems: 'center',
      justifyContent: 'space-between',
    },
    toggleLabel: {
      color: colors.text,
      fontSize: 15,
      fontWeight: '700',
    },
    userActions: {
      flexDirection: 'row',
      gap: spacing.sm,
    },
    actionButton: {
      flex: 1,
    },
    backdrop: {justifyContent: 'flex-end'},
    sheet: {
      backgroundColor: colors.surface,
      borderTopLeftRadius: 14,
      borderTopRightRadius: 14,
      gap: spacing.md,
      padding: spacing.lg,
      width: '100%',
    },
    modalActions: {
      flexDirection: 'row',
      gap: spacing.sm,
    },
  });
}
