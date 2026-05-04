import React, {useCallback, useEffect, useMemo, useState} from 'react';
import {Alert, Modal, RefreshControl, ScrollView, StyleSheet, Switch, Text, TouchableOpacity, View} from 'react-native';
import {ArrowLeft, Plus} from 'lucide-react-native';
import {useSafeAreaInsets} from 'react-native-safe-area-context';
import {useNavigation} from '@react-navigation/native';
import {ScreenRoot, ModalBackdrop, screenSafeAreaPadding} from '../components/SafeAreaSurface';
import {FluentButton, FluentCard, FluentCaption, FluentTextField, FluentTitle} from '../components/fluent';
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
      await adminCreateUser({username: createUsername.trim(), isAdmin: createIsAdmin});
      setCreateOpen(false);
      setCreateUsername('');
      setCreateIsAdmin(false);
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
    setResetOpen(true);
  }, [t]);

  const submitResetPassword = useCallback(async () => {
    if (!resetUser || !resetPassword.trim()) return;
    setResetLoading(true);
    try {
      await adminResetUserPassword(resetUser.id, resetPassword.trim());
      setResetOpen(false);
      setResetUser(null);
      setResetPassword('');
      Alert.alert(t('common.success'), 'Password reset successfully');
    } catch (e) {
      Alert.alert(t('common.error'), extractApiError(e));
    } finally {
      setResetLoading(false);
    }
  }, [resetPassword, resetUser, t]);

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
          users.map(user => (
            <FluentCard key={user.id} style={styles.section}>
              <View style={styles.userHeader}>
                <Text style={styles.userName}>{user.username}</Text>
                {user.isAdmin ? (
                  <View style={styles.adminBadge}>
                    <Text style={styles.adminBadgeText}>{t('auth.admin')}</Text>
                  </View>
                ) : null}
              </View>
              {user.createdAt ? (
                <Text style={styles.createdAt}>{user.createdAt}</Text>
              ) : null}
              <View style={styles.toggleRow}>
                <Text style={styles.toggleLabel}>{t('auth.admin')}</Text>
                <Switch
                  value={user.isAdmin}
                  onValueChange={() => handleToggleRole(user)}
                  trackColor={{false: colors.borderStrong, true: colors.primaryMuted}}
                  thumbColor={user.isAdmin ? colors.primary : colors.textMuted}
                />
              </View>
              <View style={styles.userActions}>
                <FluentButton
                  label={t('common.resetPassword')}
                  variant="secondary"
                  onPress={() => handleResetPassword(user)}
                  style={styles.actionButton}
                />
                <FluentButton
                  label={t('common.delete')}
                  variant="danger"
                  onPress={() => handleDelete(user)}
                  style={styles.actionButton}
                />
              </View>
            </FluentCard>
          ))
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
              <Switch
                value={createIsAdmin}
                onValueChange={setCreateIsAdmin}
                trackColor={{false: colors.borderStrong, true: colors.primaryMuted}}
                thumbColor={createIsAdmin ? colors.primary : colors.textMuted}
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
              label={t('common.resetPassword')}
              value={resetPassword}
              onChangeText={setResetPassword}
              placeholder={t('common.resetPassword')}
              secureTextEntry
              editable={!resetLoading}
            />
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
                disabled={resetLoading || !resetPassword.trim()}
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
    createdAt: {
      color: colors.textMuted,
      fontSize: 12,
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
