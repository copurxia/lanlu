import React, {useState} from 'react';
import {
  KeyboardAvoidingView,
  Platform,
  StyleSheet,
  Text,
  TouchableOpacity,
  View,
} from 'react-native';
import {LogIn, RotateCcw, Server} from 'lucide-react-native';
import {useSafeAreaInsets} from 'react-native-safe-area-context';

import {extractApiError} from '../api/client';
import {useAuth} from '../auth/AuthContext';
import {FluentCard, FluentTextField, FluentTitle} from '../components/fluent';
import {useI18n} from '../i18n';
import {colors, spacing} from '../theme/colors';

export function LoginScreen() {
  const {t} = useI18n();
  const {activeServer, signIn, showServerList} = useAuth();
  const insets = useSafeAreaInsets();
  const [username, setUsername] = useState('');
  const [password, setPassword] = useState('');
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState('');

  async function submit() {
    if (!username.trim() || !password) {
      setError(t('auth.credentialsRequired'));
      return;
    }
    setSubmitting(true);
    setError('');
    try {
      await signIn({username, password});
    } catch (err) {
      setError(extractApiError(err, t('auth.loginFailed')));
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <KeyboardAvoidingView
      behavior={Platform.OS === 'ios' ? 'padding' : undefined}
      style={[
        styles.screen,
        {
          paddingTop: Math.max(insets.top, spacing.lg),
          paddingBottom: Math.max(insets.bottom, spacing.lg),
          paddingLeft: Math.max(insets.left, spacing.lg),
          paddingRight: Math.max(insets.right, spacing.lg),
        },
      ]}>
      <FluentCard style={styles.panel}>
        <View style={styles.header}>
          <View style={styles.serverIcon}>
            <Server color={colors.primary} size={20} />
          </View>
          <View style={styles.headerText}>
            <FluentTitle>{t('auth.signIn')}</FluentTitle>
            <Text style={styles.serverName}>{activeServer?.name || t('auth.lanluServer')}</Text>
            <Text numberOfLines={1} style={styles.serverUrl}>
              {activeServer?.baseUrl || ''}
            </Text>
          </View>
        </View>

        <FluentTextField
          autoCapitalize="none"
          autoCorrect={false}
          label={t('auth.username')}
          onChangeText={setUsername}
          placeholder="admin"
          value={username}
        />

        <FluentTextField
          label={t('auth.password')}
          onChangeText={setPassword}
          placeholder="Password"
          secureTextEntry
          value={password}
        />

        {error ? <Text style={styles.error}>{error}</Text> : null}

        <View style={styles.actions}>
          <TouchableOpacity
            activeOpacity={0.78}
            accessibilityLabel={t('auth.switchServer')}
            accessibilityRole="button"
            onPress={() => {
              showServerList().catch(reason =>
                console.warn('Failed to switch server:', reason),
              );
            }}
            style={styles.secondaryButton}>
            <RotateCcw color={colors.textMuted} size={16} />
            <Text style={styles.secondaryButtonText}>{t('auth.switchServer')}</Text>
          </TouchableOpacity>
          <TouchableOpacity
            activeOpacity={0.82}
            accessibilityLabel={submitting ? t('auth.signingIn') : t('auth.signIn')}
            accessibilityRole="button"
            disabled={submitting}
            onPress={submit}
            style={[styles.primaryButton, submitting && styles.buttonDisabled]}>
            <LogIn color={colors.white} size={16} />
            <Text style={styles.primaryButtonText}>
              {submitting ? t('auth.signingIn') : t('auth.signIn')}
            </Text>
          </TouchableOpacity>
        </View>
      </FluentCard>
    </KeyboardAvoidingView>
  );
}

const styles = StyleSheet.create({
  screen: {
    backgroundColor: colors.background,
    flex: 1,
    justifyContent: 'center',
  },
  panel: {
    alignSelf: 'center',
    gap: spacing.md,
    maxWidth: 460,
    width: '100%',
  },
  header: {
    alignItems: 'center',
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: spacing.md,
  },
  headerText: {
    flex: 1,
    gap: 2,
    minWidth: 0,
  },
  serverIcon: {
    alignItems: 'center',
    backgroundColor: colors.primaryMuted,
    borderColor: colors.border,
    borderRadius: 8,
    borderWidth: StyleSheet.hairlineWidth,
    height: 40,
    justifyContent: 'center',
    width: 40,
  },
  serverName: {
    color: colors.text,
    fontSize: 14,
    fontWeight: '800',
  },
  serverUrl: {
    color: colors.primary,
    fontSize: 13,
  },
  error: {
    color: colors.danger,
    fontSize: 13,
    lineHeight: 18,
    marginTop: 14,
  },
  actions: {
    alignItems: 'center',
    flexDirection: 'row',
    gap: spacing.sm,
    justifyContent: 'flex-end',
    marginTop: spacing.sm,
  },
  primaryButton: {
    alignItems: 'center',
    backgroundColor: colors.primary,
    borderRadius: 8,
    flexDirection: 'row',
    gap: spacing.xs,
    height: 40,
    justifyContent: 'center',
    paddingHorizontal: spacing.md,
  },
  primaryButtonText: {
    color: colors.white,
    fontSize: 14,
    fontWeight: '800',
  },
  secondaryButton: {
    alignItems: 'center',
    backgroundColor: colors.surface,
    borderColor: colors.borderStrong,
    borderRadius: 8,
    borderWidth: StyleSheet.hairlineWidth,
    flexDirection: 'row',
    gap: spacing.xs,
    height: 40,
    justifyContent: 'center',
    paddingHorizontal: spacing.md,
  },
  secondaryButtonText: {
    color: colors.text,
    fontSize: 14,
    fontWeight: '800',
  },
  buttonDisabled: {
    opacity: 0.62,
  },
});
